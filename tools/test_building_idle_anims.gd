extends SceneTree

## 建筑待机循环动画的门禁 (雷达站 / EMP 塔 / 工厂)。
##
##     & $godot --headless --path . --script tools/test_building_idle_anims.gd
##
## 帧由 tools/build_building_idle_anims.py 渲出。这里查四件事, 每一件都对应
## 一个在做这批动画时**真的出过**的缺陷:
##
##   1. 幅度落在现役循环动画的区间里。鹰巢待机第一版只有 0.21, 比全项目最轻的
##      环境动效 (tile_water 0.33) 还低, 到 48px 显示尺寸不足 1 像素 —— 白做。
##      工厂待机第一版同样栽在这里 (0.60)。
##
##   2. 没有卡住的帧。雷达站第一版用 `A*sin(phase)` 做扇形往复, 6 个均匀相位上
##      sin 值是 0/.866/.866/0/-.866/-.866 —— f1 与 f2、f4 与 f5 完全同角度,
##      实测相邻帧 ΔRGB `3.28 0.01 3.28 3.31 0.00 3.31`, 每循环卡顿两次。
##      **中位数完全看不出这个问题** (3.29, 很健康), 必须查最小值。
##
##   3. 地基逐帧 alpha 掩码完全一致。鹰巢那次是逐帧重播抖动种子, 底座外圈每帧
##      要变 160~240 个像素, 播出来整个基座轮廓在沸腾。
##
##   4. 游戏里真的接上了。渲出 18 张图但忘了在 .gd 里调 attach(), 跑起来一切
##      正常, 只是楼不动 —— 没有任何测试会因此变红, 所以这里直接读源码。
##
## 按 CLAUDE.md 的约定: 用 _failed 标志 + 末尾唯一一次 quit(), 不用 assert
## (assert 在 headless 下是挂起而不是失败), 也不在中途 quit(1) (会被后面的
## quit(0) 覆盖掉)。

const SPRITES := "res://assets/sprites/buildings/"
const N_FRAMES := 6

## 现役循环动画的相邻帧整图 RGB 均差 (2026-09 重渲后实测):
##   tile_water 0.33 (最轻) / base_eagle 1.12 / roller_wall 1.55 /
##   wind_blower 3.97 / bunker 5.21 (最重)
## 区间取 [1.10, 5.30] —— 下界是"至少要比全项目最轻的环境动效明显",
## 上界是"别比转起来的风机还闹腾"。
const AMP_MIN := 1.10
const AMP_MAX := 5.30

## 单帧不许比这个还静。见类注释第 2 条 —— 中位数查不出卡帧。
const AMP_FRAME_FLOOR := 1.00

## 地基环带 (像素半径)。三栋楼的底座都在 r>=58 之外收边, 旋转部件够不到那里。
const BASE_RING_MIN := 70.0
const BASE_RING_MAX := 118.0

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true


func _load_frames(stem: String) -> Array:
	var out: Array = []
	for i in range(N_FRAMES):
		var path := "%s%s_f%d.png" % [SPRITES, stem, i]
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


## 相邻帧 (含 f5->f0 的循环闭合) 的整图 RGB 均差。
func _adjacent_deltas(frames: Array) -> Array:
	var deltas: Array = []
	for i in range(frames.size()):
		var a: PackedByteArray = frames[i].get_data()
		var b: PackedByteArray = frames[(i + 1) % frames.size()].get_data()
		var total := 0.0
		var n := 0
		var j := 0
		while j < a.size():
			total += absf(float(a[j]) - float(b[j]))
			total += absf(float(a[j + 1]) - float(b[j + 1]))
			total += absf(float(a[j + 2]) - float(b[j + 2]))
			n += 3
			j += 4
		deltas.append(total / float(maxi(n, 1)))
	return deltas


func _median(vals: Array) -> float:
	var s := vals.duplicate()
	s.sort()
	return s[s.size() / 2]


## 地基环带里, 有多少像素的 alpha 掩码在各帧之间不一致。
func _base_ring_mask_churn(frames: Array) -> int:
	var base: Image = frames[0]
	var w: int = base.get_width()
	var h: int = base.get_height()
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	var churn := 0
	for y in range(h):
		for x in range(w):
			var r := sqrt(pow(x - cx, 2.0) + pow(y - cy, 2.0))
			if r < BASE_RING_MIN or r >= BASE_RING_MAX:
				continue
			var first: bool = base.get_pixel(x, y).a > 0.5
			for i in range(1, frames.size()):
				var other: Image = frames[i]
				if (other.get_pixel(x, y).a > 0.5) != first:
					churn += 1
					break
	return churn


