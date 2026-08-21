class_name ShopDialog
extends PanelContainer

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

signal closed

@onready var gold_label: Label = $VBox/Header/HBox/GoldLabel
@onready var diorama_rect: TextureRect = $VBox/Header/DioramaRect
@onready var items_grid: GridContainer = $VBox/Scroll/ItemsGrid
@onready var btn_reroll: Button = $VBox/Actions/RerollButton
@onready var btn_leave: Button = $VBox/Actions/LeaveButton
@onready var toast_label: Label = $VBox/ToastLabel

var current_shop_items: Array[Dictionary] = []
var reroll_cost: int = 20

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(self, Color(0.14, 0.12, 0.16, 0.98), 16)
	UIThemeHelper.apply_clay_button(btn_reroll)
	UIThemeHelper.apply_clay_button(btn_leave)

	btn_reroll.pressed.connect(_on_reroll_pressed)
	btn_leave.pressed.connect(_on_leave_pressed)

	var d_tex = TextureHelper.get_tex("res://assets/sprites/ui/diorama_shop.png")
	if d_tex and diorama_rect:
		diorama_rect.texture = d_tex

func setup_shop() -> void:
	visible = true
	_generate_shop_inventory()
	_update_ui()

func _update_ui() -> void:
	gold_label.text = "💰 YOUR GOLD: %d G" % GameState.gold
	btn_reroll.text = "🔄 刷新货架 (Reroll %dG)" % reroll_cost
	btn_reroll.disabled = (GameState.gold < reroll_cost)
	_render_item_cards()

func _generate_shop_inventory() -> void:
	current_shop_items.clear()
	var all_items: Array[Dictionary] = [
		{
			"id": "star_tier",
			"name": "⭐ 战车升阶模块 (Star Upgrade)",
			"desc": "提升战车阶级 (Tier Up)，增强火力与射击发数",
			"cost": 95,
			"icon": "res://assets/sprites/powerups/star.png",
			"category": "WEAPON"
		},
		{
			"id": "heavy_armor",
			"name": "🛡️ 强化装甲钢板 (Armor Plating)",
			"desc": "+1 战车最大装甲上限 (Max HP +1)",
			"cost": 65,
			"icon": "res://assets/sprites/powerups/helmet.png",
			"category": "HULL"
		},
		{
			"id": "autoloader",
			"name": "⚡ 自动装填机构 (Autoloader)",
			"desc": "+10% 战车基础装填速度 (Fire Rate +10%)",
			"cost": 70,
			"icon": "res://assets/sprites/ui/badge_laser.png",
			"category": "FIREPOWER"
		},
		{
			"id": "turbo_engine",
			"name": "🏎️ 涡轮增压引擎 (Turbo Engine)",
			"desc": "+6% 战车最高机动巡航航速 (Speed +6%)",
			"cost": 55,
			"icon": "res://assets/sprites/powerups/clock.png",
			"category": "MOBILITY"
		},
		{
			"id": "extra_life",
			"name": "❤️ 备用坦克增援 (Reserve Tank)",
			"desc": "+1 出战备用坦克生命 (Extra Life +1)",
			"cost": 85,
			"icon": "res://assets/sprites/powerups/life.png",
			"category": "SUPPORT"
		},
		{
			"id": "steel_shovel",
			"name": "⛏️ 基地全铁化加固 (Steel Reinforce)",
			"desc": "+1 基地防线工程学等级 (Base Defense Level +1)",
			"cost": 50,
			"icon": "res://assets/sprites/powerups/shovel.png",
			"category": "BASE"
		},
		{
			"id": "plasma_mod",
			"name": "💥 穿甲高爆重弹 (Armor Piercer)",
			"desc": "+1 永久主炮基础杀伤力 (ATK Bonus +1)",
			"cost": 80,
			"icon": "res://assets/sprites/effects/bullet_plasma.png",
			"category": "WEAPON"
		},
		{
			"id": "landmine_crate",
			"name": "💣 战术反坦克地雷包 (Mine Crate)",
			"desc": "解锁布设反坦克地雷战术，+50 战役经验 (50 XP)",
			"cost": 45,
			"icon": "res://assets/sprites/powerups/landmine_prop.png",
			"category": "TACTICAL"
		}
	]

	all_items.shuffle()
	for i in range(min(6, all_items.size())):
		var it = all_items[i].duplicate()
		it["sold_out"] = false
		current_shop_items.append(it)

func _can_buy_item(item_id: String) -> bool:
	if item_id == "star_tier":
		return GameState.player_tier < 3
	return true

func _apply_item_purchase(item_id: String) -> void:
	match item_id:
		"star_tier":
			GameState.player_tier = mini(3, GameState.player_tier + 1)
			_show_toast("战车成功升级至阶级 %d !" % (GameState.player_tier + 1))
		"heavy_armor":
			GameState.max_hp_lvl += 1
			_show_toast("装甲升级！最大生命值 +1")
		"autoloader":
			GameState.fire_rate_lvl += 1
			_show_toast("装填速度大幅提升！")
		"turbo_engine":
			GameState.speed_lvl += 1
			_show_toast("战车引擎输出功率强化！")
		"extra_life":
			GameState.player_lives += 1
			_show_toast("呼叫近卫坦克增援，备用生命 +1！")
		"steel_shovel":
			GameState.builder_lvl += 1
			_show_toast("基地防御掩体强度大幅提升！")
		"plasma_mod":
			GameState.atk_bonus += 1
			_show_toast("主炮口径扩容，攻击力 +1！")
		"landmine_crate":
			GameState.player_xp += 50
			_show_toast("获得地雷战术补给，经验 +50！")

func _render_item_cards() -> void:
	for child in items_grid.get_children():
		child.queue_free()

	for item in current_shop_items:
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(210, 150)
		UIThemeHelper.apply_clay_panel(card, Color(0.20, 0.17, 0.23, 0.95), 8)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)

		# Top row: icon + title
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

		var lbl_title = Label.new()
		lbl_title.text = item["name"]
		lbl_title.add_theme_font_size_override("font_size", 11)
		lbl_title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.45))
		lbl_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(lbl_title)

		# Description
		var lbl_desc = Label.new()
		lbl_desc.text = item["desc"]
		lbl_desc.add_theme_font_size_override("font_size", 10)
		lbl_desc.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
		lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(lbl_desc)

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
			var can_buy_cond = _can_buy_item(item["id"])
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

	GameState.gold -= item["cost"]
	item["sold_out"] = true
	_apply_item_purchase(item["id"])
	SoundManager.play_level_up(get_tree())
	_update_ui()

func _on_reroll_pressed() -> void:
	if GameState.gold < reroll_cost:
		_show_toast("金币不足以刷新货架！")
		return

	GameState.gold -= reroll_cost
	SoundManager.play_pickup(get_tree())
	_generate_shop_inventory()
	_update_ui()
	_show_toast("军火商已更换全新货架！")

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
