class_name RPGManager
extends RefCounted

signal stats_changed
signal leveled_up(new_level: int)
signal gold_changed(new_gold: int)
signal branch_changed(player_id: int, new_branch: String, new_tier: int)

var level: int = 1
var gold: int = 100

# 属性点加成
var atk_bonus: int = 0      # 攻击力加成
var fire_rate_lvl: int = 0  # 攻速强化等级
var speed_lvl: int = 0      # 移速强化等级
var max_hp_lvl: int = 0     # 最大装甲等级
var regen_lvl: int = 0      # 纳米自愈等级
var builder_lvl: int = 0    # 防御工程强化

# RPG 分支流派与特性 (P1)

## 分支流派的**权威名单**。
##
## 这份名单以前只是下面那行注释里的一串字符串, 而 CLAUDE.md 记着它"已经长过
## 两次", 每次新增还都得配一个自己的射速地板 (FIRE_CD_FLOOR_*), 漏了就静默
## 继承 FIRE_CD_FLOOR_OTHER。注释管不住这种事 —— 现在有了常量, 就能被断言:
## tools/test_branch_unlock.gd 拿它和 branch_blueprints.gd 的图纸表对齐,
## 少一条 = 那条分支这一局永远解锁不了, 而那不会有任何报错。
const BRANCHES := ["default", "speed", "heavy", "train", "counter", "trench"]

var tank_branch: String = "default" # 取值见 BRANCHES
var branch_tier: int = 0            # 0=基础, 1=一阶进阶, 2=二阶终极
var unlocked_perks: Dictionary = {} # perk_id -> stack count, see GameState.PERK_MAX_STACKS

# RPG 分支流派与特性 (P2 - 双人合作各自独立选择)
var p2_tank_branch: String = "default"
var p2_branch_tier: int = 0
var p2_unlocked_perks: Dictionary = {}

# 每额外一层叠加的边际价值递减曲线 (第1层100%/第2层65%/第3层45%)，避免线性
# 叠 3 层的数值感觉失控，同时仍然让每一次选择都有明确增量。
const PERK_STACK_CURVE := [1.0, 0.65, 0.45]

## 分支 tier 1/2 的加成表, 按 [tier0(不可达), tier1, tier2] 索引。
const HEAVY_HP_BONUS := [0, 1, 5]
const HEAVY_DMG_BONUS := [0, 1, 5]
const TRAIN_HP_BONUS := [0, 1, 3]
## train 主炮的伤害加成。原来是硬编码在 player.gd 武器分支里的 `dmg + 1 +
## b_tier`, 不走这张表 —— 后果是 get_atk_damage() 对 train 分支永远只返回
## "1 + atk_bonus", 而 tools/test_player_power.gd 的 tier0/tier1 分支平价
## 检查就是靠调这个函数量 DPS 的, 所以 train 真实的主炮强度从来没被那两条
## 闸门看见过。
##
## 集中到这张表之后立刻暴露了问题: 原公式在 tier1 (1级, atk_bonus=0) 算出
## 主炮伤害 3, 是 default (伤害 1) 的 3 倍, DPS 倍差 x3.0 —— 比 heavy 当年
## 那次 tier1 3.40x 的 bug 还夸张, 只是因为不走这张表所以从来没被测试
## 抓到过。tier1 定为 0、tier2 定为 1: tier1 的"开局回报"本来就该是那节
## 立刻挂上的炮塔车厢 (拿到 CARRIAGE_SHARE_FLOOR 测的那份独立 DPS), 不需要
## 主炮再叠一份; tier2 给 +1, 和当时一起解锁的 can_destroy_steel 呼应。
const TRAIN_DMG_BONUS := [0, 0, 1]
const SPEED_MOVE_BONUS := [0.0, 0.25, 0.60]
const SPEED_FIRE_BONUS := [0.0, 0.70, 1.50]
const COUNTER_HP_BONUS := [0, 2, 4]
const COUNTER_DMG_BONUS := [0, 1, 3]
const TRENCH_HP_BONUS := [0, 2, 4]
# tier2 曾经是 3。ATK_LEVELS_PER_POINT 从 4 调到 5 之后 default 的 atk_bonus
# 涨得更慢, TRENCH_DMG_BONUS 这份分支专属加成在总伤害里的占比反而被动变大——
# 12 级 tier2 单体 DPS 从 149% 冲到 170%, 顶穿 test_player_power.gd 的 150%
# 上限。降到 2 才把它压回 142%, 见该测试 _check_trench_aoe_output()。
const TRENCH_DMG_BONUS := [0, 1, 2]

