class_name NetworkBattleSync
extends Node

const GameState = preload("res://scripts/game_state.gd")
const SNAPSHOT_INTERVAL := 0.05
const INPUT_INTERVAL := 1.0 / 30.0
const REMOTE_LERP_SPEED := 18.0

var main: Node = null
var _ready_for_network := false
var _snapshot_timer := 0.0
var _input_timer := 0.0
var _next_entity_id := 1
var _last_round_finished := false
var _round_serial := 1
var _client_round_serial := 0

var _enemy_replicas: Dictionary = {}
var _bullet_replicas: Dictionary = {}
var _pickup_replicas: Dictionary = {}
var _building_replicas: Dictionary = {}

func _ready() -> void:
	if not GameState.online_mode:
		set_process(false)
		return
	call_deferred("_finish_setup")

func _finish_setup() -> void:
	main = get_parent()
	if not main:
		return

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if multiplayer.is_server():
		_configure_host_players()
		if main.has_method("show_toast"):
			main.show_toast("ONLINE HOST — AUTHORITATIVE SIMULATION")
	else:
		# The client renders replicated state only. Disabling MainGame._process also
		# prevents duplicate enemy spawns, shovel timers and local restart logic.
		main.set_process(false)
		if main.builder_ctrl:
			main.builder_ctrl.set_process(false)
			main.builder_ctrl.set_process_unhandled_input(false)
		_configure_client_players()
		if main.btn_restart:
			main.btn_restart.disabled = true
		if main.has_method("show_toast"):
			main.show_toast("ONLINE CLIENT — P2 CONTROL")

	_ready_for_network = true

func _process(delta: float) -> void:
	if not _ready_for_network or not GameState.online_mode:
		return

	if multiplayer.is_server():
		_configure_host_players()
		_track_round_restart()
		_snapshot_timer += delta
		if _snapshot_timer >= SNAPSHOT_INTERVAL:
			_snapshot_timer = 0.0
			_rpc_world_snapshot.rpc(_build_world_snapshot())
	else:
		_input_timer += delta
		if _input_timer >= INPUT_INTERVAL:
			_input_timer = 0.0
			var input_state := _read_client_input()
			_rpc_submit_p2_input.rpc_id(1, input_state[0], input_state[1])
		_interpolate_remote_entities(delta)

func _track_round_restart() -> void:
	var finished := bool(main.is_game_over or main.is_victory)
	if _last_round_finished and not finished:
		_round_serial += 1
	_last_round_finished = finished

func _configure_host_players() -> void:
	if main.p2_instance and is_instance_valid(main.p2_instance):
		if main.p2_instance.has_method("set_network_input_mode"):
			main.p2_instance.set_network_input_mode(true)

func _configure_client_players() -> void:
	for pid in [1, 2]:
		var player = _get_player(pid)
		if player and is_instance_valid(player):
			_prepare_visual_replica(player)

func _read_client_input() -> Array:
	# A remote player can use either the normal P1 layout or the legacy/local P2
	# layout on their own machine. This makes keyboard and controller testing easy.
	var input_vec := Vector2.ZERO
	if Input.is_action_pressed("p1_move_up") or Input.is_action_pressed("p2_move_up"):
		input_vec = Vector2.UP
	elif Input.is_action_pressed("p1_move_down") or Input.is_action_pressed("p2_move_down"):
		input_vec = Vector2.DOWN
	elif Input.is_action_pressed("p1_move_left") or Input.is_action_pressed("p2_move_left"):
		input_vec = Vector2.LEFT
	elif Input.is_action_pressed("p1_move_right") or Input.is_action_pressed("p2_move_right"):
		input_vec = Vector2.RIGHT
	var firing := Input.is_action_pressed("p1_fire") or Input.is_action_pressed("p2_fire")
	return [input_vec, firing]

@rpc("any_peer", "call_remote", "unreliable", 1)
func _rpc_submit_p2_input(input_vec: Vector2, firing: bool) -> void:
	if not multiplayer.is_server() or not GameState.online_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if GameState.network_remote_peer_id != 0 and sender != GameState.network_remote_peer_id:
		return

	var safe_input := _sanitize_cardinal_input(input_vec)
	if main.p2_instance and is_instance_valid(main.p2_instance):
		if main.p2_instance.has_method("set_network_input"):
			main.p2_instance.set_network_input(safe_input, firing)

