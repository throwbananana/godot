class_name GameState
extends RefCounted

enum GameMode { CAMPAIGN, ARCADE, DAILY_CHALLENGE }

static var mode: GameMode = GameMode.CAMPAIGN
static var player_count: int = 1 # 1=单人, 2=本地双人

## 难度：影响战斗中的敌人数量 (main.gd::encounter_size()/max_alive_for()/
## spawn_interval_for()) 与 AI 行为 (enemy.gd 里 GameState.difficulty == "hard"
## 的瞄准/躲避分支)。title_screen.gd 用一个循环按钮直接写这个字段，**不经过
## reset_campaign()** —— 玩家选一次就应该一直生效，开新战役不该把它冲回默认值，
## 跟 mode/player_count (每次开局都由按钮显式指定) 是两类字段。
static var difficulty: String = "normal" # "easy" / "normal" / "hard"
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]

static func difficulty_label(d: String = "") -> String:
	var val = d if not d.is_empty() else difficulty
	match val:
		"easy": return "简单 EASY"
		"hard": return "困难 HARD"
		_: return "普通 NORMAL"

## 标题screen 的循环按钮调用：easy -> normal -> hard -> easy -> ...
static func cycle_difficulty() -> void:
	var idx = DIFFICULTIES.find(difficulty)
	if idx < 0:
		idx = 1 # 找不到 (脏数据) 就当作从 normal 开始循环
	difficulty = DIFFICULTIES[(idx + 1) % DIFFICULTIES.size()]

## 隐藏测试模式的解锁状态。title_screen.gd 在标题界面监听键盘序列
## "throwbanana" 或手柄序列 上上下下左左右右 X A B Y, 命中后置 true, 显示
## 那颗平时隐藏的 TEST MODE 按钮。**故意是纯运行期状态, 不落盘**: 不写进
## save_campaign()/load_campaign() 的字段表, 也不在
## tools/test_persistence_roundtrip.gd 的 EXEMPT 里出现 —— 跟 playtest_layout
## 是同一个理由, 它是"这次进程要不要显示测试入口"的临时信号, 不是战役存档的
## 一部分。关掉游戏重开就要重新输入一遍, 这是刻意的默认收敛, 不是遗漏。
static var debug_unlocked: bool = false

## 关卡编辑器"试玩"按钮用的一次性图层覆盖: main.gd::_build_map() 一旦读到
## 非空值就直接拿去当这个房间的地形, 并立刻清空自己。不是战役存档字段——
## 编辑器产物存在 CustomMapStore (user://custom_maps.json), 这里只是"下一个
## 房间强制用这张图"的临时信号, 所以在 tools/test_persistence_roundtrip.gd
## 的 EXEMPT 里有名有姓地被豁免, 不要求它能穿过 save_campaign()/load_campaign()。
static var playtest_layout: Array = []
static var current_act: int = 1   # 1..max_acts
## 一整局有几幕。**一幕 = 一层以撒式楼层**, 打掉那层的 boss 进下一幕。
##
## 8 -> 12: 单层的房间数封在 11 之后 (FloorMap.ROOM_MAX), 每层稳定 8-12 分钟,
## 靠加幕数而不是撑长单层来拉长战役。12 也是 ACT_DIFFICULTY_STRIDE=1 正好把
## current_floor 走满 0..14 的幕数。
##
## 只有 3 套视觉主题 (平原/沙漠/极地), 所以第 4 幕起循环复用 —— 12 幕就是走
## 4 圈。get_visual_act() 给主题 (1-3), get_difficulty_cycle() 给圈数 (0-3)。
##
## 再往上加收益递减: 遭遇规模 +4/圈, 但 main.gd::max_alive_for() 同屏封顶 6、
## enemy.gd::armor_plate_range() 装甲下界封顶 3, 所以大约第 4 圈之后就不再变难。
## 要做 16 幕以上得先给后段准备新的施压手段, 而不是继续调这个常数。
static var max_acts: int = 12
## 难度进度。以撒化之后一个 Act 就是一层楼, 不再有"第几层"这个走廊概念 ——
## 但 current_floor 被整套难度曲线读着 (main.gd::ENEMY_MIN_FLOOR 的解锁门槛、
## enemy.gd 的 FLOOR_SCALE_SLOPE 与 ARMOR_PLATE_FLOOR_GATE、
## MapTemplates.TEMPLATE_MIN_FLOOR 的模板分档), 全部推倒重来没有意义, 所以它
## 保留 0..max_floors-1 的取值范围, 只换算法。
##
##     current_floor = (幕数-1) * ACT_DIFFICULTY_STRIDE + 本层已清房间数/2
##
## **跨幕累积, 不是每层归零。** 这一条是必须的, 不是风格选择:
##
## 归零版本 (current_floor = 本层已清房间数) 曾经上线过, 而它会把游戏后半段
## 的内容**静默锁死**。实测每幕的 current_floor 峰值只有 4 / 6 / 7 / 9 / ...
## (第 1 幕只有 5 个战斗房), 而门槛表要的是:
##   - floor 5  AIRCRAFT / MIRAGE / BATTLESHIP / LASER / CRUSHER / SPLITTER
##   - floor 8  MISSILE / WARP
##   - floor 9  第 3 层装甲板 (ARMOR_PLATE_FLOOR_GATE)
## 也就是说**第一幕永远刷不出那六种"真正需要新对策"的敌人**, 前三幕永远见不到
## MISSILE/WARP 和三层装甲。不报错、不崩溃, 玩家只会觉得敌人种类少。
## 房间数越少锁得越死 —— 而"房间少一点、幕数多一点"正是当前的设计方向。
##
## 房间进度**除以 2** 是为了让幕数占主导。不除的话, 一层之内的爬升幅度 (0..7)
## 和整个战役的爬升幅度一样大, 于是第 1 幕最后一间的难度约等于第 8 幕第一间,
## 曲线变成锯齿。除 2 之后层内只有 +0..3 的缓坡, 大方向由幕数决定。
##
## 顺带说明为什么不用"房间到起点的 BFS 深度": 深度最多只到 6-8, 同样够不到
## 后段门槛; 而且玩家回头走已清房间时深度会**倒退**, 难度忽上忽下。
## 已清房间数是单调的。
static var current_floor: int = 0
static var max_floors: int = 15

