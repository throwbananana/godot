class_name SoundManager
extends RefCounted

## 合成波形缓存 —— 这个项目没有音频文件, 每个音效都是现场逐采样算出来的。
##
## 原来是**每次播放都重算一遍**, 而合成循环是纯 GDScript 的逐采样 for:
## 一声枪响 0.12s x 22050Hz = 2646 次迭代, 一次爆炸 7717 次。实测单次开销
## play_shot 875us / play_hit_steel 635us / play_explosion 2540us —— 60fps 下
## 一帧的预算总共才 16.7ms, 也就是说**一次爆炸吃掉 15% 的帧预算, 一声枪响 5%**。
## 战斗里子弹打墙 (play_hit_steel 有 60 处调用点)、开炮、连环爆炸挤在同一帧,
## 几毫秒几毫秒地叠, 表现出来就是开火和爆炸瞬间的卡顿。
##
## 但这些波形是**参数的纯函数**: 同样的 (时长, 起止频率, 波形, 音量) 永远算出
## 同一段字节。所以按参数指纹缓存 AudioStreamWAV, 同一种音效全局只合成一次。
## AudioStreamWAV 是 Resource, 播放状态在 AudioStreamPlayer 那边, 所以同一个
## 流被多个播放器同时播放是安全的, 不需要复制。
static var _stream_cache: Dictionary = {}

## 噪声波形是唯一带随机性的一档 (爆炸、打砖)。缓存单份的话每次爆炸听起来会
## 一模一样, 所以每套参数预生成 NOISE_VARIANTS 份, 用静态计数器轮着放 ——
## 和 explosion.gd 轮换三套爆炸贴图是同一个做法, 同样**不能用 randf()**:
## 每日挑战在 start_game() 里 seed() 了全局 RNG 流并依赖它保持确定, 而轮换
## 计数器不碰那条流。
const NOISE_VARIANTS := 3
static var _noise_pick: int = 0

## 波形分派预先转成整数, 不在逐采样循环里比字符串。
const WAVE_SQUARE := 0
const WAVE_SINE := 1
const WAVE_TRIANGLE := 2
const WAVE_SAW := 3
const WAVE_NOISE := 4

## prewarm() 期间只合成、不发声。
static var _prewarming: bool = false

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

static func play_button_click(tree: SceneTree = null) -> void:
	# Short UI confirm tick
	_play_synth_sound(0.06, 950.0, 950.0, "sine", 0.3, tree)

static func play_missile(tree: SceneTree = null) -> void:
	# Rocket propulsion whoosh
	_play_synth_sound(0.28, 280.0, 750.0, "triangle", 0.35, tree)

static func play_teleport(tree: SceneTree = null) -> void:
	# Dimensional phase warp: ascending/descending cosmic harmonic arpeggio
	_play_arpeggio([380.0, 580.0, 880.0, 1420.0], 0.045, "sine", 0.40, tree)

## 联机音效回声。
##
## 客户端不跑战斗逻辑, 所以它自己不会发出任何开炮/爆炸/拾取的声音。
## 项目里所有音效最终都收束到 _play_arpeggio / _play_synth_sound 这两个
## 合成器入口, 所以只要在这两处回声, 上面十四个 play_* 一个都不用改。
##
## 回声的是**合成参数**而不是"音效名", 于是以后新加一种声音自动就同步了,
## 不需要再往某张映射表里补一行 —— 那种表是一定会漏的。
static func _net_echo(kind: String, args: Array, tree: SceneTree) -> void:
	if tree == null:
		return
	var net = tree.root.get_node_or_null("Net")
	if net == null:
		return
	net.echo_sound(kind, args)


## 客户端侧: 按主机传来的参数重放。**必须绕开 _net_echo** ——
## 直接调 _play_arpeggio/_play_synth_sound 的话客户端会再回声一次,
## 而客户端不是主机, echo_sound 会自己挡掉, 所以其实是安全的;
## 这里仍然走独立入口, 是为了让"重放"这条路径在调用图上看得见。
static func net_replay(kind: String, args: Array, tree: SceneTree = null) -> void:
	match kind:
		"arp":
			if args.size() >= 4:
				_play_arpeggio(args[0], args[1], args[2], args[3], tree, false)
		"synth":
			if args.size() >= 5:
				_play_synth_sound(args[0], args[1], args[2], args[3], args[4], tree, false)


static func _play_arpeggio(freqs: Array, note_duration: float, wave_type: String, volume: float, tree: SceneTree = null, echo: bool = true) -> void:
	var root = _get_root(tree)
	if not root: return
	if echo:
		_net_echo("arp", [freqs, note_duration, wave_type, volume], tree)

	var key := "arp|%s|%.4f|%s|%.3f" % [str(freqs), note_duration, wave_type, volume]
	var stream := _cached(key, wave_type, func(rng): return _build_arpeggio(freqs, note_duration, wave_type, volume, rng))
	_spawn_player(root, stream)

