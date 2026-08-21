class_name BuilderController
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

enum StructureType { NONE, TURRET, FORTIFIED_WALL, ELECTRIC_WALL, STREET_LAMP, OIL_BARREL, LANDMINE, REPAIR_STATION, SHIELD_STATION, WIND_BLOWER, MISSILE_STRIKE, TIMED_BOMB }

var costs = {
	StructureType.TURRET: 80,
	StructureType.FORTIFIED_WALL: 25,
	StructureType.ELECTRIC_WALL: 50,
	StructureType.STREET_LAMP: 45,
	StructureType.OIL_BARREL: 55,
	StructureType.LANDMINE: 40,
	StructureType.REPAIR_STATION: 120,
	StructureType.SHIELD_STATION: 100,
	StructureType.WIND_BLOWER: 70,
	StructureType.MISSILE_STRIKE: 90,
	StructureType.TIMED_BOMB: 60
}

@onready var preview_sprite_p1: Sprite2D = $PreviewSprite
var preview_sprite_p2: Sprite2D

var turret_scene: PackedScene
var wall_scene: PackedScene
var electric_wall_scene: PackedScene
var street_lamp_scene: PackedScene
var oil_barrel_scene: PackedScene
var mine_scene: PackedScene
var repair_scene: PackedScene
var shield_scene: PackedScene
var wind_scene: PackedScene
var missile_strike_scene: PackedScene
var timed_bomb_scene: PackedScene

# Per-player hotbar state so P1 and P2 never clobber each other's selection.
var selection_by_pid: Dictionary = {1: StructureType.NONE, 2: StructureType.NONE}
var index_by_pid: Dictionary = {1: -1, 2: -1} # -1 = NONE

var structure_list: Array[StructureType] = [
	StructureType.TURRET,
	StructureType.FORTIFIED_WALL,
	StructureType.ELECTRIC_WALL,
	StructureType.STREET_LAMP,
	StructureType.OIL_BARREL,
	StructureType.LANDMINE,
	StructureType.REPAIR_STATION,
	StructureType.SHIELD_STATION,
	StructureType.WIND_BLOWER,
	StructureType.MISSILE_STRIKE,
	StructureType.TIMED_BOMB
]

var structure_names = {
	StructureType.TURRET: "🔫 DEFENSE TURRET",
	StructureType.FORTIFIED_WALL: "🧱 FORTIFIED WALL",
	StructureType.ELECTRIC_WALL: "⚡ ELECTRIC WALL",
	StructureType.STREET_LAMP: "💡 STREET LAMP",
	StructureType.OIL_BARREL: "🛢️ OIL BARREL",
	StructureType.LANDMINE: "💣 EMP LANDMINE",
	StructureType.REPAIR_STATION: "🔧 REPAIR BEACON",
	StructureType.SHIELD_STATION: "🛡️ SHIELD RECHARGER",
	StructureType.WIND_BLOWER: "💨 WIND TURBINE",
	StructureType.MISSILE_STRIKE: "🚀 TACTICAL MISSILE",
	StructureType.TIMED_BOMB: "💣 TIMED BOMB"
}

func _ready() -> void:
	turret_scene = load("res://scenes/buildings/defense_turret.tscn")
	wall_scene = load("res://scenes/buildings/fortified_wall.tscn")
	electric_wall_scene = load("res://scenes/buildings/electric_wall.tscn")
	street_lamp_scene = load("res://scenes/buildings/street_lamp.tscn")
	oil_barrel_scene = load("res://scenes/buildings/oil_barrel.tscn")
	mine_scene = load("res://scenes/buildings/landmine.tscn")
	repair_scene = load("res://scenes/buildings/repair_station.tscn")
	shield_scene = load("res://scenes/buildings/shield_station.tscn")
	wind_scene = load("res://scenes/buildings/wind_blower.tscn")
	missile_strike_scene = load("res://scenes/missile_strike.tscn")
	timed_bomb_scene = load("res://scenes/timed_bomb.tscn")

	preview_sprite_p2 = Sprite2D.new()
	add_child(preview_sprite_p2)

	preview_sprite_p1.visible = false
	preview_sprite_p2.visible = false

func _preview_sprite(pid: int) -> Sprite2D:
	return preview_sprite_p1 if pid == 1 else preview_sprite_p2

func cycle_prev(pid: int = 1) -> void:
	var idx: int = index_by_pid.get(pid, -1)
	if selection_by_pid.get(pid, StructureType.NONE) == StructureType.NONE or idx < 0:
		idx = structure_list.size() - 1
	else:
		idx = (idx - 1 + structure_list.size()) % structure_list.size()
	index_by_pid[pid] = idx
	select_structure(structure_list[idx], pid)
	_notify_selection(pid)

