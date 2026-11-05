extends AudioStreamPlayer
## Decoded USA VAB samples. Play independently so a new cue cannot cut off a swing.

var cues: Dictionary = {}
var voices: AudioStreamPlaybackPolyphonic

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mixer := AudioStreamPolyphonic.new()
	mixer.polyphony = 12
	stream = mixer
	play()
	voices = get_stream_playback() as AudioStreamPlaybackPolyphonic

func cue(cue_name: String) -> void:
	if not cues.has(cue_name):
		var path: String = get_script().resource_path.get_base_dir().path_join(cue_name+".wav")
		cues[cue_name] = load(path) if ResourceLoader.exists(path) else AudioStreamWAV.load_from_file(path)
	var sample: AudioStreamWAV = cues[cue_name]
	if sample != null and voices != null:
		voices.play_stream(sample,0.0,-8.0)


func _exit_tree() -> void:
	stop()
	voices = null
