class_name BuilderController
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

enum StructureType { NONE, TURRET, FORTIFIED_WALL, LANDMINE, REPAIR_STATION }

var current_selection: StructureType = StructureType.NONE
var costs = {
	StructureType.TURRET: 80,
	StructureType.FORTIFIED_WALL: 25,
	StructureType.LANDMINE: 40,
	StructureType.REPAIR_STATION: 120
}

@onready var preview_sprite: Sprite2D = $PreviewSprite

var turret_scene: PackedScene
var wall_scene: PackedScene
var mine_scene: PackedScene
var repair_scene: PackedScene

var active_builder_pid: int = 1

func _ready() -> void:
	turret_scene = load("res://scenes/buildings/defense_turret.tscn")
	wall_scene = load("res://scenes/buildings/fortified_wall.tscn")
	mine_scene = load("res://scenes/buildings/landmine.tscn")
	repair_scene = load("res://scenes/buildings/repair_station.tscn")
	preview_sprite.visible = false

func select_structure(type: StructureType, pid: int = 1) -> void:
	current_selection = type
	active_builder_pid = pid
	if current_selection == StructureType.NONE:
		preview_sprite.visible = false
		return
	
	preview_sprite.visible = true
	var tex_path = ""
	match current_selection:
		StructureType.TURRET: tex_path = "res://assets/sprites/buildings/turret_gun.png"
		StructureType.FORTIFIED_WALL: tex_path = "res://assets/sprites/buildings/fortified_wall.png"
		StructureType.LANDMINE: tex_path = "res://assets/sprites/buildings/landmine.png"
		StructureType.REPAIR_STATION: tex_path = "res://assets/sprites/buildings/repair_station.png"
	
	var tex = TextureHelper.get_tex(tex_path)
	if tex:
		preview_sprite.texture = tex

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# P1 Controls
		if event.keycode == KEY_1:
			select_structure(StructureType.TURRET, 1)
		elif event.keycode == KEY_2:
			select_structure(StructureType.FORTIFIED_WALL, 1)
		elif event.keycode == KEY_3:
			select_structure(StructureType.LANDMINE, 1)
		elif event.keycode == KEY_4:
			select_structure(StructureType.REPAIR_STATION, 1)
		elif event.keycode == KEY_Q or event.keycode == KEY_ESCAPE:
			select_structure(StructureType.NONE, 1)
		elif event.keycode == KEY_E or event.keycode == KEY_F:
			_try_place_current()
		# P2 / Alternative Controls
		elif event.keycode == KEY_7:
			select_structure(StructureType.TURRET, 2)
		elif event.keycode == KEY_8:
			select_structure(StructureType.FORTIFIED_WALL, 2)
		elif event.keycode == KEY_9:
			select_structure(StructureType.LANDMINE, 2)
		elif event.keycode == KEY_0:
			select_structure(StructureType.REPAIR_STATION, 2)
		elif event.keycode == KEY_U or event.keycode == KEY_O:
			_try_place_current()

func _process(_delta: float) -> void:
	if current_selection == StructureType.NONE:
		preview_sprite.visible = false
		return

	var place_pos = _get_target_placement_pos()
	preview_sprite.global_position = place_pos

	var is_valid = _is_placement_valid(place_pos)
	var main = get_tree().current_scene
	var cost = costs.get(current_selection, 999)
	var can_afford = (main.rpg_mgr.gold >= cost) if (main and main.rpg_mgr) else false

	if can_afford and is_valid:
		preview_sprite.modulate = Color(0.3, 1.8, 0.4, 0.70)
	else:
		preview_sprite.modulate = Color(2.5, 0.2, 0.2, 0.70)

func _get_target_placement_pos() -> Vector2:
	var target_group = "p%d" % active_builder_pid
	var players = get_tree().get_nodes_in_group(target_group)
	if players.is_empty():
		players = get_tree().get_nodes_in_group("player")
	
	if players.size() > 0 and is_instance_valid(players[0]):
		var p = players[0]
		var front_pos = p.global_position + p.facing_direction * 48.0
		var gx = round((front_pos.x - 24.0) / 48.0) * 48.0 + 24.0
		var gy = round((front_pos.y - 24.0) / 48.0) * 48.0 + 24.0
		return Vector2(gx, gy)
	return get_global_mouse_position()

func _is_placement_valid(pos: Vector2) -> bool:
	var min_bound = 24.0
	var max_bound = 13.0 * 48.0 - 24.0
	if pos.x < min_bound or pos.x > max_bound or pos.y < min_bound or pos.y > max_bound:
		return false

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 1 | 16 # Walls, terrain, border, buildings, base eagle
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits = space_state.intersect_point(query, 4)
	return hits.is_empty()

func _try_place_current() -> void:
	if current_selection == StructureType.NONE:
		return
	
	var place_pos = _get_target_placement_pos()
	if not _is_placement_valid(place_pos):
		var main_scene = get_tree().current_scene
		if main_scene and main_scene.has_method("show_toast"):
			main_scene.show_toast("CANNOT PLACE HERE (BLOCKED)!")
		return

	var main = get_tree().current_scene
	var cost = costs.get(current_selection, 999)
	if not main or not main.rpg_mgr or not main.rpg_mgr.spend_gold(cost):
		if main and main.has_method("show_toast"):
			main.show_toast("NOT ENOUGH GOLD! NEED %dG" % cost)
		return

	var new_struct: Node2D = null
	var name_str = ""

	match current_selection:
		StructureType.TURRET:
			new_struct = turret_scene.instantiate()
			name_str = "DEFENSE TURRET"
		StructureType.FORTIFIED_WALL:
			new_struct = wall_scene.instantiate()
			name_str = "FORTIFIED WALL"
		StructureType.LANDMINE:
			new_struct = mine_scene.instantiate()
			name_str = "EMP LANDMINE"
		StructureType.REPAIR_STATION:
			new_struct = repair_scene.instantiate()
			name_str = "REPAIR BEACON"

	if new_struct:
		new_struct.global_position = place_pos
		main.actors_container.add_child(new_struct)
		SoundManager.play_build(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("PLACED %s (-%dG)" % [name_str, cost])
