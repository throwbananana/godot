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

var enemy_spawn_points: Array[Vector2] = [
	Vector2(0.5 * TILE_SIZE, 0.5 * TILE_SIZE),
	Vector2(6.5 * TILE_SIZE, 0.5 * TILE_SIZE),
	Vector2(12.5 * TILE_SIZE, 0.5 * TILE_SIZE)
]
var p1_spawn_point: Vector2 = Vector2(4.5 * TILE_SIZE, 12.5 * TILE_SIZE)
var p2_spawn_point: Vector2 = Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE)
var water_sprites: Array[Sprite2D] = []
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

@onready var hud_score: Label = $HUD/SidePanel/VBox/ScoreLabel
@onready var hud_lives: Label = $HUD/SidePanel/VBox/LivesLabel
@onready var hud_enemies: Label = $HUD/SidePanel/VBox/EnemiesLabel
@onready var hud_rpg_level: Label = $HUD/SidePanel/VBox/RPGLevelLabel
@onready var hud_rpg_xp: ProgressBar = $HUD/SidePanel/VBox/XPBar
@onready var hud_gold: Label = $HUD/SidePanel/VBox/GoldLabel
@onready var hud_p1_hp: Label = $HUD/SidePanel/VBox/P1HPLabel
@onready var hud_p2_hp: Label = $HUD/SidePanel/VBox/P2HPLabel
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

func _ready() -> void:
	player_scene = load("res://scenes/player.tscn")
	enemy_scene = load("res://scenes/enemy.tscn")
	base_scene = load("res://scenes/base_eagle.tscn")
	powerup_scene = load("res://scenes/power_up.tscn")
	spawnstar_scene = load("res://scenes/spawn_star.tscn")
	landmine_hazard_scene = load("res://scenes/landmine_hazard.tscn")

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
	moving_platform_scene = load("res://scenes/moving_platform.tscn")
	wormhole_scene = load("res://scenes/wormhole.tscn")
	shield_station_scene = load("res://scenes/buildings/shield_station.tscn")
	wind_blower_scene = load("res://scenes/buildings/wind_blower.tscn")
	conveyor_belt_scene = load("res://scenes/conveyor_belt.tscn")
	jump_pad_scene = load("res://scenes/jump_pad.tscn")
	treasure_chest_scene = load("res://scenes/treasure_chest.tscn")
	treasure_key_scene = load("res://scenes/treasure_key.tscn")
	diamond_gem_scene = load("res://scenes/diamond_gem.tscn")

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

	UIThemeHelper.apply_clay_button(btn_restart)
	btn_restart.pressed.connect(_on_button_action)

	UIThemeHelper.apply_clay_button(btn_resume)
	UIThemeHelper.apply_clay_button(btn_restart_stage)
	UIThemeHelper.apply_clay_button(btn_quit_menu)

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
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
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
	shovel_timer = 0.0
	is_shovel_active = false
	hud_status.visible = false
	btn_restart.visible = false

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
		else:
			total_enemies = 12
			spawn_interval = 2.5
			show_toast("FLOOR %d: TACTICAL ENGAGEMENT" % (GameState.current_floor + 1))
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
		hud_p2_hp.visible = true
	else:
		hud_p2_hp.visible = false

	_setup_challenge_treasure()
	_update_hud()
	_update_rpg_hud()

