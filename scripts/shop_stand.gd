class_name ShopStand
extends Area2D

## 商店房地板上的一个货位 —— 以撒式的"开过去就买"，没有菜单、没有按钮、
## 没有焦点。
##
## 取代的是原来那个全屏 PanelContainer 货架 (18 张卡片 + 购买按钮 + 刷新按钮
## + 离开按钮)。那套是杀戮尖塔的交互: 玩家的坦克停在模态背后不动, 买东西靠
## 点按钮。以撒把商店做成房间本身的一部分 —— 商品摆在地上, 脚下写着价钱,
## 你开上去就成交。
##
## 这里**不重复实现任何商店规则**: 货源、定价、上限判断、发放效果全部调
## shop_dialog.gd 的静态函数。那边是唯一的一份, 抄过来必然分叉 (本仓库在
## build_*.py 上吃过这个亏)。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const ShopDialogRules = preload("res://scripts/shop_dialog.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

const TILE_SIZE := 48.0
const TILE_SCALE := TILE_SIZE / 256.0

## 成交半径。刻意做得比一格小 (18px 而不是 24px): 玩家必须**真的开上去**才
## 成交, 而不是擦着边过就被扣钱。以撒的货位也是这个手感 —— 买错东西是可能的,
## 但不能是"路过就中招"。
const BUY_RADIUS := 18.0

## 靠近多远开始显示商品说明卡。比成交半径大得多, 所以玩家在扣钱之前一定先看到
## 自己要买的是什么 —— 这是"走过去就买"这种无确认交互唯一的防呆。
const HOVER_RADIUS := 74.0

signal purchased(item_id: String, cost: int)

var item_id: String = ""
var cost: int = 0
var sold: bool = false

var _icon: Sprite2D
var _pad: Sprite2D
var _price_label: Label
var _explanation_card: PanelContainer
var _deny_cooldown: float = 0.0
var _bob_t: float = 0.0


func setup(p_item_id: String, p_cost: int, p_sold: bool) -> void:
	item_id = p_item_id
	cost = p_cost
	sold = p_sold


func _ready() -> void:
	add_to_group("shop_stand")

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BUY_RADIUS
	shape.shape = circle
	add_child(shape)

	# 底座。tile_platform 是现成的地块贴图, 压暗当台面用 —— 加新美术要走一整轮
	# Blender 离线渲染 (见 CLAUDE.md "Regenerating art"), 为一个台面不值当。
	_pad = Sprite2D.new()
	_pad.texture = TextureHelper.get_tex("res://assets/sprites/tiles/tile_platform.png")
	_pad.scale = Vector2(TILE_SCALE, TILE_SCALE)
	_pad.modulate = Color(0.72, 0.68, 0.80, 1.0)
	_pad.z_index = 1
	add_child(_pad)

	var data := ShopDialogRules.item_by_id(item_id)

	_icon = Sprite2D.new()
	var tex := TextureHelper.get_tex(str(data.get("icon", "")))
	if tex:
		_icon.texture = tex
		# 图标画得比格子小一圈, 免得盖住底座边缘 —— 玩家要看得出"这是台面上的
		# 一件东西", 而不是"地上有一块贴图"。
		_icon.scale = Vector2(TILE_SCALE * 0.62, TILE_SCALE * 0.62)
	_icon.z_index = 3
	add_child(_icon)

	_price_label = Label.new()
	_price_label.add_theme_font_size_override("font_size", 13)
	_price_label.add_theme_color_override("font_color", Color(0.98, 0.85, 0.35))
	_price_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.06))
	_price_label.add_theme_constant_override("outline_size", 4)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.size = Vector2(96, 18)
	_price_label.position = Vector2(-48, 20)
	_price_label.z_index = 4
	add_child(_price_label)

	# 黏土风格高品质悬浮商品说明卡
	_explanation_card = UIThemeHelper.create_shop_explanation_card()
	_explanation_card.modulate.a = 0.0
	_explanation_card.visible = false
	_update_card_position()
	add_child(_explanation_card)

	body_entered.connect(_on_body_entered)
	_refresh_visuals()


func _update_card_position() -> void:
	if not _explanation_card:
		return
	var card_w := 240.0
	var offset_x := -card_w * 0.5
	var offset_y := -158.0

	# 自适应屏幕边界，避免在顶部或左右贴边时溢出被裁切
	if position.y < 160.0:
		offset_y = 36.0 # 在靠顶部货位时显示在下方
	if position.x < 140.0:
		offset_x = -16.0 # 在最左侧货位时向右偏移
	elif position.x > 480.0:
		offset_x = -card_w + 16.0 # 在最右侧货位时向左偏移

	_explanation_card.position = Vector2(offset_x, offset_y)


