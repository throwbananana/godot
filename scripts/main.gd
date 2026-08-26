class_name MainGame
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")
const SpawnStar = preload("res://scripts/spawn_star.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")
const BuilderController = preload("res://scripts/builder_controller.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")
const MapDirector = preload("res://scripts/map_director.gd")
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

const TILE_SIZE: float = 48.0
const TILE_SCALE: float = TILE_SIZE / 256.0
const GRID_W: int = 13
const GRID_H: int = 13

var rpg_mgr: RPGManager = RPGManager.new()

var player_scene: PackedScene
var enemy_scene: PackedScene
var base_scene: PackedScene
var powerup_scene: PackedScene
var spawnstar_scene: PackedScene
var landmine_hazard_scene: PackedScene

var tex_brick: Texture2D
var tex_steel: Texture2D
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
var factory_instances: Array[Node] = [] # tracked for the battle-end gold/XP reward multiplier
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

var score: int = 0
var p1_lives: int = 3
var p2_lives: int = 3
var total_enemies: int = 20
var enemies_spawned: int = 0
var enemies_alive: int = 0
var spawn_timer: float = 0.0
var spawn_interval: float = 3.0
var is_game_over: bool = false
var is_victory: bool = false

var shovel_timer: float = 0.0
var is_shovel_active: bool = false

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

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

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

@onready var hud_score: Label = $HUD/SidePanel/VBox/ScoreBox/ScoreLabel
@onready var hud_lives: Label = $HUD/SidePanel/VBox/LivesBox/LivesLabel
@onready var hud_enemies: Label = $HUD/SidePanel/VBox/EnemiesBox/EnemiesLabel
@onready var hud_rpg_level: Label = $HUD/SidePanel/VBox/RPGLevelLabel
@onready var hud_rpg_xp: ProgressBar = $HUD/SidePanel/VBox/XPBar
@onready var hud_gold: Label = $HUD/SidePanel/VBox/GoldBox/GoldLabel
@onready var hud_p1_hp: Label = $HUD/SidePanel/VBox/P1HPBox/P1HPLabel
@onready var hud_p2_hp: Label = $HUD/SidePanel/VBox/P2HPBox/P2HPLabel
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
@onready var btn_restart_stage: Button = $HUD/PauseMenu/VBox/RestartStageButton
@onready var btn_quit_menu: Button = $HUD/PauseMenu/VBox/QuitToMenuButton

var upgrade_dialog: UpgradeSelectionDialog
var pending_upgrade_players: Array[int] = []
var hud_hotbar: Control = null
var hud_boss_bar: Control = null
var hud_boss_fill: TextureProgressBar = null
var hud_boss_label: Label = null
var active_boss_instance: Node2D = null

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

	tex_brick = TextureHelper.get_tex("res://assets/sprites/tiles/tile_brick.png")
	tex_steel = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
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

	UIThemeHelper.apply_clay_panel($HUD/SidePanel)
	UIThemeHelper.apply_clay_panel(pause_menu)
	UIThemeHelper.apply_clay_progressbar(hud_rpg_xp)
	
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
	$HUD.add_child(minimap)

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
	UIThemeHelper.apply_icon_button(btn_restart_stage, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_quit_menu, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(22, 22))

	btn_resume.pressed.connect(_toggle_pause)
	btn_restart_stage.pressed.connect(func():
		_toggle_pause()
		start_game()
	)
	btn_quit_menu.pressed.connect(func():
		_toggle_pause()
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	)

	var origin_x = 48.0
	var origin_y = 48.0
	game_area.position = Vector2(origin_x, origin_y)

	enemy_spawn_points = [
		Vector2(0.5 * TILE_SIZE, 0.5 * TILE_SIZE),
		Vector2(6.5 * TILE_SIZE, 0.5 * TILE_SIZE),
		Vector2(12.5 * TILE_SIZE, 0.5 * TILE_SIZE)
	]
	p1_spawn_point = Vector2(4.5 * TILE_SIZE, 12.5 * TILE_SIZE)
	p2_spawn_point = Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE)

	start_game()

