extends SceneTree

## 性能缓存回归测试 —— 守住两处"卡顿"修复。
##
## 两处都是"不修也能跑, 只是卡"的那类缺陷: 没有报错, 没有功能差异, 只有帧时间。
## 所以必须有测试盯着, 否则哪天有人把缓存删了 (看上去只是"简化了一下"),
## 没有任何东西会红。
##
## 按 CLAUDE.md "Commands" 一节: _failed 标志 + 末尾唯一一次 quit(), 不用 assert。
var _failed := false

func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING PERF CACHE TESTS <<<")
	print("==================================================")

	_test_sound_stream_is_cached()
	_test_sound_repeat_call_is_cheap()
	_test_noise_has_variants_but_is_deterministic()
	_test_prewarm_covers_every_play_function()
	_test_prewarm_is_silent()
	_test_waveform_is_byte_identical_to_original()
	await _test_texture_warm_queue()
	_test_warm_store_roundtrip()

	if _failed:
		print("\n>>> PERF CACHE CHECKS FAILED <<<")
		quit(1)
	else:
		print("\n>>> ALL PERF CACHE CHECKS PASSED! <<<")
		quit(0)

## 同样参数的音效必须复用同一个 AudioStreamWAV, 而不是每次重新合成。
func _test_sound_stream_is_cached() -> void:
	print("\n[STEP 1] 同参数音效复用同一段波形...")
	SoundManager._stream_cache.clear()
	SoundManager.prewarm(self)
	var n_after_prewarm: int = SoundManager._stream_cache.size()
	if n_after_prewarm < 10:
		_fail("预热后缓存里只有 %d 条波形, 14 个 play_* 至少该有 10 条以上" % n_after_prewarm)
	SoundManager.play_shot(self)
	SoundManager.play_shot(self)
	if n_after_prewarm == 0:
		# 缓存是空的时候 "条数没变" 恒成立 —— 0 == 0 会印出一条空转的绿。
		# 拿掉缓存跑这个文件时就出现过: 上一条 FAIL 紧跟着一条 PASS。
		_fail("缓存为空, 无法判断重复播放是否复用")
	elif SoundManager._stream_cache.size() != n_after_prewarm:
		_fail("重复播放不该再往缓存里加东西 (%d -> %d)" % [n_after_prewarm, SoundManager._stream_cache.size()])
	else:
		print("  [PASS] 缓存 %d 条, 重复播放不再合成。" % n_after_prewarm)

## 行为层面的守门: 第二次调用必须显著比第一次便宜。
##
## 只检查"缓存字典非空"是不够的 —— 有人完全可以一边填缓存一边照样重算,
## 那样字典是对的而卡顿原样还在。这里直接量时间。
func _test_sound_repeat_call_is_cheap() -> void:
	print("\n[STEP 2] 冷/热调用的耗时差...")
	SoundManager._stream_cache.clear()
	var t0 := Time.get_ticks_usec()
	SoundManager.play_explosion(self)
	var cold := Time.get_ticks_usec() - t0

	var t1 := Time.get_ticks_usec()
	for _i in range(20):
		SoundManager.play_explosion(self)
	var hot := float(Time.get_ticks_usec() - t1) / 20.0

	# 实测: 修复前每次都是 2540us; 修复后冷 ~7600us (噪声档要生成 3 份变体),
	# 热 ~13us。这里卡 20 倍, 离两边都很远, 不会因为机器快慢而误判。
	if hot <= 0.0 or cold / hot < 20.0:
		_fail("热调用没有明显变便宜: 冷 %dus, 热 %.1fus (倍数 %.1f, 要求 >= 20)" % [cold, hot, cold / maxf(hot, 0.001)])
	else:
		print("  [PASS] 冷 %dus -> 热 %.1fus (快 %.0f 倍)。" % [cold, hot, cold / hot])

## 噪声档要有多份变体 (否则每次爆炸听起来一模一样), 但不能去摇全局 RNG ——
## 每日挑战靠那条流保证所有人同一局。
func _test_noise_has_variants_but_is_deterministic() -> void:
	print("\n[STEP 3] 噪声波形: 有变体, 但不碰全局 RNG...")
	SoundManager._stream_cache.clear()

	seed(12345)
	SoundManager.play_explosion(self)
	var after_first := randi()

	seed(12345)
	for _i in range(5):
		SoundManager.play_explosion(self)
	var after_many := randi()

	if after_first != after_many:
		_fail("合成噪声动了全局 RNG 流: 播 1 次和播 5 次之后的 randi() 不同 (%d vs %d)" % [after_first, after_many])
	else:
		print("  [PASS] 播放次数不影响全局 RNG 序列。")

	var key_count := 0
	var variant_count := 0
	for k in SoundManager._stream_cache:
		var v = SoundManager._stream_cache[k]
		if typeof(v) == TYPE_ARRAY:
			key_count += 1
			variant_count = v.size()
	if key_count == 0:
		_fail("没有任何噪声档走数组变体路径")
	elif variant_count < 2:
		_fail("噪声只缓存了 %d 份变体, 每次爆炸会完全一样" % variant_count)
	else:
		print("  [PASS] 噪声档 %d 组, 每组 %d 份变体。" % [key_count, variant_count])