## 每推进一幕, 难度基线抬多少。
##
## 1 是按"12 幕走完 0..14"配的: 第 12 幕的基线是 11, 加上层内 +0..3 正好压到
## 上限 14。全部敌人种类在第 6 幕解锁完 (基线 5 + 层内 3 = 8), 第 7 幕见到三层
## 装甲, 之后交给难度圈 (get_difficulty_cycle 的遭遇规模 +4/圈 与装甲下界)。
const ACT_DIFFICULTY_STRIDE := 1

## 按当前幕数与本层进度重算 current_floor。mark_room_cleared() 与
## generate_floor() 各调一次 —— 这是它唯一的写入点。
static func _recompute_current_floor() -> void:
	var base := (current_act - 1) * ACT_DIFFICULTY_STRIDE
	current_floor = mini(max_floors - 1, base + rooms_cleared / 2)

# RPG Persistent Stats
static var gold: int = 150
static var player_level: int = 1
static var player_tier: int = 0
static var player_lives: int = 3
static var max_hp_lvl: int = 0
static var atk_bonus: int = 0
## 商店花钱买到的 atk_bonus 总数 (plasma_mod + 分支后的 star_tier), 与靠打
## 楼层升级涨的那部分分开计数。atk_bonus 是全项目唯一被精心限速的战斗数值
## (RPGManager.ATK_LEVELS_PER_POINT), 而 plasma_mod/star_tier 原来对购买
## 次数完全没有限制——autoloader 有 is_fire_rate_capped() 那样的"不卖零"
## 闸门, atk_bonus 却没有对应的机制。这个计数器就是补上那道闸门, 见
## shop_dialog.gd::can_buy_item() 和 SHOP_ATK_BONUS_CAP。
static var shop_atk_bonus_purchases: int = 0
const SHOP_ATK_BONUS_CAP := 5
static var speed_lvl: int = 0
static var fire_rate_lvl: int = 0
static var regen_lvl: int = 0
static var builder_lvl: int = 0

# RPG Branch & Archetype Specialization
## 这一局已经解锁的进阶流派 (团队共享)。空 = 只能走经典线。
##
## 分支不再是第一次升级就白给的了 —— 得先拿到对应的改装图纸
## (见 branch_blueprints.gd)。这条改动顺带把经典线的星级成长救活了:
## 以前所有人第一级就跳分支, player_tier 那条 0->3 的线实装了却没人见过。
##
## **团队共享而不是每人一份。** CLAUDE.md 记着这类奖励最容易踩的坑:
## "Any reward granted outside a battle has to ask 'which players?'" ——
## 商店那边就因为把 player_id 写死成 1, 让 P2 永远拿不到命/星级/天赋。
## 图纸是"这一局捡到的装备", 做成共享池就没有这一类分叉: 两个人看到的
## 可选分支永远一样, 也不会出现"P1 解锁了而 P2 的升级界面还是空的"。
static var unlocked_branches: Array[String] = []

static var tank_branch: String = "default" # "default", "speed", "heavy", "train", "counter", "trench"
static var branch_tier: int = 0            # 0=Unassigned/Base, 1=Tier 1, 2=Tier 2
static var has_iff_flag: bool = false      # Friendly IFF Flag: player attacks never damage the base eagle

# perk_id -> stack count (was Array[String] of unique unlocks; a single run
# now spans 15 floors instead of the original 6, so the fixed "10 unique
# perks then nothing but the gold_heal filler" pool ran out around floor
# 5-7. Perks are stackable now (see PERK_MAX_STACKS) so the level-up screen
# keeps offering real choices for the rest of a 15-floor act.
static var unlocked_perks: Dictionary = {}
static var p2_unlocked_perks: Dictionary = {}

# id (EncyclopediaData entry id, e.g. "enemy_sniper") -> true, once the
# player has actually encountered that enemy/item/building/terrain in a
# real battle. Deliberately NOT cleared by reset_campaign() below — this is
# a meta-unlock across runs (like a bestiary), not per-campaign state, so a
# new campaign should not re-fog entries the player has already seen.
static var discovered_encyclopedia: Dictionary = {}

static func discover_encyclopedia_entry(id: String) -> void:
	discovered_encyclopedia[id] = true

# How many times each perk can be picked. Perks with an existing numeric
# hook (HP/damage/rate/range/duration) scale per stack via
# RPGManager.get_perk_value(); perks that are pass/fail mechanical gates
# (full ice control, one-shot hard clay, platform damage buff) don't have a
# meaningful "3rd tier" without inventing a new threshold, so they stay
# single-unlock. Unlisted perks default to 1 (see max_stacks_for_perk).
const PERK_MAX_STACKS := {
	"titan_plating": 3,
	"rapid_loader": 3,
	"nitro_booster": 3,
	"nano_repair": 3,
	"high_explosive": 3,
	"magnetic_salvage": 3,
	"warp_drive": 3,
	"frost_cleats": 1,
	"ferry_artillery": 1,
	"clay_crusher": 1,
	# High-risk/high-reward shop-only perks (bullet.gd mechanics) --
	# ricochet_rounds stacks (each stack = +1 bounce before the bullet
	# finally dies); armor_piercing_rounds is a binary trade like the other
	# mechanical gates above, not a magnitude to scale.
	"ricochet_rounds": 3,
	"armor_piercing_rounds": 1,
	"amphibious_hull": 1,
	"kinetic_piston_rounds": 1,
	"iff_flag": 1,
}

