class_name BuilderController
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const BunkerScript = preload("res://scripts/buildings/bunker.gd")

enum StructureType { NONE, TURRET, FORTIFIED_WALL, ELECTRIC_WALL, STREET_LAMP, OIL_BARREL, LANDMINE, REPAIR_STATION, SHIELD_STATION, WIND_BLOWER, MISSILE_STRIKE, TIMED_BOMB, ROLLER_WALL, PIPE, BUNKER, WOODEN_WALL }

## Battle-placement no longer spends gold directly (see GameState.structure_inventory) --
## these structures are shop-only stock now: buy N in shop_dialog.gd's Building
## Supplies section (persists across battles), each placement here consumes
## one unit. structure_ids maps each StructureType to the string key
## GameState.structure_inventory and shop_dialog.gd's BUILDING_ITEMS use.
var structure_ids = {
	StructureType.TURRET: "turret",
	StructureType.FORTIFIED_WALL: "fortified_wall",
	StructureType.ELECTRIC_WALL: "electric_wall",
	StructureType.STREET_LAMP: "street_lamp",
	StructureType.OIL_BARREL: "oil_barrel",
	StructureType.LANDMINE: "landmine",
	StructureType.REPAIR_STATION: "repair_station",
	StructureType.SHIELD_STATION: "shield_station",
	StructureType.WIND_BLOWER: "wind_blower",
	StructureType.MISSILE_STRIKE: "missile_strike",
	StructureType.TIMED_BOMB: "timed_bomb",
	StructureType.ROLLER_WALL: "roller_wall",
	StructureType.PIPE: "pipe_conduit",
	StructureType.BUNKER: "bunker",
	StructureType.WOODEN_WALL: "wooden_wall"
}

@onready var preview_sprite_p1: Sprite2D = get_node_or_null("PreviewSprite")
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
var roller_wall_scene: PackedScene
var pipe_scene: PackedScene
var bunker_scene: PackedScene
var wooden_wall_scene: PackedScene

# Per-player hotbar state so P1 and P2 never clobber each other's selection.
var selection_by_pid: Dictionary = {1: StructureType.NONE, 2: StructureType.NONE}

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
	StructureType.TIMED_BOMB,
	StructureType.ROLLER_WALL,
	StructureType.PIPE,
	StructureType.BUNKER,
	StructureType.WOODEN_WALL
]

