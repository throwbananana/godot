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
var factory_instances: Array[Node] = [] # tracked for the battle-end gold/XP reward multiplier
var battle_gold_earned: int = 0 # reset in start_game(), read by the Factory reward multiplier at _game_over()
var has_treasure_key: bool = false
var key_has_dropped: bool = false
var key_hidden_target_type: String = "block" # "block" or "enemy"
var key_target_block_instance: Node = null
var key_target_enemy_idx: int = -1
var current_map_layout: Array = []

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

func start_game() -> void:
	score = 0
	enemies_spawned = 0
	enemies_alive = 0
	is_game_over = false
	is_victory = false
	battle_gold_earned = 0
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
		
		if GameState.battle_type == "elite":
			total_enemies = 18
			spawn_interval = 2.0
			show_toast("⚠️ ELITE BATTLE: HEAVY ARMORED CORPS!")
		elif GameState.battle_type == "boss":
			total_enemies = 24
			spawn_interval = 1.6
			show_toast("👑 BOSS BATTLE: REGIONAL COMMANDER FORTRESS!")
		elif GameState.battle_type == "challenge":
			total_enemies = 14
			spawn_interval = 2.4
			if GameState.challenge_mode == "bomb_rain":
				is_bomb_rain_active = true
				bomb_rain_timer = 2.0
				bomb_rain_interval = 4.5
				show_toast("💣 空投炸弹雨挑战：小心天降高爆定时炸弹！")
			elif GameState.challenge_mode == "night_ops":
				is_night_mode_active = true
				show_toast("🌙 黑夜突袭战术挑战：全图漆黑，保持车灯与基地视野！")
			elif GameState.challenge_mode == "night_bombs":
				is_night_mode_active = true
				is_bomb_rain_active = true
				bomb_rain_timer = 2.0
				bomb_rain_interval = 4.5
				show_toast("💀 暗夜空投极限防守：在漆黑夜幕中躲避定时炸弹并歼灭敌军！")
			else:
				show_toast("🏆 隐秘宝藏挑战：击破隐藏地块或消灭敌军寻找【金钥匙】！")
		else:
			total_enemies = 12
			spawn_interval = 2.5
			show_toast("FLOOR %d: TACTICAL ENGAGEMENT" % (GameState.current_floor + 1))
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

func _clear_all() -> void:
	water_sprites.clear()
	tree_sprites.clear()
	water_bodies.clear()
	factory_instances.clear()
	if darkness_fog_instance and is_instance_valid(darkness_fog_instance):
		darkness_fog_instance.queue_free()
		darkness_fog_instance = null
	for child in map_container.get_children():
		child.queue_free()
	for child in base_wall_container.get_children():
		child.queue_free()
	for child in actors_container.get_children():
		child.queue_free()

func _build_map() -> void:
	var map_pixel_w = GRID_W * TILE_SIZE
	var map_pixel_h = GRID_H * TILE_SIZE

	_create_border_wall(Vector2(-TILE_SIZE / 2.0, map_pixel_h / 2.0), Vector2(TILE_SIZE, map_pixel_h + TILE_SIZE * 2))
	_create_border_wall(Vector2(map_pixel_w + TILE_SIZE / 2.0, map_pixel_h / 2.0), Vector2(TILE_SIZE, map_pixel_h + TILE_SIZE * 2))
	_create_border_wall(Vector2(map_pixel_w / 2.0, -TILE_SIZE / 2.0), Vector2(map_pixel_w + TILE_SIZE * 2, TILE_SIZE))
	_create_border_wall(Vector2(map_pixel_w / 2.0, map_pixel_h + TILE_SIZE / 2.0), Vector2(map_pixel_w + TILE_SIZE * 2, TILE_SIZE))

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
		layout = MapTemplates.get_layout_for_stage(GameState.current_floor, GameState.battle_type, GameState.current_act)
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

	# Dynamic terrain hazards (Minefields on higher floors / elite encounters)
	if (GameState.current_floor >= 2 or GameState.battle_type in ["elite", "boss"]) and landmine_hazard_scene:
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

func _spawn_tile(type: String, pos: Vector2, tex: Texture2D) -> void:
	if not tex:
		return
	if type == "trees":
		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		spr.position = pos
		spr.z_index = 10
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
		key.global_position = drop_pos
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
			coin.global_position = pos
			actors_container.call_deferred("add_child", coin)
	elif roll < 0.88:
		# Rare Diamond Gem (+60G + 30XP)
		if not diamond_gem_scene:
			diamond_gem_scene = load("res://scenes/diamond_gem.tscn")
		if diamond_gem_scene and actors_container:
			var dia = diamond_gem_scene.instantiate()
			dia.global_position = pos
			actors_container.call_deferred("add_child", dia)
	else:
		# Rare Power-up (Star / Bomb / Clock / Helmet / Life / Shovel / Missile / Timed Bomb)
		if powerup_scene and actors_container:
			var p_inst = powerup_scene.instantiate()
			var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB]
			types.shuffle()
			p_inst.setup(types[0])
			p_inst.position = pos
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

func trigger_shovel(duration: float = 15.0) -> void:
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