static func max_stacks_for_perk(perk_id: String) -> int:
	return PERK_MAX_STACKS.get(perk_id, 1)

## Shared "grant one stack of this perk to this player, respecting the cap"
## used by both shop_dialog.gd and event_dialog.gd (both run in
## spire_map.tscn, operating on the persistent GameState.unlocked_perks
## directly rather than through a live RPGManager instance). Returns false if
## the perk was already at its cap.
static func grant_perk_stack(perk_id: String, player_id: int = 1) -> bool:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	var cap = max_stacks_for_perk(perk_id)
	var cur = int(perks.get(perk_id, 0))
	if cur >= cap:
		return false
	perks[perk_id] = cur + 1
	return true

## Grants the "star tier" reward (STAR power-up, the shop's ⭐ 战车升阶模块,
## the "depot" event's Weapon Star Upgrade) at the persistent GameState layer
## -- used by shop_dialog.gd and event_dialog.gd, which run in spire_map.tscn
## with no live RPGManager instance to touch.
##
## On the still-undecided "default" branch this bumps the player's classic
## tier (player_tier/p2_tier, 0-3), which player.gd's default-branch weapon
## path reads for multi-shot at T2 and armor-piercing plasma at T3. But
## player.gd only reads that tier in the "default" match arm -- once a
## player commits to speed/heavy/train (which happens at literally their
## first level-up, since the branch-choice screen has no skip option), the
## tier keeps incrementing internally but has zero observable effect. All
## three "star" reward sources would silently do nothing for the ~100% of
## players who've picked a branch. Redirect to +1 permanent ATK instead --
## every branch's damage formula (RPGManager.get_atk_damage) uses atk_bonus.
## 这一局有没有解锁某条进阶流派。
static func is_branch_unlocked(branch: String) -> bool:
	return unlocked_branches.has(branch)


## 解锁一条流派。返回 false 表示本来就已经解锁 —— 调用方拿它决定要不要发提示,
## 以及 (对宝箱/Boss 这类稀缺来源) 要不要改抽别的东西。
static func unlock_branch(branch: String) -> bool:
	if branch == "" or unlocked_branches.has(branch):
		return false
	unlocked_branches.append(branch)
	return true


static func grant_star_tier_reward(player_id: int = 1) -> void:
	var branch = tank_branch if player_id == 1 else p2_branch
	if branch == "default":
		if player_id == 1:
			player_tier = mini(player_tier + 1, 3)
		else:
			p2_tier = mini(p2_tier + 1, 3)
	else:
		atk_bonus += 1
		shop_atk_bonus_purchases += 1

## structure_id (String, e.g. "turret") -> owned count. Builder Controller
## structures used to be a flat "spend battle gold at placement time" cost;
## they're now shop-only consumable stock -- buy N in the shop (persists
## across battles like gold/perks), each in-battle placement consumes one
## unit instead of touching gold at all. See builder_controller.gd and
## shop_dialog.gd's BUILDING_ITEMS.
static var structure_inventory: Dictionary = {}

static func add_structure_stock(id: String, amount: int = 1) -> void:
	structure_inventory[id] = int(structure_inventory.get(id, 0)) + amount

static func consume_structure_stock(id: String) -> bool:
	var cur = int(structure_inventory.get(id, 0))
	if cur <= 0:
		return false
	structure_inventory[id] = cur - 1
	return true

static func get_structure_stock(id: String) -> int:
	return int(structure_inventory.get(id, 0))

# P2 Stats (For 2-Player Co-op)
static var p2_tier: int = 0
## 双人战役共享一个生命池 (player_lives), 不再有独立的 p2_lives —— main.gd 的
## _lives_shared() 机制下, 两个玩家死亡后靠按开火键手动复活, 扣的是同一个池子。
## 见 main.gd::_consume_shared_life_and_respawn()。
static var p2_branch: String = "default"
static var p2_branch_tier: int = 0

# Battle Configuration
static var battle_type: String = "battle"
static var challenge_mode: String = "" # "", "bomb_rain", "night_ops", "vault", "night_bombs", "escort"
# 这里曾经还有 total_enemies_override / boss_enabled 两个 static var, 全项目
# (含 .tscn) 除声明处外零引用 —— 既没人写也没人读, 但摆在"Battle Configuration"
# 名下很像是可用的旋钮。遭遇规模实际由 main.gd::start_game() 按 battle_type
# 直接赋 total_enemies, boss 与否由 battle_type == "boss" 决定。已删。

# Map Grid Data
## 本次 run 的种子。用来给"选哪张手搓地图"洗牌 —— 见
## MapTemplates._pick_from_pool()。
##
## 必须**持久化**而不是每次现摇: 存档读回来以后, 已经走过的楼层要还是同一张
## 图, 否则同一个存档反复读会看到不同地形。也不能直接用 randi() 当场决定,
## 那样连同一层重进都会换图。
##
## 0 表示"这是老存档 / 还没开始 run", 此时 _pick_from_pool() 退回原来的
## 纯 floor_idx 取模行为, 不会炸。
static var run_seed: int = 0

## 本层楼的房间图。key 是 FloorMap.key() 给的 "col,row" 字符串, value 是
## FloorMap._new_room() 那个字典 (type/depth/doors/secret_doors/cleared/
## visited/challenge_mode)。取代了原来的 spire_nodes + spire_connections ——
## 连接关系现在内含在每个房间的 doors 里, 不需要单独一张边表。
static var floor_rooms: Dictionary = {}
static var current_room: String = ""
static var floor_start_room: String = ""
static var floor_boss_room: String = ""
static var floor_secret_room: String = ""