func _sanitize_cardinal_input(input_vec: Vector2) -> Vector2:
	if input_vec.length_squared() < 0.01:
		return Vector2.ZERO
	if absf(input_vec.x) > absf(input_vec.y):
		return Vector2(signf(input_vec.x), 0.0)
	return Vector2(0.0, signf(input_vec.y))

func _build_world_snapshot() -> Dictionary:
	return {
		"round": _round_serial,
		"players": _collect_player_snapshot(),
		"enemies": _collect_group_snapshot("enemies", "enemy"),
		"bullets": _collect_group_snapshot("bullet", "bullet"),
		"powerups": _collect_group_snapshot("powerups", "powerup"),
		"coins": _collect_group_snapshot("collectibles", "coin"),
		"buildings": _collect_group_snapshot("buildings", "building"),
		"terrain": _collect_terrain_snapshot(),
		"base_alive": main.base_instance != null and is_instance_valid(main.base_instance),
		"hud": _collect_hud_snapshot(),
	}

func _collect_player_snapshot() -> Array:
	var result: Array = []
	for pid in [1, 2]:
		var player = _get_player(pid)
		if player and is_instance_valid(player) and not player.is_queued_for_deletion():
			result.append({
				"pid": pid,
				"pos": player.global_position,
				"rot": player.global_rotation,
				"hp": player.current_health,
				"max_hp": player.max_health,
				"tier": player.upgrade_tier,
				"facing": player.facing_direction,
				"invulnerable": player.is_invulnerable,
			})
	return result

func _collect_group_snapshot(group_name: String, kind: String) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var id := _ensure_network_id(node)
		var data := {
			"id": id,
			"pos": node.global_position,
			"rot": node.global_rotation,
		}
		match kind:
			"enemy":
				data["type"] = int(node.enemy_type)
				data["bonus"] = bool(node.is_bonus)
				data["hp"] = int(node.health)
				data["max_hp"] = int(node.max_health)
			"bullet":
				data["direction"] = node.direction
				data["speed"] = float(node.speed)
				data["damage"] = int(node.damage)
				data["plasma"] = bool(node.can_destroy_steel)
				data["shooter_type"] = str(node.shooter_type)
			"powerup":
				data["powerup_type"] = int(node.power_up_type)
			"coin":
				data["value"] = int(node.value)
			"building":
				data["scene"] = str(node.scene_file_path)
		result.append(data)
	return result

func _collect_terrain_snapshot() -> Array:
	var result: Array = []
	for scope_data in [["map", main.map_container], ["base", main.base_wall_container]]:
		var scope: String = scope_data[0]
		var container: Node = scope_data[1]
		for child in container.get_children():
			if not (child is StaticBody2D) or child.is_in_group("border"):
				continue
			var terrain_type := ""
			if child.is_in_group("brick"):
				terrain_type = "brick"
			elif child.is_in_group("steel"):
				terrain_type = "steel"
			if terrain_type.is_empty():
				continue
			result.append({"scope": scope, "pos": child.position, "type": terrain_type})
	return result

func _collect_hud_snapshot() -> Dictionary:
	return {
		"score": main.hud_score.text,
		"lives": main.hud_lives.text,
		"enemies": main.hud_enemies.text,
		"level": main.hud_rpg_level.text,
		"gold": main.hud_gold.text,
		"p1_hp": main.hud_p1_hp.text,
		"p2_hp": main.hud_p2_hp.text,
		"stats": main.hud_stats.text,
		"status_text": main.hud_status.text,
		"status_visible": main.hud_status.visible,
		"status_modulate": main.hud_status.modulate,
		"restart_text": main.btn_restart.text,
		"restart_visible": main.btn_restart.visible,
		"is_game_over": main.is_game_over,
		"is_victory": main.is_victory,
	}

func _ensure_network_id(node: Node) -> int:
	if not node.has_meta("network_entity_id"):
		node.set_meta("network_entity_id", _next_entity_id)
		_next_entity_id += 1
	return int(node.get_meta("network_entity_id"))

