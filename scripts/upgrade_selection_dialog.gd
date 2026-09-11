class_name UpgradeSelectionDialog
extends CanvasLayer

const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")

signal option_selected(option_data: Dictionary, player_id: int)
## 联机客户端选完卡: 只带索引, 效果由主机应用 (见 show_remote_options)。
signal remote_option_picked(index: int, player_id: int)

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var subtitle_label: Label = $Panel/SubtitleLabel
@onready var card_container: HBoxContainer = $Panel/CardContainer

## 经典线的四个阶级名与三次升阶的实际效果 —— 全是 player.gd 里早就实装、
## 只是没人走到的行为 (见 BRANCH_CARDS 上面那段):
##   tier1 弹速 480 -> 660      (player.gd::_shoot 的 b_speed)
##   tier2 单发 -> 三发平行弹    (upgrade_tier == 2 那一支)
##   tier3 等离子弹, 可破钢, 开火带冲击波
## 每一阶另有 +12% 移速 (speed_mult 里的 upgrade_tier * 0.12)。
const CLASSIC_RANKS := ["BASIC", "SCOUT+", "TWIN-CANNON", "PLASMA DREADNOUGHT"]
const CLASSIC_TIER_DESC := [
	"炮弹初速 480 → 660，机动性 +12%。侦察型底盘调校完成。",
	"主炮改为三管平行齐射，一次泼出三发！机动性再 +12%。",
	"换装等离子弹芯：可直接击穿钢墙，开火附带冲击波。机动性再 +12%。",
]

## 五条进阶流派的卡面文案。键必须和 branch_blueprints.gd 的 BLUEPRINTS 一致 ——
## 那边管"这条分支要哪张图纸解锁", 这边管"卡上写什么"。
## tools/test_branch_unlock.gd 比对两边的键集合: 少一条就是升级界面里少一张卡,
## 而那不会有任何报错。
##
## 拆两张表而不是合一张: 规则模块不该塞满 UI 文案。
const BRANCH_CARDS := {
	"speed": {
		"type": "branch",
		"branch": "speed",
		"icon": "speed",
		"name": "迅捷斥候型\n(Speed Scout)",
		"tag": "【极速·速射·流沙无阻】",
		"desc": "底盘轻量化流线型蜕变！移速+40%，双联高速针式机炮，无视沙漠流沙减速阻力！",
	},
	"heavy": {
		"type": "branch",
		"branch": "heavy",
		"icon": "heavy",
		"name": "重装泰坦型\n(Heavy Juggernaut)",
		"tag": "【装甲·重炮·AoE溅射】",
		"desc": "加装超厚反应装甲！生命上限+4，发射超重型高爆巨炮，命中触发大范围爆炸与击退！",
	},
	"train": {
		"type": "branch",
		"branch": "train",
		"icon": "train",
		"name": "装甲列车型\n(Armored Train)",
		"tag": "【多节车厢·自动火炮】",
		"desc": "进化为重装铁道车头！后节挂载【全自动火炮车厢】，360度自动索敌消灭后方威胁！",
	},
	"counter": {
		"type": "branch",
		"branch": "counter",
		"icon": "counter",
		"name": "绝地反击型\n(Counter Vanguard)",
		"tag": "【精准盾反·升阶逆转】",
		"desc": "搭载能量反冲盾！开火瞬间部署能量盾反弹敌弹并反射激光，完美弹反令炮弹升阶破钢！攻速极慢。",
	},
	"trench": {
		"type": "branch",
		"branch": "trench",
		"icon": "trench",
		"name": "壕沟先锋型\n(Trench Raider)",
		"tag": "【短距环刃·破钢切弹】",
		"desc": "改装前向高频激光环形切刀！近身短距环刃横扫，瞬间切割拦截敌方炮弹并粉碎掩体，切割等级与当前炮弹等级相等！",
	},
}

var cards_data: Array[Dictionary] = []
var current_player_id: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if panel:
		UIThemeHelper.apply_clay_panel(panel)

func show_upgrade_options(rpg_mgr: RPGManager, player_id: int = 1) -> void:
	_show_cards(_generate_choices(rpg_mgr, player_id), player_id, rpg_mgr)