func cycle_next(pid: int = 1) -> void:
	var idx: int = index_by_pid.get(pid, -1)
	if selection_by_pid.get(pid, StructureType.NONE) == StructureType.NONE or idx < 0:
		idx = 0
	else:
		idx = (idx + 1) % structure_list.size()
	index_by_pid[pid] = idx
	select_structure(structure_list[idx], pid)
	_notify_selection(pid)

func _notify_selection(pid: int) -> void:
	var selection = selection_by_pid.get(pid, StructureType.NONE)
	var name_tag = structure_names.get(selection, "UNKNOWN")
	var cost_val = costs.get(selection, 0)
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("show_toast"):
		var place_key = "F" if pid == 1 else "K"
		main_scene.show_toast("P%d [%s] (%dG) | [%s] 放置" % [pid, name_tag, cost_val, place_key])

func select_structure(type: StructureType, pid: int = 1) -> void:
	selection_by_pid[pid] = type
	var preview_sprite = _preview_sprite(pid)
	var main_scene = get_tree().current_scene
	if type == StructureType.NONE:
		index_by_pid[pid] = -1
		preview_sprite.visible = false
		if main_scene and "hud_hotbar" in main_scene and main_scene.hud_hotbar and pid == 1:
			UIThemeHelper.update_hotbar_selection(main_scene.hud_hotbar, -1)
		return

	index_by_pid[pid] = structure_list.find(type)
	if main_scene and "hud_hotbar" in main_scene and main_scene.hud_hotbar and pid == 1:
		UIThemeHelper.update_hotbar_selection(main_scene.hud_hotbar, index_by_pid[pid])

	preview_sprite.visible = true
	var tex_path = ""
	match type:
		StructureType.TURRET: tex_path = "res://assets/sprites/buildings/turret_gun.png"
		StructureType.FORTIFIED_WALL: tex_path = "res://assets/sprites/buildings/fortified_wall.png"
		StructureType.ELECTRIC_WALL: tex_path = "res://assets/sprites/tiles/tile_electric_wall_f0.png"
		StructureType.STREET_LAMP: tex_path = "res://assets/sprites/buildings/street_lamp.png"
		StructureType.OIL_BARREL: tex_path = "res://assets/sprites/buildings/oil_barrel.png"
		StructureType.LANDMINE: tex_path = "res://assets/sprites/buildings/landmine.png"
		StructureType.REPAIR_STATION: tex_path = "res://assets/sprites/buildings/repair_station.png"
		StructureType.SHIELD_STATION: tex_path = "res://assets/sprites/buildings/shield_station.png"
		StructureType.WIND_BLOWER: tex_path = "res://assets/sprites/buildings/wind_blower.png"
		StructureType.MISSILE_STRIKE: tex_path = "res://assets/sprites/powerups/missile_strike.png"
		StructureType.TIMED_BOMB: tex_path = "res://assets/sprites/buildings/prop_timed_bomb.png"

	var tex = TextureHelper.get_tex(tex_path)
	if tex:
		preview_sprite.texture = tex

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Local co-op has one shared mouse; by convention it drives P1's hotbar.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_next(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_prev(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			select_structure(StructureType.NONE, 1)

	if event is InputEventKey and event.pressed:
		# P1 Main Controls: [Q] ◀ Prev | [E] ▶ Next | [F] Place
		if event.keycode == KEY_Q or event.keycode == KEY_Z:
			cycle_prev(1)
		elif event.keycode == KEY_E or event.keycode == KEY_C:
			cycle_next(1)
		elif event.keycode == KEY_F:
			if selection_by_pid.get(1, StructureType.NONE) == StructureType.NONE:
				cycle_next(1) # Open hotbar
			else:
				_try_place_current(1)
		elif event.keycode == KEY_ESCAPE or event.keycode == KEY_R:
			select_structure(StructureType.NONE, 1)

		# P2 Controls: [U] ◀ Prev | [O] ▶ Next | [K] Place
		elif event.keycode == KEY_U or event.keycode == KEY_J:
			cycle_prev(2)
		elif event.keycode == KEY_O or event.keycode == KEY_L:
			cycle_next(2)
		elif event.keycode == KEY_K or event.keycode == KEY_ENTER:
			if selection_by_pid.get(2, StructureType.NONE) == StructureType.NONE:
				cycle_next(2)
			else:
				_try_place_current(2)
		elif event.keycode == KEY_BACKSPACE:
			select_structure(StructureType.NONE, 2)

		# Quick number direct select fallback (1..6) — P1 only
		elif event.keycode == KEY_1: select_structure(StructureType.TURRET, 1)
		elif event.keycode == KEY_2: select_structure(StructureType.FORTIFIED_WALL, 1)
		elif event.keycode == KEY_3: select_structure(StructureType.LANDMINE, 1)
		elif event.keycode == KEY_4: select_structure(StructureType.REPAIR_STATION, 1)
		elif event.keycode == KEY_5: select_structure(StructureType.SHIELD_STATION, 1)
		elif event.keycode == KEY_6: select_structure(StructureType.WIND_BLOWER, 1)

