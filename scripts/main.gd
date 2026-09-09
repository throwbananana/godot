class_name MainGame
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const AllyTank = preload("res://scripts/ally_tank.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")
const SpawnStar = preload("res://scripts/spawn_star.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")
const BuilderController = preload("res://scripts/builder_controller.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")
const MapDirector = preload("res://scripts/map_director.gd")
const CompositeRoomBuilder = preload("res://scripts/composite_room_builder.gd")
const DarknessFog = preload("res://scripts/darkness_fog.gd")
const FallingBombHazard = preload("res://scripts/falling_bomb_hazard.gd")
const BalanceLog = preload("res://scripts/balance_log.gd")
const FloorMap = preload("res://scripts/floor_map.gd")
const RoomDoor = preload("res://scripts/room_door.gd")
const Minimap = preload("res://scripts/minimap.gd")
const ShopStand = preload("res://scripts/shop_stand.gd")
const ShopRerolder = preload("res://scripts/shop_rerolder.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")
const NetSession = preload("res://scripts/net_session.gd")
const NetPuppet = preload("res://scripts/net_puppet.gd")

const TILE_SIZE: float = 48.0
const TILE_SCALE: float = TILE_SIZE / 256.0
## 普通房间恒为 13x13; 大房间(26x26)/超大房间(52x52)在 enter_room() 里改写这两个值,
## 所以不能再是 const -- 见 CompositeRoomBuilder。
var GRID_W: int = 13
var GRID_H: int = 13

## 屏幕上实际不被 SidePanel/边距遮挡的可视区域 (SidePanel 从 x=736 开始,
## GameArea 从 x=48 开始, 所以横向可视约 688px; 纵向留一点边距估 720px)。
## 这就是"视角视野还是原来的大小"的具体量化 -- 摄像机的 clamp 范围用它,
## 普通 13x13 房间 (624x624) 比它小, clamp 会把摄像机钉在房间正中心不动,
## 跟今天完全没有摄像机时的画面像素对像素一致; 只有 26x26/52x52 的大房间
## 才会真正触发滚动。
const CAMERA_VISIBLE_SIZE: Vector2 = Vector2(688.0, 720.0)

var rpg_mgr: RPGManager = RPGManager.new()

var player_scene: PackedScene
var enemy_scene: PackedScene
var base_scene: PackedScene
var powerup_scene: PackedScene
var spawnstar_scene: PackedScene
var landmine_hazard_scene: PackedScene
var ally_tank_scene: PackedScene

var tex_brick: Texture2D
var tex_steel: Texture2D
var tex_reinforced_steel: Texture2D
var tex_water_frames: Array[Texture2D] = []
var tex_trees: Texture2D
var tex_sand: Texture2D
var tex_sand_dune: Texture2D
var tex_hard_clay: Texture2D
var tex_ice: Texture2D
var tex_wormhole: Texture2D
var moving_platform_scene: PackedScene
var wormhole_scene: PackedScene
var shield_station_scene: PackedScene
var wind_blower_scene: PackedScene
var conveyor_belt_scene: PackedScene
var jump_pad_scene: PackedScene
var treasure_chest_scene: PackedScene
var treasure_key_scene: PackedScene
var diamond_gem_scene: PackedScene
var street_lamp_scene: PackedScene
var electric_wall_scene: PackedScene
var bomb_switch_scene: PackedScene
var energy_wall_scene: PackedScene
var oil_barrel_scene: PackedScene
var signal_jammer_tower_scene: PackedScene
var factory_scene: PackedScene
var drifting_supplies_scene: PackedScene
var enemy_shield_tower_scene: PackedScene
var pipe_conduit_scene: PackedScene
var radar_station_scene: PackedScene
var ammo_depot_scene: PackedScene
var command_post_scene: PackedScene
var sniper_nest_scene: PackedScene
var emp_tower_scene: PackedScene
var piston_switch_scene: PackedScene
var factory_instances: Array[Node] = [] # tracked for the battle-end gold reward multiplier
var battle_gold_earned: int = 0 # reset in start_game(), read by the Factory reward multiplier at _game_over()
var battle_start_msec: int = 0 # reset in start_game(), read by the balance log at _game_over()
var has_treasure_key: bool = false
var key_has_dropped: bool = false
var key_hidden_target_type: String = "block" # "block" or "enemy"
var key_target_block_instance: Node = null
var key_target_enemy_idx: int = -1
var current_map_layout: Array = []

# ---------------------------------------------------------------- 房间系统
#
# 一个 Act = 一层以撒式楼层, 整层楼都在 main.tscn 这**一个场景**里跑:
# 换房间是 _clear_all() + _build_room() 原地重建, 不是 change_scene_to_file()。
#
# 之所以不换场景: 玩家的血量、装甲、火车车厢、rpg_mgr 的本场状态全都挂在
# 节点和实例上, 换场景等于每过一道门就重来一遍 "sync_to_game_state ->
# 新场景 -> sync_from_game_state"。那条同步链是手写字段列表 (见 CLAUDE.md
# "The two state layers"), 每天走几十次的话, 漏一个字段的代价就从"换层掉一次"
# 变成"每过一道门掉一次"。原地重建则完全绕开它。
var doors: Dictionary = {}          # dir(int) -> RoomDoor
var is_transitioning: bool = false  # 切房动画期间吃掉输入与再次触发
var room_cleared_pending: bool = false
var fade_layer: ColorRect = null
var minimap: Minimap = null

# 事件 / 休息房的对话框。原来是 spire_map.tscn 的子节点 (在路线图上点节点触发),
# 现在改成走进对应房间触发。脚本内部只读写 GameState, 和所在场景无关,
# 所以搬过来一行没改。
#
# **商店不在这里** —— 它已经改成地板上的物理货位 (ShopStand),
# 没有对话框了。shop_dialog.gd / .tscn 保留着, 但只当"商店规则模块"用
# (build_inventory / item_by_id / can_buy_item / apply_item_purchase 都是 static),
# 并且仍然被 tools/test_shop_*.gd 和平衡探针当作数据源实例化。
var event_dialog: PanelContainer = null

var p1_instance: PlayerTank
var p2_instance: PlayerTank
var base_instance: BaseEagle
## "escort" 挑战房要保护的友军实例, 生命周期跟 base_instance 一样是"当前
## 房间"级别的——见 _clear_all()/_despawn_base() 旁边的清空点。
## 大/超大房间会一次性生成多只 (ESCORT_ALLY_COUNT), 所以是数组而不是单个
## 引用; escort_ally_original_count 记着刚生成时的总数, 用来算"过半阵亡"
## 的判负门槛 (见 _on_escort_ally_destroyed())。
var escort_ally_instances: Array[AllyTank] = []
var escort_ally_original_count: int = 0

## 活塞开关/电路谜题的当前房间状态。color(如 "red"/"blue") -> 是否已解开
## (circuit_solved) / 该颜色下所有受控建筑的实例 (circuit_gated_buildings)。
## 和 escort_ally_instances 同一个理由是当前房间级别的——房间每次重建都是
## 全新的建筑实例, 上一间房的开关状态对新房间毫无意义, 必须在 _clear_all()
## 里跟着清空, 否则会把上一间房已经按过的开关误判成"这间房也解开了"。
var circuit_solved: Dictionary = {}
var circuit_gated_buildings: Dictionary = {}

var score: int = 0
var p1_lives: int = 3
var p2_lives: int = 3

## 双人战役的"共享生命池 + 手动复活"机制: 死亡不立刻扣命/自动重生, 而是等
## 约 SHARED_REVIVE_DELAY 秒后弹出提示, 死亡玩家自己按开火键才复活并扣一条
## 共享生命。_lives_shared() 为 false 的模式 (单人、双人街机、每日挑战)
## 完全走原来的自动重生逻辑, 不受这套状态影响。
const SHARED_REVIVE_DELAY := 1.5
var p1_awaiting_revive: bool = false
var p2_awaiting_revive: bool = false

var total_enemies: int = 20
var enemies_spawned: int = 0
var enemies_alive: int = 0
var spawn_timer: float = 0.0
var spawn_interval: float = 3.0
var is_game_over: bool = false
var is_victory: bool = false

var shovel_timer: float = 0.0
var is_shovel_active: bool = false
var iff_flag_timer: float = 0.0
var iff_flag_active: bool = false

var darkness_fog_instance: DarknessFog = null
var is_night_mode_active: bool = false
var is_bomb_rain_active: bool = false
var bomb_rain_timer: float = 0.0
var bomb_rain_interval: float = 4.5

var enemy_spawn_points: Array[Vector2] = [
	Vector2(0.5 * TILE_SIZE, 0.5 * TILE_SIZE),
	Vector2(6.5 * TILE_SIZE, 0.5 * TILE_SIZE),
	Vector2(12.5 * TILE_SIZE, 0.5 * TILE_SIZE)
]
var p1_spawn_point: Vector2 = Vector2(4.5 * TILE_SIZE, 12.5 * TILE_SIZE)
var p2_spawn_point: Vector2 = Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE)
var water_sprites: Array[Sprite2D] = []

# 树林格号 -> Sprite2D。树冠是画在坦克*上面*的 (z_index=10) 且完全不透明,
# 所以钻进林子的坦克会彻底消失 —— 连自己在哪都看不到。这里按格记下来, 由
# _update_tree_transparency() 在有坦克压着时把那几格淡下去。
#
# 为什么不干脆把树冠整体做成半透明: MIRAGE 敌人静止时会把自己的贴图换成这张
# 树瓦片来伪装 (enemy.gd 的光学迷彩状态机)。整体调透明的话, 它那棵不透明的
# 假树会在一片半透明的真树里格外扎眼, 伪装当场失效。按格动态淡入淡出不碰
# 这个机制: 假树是敌人自己的 Sprite, 不在这张表里。
var tree_sprites: Dictionary = {}

# 被坦克压住时树冠的不透明度。不做成 0 是故意的 —— 树林的战术价值就是遮蔽,
# 全透就等于这块地形没用了。0.38 能让人看出"林子里有个东西在动"和自己的位置,
# 但看不清朝向和血条, 伏击仍然成立。
const TREE_REVEAL_ALPHA: float = 0.38
const TREE_FADE_SPEED: float = 6.0

# 风吹树冠的轻微摇摆。锚定在瓦片下半 (VERTEX.y > 0 处 top_weight 被 clamp 到 0),
# 只让上半的树冠晃, 免得整块 256px 不透明瓦片跟着水平漂移, 在相邻瓦片的接缝处
# 露出下面的地面瓦片 (参见 CLAUDE.md 里 tileseam 那段的教训)。相位从每棵树自己
# 的世界坐标哈希出来 (MODEL_MATRIX[3].xy), 所以同一份 ShaderMaterial 可以被全部
# 树冠 Sprite2D 共用, 而不会所有树同步晃成一个整体。伪装成树的 MIRAGE 用的是
# 敌方坦克自己的 Sprite2D, 不在这份材质的挂载点上, 保持静止 —— 这跟
# _update_tree_transparency() 特意跳过伪装中 MIRAGE 是同一个理由: 会动的树会把
# 静止的假树衬得格外显眼, 伪装机制就废了。
const TREE_SWAY_SHADER_CODE = """
shader_type canvas_item;

uniform float sway_speed = 1.1;
uniform float sway_amount = 4.0;

void vertex() {
	vec2 world_pos = MODEL_MATRIX[3].xy;
	float phase = fract(sin(dot(world_pos, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	float top_weight = clamp(-VERTEX.y / 128.0, 0.0, 1.0);
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount * top_weight;
}
"""
var _tree_sway_material: ShaderMaterial
var water_bodies: Array[StaticBody2D] = [] # used by player.gd's Amphibious Hull perk for add_collision_exception_with()
var water_frame: int = 0
var water_anim_timer: float = 0.0

var trauma: float = 0.0
var base_game_area_pos: Vector2 = Vector2(48.0, 48.0)
var max_shake_offset: Vector2 = Vector2(10.0, 10.0)
var trauma_decay: float = 2.4

## RoomCamera 的"零滚动"偏移量, 每次进房间 (GRID_W/GRID_H 确定后) 由
## _update_camera_bounds() 重算一次, 之后每帧只叠加抖动/跟随, 不再重算。
## 见 _update_camera_bounds() 的推导注释。
var camera_offset_base: Vector2 = Vector2.ZERO
## 摄像机当前实际瞄准的房间本地坐标 (已夹在房间边界内), 每帧由
## _update_camera_position() 刷新。
var camera_target_local: Vector2 = Vector2.ZERO

## 战场是按 1024x768 这块基准画布手搓的固定像素坐标 (GameArea/SidePanel/
## 热键栏/Boss 血条一开始都以为窗口就是 1024x768)。window/stretch/aspect=
## "expand" 不会帮它们居中 —— 宽/高分辨率下只会往右/下多显出一截画布, 这些
## 没有锚定去追踪新边缘的节点仍然贴在原来左上角, 分辨率越宽画面看起来就越
## 偏左上。_apply_layout_offset() 补上这一半的偏移量, 见该函数注释。
var layout_offset: Vector2 = Vector2.ZERO

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

## 把整块 1024x768 设计画布 (战场 + 侧栏 + 热键栏 + Boss 血条) 当一个整体,
## 居中摆进当前实际显示的画布里, 而不是任由 expand 把它钉在左上角。
##
## Background 已经在 main.tscn 里改成 anchors_preset=15 (铺满整个可视矩形),
## 会自己跟着变, 不需要手动摆。CenterMessage/RestartButton/PauseMenu/
## VictoryDefeatModal 这几个已经是 anchor=0.5 的居中控件, 本来就跟着窗口
## 真正的几何中心走, 也不用碰。剩下这几个是当初按固定像素坐标摆在设计画布
## 左上角附近的, 才需要手动补偏移:
##   - GameArea: 战场本体, Node2D 没有锚点这回事, 只能手动挪 (x, y 都要)。
##   - SidePanel: 同理是 offset_left/top 写死的 PanelContainer (x, y 都要)。
##   - hud_hotbar / hud_boss_bar: 已经分别是 BOTTOM_LEFT / TOP_WIDE 锚点,
##     纵向早就跟着新边缘自动挪了, 这里只需要补横向 (只动 .position.x,
##     不能碰 .position.y —— 覆盖掉纵向锚点已经算好的偏移量会前功尽弃)。
func _apply_layout_offset() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	layout_offset = (visible_size - Vector2(1024.0, 768.0)).max(Vector2.ZERO) / 2.0

	base_game_area_pos = Vector2(48.0, 48.0) + layout_offset
	# GameArea 节点本身的 position 不再需要跟着 layout_offset 挪 -- 加了
	# RoomCamera 之后, GameArea.position 在"世界坐标"和"摄像机世界坐标"两边
	# 都会加一次, 换算到屏幕坐标时正好抵消 (见 _update_camera_bounds() 的
	# 推导), 所以让它永远待在 main.tscn 里的默认值 (48,48) 就够, 不用再手写。
	# base_game_area_pos 仍然要算, 因为 _update_camera_bounds() 拿它当输入。

	if side_panel:
		side_panel.position = Vector2(736.0, 24.0) + layout_offset
	if hud_hotbar:
		hud_hotbar.position.x = 72.0 + layout_offset.x
	if hud_boss_bar:
		hud_boss_bar.position.x = 120.0 + layout_offset.x
		hud_boss_bar.position.y = 3.0 + layout_offset.y
	_update_camera_bounds()

## 房间中心的本地坐标 (相对 GameArea), 用整数列/行下取整再 +0.5 保证偶数宽的
## 大/超大房间也有一个明确的"中心格" (26 宽时中心列是 12, 不是 12.5)。
func _room_center_local() -> Vector2:
	var center_col := (GRID_W - 1) / 2
	var center_row := (GRID_H - 1) / 2
	return Vector2(center_col + 0.5, center_row + 0.5) * TILE_SIZE

## 摄像机是 GameArea 的子节点, 所以任意本地点 L 的屏幕坐标是
## VP/2 + L - (camera.position + camera.offset) -- GameArea 自身的 position
## 在这条链路里两边各出现一次, 正好消掉。要求"房间铺满可视区时,
## 画面跟没有摄像机时逐像素一致"(即 screen(L) == base_game_area_pos + L),
## 代入 camera.position == room_center (钉死不滚动的情形) 解出:
##   camera.offset == VP/2 - room_center - base_game_area_pos
## 这就是钉死模式的 offset。换房间 (GRID_W/GRID_H 变了) 或窗口尺寸变了都要
## 重算一次; 之后每帧只是在这个基准上叠加抖动, 不再重算。
##
## 大/超大房间的跟随模式不能照搬这条 offset —— 曾经这样实现过, 是一个真实
## 出现过的 bug (玩家反馈"大地图看不到坦克, 只看到移动"): 跟随模式下
## camera.position 每帧都在变 (追着玩家的本地坐标 L), 不再是常量
## room_center。把 screen(L) = VP/2 + L - camera.position - offset 代入
## camera.position == L (没被夹住时的跟随结果) 化简, L 会跟自己抵消掉,
## 结果 screen(L) = VP/2 - offset + (room_center 项的残留) —— 一个**跟 L
## 无关的常数**, 换算下来落在 room_center + base_game_area_pos, 对超大房间
## 而言远远超出 1024x768 画布之外。也就是说摄像机属性(position/offset)
## 每帧都在正确更新、连通性和地形分派也都正常, 但玩家在屏幕上的实际投影
## 位置纹丝不动地钉在画布外的同一个点上——只有夹墙(clamp)生效的边缘地带
## 才会因为 L 和 camera.position 出现差值而露出一点点画面, 这正好对应
## "摄像机不跟随、只有卡边时才动一下"的症状。
##
## 跟随模式需要一条不挂 room_center 的独立公式: 让"任意被跟随的本地点"都
## 落在游戏区列的正中央 (base_game_area_pos + CAMERA_VISIBLE_SIZE/2), 而不是
## 复用钉死模式那个针对常量 room_center 校准出来的偏移量。推导方式相同,
## 只是把"钉死点 room_center"换成"跟随模式下屏幕上应该显示被跟随点的锚点":
##   camera.offset == VP/2 - (base_game_area_pos + CAMERA_VISIBLE_SIZE/2)
## 按轴分别判定是否进入跟随模式 (跟 _camera_clamp_axis 的 room_size <= visible
## 判据保持一致), 因为两个方向理论上可能不同时超出可视区 (虽然目前大/超大
## 房间恒为正方形, 两轴总是同时触发)。
func _update_camera_bounds() -> void:
	if not room_camera:
		return
	var room_center := _room_center_local()
	var vp := get_viewport_rect().size
	var pinned_offset := vp / 2.0 - room_center - base_game_area_pos
	var follow_anchor := base_game_area_pos + CAMERA_VISIBLE_SIZE / 2.0
	var follow_offset := vp / 2.0 - follow_anchor
	camera_offset_base = Vector2(
		follow_offset.x if GRID_W * TILE_SIZE > CAMERA_VISIBLE_SIZE.x else pinned_offset.x,
		follow_offset.y if GRID_H * TILE_SIZE > CAMERA_VISIBLE_SIZE.y else pinned_offset.y
	)
	room_camera.offset = camera_offset_base
	room_camera.position = room_center
	camera_target_local = room_center

## 房间比可视窗口小(普通 13x13 房间)时摄像机钉在房间正中心不动 -- 这正是
## "视角视野还是原来的大小"的字面实现, 普通房间在这条分支下画面跟今天完全
## 没有摄像机时逐像素一致。房间比可视窗口大 (26x26/52x52) 时才真正夹住
## 滚动范围, 不让镜头看到房间边界外的虚空。
func _camera_clamp_axis(target: float, room_size: float, visible: float) -> float:
	if room_size <= visible:
		return room_size / 2.0
	return clampf(target, visible / 2.0, room_size - visible / 2.0)

## 每帧刷新摄像机瞄准点 (双人取中点), 在 _process() 里抖动叠加之前调用。
func _update_camera_position() -> void:
	if not room_camera:
		return
	var pts: Array[Vector2] = []
	if p1_instance and is_instance_valid(p1_instance):
		pts.append(map_container.to_local(p1_instance.global_position))
	if p2_instance and is_instance_valid(p2_instance) and GameState.player_count == 2:
		pts.append(map_container.to_local(p2_instance.global_position))
	var target: Vector2
	if pts.size() == 2:
		target = (pts[0] + pts[1]) / 2.0
	elif pts.size() == 1:
		target = pts[0]
	else:
		target = _room_center_local()
	camera_target_local = Vector2(
		_camera_clamp_axis(target.x, GRID_W * TILE_SIZE, CAMERA_VISIBLE_SIZE.x),
		_camera_clamp_axis(target.y, GRID_H * TILE_SIZE, CAMERA_VISIBLE_SIZE.y)
	)
	room_camera.position = camera_target_local

## 隐藏测试模式在战斗内的那一半 (关卡跳转在 debug_test_menu.gd 里)。F1 开关,
## 只在 GameState.debug_unlocked 时被 _ready() 建出来 —— "随意调用工具"按
## 用户原话理解成一小撮常用作弊动作, 而不是重新做一套控制台, 每个按钮都直接
## 复用游戏本来就有的路径 (add_gold()/rpg_mgr.add_level()/enemy._die() 等),
## 不另写一条与正常玩法分叉的成功/失败逻辑。
func _build_debug_panel() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.visible = false
	debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_panel.position = Vector2(-266.0, 8.0)
	debug_panel.custom_minimum_size = Vector2(256.0, 0)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UIThemeHelper.apply_clay_panel(debug_panel, Color(0.05, 0.20, 0.05, 0.94), 10)
	$HUD.add_child(debug_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	debug_panel.add_child(vb)

	var title := Label.new()
	title.text = "🧪 DEBUG TOOLS (F1 关闭)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55, 1))
	vb.add_child(title)

	var btn_gold := _make_debug_button("+500 GOLD (金币)")
	btn_gold.pressed.connect(func(): add_gold(500))
	vb.add_child(btn_gold)

	var btn_level := _make_debug_button("+1 LEVEL (等级)")
	btn_level.pressed.connect(func(): rpg_mgr.add_level(1))
	vb.add_child(btn_level)

	var btn_god := _make_debug_button("GOD MODE: OFF (无敌)")
	btn_god.pressed.connect(func():
		debug_god_mode = not debug_god_mode
		btn_god.text = "GOD MODE: %s (无敌)" % ("ON" if debug_god_mode else "OFF")
		_debug_apply_god_mode(debug_god_mode)
	)
	vb.add_child(btn_god)

	var btn_clear := _make_debug_button("☠️ CLEAR ROOM (清空本房)")
	btn_clear.pressed.connect(_debug_clear_room)
	vb.add_child(btn_clear)

	var btn_night := _make_debug_button("NIGHT FOG: OFF (夜战雾)")
	btn_night.pressed.connect(func():
		_debug_toggle_night_fog()
		btn_night.text = "NIGHT FOG: %s (夜战雾)" % ("ON" if is_night_mode_active else "OFF")
	)
	vb.add_child(btn_night)

	var btn_title := _make_debug_button("🔄 返回标题重选关卡")
	btn_title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))
	vb.add_child(btn_title)


func _make_debug_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	UIThemeHelper.apply_clay_button(b, false)
	return b


func _debug_apply_god_mode(on: bool) -> void:
	for p in [p1_instance, p2_instance]:
		if not (p and is_instance_valid(p)):
			continue
		if on:
			# 用一个很大的时长当"常驻无敌"用, 不新增一条独立于 invulnerable_timer
			# 的状态 —— 复用 set_invulnerable() 本来就有的倒计时/护盾贴图逻辑,
			# 一场测试会话内基本不可能倒计时耗尽。
			p.set_invulnerable(999999.0)
		else:
			p.is_invulnerable = false
			p.invulnerable_timer = 0.0
			if p.shield_sprite:
				p.shield_sprite.visible = false


## 杀光本房间当前存活的敌人, 并让spawner 别再补新的 —— 单独杀光存活的那一批
## 并不会立刻清房: _on_enemy_destroyed() 只有在 enemies_spawned >= total_enemies
## 且 enemies_alive <= 0 时才会判房间清空, 后续波次还会继续刷。这里把
## total_enemies 拉平到当前已刷出的数量, 相当于"提前用完这房间的怪"。
##
## 击杀走 enemy._die() 而不是 take_damage(999): 后者在 is_shielded() 为真时
## (比如站在敌方护盾塔范围内) 会直接吞掉伤害, 一个作弊工具打不穿自己游戏里的
## 防御机制没有意义。_die() 绕开护盾判定直接触发死亡结算, 这也是
## tools/test_firewall_tank.gd 已经在用的同一条路径, 不是本文件独创的后门。
##
## 分帧轮询而不是单次遍历一遍就收工: _request_spawn_enemy() 在丢出 spawn_star
## 的**那一刻**就已经 enemies_spawned += 1 / enemies_alive += 1 (main.gd::
## _request_spawn_enemy()), 而实际的坦克要等 spawn_star 的 finished 回调
## (_instantiate_enemy()) 才会真正加入 "enemies" 组。按下这颗按钮那一帧,
## 计数器里可能还挂着 1-2 只"已经算数但还没实体化"的怪 —— 只扫一遍
## get_nodes_in_group("enemies") 会漏掉它们, 房间因此差一只怪永远清不空。
func _debug_clear_room() -> void:
	total_enemies = enemies_spawned
	var waited := 0
	while enemies_alive > 0 and waited < 180:
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e.has_method("_die"):
				e._die()
		if enemies_alive <= 0:
			break
		await get_tree().process_frame
		waited += 1


func activate_darkness_fog() -> DarknessFog:
	if darkness_fog_instance and is_instance_valid(darkness_fog_instance):
		return darkness_fog_instance
	darkness_fog_instance = DarknessFog.new()
	darkness_fog_instance.setup_trackers(p1_instance, p2_instance, base_instance)
	if game_area:
		game_area.add_child(darkness_fog_instance)
	return darkness_fog_instance


func deactivate_darkness_fog() -> void:
	if not (darkness_fog_instance and is_instance_valid(darkness_fog_instance)):
		return
	if is_night_mode_active:
		return

	# Check if any active darkness devices still remain on the battlefield
	var devices = get_tree().get_nodes_in_group("darkness_device")
	for d in devices:
		if is_instance_valid(d) and not d.is_queued_for_deletion() and d.get("is_active") != false:
			return

	var fog = darkness_fog_instance
	darkness_fog_instance = null
	if is_inside_tree() and fog.is_inside_tree():
		var tw = fog.create_tween()
		tw.tween_property(fog, "modulate:a", 0.0, 0.35)
		tw.tween_callback(fog.queue_free)
	else:
		fog.queue_free()


func _debug_toggle_night_fog() -> void:
	is_night_mode_active = not is_night_mode_active
	if is_night_mode_active:
		activate_darkness_fog()
	else:
		deactivate_darkness_fog()


