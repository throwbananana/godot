class_name BranchBlueprints
extends RefCounted

## 进阶流派的**解锁图纸** —— 这一局里，玩家必须先拿到对应的改装图纸，
## 升级界面才会出现那条分支。
##
## === 为什么改成解锁制 ===
##
## 原来第一次升级就无条件摆出全部 5 条分支, 于是每个玩家在第一次升级那一刻
## 就永远离开了经典线。CLAUDE.md 早就记着这件事的后果:
##
##     "Beware the 'star tier' trap: player_tier only has an observable effect
##      on the 'default' branch, and every player picks a branch at their
##      first level-up."
##
## 也就是说经典线那条 0->3 的星级成长 (BASIC -> SCOUT+ -> TWIN-CANNON ->
## PLASMA DREADNOUGHT: 弹速 480->660、双管变三管、等离子破钢) 是**实装了但
## 没人见过**的内容 —— 所有 ⭐ 奖励都被 grant_star_tier_reward() 改道成了
## +1 攻击。把分支变成需要解锁的东西, 等于把这条线还给玩家当默认路线。
##
## === 一张表, 四个消费方 ===
##
## 图纸要同时出现在商店货架、宝箱掉落、Boss 掉落和升级界面。这四处各写一份
## 名字/图标/描述, 就是这个仓库反复吃亏的那种重复 (见 CLAUDE.md 里 shop 的
## `_upgrade_pool()` 一处定义, 以及"两份手写字段表迟早会漂"那几段)。
## 所以全部集中在这里, 那四处只认 branch id。

## branch id -> 图纸信息。
##
## branch id 必须和 rpg_manager.gd 的 BRANCHES 对得上 —— 那边是分支的权威
## 名单, 这里只是给它套一层解锁条件。多出或少一条都会被
## tools/test_branch_unlock.gd 抓住。
const BLUEPRINTS := {
	"speed": {
		"item_id": "blueprint_speed",
		"name": "轻量化底盘图纸",
		"icon": "speed",
		"desc": "解锁【迅捷斥候型】进阶路线",
	},
	"heavy": {
		"item_id": "blueprint_heavy",
		"name": "反应装甲图纸",
		"icon": "heavy",
		"desc": "解锁【重装泰坦型】进阶路线",
	},
	"train": {
		"item_id": "blueprint_train",
		"name": "铁道车钩图纸",
		"icon": "train",
		"desc": "解锁【装甲列车型】进阶路线",
	},
	"counter": {
		"item_id": "blueprint_counter",
		"name": "能量反冲盾图纸",
		"icon": "counter",
		"desc": "解锁【绝地反击型】进阶路线",
	},
	"trench": {
		"item_id": "blueprint_trench",
		"name": "高频环刃图纸",
		"icon": "trench",
		"desc": "解锁【壕沟先锋型】进阶路线",
	},
}


static func all_branches() -> Array:
	return BLUEPRINTS.keys()


static func has(branch: String) -> bool:
	return BLUEPRINTS.has(branch)


static func info(branch: String) -> Dictionary:
	return BLUEPRINTS.get(branch, {})


static func display_name(branch: String) -> String:
	return str(BLUEPRINTS.get(branch, {}).get("name", branch))


## item_id -> branch, 给商店那边用 (货架上存的是 item id)。
static func branch_of_item(item_id: String) -> String:
	for b in BLUEPRINTS:
		if BLUEPRINTS[b]["item_id"] == item_id:
			return b
	return ""


## 这一局还没解锁的分支。掉落方按这个列表抽, 于是**永远不会掉到重复的图纸** ——
## 一个已经解锁的分支再掉一次, 玩家拿到的是彻头彻尾的空气, 而宝箱/Boss 是
## 稀缺资源, 空军一次的挫败感远大于少给一点。
static func locked_branches() -> Array:
	var out: Array = []
	for b in BLUEPRINTS:
		if not GameState.is_branch_unlocked(b):
			out.append(b)
	return out


## 随机抽一张还没拿到的图纸并解锁; 返回 branch id, 全解锁了就返回 ""。
##
## **用 randi() 是安全的**, 和 explosion.gd 那条"必须用静态计数器"的规矩不冲突:
## 那条规矩防的是"每帧都会发生、且发生次数两端不一致"的调用挪动全局 RNG 流。
## 开宝箱/杀 Boss 都是主机权威的一次性事件, 客户端根本不跑这条路径 (战利品
## 走 campaign 字典同步), 而每日挑战的地图与刷怪在开箱之前就已经定好了。
static func roll_unlock() -> String:
	var pool := locked_branches()
	if pool.is_empty():
		return ""
	var picked: String = pool[randi() % pool.size()]
	GameState.unlock_branch(picked)
	return picked
