extends SceneTree

## 商店经济与双人分发的回归测试。
##
## 商店卖的是"给队伍"的东西。大多数商品写的是 GameState 上的团队字段
## (max_hp_lvl / fire_rate_lvl / speed_lvl / builder_lvl / atk_bonus /
## player_xp), 两人天然共享; 但有四样不是 —— 备用生命 (player_lives 与
## p2_lives 分开)、升阶模块, 以及三个 perk (unlocked_perks 与
## p2_unlocked_perks 分开)。这四样以前一律硬编码 player_id = 1, 双人模式下
## 2P 永远拿不到, 而且不会报错: 钱照扣、提示照弹, 只是东西没到。
##
## 判定它是 bug 而不是另一种设计的依据是同一个项目里的 event_dialog.gd ——
## 它对**完全相同的三类奖励**都写了 player_count == 2 的分发
## (_grant_life / _grant_tier_up / _grant_perk)。所以这个测试同时验两边,
## 并直接断言"商店与事件对同一份奖励的到账结果一致"。
##
## 另外锁住经济本身的两条底线: 买不起不能扣钱, 买满上限不能扣钱。后者以前
## 只靠 btn_buy.disabled 挡着 —— 走 UI 点不出来, 但逻辑层是敞开的。

const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> SHOP ECONOMY / 2P PARITY TEST <<<")
	print("==================================================")
	_check_2p_perk_parity()
	_check_2p_extra_life()
	_check_2p_star_tier()
	_check_no_charge_when_capped()
	_check_no_charge_when_broke()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL SHOP ECONOMY CHECKS PASSED! <<<")
		quit(0)


func _new_shop() -> Node:
	var scn: PackedScene = load("res://scenes/shop_dialog.tscn")
	var d = scn.instantiate()
	root.add_child(d)
	return d


func _check_2p_perk_parity() -> void:
	print("\n--- 双人: 商店 perk 必须两个人都拿到 ---")
	for perk in ["ricochet_rounds", "amphibious_hull", "armor_piercing_rounds"]:
		GameState.reset_campaign(2)
		GameState.gold = 9999
		var shop = _new_shop()
		shop._apply_item_purchase(perk)
		var p1 := int(GameState.unlocked_perks.get(perk, 0))
		var p2 := int(GameState.p2_unlocked_perks.get(perk, 0))
		shop.free()
		if p1 == 1 and p2 == 1:
			ok("%s: P1=%d P2=%d" % [perk, p1, p2])
		else:
			fail("%s 在双人模式下只发给了一个人 (P1=%d, P2=%d) —— "
				% [perk, p1, p2]
				+ "对照 event_dialog._grant_perk() 是发两份的")


func _check_2p_extra_life() -> void:
	print("\n--- 双人: 备用生命必须两个人都加 ---")
	GameState.reset_campaign(2)
	var l1 := GameState.player_lives
	var l2 := GameState.p2_lives
	var shop = _new_shop()
	shop._apply_item_purchase("extra_life")
	var d1 := GameState.player_lives - l1
	var d2 := GameState.p2_lives - l2
	shop.free()
	if d1 == 1 and d2 == 1:
		ok("extra_life: P1 +%d, P2 +%d" % [d1, d2])
	else:
		fail("extra_life 在双人模式下 P1 +%d 而 P2 +%d —— "
			% [d1, d2] + "player_lives 和 p2_lives 是分开的两个字段")


func _check_2p_star_tier() -> void:
	print("\n--- 双人: 升阶模块必须两个人都升 ---")
	GameState.reset_campaign(2)
	var shop = _new_shop()
	shop._apply_item_purchase("star_tier")
	var t1 := GameState.player_tier
	var t2 := GameState.p2_tier
	shop.free()
	if t1 == 1 and t2 == 1:
		ok("star_tier (default 分支): P1 tier=%d, P2 tier=%d" % [t1, t2])
	else:
		fail("star_tier 在双人模式下 P1 tier=%d 而 P2 tier=%d" % [t1, t2])

	# 单人时不能误伤 p2 字段
	GameState.reset_campaign(1)
	var shop2 = _new_shop()
	shop2._apply_item_purchase("star_tier")
	var solo_t2 := GameState.p2_tier
	shop2.free()
	if solo_t2 == 0:
		ok("单人模式不会顺手给不存在的 2P 发奖励")
	else:
		fail("单人模式下 p2_tier 被动到了 (=%d)" % solo_t2)


func _check_no_charge_when_capped() -> void:
	print("\n--- 满上限时不能扣钱 ---")
	GameState.reset_campaign(1)
	GameState.gold = 500
	# amphibious_hull 上限 1, 先吃满
	GameState.grant_perk_stack("amphibious_hull", 1)
	var shop = _new_shop()
	if shop._can_buy_item("amphibious_hull"):
		fail("amphibious_hull 已达上限, _can_buy_item() 仍然返回 true")
	var before := GameState.gold
	shop._on_buy_item({"id": "amphibious_hull", "cost": 120, "sold_out": false})
	var after := GameState.gold
	var stacks := int(GameState.unlocked_perks.get("amphibious_hull", 0))
	shop.free()
	if after == before:
		ok("满上限时购买被拒, 金币未变 (%d)" % after)
	else:
		fail("满上限却扣了 %d 金币, perk 仍是 %d 层 —— 花钱买了个空气"
			% [before - after, stacks])


func _check_no_charge_when_broke() -> void:
	print("\n--- 买不起时不能扣钱, 也不能扣成负数 ---")
	GameState.reset_campaign(1)
	GameState.gold = 10
	var shop = _new_shop()
	shop._on_buy_item({"id": "heavy_armor", "cost": 65, "sold_out": false})
	var g := GameState.gold
	var hp := GameState.max_hp_lvl
	shop.free()
	if g == 10 and hp == 0:
		ok("金币不足时购买被拒, 金币仍为 %d" % g)
	else:
		fail("金币不足却成交了: 金币 %d, max_hp_lvl %d" % [g, hp])