func hit_stop(duration_sec: float = 0.05) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(duration_sec * 0.05, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
	)

@onready var game_area: Node2D = $GameArea
@onready var map_container: Node2D = $GameArea/MapContainer
@onready var base_wall_container: Node2D = $GameArea/BaseWallContainer
@onready var actors_container: Node2D = $GameArea/ActorsContainer
@onready var builder_ctrl: BuilderController = $GameArea/BuilderController
@onready var room_camera: Camera2D = $GameArea/RoomCamera

@onready var hud_score: Label = $HUD/SidePanel/VBox/ScoreBox/ScoreLabel
@onready var hud_lives: Label = $HUD/SidePanel/VBox/LivesBox/LivesLabel
@onready var hud_enemies: Label = $HUD/SidePanel/VBox/EnemiesBox/EnemiesLabel
@onready var hud_rpg_level: Label = $HUD/SidePanel/VBox/RPGLevelLabel
@onready var hud_rpg_xp: ProgressBar = $HUD/SidePanel/VBox/XPBar
@onready var hud_gold: Label = $HUD/SidePanel/VBox/GoldBox/GoldLabel
@onready var hud_p1_hp: Label = $HUD/SidePanel/VBox/P1HPBox/P1HPLabel
@onready var hud_p1_hearts: HBoxContainer = $HUD/SidePanel/VBox/P1HPBox/P1Hearts
@onready var hud_p2_hp: Label = $HUD/SidePanel/VBox/P2HPBox/P2HPLabel
@onready var hud_p2_hearts: HBoxContainer = $HUD/SidePanel/VBox/P2HPBox/P2Hearts
@onready var hud_p2_hp_box: HBoxContainer = $HUD/SidePanel/VBox/P2HPBox
@onready var hud_score_icon: TextureRect = $HUD/SidePanel/VBox/ScoreBox/ScoreIcon
@onready var hud_lives_icon: TextureRect = $HUD/SidePanel/VBox/LivesBox/LivesIcon
@onready var hud_enemies_icon: TextureRect = $HUD/SidePanel/VBox/EnemiesBox/EnemiesIcon
@onready var hud_gold_icon: TextureRect = $HUD/SidePanel/VBox/GoldBox/GoldIcon
@onready var hud_p1_hp_icon: TextureRect = $HUD/SidePanel/VBox/P1HPBox/P1HPIcon
@onready var hud_p2_hp_icon: TextureRect = $HUD/SidePanel/VBox/P2HPBox/P2HPIcon
@onready var hud_controls_icon: TextureRect = $HUD/SidePanel/VBox/ControlsBox/ControlsIcon
@onready var pause_icon: TextureRect = $HUD/PauseMenu/VBox/PauseIcon
@onready var hud_stats: Label = $HUD/SidePanel/VBox/StatsLabel
@onready var hud_toast: Label = $HUD/SidePanel/VBox/ToastLabel
@onready var hud_status: Label = $HUD/CenterMessage
@onready var btn_restart: Button = $HUD/RestartButton
@onready var side_panel: PanelContainer = $HUD/SidePanel

@onready var pause_menu: PanelContainer = $HUD/PauseMenu
@onready var btn_resume: Button = $HUD/PauseMenu/VBox/ResumeButton
@onready var btn_settings_pause: Button = $HUD/PauseMenu/VBox/SettingsButton
@onready var btn_restart_stage: Button = $HUD/PauseMenu/VBox/RestartStageButton
@onready var btn_quit_menu: Button = $HUD/PauseMenu/VBox/QuitToMenuButton
@onready var pause_settings_dialog: SettingsDialog = $HUD/SettingsDialog

var upgrade_dialog: UpgradeSelectionDialog
var pending_upgrade_players: Array[int] = []
var hud_hotbar: Control = null
var hud_boss_bar: Control = null
var hud_boss_fill: TextureProgressBar = null
var hud_boss_label: Label = null
var active_boss_instance: Node2D = null
## 上一只 boss 死亡触发的淡出动画。它跑在后台 0.45s, 如果同一时间窗口内下一
## 只 boss (TRAIN_BOSS 常规填怪也算) 紧接着刷出来, _instantiate_enemy() 会把
## 血条立刻设回 visible/alpha=1 —— 但没有东西去打断这个残留的 tween, 它照样
## 会在稍后把 alpha 淡回 0 并在回调里 visible=false, 于是新 boss 明明还活着,
## 血条却在几帧后自己消失, 而数值 (hud_boss_fill.value) 因为走的是另一条
## 每帧同步的路径, 底下其实一直在正确刷新, 只是容器被隐藏了看不见。
## 任何要让血条重新出现的地方都必须先 kill() 掉这个残留 tween。
var hud_boss_fade_tween: Tween = null

## 隐藏调试面板 (F1 呼出), 只在 GameState.debug_unlocked 时由 _build_debug_panel()
## 建出来; 未解锁的正常玩家这个节点根本不存在, 不只是不可见。
var debug_panel: PanelContainer = null
var debug_god_mode: bool = false

var victory_modal_root: Control = null
var victory_modal_banner: TextureRect = null
var victory_modal_title: Label = null
var victory_modal_desc: Label = null
var victory_modal_stats: VBoxContainer = null
var victory_modal_button: Button = null

func _ready() -> void:
	player_scene = load("res://scenes/player.tscn")
	enemy_scene = load("res://scenes/enemy.tscn")
	base_scene = load("res://scenes/base_eagle.tscn")
	powerup_scene = load("res://scenes/power_up.tscn")
	spawnstar_scene = load("res://scenes/spawn_star.tscn")
	landmine_hazard_scene = load("res://scenes/landmine_hazard.tscn")
	ally_tank_scene = load("res://scenes/ally_tank.tscn")
	moving_platform_scene = load("res://scenes/moving_platform.tscn")
	wormhole_scene = load("res://scenes/wormhole.tscn")
	shield_station_scene = load("res://scenes/buildings/shield_station.tscn")
	wind_blower_scene = load("res://scenes/buildings/wind_blower.tscn")
	conveyor_belt_scene = load("res://scenes/conveyor_belt.tscn")
	jump_pad_scene = load("res://scenes/jump_pad.tscn")
	treasure_chest_scene = load("res://scenes/treasure_chest.tscn")
	treasure_key_scene = load("res://scenes/treasure_key.tscn")
	diamond_gem_scene = load("res://scenes/diamond_gem.tscn")
	street_lamp_scene = load("res://scenes/buildings/street_lamp.tscn")
	electric_wall_scene = load("res://scenes/buildings/electric_wall.tscn")
	oil_barrel_scene = load("res://scenes/buildings/oil_barrel.tscn")
	signal_jammer_tower_scene = load("res://scenes/buildings/signal_jammer_tower.tscn")
	factory_scene = load("res://scenes/buildings/factory.tscn")
	drifting_supplies_scene = load("res://scenes/drifting_supplies.tscn")
	enemy_shield_tower_scene = load("res://scenes/buildings/enemy_shield_tower.tscn")
	pipe_conduit_scene = load("res://scenes/buildings/pipe_conduit.tscn")
	radar_station_scene = load("res://scenes/buildings/radar_station.tscn")
	ammo_depot_scene = load("res://scenes/buildings/ammo_depot.tscn")
	command_post_scene = load("res://scenes/buildings/command_post.tscn")
	sniper_nest_scene = load("res://scenes/buildings/sniper_nest.tscn")
	emp_tower_scene = load("res://scenes/buildings/emp_tower.tscn")

	var upg_scene = load("res://scenes/upgrade_selection_dialog.tscn")
	if upg_scene:
		upgrade_dialog = upg_scene.instantiate()
		add_child(upgrade_dialog)
		upgrade_dialog.option_selected.connect(_on_upgrade_option_selected)
		# 客户端选完自己的卡, 把索引报给主机去应用 (见 net_apply_remote_upgrade)。
		upgrade_dialog.remote_option_picked.connect(func(index: int, pid: int):
			var n := get_node_or_null("/root/Net")
			if n:
				n.send_upgrade_pick(index, pid)
		)

	tex_brick = TextureHelper.get_tex("res://assets/sprites/tiles/tile_brick.png")
	tex_steel = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	# 强化钢墙暂时复用钢墙贴图, 在 _spawn_tile() 里用更深冷的色调压暗区分——
	# 项目里"靠明度而不是另画一张图区分层级"的既有做法(当年 tile_steel 就是
	# 这样跟 tile_ice 分开的), 真正的黏土渲染新图是后续单独的美术任务。
	tex_reinforced_steel = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	tex_trees = TextureHelper.get_tex("res://assets/sprites/tiles/tile_trees.png")
	tex_sand = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand.png")
	tex_sand_dune = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand_dune.png")
	tex_hard_clay = TextureHelper.get_tex("res://assets/sprites/tiles/tile_hard_clay.png")
	tex_ice = TextureHelper.get_tex("res://assets/sprites/tiles/tile_ice.png")
	tex_wormhole = TextureHelper.get_tex("res://assets/sprites/tiles/tile_wormhole.png")

	tex_water_frames.clear()
	for i in range(6):
		var w_tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_water_f%d.png" % i)
		if w_tex:
			tex_water_frames.append(w_tex)

	rpg_mgr.leveled_up.connect(_on_rpg_level_up)
	rpg_mgr.stats_changed.connect(_update_rpg_hud)
	rpg_mgr.gold_changed.connect(func(_g): _update_rpg_hud())

	UIThemeHelper.apply_hud_sidepanel($HUD/SidePanel)
	UIThemeHelper.apply_pause_menu_theme(pause_menu, [btn_resume, btn_settings_pause, btn_restart_stage, btn_quit_menu])
	UIThemeHelper.apply_clay_progressbar(hud_rpg_xp, Color(0.40, 0.88, 1.0, 1.0))
	# 经验条已经取消 -- 升级只能靠吃 STAR 道具, 没有可显示的"进度"了, 见
	# rpg_manager.gd::add_level()。节点留着 (main.tscn 不动), 只是隐藏。
	if hud_rpg_xp:
		hud_rpg_xp.visible = false

	if hud_toast:
		var toast_sb := StyleBoxFlat.new()
		toast_sb.bg_color = Color(0.18, 0.14, 0.22, 0.95)
		toast_sb.corner_radius_top_left = 8
		toast_sb.corner_radius_top_right = 8
		toast_sb.corner_radius_bottom_left = 8
		toast_sb.corner_radius_bottom_right = 8
		toast_sb.border_width_left = 2
		toast_sb.border_width_top = 2
		toast_sb.border_width_right = 2
		toast_sb.border_width_bottom = 2
		toast_sb.border_color = Color(0.55, 0.45, 0.65, 0.9)
		toast_sb.content_margin_left = 8
		toast_sb.content_margin_right = 8
		toast_sb.content_margin_top = 6
		toast_sb.content_margin_bottom = 6
		hud_toast.add_theme_stylebox_override("normal", toast_sb)
		hud_toast.modulate.a = 0.0
		hud_toast.visible = false
	
	TextureHelper._cache.clear()
	if hud_score_icon: hud_score_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_score_trophy.png")
	if hud_lives_icon: hud_lives_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/hp_heart_full.png")
	if hud_enemies_icon: hud_enemies_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_enemy_radar.png")
	if hud_gold_icon: hud_gold_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_badge_gold.png")
	if hud_p1_hp_icon: hud_p1_hp_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_tank_p1.png")
	if hud_p2_hp_icon: hud_p2_hp_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_tank_p2.png")
	if hud_controls_icon: hud_controls_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_controls.png")
	if pause_icon: pause_icon.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_pause.png")
	
	hud_hotbar = UIThemeHelper.create_hotbar_ui($HUD)

	# 切房用的黑幕。放在 HUD (CanvasLayer) 上而不是 GameArea 里, 这样它不跟着
	# 屏幕震动 (game_area.position 被 trauma 抖动) 一起晃, 也盖得住整个视口。
	fade_layer = ColorRect.new()
	fade_layer.color = Color(0.05, 0.04, 0.06, 1.0)
	fade_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.modulate.a = 0.0
	fade_layer.z_index = 50
	$HUD.add_child(fade_layer)

	minimap = Minimap.new()
	$HUD/SidePanel/VBox/MinimapDock.add_child(minimap)

	var ev_scene = load("res://scenes/event_dialog.tscn")
	if ev_scene:
		event_dialog = ev_scene.instantiate()
		$HUD.add_child(event_dialog)
		event_dialog.visible = false
		event_dialog.closed.connect(_on_room_dialog_closed)

	var boss_dict = UIThemeHelper.create_boss_bar($HUD)
	hud_boss_bar = boss_dict["root"]
	hud_boss_fill = boss_dict["prog"]
	hud_boss_label = boss_dict["label"]

	var modal_dict = UIThemeHelper.create_victory_defeat_modal($HUD)
	victory_modal_root = modal_dict["root"]
	victory_modal_banner = modal_dict["banner"]
	victory_modal_title = modal_dict["title"]
	victory_modal_desc = modal_dict["desc"]
	victory_modal_stats = modal_dict["stats_box"]
	victory_modal_button = modal_dict["button"]
	victory_modal_button.pressed.connect(_on_button_action)

	UIThemeHelper.apply_clay_button(btn_restart)
	btn_restart.pressed.connect(_on_button_action)

	UIThemeHelper.apply_icon_button(btn_resume, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_settings_pause, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_restart_stage, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_quit_menu, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(22, 22))

	btn_resume.pressed.connect(_toggle_pause)
	btn_settings_pause.pressed.connect(func():
		if pause_settings_dialog:
			pause_settings_dialog.open_dialog()
	)
	if pause_settings_dialog:
		pause_settings_dialog.closed.connect(func(): btn_settings_pause.grab_focus())
	btn_restart_stage.pressed.connect(func():
		_toggle_pause()
		start_game()
	)
	btn_quit_menu.pressed.connect(func():
		_toggle_pause()
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	)

	_apply_layout_offset()
	get_viewport().size_changed.connect(_apply_layout_offset)

	enemy_spawn_points = [
		Vector2(0.5 * TILE_SIZE, 0.5 * TILE_SIZE),
		Vector2(6.5 * TILE_SIZE, 0.5 * TILE_SIZE),
		Vector2(12.5 * TILE_SIZE, 0.5 * TILE_SIZE)
	]
	p1_spawn_point = Vector2(4.5 * TILE_SIZE, 12.5 * TILE_SIZE)
	p2_spawn_point = Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE)

	# 只有从标题界面输对暗号解锁过的这次进程才装这块面板 —— 正常玩家的
	# main.tscn 里压根不存在这些节点, 而不只是"存在但隐藏"。
	if GameState.debug_unlocked:
		_build_debug_panel()

	_net_attach()

	start_game()

	# 客户端: 告诉主机"我的世界已经建好了"。从收到开局种子到这一行之间实测
	# 有两秒以上 (加载全部贴图 + 建 174 块地形), 那段时间里客户端虽然已经在
	# 发输入包了, 但屏幕上什么都没有 —— 所以主机不能拿"收到过对方的包"
	# 当作"对方进来了"。放在 _ready() 而不是 start_game() 末尾: 后者在战役
	# 模式下有一条提前 return, 会漏掉。
	if NetSession.is_client():
		var ready_net := get_node_or_null("/root/Net")
		if ready_net:
			ready_net.notify_ready()


# ================================================================ 联机接线
#
# 这一段是 main.gd 对外暴露给 `Net` (scripts/net_manager.gd) 的全部接口。
# 战斗逻辑本身几乎没有改动 —— 主机跑的就是单机那一套, 客户端靠
# NetSession.is_authority() 把这些逻辑整段跳过, 只留表现层。

func _net_attach() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return
	net.attach_game(self)
	if not net.peer_left.is_connected(_on_net_peer_left):
		net.peer_left.connect(_on_net_peer_left)

	if NetSession.is_active():
		# 暂停菜单里的"重开本关"在联机下必须关掉: 它只重开按按钮的这一台,
		# 另一端会留在一个已经不存在的世界里, 而且两端的随机种子从此分家。
		if btn_restart_stage:
			btn_restart_stage.disabled = true
			btn_restart_stage.tooltip_text = "联机对局中不能单方面重开"
		# "退出到标题"要顺带断开会话, 否则 socket 会一直挂着, 下次开房会
		# 撞到"端口已被占用"。这条连接排在场景切换那条 lambda 后面,
		# 但 change_scene_to_file 是延迟到帧尾执行的, 所以先断后切。
		if btn_quit_menu:
			btn_quit_menu.pressed.connect(func():
				var n := get_node_or_null("/root/Net")
				if n:
					n.leave()
			)

	if NetSession.is_client():
		# 客户端在快照到来之前得先有一张一样的地图。种子在 begin_match 里
		# 已经拿到了, start_game() 会用它建图。
		#
		# 这台机器自己那份 GameState 的备份/还原**不在这里** —— 备份必须发生
		# 在大厅里 (进对局之前, 还没被主机的状态覆盖), 还原在
		# net_manager.leave()。见 NetSession.client_campaign_backup。
		if net.has_signal("match_ended") and not net.match_ended.is_connected(_on_net_match_ended):
			net.match_ended.connect(_on_net_match_ended)
	if NetSession.is_host():
		# 可破坏地形消失时把格子坐标广播出去。挂在容器的信号上而不是每种
		# 砖块脚本里, 是因为这个项目有十几种可破坏方块 (砖/黏土/木墙/
		# 滚墙/能量墙…), 一个个改等于十几个能漏掉的地方。
		if not map_container.child_exiting_tree.is_connected(_on_net_tile_exiting):
			map_container.child_exiting_tree.connect(_on_net_tile_exiting)


func _exit_tree() -> void:
	var net := get_node_or_null("/root/Net")
	if net:
		net.detach_game(self)


func _on_net_tile_exiting(child: Node) -> void:
	if not (child is Node2D):
		return
	var net := get_node_or_null("/root/Net")
	if net == null:
		return
	var p: Vector2 = (child as Node2D).position
	net.notify_tile_gone(_grid_col(p.x), _grid_col(p.y), String(child.name).left(6))


## 坐标 -> 格号。**必须是 floor 不是 round**: 瓦片摆在格心, 即
## (col + 0.5) * TILE_SIZE, 所以 24px 是第 0 格、72px 是第 1 格。
## round 会把 24px(0.5) 和 48px(1.0) 都算成第 1 格 —— 两个不同的位置
## 撞进同一个格号, 于是"删掉这一格"会删错东西或者什么都删不掉。
func _grid_col(v: float) -> int:
	return int(floor(v / TILE_SIZE))


## 客户端侧: 主机说某格地形没了。
##
## 按 (格号 + 类型前缀) 定位, 不按节点路径 —— 两端的节点名不保证一致
## (Godot 给重名节点自动加 @ 后缀, 而两端的生成顺序里混着 VFX 之类的
## 本地节点)。前缀是必要的第二个维度: 一格里可能同时叠着水面精灵和水体
## 碰撞盒, 只按格号删会把没被摧毁的那半也删掉。
func net_remove_tile(gx: int, gy: int, tag: String = "") -> void:
	for child in map_container.get_children():
		if not (child is Node2D):
			continue
		var p: Vector2 = (child as Node2D).position
		if _grid_col(p.x) != gx or _grid_col(p.y) != gy:
			continue
		if tag != "" and String(child.name).left(6) != tag:
			continue
		child.queue_free()
		return


## 客户端侧: 一辆玩家坦克的傀儡生成了。把它接到本来就存在的
## p1_instance / p2_instance 上, 于是摄像机跟随、树冠淡出、夜战雾这些
## 只认这两个引用的表现代码在客户端上一行都不用改。
func net_register_player_puppet(node: Node) -> void:
	if node.player_id == 1:
		p1_instance = node
	else:
		p2_instance = node
	if darkness_fog_instance and is_instance_valid(darkness_fog_instance):
		darkness_fog_instance.setup_trackers(p1_instance, p2_instance, base_instance)


## 主机侧: 打包那些"不是实体、但客户端 HUD 要用"的状态。
## 频率只有 6Hz (见 net_manager.STATE_HZ) —— 分数和命数不需要更快。
func net_collect_state() -> Dictionary:
	var p1_hp := 0
	var p1_max := 0
	var p2_hp := 0
	var p2_max := 0
	if p1_instance and is_instance_valid(p1_instance):
		p1_hp = p1_instance.current_health
		p1_max = p1_instance.max_health
	if p2_instance and is_instance_valid(p2_instance):
		p2_hp = p2_instance.current_health
		p2_max = p2_instance.max_health
	return {
		"score": score,
		"p1_lives": p1_lives,
		"p2_lives": p2_lives,
		"left": maxi(0, total_enemies - enemies_spawned) + enemies_alive,
		"p1_hp": p1_hp, "p1_max": p1_max,
		"p2_hp": p2_hp, "p2_max": p2_max,
		"over": is_game_over,
		"victory": is_victory,
		"map": NetSession.map_checksum,
		# 校验和必须连着"这是哪间房"一起发。换房的那半秒里主机已经建好了新
		# 房间, 客户端还在淡出/等 RPC —— 两边此刻本来就该不一样, 拿它去比
		# 会报出一条吓人的"地形不一致", 而实际上什么问题都没有。
		"room": GameState.current_room,
		# 建造库存是**共享的一池**(本地双人也是, consume_structure_stock 不分
		# 玩家), 所以必须以主机为准下发, 否则客户端的热键栏显示的是它自己
		# 存档里的数字, 点下去主机却说库存不足。
		"stock": GameState.structure_inventory,
	}


## 客户端侧: 把主机推下来的状态写进本地 HUD。
func net_apply_state(state: Dictionary) -> void:
	score = int(state.get("score", score))
	p1_lives = int(state.get("p1_lives", p1_lives))
	p2_lives = int(state.get("p2_lives", p2_lives))
	_net_enemies_left = int(state.get("left", 0))
	if int(state.get("p1_max", 0)) > 0:
		_on_player_hp_changed(1, int(state["p1_hp"]), int(state["p1_max"]))
	if int(state.get("p2_max", 0)) > 0:
		_on_player_hp_changed(2, int(state["p2_hp"]), int(state["p2_max"]))
	if state.has("stock"):
		GameState.structure_inventory = state["stock"]
		if hud_hotbar:
			UIThemeHelper.update_hotbar_stock(hud_hotbar)
	var host_map := int(state.get("map", 0))
	# 只在"两边都认为自己在同一间房"时才比校验和 —— 换房途中的不一致是正常的,
	# 见 net_collect_state 里 "room" 字段的注释。
	var same_room := str(state.get("room", "")) == GameState.current_room
	if same_room and not _net_map_warned and host_map != 0 and NetSession.map_checksum != 0 and host_map != NetSession.map_checksum:
		_net_map_warned = true
		push_error("[NET] 地形校验和不一致: 主机 %d / 本机 %d —— 两端的地图不是同一张, 子弹和墙的判定会对不上" % [host_map, NetSession.map_checksum])
		show_toast("⚠️ 地图与主机不一致，请检查双方版本")
	_update_hud()


## 主机: 把整局战役状态推给客户端。
##
## 调用点是"主机侧改了 GameState 而客户端看得见后果"的那几处: 清房 (开门、
## 发奖)、商店成交、换货、事件结算、宝物房。频率很低 (一间房几次), 所以
## 整份推而不是做增量 —— 增量同步意味着每加一种改动都要记得加一条消息,
## 那正是这个项目在存档那条链上吃过亏的地方 (见 campaign_to_dict 的注释)。
func _net_push_campaign() -> void:
	if not NetSession.is_host():
		return
	var net := get_node_or_null("/root/Net")
	if net:
		net.broadcast_campaign(GameState.campaign_to_dict())


## 客户端: 收下主机推来的战役状态, 并把由它派生的表现刷新一遍。
##
## 门的开合、商店货位的售罄、小地图、HUD 全都是**从 GameState 推出来的**,
## 所以这里不需要为每一种变化单独发一条消息 —— 状态到了, 重算一遍即可。
func net_apply_campaign(d: Dictionary) -> void:
	GameState.campaign_from_dict(d)
	rpg_mgr.sync_from_game_state()

	var room := GameState.current_room_data()
	if bool(room.get("cleared", false)):
		_open_doors()
	if str(room.get("type", "")) == "shop":
		_rebuild_shop_stands()

	_refresh_minimap()
	_update_hud()
	_update_rpg_hud()


## 主机侧: 客户端要买第 slot 号货位。
##
## 走的就是主机自己那条 try_purchase() —— 库存/金币/上限判断、扣账、发放、
## 音效、写回房间字典全部复用, 没有一条"联机专用"的成交逻辑可以走偏。
## 拒绝 (钱不够/已达上限/已卖出) 也在那里面, 所以客户端不需要预判。
## 主机替客户端成交过多少次。诊断用 —— 出问题时第一个要分清的是"这笔账是
## 谁下的单", 本地成交和远端请求在结果上长得一模一样。
var _net_remote_buys_applied: int = 0


func net_apply_buy(slot: int) -> void:
	if not NetSession.is_host():
		return
	_net_remote_buys_applied += 1
	for c in map_container.get_children():
		if c is ShopStand and int(c.slot_index) == slot:
			c.try_purchase()
			return


## 主机侧: 客户端要换货。
func net_apply_reroll() -> void:
	if not NetSession.is_host():
		return
	for c in map_container.get_children():
		if c is ShopRerolder:
			c.try_reroll()
			return


## 只重建货位, 不动房间 —— 和 _do_shop_reroll() 里那段是同一个理由 (玩家
## 正站在货位旁边, 重建整个房间会把他挪回门口)。
func _rebuild_shop_stands() -> void:
	for c in map_container.get_children():
		if c is ShopStand or c is ShopRerolder:
			c.queue_free()
	_build_shop_room()


## 客户端收到过多少次换房指令。诊断用: 联机战役里"客户端没跟上房间"有两种
## 完全不同的原因 —— 指令没到 (网络/权限), 还是到了但没走完 (被暂停/重入
## 卡住)。这个计数把两者分开。
var _net_rooms_entered: int = 0


## 客户端: 主机说换房了。
func net_enter_room(d: Dictionary, room_seed: int, room_key: String, travel_dir: int) -> void:
	_net_rooms_entered += 1
	GameState.campaign_from_dict(d)
	rpg_mgr.sync_from_game_state()
	_transition_to_room(room_key, travel_dir, room_seed)


## 客户端 HUD 上"剩余敌人"的数字来自主机, 不是本地算的 (客户端根本不刷怪)。
var _net_enemies_left: int = 0
## 地图校验和只报一次警, 不然 6Hz 的状态包会把控制台刷爆。
var _net_map_warned: bool = false


