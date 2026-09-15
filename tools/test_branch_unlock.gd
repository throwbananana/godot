extends SceneTree

## 进阶流派的**图纸解锁制** 门禁。
##
##     & $godot --headless --path . --script tools/test_branch_unlock.gd
##
## 规则: 升级界面默认只给经典线 (阶级卡 + 战术芯片); 某条分支要先拿到对应的
## 改装图纸才会出现在卡面上。图纸来自 Boss 必掉 / 上锁宝箱 / 商店购买。
##
## 覆盖:
##   1. 一张图纸都没有时, 升级界面**不出现任何分支卡**
##   2. 解锁之后那条分支才出现, 且只出现解锁了的那些
##   3. 经典线阶级卡在 tier<3 时出现, 满阶后消失
##   4. 卡面永远不会是空的 (芯片池对两条路径都生效)
##   5. 两张按 branch id 对齐的表 (BRANCH_CARDS / BLUEPRINTS) 键集合一致
##   6. 解锁状态进存档, 且能从存档读回来
##   7. 商店: 已解锁的图纸不再上架, 也不允许成交
##   8. 掉落不会掉到重复的图纸
##
## 按 CLAUDE.md 的约定: _failed 标志 + 末尾唯一一次 quit(), 不用 assert。

const GameState = preload("res://scripts/game_state.gd")
const BranchBlueprints = preload("res://scripts/branch_blueprints.gd")
const ShopDialog = preload("res://scripts/shop_dialog.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] " + msg)
	_failed = true


func _ok(msg: String) -> void:
	print("  ok  " + msg)


## 造一个只够 _generate_choices() 用的升级界面。
##
## 直接 new 脚本而不是实例化 .tscn: 那个场景带 Panel/Label/HBox 一堆节点,
## 而 _generate_choices() 只读 rpg_mgr 和 GameState, 对 title_label 之类
## 全是 `if title_label:` 的空守卫。少布一棵树, 少一堆和本用例无关的依赖。
func _make_dialog() -> Node:
	var scr := load("res://scripts/upgrade_selection_dialog.gd")
	return scr.new()


func _choices(dlg: Node, rpg: RPGManager, pid: int = 1) -> Array:
	return dlg._generate_choices(rpg, pid)


func _branch_cards(choices: Array) -> Array:
	var out: Array = []
	for c in choices:
		if str(c.get("type", "")) == "branch":
			out.append(str(c.get("branch", "")))
	return out


func _has_type(choices: Array, t: String) -> bool:
	for c in choices:
		if str(c.get("type", "")) == t:
			return true
	return false


# ---------------------------------------------------------------- 用例

func _test_locked_by_default(dlg: Node, rpg: RPGManager) -> void:
	GameState.reset_campaign(1)
	GameState.player_tier = 0
	rpg.sync_from_game_state()
	var ch := _choices(dlg, rpg)
	var branches := _branch_cards(ch)
	if not branches.is_empty():
		_fail("一张图纸都没拿到, 升级界面却给出了分支卡 %s —— 分支应当要先解锁" % str(branches))
	else:
		_ok("默认状态: 没有任何分支卡")
	if not _has_type(ch, "classic_tier"):
		_fail("经典线还没满阶 (tier=0), 却没有给出阶级卡 —— 单线就没有可选内容了")
	else:
		_ok("经典线阶级卡在位")
	if ch.is_empty():
		_fail("升级界面一张卡都没有 —— 芯片池没有对经典线这条路径生效")
	else:
		_ok("卡面非空 (%d 张)" % ch.size())


func _test_unlock_reveals(dlg: Node, rpg: RPGManager) -> void:
	GameState.reset_campaign(1)
	rpg.sync_from_game_state()
	GameState.unlock_branch("heavy")
	var ch := _choices(dlg, rpg)
	var branches := _branch_cards(ch)
	if not branches.has("heavy"):
		_fail("解锁了 heavy, 升级界面却没有它 (实际 %s)" % str(branches))
	elif branches.size() != 1:
		_fail("只解锁了 heavy, 却出现了 %d 张分支卡 %s —— 未解锁的分支漏出来了"
			% [branches.size(), str(branches)])
	else:
		_ok("只出现已解锁的那一条 (heavy)")

	GameState.unlock_branch("train")
	var ch2 := _choices(dlg, rpg)
	var b2 := _branch_cards(ch2)
	b2.sort()
	if b2 != ["heavy", "train"]:
		_fail("解锁两条后应当出现 [heavy, train], 实际 %s" % str(b2))
	else:
		_ok("解锁第二条后两张都出现")


func _test_classic_tier_caps(dlg: Node, rpg: RPGManager) -> void:
	GameState.reset_campaign(1)
	rpg.sync_from_game_state()
	GameState.player_tier = 3
	var ch := _choices(dlg, rpg)
	if _has_type(ch, "classic_tier"):
		_fail("经典线已满阶 (tier=3), 却还在发阶级卡 —— 那是一张点了没用的牌")
	else:
		_ok("满阶后不再发阶级卡")
	if ch.is_empty():
		_fail("满阶且无解锁时卡面是空的 —— 玩家会看到一个没有任何按钮的升级框")
	else:
		_ok("满阶且无解锁时仍有 %d 张 (靠芯片池兜底)" % ch.size())


