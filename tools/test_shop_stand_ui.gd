extends SceneTree

const ShopStand = preload("res://scripts/shop_stand.gd")
const ShopRerolder = preload("res://scripts/shop_rerolder.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> SHOP STAND & REROLLER EXPLANATION UI TEST <<<")
	print("==================================================")

	var root_node = Node2D.new()
	root.add_child(root_node)

	_test_category_info()
	_test_shop_stand_card_creation_and_binding(root_node)
	_test_shop_stand_progress_and_cap(root_node)
	_test_shop_stand_hover_and_position(root_node)
	_test_shop_reroller_ui(root_node)
	_test_shop_stand_purchase_flow(root_node)

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项测试失败！" % failures)
		quit(1)
	else:
		print(">>> ALL SHOP STAND & REROLLER UI TESTS PASSED! <<<")
		quit(0)


func _test_category_info() -> void:
	print("\n--- 1. 测试商品分类标签与颜色映射 (Category Info) ---")
	var build_info := UIThemeHelper.get_category_info("BUILD")
	if build_info.get("tag", "") == "【战备建筑】":
		ok("BUILD 分类解析为 【战备建筑】")
	else:
		fail("BUILD 分类标签错误: %s" % str(build_info))

	var risk_info := UIThemeHelper.get_category_info("RISK")
	if risk_info.get("tag", "") == "【高风险改造】":
		ok("RISK 分类解析为 【高风险改造】")
	else:
		fail("RISK 分类标签错误: %s" % str(risk_info))

	var weapon_info := UIThemeHelper.get_category_info("WEAPON")
	if weapon_info.get("tag", "") == "【核心武装】":
		ok("WEAPON 分类解析为 【核心武装】")
	else:
		fail("WEAPON 分类标签错误: %s" % str(weapon_info))


func _test_shop_stand_card_creation_and_binding(parent: Node2D) -> void:
	print("\n--- 2. 测试货位说明卡构建与基础数据绑定 ---")
	GameState.gold = 500
	var stand := ShopStand.new()
	stand.setup("turret", 80, false)
	parent.add_child(stand)

	var card: PanelContainer = stand._explanation_card
	if not card:
		fail("ShopStand 未创建 _explanation_card")
		return
	ok("ShopStand 成功生成 _explanation_card")

	var title_lbl: Label = card.find_child("TitleLabel", true, false)
	var tag_lbl: Label = card.find_child("TagLabel", true, false)
	var price_lbl: Label = card.find_child("PriceLabel", true, false)
	var status_lbl: Label = card.find_child("StatusLabel", true, false)
	var desc_lbl: Label = card.find_child("DescLabel", true, false)
	var progress_lbl: Label = card.find_child("ProgressLabel", true, false)

	if title_lbl and "防御炮塔" in title_lbl.text:
		ok("标题正确包含商品名称: %s" % title_lbl.text)
	else:
		fail("标题未正确设置商品名称: %s" % (title_lbl.text if title_lbl else "null"))

	if tag_lbl and tag_lbl.text == "【战备建筑】":
		ok("标签正确显示 【战备建筑】")
	else:
		fail("标签错误: %s" % (tag_lbl.text if tag_lbl else "null"))

	if price_lbl and price_lbl.text == "💰 80 G":
		ok("价格正确显示: %s" % price_lbl.text)
	else:
		fail("价格标签错误: %s" % (price_lbl.text if price_lbl else "null"))

	if status_lbl and "可购买" in status_lbl.text:
		ok("金币充足时状态显示: %s" % status_lbl.text)
	else:
		fail("状态显示错误: %s" % (status_lbl.text if status_lbl else "null"))

	if desc_lbl and desc_lbl.text != "":
		ok("描述文案有效绑定: %s" % desc_lbl.text)
	else:
		fail("描述文案为空")


func _test_shop_stand_progress_and_cap(parent: Node2D) -> void:
	print("\n--- 3. 测试强化进度与库存实时更新 (Progress & Cap) ---")
	GameState.gold = 50
	GameState.structure_inventory["turret"] = 3
	var stand := ShopStand.new()
	stand.setup("turret", 80, false)
	parent.add_child(stand)

	stand._refresh_visuals()
	var card: PanelContainer = stand._explanation_card
	var progress_lbl: Label = card.find_child("ProgressLabel", true, false)
	var status_lbl: Label = card.find_child("StatusLabel", true, false)

	if progress_lbl and "当前战备库存: x3" in progress_lbl.text:
		ok("建筑库存正确反映: %s" % progress_lbl.text)
	else:
		fail("建筑库存显示错误: %s" % (progress_lbl.text if progress_lbl else "null"))

	if status_lbl and "金币不足" in status_lbl.text:
		ok("金币不足时正确提示: %s" % status_lbl.text)
	else:
		fail("金币不足状态错误: %s" % (status_lbl.text if status_lbl else "null"))

	# 测试 Perk 达到上限
	GameState.gold = 500
	GameState.unlocked_perks["ricochet_rounds"] = 3
	var perk_stand := ShopStand.new()
	perk_stand.setup("ricochet_rounds", 110, false)
	parent.add_child(perk_stand)
	perk_stand._refresh_visuals()

	var perk_card: PanelContainer = perk_stand._explanation_card
	var perk_status: Label = perk_card.find_child("StatusLabel", true, false)
	var perk_prog: Label = perk_card.find_child("ProgressLabel", true, false)

	if perk_status and "已达上限" in perk_status.text:
		ok("Perk 满层时状态正确显示 [已达上限 MAX]")
	else:
		fail("Perk 满层状态错误: %s" % (perk_status.text if perk_status else "null"))

	if perk_prog and "3 / 3 层" in perk_prog.text:
		ok("Perk 满层进度正确显示: %s" % perk_prog.text)
	else:
		fail("Perk 进度显示错误: %s" % (perk_prog.text if perk_prog else "null"))


