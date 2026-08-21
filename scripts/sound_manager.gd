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

static func play_pickup(tree: SceneTree = null) -> void:
	# Bright 2-tone chime (G5 -> C6)
	_play_arpeggio([784.0, 1046.5], 0.08, "sine", 0.35, tree)

static func play_level_up(tree: SceneTree = null) -> void:
	# 4-tone triumphant RPG fanfare (C5 -> E5 -> G5 -> C6)
	_play_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.10, "triangle", 0.45, tree)

static func play_build(tree: SceneTree = null) -> void:
	# Solid clay installation pop
	_play_synth_sound(0.14, 180.0, 420.0, "sine", 0.40, tree)

static func play_victory(tree: SceneTree = null) -> void:
	# Major chord fanfare (C5 -> G5 -> C6 -> E6)
	_play_arpeggio([523.25, 783.99, 1046.5, 1318.5], 0.16, "square", 0.40, tree)

static func play_shield_hit(tree: SceneTree = null) -> void:
	# Resonant energy deflection hum
	_play_synth_sound(0.15, 1200.0, 300.0, "sine", 0.35, tree)

static func play_laser(tree: SceneTree = null) -> void:
	# High-tech piercing laser sweep
	_play_synth_sound(0.22, 1800.0, 320.0, "sawtooth", 0.45, tree)

static func play_missile(tree: SceneTree = null) -> void:
	# Rocket propulsion whoosh
	_play_synth_sound(0.28, 280.0, 750.0, "triangle", 0.35, tree)

static func _play_arpeggio(freqs: Array, note_duration: float, wave_type: String, volume: float, tree: SceneTree = null) -> void:
	var root = _get_root(tree)
	if not root: return

	var sample_rate: int = 22050
	var total_frames: int = int(note_duration * freqs.size() * sample_rate)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var data = PackedByteArray()
	data.resize(total_frames)

	var frames_per_note: int = int(note_duration * sample_rate)
	var phase: float = 0.0

	for note_idx in range(freqs.size()):
		var target_freq: float = freqs[note_idx]
		var start_f = note_idx * frames_per_note
		var end_f = mini((note_idx + 1) * frames_per_note, total_frames)

		for i in range(start_f, end_f):
			var local_t: float = float(i - start_f) / float(frames_per_note)
			phase += (target_freq * 2.0 * PI) / float(sample_rate)
			var val: float = _get_sample_val(phase, wave_type)
			var env: float = (1.0 - local_t * 0.7) * volume
			data[i] = clampi(int(128 + val * env * 127), 0, 255)

	stream.data = data
	_spawn_player(root, stream)

static func _play_synth_sound(duration: float, start_freq: float, end_freq: float, wave_type: String, volume: float, tree: SceneTree = null) -> void:
	var root = _get_root(tree)
	if not root: return

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
		var val: float = _get_sample_val(phase, wave_type)
		var env: float = (1.0 - t) * volume
		data[i] = clampi(int(128 + val * env * 127), 0, 255)
	
	stream.data = data
	_spawn_player(root, stream)

static func _get_sample_val(phase: float, wave_type: String) -> float:
	if wave_type == "square":
		return 1.0 if sin(phase) >= 0.0 else -1.0
	elif wave_type == "sine":
		return sin(phase)
	elif wave_type == "triangle":
		return asin(sin(phase)) * (2.0 / PI)
	elif wave_type == "sawtooth":
		return (fmod(phase / (2.0 * PI), 1.0) * 2.0) - 1.0
	elif wave_type == "noise":
		return randf_range(-1.0, 1.0)
	return 0.0

static func _get_root(tree: SceneTree) -> Node:
	if tree and tree.root:
		return tree.root
	elif Engine.get_main_loop() is SceneTree:
		return (Engine.get_main_loop() as SceneTree).root
	return null

static func _spawn_player(root: Node, stream: AudioStream) -> void:
	var player = AudioStreamPlayer.new()
	player.stream = stream
	root.add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())