func _check_sequence(stem: String) -> void:
	var frames := _load_frames(stem)
	if frames.is_empty():
		return

	var deltas := _adjacent_deltas(frames)
	var med := _median(deltas)
	var lo: float = deltas.min()

	var line := ""
	for d in deltas:
		line += "%.2f " % d

	if med < AMP_MIN:
		_fail("%s 待机幅度太轻: 相邻帧 ΔRGB 中位 %.2f < %.2f —— 参照 tile_water 0.33 / roller_wall 1.55 / wind_blower 3.97, 这个量级到 48px 显示尺寸就看不见了。逐帧: %s"
			% [stem, med, AMP_MIN, line])
	elif med > AMP_MAX:
		_fail("%s 待机幅度太重: 相邻帧 ΔRGB 中位 %.2f > %.2f —— 比转起来的风机还闹腾, 常驻动效不该这么抢眼。逐帧: %s"
			% [stem, med, AMP_MAX, line])

	if lo < AMP_FRAME_FLOOR:
		_fail("%s 有卡住的帧: 最小相邻帧 ΔRGB 只有 %.2f (< %.2f), 而中位是 %.2f —— 中位健康说明整体幅度没问题, 卡的是某两帧。往复动画用均匀相位采样正弦就会这样 (峰值两侧对称撞车), 见 build_building_idle_anims.py 里雷达站那段。逐帧: %s"
			% [stem, lo, AMP_FRAME_FLOOR, med, line])

	var churn := _base_ring_mask_churn(frames)
	if churn > 0:
		_fail("%s 地基在动: 环带 r[%d,%d) 里有 %d 个像素的 alpha 掩码逐帧不一致, 期望 0 —— 底座压在固定格子上, 一动整栋楼看起来就在地上漂。多半是逐帧重播了抖动种子 (应当在 builder 里 reset_jitter_seed 成同一个值)。"
			% [stem, int(BASE_RING_MIN), int(BASE_RING_MAX), churn])

	print("  %-14s 幅度中位 %.2f (最小 %.2f) 地基churn %d   逐帧 %s"
		% [stem, med, lo, churn, line])


## 去掉注释, 只留代码。
##
## 源码检查必须先做这一步, 而且两个方向都会错:
##   - 查"不许出现" (randi) 时, 命中自己解释为什么不许用 randi 的那句注释;
##   - 查"必须出现" (attach) 时, 一句提到它的注释就能让检查空转变绿。
## 这两个坑在做这批改动时各踩了一次 —— qa_style_consistency.py 的 srgb 检查
## 第一版也是被自己 docstring 里的示例命中的, 那次改用了 ast。GDScript 这边没有
## 现成的解析器, 按行砍 `#` 已经够用 (本仓库的 .gd 里没有含 # 的字符串字面量)。
func _code_only(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var i := line.find("#")
		out += (line if i < 0 else line.substr(0, i)) + "\n"
	return out


## 渲了图但没在 .gd 里接上, 是这类改动最容易漏掉的一步 —— 而且漏了完全没有报错。
func _check_wired() -> void:
	var wiring := {
		"res://scripts/buildings/radar_station.gd": "radar_station.png",
		"res://scripts/buildings/emp_tower.gd": "emp_tower.png",
		"res://scripts/buildings/factory.gd": "factory.png",
	}
	for path in wiring:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("读不到 " + path)
			continue
		var src := _code_only(f.get_as_text())
		f.close()
		if not src.contains("BuildingIdleAnim.attach"):
			_fail("%s 没有调用 BuildingIdleAnim.attach() —— 18 张待机帧渲出来了但游戏里不会播, 而且不会有任何报错" % path)

	var hf := FileAccess.open("res://scripts/building_idle_anim.gd", FileAccess.READ)
	if hf == null:
		_fail("读不到 building_idle_anim.gd")
		return
	var hsrc := _code_only(hf.get_as_text())
	hf.close()

	# 每日挑战在 start_game() 里给全局 RNG 播了种, 之后敌人生成一路都在从这条流
	# 上取数。在建筑 _ready() 里随手 randi() 会让当天所有人的 run 分叉 ——
	# explosion.gd 挑爆炸差分时用静态计数器而不是 randi(), 就是同一个理由。
	if hsrc.contains("randi(") or hsrc.contains("randf("):
		_fail("building_idle_anim.gd 用了 randi()/randf() 错开相位 —— 这会挪动全局 RNG 流, 让每日挑战的地图和敌人对所有人都不一样。应当用静态计数器轮转 (见 explosion.gd)。")

	# _process 被傀儡关掉了, 所以待机必须走 Tween。见 building_idle_anim.gd 类注释。
	if not hsrc.contains("create_tween"):
		_fail("building_idle_anim.gd 没有用 create_tween() 驱动 —— net_puppet.gd 对 SCENE_NODE 傀儡调了 set_process(false), 改回 _process 会让客户端上玩家自己盖的建筑不动, 而地图自带的那座在动。")


func _run() -> void:
	print("=== 建筑待机循环动画 ===")
	for stem in ["radar_station", "emp_tower", "factory"]:
		_check_sequence(stem)
	_check_wired()

	print("")
	if _failed:
		print("[FAIL] 建筑待机动画检查未通过")
		quit(1)
	else:
		print("[OK] 建筑待机动画检查全部通过")
		quit(0)


func _init() -> void:
	_run()
