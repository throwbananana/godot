class_name SoundManager
extends RefCounted

static func play_shot(tree: SceneTree = null) -> void:
	_play_synth_sound(0.12, 600.0, 150.0, "square", 0.3, tree)

static func play_explosion(tree: SceneTree = null) -> void:
	_play_synth_sound(0.35, 180.0, 40.0, "noise", 0.5, tree)

static func play_hit_steel(tree: SceneTree = null) -> void:
	_play_synth_sound(0.08, 900.0, 700.0, "sine", 0.25, tree)

static func play_hit_brick(tree: SceneTree = null) -> void:
	_play_synth_sound(0.1, 250.0, 80.0, "noise", 0.3, tree)

static func play_game_over(tree: SceneTree = null) -> void:
	_play_synth_sound(0.8, 300.0, 80.0, "sawtooth", 0.4, tree)

static func _play_synth_sound(duration: float, start_freq: float, end_freq: float, wave_type: String, volume: float, tree: SceneTree = null) -> void:
	var root: Node = null
	if tree and tree.root:
		root = tree.root
	elif Engine.get_main_loop() is SceneTree:
		root = (Engine.get_main_loop() as SceneTree).root
	if not root:
		return

	var sample_rate: int = 22050
	var total_frames: int = int(duration * sample_rate)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	
	var data = PackedByteArray()
	data.resize(total_frames)
	var phase: float = 0.0
	
	for i in range(total_frames):
		var t: float = float(i) / float(total_frames)
		var freq: float = lerp(start_freq, end_freq, t)
		phase += (freq * 2.0 * PI) / float(sample_rate)
		var val: float = 0.0
		
		if wave_type == "square":
			val = 1.0 if sin(phase) >= 0.0 else -1.0
		elif wave_type == "sine":
			val = sin(phase)
		elif wave_type == "sawtooth":
			val = (fmod(phase / (2.0 * PI), 1.0) * 2.0) - 1.0
		elif wave_type == "noise":
			val = randf_range(-1.0, 1.0)
		
		var env: float = (1.0 - t) * volume
		var sample_byte: int = clampi(int(128 + val * env * 127), 0, 255)
		data[i] = sample_byte
	
	stream.data = data
	
	var player = AudioStreamPlayer.new()
	player.stream = stream
	root.add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())
