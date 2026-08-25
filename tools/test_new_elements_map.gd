extends SceneTree

const MapTemplatesScript = preload("res://scripts/map_templates.gd")
const RadarStationScript = preload("res://scripts/buildings/radar_station.gd")
const AmmoDepotScript = preload("res://scripts/buildings/ammo_depot.gd")
const CommandPostScript = preload("res://scripts/buildings/command_post.gd")
const SniperNestScript = preload("res://scripts/buildings/sniper_nest.gd")
const EMPTowerScript = preload("res://scripts/buildings/emp_tower.gd")
const PipeConduitScript = preload("res://scripts/buildings/pipe_conduit.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING NEW ELEMENTS & MAP TEMPLATES TESTS <<<")
	print("==================================================")

	_test_new_building_scenes_and_scripts()
	_test_new_map_templates_structure_and_base_fit()
	_test_map_pools_and_floor_gating()

	print("\n>>> ALL NEW ELEMENTS & MAP TEMPLATES TESTS PASSED! <<<")
	quit(0)

func _test_new_building_scenes_and_scripts() -> void:
	print("\n[STEP 1] 验证所有新建筑场景与脚本实例化与基本功能...")

	var building_specs = [
		{"path": "res://scenes/buildings/radar_station.tscn", "group": "radar_station", "hp": 10},
		{"path": "res://scenes/buildings/ammo_depot.tscn", "group": "ammo_depot", "hp": 6},
		{"path": "res://scenes/buildings/command_post.tscn", "group": "command_post", "hp": 18},
		{"path": "res://scenes/buildings/sniper_nest.tscn", "group": "sniper_nest", "hp": 8},
		{"path": "res://scenes/buildings/emp_tower.tscn", "group": "emp_tower", "hp": 10},
		{"path": "res://scenes/buildings/pipe_conduit.tscn", "group": "pipe_conduit", "hp": 4}
	]

	for spec in building_specs:
		var scene = load(spec["path"])
		assert(scene != null, "场景文件 %s 必须存在并能成功加载" % spec["path"])
		var inst = scene.instantiate() as Node2D
		assert(inst != null, "场景 %s 必须能成功实例化" % spec["path"])
		root.add_child(inst)

		assert(inst.is_in_group(spec["group"]), "实例必须属于组 %s" % spec["group"])
		assert(inst.is_in_group("building") or inst.is_in_group("buildings"), "实例必须属于 building/buildings 组")
		assert(inst.is_in_group("destructible"), "实例必须属于 destructible 组")
		assert(inst.current_health == spec["hp"], "%s 初始 HP 必须为 %d, 实际为 %d" % [spec["group"], spec["hp"], inst.current_health])

		# 测试受击
		inst.take_damage(1)
		assert(inst.current_health == spec["hp"] - 1, "%s 受击后 HP 必须正确扣减" % spec["group"])

		inst.queue_free()

	print("  [PASS] 所有 6 类新建筑场景与脚本验证通过。")

func _test_new_map_templates_structure_and_base_fit() -> void:
	print("\n[STEP 2] 验证 5 张新地图模板的网格尺寸 (13x13) 与鹰巢保留区合法性...")

	var new_templates = [
		{"name": "TEMPLATE_CONDUIT_CROSSFIRE", "grid": MapTemplatesScript.TEMPLATE_CONDUIT_CROSSFIRE},
		{"name": "TEMPLATE_RADAR_COMMAND_CENTER", "grid": MapTemplatesScript.TEMPLATE_RADAR_COMMAND_CENTER},
		{"name": "TEMPLATE_EMP_TESLA_LABYRINTH", "grid": MapTemplatesScript.TEMPLATE_EMP_TESLA_LABYRINTH},
		{"name": "TEMPLATE_SNIPER_AMMO_DEPOT", "grid": MapTemplatesScript.TEMPLATE_SNIPER_AMMO_DEPOT},
		{"name": "TEMPLATE_PIPELINE_PINBALL_NEXUS", "grid": MapTemplatesScript.TEMPLATE_PIPELINE_PINBALL_NEXUS},
	]

	for t in new_templates:
		var name = t["name"]
		var grid = t["grid"]
		assert(grid.size() == 13, "%s 行数必须正好为 13, 实际为 %d" % [name, grid.size()])

		for r in range(13):
			assert(grid[r].size() == 13, "%s 第 %d 行列数必须为 13, 实际为 %d" % [name, r, grid[r].size()])
			for c in range(13):
				var tile = grid[r][c]
				assert(tile >= 0 and tile <= 39, "%s 在 (%d,%d) 的瓦片值 %d 超出合法范围 [0..39]" % [name, r, c, tile])

		# 验证鹰巢保护区：第 11~12 行的 col 5~7 必须全部为 0 (留给 main.gd 动态生成老鹰与防护砖)
		for r in [11, 12]:
			for c in [5, 6, 7]:
				assert(grid[r][c] == 0, "%s 在鹰巢保护区 (%d,%d) 必须为 0, 实际为 %d" % [name, r, c, grid[r][c]])

		# 验证第 0 行敌人出生点 (col 0, 6, 12) 没有被不可穿过的砖墙/钢墙死封
		for c in [0, 6, 12]:
			assert(grid[0][c] == 0, "%s 在第 0 行敌人出生区 (%d) 必须为 0" % [name, c])

	print("  [PASS] 5 张全新地图模板全部符合 13x13 几何规格与鹰巢/出生点保护标准。")

func _test_map_pools_and_floor_gating() -> void:
	print("\n[STEP 3] 验证新模板在 TEMPLATE_MIN_FLOOR 门禁与地图池中的注册...")

	var templates_to_check = [
		MapTemplatesScript.TEMPLATE_CONDUIT_CROSSFIRE,
		MapTemplatesScript.TEMPLATE_RADAR_COMMAND_CENTER,
		MapTemplatesScript.TEMPLATE_EMP_TESLA_LABYRINTH,
		MapTemplatesScript.TEMPLATE_SNIPER_AMMO_DEPOT,
		MapTemplatesScript.TEMPLATE_PIPELINE_PINBALL_NEXUS
	]

	for t in templates_to_check:
		assert(MapTemplatesScript.TEMPLATE_MIN_FLOOR.has(t), "新模板必须在 TEMPLATE_MIN_FLOOR 中注册门禁楼层")
		var min_f = MapTemplatesScript.TEMPLATE_MIN_FLOOR[t]
		assert(min_f == 2 or min_f == 5, "新模板门禁必须为合理档位 (2 或 5), 实际为 %d" % min_f)

	# 验证 get_layout_for_stage 针对不同 act / battle_type 能正确返回地图
	for act in [1, 2, 3]:
		for btype in ["battle", "elite", "challenge"]:
			var layout = MapTemplatesScript.get_layout_for_stage(6, btype, act, false)
			assert(layout.size() == 13 and layout[0].size() == 13, "获取 Act %d %s 阶段地图必须返回有效 13x13 数组" % [act, btype])

	print("  [PASS] 门禁楼层与地图池抽取调度机制测试通过。")