func _refresh_visuals() -> void:
	if sold:
		_icon.visible = false
		_price_label.text = "SOLD"
		_price_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
		_pad.modulate = Color(0.42, 0.40, 0.46, 1.0)
	else:
		_icon.visible = true
		_price_label.text = "%d G" % cost
		_pad.modulate = Color(0.72, 0.68, 0.80, 1.0)

	if _explanation_card:
		UIThemeHelper.update_shop_explanation_card(_explanation_card, item_id, cost, sold)


func _process(delta: float) -> void:
	if _deny_cooldown > 0.0:
		_deny_cooldown -= delta

	if not sold:
		# 图标轻微上下浮动, 和地面上的其它东西区分开 —— 静止的图标看着像地贴。
		_bob_t += delta * 2.4
		_icon.position.y = sin(_bob_t) * 2.5

	var near := _nearest_player_distance()

	# 靠近渐显商品说明卡窗口
	var want_alpha := 1.0 if near <= HOVER_RADIUS else 0.0
	if _explanation_card:
		if want_alpha > 0.0:
			UIThemeHelper.update_shop_explanation_card(_explanation_card, item_id, cost, sold)
		_explanation_card.modulate.a = move_toward(_explanation_card.modulate.a, want_alpha, delta * 6.0)
		_explanation_card.visible = (_explanation_card.modulate.a > 0.001)

	# 买不起或达上限时价签变色
	if not sold:
		var can_buy_cond := ShopDialogRules.can_buy_item(item_id)
		var affordable := GameState.gold >= cost
		if not can_buy_cond:
			_price_label.modulate = Color(0.95, 0.55, 0.45)
		elif not affordable:
			_price_label.modulate = Color(1.0, 0.45, 0.45)
		else:
			_price_label.modulate = Color(1.0, 1.0, 1.0)


func _nearest_player_distance() -> float:
	var best := 99999.0
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D and is_instance_valid(p):
			best = minf(best, global_position.distance_to(p.global_position))
	return best


func _on_body_entered(body: Node2D) -> void:
	if sold:
		return
	# 车厢也在 player 组里 (train_carriage.gd::_ready)。让尾巴触发成交的话,
	# 一条火车开过货位会连买好几次 —— 见 CLAUDE.md "player is not the same
	# set as the player tank"。resolve_train_owner() 把车厢回溯到车头,
	# 非火车部件返回 null。
	var owner_tank := TrainFollowHelper.resolve_train_owner(body)
	if owner_tank == null:
		return

	if GameState.gold < cost:
		_deny("金币不足：%s 需要 %d G" % [_short_name(), cost])
		return
	# 上限判断必须在扣钱之前。star_tier 在 tier 3 封顶、perk 到 PERK_MAX_STACKS
	# 封顶、射速撞到冷却地板之后都是**买了等于没买**, 而 grant_perk_stack()
	# 到顶时只是静默返回 false —— 少了这一句就是"扣了全款、什么都没给、还播
	# 了成交音效"。原来的对话框里也踩过同一个坑, 所以那边的注释写得很长。
	if not ShopDialogRules.can_buy_item(item_id):
		_deny("%s 已达上限" % _short_name())
		return

	GameState.gold -= cost
	var msg := ShopDialogRules.apply_item_purchase(item_id)
	sold = true
	_refresh_visuals()

	SoundManager.play_level_up(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	purchased.emit(item_id, cost)

	var main = get_tree().current_scene
	if main and main.has_method("show_toast"):
		main.show_toast(msg if msg != "" else "已购入 %s" % _short_name())


## 商品名去掉括号里的英文, 战场上的 toast 只有一行, 中英双语会被截断。
func _short_name() -> String:
	var n := str(ShopDialogRules.item_by_id(item_id).get("name", item_id))
	var idx := n.find(" (")
	return n.substr(0, idx) if idx > 0 else n


func _deny(msg: String) -> void:
	# 冷却: body_entered 只在进入的那一刻发一次, 但玩家会在货位上来回蹭,
	# 每次重新进入都弹一句 toast 会把提示栏刷爆。
	if _deny_cooldown > 0.0:
		return
	_deny_cooldown = 1.2
	SoundManager.play_hit_steel(get_tree())
	var main = get_tree().current_scene
	if main and main.has_method("show_toast"):
		main.show_toast(msg)

