class_name MainGame
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")
const SpawnStar = preload("res://scripts/spawn_star.gd")

const TILE_SIZE: float = 48.0
const GRID_W: int = 13
const GRID_H: int = 13

var player_scene: PackedScene
var enemy_scene: PackedScene
var base_scene: PackedScene
var powerup_scene: PackedScene
var spawnstar_scene: PackedScene

var tex_brick: Texture2D
var tex_steel: Texture2D
var tex_water: Texture2D
var tex_trees: Texture2D
var tex_ice: Texture2D

@onready var game_area: Node2D = $GameArea
@onready var map_container: Node2D = $GameArea/MapContainer
@onready var base_wall_container: Node2D = $GameArea/BaseWallContainer
@onready var actors_container: Node2D = $GameArea/ActorsContainer
@onready var hud_score: Label = $HUD/SidePanel/VBox/ScoreLabel
@onready var hud_lives: Label = $HUD/SidePanel/VBox/LivesLabel
@onready var hud_enemies: Label = $HUD/SidePanel/VBox/EnemiesLabel
@onready var hud_status: Label = $HUD/CenterMessage
@onready var hud_toast: Label = $HUD/SidePanel/VBox/ToastLabel
@onready var btn_restart: Button = $HUD/RestartButton

var score: int = 0
var player_lives: int = 3
var total_enemies: int = 20
var enemies_spawned: int = 0
var enemies_alive: int = 0
var is_game_over: bool = false
var is_victory: bool = false

var player_instance: CharacterBody2D = null
var base_instance: Area2D = null
var spawn_timer: float = 0.0
var spawn_interval: float = 2.8

var enemy_spawn_points: Array[Vector2] = []
var player_spawn_point: Vector2 = Vector2.ZERO

var shovel_timer: float = 0.0
var is_shovel_active: bool = false

func _ready() -> void:
	player_scene = load("res://scenes/player.tscn")
	enemy_scene = load("res://scenes/enemy.tscn")
	base_scene = load("res://scenes/base_eagle.tscn")
	powerup_scene = load("res://scenes/power_up.tscn")
	spawnstar_scene = load("res://scenes/spawn_star.tscn")

	tex_brick = TextureHelper.get_tex("res://assets/sprites/tiles/tile_brick.png")
	tex_steel = TextureHelper.get_tex("res://assets/sprites/tiles/tile_steel.png")
	tex_water = TextureHelper.get_tex("res://assets/sprites/tiles/tile_water.png")
	tex_trees = TextureHelper.get_tex("res://assets/sprites/tiles/tile_trees.png")
	tex_ice = TextureHelper.get_tex("res://assets/sprites/tiles/tile_ice.png")

	btn_restart.pressed.connect(restart_game)
	btn_restart.visible = false
	hud_status.visible = false

	var origin_x = 48.0
	var origin_y = 48.0
	game_area.position = Vector2(origin_x, origin_y)

	enemy_spawn_points = [
		Vector2(1.0 * TILE_SIZE, 1.0 * TILE_SIZE),
		Vector2(6.5 * TILE_SIZE, 1.0 * TILE_SIZE),
		Vector2(12.0 * TILE_SIZE, 1.0 * TILE_SIZE)
	]
	player_spawn_point = Vector2(4.5 * TILE_SIZE, 12.0 * TILE_SIZE)

	start_game()

func start_game() -> void:
	score = 0
	player_lives = 3
	total_enemies = 20
	enemies_spawned = 0
	enemies_alive = 0
	is_game_over = false
	is_victory = false
	shovel_timer = 0.0
	is_shovel_active = false
	hud_status.visible = false
	btn_restart.visible = false

	_clear_all()
	_build_map()
	_spawn_base_and_walls(false)
	_spawn_player()
	_update_hud()
	show_toast("STAGE 1 - START!")

func _clear_all() -> void:
	for child in map_container.get_children():
		child.queue_free()
	for child in base_wall_container.get_children():
		child.queue_free()
	for child in actors_container.get_children():
		child.queue_free()

