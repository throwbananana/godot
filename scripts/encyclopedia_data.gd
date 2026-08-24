class_name EncyclopediaData
extends RefCounted

## 战术图鉴数据库 (Tactical Compendium Data Registry)
## 包含五大分类: 升级路线(UPGRADES)、坦克战车(TANKS)、道具宝物(ITEMS)、防御建筑(BUILDINGS)、战场地形(TERRAIN)

const CATEGORIES := [
	{"id": "UPGRADES", "name": "🌟 升级路线 (UPGRADES)", "icon": "res://assets/sprites/ui/perk_atk.png"},
	{"id": "TANKS", "name": "🛡️ 坦克战车 (TANKS)", "icon": "res://assets/sprites/tanks/player_tier0_f0.png"},
	{"id": "ITEMS", "name": "⚡ 道具宝物 (ITEMS)", "icon": "res://assets/sprites/powerups/star.png"},
	{"id": "BUILDINGS", "name": "🏗️ 防御建筑 (BUILDINGS)", "icon": "res://assets/sprites/buildings/turret_gun.png"},
	{"id": "TERRAIN", "name": "🌲 战场地形 (TERRAIN)", "icon": "res://assets/sprites/tiles/tile_brick.png"}
]

const ENTRIES: Array[Dictionary] = [
	# =========================================================================
	# 0. 升级路线与专长树 (UPGRADES)
	# =========================================================================
	{
		"id": "tree_classic",
		"category": "UPGRADES",
		"name": "经典主战流派 (Classic Pioneer Tree)",
		"tag": "四阶演进 / 等离子破钢",
		"icon": "res://assets/sprites/tanks/player_tier3_f0.png",
		"stats": {
			"Tier 0 原型战车": "基础单发实弹，机动转向均衡，初始 3 HP",
			"Tier 1 巡逻先锋": "主炮初速提升 30%，装填间隔缩短至 0.45s",
			"Tier 2 双管强击": "双炮塔齐发双发高速重弹，火力输出翻倍",
			"Tier 3 等离子毁灭者": "发射等离子穿甲光束弹，可直接贯穿摧毁坚固钢铁掩体！"
		},
		"desc": "保留最纯正坦克大战血统的经典全能战车演进路线。通过拾取五角星能量或商店升阶模块逐步解锁四阶完整威力。",
		"tactics": "通用性最强的流派。在第 3 阶解锁等离子穿甲弹后，敌方钢墙工事将不再是阻碍，可远距离穿墙轰杀敌方防御核心。"
	},
	{
		"id": "tree_speed",
		"category": "UPGRADES",
		"name": "极速突击流派 (Speed Striker Tree)",
		"tag": "超高移速 / 暴风疾射",
		"icon": "res://assets/sprites/tanks/player_speed_t2_f0.png",
		"stats": {
			"Tier 1 疾风突击型": "基础移速 190 px/s (+52%)，装填缩短至 0.18s 极速连击",
			"Tier 2 暴风闪电型": "极速双发连珠弹幕，高速转弯与绝佳脱困响应",
			"流派核心优势": "无解的跑轰机动与全图资源抢夺控制力"
		},
		"desc": "牺牲部分厚重装甲换取极致机动与近乎无冷却的暴风开火节奏。在开阔地形与多障碍战场中能以极快速度放风筝收割敌人。",
		"tactics": "极度适配【战术跳弹】与【氮气增压】被动。利用超高航速在敌方炮火间隙蛇皮走位，近身打出瞬间爆发后迅速撤出危险区。"
	},
	{
		"id": "tree_heavy",
		"category": "UPGRADES",
		"name": "泰坦重装流派 (Heavy Juggernaut Tree)",
		"tag": "钢铁要塞 / 单发重炮",
		"icon": "res://assets/sprites/tanks/player_heavy_t2_f0.png",
		"stats": {
			"Tier 1 钢铁巨兽": "基础生命 +3 HP，主炮伤害 +1，受击抗性提高",
			"Tier 2 泰坦灭世要塞": "额外 +5 最大生命上限，攻城单发重磅爆破巨炮 (+2 伤害)",
			"流派核心优势": "拥有全游最高的有效血量与正面阵地压制力"
		},
		"desc": "全身覆盖重型复合装甲与大口径滑膛炮的陆战霸主。能顶着敌方的凶猛弹幕正面推进，一发一辆解决敌军硬骨头。",
		"tactics": "与【纳米自愈】、【复合装甲】及【战场维修站】形成终极协同。在狭窄隘口一夫当关，为基地提供不可逾越的正面肉盾壁垒。"
	},
	{
		"id": "tree_train",
		"category": "UPGRADES",
		"name": "装甲列车流派 (Armored Train Tree)",
		"tag": "多节车厢 / 随行火力",
		"icon": "res://assets/sprites/tanks/player_train_loco_t2_f0.png",
		"stats": {
			"Tier 1 战术机车头": "牵引 1 节自动旋转 360° 索敌的炮塔副炮车厢",
			"Tier 2 重型列车长龙": "追加第 2 节长程追踪火箭炮车厢，全屏密集火力打击",
			"流派核心优势": "多角度全自动副炮支援 + 长车身物理阻挡敌方弹道"
		},
		"desc": "化身移动列车战团！车头负责机动与主炮射击，身后的副炮车厢与火箭车厢会自主索敌并向四周倾泻火力，车厢还能为车头挡子弹。",
		"tactics": "行驶时注意蛇形拉扯让车厢甩动，最大化副炮射击覆盖面。后方车厢可充当移动防弹墙，掩护基地或受伤队友。"
	},
	{
		"id": "perk_rapid_loader",
		"category": "UPGRADES",
		"name": "快速装弹系统 (Rapid Loader)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_atk.png",
		"stats": {
			"第 1 层": "主炮开火装填间隔缩短 25%",
			"第 2 层": "装填间隔累计缩减至 42%",
			"第 3 层": "装填间隔累计缩减至 55% (极速连射)"
		},
		"desc": "改进炮膛供弹机构与液压退壳系统，大幅缩短每次射击后的等待冷却，大幅提高 DPS 输出。",
		"tactics": "所有流派均适用的核心输出被动，对单发重炮与多管齐射提升尤为显著。"
	},
	{
		"id": "perk_titan_plating",
		"category": "UPGRADES",
		"name": "泰坦复合装甲 (Titan Plating)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_armor.png",
		"stats": {
			"第 1 层": "战车最大生命值 +2 HP",
			"第 2 层": "最大生命值累计 +3.5 HP",
			"第 3 层": "最大生命值累计 +4.5 HP"
		},
		"desc": "在底盘与炮塔外层焊接多层高密度陶泥与合金复合装甲板，赋予战车抵御多次致命打击的硬度。",
		"tactics": "提升高难度关卡和精英战容错率的关键生存专长。"
	},
	{
		"id": "perk_nitro_booster",
		"category": "UPGRADES",
		"name": "氮气涡轮增压 (Nitro Booster)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_speed.png",
		"stats": {
			"第 1 层": "基础移动巡航速度提升 22%",
			"第 2 层": "移速累计提升 36%",
			"第 3 层": "移速累计提升 46% (风驰电掣)"
		},
		"desc": "升级大马力双涡轮引擎与轻量化履带传动轴，使战车在急转弯与直线加速时更为敏捷。",
		"tactics": "有效化解敌方高爆轰炸与导弹准星锁定，轻松风筝慢速重装敌人。"
	},
	{
		"id": "perk_ricochet_rounds",
		"category": "UPGRADES",
		"name": "战术跳弹装置 (Ricochet Rounds)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_ricochet.png",
		"stats": {
			"第 1 层": "炮弹命中不可摧掩体反弹折射 1 次",
			"第 2 层": "炮弹可连续折射反弹 2 次",
			"第 3 层": "炮弹可连续折射反弹 3 次"
		},
		"desc": "为炮弹加装特种硬化被帽与反弹引信。炮弹打在钢墙或坚固障碍上不会湮灭，而是按物理入射角高速反弹！",
		"tactics": "在多走廊或密集掩体地图中，朝墙壁斜向射击可安全消灭拐角后方隐蔽的敌军，无需探身涉险。"
	},
	{
		"id": "perk_amphibious_hull",
		"category": "UPGRADES",
		"name": "两栖潜渡底盘 (Amphibious Hull)",
		"tag": "地形特种专长",
		"icon": "res://assets/sprites/powerups/amphibious_hull.png",
		"stats": {
			"解锁效果": "战车可自由驶入并穿越水域河流",
			"水面机动": "在水域中保持正常机动，不沉没不减速"
		},
		"desc": "底盘加装密闭浮力气囊与水下螺旋桨推进系统，彻底消除水面阻隔限制。",
		"tactics": "在河流横贯的地图中可直接涉水跨河奇袭敌军后方，或躲入河道躲避地面冲锋单位。"
	},
	{
		"id": "perk_nano_repair",
		"category": "UPGRADES",
		"name": "纳米脱战自愈 (Nano Repair)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_regen.png",
		"stats": {
			"机制": "脱离交火 3.0 秒后激活",
			"回复速率": "每秒持续恢复 0.5 ~ 1.2 HP"
		},
		"desc": "搭载智能纳米战地维修机器人群。只要暂时脱离交火避开攻击，纳米虫便会自动重组修复受损装甲。",
		"tactics": "受伤后切忌硬拼，利用掩体拉开距离等待 3 秒自愈充能完毕再重返战场。"
	},
	{
		"id": "perk_high_explosive",
		"category": "UPGRADES",
		"name": "高爆破片弹头 (High Explosive)",
		"tag": "专长被动 / 可叠 3 层",
		"icon": "res://assets/sprites/ui/perk_bomb.png",
		"stats": {
			"杀伤提升": "炮弹爆炸半径与杀伤力提升 30% ~ 65%",
			"群伤溅射": "命中目标时对周边贴近敌人造成连锁破片伤害"
		},
		"desc": "填装特种高能黑索金炸药，每次击中目标均会迸发广域高热火球破片。",
		"tactics": "对扎堆集群冲锋的敌方车队有毁灭性清场奇效。"
	},
	{
		"id": "tree_progression_curve",
		"category": "UPGRADES",
		"name": "等级与属性成长曲线 (RPG Growth Curve)",
		"tag": "核心机制 / 1-24 级节奏",
		"icon": "res://assets/sprites/ui/icon_atk.png",
		"stats": {
			"攻击力 (ATK)": "从第 3 级起每 4 级 +1 伤害 (3/7/11/15/19/23级)",
			"攻速 (Fire Rate)": "每 2 级 (偶数级) 提升 1 阶装填速度",
			"最大装甲 (HP)": "每 3 级提升 1 阶最大生命上限",
			"纳米自愈 (Regen)": "每 4 级提升 1 阶自愈恢复速率",
			"机动与工程 (Speed/Build)": "每奇数级提升移速与防御工程耐久"
		},
		"desc": "战役模式中击毁敌军获取经验值（XP）提升战车等级。各项战术指标按硬核平衡曲线自动成长升级，确保每一级都带来清晰可感知的战力增幅。",
		"tactics": "优先保护基地老鹰与击破精英怪快速积累 XP，前 3 级尽快升出第 1 点攻击力以确保在后续楼层具备一发秒杀常规杂兵的能力。"
	},

	# =========================================================================
	# 1. 坦克战车 (TANKS)
	# =========================================================================
	{
		"id": "player_classic",
		"category": "TANKS",
		"name": "经典先锋坦克 (Classic Tank)",
		"tag": "友方基础 / 进阶四阶",
		"icon": "res://assets/sprites/tanks/player_tier3_f0.png",
		"stats": {
			"基础生命": "3~6 HP (随等级成长)",
			"机动移速": "140 px/s (敏捷)",
			"武器火力": "单发实弹 -> 双发连射 -> 等离子穿甲",
			"专属优势": "均衡全能，星级升阶后具备等离子破钢能力"
		},
		"desc": "玩家初始标准主战坦克。具备优良的底盘转向机动与射速成长，在未分支选择前通过拾取【星星】可依次升级为双发高速炮与等离子激光炮。",
		"tactics": "早期优先拾取星星增强弹道威力。保持机动，避免被多方敌军十字交叉夹击。"
	},
	{
		"id": "player_speed",
		"category": "TANKS",
		"name": "高速突击战车 (Speed Striker)",
		"tag": "友方分支 / 极速狂飙",
		"icon": "res://assets/sprites/tanks/player_speed_t1_f0.png",
		"stats": {
			"基础生命": "3~5 HP",
			"机动移速": "190 px/s (超极速)",
			"主炮射速": "极快 (0.18s 极速装填)",
			"专属优势": "无与伦比的游击切入与抢夺空投资源能力"
		},
		"desc": "以牺牲少量装甲为代价换取极致爆发航速与超快装填周期的游侠战车。能在敌方弹幕中自如穿插穿梭。",
		"tactics": "适合放风筝与打带跑（Hit-and-Run）。在开阔地形中利用移速优势快速收割后排脆皮敌人。"
	},
	{
		"id": "player_heavy",
		"category": "TANKS",
		"name": "泰坦重装巨兽 (Heavy Juggernaut)",
		"tag": "友方分支 / 钢铁堡垒",
		"icon": "res://assets/sprites/tanks/player_heavy_t1_f0.png",
		"stats": {
			"基础生命": "6~10 HP (厚重坚固)",
			"机动移速": "115 px/s (沉稳)",
			"主炮威力": "巨炮重击 (+2 基础伤害)",
			"专属优势": "开场高生命与高额单发单发击杀压制力"
		},
		"desc": "装配重型复合陶泥装甲与大口径攻城主炮的钢铁堡垒。能在正面硬刚敌方重火力并一炮轰杀硬化目标。",
		"tactics": "适合阵地推进与正面拦截敌方冲锋。配合基地维修站或护盾站可实现近乎不死的坚守。"
	},
	{
		"id": "player_train",
		"category": "TANKS",
		"name": "装甲列车战团 (Armored Train)",
		"tag": "友方分支 / 多重车厢",
		"icon": "res://assets/sprites/tanks/player_train_loco_t1_f0.png",
		"stats": {
			"基础生命": "4~8 HP + 独立车厢生命",
			"随行单位": "1~2 节独立开火副炮车厢",
			"武器火力": "主车炮 + 火炮/火箭随行护卫",
			"专属优势": "车身长龙可有效阻挡来袭子弹并多角度锁敌"
		},
		"desc": "战术牵引车头，身后挂载跟随车厢。车厢不仅拥有自主索敌射击能力，还能在战场上充当活体掩体阻挡敌弹。",
		"tactics": "转向游走时注意车厢甩尾轨迹，利用长车身封堵路口或掩护残血队友撤退。"
	},
	{
		"id": "enemy_basic",
		"category": "TANKS",
		"name": "敌方基础轻坦 (Basic Tank)",
		"tag": "常规敌军 / 侦察兵",
		"icon": "res://assets/sprites/tanks/enemy_basic_f0.png",
		"stats": {
			"生命值": "1 HP (素车) ~ 3 HP (带甲)",
			"移速": "75 px/s",
			"射击间隔": "3.0s (常规直射)",
			"威胁等级": "★☆☆☆☆"
		},
		"desc": "敌军最常见的量产轻型巡逻单位。单发一击即溃，但多辆协同突入时会对基地构成隐患。",
		"tactics": "一枪一发清理，注意不要让其偷溜到基地老鹰背后。"
	},
	{
		"id": "enemy_fast",
		"category": "TANKS",
		"name": "极速突击坦 (Fast Raider)",
		"tag": "常规敌军 / 高速奔袭",
		"icon": "res://assets/sprites/tanks/enemy_fast_f0.png",
		"stats": {
			"生命值": "1 HP",
			"移速": "120 px/s (迅捷)",
			"射击间隔": "2.6s",
			"威胁等级": "★★☆☆☆"
		},
		"desc": "敌方高速先锋车，机动性极强，喜欢在掩体间快速穿插直扑玩家后方。",
		"tactics": "提前在路口预判瞄准射击，或建造滑轮墙、电墙进行卡位减速。"
	},
	{
		"id": "enemy_power",
		"category": "TANKS",
		"name": "重炮强击车 (Power Gunner)",
		"tag": "常规敌军 / 狙击火力",
		"icon": "res://assets/sprites/tanks/enemy_power_f0.png",
		"stats": {
			"生命值": "2 HP",
			"移速": "70 px/s",
			"弹道航速": "480 px/s (高速弹)",
			"威胁等级": "★★★☆☆"
		},
		"desc": "配备高速长身管滑膛炮的威胁单位，发射的炮弹飞行速度远超普通坦克，躲避反应窗口较窄。",
		"tactics": "不要在直线走廊与其长时间对狙，利用横向位移诱导其空枪后反击。"
	},
	{
		"id": "enemy_armor",
		"category": "TANKS",
		"name": "重型装甲车 (Heavy Armor Tank)",
		"tag": "常规敌军 / 肉盾中坚",
		"icon": "res://assets/sprites/tanks/enemy_armor_f0.png",
		"stats": {
			"生命值": "4 HP (极其耐打)",
			"移速": "60 px/s (沉重)",
			"受损反馈": "受损时外壳颜色逐级泛红",
			"威胁等级": "★★★☆☆"
		},
		"desc": "拥有 4 层厚重强化陶泥装甲的硬骨头。在未装备高伤主炮时需要连射 4 枪方能击毁。",
		"tactics": "优先利用定时炸弹、地雷或呼叫战术导弹快速破除其高额血量。"
	},
	{
		"id": "enemy_shotgun",
		"category": "TANKS",
		"name": "散弹突击车 (Shotgun Assault)",
		"tag": "特性敌军 / 扇形轰击",
		"icon": "res://assets/sprites/tanks/enemy_shotgun_f0.png",
		"stats": {
			"生命值": "3 HP",
			"移速": "95 px/s (快速突进)",
			"攻击模式": "一次齐射 3 发扇形扩散弹 (-20°/0°/+20°)",
			"威胁等级": "★★★☆☆"
		},
		"desc": "装备三联装大口径喇叭形霰弹炮口的冲锋坦克。中近距离齐射覆盖大片扇形区域，毁灭性极强。",
		"tactics": "切忌贴脸肉搏！拉开距离在扇形弹幕间隙规避或绕后攻击。"
	},
	{
		"id": "enemy_sniper",
		"category": "TANKS",
		"name": "侦察狙击车 (Sniper Scout)",
		"tag": "特性敌军 / 极速长蓄力",
		"icon": "res://assets/sprites/tanks/enemy_sniper_f0.png",
		"stats": {
			"生命值": "2 HP (脆弱轻装)",
			"移速": "135 px/s (极快游走)",
			"装填蓄力": "4.8s (射击前 0.6s 驻车锁定闪烁)",
			"弹道航速": "620 px/s (超音速穿甲弹，可毁钢墙)",
			"威胁等级": "★★★★☆"
		},
		"desc": "极高机动性的磁轨狙击坦克。在开火前会突然驻车瞄准并泛出青蓝光晕，随后轰出全图贯穿的超高速穿甲弹。",
		"tactics": "观察其瞄准闪烁特征，在其驻车瞄准的 0.6 秒硬直期横向大角度变向躲避并实施反杀。"
	},
	{
		"id": "enemy_gatling",
		"category": "TANKS",
		"name": "加特林重坦 (Gatling Juggernaut)",
		"tag": "特性敌军 / 极速弹幕",
		"icon": "res://assets/sprites/tanks/enemy_gatling_f0.png",
		"stats": {
			"生命值": "5 HP (超厚要塞)",
			"移速": "42 px/s (极其迟缓)",
			"射击间隔": "0.40s (极速高密机枪压制)",
			"威胁等级": "★★★★☆"
		},
		"desc": "装备六管旋转加特林机炮与巨型后置弹鼓的重型要塞。移动极其缓慢，但一旦进入射程会倾泻连续不断的弹幕火网。",
		"tactics": "切勿正面顶着弹幕硬冲！利用转角地形卡视野伏击，或在其正面放置滑轮墙反弹反压。"
	},
	{
		"id": "enemy_crusher",
		"category": "TANKS",
		"name": "粉碎者巨坦 (The Crusher)",
		"tag": "特种敌军 / 碾碎一切",
		"icon": "res://assets/sprites/tanks/enemy_crusher_f0.png",
		"stats": {
			"生命值": "10 HP (超绝重装甲)",
			"移速": "40 px/s (沉重缓慢)",
			"攻击方式": "无子弹，巨型旋转尖刺滚筒",
			"碾碎能力": "硬生生碾破钢墙、砖泥、全建筑与玩家",
			"威胁等级": "★★★★★"
		},
		"desc": "前置巨型旋转带刺滚筒的超重型机械怪兽。它从不发射子弹，但能将沿途所碰到的所有掩体、钢铁墙壁、玩家防御建筑与坦克碾压粉碎！",
		"tactics": "绝不可让其接近基地或防御核心！必须集中远程全火力拉扯风筝集火，或用地雷/炸弹暴力爆破。"
	},
	{
		"id": "enemy_flamethrower",
		"category": "TANKS",
		"name": "烈焰喷火坦 (Flamethrower)",
		"tag": "特性敌军 / 持续锥形火舌",
		"icon": "res://assets/sprites/tanks/enemy_flame_f0.png",
		"stats": {
			"生命值": "3 HP",
			"移速": "65 px/s",
			"武器机制": "喷发持续性前方烈焰锥 (2.75格射程)",
			"威胁等级": "★★★★☆"
		},
		"desc": "装备持续喷火枪管的压制战车，周期性喷涌炽热火舌，对射程内的所有建筑与坦克造成连续灼烧。",
		"tactics": "射程有限是其致命伤。保持在 3 格以外安全距离侧向射击即可轻松化解。"
	},
	{
		"id": "enemy_bomber",
		"category": "TANKS",
		"name": "轰炸布雷车 (Bomber Tank)",
		"tag": "区域封锁 / 定时爆破",
		"icon": "res://assets/sprites/tanks/enemy_bomber_f0.png",
		"stats": {
			"生命值": "2 HP",
			"移速": "75 px/s",
			"武器机制": "在身后丢下倒计时 2.4s 的高爆炸弹",
			"威胁等级": "★★★☆☆"
		},
		"desc": "穿行在战场上的布雷专家，会在路径上不断丢下大威力定时炸弹，引爆十字冲击波。",
		"tactics": "切勿跟在其屁股后面追击，注意避开其留下的闪烁定时炸弹。"
	},
	{
		"id": "enemy_suicide",
		"category": "TANKS",
		"name": "自爆突击卡车 (Suicide Demolisher)",
		"tag": "极速突袭 / 接触自爆",
		"icon": "res://assets/sprites/tanks/enemy_suicide_f0.png",
		"stats": {
			"生命值": "1 HP",
			"移速": "170 px/s (极速冲锋)",
			"自爆威力": "84px 广域绿色高能爆轰",
			"威胁等级": "★★★★☆"
		},
		"desc": "载满核能高爆燃料的疯狂突击卡车，发现目标后会不顾一切高速撞击并在近身瞬间自爆。",
		"tactics": "听到警报或看到红光闪烁时立即后撤并远距离点射引爆它！它的殉爆还会炸死周遭敌军。"
	},
	{
		"id": "enemy_aircraft",
		"category": "TANKS",
		"name": "高空战机 (Sky Corsair)",
		"tag": "全地形飞行 / 航炮轰炸",
		"icon": "res://assets/sprites/tanks/enemy_aircraft_f0.png",
		"stats": {
			"生命值": "2 HP",
			"移速": "160 px/s (高空疾驰)",
			"地形穿透": "完全无视水面、墙体与深渊",
			"武器机制": "双联航炮高速扫射 + 40%概率空投炸弹",
			"威胁等级": "★★★★☆"
		},
		"desc": "在高空盘旋的空中单位，地面任何墙体与河流都无法阻挡其航线，对地面目标实施多角度立体轰炸。",
		"tactics": "建造强化防空墙或自动防御炮塔可形成有效对空阻截。"
	},
	{
		"id": "enemy_mirage",
		"category": "TANKS",
		"name": "幻影隐形车 (Mirage Phantom)",
		"tag": "光学伪装 / 隐蔽激光",
		"icon": "res://assets/sprites/tanks/enemy_mirage_f0.png",
		"stats": {
			"生命值": "2 HP",
			"移速": "70 px/s",
			"伪装机制": "静止 0.45s 自动伪装成树木地块",
			"武器机制": "树丛隐匿射出贯穿高能激光",
			"威胁等级": "★★★★☆"
		},
		"desc": "搭载光学迷彩的潜行战车。静止时与普通树木完全无二，唯有移动或开火时才会显形。",
		"tactics": "观察丛林中不自然开火的激光来源，或者直接用高爆范围武器清扫可疑树木丛林。"
	},
	{
		"id": "enemy_battleship",
		"category": "TANKS",
		"name": "两栖战列巡洋舰 (Amphibious Battleship)",
		"tag": "水域霸主 / 范围重炮",
		"icon": "res://assets/sprites/tanks/enemy_battleship_f0.png",
		"stats": {
			"生命值": "6 HP (重型水陆战舰)",
			"移速": "65 px/s (水面全速畅行)",
			"武器机制": "双联重装舰炮 (42px 范围爆破轰击)",
			"威胁等级": "★★★★☆"
		},
		"desc": "拥有重装甲与双联舰炮的重型两栖水军主力，在水面如履平地且能轰出大范围爆破杀伤。",
		"tactics": "岸防作战时注意规避其范围爆炸溅射伤害，利用等离子武器集火击沉。"
	},
	{
		"id": "enemy_laser",
		"category": "TANKS",
		"name": "聚能激光坦 (Laser Piercer)",
		"tag": "瞬间贯穿 / 直线绝杀",
		"icon": "res://assets/sprites/tanks/enemy_laser_f0.png",
		"stats": {
			"生命值": "3 HP",
			"移速": "65 px/s",
			"武器机制": "瞬间发射穿透所有目标的聚能光束",
			"威胁等级": "★★★★☆"
		},
		"desc": "装备聚能激光发射器的高科技战车，激光能瞬间穿透一整列障碍物并击穿多辆坦克。",
		"tactics": "不要与多名队友或基地处在同一条水平/垂直直线上，错位站位能完全化解激光威胁。"
	},
	{
		"id": "enemy_missile",
		"category": "TANKS",
		"name": "战术导弹引导车 (Missile Launcher)",
		"tag": "超视距打击 / 准星预警",
		"icon": "res://assets/sprites/tanks/enemy_missile_f0.png",
		"stats": {
			"生命值": "3 HP",
			"移速": "80 px/s",
			"打击机制": "1.8s 准星缩圈预警，随后天降导弹轰炸",
			"威胁等级": "★★★★★"
		},
		"desc": "可在全图任意角落呼叫全屏天降战术导弹的远程危险单位。",
		"tactics": "地面出现红色收缩准星时，必须在 1.8 秒内迅速驶离爆心红色区域！"
	},
	{
		"id": "enemy_warp",
		"category": "TANKS",
		"name": "虚空折跃坦克 (Warp Phantom)",
		"tag": "瞬移折跃 / 捉摸不定",
		"icon": "res://assets/sprites/tanks/enemy_warp_f0.png",
		"stats": {
			"生命值": "3 HP",
			"移速": "100 px/s (冰面额外抓地)",
			"折跃机制": "每 3.5~5.5s 随机瞬间折跃传送",
			"威胁等级": "★★★★☆"
		},
		"desc": "极北冰原与虚空异界专属兵种，能在战场空地上神出鬼没地瞬间传送，难以被常规直线火力瞄准锁定。",
		"tactics": "利用自动防御炮塔全方位索敌，或在空地上布设地雷让其折跃着陆即踩雷。"
	},
	{
		"id": "enemy_splitter",
		"category": "TANKS",
		"name": "重装母体分裂车 (Splitter Colossus)",
		"tag": "大型精英 / 聚落分化",
		"icon": "res://assets/sprites/tanks/enemy_splitter_f0.png",
		"stats": {
			"生命值": "7 HP (超厚重型母体)",
			"移速": "52 px/s",
			"主武器": "双联重炮齐射",
			"特殊机制": "阵亡爆裂时瞬间向四方分裂解体出 4 辆小型战车",
			"威胁等级": "★★★★★"
		},
		"desc": "重型多舱母体战车，四角搭载独立挂载式子舱。被彻底摧毁时其内置的动力炉会引发聚变弹射，瞬间向对角线四散出 4 辆极速小型战车进行二次围剿。",
		"tactics": "击毁母体前先退至安全距离或预留范围穿透弹药。分裂瞬间快速调转枪口清理刚着陆的小型车，防止被反向包夹。"
	},
	{
		"id": "enemy_split_mini",
		"category": "TANKS",
		"name": "小型分裂子战车 (Mini Split Drone)",
		"tag": "集群骚扰 / 敏捷先锋",
		"icon": "res://assets/sprites/tanks/enemy_split_mini_f0.png",
		"stats": {
			"生命值": "1 HP (一击即溃)",
			"移速": "130 px/s (极速冲锋)",
			"射击间隔": "1.8s (轻量连珠)",
			"威胁等级": "★★☆☆☆"
		},
		"desc": "母体分裂坦克解体后诞生的无人轻蜂战车。体积小巧机动敏捷，虽然装甲极薄，但数量众多且散开速度极快。",
		"tactics": "利用普通主炮或霰弹扇形散射一网打尽。切勿放任其溜向基地。"
	},
	{
		"id": "enemy_boss",
		"category": "TANKS",
		"name": "巅峰要塞巨神 (Summit Colossus)",
		"tag": "终极首领 / 全面战争",
		"icon": "res://assets/sprites/tanks/enemy_boss_f0.png",
		"stats": {
			"生命值": "10~25 HP (巨额首领血条)",
			"移速": "50 px/s",
			"主武器": "双联攻城巨炮 (破钢弹)",
			"副武器": "35% 概率发射自动追踪锁定追踪弹",
			"威胁等级": "★★★★★★"
		},
		"desc": "战役关卡巅峰终极巨型战车要塞。具备强横的攻城火力与自动索敌追踪导弹，体型庞大压迫感十足。",
		"tactics": "充分利用全场掩体与队友协同输出，注意引诱或拦截其发射的制导追踪导弹。"
	},

	# =========================================================================
	# 2. 道具与拾取物 (ITEMS)
	# =========================================================================
	{
		"id": "item_star",
		"category": "ITEMS",
		"name": "能量五角星 (Power Star)",
		"tag": "主炮进阶",
		"icon": "res://assets/sprites/powerups/star.png",
		"stats": {"获取效果": "主炮等级 +1 (最高可达等离子穿甲级)"},
		"desc": "经典战场能量强化之星。拾取后可逐步提升子弹飞行速度、连射数量并解锁等离子破钢能力。",
		"tactics": "开局最重要的争夺物资，一旦出现应优先夺取。"
	},
	{
		"id": "item_bomb",
		"category": "ITEMS",
		"name": "全场核爆弹 (Tactical Nuke)",
		"tag": "全屏清场",
		"icon": "res://assets/sprites/powerups/bomb.png",
		"stats": {"获取效果": "瞬间引爆消灭全场所有普通敌军坦克"},
		"desc": "战术核爆装置。拾取瞬间引发全屏震颤爆轰，将场上所有在场普通敌人瞬间化为乌有。",
		"tactics": "在敌人数量达到上限或基地被重重包围时拾取收益最大。"
	},
	{
		"id": "item_clock",
		"category": "ITEMS",
		"name": "时间定格钟 (Time Clock)",
		"tag": "时间冻结",
		"icon": "res://assets/sprites/powerups/clock.png",
		"stats": {"获取效果": "全体敌人完全静止冻结数秒"},
		"desc": "超时空时钟发生器。在有效时间内所有敌方坦克停止移动与开火，任由玩家宰割。",
		"tactics": "抓住冻结窗口期快速定点清除高威胁的粉碎者或狙击手。"
	},
	{
		"id": "item_helmet",
		"category": "ITEMS",
		"name": "能量防御盔 (Shield Helmet)",
		"tag": "无敌护盾",
		"icon": "res://assets/sprites/powerups/helmet.png",
		"stats": {"获取效果": "赋予战车无敌防护罩 (持续 6 秒)"},
		"desc": "高能防护力场头盔。激活期间免疫所有子弹、爆炸与近身撞击伤害。",
		"tactics": "可趁无敌状态直接横冲直撞冲入敌方阵地近身轰碎强敌。"
	},
	{
		"id": "item_shovel",
		"category": "ITEMS",
		"name": "工事工兵铲 (Fortify Shovel)",
		"tag": "基地钢化",
		"icon": "res://assets/sprites/powerups/shovel.png",
		"stats": {"获取效果": "基地周围外墙临时转化为坚不可摧的钢墙"},
		"desc": "基地应急加固工具。能迅速将老鹰周边的砖墙升级为坚不可摧的钢铁防线。",
		"tactics": "在基地砖墙被敌军打穿危在旦夕时起到绝处逢生的关键保命作用。"
	},
	{
		"id": "item_life",
		"category": "ITEMS",
		"name": "增援备用战车 (Extra Life)",
		"tag": "额外奖命",
		"icon": "res://assets/sprites/powerups/life.png",
		"stats": {"获取效果": "玩家生命数 +1"},
		"desc": "后备重装战车配额。延长战役容错率与通关保障。",
		"tactics": "双人模式下注意协同分配，保证两人均有足够复活配额。"
	},
	{
		"id": "item_gold_gem",
		"category": "ITEMS",
		"name": "战术金币与钻石 (Gold & Gems)",
		"tag": "战利品经济",
		"icon": "res://assets/sprites/powerups/diamond_gem.png",
		"stats": {"获取效果": "增加战役金币，用于在尖塔商店购买构筑"},
		"desc": "击毁敌方坦克或开启秘宝宝箱掉落的贵重硬币与宝石物资，在战役地图的商店中可采购高阶建筑与被动技能。",
		"tactics": "金币掉落后有存在时效，安全前提下尽量驾车扫荡拾取。"
	},
	{
		"id": "item_chest_key",
		"category": "ITEMS",
		"name": "秘宝宝箱与金钥匙 (Treasure Chest & Key)",
		"tag": "秘密秘宝",
		"icon": "res://assets/sprites/powerups/treasure_chest.png",
		"stats": {"获取效果": "用钥匙打开宝箱获取丰厚金币与高级增益"},
		"desc": "隐藏在战场地块深处的神秘宝藏。拾取战场金钥匙后撞击宝箱即可开启。",
		"tactics": "在挑战关卡中注意扫平角落障碍搜寻钥匙与宝箱。"
	},

	# =========================================================================
	# 3. 防御建筑 (BUILDINGS)
	# =========================================================================
	{
		"id": "bld_turret",
		"category": "BUILDINGS",
		"name": "自动防御炮塔 (Defense Turret)",
		"tag": "全自动火力支援",
		"icon": "res://assets/sprites/buildings/turret_gun.png",
		"stats": {
			"生命值": "3 HP (坚实结构)",
			"攻击射程": "280 px (大范围索敌)",
			"攻击模式": "360° 自动旋转锁定并射击靠近的敌人"
		},
		"desc": "由底座与自动旋转炮管组成。放置在交通要道可形成无人自动化防线，有效阻击漏网之鱼。",
		"tactics": "布置在基地侧翼或路口转角处，可替玩家守护侧后方防线。"
	},
	{
		"id": "bld_fortified_wall",
		"category": "BUILDINGS",
		"name": "强化防空墙 (Fortified Wall)",
		"tag": "多模块加固钢墙",
		"icon": "res://assets/sprites/buildings/fortified_wall.png",
		"stats": {
			"结构组成": "4 个独立坚固模块",
			"阻挡能力": "免疫常规子弹穿透，有效拦截地面与空中威胁"
		},
		"desc": "由 4 块坚实模块拼接而成的超耐久复合工程墙。单块受损不会导致全墙坍塌，还能被维修站修复。",
		"tactics": "放置在敌军主进攻路线上，迫使敌军转向绕行。"
	},
	{
		"id": "bld_electric_wall",
		"category": "BUILDINGS",
		"name": "高压电击墙 (Electric Wall)",
		"tag": "区域麻痹减速",
		"icon": "res://assets/sprites/tiles/tile_electric_wall_f0.png",
		"stats": {
			"防御特性": "持续释放高压电流弧光",
			"受击反馈": "敌人接触时遭受电击麻痹、大幅减速并受创"
		},
		"desc": "通体闪烁电弧的高科技电磁防线。能让任何试图强行穿越的敌方坦克陷入持续触电硬直。",
		"tactics": "配合自动炮塔使用，电击墙减速留人，炮塔趁机集火收割。"
	},
	{
		"id": "bld_repair_station",
		"category": "BUILDINGS",
		"name": "战场维修站 (Repair Station)",
		"tag": "范围战地治疗",
		"icon": "res://assets/sprites/buildings/repair_station.png",
		"stats": {
			"维修范围": "以自身为中心 2 格半径",
			"治疗效果": "为范围内的玩家战车与防御建筑持续修复生命"
		},
		"desc": "战地后勤保障核心。展开后持续向周遭释放绿色纳米修复光晕，大幅提升阵地战续航。",
		"tactics": "建立在基地内部或坚固掩体后方，打造不可攻破的补给据点。"
	},
	{
		"id": "bld_shield_station",
		"category": "BUILDINGS",
		"name": "能量护盾站 (Shield Station)",
		"tag": "便携护甲充能",
		"icon": "res://assets/sprites/buildings/shield_station.png",
		"stats": {
			"充能范围": "1.5 格半径",
			"防护效果": "为进入范围的友军战车充能一层临时抗冲击护盾"
		},
		"desc": "投射蓝色球形能量力场的充能装置，能为路过的战车提供一层额外抵御伤害的护盾。",
		"tactics": "放置在玩家经常出击的必经之路上，每次出击前顺路充能护盾。"
	},
	{
		"id": "bld_wind_blower",
		"category": "BUILDINGS",
		"name": "强力风力涡轮 (Wind Turbine)",
		"tag": "强风推移控制",
		"icon": "res://assets/sprites/buildings/wind_blower.png",
		"stats": {
			"风向范围": "直线 4 格强劲定向风道",
			"推移效果": "强力推飞吹阻敌方战车并偏转迎面子弹"
		},
		"desc": "工业级强力鼓风装置，能向指定朝向吹出呼啸气流，彻底打乱敌军进攻步调与弹道航向。",
		"tactics": "正对敌军出怪口布置，可将冲出的敌人直接吹回甚至卡死在角落。"
	},
	{
		"id": "bld_street_lamp",
		"category": "BUILDINGS",
		"name": "战术探照路灯 (Street Lamp)",
		"tag": "夜战黑夜照明",
		"icon": "res://assets/sprites/buildings/street_lamp.png",
		"stats": {
			"照明范围": "驱散黑夜迷雾，照亮周边 3 格区域",
			"战术价值": "夜间作战必备，提供关键视野"
		},
		"desc": "在黑夜战役或暗夜空投挑战中，路灯能驱散深邃夜幕，提前侦测潜伏逼近的暗夜敌军。",
		"tactics": "在黑夜关卡中优先沿主干道插放路灯建立光明防线。"
	},
	{
		"id": "bld_roller_wall",
		"category": "BUILDINGS",
		"name": "滑轮防线墙 (Roller Wall)",
		"tag": "受力推移 / 撞击碾压",
		"icon": "res://assets/sprites/buildings/roller_wall.png",
		"stats": {
			"受击反馈": "受到攻击时顺应受力方向滚动推移 1 格 (48px)",
			"碾压攻击": "推移过程中粉碎路途上的砖块并对敌军造成撞击碾伤"
		},
		"desc": "底部装有滚轮与撞击卡齿的机动防线墙。玩家射击墙体可将其像保龄球一样向前推移，撞毁沿途障碍与敌人。",
		"tactics": "站在滑轮墙后方向前射击推进，利用墙体充当移动掩体直推敌方阵线。"
	},
	{
		"id": "bld_oil_barrel",
		"category": "BUILDINGS",
		"name": "高爆引火油桶 (Oil Barrel)",
		"tag": "范围烈焰殉爆",
		"icon": "res://assets/sprites/buildings/oil_barrel.png",
		"stats": {
			"殉爆范围": "3x3 范围毁灭性连锁烈焰爆轰",
			"破坏力": "秒杀普通敌人并轰破周边钢墙与砖块"
		},
		"desc": "装满高燃重油的危险品桶。受子弹或爆炸波及将瞬间引爆，产生毁灭性的连锁烈焰。",
		"tactics": "算准敌军集群靠近油桶的时机，一枪引爆实现四两拨千斤的全歼。"
	},
	{
		"id": "bld_enemy_shield_tower",
		"category": "BUILDINGS",
		"name": "敌方护盾发生塔 (Enemy Shield Pylon)",
		"tag": "敌方要塞 / 范围无敌力场",
		"icon": "res://assets/sprites/buildings/enemy_shield_tower.png",
		"stats": {
			"生命值": "8 HP (重装防卫结构)",
			"力场半径": "180 px (广域防护力场)",
			"庇护效果": "为力场内的所有敌方坦克提供坚不可摧的无敌护盾",
			"破解机制": "必须将其本体彻底摧毁，才能解除并消除敌方的护盾增益"
		},
		"desc": "敌军高阶防御要塞中矗立的重型护盾发生塔，顶端悬浮高能等离子共振核心。只要塔体存活，力场笼罩下的所有敌军战车均处于完全免伤状态。",
		"tactics": "切勿与力场内的无敌敌军硬拼。应优先集火或绕过敌军防线强攻摧毁护盾塔本体，力场崩解后敌军战车便会失去保护，即可轻松歼灭。"
	},

	# =========================================================================
	# 4. 战场地形 (TERRAIN)
	# =========================================================================
	{
		"id": "tile_brick",
		"category": "TERRAIN",
		"name": "经典红砖墙 (Brick Wall)",
		"tag": "可打碎掩体",
		"icon": "res://assets/sprites/tiles/tile_brick.png",
		"stats": {"通行特性": "阻挡坦克通行与子弹射击", "破坏方式": "任意常规炮弹可逐块打碎"},
		"desc": "坦克大战最基础的战术地形。能够抵挡子弹并为战车提供掩护，但会被持续射击逐步消磨殆尽。",
		"tactics": "利用拐角砖块露头开枪，在砖墙即将被打穿前迅速转移。"
	},
	{
		"id": "tile_steel",
		"category": "TERRAIN",
		"name": "强化钢铁墙 (Steel Wall)",
		"tag": "不可摧硬质掩体",
		"icon": "res://assets/sprites/tiles/tile_steel.png",
		"stats": {"通行特性": "阻挡坦克与常规子弹", "破坏方式": "仅等离子3级弹、爆炸物与粉碎者可破"},
		"desc": "坚硬无比的工业级厚重钢板地块。常规炮弹打在其上只会迸发火花弹飞，是极佳的永久掩体。",
		"tactics": "利用钢墙抵挡强敌的高速主炮与激光直射。"
	},
	{
		"id": "tile_trees",
		"category": "TERRAIN",
		"name": "隐蔽丛林树木 (Forest Trees)",
		"tag": "视线伪装遮蔽",
		"icon": "res://assets/sprites/tiles/tile_trees.png",
		"stats": {"通行特性": "坦克可驶入隐蔽", "弹道特性": "子弹可自由穿透树冠"},
		"desc": "茂密的丛林地带。战车开入其中会被树荫遮蔽隐匿，但树木无法阻挡子弹穿透。",
		"tactics": "警惕潜伏在树林里的幻影坦克，利用范围武器探草排险。"
	},
	{
		"id": "tile_water",
		"category": "TERRAIN",
		"name": "水域河流 (River Water)",
		"tag": "天然屏障",
		"icon": "res://assets/sprites/tiles/tile_water_f0.png",
		"stats": {"通行特性": "阻挡普通陆地坦克，两栖战列舰与高空战机可通行", "弹道特性": "子弹可飞跃水面"},
		"desc": "波光粼粼的水面阻隔。形成天然的战术隔断，使得陆地单位必须寻找桥梁或狭道绕行。",
		"tactics": "隔着河流水域对对岸行动受限的敌人进行安全点射。"
	},
	{
		"id": "tile_sand",
		"category": "TERRAIN",
		"name": "荒漠流沙与沙丘 (Desert Sand & Dune)",
		"tag": "地形阻力减速",
		"icon": "res://assets/sprites/tiles/tile_sand.png",
		"stats": {"通行特性": "普通敌人进入沙地减速 50%，沙漠坦克加速 45%", "沙丘特性": "可被摧毁的松散沙堆"},
		"desc": "松软深陷的沙地环境。常规战车行驶其上如陷泥潭，唯有装备沙漠履带的特种坦克能如鱼得水。",
		"tactics": "引诱追击的敌人驶入沙地，在其大幅减速陷入泥沼时精准歼灭。"
	},
	{
		"id": "tile_ice",
		"category": "TERRAIN",
		"name": "极寒光滑冰面 (Glacial Ice)",
		"tag": "高速失控滑行",
		"icon": "res://assets/sprites/tiles/tile_ice.png",
		"stats": {"通行特性": "战车在冰面上获得 35% 速度加成，但惯性极高容易打滑"},
		"desc": "极北冰原地带的光滑冰封地带。战车驶入会高速滑移且刹车惯性极大。",
		"tactics": "利用冰面高速冲刺穿梭，但要提前预判转向以防一头撞进敌军怀里。"
	},
	{
		"id": "tile_hard_clay",
		"category": "TERRAIN",
		"name": "硬化陶泥块 (Hard Clay)",
		"tag": "多段破坏地块",
		"icon": "res://assets/sprites/tiles/tile_hard_clay.png",
		"stats": {"耐久特性": "需连续承受 3 次命中方可击碎", "受损反馈": "受损时裂纹逐级扩散"},
		"desc": "经过高温煅烧的硬质陶土块。比普通砖墙更结实耐打，形成富有弹性的临时防线。",
		"tactics": "适合作为中转掩体利用。"
	},
	{
		"id": "tile_conveyor",
		"category": "TERRAIN",
		"name": "动力传送带 (Conveyor Belt)",
		"tag": "强制定向输送",
		"icon": "res://assets/sprites/tiles/tile_conveyor.png",
		"stats": {"输送特性": "持续沿箭头朝向强制推移上方所有坦克与建筑"},
		"desc": "自动化工业传送履带，会将上方经过的任何战车向指定方向强制推移。",
		"tactics": "利用顺向传送带实现瞬间弹射加速，或将滑轮墙推上输送带自动前送。"
	},
	{
		"id": "tile_jump_pad",
		"category": "TERRAIN",
		"name": "弹跳跃板 (Jump Pad)",
		"tag": "瞬间高空弹射",
		"icon": "res://assets/sprites/tiles/tile_jump_pad.png",
		"stats": {"弹跳效果": "踏上瞬间将战车弹射跨越前方障碍"},
		"desc": "强力弹射板，战车踩上瞬间会被强行抛射跨过前方的障碍与深坑。",
		"tactics": "利用跳板实现出其不意的飞跃奇袭与绝地脱困。"
	},
	{
		"id": "tile_wormhole",
		"category": "TERRAIN",
		"name": "空间折跃虫洞 (Wormhole Portal)",
		"tag": "双向空间穿越",
		"icon": "res://assets/sprites/tiles/tile_wormhole.png",
		"stats": {"折跃效果": "进入虫洞瞬间从战场另一端的相连虫洞驶出"},
		"desc": "神秘的空间撕裂通道。驶入一端会立刻在另一端的出口重组现身，连通战场的两极。",
		"tactics": "在被大批敌军围困时果断驶入虫洞实现瞬间乾坤大挪移。"
	},
	{
		"id": "tile_base_eagle",
		"category": "TERRAIN",
		"name": "指挥司令基地老鹰 (Base Eagle)",
		"tag": "核心守护目标",
		"icon": "res://assets/sprites/tiles/base_eagle.png",
		"stats": {"防御特性": "1 次致命命中即告被毁", "战败条件": "老鹰被摧毁则战斗立刻失败宣告 GAME OVER"},
		"desc": "战场的最高指挥神经中枢！象征着阵地的存亡。无论任何情况下，保护老鹰基地都是第一要务。",
		"tactics": "在老鹰周围修建自动炮塔、强化墙或维修站，时刻留意绕后的敌军高速车与高空战机！"
	}
]

static func get_entries_by_category(cat: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entry in ENTRIES:
		if entry.get("category", "") == cat:
			list.append(entry)
	return list

static func get_entry_by_id(id: String) -> Dictionary:
	for entry in ENTRIES:
		if entry.get("id", "") == id:
			return entry
	return {}