func get_branch(player_id: int = 1) -> String:
	return tank_branch if player_id == 1 else p2_tank_branch

func get_branch_tier(player_id: int = 1) -> int:
	return branch_tier if player_id == 1 else p2_branch_tier

func reset() -> void:
	level = 1
	gold = 100
	atk_bonus = 0
	fire_rate_lvl = 0
	speed_lvl = 0
	max_hp_lvl = 0
	regen_lvl = 0
	builder_lvl = 0
	tank_branch = "default"
	branch_tier = 0
	unlocked_perks.clear()
	p2_tank_branch = "default"
	p2_branch_tier = 0
	p2_unlocked_perks.clear()
	stats_changed.emit()
	gold_changed.emit(gold)
	branch_changed.emit(1, tank_branch, branch_tier)
	branch_changed.emit(2, p2_tank_branch, p2_branch_tier)

func sync_from_game_state() -> void:
	level = GameState.player_level
	gold = GameState.gold
	atk_bonus = GameState.atk_bonus
	fire_rate_lvl = GameState.fire_rate_lvl
	speed_lvl = GameState.speed_lvl
	max_hp_lvl = GameState.max_hp_lvl
	regen_lvl = GameState.regen_lvl
	builder_lvl = GameState.builder_lvl
	tank_branch = GameState.tank_branch
	branch_tier = GameState.branch_tier
	unlocked_perks = GameState.unlocked_perks.duplicate()
	p2_tank_branch = GameState.p2_branch
	p2_branch_tier = GameState.p2_branch_tier
	p2_unlocked_perks = GameState.p2_unlocked_perks.duplicate()

	stats_changed.emit()
	gold_changed.emit(gold)
	branch_changed.emit(1, tank_branch, branch_tier)
	branch_changed.emit(2, p2_tank_branch, p2_branch_tier)

func sync_to_game_state() -> void:
	GameState.player_level = level
	GameState.gold = gold
	GameState.atk_bonus = atk_bonus
	GameState.fire_rate_lvl = fire_rate_lvl
	GameState.speed_lvl = speed_lvl
	GameState.max_hp_lvl = max_hp_lvl
	GameState.regen_lvl = regen_lvl
	GameState.builder_lvl = builder_lvl
	GameState.tank_branch = tank_branch
	GameState.branch_tier = branch_tier
	GameState.unlocked_perks = unlocked_perks.duplicate()
	GameState.p2_branch = p2_tank_branch
	GameState.p2_branch_tier = p2_branch_tier
	GameState.p2_unlocked_perks = p2_unlocked_perks.duplicate()

func set_branch(new_branch: String, player_id: int = 1) -> void:
	if player_id == 1:
		tank_branch = new_branch
		if branch_tier == 0:
			branch_tier = 1
	else:
		p2_tank_branch = new_branch
		if p2_branch_tier == 0:
			p2_branch_tier = 1
	sync_to_game_state()
	branch_changed.emit(player_id, get_branch(player_id), get_branch_tier(player_id))
	stats_changed.emit()

func promote_branch_tier(player_id: int = 1) -> void:
	if player_id == 1:
		branch_tier = mini(branch_tier + 1, 2)
	else:
		p2_branch_tier = mini(p2_branch_tier + 1, 2)
	sync_to_game_state()
	branch_changed.emit(player_id, get_branch(player_id), get_branch_tier(player_id))
	stats_changed.emit()

## Returns false (no-op) once perk_id is already at GameState.max_stacks_for_perk.
func add_perk(perk_id: String, player_id: int = 1) -> bool:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	var cur = int(perks.get(perk_id, 0))
	if cur >= GameState.max_stacks_for_perk(perk_id):
		return false
	perks[perk_id] = cur + 1
	sync_to_game_state()
	stats_changed.emit()
	return true