func _unhandled_input(event: InputEvent) -> void:
	# "pause" = ESC / P / 两个手柄的 START。以前这里是 ui_cancel + 硬编码 KEY_P,
	# 而 ui_cancel 在手柄上的默认绑定是 B —— B 同时又是菜单里的"返回", 于是手柄
	# 玩家一按 B 就会在关闭对话框的同时弹出暂停菜单。改用独立 action 后 B 只管
	# 菜单返回, 暂停归 START。键盘行为不变: ESC 和 P 都在这个 action 里。
	# 注意 START 也绑着 restart, 但那个只在 is_game_over/is_victory 时读取,
	# 而这里恰好把那两种状态排除了, 所以同一颗键不会有歧义。
	if event.is_action_pressed("pause"):
		if not is_game_over and not is_victory:
			_toggle_pause()

func _toggle_pause() -> void:
	var paused = not get_tree().paused
	get_tree().paused = paused
	pause_menu.visible = paused

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
const ENCOUNTER_PER_LAP := 4

const SPAWN_INTERVAL_BASE := {
	"elite": 2.0,
	"boss": 1.6,
	"challenge": 2.4,
	"battle": 2.5,
}
## 每圈出车间隔收紧多少; 下限 1.2 秒 —— 再快的话三个出生点会堵住,
## 车挤在门口反而比正常涌出来好打。
const SPAWN_INTERVAL_PER_LAP := 0.25
const SPAWN_INTERVAL_FLOOR := 1.2

## 场上同时存在的敌人上限。
##
## 这一条是难度圈真正加压的地方。光加遭遇规模不够 —— 上限锁死在 4 的话,
## "一场 20 辆"和"一场 12 辆"的区别只是**打得久**, 每一刻的压力一模一样,
## 而更长不等于更难。上限抬到 6, 场上多两辆车才是实打实的压迫感, 而且它同样
## 是个整数、同样一眼看得见 (屏幕上就是多两辆)。
##
## 封顶 6: 13x13 的地图加三个出生点, 再多就变成敌人互相堵路, 反而更好打。
const MAX_ALIVE_BASE := 4
const MAX_ALIVE_CAP := 6

var max_alive_cap: int = MAX_ALIVE_BASE

static func max_alive_for(cycle: int) -> int:
	return mini(MAX_ALIVE_CAP, MAX_ALIVE_BASE + maxi(0, cycle))


static func encounter_size(battle_type: String, cycle: int) -> int:
	var base: int = int(ENCOUNTER_BASE.get(battle_type, ENCOUNTER_BASE["battle"]))
	return base + maxi(0, cycle) * ENCOUNTER_PER_LAP


static func spawn_interval_for(battle_type: String, cycle: int) -> float:
	var base: float = float(SPAWN_INTERVAL_BASE.get(battle_type, SPAWN_INTERVAL_BASE["battle"]))
	return maxf(SPAWN_INTERVAL_FLOOR, base - float(maxi(0, cycle)) * SPAWN_INTERVAL_PER_LAP)


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
	hud_status.visible = false
	btn_restart.visible = false
	if victory_modal_root:
		victory_modal_root.visible = false

	is_night_mode_active = false
	is_bomb_rain_active = false
	bomb_rain_timer = 0.0

	if GameState.mode == GameState.GameMode.CAMPAIGN:
		p1_lives = GameState.player_lives
		p2_lives = GameState.p2_lives
		rpg_mgr.sync_from_game_state()
		max_alive_cap = max_alive_for(GameState.get_difficulty_cycle())

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

	_clear_all()
	_build_map()
	_spawn_base_and_walls(false)
	_spawn_player(1)
	if GameState.player_count == 2:
		_spawn_player(2)
		if hud_p2_hp_box: hud_p2_hp_box.visible = true
	else:
		if hud_p2_hp_box: hud_p2_hp_box.visible = false

	if is_night_mode_active:
		darkness_fog_instance = DarknessFog.new()
		darkness_fog_instance.setup_trackers(p1_instance, p2_instance, base_instance)
		game_area.add_child(darkness_fog_instance)

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
			upgrade_dialog.show_upgrade_options(rpg_mgr, pending_upgrade_players[0])

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

	if not pending_upgrade_players.is_empty() and upgrade_dialog and is_instance_valid(upgrade_dialog):
		upgrade_dialog.show_upgrade_options(rpg_mgr, pending_upgrade_players[0])
	else:
		get_tree().paused = false

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