## 建完图之后算一次地形校验和。
##
## 两端是各自按同一个种子跑 _build_map() 得到地图的, 不是把瓦片复制过去的。
## 这个做法对**除了种子以外的任何输入**都很敏感: 难度、幕数、房间类型只要
## 有一项两端不同, 生成的图就会不一样。而它的症状极其阴险 —— 画面上双方
## 各看各的墙, 子弹在对方那边"穿墙", 却没有任何报错。所以这里必须留一个
## 会自己喊出来的检查, 而不是指望改代码的人记得两端要一致。
func _net_verify_map() -> void:
	NetSession.map_checksum = NetSession.terrain_checksum(map_container, TILE_SIZE)
	_net_map_warned = false


func _on_net_match_ended(victory: bool, final_score: int) -> void:
	score = final_score
	_game_over(victory)


## 对局中掉线。两端的处理必须不同, 而且都不能"什么都不做":
##
## - **客户端**: 主机没了就没有任何权威了 —— 本地既不刷怪也不判定, 留在场上
##   只会看到一个冻住的世界。更要命的是 net_manager 断线时会 leave(),
##   NetSession.role 归零, 于是 is_authority() 突然变成 true, 这台机器会
##   开始用一个没有玩家坦克的场景跑刷怪逻辑。_net_disconnected 就是为了
##   在那之前先把 _process 掐掉。
## - **主机**: 继续单机跑就行。remote_input 已经在 net_manager 里清空,
##   于是 2 号坦克读到的输入恒为 0, 会停在原地而不是保持最后一次按键
##   一直往前冲 —— 后者才是"队友掉线后坦克自己撞死"的那种 bug。
func _on_net_peer_left(_id: int) -> void:
	if NetSession.is_host():
		show_toast("⚠️ 队友掉线，2P 坦克已停止行动")
		return
	_net_disconnected = true
	show_toast("⚠️ 与主机断开连接，正在返回标题…")
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


var _net_disconnected: bool = false


## 复活提示的按键边沿。联机时 2 号玩家的开火键在客户端手里, 走
## NetSession 而不是本地 Input —— 否则客户端永远复活不了自己。
var _net_fire_prev: Dictionary = {1: false, 2: false}
var _net_fire_edge: Dictionary = {1: false, 2: false}


func _net_update_fire_edges() -> void:
	for pid in [1, 2]:
		var now := NetSession.has_bit(NetSession.input_for(pid), NetSession.IN_FIRE)
		_net_fire_edge[pid] = now and not bool(_net_fire_prev[pid])
		_net_fire_prev[pid] = now


func _unhandled_input(event: InputEvent) -> void:
	if minimap and is_instance_valid(minimap) and minimap.is_maximized():
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_M]):
			minimap.toggle_maximized(false)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if minimap and is_instance_valid(minimap):
			minimap.toggle_maximized()
			get_viewport().set_input_as_handled()
			return

	# F1 呼出/收起隐藏调试面板。跟 KEY_M 一样是纯键盘的开发者快捷键 (没有
	# 手柄等价物), 且整条分支挂在 GameState.debug_unlocked 门槛后面 ——
	# 没在标题界面输过暗号的玩家这里直接短路, 面板节点也根本没被建出来。
	if GameState.debug_unlocked and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		if debug_panel:
			debug_panel.visible = not debug_panel.visible
			get_viewport().set_input_as_handled()
			return

	# "pause" = ESC / P / 两个手柄的 START。以前这里是 ui_cancel + 硬编码 KEY_P,
	# 而 ui_cancel 在手柄上的默认绑定是 B —— B 同时又是菜单里的"返回", 于是手柄
	# 玩家一按 B 就会在关闭对话框的同时弹出暂停菜单。改用独立 action 后 B 只管
	# 菜单返回, 暂停归 START。键盘行为不变: ESC 和 P 都在这个 action 里。
	# 注意 START 也绑着 restart, 但那个只在 is_game_over/is_victory 时读取,
	# 而这里恰好把那两种状态排除了, 所以同一颗键不会有歧义。
	if event.is_action_pressed("pause"):
		# 设置弹窗开着的时候 ESC 同时是 ui_cancel (它自己的关闭键) 和 pause
		# (这里的暂停/恢复键) —— 跟 builder_controller.gd 里 build_cancel
		# 刻意不绑 ESC/B 是同一个坑。这里不把两个处理器谁先跑的顺序当保证,
		# 而是让本处理器在弹窗开着时直接不动 pause 状态, 把 ESC 完全让给
		# settings_dialog.gd 自己的 ui_cancel 分支去关弹窗。
		if pause_settings_dialog and pause_settings_dialog.visible:
			return
		if not is_game_over and not is_victory:
			_toggle_pause()

func _toggle_pause() -> void:
	var paused = not get_tree().paused
	get_tree().paused = paused
	pause_menu.visible = paused
	if paused:
		UIThemeHelper.focus_first(pause_menu)

## 遭遇规模 —— 一场要打多少辆车, 按战斗类型 + 难度圈。
##
## 这里承担了难度圈 (act 4-8 重走前三幕主题) 原本挂在敌人身上的那部分强度。
## 以前是 enemy.gd 里 max_health x (1 + cycle * 0.18) 加 speed x (1 + cycle * 0.07),
## 两个都是看不见的乘数, 速度那个还小到根本感觉不出来 (75 -> 81 px/s)。
##
## 换成遭遇规模的理由很简单: 它是一个**整数**, 而且"这一场来了 20 辆而不是
## 12 辆"是玩家一眼就能看出来的 —— 和装甲板同一条原则 (敌人的强弱只能是整数,
## 而且必须看得见, 见 enemy.gd 的 ARMOR_PLATE_HP 那段)。血量那部分则由
## roll_armor_plates() 抬装甲下界来承担: 第二三圈的素车越来越少。
##
## static 是为了可测: tools/test_enemy_balance_curve.gd 直接调它算每圈的
## 遭遇总血量, 不用把 main.tscn 起三遍, 也不用在测试里手抄一份规模表
## (手抄的表必然和这里发散)。
const ENCOUNTER_BASE := {
	"elite": 18,
	"boss": 24,
	"challenge": 14,
	"battle": 12,
}
## 硬核化调整: 4 -> 5。每圈遭遇规模的绝对值抬高一档, 战斗打得更久;
## 下面 MAX_ALIVE_BASE 才是"每一刻更挤"的那个杠杆, 两者一起调才不会变成
## "只是更长不是更难"。
const ENCOUNTER_PER_LAP := 5

const SPAWN_INTERVAL_BASE := {
	"elite": 2.0,
	"boss": 1.6,
	"challenge": 2.4,
	"battle": 2.5,
}
## 每圈出车间隔收紧多少; 下限 1.2 秒 —— 再快的话三个出生点会堵住,
## 车挤在门口反而比正常涌出来好打。硬核化调整只动收紧速度 (0.25 -> 0.35,
## 更早触到这个下限), 不动 1.2 这个下限本身 —— 那条是地图几何决定的真实
## 上限, 不是随便能往上顶的数字。
const SPAWN_INTERVAL_PER_LAP := 0.35
const SPAWN_INTERVAL_FLOOR := 1.2

## 场上同时存在的敌人上限。
##
## 这一条是难度圈真正加压的地方。光加遭遇规模不够 —— 上限锁死在 4 的话,
## "一场 20 辆"和"一场 12 辆"的区别只是**打得久**, 每一刻的压力一模一样,
## 而更长不等于更难。上限抬到 6, 场上多两辆车才是实打实的压迫感, 而且它同样
## 是个整数、同样一眼看得见 (屏幕上就是多两辆)。
##
## 封顶 6: 13x13 的地图加三个出生点, 再多就变成敌人互相堵路, 反而更好打。
## 这个上限不动——硬核化调整改的是 BASE (4 -> 5): 圈 0 起步就是 5 辆同屏,
## 圈 1 就摸到封顶, 比原来"圈 2 才摸到封顶"提前压满, 整条难度圈曲线往前
## 挪了一步, 而不是把封顶本身顶破。
const MAX_ALIVE_BASE := 5
const MAX_ALIVE_CAP := 6

## GameState.difficulty (玩家在标题screen选的 easy/normal/hard) 加压的三个杠杆,
## 和上面的"难度圈" (get_difficulty_cycle, 同一幕主题第几次重打) 是两个独立的轴,
## 乘/加在一起而不是互相替代 —— 圈数管"这局打到多后期", 这里管"这局本身多硬"。
## 沿用"敌人强弱必须整数且看得见"那条铁律 (见 enemy.gd 装甲板注释): 三档只动
## 数量/间隔这些一眼可数的整数, 不碰任何敌人的隐藏血量或速度乘数。
const DIFFICULTY_ENCOUNTER_MULT := {"easy": 0.75, "normal": 1.0, "hard": 1.3}
const DIFFICULTY_ALIVE_OFFSET := {"easy": -1, "normal": 0, "hard": 1}
const DIFFICULTY_SPAWN_INTERVAL_MULT := {"easy": 1.25, "normal": 1.0, "hard": 0.8}

## 大/超大房间的"攻城战"加成, 叠加在上面 ENCOUNTER_BASE/MAX_ALIVE_BASE 算出
## 的普通遭遇规模之上, 只在这一间房生效, 不改任何全局曲线。两张表分别对应
## CLAUDE.md"敌人强弱要整数且看得见"那条铁律的两个可见维度: 更多敌人总量、
## 更高的同屏上限 (大房间物理空间更大, 不会像 13x13 那样互相堵路)。出生点
## 数量不在这里另开一张表——直接读 CompositeRoomBuilder.enemy_spawn_count_for(),
## 跟拼图纸时留几个出生点缺口用的是同一个数字, 两边分别维护迟早会有一边漏改。
const SIEGE_ENCOUNTER_MULT := {"large": 2, "huge": 4}
const SIEGE_ALIVE_BONUS := {"large": 4, "huge": 10}

## 护送风味的友军数量, 跟 CompositeRoomBuilder.enemy_spawn_count_for() 的
## 表是两回事 (那张管地形留几个出生点, 这张管刷几只 AllyTank), 但都用同一套
## "normal/large/huge" 键。
const ESCORT_ALLY_COUNT := {"normal": 1, "large": 3, "huge": 4}

var max_alive_cap: int = MAX_ALIVE_BASE

static func max_alive_for(cycle: int, difficulty: String = "normal") -> int:
	var offset: int = int(DIFFICULTY_ALIVE_OFFSET.get(difficulty, 0))
	# 下限 3: 就算 easy 撞上圈 0, 场上也不能比"三个出生点各出一辆"还挤不满,
	# 不然新手局面反而空得不自然。上限沿用原来的 MAX_ALIVE_CAP, 不因难度突破。
	return clampi(MAX_ALIVE_BASE + maxi(0, cycle) + offset, 3, MAX_ALIVE_CAP)


static func encounter_size(battle_type: String, cycle: int, difficulty: String = "normal") -> int:
	var base: int = int(ENCOUNTER_BASE.get(battle_type, ENCOUNTER_BASE["battle"]))
	var raw: int = base + maxi(0, cycle) * ENCOUNTER_PER_LAP
	var mult: float = float(DIFFICULTY_ENCOUNTER_MULT.get(difficulty, 1.0))
	return maxi(1, int(round(raw * mult)))


static func spawn_interval_for(battle_type: String, cycle: int, difficulty: String = "normal") -> float:
	var base: float = float(SPAWN_INTERVAL_BASE.get(battle_type, SPAWN_INTERVAL_BASE["battle"]))
	var raw: float = maxf(SPAWN_INTERVAL_FLOOR, base - float(maxi(0, cycle)) * SPAWN_INTERVAL_PER_LAP)
	var mult: float = float(DIFFICULTY_SPAWN_INTERVAL_MULT.get(difficulty, 1.0))
	return maxf(SPAWN_INTERVAL_FLOOR, raw * mult)


func start_game() -> void:
	score = 0
	enemies_spawned = 0
	enemies_alive = 0
	is_game_over = false
	is_victory = false
	battle_gold_earned = 0
	battle_start_msec = Time.get_ticks_msec()
	# 每场重置 —— 只有战役模式的难度圈会抬它, 街机/每日挑战用基准值。
	# 不重置的话重开一局会继承上一局的上限。
	max_alive_cap = MAX_ALIVE_BASE
	shovel_timer = 0.0
	is_shovel_active = false
	if not GameState.has_iff_flag:
		iff_flag_active = false
		iff_flag_timer = 0.0
	else:
		iff_flag_active = true
		iff_flag_timer = 999999.0
	hud_status.visible = false
	btn_restart.visible = false
	if victory_modal_root:
		victory_modal_root.visible = false

	is_night_mode_active = false
	is_bomb_rain_active = false
	bomb_rain_timer = 0.0

	p1_awaiting_revive = false
	p2_awaiting_revive = false

	# 联机对局: 两端用主机掷的同一个种子播种全局 RNG, 然后各自跑同一份
	# _build_map()。地形因此逐块一致, 不需要把几百个瓦片复制过去 —— 这跟
	# 每日挑战让所有人拿到同一张图用的是同一条机制 (见下面 DAILY_CHALLENGE)。
	# 建完之后两端各算一次校验和, 对不上就吼出来 (见 _net_verify_map)。
	if NetSession.is_active():
		seed(NetSession.match_seed)

	if GameState.mode == GameState.GameMode.CAMPAIGN:
		# 双人战役下 player_lives 是唯一的共享池, p1_lives/p2_lives 两个本局
		# 镜像变量全程保持相等 (_lives_shared() 的所有改动点都维持这个不变式)。
		# 单人战役下 p2_lives 没人用, 赋成同一个值也无所谓。
		p1_lives = GameState.player_lives
		p2_lives = GameState.player_lives
		rpg_mgr.sync_from_game_state()
		max_alive_cap = max_alive_for(GameState.get_difficulty_cycle(), GameState.difficulty)

		# 存档里没有楼层 (新开局, 或者尖塔时代的老存档) 就现生成一层;
		# 有楼层但当前房间指向不存在的房间就挪回起始房。
		GameState.ensure_floor_ready()

		# 战役模式从这里往下全部交给房间系统: 建图、放基地、放玩家、刷怪、
		# 开门全在 enter_room() 里, 和之后每一次过门走的是同一条路径。
		# 首次进场传 -1 表示"不是从某扇门进来的"。
		if hud_p2_hp_box: hud_p2_hp_box.visible = GameState.player_count == 2
		enter_room(GameState.current_room, -1)
		_setup_challenge_treasure()
		_update_hud()
		_update_rpg_hud()
		return
	elif GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
		# Seed the global RNG stream from today's date so every randf()/randi()
		# call from here on (map layout, enemy rolls, spawn positions) plays
		# out identically for everyone who runs the challenge today -- a
		# fair, comparable "one shot" score attempt, not just "randomize now".
		seed(GameState.get_daily_seed())
		p1_lives = 1
		p2_lives = 0
		total_enemies = 99 # effectively endless -- the run ends when you die, not when enemies run out
		spawn_interval = 2.2
		rpg_mgr.reset()
		var today_best = GameState.get_daily_best_score()
		if today_best > 0:
			show_toast("☠️ 每日挑战：只有一条命！今日最高分 %06d" % today_best)
		else:
			show_toast("☠️ 每日挑战：只有一条命，随机地图与随机敌人，尽力而为！")
	else:
		p1_lives = 3
		p2_lives = 3
		total_enemies = 20
		rpg_mgr.reset()
		show_toast("2-PLAYER CO-OP ARCADE READY!")

	var net := get_node_or_null("/root/Net")
	if net and NetSession.is_active():
		net.begin_bulk_change()
	_clear_all()
	_build_map()
	if net and NetSession.is_active():
		net.end_bulk_change()
		_net_verify_map()
	_spawn_base_and_walls(false)
	# 客户端一辆坦克都不生成 —— 两辆玩家坦克都会以傀儡的形式从主机的
	# spawn 包里过来 (见 net_register_player_puppet)。这里如果也建一辆,
	# 场上就会有两辆 1 号坦克: 一辆本地的、一辆傀儡的。
	if NetSession.is_authority():
		_spawn_player(1)
		if GameState.player_count == 2:
			_spawn_player(2)
	if hud_p2_hp_box: hud_p2_hp_box.visible = GameState.player_count == 2

	if is_night_mode_active:
		activate_darkness_fog()

	_setup_challenge_treasure()
	_update_hud()
	_update_rpg_hud()

func add_gold(amount: int) -> void:
	rpg_mgr.add_gold(amount)
	battle_gold_earned += amount
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()
	show_toast("+%d GOLD!" % amount)

func _on_rpg_level_up(new_lvl: int) -> void:
	SoundManager.play_level_up(get_tree())
	add_trauma(0.30)
	show_toast("★ LEVEL UP! LV.%d REACHED! ★" % new_lvl)
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()
	if p1_instance and is_instance_valid(p1_instance):
		p1_instance._apply_rpg_stats()
	if p2_instance and is_instance_valid(p2_instance):
		p2_instance._apply_rpg_stats()

	if upgrade_dialog and is_instance_valid(upgrade_dialog):
		var was_empty = pending_upgrade_players.is_empty()
		# A ternary between two untyped array literals ([1,2] / [1]) doesn't
		# coerce to Array[int] at runtime -- Godot throws "Trying to assign
		# an array of type Array to a variable of type Array[int]" the
		# instant this line executes. Assigning each literal directly to the
		# already-typed variable (instead of picking between them via `if
		# ... else` first) does convert correctly.
		var new_players: Array[int] = [1]
		if GameState.player_count == 2:
			new_players = [1, 2]
		pending_upgrade_players.append_array(new_players)
		if was_empty:
			_show_next_upgrade()


## 弹出队列里下一个玩家的升级选择。
##
## 联机时**每个人在自己的屏幕上选自己的卡**: 轮到远端那位时, 主机生成卡面
## (rpg_mgr 只在主机这边) 并发过去, 然后暂停等他回报索引。让主机替对方选
## 是不能接受的 —— 战役里两名玩家各有各的流派和天赋池 (p2_branch /
## p2_unlocked_perks), 那是对方这一局的核心决策。
func _show_next_upgrade() -> void:
	if pending_upgrade_players.is_empty():
		get_tree().paused = false
		return
	if not (upgrade_dialog and is_instance_valid(upgrade_dialog)):
		get_tree().paused = false
		return

	var pid: int = pending_upgrade_players[0]
	if NetSession.is_host() and pid != NetSession.local_player_id:
		var choices: Array[Dictionary] = upgrade_dialog._generate_choices(rpg_mgr, pid)
		_net_pending_choices = choices
		var net := get_node_or_null("/root/Net")
		if net:
			net.send_upgrade_options(choices, pid)
		show_toast("⏳ 等待队友选择强化…")
		# 主机也要停下来等: 不停的话对方在选卡的几秒里战场照常推进, 他一回来
		# 发现自己已经被打死了。本地双人弹这个框时同样是全局暂停。
		get_tree().paused = true
		return

	upgrade_dialog.show_upgrade_options(rpg_mgr, pid)


## 主机侧: 客户端报回了他选的第几张卡。
##
## 应用走的是本地那条一模一样的 _on_card_picked —— 没有"联机专用"的强化
## 应用逻辑, 所以不会和单机的行为分家。current_player_id 要先摆对, 那个
## 函数拿它决定加到谁头上。
func net_apply_remote_upgrade(index: int, pid: int) -> void:
	if not NetSession.is_host():
		return
	if index < 0 or index >= _net_pending_choices.size():
		return
	if not (upgrade_dialog and is_instance_valid(upgrade_dialog)):
		return
	upgrade_dialog.current_player_id = pid
	upgrade_dialog._on_card_picked(_net_pending_choices[index], rpg_mgr)
	_net_pending_choices = []


## 主机侧: 当前是否还有一个未结算的事件框。
##
## 事件是共享决策, 两个人都能点。这个标志就是去重: 谁先点算谁的, 后到的
## 那一次直接丢掉 —— 否则两个人同时点会把奖励结算两遍 (金币加两次、
## 天赋给两层), 而且不会有任何报错。
var _net_event_open: bool = false

## 主机替客户端结算过多少次事件。诊断/测试用 —— "结算了几次"是这条链路上
## 唯一真正危险的量 (共享奖励结算两遍不会报错), 用计数器断言比用统计量的
## 增减去反推可靠得多。
var _net_remote_events_resolved: int = 0


## 主机侧: 客户端点了事件选项。
func net_apply_event_choice(idx: int) -> void:
	if not NetSession.is_host() or not _net_event_open:
		return
	_net_remote_events_resolved += 1
	if event_dialog and is_instance_valid(event_dialog):
		# 走的就是主机本地点按钮那条 _on_choice —— 结算规则只有这一份。
		# 它内部会 visible = false 并 emit closed, 而 closed 接的是
		# _on_room_dialog_closed, 那里会把战役状态推给客户端。
		event_dialog._on_choice(idx)


## 客户端侧: 主机推来一个事件框。
func net_show_event(dialog_type: String, event_id: String) -> void:
	if event_dialog and is_instance_valid(event_dialog):
		event_dialog.setup(dialog_type, event_id)
		event_dialog.visible = true


## 客户端侧: 事件已经被结算了 (可能是队友点的), 把框收掉。
func net_close_event() -> void:
	if event_dialog and is_instance_valid(event_dialog):
		event_dialog.visible = false


## 客户端侧: 主机把该我选的卡面发过来了。
func net_show_upgrade_options(options: Array, pid: int) -> void:
	if upgrade_dialog and is_instance_valid(upgrade_dialog):
		upgrade_dialog.show_remote_options(options, pid)


## 主机发给远端玩家、正在等回报的那组卡面。
var _net_pending_choices: Array[Dictionary] = []

func _on_upgrade_option_selected(opt: Dictionary, player_id: int) -> void:
	var p_tag = "P1" if player_id == 1 else "P2"
	show_toast("★ [%s] 激活战备: %s ★" % [p_tag, opt.get("name", "").replace("\n", " ")])
	if player_id == 1 and p1_instance and is_instance_valid(p1_instance):
		p1_instance._apply_rpg_stats()
		p1_instance._update_tier_appearance()
	elif player_id == 2 and p2_instance and is_instance_valid(p2_instance):
		p2_instance._apply_rpg_stats()
		p2_instance._update_tier_appearance()
	_update_rpg_hud()

	if not pending_upgrade_players.is_empty():
		pending_upgrade_players.remove_at(0)

	# 强化改的是 GameState/rpg_mgr, 客户端的 HUD 和下一次同步都要跟上。
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()
	_net_push_campaign()

	_show_next_upgrade()

## keep_players: 换房间时为 true —— 玩家坦克必须**跨房间存活**, 否则每过一
## 道门血量、无敌帧、火车车厢全部重置, 房间之间就没有连续性可言了。
##
## 车厢也要一起留: train_carriage 是 player 的**兄弟节点** (player.gd 的
## _sync_train_carriages() 用 get_parent().add_child()), 不是子节点, 所以
## 只跳过 p1/p2 实例的话尾巴会被删光, 火车分支每过一道门就断成光杆车头。
## 这里按组判断而不是遍历 attached_carriages: 组名是车厢自己在 _ready() 里
## 挂的, 不依赖玩家那份数组的即时正确性。
func _clear_all(keep_players: bool = false) -> void:
	water_sprites.clear()
	tree_sprites.clear()
	water_bodies.clear()
	factory_instances.clear()
	doors.clear()
	active_boss_instance = null
	# _process() 的淡出动画只在 "active_boss_instance 从有效变无效" 那一帧触发;
	# 这里是强制清空 (换房/重开关卡), 不是自然死亡, 上面这行已经把触发条件
	# 关掉了, 所以血条永远等不到那个分支, 会带着上一场的读数一直挂在屏幕上,
	# 持续侵占新房间/新一局的画面。直接同步隐藏掉。
	if hud_boss_fade_tween and hud_boss_fade_tween.is_valid():
		hud_boss_fade_tween.kill()
		hud_boss_fade_tween = null
	if hud_boss_bar and hud_boss_bar.visible:
		hud_boss_bar.visible = false
		hud_boss_bar.modulate.a = 1.0
	if darkness_fog_instance and is_instance_valid(darkness_fog_instance):
		darkness_fog_instance.queue_free()
		darkness_fog_instance = null
	for child in map_container.get_children():
		child.queue_free()
	for child in base_wall_container.get_children():
		child.queue_free()
	# base_instance 指向刚被 queue_free 的那只鹰。queue_free 是**延迟**的, 所以
	# 在本帧剩下的时间里 is_instance_valid(base_instance) 仍然为 true ——
	# 而 enter_room() 正是在同一帧里接着建下一个房间。不置空的话, 走进一间已经
	# 清空的房间时 base_instance 还挂着上一间那只待删的鹰: 铲子会对着它生效,
	# 夜战雾会把它当作追踪目标, 而它下一帧就没了。
	base_instance = null
	# 同一个理由: escort_ally_instances 里的友军可能刚被 queue_free (自然阵亡
	# 或者换房清场), 而 queue_free 是延迟生效的——不清空的话下一间房还没决定
	# 要不要刷新友军之前, is_instance_valid() 就会先读到上一间房那些待删对象。
	escort_ally_instances.clear()
	# 同一个理由: circuit_gated_buildings 里存的建筑实例也即将被上面/下面
	# 这几段 queue_free() 清掉, circuit_solved 则是"这间房解开了哪些颜色"的
	# 记录, 换房之后完全作废——两者都要清空, 不然新房间的开关状态会被上一间
	# 房残留的记录污染 (例如误判"红色电路已经解开过了")。
	circuit_solved.clear()
	circuit_gated_buildings.clear()
	for child in actors_container.get_children():
		if keep_players and (child == p1_instance or child == p2_instance or child.is_in_group("player_carriage")):
			continue
		child.queue_free()

# ================================================================ 房间生命周期

## 当前房间有门的方向。非战役模式 (街机/每日挑战) 没有楼层概念, 返回空数组,
## 于是边墙四面封死 —— 那两个模式的行为和以撒化之前完全一致。
func _current_door_dirs() -> Array:
	if GameState.mode != GameState.GameMode.CAMPAIGN:
		return []
	var room := GameState.current_room_data()
	if room.is_empty():
		return []
	var out: Array = []
	for d in range(4):
		if bool(room["doors"][d]):
			out.append(d)
	return out


func _spawn_doors() -> void:
	var room := GameState.current_room_data()
	if room.is_empty():
		return
	for d in range(4):
		if not bool(room["doors"][d]):
			continue
		var st: int = RoomDoor.State.LOCKED
		if bool(room["secret_doors"][d]) and not GameState.secret_room_found:
			st = RoomDoor.State.SECRET
		elif bool(room["cleared"]):
			st = RoomDoor.State.OPEN

		var door := RoomDoor.new()
		# setup() 必须在 add_child() 之前 —— _ready() 是在 add_child() 里跑的,
		# 它要读 direction/state/target_type 才能摆好碰撞盒和贴图。
		var neighbor_key := GameState.neighbor_key(GameState.current_room, d)
		var neighbor_room := GameState.get_room(neighbor_key)
		var target_type := str(neighbor_room.get("type", "normal"))
		if bool(room["secret_doors"][d]):
			target_type = "secret"
		door.setup(d, st, target_type)
		door.position = RoomDoor.local_position_for(d, GRID_W, GRID_H)
		door.player_entered.connect(_on_door_entered)
		door.secret_breached.connect(_on_secret_breached)
		map_container.add_child(door)
		doors[d] = door


