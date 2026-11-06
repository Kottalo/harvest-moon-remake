extends Node
## Pi's Node worker is started on the first utterance and talks over private stdio.
signal partial(text: String)
signal answered(text: String, problem: String)
signal usage_changed

const WORKER := "res://game/npc/dialogue/pi/worker.mjs"
const KEY_FILE := "user://deepseek.key"
const NODE_FILE := "user://pi-node.path"

var process := {}
var pipe: FileAccess
var buffer := PackedByteArray()
var outbound := ""
var deadline := 0
var requests := 0
var reported := 0
var totals := {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}
var last_usage := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func ask(messages: Array) -> void:
	var key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if key.is_empty() and FileAccess.file_exists(KEY_FILE):
		key = FileAccess.get_file_as_string(KEY_FILE).strip_edges()
	if key.is_empty():
		answered.emit("","本机还没配置 DeepSeek 密钥。")
		return
	if not process.is_empty() and not OS.is_process_running(process.pid):
		_stop_worker()
	if process.is_empty():
		var node := "node"
		if FileAccess.file_exists(NODE_FILE):
			node = FileAccess.get_file_as_string(NODE_FILE).strip_edges()
		var worker := ProjectSettings.globalize_path(WORKER)
		if not FileAccess.file_exists(worker.get_base_dir()+"/node_modules/@earendil-works/pi-agent-core/package.json"):
			answered.emit("","Pi Agent 依赖尚未安装。")
			return
		process = OS.execute_with_pipe(node,[worker],false)
		if process.is_empty():
			answered.emit("","无法启动 Pi Agent 的 Node.js。")
			return
		pipe = process.stdio
	outbound = Marshalls.utf8_to_base64(JSON.stringify({"key":key,"messages":messages}))
	if not _write_chunk():
		return
	requests += 1
	deadline = Time.get_ticks_msec()+30_000
	set_process(true)
	usage_changed.emit()

func _write_chunk() -> bool:
	# Windows' nonblocking byte pipe can partially write large prompts. Wait
	# for an acknowledgement before each small, complete frame.
	var chunk := outbound.left(2048)
	outbound = outbound.substr(chunk.length())
	if pipe.store_line(("=" if outbound.is_empty() else "+")+chunk):
		return true
	_fail("无法把对话发送给 Pi Agent。")
	return false

func cancel_request() -> void:
	if is_processing():
		_stop_worker()

func _exit_tree() -> void:
	_stop_worker()

func _stop_worker() -> void:
	set_process(false)
	if not process.is_empty() and OS.is_process_running(process.pid):
		OS.kill(process.pid)
	pipe = null
	process.clear()
	buffer.clear()
	outbound = ""

func _fail(problem: String) -> void:
	_stop_worker()
	answered.emit("",problem)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec()>=deadline:
		_fail("Pi Agent 等待超时，请重试。")
		return
	buffer.append_array(pipe.get_buffer(8192))
	if buffer.size()>64_000:
		_fail("Pi Agent 返回的数据过长。")
		return
	var end := buffer.find(10)
	while end>=0:
		var line := buffer.slice(0,end).get_string_from_utf8()
		buffer = buffer.slice(end+1)
		var event = JSON.parse_string(line)
		if not event is Dictionary:
			_fail("Pi Agent 返回的数据无效。")
			return
		if event.has("ack"):
			if not _write_chunk():
				return
		elif event.has("partial"):
			partial.emit(event.partial)
		else:
			set_process(false)
			var reply: String = event.get("answer","")
			if event.has("usage") and event.usage.values().any(func(count): return count>0):
				last_usage = event.usage
				reported += 1
				for category in totals:
					totals[category] += int(last_usage.get(category,0))
				usage_changed.emit()
			var problem: String = event.get("problem","")
			if reply.is_empty() and problem.is_empty():
				problem = "DeepSeek 返回了空白。"
			answered.emit(reply,problem)
			return
		end = buffer.find(10)
	if not OS.is_process_running(process.pid):
		_fail("Pi Agent 意外退出，请重试。")

func usage_summary() -> String:
	var total_input: int = totals.input+totals.cacheRead+totals.cacheWrite
	var last := "—" if last_usage.is_empty() else "%d 输入 / %d 输出" % [
		last_usage.input+last_usage.cacheRead+last_usage.cacheWrite,last_usage.output]
	return "Pi Agent · DeepSeek Flash\n请求 %d · 已回报用量 %d\n本次游戏  输入 %d（缓存命中 %d） / 输出 %d\n最近一次  %s" % [
		requests,reported,total_input,totals.cacheRead,totals.output,last]