## 秘密房是否已被炸开。一层只有一个秘密房, 所以一个布尔就够, 不需要按门记。
static var secret_room_found: bool = false

## 本层已清空的房间数。current_floor 跟着它走 (见上面那段), 单独留一个字段是
## 因为 current_floor 会被夹到 max_floors-1, 而进度显示要的是真实值。
static var rooms_cleared: int = 0

## 换货费用。跨房间存活, 存进存档。
##
## 原来这是 shop_dialog 的实例变量, 每次 setup_shop() 重置成 REROLL_BASE ——
## 那在尖塔时代是对的: 进一次商店节点就是一次性的, "涨价只在同一次进店内累积"
## 是刻意的设计。房间制下商店房可以自由进出, 实例变量会在每次进门时重置,
## 于是走出去再进来费用就回到 20 G, 递增彻底失效。提到 GameState 上按**楼层**
## 累积。
static var shop_reroll_cost: int = 20
const SHOP_REROLL_BASE := 20
# 硬核化调整: 和 shop_dialog.gd::REROLL_STEP 一起从 25 改成 30, 两处必须同步。
const SHOP_REROLL_STEP := 30

static func bump_shop_reroll_cost() -> void:
	shop_reroll_cost += SHOP_REROLL_STEP
	save_campaign()

## Which of the 3 unique visual themes (Plains/Desert/Glacial) an act reuses.
## Acts 1-3 map 1:1; acts 4-8 cycle back through the same 3 themes.
static func get_visual_act(act_idx: int = -1) -> int:
	var a = current_act if act_idx == -1 else act_idx
	return ((a - 1) % 3) + 1

## How many full 3-act laps have completed before this act -- 0 for acts
## 1-3, 1 for acts 4-6, 2 for acts 7-8. Used to scale difficulty back up on
## repeat laps so acts 4-8 aren't just acts 1-3 replayed at identical
## difficulty.
static func get_difficulty_cycle(act_idx: int = -1) -> int:
	var a = current_act if act_idx == -1 else act_idx
	return (a - 1) / 3

static func get_act_name(act_idx: int = -1) -> String:
	var a = current_act if act_idx == -1 else act_idx
	var cycle = get_difficulty_cycle(a)
	var base_name = ""
	match get_visual_act(a):
		1: base_name = "诺曼底平原与河道要塞 (Frontline Plains & Rivers)"
		2: base_name = "阿塔卡马狂沙与流沙迷宫 (Atacama Quicksand Labyrinth)"
		3: base_name = "极地冻原与异次元要塞 (Glacial Singularity Citadel)"
	var suffix = "" if cycle == 0 else "  [重临 x%d / Lap %d]" % [cycle + 1, cycle + 1]
	return "ACT %d: %s%s" % [a, base_name, suffix]

## 曾经在这里手抄了一份 heavy/train/counter/trench 的加成公式, 和
## RPGManager 那四张 *_HP_BONUS 表各自独立维护 —— 结果没有一条真的对得上:
## heavy 是 `2+tier*2` (tier1=4, 表里是 1; tier2=6, 表里是 5), train 是
## `1+tier` (tier1=2, 表里是 1), counter/trench 是 `2+tier` (tier1=3, 表里
## 都是 2)。两边只有 tier2 的 counter/trench 碰巧对上。这份地图回退值
## (没有存活 RPGManager 时用, 比如地图界面) 因此和真正战斗里的血量对不上。
## 直接引用 RPGManager 的表 (GDScript 的类常量不需要实例就能读), 单一数据源。
static func get_player_max_hp() -> int:
	var bonus_hp = 0
	if tank_branch == "heavy":
		bonus_hp += RPGManager.HEAVY_HP_BONUS[branch_tier]
	elif tank_branch == "train":
		bonus_hp += RPGManager.TRAIN_HP_BONUS[branch_tier]
	elif tank_branch == "counter":
		bonus_hp += RPGManager.COUNTER_HP_BONUS[branch_tier]
	elif tank_branch == "trench":
		bonus_hp += RPGManager.TRENCH_HP_BONUS[branch_tier]
	return 1 + max_hp_lvl + bonus_hp

static func reset_campaign(p_count: int = 1) -> void:
	mode = GameMode.CAMPAIGN
	player_count = p_count
	current_act = 1
	current_floor = 0
	gold = 150
	player_level = 1
	player_tier = 0
	player_lives = 3
	tank_branch = "default"
	branch_tier = 0
	unlocked_branches.clear()
	has_iff_flag = false
	unlocked_perks.clear()
	structure_inventory.clear()
	p2_tier = 0
	p2_branch = "default"
	p2_branch_tier = 0
	p2_unlocked_perks.clear()
	max_hp_lvl = 0
	atk_bonus = 0
	shop_atk_bonus_purchases = 0
	speed_lvl = 0
	fire_rate_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	battle_type = "battle"
	challenge_mode = ""
	# 每局换一批地图。maxi(1, ...) 是因为 0 被 _pick_from_pool() 当作
	# "没有种子"的哨兵值。
	run_seed = maxi(1, randi())
	generate_floor()

static func advance_to_next_act() -> void:
	current_act = mini(current_act + 1, max_acts)
	generate_floor()  # 内部会 _recompute_current_floor(), 不要在这里把 current_floor 清零

