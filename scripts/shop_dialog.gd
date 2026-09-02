class_name ShopDialog
extends PanelContainer

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const RPGManager = preload("res://scripts/rpg_manager.gd")

signal closed

@onready var gold_label: Label = $VBox/Header/HBox/GoldLabel
@onready var diorama_rect: TextureRect = $VBox/Header/DioramaRect
@onready var items_grid: GridContainer = $VBox/Scroll/ItemsGrid
@onready var btn_reroll: Button = $VBox/Actions/RerollButton
@onready var btn_leave: Button = $VBox/Actions/LeaveButton
@onready var toast_label: Label = $VBox/ToastLabel

var current_shop_items: Array[Dictionary] = []

## 刷新费用: 每次进店从 REROLL_BASE 起, 每刷一次涨 REROLL_STEP。
##
## 以前是固定 20 G 且可以无限刷。货架的设计是"11 种强化里随机上架 6 种",
## 也就是说"这次没抽到想要的"本该是一个真实的取舍。但实测中后期一层的金币
## 收入就有 600-680 G —— 等于一层的收入够刷三十次, 那条随机上架的约束就
## 完全是装饰: 想要什么刷到出为止即可。
##
## 递增之后, 刷新变成"要不要为了指定的一件东西, 放弃买两三件别的", 这才是
## 原本想要的取舍。基数保持 20 不变, 所以第一次刷新的手感和以前一样。
const REROLL_BASE: int = 20
const REROLL_STEP: int = 25
var reroll_cost: int = REROLL_BASE
var reroll_count: int = 0

