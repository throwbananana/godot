extends SceneTree

# GameState.grant_star_tier_reward() 与它背后那道"非升级来源 atk_bonus"上限。
#
# === 这个文件守的两代缺陷 ===
#
# 第一代 (原始版本): ⭐ / 商店的 star_tier / 事件的升阶奖励, 对**已经选了分支**
# 的玩家是纯粹的空操作 —— player.gd 只在 "default" 分支的武器路径里读
# player_tier/p2_tier, 分支一选定, 再 mini(tier+1, 3) 谁也看不见。于是这三处
# 奖励改成重定向为永久 +1 atk_bonus。
#
# 第二代 (现在): 那条重定向**没有上限**, 而它补偿的东西 (upgrade_tier) 封顶 3。
# 实测一局战役能吃到约 25 颗 ⭐, 同期升级曲线只给 5 点攻击力 —— 于是整场打完
# 经典线伤害 6、已分支 31 (tools/test_player_power.gd::_check_star_driven_atk_gap
# 把这个倍差常驻打印出来)。现在两条路都有上限:
#   default -> upgrade_tier 夹 3
#   已分支  -> atk_bonus 夹 GameState.SHOP_ATK_BONUS_CAP
# 而且上限是**四条路共用的一个预算** (商店 plasma_mod / 商店 star_tier /
# 事件奖励 / 战场 ⭐), 判定只在 GameState.can_grant_flat_atk() 一处。
#
# === 为什么不用 assert ===
#
# 见 CLAUDE.md "Commands": tools/test_*.gd 里的 assert 在 headless 下是**挂起**
# 而不是失败, run_tests.ps1 报一个没有诊断的 TIMEOUT; 而散落的 quit(1) 会被同
# 进程后面的 quit(0) 覆盖。这个文件原来是 15 条 assert, 属于 CLAUDE.md 点名的
# 那批"潜在静默超时", 借这次改动一并转成 _failed 标志 + 末尾唯一一次 quit()。

var _failed := false


func _fail(msg: String) -> void:
	_failed = true
	print("  [FAIL] %s" % msg)


func _ok(msg: String) -> void:
	print("  [PASS] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> RUNNING STAR TIER REWARD TEST  <<<")
	print("==================================================")

	_test_default_branch_bumps_tier()
	_test_branched_player_redirects_to_atk()
	_test_redirect_is_capped()
	_test_cap_is_one_shared_budget()
	_test_players_are_independent()
	_test_shared_field_is_not_fanned_out()
	_test_death_resets_everything()

	print("==================================================")
	if _failed:
		print(">>> STAR TIER REWARD: 有检查未通过 <<<")
	else:
		print(">>> ALL STAR TIER REWARD CHECKS PASSED! <<<")
	quit(1 if _failed else 0)


func _test_default_branch_bumps_tier() -> void:
	print("\n[STEP] 还在 default 分支: 奖励抬 player_tier, 封顶 3...")
	GameState.reset_campaign(1)
	if GameState.tank_branch != "default" or GameState.player_tier != 0:
		_fail("新战役应该是 default/tier0, 实际 %s/tier%d" % [GameState.tank_branch, GameState.player_tier])
		return
	var atk_before := GameState.atk_bonus

	for _i in range(4): # 第 4 次应该夹住而不是溢出
		GameState.grant_star_tier_reward(1)

	if GameState.player_tier != 3:
		_fail("player_tier 应夹在 3, 实际 %d" % GameState.player_tier)
	elif GameState.atk_bonus != atk_before:
		_fail("default 分支的奖励不该碰 atk_bonus, 实际从 %d 变成 %d" % [atk_before, GameState.atk_bonus])
	else:
		_ok("default 分支抬 tier 并夹在 3, 不碰 atk_bonus。")


func _test_branched_player_redirects_to_atk() -> void:
	print("\n[STEP] 已选分支: 奖励重定向成 +1 攻击力...")
	GameState.reset_campaign(1)
	GameState.tank_branch = "speed"
	var tier_before := GameState.player_tier
	var atk_before := GameState.atk_bonus

	GameState.grant_star_tier_reward(1)

	if GameState.player_tier != tier_before:
		_fail("已分支的奖励不该碰 player_tier (碰了就是当年那个空操作的翻版)")
	elif GameState.atk_bonus != atk_before + 1:
		_fail("已分支的奖励应 +1 atk_bonus, 实际 %d -> %d" % [atk_before, GameState.atk_bonus])
	else:
		_ok("已分支时重定向为 +1 atk_bonus, 不再是死属性。")