var structure_names = {
	StructureType.TURRET: "DEFENSE TURRET",
	StructureType.FORTIFIED_WALL: "FORTIFIED WALL",
	StructureType.ELECTRIC_WALL: "ELECTRIC WALL",
	StructureType.STREET_LAMP: "STREET LAMP",
	StructureType.OIL_BARREL: "OIL BARREL",
	StructureType.LANDMINE: "EMP LANDMINE",
	StructureType.REPAIR_STATION: "REPAIR BEACON",
	StructureType.SHIELD_STATION: "SHIELD RECHARGER",
	StructureType.WIND_BLOWER: "WIND TURBINE",
	StructureType.MISSILE_STRIKE: "TACTICAL MISSILE",
	StructureType.TIMED_BOMB: "TIMED BOMB",
	StructureType.ROLLER_WALL: "ROLLER WALL",
	StructureType.PIPE: "CONDUIT PIPE",
	StructureType.BUNKER: "TACTICAL BUNKER",
	StructureType.WOODEN_WALL: "WOODEN WALL"
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
	roller_wall_scene = load("res://scenes/buildings/roller_wall.tscn")
	pipe_scene = load("res://scenes/buildings/pipe_conduit.tscn")
	bunker_scene = load("res://scenes/buildings/bunker.tscn")
	wooden_wall_scene = load("res://scenes/buildings/wooden_wall.tscn")

	if not preview_sprite_p1:
		preview_sprite_p1 = Sprite2D.new()
		add_child(preview_sprite_p1)
	preview_sprite_p2 = Sprite2D.new()
	add_child(preview_sprite_p2)

	preview_sprite_p1.visible = false
	preview_sprite_p2.visible = false

func _preview_sprite(pid: int) -> Sprite2D:
	return preview_sprite_p1 if pid == 1 else preview_sprite_p2

## Only structures with GameState stock > 0 -- the hotbar (and cycling
## through it) should only ever offer things you actually have, not the full
## fixed catalog regardless of what's in inventory. Recomputed on every call
## since stock changes mid-battle (placing one, buying more next visit).
func _get_available_structures() -> Array[StructureType]:
	var avail: Array[StructureType] = []
	for t in structure_list:
		if GameState.get_structure_stock(structure_ids.get(t, "")) > 0:
			avail.append(t)
	return avail

func _show_no_stock_toast(pid: int) -> void:
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("show_toast"):
		main_scene.show_toast("P%d 没有可用道具库存 —— 请去商店购买！" % pid)

func cycle_prev(pid: int = 1) -> void:
	var avail = _get_available_structures()
	if avail.is_empty():
		_show_no_stock_toast(pid)
		select_structure(StructureType.NONE, pid)
		return
	var idx = avail.find(selection_by_pid.get(pid, StructureType.NONE))
	idx = avail.size() - 1 if idx <= 0 else idx - 1
	select_structure(avail[idx], pid)
	_notify_selection(pid)

func cycle_next(pid: int = 1) -> void:
	var avail = _get_available_structures()
	if avail.is_empty():
		_show_no_stock_toast(pid)
		select_structure(StructureType.NONE, pid)
		return
	var idx = avail.find(selection_by_pid.get(pid, StructureType.NONE))
	idx = (idx + 1) % avail.size()
	select_structure(avail[idx], pid)
	_notify_selection(pid)

func _notify_selection(pid: int) -> void:
	var selection = selection_by_pid.get(pid, StructureType.NONE)
	var name_tag = structure_names.get(selection, "UNKNOWN")
	var stock = GameState.get_structure_stock(structure_ids.get(selection, ""))
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("show_toast"):
		var place_key = "F" if pid == 1 else "K"
		main_scene.show_toast("P%d [%s] (库存 x%d) | [%s] 放置" % [pid, name_tag, stock, place_key])

func select_structure(type: StructureType, pid: int = 1) -> void:
	var main_scene = get_tree().current_scene

	# Guards every entry point (hotbar cycling already filters to in-stock
	# items via _get_available_structures(), but the quick number-key
	# shortcuts below call select_structure() directly) -- you can never end
	# up with a zero-stock structure selected.
	if type != StructureType.NONE and GameState.get_structure_stock(structure_ids.get(type, "")) <= 0:
		if main_scene and main_scene.has_method("show_toast"):
			main_scene.show_toast("库存不足，无法选择 [%s] —— 请去商店购买" % structure_names.get(type, "UNKNOWN"))
		return

	selection_by_pid[pid] = type
	var preview_sprite = _preview_sprite(pid)
	if type == StructureType.NONE:
		preview_sprite.visible = false
		if main_scene and "hud_hotbar" in main_scene and main_scene.hud_hotbar and pid == 1:
			UIThemeHelper.update_hotbar_selection(main_scene.hud_hotbar, "")
		return

	if main_scene and "hud_hotbar" in main_scene and main_scene.hud_hotbar and pid == 1:
		UIThemeHelper.update_hotbar_selection(main_scene.hud_hotbar, structure_ids.get(type, ""))

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
		StructureType.ROLLER_WALL: tex_path = "res://assets/sprites/buildings/roller_wall.png"
		StructureType.PIPE: tex_path = "res://assets/sprites/buildings/pipe_conduit.png"
		StructureType.BUNKER: tex_path = "res://assets/sprites/buildings/bunker.png"
		StructureType.WOODEN_WALL: tex_path = "res://assets/sprites/buildings/wooden_wall.png"

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

	# 建造走 input action 而不是原始 keycode —— 原来那套 event.keycode == KEY_Q
	# 的写法把整个建造系统锁死在键盘上, 手柄玩家一个建筑都放不了 (移动和开火
	# 早就有手柄绑定, 唯独这里没有)。
	# 键盘按键没变: Q/Z E/C F R 和 U/J O/L K/Enter Backspace 都还在, 只是搬进了
	# project.godot 的 p1_build_* / p2_build_* 里, 每个 action 另外挂了手柄键。
	# 手柄布局 (两名玩家各自的设备): LB=上一个 X=下一个 Y=放置 BACK=取消。
	# 刻意避开 B: 它是内置 ui_cancel 的默认绑定 —— 见下面 cancel 处的注释。
	for pid in [1, 2]:
		if event.is_action_pressed("p%d_build_prev" % pid):
			cycle_prev(pid)
			return
		if event.is_action_pressed("p%d_build_next" % pid):
			cycle_next(pid)
			return
		if event.is_action_pressed("p%d_build_place" % pid):
			if selection_by_pid.get(pid, StructureType.NONE) == StructureType.NONE:
				cycle_next(pid) # 未选中时先开热键栏
			else:
				_try_place_current(pid)
			return
		if event.is_action_pressed("p%d_build_cancel" % pid):
			# ESC/B 刻意*不*绑在这里 —— main.gd 的 _unhandled_input 用
			# ui_cancel/pause 开暂停菜单, 两个处理器会在同一次按键上都触发:
			# 既取消了选择又弹出暂停菜单。键盘留 R/Backspace, 手柄留 BACK。
			select_structure(StructureType.NONE, pid)
			return

	if event is InputEventKey and event.pressed:
		# 数字键 1..6 直选 —— 仅 P1, 键盘专属的便捷方式, 手柄用 LB/X 循环即可
		if event.keycode == KEY_1: select_structure(StructureType.TURRET, 1)
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
		var has_stock = GameState.get_structure_stock(structure_ids.get(selection, "")) > 0

		if has_stock and is_valid:
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
	# pos 是 _get_target_placement_pos() 算出来的**全局**坐标(基于
	# p.global_position), 但 min_bound/max_bound 是按 13x13 地图的**局部**
	# 格心范围写的 (0..624 网格, 排除半格边距)。BuilderController 本身挂在
	# GameArea 下且没有额外偏移, 用 to_local() 换算成同一套坐标系再比较 ——
	# 换算前, 全局的最后一行/列(局部 600, 全局 648, 老鹰所在那一整行)会被
	# 误判越界, 玩家在地图最右列/最下一行(含老鹰旁边)完全放不了任何建筑。
	var min_bound = 24.0
	var max_bound = 13.0 * 48.0 - 24.0
	var local_pos = to_local(pos)
	if local_pos.x < min_bound or local_pos.x > max_bound or local_pos.y < min_bound or local_pos.y > max_bound:
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
	var struct_id = structure_ids.get(selection, "")
	if not main or not GameState.consume_structure_stock(struct_id):
		if main and main.has_method("show_toast"):
			main.show_toast("库存不足！去商店购买 [%s]" % structure_names.get(selection, "UNKNOWN"))
		return

	if pid == 1 and "hud_hotbar" in main and main.hud_hotbar:
		UIThemeHelper.update_hotbar_stock(main.hud_hotbar)

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
			main.show_toast("呼叫战术导弹打击！(剩余库存 x%d)" % GameState.get_structure_stock(struct_id))
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
			main.show_toast("放置定时炸弹！(剩余库存 x%d)" % GameState.get_structure_stock(struct_id))
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
		StructureType.ROLLER_WALL:
			new_struct = roller_wall_scene.instantiate()
			name_str = "ROLLER WALL"
		StructureType.PIPE:
			new_struct = pipe_scene.instantiate()
			name_str = "CONDUIT PIPE"
			var players = get_tree().get_nodes_in_group("p%d" % pid)
			if players.size() > 0 and is_instance_valid(players[0]):
				var p = players[0]
				var f_dir = p.facing_direction
				if absf(f_dir.x) > absf(f_dir.y):
					if f_dir.x > 0:
						new_struct.set_orientation(PipeConduit.Orientation.LEFT_TO_UP)
					else:
						new_struct.set_orientation(PipeConduit.Orientation.RIGHT_TO_DOWN)
				else:
					if f_dir.y > 0:
						new_struct.set_orientation(PipeConduit.Orientation.UP_TO_RIGHT)
					else:
						new_struct.set_orientation(PipeConduit.Orientation.DOWN_TO_LEFT)

		StructureType.BUNKER:
			new_struct = bunker_scene.instantiate()
			name_str = "TACTICAL BUNKER"
			var players = get_tree().get_nodes_in_group("p%d" % pid)
			if players.size() > 0 and is_instance_valid(players[0]):
				var p = players[0]
				var f_dir = p.facing_direction
				if absf(f_dir.x) > absf(f_dir.y):
					if f_dir.x > 0:
						new_struct.set_facing(BunkerScript.FacingDirection.RIGHT)
					else:
						new_struct.set_facing(BunkerScript.FacingDirection.LEFT)
				else:
					if f_dir.y > 0:
						new_struct.set_facing(BunkerScript.FacingDirection.DOWN)
					else:
						new_struct.set_facing(BunkerScript.FacingDirection.UP)

		StructureType.WOODEN_WALL:
			new_struct = wooden_wall_scene.instantiate()
			name_str = "WOODEN WALL"

	if new_struct:
		main.actors_container.add_child(new_struct)
		new_struct.global_position = place_pos
		# 落成特效: 全项目唯一向内收敛的一组, 末帧最实 —— "东西被造出来了"
		# 靠收束感传达, 和所有向外炸开的效果正好相反。
		VFXAnimator.spawn_build_assemble(main.actors_container, place_pos)
		SoundManager.play_build(get_tree())
		if main.has_method("show_toast"):
			main.show_toast("PLACED %s (剩余库存 x%d)" % [name_str, GameState.get_structure_stock(struct_id)])