## 预热走反射遍历 play_*, 不是手写表 —— 新加一个音效必须自动被覆盖。
func _test_prewarm_covers_every_play_function() -> void:
	print("\n[STEP 4] 预热覆盖全部 play_* ...")
	var script_obj: Object = load("res://scripts/sound_manager.gd")
	var expected := 0
	for m in (script_obj as Script).get_script_method_list():
		var n: String = m.get("name", "")
		if n.begins_with("play_") and m.get("args", []).size() <= 1:
			expected += 1

	SoundManager._stream_cache.clear()
	SoundManager.prewarm(self)
	var cached: int = SoundManager._stream_cache.size()
	if expected < 10:
		_fail("只反射到 %d 个 play_* 函数, 反射没生效" % expected)
	elif cached < expected - 1:
		# -1 的余量: 个别 play_* 可能参数完全相同因而共用一条缓存键。
		_fail("预热后缓存 %d 条, 少于 play_* 函数数 %d —— 有音效没被预热到" % [cached, expected])
	else:
		print("  [PASS] %d 个 play_* 全部预热 (缓存 %d 条)。" % [expected, cached])

## 预热只合成、不发声。否则一进标题界面就会同时炸响十四种音效。
func _test_prewarm_is_silent() -> void:
	print("\n[STEP 5] 预热期间不发声...")
	var before := _count_audio_players()
	SoundManager._stream_cache.clear()
	SoundManager.prewarm(self)
	var after := _count_audio_players()
	if after > before:
		_fail("预热期间新建了 %d 个 AudioStreamPlayer —— 应该只合成不播放" % [after - before])
	else:
		print("  [PASS] 没有产生任何播放器节点。")

func _count_audio_players() -> int:
	var n := 0
	for c in root.get_children():
		if c is AudioStreamPlayer:
			n += 1
	return n

## 加缓存的同时还把逐采样循环里的常量提了出去 (波形分派从比字符串改成比整数,
## 相位步进和 1/total 提到循环外)。这些都应该是恒等变换, 但"应该"不算数 ——
## 音色被悄悄改掉是不会报错的, 只会听起来不对。这里按**原始公式**在测试里重新
## 算一遍, 逐字节比对。
func _test_waveform_is_byte_identical_to_original() -> void:
	print("\n[STEP 6] 重构后的波形与原公式逐字节一致...")

	# play_shot 的参数。方波档没有随机性, 可以精确比对。
	var duration := 0.12
	var start_freq := 600.0
	var end_freq := 150.0
	var volume := 0.3
	var sample_rate := 22050
	var total_frames := int(duration * sample_rate)

	# 原始实现 (重构前逐字抄回来的写法)
	var expected := PackedByteArray()
	expected.resize(total_frames)
	var phase := 0.0
	for i in range(total_frames):
		var t: float = float(i) / float(total_frames)
		var freq: float = lerp(start_freq, end_freq, t)
		phase += (freq * 2.0 * PI) / float(sample_rate)
		var val: float = 1.0 if sin(phase) >= 0.0 else -1.0
		var env: float = (1.0 - t) * volume
		expected[i] = clampi(int(128 + val * env * 127), 0, 255)

	var stream: AudioStreamWAV = SoundManager._build_synth(duration, start_freq, end_freq, "square", volume, null)
	var actual: PackedByteArray = stream.data

	if actual.size() != expected.size():
		_fail("采样数变了: 原 %d, 现 %d" % [expected.size(), actual.size()])
		return
	var diffs := 0
	for i in range(expected.size()):
		if actual[i] != expected[i]:
			diffs += 1
	if diffs > 0:
		_fail("波形被改变了: %d/%d 个采样与原公式不符" % [diffs, expected.size()])
	else:
		print("  [PASS] %d 个采样逐字节一致, 音色未变。" % expected.size())

## 后台预热队列: 排进去的路径最终要真的进 TextureHelper 的缓存。
func _test_texture_warm_queue() -> void:
	print("\n[STEP 7] 贴图后台预热队列...")
	var probe := "res://assets/sprites/tiles/tile_brick.png"
	if not ResourceLoader.exists(probe):
		print("  [SKIP] 找不到探针贴图 %s" % probe)
		return

	TextureHelper._cache.erase(probe)
	TextureHelper.warm_async([probe])
	if TextureHelper._warm_queue.is_empty() and TextureHelper._warm_active == "":
		_fail("warm_async() 之后队列是空的")
		return

	var spins := 0
	while spins < 600 and not TextureHelper._cache.has(probe):
		TextureHelper.warm_pump()
		await process_frame
		spins += 1

	if not TextureHelper._cache.has(probe):
		_fail("600 帧内后台预热没有把 %s 放进缓存" % probe)
	else:
		print("  [PASS] %d 帧内完成预热。" % spins)

	# 已经在缓存里的不该再排队 —— 否则每次进房间都会把整张清单重排一遍。
	var before: int = TextureHelper._warm_queue.size()
	TextureHelper.warm_async([probe])
	if TextureHelper._warm_queue.size() != before:
		_fail("已缓存的路径不该再次入队")

## 清单存档必须能往返, 而且测试绝不能碰玩家真正的文件。
func _test_warm_store_roundtrip() -> void:
	print("\n[STEP 8] 预热清单存档往返...")
	var real_path := TextureWarmStore.save_path
	TextureWarmStore.save_path = "user://_test_texture_warm_list.json"

	var sample := ["res://a.png", "res://b.png", "res://c.png"]
	TextureWarmStore.save_list(sample)
	var back := TextureWarmStore.load_list()
	if back.size() != sample.size():
		_fail("往返后条数不对: 存 %d 条, 读回 %d 条" % [sample.size(), back.size()])
	elif back[0] != sample[0] or back[2] != sample[2]:
		_fail("往返后内容不对: %s" % str(back))
	else:
		print("  [PASS] %d 条往返一致。" % back.size())

	# 缺文件时必须安静地返回空表, 而不是报错 —— 首次运行就是这个情况。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TextureWarmStore.save_path))
	if TextureWarmStore.load_list().size() != 0:
		_fail("清单文件不存在时应该返回空表")

	TextureWarmStore.save_path = real_path
