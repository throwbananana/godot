class_name UpgradeSelectionDialog
extends CanvasLayer

const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

signal option_selected(option_data: Dictionary, player_id: int)

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var subtitle_label: Label = $Panel/SubtitleLabel
@onready var card_container: HBoxContainer = $Panel/CardContainer

var cards_data: Array[Dictionary] = []
var current_player_id: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if panel:
		UIThemeHelper.apply_clay_panel(panel)

func show_upgrade_options(rpg_mgr: RPGManager, player_id: int = 1) -> void:
	current_player_id = player_id
	get_tree().paused = true
	visible = true
	SoundManager.play_level_up(get_tree())

	# Clear previous cards
	for child in card_container.get_children():
		child.queue_free()

	cards_data = _generate_choices(rpg_mgr, player_id)
	if player_id == 2:
		title_label.text = "[P2] " + title_label.text

	for opt in cards_data:
		var card_btn = Button.new()
		card_btn.custom_minimum_size = Vector2(210, 240)
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_branch: bool = str(opt.get("type", "")) == "branch"
		UIThemeHelper.apply_clay_upgrade_card(card_btn, is_branch)

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
		# First class promotion choices!
		title_label.text = "突破阶级：选择战车进阶流派"
		subtitle_label.text = "选择你的专属坦克职业，蜕变全新 3D 外观与专属战斗机制！"

		choices.append({
			"type": "branch",
			"branch": "speed",
			"icon": "speed",
			"name": "迅捷斥候型\n(Speed Scout)",
			"tag": "【极速·速射·流沙无阻】",
			"desc": "底盘轻量化流线型蜕变！移速+40%，双联高速针式机炮，无视沙漠流沙减速阻力！"
		})

		choices.append({
			"type": "branch",
			"branch": "heavy",
			"icon": "heavy",
			"name": "重装泰坦型\n(Heavy Juggernaut)",
			"tag": "【装甲·重炮·AoE溅射】",
			"desc": "加装超厚反应装甲！生命上限+4，发射超重型高爆巨炮，命中触发大范围爆炸与击退！"
		})

		choices.append({
			"type": "branch",
			"branch": "train",
			"icon": "train",
			"name": "装甲列车型\n(Armored Train)",
			"tag": "【多节车厢·自动火炮】",
			"desc": "进化为重装铁道车头！后节挂载【全自动火炮车厢】，360度自动索敌消灭后方威胁！"
		})
	else:
		# In branch: offer Branch Tier 2 promotion + Tactical Perks
		title_label.text = "战术强化：战备选择 (LEVEL %d)" % rpg_mgr.level
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

func _on_card_picked(opt: Dictionary, rpg_mgr: RPGManager) -> void:
	SoundManager.play_button_click(get_tree())
	match opt["type"]:
		"branch":
			rpg_mgr.set_branch(opt["branch"], current_player_id)
		"tier_up":
			rpg_mgr.promote_branch_tier(current_player_id)
		"perk":
			rpg_mgr.add_perk(opt["id"], current_player_id)
		"gold_heal":
			rpg_mgr.add_gold(150)
			var main = get_tree().current_scene
			if main and main.has_method("heal_player"):
				main.heal_player(99)

	visible = false
	option_selected.emit(opt, current_player_id)