func add_gold(amount: int) -> void:
	rpg_mgr.add_gold(amount)
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
		var new_players: Array[int] = [1, 2] if GameState.player_count == 2 else [1]
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

	var layout = MapTemplates.get_layout_for_stage(GameState.current_floor, GameState.battle_type, GameState.current_act)
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

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
	col.shape = shape
	body.add_child(col)

	map_container.add_child(body)

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
		chest.position = chest_pos
		actors_container.add_child(chest)

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
		actors_container.add_child(key)
		key.global_position = drop_pos
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
			actors_container.add_child(coin)
			coin.global_position = pos
	elif roll < 0.88:
		# Rare Diamond Gem (+60G + 30XP)
		if not diamond_gem_scene:
			diamond_gem_scene = load("res://scenes/diamond_gem.tscn")
		if diamond_gem_scene and actors_container:
			var dia = diamond_gem_scene.instantiate()
			actors_container.add_child(dia)
			dia.global_position = pos
	else:
		# Rare Power-up (Star / Bomb / Clock / Helmet / Life / Shovel / Missile / Timed Bomb)
		if powerup_scene and actors_container:
			var p_inst = powerup_scene.instantiate()
			var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE, PowerUp.Type.MISSILE, PowerUp.Type.TIMED_BOMB]
			types.shuffle()
			p_inst.setup(types[0])
			p_inst.position = pos
			actors_container.add_child(p_inst)
			show_toast("✨ 砖块暗藏极品道具！")

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
	if empty_candidates.size() > 0:
		return empty_candidates[randi() % empty_candidates.size()]
	return Vector2(randf_range(96.0, 528.0), randf_range(96.0, 528.0))

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

	if is_game_over or is_victory:
		if Input.is_action_just_pressed("restart"):
			_on_button_action()
		return

	if enemies_spawned < total_enemies and enemies_alive < 4:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_request_spawn_enemy()

func _request_spawn_enemy() -> void:
	if enemies_spawned >= total_enemies or enemy_spawn_points.is_empty():
		return
	
	var spawn_idx = enemies_spawned % enemy_spawn_points.size()
	var spawn_pos = enemy_spawn_points[spawn_idx]
	var is_bonus = (enemies_spawned in [3, 10, 17])
	
	var type = EnemyTank.EnemyType.BASIC
	var r = randf()
	var floor_idx = GameState.current_floor

	var has_water = false
	if current_map_layout and current_map_layout.size() > 0:
		for row in current_map_layout:
			if 3 in row:
				has_water = true
				break

	if GameState.battle_type == "boss":
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
		else: type = EnemyTank.EnemyType.POWER
	elif GameState.battle_type == "elite":
		if enemies_spawned == 0:
			type = EnemyTank.EnemyType.TRAIN_BOSS
			show_toast("🚂 ELITE ARMORED CONVOY DETECTED! 🚂")
			add_trauma(0.50)
		elif r < 0.15: type = EnemyTank.EnemyType.AIRCRAFT
		elif r < 0.30: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.SUICIDE
		elif r < 0.48: type = EnemyTank.EnemyType.MIRAGE
		elif r < 0.65: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.80: type = EnemyTank.EnemyType.BOMBER
		elif r < 0.90: type = EnemyTank.EnemyType.LASER
		else: type = EnemyTank.EnemyType.ARMOR
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
				if r < 0.25: type = EnemyTank.EnemyType.DESERT
				elif r < 0.45: type = EnemyTank.EnemyType.FAST
				elif r < 0.62: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.76: type = EnemyTank.EnemyType.BOMBER
				elif r < 0.88: type = EnemyTank.EnemyType.AIRCRAFT
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.ARMOR
			3:
				if r < 0.12: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.25: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.40: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.55: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.70: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.85: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			4:
				if r < 0.15: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.30: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.45: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.60: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.75: type = EnemyTank.EnemyType.BOMBER
				elif r < 0.88: type = EnemyTank.EnemyType.MISSILE
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER
			_:
				if r < 0.15: type = EnemyTank.EnemyType.TRAIN_BOSS
				elif r < 0.30: type = EnemyTank.EnemyType.MIRAGE
				elif r < 0.45: type = EnemyTank.EnemyType.AIRCRAFT
				elif r < 0.60: type = EnemyTank.EnemyType.SUICIDE
				elif r < 0.75: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.88: type = EnemyTank.EnemyType.BOMBER
				else: type = EnemyTank.EnemyType.BATTLESHIP if has_water else EnemyTank.EnemyType.LASER

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
		actors_container.add_child(p_inst)
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
				actors_container.add_child(coin)
				coin.global_position = death_pos + offset

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

	if victory:
		is_victory = true
		SoundManager.play_victory(get_tree())
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			if GameState.battle_type == "boss":
				if GameState.current_act < GameState.max_acts:
					hud_status.text = "🏆 ACT %d CONQUERED! 🏆\n%s SECURED!" % [GameState.current_act, GameState.get_act_name(GameState.current_act)]
					hud_status.modulate = Color(0.98, 0.85, 0.35)
					btn_restart.text = "PROCEED TO ACT %d ->" % (GameState.current_act + 1)
					GameState.save_campaign()
				else:
					hud_status.text = "👑 GRAND DEMO VICTORY! 👑\nALL 3 MAJOR ACTS CONQUERED!"
					hud_status.modulate = Color(0.98, 0.82, 0.35)
					btn_restart.text = "RETURN TO TITLE"
					GameState.delete_saved_game()
			else:
				hud_status.text = "VICTORY!\nSECTOR SECURED"
				hud_status.modulate = Color(0.58, 0.86, 0.6)
				btn_restart.text = "CONTINUE CLIMBING"
				GameState.save_campaign()
		else:
			hud_status.text = "VICTORY!\nSTAGE CLEARED"
			hud_status.modulate = Color(0.58, 0.86, 0.6)
			btn_restart.text = "PLAY AGAIN"
	else:
		is_game_over = true
		SoundManager.play_game_over(get_tree())
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.delete_saved_game()
		hud_status.text = "GAME OVER\nBASE DESTROYED"
		hud_status.modulate = Color(0.88, 0.42, 0.4)
		btn_restart.text = "RETURN TO MENU"
	
	hud_status.visible = true
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
			return "⚡SPEED T%d" % rpg_mgr.get_branch_tier(player_id)
		"heavy":
			return "💥HEAVY T%d" % rpg_mgr.get_branch_tier(player_id)
		"train":
			return "🚂TRAIN T%d" % rpg_mgr.get_branch_tier(player_id)
		_:
			return "DEFAULT"

