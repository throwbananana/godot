extends SceneTree

const BunkerScript = preload("res://scripts/buildings/bunker.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("==================================================")
	print(">>> RUNNING TACTICAL BUNKER (战术防御堡垒) TESTS <<<")
	print("==================================================")

	_test_bunker_assets_and_instantiation()
	_test_rear_shooting_pass_through()
	_test_frontal_shield_block()
	_test_flank_vulnerability_and_destruction()
	_test_shop_and_builder_metadata()

	print("\n>>> ALL TACTICAL BUNKER TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func _test_bunker_assets_and_instantiation() -> void:
	print("\n[STEP 1] 验证战术堡垒 3D 渲染资产与场景实例...")

	var required_textures = [
		"res://assets/sprites/buildings/bunker.png",
		"res://assets/sprites/buildings/bunker_f0.png",
		"res://assets/sprites/buildings/bunker_f1.png",
		"res://assets/sprites/buildings/bunker_f2.png",
		"res://assets/sprites/buildings/bunker_f3.png"
	]
	for path in required_textures:
		var tex = load(path)
		assert(tex != null, "堡垒贴图必须存在: %s" % path)

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	assert(bunker_scene != null, "bunker.tscn 场景必须存在")
	var bunker = bunker_scene.instantiate()
	root.add_child(bunker)

	assert(bunker.is_in_group("building"), "必须属于 building 组")
	assert(bunker.is_in_group("bunker"), "必须属于 bunker 组")
	assert(bunker.max_health == 6, "堡垒基础生命值必须为 6")
	assert(bunker.current_health == 6, "初始生命值必须为 6")

	bunker.queue_free()
	print("  [PASS] 资产加载与场景实例测试通过。")

func _test_rear_shooting_pass_through() -> void:
	print("\n[STEP 2] 验证躲在堡垒后方向前射击 (穿透射击孔出膛)...")

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	var bunker = bunker_scene.instantiate()
	bunker.set_facing(BunkerScript.FacingDirection.UP)
	root.add_child(bunker)

	# 模拟从后方飞向前方的玩家子弹 (dir = Vector2.UP, 与堡垒朝向一致)
	var bullet = Node2D.new()
	bullet.set_script(load("res://scripts/bullet.gd"))
	bullet.set("direction", Vector2.UP)
	bullet.set("shooter_type", "player")
	bullet.set("damage", 1)
	root.add_child(bullet)

	var handled = bunker.handle_bullet_hit(bullet, bunker.global_position, Vector2.UP)
	assert(handled == true, "穿过射击孔必须由堡垒接管")
	assert(bunker.current_health == 6, "穿过射击孔出膛的子弹不得扣除堡垒生命值")
	assert(!bullet.is_queued_for_deletion(), "出膛子弹不得被销毁，必须允许继续飞行")

	bullet.queue_free()
	bunker.queue_free()
	print("  [PASS] 后方架枪穿透射击孔出膛测试通过。")

func _test_frontal_shield_block() -> void:
	print("\n[STEP 3] 验证正面飞来的子弹 (正面重装甲格挡阻拦)...")

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	var bunker = bunker_scene.instantiate()
	bunker.set_facing(BunkerScript.FacingDirection.UP)
	root.add_child(bunker)

	# 模拟从正面迎头打来的敌方普通子弹 (dir = Vector2.DOWN, 与堡垒朝向相反)
	var bullet = Node2D.new()
	bullet.set_script(load("res://scripts/bullet.gd"))
	bullet.set("direction", Vector2.DOWN)
	bullet.set("shooter_type", "enemy")
	bullet.set("damage", 1)
	bullet.set("can_destroy_steel", false) # 低级炮弹
	root.add_child(bullet)

	var handled = bunker.handle_bullet_hit(bullet, bunker.global_position, Vector2.DOWN)
	assert(handled == true, "正面格挡必须由堡垒接管")
	assert(bunker.current_health == 6, "正面低级炮弹命中时堡垒必须免伤")
	assert(bullet.is_queued_for_deletion(), "被格挡的来袭子弹必须被销毁")

	bunker.queue_free()
	print("  [PASS] 正面重盾格挡免伤测试通过。")

func _test_flank_vulnerability_and_destruction() -> void:
	print("\n[STEP 4] 验证左面/右面侧翼受击弱点与被破坏机制...")

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	var bunker = bunker_scene.instantiate()
	bunker.set_facing(BunkerScript.FacingDirection.UP) # 正面朝上
	root.add_child(bunker)

	# 1. 从左侧射入 (dir = Vector2.RIGHT, 垂直于正面)
	var bullet_left = Node2D.new()
	bullet_left.set_script(load("res://scripts/bullet.gd"))
	bullet_left.set("direction", Vector2.RIGHT)
	bullet_left.set("damage", 2)
	root.add_child(bullet_left)

	var handled1 = bunker.handle_bullet_hit(bullet_left, bunker.global_position, Vector2.RIGHT)
	assert(handled1 == true, "侧面受击必须被处理")
	assert(bunker.current_health == 4, "侧面受击必须正常扣血 (6 - 2 = 4), 实际为 %d" % bunker.current_health)

	# 2. 从右侧射入 (dir = Vector2.LEFT)
	var bullet_right = Node2D.new()
	bullet_right.set_script(load("res://scripts/bullet.gd"))
	bullet_right.set("direction", Vector2.LEFT)
	bullet_right.set("damage", 4)
	root.add_child(bullet_right)

	var handled2 = bunker.handle_bullet_hit(bullet_right, bunker.global_position, Vector2.LEFT)
	assert(handled2 == true, "右侧受击必须被处理")
	assert(bunker.current_health <= 0, "生命归零必须被破坏")
	assert(bunker.is_destroyed == true, "堡垒状态必须标记为 is_destroyed")

	print("  [PASS] 侧翼受击扣血与生命耗尽摧毁测试通过。")

func _test_shop_and_builder_metadata() -> void:
	print("\n[STEP 5] 验证图鉴、商店与建造者配置...")

	# 1. 图鉴条目
	var found_encyclopedia := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "bld_bunker":
			found_encyclopedia = true
			assert(entry.get("category") == "BUILDINGS", "图鉴分类必须为 BUILDINGS")
			assert("正面" in entry.get("stats", {}).get("正面防御", ""), "图鉴必须标明正面防御")
			break
	assert(found_encyclopedia, "图鉴中必须包含 bld_bunker 条目")

	# 2. 商店条目
	var found_shop := false
	for item in ShopDialogScript.BUILDING_ITEMS:
		if item.get("id") == "bunker":
			found_shop = true
			assert(item.get("category") == "BUILD", "商店分类必须为 BUILD")
			assert(item.get("cost") > 0, "购买价格必须大于 0")
			break
	assert(found_shop, "商店物资必须包含 bunker 条目")

	print("  [PASS] 图鉴与商店元数据配置完整有效。")