## Builder Controller structures used to cost battle gold at the moment you
## placed them; they're shop-only stock now (see GameState.structure_inventory
## + builder_controller.gd). Always shown in full every shop visit (not
## shuffled/limited to 6 like the stat-upgrade pool below) -- these are core
## tactical tools, not flavor, so restocking them needs to be reliable rather
## than an RNG roll. Costs carried over unchanged from the old per-placement
## prices. ids match builder_controller.gd::structure_ids exactly.
const BUILDING_ITEMS: Array[Dictionary] = [
	{"id": "turret", "name": "防御炮塔补给 (Defense Turret)", "desc": "购入 1 座防御炮塔库存，战斗中可用热键放置。", "cost": 80, "icon": "res://assets/sprites/buildings/turret_gun.png", "category": "BUILD"},
	{"id": "fortified_wall", "name": "强化墙体补给 (Fortified Wall)", "desc": "购入 1 面强化墙体库存，战斗中可用热键放置。", "cost": 25, "icon": "res://assets/sprites/buildings/fortified_wall.png", "category": "BUILD"},
	{"id": "electric_wall", "name": "高压电墙补给 (Electric Wall)", "desc": "购入 1 座高压电墙库存，战斗中可用热键放置。", "cost": 50, "icon": "res://assets/sprites/tiles/tile_electric_wall_f0.png", "category": "BUILD"},
	{"id": "street_lamp", "name": "照明路灯补给 (Street Lamp)", "desc": "购入 1 座照明路灯库存，战斗中可用热键放置。", "cost": 45, "icon": "res://assets/sprites/buildings/street_lamp.png", "category": "BUILD"},
	{"id": "oil_barrel", "name": "燃油桶补给 (Oil Barrel)", "desc": "购入 1 个燃油桶库存，战斗中可用热键放置。", "cost": 55, "icon": "res://assets/sprites/buildings/oil_barrel.png", "category": "BUILD"},
	{"id": "landmine", "name": "反坦克地雷补给 (EMP Landmine)", "desc": "购入 1 枚反坦克地雷库存，战斗中可用热键放置。", "cost": 40, "icon": "res://assets/sprites/buildings/landmine.png", "category": "BUILD"},
	{"id": "repair_station", "name": "维修站补给 (Repair Beacon)", "desc": "购入 1 座维修站库存，战斗中可用热键放置。", "cost": 120, "icon": "res://assets/sprites/buildings/repair_station.png", "category": "BUILD"},
	{"id": "shield_station", "name": "护盾充能站补给 (Shield Recharger)", "desc": "购入 1 座护盾充能站库存，战斗中可用热键放置。", "cost": 100, "icon": "res://assets/sprites/buildings/shield_station.png", "category": "BUILD"},
	{"id": "wind_blower", "name": "风力涡轮补给 (Wind Turbine)", "desc": "购入 1 座风力涡轮库存，战斗中可用热键放置。", "cost": 70, "icon": "res://assets/sprites/buildings/wind_blower.png", "category": "BUILD"},
	{"id": "missile_strike", "name": "战术导弹补给 (Missile Strike)", "desc": "购入 1 次战术导弹打击库存，战斗中可用热键呼叫。", "cost": 90, "icon": "res://assets/sprites/powerups/missile_strike.png", "category": "BUILD"},
	{"id": "timed_bomb", "name": "定时炸弹补给 (Timed Bomb)", "desc": "购入 1 枚定时炸弹库存，战斗中可用热键放置。", "cost": 60, "icon": "res://assets/sprites/buildings/prop_timed_bomb.png", "category": "BUILD"},
	{"id": "roller_wall", "name": "滑轮防线补给 (Roller Wall)", "desc": "购入 1 面滑轮防线墙体。受击时会向受力方向滚动推移一格，可用来顶撞碾压敌人。", "cost": 35, "icon": "res://assets/sprites/buildings/roller_wall.png", "category": "BUILD"},
	{"id": "pipe_conduit", "name": "导流管道补给 (Conduit Pipe)", "desc": "购入 1 个导流管道。子弹从入口打入会改变方向射出，在非入口方向受击可被破坏。", "cost": 30, "icon": "res://assets/sprites/buildings/pipe_conduit.png", "category": "BUILD"},
	{"id": "bunker", "name": "战术防御堡垒 (Tactical Bunker)", "desc": "购入 1 座防御堡垒。坦克可躲在后方射穿射击孔出膛，正面格挡阻挡低阶炮弹，从左右侧面受击可被破坏。", "cost": 45, "icon": "res://assets/sprites/buildings/bunker.png", "category": "BUILD"},
	{"id": "wooden_wall", "name": "便携木墙补给 (Wooden Wall)", "desc": "购入 1 面可移动木制防线。具有韧性且可被推移，撞击敌军或障碍物时造成接触破坏，承受多次撞击与攻击后碎裂。", "cost": 30, "icon": "res://assets/sprites/buildings/wooden_wall.png", "category": "BUILD"},
]

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(self, Color(0.14, 0.12, 0.16, 0.98), 16)
	
	var reroll_tex = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_reroll.png")
	var leave_tex = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_leave.png")

	if reroll_tex:
		var sb_r = StyleBoxTexture.new()
		sb_r.texture = reroll_tex
		sb_r.texture_margin_left = 22
		sb_r.texture_margin_right = 22
		sb_r.texture_margin_top = 14
		sb_r.texture_margin_bottom = 18
		sb_r.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb_r.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb_r.content_margin_left = 14
		sb_r.content_margin_right = 14
		sb_r.content_margin_top = 8
		sb_r.content_margin_bottom = 10
		btn_reroll.add_theme_stylebox_override("normal", sb_r)
		btn_reroll.add_theme_stylebox_override("disabled", sb_r)
		var sb_rh = sb_r.duplicate() as StyleBoxTexture
		sb_rh.modulate_color = Color(1.15, 1.15, 1.05)
		btn_reroll.add_theme_stylebox_override("hover", sb_rh)
		btn_reroll.add_theme_stylebox_override("focus", sb_rh)
	else:
		UIThemeHelper.apply_icon_button(btn_reroll, "res://assets/sprites/ui/ui_icon_shop_refresh.png", Vector2(20, 20))

	if leave_tex:
		var sb_l = StyleBoxTexture.new()
		sb_l.texture = leave_tex
		sb_l.texture_margin_left = 22
		sb_l.texture_margin_right = 22
		sb_l.texture_margin_top = 14
		sb_l.texture_margin_bottom = 18
		sb_l.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb_l.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb_l.content_margin_left = 14
		sb_l.content_margin_right = 14
		sb_l.content_margin_top = 8
		sb_l.content_margin_bottom = 10
		btn_leave.add_theme_stylebox_override("normal", sb_l)
		btn_leave.add_theme_stylebox_override("disabled", sb_l)
		var sb_lh = sb_l.duplicate() as StyleBoxTexture
		sb_lh.modulate_color = Color(1.15, 1.15, 1.05)
		btn_leave.add_theme_stylebox_override("hover", sb_lh)
		btn_leave.add_theme_stylebox_override("focus", sb_lh)
	else:
		UIThemeHelper.apply_icon_button(btn_leave, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(20, 20))

	btn_reroll.pressed.connect(_on_reroll_pressed)
	btn_leave.pressed.connect(_on_leave_pressed)

	var d_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_banner_shop_title.png")
	if not d_tex:
		d_tex = TextureHelper.get_tex("res://assets/sprites/ui/diorama_shop.png")
	if d_tex and diorama_rect:
		diorama_rect.texture = d_tex