func has_perk(perk_id: String, player_id: int = 1) -> bool:
	return get_perk_stacks(perk_id, player_id) > 0

func get_perk_stacks(perk_id: String, player_id: int = 1) -> int:
	var perks = unlocked_perks if player_id == 1 else p2_unlocked_perks
	return int(perks.get(perk_id, 0))

## base * how many stacks owned, run through PERK_STACK_CURVE so each
## additional copy of the same perk still matters but tapers off instead of
## scaling linearly (3 stacks of rapid_loader is +65% total, not +90%).
func get_perk_value(perk_id: String, base: float, player_id: int = 1) -> float:
	var stacks = get_perk_stacks(perk_id, player_id)
	var total := 0.0
	for i in range(mini(stacks, PERK_STACK_CURVE.size())):
		total += base * PERK_STACK_CURVE[i]
	return total

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

## 唯一的升级入口。以撒式经验条已经取消 —— 击杀/道具/事件/商店都不再暗中
## 攒经验, 战车只能靠吃到 ⭐ STAR 道具升级 (player.gd::apply_powerup()),
## 一颗星 = 一级, 不设门槛。amount > 1 用于一次性补发多级 (调试菜单、
## Factory 一类"翻倍奖励"如果以后想按等级发放的话)。
func add_level(amount: int = 1) -> void:
	for i in range(amount):
		level += 1
		_auto_level_bonus()
		leveled_up.emit(level)
	stats_changed.emit()

## 攻击力的成长节奏。
##
## **这里原来写着"一幕之内玩家大约涨 22-24 级"—— 那个数字贴错了标签, 差 11 倍。**
## 22-26 级是**整场 12 幕战役**走完的量, 不是一幕。实测口径: 升级的唯一入口是
## 吃 ⭐ (见 add_level() 头上的注释), 而 ⭐ 的真实产出是每幕约 1.4 (act 1) 到
## 2.5 (act 12) 颗 —— 整场约 25 颗, 也就是约 25 级。所以 5 级 +1 意味着
## **整场战役 +5 伤害**, 幕均不到半点。
##
## 下面 ATK_FIRST_POINT_LEVEL 和 _auto_level_bonus() 里的长注释同样按这个口径读。
##
## 硬核化调整: 4 -> 5。依据是 test_enemy_balance_curve.gd 测的秒杀率 45-48%
## 对门禁上限 60% 还有余量 —— 那次测量本身是有效的 (该测试扫的 floor 0..14
## 正是整场战役的难度轴), 只是当时也被称作"一幕"。ATK_FIRST_POINT_LEVEL 不动
## (第一点仍在 3 级, 保住"floor 1 杂兵还是一发一个"这条底线), 只是后续每一点
## 隔得更远, 让 ARMOR/BATTLESHIP/TRAIN_BOSS 这套血量分层在后期认得更久。
##
## 注意该测试换成真实的 ⭐ 产出模型之后 (原来是一个 XP 池, 而经验条已经删了),
## 中段秒杀率比当初测的更低: floor 3 是 8%, floor 7 精英层是 0%。归零那条
## 底线现在只靠"廉价兵还有剩"撑着, 再往硬调之前先复核。
const ATK_LEVELS_PER_POINT := 5

## 第一点攻击力落在哪一级。**不是 4 而是 3**, 而且这一格错位是必需的。
##
## 直接写 level % 4 == 0 的话第一点要等到 4 级 —— 于是开局那几层的伤害还是 1,
## 而敌人血量已经吃了楼层缩放
## (BASIC 的 1 血 ceil(1 x 1.08) = 2), 结果是**整个 floor 1 一发都秒不掉**,
## 秒杀率从 floor 0 的 100% 直接掉到 0%。坦克大战的底子就是"杂兵一发一个",
## 开局第二层就把这条收走, 玩家读到的不是"变难了"而是"我的炮变哑了"。
##
## 从 3 级开始, 拿到的点数和 level % 4 完全一样 (3/7/11/15/19/23 —— 按现在的
## ATK_LEVELS_PER_POINT=5 则是 3/8/13/18/23), 只是把第一点提前一级填上这个坑。
## 这几个等级按真实节奏分别落在第 2/4/7/9/12 幕附近。
const ATK_FIRST_POINT_LEVEL := 3