func _transition_to_room(room_key: String, travel_dir: int) -> void:
	is_transitioning = true
	if fade_layer:
		var tw := create_tween()
		tw.tween_property(fade_layer, "modulate:a", 1.0, ROOM_FADE_SEC)
		await tw.finished

	enter_room(room_key, FloorMap.opposite(travel_dir))

	if fade_layer:
		var tw2 := create_tween()
		tw2.tween_property(fade_layer, "modulate:a", 0.0, ROOM_FADE_SEC)
		await tw2.finished
	is_transitioning = false


## 进入一个房间并把它整个建起来。start_game() 的首次进场和之后每一次过门都
## 走这里, 所以"房间该长什么样"只有这一份实现。
##
## entry_dir 是**本房间**那扇门的朝向 (玩家从哪边进来), -1 表示首次进场
## (站在房间中央偏下)。
func enter_room(room_key: String, entry_dir: int) -> void:
	GameState.visit_room(room_key)

	var room := GameState.current_room_data()
	var is_combat: bool = FloorMap.is_combat_room(room)

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

	_clear_all(true)
	_build_map()
	_spawn_doors()

	if is_combat:
		_spawn_base_and_walls(false)

	_place_players_at_entry(entry_dir)

	if is_night_mode_active:
		darkness_fog_instance = DarknessFog.new()
		darkness_fog_instance.setup_trackers(p1_instance, p2_instance, base_instance)
		game_area.add_child(darkness_fog_instance)

	room_cleared_pending = false
	if is_combat:
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
	match str(room.get("type", "")):
		"shop":
			_build_shop_room()
		"event", "rest":
			if event_dialog:
				event_dialog.setup(str(room.get("type", "event")))
				event_dialog.visible = true
		"treasure":
			_grant_treasure_room_reward()
		"secret":
			show_toast("🔒 隐藏房间 —— 补给已就位")
			_grant_treasure_room_reward()


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
		# 卖掉的状态要写回房间字典 —— 否则走出门再回来东西又回来了。
		stand.purchased.connect(func(_id, _c): _on_shop_item_sold(i))
		map_container.add_child(stand)

	var roller := ShopRerolder.new()
	roller.position = Vector2((SHOP_REROLLER_CELL.x + 0.5) * TILE_SIZE, (SHOP_REROLLER_CELL.y + 0.5) * TILE_SIZE)
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
		var types = [PowerUp.Type.STAR, PowerUp.Type.LIFE, PowerUp.Type.HELMET, PowerUp.Type.BOMB]
		types.shuffle()
		p_inst.setup(types[0])
		p_inst.position = Vector2((GRID_W / 2.0) * TILE_SIZE, (GRID_H / 2.0) * TILE_SIZE)
		actors_container.call_deferred("add_child", p_inst)
	add_gold(80)
	GameState.save_campaign()


func _announce_room(room: Dictionary) -> void:
	match str(room.get("type", "normal")):
		"boss":
			show_toast("👑 BOSS 房：区域指挥官要塞！")
		"challenge":
			match GameState.challenge_mode:
				"bomb_rain": show_toast("💣 挑战房：空投炸弹雨！")
				"night_ops": show_toast("🌙 挑战房：黑夜突袭！")
				"night_bombs": show_toast("💀 挑战房：暗夜空投极限防守！")
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
		# 首次进场: 起始房中央偏下, 和以前的出生点一致。
		base_pos = Vector2((GRID_W / 2.0) * TILE_SIZE, (GRID_H - 2.5) * TILE_SIZE)

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
	# 缺口在门那一格上, 由 RoomDoor.DOOR_COL / DOOR_ROW 决定 —— 不是边的中点,
	# 因为中点会撞上底边中央的老鹰基地, 详见 room_door.gd 里那段注释。
	var gap_x0 := RoomDoor.DOOR_COL * TILE_SIZE
	var gap_x1 := gap_x0 + TILE_SIZE
	var gap_y0 := RoomDoor.DOOR_ROW * TILE_SIZE
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
	for d in door_dirs:
		for step in range(CORRIDOR_DEPTH):
			var r := 0
			var c := 0
			match int(d):
				0: r = step;               c = RoomDoor.DOOR_COL
				2: r = GRID_H - 1 - step;  c = RoomDoor.DOOR_COL
				3: r = RoomDoor.DOOR_ROW;  c = step
				1: r = RoomDoor.DOOR_ROW;  c = GRID_W - 1 - step
			if r >= 0 and r < layout.size() and c >= 0 and c < layout[r].size():
				layout[r][c] = 0


