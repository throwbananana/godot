extends SceneTree

## 语义化特效组的门禁 (tools/build_semantic_vfx.py 渲的那六组)。
##
## 为什么不并进 test_explosion_vfx.gd: 那个测的是"爆炸型序列必须消散", 这里要测
## 的三件事它结构上做不到 ——
##
##   1. vfx_build_assemble 的规矩是**反的** (向内收敛, 末帧最实), 拿消散断言套它
##      只会把它改坏;
##   2. 这批资源的存在理由是"可区分", 那是序列*之间*的性质, 单序列检查看不见;
##   3. 改接的调用点会不会被人改回通用冲击波, 得断言 VFXAnimator 的接口还在。
##
## 最值钱的是第 2 条。这批东西是为了解决一个量出来的问题: VFXAnimator 12 个
## spawn_* 函数 240 处调用, 其中 spawn_shockwave / spawn_clay_debris /
## spawn_dust_puff 三个占了 198 处 —— 胜利爆发、EMP 瘫痪、雷达扫描、护盾充能、
## 宝箱开启、跳板弹射、钥匙拾取、虫洞、建筑爆破、鹰旗阵亡全共用同一个灰环。
## 如果新加的六组彼此仍然长得差不多, 那这批工作就白做了, 而且**没有任何现有
## 断言能发现这件事** —— 每一组单独看都完全合格。
##
## 关键: 区分度必须在**显示尺寸**上量, 不是在 256px 源图上。世界精灵按
## TILE_SCALE=0.1875 画 (256 -> 48px), 源图上明显的细节到 48px 基本不剩什么。
## 这和 CLAUDE.md 里"阶段2 世界坐标颗粒"那次的教训是同一条: 验收指标要定在
## 玩家真正看到的那个尺寸上, 否则量的是自己没在看的东西。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_semantic_vfx.gd