func _open_doors() -> void:
	for d in doors.keys():
		var door = doors[d]
		if not is_instance_valid(door):
			continue
		# 秘密门不跟着开: 它得先被炸开。清空房间不该顺手把暗门也送给玩家。
		if door.state == RoomDoor.State.SECRET:
			continue
		door.open()


func _on_secret_breached(d: int) -> void:
	GameState.mark_secret_found()
	var door = doors.get(d)
	if is_instance_valid(door):
		# 炸开只是把墙拆了, 门闩规则照旧: 房间没清空还是不让走。
		if bool(GameState.current_room_data().get("cleared", false)):
			door.open()
		else:
			door.lock()
	SoundManager.play_explosion(get_tree())
	add_trauma(0.35)
	show_toast("💥 暗门被炸开了 —— 发现隐藏房间！")


func _on_door_entered(d: int) -> void:
	# 换房只能由主机决定。客户端本地预测的那辆坦克碰撞是开着的 (见
	# NetPuppet._strip_interaction 里 layer/mask 不对称的理由), 所以它**会**
	# 真的踩到本地那扇门的 Area2D —— 不拦的话客户端会自己切到隔壁房间,
	# 而主机还在原地, 两台机器从此各玩各的。
	if not NetSession.is_authority():
		return
	if is_transitioning or is_game_over or is_victory:
		return
	if not GameState.can_exit(GameState.current_room, d):
		return
	var nk := GameState.neighbor_key(GameState.current_room, d)
	if nk == "":
		return
	_transition_to_room(nk, d)


## 切房。淡出 -> 原地重建 -> 淡入。
##
## 用黑幕淡入淡出而不是以撒那种双房间滑屏: 滑屏要求新旧两个房间在同一时刻都
## 存在于场景里, 而这里所有地块和敌人都共用 MapContainer/ActorsContainer 这
## 一套容器和一套物理空间 —— 两个房间同时在场会让敌人 AI、爆炸判定、寻路全部
## 跨房串味。真要做滑屏得先把房间拆成独立子场景, 那是另一次重构。
const ROOM_FADE_SEC := 0.16

## room_seed: 联机时由主机掷出并下发, 两端用它播种再建图, 于是新房间的地形
## 逐块一致 (和开局那次用 match_seed 是同一条机制)。0 表示单机, 不动 RNG。
func _transition_to_room(room_key: String, travel_dir: int, room_seed: int = 0) -> void:
	if NetSession.is_host():
		room_seed = randi()
		var net := get_node_or_null("/root/Net")
		if net:
			# **在 enter_room 之前发。** 这份字典是 visit_room() 改动之前的
			# 状态; 客户端拿到之后跑自己那份 enter_room, 里面同样会调
			# visit_room, 两边做的是同一次改动。发在之后的话客户端会先被写入
			# 改动结果、再自己改一遍。
			net.broadcast_enter_room(GameState.campaign_to_dict(), room_seed, room_key, travel_dir)

	is_transitioning = true
	if fade_layer:
		var tw := create_tween()
		# **淡入淡出不能被暂停卡住。**
		#
		# 换房是 await 在这个 tween 上的 —— 树一暂停, tween 默认跟着停,
		# enter_room() 就永远不会被调用, 玩家卡在一块全黑的幕布后面。
		# 单机时这不可能发生 (暂停菜单是玩家自己开的, 而他此刻正在换房),
		# 但联机时**换房的指令来自对端**: 主机过门的那一刻, 客户端完全可能
		# 正停在升级选卡界面里 (那个框会 get_tree().paused = true)。
		# 于是客户端收到换房 RPC、开始淡出、然后永远停在那里。
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(fade_layer, "modulate:a", 1.0, ROOM_FADE_SEC)
		await tw.finished

	enter_room(room_key, FloorMap.opposite(travel_dir), room_seed)

	if fade_layer:
		var tw2 := create_tween()
		tw2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw2.tween_property(fade_layer, "modulate:a", 0.0, ROOM_FADE_SEC)
		await tw2.finished
	is_transitioning = false


## 进入一个房间并把它整个建起来。start_game() 的首次进场和之后每一次过门都
## 走这里, 所以"房间该长什么样"只有这一份实现。
##
## entry_dir 是**本房间**那扇门的朝向 (玩家从哪边进来), -1 表示首次进场
## (站在房间中央偏下)。
func enter_room(room_key: String, entry_dir: int, room_seed: int = 0) -> void:
	# 播种要**紧挨着建图**, 不能提前到淡出动画之前: 淡出的那 0.16 秒里主机的
	# _process 还在跑, 而屏幕抖动用的是 randf_range() —— 抖一下就吃掉几个
	# 随机数, 客户端那边没有同样的抖动, 两边的 RNG 流当场分家, 地图就不一样了。
	# 从这里到 _build_map() 之间是一条没有 await 的同步路径, 所以两端消耗的
	# 随机数序列完全相同。
	if room_seed != 0:
		seed(room_seed)
	GameState.visit_room(room_key)

	var room := GameState.current_room_data()
	var is_combat: bool = FloorMap.is_combat_room(room)

	# 大/超大房间: GRID_W/GRID_H 要在 _build_map()/_spawn_doors()/
	# _spawn_base_and_walls() 之前就确定, 因为它们全部直接读这两个模块变量。
	# 摄像机边界和建造范围也要跟着重算, 否则会用上一个房间的尺寸残留一帧。
	match str(room.get("size", "normal")):
		"large":
			GRID_W = 26
			GRID_H = 26
		"huge":
			GRID_W = 52
			GRID_H = 52
		_:
			GRID_W = 13
			GRID_H = 13
	_update_camera_bounds()
	if builder_ctrl:
		builder_ctrl.set_room_bounds(GRID_W, GRID_H)

	# 每间房重新判定挑战模式: battle_type/challenge_mode 是 visit_room() 按
	# 房型刚写进 GameState 的, 而夜战雾和炸弹雨是**逐房**生效的效果, 不能
	# 沿用上一间房的状态 (否则走出挑战房之后天还是黑的)。
	is_night_mode_active = false
	is_bomb_rain_active = false
	bomb_rain_timer = 0.0
	is_shovel_active = false
	shovel_timer = 0.0
	base_wall_container.modulate.a = 1.0

	if is_combat and GameState.battle_type == "challenge":
		match GameState.challenge_mode:
			"bomb_rain":
				is_bomb_rain_active = true
				bomb_rain_timer = 2.0
			"night_ops":
				is_night_mode_active = true
			"night_bombs":
				is_night_mode_active = true
				is_bomb_rain_active = true
				bomb_rain_timer = 2.0

	var net_bulk := get_node_or_null("/root/Net")
	if net_bulk and NetSession.is_active():
		net_bulk.begin_bulk_change()
	_clear_all(true)
	if NetSession.is_client():
		# _clear_all 刚把上一间房的敌人/子弹傀儡 queue_free 掉了, 但
		# NetSession.puppets 里还留着它们的 net_id。不清的话这张表会一路涨,
		# 而且主机随后发来的 despawn 会落在已经失效的引用上。
		NetSession.purge_dead_puppets()
	_build_map()
	if net_bulk and NetSession.is_active():
		net_bulk.end_bulk_change()
		_net_verify_map()
	_spawn_doors()

	if is_combat:
		_spawn_base_and_walls(false)

	# 客户端的玩家坦克是傀儡, 位置由快照给。这里再本地摆一次只会让它在
	# 落点和权威位置之间弹一下。
	if NetSession.is_authority():
		_place_players_at_entry(entry_dir)

	if is_night_mode_active:
		activate_darkness_fog()

	room_cleared_pending = false
	if is_combat:
		if NetSession.is_authority():
			_begin_room_encounter()
		_announce_room(room)
	else:
		# 遭遇计数器必须清零。它们是 main.gd 的成员变量, 跨房间存活 ——
		# 不清的话走进商店/已清空的房间时, 上一间战斗房留下的
		# enemies_spawned/total_enemies 还挂在那儿。HUD 会显示上一场的残余,
		# 更糟的是 _process() 的补刷条件是 enemies_spawned < total_enemies,
		# 于是"从一间 total=12 的房走进一间继承了 spawned=12 但 total 更大的房"
		# 会在一间本该安静的房间里开始刷怪。
		total_enemies = 0
		enemies_spawned = 0
		enemies_alive = 0
		spawn_timer = 0.0

		# 非战斗房一进来就算"清空": 门直接开着, 玩家随时能走。
		# count_progress=false —— 它不是一场仗, 不该推高难度曲线
		# (current_floor 的语义是"打赢了多少间", 见 game_state.gd)。
		GameState.mark_room_cleared(room_key, false)
		_open_doors()
		_on_enter_non_combat_room(room)

	_update_hud()
	_update_rpg_hud()
	_refresh_minimap()


## 商店/事件对话框关掉之后, 玩家买到的东西 (perk、建材、金币、等级) 都写在
## GameState 上, 而战斗里读的是 rpg_mgr —— 两层状态是手动同步的
## (见 CLAUDE.md "The two state layers")。在尖塔时代这两个对话框跑在
## spire_map.tscn 里, 关掉之后必然要重新进一次 main.tscn, 同步顺带就做了;
## 现在它们和战斗同场景, 不主动拉一次的话, 刚买的强化要等到下一层才生效。
func _on_room_dialog_closed() -> void:
	rpg_mgr.sync_from_game_state()
	if p1_instance and is_instance_valid(p1_instance):
		p1_instance._apply_rpg_stats()
		p1_instance._update_tier_appearance()
	if p2_instance and is_instance_valid(p2_instance):
		p2_instance._apply_rpg_stats()
		p2_instance._update_tier_appearance()
	UIThemeHelper.update_hotbar_stock(hud_hotbar)
	_update_hud()
	_update_rpg_hud()
	GameState.save_campaign()
	# 事件的结算 (加钱、给天赋、扣血) 全落在 GameState 上, 客户端要跟上。
	# 顺序: 先收框再推状态 —— 反过来的话客户端会先看到收益到账、事件框却
	# 还开着, 像是还能再点一次。
	if NetSession.is_host() and _net_event_open:
		_net_event_open = false
		var net_close := get_node_or_null("/root/Net")
		if net_close:
			net_close.broadcast_event_closed()
	_net_push_campaign()


func _refresh_minimap() -> void:
	if minimap and is_instance_valid(minimap):
		minimap.refresh()


## 走进一个不用打的房间。
##
## 商店房把商品摆成地板上的物理货位 (以撒式, 开过去就买); 事件/休息房沿用
## spire 时代那个 event_dialog —— 它原本挂在 spire_map.tscn 上、直接读写
## GameState, 那套逻辑正好和场景无关, 所以搬过来不用改内部实现, 只换个触发点:
## 从"点地图节点"变成"走进房间"。
func _on_enter_non_combat_room(room: Dictionary) -> void:
	var room_type := str(room.get("type", ""))

	# 客户端: 非战斗房的**结算**在主机侧, 但交互不一定。
	#
	# 商店是完整可玩的: 货架内容 (shop_stock) 在房间字典里随战役状态同步,
	# 所以两端摆的是同一批货同一个价; 客户端开上货位会发一条成交请求, 由主机
	# 执行并把结果同步回来 (ShopStand._on_body_entered / net_apply_buy)。
	#
	# 事件/休息/宝物房还没有对应的上行交互, 客户端只有提示。
	if NetSession.is_client():
		match room_type:
			"shop":
				_build_shop_room()
			"event", "rest":
				# 事件框由主机推过来 (net_show_event) —— 事件种类是主机掷的,
				# 客户端不能自己 setup, 否则两边显示的是两个不同的事件而选项
				# 编号却对得上, 玩家以为选的是 A、主机结算的是 B。
				pass
			"treasure", "secret":
				show_toast("📦 队友正在开箱…")
		return

	match room_type:
		"shop":
			_build_shop_room()
			# 货架就是在上一行刚掷出来并写进房间字典的。必须立刻推给客户端 ——
			# 它那边不会自己掷 (见 _ensure_shop_stock 里的理由), 在收到之前
			# 商店是空的。
			_net_push_campaign()
		"event", "rest":
			if event_dialog:
				event_dialog.setup(str(room.get("type", "event")))
				event_dialog.visible = true
				# 事件种类是这里 randi() 掷出来的, 客户端必须拿到同一个,
				# 所以连着 dialog_type 一起发过去。
				_net_event_open = true
				var net_ev := get_node_or_null("/root/Net")
				if net_ev:
					net_ev.broadcast_event(str(room.get("type", "event")), str(event_dialog.current_event_id))
		"treasure":
			_grant_treasure_room_reward()
			_net_push_campaign()
		"secret":
			show_toast("🔒 隐藏房间 —— 补给已就位")
			_grant_treasure_room_reward()
			_net_push_campaign()


# ---------------------------------------------------------------- 商店房
#
# 以撒式: 商品是地板上的**物理货位**, 开过去就买。没有全屏货架、没有购买
# 按钮、没有离开按钮 —— 走出门就是离开。规则 (货源/定价/上限/发放) 全部复用
# shop_dialog.gd 的静态函数, 这里只负责摆放和存档。

## 货位布局。6 个商品 + 1 台换货机。
##
## 避开三处: 第 6 行是东西门的门廊, 第 3 列是南北门的门廊 (RoomDoor.DOOR_COL /
## DOOR_ROW), 玩家从门进来会沿着它们走 —— 货位摆在门廊上等于"进门就被扣钱"。
## 用 2/6/10 列而不是 3/6/9, 就是为了让第 3 列整列空出来。
const SHOP_STAND_CELLS: Array = [
	Vector2i(2, 4), Vector2i(6, 4), Vector2i(10, 4),
	Vector2i(2, 8), Vector2i(6, 8), Vector2i(10, 8),
]
## 换货机的位置。**不能压在任何一个入场点上。**
##
## 这里原本是 (6,10) —— 正好就是 _place_players_at_entry() 的默认落点
## (GRID_W/2, GRID_H-2.5) = (6.5, 10.5)。于是首次走进商店房的那一瞬间, 玩家
## 就站在换货机上, 立刻被扣一次换货费; 而换货会重建全部货位, 又是在物理回调
## 里删节点, 直接触发 "Can't change this state while flushing queries"。
##
## 要避开的落点一共五个: 四扇门的门内格 (RoomDoor.entry_position_for) 加这个
## 默认落点。test_room_flow.gd 里有一条断言把这五个位置逐个查过。
const SHOP_REROLLER_CELL := Vector2i(10, 10)

## 前 3 个货位放强化, 后 3 个放建材。
##
## **固定配比, 不是从 23 件里随机抽 6 件。** 建材是 GameState.structure_inventory
## 的唯一来源 (add_structure_stock 全项目只有商店在调), 混进同一个随机池的话,
## 一层楼抽不到建材就意味着建造系统那一层直接断粮, 而玩家只会觉得是运气差。
## 原来的对话框是"12 种建材每次全部上架"来保证这一点; 地板摆不下 12 个货位,
## 所以退一步到"必定有 3 种, 但哪 3 种是随机的" —— "这家店没有炮塔"变成一个
## 真实的变量, 而不是功能缺失。
const SHOP_UPGRADE_SLOTS := 3
const SHOP_BUILD_SLOTS := 3


## 生成/取出这个商店房的货架, 并存进房间字典。
##
## **必须存下来。** 房间是可以自由进出的, 而原来的 shop_dialog.setup_shop()
## 每次调用都重新洗牌 —— 实测走出门再走回来 6 次会拿到 6 种完全不同的货架,
## 也就是说"走出去再进来"就是一次免费刷新, 换货机和它那套递增计费完全被架空。
## 尖塔时代进商店节点是一次性的, 所以那时不存在这个问题。
##
## 只存 id + 成交价 + 是否卖掉。图标和描述每次从 ShopDialog.item_by_id() 现查,
## 避免把整个商品字典塞进 JSON 存档。
func _ensure_shop_stock(reroll: bool = false) -> Array:
	var room := GameState.current_room_data()
	if room.is_empty():
		return []
	if not reroll and room.has("shop_stock") and (room["shop_stock"] is Array) and not room["shop_stock"].is_empty():
		return room["shop_stock"]

	# **联机客户端永远不自己掷货架。**
	#
	# 货架是主机掷的, 随房间字典同步下来。客户端在同步到之前自己掷一份的话,
	# 两个人看到的是**不同的商品和价钱**, 而成交请求带的是槽位号 —— 客户端
	# 点"便宜的弹药", 主机按 0 号槽结算的可能是"贵的模块"。买错东西、扣错钱,
	# 而且两边的界面各自都自洽, 没有任何地方会报错。
	#
	# 拿不到就先摆空货架, 等主机把状态推下来 (net_apply_campaign 会重建货位)。
	if NetSession.is_client():
		return []

	var upgrades: Array = []
	var builds: Array = []
	for it in ShopDialog.build_inventory():
		if str(it.get("category", "")) == "BUILD":
			builds.append(it)
		else:
			upgrades.append(it)
	builds.shuffle()

	var stock: Array = []
	for i in range(mini(SHOP_UPGRADE_SLOTS, upgrades.size())):
		stock.append({"id": str(upgrades[i]["id"]), "cost": int(upgrades[i]["cost"]), "sold": false})
	for i in range(mini(SHOP_BUILD_SLOTS, builds.size())):
		stock.append({"id": str(builds[i]["id"]), "cost": int(builds[i]["cost"]), "sold": false})

	room["shop_stock"] = stock
	GameState.save_campaign()
	return stock


func _build_shop_room() -> void:
	var stock := _ensure_shop_stock()

	for i in range(mini(stock.size(), SHOP_STAND_CELLS.size())):
		var entry: Dictionary = stock[i]
		var cell: Vector2i = SHOP_STAND_CELLS[i]
		var stand := ShopStand.new()
		# setup() 要在 add_child() 之前 —— _ready() 是在 add_child 里跑的,
		# 它要读 item_id/cost/sold 才能摆好图标和价签。
		stand.setup(str(entry["id"]), int(entry["cost"]), bool(entry["sold"]))
		stand.position = Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)
		# 槽位号是客户端下单时唯一带过去的东西 —— 见 ShopStand.slot_index。
		stand.slot_index = i
		# 客户端的货位**照常可交互**: 它开上去会发一条成交请求, 由主机执行
		# (ShopStand._on_body_entered 里的联机分支)。所以这里两端一样接线,
		# 只是 purchased 信号在客户端永远不会响 —— 那边根本不会走到成交。
		if not NetSession.is_client():
			# 卖掉的状态要写回房间字典 —— 否则走出门再回来东西又回来了。
			stand.purchased.connect(func(_id, _c): _on_shop_item_sold(i))
		map_container.add_child(stand)

	var roller := ShopRerolder.new()
	roller.position = Vector2((SHOP_REROLLER_CELL.x + 0.5) * TILE_SIZE, (SHOP_REROLLER_CELL.y + 0.5) * TILE_SIZE)
	if not NetSession.is_client():
		roller.reroll_requested.connect(_on_shop_reroll)
	map_container.add_child(roller)


func _on_shop_item_sold(slot_idx: int) -> void:
	var room := GameState.current_room_data()
	if room.is_empty() or not room.has("shop_stock"):
		return
	var stock: Array = room["shop_stock"]
	if slot_idx >= 0 and slot_idx < stock.size():
		stock[slot_idx]["sold"] = true
	# 买完立刻把 GameState -> rpg_mgr 拉一次。战斗和商店现在同场景, 不再有
	# "换场景时顺带同步"这一步 (见 CLAUDE.md "The two state layers"), 不主动
	# 拉的话刚买的强化要等到下一层才生效。
	_sync_after_shop_purchase()
	# 客户端那边的货位是镜像, 得知道这格已经卖掉了。
	_net_push_campaign()


func _on_shop_reroll() -> void:
	# 必须 deferred。这个函数是从 ShopRerolder 的 body_entered 里调过来的,
	# 而那是在物理查询 flush 期间跑的回调 —— 此刻删节点/建带碰撞体的新节点会
	# 被引擎拒绝: "Can't change this state while flushing queries"。
	# 延到本帧调用栈退完再做。
	call_deferred("_do_shop_reroll")


func _do_shop_reroll() -> void:
	# 只重建货位, 不重建整个房间 —— enter_room() 会把玩家挪回门口, 而玩家
	# 此刻正站在换货机旁边。
	for c in map_container.get_children():
		if c is ShopStand or c is ShopRerolder:
			c.queue_free()
	_ensure_shop_stock(true)
	_build_shop_room()
	_sync_after_shop_purchase()
	_net_push_campaign()
	show_toast("军火商换了一批货 (下次换货 %d G)" % GameState.shop_reroll_cost)


func _sync_after_shop_purchase() -> void:
	rpg_mgr.sync_from_game_state()
	if p1_instance and is_instance_valid(p1_instance):
		p1_instance._apply_rpg_stats()
		p1_instance._update_tier_appearance()
	if p2_instance and is_instance_valid(p2_instance):
		p2_instance._apply_rpg_stats()
		p2_instance._update_tier_appearance()
	UIThemeHelper.update_hotbar_stock(hud_hotbar)
	_update_hud()
	_update_rpg_hud()
	GameState.save_campaign()


## 宝物房/秘密房的一次性奖励。用 once 标记记在房间字典里, 否则玩家来回走
## 两趟就能反复领 —— 房间是可以回头的, 这一点和原来单向向上的尖塔不一样。
func _grant_treasure_room_reward() -> void:
	var room := GameState.current_room_data()
	if bool(room.get("looted", false)):
		return
	room["looted"] = true

	if powerup_scene:
		var p_inst = powerup_scene.instantiate()
		# MISSILE/TIMED_BOMB 曾经完全不在这张表里 —— 房间奖励是这套架构下玩家
		# 最稳定的道具来源 (每个宝藏房必掉一次), 而砖块/bonus 击杀是随机的。
		# 两者不含这两种道具, 意味着不靠打砖块或 bonus 击杀就永远发现不了它们。
		var types = [PowerUp.Type.STAR, PowerUp.Type.LIFE, PowerUp.Type.HELMET, PowerUp.Type.BOMB, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB, PowerUp.Type.PISTON, PowerUp.Type.IFF_FLAG]
		types.shuffle()
		p_inst.setup(types[0])
		p_inst.position = Vector2((GRID_W / 2.0) * TILE_SIZE, (GRID_H / 2.0) * TILE_SIZE)
		actors_container.call_deferred("add_child", p_inst)
	add_gold(80)
	GameState.save_campaign()


func _announce_room(room: Dictionary) -> void:
	var room_size := str(room.get("size", "normal"))
	# 大/超大房间是稀有关卡事件, 用专属播报盖过普通的按类型播报——护送风味要
	# 把"友军阵亡即战败"换成新的过半判负规则, 攻城风味则直接点名这是一场
	# 加大号的老鹰保卫战 (老鹰保卫战本身没有新状态, 见 _on_base_destroyed())。
	if room_size != "normal":
		var size_label := "大型" if room_size == "large" else "超大型"
		if GameState.battle_type == "challenge" and GameState.challenge_mode == "escort":
			var count: int = int(ESCORT_ALLY_COUNT.get(room_size, 1))
			var required: int = count / 2 + 1
			show_toast("🛡️ %s护送房：保护 %d 名友军, 至少 %d 名存活才算成功！" % [size_label, count, required])
		else:
			show_toast("🏰 %s攻城房：全力守住老鹰基地！" % size_label)
		return

	match str(room.get("type", "normal")):
		"boss":
			show_toast("👑 BOSS 房：区域指挥官要塞！")
		"challenge":
			match GameState.challenge_mode:
				"bomb_rain": show_toast("💣 挑战房：空投炸弹雨！")
				"night_ops": show_toast("🌙 挑战房：黑夜突袭！")
				"night_bombs": show_toast("💀 挑战房：暗夜空投极限防守！")
				"escort": show_toast("🛡️ 挑战房：护送友军撑到最后！友军阵亡即战败！")
				_: show_toast("🏆 挑战房：隐秘宝藏！")
		"elite":
			show_toast("⚠️ 精英房：重装甲部队！")
		_:
			show_toast("战斗房 —— 消灭全部敌人以开门")


## 玩家入场定位。
##
## 走的是"移动已有实例"而不是"重新 _spawn_player()": 玩家坦克必须跨房间保留
## 血量和状态 (见 _clear_all 的 keep_players)。只有实例不存在时才真的生成。
func _place_players_at_entry(entry_dir: int) -> void:
	var base_pos: Vector2
	if entry_dir >= 0:
		base_pos = RoomDoor.entry_position_for(entry_dir, GRID_W, GRID_H)
	else:
		# 首次进场: 起始房中央偏下, 和以前的出生点一致。起始房永远不会被
		# _assign_room_sizes() 标记成大/超大 (它不在候选池里), 这条分支
		# 只在 GRID_W/GRID_H 是 13 时真正跑到, 这里用通用公式只是保持
		# 跟 _spawn_base_and_walls() 同一套写法, 不是为了真的支持大房间。
		base_pos = Vector2((RoomDoor.center_col_for(GRID_W) + 0.5) * TILE_SIZE, (GRID_H - 2.5) * TILE_SIZE)

	# 双人时把两台车沿门的切线方向分开一格, 否则两人叠在同一格里互相顶。
	var offset := Vector2(TILE_SIZE * 0.75, 0.0)
	if entry_dir == 1 or entry_dir == 3:
		offset = Vector2(0.0, TILE_SIZE * 0.75)

	p1_spawn_point = base_pos if GameState.player_count == 1 else base_pos - offset
	p2_spawn_point = base_pos + offset

	_settle_player(1, p1_spawn_point)
	if GameState.player_count == 2:
		_settle_player(2, p2_spawn_point)


func _settle_player(pid: int, pos: Vector2) -> void:
	var inst: PlayerTank = p1_instance if pid == 1 else p2_instance
	if inst == null or not is_instance_valid(inst):
		# 共享生命池下, 死亡玩家是"等按键", 不是"等下一次进房间就自动回来" ——
		# 不加这条守卫的话, 队友随便走一扇门就白送一条命, 手动复活形同虚设。
		# p1_spawn_point/p2_spawn_point 已经在调用方 (_place_players_at_entry)
		# 里刷新过了, 所以哪怕这次跳过生成, 玩家日后按键复活时落点仍是新房间的。
		if _lives_shared() and (p1_awaiting_revive if pid == 1 else p2_awaiting_revive):
			return
		_spawn_player(pid)
		return
	inst.position = pos
	# 火车分支: 车厢是靠"跟着车头的历史轨迹走"定位的, 车头瞬移之后那串历史
	# 还指向上一个房间, 尾巴会横穿整张图飞过来。teleport_train_chain() 就是
	# 干这个的 —— 把整条链的历史重置到新位置。
	TrainFollowHelper.teleport_train_chain(inst)