@rpc("authority", "call_remote", "unreliable", 2)
func _rpc_world_snapshot(snapshot: Dictionary) -> void:
	if multiplayer.is_server() or not GameState.online_mode:
		return
	if int(snapshot.get("round", 1)) != _client_round_serial:
		_client_round_serial = int(snapshot.get("round", 1))
		_reset_client_round_visuals()

	_sync_players(snapshot.get("players", []))
	_sync_enemies(snapshot.get("enemies", []))
	_sync_bullets(snapshot.get("bullets", []))
	_sync_pickups(snapshot.get("powerups", []), snapshot.get("coins", []))
	_sync_buildings(snapshot.get("buildings", []))
	_sync_terrain(snapshot.get("terrain", []))
	_sync_base(bool(snapshot.get("base_alive", true)))
	_sync_hud(snapshot.get("hud", {}))

func _reset_client_round_visuals() -> void:
	if not main:
		return
	# Rebuild the deterministic arena locally, then immediately return to
	# snapshot-driven rendering. This also restores destructible terrain between
	# online arcade rounds.
	main._clear_all()
	main._build_map()
	main._spawn_base_and_walls(false)
	main.p1_lives = 3
	main.p2_lives = 3
	main._spawn_player(1)
	main._spawn_player(2)
	_configure_client_players()
	_enemy_replicas.clear()
	_bullet_replicas.clear()
	_pickup_replicas.clear()
	_building_replicas.clear()

func _sync_players(states: Array) -> void:
	var present := {1: false, 2: false}
	for data in states:
		var pid := int(data.get("pid", 0))
		if pid != 1 and pid != 2:
			continue
		present[pid] = true
		var player = _get_player(pid)
		if not player or not is_instance_valid(player):
			main._spawn_player(pid)
			player = _get_player(pid)
		if not player:
			continue
		_prepare_visual_replica(player)
		player.visible = true
		player.current_health = int(data.get("hp", player.current_health))
		player.max_health = int(data.get("max_hp", player.max_health))
		var tier := int(data.get("tier", player.upgrade_tier))
		if tier != player.upgrade_tier:
			player.upgrade_tier = tier
			player._update_tier_appearance()
		player.facing_direction = data.get("facing", player.facing_direction)
		player.is_invulnerable = bool(data.get("invulnerable", false))
		if player.shield_sprite:
			player.shield_sprite.visible = player.is_invulnerable
		_set_remote_target(player, data.get("pos", player.global_position), float(data.get("rot", player.global_rotation)))

	for pid in [1, 2]:
		if not present[pid]:
			var missing = _get_player(pid)
			if missing and is_instance_valid(missing):
				missing.visible = false

func _sync_enemies(states: Array) -> void:
	var seen: Dictionary = {}
	for data in states:
		var id := int(data.get("id", 0))
		seen[id] = true
		var enemy = _enemy_replicas.get(id)
		if not enemy or not is_instance_valid(enemy):
			enemy = main.enemy_scene.instantiate()
			enemy.enemy_type = int(data.get("type", 0))
			enemy.is_bonus = bool(data.get("bonus", false))
			main.actors_container.add_child(enemy)
			_prepare_visual_replica(enemy)
			_enemy_replicas[id] = enemy
		enemy.health = int(data.get("hp", enemy.health))
		enemy.max_health = int(data.get("max_hp", enemy.max_health))
		_set_remote_target(enemy, data.get("pos", enemy.global_position), float(data.get("rot", enemy.global_rotation)))
	_remove_unseen(_enemy_replicas, seen)