func _process(_delta: float) -> void:
	for pid in [1, 2]:
		var preview_sprite = _preview_sprite(pid)
		var selection = selection_by_pid.get(pid, StructureType.NONE)
		if selection == StructureType.NONE:
			preview_sprite.visible = false
			continue

		var place_pos = _get_target_placement_pos(pid)
		preview_sprite.visible = true
		preview_sprite.global_position = place_pos

		var is_valid = _is_placement_valid(place_pos)
		var main = get_tree().current_scene
		var cost = costs.get(selection, 999)
		var can_afford = (main.rpg_mgr.gold >= cost) if (main and main.rpg_mgr) else false

		if can_afford and is_valid:
			preview_sprite.modulate = Color(0.3, 1.8, 0.4, 0.70)
		else:
			preview_sprite.modulate = Color(2.5, 0.2, 0.2, 0.70)

func _get_target_placement_pos(pid: int) -> Vector2:
	var target_group = "p%d" % pid
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
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40.0, 40.0)
	query.shape = shape
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1 | 16 # Walls, terrain, border, buildings, base eagle
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits = space_state.intersect_shape(query, 4)
	return hits.is_empty()

func _try_place_current(pid: int) -> void:
	var selection = selection_by_pid.get(pid, StructureType.NONE)
	if selection == StructureType.NONE:
		return

	var place_pos = _get_target_placement_pos(pid)
	if selection != StructureType.MISSILE_STRIKE and not _is_placement_valid(place_pos):
		var main_scene = get_tree().current_scene
		if main_scene and main_scene.has_method("show_toast"):
			main_scene.show_toast("CANNOT PLACE HERE (BLOCKED)!")
		return

	var main = get_tree().current_scene
	var cost = costs.get(selection, 999)
	if not main or not main.rpg_mgr or not main.rpg_mgr.spend_gold(cost):
		if main and main.has_method("show_toast"):
			main.show_toast("NOT ENOUGH GOLD! NEED %dG" % cost)
		return

	if selection == StructureType.MISSILE_STRIKE:
		if missile_strike_scene:
			var strike = missile_strike_scene.instantiate()
			strike.team = "player"
			strike.aim_duration = 1.6
			strike.damage = 6
			main.actors_container.add_child(strike)
			strike.global_position = place_pos
		SoundManager.play_shot(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("🚀 呼叫战术导弹打击！(-%dG)" % cost)
		return

	if selection == StructureType.TIMED_BOMB:
		if timed_bomb_scene:
			var bomb = timed_bomb_scene.instantiate()
			bomb.team = "player"
			bomb.countdown = 2.2
			bomb.blast_range = 3
			bomb.damage = 4
			main.actors_container.add_child(bomb)
			bomb.global_position = place_pos
		SoundManager.play_build(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("💣 放置定时炸弹！(-%dG)" % cost)
		return

	var new_struct: Node2D = null
	var name_str = ""

	match selection:
		StructureType.TURRET:
			new_struct = turret_scene.instantiate()
			name_str = "DEFENSE TURRET"
		StructureType.FORTIFIED_WALL:
			new_struct = wall_scene.instantiate()
			name_str = "FORTIFIED WALL"
		StructureType.ELECTRIC_WALL:
			new_struct = electric_wall_scene.instantiate()
			name_str = "ELECTRIC WALL"
		StructureType.STREET_LAMP:
			new_struct = street_lamp_scene.instantiate()
			name_str = "STREET LAMP"
		StructureType.OIL_BARREL:
			new_struct = oil_barrel_scene.instantiate()
			name_str = "OIL BARREL"
		StructureType.LANDMINE:
			new_struct = mine_scene.instantiate()
			name_str = "EMP LANDMINE"
		StructureType.REPAIR_STATION:
			new_struct = repair_scene.instantiate()
			name_str = "REPAIR BEACON"
		StructureType.SHIELD_STATION:
			new_struct = shield_scene.instantiate()
			name_str = "SHIELD RECHARGER"
		StructureType.WIND_BLOWER:
			new_struct = wind_scene.instantiate()
			name_str = "WIND TURBINE"
			# Face same direction as player
			var players = get_tree().get_nodes_in_group("p%d" % pid)
			if players.size() > 0 and is_instance_valid(players[0]):
				var p = players[0]
				if abs(p.facing_direction.x) > abs(p.facing_direction.y):
					if p.facing_direction.x > 0:
						new_struct.set_direction(WindBlower.Direction.RIGHT)
					else:
						new_struct.set_direction(WindBlower.Direction.LEFT)
				else:
					if p.facing_direction.y > 0:
						new_struct.set_direction(WindBlower.Direction.DOWN)
					else:
						new_struct.set_direction(WindBlower.Direction.UP)

	if new_struct:
		main.actors_container.add_child(new_struct)
		new_struct.global_position = place_pos
		SoundManager.play_build(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("PLACED %s (-%dG)" % [name_str, cost])