func setup_shop() -> void:
	visible = true
	# 每次进店重置刷新费用 —— 涨价只在**同一次**进店内累积, 不跨商店惩罚。
	reroll_count = 0
	reroll_cost = REROLL_BASE
	_generate_shop_inventory()
	_update_ui()

	# 让手柄/键盘一进来就有焦点; 没有这一句菜单只能用鼠标。
	UIThemeHelper.focus_first(self)

func _update_ui() -> void:
	gold_label.text = "YOUR GOLD: %d G" % GameState.gold
	btn_reroll.text = "刷新货架 (Reroll %dG)" % reroll_cost
	btn_reroll.disabled = (GameState.gold < reroll_cost)
	_render_item_cards()
	# _render_item_cards() 把货架卡片(包括当前抓着焦点的那张)全部 queue_free
	# 再重建, 手柄/键盘的焦点持有者被删掉之后 gui_get_focus_owner() 变 null,
	# 方向键/摇杆再也无法导航, 只能切回鼠标。买完一件东西或点刷新货架都会走
	# 到这里, 重建后必须重新指定焦点。
	UIThemeHelper.focus_first(self)

func _generate_shop_inventory() -> void:
	current_shop_items = build_inventory()


## 货架生成。static 且不碰任何 UI —— 以撒式的物理底座
## (scripts/shop_stand.gd) 和这个对话框要用**同一份**货源与定价。
## 抄一份到底座那边的话, 两张表会在下一次调价时分叉, 而平衡探针
## (tools/probe_balance_report.gd) 只盯得住其中一份。
static func build_inventory() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all_items: Array[Dictionary] = _upgrade_pool()
	all_items.shuffle()
	for i in range(min(6, all_items.size())):
		var it = all_items[i].duplicate()
		it["cost"] = _price_for(int(it["cost"]))
		it["sold_out"] = false
		out.append(it)

	# Building supplies are appended in full, every visit -- not part of the
	# shuffle-and-pick-6 above.
	for b in BUILDING_ITEMS:
		var it2 = b.duplicate()
		it2["cost"] = _price_for(int(it2["cost"]))
		it2["sold_out"] = false
		out.append(it2)
	return out


## 按 id 取一件商品的完整定义 (含图标/描述/**基础**价, 未经楼层缩放)。
##
## 房间里的货架只把 **id 和成交价** 存进存档 (见 main.gd::_ensure_shop_stock),
## 图标和长描述每次从这里现查 —— 把整个商品字典序列化进 JSON 会让存档
## 肿上好几 KB, 而且改一句描述文案就会和老存档对不上。
static func item_by_id(item_id: String) -> Dictionary:
	for b in BUILDING_ITEMS:
		if str(b["id"]) == item_id:
			return b.duplicate()
	for it in _upgrade_pool():
		if str(it["id"]) == item_id:
			return it.duplicate()
	return {}