# ==================== 楼层房间图 (FloorMap) ====================
#
# 这里原本是杀戮尖塔那套分支节点图: _floor_band() 把 15 层归进节奏带、
# _band_pool() 给每带一份候选行、_generate_spire_map() 摇出节点和不交叉的
# 连线、_ensure_shop_coverage() 用 DAG 上的 DP 保证一条路线上有 3 个商店。
#
# 全部被以撒式楼层取代 (scripts/floor_map.gd)。两者的结构差别决定了这些函数
# 没有一个能平移过来:
#
#   - 尖塔图是**有向无环图**, 按 floor 分层、单向向上, 所以"最优路线"是一个
#     可以 DP 的东西, _ensure_shop_coverage() 才有意义。房间图是**无向连通
#     图**, 玩家可以回头, 不存在"一条路线"—— 商店保底因此变成"这一层有没有
#     商店房", 由 FloorMap.MIN_SHOPS_PER_FLOOR 在生成时保证。
#   - 尖塔的节点类型按楼层节奏带摇; 房间类型按**死胡同**分配 (以撒的规矩:
#     特殊房放在要多走一趟才能到的地方, 于是"绕不绕"成为决策)。
#
# best_shop_route() 一并删掉了 —— 它的调用方 (tools/test_shop_pricing.gd 和
# tools/probe_balance_report.gd) 改成按楼层统计商店房。

const FloorMapCls = preload("res://scripts/floor_map.gd")

## 生成当前 act 的楼层。
##
## 种子由 run_seed 和 current_act 混合而成, 而不是直接用 run_seed: 直接用的
## 话 8 个 act 会拿到同一个种子, 也就是同一张房间图, 整个 run 走 8 遍一模一样
## 的楼层。混入 act 之后每层不同, 但仍然完全由 run_seed 决定 —— 存档读回来
## 还是同一层楼, 这正是 run_seed 当初被持久化的理由。
static func generate_floor() -> void:
	var floor_seed := hash("%d::floor::%d" % [run_seed, current_act])
	var data: Dictionary = FloorMapCls.generate(current_act, floor_seed, get_visual_act())

	floor_rooms = data["rooms"]
	floor_start_room = str(data["start"])
	floor_boss_room = str(data["boss"])
	floor_secret_room = str(data["secret"])
	current_room = floor_start_room
	secret_room_found = false
	rooms_cleared = 0
	shop_reroll_cost = SHOP_REROLL_BASE
	# 新一层的起始难度不是 0, 而是这一幕的基线 —— 不这么做就退回到
	# 每层归零, 后段内容重新被锁死 (见 current_floor 那段注释)。
	_recompute_current_floor()
	battle_type = "battle"
	challenge_mode = ""


static func has_floor() -> bool:
	return not floor_rooms.is_empty() and floor_rooms.has(current_room)


static func get_room(room_key: String) -> Dictionary:
	return floor_rooms.get(room_key, {})


static func current_room_data() -> Dictionary:
	return get_room(current_room)


## 房间类型 -> main.gd 认识的 battle_type。以撒的房型和原来的节点类型不是
## 一一对应: 普通房打的是原来的 "battle", boss 房是 "boss", 挑战房是
## "challenge"; 商店/宝物/事件/休息房不打仗, 但仍然要给一个合法值, 否则
## main.gd::encounter_size() 会拿 ENCOUNTER_BASE 的默认分支去算遭遇规模。
##
## "shop" 单独给一个值 (而不是退到 "battle" 默认分支), 是因为
## MapTemplates.get_layout_for_stage() 按 battle_type 分派地图池 —— 退到
## "battle" 意味着商店房和普通战斗房抽同一个池子, 货位 (main.gd::
## SHOP_STAND_CELLS) 摆下去就可能压在那张图的砖墙/水面上, 玩家根本走不到货位。
## encounter_size()/spawn_interval_for() 对不认识的 battle_type 会退回
## ENCOUNTER_BASE["battle"] 的默认值, 所以这里加一个新值不会破坏遭遇规模计算 ——
## 反正商店房从不进 _begin_room_encounter(), 这两个函数压根不会被调用。
static func battle_type_for_room(room: Dictionary) -> String:
	match str(room.get("type", "normal")):
		"boss": return "boss"
		"challenge": return "challenge"
		"elite": return "elite"
		"shop": return "shop"
		_: return "battle"


## 走进一个房间。只更新状态, 不负责建地图 —— 那是 main.gd::enter_room() 的事。
static func visit_room(room_key: String) -> void:
	if not floor_rooms.has(room_key):
		return
	current_room = room_key
	var room: Dictionary = floor_rooms[room_key]
	room["visited"] = true
	battle_type = battle_type_for_room(room)
	challenge_mode = str(room.get("challenge_mode", ""))
	save_campaign()


## 清空一个房间。这是 current_floor 唯一的增长点 —— 难度按"打赢了多少间"爬,
## 而不是按"走进了多少间", 否则玩家一路跑过去不打, 难度照样涨。
##
## count_progress=false 给商店/宝物/事件这些非战斗房用: 它们一进门就算清空
## (好让门开着), 但它们不是一场仗, 不该推高难度。把这个参数漏掉的话, 一层
## 楼里逛几个商店就能把敌人档位顶上去, 而玩家一枪没开。
static func mark_room_cleared(room_key: String, count_progress: bool = true) -> void:
	if not floor_rooms.has(room_key):
		return
	var room: Dictionary = floor_rooms[room_key]
	if bool(room.get("cleared", false)):
		return
	room["cleared"] = true
	if count_progress:
		rooms_cleared += 1
		_recompute_current_floor()
	save_campaign()


## 秘密房被炸开。存进存档, 否则读档之后裂缝墙又长回来了。
static func mark_secret_found() -> void:
	if secret_room_found:
		return
	secret_room_found = true
	save_campaign()


## 这一层是不是打通了 = boss 房清空了没有。
static func is_floor_complete() -> bool:
	if floor_boss_room == "" or not floor_rooms.has(floor_boss_room):
		return false
	return bool(floor_rooms[floor_boss_room].get("cleared", false))


