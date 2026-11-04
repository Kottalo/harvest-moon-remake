extends HTTPRequest
## Direct DeepSeek client for a locally configured game.
signal answered(text: String, problem: String)

const ENDPOINT := "https://api.deepseek.com/chat/completions"
const MODEL := "deepseek-flash"
const KEY_FILE := "user://deepseek.key"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	use_threads = true
	timeout = 18.0
	body_size_limit = 65536
	max_redirects = 0
	request_completed.connect(_finished)

func ask(messages: Array) -> void:
	var key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if key.is_empty() and FileAccess.file_exists(KEY_FILE):
		key = FileAccess.get_file_as_string(KEY_FILE).strip_edges()
	if key.is_empty():
		answered.emit("","本机还没配置 DeepSeek 密钥。")
		return
	var payload := JSON.stringify({
		"model":MODEL,"messages":messages,"thinking":{"type":"disabled"},
		"max_tokens":160,"stream":false,
	})
	var error := request(ENDPOINT,["Content-Type: application/json","Authorization: Bearer "+key],
		HTTPClient.METHOD_POST,payload)
	if error != OK:
		answered.emit("","没能发出请求，请重试。")

func _finished(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != RESULT_SUCCESS:
		answered.emit("","连接 DeepSeek 失败或超时，请重试。")
		return
	if status!=200:
		var problem := "DeepSeek 暂时无法回答（HTTP %d）。" % status
		match status:
			401: problem = "DeepSeek 密钥无效或已撤销。"
			402: problem = "DeepSeek 账户余额不足。"
			429: problem = "请求太频繁，请稍后重试。"
		answered.emit("",problem)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var choices = data.get("choices") if data is Dictionary else null
	var message = choices[0].get("message") if choices is Array and not choices.is_empty() and choices[0] is Dictionary else null
	var content = message.get("content") if message is Dictionary else null
	if not content is String or content.strip_edges().is_empty():
		answered.emit("","DeepSeek 返回了空白，请重试。")
		return
	answered.emit(content.strip_edges().left(180),"")