## 非建材的强化池, 11 种全在。这里是它们的**唯一**定义 ——
## build_inventory() 从这里抽 6 种上架, item_by_id() 从这里回查。
static func _upgrade_pool() -> Array[Dictionary]:
	return [
		{
			"id": "star_tier",
			"name": "战车升阶模块 (Star Upgrade)",
			"desc": "提升战车阶级 (Tier Up)，增强火力与射击发数",
			"cost": 95,
			"icon": "res://assets/sprites/powerups/star.png",
			"category": "WEAPON"
		},
		{
			"id": "heavy_armor",
			"name": "强化装甲钢板 (Armor Plating)",
			"desc": "+1 战车最大装甲上限 (Max HP +1)",
			"cost": 65,
			"icon": "res://assets/sprites/powerups/helmet.png",
			"category": "HULL"
		},
		{
			"id": "autoloader",
			"name": "自动装填机构 (Autoloader)",
			"desc": "+10% 战车基础装填速度 (Fire Rate +10%)",
			"cost": 70,
			"icon": "res://assets/sprites/ui/badge_laser.png",
			"category": "FIREPOWER"
		},
		{
			"id": "turbo_engine",
			"name": "涡轮增压引擎 (Turbo Engine)",
			"desc": "+6% 战车最高机动巡航航速 (Speed +6%)",
			"cost": 55,
			"icon": "res://assets/sprites/powerups/clock.png",
			"category": "MOBILITY"
		},
		{
			"id": "extra_life",
			"name": "备用坦克增援 (Reserve Tank)",
			"desc": "+1 出战备用坦克生命 (Extra Life +1)",
			"cost": 85,
			"icon": "res://assets/sprites/powerups/life.png",
			"category": "SUPPORT"
		},
		{
			"id": "steel_shovel",
			"name": "基地全铁化加固 (Steel Reinforce)",
			"desc": "+1 基地防线工程学等级 (Base Defense Level +1)",
			"cost": 50,
			"icon": "res://assets/sprites/powerups/shovel.png",
			"category": "BASE"
		},
		{
			"id": "plasma_mod",
			"name": "穿甲高爆重弹 (Armor Piercer)",
			"desc": "+1 永久主炮基础杀伤力 (ATK Bonus +1)",
			"cost": 80,
			"icon": "res://assets/sprites/effects/bullet_plasma.png",
			"category": "WEAPON"
		},
		{
			"id": "landmine_crate",
			"name": "战术反坦克地雷包 (Mine Crate)",
			"desc": "紧急空投 2 枚反坦克地雷库存，战斗中可用热键放置 (原本的经验值奖励已改为地雷库存 -- 升级只能靠吃 STAR 道具)",
			"cost": 45,
			"icon": "res://assets/sprites/powerups/landmine_prop.png",
			"category": "TACTICAL"
		},
		{
			"id": "ricochet_rounds",
			"name": "反射炮弹 (Ricochet Rounds)",
			"desc": "炮弹命中障碍后不会消失，而是随机弹向新方向继续飞行（可叠加购买，最多3层，层数=可反弹次数）。高风险：反弹后的炮弹会失去友军免疫，可能反过来打中你自己！",
			"cost": 110,
			"icon": "res://assets/sprites/powerups/ricochet_rounds.png",
			"category": "RISK"
		},
		{
			"id": "amphibious_hull",
			"name": "两栖化改造 (Amphibious Hull)",
			"desc": "战车加装水陆两用推进系统，终于可以下水通行！代价：改装后底盘变重，陆地机动速度永久 -50%（下水时无此惩罚）。",
			"cost": 90,
			"icon": "res://assets/sprites/powerups/amphibious_hull.png",
			"category": "RISK"
		},
		{
			"id": "armor_piercing_rounds",
			"name": "贯穿装甲弹 (Armor-Piercing Rounds)",
			"desc": "炮弹可直接洞穿一切可摧毁的墙体持续飞行，不再被击中的第一面墙拦下。高风险：弹芯经过特殊改造后无法再拦截敌方炮弹，来袭的炮弹会直接穿过你的子弹继续飞向你！",
			"cost": 120,
			"icon": "res://assets/sprites/powerups/armor_piercing_rounds.png",
			"category": "RISK"
		}
	]


