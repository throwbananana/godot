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

func _ready() -> void:
	player_scene = load("res://scenes/player.tscn")
	enemy_scene = load("res://scenes/enemy.tscn")
	base_scene = load("res://scenes/base_eagle.tscn")
	powerup_scene = load("res://scenes/power_up.tscn")
	spawnstar_scene = load("res://scenes/spawn_star.tscn")
	landmine_hazard_scene = load("res://scenes/landmine_hazard.tscn")

	tex_brick = TextureHelper.get_tex("res://assets/sprites/tiles/tile_brick.png")
	tex_steel = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	tex_trees = TextureHelper.get_tex("res://assets/sprites/tiles/tile_trees.png")
	tex_sand = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand.png")
	tex_sand_dune = TextureHelper.get_tex("res://assets/sprites/tiles/tile_sand_dune.png")

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

	var layout = MapTemplates.get_layout_for_stage(GameState.current_floor, GameState.battle_type)

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

func add_life(amount: int = 1) -> void:
	p1_lives += amount
	if GameState.player_count == 2:
		p2_lives += amount
	if GameState.mode == GameState.GameMode.CAMPAIGN:
		GameState.player_lives = p1_lives
		GameState.p2_lives = p2_lives
	_update_hud()
	show_toast("+1 EXTRA LIFE!")

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
		hud_p1_hp.text = "P1 [YEL] HP: %d / %d" % [curr, max_hp]
	elif pid == 2 and hud_p2_hp:
		hud_p2_hp.text = "P2 [GRN] HP: %d / %d" % [curr, max_hp]

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

	if GameState.battle_type == "boss":
		if enemies_spawned == 0 or enemies_spawned == total_enemies - 1:
			type = EnemyTank.EnemyType.BOSS
			show_toast("⚠️ SUMMIT COLOSSUS DETECTED! ⚠️")
			add_trauma(0.50)
		elif r < 0.25: type = EnemyTank.EnemyType.ARMOR
		elif r < 0.52: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.78: type = EnemyTank.EnemyType.LASER
		else: type = EnemyTank.EnemyType.POWER
	elif GameState.battle_type == "elite":
		if r < 0.25: type = EnemyTank.EnemyType.ARMOR
		elif r < 0.55: type = EnemyTank.EnemyType.MISSILE
		elif r < 0.80: type = EnemyTank.EnemyType.LASER
		else: type = EnemyTank.EnemyType.POWER
	else:
		match floor_idx:
			0:
				type = EnemyTank.EnemyType.BASIC if r < 0.65 else EnemyTank.EnemyType.FAST
			1:
				if r < 0.40: type = EnemyTank.EnemyType.BASIC
				elif r < 0.70: type = EnemyTank.EnemyType.FAST
				else: type = EnemyTank.EnemyType.POWER
			2:
				if r < 0.45: type = EnemyTank.EnemyType.DESERT
				elif r < 0.70: type = EnemyTank.EnemyType.FAST
				elif r < 0.88: type = EnemyTank.EnemyType.POWER
				else: type = EnemyTank.EnemyType.ARMOR
			3:
				if r < 0.35: type = EnemyTank.EnemyType.DESERT
				elif r < 0.60: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.80: type = EnemyTank.EnemyType.ARMOR
				else: type = EnemyTank.EnemyType.LASER
			4:
				if r < 0.20: type = EnemyTank.EnemyType.DESERT
				elif r < 0.45: type = EnemyTank.EnemyType.ARMOR
				elif r < 0.75: type = EnemyTank.EnemyType.MISSILE
				else: type = EnemyTank.EnemyType.LASER
			_:
				if r < 0.25: type = EnemyTank.EnemyType.DESERT
				elif r < 0.50: type = EnemyTank.EnemyType.MISSILE
				elif r < 0.75: type = EnemyTank.EnemyType.LASER
				else: type = EnemyTank.EnemyType.ARMOR

	var star = spawnstar_scene.instantiate()
	star.position = spawn_pos
	star.finished.connect(func(): _instantiate_enemy(spawn_pos, type, is_bonus))
	actors_container.add_child(star)
	
	enemies_spawned += 1
	enemies_alive += 1
	_update_hud()

func _instantiate_enemy(pos: Vector2, type: EnemyTank.EnemyType, is_bonus: bool) -> void:
	if not enemy_scene:
		return
	var enemy = enemy_scene.instantiate()
	enemy.position = pos
	enemy.enemy_type = type
	enemy.is_bonus = is_bonus
	enemy.enemy_destroyed.connect(_on_enemy_destroyed)
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
		var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE]
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
	if pid == 1:
		p1_lives -= 1
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.player_lives = p1_lives
		if p1_lives > 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _spawn_player(1))
	else:
		p2_lives -= 1
		if GameState.mode == GameState.GameMode.CAMPAIGN:
			GameState.p2_lives = p2_lives
		if p2_lives > 0:
			get_tree().create_timer(1.5).timeout.connect(func(): _spawn_player(2))
	
	_update_hud()
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
			GameState.save_campaign()
			if GameState.battle_type == "boss":
				hud_status.text = "👑 VICTORY! 👑\nSPIRE CONQUERED!"
				hud_status.modulate = Color(0.98, 0.82, 0.35)
				btn_restart.text = "RETURN TO TITLE"
				GameState.delete_saved_game()
			else:
				hud_status.text = "VICTORY!\nSECTOR SECURED"
				hud_status.modulate = Color(0.58, 0.86, 0.6)
				btn_restart.text = "CONTINUE CLIMBING"
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
		if is_victory and GameState.battle_type != "boss":
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

func _update_rpg_hud() -> void:
	if hud_rpg_level:
		hud_rpg_level.text = "★ LEVEL: LV.%d" % rpg_mgr.level
	if hud_rpg_xp:
		hud_rpg_xp.max_value = rpg_mgr.xp_to_next
		hud_rpg_xp.value = rpg_mgr.current_xp
	if hud_gold:
		hud_gold.text = "🪙 GOLD: %d G" % rpg_mgr.gold
	if hud_p1_hp and p1_instance and is_instance_valid(p1_instance):
		hud_p1_hp.text = "P1 [YEL] HP: %d / %d" % [p1_instance.current_health, p1_instance.max_health]
	if hud_p2_hp and p2_instance and is_instance_valid(p2_instance):
		hud_p2_hp.text = "P2 [GRN] HP: %d / %d" % [p2_instance.current_health, p2_instance.max_health]
	if hud_stats:
		hud_stats.text = "⚔️ ATK: +%d | ⚡ SPD: +%d%%\n❤️ REGEN: +%.1f/s" % [
			rpg_mgr.atk_bonus,
			int((rpg_mgr.get_speed_multiplier() - 1.0) * 100),
			rpg_mgr.get_regen_rate()
		]
