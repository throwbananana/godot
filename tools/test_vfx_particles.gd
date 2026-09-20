extends SceneTree

## 运行时粒子层 (scripts/vfx_particles.gd) 的回归测试。
##
## 这一层是新加的: 在它之前"粒子效果"全是 VFXAnimator 的六帧翻书图章, 每颗碎片
## 的轨迹在 Blender 里就烤死了。下面盯的几条性质, 每一条都是这层存在的理由,
## 而且每一条坏掉都**不会报错** —— 只会看起来不对。
##
## 按 CLAUDE.md "Commands" 一节: _failed 标志 + 末尾唯一一次 quit(), 不用 assert。
var _failed := false

const VFXParticles = preload("res://scripts/vfx_particles.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING VFX PARTICLE SYSTEM TESTS <<<")
	print("==================================================")

	_test_atoms_exist()
	await _test_emits_and_moves()
	await _test_direction_is_respected()
	await _test_same_seed_same_burst()
	_test_never_touches_global_rng()
	await _test_particles_expire_and_free()
	await _test_global_budget_caps()
	_test_single_canvas_item()
	_test_flipbook_jitter_varies_but_is_deterministic()
	_test_call_sites_are_wired()

	if _failed:
		print("\n>>> VFX PARTICLE CHECKS FAILED <<<")
		quit(1)
	else:
		print("\n>>> ALL VFX PARTICLE CHECKS PASSED! <<<")
		quit(0)

func _host() -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	return n

## 六张原子贴图必须都能取到。**不检查 ResourceLoader.exists()** ——
## TextureHelper 在没有 .import 时会走 Image.load_from_file 兜底, 那条路在
## 编辑器/源码运行下是通的; 这里要守的是"贴图取得到", 导入状态由
## test_texture_mipmaps.gd 那条线管。
func _test_atoms_exist() -> void:
	print("\n[STEP 1] 粒子原子贴图...")
	var atoms := [
		VFXParticles.ATOM_CHUNK_A, VFXParticles.ATOM_CHUNK_B, VFXParticles.ATOM_CHUNK_C,
		VFXParticles.ATOM_SPARK, VFXParticles.ATOM_EMBER, VFXParticles.ATOM_SMOKE,
	]
	var missing := 0
	for a in atoms:
		var tex = TextureHelper.get_tex(String(a))
		if tex == null:
			_fail("取不到粒子原子贴图: %s" % a)
			missing += 1
	if missing == 0:
		print("  [PASS] %d 张原子贴图全部可加载。" % atoms.size())

## 发射之后粒子要真的在动 —— 这是它和"翻书图章"的根本区别。
func _test_emits_and_moves() -> void:
	print("\n[STEP 2] 粒子发射并按速度移动...")
	var host := _host()
	var node = VFXParticles.emit("debris", host, Vector2(100, 100), Vector2.RIGHT)
	if node == null:
		_fail("emit() 没有返回节点")
		host.queue_free()
		return
	if node._pos.size() == 0:
		_fail("发射了 0 颗粒子")
		host.queue_free()
		return

	var n0: int = node._pos.size()
	var first_before: Vector2 = node._pos[0]
	for _i in range(6):
		await process_frame
	if not is_instance_valid(node):
		_fail("粒子节点在 6 帧内就没了, 寿命不对")
		host.queue_free()
		return
	var moved: float = node._pos[0].distance_to(first_before)
	if moved < 1.0:
		_fail("粒子没有移动 (位移 %.2f px) —— 积分没跑" % moved)
	else:
		print("  [PASS] %d 颗粒子, 6 帧内首颗移动 %.1f px。" % [n0, moved])
	host.queue_free()
	await process_frame

## 给了方向就要朝那个方向飞。这是整层最主要的卖点:
## 翻书那层做不到"朝子弹打来的反方向崩"。
func _test_direction_is_respected() -> void:
	print("\n[STEP 3] 发射方向...")
	var host := _host()
	var node = VFXParticles.emit("impact_spark", host, Vector2.ZERO, Vector2.RIGHT)
	if node == null or node._pos.size() == 0:
		_fail("方向测试: 没有发射出粒子")
		host.queue_free()
		return

	var n: int = node._vel.size()
	var right := 0
	for i in range(n):
		if node._vel[i].x > 0.0:
			right += 1
	if right < n:
		_fail("朝 RIGHT 发射, 却有 %d/%d 颗速度的 x 分量不为正" % [n - right, n])
	else:
		print("  [PASS] %d 颗全部朝 +x 飞。" % n)

	# 反向对照: 不给方向时必须是各向同性, 否则"方向生效"可能只是碰巧。
	var iso = VFXParticles.emit("impact_spark", host, Vector2.ZERO, Vector2.ZERO)
	if iso != null and iso._vel.size() >= 4:
		var pos_x := 0
		var neg_x := 0
		for i in range(iso._vel.size()):
			if iso._vel[i].x > 0.0: pos_x += 1
			else: neg_x += 1
		if pos_x == 0 or neg_x == 0:
			_fail("不给方向时应当各向同性, 实际 +x %d / -x %d" % [pos_x, neg_x])
		else:
			print("  [PASS] 不给方向时各向同性 (+x %d / -x %d)。" % [pos_x, neg_x])
	host.queue_free()
	await process_frame