## 售价随楼层缩放。表里写死的价格是"第 1 层的价格"。
##
## 收入侧是一路涨的: 敌人的 gold_value 从单只均 18.5 涨到 147 (换的敌人种类更贵,
## 再乘楼层缩放), 于是常规战一层的期望金币从 89 G 涨到 704 G。售价不跟着涨的话,
## 金币在中后期就不再是一个需要权衡的资源 —— 想要什么买什么。
##
## 斜率 0.12 是量出来的, 不是拍的。配合 GameState.MIN_SHOPS_PER_ACT 的路线保底,
## 实测 (tools/probe_balance_report.gd, 400 局最优路线) 全幕盈余倍率
## = 收入 / 整幕能花掉的上限:
##
##     斜率 0.08 + 保底 1 个商店   均值 1.07  中位 0.87  p90 1.94  最大 6.37
##     斜率 0.12 + 保底 3 个商店   均值 0.65  中位 0.62  p90 1.04
##
## 也就是说典型的一局能买下货架上大约六成的东西 —— 每进一次店都得取舍, 而不是
## 从头买到尾; 同时"钱多到花不掉"的那条长尾没了。这是刻意偏硬核的一档:
## 0.08 那一档下中位数 0.87 意味着典型局几乎能全买, 商店等于自动发牌。
##
## 注意 0.12 只在中后期咬人 (floor 0 原价, floor 14 是 2.68 倍), 前几层的手感
## 完全没动 —— 早期本来就是教学段, 卡钱只会让人以为系统坏了。
const PRICE_FLOOR_SLOPE := 0.12

static func _price_for(base_cost: int) -> int:
	var floor_mult := 1.0 + float(GameState.current_floor) * PRICE_FLOOR_SLOPE
	return int(round(float(base_cost) * floor_mult))

## 商店卖的是"给队伍"的东西, 不是"给 1 号位"的东西。
##
## 大多数商品写的是 GameState 上的团队字段 (max_hp_lvl / fire_rate_lvl /
## speed_lvl / builder_lvl / atk_bonus), 两个玩家天然共享。但有
## 三样不是: 升阶模块 (player_tier 与 p2_tier 分开), 以及三个 perk
## (unlocked_perks 与 p2_unlocked_perks 分开)。这几样以前一律硬编码
## player_id = 1, 于是**双人模式下 2P 永远拿不到**。
##
## 备用生命曾经也在这份名单里 (player_lives 与 p2_lives 分开), 双人战役改成
## 共享生命池之后, p2_lives 整个字段被删掉了, "lives" 天然变回团队字段 ——
## 不再需要 player_count == 2 时额外发一份。见 game_state.gd::p2_branch
## 前面的注释和 main.gd::_lives_shared()。
##
## 同一个项目里的 event_dialog.gd 对完全相同的奖励是发两份的
## (_grant_tier_up / _grant_perk 都判 player_count == 2) —— 也就是说双份才是
## 既定行为, 商店这边是漏了, 不是另一种设计。
const PER_PLAYER_PERKS := ["ricochet_rounds", "amphibious_hull", "armor_piercing_rounds"]


## 这一局有几个玩家要拿这份奖励。
static func _reward_targets() -> Array:
	return [1, 2] if GameState.player_count == 2 else [1]


static func can_buy_item(item_id: String) -> bool:
	if item_id == "star_tier":
		# Only default-branch players actually cap at tier 3 (multi-shot/plasma
		# progression). Once a branch is picked, this item redirects to a
		# permanent +1 ATK (GameState.grant_star_tier_reward) which has no
		# such cap -- same as the shop's other flat stat items.
		#
		# 双人时只要还有一个人吃得下就该能买 —— 否则 1P 顶了 tier 3 会连带
		# 把 2P 的升阶也锁死。
		for pid in _reward_targets():
			var branch = GameState.tank_branch if pid == 1 else GameState.p2_branch
			var tier = GameState.player_tier if pid == 1 else GameState.p2_tier
			if branch != "default" or tier < 3:
				return true
		return false
	if item_id in PER_PLAYER_PERKS:
		# These are perks (GameState.unlocked_perks), not flat stat fields --
		# unlike the items above, repeat purchases across shop visits are
		# capped by GameState.PERK_MAX_STACKS.
		var cap = GameState.max_stacks_for_perk(item_id)
		for pid in _reward_targets():
			var perks = GameState.unlocked_perks if pid == 1 else GameState.p2_unlocked_perks
			if int(perks.get(item_id, 0)) < cap:
				return true
		return false
	if item_id == "autoloader":
		# 射速强化在冷却撞到地板之后是**纯白给** —— player.gd::_fire() 把冷却
		# 夹在 0.18/0.32 秒, 到底之后再涨射速一点效果都没有, 而卡片上照样写着
		# "+10% 装填速度"。这和上面那两条上限检查是同一件事: 不卖零。
		# 详见 rpg_manager.gd::is_fire_rate_capped()。
		for pid in _reward_targets():
			if not _fire_rate_capped_for(pid, 0.10):
				return true
		return false
	return true