## 从 room_key 往 d 方向能不能走过去。把"门存在""不是没炸开的秘密门"
## "本房已清空"三条合到一处 —— 门画成开着但走不过去 (或者反过来) 全都是
## 这三条在两个地方各写一遍写歪的。
static func can_exit(room_key: String, d: int) -> bool:
	var room := get_room(room_key)
	if room.is_empty():
		return false
	return FloorMapCls.is_door_passable(room, d, secret_room_found)


## room_key 往 d 方向的邻居 key, 没有就返回 ""。
static func neighbor_key(room_key: String, d: int) -> String:
	var c := FloorMapCls.parse_key(room_key)
	var nk := FloorMapCls.key(c + FloorMapCls.DIR_VECTORS[d])
	return nk if floor_rooms.has(nk) else ""


## 一层楼里还剩几间没清空的战斗房 —— 给 HUD 显示进度用。
static func combat_rooms_left() -> int:
	var n := 0
	for k in floor_rooms.keys():
		if FloorMapCls.is_combat_room(floor_rooms[k]):
			n += 1
	return n



# ==================== DAILY CHALLENGE ====================
# One seeded, single-life run per calendar day: same map + same enemy
# sequence for everyone who plays today (see main.gd::start_game()'s
# DAILY_CHALLENGE branch, which calls `seed(GameState.get_daily_seed())`
# before generating the map/enemies), so a score comparison is meaningful.
# Separate save file from the campaign one so daily-challenge results don't
# interact with campaign progress at all.

const DAILY_SAVE_PATH = "user://daily_challenge_save.json"
static var _daily_best_score: int = 0
static var _daily_best_date: String = ""
static var _daily_record_loaded: bool = false

static func get_daily_date_string() -> String:
	var d = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func get_daily_seed() -> int:
	# String.hash() on "YYYY-MM-DD" alone has weak avalanche for these
	# particular strings -- consecutive days differ only in the last digit,
	# and hashing produced near-sequential seeds (e.g. 08-20..08-23 hashed to
	# ...619/620/621/622). Salting with a fixed tag before hashing spreads
	# adjacent days apart instead of relying on the tail character alone.
	return hash(get_daily_date_string() + "::tank_battle_daily_seed")

static func _load_daily_record() -> void:
	if _daily_record_loaded:
		return
	_daily_record_loaded = true
	if not FileAccess.file_exists(DAILY_SAVE_PATH):
		return
	var file = FileAccess.open(DAILY_SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_daily_best_score = int(json.data.get("best_score", 0))
		_daily_best_date = str(json.data.get("best_date", ""))
	file.close()

## Today's best score, or 0 if today's date has no record yet (a record from
## a previous day doesn't count -- different seed, not a fair comparison).
static func get_daily_best_score() -> int:
	_load_daily_record()
	if _daily_best_date != get_daily_date_string():
		return 0
	return _daily_best_score

## Call once when a Daily Challenge run ends. Returns true if `score` beat
## today's best.
static func submit_daily_score(score: int) -> bool:
	_load_daily_record()
	var today = get_daily_date_string()
	if _daily_best_date != today:
		_daily_best_score = 0
		_daily_best_date = today
	var is_record = score > _daily_best_score
	if is_record:
		_daily_best_score = score
	var file = FileAccess.open(DAILY_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"best_score": _daily_best_score, "best_date": _daily_best_date}, "\t"))
		file.close()
	return is_record

# ==================== CAMPAIGN SAVE / LOAD SYSTEM ====================

const SAVE_PATH = "user://campaign_save.json"

static func has_saved_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 把整局战役状态打成一个字典。
##
## 从 save_campaign() 里拆出来的, 因为**联机也要传同一份东西**: 客户端加入
## 战役合作时必须完整接管主机的这一局 (幕数、金币、天赋、楼层图、当前房间)。
##
## 拆开而不是各写一份的理由是硬的: `tools/test_persistence_roundtrip.gd` 会
## 反射 GameState 的全部字段, 要求每一个都能穿过 save/load 往返, 漏一个就变红。
## 联机同步走同一个字典, 就等于**白拿了这条保障** —— 以后给 GameState 加字段,
## 忘了同步的话那个测试会先叫起来, 而不是等到某一局联机里"客户端的天赋莫名
## 少了一条"。两份手写清单是绝对会分家的。
static func campaign_to_dict() -> Dictionary:
	# floor_rooms 是"字典套字典, 里面还有数组", JSON 能原样吞下去, 不需要像
	# 原来的 spire_nodes 那样先把 Vector2 拆成 {x, y} —— FloorMap 的房间字典
	# 刻意只用 int/bool/String/Array, 就是为了免掉那一层手工序列化 (以及它
	# 对应的、只要漏一个字段就静默丢数据的还原代码)。
	#
	# 深拷贝: 直接塞引用的话, 存档写完之后游戏里再改房间状态会连带改掉这个
	# 字典 —— 虽然此处写完就丢, 但 duplicate(true) 让"存下来的是当时的快照"
	# 这件事在代码上是显然的。
	var rooms_copy: Dictionary = floor_rooms.duplicate(true)

	var save_dict = {
		"mode": int(mode),
		"player_count": player_count,
		"current_act": current_act,
		"current_floor": current_floor,
		"gold": gold,
		"player_level": player_level,
		"player_tier": player_tier,
		"player_lives": player_lives,
		"tank_branch": tank_branch,
		"branch_tier": branch_tier,
		# **必须 duplicate()。** 字典和数组是引用: 直接放进去的话, 之后任何一次
		# reset_campaign() (它会 .clear()) 都会把这份"已经存下来的"快照一起清空。
		# 存盘那条路径侥幸没事 (立刻就 JSON 序列化了), 但 NetSession 的
		# client_campaign_backup 是**原样留在内存里**的 —— 客户端进大厅时备份
		# 自己那局, 等 leave() 再还原, 中间隔着一次 reset。CLAUDE.md 给
		# test_persistence_roundtrip.gd 记的正是同一个坑。
		"unlocked_branches": unlocked_branches.duplicate(),
		"unlocked_perks": unlocked_perks.duplicate(),
		"structure_inventory": structure_inventory.duplicate(),
		"p2_tier": p2_tier,
		"p2_branch": p2_branch,
		"p2_branch_tier": p2_branch_tier,
		"p2_unlocked_perks": p2_unlocked_perks,
		"max_hp_lvl": max_hp_lvl,
		"atk_bonus": atk_bonus,
		"shop_atk_bonus_purchases": shop_atk_bonus_purchases,
		"speed_lvl": speed_lvl,
		"fire_rate_lvl": fire_rate_lvl,
		"regen_lvl": regen_lvl,
		"builder_lvl": builder_lvl,
		# 商店买的永久增益, 和上面几个 *_lvl 同类 —— 一次性买断、跨楼层生效,
		# 所以必须进存档。漏掉它的表现是"花钱买了、重载之后没了", 而且不报错。
		"has_iff_flag": has_iff_flag,
		"battle_type": battle_type,
		"challenge_mode": challenge_mode,
		"run_seed": run_seed,
		"floor_rooms": rooms_copy,
		"current_room": current_room,
		"floor_start_room": floor_start_room,
		"floor_boss_room": floor_boss_room,
		"floor_secret_room": floor_secret_room,
		"secret_room_found": secret_room_found,
		"rooms_cleared": rooms_cleared,
		"shop_reroll_cost": shop_reroll_cost,
		"discovered_encyclopedia": discovered_encyclopedia,
		"difficulty": difficulty,
	}
	return save_dict