func _sync_bullets(states: Array) -> void:
	var seen: Dictionary = {}
	for data in states:
		var id := int(data.get("id", 0))
		seen[id] = true
		var bullet = _bullet_replicas.get(id)
		if not bullet or not is_instance_valid(bullet):
			bullet = main.player_scene # keep typed parser from inferring Variant incorrectly
			bullet = load("res://scenes/bullet.tscn").instantiate()
			bullet.direction = data.get("direction", Vector2.UP)
			bullet.speed = float(data.get("speed", 480.0))
			bullet.damage = int(data.get("damage", 1))
			bullet.can_destroy_steel = bool(data.get("plasma", false))
			bullet.shooter_type = str(data.get("shooter_type", "player"))
			main.actors_container.add_child(bullet)
			_prepare_visual_replica(bullet)
			_bullet_replicas[id] = bullet
		_set_remote_target(bullet, data.get("pos", bullet.global_position), float(data.get("rot", bullet.global_rotation)))
	_remove_unseen(_bullet_replicas, seen)

func _sync_pickups(powerups: Array, coins: Array) -> void:
	var seen: Dictionary = {}
	for data in powerups:
		var id := int(data.get("id", 0))
		var key := "p:%d" % id
		seen[key] = true
		var item = _pickup_replicas.get(key)
		if not item or not is_instance_valid(item):
			item = main.powerup_scene.instantiate()
			item.power_up_type = int(data.get("powerup_type", 0))
			main.actors_container.add_child(item)
			item.setup(item.power_up_type)
			_prepare_visual_replica(item)
			_pickup_replicas[key] = item
		_set_remote_target(item, data.get("pos", item.global_position), float(data.get("rot", item.global_rotation)))

	for data in coins:
		var id := int(data.get("id", 0))
		var key := "c:%d" % id
		seen[key] = true
		var coin = _pickup_replicas.get(key)
		if not coin or not is_instance_valid(coin):
			coin = load("res://scenes/gold_coin.tscn").instantiate()
			coin.value = int(data.get("value", 25))
			main.actors_container.add_child(coin)
			_prepare_visual_replica(coin)
			_pickup_replicas[key] = coin
		_set_remote_target(coin, data.get("pos", coin.global_position), float(data.get("rot", coin.global_rotation)))
	_remove_unseen(_pickup_replicas, seen)

func _sync_buildings(states: Array) -> void:
	var seen: Dictionary = {}
	for data in states:
		var id := int(data.get("id", 0))
		var scene_path := str(data.get("scene", ""))
		if scene_path.is_empty():
			continue
		seen[id] = true
		var building = _building_replicas.get(id)
		if not building or not is_instance_valid(building):
			var packed = load(scene_path)
			if not packed:
				continue
			building = packed.instantiate()
			main.actors_container.add_child(building)
			_prepare_visual_replica(building)
			_building_replicas[id] = building
		_set_remote_target(building, data.get("pos", building.global_position), float(data.get("rot", building.global_rotation)))
	_remove_unseen(_building_replicas, seen)

func _sync_terrain(states: Array) -> void:
	var expected: Dictionary = {}
	for data in states:
		expected[_terrain_key(str(data.get("scope", "map")), data.get("pos", Vector2.ZERO))] = data

	var existing: Dictionary = {}
	for scope_data in [["map", main.map_container], ["base", main.base_wall_container]]:
		var scope: String = scope_data[0]
		var container: Node = scope_data[1]
		for child in container.get_children():
			if not (child is StaticBody2D) or child.is_in_group("border"):
				continue
			if not child.is_in_group("brick") and not child.is_in_group("steel"):
				continue
			var key := _terrain_key(scope, child.position)
			existing[key] = child
			if not expected.has(key):
				child.queue_free()
			else:
				_apply_terrain_type(child, str(expected[key].get("type", "brick")))

	for key in expected.keys():
		if not existing.has(key):
			_create_client_terrain(expected[key])

func _terrain_key(scope: String, pos: Vector2) -> String:
	return "%s:%d:%d" % [scope, roundi(pos.x * 10.0), roundi(pos.y * 10.0)]

func _apply_terrain_type(body: StaticBody2D, terrain_type: String) -> void:
	body.remove_from_group("brick")
	body.remove_from_group("steel")
	body.add_to_group(terrain_type)
	var sprite := body.get_node_or_null("Sprite2D") as Sprite2D
	if not sprite and body.get_child_count() > 0 and body.get_child(0) is Sprite2D:
		sprite = body.get_child(0)
	if sprite:
		sprite.texture = main.tex_steel if terrain_type == "steel" else main.tex_brick