## 边墙。有门的那一边要在正中留一格缺口给门, 所以那条边拆成两段。
##
## 没门的边仍然是整整一条 —— 不是"四条边都拆成两段然后拿门堵中间": 关着的门
## 是 border 组的碰撞体没错, 但它是 Area2D 的子节点, 而 Area2D 会被
## _clear_all() 连根删掉; 中间那一格如果本来就该是实墙, 让它由边墙本身盖住
## 才不依赖门节点的生命周期。
func _build_border_walls(door_dirs: Array) -> void:
	var w := GRID_W * TILE_SIZE
	var h := GRID_H * TILE_SIZE
	# 四条边各自向外多包一格, 靠互相重叠把四个角封死 (原来那四条整墙就是这么做的)。
	var lo := -TILE_SIZE
	var hi_x := w + TILE_SIZE
	var hi_y := h + TILE_SIZE
	# 缺口在门那一格上, 由 RoomDoor.door_col_for()/door_row_for() 决定 ——
	# 不是边的中点, 因为中点会撞上底边中央的老鹰基地, 详见 room_door.gd
	# 里那段注释。这两个函数在 GRID_W/GRID_H == 13 时精确退化成
	# DOOR_COL/DOOR_ROW, 大/超大房间下则是同一条"避让基地"推导按新尺寸重算。
	var gap_x0 := RoomDoor.door_col_for(GRID_W) * TILE_SIZE
	var gap_x1 := gap_x0 + TILE_SIZE
	var gap_y0 := RoomDoor.door_row_for(GRID_H) * TILE_SIZE
	var gap_y1 := gap_y0 + TILE_SIZE

	for d in range(4):
		var has_door: bool = door_dirs.has(d)
		match d:
			0: # N —— 横墙, 缺口在 x 方向
				if has_door:
					_border_rect(lo, -TILE_SIZE, gap_x0, 0.0)
					_border_rect(gap_x1, -TILE_SIZE, hi_x, 0.0)
				else:
					_border_rect(lo, -TILE_SIZE, hi_x, 0.0)
			2: # S
				if has_door:
					_border_rect(lo, h, gap_x0, h + TILE_SIZE)
					_border_rect(gap_x1, h, hi_x, h + TILE_SIZE)
				else:
					_border_rect(lo, h, hi_x, h + TILE_SIZE)
			3: # W —— 竖墙, 缺口在 y 方向
				if has_door:
					_border_rect(-TILE_SIZE, lo, 0.0, gap_y0)
					_border_rect(-TILE_SIZE, gap_y1, 0.0, hi_y)
				else:
					_border_rect(-TILE_SIZE, lo, 0.0, hi_y)
			1: # E
				if has_door:
					_border_rect(w, lo, w + TILE_SIZE, gap_y0)
					_border_rect(w, gap_y1, w + TILE_SIZE, hi_y)
				else:
					_border_rect(w, lo, w + TILE_SIZE, hi_y)


## 按矩形的两个角建一段边墙。缺口不在中点, 所以左右两段长度不等 —— 用
## "从哪到哪"描述比用"中心 + 尺寸"少算错一次除以二。
func _border_rect(x0: float, y0: float, x1: float, y1: float) -> void:
	var size := Vector2(x1 - x0, y1 - y0)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_create_border_wall(Vector2((x0 + x1) / 2.0, (y0 + y1) / 2.0), size)


## 把每扇门往房间里 CORRIDOR_DEPTH 格挖通。原地改传进来的数组。
##
## 必须挖: 玩家就是从这里进场的, 落点如果是砖墙/钢墙会直接卡死, 而 56 张手搓
## 模板没有一张是按"四条边上某一格要通"画的 —— 它们的硬性空格约定只有基地
## 那一坨和出生点 (见 CLAUDE.md 的模板结构要求)。
##
## 只挖门廊, 不做全图连通性修复: 模板是人手画的, 内部本来就连通; 程序生成的
## 那一支走 MapDirector, 它自带 _carve_critical_paths()。基地区域也不用挖 ——
## 模板和 MapDirector 都已经保证 [11][5..7] / [12][5,6,7] 为空。
const CORRIDOR_DEPTH := 2

func _carve_room_openings(layout: Array, door_dirs: Array) -> void:
	var door_col := RoomDoor.door_col_for(GRID_W)
	var door_row := RoomDoor.door_row_for(GRID_H)
	for d in door_dirs:
		for step in range(CORRIDOR_DEPTH):
			var r := 0
			var c := 0
			match int(d):
				0: r = step;               c = door_col
				2: r = GRID_H - 1 - step;  c = door_col
				3: r = door_row;           c = step
				1: r = door_row;           c = GRID_W - 1 - step
			if r >= 0 and r < layout.size() and c >= 0 and c < layout[r].size():
				layout[r][c] = 0


func _build_map() -> void:
	var door_dirs := _current_door_dirs()
	_build_border_walls(door_dirs)

	var room_size := str(GameState.current_room_data().get("size", "normal"))

	var layout: Array
	if not GameState.playtest_layout.is_empty():
		# 关卡编辑器的"试玩"按钮: 最高优先级, 用完即清空, 只影响这一个房间。
		layout = GameState.playtest_layout.duplicate(true)
		GameState.playtest_layout = []
	elif room_size != "normal":
		# 大/超大房间: 拼 N x N 张已验收的普通 13x13 关卡, 而不是走手搓模板/
		# MapDirector 的 13x13 硬校验 —— 见 CompositeRoomBuilder 顶部注释。
		# 每日挑战没有 floor_rooms/size 概念, room_size 恒为 "normal", 不会
		# 落进这个分支。
		layout = CompositeRoomBuilder.build(room_size, GameState.current_floor, GameState.battle_type, GameState.current_act, GameState.current_room)
	elif GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
		# Fully procedural terrain (not one of the handcrafted templates) --
		# "random tiles" is the point of the mode. Biome is randomized too
		# (global RNG was already seed()-ed from today's date in start_game()),
		# but the generator itself takes an explicit custom_seed since it
		# spins up its own local RandomNumberGenerator rather than using the
		# global randi()/randf() stream.
		var daily_act = randi_range(1, 3)
		# tier_override=2: 每日挑战是单场一命的花活局, 机制拉满才是它的卖点,
		# 不该被楼层档位压成入门图 (它本来也没有"楼层"的概念)。
		# 走 MapDirector 是为了拿到连通性验收 —— 每日是全服同一张图, 生成出
		# 一张出生点被钢墙隔断的图, 所有人当天都得吃这个亏。
		layout = MapDirector.build(0, daily_act, GameState.get_daily_seed(), 2)
	else:
		layout = MapTemplates.get_layout_for_stage(GameState.current_floor, GameState.battle_type, GameState.current_act, true, GameState.current_room)

	# **必须深拷贝。** get_layout_for_stage() 手搓模板那一支返回的是
	# map_templates.gd 里那个 const 数组**本身**的引用, 不是副本; 下面
	# _carve_room_openings() 是原地改数组。不拷贝的话第一次开门就把
	# TEMPLATE_CLASSIC 的中央 3x3 和四条边中点永久挖空了, 本次运行里之后
	# 每一个抽到这张模板的房间都会拿到被挖过的版本 —— 而且挖痕会累积,
	# 因为每个房间的门朝向不同。这类破坏不报错, 只是地图慢慢烂掉。
	layout = layout.duplicate(true)
	_carve_room_openings(layout, door_dirs)
	current_map_layout = layout

	for r in range(layout.size()):
		for c in range(layout[r].size()):
			var tile_type = layout[r][c]
			var pos = Vector2((c + 0.5) * TILE_SIZE, (r + 0.5) * TILE_SIZE)
			if tile_type == 1:
				_spawn_tile("brick", pos, tex_brick)
			elif tile_type == 2:
				_spawn_tile("steel", pos, tex_steel)
			elif tile_type == 3:
				_spawn_tile("water", pos, tex_water_frames[0] if tex_water_frames.size() > 0 else null)
			elif tile_type == 4:
				_spawn_tile("trees", pos, tex_trees)
			elif tile_type == 5 and landmine_hazard_scene:
				var mine = landmine_hazard_scene.instantiate()
				mine.position = pos
				map_container.add_child(mine)
			elif tile_type == 6:
				_spawn_tile("sand", pos, tex_sand)
			elif tile_type == 7:
				_spawn_tile("sand_dune", pos, tex_sand_dune)
			elif tile_type == 8:
				_spawn_tile("hard_clay", pos, tex_hard_clay)
			elif tile_type == 9:
				_spawn_tile("ice", pos, tex_ice)
			elif tile_type == 10:
				_spawn_moving_platform(pos, Vector2.RIGHT, 144.0, 48.0)
			elif tile_type == 11:
				_spawn_moving_platform(pos, Vector2.DOWN, 96.0, 48.0)
			elif tile_type == 12:
				_spawn_wormhole(pos)
			elif tile_type == 13:
				_spawn_shield_station(pos)
			elif tile_type == 14:
				_spawn_wind_blower(pos, WindBlower.Direction.UP)
			elif tile_type == 15:
				_spawn_wind_blower(pos, WindBlower.Direction.DOWN)
			elif tile_type == 16:
				_spawn_wind_blower(pos, WindBlower.Direction.LEFT)
			elif tile_type == 17:
				_spawn_wind_blower(pos, WindBlower.Direction.RIGHT)
			elif tile_type == 18:
				_spawn_conveyor(pos, ConveyorBelt.Direction.UP)
			elif tile_type == 19:
				_spawn_conveyor(pos, ConveyorBelt.Direction.DOWN)
			elif tile_type == 20:
				_spawn_conveyor(pos, ConveyorBelt.Direction.LEFT)
			elif tile_type == 21:
				_spawn_conveyor(pos, ConveyorBelt.Direction.RIGHT)
			elif tile_type == 22:
				_spawn_jump_pad(pos)
			elif tile_type == 23:
				_spawn_moving_platform(pos, Vector2.LEFT, 144.0, 48.0)
			elif tile_type == 24:
				_spawn_street_lamp(pos)
			elif tile_type == 25:
				_spawn_electric_wall(pos)
			elif tile_type == 26:
				_spawn_oil_barrel(pos)
			elif tile_type == 27:
				_spawn_signal_jammer_tower(pos)
			elif tile_type == 28:
				_spawn_factory(pos)
			elif tile_type == 29:
				_spawn_drifting_supplies(pos)
			elif tile_type == 30:
				_spawn_enemy_shield_tower(pos)
			elif tile_type == 31:
				_spawn_pipe_conduit(pos, 0)
			elif tile_type == 32:
				_spawn_pipe_conduit(pos, 1)
			elif tile_type == 33:
				_spawn_pipe_conduit(pos, 2)
			elif tile_type == 34:
				_spawn_pipe_conduit(pos, 3)
			elif tile_type == 35:
				_spawn_radar_station(pos)
			elif tile_type == 36:
				_spawn_ammo_depot(pos)
			elif tile_type == 37:
				_spawn_command_post(pos)
			elif tile_type == 38:
				_spawn_sniper_nest(pos)
			elif tile_type == 39:
				_spawn_emp_tower(pos)
			elif tile_type == 40:
				_spawn_bunker(pos, 0) # UP
			elif tile_type == 41:
				_spawn_bunker(pos, 1) # RIGHT
			elif tile_type == 42:
				_spawn_bunker(pos, 2) # DOWN
			elif tile_type == 43:
				_spawn_bunker(pos, 3) # LEFT
			elif tile_type == 44:
				_spawn_wooden_wall(pos)
			elif tile_type == 45:
				_spawn_tile("reinforced_steel", pos, tex_reinforced_steel)
			elif tile_type == 46:
				_spawn_piston_switch(pos, "red")
			elif tile_type == 47:
				_spawn_piston_switch(pos, "blue")
			elif tile_type == 48:
				_spawn_gated_electric_wall(pos, "red")
			elif tile_type == 49:
				_spawn_gated_electric_wall(pos, "blue")
			elif tile_type == 50:
				_spawn_gated_shield_station(pos, "red")
			elif tile_type == 51:
				_spawn_gated_shield_station(pos, "blue")
			elif tile_type == 52:
				_spawn_bomb_switch(pos, "red")
			elif tile_type == 53:
				_spawn_bomb_switch(pos, "blue")
			elif tile_type == 54:
				_spawn_energy_wall(pos, "red")
			elif tile_type == 55:
				_spawn_energy_wall(pos, "blue")

	# Dynamic terrain hazards (Minefields on higher floors / elite encounters).
	# 只在战斗房加 —— 这段是在 _build_map() 尾部无条件跑的, 跟房间类型无关;
	# 商店/事件/宝物/休息房也会经过 _build_map() (每间房都建图), 不加这个判定
	# 的话高楼层的商店房会在货位旁边埋地雷, 玩家逛街进门就被炸。
	# **只有战役模式有"房间"这个概念。** 原来的条件写的是"不是每日挑战就查
	# 房间类型", 于是街机模式每建一次图都会拿一个空字典去调 is_combat_room(),
	# 在 room["type"] 上抛 "Invalid access to property or key 'type'"。
	# 它不致命 (room_is_combat 保持 true, 地雷照埋), 所以一直没人发现 ——
	# 但控制台里每局都有一条红字, 而且联机走的正是街机模式。
	var room_is_combat: bool = true
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		room_is_combat = FloorMap.is_combat_room(GameState.current_room_data())
	if room_is_combat and (GameState.current_floor >= 2 or GameState.battle_type in ["elite", "boss"]) and landmine_hazard_scene:
		var mine_positions = []
		if GameState.current_floor == 2:
			mine_positions = [
				Vector2(4.5 * TILE_SIZE, 6.5 * TILE_SIZE),
				Vector2(8.5 * TILE_SIZE, 6.5 * TILE_SIZE)
			]
		elif GameState.current_floor == 3:
			mine_positions = [
				Vector2(2.5 * TILE_SIZE, 4.5 * TILE_SIZE),
				Vector2(10.5 * TILE_SIZE, 4.5 * TILE_SIZE),
				Vector2(6.5 * TILE_SIZE, 8.5 * TILE_SIZE)
			]
		elif GameState.current_floor >= 4 or GameState.battle_type in ["elite", "boss"]:
			mine_positions = [
				Vector2(2.5 * TILE_SIZE, 4.5 * TILE_SIZE),
				Vector2(10.5 * TILE_SIZE, 4.5 * TILE_SIZE),
				Vector2(4.5 * TILE_SIZE, 8.5 * TILE_SIZE),
				Vector2(8.5 * TILE_SIZE, 8.5 * TILE_SIZE)
			]

		for m_pos in mine_positions:
			var mine = landmine_hazard_scene.instantiate()
			mine.position = m_pos
			map_container.add_child(mine)

func _create_border_wall(pos: Vector2, size: Vector2) -> void:
	var body = StaticBody2D.new()
	body.position = pos
	body.add_to_group("border")
	body.add_to_group("steel")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	map_container.add_child(body)

func _spawn_brick_tile(container: Node2D, pos: Vector2, is_steel: bool = false) -> void:
	# 差分选图。这个函数有两个调用点 —— _spawn_tile() 的地形分支, 以及
	# _spawn_base_and_walls() 摆老鹰砖圈 (铲子道具还会把它整圈换成钢),
	# 两边都该吃到差分, 所以选图放在这里而不是调用方。
	var group_key := "steel" if is_steel else "brick"
	var tex: Texture2D = TerrainVariants.texture_for(
		group_key, TerrainVariants.cell_of(pos, TILE_SIZE))
	if not tex:
		tex = tex_steel if is_steel else tex_brick
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png" if is_steel else "res://assets/sprites/tiles/tile_brick.png")
	if not tex:
		return
	var group_name = "steel" if is_steel else "brick"
	var sub_size = TILE_SIZE / 2.0

	for r in range(2):
		for c in range(2):
			var sub_body = StaticBody2D.new()
			var offset = Vector2((c - 0.5) * sub_size, (r - 0.5) * sub_size)
			sub_body.position = pos + offset
			sub_body.add_to_group(group_name)

			var spr = Sprite2D.new()
			spr.texture = tex
			spr.region_enabled = true
			spr.region_rect = Rect2(c * 128.0, r * 128.0, 128.0, 128.0)
			spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
			sub_body.add_child(spr)

			var col = CollisionShape2D.new()
			var shape = RectangleShape2D.new()
			shape.size = Vector2(sub_size, sub_size)
			col.shape = shape
			sub_body.add_child(col)

			container.add_child(sub_body)

func _spawn_hard_clay_tile(container: Node2D, pos: Vector2) -> void:
	var tex = tex_hard_clay
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_hard_clay.png")
	if not tex:
		tex = tex_brick
	if not tex:
		return

	var sub_size = TILE_SIZE / 2.0
	for r in range(2):
		for c in range(2):
			var sub_body = HardClayBlock.new()
			var offset = Vector2((c - 0.5) * sub_size, (r - 0.5) * sub_size)
			sub_body.position = pos + offset

			var spr = Sprite2D.new()
			spr.texture = tex
			spr.region_enabled = true
			spr.region_rect = Rect2(c * 128.0, r * 128.0, 128.0, 128.0)
			spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
			sub_body.add_child(spr)
			sub_body.sprite = spr

			var col = CollisionShape2D.new()
			var shape = RectangleShape2D.new()
			shape.size = Vector2(sub_size, sub_size)
			col.shape = shape
			sub_body.add_child(col)

			container.add_child(sub_body)

func _tree_sway_mat() -> ShaderMaterial:
	if _tree_sway_material == null:
		var shader := Shader.new()
		shader.code = TREE_SWAY_SHADER_CODE
		_tree_sway_material = ShaderMaterial.new()
		_tree_sway_material.shader = shader
	return _tree_sway_material

func _spawn_tile(type: String, pos: Vector2, tex: Texture2D) -> void:
	GameState.discover_encyclopedia_entry("tile_" + type)
	# 外观差分: 同一种地形有多张磨损/主题差分, 按格号确定性挑一张, 让整片
	# 地形不再是同一张图复制几十遍。选图逻辑在 TerrainVariants ——
	# 那边一个随机数都不取 (每日挑战依赖全局 RNG 流保持确定), 全靠哈希。
	# 没有差分的地形 (ice / hard_clay / wormhole ...) 返回 null, 沿用传进来
	# 的贴图, 所以这一句对它们是彻底的空操作。
	var variant_tex: Texture2D = TerrainVariants.texture_for(
		type, TerrainVariants.cell_of(pos, TILE_SIZE))
	if variant_tex:
		tex = variant_tex
	if not tex:
		return
	if type == "trees":
		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		spr.position = pos
		spr.z_index = 10
		spr.material = _tree_sway_mat()
		spr.add_to_group("trees")
		map_container.add_child(spr)
		# 按格记下来, 供 _update_tree_transparency() 做"有坦克进林子就透出来"。
		# pos 是格心 (c+0.5)*TILE_SIZE, 所以直接整除就能还原格号。
		tree_sprites[Vector2i(int(pos.x / TILE_SIZE), int(pos.y / TILE_SIZE))] = spr
		return
	if type == "brick":
		_spawn_brick_tile(map_container, pos, false)
		return
	if type == "hard_clay":
		_spawn_hard_clay_tile(map_container, pos)
		return
	if type == "steel":
		_spawn_brick_tile(map_container, pos, true)
		return
	if type == "reinforced_steel":
		# 比普通钢墙硬一档: 对所有子弹/激光/破钢弹一律免疫 (见 bullet.gd /
		# laser_piercer.gd / laser_ring_cutter.gd 里 "reinforced_steel" 排除项),
		# 只有 timed_bomb / landmine / missile_strike 三种爆破物能炸开它,
		# 油桶不算在内 (见 oil_barrel.gd 里的例外注释)。不做 2x2 细分——
		# 普通钢墙细分是为了配合子弹的逐格破坏, 这堵墙对子弹完全免疫,
		# 能破坏它的爆破物又都是整块 queue_free(), 细分没有意义。
		var body := StaticBody2D.new()
		body.position = pos
		body.add_to_group("steel")
		body.add_to_group("reinforced_steel")

		var r_spr := Sprite2D.new()
		r_spr.texture = tex
		r_spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		r_spr.modulate = Color(0.5, 0.58, 0.7, 1.0)
		body.add_child(r_spr)

		var r_col := CollisionShape2D.new()
		var r_shape := RectangleShape2D.new()
		r_shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		r_col.shape = r_shape
		body.add_child(r_col)

		map_container.add_child(body)
		return
	if type == "sand":
		var sand_area = Area2D.new()
		sand_area.position = pos
		sand_area.z_index = -1
		sand_area.add_to_group("sand")

		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		sand_area.add_child(spr)

		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		col.shape = shape
		sand_area.add_child(col)

		sand_area.body_entered.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_enter_sand"):
				b.on_enter_sand()
		)
		sand_area.body_exited.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_exit_sand"):
				b.on_exit_sand()
		)

		map_container.add_child(sand_area)
		return
	if type == "ice":
		var ice_area = Area2D.new()
		ice_area.position = pos
		ice_area.z_index = -1
		ice_area.add_to_group("ice")

		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		ice_area.add_child(spr)

		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		col.shape = shape
		ice_area.add_child(col)

		ice_area.body_entered.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_enter_ice"):
				b.on_enter_ice()
		)
		ice_area.body_exited.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_exit_ice"):
				b.on_exit_ice()
		)

		map_container.add_child(ice_area)
		return
	if type == "sand_dune":
		var dune_body = StaticBody2D.new()
		dune_body.position = pos
		dune_body.add_to_group("brick")
		dune_body.add_to_group("sand_dune")

		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		dune_body.add_child(spr)

		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		col.shape = shape
		dune_body.add_child(col)

		map_container.add_child(dune_body)
		return

	var body = StaticBody2D.new()
	body.position = pos
	body.add_to_group(type)
	
	var spr = Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
	body.add_child(spr)

	if type == "water":
		water_sprites.append(spr)
		water_bodies.append(body)

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
	col.shape = shape
	body.add_child(col)

	map_container.add_child(body)

	if type == "water":
		# Sibling Area2D purely for overlap *detection* (on_enter_water/
		# on_exit_water) -- the StaticBody2D above still physically blocks
		# everyone by default. Amphibious Hull grants a collision exception
		# against the StaticBody2D itself (player.gd::_apply_rpg_stats), so
		# it needs this separate Area2D to know when it's actually "in"
		# water for the land-only speed penalty, same as the sand/ice areas
		# below use body_entered/exited to track is_on_sand/is_on_ice.
		var water_area = Area2D.new()
		water_area.position = pos
		water_area.z_index = -1
		var area_col = CollisionShape2D.new()
		var area_shape = RectangleShape2D.new()
		area_shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		area_col.shape = area_shape
		water_area.add_child(area_col)
		water_area.body_entered.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_enter_water"):
				b.on_enter_water()
		)
		water_area.body_exited.connect(func(b):
			if is_instance_valid(b) and b.has_method("on_exit_water"):
				b.on_exit_water()
		)
		map_container.add_child(water_area)

func _spawn_moving_platform(pos: Vector2, axis: Vector2 = Vector2.RIGHT, dist: float = 144.0, speed: float = 48.0) -> void:
	if not moving_platform_scene:
		moving_platform_scene = load("res://scenes/moving_platform.tscn")
	if moving_platform_scene:
		var plat = moving_platform_scene.instantiate() as MovingPlatform
		plat.position = pos
		plat.patrol_axis = axis
		plat.patrol_distance = dist
		plat.move_speed = speed
		actors_container.add_child(plat)

func _spawn_wormhole(pos: Vector2) -> void:
	GameState.discover_encyclopedia_entry("tile_wormhole")
	if not wormhole_scene:
		wormhole_scene = load("res://scenes/wormhole.tscn")
	if wormhole_scene:
		var wh = wormhole_scene.instantiate()
		wh.position = pos
		actors_container.add_child(wh)

func _spawn_shield_station(pos: Vector2) -> void:
	if not shield_station_scene:
		shield_station_scene = load("res://scenes/buildings/shield_station.tscn")
	if shield_station_scene:
		var st = shield_station_scene.instantiate()
		st.position = pos
		actors_container.add_child(st)

func _spawn_wind_blower(pos: Vector2, dir: WindBlower.Direction) -> void:
	if not wind_blower_scene:
		wind_blower_scene = load("res://scenes/buildings/wind_blower.tscn")
	if wind_blower_scene:
		var wb = wind_blower_scene.instantiate()
		wb.position = pos
		wb.set_direction(dir)
		actors_container.add_child(wb)

func _spawn_conveyor(pos: Vector2, dir: ConveyorBelt.Direction) -> void:
	GameState.discover_encyclopedia_entry("tile_conveyor")
	if not conveyor_belt_scene:
		conveyor_belt_scene = load("res://scenes/conveyor_belt.tscn")
	if conveyor_belt_scene:
		var cb = conveyor_belt_scene.instantiate()
		cb.position = pos
		cb.set_direction(dir)
		map_container.add_child(cb)

func _spawn_jump_pad(pos: Vector2) -> void:
	GameState.discover_encyclopedia_entry("tile_jump_pad")
	if not jump_pad_scene:
		jump_pad_scene = load("res://scenes/jump_pad.tscn")
	if jump_pad_scene:
		var jp = jump_pad_scene.instantiate()
		jp.position = pos
		map_container.add_child(jp)

func _spawn_street_lamp(pos: Vector2) -> void:
	if not street_lamp_scene:
		street_lamp_scene = load("res://scenes/buildings/street_lamp.tscn")
	if street_lamp_scene:
		var lamp = street_lamp_scene.instantiate()
		lamp.position = pos
		actors_container.add_child(lamp)

func _spawn_electric_wall(pos: Vector2) -> void:
	if not electric_wall_scene:
		electric_wall_scene = load("res://scenes/buildings/electric_wall.tscn")
	if electric_wall_scene:
		var ew = electric_wall_scene.instantiate()
		ew.position = pos
		map_container.add_child(ew)

## 活塞开关。放进 actors_container 而不是 map_container——跟 shield_station/
## pipe_conduit/wooden_wall 是同一批"非纯地形" building 的既有惯例, 不是
## 因为它会动。
func _spawn_piston_switch(pos: Vector2, color: String) -> void:
	if not piston_switch_scene:
		piston_switch_scene = load("res://scenes/buildings/piston_switch.tscn")
	if piston_switch_scene:
		var sw = piston_switch_scene.instantiate()
		sw.gate_color = color
		sw.position = pos
		actors_container.add_child(sw)
		sw.switch_pressed.connect(_on_circuit_switch_pressed)

