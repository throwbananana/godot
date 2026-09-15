class_name BuildingSkin
extends Node

## 建筑的外观差分组件: 通用战损贴花 + 战区覆盖层。
##
## 用法是每个有血量的建筑在 _ready() 末尾加一行:
##
##     BuildingSkin.attach(self)
##
## === 为什么是一张通用贴花, 不是逐建筑的战损图 ===
##
## 有血量的建筑有十来种, 逐个渲两档战损是二十多张图, 而其中好几张的属主脚本
## 按 CLAUDE.md 的记录已经无法复现已提交的美术 —— 重渲它们等于拿已知可用的图
## 去换一版没人审过的。通用贴花是**新美术**, 不需要复现任何东西, 也就完全不碰
## 那些已提交的图。同一条路线在敌人那边已经走过两次 (enemy_plate_t1..t3、
## tank_dmg_t1/t2)。
##
## === clip_children 是这套方案能成立的关键 ===
##
## 通用贴花的死穴是建筑轮廓差别极大 (street_lamp 细高、bunker 方阔), 一张固定
## 形状的贴花必然有一部分飘在建筑外面, 读起来是"地上多了几道裂纹"而不是"这座
## 建筑裂了"。
##
## 所以这里把建筑的 Sprite2D 设成 CLIP_CHILDREN_AND_DRAW: 子节点被按父节点的
## alpha 裁剪, 贴花超出建筑轮廓的部分由引擎切掉。贴花那边相应地画得比任何单个
## 建筑都大 (见 tools/build_building_variants.py 的 DECAL_REACH), 这样小建筑上
## 也不会露出贴花自己的边 —— 那比飘在外面更假, 因为它是一条与建筑无关的直边。
##
## === region_rect 必须跟着抄 ===
##
## fortified_wall 不是一张整图: 它是 2x2 个 Piece, 每个用 region_rect 取
## 256x256 贴图的一个象限。贴花如果不抄这个 region, 四个象限会各自贴上一整张
## 完整的贴花, 于是一面墙上出现四份重复的裂纹。attach() 因此无条件从父
## Sprite2D 上抄 region_enabled / region_rect。
##
## === 哪些建筑不挂 ===
##
## wooden_wall 有自己专门画的三档战损 (wooden_wall_dmg0..2), 比通用贴花贴合,
## 保持原样不叠。它也是这套通用方案的参照物: 值得专门画的建筑就专门画, 通用
## 贴花是给"值不上专门画一套"的那十来种兜底的。

const TextureHelper = preload("res://scripts/texture_helper.gd")

const BUILDINGS := "res://assets/sprites/buildings/"

## 战损换档的血量比例。和 enemy.gd 的 DAMAGE_T1/T2_FRAC 保持一致 —— 玩家在
## 坦克身上学到的"这个花纹表示快死了", 应该在建筑上原样成立。
const DAMAGE_T1_FRAC := 0.60
const DAMAGE_T2_FRAC := 0.30
## 满血 1 的建筑没有中间态, 挂了也永远不显示。
const DAMAGE_MIN_MAX_HP := 2

const THEME_Z := 1
const DAMAGE_Z := 2

var _owner_node: Node = null
var _sprite: Sprite2D = null
var _damage_sprite: Sprite2D = null
var _tier: int = 0


## 给 building 挂上外观差分。找不到 Sprite2D 就安静地什么也不做 ——
## 差分是纯装饰, 不该因为某个建筑的场景结构不一样就让它 _ready() 崩掉。
static func attach(building: Node) -> BuildingSkin:
	if building == null:
		return null
	var spr := _find_sprite(building)
	if spr == null:
		return null

	# 子节点按父节点 alpha 裁剪 —— 见类注释。AND_DRAW 而不是 ONLY:
	# 建筑本身当然还要画出来。
	spr.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	# 战区覆盖层 (沙尘/积雪)。第一幕不挂 —— 三幕都盖一层就没有对照,
	# 玩家读不出"换战区了"。挂上去就不再变, 所以不需要进 _process。
	var act := GameState.get_visual_act()
	if act >= 2:
		var t_tex = TextureHelper.get_tex(BUILDINGS + "building_theme_a%d.png" % act)
		if t_tex:
			var theme_spr := Sprite2D.new()
			theme_spr.texture = t_tex
			theme_spr.z_index = THEME_Z
			_copy_region(spr, theme_spr)
			spr.add_child(theme_spr)

	var skin := BuildingSkin.new()
	skin.name = "BuildingSkin"
	skin._owner_node = building
	skin._sprite = spr
	building.add_child(skin)
	return skin


static func _find_sprite(building: Node) -> Sprite2D:
	# 多数建筑脚本自己有 `var sprite: Sprite2D`; 少数没有, 但场景里节点名
	# 都叫 Sprite2D; fortified_wall 的 Piece 是代码里 new 出来的, 走第三条。
	var declared = building.get("sprite")
	if declared is Sprite2D:
		return declared
	var by_name := building.get_node_or_null("Sprite2D")
	if by_name is Sprite2D:
		return by_name
	for child in building.get_children():
		if child is Sprite2D:
			return child
	return null


## 贴花必须和父 Sprite2D 用同一个 region, 否则被 region 切成四块的建筑
## (fortified_wall) 每一块都会贴上一整张贴花。
static func _copy_region(src: Sprite2D, dst: Sprite2D) -> void:
	if src.region_enabled:
		dst.region_enabled = true
		dst.region_rect = src.region_rect


func _process(_delta: float) -> void:
	_refresh()


## 按当前血量比例换战损档。只在跨档时动节点 —— 每帧重建 Sprite2D 既浪费,
## 也会让贴花在连续受击时闪。
func _refresh() -> void:
	if not is_instance_valid(_owner_node) or not is_instance_valid(_sprite):
		set_process(false)
		return
	var max_hp = _owner_node.get("max_health")
	var cur_hp = _owner_node.get("current_health")
	if not (max_hp is int) or not (cur_hp is int) or max_hp < DAMAGE_MIN_MAX_HP:
		# 这个建筑没有本组件认得的血量字段 —— 只吃战区覆盖层, 不吃战损。
		set_process(false)
		return

	var frac := float(cur_hp) / float(max_hp)
	var want := 0
	if frac <= DAMAGE_T2_FRAC:
		want = 2
	elif frac <= DAMAGE_T1_FRAC:
		want = 1
	if want == _tier:
		return
	_tier = want

	if is_instance_valid(_damage_sprite):
		_damage_sprite.queue_free()
	_damage_sprite = null
	if want <= 0:
		return
	var tex = TextureHelper.get_tex(BUILDINGS + "building_dmg_t%d.png" % want)
	if tex == null:
		return
	_damage_sprite = Sprite2D.new()
	_damage_sprite.texture = tex
	_damage_sprite.z_index = DAMAGE_Z
	_copy_region(_sprite, _damage_sprite)
	_sprite.add_child(_damage_sprite)