## 两张表按 branch id 对齐: 一张管解锁条件, 一张管卡面文案。
## 少一条 = 那条分支永远解锁不了, 或者解锁了却没有卡可点, 而且都不会报错。
func _test_tables_agree(dlg: Node) -> void:
	var bp_keys: Array = BranchBlueprints.all_branches()
	var card_keys: Array = dlg.BRANCH_CARDS.keys()
	bp_keys.sort()
	card_keys.sort()
	if bp_keys != card_keys:
		_fail("BLUEPRINTS 与 BRANCH_CARDS 的键对不上: 图纸 %s vs 卡面 %s" % [str(bp_keys), str(card_keys)])
	else:
		_ok("图纸表与卡面表键集合一致 (%d 条)" % bp_keys.size())

	# 还要和 rpg_manager 的分支名单对得上 —— 那边才是分支的权威定义。
	var rpg_branches: Array = []
	for b in RPGManager.BRANCHES:
		if str(b) != "default":
			rpg_branches.append(str(b))
	rpg_branches.sort()
	if rpg_branches != bp_keys:
		_fail("rpg_manager 的分支名单 %s 和图纸表 %s 对不上 —— 有分支没有解锁途径, 或者图纸指向了不存在的分支"
			% [str(rpg_branches), str(bp_keys)])
	else:
		_ok("与 rpg_manager 的分支名单一致")


func _test_persistence() -> void:
	GameState.reset_campaign(1)
	GameState.unlock_branch("counter")
	GameState.unlock_branch("trench")
	var d := GameState.campaign_to_dict()
	GameState.reset_campaign(1)
	if not GameState.unlocked_branches.is_empty():
		_fail("reset_campaign() 没有清掉已解锁的分支 —— 新开一局会带着上一局的解锁")
	GameState.campaign_from_dict(d)
	var got: Array = GameState.unlocked_branches.duplicate()
	got.sort()
	if got != ["counter", "trench"]:
		_fail("解锁状态没有完整地过一遍存档: 存进去 [counter, trench], 读出来 %s" % str(got))
	else:
		_ok("解锁状态可存可读")


func _test_shop(dlg: Node) -> void:
	GameState.reset_campaign(1)
	var item_id := str(BranchBlueprints.info("speed")["item_id"])

	if not ShopDialog.can_buy_item(item_id):
		_fail("还没解锁 speed, 商店却不允许买它的图纸")
	else:
		_ok("未解锁时图纸可购买")

	ShopDialog.apply_item_purchase(item_id)
	if not GameState.is_branch_unlocked("speed"):
		_fail("买了图纸却没有解锁 speed")
	else:
		_ok("购买图纸 -> 解锁分支")

	if ShopDialog.can_buy_item(item_id):
		_fail("speed 已解锁, 商店仍然允许再买一次同一张图纸 —— 那是一次纯亏损的成交, 而且不会报错")
	else:
		_ok("已解锁后不再允许成交")

	# 上架过滤: 连抽几次货架, 已解锁的那张不该再出现
	var seen := false
	for _i in range(40):
		for it in ShopDialog.build_inventory():
			if str(it["id"]) == item_id:
				seen = true
	if seen:
		_fail("speed 已解锁, 它的图纸仍然会被摆上货架 —— 货位上是一件永远点不动的商品")
	else:
		_ok("已解锁的图纸不再上架")


func _test_drop_never_duplicates() -> void:
	GameState.reset_campaign(1)
	var got: Array = []
	var total: int = BranchBlueprints.all_branches().size()
	for _i in range(total):
		var b := BranchBlueprints.roll_unlock()
		if b == "":
			_fail("还没集齐就掷不出图纸了 (已拿到 %s)" % str(got))
			return
		if got.has(b):
			_fail("掉落掷出了重复的图纸 %s —— 稀缺来源给出空气是最挫败的结果" % b)
			return
		got.append(b)
	if BranchBlueprints.roll_unlock() != "":
		_fail("已经全部解锁, roll_unlock() 还在返回分支")
	else:
		_ok("%d 次掉落各不相同, 集齐后返回空" % total)


func _run() -> void:
	print("=== 进阶流派: 图纸解锁制 ===")
	var dlg := _make_dialog()
	var rpg := RPGManager.new()

	_test_locked_by_default(dlg, rpg)
	_test_unlock_reveals(dlg, rpg)
	_test_classic_tier_caps(dlg, rpg)
	_test_tables_agree(dlg)
	_test_persistence()
	_test_shop(dlg)
	_test_drop_never_duplicates()

	dlg.free()
	print("")
	if _failed:
		print("[FAIL] 图纸解锁制检查未通过")
		quit(1)
	else:
		print("[OK] 图纸解锁制检查全部通过")
		quit(0)


func _init() -> void:
	_run()