func _update_rpg_hud() -> void:
	if hud_rpg_level:
		hud_rpg_level.text = "★ LV.%d [%s]" % [rpg_mgr.level, _branch_tag(1)]
	if hud_rpg_xp:
		hud_rpg_xp.max_value = rpg_mgr.xp_to_next
		hud_rpg_xp.value = rpg_mgr.current_xp
	if hud_gold:
		hud_gold.text = "🪙 GOLD: %d G" % rpg_mgr.gold
	if hud_p1_hp and p1_instance and is_instance_valid(p1_instance):
		hud_p1_hp.text = "P1 [YEL] HP: %d / %d [%s]" % [p1_instance.current_health, p1_instance.max_health, _branch_tag(1)]
	if hud_p2_hp and p2_instance and is_instance_valid(p2_instance):
		hud_p2_hp.text = "P2 [GRN] HP: %d / %d [%s]" % [p2_instance.current_health, p2_instance.max_health, _branch_tag(2)]
	if hud_stats:
		if GameState.player_count == 2:
			hud_stats.text = "P1 ⚔️%d ⚡+%d%% | P2 ⚔️%d ⚡+%d%%" % [
				rpg_mgr.get_atk_damage(1), int((rpg_mgr.get_speed_multiplier(1) - 1.0) * 100),
				rpg_mgr.get_atk_damage(2), int((rpg_mgr.get_speed_multiplier(2) - 1.0) * 100)
			]
		else:
			hud_stats.text = "⚔️ ATK: %d | ⚡ SPD: +%d%%\n❤️ REGEN: +%.1f/s" % [
				rpg_mgr.get_atk_damage(1),
				int((rpg_mgr.get_speed_multiplier(1) - 1.0) * 100),
				rpg_mgr.get_regen_rate(1)
			]
