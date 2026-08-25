extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")

func _init() -> void:
	print("==================================================")
	print(">>> RUNNING STATE & SAVE REGRESSION TEST SUITE <<<")
	print("==================================================")
	
	var passed = 0
	var total = 0
	
	total += 1
	if test_max_hp_reward():
		print("  [PASS] Test 1: Max HP reward single source of truth")
		passed += 1
	else:
		print("  [FAIL] Test 1: Max HP reward failed!")

	total += 1
	if test_speed_reward():
		print("  [PASS] Test 2: Speed reward single source of truth")
		passed += 1
	else:
		print("  [FAIL] Test 2: Speed reward failed!")

	total += 1
	if test_cross_scene_level_up():
		print("  [PASS] Test 3: Cross-scene XP level up emits signal")
		passed += 1
	else:
		print("  [FAIL] Test 3: Cross-scene XP level up failed!")

	total += 1
	if test_save_load_roundtrip():
		print("  [PASS] Test 4: Save / Load roundtrip & type preservation")
		passed += 1
	else:
		print("  [FAIL] Test 4: Save / Load roundtrip failed!")

	print("==================================================")
	print(">>> RESULTS: %d / %d TESTS PASSED <<<" % [passed, total])
	print("==================================================")
	
	if passed == total:
		quit(0)
	else:
		quit(1)

func test_max_hp_reward() -> bool:
	GameState.reset_campaign(1)
	if GameState.get_player_max_hp() != 1:
		print("    Error: Initial max HP is not 1")
		return false
	
	GameState.max_hp_lvl += 2
	
	var rpg = RPGManager.new()
	rpg.sync_from_game_state()
	if rpg.get_player_max_hp() != 3:
		print("    Error: RPG max HP is %d, expected 3" % rpg.get_player_max_hp())
		return false
	if rpg.max_hp_lvl != 2:
		return false
	
	rpg.sync_to_game_state()
	if GameState.max_hp_lvl != 2:
		return false
	return true

func test_speed_reward() -> bool:
	GameState.reset_campaign(1)
	if GameState.speed_lvl != 0:
		return false
	
	GameState.speed_lvl += 1
	
	var rpg = RPGManager.new()
	rpg.sync_from_game_state()
	if rpg.speed_lvl != 1:
		print("    Error: RPG speed_lvl is %d, expected 1" % rpg.speed_lvl)
		return false
	
	rpg.sync_to_game_state()
	if GameState.speed_lvl != 1:
		print("    Error: GameState speed_lvl is %d, expected 1" % GameState.speed_lvl)
		return false
	return true

func test_cross_scene_level_up() -> bool:
	GameState.reset_campaign(1)
	GameState.player_xp += 350
	
	var rpg = RPGManager.new()
	var emitted_levels: Array[int] = []
	rpg.leveled_up.connect(func(lvl): emitted_levels.append(lvl))
	
	rpg.sync_from_game_state()
	
	if rpg.level != 3:
		print("    Error: RPG level is %d, expected 3" % rpg.level)
		return false
	if emitted_levels.size() != 2 or emitted_levels != [2, 3]:
		print("    Error: Emitted levels are %s, expected [2, 3]" % str(emitted_levels))
		return false
	return true

func test_save_load_roundtrip() -> bool:
	GameState.reset_campaign(2)
	GameState.gold = 380
	GameState.player_tier = 2
	GameState.p2_tier = 1
	GameState.player_lives = 4
	GameState.max_hp_lvl = 3
	GameState.speed_lvl = 2
	GameState.current_floor = 3
	# 楼层房间图的一些可观测状态: 当前在哪间房、清了几间、秘密房炸开了没。
	var probe_room := str(GameState.floor_boss_room)
	GameState.current_room = probe_room
	GameState.rooms_cleared = 5
	GameState.secret_room_found = true
	GameState.floor_rooms[probe_room]["cleared"] = true
	GameState.floor_rooms[probe_room]["visited"] = true
	# run_seed 决定这一局抽到哪批手搓地图 (MapTemplates._pick_from_pool)。
	# 它必须跟着存档走: 存了不读回来的话, 同一个存档每次读进来都会换一批
	# 地形 —— 已经打过的楼层也会跟着变脸。
	var saved_seed := GameState.run_seed
	if saved_seed == 0:
		print("    Error: reset_campaign() 没有生成 run_seed")
		return false

	GameState.save_campaign()
	if not GameState.has_saved_game():
		print("    Error: Save file was not created")
		return false
	
	GameState.reset_campaign(1)
	
	if not GameState.load_campaign():
		print("    Error: Failed to load campaign")
		return false
	
	if GameState.player_count != 2: return false
	if GameState.gold != 380: return false
	if GameState.player_tier != 2: return false
	if GameState.p2_tier != 1: return false
	if GameState.player_lives != 4: return false
	if GameState.max_hp_lvl != 3: return false
	if GameState.speed_lvl != 2: return false
	if GameState.current_floor != 3: return false
	if GameState.current_room != probe_room:
		print("    Error: current_room 没存回来 (存 %s, 读 %s)" % [probe_room, GameState.current_room])
		return false
	if GameState.rooms_cleared != 5: return false
	if not GameState.secret_room_found:
		print("    Error: secret_room_found 没存回来 —— 读档后裂缝墙会重新长回去")
		return false
	if GameState.run_seed != saved_seed:
		print("    Error: run_seed 没存回来 (存 %d, 读 %d) —— 地图会每次读档都变"
			% [saved_seed, GameState.run_seed])
		return false

	# 嵌套结构的还原。floor_rooms 在 test_persistence_roundtrip.gd 里是被
	# EXEMPT 掉的 (那份测试用 str() 比字段, 比不了字典套字典), 所以它的
	# 类型还原必须在这里盯。JSON 把所有数字读成 float —— col/row/depth
	# 要是留着 float, FloorMap 里所有整数比较和键拼接都会在 float 上做。
	if GameState.floor_rooms.is_empty():
		print("    Error: floor_rooms 读回来是空的")
		return false
	for k in GameState.floor_rooms.keys():
		var room = GameState.floor_rooms[k]
		if typeof(room["col"]) != TYPE_INT or typeof(room["row"]) != TYPE_INT:
			print("    Error: 房间 %s 的 col/row 不是 int" % k)
			return false
		if typeof(room["depth"]) != TYPE_INT:
			print("    Error: 房间 %s 的 depth 不是 int" % k)
			return false
		if not (room["doors"] is Array) or room["doors"].size() != 4:
			print("    Error: 房间 %s 的 doors 不是长度 4 的数组" % k)
			return false
	if not bool(GameState.floor_rooms[probe_room]["cleared"]):
		print("    Error: 房间的 cleared 标记没穿过存档")
		return false
	
	GameState.delete_saved_game()
	return true
