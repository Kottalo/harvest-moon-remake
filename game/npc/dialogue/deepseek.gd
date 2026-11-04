extends Node
## Polls the provider's SSE response while the dialogue has paused the world.
signal partial(text: String)
signal answered(text: String, problem: String)

const HOST := "api.deepseek.com"
const PATH := "/chat/completions"
const MODEL := "deepseek-flash"
const KEY_FILE := "user://deepseek.key"
const TIMEOUT_MS := 30000
const BODY_LIMIT := 128 * 1024
const REPLY_LIMIT := 180

var http := HTTPClient.new()
var headers := PackedStringArray()
var payload := ""
var deadline := 0
var buffer := PackedByteArray()
var received_bytes := 0
var reply := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func ask(messages: Array) -> void:
	cancel_request()
	var key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if key.is_empty() and FileAccess.file_exists(KEY_FILE):
		key = FileAccess.get_file_as_string(KEY_FILE).strip_edges()
	if key.is_empty():
		answered.emit("","本机还没配置 DeepSeek 密钥。")
		return
	headers = ["Content-Type: application/json","Accept: text/event-stream","Authorization: Bearer "+key]
	payload = JSON.stringify({
		"model":MODEL,"messages":messages,"thinking":{"type":"disabled"},
		"max_tokens":160,"stream":true,
	})
	deadline = Time.get_ticks_msec()+TIMEOUT_MS
	if http.connect_to_host(HOST,443,TLSOptions.client()) != OK:
		_finish("没能发出请求，请重试。")
		return
	set_process(true)

func cancel_request() -> void:
	set_process(false)
	http.close()
	headers.clear()
	payload = ""
	buffer.clear()
	received_bytes = 0
	reply = ""

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= deadline or http.poll() != OK:
		_finish("连接 DeepSeek 失败或超时，请重试。")
		return
	match http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if payload.is_empty():
				var status := http.get_response_code() if http.has_response() else 200
				_finish(_http_problem(status) if status!=200 else "DeepSeek 回复中断，请重试。")
			else:
				var error := http.request(HTTPClient.METHOD_POST,PATH,headers,payload)
				payload = ""
				headers.clear()
				if error != OK:
					_finish("没能发出请求，请重试。")
		HTTPClient.STATUS_BODY:
			var status := http.get_response_code()
			if status != 200:
				_finish(_http_problem(status))
			else:
				_receive(http.read_response_body_chunk())
		_:
			_finish("连接 DeepSeek 失败或回复中断，请重试。")

func _receive(bytes: PackedByteArray) -> void:
	received_bytes += bytes.size()
	if received_bytes > BODY_LIMIT:
		_finish("DeepSeek 回复过长，请重试。")
		return
	buffer.append_array(bytes)
	# Decode complete lines so a Chinese character split across packets stays intact.
	var end := buffer.find(10)
	while end >= 0:
		var line := buffer.slice(0,end).get_string_from_utf8()
		buffer = buffer.slice(end+1)
		if line.begins_with("data:"):
			var data := line.substr(5).strip_edges()
			if data == "[DONE]":
				_finish("DeepSeek 返回了空白，请重试。" if reply.strip_edges().is_empty() else "")
				return
			var event = JSON.parse_string(data)
			if not event is Dictionary or event.has("error"):
				_finish("DeepSeek 回复格式有误，请重试。")
				return
			var choices = event.get("choices")
			if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
				var delta = choices[0].get("delta")
				var content = delta.get("content") if delta is Dictionary else null
				if content is String and not content.is_empty() and reply.length()<REPLY_LIMIT:
					reply = (reply+content).left(REPLY_LIMIT)
					partial.emit(reply.strip_edges())
		end = buffer.find(10)

func _finish(problem: String) -> void:
	var text := reply.strip_edges() if problem.is_empty() else ""
	cancel_request()
	answered.emit(text,problem)

func _http_problem(status: int) -> String:
	match status:
		401: return "DeepSeek 密钥无效或已撤销。"
		402: return "DeepSeek 账户余额不足。"
		429: return "请求太频繁，请稍后重试。"
	return "DeepSeek 暂时无法回答（HTTP %d）。" % status