func _test_redirect_is_capped() -> void:
	print("\n[STEP] 重定向必须有上限 —— 它补偿的 upgrade_tier 就是封顶 3 的...")
	GameState.reset_campaign(1)
	GameState.tank_branch = "heavy"
	var atk_before := GameState.atk_bonus
	var cap: int = GameState.SHOP_ATK_BONUS_CAP

	var granted := 0
	for _i in range(cap + 8): # 故意远超上限
		if GameState.grant_star_tier_reward(1):
			granted += 1

	var gained := GameState.atk_bonus - atk_before
	if gained != cap:
		_fail("超额授予 %d 次之后 atk_bonus 涨了 %d, 应该夹在 SHOP_ATK_BONUS_CAP=%d —— "
			% [cap + 8, gained, cap]
			+ "这条重定向一旦无上限, 已分支玩家整场能比经典线多出 5 倍伤害")
	elif granted != cap:
		_fail("返回 true 的次数 %d 应等于真实授予次数 %d —— 调用方靠这个返回值决定"
			% [granted, cap] + "要不要播 '+1 攻击力' 的提示, 错了就会播骗人的 toast")
	elif GameState.can_grant_flat_atk():
		_fail("已经到顶了, can_grant_flat_atk() 却仍然返回 true")
	else:
		_ok("重定向夹在 %d 点, 到顶后返回 false 且 can_grant_flat_atk() 转 false。" % cap)


func _test_cap_is_one_shared_budget() -> void:
	print("\n[STEP] 商店 / 事件 / 战场 ⭐ 共用同一个预算, 不是各有一份...")
	GameState.reset_campaign(1)
	GameState.tank_branch = "train"
	var cap: int = GameState.SHOP_ATK_BONUS_CAP

	# 先用"商店 plasma_mod"那条路把预算吃掉 cap-1 份
	for _i in range(cap - 1):
		GameState.try_grant_flat_atk()
	# 再走"战场 ⭐ / 事件"那条路: 只应该还剩 1 份
	var extra := 0
	for _i in range(5):
		if GameState.grant_star_tier_reward(1):
			extra += 1

	if extra != 1:
		_fail("预算只剩 1 份时, 另一条路又拿到了 %d 份 —— 说明两条路各自记了一本账" % extra)
	elif GameState.shop_atk_bonus_purchases != cap:
		_fail("计数器应停在 %d, 实际 %d" % [cap, GameState.shop_atk_bonus_purchases])
	else:
		_ok("四条授予路共用一个预算, 判定只在 can_grant_flat_atk() 一处。")


func _test_players_are_independent() -> void:
	print("\n[STEP] 双人合作时 P1/P2 各自按自己的分支状态结算...")
	GameState.reset_campaign(2)
	GameState.tank_branch = "default"
	GameState.p2_branch = "heavy" # P2 已分支, P1 还没定
	var atk_before := GameState.atk_bonus

	GameState.grant_star_tier_reward(1) # P1: 仍是 default -> 抬 tier
	GameState.grant_star_tier_reward(2) # P2: 已分支 -> 重定向

	if GameState.player_tier != 1:
		_fail("P1 (仍是 default) 应该抬一阶, 实际 tier%d" % GameState.player_tier)
	elif GameState.p2_tier != 0:
		_fail("P2 (已分支) 不该抬 tier")
	elif GameState.atk_bonus != atk_before + 1:
		_fail("P2 (已分支) 应该拿到 +1 atk_bonus, 实际 %d -> %d" % [atk_before, GameState.atk_bonus])
	else:
		_ok("同一局里 P1 走 tier、P2 走重定向, 互不干扰。")