## 商店跑在 spire_map.tscn 里, 没有活着的 RPGManager 可用。这里临时造一个并
## 从 GameState 同步 —— 不在这边复刻射速公式, 复刻的必然和 rpg_manager 发散。
static func _fire_rate_capped_for(player_id: int, extra_rate: float) -> bool:
	var m := RPGManager.new()
	m.sync_from_game_state()
	return m.is_fire_rate_capped(player_id, extra_rate)

static func _grant_perk_to_team(perk_id: String) -> void:
	for pid in _reward_targets():
		GameState.grant_perk_stack(perk_id, pid)


## 执行一笔购买。**不扣金币**(调用方负责), 也不碰 UI —— 返回一句提示文案,
## 由调用方决定是弹对话框 toast 还是在战场 HUD 上显示。
## 对话框和以撒式底座共用这一份发放逻辑。
static func apply_item_purchase(item_id: String) -> String:
	for b in BUILDING_ITEMS:
		if b["id"] == item_id:
			GameState.add_structure_stock(item_id, 1)
			return "%s 已入库！当前库存 x%d，可在热键栏放置。" % [b["name"], GameState.get_structure_stock(item_id)]

	match item_id:
		"star_tier":
			var was_default = (GameState.tank_branch == "default")
			for pid in _reward_targets():
				GameState.grant_star_tier_reward(pid)
			if was_default:
				return "战车成功升级至阶级 %d !" % (GameState.player_tier + 1)
			else:
				return "已选定专属流派，武器模块转化为永久攻击力 +1！"
		"heavy_armor":
			GameState.max_hp_lvl += 1
			return "装甲升级！最大生命值 +1"
		"autoloader":
			GameState.fire_rate_lvl += 1
			return "装填速度大幅提升！"
		"turbo_engine":
			GameState.speed_lvl += 1
			return "战车引擎输出功率强化！"
		"extra_life":
			# player_lives 是双人战役下的共享生命池, 买一次就是整个团队 +1,
			# 不需要再单独发一份给 P2。
			GameState.player_lives += 1
			return "呼叫近卫坦克增援，备用生命 +1！"
		"steel_shovel":
			GameState.builder_lvl += 1
			return "基地防御掩体强度大幅提升！"
		"plasma_mod":
			GameState.atk_bonus += 1
			return "主炮口径扩容，攻击力 +1！"
		"landmine_crate":
			# 以前这里发 +50 XP; 升级已经不吃经验条了 (只能吃 STAR, 见
			# rpg_manager.gd::add_level()), 改发跟名字更贴的地雷库存。
			GameState.add_structure_stock("landmine", 2)
			return "获得地雷战术补给，反坦克地雷库存 +2！"
		"ricochet_rounds":
			_grant_perk_to_team("ricochet_rounds")
			var bounces = int(GameState.unlocked_perks.get("ricochet_rounds", 0))
			return "反射炮弹改装完成！当前可反弹 %d 次 —— 小心别被自己的流弹打中！" % bounces
		"amphibious_hull":
			_grant_perk_to_team("amphibious_hull")
			return "两栖化改装完成！可以下水了，但陆地机动力永久 -50%！"
		"armor_piercing_rounds":
			_grant_perk_to_team("armor_piercing_rounds")
			return "贯穿装甲弹装填完毕！可洞穿墙体，但再也无法拦截敌方炮弹！"
	return ""


