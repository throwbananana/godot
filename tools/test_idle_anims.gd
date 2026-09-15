extends SceneTree

## 待机循环动画的门禁 —— 有源建筑 + 战场拾取物。
##
##     & $godot --headless --path . --script tools/test_idle_anims.gd
##
## 帧由 tools/build_building_idle_anims.py 和 tools/build_pickup_idle_anims.py
## 渲出, 由 scripts/sprite_idle_anim.gd 播放。
##
## (本文件取代了原来的 test_building_idle_anims.gd —— 拾取物那批做出来之后,
##  两组用的是同一套判据, 分成两个文件只会让两边的阈值慢慢漂开。)
##
## === 幅度必须按"每帧移动了几个像素"来量, 不能按像素均差 ===
##
## 第一版量的是相邻帧整图 RGB 均差。那个数**把"动得快"和"轮廓大且高对比"
## 混为一谈**了: 一颗 ☆ 缓慢自转 (每帧 12°) 得 13.9, 而一台风机高速旋转只得
## 3.8 —— 不是因为星转得快, 而是因为星的轮廓又大又是纯金色压在透明底上,
## 边缘扫过的每个像素都是满对比。照那个数去调, 会把本来很舒服的星硬压慢。
##
## 现在改成: 相邻帧均差 ÷ **该精灵自己平移 1px 造成的均差**。分母正好抵掉了
## "这张图有多少对比度"这个因素, 商就是"这一帧相对上一帧, 大约移动了几个
## 像素"—— 一个能直接和显示尺寸对话的量。全部在 48px 上算, 因为那才是玩家
## 看到的尺寸 (main.gd: TILE_SIZE 48 / 渲染 256)。
##
## 实测现役循环 (px/帧, 本文件自己打印的口径): base_eagle 0.13 /
## roller_wall 0.16 / ammo_depot 0.18 / command_post 0.22 / sniper_nest 0.25 /
## factory 0.40 / wind_blower 0.50 / emp_tower 0.61 / radar_station 0.79 /
## bunker 1.97。
##
## === 自发光脉动曾经整体失效, 排查动画"没动"时先查这条 ===
##
## create_clay_mat 末尾有一道防过曝钳位 (emission_peak=0.85): 对线性峰值为 1.0
## 的颜色, **任何大于 0.85 的 emission_str 都会被压成同一个 0.85**。而现役几段
## 待机动画原本给的是 1.7~8.0, 整个区间都在钳位线以上 —— 于是四个"明灭/呼吸"
## 通道逐帧完全没有变化, 恒等于零而不是幅度不够。
##
## 佐证是工厂那串逐帧读数曾经是 `0.36 0.36 0.36 0.36 0.36 0.36`, 六个数一位
## 小数都不差 —— 画面上只有烟 (纯几何) 在动。修好之后变成
## `0.40 0.37 0.39 0.41 0.37 0.40`。
##
## 现在一律走 build_building_idle_anims.py::_pulse_str 把强度映射到钳位以内。
##
## === 其余三条检查 ===
##
##   1. 没有卡住的帧。用**最小值与中位数的比**而不是绝对值 —— 幅度本来就小的
##      动画 (鹰巢 0.13) 和幅度大的动画不该用同一个绝对下限。雷达站第一版
##      `3.28 0.01 3.28 3.31 0.00 3.31` 中位健康而每循环卡顿两次, 炸弹第一版
##      更是有一对完全相同的帧 —— 两者的中位数都看不出问题。
##   2. 地基不许整体在动 (**只对建筑**)。建筑压在固定格子上, 底座一动整栋楼
##      就像在地上漂; 拾取物是自由摆放的, 没有这条。判据是环带里"有变化的
##      扇区占比", 不是"变化的像素数"—— 详见 BASE_CHURN_MAX_FRAC 的注释。
##   3. 不能被画幅裁掉 (**只对拾取物**)。道具本来就把 256px 占得比较满, 动起来
##      一旦出框就是"边缘一闪一闪"。建筑是满幅底板, 贴边是正常的。
##
## 按 CLAUDE.md 的约定: _failed 标志 + 末尾唯一一次 quit(), 不用 assert
## (headless 下 assert 是挂起而不是失败), 也不在中途 quit(1) (会被后面的
## quit(0) 覆盖掉)。