const NetSessionCls = preload("res://scripts/net_session.gd")


static func save_campaign() -> void:
	# **联机客户端一律不写存档。**
	#
	# 加入战役合作之后, 这台机器的 GameState 装的是**主机那一局**
	# (campaign_from_dict 整个覆盖过)。而 save_campaign() 的三个调用点
	# (visit_room / mark_room_cleared / mark_secret_found) 每过一道门就会
	# 触发一次 —— 不拦的话, "陪朋友打一局联机战役"会把自己的
	# campaign_save.json 覆盖成别人的进度, 而且是静默的、不可逆的。
	#
	# 拦在这里而不是三个调用点上: 少一处漏, 而且以后新增调用点自动被覆盖。
	if NetSessionCls.is_client():
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(campaign_to_dict(), "\t"))
		file.close()


## campaign_to_dict() 的逆。存档读取和联机同步共用 —— 见 campaign_to_dict()
## 顶部关于"白拿一条回归保障"的说明。
static func campaign_from_dict(d: Dictionary) -> void:
	mode = int(d.get("mode", GameMode.CAMPAIGN)) as GameMode
	player_count = int(d.get("player_count", 1))
	current_act = int(d.get("current_act", 1))
	current_floor = int(d.get("current_floor", 0))
	gold = int(d.get("gold", 150))
	player_level = int(d.get("player_level", 1))
	player_tier = int(d.get("player_tier", 0))
	player_lives = int(d.get("player_lives", 3))
	tank_branch = str(d.get("tank_branch", "default"))
	branch_tier = int(d.get("branch_tier", 0))
	# 逐个转成 String 再装进 Array[String] —— JSON 反序列化出来的是无类型
	# Array, 直接赋值给类型化数组会在运行时报类型错。老存档没有这个 key,
	# 读出来就是空数组 = 一条分支都没解锁, 正好是新规则下的正确起点。
	unlocked_branches.clear()
	for b in d.get("unlocked_branches", []):
		unlocked_branches.append(str(b))
	unlocked_perks = _load_perk_dict(d.get("unlocked_perks", {}))
	structure_inventory = _load_perk_dict(d.get("structure_inventory", {})) # same {string: int} shape, reuse the same loader
	p2_tier = int(d.get("p2_tier", 0))
	# p2_lives 字段不再读取: 老存档里可能还带着这个 key, 直接忽略就是了 ——
	# 生命现在是单一共享池 (player_lives), 见上面 p2_branch 之前的注释。
	p2_branch = str(d.get("p2_branch", "default"))
	p2_branch_tier = int(d.get("p2_branch_tier", 0))
	p2_unlocked_perks = _load_perk_dict(d.get("p2_unlocked_perks", {}))
	discovered_encyclopedia = _load_perk_dict(d.get("discovered_encyclopedia", {}))
	difficulty = str(d.get("difficulty", "normal"))
	max_hp_lvl = int(d.get("max_hp_lvl", 0))
	atk_bonus = int(d.get("atk_bonus", 0))
	shop_atk_bonus_purchases = int(d.get("shop_atk_bonus_purchases", 0))
	speed_lvl = int(d.get("speed_lvl", 0))
	fire_rate_lvl = int(d.get("fire_rate_lvl", 0))
	regen_lvl = int(d.get("regen_lvl", 0))
	builder_lvl = int(d.get("builder_lvl", 0))
	# 老存档没有这个 key -> false, 也就是"没买过", 和实际情况一致。
	has_iff_flag = bool(d.get("has_iff_flag", false))
	battle_type = str(d.get("battle_type", "battle"))
	challenge_mode = str(d.get("challenge_mode", ""))
	# 老存档没有这个字段 -> 0 -> _pick_from_pool() 退回旧的取模行为。
	# 存档里已经打过的楼层因此和存档时看到的一致, 不会因为升级而变脸。
	run_seed = int(d.get("run_seed", 0))

	floor_rooms = _load_floor_rooms(d.get("floor_rooms", {}))
	current_room = str(d.get("current_room", ""))
	floor_start_room = str(d.get("floor_start_room", ""))
	floor_boss_room = str(d.get("floor_boss_room", ""))
	floor_secret_room = str(d.get("floor_secret_room", ""))
	secret_room_found = bool(d.get("secret_room_found", false))
	rooms_cleared = int(d.get("rooms_cleared", 0))
	shop_reroll_cost = int(d.get("shop_reroll_cost", SHOP_REROLL_BASE))