func _auto_level_bonus() -> void:
	# 攻击力每 ATK_LEVELS_PER_POINT 级 +1, 不是每级。
	#
	# get_atk_damage() 是 1 + atk_bonus, 所以以前"每级 +1"等于**伤害 == 等级**,
	# 线性无上限。(下面这段实测里的"一幕涨 22 级"同样是贴错的标签, 那是整场
	# 战役的量 —— 见 ATK_LEVELS_PER_POINT 头上的订正; 结论不受影响, 因为
	# test_enemy_balance_curve.gd 扫的 floor 0..14 本来就是整场的难度轴。)
	# 实测涨 22 级, 而敌人血量在同一段里恒定 ——
	# 从 floor 4 起玩家一发秒掉场上 100% 的敌人, 包括 14 血的 TRAIN_BOSS 和
	# 10 血的最终 BOSS。ARMOR(4)/BATTLESHIP(6)/TRAIN_BOSS(14) 这套血量分层
	# 整个维度报废, 肉盾单位没有肉盾, 只剩外形不同 —— 连"靠敌人种类而非数值
	# 堆砌来提难度"这个设计意图本身也被削平了。
	#
	# 升级带来的其它收益 (射速/血量/回复/移速/建造) 保持原节奏不动: 问题出在
	# 伤害这一项独自线性碾过了所有敌人血量, 不是升级给得太多。
	#
	# 从 3 级 +1 收到 4 级 +1, 是刻意往硬核那一档挪。改成每 3 级之后秒杀率
	# 确实从"全场 100%"下来了, 但实测**相对**强度仍然全程持平: 玩家伤害一幕
	# 之内 1 -> 8, 敌人均血同期 1.00 -> 8.17, 两条线并排跑, "打一只要几发"
	# 从 floor 1 到 floor 14 纹丝不动 (STK 1.37 -> 1.27, 甚至微降)。
	#
	# 先试的是抬敌人血量的楼层斜率 (0.08 -> 0.11), 没用: 血量只涨 2.5 倍而
	# 伤害涨 8 倍, 差着一个数量级, 那点余量追不上; 而且"给所有敌人偷偷加血"
	# 正是这个项目明确否掉的那条难度路线 (难度靠敌人种类, 见
	# main.gd::ENEMY_MIN_FLOOR 的按机制分层解锁)。刹车踩在这里才对 ——
	# 收慢的是玩家的伤害成长, 而不是给敌人塞隐藏数值; 效果是 ARMOR(4) /
	# BATTLESHIP(6) / TRAIN_BOSS(14) 这套本来就存在的血量分层到了后期还认得出。
	if level >= ATK_FIRST_POINT_LEVEL and (level - ATK_FIRST_POINT_LEVEL) % ATK_LEVELS_PER_POINT == 0:
		atk_bonus += 1
	if level % 2 == 0:
		fire_rate_lvl += 1
	if level % 3 == 0:
		max_hp_lvl += 1
	if level % 4 == 0:
		regen_lvl += 1
	if level % 2 == 1:
		speed_lvl += 1
		builder_lvl += 1
	stats_changed.emit()

func get_player_max_hp(player_id: int = 1) -> int:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var hp = 1 + max_hp_lvl
	if branch == "heavy":
		hp += HEAVY_HP_BONUS[tier]
	elif branch == "train":
		hp += TRAIN_HP_BONUS[tier]
	elif branch == "counter":
		hp += COUNTER_HP_BONUS[tier]
	elif branch == "trench":
		hp += TRENCH_HP_BONUS[tier]
	hp += int(round(get_perk_value("titan_plating", 2.0, player_id)))
	return hp

func get_speed_multiplier(player_id: int = 1) -> float:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var mult = 1.0 + float(speed_lvl) * 0.04
	if branch == "speed":
		mult += SPEED_MOVE_BONUS[tier]
	elif branch == "heavy":
		mult -= 0.10 # 重装型较重，稍显沉稳
	mult += get_perk_value("nitro_booster", 0.18, player_id)
	return maxf(0.5, mult)