const N_FRAMES := 6
const DISP := 48

## 每帧移动的像素数 (48px 显示尺寸)。上界 2.60 略高于现役最闹腾的 bunker(1.97),
## 给 ☆ 这种"玩家必须注意到"的道具留了余量; 下界 0.12 略低于最含蓄的鹰巢(0.13)。
const AMP_MIN_PX := 0.12
const AMP_MAX_PX := 2.60

## 卡帧判据: 最小帧间运动不得低于中位数的这个比例。
const STALL_RATIO := 0.25

## 即使在豁免名单里, 也不允许两帧几乎完全相同。
const STALL_ABS_FLOOR := 0.12

## 地基环带 (像素半径), 只对建筑。
const BASE_RING_MIN := 70.0
const BASE_RING_MAX := 118.0

## 环带按角度切成多少份, 以及"有变化的扇区"占比的上限。
##
## === 为什么从"一个像素都不许变"改成"变化必须局限在一个扇区" ===
##
## 原判据是: 环带 r[70,118) 里的 alpha 掩码必须逐帧完全一致 (churn == 0)。
## 那个环带**只是"地基在哪"的代理**, 而这个代理对一部分建筑不成立 ——
## 狙击碉堡伸在外面的枪架落在 r=0.56~1.12, 正好压在环带上。枪架是武器不是
## 地基, 它横扫搜索是这栋楼该有的动作, 老判据却会把它判成"整栋楼在地上漂"。
##
## 直接放宽成"允许若干像素变化"是不行的: 环带检查真正要抓的两个 bug ——
## 整栋楼平移、以及逐帧重播抖动种子导致的轮廓沸腾 —— 都是**低强度但遍布
## 全周**的, 用像素数当阈值就得放到很大, 那时候它也抓不住原来那两个 bug 了。
##
## 区分它们的不是强度而是**角向分布形状**: 附件在动 = churn 集中在一个扇区;
## 整栋楼在动 / 轮廓沸腾 = churn 铺满整个周长。实测 (自测方法见下):
##
##                      正常          逐帧重播种子 (复现 bug)
##     command_post     0/180  (0%)   178/180  (99%)
##     sniper_nest     20/112 (18%)   114/112 (102%)
##     radar/emp/factory/ammo_depot   0%
##
## 18% 与 99% 之间空档极大, 阈值取 0.35 两边都有两三倍余量。
##
## === 这条放宽是自测过的, 不是"调到能过为止" ===
##
## 把 reset_jitter_seed 换成逐帧不同的种子 (rerender_vfx.py 就是这么写的,
## 也正是鹰巢待机第一版的真实 bug), 重渲 6 帧, 新判据必须变红。实测 99%/102%,
## 远在 35% 之上。**幅度指标抓不住这个 bug** (command_post 0.21 -> 0.36, 反而
## 更"合格"了), 所以环带检查是承重的, 只能改判据不能删。
const BASE_ANGLE_BINS := 180
const BASE_CHURN_MAX_FRAC := 0.35

## 拾取物离画幅边缘至少要留的像素。
const PICKUP_MARGIN_MIN := 3

## 节奏本来就该不均匀、因此豁免 STALL_RATIO 的资源。
##
## life 是心跳: 收缩期"咚-哒"两下之后有一段舒张停顿, 那段停顿正是它读起来像
## 心跳而不像呼吸的原因。用正弦把它抹平, 就等于把这个道具的语义删掉了。
## 这条豁免和 test_semantic_vfx.gd 给 vfx_build_assemble 开的口子是同一类:
## 主规则表达的是常态, 而这个资源的正确形态恰好是常态的反面 —— 所以要
## **单独断言它的反面性质** (这里是 STALL_ABS_FLOOR: 可以慢, 但不许有重复帧)。
const UNEVEN_OK := {"life": "心跳的舒张停顿; 抹平就不像心跳了"}

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true


func _load_frames(dir_name: String, stem: String) -> Array:
	var out: Array = []
	for i in range(N_FRAMES):
		var path := "res://assets/sprites/%s/%s_f%d.png" % [dir_name, stem, i]
		if not FileAccess.file_exists(path):
			_fail("%s 缺少第 %d 帧 (%s)" % [stem, i, path])
			return []
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			_fail("%s_f%d.png 读不出来" % [stem, i])
			return []
		img.convert(Image.FORMAT_RGBA8)
		out.append(img)
	return out


