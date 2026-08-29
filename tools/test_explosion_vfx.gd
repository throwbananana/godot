extends SceneTree

## 爆炸类特效的回归测试。
##
## 核心断言是"消散不变量": 一段爆炸动画的 alpha 覆盖率必须*先涨后跌* ——
## 中间某一帧最大, 最后一帧要显著小于峰值。
##
## 这不是凭空定的规矩, 它精确对应这次修掉的那个缺陷: 旧版三段动画的半径都由
## `scale_factor = 起点 + frame * 步长` 这种单调递增公式算出来, 于是烟越飘越
## *大*, explosion 的最后一帧覆盖率 33.7% 反而比峰值帧 19.0% 还大 —— 爆炸永远
## 不会消散, 只会一路胖成一颗糊在屏幕上的大球然后被整帧切掉。
##
## 所以这条断言是能咬人的: 拿 HEAD 之前的旧图跑, explosion 和 dust 都会红。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_explosion_vfx.gd

const TextureHelper = preload("res://scripts/texture_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const EnemyTank = preload("res://scripts/enemy.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _tick(n: int) -> void:
	for i in range(n):
		await physics_frame


func _init() -> void:
	print("==================================================")
	print(">>> EXPLOSION / BLAST VFX TEST <<<")
	print("==================================================")

	_check_sequence("explosion", "res://assets/sprites/effects/explosion_%d.png")
	_check_sequence("suicide_blast", "res://assets/sprites/effects/vfx_suicide_blast_f%d.png")
	_check_sequence("dust_puff", "res://assets/sprites/effects/dust_puff_%d.png")
	_check_sequence("boss_plasma_nova", "res://assets/sprites/effects/boss_plasma_nova_%d.png")
	_check_sequence("boss_frost_nova", "res://assets/sprites/effects/boss_frost_nova_%d.png")
	_check_legacy_asset_gone()
	await _check_runtime()

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL EXPLOSION VFX CHECKS PASSED! <<<")
		quit(0)


func _coverage(tex: Texture2D) -> float:
	var img := tex.get_image()
	var opaque := 0
	var total := 0
	# 每 3 像素采样一次就够了 —— 要的是趋势, 不是精确面积
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			total += 1
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / float(max(1, total))


func _check_sequence(label: String, path_tmpl: String) -> void:
	print("\n--- %s ---" % label)
	var covs: Array[float] = []
	for i in range(6):
		var tex = TextureHelper.get_tex(path_tmpl % i)
		if tex == null:
			fail("%s 第 %d 帧加载不出来" % [label, i])
			return
		covs.append(_coverage(tex))

	var line := ""
	for c in covs:
		line += "%5.1f%%" % (c * 100.0)
	print("    覆盖率: %s" % line)

	# 每帧都得有东西 —— 本仓库出过"渲染成功但整张空白"的事故
	for i in range(6):
		if covs[i] < 0.005:
			fail("%s 第 %d 帧几乎全透明 (%.2f%%)" % [label, i, covs[i] * 100.0])
			return

	var peak_i := 0
	for i in range(6):
		if covs[i] > covs[peak_i]:
			peak_i = i

	if peak_i == 0 or peak_i == 5:
		fail("%s 的峰值在第 %d 帧 —— 爆炸必须先胀后消, 峰值应在中段" % [label, peak_i])
	else:
		ok("峰值在第 %d 帧 (%.1f%%)" % [peak_i, covs[peak_i] * 100.0])

	# 消散: 末帧要显著小于峰值。旧版 explosion 是 33.7% vs 19.0%, 这里会红。
	if covs[5] >= covs[peak_i] * 0.5:
		fail("%s 末帧覆盖率 %.1f%% 相对峰值 %.1f%% 没降下来 —— 没有消散"
			% [label, covs[5] * 100.0, covs[peak_i] * 100.0])
	else:
		ok("末帧 %.1f%% 相对峰值 %.1f%% 已消散" % [covs[5] * 100.0, covs[peak_i] * 100.0])

	# 起手也要小: 爆炸是从一点炸开的
	if covs[0] >= covs[peak_i] * 0.6:
		fail("%s 首帧就有 %.1f%% (峰值 %.1f%%) —— 缺少炸开的过程"
			% [label, covs[0] * 100.0, covs[peak_i] * 100.0])
	else:
		ok("首帧 %.1f%%, 有起爆过程" % (covs[0] * 100.0))


func _check_legacy_asset_gone() -> void:
	print("\n--- 旧单帧资源 ---")
	# 那张静态图已被 6 帧动画取代。留着它的风险是有人再把它接回去, 于是自爆
	# 又变回"一张图 tween 缩放"。
	if FileAccess.file_exists("res://assets/sprites/effects/vfx_suicide_blast.png"):
		fail("旧的单帧 vfx_suicide_blast.png 还在, 应当已被 6 帧序列取代")
	else:
		ok("旧单帧图已删除")

	var src := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	if src.contains("vfx_suicide_blast.png"):
		fail("enemy.gd 里还引用着旧的单帧图")
	else:
		ok("enemy.gd 不再引用旧单帧图")


func _check_runtime() -> void:
	print("\n--- 实战场景 ---")
	var scene = load("res://scenes/main.tscn")
	if scene == null:
		fail("main.tscn 加载失败")
		return
	var main = scene.instantiate()
	root.add_child(main)
	await _tick(3)

	main._instantiate_enemy(Vector2(220, 220), EnemyTank.EnemyType.SUICIDE, false, 0)
	var foe: Node = null
	for c in main.actors_container.get_children():
		if "enemy_type" in c and c.enemy_type == EnemyTank.EnemyType.SUICIDE:
			foe = c
			break
	if foe == null:
		fail("SUICIDE 敌人没能实例化")
		main.queue_free()
		return

	# 先把场上已有的爆炸清掉, 免得把别人的算到自爆头上
	for c in main.actors_container.get_children():
		if c is Explosion or (c.get_script() != null and c is VFXAnimator):
			c.free()
	await _tick(1)

	foe.global_position = main.get_random_empty_tile_position()
	foe._suicide_detonate()
	await _tick(1)

	var anim_count := 0
	var explosion_count := 0
	var blast_frames := 0
	for c in main.actors_container.get_children():
		if c is Explosion:
			explosion_count += 1
		elif c is VFXAnimator:
			anim_count += 1
			if c.frame_textures.size() > blast_frames:
				blast_frames = c.frame_textures.size()

	if anim_count == 0:
		fail("自爆之后没有生成任何 VFXAnimator —— 爆炸动画没播")
	else:
		ok("自爆生成了 %d 个 VFXAnimator" % anim_count)

	if blast_frames < 6:
		fail("最长的那段爆炸动画只有 %d 帧, 期望 6 帧" % blast_frames)
	else:
		ok("爆炸动画有 %d 帧" % blast_frames)

	# 通用 explosion.tscn 已从自爆流程移除: 它会和专用爆炸叠在一起糊掉"绿核"
	# 这个辨识点, 而且 explosion.gd::_ready() 自己会再放一次爆炸音效, 撞车。
	if explosion_count > 0:
		fail("自爆还额外生成了 %d 个通用 Explosion —— 会叠图并重复播放音效" % explosion_count)
	else:
		ok("没有额外叠加通用 Explosion")

	main.queue_free()
	await _tick(1)