func _build_map() -> void:
	var door_dirs := _current_door_dirs()
	_build_border_walls(door_dirs)

	var layout: Array
	if GameState.mode == GameState.GameMode.DAILY_CHALLENGE:
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

	# Dynamic terrain hazards (Minefields on higher floors / elite encounters).
	# 只在战斗房加 —— 这段是在 _build_map() 尾部无条件跑的, 跟房间类型无关;
	# 商店/事件/宝物/休息房也会经过 _build_map() (每间房都建图), 不加这个判定
	# 的话高楼层的商店房会在货位旁边埋地雷, 玩家逛街进门就被炸。
	var room_is_combat: bool = true
	if GameState.mode != GameState.GameMode.DAILY_CHALLENGE:
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
	var tex = tex_steel if is_steel else tex_brick
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
	if not conveyor_belt_scene:
		conveyor_belt_scene = load("res://scenes/conveyor_belt.tscn")
	if conveyor_belt_scene:
		var cb = conveyor_belt_scene.instantiate()
		cb.position = pos
		cb.set_direction(dir)
		map_container.add_child(cb)

func _spawn_jump_pad(pos: Vector2) -> void:
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
		GameState.p2_lives = p2_lives
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
		# Rare Diamond Gem (+60G + 30XP)
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
			var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB]
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
	if layout and layout.size() > 0:
		for r in range(layout.size()):
			for c in range(layout[r].size()):
				if layout[r][c] == 0:
					# Avoid teleporting onto Eagle base
					if r >= 10 and c >= 4 and c <= 8:
						continue
					empty_candidates.append(Vector2((c + 0.5) * TILE_SIZE, (r + 0.5) * TILE_SIZE))
	var local_pos := Vector2(randf_range(96.0, 528.0), randf_range(96.0, 528.0))
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
	for child in base_wall_container.get_children():
		child.queue_free()

	base_instance = base_scene.instantiate()
	base_instance.position = Vector2(6.5 * TILE_SIZE, 12.5 * TILE_SIZE)
	base_instance.destroyed.connect(_on_base_destroyed)
	base_wall_container.add_child(base_instance)

	var wall_positions = [
		Vector2(5.5 * TILE_SIZE, 12.5 * TILE_SIZE),
		Vector2(5.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(6.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(7.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(7.5 * TILE_SIZE, 12.5 * TILE_SIZE)
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
	total_enemies = encounter_size(GameState.battle_type, cycle)
	spawn_interval = spawn_interval_for(GameState.battle_type, cycle)
	max_alive_cap = max_alive_for(cycle)
	enemies_spawned = 0
	enemies_alive = 0
	spawn_timer = 0.0

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

func show_toast(msg: String) -> void:
	if hud_toast:
		hud_toast.text = msg
		hud_toast.visible = true
		var tween = create_tween()
		tween.tween_property(hud_toast, "modulate:a", 1.0, 0.2)
		tween.tween_interval(2.0)
		tween.tween_property(hud_toast, "modulate:a", 0.0, 0.5)

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

func _on_player_hp_changed(pid: int, curr: int, max_hp: int) -> void:
	if pid == 1 and hud_p1_hp:
		hud_p1_hp.text = "P1 [YEL] HP: %d / %d [%s]" % [curr, max_hp, _branch_tag(1)]
	elif pid == 2 and hud_p2_hp:
		hud_p2_hp.text = "P2 [GRN] HP: %d / %d [%s]" % [curr, max_hp, _branch_tag(2)]

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
	# Trauma Screen Shake
	if trauma > 0.0:
		var shake = trauma * trauma
		var offset = Vector2(
			randf_range(-1.0, 1.0) * max_shake_offset.x * shake,
			randf_range(-1.0, 1.0) * max_shake_offset.y * shake
		)
		game_area.position = base_game_area_pos + offset
		trauma = max(0.0, trauma - trauma_decay * delta)
	else:
		game_area.position = base_game_area_pos

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

	# Boss Health Bar Realtime Sync & Smooth Fade
	if active_boss_instance:
		if is_instance_valid(active_boss_instance) and hud_boss_fill:
			hud_boss_fill.value = active_boss_instance.health
		else:
			active_boss_instance = null
			if hud_boss_bar and hud_boss_bar.visible:
				var tw = create_tween()
				tw.tween_property(hud_boss_bar, "modulate:a", 0.0, 0.45)
				tw.tween_callback(func():
					hud_boss_bar.visible = false
					hud_boss_bar.modulate.a = 1.0
				)

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
	EnemyTank.EnemyType.SNIPER: 4,
	EnemyTank.EnemyType.GATLING: 4,
	EnemyTank.EnemyType.SPIDER: 4,
	EnemyTank.EnemyType.SANDWORM: 4,
	EnemyTank.EnemyType.CANNON: 4,
	EnemyTank.EnemyType.AIRCRAFT: 5,
	EnemyTank.EnemyType.MIRAGE: 5,
	EnemyTank.EnemyType.BATTLESHIP: 5,
	EnemyTank.EnemyType.LASER: 5,
	EnemyTank.EnemyType.CRUSHER: 5,
	EnemyTank.EnemyType.SPLITTER: 5,
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
	EnemyTank.EnemyType.BOMBER, EnemyTank.EnemyType.ENGINEER, EnemyTank.EnemyType.FLAMETHROWER, EnemyTank.EnemyType.FIREWALL,
	EnemyTank.EnemyType.SNIPER, EnemyTank.EnemyType.GATLING, EnemyTank.EnemyType.SPIDER, EnemyTank.EnemyType.SANDWORM, EnemyTank.EnemyType.CANNON,
	EnemyTank.EnemyType.AIRCRAFT, EnemyTank.EnemyType.MIRAGE,
	EnemyTank.EnemyType.BATTLESHIP, EnemyTank.EnemyType.LASER,
	EnemyTank.EnemyType.CRUSHER, EnemyTank.EnemyType.SPLITTER,
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
			type = EnemyTank.EnemyType.BOSS
			show_toast("⚠️ WARLORD SUPER-TANK DETECTED! ⚠️")
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
		elif r < 0.76: type = EnemyTank.EnemyType.CRUSHER
		elif r < 0.82: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.88: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.94: type = EnemyTank.EnemyType.LASER
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
				elif r < 0.16: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.24: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.32: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.40: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.48: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.58: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.68: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.78: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.88: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			4:
				if r < 0.05: type = EnemyTank.EnemyType.ARMOR
				elif r < 0.10: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.15: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.20: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.26: type = EnemyTank.EnemyType.SPIDER
				elif r < 0.32: type = EnemyTank.EnemyType.SANDWORM
				elif r < 0.38: type = EnemyTank.EnemyType.CANNON
				elif r < 0.44: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.51: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.58: type = EnemyTank.EnemyType.GATLING
				elif r < 0.65: type = EnemyTank.EnemyType.SNIPER
				elif r < 0.72: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.79: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.89: type = EnemyTank.EnemyType.SUICIDE
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			_:
				# floor 5 以后全阵容展开: SPLITTER, CRUSHER, ENGINEER, SPIDER, FIREWALL, HUNTER, SANDWORM, CANNON, GATLING 等。
				if r < 0.05: type = EnemyTank.EnemyType.SPLITTER
				elif r < 0.09: type = EnemyTank.EnemyType.CRUSHER
				elif r < 0.13: type = EnemyTank.EnemyType.ENGINEER
				elif r < 0.17: type = EnemyTank.EnemyType.FIREWALL
				elif r < 0.21: type = EnemyTank.EnemyType.HUNTER
				elif r < 0.26: type = EnemyTank.EnemyType.SPIDER
				elif r < 0.31: type = EnemyTank.EnemyType.SANDWORM
				elif r < 0.36: type = EnemyTank.EnemyType.CANNON
				elif r < 0.42: type = EnemyTank.EnemyType.GATLING
				elif r < 0.48: type = EnemyTank.EnemyType.SNIPER
				elif r < 0.54: type = EnemyTank.EnemyType.SHOTGUN
				elif r < 0.60: type = EnemyTank.EnemyType.BATTLESHIP
				elif r < 0.67: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.74: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.81: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.88: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.94: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER

	# Floor-gate the roll above -- the boss/elite tables (unlike the plain
	# "battle" one) never checked floor_idx, so an early Act1 elite fight
	# (first possible around floor_idx 4) could roll a MISSILE/BOMBER truck
	# well before the player has any counterplay for it. TRAIN_BOSS/BOSS and
	# the current act's themed_type are exempt -- they're encounter identity
	# (the elite's boss escort, the act finale, the act's signature silhouette),
	# not power-tier filler.
	if GameState.mode != GameState.GameMode.DAILY_CHALLENGE and type != EnemyTank.EnemyType.TRAIN_BOSS and type != EnemyTank.EnemyType.BOSS and type != themed_type:
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

	if type in [EnemyTank.EnemyType.BOSS, EnemyTank.EnemyType.TRAIN_BOSS]:
		active_boss_instance = enemy
		if hud_boss_bar and hud_boss_fill and hud_boss_label:
			hud_boss_bar.visible = true
			hud_boss_bar.modulate.a = 1.0
			var b_name = "👑 SUMMIT COLOSSUS FORTRESS" if type == EnemyTank.EnemyType.BOSS else "🚂 ARMORED TRAIN FORTRESS"
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
		var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB]
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
	_open_doors()
	_refresh_minimap()
	SoundManager.play_victory(get_tree())

	_grant_room_clear_reward()

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
		var types = [PowerUp.Type.STAR, PowerUp.Type.HELMET, PowerUp.Type.LIFE, PowerUp.Type.CLOCK, PowerUp.Type.SHOVEL]
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
		p1_lives -= 1
		GameState.player_tier = 0
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.player_lives = p1_lives
		if p1_lives > 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _spawn_player(1))
	else:
		p2_lives -= 1
		GameState.p2_tier = 0
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.p2_lives = p2_lives
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

## Factory map building: doubles this battle's earned gold+XP if at least one
## Factory instance survived to the end, halves it if every Factory on the
## map was destroyed. No-op if the map had no Factory. Applies to
## battle_gold_earned/rpg_mgr.xp_earned_this_battle -- everything earned this
## battle, including any mission-completion bonus already granted above --
## not the player's full running totals.
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
	var xp_delta = int(round(rpg_mgr.xp_earned_this_battle * (mult - 1.0)))

	if gold_delta != 0:
		rpg_mgr.gold = maxi(0, rpg_mgr.gold + gold_delta)
		rpg_mgr.gold_changed.emit(rpg_mgr.gold)
	if xp_delta > 0:
		rpg_mgr.add_xp(xp_delta) # may cascade a level-up, same as any other XP grant
	elif xp_delta < 0:
		rpg_mgr.current_xp = maxi(0, rpg_mgr.current_xp + xp_delta) # clamp only -- no delevel mechanic exists

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
	
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		rpg_mgr.sync_to_game_state()
		GameState.player_lives = p1_lives
		GameState.p2_lives = p2_lives
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
				add_gold(150)
				rpg_mgr.add_xp(100)
				modal_title_str = "🏆 CHALLENGE COMPLETE! 🏆"
				modal_desc_str = "战术极限挑战大成功！额外斩获 +150G 与 +100XP！"
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
	if GameState.player_count == 1:
		hud_lives.text = "LIVES: %d" % p1_lives
	else:
		hud_lives.text = "LIVES: P1:%d | P2:%d" % [p1_lives, p2_lives]
	var remaining = total_enemies - enemies_spawned + enemies_alive
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
	if hud_rpg_xp:
		hud_rpg_xp.max_value = rpg_mgr.xp_to_next
		hud_rpg_xp.value = rpg_mgr.current_xp
	if hud_gold:
		hud_gold.text = "GOLD: %d G" % rpg_mgr.gold
	if hud_p1_hp and p1_instance and is_instance_valid(p1_instance):
		hud_p1_hp.text = "P1 [YEL] HP: %d / %d [%s]" % [p1_instance.current_health, p1_instance.max_health, _branch_tag(1)]
	if hud_p2_hp and p2_instance and is_instance_valid(p2_instance):
		hud_p2_hp.text = "P2 [GRN] HP: %d / %d [%s]" % [p2_instance.current_health, p2_instance.max_health, _branch_tag(2)]
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