## 联机客户端用: 卡面由**主机**生成并下发, 这边只负责显示, 以及回报"选了
## 第几张"。
##
## 效果的应用留在主机 (rpg_mgr 在那边, 客户端根本不跑自己那份), 所以回报的
## 是索引而不是选项内容 —— 客户端能改的只有"第几张", 改不了那张卡是什么。
func show_remote_options(options: Array, player_id: int) -> void:
	var typed: Array[Dictionary] = []
	for o in options:
		typed.append(o as Dictionary)
	_show_cards(typed, player_id, null)


## rpg_mgr 为 null = 这是客户端的远端选卡界面, 点下去只回报索引。
func _show_cards(choices: Array[Dictionary], player_id: int, rpg_mgr: RPGManager) -> void:
	current_player_id = player_id
	get_tree().paused = true
	visible = true
	SoundManager.play_level_up(get_tree())

	# Clear previous cards
	for child in card_container.get_children():
		child.queue_free()

	cards_data = choices
	if player_id == 2:
		title_label.text = "[P2] " + title_label.text

	var card_index := -1
	for opt in cards_data:
		card_index += 1
		var card_btn = Button.new()
		var card_w = 175 if cards_data.size() >= 4 else 210
		card_btn.custom_minimum_size = Vector2(card_w, 240)
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_branch: bool = str(opt.get("type", "")) == "branch"
		var theme_type = "normal"
		var branch_name = str(opt.get("branch", ""))
		var perk_id = str(opt.get("id", ""))
		if branch_name == "heavy" or perk_id in ["titan_plating", "high_explosive", "clay_crusher"]:
			theme_type = "heavy"
		elif branch_name == "speed" or perk_id in ["rapid_loader", "nitro_booster", "frost_cleats"]:
			theme_type = "speed"
		elif branch_name == "train" or perk_id in ["warp_drive", "nano_repair"]:
			theme_type = "shield"
		elif branch_name == "counter" or branch_name == "trench":
			theme_type = "branch"
		elif is_branch:
			theme_type = "branch"
		UIThemeHelper.apply_clay_upgrade_card_themed(card_btn, theme_type)

		var vbox = VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 10)
		card_btn.add_child(vbox)

		# Icon Badge
		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(54, 54)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = UIThemeHelper.get_perk_icon(opt)
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)

		# Name
		var name_lbl = Label.new()
		name_lbl.text = opt["name"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
		vbox.add_child(name_lbl)

		# Tag label
		var tag_lbl = Label.new()
		tag_lbl.text = opt.get("tag", "战术升级")
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag_lbl.add_theme_font_size_override("font_size", 12)
		tag_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		vbox.add_child(tag_lbl)

		# Description
		var desc_lbl = Label.new()
		desc_lbl.text = opt["desc"]
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.custom_minimum_size = Vector2(180, 60)
		vbox.add_child(desc_lbl)

		if rpg_mgr == null:
			card_btn.pressed.connect(_on_remote_card_picked.bind(card_index, player_id))
		else:
			card_btn.pressed.connect(_on_card_picked.bind(opt, rpg_mgr))
		card_container.add_child(card_btn)

	# 让手柄/键盘一进来就有焦点; 没有这一句菜单只能用鼠标。
	#
	# 必须 call_deferred, 不能直接调用: 上面 for 循环开头的 queue_free() 要等
	# 到这一帧末尾才真正把旧卡片移出 card_container.get_children(), 此刻树里
	# 仍然是"旧卡片 + 新卡片"并存, 而 _first_focusable() 按树序找第一个可见
	# 可用按钮, 找到的会是马上要被删除的旧卡。main.gd 的 P1->P2 连续弹窗
	# (player_count == 2 时, P1 选完卡在同一次 _on_card_picked 调用栈里直接
	# 弹出 P2 的选择框)正是这种情况 —— 旧的 P1 卡片被抓了焦点, 一帧后节点被
	# 删除, 焦点归零, 手柄/方向键再也无法导航。推迟到旧卡片真正移除之后再找,
	# 就不会抓到一个即将消失的节点。
	call_deferred("_apply_initial_focus")

func _apply_initial_focus() -> void:
	UIThemeHelper.focus_first(self)

func _generate_choices(rpg_mgr: RPGManager, player_id: int) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var branch = rpg_mgr.get_branch(player_id)
	var b_tier = rpg_mgr.get_branch_tier(player_id)

	if branch == "default":
		# === 经典线 (单线) + 已解锁的进阶流派 ===
		#
		# 分支不再无条件摆出来: 这一局拿到了哪张改装图纸, 才有哪条分支
		# (见 branch_blueprints.gd 的文件头)。一张都没拿到时这里只剩经典线的
		# 阶级卡, 下面共享的芯片池会把牌面补满 —— "没解锁"不等于"没得选"。
		var has_any: bool = not GameState.unlocked_branches.is_empty()
		if title_label:
			title_label.text = "突破阶级：选择战车进阶流派" if has_any else "战车改装：经典线强化"
		if subtitle_label:
			subtitle_label.text = "已解锁的进阶流派可在此选择，也可以继续沿经典线强化！" if has_any 				else "沿经典线继续强化，或激活战术芯片。进阶流派需要先找到对应的改装图纸。"

		# 经典线阶级卡。这条线原来是死内容 —— 所有人第一次升级就跳分支了,
		# 而 player_tier 只在 default 分支下有可观测效果 (见
		# GameState.grant_star_tier_reward 的注释)。
		var classic_tier: int = _live_classic_tier(player_id)
		if classic_tier < 3:
			choices.append({
				"type": "classic_tier",
				"icon": "star",
				"name": "经典线 ↑ 阶
(%s)" % CLASSIC_RANKS[classic_tier + 1],
				"tag": "【经典线·第 %d 阶】" % (classic_tier + 1),
				"desc": CLASSIC_TIER_DESC[classic_tier],
			})

		# 已解锁的进阶流派
		for b in GameState.unlocked_branches:
			if BRANCH_CARDS.has(b):
				choices.append((BRANCH_CARDS[b] as Dictionary).duplicate())
	else:
		# In branch: offer Branch Tier 2 promotion + Tactical Perks
		if title_label:
			title_label.text = "战术强化：战备选择 (LEVEL %d)" % rpg_mgr.level
		if subtitle_label:
			subtitle_label.text = "强化当前流派阶级，或激活强力被动战术芯片！"

		# Evolution option
		if b_tier < 2:
			if branch == "speed":
				choices.append({
					"type": "tier_up",
					"icon": "⚡⚡",
					"name": "三管超频暴风\n(Speed Tier 2)",
					"tag": "【流派二阶进化】",
					"desc": "进阶为三管扇形速射机炮，尾翼推进器全开，极限提升机动性！"
				})
			elif branch == "heavy":
				choices.append({
					"type": "tier_up",
					"icon": "💥💥",
					"name": "双联重型要塞炮\n(Heavy Tier 2)",
					"tag": "【流派二阶进化】",
					"desc": "升级为四履带超重底盘与双联重型臼炮，主炮直接粉碎钢铁掩体！"
				})
			elif branch == "train":
				choices.append({
					"type": "tier_up",
					"icon": "🚂🚀",
					"name": "追加火箭重炮车厢\n(Train Tier 2)",
					"tag": "【流派二阶进化】",
					"desc": "列车编队追加第二节【火箭重炮车厢】，周期性发射大范围迫击飞弹！"
				})
			elif branch == "counter":
				choices.append({
					"type": "tier_up",
					"icon": "🛡️⚡",
					"name": "超导破阵要塞\n(Counter Tier 2)",
					"tag": "【流派二阶进化】",
					"desc": "进阶为超导反弹重盾，弹反完美判定窗口扩宽，反弹激光升阶为三向扇面棱镜全反射！"
				})
			elif branch == "trench":
				choices.append({
					"type": "tier_up",
					"icon": "⚔️⚡",
					"name": "超导破阵战壕堡垒\n(Trench Tier 2)",
					"tag": "【流派二阶进化】",
					"desc": "升级为双重高频超导等离子环刃，切割半径大幅扩张，切割等级提升至破钢级，秒杀掩体与敌阵！"
				})


	# === 芯片池对两条路径都生效 ===
	#
	# 这一段原来整个缩在 else (已选分支) 里, 因为 default 那一支必定摆满 5 张
	# 分支卡, 不需要补牌。改成解锁制之后 default 那一支可能只有 1 张 (经典线
	# 阶级卡) 甚至 0 张 (阶级满了还没拿到图纸) —— 不共享的话玩家会看到一个
	# 空的升级界面。
	# Perk pool
	var perk_pool = [
		{
			"type": "perk",
			"id": "titan_plating",
			"icon": "🛡️",
			"name": "钛金复合装甲",
			"tag": "【生命强化】",
			"desc": "加挂钛合金防爆装甲，最大装甲上限永久额外 +2 格！"
		},
		{
			"type": "perk",
			"id": "rapid_loader",
			"icon": "⚡",
			"name": "超频装填机构",
			"tag": "【攻速强化】",
			"desc": "优化炮膛供弹链，射击主炮冷却时间额外缩短 30%！"
		},
		{
			"type": "perk",
			"id": "nitro_booster",
			"icon": "🚀",
			"name": "氮气加速涡轮",
			"tag": "【机动强化】",
			"desc": "加装高压尾气喷射装置，战车行驶速度永久额外 +20%！"
		},
		{
			"type": "perk",
			"id": "nano_repair",
			"icon": "🔧",
			"name": "纳米自愈核心",
			"tag": "【战地自愈】",
			"desc": "装备战地纳米修复机，战车每秒额外自愈 0.5 点装甲值！"
		},
		{
			"type": "perk",
			"id": "high_explosive",
			"icon": "💣",
			"name": "高爆裂变弹头",
			"tag": "【破坏威力】",
			"desc": "弹头装药增强，主炮攻击力与轰炸破坏威力永久额外 +2！"
		},
		{
			"type": "perk",
			"id": "warp_drive",
			"icon": "🌀",
			"name": "空间跃迁引擎",
			"tag": "【虫洞战术】",
			"desc": "进入虫洞折跃后，立刻获得 3.0 秒无敌能量护盾与空间震荡波！"
		},
		{
			"type": "perk",
			"id": "frost_cleats",
			"icon": "❄️",
			"name": "极地防滑钉履带",
			"tag": "【冰面掌控】",
			"desc": "彻底免除冰面失控打滑，在冰地上行驶获得完全抓地操控与 +25% 速度加成！"
		},
		{
			"type": "perk",
			"id": "ferry_artillery",
			"icon": "🚢",
			"name": "浮空驳船重炮",
			"tag": "【平台协同】",
			"desc": "在移动摆渡平台上作战时，主炮攻击力与破坏范围大幅提升 40%！"
		},
		{
			"type": "perk",
			"id": "clay_crusher",
			"icon": "🔨",
			"name": "坚土粉碎者",
			"tag": "【战术破障】",
			"desc": "强化破障弹芯，一发主炮直接秒杀多段耐久的加固硬土块与流沙沙丘！"
		},
		{
			"type": "perk",
			"id": "magnetic_salvage",
			"icon": "🧲",
			"name": "磁力回收核心",
			"tag": "【资源富集】",
			"desc": "战场击毁敌军金币掉落收益提升 30%，战车自动牵引回收战备物资！"
		},
	]

	# Filter perks already at their stack cap (GameState.PERK_MAX_STACKS) --
	# most perks can be picked up to 3 times with diminishing returns
	# (RPGManager.PERK_STACK_CURVE) so the level-up screen keeps offering
	# real choices across a full 15-floor act instead of running out
	# after ~11 picks and falling back to the gold_heal filler for the
	# rest of the run.
	var available_perks = []
	for p in perk_pool:
		var stacks = rpg_mgr.get_perk_stacks(p["id"], player_id)
		var cap = GameState.max_stacks_for_perk(p["id"])
		if stacks >= cap:
			continue
		# 射速类强化在冷却撞到地板之后完全没有效果 (player.gd::_fire() 把
		# 冷却夹在 0.18/0.32 秒)。实测叠满 3 层 rapid_loader 的话 10 级就
		# 到底, 也就是一幕三分之一处往后再抽到它就是废卡 —— 而卡面上写的是
		# "冷却时间额外缩短 30%"。宁可不发这张牌, 也不发一张骗人的牌。
		if p["id"] == "rapid_loader" and rpg_mgr.is_fire_rate_capped(player_id, 0.30):
			continue
		var card = p.duplicate()
		if stacks > 0:
			card["tag"] = "%s [已强化 %d/%d]" % [card["tag"], stacks, cap]
		available_perks.append(card)
	available_perks.shuffle()

	while choices.size() < 3 and available_perks.size() > 0:
		choices.append(available_perks.pop_back())

	# Fallback if perks exhausted
	if choices.size() < 3:
		choices.append({
			"type": "gold_heal",
			"icon": "💰",
			"name": "后勤战略补给箱",
			"tag": "【黄金·全修复】",
			"desc": "立即获得 +150 金币，并完全修复所有受损战车装甲！"
		})

	return choices

## 经典线升一阶。
##
## **两个地方都要写**: GameState.player_tier 是跨幕存档的那一份, 而
## player.upgrade_tier 是这一局战斗里真正被 _shoot() / speed_mult /
## _update_tier_appearance() 读的那一份。main.gd 在开局把前者灌进后者
## (main.gd:3550), 战斗结束再写回去 (main.gd:4380) —— 也就是说只改
## GameState 的话，这一阶要等到下一幕才生效, 而玩家刚刚点的是一张
## "立刻变强"的卡。
##
## 上限 3 和 grant_star_tier_reward 保持一致; 卡面在 tier>=3 时就不发了,
## 这里再夹一次是防手滑 (mini 而不是 assert —— 这是 UI 路径, 不该崩)。
## 经典线当前阶级 —— **优先读战斗中那辆坦克身上的值**。
##
## 这个数有两份: GameState.player_tier 是跨幕存档的那一份, player.upgrade_tier
## 是战斗中真正被 _shoot()/speed_mult 读的那一份。main.gd 开局把前者灌进后者
## (main.gd:3550), 战斗结束再写回去 (main.gd:4380) —— 中间这一整场,
## ⭐ 道具只加 player.upgrade_tier (player.gd 的 STAR 分支), GameState 那份是
## 落后的。只读 GameState 的话, 一个刚吃了星升到 3 阶的玩家还会被发一张
## "经典线 ↑ 阶"的卡, 点下去 mini(3+1,3) 什么也不会发生。
##
## 拿不到坦克实例 (联机客户端的远端卡面、测试里的裸 dialog) 就退回 GameState。
func _live_classic_tier(pid: int) -> int:
	var main = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	if main:
		var tank = main.get("p1_instance") if pid == 1 else main.get("p2_instance")
		if is_instance_valid(tank) and "upgrade_tier" in tank:
			return int(tank.upgrade_tier)
	return GameState.player_tier if pid == 1 else GameState.p2_tier


func _promote_classic_tier(pid: int) -> void:
	var main = get_tree().current_scene
	if pid == 1:
		GameState.player_tier = mini(GameState.player_tier + 1, 3)
	else:
		GameState.p2_tier = mini(GameState.p2_tier + 1, 3)

	var tank = null
	if main:
		tank = main.p1_instance if pid == 1 else main.p2_instance
	if is_instance_valid(tank):
		tank.upgrade_tier = GameState.player_tier if pid == 1 else GameState.p2_tier
		if tank.has_method("_update_tier_appearance"):
			tank._update_tier_appearance()


func _on_card_picked(opt: Dictionary, rpg_mgr: RPGManager) -> void:
	SoundManager.play_button_click(get_tree())
	match opt["type"]:
		"branch":
			# 再验一次解锁状态。卡面本来就只会列出已解锁的分支, 但这条路径
			# **也是联机客户端选卡的落点** (net_apply_remote_upgrade 按索引
			# 回调到这里), 而索引来自对端。卡面生成和效果应用之间隔着一次
			# 网络往返, 中间图纸表理论上可以变。这跟 shop_dialog 把上限检查
			# 从按钮挪进购买路径是同一件事: 门禁要放在真正生效的那一步。
			if not GameState.is_branch_unlocked(str(opt["branch"])):
				return
			rpg_mgr.set_branch(opt["branch"], current_player_id)
		"tier_up":
			rpg_mgr.promote_branch_tier(current_player_id)
		"classic_tier":
			_promote_classic_tier(current_player_id)
		"perk":
			rpg_mgr.add_perk(opt["id"], current_player_id)
		"gold_heal":
			rpg_mgr.add_gold(150)
			var main = get_tree().current_scene
			if main and main.has_method("heal_player"):
				main.heal_player(99)

	visible = false
	option_selected.emit(opt, current_player_id)


## 客户端点了一张卡。这边不应用任何效果 —— 只把索引报给主机, 由主机在
## 自己的 rpg_mgr 上执行 _on_card_picked, 再随战役状态同步回来。
func _on_remote_card_picked(index: int, player_id: int) -> void:
	SoundManager.play_button_click(get_tree())
	visible = false
	get_tree().paused = false
	remote_option_picked.emit(index, player_id)