func _create_client_terrain(data: Dictionary) -> void:
	var scope := str(data.get("scope", "map"))
	var terrain_type := str(data.get("type", "brick"))
	var container: Node = main.base_wall_container if scope == "base" else main.map_container
	var body := StaticBody2D.new()
	body.position = data.get("pos", Vector2.ZERO)
	body.add_to_group(terrain_type)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = main.tex_steel if terrain_type == "steel" else main.tex_brick
	sprite.scale = Vector2(48.0 / 256.0, 48.0 / 256.0)
	body.add_child(sprite)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(46.0, 46.0)
	col.shape = shape
	body.add_child(col)
	container.add_child(body)

func _sync_base(base_alive: bool) -> void:
	if main.base_instance and is_instance_valid(main.base_instance):
		main.base_instance.visible = base_alive

func _sync_hud(data: Dictionary) -> void:
	main.hud_score.text = str(data.get("score", main.hud_score.text))
	main.hud_lives.text = str(data.get("lives", main.hud_lives.text))
	main.hud_enemies.text = str(data.get("enemies", main.hud_enemies.text))
	main.hud_rpg_level.text = str(data.get("level", main.hud_rpg_level.text))
	main.hud_gold.text = str(data.get("gold", main.hud_gold.text))
	main.hud_p1_hp.text = str(data.get("p1_hp", main.hud_p1_hp.text))
	main.hud_p2_hp.text = str(data.get("p2_hp", main.hud_p2_hp.text))
	main.hud_stats.text = str(data.get("stats", main.hud_stats.text))
	main.hud_status.text = str(data.get("status_text", main.hud_status.text))
	main.hud_status.visible = bool(data.get("status_visible", false))
	main.hud_status.modulate = data.get("status_modulate", main.hud_status.modulate)
	main.btn_restart.text = "WAIT FOR HOST" if bool(data.get("restart_visible", false)) else str(data.get("restart_text", main.btn_restart.text))
	main.btn_restart.visible = bool(data.get("restart_visible", false))
	main.btn_restart.disabled = true
	main.is_game_over = bool(data.get("is_game_over", false))
	main.is_victory = bool(data.get("is_victory", false))

func _get_player(pid: int):
	return main.p1_instance if pid == 1 else main.p2_instance

func _prepare_visual_replica(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is CollisionObject2D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Area2D:
		node.monitoring = false
		node.monitorable = false

func _set_remote_target(node: Node2D, pos: Vector2, rot: float) -> void:
	node.set_meta("network_target_position", pos)
	node.set_meta("network_target_rotation", rot)

func _interpolate_remote_entities(delta: float) -> void:
	var weight := clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0)
	for pid in [1, 2]:
		var player = _get_player(pid)
		if player and is_instance_valid(player):
			_interpolate_node(player, weight)
	for replica_map in [_enemy_replicas, _bullet_replicas, _pickup_replicas, _building_replicas]:
		for node in replica_map.values():
			if node and is_instance_valid(node):
				_interpolate_node(node, weight)

func _interpolate_node(node: Node2D, weight: float) -> void:
	if node.has_meta("network_target_position"):
		var target_pos: Vector2 = node.get_meta("network_target_position")
		node.global_position = node.global_position.lerp(target_pos, weight)
	if node.has_meta("network_target_rotation"):
		var target_rot: float = float(node.get_meta("network_target_rotation"))
		node.global_rotation = lerp_angle(node.global_rotation, target_rot, weight)

func _remove_unseen(replica_map: Dictionary, seen: Dictionary) -> void:
	for id in replica_map.keys().duplicate():
		if not seen.has(id):
			var node = replica_map[id]
			if node and is_instance_valid(node):
				node.queue_free()
			replica_map.erase(id)

func _on_server_disconnected() -> void:
	if multiplayer.is_server():
		return
	_return_to_title("HOST DISCONNECTED")

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == GameState.network_remote_peer_id:
		_return_to_title("REMOTE PLAYER DISCONNECTED")

func _return_to_title(message: String) -> void:
	if main and main.hud_status:
		main.hud_status.text = message
		main.hud_status.visible = true
	GameState.reset_network()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