const TextureHelper = preload("res://scripts/texture_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

## 显示尺寸。48px 是 TILE_SIZE, 也是这些特效在战场上实际占的量级。
const DISPLAY_PX := 48

## 两组特效在 48px 下的平均通道差, 低于这个值就认为"玩家分不出来"。
##
## 12.0 这个数是量出来的, 中间还错过一次, 值得把过程留在这里:
##
## 第一版拍了 8.0, 理由写的是"参照现役资源的最小值"—— 但当时**根本没量**。
## 实际量完 9 组现役特效的 36 个两两组合: 最小 14.39 (dust_puff vs clay_debris),
## 中位 39.99。也就是 8.0 比现役最差的一对还松了将近一半, 方向和我以为的相反。
##
## 定 12.0 而不是 14.39, 是因为这个指标只比**峰值那一帧**, 看不见运动 —— 而
## 运动是实打实的区分手段: build_assemble 向内收敛、heal_pulse 竖向上升、
## sand_burst 横向塌落, 这些在播放时一眼可辨, 在静帧上却完全不体现。所以指标
## 是个偏保守的下界, 卡在现役最小值稍下方比较合适。低于 12 则是任何现役组合都
## 达不到的相似度, 那就一定是真问题。
##
## 当前落在 12~14.4 这个带里的三对 (frost vs dust_puff 12.3 / reward vs
## muzzle_flash 12.7 / frost vs muzzle_flash 14.0) 是有意接受的: 它们在游戏里
## 从不同时出现 —— 枪口火花只在炮管上、扬尘只在移动和撞击时、碎冰只在被冻住
## 那一下 (而且同时坦克会变蓝并停住), 上下文本身就把它们分开了。
const MIN_PAIR_DIST := 12.0

var failures: int = 0

var SEQS := {
	"heal_pulse": "res://assets/sprites/effects/vfx_heal_pulse_f%d.png",
	"emp_pulse": "res://assets/sprites/effects/vfx_emp_pulse_f%d.png",
	"reward_burst": "res://assets/sprites/effects/vfx_reward_burst_f%d.png",
	"frost_shatter": "res://assets/sprites/effects/vfx_frost_shatter_f%d.png",
	"sand_burst": "res://assets/sprites/effects/vfx_sand_burst_f%d.png",
	"build_assemble": "res://assets/sprites/effects/vfx_build_assemble_f%d.png",
	# 第二批拆分。通用特效那时仍然承担着 217 处调用 (shockwave 82 /
	# clay_debris 74 / dust_puff 61), 这两组拆的是其中最要命的两对语义:
	# "打不动" vs "打没了"、"受伤" vs "被摧毁"。
	"ricochet_spark": "res://assets/sprites/effects/vfx_ricochet_spark_f%d.png",
	"hit_spall": "res://assets/sprites/effects/vfx_hit_spall_f%d.png",
}


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> SEMANTIC VFX TEST <<<")
	print("==================================================")

	_check_all_frames_present()
	_check_build_assemble_converges()
	_check_pairwise_distinct()
	# 等一帧再 spawn: _init() 阶段刚 add_child 的节点还没真正进树,
	# 此时 VFXAnimator._notify_darkness_flash() 里的 parent.get_tree() 会返回
	# null 并让引擎打一条 ERROR。它本身有 null 保护、不影响结果, 但那条红字
	# 混在测试输出里会被当成真失败。
	await process_frame
	_check_spawn_api()

	print("\n==================================================")
	if failures > 0:
		print("❌ %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL SEMANTIC VFX CHECKS PASSED! <<<")
		quit(0)


## 每组 6 帧都要能加载, 且都不能是空图。
##
## "空图"这条是有来历的: 当年 build_ui_character_art_replacements.py 少了一次
## clear_scene(), 九张 UI 图渲成了一模一样的灰方块并且就这么入库了 —— 渲染
## 本身"成功"了, 没有任何东西报错。
func _check_all_frames_present() -> void:
	print("\n--- 帧完整性 ---")
	for name in SEQS:
		var tmpl: String = SEQS[name]
		var missing := 0
		var blank := 0
		for i in range(6):
			var tex = TextureHelper.get_tex(tmpl % i)
			if tex == null:
				missing += 1
				continue
			if _coverage(tex) < 0.002:
				blank += 1
		if missing > 0:
			fail("%s 有 %d 帧加载不出来" % [name, missing])
		elif blank > 0:
			fail("%s 有 %d 帧几乎全空 —— 疑似渲染时场景是空的" % [name, blank])
		else:
			ok("%s 6 帧齐全且非空" % name)


## build_assemble 的反向断言。
##
## 它是全项目唯一向内收敛的特效, 演的是"建筑落成"。这里量的不是覆盖率 (收敛
## 过程中总墨量基本不变), 而是**亮部离中心的平均距离**必须单调下降 —— 那才是
## "合拢"这件事本身。用覆盖率去量会得出"没有变化", 看不出方向。
func _check_build_assemble_converges() -> void:
	print("\n--- build_assemble 收敛方向 ---")
	var tmpl: String = SEQS["build_assemble"]
	var radii: Array[float] = []
	for i in range(6):
		var tex = TextureHelper.get_tex(tmpl % i)
		if tex == null:
			fail("build_assemble 第 %d 帧加载不出来" % i)
			return
		radii.append(_mean_radius(tex))

	var line := ""
	for r in radii:
		line += "%6.1f" % r
	print("   平均半径:%s" % line)

	if radii[5] >= radii[0]:
		fail("build_assemble 末帧平均半径 %.1f 不小于首帧 %.1f —— 没有在合拢" % [radii[5], radii[0]])
	else:
		ok("平均半径 %.1f -> %.1f, 确实向内收敛" % [radii[0], radii[5]])

	# 顺带钉死它*不该*消散: 有人把它加进 test_explosion_vfx.gd 的列表就会在这里红。
	var covs: Array[float] = []
	for i in range(6):
		covs.append(_coverage(TextureHelper.get_tex(tmpl % i)))
	var peak := covs[0]
	for c in covs:
		peak = maxf(peak, c)
	if covs[5] < peak * 0.5:
		fail("build_assemble 末帧覆盖率 %.1f%% 掉到峰值 %.1f%% 的一半以下 —— 它应该收束成实体, 不是散掉"
			% [covs[5] * 100.0, peak * 100.0])
	else:
		ok("末帧 %.1f%% 相对峰值 %.1f%%, 保持实体" % [covs[5] * 100.0, peak * 100.0])


## 这批资源的**存在理由**: 两两之间在 48px 下必须真的看得出区别。
##
## 每组取自己的峰值帧 (最能代表这组长相的一帧), 缩到 48px, 算平均通道差。
## 顺带把通用 shockwave 也拉进来比 —— 新效果和它撞了的话, 等于没拆。
func _check_pairwise_distinct() -> void:
	print("\n--- 48px 下的两两区分度 (阈值 %.1f) ---" % MIN_PAIR_DIST)

	var names: Array[String] = []
	var imgs: Array[Image] = []

	for name in SEQS:
		var img := _peak_frame_small(SEQS[name])
		if img == null:
			fail("%s 取不到峰值帧" % name)
			continue
		names.append(name)
		imgs.append(img)

	# 现役特效作为对照组。不能只放 shockwave: 实测新特效真正容易撞的是
	# dust_puff 和 muzzle_flash (它们同样是"几团中等大小的亮斑"), 只比冲击波
	# 会漏掉真正的风险对。clay_debris / explosion 一并带上凑够参照面。
	var refs := {
		"shockwave(旧)": "res://assets/sprites/effects/shockwave_%d.png",
		"dust_puff(旧)": "res://assets/sprites/effects/dust_puff_%d.png",
		"muzzle_flash(旧)": "res://assets/sprites/effects/muzzle_flash_%d.png",
		"clay_debris(旧)": "res://assets/sprites/effects/clay_debris_%d.png",
		"explosion(旧)": "res://assets/sprites/effects/explosion_%d.png",
	}
	for rname in refs:
		var rimg := _peak_frame_small(refs[rname])
		if rimg != null:
			names.append(rname)
			imgs.append(rimg)

	var worst := 999.0
	var worst_pair := ""
	for a in range(names.size()):
		for b in range(a + 1, names.size()):
			var d := _img_distance(imgs[a], imgs[b])
			if d < worst:
				worst = d
				worst_pair = "%s vs %s" % [names[a], names[b]]
			if d < MIN_PAIR_DIST:
				fail("%s vs %s 在 48px 下只差 %.1f —— 玩家分不出这两个事件" % [names[a], names[b], d])

	if failures == 0:
		ok("最接近的一对是 %s, 差 %.1f (阈值 %.1f)" % [worst_pair, worst, MIN_PAIR_DIST])


## 接口还在, 且确实产出 6 帧动画。
##
## 断言的是*行为*不是名字: 只检查函数名存在的话, 有人把函数体清空成 pass 也
## 照样绿。这里真的 spawn 一次, 数生成的 VFXAnimator 挂了几帧贴图。
##
## 写法说明: 这些是 static 函数, 而 GDScript 不允许在脚本类上直接 has_method()
## / call() (会是解析错误, 不是运行期 false)。所以这里把它们当 Callable 直接
## 引用。副作用是**删掉其中任何一个函数会让这个测试文件解析失败**而不是报一条
## [FAIL] —— 依然是红的, 只是错误信息长得不一样, 别以为是测试自己坏了。
func _check_spawn_api() -> void:
	print("\n--- VFXAnimator 接口 ---")
	var fns := [
		["spawn_heal_pulse", VFXAnimator.spawn_heal_pulse],
		["spawn_emp_pulse", VFXAnimator.spawn_emp_pulse],
		["spawn_reward_burst", VFXAnimator.spawn_reward_burst],
		["spawn_frost_shatter", VFXAnimator.spawn_frost_shatter],
		["spawn_sand_burst", VFXAnimator.spawn_sand_burst],
		["spawn_build_assemble", VFXAnimator.spawn_build_assemble],
		["spawn_ricochet_spark", VFXAnimator.spawn_ricochet_spark],
		["spawn_hit_spall", VFXAnimator.spawn_hit_spall],
	]
	for entry in fns:
		var fn_name: String = entry[0]
		var fn_call: Callable = entry[1]
		var host := Node2D.new()
		root.add_child(host)
		fn_call.call(host, Vector2(100, 100), 1.0)
		var frames := 0
		for c in host.get_children():
			if c is VFXAnimator:
				frames = maxi(frames, c.frame_textures.size())
		if frames < 6:
			fail("%s() 只产出 %d 帧动画, 期望 6 帧" % [fn_name, frames])
		else:
			ok("%s() 产出 %d 帧" % [fn_name, frames])
		host.queue_free()


# ---------------------------------------------------------------- 工具

func _coverage(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var img := tex.get_image()
	var opaque := 0
	var total := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			total += 1
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / maxf(1.0, float(total))


## 不透明像素到画面中心的平均距离 (按半幅归一到 0..100)。
func _mean_radius(tex: Texture2D) -> float:
	var img := tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var cx := w * 0.5
	var cy := h * 0.5
	var half := minf(cx, cy)
	var sum := 0.0
	var n := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).a > 0.5:
				sum += Vector2(x - cx, y - cy).length()
				n += 1
	if n == 0:
		return 0.0
	return (sum / float(n)) / half * 100.0


## 取一段序列覆盖率最大的那一帧, 缩到显示尺寸。
func _peak_frame_small(tmpl: String) -> Image:
	var best_i := -1
	var best_cov := -1.0
	for i in range(6):
		var tex = TextureHelper.get_tex(tmpl % i)
		if tex == null:
			continue
		var c := _coverage(tex)
		if c > best_cov:
			best_cov = c
			best_i = i
	if best_i < 0:
		return null
	var img := TextureHelper.get_tex(tmpl % best_i).get_image()
	img = img.duplicate()
	img.resize(DISPLAY_PX, DISPLAY_PX, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


## 两张 48px 图的平均通道差 (0..255)。透明处按"底色"参与比较, 这样剪影差异
## 也会计入 —— 形状不同本来就是这批效果最主要的区分手段。
func _img_distance(a: Image, b: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(DISPLAY_PX):
		for x in range(DISPLAY_PX):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			# 预乘 alpha: 透明区域折算成 0, 剪影差异因此直接体现在数值上
			sum += absf(ca.r * ca.a - cb.r * cb.a) * 255.0
			sum += absf(ca.g * ca.a - cb.g * cb.a) * 255.0
			sum += absf(ca.b * ca.a - cb.b * cb.a) * 255.0
			n += 3
	return sum / maxf(1.0, float(n))
