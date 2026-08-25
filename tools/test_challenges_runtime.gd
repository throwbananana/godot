extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const DarknessFog = preload("res://scripts/darkness_fog.gd")
const FallingBombHazard = preload("res://scripts/falling_bomb_hazard.gd")
const FloorMap = preload("res://scripts/floor_map.gd")

func _init() -> void:
	print("=== Running Challenge Modes & Hazards Runtime Test ===")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var MainGameScene = load("res://scenes/main.tscn")

	# Test 1: 楼层生成里的挑战房。
	#
	# 挑战房是分给**死胡同**的 (FloorMap._assign_types), 而一张图能不能分到
	# 挑战房 取决于 boss/商店/宝物房先拿走之后还剩几个死胡同 —— 小地图
	# 完全可能一个都不剩。所以这里扫多个种子, 只要有一层楼分出了挑战房
	# 就算通过; 卡成"每层必须有"的话, 测试会在完全正常的小地图上随机变红。
	print("1. Testing Floor Map Challenge Room Generation...")
	var found_challenges = 0
	for attempt in range(12):
		GameState.reset_campaign(1)
		for k in GameState.floor_rooms.keys():
			var room = GameState.floor_rooms[k]
			if room["type"] == "challenge":
				found_challenges += 1
				print("   Found challenge room [%s] mode: %s" % [k, room.get("challenge_mode", "N/A")])
				assert(room.get("challenge_mode", "") in ["bomb_rain", "night_ops", "vault", "night_bombs"], "Invalid challenge mode!")
		if found_challenges > 0:
			break
	assert(found_challenges > 0, "No challenge rooms found across 12 generated floors!")
	print("   ✓ Floor Map Challenge Room Generation OK!")

	# Test 2: Night Mode (DarknessFog) Initialization and Real-time Tracking
	print("2. Testing DarknessFog Night Mode...")
	GameState.mode = GameState.GameMode.CAMPAIGN

	var main_inst = MainGameScene.instantiate()
	root.add_child(main_inst)
	_enter_forced_challenge_room(main_inst, "night_ops")

	assert(main_inst.is_night_mode_active == true, "Night mode should be active!")
	assert(main_inst.darkness_fog_instance != null, "DarknessFog instance should be created!")
	assert(is_instance_valid(main_inst.darkness_fog_instance), "DarknessFog instance should be valid in scene tree!")

	# Test dynamic light flashes
	main_inst.darkness_fog_instance.add_flash(Vector2(200, 200), 180.0, 0.3)
	assert(main_inst.darkness_fog_instance.flashes.size() == 1, "Flash should be registered!")
	print("   ✓ DarknessFog Night Mode OK!")

	main_inst.queue_free()

	# Test 3: Bomb Rain Hazard Spawning and Detonation
	print("3. Testing Bomb Rain (Falling Bomb Hazard)...")
	var main_inst_bomb = MainGameScene.instantiate()
	root.add_child(main_inst_bomb)
	_enter_forced_challenge_room(main_inst_bomb, "bomb_rain")

	assert(main_inst_bomb.is_bomb_rain_active == true, "Bomb rain should be active!")
	
	# Manually trigger a falling bomb spawn
	main_inst_bomb._spawn_falling_bomb()
	var found_hazard = false
	for child in main_inst_bomb.actors_container.get_children():
		if child is FallingBombHazard:
			found_hazard = true
			# Advance and land the bomb immediately
			child._land()
			break
	assert(found_hazard, "FallingBombHazard should be spawned in actors container!")
	
	# Verify TimedBomb was placed on landing
	var found_timed_bomb = false
	for child in main_inst_bomb.actors_container.get_children():
		if child.is_in_group("timed_bomb"):
			found_timed_bomb = true
			# Trigger instant detonation test
			child.detonate()
			break
	assert(found_timed_bomb, "TimedBomb should be spawned upon bomb landing!")
	print("   ✓ Bomb Rain Falling Bomb & Detonation OK!")

	main_inst_bomb.queue_free()

	# Test 4: Campaign Persistence with Challenge Mode
	print("4. Testing Campaign Persistence for Challenge Mode...")
	GameState.challenge_mode = "night_bombs"
	GameState.save_campaign()
	GameState.challenge_mode = ""
	var loaded = GameState.load_campaign()
	assert(loaded, "Failed to load campaign save!")
	assert(GameState.challenge_mode == "night_bombs", "Challenge mode was not restored correctly!")
	GameState.delete_saved_game()
	print("   ✓ Campaign Persistence OK!")

	print("\n🎉 ALL CHALLENGE TESTS PASSED PERFECTLY! 🎉")
	quit(0)


## 把本层的一间战斗房强行改造成指定模式的挑战房, 然后走进去。
##
## 以前这里是"先设 GameState.battle_type/challenge_mode, 再实例化 main.tscn",
## 房间化之后那一套不再成立: battle_type 和 challenge_mode 现在是
## **从房间类型推出来的** (GameState.visit_room), 外部先赋的值会在进房间时
## 被盖掉 —— 而 main.tscn 一启动进的是起始房 (battle_type 回到 "battle",
## challenge_mode 回到空), 于是夜战雾根本不会开。
##
## 改成直接改房间数据再 enter_room(), 走的就是真实路径, 而且不依赖
## "这一层刚好摇出了 night_ops 挑战房"这种随机性。
func _enter_forced_challenge_room(main_node, mode: String) -> void:
	var target := ""
	for k in GameState.floor_rooms.keys():
		if FloorMap.is_combat_room(GameState.floor_rooms[k]):
			target = str(k)
			break
	assert(target != "", "本层找不到任何战斗房")
	GameState.floor_rooms[target]["type"] = "challenge"
	GameState.floor_rooms[target]["challenge_mode"] = mode
	main_node.enter_room(target, -1)