static func _build_arpeggio(freqs: Array, note_duration: float, wave_type: String, volume: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
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
	var wave := _wave_code(wave_type)

	for note_idx in range(freqs.size()):
		var target_freq: float = freqs[note_idx]
		var start_f = note_idx * frames_per_note
		var end_f = mini((note_idx + 1) * frames_per_note, total_frames)
		var phase_step: float = (target_freq * 2.0 * PI) / float(sample_rate)

		for i in range(start_f, end_f):
			var local_t: float = float(i - start_f) / float(frames_per_note)
			phase += phase_step
			var val: float = _sample_of(phase, wave, rng)
			var env: float = (1.0 - local_t * 0.7) * volume
			data[i] = clampi(int(128 + val * env * 127), 0, 255)

	stream.data = data
	return stream

static func _play_synth_sound(duration: float, start_freq: float, end_freq: float, wave_type: String, volume: float, tree: SceneTree = null, echo: bool = true) -> void:
	var root = _get_root(tree)
	if not root: return
	if echo:
		_net_echo("synth", [duration, start_freq, end_freq, wave_type, volume], tree)

	var key := "synth|%.4f|%.2f|%.2f|%s|%.3f" % [duration, start_freq, end_freq, wave_type, volume]
	var stream := _cached(key, wave_type, func(rng): return _build_synth(duration, start_freq, end_freq, wave_type, volume, rng))
	_spawn_player(root, stream)

static func _build_synth(duration: float, start_freq: float, end_freq: float, wave_type: String, volume: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_frames: int = int(duration * sample_rate)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false

	var data = PackedByteArray()
	data.resize(total_frames)
	var phase: float = 0.0
	var wave := _wave_code(wave_type)
	var inv_total: float = 1.0 / float(maxi(1, total_frames))
	var two_pi_over_rate: float = (2.0 * PI) / float(sample_rate)

	for i in range(total_frames):
		var t: float = float(i) * inv_total
		phase += lerp(start_freq, end_freq, t) * two_pi_over_rate
		var val: float = _sample_of(phase, wave, rng)
		var env: float = (1.0 - t) * volume
		data[i] = clampi(int(128 + val * env * 127), 0, 255)

	stream.data = data
	return stream

## 取缓存, 没有就合成一份。
##
## 噪声档存的是一个数组 (NOISE_VARIANTS 份不同的样本), 其余档存单份。
## 噪声用**自带种子的局部 RandomNumberGenerator**, 不碰全局 RNG ——
## 原来逐采样调 randf_range(), 一次爆炸就从全局流里抽走 7717 个数,
## 而每日挑战靠那条流保持所有人同一局 (见 CLAUDE.md "The balance log" 一节
## 关于 randi() 的同一条理由)。缓存之后连"只在第一次抽"都不存在了。
static func _cached(key: String, wave_type: String, builder: Callable) -> AudioStreamWAV:
	if wave_type != "noise":
		if not _stream_cache.has(key):
			_stream_cache[key] = builder.call(null)
		return _stream_cache[key]

	if not _stream_cache.has(key):
		var variants: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		for _v in range(NOISE_VARIANTS):
			variants.append(builder.call(rng))
		_stream_cache[key] = variants
	var arr: Array = _stream_cache[key]
	_noise_pick += 1
	return arr[_noise_pick % arr.size()]

static func _wave_code(wave_type: String) -> int:
	match wave_type:
		"square": return WAVE_SQUARE
		"sine": return WAVE_SINE
		"triangle": return WAVE_TRIANGLE
		"sawtooth": return WAVE_SAW
		"noise": return WAVE_NOISE
	return WAVE_SINE

## 按整数波形码取一个采样。逐采样比字符串是这个循环里最贵的一项之一,
## 波形码在循环外算一次就够了。
static func _sample_of(phase: float, wave: int, rng: RandomNumberGenerator) -> float:
	match wave:
		WAVE_SQUARE: return 1.0 if sin(phase) >= 0.0 else -1.0
		WAVE_SINE: return sin(phase)
		WAVE_TRIANGLE: return asin(sin(phase)) * (2.0 / PI)
		WAVE_SAW: return (fmod(phase / (2.0 * PI), 1.0) * 2.0) - 1.0
		WAVE_NOISE: return rng.randf_range(-1.0, 1.0) if rng else 0.0
	return 0.0

## 开局把所有音效各合成一遍, 让首次播放的那一下尖峰落在加载阶段而不是战斗里。
##
## 刻意用反射遍历 play_* 而不是手写一张参数表: 这个类里已经有 14 个 play_*,
## 手写表漏掉一个不会报错, 只会让那个音效在战斗中第一次响的时候卡一下 ——
## 正是这种"漏了也没人发现"的表, CLAUDE.md 里反复说会烂掉。
static func prewarm(tree: SceneTree = null) -> void:
	_prewarming = true
	# 经由 Script 对象反射调用静态函数。不能写 SoundManager.call(...) ——
	# 那是在类名上直接调非静态的 Object.call(), 解析期就报
	# "Cannot call non-static function call() on the class directly"。
	var script_obj: Object = load("res://scripts/sound_manager.gd")
	for m in (script_obj as Script).get_script_method_list():
		var n: String = m.get("name", "")
		if n.begins_with("play_") and m.get("args", []).size() <= 1:
			script_obj.call(n, tree)
	_prewarming = false

static func _get_root(tree: SceneTree) -> Node:
	if tree and tree.root:
		return tree.root
	elif Engine.get_main_loop() is SceneTree:
		return (Engine.get_main_loop() as SceneTree).root
	return null

static func _spawn_player(root: Node, stream: AudioStream) -> void:
	if _prewarming:
		return # 预热只要把波形算进缓存, 不发声
	var player = AudioStreamPlayer.new()
	player.stream = stream
	root.add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())