## 缩到显示尺寸并预乘 alpha, 返回 [w*h*3] 的浮点数组。
## 预乘是为了让"半透的边缘"按它实际压在背景上的权重计入, 而不是按它的原色。
func _premultiplied_48(src: Image) -> PackedFloat32Array:
	var img := Image.new()
	img.copy_from(src)
	img.resize(DISP, DISP, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = img.get_data()
	var out := PackedFloat32Array()
	out.resize(DISP * DISP * 3)
	var j := 0
	var k := 0
	while j < raw.size():
		var a := float(raw[j + 3]) / 255.0
		out[k] = float(raw[j]) * a
		out[k + 1] = float(raw[j + 1]) * a
		out[k + 2] = float(raw[j + 2]) * a
		j += 4
		k += 3
	return out


func _mean_abs_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var total := 0.0
	for i in range(a.size()):
		total += absf(a[i] - b[i])
	return total / float(maxi(a.size(), 1))


## 把图整体横移 1px 造成的均差 —— "一个像素的运动"值多少个单位。
## 这是上面那个归一化的分母, 见类注释。
func _one_pixel_scale(a: PackedFloat32Array) -> float:
	var shifted := PackedFloat32Array()
	shifted.resize(a.size())
	for y in range(DISP):
		for x in range(DISP):
			var src_x := (x + DISP - 1) % DISP
			var di := (y * DISP + x) * 3
			var si := (y * DISP + src_x) * 3
			shifted[di] = a[si]
			shifted[di + 1] = a[si + 1]
			shifted[di + 2] = a[si + 2]
	return _mean_abs_diff(a, shifted)


func _median(vals: Array) -> float:
	var s := vals.duplicate()
	s.sort()
	return s[s.size() / 2]


## 地基环带里的逐帧 alpha 掩码变化, 按角度分箱统计。
##
## 返回 {px, hit, present}: 变化的像素数 / 含变化的扇区数 / 环带里**任意一帧**
## 有不透明像素的扇区数。分母用"任意一帧"而不是"第 0 帧" —— 拿第 0 帧当分母
## 时, 一个扫出第 0 帧轮廓之外的附件会让占比算出 102% 这种数。
func _base_ring_churn(frames: Array) -> Dictionary:
	var base: Image = frames[0]
	var w: int = base.get_width()
	var h: int = base.get_height()
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	var bin_w := 360.0 / float(BASE_ANGLE_BINS)
	var churn := 0
	var hit := {}
	var present := {}
	for y in range(h):
		for x in range(w):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var r := sqrt(dx * dx + dy * dy)
			if r < BASE_RING_MIN or r >= BASE_RING_MAX:
				continue
			var b := int(fposmod(rad_to_deg(atan2(dy, dx)), 360.0) / bin_w) % BASE_ANGLE_BINS
			var first: bool = base.get_pixel(x, y).a > 0.5
			var any_opaque := first
			var differs := false
			for i in range(1, frames.size()):
				var other: bool = (frames[i] as Image).get_pixel(x, y).a > 0.5
				if other:
					any_opaque = true
				if other != first:
					differs = true
			if any_opaque:
				present[b] = true
			if differs:
				churn += 1
				hit[b] = true
	return {"px": churn, "hit": hit.size(), "present": present.size()}


## 各帧里最靠近画幅边缘的那一帧, 还剩多少像素余量。
func _min_frame_margin(frames: Array) -> int:
	var worst := 9999
	for f in frames:
		var img: Image = f
		var w := img.get_width()
		var h := img.get_height()
		var x0 := w
		var x1 := -1
		var y0 := h
		var y1 := -1
		for y in range(h):
			for x in range(w):
				if img.get_pixel(x, y).a > 0.03:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		if x1 < 0:
			continue
		worst = mini(worst, mini(mini(x0, w - 1 - x1), mini(y0, h - 1 - y1)))
	return worst


func _check_sequence(dir_name: String, stem: String, is_building: bool) -> void:
	var frames := _load_frames(dir_name, stem)
	if frames.is_empty():
		return

	var flat: Array = []
	for f in frames:
		flat.append(_premultiplied_48(f))

	var scale_sum := 0.0
	for a in flat:
		scale_sum += _one_pixel_scale(a)
	var px_scale := scale_sum / float(flat.size())
	if px_scale <= 0.001:
		_fail("%s: 整组图几乎是空的, 无法归一化" % stem)
		return

	var moves: Array = []
	for i in range(flat.size()):
		moves.append(_mean_abs_diff(flat[i], flat[(i + 1) % flat.size()]) / px_scale)

	var med := _median(moves)
	var lo: float = moves.min()
	var line := ""
	for m in moves:
		line += "%.2f " % m

	if med < AMP_MIN_PX:
		_fail("%s 待机幅度太轻: 每帧只移动 %.2f px (< %.2f) —— 参照 base_eagle 0.13 / wind_blower 0.50 / bunker 1.97, 这个量级在 48px 显示尺寸下看不出来。逐帧: %s"
			% [stem, med, AMP_MIN_PX, line])
	elif med > AMP_MAX_PX:
		_fail("%s 待机幅度太重: 每帧移动 %.2f px (> %.2f) —— 比全项目最闹腾的 bunker(1.97) 还高, 常驻动效不该这么抢眼。逐帧: %s"
			% [stem, med, AMP_MAX_PX, line])

	if UNEVEN_OK.has(stem):
		if lo < STALL_ABS_FLOOR:
			_fail("%s 有近乎重复的帧: 最小帧间运动 %.2f px < %.2f。这个资源允许节奏不均匀 (%s), 但仍然不许出现两帧几乎一样。逐帧: %s"
				% [stem, lo, STALL_ABS_FLOOR, UNEVEN_OK[stem], line])
	elif lo < med * STALL_RATIO:
		_fail("%s 有卡住的帧: 最小帧间运动 %.2f px, 只有中位 %.2f px 的 %.0f%% —— 中位健康说明整体幅度没问题, 卡的是某两帧。均匀相位采样任何单一正弦都会成对撞上同一个值 (a*sin+b*cos 也没用, 那仍是一条正弦); 要么加一个二倍频/显式表格通道, 要么改成单调推进的整圈旋转。逐帧: %s"
			% [stem, lo, med, 100.0 * lo / maxf(med, 0.0001), line])

	var extra := ""
	if is_building:
		var ring := _base_ring_churn(frames)
		var present: int = maxi(ring["present"], 1)
		var frac := float(ring["hit"]) / float(present)
		extra = "地基churn %d px, %d/%d 扇区 (%.0f%%)" % [ring["px"], ring["hit"], present, 100.0 * frac]
		if frac > BASE_CHURN_MAX_FRAC:
			_fail("%s 地基在动: 环带 r[%d,%d) 里有 %d/%d 个扇区 (%.0f%%) 的 alpha 掩码逐帧不一致, 上限 %.0f%% —— 变化铺满整个周长而不是集中在某一处, 这是**整栋楼在动**或**轮廓在沸腾**的形状, 不是某个附件在动 (附件实测只占 18%%)。底座压在固定格子上, 一动整栋楼看起来就在地上漂。最常见的原因是逐帧重播了抖动种子: builder 里应当 reset_jitter_seed 成**同一个值**, 而不是像 rerender_vfx.py 那样 seed+i。注意幅度指标抓不住这个 bug (实测重播种子反而让幅度从 0.21 涨到 0.36), 别拿「幅度正常」当反证。"
				% [stem, int(BASE_RING_MIN), int(BASE_RING_MAX), ring["hit"], present,
					100.0 * frac, 100.0 * BASE_CHURN_MAX_FRAC])
	else:
		var margin := _min_frame_margin(frames)
		extra = "画幅余量 %dpx" % margin
		if margin < PICKUP_MARGIN_MIN:
			_fail("%s 动起来顶到画幅了: 最紧的一帧只剩 %d px 余量 (< %d) —— 再大一点就会被裁掉一角, 而裁切在动画里表现为边缘一闪一闪, 比不做动画还难看。"
				% [stem, margin, PICKUP_MARGIN_MIN])

	print("  %-14s %.2f px/帧 (最小 %.2f) %-16s 逐帧 %s"
		% [stem, med, lo, extra, line])


## 去掉注释, 只留代码。
##
## 源码检查必须先做这一步, 而且两个方向都会错:
##   - 查"不许出现" (randi) 时, 会命中自己解释为什么不许用 randi 的那句注释;
##   - 查"必须出现" (attach) 时, 一句提到它的注释就能让检查空转变绿。
## 这两个坑各踩过一次。GDScript 没有现成的解析器, 按行砍 `#` 已经够用
## (本仓库的 .gd 里没有含 # 的字符串字面量)。
func _code_only(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var i := line.find("#")
		out += (line if i < 0 else line.substr(0, i)) + "\n"
	return out


## 渲了图但没在 .gd 里接上, 是这类改动最容易漏掉的一步 —— 而且漏了完全没有报错。
func _check_wired() -> void:
	for path in [
		"res://scripts/buildings/radar_station.gd",
		"res://scripts/buildings/emp_tower.gd",
		"res://scripts/buildings/factory.gd",
		"res://scripts/buildings/command_post.gd",
		"res://scripts/buildings/ammo_depot.gd",
		"res://scripts/buildings/sniper_nest.gd",
		"res://scripts/power_up.gd",
		"res://scripts/gold_coin.gd",
	]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("读不到 " + path)
			continue
		var src := _code_only(f.get_as_text())
		f.close()
		if not src.contains("SpriteIdleAnim.attach"):
			_fail("%s 没有调用 SpriteIdleAnim.attach() —— 帧渲出来了但游戏里不会播, 而且不会有任何报错" % path)

	# 金币原来那句 2D 自转必须去掉: 它会和渲好的倾角自转叠在一起, 变成一枚
	# 既在翻又在打转的硬币。
	var cf := FileAccess.open("res://scripts/gold_coin.gd", FileAccess.READ)
	if cf != null:
		var csrc := _code_only(cf.get_as_text())
		cf.close()
		if csrc.contains("sprite.rotation +="):
			_fail("gold_coin.gd 还留着 `sprite.rotation +=` 的 2D 自转 —— 它会和待机帧里的倾角自转叠加, 读起来是硬币又翻又转")

	var hf := FileAccess.open("res://scripts/sprite_idle_anim.gd", FileAccess.READ)
	if hf == null:
		_fail("读不到 sprite_idle_anim.gd")
		return
	var hsrc := _code_only(hf.get_as_text())
	hf.close()

	# 每日挑战在 start_game() 里给全局 RNG 播了种, 之后敌人生成一路都在从这条流
	# 上取数。在 _ready() 里随手 randi() 会让当天所有人的 run 分叉 ——
	# explosion.gd 挑爆炸差分时用静态计数器而不是 randi(), 就是同一个理由。
	if hsrc.contains("randi(") or hsrc.contains("randf("):
		_fail("sprite_idle_anim.gd 用了 randi()/randf() 错开相位 —— 这会挪动全局 RNG 流, 让每日挑战的地图和敌人对所有人都不一样。应当用静态计数器轮转 (见 explosion.gd)。")

	# _process 被 SCENE_NODE 傀儡关掉了, 所以待机必须走 Tween。
	if not hsrc.contains("create_tween"):
		_fail("sprite_idle_anim.gd 没有用 create_tween() 驱动 —— net_puppet.gd 对 SCENE_NODE 傀儡调了 set_process(false), 改回 _process 会让客户端上玩家自己盖的建筑不动, 而地图自带的那座在动。")


func _run() -> void:
	print("=== 待机循环动画 (幅度按 48px 下每帧移动的像素数) ===")
	print("--- 有源建筑 ---")
	for stem in ["radar_station", "emp_tower", "factory",
			"command_post", "ammo_depot", "sniper_nest"]:
		_check_sequence("buildings", stem, true)
	print("--- 战场拾取物 ---")
	for stem in ["star", "gold_coin", "clock", "helmet", "shovel", "bomb", "life"]:
		_check_sequence("powerups", stem, false)
	_check_wired()

	print("")
	if _failed:
		print("[FAIL] 待机动画检查未通过")
		quit(1)
	else:
		print("[OK] 待机动画检查全部通过")
		quit(0)


func _init() -> void:
	_run()