static func load_campaign() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK or not (json.data is Dictionary):
		return false
	campaign_from_dict(json.data)
	return true


## 保证有一层可以进的楼。**故意不放在 load_campaign() 里** —— 那个函数必须是
## 纯反序列化。
##
## 之前这段兜底写在 load_campaign() 末尾, 于是"读出来的 current_room 不在
## floor_rooms 里"会触发 generate_floor(), 而它会顺手重置 current_floor /
## battle_type / challenge_mode / floor_*_room 五个刚刚才读进来的字段。
## tools/test_persistence_roundtrip.gd 一次点名了全部六个 —— 反射式的往返测试
## 正是为了逮这种"存进去了、也读出来了、然后被同一个函数覆盖掉"的情况。
##
## 另一处修正: 房间图非空但 current_room 对不上时, 只把玩家挪回起始房, **不**
## 重新生成整层。重新生成会连带抹掉所有已清房间的记录 —— 读个档把打过的进度
## 清零, 比"位置不对"严重得多。
static func ensure_floor_ready() -> void:
	if floor_rooms.is_empty():
		generate_floor()
		return
	if floor_rooms.has(current_room):
		return
	if floor_rooms.has(floor_start_room):
		current_room = floor_start_room
	else:
		current_room = str(floor_rooms.keys()[0])


## JSON 把所有数字读成 float, 把 doors 读成无类型 Array。房间字典里的
## col/row/depth 要是留着 float, FloorMap.key() 的 "%d,%d" 会把 3.0 格式化成
## "3" 看起来没事, 但任何 int 比较 (深度排序、邻居查找) 都会在 float 上做,
## 而 doors[d] 留着 Variant 会让 `bool(...)` 之外的用法静默出错。统一收敛。
static func _load_floor_rooms(raw) -> Dictionary:
	var result: Dictionary = {}
	if not (raw is Dictionary):
		return result
	for k in raw.keys():
		var r = raw[k]
		if not (r is Dictionary):
			continue
		var room: Dictionary = {
			"col": int(r.get("col", 0)),
			"row": int(r.get("row", 0)),
			"type": str(r.get("type", "normal")),
			"depth": int(r.get("depth", 0)),
			"cleared": bool(r.get("cleared", false)),
			"visited": bool(r.get("visited", false)),
			"secret": bool(r.get("secret", false)),
			"challenge_mode": str(r.get("challenge_mode", "")),
			"doors": _load_bool4(r.get("doors", [])),
			"secret_doors": _load_bool4(r.get("secret_doors", [])),
			# "size" 是后加的字段 (大/超大房间), 漏掉这一行的话字段会在每次
			# 读档后静默还原成 "normal" —— 跟本文件其它每一行一样, 都是
			# 手抄字段表, 加字段必须两头一起改 (见 tools/test_persistence_roundtrip.gd)。
			"size": str(r.get("size", "normal")),
		}
		# 商店货架。**这一行以前是漏的**, 而丢失是完全静默的:
		# save_campaign() 会把 shop_stock 原样写进文件 (floor_rooms 是整份
		# duplicate(true)), 却在这里被丢掉。后果正是 _ensure_shop_stock() 那段
		# 注释里说必须避免的事 —— 在商店房存盘再读档, 货架重新洗一批,
		# 换货机和它那套递增计费被完全架空。
		#
		# 之所以一直没人喊: test_persistence_roundtrip.gd 把 floor_rooms 整个
		# 豁免了 ("字典套字典还带数组, 比不了嵌套结构"), 而这是那份豁免底下
		# 唯一一个真的会丢数据的字段。联机把它顶出来了 —— 客户端接管主机的
		# 战役状态时走的就是这条路, 货架丢了之后客户端看到的是另一批货。
		if r.has("shop_stock"):
			room["shop_stock"] = _load_shop_stock(r["shop_stock"])
		result[str(k)] = room
	return result


## 一格货位只存 id + 成交价 + 是否卖掉 (图标和描述每次从 ShopDialog 现查),
## 所以还原也只认这三个字段。
static func _load_shop_stock(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for e in raw:
		if not (e is Dictionary):
			continue
		out.append({
			"id": str(e.get("id", "")),
			"cost": int(e.get("cost", 0)),
			"sold": bool(e.get("sold", false)),
		})
	return out


static func _load_bool4(raw) -> Array:
	var out: Array = [false, false, false, false]
	if raw is Array:
		for i in range(mini(4, raw.size())):
			out[i] = bool(raw[i])
	return out

## Reads either the new {perk_id: stack_count} format or an old save's
## Array[String] of unique perk ids (each implicitly 1 stack), so existing
## save files from before perks became stackable still load instead of
## erroring out on a type mismatch.
static func _load_perk_dict(raw) -> Dictionary:
	var result: Dictionary = {}
	if raw is Dictionary:
		for k in raw.keys():
			result[str(k)] = int(raw[k])
	elif raw is Array:
		for p in raw:
			result[str(p)] = 1
	return result

static func delete_saved_game() -> void:
	# 和 save_campaign() 同一个理由: 联机战役里全灭时主机会删掉自己的存档,
	# 客户端跟着删就等于替对方的失败陪葬掉自己的进度。
	if NetSessionCls.is_client():
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
