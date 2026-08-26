extends SceneTree

const BunkerScript = preload("res://scripts/buildings/bunker.gd")
const EncyclopediaDataScript = preload("res://scripts/encyclopedia_data.gd")
const ShopDialogScript = preload("res://scripts/shop_dialog.gd")
const BulletScene = preload("res://scenes/bullet.tscn")

var failures: int = 0

func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)

func check(cond: bool, msg: String) -> bool:
	if not cond:
		fail(msg)
	return cond

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

	if failures > 0:
		print("\n[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print("\n>>> ALL TACTICAL BUNKER TESTS PASSED SUCCESSFULLY! <<<")
		quit(0)

## 造一颗真实的 bullet.tscn 实例作为测试子弹，而不是 Node2D.new() + set_script(bullet.gd)。
## bullet.gd 是 `extends Area2D` 且用了 @onready var sprite = $Sprite2D，用错底层节点
## 类型会导致 set_script() 被 Godot 静默拒绝（"Script inherits from native type 'Area2D'"），
## 这样一来后续所有 .set(...) 调用都落在一个没有脚本的裸节点上，不会报错但也什么都不做，
## 使得针对 bullet.damage / bullet.direction 等字段的断言测的其实是 handle_bullet_hit()
## 里的兜底默认值分支，而不是真实的子弹行为。
func _make_test_bullet(direction: Vector2, damage: int, shooter_type: String = "enemy", can_destroy_steel: bool = false) -> Area2D:
	var bullet: Area2D = BulletScene.instantiate()
	bullet.direction = direction
	bullet.damage = damage
	bullet.shooter_type = shooter_type
	bullet.can_destroy_steel = can_destroy_steel
	root.add_child(bullet)
	return bullet

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
		if not check(tex != null, "堡垒贴图必须存在: %s" % path):
			continue

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	if not check(bunker_scene != null, "bunker.tscn 场景必须存在"):
		return
	var bunker = bunker_scene.instantiate()
	root.add_child(bunker)

	check(bunker.is_in_group("building"), "必须属于 building 组")
	check(bunker.is_in_group("bunker"), "必须属于 bunker 组")
	check(bunker.max_health == 6, "堡垒基础生命值必须为 6")
	check(bunker.current_health == 6, "初始生命值必须为 6")

	bunker.queue_free()
	print("  [PASS] 资产加载与场景实例测试通过。")

func _test_rear_shooting_pass_through() -> void:
	print("\n[STEP 2] 验证躲在堡垒后方向前射击 (穿透射击孔出膛)...")

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	var bunker = bunker_scene.instantiate()
	bunker.set_facing(BunkerScript.FacingDirection.UP)
	root.add_child(bunker)

	# 模拟从后方飞向前方的玩家子弹 (dir = Vector2.UP, 与堡垒朝向一致)
	var bullet = _make_test_bullet(Vector2.UP, 1, "player")

	var handled = bunker.handle_bullet_hit(bullet, bunker.global_position, Vector2.UP)
	check(handled == true, "穿过射击孔必须由堡垒接管")
	check(bunker.current_health == 6, "穿过射击孔出膛的子弹不得扣除堡垒生命值")
	check(!bullet.is_queued_for_deletion(), "出膛子弹不得被销毁，必须允许继续飞行")

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
	var bullet = _make_test_bullet(Vector2.DOWN, 1, "enemy", false)

	var handled = bunker.handle_bullet_hit(bullet, bunker.global_position, Vector2.DOWN)
	check(handled == true, "正面格挡必须由堡垒接管")
	check(bunker.current_health == 6, "正面低级炮弹命中时堡垒必须免伤")
	check(bullet.is_queued_for_deletion(), "被格挡的来袭子弹必须被销毁")

	bunker.queue_free()
	print("  [PASS] 正面重盾格挡免伤测试通过。")

func _test_flank_vulnerability_and_destruction() -> void:
	print("\n[STEP 4] 验证左面/右面侧翼受击弱点与被破坏机制...")

	var bunker_scene = load("res://scenes/buildings/bunker.tscn")
	var bunker = bunker_scene.instantiate()
	bunker.set_facing(BunkerScript.FacingDirection.UP) # 正面朝上
	root.add_child(bunker)

	# 1. 从左侧射入 (dir = Vector2.RIGHT, 垂直于正面)
	var bullet_left = _make_test_bullet(Vector2.RIGHT, 2)

	var handled1 = bunker.handle_bullet_hit(bullet_left, bunker.global_position, Vector2.RIGHT)
	check(handled1 == true, "侧面受击必须被处理")
	check(bunker.current_health == 4, "侧面受击必须正常扣血 (6 - 2 = 4), 实际为 %d" % bunker.current_health)

	# 2. 从右侧射入 (dir = Vector2.LEFT)
	var bullet_right = _make_test_bullet(Vector2.LEFT, 4)

	var handled2 = bunker.handle_bullet_hit(bullet_right, bunker.global_position, Vector2.LEFT)
	check(handled2 == true, "右侧受击必须被处理")
	check(bunker.current_health <= 0, "生命归零必须被破坏")
	check(bunker.is_destroyed == true, "堡垒状态必须标记为 is_destroyed")

	bullet_left.queue_free()
	bullet_right.queue_free()
	print("  [PASS] 侧翼受击扣血与生命耗尽摧毁测试通过。")

func _test_shop_and_builder_metadata() -> void:
	print("\n[STEP 5] 验证图鉴、商店与建造者配置...")

	# 1. 图鉴条目
	var found_encyclopedia := false
	for entry in EncyclopediaDataScript.ENTRIES:
		if entry.get("id") == "bld_bunker":
			found_encyclopedia = true
			check(entry.get("category") == "BUILDINGS", "图鉴分类必须为 BUILDINGS")
			check("正面" in entry.get("stats", {}).get("正面防御", ""), "图鉴必须标明正面防御")
			break
	check(found_encyclopedia, "图鉴中必须包含 bld_bunker 条目")

	# 2. 商店条目
	var found_shop := false
	for item in ShopDialogScript.BUILDING_ITEMS:
		if item.get("id") == "bunker":
			found_shop = true
			check(item.get("category") == "BUILD", "商店分类必须为 BUILD")
			check(item.get("cost") > 0, "购买价格必须大于 0")
			break
	check(found_shop, "商店物资必须包含 bunker 条目")

	print("  [PASS] 图鉴与商店元数据配置完整有效。")
