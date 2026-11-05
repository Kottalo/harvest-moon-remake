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
		# The source WAV is current in the editor; exported builds use the imported resource.
		cues[cue_name] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else load(path)
	var sample: AudioStreamWAV = cues[cue_name]
	if sample != null and voices != null:
		# The source footstep sample already includes the low 20/127 voice volume.
		var gain_db := 4.0 if cue_name=="step" else -8.0
		voices.play_stream(sample,0.0,gain_db)


func _exit_tree() -> void:
	stop()
	voices = null