## 受电路控制的电墙: 默认保持 is_powered=true (跟普通电墙一样, 出生即通电/
## 危险), 电路解开前不做任何特殊处理——它就是一堵会通电的墙, 只是额外记进
## circuit_gated_buildings 好让 _on_circuit_switch_pressed() 找得到它。
func _spawn_gated_electric_wall(pos: Vector2, color: String) -> void:
	if not electric_wall_scene:
		electric_wall_scene = load("res://scenes/buildings/electric_wall.tscn")
	if electric_wall_scene:
		var ew = electric_wall_scene.instantiate()
		ew.position = pos
		map_container.add_child(ew)
		if not circuit_gated_buildings.has(color):
			circuit_gated_buildings[color] = []
		circuit_gated_buildings[color].append(ew)

## 受电路控制的充能站: 出生即 is_powered=false (完全惰性, 电路解开前不可用)。
## 这一行必须在 add_child() 之前赋值——is_powered 是普通实例变量, 赋值不需要
## 节点已经在树里, 但 shield_station.gd::_ready() (在 add_child() 期间跑)
## 要靠它才知道不该把 is_charged 钉回 true。
func _spawn_gated_shield_station(pos: Vector2, color: String) -> void:
	if not shield_station_scene:
		shield_station_scene = load("res://scenes/buildings/shield_station.tscn")
	if shield_station_scene:
		var st = shield_station_scene.instantiate()
		st.is_powered = false
		st.position = pos
		actors_container.add_child(st)
		if not circuit_gated_buildings.has(color):
			circuit_gated_buildings[color] = []
		circuit_gated_buildings[color].append(st)

## 某种颜色的活塞开关被按下: 把这个颜色底下所有还活着的受控建筑一次性
## set_circuit_solved(true)。circuit_solved[color] 挡重复触发——同色可能有
## 不止一个开关 (任意一个按下即算解开, OR 逻辑), 后按的那些应该是无操作,
## 不用重放一次音效/提示。
func _on_circuit_switch_pressed(color: String) -> void:
	if circuit_solved.get(color, false):
		return
	circuit_solved[color] = true
	for building in circuit_gated_buildings.get(color, []):
		if is_instance_valid(building) and building.has_method("set_circuit_solved"):
			building.set_circuit_solved(true)
	SoundManager.play_pickup(get_tree())
	var color_label: String = {"red": "红色", "blue": "蓝色"}.get(color, color)
	show_toast("🔌 %s电路已接通！" % color_label)

## 可摧毁开关: 跟 _spawn_piston_switch 接同一个 switch_pressed 信号 ->
## _on_circuit_switch_pressed, 两种触发方式共用一份 circuit_solved 状态。
func _spawn_bomb_switch(pos: Vector2, color: String) -> void:
	if not bomb_switch_scene:
		bomb_switch_scene = load("res://scenes/buildings/bomb_switch.tscn")
	if bomb_switch_scene:
		var sw = bomb_switch_scene.instantiate()
		sw.gate_color = color
		sw.position = pos
		actors_container.add_child(sw)
		sw.switch_pressed.connect(_on_circuit_switch_pressed)

## 能量墙: 出生即对一切火力免疫, 只有同色开关 (压力板或可摧毁款均可) 触发后
## set_circuit_solved(true) 才会让它自我摧毁——见 energy_wall.gd 顶部注释。
func _spawn_energy_wall(pos: Vector2, color: String) -> void:
	if not energy_wall_scene:
		energy_wall_scene = load("res://scenes/buildings/energy_wall.tscn")
	if energy_wall_scene:
		var ew = energy_wall_scene.instantiate()
		ew.gate_color = color
		ew.position = pos
		map_container.add_child(ew)
		if not circuit_gated_buildings.has(color):
			circuit_gated_buildings[color] = []
		circuit_gated_buildings[color].append(ew)

func _spawn_oil_barrel(pos: Vector2) -> void:
	if not oil_barrel_scene:
		oil_barrel_scene = load("res://scenes/buildings/oil_barrel.tscn")
	if oil_barrel_scene:
		var barrel = oil_barrel_scene.instantiate()
		barrel.position = pos
		actors_container.add_child(barrel)

func _spawn_signal_jammer_tower(pos: Vector2) -> void:
	if not signal_jammer_tower_scene:
		signal_jammer_tower_scene = load("res://scenes/buildings/signal_jammer_tower.tscn")
	if signal_jammer_tower_scene:
		var jammer = signal_jammer_tower_scene.instantiate()
		jammer.position = pos
		actors_container.add_child(jammer)

func _spawn_factory(pos: Vector2) -> void:
	if not factory_scene:
		factory_scene = load("res://scenes/buildings/factory.tscn")
	if factory_scene:
		var factory = factory_scene.instantiate()
		factory.position = pos
		actors_container.add_child(factory)
		factory_instances.append(factory)

func _spawn_drifting_supplies(pos: Vector2) -> void:
	# Decorative water backdrop with NO collision body -- unlike a real water
	# tile (_spawn_tile("water", ...)), this cell is deliberately walkable so
	# any tank (not just Amphibious Hull owners) can reach the crate on it.
	# Registered into water_sprites so it animates in sync with real water.
	var spr = Sprite2D.new()
	if tex_water_frames.size() > 0:
		spr.texture = tex_water_frames[0]
	spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
	spr.position = pos
	spr.z_index = -1
	map_container.add_child(spr)
	water_sprites.append(spr)

	if not drifting_supplies_scene:
		drifting_supplies_scene = load("res://scenes/drifting_supplies.tscn")
	if drifting_supplies_scene:
		var crate = drifting_supplies_scene.instantiate()
		crate.position = pos
		actors_container.add_child(crate)

func _spawn_enemy_shield_tower(pos: Vector2) -> void:
	if not enemy_shield_tower_scene:
		enemy_shield_tower_scene = load("res://scenes/buildings/enemy_shield_tower.tscn")
	if enemy_shield_tower_scene:
		var tower = enemy_shield_tower_scene.instantiate()
		tower.position = pos
		actors_container.add_child(tower)

func _spawn_pipe_conduit(pos: Vector2, orient: int) -> void:
	if not pipe_conduit_scene:
		pipe_conduit_scene = load("res://scenes/buildings/pipe_conduit.tscn")
	if pipe_conduit_scene:
		var pipe = pipe_conduit_scene.instantiate()
		pipe.position = pos
		if pipe.has_method("set_orientation"):
			pipe.set_orientation(orient)
		actors_container.add_child(pipe)

func _spawn_radar_station(pos: Vector2) -> void:
	if not radar_station_scene:
		radar_station_scene = load("res://scenes/buildings/radar_station.tscn")
	if radar_station_scene:
		var radar = radar_station_scene.instantiate()
		radar.position = pos
		actors_container.add_child(radar)

func _spawn_ammo_depot(pos: Vector2) -> void:
	if not ammo_depot_scene:
		ammo_depot_scene = load("res://scenes/buildings/ammo_depot.tscn")
	if ammo_depot_scene:
		var depot = ammo_depot_scene.instantiate()
		depot.position = pos
		actors_container.add_child(depot)

func _spawn_command_post(pos: Vector2) -> void:
	if not command_post_scene:
		command_post_scene = load("res://scenes/buildings/command_post.tscn")
	if command_post_scene:
		var cp = command_post_scene.instantiate()
		cp.position = pos
		actors_container.add_child(cp)

func _spawn_sniper_nest(pos: Vector2, fire_dir: Vector2 = Vector2.UP) -> void:
	if not sniper_nest_scene:
		sniper_nest_scene = load("res://scenes/buildings/sniper_nest.tscn")
	if sniper_nest_scene:
		var nest = sniper_nest_scene.instantiate()
		nest.position = pos
		if nest.has_method("set_fire_direction"):
			nest.set_fire_direction(fire_dir)
		actors_container.add_child(nest)

func _spawn_emp_tower(pos: Vector2) -> void:
	if not emp_tower_scene:
		emp_tower_scene = load("res://scenes/buildings/emp_tower.tscn")
	if emp_tower_scene:
		var emp = emp_tower_scene.instantiate()
		emp.position = pos
		actors_container.add_child(emp)

func _spawn_bunker(pos: Vector2, facing: int = 0) -> void:
	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	if bunker_scene:
		var bunker = bunker_scene.instantiate()
		bunker.position = pos
		if bunker.has_method("set_facing"):
			bunker.set_facing(facing)
		actors_container.add_child(bunker)

func _spawn_wooden_wall(pos: Vector2) -> void:
	var wooden_wall_scene = load("res://scenes/buildings/wooden_wall.tscn")
	if wooden_wall_scene:
		var w_wall = wooden_wall_scene.instantiate()
		w_wall.position = pos
		actors_container.add_child(w_wall)

func _setup_challenge_treasure() -> void:
	has_treasure_key = false
	key_has_dropped = false
	key_target_block_instance = null
	key_target_enemy_idx = -1

	var is_challenge = (GameState.battle_type == "challenge")
	# 100% chance in challenge nodes, 40% chance in any other stage as a secret vault event!
	if not is_challenge and randf() > 0.40:
		return

	# Spawn chest at random empty spot
	if treasure_chest_scene:
		var chest_pos = get_random_empty_tile_position()
		var chest = treasure_chest_scene.instantiate()
		actors_container.add_child(chest)
		# get_random_empty_tile_position() 现在返回全局坐标, 所以要先入树再设
		# global_position —— 入树前设 global_position 等价于设 position, 白搭。
		chest.global_position = chest_pos

	# Pick secret key carrier (completely hidden, no visual cues until destroyed)
	var destructible_blocks: Array[Node] = []
	for child in map_container.get_children():
		if child.is_in_group("brick") or child.is_in_group("hard_clay") or child.is_in_group("sand_dune"):
			destructible_blocks.append(child)

	if destructible_blocks.size() > 0 and (randf() < 0.5 or total_enemies <= 2):
		key_hidden_target_type = "block"
		key_target_block_instance = destructible_blocks[randi() % destructible_blocks.size()]
	else:
		key_hidden_target_type = "enemy"
		key_target_enemy_idx = randi_range(2, max(2, total_enemies - 1))

	if is_challenge:
		show_toast("🏆 隐秘宝藏挑战关：击破隐藏地块或击杀敌军寻找【金钥匙】！")
	else:
		show_toast("✨ 战场暗藏秘宝！击破特定地块或消灭敌军可掉落【金钥匙】！")

func check_key_drop(source: Node, drop_pos: Vector2) -> void:
	if key_has_dropped:
		return
	
	if key_hidden_target_type == "block":
		if is_instance_valid(key_target_block_instance) and source == key_target_block_instance:
			_drop_treasure_key(drop_pos)
		elif not is_instance_valid(key_target_block_instance):
			_drop_treasure_key(drop_pos)

func check_key_drop_enemy(enemy_node: Node, drop_pos: Vector2) -> void:
	if key_has_dropped:
		return
	if key_hidden_target_type == "enemy":
		if enemy_node.has_meta("enemy_spawn_index") and enemy_node.get_meta("enemy_spawn_index") == key_target_enemy_idx:
			_drop_treasure_key(drop_pos)
		elif enemies_alive <= 1 and enemies_spawned >= total_enemies:
			_drop_treasure_key(drop_pos)

func _drop_treasure_key(drop_pos: Vector2) -> void:
	if key_has_dropped:
		return
	key_has_dropped = true
	if not treasure_key_scene:
		treasure_key_scene = load("res://scenes/treasure_key.tscn")
	if treasure_key_scene:
		var key = treasure_key_scene.instantiate()
		# add_child 是 deferred 的, 此刻节点还不在树里, 赋 global_position
		# 等同于赋 position; 真正入树后再叠一次 GameArea 的 (48,48) 偏移,
		# 钥匙会画在触发源右下方整整一格。用 to_local() 提前把全局坐标转成
		# actors_container 的局部坐标, 赋给 position 就不受入树时机影响
		# (跟 enemy.gd:907 金币掉落的写法一致)。
		key.position = actors_container.to_local(drop_pos)
		actors_container.call_deferred("add_child", key)
		SoundManager.play_level_up(get_tree())
		VFXAnimator.spawn_teleport_burst(actors_container, drop_pos)
		show_toast("🔑 发现神秘金钥匙！快去触碰战场宝箱！")

func obtain_treasure_key() -> void:
	has_treasure_key = true
	show_toast("🔑 已获得金钥匙！触碰宝箱即可开启！")

func add_life(amount: int = 1) -> void:
	p1_lives += amount
	if GameState.player_count == 2:
		p2_lives += amount
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		GameState.player_lives = p1_lives
	_update_hud()
	show_toast("❤️ EXTRA LIFE +%d!" % amount)

func try_spawn_block_loot(pos: Vector2) -> void:
	# Later stage bonus loot drop rate (scales with floor & Act)
	# Floor 0: ~6% chance
	# Floor 3, Act 2: ~16% chance
	# Floor 5, Act 3: ~26% chance
	var base_chance = 0.06 + (GameState.current_floor * 0.025) + ((GameState.current_act - 1) * 0.05)
	if randf() > base_chance:
		return

	var roll = randf()
	if roll < 0.62:
		# Gold Coin (+10~25G)
		var coin_scene = load("res://scenes/gold_coin.tscn")
		if coin_scene and actors_container:
			var coin = coin_scene.instantiate()
			# pos 是调用方传入的全局坐标(bullet.gd/timed_bomb.gd/missile_strike.gd
			# 都传 body.global_position); add_child 是 deferred 的, 直接赋
			# global_position 会在节点入树前退化成 position, 入树后再叠一次
			# GameArea 偏移, 金币画在被打碎砖块的右下方一格。
			coin.position = actors_container.to_local(pos)
			actors_container.call_deferred("add_child", coin)
	elif roll < 0.88:
		# Rare Diamond Gem (+90G)
		if not diamond_gem_scene:
			diamond_gem_scene = load("res://scenes/diamond_gem.tscn")
		if diamond_gem_scene and actors_container:
			var dia = diamond_gem_scene.instantiate()
			dia.position = actors_container.to_local(pos)
			actors_container.call_deferred("add_child", dia)
	else:
		# Rare Power-up (Star / Bomb / Clock / Helmet / Life / Shovel / Missile / Timed Bomb)
		if powerup_scene and actors_container:
			var p_inst = powerup_scene.instantiate()
			var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB, PowerUp.Type.PISTON, PowerUp.Type.IFF_FLAG]
			types.shuffle()
			p_inst.setup(types[0])
			# pos 是全局坐标, 这里原来直接赋给 position(局部), 掉落道具落在
			# 打碎砖块的右下方一格。
			p_inst.position = actors_container.to_local(pos)
			actors_container.call_deferred("add_child", p_inst)
			show_toast("✨ 砖块暗藏极品道具！")

## 随机挑一块空地, 返回**全局**坐标。
##
## 返回全局而不是网格局部, 是因为两个调用点里更容易搞错的那个用的就是全局:
## wormhole.gd 把结果直接赋给 body.global_position。而 (c+0.5)*TILE_SIZE 这套
## 网格算式产出的是 map_container 的局部坐标 —— GameArea 在 main.tscn 里
## position = Vector2(48,48), 于是两者差整整一格。
## 后果不是"偏一点点"而是实打实的错格: 这个函数精心挑了一块空地, 传送却把单位
## 放到它左上角那一格 —— 而那一格完全可能是砖墙或水。
## 现在契约统一为全局, 两个调用点都用 global_position。
func get_random_empty_tile_position() -> Vector2:
	var empty_candidates: Array[Vector2] = []
	var layout = current_map_layout
	# 基地避让区按 RoomDoor 的通用公式算, 不再写死 10/4/8 —— 大/超大房间的
	# 基地仍然只占中心 3 列 (center_col-2..center_col+2), 但那三个字面量是
	# 按 13x13 量出来的, 房间一大就不再对齐真正的基地位置。
	var avoid_row := RoomDoor.base_row_for(GRID_H) - 2
	var avoid_col_lo := RoomDoor.center_col_for(GRID_W) - 2
	var avoid_col_hi := RoomDoor.center_col_for(GRID_W) + 2
	if layout and layout.size() > 0:
		for r in range(layout.size()):
			for c in range(layout[r].size()):
				if layout[r][c] == 0:
					# Avoid teleporting onto Eagle base
					if r >= avoid_row and c >= avoid_col_lo and c <= avoid_col_hi:
						continue
					empty_candidates.append(Vector2((c + 0.5) * TILE_SIZE, (r + 0.5) * TILE_SIZE))
	var local_pos := Vector2(
		randf_range(2.0 * TILE_SIZE, (GRID_W - 2.0) * TILE_SIZE),
		randf_range(2.0 * TILE_SIZE, (GRID_H - 2.0) * TILE_SIZE)
	)
	if empty_candidates.size() > 0:
		local_pos = empty_candidates[randi() % empty_candidates.size()]
	if map_container:
		return map_container.to_global(local_pos)
	return local_pos

## 老鹰基地。**放在房间正中**, 不再是棋盘底边中央。
##
## 原来的位置 (6.5, 12.5) 是坦克大战的经典布局: 基地贴着己方底边, 敌人从
## 对面顶边三个点涌下来, 玩家守一个方向。以撒式房间有四扇门, "己方那一边"
## 这个概念不存在了 —— 基地贴着南墙的话, 从南门进来的玩家一脚就踩在基地上,
## 而从北门进来的敌人有整整 12 格的缓冲。位置一偏, 四扇门的公平性就没了。
##
## 正中还顺带解决了另一件事: 底边中央那三格 ([12][5,6,7]) 正是南门的门廊,
## 基地摆在那儿会把自己的出口堵死。
##
## 围墙从原来的 5 块改成上下左右 4 块: 正中是四面受敌, 五块砖那种"开口朝北"
## 的不对称布局会凭空规定一个弱侧。
## 老鹰基地。位置和围墙布局保持坦克大战的经典样子: 底边中央 [12][6], 外面
## 一圈五块砖 —— 房间化没有动它。
##
## 房间制下它是**临时**的: 只在没打完的战斗房里存在, 房间一清空就整个撤掉
## (见 _despawn_base)。所以下面的门位常量必须绕开这块区域, 见 room_door.gd
## 的 DOOR_COL 那段。
func _spawn_base_and_walls(use_steel: bool = false) -> void:
	GameState.discover_encyclopedia_entry("tile_base_eagle")
	for child in base_wall_container.get_children():
		child.queue_free()

	# center_x/base_y 用 RoomDoor 的通用公式而不是字面量 6.5/12.5 —— 大/超大
	# 房间的 GRID_W/GRID_H 不是 13, 但基地永远在"房间正中心的底边", 这两个
	# 公式在 13x13 下精确退化回原来的字面量。
	var center_x := (RoomDoor.center_col_for(GRID_W) + 0.5) * TILE_SIZE
	var base_y := (RoomDoor.base_row_for(GRID_H) + 0.5) * TILE_SIZE

	base_instance = base_scene.instantiate()
	base_instance.position = Vector2(center_x, base_y)
	base_instance.destroyed.connect(_on_base_destroyed)
	base_wall_container.add_child(base_instance)
	if is_iff_flag_active():
		base_instance.set_iff_active(true)

	var wall_positions = [
		Vector2(center_x - TILE_SIZE, base_y),
		Vector2(center_x - TILE_SIZE, base_y - TILE_SIZE),
		Vector2(center_x, base_y - TILE_SIZE),
		Vector2(center_x + TILE_SIZE, base_y - TILE_SIZE),
		Vector2(center_x + TILE_SIZE, base_y)
	]

	for p in wall_positions:
		_spawn_brick_tile(base_wall_container, p, use_steel)


## 房间通关后撤掉基地和它那圈砖墙。
##
## 这不只是表现: 基地在底边中央, 它那圈砖墙占掉 [11][5..7] 和 [12][5,6,7]。
## 房间清空之后玩家要能自由走位到任意一扇门, 而这块 3x2 的实心区域正压在
## 底边中段。留着的话, 已经打完的房间里还杵着一个必须绕开的障碍, 而它此刻
## 已经没有任何玩法意义 —— 没有敌人会来打它了。
func _despawn_base() -> void:
	if base_instance and is_instance_valid(base_instance):
		# 先断信号: queue_free() 不会触发 destroyed, 但 base_eagle.gd 将来
		# 若在 _exit_tree 里补发一次, 就会在通关瞬间判负。断掉最省心。
		if base_instance.destroyed.is_connected(_on_base_destroyed):
			base_instance.destroyed.disconnect(_on_base_destroyed)
	base_instance = null
	for child in base_wall_container.get_children():
		child.queue_free()
	is_shovel_active = false
	shovel_timer = 0.0
	if not GameState.has_iff_flag:
		iff_flag_active = false
		iff_flag_timer = 0.0
	base_wall_container.modulate.a = 1.0


## 开一场房间遭遇。
##
## **刷怪逻辑一行没改**: 还是顶边三个出生点轮转、spawn_timer 按 spawn_interval
## 一波波补充、同屏上限 max_alive_cap、总量 encounter_size(battle_type, cycle)。
## 也就是说每一个战斗房都是一整场完整的坦克大战遭遇, 房间化只改变了"打完之后
## 发生什么"(开门、撤基地), 没有改变"怎么打"。
##
## 这里只负责把三个计数器归零 —— 它们原本是 start_game() 一场一次, 现在每进
## 一间没清空的房都要重来一遍。漏掉归零的话, 第二间房会带着上一间的
## enemies_spawned 进来, 于是 enemies_spawned >= total_enemies 立刻成立,
## 一只都不刷、门直接开。
func _begin_room_encounter() -> void:
	var cycle: int = GameState.get_difficulty_cycle()
	var room_size := str(GameState.current_room_data().get("size", "normal"))
	total_enemies = encounter_size(GameState.battle_type, cycle, GameState.difficulty)
	total_enemies *= int(SIEGE_ENCOUNTER_MULT.get(room_size, 1))
	spawn_interval = spawn_interval_for(GameState.battle_type, cycle, GameState.difficulty)
	max_alive_cap = max_alive_for(cycle, GameState.difficulty)
	max_alive_cap += int(SIEGE_ALIVE_BONUS.get(room_size, 0))
	enemies_spawned = 0
	enemies_alive = 0
	spawn_timer = 0.0

	# 攻城房 (size != normal 且不是护送风味) 环绕更大的地图多摆几个敌人出生点,
	# 而不是仍然只有三个点朝一个方向涌——读 CompositeRoomBuilder 的
	# enemy_spawn_count_for(), 跟拼图纸时留几个出生点缺口是同一个数字, 不会
	# 出现"地形只留了 5 个缺口, 这里却按 7 个出生点算坐标"这种两边对不上的
	# 情况。护送房不改出生点数量, 因为它的看点是保护友军而不是被围攻。
	if room_size != "normal" and not (GameState.battle_type == "challenge" and GameState.challenge_mode == "escort"):
		var spawn_count: int = CompositeRoomBuilder.enemy_spawn_count_for(room_size)
		enemy_spawn_points.clear()
		for col in RoomDoor.enemy_spawn_cols_for(GRID_W, spawn_count):
			enemy_spawn_points.append(Vector2((col + 0.5) * TILE_SIZE, 0.5 * TILE_SIZE))

	if GameState.battle_type == "challenge" and GameState.challenge_mode == "escort":
		_spawn_escort_ally(room_size)

## "escort" 挑战房: 生成 1~4 名要保护到房间清空的友军 (数量按房间尺寸看
## ESCORT_ALLY_COUNT), 阵亡过半即战败——见 _on_escort_ally_destroyed()。
## 跟老鹰基地一样是当前房间级别的临时对象, 见 escort_ally_instances 声明处
## 和 _clear_all() 里的清空注释。
func _spawn_escort_ally(room_size: String = "normal") -> void:
	if not ally_tank_scene:
		return
	var count: int = int(ESCORT_ALLY_COUNT.get(room_size, 1))
	escort_ally_original_count = count
	for i in range(count):
		var inst: AllyTank = ally_tank_scene.instantiate()
		actors_container.add_child(inst)
		inst.ally_destroyed.connect(_on_escort_ally_destroyed.bind(inst))
		# get_random_empty_tile_position() 返回的是全局坐标 (修过的坑, 见
		# CLAUDE.md "GameArea 局部/全局坐标差一格" 一节), 所以必须在
		# add_child() 之后再赋值, 不能反过来。
		var pos := get_random_empty_tile_position()
		# 多只友军挤在同一格看起来像重叠贴图, 试几次找一个离其它友军够远的
		# 位置; 找不到就用最后抽到的那个 (总比完全不生成好)。
		for _attempt in range(20):
			var too_close := false
			for other in escort_ally_instances:
				if is_instance_valid(other) and other.global_position.distance_to(pos) < TILE_SIZE * 3.0:
					too_close = true
					break
			if not too_close:
				break
			pos = get_random_empty_tile_position()
		inst.global_position = pos
		escort_ally_instances.append(inst)

## 护送房不再是"死一个就立刻输"——大/超大房间一次要保护 3~4 只友军, 玩家
## 不可能同时守在每一只身边, 全灭才判负会让稀有奖励房变成看运气的惩罚。
## 改成"过半必须存活才算成功": 剩余数量严格大于半数 (floor(n/2)+1) 才算
## 队伍还站得住, 否则判负。单只房间 (ESCORT_ALLY_COUNT["normal"]==1) 下
## floor(1/2)+1==1, 死一个就跌破门槛, 行为跟改造前"死一个即战败"完全一致;
## 4 只的房间下门槛是 3, 即最多容许损失 1 只 (3/4 > 半数), 而不是常见的
## ceil(4/2)==2 那种"刚好损失一半也算及格"的读法。
func _on_escort_ally_destroyed(instance: AllyTank) -> void:
	escort_ally_instances.erase(instance)
	var remaining := escort_ally_instances.size()
	var required := escort_ally_original_count / 2 + 1
	if remaining >= required:
		show_toast("💀 一名友军阵亡！(剩余 %d/%d)" % [remaining, escort_ally_original_count])
		add_trauma(0.4)
		hit_stop(0.05)
		return
	show_toast("💀 护送队伍损失过半！护送失败！")
	add_trauma(0.6)
	hit_stop(0.08)
	_game_over(false)

## 护送成功: 房间清空时安全撤离友军, 不算阵亡。
##
## 先断开信号再 queue_free()——目前 ally_tank.gd 的 queue_free() 本身不会
## 触发 ally_destroyed (那个信号只从 _die() 发, 而 _die() 只有 take_damage()
## 打到 0 血才会调用), 所以这条断开眼下不是必须的。留着是防将来重蹈
## base_eagle.gd 的覆辙——那边同样的信号后来在 _exit_tree() 里补发了一次,
## 导致"清空房间"和"基地被摧毁"在 queue_free 之后的那一帧混成了一件事
## (见 _despawn_base() 头上的注释)。断开信号这一步比记住"以后改 ally_tank.gd
## 时留意这个坑"更可靠。
func _despawn_escort_ally() -> void:
	for inst in escort_ally_instances:
		if inst == null or not is_instance_valid(inst):
			continue
		var bound_callable := _on_escort_ally_destroyed.bind(inst)
		if inst.ally_destroyed.is_connected(bound_callable):
			inst.ally_destroyed.disconnect(bound_callable)
		inst.queue_free()
	escort_ally_instances.clear()