## 一次奖励的两半归属不同: tier 每人一份 (该 fan-out), 重定向落到队伍共享的
## atk_bonus (不该 fan-out)。两个都已分支的玩家各调一次 grant_star_tier_reward()
## 的话, 一次购买就给 +2 攻击力并烧掉 2 份预算 —— 双人凭空比单人多拿一倍,
## 没有任何报错。商店和事件原来各写了一份 fan-out 循环, 两份都有这个问题。
##
## 四种分支组合都要覆盖: 只有"两边都已分支"那一种会暴露它, 另外三种在修复前后
## 表现完全一样 —— 只测其中一种就是一条空转的绿。
func _test_shared_field_is_not_fanned_out() -> void:
	print("\n[STEP] 双人: 队伍共享的 atk_bonus 不能被 fan-out 重复发放...")
	var cases := [
		{"p1": "default", "p2": "default", "atk": 0, "t1": 1, "t2": 1, "why": "两边都还没分支 -> 各抬各的 tier"},
		{"p1": "default", "p2": "heavy", "atk": 1, "t1": 1, "t2": 0, "why": "一人 tier 一人重定向"},
		{"p1": "speed", "p2": "default", "atk": 1, "t1": 0, "t2": 1, "why": "同上, 顺序反过来"},
		{"p1": "speed", "p2": "heavy", "atk": 1, "t1": 0, "t2": 0, "why": "**两边都已分支 -> 共享字段只该 +1**"},
	]
	for c in cases:
		GameState.reset_campaign(2)
		GameState.tank_branch = str(c["p1"])
		GameState.p2_branch = str(c["p2"])
		var atk_before := GameState.atk_bonus
		var budget_before := GameState.shop_atk_bonus_purchases

		GameState.grant_star_tier_reward_to([1, 2])

		var d_atk := GameState.atk_bonus - atk_before
		var d_budget := GameState.shop_atk_bonus_purchases - budget_before
		if d_atk != int(c["atk"]):
			_fail("%s/%s: atk_bonus 应 +%d, 实际 +%d (%s)"
				% [c["p1"], c["p2"], int(c["atk"]), d_atk, c["why"]])
		elif d_budget != int(c["atk"]):
			_fail("%s/%s: 预算应消耗 %d 份, 实际 %d 份 —— 攻击力对了但预算多烧了"
				% [c["p1"], c["p2"], int(c["atk"]), d_budget])
		elif GameState.player_tier != int(c["t1"]) or GameState.p2_tier != int(c["t2"]):
			_fail("%s/%s: tier 应是 %d/%d, 实际 %d/%d —— 每人一份的那一半反而漏发了"
				% [c["p1"], c["p2"], int(c["t1"]), int(c["t2"]),
					GameState.player_tier, GameState.p2_tier])
		else:
			_ok("%-8s/%-8s -> atk +%d, tier %d/%d  (%s)"
				% [c["p1"], c["p2"], d_atk, GameState.player_tier, GameState.p2_tier, c["why"]])


## 死亡 = 存档被删 (main.gd::_game_over -> delete_saved_game), 玩家只能重开一局,
## 而重开走的是 reset_campaign()。所以"死亡后一切归 1 级"这条, 落实处就是
## reset_campaign() 有没有把这些字段清干净 —— 尤其是**上限计数器**: 漏了它的话,
## 上一局吃满 5 点的玩家开新档时预算是空的, 整局再也拿不到一点重定向攻击力,
## 而且不会有任何报错。
func _test_death_resets_everything() -> void:
	print("\n[STEP] 死亡重开: 等级 / 阶级 / 攻击力 / 上限计数器全部归零...")
	GameState.reset_campaign(1)
	GameState.tank_branch = "speed"
	GameState.player_level = 17
	for _i in range(GameState.SHOP_ATK_BONUS_CAP):
		GameState.grant_star_tier_reward(1)
	GameState.player_tier = 2
	GameState.p2_tier = 3

	if GameState.can_grant_flat_atk():
		_fail("前置条件没成立: 吃满之后预算应该是空的")
		return

	GameState.reset_campaign(1) # <- 死亡之后重开一局走的就是这里

	var bad := PackedStringArray()
	if GameState.player_level != 1:
		bad.append("player_level=%d" % GameState.player_level)
	if GameState.player_tier != 0:
		bad.append("player_tier=%d" % GameState.player_tier)
	if GameState.p2_tier != 0:
		bad.append("p2_tier=%d" % GameState.p2_tier)
	if GameState.atk_bonus != 0:
		bad.append("atk_bonus=%d" % GameState.atk_bonus)
	if GameState.shop_atk_bonus_purchases != 0:
		bad.append("shop_atk_bonus_purchases=%d" % GameState.shop_atk_bonus_purchases)

	if not bad.is_empty():
		_fail("重开一局之后这些字段没有归零: %s" % ", ".join(bad))
	elif not GameState.can_grant_flat_atk():
		_fail("重开一局之后 can_grant_flat_atk() 仍是 false —— 新的一局一点重定向"
			+ "攻击力都拿不到, 而且不会报错")
	else:
		_ok("重开一局: 等级/阶级/攻击力/上限预算全部回到起点。")