func _build_map() -> void:
	var map_pixel_w = (GRID_W + 1) * TILE_SIZE
	var map_pixel_h = (GRID_H + 1) * TILE_SIZE

	_create_border_wall(Vector2(-TILE_SIZE/2, map_pixel_h/2 - TILE_SIZE/2), Vector2(TILE_SIZE, map_pixel_h + TILE_SIZE*2))
	_create_border_wall(Vector2(map_pixel_w + TILE_SIZE/2, map_pixel_h/2 - TILE_SIZE/2), Vector2(TILE_SIZE, map_pixel_h + TILE_SIZE*2))
	_create_border_wall(Vector2(map_pixel_w/2 - TILE_SIZE/2, -TILE_SIZE/2), Vector2(map_pixel_w + TILE_SIZE*2, TILE_SIZE))
	_create_border_wall(Vector2(map_pixel_w/2 - TILE_SIZE/2, map_pixel_h + TILE_SIZE/2), Vector2(map_pixel_w + TILE_SIZE*2, TILE_SIZE))

	var layout = [
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		[0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 0, 2, 2, 2, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0],
		[0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0],
		[2, 2, 0, 1, 1, 3, 3, 3, 1, 1, 0, 2, 2],
		[0, 0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0],
		[0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	]

	for r in range(layout.size()):
		for c in range(layout[r].size()):
			var tile_type = layout[r][c]
			var pos = Vector2((c + 0.5) * TILE_SIZE, (r + 0.5) * TILE_SIZE)
			if tile_type == 1:
				_spawn_tile("brick", pos, tex_brick)
			elif tile_type == 2:
				_spawn_tile("steel", pos, tex_steel)
			elif tile_type == 3:
				_spawn_tile("water", pos, tex_water)
			elif tile_type == 4:
				_spawn_tile("trees", pos, tex_trees)

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

func _spawn_tile(type: String, pos: Vector2, tex: Texture2D) -> void:
	if not tex:
		return
	if type == "trees":
		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(0.38, 0.38)
		spr.position = pos
		spr.z_index = 10
		map_container.add_child(spr)
		return

	var body = StaticBody2D.new()
	body.position = pos
	body.add_to_group(type)
	
	var spr = Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(0.38, 0.38)
	body.add_child(spr)

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
	col.shape = shape
	body.add_child(col)

	map_container.add_child(body)

func _spawn_base_and_walls(use_steel: bool = false) -> void:
	for child in base_wall_container.get_children():
		child.queue_free()

	# 基地自身
	base_instance = base_scene.instantiate()
	base_instance.position = Vector2(6.5 * TILE_SIZE, 12.5 * TILE_SIZE)
	base_instance.destroyed.connect(_on_base_destroyed)
	base_wall_container.add_child(base_instance)

	# 环绕基地的保护墙
	var wall_positions = [
		Vector2(5.5 * TILE_SIZE, 12.5 * TILE_SIZE),
		Vector2(5.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(6.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(7.5 * TILE_SIZE, 11.5 * TILE_SIZE),
		Vector2(7.5 * TILE_SIZE, 12.5 * TILE_SIZE)
	]

	var group_name = "steel" if use_steel else "brick"
	var tex = tex_steel if use_steel else tex_brick

	for p in wall_positions:
		var body = StaticBody2D.new()
		body.position = p
		body.add_to_group(group_name)
		var spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(0.38, 0.38)
		body.add_child(spr)
		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		col.shape = shape
		body.add_child(col)
		base_wall_container.add_child(body)

func trigger_shovel(duration: float = 15.0) -> void:
	is_shovel_active = true
	shovel_timer = duration
	_spawn_base_and_walls(true)
	show_toast("BASE REINFORCED WITH STEEL!")

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
	show_toast("BOMB TRIGGERED! %d ENEMIES DESTROYED" % count)

func add_life(amount: int = 1) -> void:
	player_lives += amount
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

func _spawn_player() -> void:
	if player_lives <= 0 or not player_scene:
		_game_over(false)
		return
	player_instance = player_scene.instantiate()
	player_instance.position = player_spawn_point
	player_instance.destroyed.connect(_on_player_destroyed)
	player_instance.powerup_collected.connect(func(type_name): show_toast("GOT %s!" % type_name))
	actors_container.add_child(player_instance)
	_update_hud()

func _process(delta: float) -> void:
	if is_shovel_active:
		shovel_timer -= delta
		if shovel_timer <= 3.0:
			# 快结束时闪烁
			base_wall_container.modulate.a = 0.4 if int(shovel_timer * 6.0) % 2 == 0 else 1.0
		if shovel_timer <= 0.0:
			is_shovel_active = false
			base_wall_container.modulate.a = 1.0
			_spawn_base_and_walls(false)
			show_toast("BASE STEEL EXPIRED")

	if is_game_over or is_victory:
		if Input.is_action_just_pressed("restart"):
			restart_game()
		return

	# 刷怪调度
	if enemies_spawned < total_enemies and enemies_alive < 4:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			_request_spawn_enemy()

func _request_spawn_enemy() -> void:
	if enemies_spawned >= total_enemies:
		return
	
	var spawn_idx = enemies_spawned % enemy_spawn_points.size()
	var spawn_pos = enemy_spawn_points[spawn_idx]
	
	# 判断是否为携带道具的闪烁坦克 (第 4, 11, 18 辆)
	var is_bonus = (enemies_spawned in [3, 10, 17])
	
	# 敌军类型权重
	var type = EnemyTank.EnemyType.BASIC
	var r = randf()
	if r < 0.40:
		type = EnemyTank.EnemyType.BASIC
	elif r < 0.65:
		type = EnemyTank.EnemyType.FAST
	elif r < 0.85:
		type = EnemyTank.EnemyType.POWER
	else:
		type = EnemyTank.EnemyType.ARMOR

	# 播放闪烁星生成指示器
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
	_update_hud()

	# 爆出道具
	if is_bonus and powerup_scene:
		var p_inst = powerup_scene.instantiate()
		var types = [PowerUp.Type.STAR, PowerUp.Type.BOMB, PowerUp.Type.CLOCK, PowerUp.Type.HELMET, PowerUp.Type.SHOVEL, PowerUp.Type.LIFE]
		types.shuffle()
		p_inst.setup(types[0])
		# 随机选择一个合适的位置（或在敌军死亡位置）
		p_inst.position = drop_pos
		actors_container.add_child(p_inst)
		show_toast("BONUS ITEM DROPPED!")

	if enemies_spawned >= total_enemies and enemies_alive <= 0:
		_game_over(true)

func _on_player_destroyed() -> void:
	player_lives -= 1
	SoundManager.play_explosion(get_tree())
	_update_hud()
	if player_lives > 0:
		get_tree().create_timer(1.5).timeout.connect(_spawn_player)
	else:
		_game_over(false)

func _on_base_destroyed() -> void:
	_game_over(false)

func _game_over(victory: bool) -> void:
	if is_game_over or is_victory:
		return
	if victory:
		is_victory = true
		hud_status.text = "VICTORY!\nSTAGE CLEARED"
		hud_status.modulate = Color(0.2, 1.0, 0.4)
	else:
		is_game_over = true
		hud_status.text = "GAME OVER\nBASE DESTROYED"
		hud_status.modulate = Color(1.0, 0.2, 0.2)
	
	hud_status.visible = true
	btn_restart.visible = true

func _update_hud() -> void:
	hud_score.text = "SCORE: %06d" % score
	hud_lives.text = "LIVES: %d" % player_lives
	var remaining = total_enemies - enemies_spawned + enemies_alive
	hud_enemies.text = "ENEMIES: %d" % remaining

func restart_game() -> void:
	start_game()