func trigger_shovel(duration: float = 15.0) -> void:
	# 房间清空后基地已经撤掉了 (_despawn_base)。此时再吃到铲子不能重建它 ——
	# 那会在一间已经打完的房间正中央凭空长出一座基地和五块钢墙, 把南门重新堵上。
	if base_instance == null or not is_instance_valid(base_instance):
		show_toast("BASE ALREADY SECURED — SHOVEL UNUSED")
		return
	is_shovel_active = true
	shovel_timer = duration
	_spawn_base_and_walls(true)
	show_toast("BASE FORTIFIED WITH STEEL!")

func trigger_iff_flag(duration: float = 40.0) -> void:
	iff_flag_active = true
	iff_flag_timer = maxf(iff_flag_timer, duration)
	if base_instance and is_instance_valid(base_instance):
		if base_instance.has_method("set_iff_active"):
			base_instance.set_iff_active(true)
	show_toast("🚩 友军标识旗已生效！我方火力绝对豁免基地伤害！")

func is_iff_flag_active() -> bool:
	return iff_flag_active or ("has_iff_flag" in GameState and GameState.has_iff_flag)

func trigger_freeze(duration: float = 7.5) -> void:
	for node in actors_container.get_children():
		if node is EnemyTank:
			node.freeze(duration)
	show_toast("TIME FROZEN!")

func trigger_bomb() -> void:
	var count = 0
	for node in actors_container.get_children():
		if node is EnemyTank:
			node.take_damage(99)
			count += 1
	show_toast("BOMB TRIGGERED! %d DESTROYED" % count)

func heal_player(amount: int = 99) -> void:
	if p1_instance and is_instance_valid(p1_instance):
		p1_instance.heal(amount)
	if p2_instance and is_instance_valid(p2_instance):
		p2_instance.heal(amount)
	show_toast("❤️ 装甲全功率修复！")

var _toast_tween: Tween = null

func show_toast(msg: String) -> void:
	if hud_toast:
		hud_toast.text = msg
		hud_toast.visible = true
		if _toast_tween and _toast_tween.is_valid():
			_toast_tween.kill()
		hud_toast.modulate.a = 0.0
		_toast_tween = create_tween()
		_toast_tween.tween_property(hud_toast, "modulate:a", 1.0, 0.15)
		_toast_tween.tween_interval(2.2)
		_toast_tween.tween_property(hud_toast, "modulate:a", 0.0, 0.4)
		_toast_tween.tween_callback(func(): hud_toast.visible = false)

## 双人战役是否走"共享生命池 + 手动复活"。单人 (没有队友概念)、双人街机
## (start_game() 给它一套独立于 GameState 的本局 3/3, 跟战役存档无关)、
## 每日挑战 (单人一命) 都不受影响, 继续用原来的自动重生。
func _lives_shared() -> bool:
	return GameState.mode == GameState.GameMode.CAMPAIGN and GameState.player_count == 2


func _spawn_player(pid: int) -> void:
	var lives = p1_lives if pid == 1 else p2_lives
	if lives <= 0 or not player_scene:
		_check_defeat_condition()
		return

	var p_inst = player_scene.instantiate()
	p_inst.player_id = pid
	p_inst.position = p1_spawn_point if pid == 1 else p2_spawn_point
	p_inst.destroyed.connect(_on_player_destroyed)
	p_inst.powerup_collected.connect(func(type_name): show_toast(type_name))
	p_inst.health_changed.connect(_on_player_hp_changed)

	if pid == 1:
		p1_instance = p_inst
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			p1_instance.upgrade_tier = GameState.player_tier
	else:
		p2_instance = p_inst
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			p2_instance.upgrade_tier = GameState.p2_tier

	actors_container.add_child(p_inst)
	_update_hud()
	_update_rpg_hud()

func _update_hearts_container(container: HBoxContainer, curr: int, max_hp: int) -> void:
	if not container:
		return
	for child in container.get_children():
		child.queue_free()
	
	var full_tex = TextureHelper.get_tex("res://assets/sprites/ui/hp_heart_full.png")
	var empty_tex = TextureHelper.get_tex("res://assets/sprites/ui/hp_heart_empty.png")
	
	var count = min(max_hp, 8)
	for i in range(count):
		var tr = TextureRect.new()
		tr.custom_minimum_size = Vector2(16, 16)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = full_tex if (i < curr) else empty_tex
		container.add_child(tr)

func _on_player_hp_changed(pid: int, curr: int, max_hp: int) -> void:
	if pid == 1:
		if hud_p1_hp:
			hud_p1_hp.text = "P1 [%s]:" % _branch_tag(1)
		if hud_p1_hearts:
			_update_hearts_container(hud_p1_hearts, curr, max_hp)
	elif pid == 2:
		if hud_p2_hp:
			hud_p2_hp.text = "P2 [%s]:" % _branch_tag(2)
		if hud_p2_hearts:
			_update_hearts_container(hud_p2_hearts, curr, max_hp)

## 丛林隐匿机制:
## 树冠 (z_index=10) 默认完全遮盖下方的坦克。
## 玩家单位 (P1/P2/车厢) 进入树林时淡化该格树冠 (TREE_REVEAL_ALPHA = 0.38)，
## 使玩家看清自车位置以及与玩家处于同一树林格内的敌方伏击单位；
## 当仅有敌方处于树林中且玩家在远处时，树冠保持 100% 不透明 (a = 1.0)，
## 敌方获得完全的丛林隐匿 (Camouflage) 效果。
func _update_tree_transparency(delta: float) -> void:
	if tree_sprites.is_empty():
		return

	var occupied := {}
	var units: Array = []
	units.append_array(get_tree().get_nodes_in_group("player"))
	const HALF := 17.0
	for u in units:
		if not is_instance_valid(u) or not (u is Node2D):
			continue
		var lp: Vector2 = map_container.to_local(u.global_position)
		var c0 := int(floor((lp.x - HALF) / TILE_SIZE))
		var c1 := int(floor((lp.x + HALF) / TILE_SIZE))
		var r0 := int(floor((lp.y - HALF) / TILE_SIZE))
		var r1 := int(floor((lp.y + HALF) / TILE_SIZE))
		for c in range(c0, c1 + 1):
			for r in range(r0, r1 + 1):
				occupied[Vector2i(c, r)] = true

	for cell in tree_sprites:
		var spr = tree_sprites[cell]
		if not is_instance_valid(spr):
			continue
		var target: float = TREE_REVEAL_ALPHA if occupied.has(cell) else 1.0
		if absf(spr.modulate.a - target) < 0.004:
			spr.modulate.a = target
			continue
		spr.modulate.a = move_toward(spr.modulate.a, target, TREE_FADE_SPEED * delta)

func _process(delta: float) -> void:
	_update_camera_position()

	# Trauma Screen Shake -- 现在抖动叠加在 RoomCamera.offset 上而不是
	# GameArea.position (加了摄像机之后 GameArea.position 已经跟屏幕坐标
	# 无关, 见 _update_camera_bounds() 的推导), 减号是因为 offset 在屏幕
	# 坐标公式里前面带负号, 这样叠加出来的抖动方向、幅度才跟改造前一致。
	if trauma > 0.0:
		var shake = trauma * trauma
		var offset = Vector2(
			randf_range(-1.0, 1.0) * max_shake_offset.x * shake,
			randf_range(-1.0, 1.0) * max_shake_offset.y * shake
		)
		room_camera.offset = camera_offset_base - offset
		trauma = max(0.0, trauma - trauma_decay * delta)
	else:
		room_camera.offset = camera_offset_base

	_update_tree_transparency(delta)

	water_anim_timer += delta
	if water_anim_timer >= 0.12:
		water_anim_timer = 0.0
		if tex_water_frames.size() > 0:
			water_frame = (water_frame + 1) % tex_water_frames.size()
			var w_tex = tex_water_frames[water_frame]
			for spr in water_sprites:
				if is_instance_valid(spr):
					spr.texture = w_tex

	# ---- 分界线: 上面是纯表现 (摄像机、抖动、树冠、水面动画), 客户端照跑;
	# 下面全是权威逻辑 (计时器、刷怪、判负、复活), 客户端一律不跑 —— 那些
	# 状态由主机的快照和状态包给。
	#
	# 这条早退是整个联机改造对 main.gd 侵入最小的地方: 主机跑的仍然是和
	# 单机逐行相同的代码路径, 没有任何 "if 联机 then 换一套算法" 的分叉。
	if not NetSession.is_authority() or _net_disconnected:
		return

	_net_update_fire_edges()

	if is_shovel_active:
		shovel_timer -= delta
		if shovel_timer <= 3.0:
			base_wall_container.modulate.a = 0.4 if int(shovel_timer * 6.0) % 2 == 0 else 1.0
		if shovel_timer <= 0.0:
			is_shovel_active = false
			base_wall_container.modulate.a = 1.0
			# 钢墙到期期间房间可能已经清空并撤掉了基地; 那就别再重建一遍。
			if base_instance and is_instance_valid(base_instance):
				_spawn_base_and_walls(false)
				show_toast("BASE STEEL EXPIRED")

	if iff_flag_active and not GameState.has_iff_flag:
		iff_flag_timer -= delta
		if iff_flag_timer <= 0.0:
			iff_flag_active = false
			if base_instance and is_instance_valid(base_instance) and base_instance.has_method("set_iff_active"):
				base_instance.set_iff_active(false)
			show_toast("🚩 友军标识旗已失效")

	# Boss Health Bar Realtime Sync & Smooth Fade
	if active_boss_instance:
		if is_instance_valid(active_boss_instance) and hud_boss_fill:
			hud_boss_fill.value = active_boss_instance.health
		else:
			active_boss_instance = null
			if hud_boss_bar and hud_boss_bar.visible:
				if hud_boss_fade_tween and hud_boss_fade_tween.is_valid():
					hud_boss_fade_tween.kill()
				hud_boss_fade_tween = create_tween()
				var tw = hud_boss_fade_tween
				tw.tween_property(hud_boss_bar, "modulate:a", 0.0, 0.45)
				tw.tween_callback(func():
					hud_boss_bar.visible = false
					hud_boss_bar.modulate.a = 1.0
				)

	if _lives_shared() and not is_game_over and not is_victory and not get_tree().paused:
		# 边沿由 _net_update_fire_edges() 每帧统一算 —— 联机时 2 号玩家的
		# 开火键在客户端手里, 直接读本地 Input 的话客户端永远复活不了自己。
		if p1_awaiting_revive and bool(_net_fire_edge[1]):
			_consume_shared_life_and_respawn(1)
		if p2_awaiting_revive and bool(_net_fire_edge[2]):
			_consume_shared_life_and_respawn(2)

	if is_game_over or is_victory:
		if Input.is_action_just_pressed("restart"):
			_on_button_action()
		return

	if is_bomb_rain_active:
		bomb_rain_timer += delta
		if bomb_rain_timer >= bomb_rain_interval:
			bomb_rain_timer = 0.0
			bomb_rain_interval = randf_range(3.8, 6.0)
			_spawn_falling_bomb()

	if enemies_spawned < total_enemies and enemies_alive < max_alive_cap:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_request_spawn_enemy()

func _spawn_falling_bomb() -> void:
	var col = randi_range(1, 11)
	var row = randi_range(1, 10)
	if row >= 10 and col >= 4 and col <= 8:
		row = randi_range(1, 8)
	var target_pos = Vector2((col + 0.5) * TILE_SIZE, (row + 0.5) * TILE_SIZE)
	var bomb_hazard = FallingBombHazard.new()
	bomb_hazard.position = target_pos
	actors_container.add_child(bomb_hazard)

## Power tier -> earliest per-act floor_idx it's allowed to roll on. Applied
## uniformly to the battle/elite/boss tables in _request_spawn_enemy() below
## so "harder" encounter types can't front-load an early elite/boss node with
## enemies the player has no counterplay for yet. Types absent from this dict
## (BASIC, FAST, ARMOR/DESERT/WARP, TRAIN_BOSS, BOSS) are unrestricted --
## the themed types are act signatures gated by _band_pool()/act instead.
##
## Tiers are grouped by actual mechanic, not just raw stats:
##   Floor 1 -- tankier/faster reskins of the basic direct-fire loop, nothing
##              new to read (POWER: 2hp+faster bullet, SUICIDE: no gun, just
##              a fast contact-detonate rush, ARMOR: 4hp sponge).
##   Floor 3 -- BOMBER: still direct threat, but adds a timed-delay AoE the
##              player has to track after the enemy has already moved on.
##   Floor 5 -- genuinely new counterplay required: AIRCRAFT ignores every
##              wall/water tile on the map (ex-Floor-1 bug -- it used to be
##              gated as if it were a plain reskin, which is why it could
##              show up in Act 1), MIRAGE turns invisible, BATTLESHIP/LASER
##              hit in an AoE/piercing line instead of a single bullet.
##   Floor 8 -- MISSILE/WARP: off-screen-telegraphed AoE strikes and
##              teleporting mobility -- the actual "boss-adjacent" tier.
const ENEMY_MIN_FLOOR: Dictionary = {
	EnemyTank.EnemyType.POWER: 1,
	EnemyTank.EnemyType.SUICIDE: 1,
	EnemyTank.EnemyType.ARMOR: 1,
	EnemyTank.EnemyType.SHOTGUN: 2,
	EnemyTank.EnemyType.HUNTER: 2,
	EnemyTank.EnemyType.BOMBER: 3,
	EnemyTank.EnemyType.ENGINEER: 3,
	EnemyTank.EnemyType.FLAMETHROWER: 3,
	EnemyTank.EnemyType.FIREWALL: 3,
	EnemyTank.EnemyType.TRENCH: 3,
	EnemyTank.EnemyType.SNIPER: 4,
	EnemyTank.EnemyType.GATLING: 4,
	EnemyTank.EnemyType.SPIDER: 4,
	EnemyTank.EnemyType.SANDWORM: 4,
	EnemyTank.EnemyType.CANNON: 4,
	EnemyTank.EnemyType.TESLA: 4,
	EnemyTank.EnemyType.TOXIC: 4,
	EnemyTank.EnemyType.AIRCRAFT: 5,
	EnemyTank.EnemyType.MIRAGE: 5,
	EnemyTank.EnemyType.BATTLESHIP: 5,
	EnemyTank.EnemyType.LASER: 5,
	EnemyTank.EnemyType.CRUSHER: 5,
	EnemyTank.EnemyType.BULLDOZER: 5,
	EnemyTank.EnemyType.SPLITTER: 5,
	EnemyTank.EnemyType.DRONE_CARRIER: 6,
	EnemyTank.EnemyType.DRONE_MINI: 6,
	EnemyTank.EnemyType.MISSILE: 8,
	EnemyTank.EnemyType.WARP: 8,
}

## 被门禁挡下时的替补名单, 按解锁顺序排列。
##
## 刻意不含 BOSS / TRAIN_BOSS (它们是遭遇身份, 不是填充兵) 和 DESERT
## (第 2 幕的招牌轮廓, 走 themed_type 那条豁免路径)。
const GATE_FALLBACK_POOL: Array = [
	EnemyTank.EnemyType.BASIC, EnemyTank.EnemyType.FAST,
	EnemyTank.EnemyType.POWER, EnemyTank.EnemyType.SUICIDE, EnemyTank.EnemyType.ARMOR,
	EnemyTank.EnemyType.SHOTGUN, EnemyTank.EnemyType.HUNTER,
	EnemyTank.EnemyType.BOMBER, EnemyTank.EnemyType.ENGINEER, EnemyTank.EnemyType.FLAMETHROWER, EnemyTank.EnemyType.FIREWALL, EnemyTank.EnemyType.TRENCH,
	EnemyTank.EnemyType.SNIPER, EnemyTank.EnemyType.GATLING, EnemyTank.EnemyType.SPIDER, EnemyTank.EnemyType.SANDWORM, EnemyTank.EnemyType.CANNON,
	EnemyTank.EnemyType.TESLA, EnemyTank.EnemyType.TOXIC,
	EnemyTank.EnemyType.AIRCRAFT, EnemyTank.EnemyType.MIRAGE,
	EnemyTank.EnemyType.BATTLESHIP, EnemyTank.EnemyType.LASER,
	EnemyTank.EnemyType.CRUSHER, EnemyTank.EnemyType.BULLDOZER, EnemyTank.EnemyType.SPLITTER,
	EnemyTank.EnemyType.DRONE_CARRIER,
	EnemyTank.EnemyType.MISSILE, EnemyTank.EnemyType.WARP,
]

func _gate_enemy_type(type: EnemyTank.EnemyType, floor_idx: int) -> EnemyTank.EnemyType:
	if floor_idx >= ENEMY_MIN_FLOOR.get(type, 0):
		return type
	# 以前这里一律砸成 FAST, 结果是 roll 表写的花样全是假的: floor 3 的表列了
	# 8 个条目, 其中 MIRAGE/AIRCRAFT/MISSILE/BATTLESHIP/LASER 五个都还没解锁,
	# 于是实测 62% 的敌人是 FAST —— 读代码像是花样最多的一层, 玩起来是全局最
	# 单调的一层, 甚至比 floor 2 (56%) 还单调。
	#
	# 改成在**当层已解锁**的填充兵里重摇: 门禁的本意是"这个机制还没到时候",
	# 不是"那就给你最便宜的那只"。槽位该有的分量保住了, 未解锁的机制也仍然
	# 出不来。
	var unlocked: Array = []
	for t in GATE_FALLBACK_POOL:
		if floor_idx >= ENEMY_MIN_FLOOR.get(t, 0):
			unlocked.append(t)
	if unlocked.is_empty():
		return EnemyTank.EnemyType.BASIC
	return unlocked[randi() % unlocked.size()]

func _request_spawn_enemy() -> void:
	if enemies_spawned >= total_enemies or enemy_spawn_points.is_empty():
		return

	var spawn_idx = enemies_spawned % enemy_spawn_points.size()
	var spawn_pos = enemy_spawn_points[spawn_idx]
	var is_bonus = (enemies_spawned in [3, 10, 17])
	
	var type = EnemyTank.EnemyType.BASIC
	var r = randf()
	var floor_idx = GameState.current_floor

	# Terrain-themed "signature" enemy slot -- kept to one type per act so a
	# new silhouette (not a hidden stat buff) is what signals "this act is
	# different": Act1 plains/rivers get no special terrain tank (falls back
	# to ARMOR, already this table's default filler), Act2 desert maps get
	# DESERT, Act3 glacial/warp maps get WARP. Previously DESERT was tied
	# only to floor_idx==2 with no act check, so it could spawn on Act1/Act3
	# maps that have no desert tiles at all.
	var themed_type = EnemyTank.EnemyType.ARMOR
	match GameState.get_visual_act():
		2: themed_type = EnemyTank.EnemyType.DESERT
		3: themed_type = EnemyTank.EnemyType.WARP

	var has_water = false
	if current_map_layout and current_map_layout.size() > 0:
		for row in current_map_layout:
			if 3 in row:
				has_water = true
				break

	if GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
		# Uniformly random across the whole roster, no floor-tier gate --
		# unpredictability is the entire point of "random enemies" here,
		# not a curated ramp-up like the campaign floors get.
		var all_types = EnemyTank.EnemyType.values()
		type = all_types[randi() % all_types.size()]
	elif GameState.battle_type == "boss":
		if enemies_spawned == 0:
			# 一幕一主 Boss, 不再是硬币赌命: 每个视觉主题 (get_visual_act(),
			# 1-3, 12 幕循环 3 轮) 各自固定一只专属 Boss, 血量/机动/地图三者
			# 严丝合缝。以前这里是每幕再掷一次硬币, 50%/40%/40% 概率被
			# TITAN_BOSS (16 血, 该表里第二硬) 顶替, 于是 Act 1 有一半局会在
			# 玩家还只有 1~3 格血、伤害 1 点时撞上终局级数值, 且 TITAN 三幕
			# 轮流串场把 SCORPION/MAMMOTH 各自的主题辨识度稀释掉了。
			#
			# TITAN_BOSS 改用 get_difficulty_cycle() (0 = 第 1~3 幕, 1+ = 第
			# 4 幕起的每一轮重复周目) 而不是 get_visual_act() 的 `_` 分支 ——
			# 后者永远落在 1/2/3 之内 (12 幕循环 3 个主题), 那条 `_` 分支其实
			# 是从未被执行过的死代码, 之前"Act 4+ 100% Titan"根本没有真的发生
			# 过。地图侧的匹配见 map_templates.gd::get_layout_for_stage()。
			if GameState.get_difficulty_cycle() >= 1:
				type = EnemyTank.EnemyType.TITAN_BOSS
				show_toast("⚡ DREADNOUGHT TITAN FORTRESS DETECTED! ⚡")
			else:
				match GameState.get_visual_act():
					1:
						type = EnemyTank.EnemyType.BOSS
						show_toast("👑 WARLORD SUPER-TANK DETECTED! 👑")
					2:
						type = EnemyTank.EnemyType.SCORPION_BOSS
						show_toast("🦂 DESERT SCORPION MECH DETECTED! 🦂")
					3:
						type = EnemyTank.EnemyType.MAMMOTH_BOSS
						show_toast("❄️ GLACIAL MAMMOTH MECH DETECTED! ❄️")
			add_trauma(0.50)
		elif r < 0.10: type = EnemyTank.EnemyType.AIRCRAFT
		elif r < 0.20: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.SUICIDE
		elif r < 0.30: type = EnemyTank.EnemyType.MIRAGE
		elif r < 0.40: type = EnemyTank.EnemyType.GATLING
		elif r < 0.50: type = EnemyTank.EnemyType.SNIPER
		elif r < 0.60: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.70: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.78: type = EnemyTank.EnemyType.CRUSHER
		elif r < 0.86: type = EnemyTank.EnemyType.SPLITTER
		elif r < 0.92: type = EnemyTank.EnemyType.LASER
		else: type = EnemyTank.EnemyType.WARP if GameState.get_visual_act() == 3 else EnemyTank.EnemyType.POWER
	elif GameState.battle_type == "elite":
		if enemies_spawned == 0:
			type = EnemyTank.EnemyType.TRAIN_BOSS
			show_toast("🚂 ELITE ARMORED CONVOY DETECTED! 🚂")
			add_trauma(0.50)
		elif r < 0.12: type = EnemyTank.EnemyType.AIRCRAFT
		elif r < 0.22: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.SUICIDE
		elif r < 0.32: type = EnemyTank.EnemyType.MIRAGE
		elif r < 0.42: type = EnemyTank.EnemyType.FLAMETHROWER
		elif r < 0.52: type = EnemyTank.EnemyType.GATLING
		elif r < 0.62: type = EnemyTank.EnemyType.SNIPER
		elif r < 0.70: type = EnemyTank.EnemyType.CANNON
		elif r < 0.76: type = EnemyTank.EnemyType.TRENCH
		elif r < 0.81: type = EnemyTank.EnemyType.CRUSHER
		elif r < 0.86: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.91: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.96: type = EnemyTank.EnemyType.LASER
		else: type = themed_type
	else:
		match floor_idx:
			0:
				type = EnemyTank.EnemyType.BASIC if r < 0.65 else EnemyTank.EnemyType.FAST
			1:
				if r < 0.30: type = EnemyTank.EnemyType.BASIC
				elif r < 0.60: type = EnemyTank.EnemyType.FAST
				elif r < 0.80: type = EnemyTank.EnemyType.POWER
				elif r < 0.92: type = EnemyTank.EnemyType.SUICIDE
				else: type = EnemyTank.EnemyType.AIRCRAFT
			2:
				if r < 0.20: type = themed_type
				elif r < 0.35: type = EnemyTank.EnemyType.FAST
				elif r < 0.48: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.60: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.72: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.82: type = EnemyTank.EnemyType.BOMBER
				elif r < 0.90: type = EnemyTank.EnemyType.AIRCRAFT
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.ARMOR
			3:
				if r < 0.08: type = EnemyTank.EnemyType.ARMOR
				elif r < 0.15: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.22: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.30: type = EnemyTank.EnemyType.TRENCH
				elif r < 0.38: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.46: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.54: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.63: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.72: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.81: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.90: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			4:
				if r < 0.05: type = EnemyTank.EnemyType.ARMOR
				elif r < 0.10: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.15: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.20: type = EnemyTank.EnemyType.TRENCH
				elif r < 0.25: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.30: type = EnemyTank.EnemyType.SPIDER
				elif r < 0.35: type = EnemyTank.EnemyType.SANDWORM
				elif r < 0.40: type = EnemyTank.EnemyType.CANNON
				elif r < 0.46: type = EnemyTank.EnemyType.TESLA
				elif r < 0.52: type = EnemyTank.EnemyType.TOXIC
				elif r < 0.58: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.64: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.70: type = EnemyTank.EnemyType.GATLING
				elif r < 0.76: type = EnemyTank.EnemyType.SNIPER
				elif r < 0.82: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.88: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.94: type = EnemyTank.EnemyType.SUICIDE
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			_:
				# floor 5 以后全阵容展开: DRONE_CARRIER, TESLA, TOXIC, SPLITTER, CRUSHER, ENGINEER, SPIDER, FIREWALL, HUNTER, SANDWORM, CANNON, GATLING 等。
				if r < 0.04: type = EnemyTank.EnemyType.DRONE_CARRIER
				elif r < 0.08: type = EnemyTank.EnemyType.TESLA
				elif r < 0.12: type = EnemyTank.EnemyType.TOXIC
				elif r < 0.16: type = EnemyTank.EnemyType.SPLITTER
				elif r < 0.19: type = EnemyTank.EnemyType.CRUSHER
				elif r < 0.22: type = EnemyTank.EnemyType.BULLDOZER
				elif r < 0.25: type = EnemyTank.EnemyType.TRENCH
				elif r < 0.29: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.33: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.37: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.41: type = EnemyTank.EnemyType.SPIDER
				elif r < 0.46: type = EnemyTank.EnemyType.SANDWORM
				elif r < 0.51: type = EnemyTank.EnemyType.CANNON
				elif r < 0.57: type = EnemyTank.EnemyType.GATLING
				elif r < 0.63: type = EnemyTank.EnemyType.SNIPER
				elif r < 0.69: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.74: type = EnemyTank.EnemyType.BATTLESHIP
				elif r < 0.79: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.85: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.91: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.96: type = EnemyTank.EnemyType.SUICIDE
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER

	# Floor-gate the roll above -- the boss/elite tables (unlike the plain
	# "battle" one) never checked floor_idx, so an early Act1 elite fight
	# (first possible around floor_idx 4) could roll a MISSILE/BOMBER truck
	# well before the player has any counterplay for it. TRAIN_BOSS/BOSS and
	# the current act's themed_type are exempt -- they're encounter identity
	# (the elite's boss escort, the act finale, the act's signature silhouette),
	# not power-tier filler.
	if GameState.mode != GameState.GameMode.DAILY_CHALLENGE and not (type in [EnemyTank.EnemyType.TRAIN_BOSS, EnemyTank.EnemyType.BOSS, EnemyTank.EnemyType.TITAN_BOSS, EnemyTank.EnemyType.SCORPION_BOSS, EnemyTank.EnemyType.MAMMOTH_BOSS]) and type != themed_type:
		type = _gate_enemy_type(type, floor_idx)

	var spawn_index = enemies_spawned
	var star = spawnstar_scene.instantiate()
	star.position = spawn_pos
	star.finished.connect(func(): _instantiate_enemy(spawn_pos, type, is_bonus, spawn_index))
	actors_container.add_child(star)

	enemies_spawned += 1
	enemies_alive += 1
	_update_hud()