func get_fire_cooldown_mult(player_id: int = 1) -> float:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var rate = 1.0 + float(fire_rate_lvl) * 0.10
	if branch == "speed":
		rate += SPEED_FIRE_BONUS[tier] # 极高射速
	elif branch == "heavy":
		rate *= 0.85 # 重型巨炮单发威猛，装填稍慢
	elif branch == "counter":
		rate *= 0.50 # 反击型攻速极慢，主要依赖时机弹反破敌
	elif branch == "trench":
		# 曾经是 x1.25 (比 default 更快), 和它已经免费拿到的范围伤害 + 自动
		# 切弹叠在一起, 实测 12 级单体 DPS 是 default 的 152%(tier1)/229%(tier2)
		# —— 命中一个目标都用不到就打平了 default 的全部输出, 范围/切弹反而
		# 变成纯赠品。姊妹机制 heavy 走的是同一条"AoE 武器该更慢"的路子 (見
		# 上面 x0.85), 这里对齐它, 而不是自成一档。
		rate *= 0.85 # 壕沟切割是范围武器, 该用装填换范围, 不该比单体武器还快
	rate += get_perk_value("rapid_loader", 0.30, player_id)
	return 1.0 / rate

const BASE_FIRE_COOLDOWN := 0.65
const FIRE_CD_FLOOR_SPEED := 0.18
const FIRE_CD_FLOOR_OTHER := 0.32
# 曾经写着 0.95/0.38, 和 player.gd::_fire() 里实际生效的 1.10/0.40 对不上 ——
# 那边原来是重写的字面量, 不是引用这两个常量。现在 player.gd 直接引用这两个
# 常量了 (单一数据源), 这里改成和已经在跑的那份行为一致, 而不是反过来把
# 实际手感悄悄改掉。
const FIRE_CD_FLOOR_COUNTER := 1.10
const FIRE_CD_FLOOR_TRENCH := 0.40

## 再加 extra_rate 点射速之后, 冷却是不是仍然贴在地板上 (也就是这份强化
## 完全没有效果)。extra_rate 默认 0 = 问"现在是不是已经到底了"。
func is_fire_rate_capped(player_id: int = 1, extra_rate: float = 0.0) -> bool:
	var branch = get_branch(player_id)
	var floor_v = FIRE_CD_FLOOR_SPEED if branch == "speed" else (FIRE_CD_FLOOR_TRENCH if branch == "trench" else (FIRE_CD_FLOOR_COUNTER if branch == "counter" else FIRE_CD_FLOOR_OTHER))
	# get_fire_cooldown_mult 返回的是 1/rate, 所以先还原成 rate 再加。
	var rate = 1.0 / maxf(0.0001, get_fire_cooldown_mult(player_id))
	var cd_now = BASE_FIRE_COOLDOWN / maxf(0.0001, rate)
	var cd_after = BASE_FIRE_COOLDOWN / maxf(0.0001, rate + extra_rate)
	# 加之前就已经到底, 而且加完还是到底 -> 这份强化一点用都没有
	return cd_now <= floor_v and cd_after <= floor_v

func get_atk_damage(player_id: int = 1) -> int:
	var branch = get_branch(player_id)
	var tier = get_branch_tier(player_id)
	var dmg = 1 + atk_bonus
	if branch == "heavy":
		dmg += HEAVY_DMG_BONUS[tier]
	elif branch == "train":
		dmg += TRAIN_DMG_BONUS[tier]
	elif branch == "counter":
		dmg += COUNTER_DMG_BONUS[tier]
	elif branch == "trench":
		dmg += TRENCH_DMG_BONUS[tier]
	dmg += int(round(get_perk_value("high_explosive", 2.0, player_id)))
	return dmg

func get_regen_rate(player_id: int = 1) -> float:
	var rate = float(regen_lvl) * 0.25
	rate += get_perk_value("nano_repair", 0.50, player_id)
	return rate

func get_building_hp_mult() -> float:
	return 1.0 + float(builder_lvl) * 0.25