func _test_shop_stand_hover_and_position(parent: Node2D) -> void:
	print("\n--- 4. 测试卡片自适应定位与靠近显示 ---")
	var stand_top := ShopStand.new()
	stand_top.position = Vector2(100, 100) # 顶部且靠左
	stand_top.setup("heavy_armor", 65, false)
	parent.add_child(stand_top)

	if stand_top._explanation_card.position.y > 0:
		ok("顶部货位说明卡自适应下移 (y > 0)")
	else:
		fail("顶部货位说明卡未下移: %s" % str(stand_top._explanation_card.position))

	if stand_top._explanation_card.position.x > -100:
		ok("靠左货位说明卡自适应向右偏移")
	else:
		fail("靠左货位说明卡未右偏: %s" % str(stand_top._explanation_card.position))


func _test_shop_reroller_ui(parent: Node2D) -> void:
	print("\n--- 5. 测试换货机专属说明卡 (ShopReroller UI) ---")
	GameState.gold = 30
	GameState.shop_reroll_cost = 20
	var reroller := ShopRerolder.new()
	reroller.position = Vector2(504, 504)
	parent.add_child(reroller)

	var card: PanelContainer = reroller._explanation_card
	if not card:
		fail("ShopRerolder 未创建说明卡")
		return
	ok("ShopRerolder 成功生成说明卡")

	var title_lbl: Label = card.find_child("TitleLabel", true, false)
	var tag_lbl: Label = card.find_child("TagLabel", true, false)
	var price_lbl: Label = card.find_child("PriceLabel", true, false)
	var status_lbl: Label = card.find_child("StatusLabel", true, false)

	if title_lbl and "军火商货物刷新机" in title_lbl.text:
		ok("换货机标题正确: %s" % title_lbl.text)
	else:
		fail("换货机标题错误: %s" % (title_lbl.text if title_lbl else "null"))

	if tag_lbl and tag_lbl.text == "【货架重置】":
		ok("换货机标签正确显示 【货架重置】")
	else:
		fail("换货机标签错误: %s" % (tag_lbl.text if tag_lbl else "null"))

	if price_lbl and "20 G" in price_lbl.text:
		ok("换货机价格正确: %s" % price_lbl.text)
	else:
		fail("换货机价格错误: %s" % (price_lbl.text if price_lbl else "null"))

	if status_lbl and "可刷新" in status_lbl.text:
		ok("换货机可刷新状态显示正确: %s" % status_lbl.text)
	else:
		fail("换货机状态错误: %s" % (status_lbl.text if status_lbl else "null"))


func _test_shop_stand_purchase_flow(parent: Node2D) -> void:
	print("\n--- 6. 测试货位购买流程与售罄状态显示 ---")
	GameState.gold = 200
	GameState.max_hp_lvl = 1
	var stand := ShopStand.new()
	stand.setup("heavy_armor", 65, false)
	parent.add_child(stand)

	# 模拟玩家坦克触发购买
	var player_scene = load("res://scenes/player.tscn")
	var player_tank = player_scene.instantiate()
	parent.add_child(player_tank)

	stand._on_body_entered(player_tank)

	if stand.sold:
		ok("购买后货位正确标记 sold = true")
	else:
		fail("购买后货位 sold 未更新")

	if GameState.gold == 135:
		ok("金币正确扣除 65 G (剩余 135 G)")
	else:
		fail("金币扣除错误: 当前 %d G" % GameState.gold)

	if GameState.max_hp_lvl == 2:
		ok("强化等级正确加 1 (当前 %d)" % GameState.max_hp_lvl)
	else:
		fail("强化等级加成错误: %d" % GameState.max_hp_lvl)

	var card: PanelContainer = stand._explanation_card
	var status_lbl: Label = card.find_child("StatusLabel", true, false)
	if status_lbl and "已售罄" in status_lbl.text:
		ok("售罄后说明卡状态正确显示 [已售罄 SOLD]")
	else:
		fail("售罄状态显示错误: %s" % (status_lbl.text if status_lbl else "null"))