## 同一个种子必须产生逐颗一致的一发 —— 联机回声只发种子, 靠的就是这条。
func _test_same_seed_same_burst() -> void:
	print("\n[STEP 4] 同种子 = 同一发 (联机回声的前提)...")
	var host := _host()
	var a = VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.UP, 1.0, 12345)
	var b = VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.UP, 1.0, 12345)
	if a == null or b == null:
		_fail("种子测试: 发射失败")
		host.queue_free()
		return
	if a._vel.size() != b._vel.size():
		_fail("同种子两发的粒子数不同: %d vs %d" % [a._vel.size(), b._vel.size()])
	else:
		var diff := 0
		for i in range(a._vel.size()):
			if a._vel[i].distance_to(b._vel[i]) > 0.001:
				diff += 1
		if diff > 0:
			_fail("同种子两发有 %d 颗速度不同 —— 客户端会看到和主机不一样的碎片" % diff)
		else:
			print("  [PASS] 同种子 %d 颗逐颗一致。" % a._vel.size())

	# 反向对照: 不同种子必须真的不同, 否则上面那条是空转的绿。
	var c = VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.UP, 1.0, 999)
	if c != null and c._vel.size() == a._vel.size():
		var same := true
		for i in range(a._vel.size()):
			if a._vel[i].distance_to(c._vel[i]) > 0.001:
				same = false
				break
		if same:
			_fail("不同种子产生了完全相同的一发 —— 种子根本没起作用")
	host.queue_free()
	await process_frame

## 绝不能碰全局 RNG: 每日挑战靠那条流让所有人跑同一局, 而粒子发射极其频繁。
func _test_never_touches_global_rng() -> void:
	print("\n[STEP 5] 不碰全局 RNG...")
	var host := _host()

	seed(4242)
	var baseline := randi()

	seed(4242)
	for _i in range(12):
		VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.RIGHT)
		VFXParticles.emit("impact_spark", host, Vector2.ZERO, Vector2.UP)
	var after := randi()

	if baseline != after:
		_fail("发射粒子动了全局 RNG 流 (%d vs %d) —— 每日挑战会因此分叉" % [baseline, after])
	else:
		print("  [PASS] 发射 24 发之后全局 RNG 序列不变。")
	host.queue_free()

## 粒子到寿命就要消失, 节点在全部消失后要自毁 —— 否则战斗打久了场上全是空节点。
func _test_particles_expire_and_free() -> void:
	print("\n[STEP 6] 寿命到期与自毁...")
	var host := _host()
	var node = VFXParticles.emit("impact_spark", host, Vector2.ZERO, Vector2.RIGHT)
	if node == null:
		_fail("自毁测试: 发射失败")
		host.queue_free()
		return

	# impact_spark 最长 0.30s, 给足 3 秒的帧数。
	var frames := 0
	while frames < 400 and is_instance_valid(node):
		await process_frame
		frames += 1

	if is_instance_valid(node):
		_fail("400 帧后粒子节点仍然存在 (剩 %d 颗), 不会自毁" % node._pos.size())
	else:
		print("  [PASS] %d 帧内全部到期并自毁。" % frames)
	host.queue_free()
	await process_frame

## 同屏总量要有上限。连环爆炸时宁可少画几颗, 也不要把刚修好的帧预算吃回去。
func _test_global_budget_caps() -> void:
	print("\n[STEP 7] 全局粒子预算...")
	var host := _host()
	for _i in range(400):
		VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.RIGHT)
	var live: int = VFXParticles._live_particles
	if live > VFXParticles.GLOBAL_MAX_PARTICLES:
		_fail("同屏粒子 %d 颗, 超过上限 %d" % [live, VFXParticles.GLOBAL_MAX_PARTICLES])
	else:
		print("  [PASS] 猛发 400 发后同屏 %d 颗, 未超上限 %d。" % [live, VFXParticles.GLOBAL_MAX_PARTICLES])
	host.queue_free()
	# 等节点真的释放, 否则下一个测试会读到被这一步撑满的计数
	for _i in range(6):
		await process_frame