func _render_item_cards() -> void:
	for child in items_grid.get_children():
		child.queue_free()

	for item in current_shop_items:
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(210, 160)
		UIThemeHelper.apply_clay_panel(card, Color(0.18, 0.15, 0.22, 0.95), 10)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		card.add_child(vbox)

		# Top row: icon + title + tag
		var top_row = HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 6)
		vbox.add_child(top_row)

		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex = TextureHelper.get_tex(item["icon"])
		if tex:
			icon_rect.texture = tex
		top_row.add_child(icon_rect)

		var title_box = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		top_row.add_child(title_box)

		var lbl_title = Label.new()
		lbl_title.text = item["name"]
		lbl_title.add_theme_font_size_override("font_size", 11)
		lbl_title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.45))
		lbl_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_box.add_child(lbl_title)

		var cat_info = UIThemeHelper.get_category_info(str(item.get("category", "")), str(item["id"]))
		var lbl_tag = Label.new()
		lbl_tag.text = cat_info["tag"]
		lbl_tag.add_theme_font_size_override("font_size", 9)
		lbl_tag.add_theme_color_override("font_color", cat_info["color"])
		title_box.add_child(lbl_tag)

		# Description
		var lbl_desc = Label.new()
		lbl_desc.text = item["desc"]
		lbl_desc.add_theme_font_size_override("font_size", 9)
		lbl_desc.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
		lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(lbl_desc)

		# Progress / stock info
		var item_id_str = str(item["id"])
		var stock_info = ""
		if str(item.get("category", "")) == "BUILD":
			stock_info = "当前库存: x%d" % GameState.get_structure_stock(item_id_str)
		elif item_id_str in PER_PLAYER_PERKS:
			stock_info = "已强化: %d/%d 层" % [int(GameState.unlocked_perks.get(item_id_str, 0)), GameState.max_stacks_for_perk(item_id_str)]
		if stock_info != "":
			var lbl_stock = Label.new()
			lbl_stock.text = stock_info
			lbl_stock.add_theme_font_size_override("font_size", 9)
			lbl_stock.add_theme_color_override("font_color", Color(0.55, 0.88, 0.98))
			vbox.add_child(lbl_stock)

		# Bottom Row: Price & Buy Button
		var bot_row = HBoxContainer.new()
		bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(bot_row)

		var btn_buy = Button.new()
		btn_buy.custom_minimum_size = Vector2(180, 32)
		UIThemeHelper.apply_clay_button(btn_buy)

		if item["sold_out"]:
			btn_buy.text = "✓ 已购买 (SOLD OUT)"
			btn_buy.disabled = true
			btn_buy.modulate = Color(0.5, 0.5, 0.5, 0.6)
		else:
			var can_afford = (GameState.gold >= item["cost"])
			var can_buy_cond = can_buy_item(item["id"])
			btn_buy.text = "💰 %d G - 购买" % item["cost"]
			btn_buy.disabled = not (can_afford and can_buy_cond)
			if not can_buy_cond:
				btn_buy.text = "MAX (已达上限)"
			elif not can_afford:
				btn_buy.modulate = Color(1.0, 0.6, 0.6, 0.8)

			var captured_item = item
			btn_buy.pressed.connect(func(): _on_buy_item(captured_item))

		bot_row.add_child(btn_buy)
		items_grid.add_child(card)

func _on_buy_item(item: Dictionary) -> void:
	if GameState.gold < item["cost"]:
		_show_toast("金币不足！(Not Enough Gold)")
		return
	# 上限也要在这里再判一次, 不能只靠 btn_buy.disabled。禁用按钮确实不会发
	# pressed, 所以今天走 UI 点不出问题 —— 但"扣了钱、grant_perk_stack()
	# 返回 false、什么都没给, 还弹一句购买成功"离得只有一个新调用点那么远,
	# 而且真出了也不会报错。
	if not can_buy_item(item["id"]):
		_show_toast("已达上限，无法再购买！")
		return

	GameState.gold -= item["cost"]
	item["sold_out"] = true
	_show_toast(apply_item_purchase(str(item["id"])))
	SoundManager.play_level_up(get_tree())
	_update_ui()

func _on_reroll_pressed() -> void:
	if GameState.gold < reroll_cost:
		_show_toast("金币不足以刷新货架！")
		return

	GameState.gold -= reroll_cost
	reroll_count += 1
	reroll_cost = REROLL_BASE + REROLL_STEP * reroll_count
	SoundManager.play_pickup(get_tree())
	_generate_shop_inventory()
	_update_ui()
	_show_toast("军火商已更换全新货架！(下次刷新 %d G)" % reroll_cost)

func _on_leave_pressed() -> void:
	visible = false
	GameState.save_campaign()
	SoundManager.play_hit_steel(get_tree())
	closed.emit()

func _show_toast(msg: String) -> void:
	if toast_label:
		toast_label.text = msg
		toast_label.modulate.a = 1.0
		var tw = create_tween()
		tw.tween_interval(2.0)
		tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)
