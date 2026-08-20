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

var player_ref: CharacterBody2D = null

func _ready() -> void:
	turret_scene = load("res://scenes/buildings/defense_turret.tscn")
	wall_scene = load("res://scenes/buildings/fortified_wall.tscn")
	mine_scene = load("res://scenes/buildings/landmine.tscn")
	repair_scene = load("res://scenes/buildings/repair_station.tscn")
	preview_sprite.visible = false

func select_structure(type: StructureType) -> void:
	current_selection = type
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
		if event.keycode == KEY_1:
			select_structure(StructureType.TURRET)
		elif event.keycode == KEY_2:
			select_structure(StructureType.FORTIFIED_WALL)
		elif event.keycode == KEY_3:
			select_structure(StructureType.LANDMINE)
		elif event.keycode == KEY_4:
			select_structure(StructureType.REPAIR_STATION)
		elif event.keycode == KEY_Q or event.keycode == KEY_ESCAPE:
			select_structure(StructureType.NONE)
		elif event.keycode == KEY_E or event.keycode == KEY_F:
			_try_place_current()

func _process(_delta: float) -> void:
	if current_selection == StructureType.NONE:
		preview_sprite.visible = false
		return

	var place_pos = _get_target_placement_pos()
	preview_sprite.global_position = place_pos

	# 检查金币与放置合法性
	var main = get_tree().current_scene
	var cost = costs.get(current_selection, 999)
	var can_afford = (main.rpg_mgr.gold >= cost) if (main and main.rpg_mgr) else false

	if can_afford:
		preview_sprite.modulate = Color(0.3, 1.5, 0.4, 0.65)
	else:
		preview_sprite.modulate = Color(2.5, 0.3, 0.3, 0.65)

func _get_target_placement_pos() -> Vector2:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		var p = players[0]
		var front_pos = p.global_position + p.facing_direction * 48.0
		# 对齐到 48px 网格
		var gx = round((front_pos.x - 24.0) / 48.0) * 48.0 + 24.0
		var gy = round((front_pos.y - 24.0) / 48.0) * 48.0 + 24.0
		return Vector2(gx, gy)
	return get_global_mouse_position()

func _try_place_current() -> void:
	if current_selection == StructureType.NONE:
		return
	
	var main = get_tree().current_scene
	var cost = costs.get(current_selection, 999)
	if not main or not main.rpg_mgr or not main.rpg_mgr.spend_gold(cost):
		if main and main.has_method("show_toast"):
			main.show_toast("NOT ENOUGH GOLD! NEED %dG" % cost)
		return

	var place_pos = _get_target_placement_pos()
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
		SoundManager.play_hit_steel(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("PLACED %s (-%dG)" % [name_str, cost])