func _instantiate_enemy(pos: Vector2, type: EnemyTank.EnemyType, is_bonus: bool, spawn_index: int) -> void:
	if not enemy_scene:
		return
	var enemy = enemy_scene.instantiate()
	enemy.position = pos
	enemy.enemy_type = type
	enemy.is_bonus = is_bonus
	enemy.set_meta("enemy_spawn_index", spawn_index)
	enemy.enemy_destroyed.connect(func(pts, bonus, drop_p):
		check_key_drop_enemy(enemy, drop_p)
		_on_enemy_destroyed(pts, bonus, drop_p)
	)
	actors_container.add_child(enemy)

	if type in [EnemyTank.EnemyType.BOSS, EnemyTank.EnemyType.TRAIN_BOSS, EnemyTank.EnemyType.TITAN_BOSS, EnemyTank.EnemyType.SCORPION_BOSS, EnemyTank.EnemyType.MAMMOTH_BOSS]:
		active_boss_instance = enemy
		if hud_boss_bar and hud_boss_fill and hud_boss_label:
			# 上一只 boss 的死亡淡出可能还没跑完就轮到这只刷出来 (TRAIN_BOSS
			# 常规填怪尤其常见); 不 kill 掉残留 tween 的话它会在几百毫秒后把
			# 这只活着的 boss 的血条又淡出并隐藏掉, 见 hud_boss_fade_tween 声明处。
			if hud_boss_fade_tween and hud_boss_fade_tween.is_valid():
				hud_boss_fade_tween.kill()
				hud_boss_fade_tween = null
			hud_boss_bar.visible = true
			hud_boss_bar.modulate.a = 1.0
			var b_name = "👑 SUMMIT COLOSSUS FORTRESS"
			match type:
				EnemyTank.EnemyType.BOSS: b_name = "👑 SUMMIT COLOSSUS FORTRESS"
				EnemyTank.EnemyType.TRAIN_BOSS: b_name = "🚂 ARMORED TRAIN FORTRESS"
				EnemyTank.EnemyType.TITAN_BOSS: b_name = "⚡ DREADNOUGHT TITAN FORTRESS"
				EnemyTank.EnemyType.SCORPION_BOSS: b_name = "🦂 DESERT SCORPION MECH"
				EnemyTank.EnemyType.MAMMOTH_BOSS: b_name = "❄️ GLACIAL MAMMOTH MECH"
			hud_boss_label.text = b_name
			hud_boss_fill.max_value = enemy.max_health
			hud_boss_fill.value = enemy.health

func _on_enemy_destroyed(points: int, is_bonus: bool, drop_pos: Vector2) -> void:
	score += points
	enemies_alive -= 1
	SoundManager.play_explosion(get_tree())
	if is_bonus or GameState.battle_type != "battle":
		add_trauma(0.40)
		hit_stop(0.04)
	else:
		add_trauma(0.20)
	_update_hud()

	if is_bonus and powerup_scene:
		var p_inst = powerup_scene.instantiate()
		var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB, PowerUp.Type.PISTON, PowerUp.Type.IFF_FLAG]
		types.shuffle()
		p_inst.setup(types[0])
		# drop_pos 来自 enemy.gd 的 enemy_destroyed 信号, 是全局坐标
		# (enemy_destroyed.emit(score_value, is_bonus, global_position)),
		# 直接赋 position(局部)会让掉落道具落在死亡敌人右下方一格。
		p_inst.position = actors_container.to_local(drop_pos)
		actors_container.call_deferred("add_child", p_inst)
		show_toast("BONUS ITEM DROPPED!")

	if enemies_spawned >= total_enemies and enemies_alive <= 0:
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			_on_room_cleared()
		else:
			# 街机/每日挑战没有房间, 打完就是打完 —— 保持原来的行为。
			_game_over(true)


## 本房间清空。这是以撒的核心节拍: 门开 -> 可以走 -> 只有 boss 房清空才算过层。
##
## 注意"清空一间房"和"打赢一场仗"在这里被拆开了。原来两者是同一件事, 所以
## _on_enemy_destroyed() 直接调 _game_over(true); 现在绝大多数房间清空只是
## 开个门, 结算界面一层楼只出现一次。
func _on_room_cleared() -> void:
	if room_cleared_pending:
		return
	room_cleared_pending = true

	GameState.mark_room_cleared(GameState.current_room, true)
	# 先撤基地再开门: 基地那一坨压在底边中段, 撤掉之后玩家才能顺畅走到南门。
	_despawn_base()
	_despawn_escort_ally()
	_open_doors()
	_refresh_minimap()
	SoundManager.play_victory(get_tree())

	_grant_room_clear_reward()
	# 清房改了一大票状态: 房间标记为已清、门开了、掉了奖励、难度曲线的
	# rooms_cleared 也进了一格。客户端的门要跟着开, 小地图要跟着变色。
	_net_push_campaign()

	if GameState.is_floor_complete():
		# boss 房清空 = 这一层打通。走原来的胜利结算, 由 _on_button_action()
		# 决定是进下一幕还是通关。
		_game_over(true)
	else:
		show_toast("★ 房间肃清 —— 门已打开 ★")
	_update_hud()


## 清房奖励。以撒清房会掉心/钱/炸弹; 这里沿用本作已有的掉落物, 不引入新道具。
##
## 概率而非必掉: 必掉的话玩家会把每一间房都清干净当作纯收益, "要不要绕过这间
## 房"就不再是决策 —— 而房间制的整个意义就是让玩家能选择跳过。
func _grant_room_clear_reward() -> void:
	var room := GameState.current_room_data()
	var r := randf()
	var drop_pos := Vector2((GRID_W / 2.0) * TILE_SIZE, (GRID_H / 2.0 - 2.0) * TILE_SIZE)

	if str(room.get("type", "")) == "boss":
		return # boss 房走胜利结算, 不额外掉

	if r < 0.35 and powerup_scene:
		var p_inst = powerup_scene.instantiate()
		# 同上 (见宝藏房奖励那处注释): 补齐 MISSILE/TIMED_BOMB, 房间奖励不该是
		# 这两种道具唯一发现不了的死角。
		var types = [PowerUp.Type.STAR, PowerUp.Type.HELMET, PowerUp.Type.LIFE, PowerUp.Type.CLOCK, PowerUp.Type.SHOVEL, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB, PowerUp.Type.PISTON, PowerUp.Type.IFF_FLAG]
		types.shuffle()
		p_inst.setup(types[0])
		p_inst.position = drop_pos
		actors_container.call_deferred("add_child", p_inst)
	elif r < 0.75:
		var coin_scene = load("res://scenes/gold_coin.tscn")
		if coin_scene:
			for i in range(randi_range(1, 3)):
				var coin = coin_scene.instantiate()
				coin.position = drop_pos + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
				actors_container.call_deferred("add_child", coin)

func _on_player_destroyed(pid: int) -> void:
	SoundManager.play_explosion(get_tree())
	add_trauma(0.60)
	hit_stop(0.06)

	var death_pos = Vector2(6.5 * TILE_SIZE, 11.5 * TILE_SIZE)
	if pid == 1 and p1_instance and is_instance_valid(p1_instance):
		death_pos = p1_instance.global_position
	elif pid == 2 and p2_instance and is_instance_valid(p2_instance):
		death_pos = p2_instance.global_position

	# 1. Reset Tank Upgrades to Base Scout Tier on Death
	if pid == 1:
		GameState.player_tier = 0
	else:
		GameState.p2_tier = 0

	if _lives_shared():
		# 共享生命池: 死亡本身不扣命、不自动重生 —— 扣命发生在玩家自己按开火键
		# 复活的那一刻 (_consume_shared_life_and_respawn), 死亡只是排到"等按键"
		# 的队列里。延迟只是给爆炸特效留时间, 跟原来自动重生前的停顿一致。
		get_tree().create_timer(SHARED_REVIVE_DELAY).timeout.connect(func(): _arm_revive_prompt(pid))
	elif pid == 1:
		p1_lives -= 1
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.player_lives = p1_lives
		if p1_lives > 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _spawn_player(1))
	else:
		p2_lives -= 1
		if p2_lives > 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _spawn_player(2))

	# 2. Gold Penalty & Death Coin Drop
	var current_gold = rpg_mgr.gold if rpg_mgr else 0
	var lost_gold = int(current_gold * 0.35)
	if lost_gold > 0:
		rpg_mgr.spend_gold(lost_gold)
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			rpg_mgr.sync_to_game_state()

		var coin_scene = load("res://scenes/gold_coin.tscn")
		if coin_scene and actors_container:
			var coin_count = mini(4, max(1, lost_gold / 25))
			for i in range(coin_count):
				var coin = coin_scene.instantiate()
				var offset = Vector2(randf_range(-28.0, 28.0), randf_range(-28.0, 28.0))
				# death_pos 是坦克的全局坐标; add_child 是 deferred 的,
				# 提前赋 global_position 会在节点入树前退化成 position,
				# 死亡掉的金币画在坦克右下方一格。
				coin.position = actors_container.to_local(death_pos + offset)
				actors_container.call_deferred("add_child", coin)

	show_toast("⚠️ P%d 战车损毁！装甲星级重置，损失 %dG 金币！" % [pid, lost_gold])

	_update_hud()
	_update_rpg_hud()
	_check_defeat_condition()

## 共享生命池死亡延迟结束: 该玩家仍然没有坦克的话, 挂出"按开火键复活"的提示。
## 池子已经空了就没什么好等的, 直接走一遍失败判定 (处理"队友先把最后一条命
## 花掉了"这种情况)。
func _arm_revive_prompt(pid: int) -> void:
	if is_game_over or is_victory:
		return
	if pid == 1 and p1_instance and is_instance_valid(p1_instance):
		return
	if pid == 2 and p2_instance and is_instance_valid(p2_instance):
		return
	if p1_lives <= 0:
		_check_defeat_condition()
		return
	if pid == 1:
		p1_awaiting_revive = true
	else:
		p2_awaiting_revive = true
	_update_revive_prompt()


## 死亡玩家按下自己的开火键触发的手动复活。顺序很关键: 先在生命值还没扣减
## 时调用 _spawn_player() (它自己有 lives <= 0 的守卫), 花的是"这一条"命,
## 花完之后再扣减 —— 花最后一条命也应该能复活这一次, 只是复活之后没有下一次
## 了。p1_lives/p2_lives 全程保持镜像相等, 这样 _check_defeat_condition() 才
## 不需要改。
func _consume_shared_life_and_respawn(pid: int) -> void:
	if p1_lives <= 0:
		_check_defeat_condition()
		return
	if pid == 1:
		p1_awaiting_revive = false
	else:
		p2_awaiting_revive = false
	_spawn_player(pid)
	p1_lives -= 1
	p2_lives -= 1
	GameState.player_lives = p1_lives
	_update_revive_prompt()


## 用 HUD 中央那条 (hud_status, 平时只有胜利/失败结算用它, 对局中一直隐藏)
## 显示"谁在等复活 + 剩余共享生命"。非共享模式下什么都不做。
func _update_revive_prompt() -> void:
	if not _lives_shared():
		return
	if is_game_over or is_victory:
		return
	if not p1_awaiting_revive and not p2_awaiting_revive:
		hud_status.visible = false
		return
	var lines: Array[String] = []
	if p1_awaiting_revive:
		lines.append("P1 阵亡 —— 按开火键复活 (REVIVE)")
	if p2_awaiting_revive:
		lines.append("P2 阵亡 —— 按开火键复活 (REVIVE)")
	lines.append("剩余共享生命 SHARED LIVES: %d" % p1_lives)
	hud_status.text = "\n".join(lines)
	hud_status.visible = true


func _check_defeat_condition() -> void:
	if GameState.player_count == 1:
		if p1_lives <= 0 and (p1_instance == null or not is_instance_valid(p1_instance)):
			_game_over(false)
	else:
		var p1_dead = (p1_lives <= 0 and (p1_instance == null or not is_instance_valid(p1_instance)))
		var p2_dead = (p2_lives <= 0 and (p2_instance == null or not is_instance_valid(p2_instance)))
		if p1_dead and p2_dead:
			_game_over(false)

func _on_base_destroyed() -> void:
	add_trauma(0.85)
	hit_stop(0.08)
	_game_over(false)

## Factory map building: doubles this battle's earned gold if at least one
## Factory instance survived to the end, halves it if every Factory on the
## map was destroyed. No-op if the map had no Factory. Applies to
## battle_gold_earned -- everything earned this battle, including any
## mission-completion bonus already granted above -- not the player's full
## running gold total.
##
## Used to also double/halve rpg_mgr.xp_earned_this_battle. That field is
## gone -- leveling no longer comes from an XP pool at all, only from eating
## a STAR power-up (RPGManager.add_level(), see player.gd::apply_powerup())
## -- so there is nothing left for this building to multiply on that side.
func _apply_factory_reward_multiplier() -> void:
	if factory_instances.is_empty() or not rpg_mgr:
		return

	var any_factory_alive = false
	for f in factory_instances:
		if is_instance_valid(f):
			any_factory_alive = true
			break

	var mult = 2.0 if any_factory_alive else 0.5
	var gold_delta = int(round(battle_gold_earned * (mult - 1.0)))

	if gold_delta != 0:
		rpg_mgr.gold = maxi(0, rpg_mgr.gold + gold_delta)
		rpg_mgr.gold_changed.emit(rpg_mgr.gold)

	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()

	if any_factory_alive:
		show_toast("🏭 工厂保存完好！本局奖励翻倍！")
	else:
		show_toast("🏭 工厂被摧毁！本局奖励减半！")

func _create_modal_stat_row(icon_path: String, text_str: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex = TextureHelper.get_tex(icon_path)
	if tex:
		icon_rect.texture = tex
	hbox.add_child(icon_rect)

	var lbl = Label.new()
	lbl.text = text_str
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.85))
	hbox.add_child(lbl)

	return hbox

func _game_over(victory: bool) -> void:
	if is_game_over or is_victory:
		return

	# 主机把结果推给客户端。客户端自己永远不会走到这里 (判负/判胜的逻辑
	# 都在权威侧), 它是被 _on_net_match_ended() 叫进来的, 而那条路上
	# NetSession.is_host() 为假, 不会再回声一次。
	if NetSession.is_host():
		var net := get_node_or_null("/root/Net")
		if net:
			net.end_match(victory, score)

	p1_awaiting_revive = false
	p2_awaiting_revive = false

	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()
		GameState.player_lives = p1_lives
		if p1_instance and is_instance_valid(p1_instance):
			GameState.player_tier = p1_instance.upgrade_tier
		if p2_instance and is_instance_valid(p2_instance):
			GameState.p2_tier = p2_instance.upgrade_tier

	var btn_action_text = "CONTINUE"
	var modal_title_str = ""
	var modal_desc_str = ""

	if victory:
		is_victory = true
		SoundManager.play_victory(get_tree())
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			var campaign_complete = false
			if GameState.battle_type == "boss":
				if GameState.current_act < GameState.max_acts:
					modal_title_str = "🏆 ACT %d CONQUERED! 🏆" % GameState.current_act
					modal_desc_str = "%s 要塞已彻底肃清攻克！" % GameState.get_act_name(GameState.current_act)
					btn_action_text = "PROCEED TO ACT %d ->" % (GameState.current_act + 1)
				else:
					modal_title_str = "👑 GRAND VICTORY! 👑"
					modal_desc_str = "全部 %d 大战役关卡通关！传奇战车指挥官！" % GameState.max_acts
					btn_action_text = "RETURN TO TITLE"
					campaign_complete = true
			elif GameState.battle_type == "challenge":
				# 以前这里还发 +100 XP; 升级已经不吃经验条了 (见 rpg_manager.gd
				# ::add_level() 头上的注释), 折算进金币里而不是白白消失。
				add_gold(250)
				modal_title_str = "🏆 CHALLENGE COMPLETE! 🏆"
				modal_desc_str = "战术极限挑战大成功！额外斩获 +250G！"
				btn_action_text = "CONTINUE CLIMBING"
			else:
				modal_title_str = "★ SECTOR SECURED ★"
				modal_desc_str = "当前战区敌对势力全数歼灭！防线稳固！"
				btn_action_text = "CONTINUE CLIMBING"

			_apply_factory_reward_multiplier()

			if campaign_complete:
				GameState.delete_saved_game()
			else:
				GameState.save_campaign()
		elif GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
			# Only reachable by actually clearing all 99 enemies without dying --
			# still counts as a (very impressive) score submission.
			var is_record = GameState.submit_daily_score(score)
			modal_title_str = "🏆 DAILY CHALLENGE CLEARED! 🏆"
			modal_desc_str = "今日挑战被你打穿了！最终得分 %06d%s" % [score, "（新纪录！）" if is_record else ""]
			btn_action_text = "RETURN TO TITLE"
		else:
			modal_title_str = "★ STAGE CLEARED ★"
			modal_desc_str = "双人街机模式本关肃清！"
			btn_action_text = "PLAY AGAIN"
	else:
		is_game_over = true
		SoundManager.play_game_over(get_tree())
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.delete_saved_game()
		if GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
			var is_record = GameState.submit_daily_score(score)
			modal_title_str = "☠️ DAILY CHALLENGE OVER ☠️"
			modal_desc_str = "今日挑战结束，最终得分 %06d%s" % [score, "（新纪录！）" if is_record else "（今日最高分 %06d）" % GameState.get_daily_best_score()]
			btn_action_text = "RETURN TO TITLE"
		else:
			modal_title_str = "DEFEAT (防线陷落)"
			modal_desc_str = "基地要塞被敌军重炮摧毁或战车全毁！"
			btn_action_text = "RETURN TO MENU"

	_log_battle_result(victory)

	if victory_modal_root:
		victory_modal_root.visible = true
		for c in victory_modal_stats.get_children():
			c.queue_free()

		var row_score = _create_modal_stat_row("res://assets/sprites/ui/ui_icon_score_trophy.png", "战役总得分 (Score): %06d" % score)
		var row_kills = _create_modal_stat_row("res://assets/sprites/ui/ui_icon_enemy_radar.png", "歼灭敌军数量 (Kills): %d 辆" % enemies_spawned)
		var row_gold = _create_modal_stat_row("res://assets/sprites/ui/ui_badge_gold.png", "战役缴获黄金 (Gold): %d G" % battle_gold_earned)
		victory_modal_stats.add_child(row_score)
		victory_modal_stats.add_child(row_kills)
		victory_modal_stats.add_child(row_gold)

		if victory:
			victory_modal_banner.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_banner_victory.png")
			victory_modal_title.text = modal_title_str
			victory_modal_title.modulate = Color(1.0, 0.90, 0.35)
			victory_modal_desc.text = modal_desc_str
			UIThemeHelper.apply_icon_button(victory_modal_button, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(24, 24))
			victory_modal_button.text = btn_action_text
		else:
			victory_modal_banner.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_banner_gameover.png")
			victory_modal_title.text = modal_title_str
			victory_modal_title.modulate = Color(0.95, 0.35, 0.35)
			victory_modal_desc.text = modal_desc_str
			UIThemeHelper.apply_icon_button(victory_modal_button, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(24, 24))
			victory_modal_button.text = btn_action_text
	else:
		hud_status.text = modal_title_str + "\n" + modal_desc_str
		hud_status.visible = true
		btn_restart.text = btn_action_text
		btn_restart.visible = true

## 每打完一场就往 logs/balance/battle_result.jsonl 追加一行。
##
## 探针 (tools/probe_balance_report.gd) 量的是**理论值**: 敌人刷出来多少血、
## 期望掉多少金。这里量的是**实机值**: 这一场实际花了多久、实际捡到多少金、
## 死了几条命。两者的差就是探针看不见的那部分 —— 金币是掉在地上要开过去捡的
## (25 秒消失, 120px 磁吸), 所以"期望收入"和"到手收入"从来不是一回事; 探针
## 假设全捡到, 实机会告诉你到手率是多少。
##
## 放在 _apply_factory_reward_multiplier() 之后, 所以 gold 是最终结算值。
## BalanceLog 自己判断开关 (非 debug 构建不写, TANK_BALANCE_LOG=0 也能关)。
func _log_battle_result(victory: bool) -> void:
	var dur := float(Time.get_ticks_msec() - battle_start_msec) / 1000.0
	BalanceLog.emit("battle_result", {
		"mode": int(GameState.mode),
		"act": GameState.current_act,
		"floor": GameState.current_floor,
		"bt": GameState.battle_type,
		"challenge": GameState.challenge_mode,
		"victory": victory,
		"duration_s": dur,
		"score": score,
		"gold_earned": battle_gold_earned,
		"enemies_spawned": enemies_spawned,
		"total_enemies": total_enemies,
		"level": rpg_mgr.level,
		"atk_damage": rpg_mgr.get_atk_damage(1),
		"p1_lives": p1_lives,
		"p2_lives": p2_lives,
		"player_count": GameState.player_count,
		"gold_after": GameState.gold,
	})


func _on_button_action() -> void:
	# 联机对局结束后一律回标题, 不走街机那条 "start_game() 原地重开"。
	# 原地重开只发生在按按钮的那一台机器上, 另一端会留在结算界面看着一个
	# 已经重开了的世界 —— 而且两边的随机种子从此分家。重开要联机化, 得由
	# 主机重新广播一次 begin_match, 那是下一步的事。
	if NetSession.is_active():
		var net := get_node_or_null("/root/Net")
		if net:
			net.leave()
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
		return

	if GameState.mode == GameState.GameMode.CAMPAIGN:
		if is_victory:
			# 战役的胜利结算只在**打通一层**时出现 (_on_room_cleared() 里
			# is_floor_complete() 才调 _game_over(true)), 而打通一层 = boss 房
			# 清空, 所以这里 battle_type 必然是 "boss"。
			if GameState.current_act < GameState.max_acts:
				GameState.advance_to_next_act()
				GameState.save_campaign()
				# 重新加载 main.tscn 而不是切到别的场景。以撒化之后没有中间的
				# 路线图场景了 —— 这里原本写的是 spire_map.tscn, 而那个场景已经
				# 随尖塔一起删除, change_scene_to_file() 找不到文件时只是打一条
				# 错误日志然后**什么都不做**: 玩家会永远卡在胜利结算界面上,
				# 不崩溃、不报错给玩家看。
				#
				# 重新加载会走一遍 _ready() -> start_game() -> ensure_floor_ready(),
				# 而 advance_to_next_act() 已经生成好了下一层, 于是玩家落在新一层
				# 的起始房。玩家的血量/等级这时**应该**重来一遍同步 —— 跨层是
				# 换场景的唯一时机, sync_to_game_state() 在 _game_over() 里已经做过。
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	elif GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
		# Unlike Arcade's "loop on itself" restart, a daily run ending should
		# go back to the title -- replaying today's seed again isn't the
		# point (there's no server-side lock on it, but the button flow
		# shouldn't invite grinding a one-shot mode for a better roll).
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	else:
		start_game()

func _update_hud() -> void:
	hud_score.text = "SCORE: %06d" % score
	if _lives_shared():
		# 双人战役共享池: p1_lives/p2_lives 本来就镜像相等, 分开显示 "P1:3 | P2:3"
		# 会让人以为是两份独立的命, 所以单独给一行 "SHARED"。
		hud_lives.text = "LIVES (SHARED): %d" % p1_lives
	elif GameState.player_count == 1:
		hud_lives.text = "LIVES: %d" % p1_lives
	else:
		hud_lives.text = "LIVES: P1:%d | P2:%d" % [p1_lives, p2_lives]
	# 客户端不刷怪, 本地的 total_enemies/enemies_spawned 全是初始值, 算出来
	# 恒等于满编。剩余数由主机的状态包给 (见 net_apply_state)。
	var remaining = _net_enemies_left if NetSession.is_client() else (total_enemies - enemies_spawned + enemies_alive)
	hud_enemies.text = "ENEMIES: %d" % remaining

func _branch_tag(player_id: int) -> String:
	match rpg_mgr.get_branch(player_id):
		"speed":
			return "SPEED T%d" % rpg_mgr.get_branch_tier(player_id)
		"heavy":
			return "HEAVY T%d" % rpg_mgr.get_branch_tier(player_id)
		"train":
			return "TRAIN T%d" % rpg_mgr.get_branch_tier(player_id)
		_:
			return "DEFAULT"

func _update_rpg_hud() -> void:
	if hud_rpg_level:
		hud_rpg_level.text = "LV.%d [%s]" % [rpg_mgr.level, _branch_tag(1)]
	if hud_gold:
		hud_gold.text = "GOLD: %d G" % rpg_mgr.gold
	if p1_instance and is_instance_valid(p1_instance):
		if hud_p1_hp:
			hud_p1_hp.text = "P1 [%s]:" % _branch_tag(1)
		if hud_p1_hearts:
			_update_hearts_container(hud_p1_hearts, p1_instance.current_health, p1_instance.max_health)
	if p2_instance and is_instance_valid(p2_instance):
		if hud_p2_hp:
			hud_p2_hp.text = "P2 [%s]:" % _branch_tag(2)
		if hud_p2_hearts:
			_update_hearts_container(hud_p2_hearts, p2_instance.current_health, p2_instance.max_health)
	if hud_stats:
		if GameState.player_count == 2:
			hud_stats.text = "P1 ATK:%d SPD:+%d%% | P2 ATK:%d SPD:+%d%%" % [
				rpg_mgr.get_atk_damage(1), int((rpg_mgr.get_speed_multiplier(1) - 1.0) * 100),
				rpg_mgr.get_atk_damage(2), int((rpg_mgr.get_speed_multiplier(2) - 1.0) * 100)
			]
		else:
			hud_stats.text = "ATK: %d | SPD: +%d%%\nREGEN: +%.1f/s" % [
				rpg_mgr.get_atk_damage(1),
				int((rpg_mgr.get_speed_multiplier(1) - 1.0) * 100),
				rpg_mgr.get_regen_rate(1)
			]