## 一整发粒子只占一个 CanvasItem: 所有粒子画在本节点的 _draw() 里,
## 而不是每颗一个 Sprite2D。**退回每颗一个节点不会报错, 只会变慢**,
## 所以必须有东西盯着。
func _test_single_canvas_item() -> void:
	print("\n[STEP 8] 单 CanvasItem 渲染...")
	var host := _host()
	var node = VFXParticles.emit("debris", host, Vector2.ZERO, Vector2.RIGHT)
	if node == null:
		_fail("渲染测试: 发射失败")
		host.queue_free()
		return
	var kids: int = node.get_child_count()
	if kids > 0:
		_fail("粒子节点有 %d 个子节点 —— 应该全部走 _draw(), 不建子节点" % kids)
	elif node._pos.size() < 2:
		_fail("粒子太少 (%d), 这一步测不出东西" % node._pos.size())
	else:
		print("  [PASS] %d 颗粒子, 0 个子节点。" % node._pos.size())
	host.queue_free()

## 翻书层的随播抖动: 要真的在变, 但必须是确定性的轮换而不是 randf()。
func _test_flipbook_jitter_varies_but_is_deterministic() -> void:
	print("\n[STEP 9] 翻书层随播抖动...")

	VFXAnimator._jitter_cursor = 0
	var seen_rot := {}
	var seen_scale := {}
	for _i in range(8):
		var j := VFXAnimator._next_jitter()
		seen_rot[j[0]] = true
		seen_scale[j[1]] = true
	if seen_rot.size() < 4:
		_fail("8 次抖动只出现了 %d 种旋转值, 变化太少" % seen_rot.size())
	elif seen_scale.size() < 3:
		_fail("8 次抖动只出现了 %d 种缩放值, 变化太少" % seen_scale.size())
	else:
		print("  [PASS] 8 次里有 %d 种旋转 / %d 种缩放。" % [seen_rot.size(), seen_scale.size()])

	# 确定性: 游标归零后必须重放出同一串。
	VFXAnimator._jitter_cursor = 0
	var first := VFXAnimator._next_jitter()
	VFXAnimator._jitter_cursor = 0
	var again := VFXAnimator._next_jitter()
	if first[0] != again[0] or first[1] != again[1]:
		_fail("同一游标位置取到了不同的抖动 —— 说明掺了随机数")
	else:
		print("  [PASS] 同游标位置可重现 (确定性轮换, 不是 randf)。")

	# dir_to_rot: 零向量要安全退回 0, 否则 Vector2.ZERO.angle() 会把
	# 所有"没有方向"的特效都钉在 0 弧度上看不出问题, 但调用方无从判空。
	if VFXAnimator.dir_to_rot(Vector2.ZERO) != 0.0:
		_fail("dir_to_rot(ZERO) 应当返回 0")
	if absf(VFXAnimator.dir_to_rot(Vector2.RIGHT)) > 0.001:
		_fail("dir_to_rot(RIGHT) 应当是 0 弧度")
	if absf(VFXAnimator.dir_to_rot(Vector2.DOWN) - PI / 2.0) > 0.001:
		_fail("dir_to_rot(DOWN) 应当是 PI/2")
	print("  [PASS] dir_to_rot 的方向换算正确。")

## 接线检查: 读源码确认粒子层真的挂在了战斗路径上。
##
## 上面全部步骤都是直接调 emit() 的单元测试 —— 它们在"有人把 bullet.gd 里那几行
## 删掉"之后仍然全绿, 因为 API 本身没坏, 只是游戏里再也不发射粒子了。这种断线
## 不报任何错, 只是画面变回原样。同一个手法见 test_netcode.gd 读 player.gd 源码
## 确认输入接缝还在。
func _test_call_sites_are_wired() -> void:
	print("\n[STEP 10] 战斗路径上的接线...")
	var expect := {
		"res://scripts/bullet.gd": ["impact_spark", "debris"],
		"res://scripts/explosion.gd": ["ember", "smoke"],
	}
	for path in expect:
		var f := FileAccess.open(String(path), FileAccess.READ)
		if f == null:
			_fail("读不到 %s" % path)
			continue
		var src := f.get_as_text()
		f.close()
		# 去掉整行注释, 免得"注释里提过一次"就算通过 —— 空转的绿。
		var code := ""
		for line in src.split("\n"):
			var stripped := line.strip_edges()
			if not stripped.begins_with("#"):
				code += line + "\n"
		if code.find("VFXParticles.emit(") < 0:
			_fail("%s 里没有任何 VFXParticles.emit() 调用 —— 粒子层没接到战斗路径上" % path)
			continue
		for preset in expect[path]:
			if code.find("\"%s\"" % preset) < 0:
				_fail("%s 里没有发射 '%s' 预设" % [path, preset])
	if not _failed:
		print("  [PASS] bullet.gd / explosion.gd 均已接线。")