## 有坦克钻进树林时, 把它压着的那几格树冠淡下去。
##
## 遍历的是坦克 (最多十几个) 而不是树格, 所以开销和林子多大无关。
##
## 用包围盒而不是"中心点所在的那一格": 坦克约 40px 宽而格子 48px, 骑在两格
## 中间是常态。只算中心格的话, 车头探进相邻那格的部分照样是隐形的 —— 而那
## 半截车正是玩家最需要看见的部分。
func _update_tree_transparency(delta: float) -> void:
	if tree_sprites.is_empty():
		return

	var occupied := {}
	var units: Array = []
	units.append_array(get_tree().get_nodes_in_group("player"))
	units.append_array(get_tree().get_nodes_in_group("enemies"))
	const HALF := 17.0
	for u in units:
		if not is_instance_valid(u) or not (u is Node2D):
			continue
		# 已经开启光学迷彩的 MIRAGE 不触发淡出。它静止时会把自己伪装成一棵树,
		# 要是周围的真树反而因为它而淡了一圈, 等于亲手在地图上标出"这里有东西",
		# 它整个机制就废了。潜行单位不该自己暴露自己。
		if "is_camouflaged" in u and u.is_camouflaged:
			continue
		# 树瓦片挂在 map_container 下用的是*局部*坐标, 而坦克给的是全局坐标。
		# GameArea 有 (48,48) 的偏移, 直接拿全局坐标去除以 TILE_SIZE 会整整
		# 差一格 —— 见 CLAUDE.md 的坐标系一节。
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

	if enemies_spawned < total_enemies and enemies_alive < 4:
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
	EnemyTank.EnemyType.BOMBER: 3,
	# 喷火兵和 BOMBER 同档 (延时/持续的范围压制), 而不是和 LASER 那档 (5 层)。
	# 它的射程只有 2.75 格, 绕侧面就能解 —— 属于"逼你换位"而不是"逼你换装备",
	# 早点出现反而能教会玩家侧向机动, 为 5 层以后真正的远程威胁做铺垫。
	EnemyTank.EnemyType.FLAMETHROWER: 3,
	EnemyTank.EnemyType.AIRCRAFT: 5,
	EnemyTank.EnemyType.MIRAGE: 5,
	EnemyTank.EnemyType.BATTLESHIP: 5,
	EnemyTank.EnemyType.LASER: 5,
	EnemyTank.EnemyType.MISSILE: 8,
	EnemyTank.EnemyType.WARP: 8,
}

func _gate_enemy_type(type: EnemyTank.EnemyType, floor_idx: int) -> EnemyTank.EnemyType:
	if floor_idx >= ENEMY_MIN_FLOOR.get(type, 0):
		return type
	return EnemyTank.EnemyType.FAST if floor_idx >= 1 else EnemyTank.EnemyType.BASIC

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
			type = EnemyTank.EnemyType.TRAIN_BOSS
			show_toast("🚂 ARMORED TRAIN FORTRESS DETECTED! 🚂")
			add_trauma(0.60)
		elif enemies_spawned == total_enemies - 1:
			type = EnemyTank.EnemyType.BOSS
			show_toast("⚠️ SUMMIT COLOSSUS DETECTED! ⚠️")
			add_trauma(0.50)
		elif r < 0.15: type = EnemyTank.EnemyType.AIRCRAFT
		elif r < 0.30: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.SUICIDE
		elif r < 0.45: type = EnemyTank.EnemyType.MIRAGE
		elif r < 0.60: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.75: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.88: type = EnemyTank.EnemyType.LASER
		else: type = EnemyTank.EnemyType.WARP if GameState.get_visual_act() == 3 else EnemyTank.EnemyType.POWER
	elif GameState.battle_type == "elite":
		if enemies_spawned == 0:
			type = EnemyTank.EnemyType.TRAIN_BOSS
			show_toast("🚂 ELITE ARMORED CONVOY DETECTED! 🚂")
			add_trauma(0.50)
		elif r < 0.15: type = EnemyTank.EnemyType.AIRCRAFT
		elif r < 0.30: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.SUICIDE
		elif r < 0.42: type = EnemyTank.EnemyType.MIRAGE
		elif r < 0.52: type = EnemyTank.EnemyType.FLAMETHROWER
		elif r < 0.68: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.80: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.90: type = EnemyTank.EnemyType.LASER
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
				if r < 0.25: type = themed_type
				elif r < 0.45: type = EnemyTank.EnemyType.FAST
				elif r < 0.62: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.76: type = EnemyTank.EnemyType.BOMBER
				elif r < 0.88: type = EnemyTank.EnemyType.AIRCRAFT
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.ARMOR
			3:
				if r < 0.12: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.22: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.32: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.40: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.55: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.70: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.85: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			4:
				if r < 0.15: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.25: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.36: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.45: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.60: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.75: type = EnemyTank.EnemyType.BOMBER
				elif r < 0.88: type = EnemyTank.EnemyType.MISSILE
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			_:
				if r < 0.15: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.25: type = EnemyTank.EnemyType.FLAMETHROWER
				elif r < 0.36: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.45: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.60: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.75: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.88: type = EnemyTank.EnemyType.BOMBER
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
		p_inst.position = drop_pos
		actors_container.call_deferred("add_child", p_inst)
		show_toast("BONUS ITEM DROPPED!")

	if enemies_spawned >= total_enemies and enemies_alive <= 0:
		_game_over(true)

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
				coin.global_position = death_pos + offset
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

func _on_button_action() -> void:
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		if is_victory:
			if GameState.battle_type == "boss":
				if GameState.current_act < GameState.max_acts:
					GameState.advance_to_next_act()
					GameState.save_campaign()
					get_tree().change_scene_to_file("res://scenes/spire_map.tscn")
				else:
					get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/spire_map.tscn")
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
