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
var last_destination := ""
var last_problem := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func ask(messages: Array) -> void:
	last_destination = ""
	var key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if key.is_empty() and FileAccess.file_exists(KEY_FILE):
		key = FileAccess.get_file_as_string(KEY_FILE).strip_edges()
	if key.is_empty():
		_answer("","本机还没配置 DeepSeek 密钥。")
		return
	if not process.is_empty() and not OS.is_process_running(process.pid):
		_stop_worker()
	if process.is_empty():
		var worker := _worker_path()
		if not FileAccess.file_exists(worker) or not FileAccess.file_exists(
				worker.get_base_dir().path_join("node_modules/@earendil-works/pi-agent-core/package.json")):
			_answer("","Pi Agent 依赖尚未安装。")
			return
		var configured := FileAccess.get_file_as_string(NODE_FILE).strip_edges() if FileAccess.file_exists(NODE_FILE) else ""
		for node in _node_candidates(worker,configured):
			process = OS.execute_with_pipe(node,[worker],false)
			if not process.is_empty():
				break
		if process.is_empty():
			_answer("","找不到可启动的 Node.js。请安装 Node.js，或使用包含便携运行时的游戏版本。")
			return
		pipe = process.stdio
	outbound = Marshalls.utf8_to_base64(JSON.stringify({"key":key,"messages":messages}))
	if not _write_chunk():
		return
	requests += 1
	last_problem = ""
	deadline = Time.get_ticks_msec()+30_000
	set_process(true)
	usage_changed.emit()

func _worker_path() -> String:
	var source := ProjectSettings.globalize_path(WORKER)
	if FileAccess.file_exists(source):
		return source
	return OS.get_executable_path().get_base_dir().path_join("pi/worker.mjs")

func _node_candidates(worker: String, configured: String) -> PackedStringArray:
	var windows := OS.get_name()=="Windows"
	var executable := "node.exe" if windows else "node"
	var paths := PackedStringArray()
	if configured.is_absolute_path():
		paths.append(configured)
	paths.append(worker.get_base_dir().path_join("runtime").path_join(executable))
	if windows:
		for entry in [["LOCALAPPDATA","Programs/nodejs"],["ProgramFiles","nodejs"]]:
			var base := OS.get_environment(entry[0])
			if not base.is_empty():
				paths.append(base.path_join(entry[1]).path_join(executable))
	var candidates := PackedStringArray()
	for path in paths:
		if FileAccess.file_exists(path) and not candidates.has(path):
			candidates.append(path)
	candidates.append(executable)
	return candidates

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
	_answer("",problem)

func _answer(text: String, problem: String) -> void:
	last_problem = problem
	usage_changed.emit()
	answered.emit(text,problem)

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
			last_destination = event.get("destination","")
			if event.has("usage") and event.usage.values().any(func(count): return count>0):
				last_usage = event.usage
				reported += 1
				for category in totals:
					totals[category] += int(last_usage.get(category,0))
			var problem: String = event.get("problem","")
			if reply.is_empty() and problem.is_empty():
				problem = "DeepSeek 返回了空白。"
			_answer(reply,problem)
			return
		end = buffer.find(10)
	if not OS.is_process_running(process.pid):
		_fail("Pi Agent 意外退出，请重试。")

func usage_summary() -> String:
	var total_input: int = totals.input+totals.cacheRead+totals.cacheWrite
	var last := "—" if last_usage.is_empty() else "%d 输入 / %d 输出" % [
		last_usage.input+last_usage.cacheRead+last_usage.cacheWrite,last_usage.output]
	var summary := "Pi Agent · DeepSeek Flash\n请求 %d · 已回报用量 %d\n本次游戏  输入 %d（缓存命中 %d） / 输出 %d\n最近一次  %s" % [
		requests,reported,total_input,totals.cacheRead,totals.output,last]
	return summary if last_problem.is_empty() else summary+"\n"+last_problem
