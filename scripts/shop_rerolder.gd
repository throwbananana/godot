class_name ShopRerolder
extends Area2D

## 商店房里的刷新机。开上去付费，整排货位换一批。
##
## 原来这是货架对话框上的一个"刷新货架 (Reroll 20G)"按钮。以撒本身没有店内
## 刷新, 但这个游戏的货架是"11 种强化里随机上架"的, 刷新是那条随机性配套的
## 取舍 —— 直接删掉等于让"这次没抽到想要的"变成纯粹的坏运气。所以保留机制,
## 只把交互形式换成和商品一致的"开过去触发"。
##
## 递增计费 (ShopDialog.REROLL_BASE + REROLL_STEP * n) 原样保留, 理由见那边的
## 注释: 固定 20 G 无限刷的话, 中后期一层的收入够刷三十次, 随机上架就成了装饰。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const ShopDialogRules = preload("res://scripts/shop_dialog.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

const TILE_SIZE := 48.0
const TILE_SCALE := TILE_SIZE / 256.0
const TRIGGER_RADIUS := 20.0

signal reroll_requested

var _sprite: Sprite2D
var _label: Label
var _cooldown: float = 0.0


func _ready() -> void:
	add_to_group("shop_rerolder")

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TRIGGER_RADIUS
	shape.shape = circle
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture = TextureHelper.get_tex("res://assets/sprites/map/node_shop.png")
	_sprite.scale = Vector2(TILE_SCALE * 0.85, TILE_SCALE * 0.85)
	_sprite.z_index = 3
	add_child(_sprite)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.70, 0.92, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.06))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(140, 18)
	_label.position = Vector2(-70, 20)
	_label.z_index = 4
	add_child(_label)

	body_entered.connect(_on_body_entered)
	refresh_label()


func refresh_label() -> void:
	var c := GameState.shop_reroll_cost
	_label.text = "换货 %d G" % c
	_label.modulate = Color(1.0, 1.0, 1.0) if GameState.gold >= c else Color(1.0, 0.45, 0.45)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	_sprite.rotation += delta * 0.6
	refresh_label()


func _on_body_entered(body: Node2D) -> void:
	# 冷却: 刷新之后玩家多半还站在机器上, 没有冷却的话只要不挪窝就会被反复扣钱。
	# 商品货位靠"卖掉就没了"天然免疫这个问题, 刷新机不会消失, 所以必须自己挡。
	if _cooldown > 0.0:
		return
	if TrainFollowHelper.resolve_train_owner(body) == null:
		return

	var cost := GameState.shop_reroll_cost
	if GameState.gold < cost:
		_cooldown = 1.2
		SoundManager.play_hit_steel(get_tree())
		var m = get_tree().current_scene
		if m and m.has_method("show_toast"):
			m.show_toast("金币不足以换货 (需要 %d G)" % cost)
		return

	_cooldown = 1.5
	GameState.gold -= cost
	GameState.bump_shop_reroll_cost()
	SoundManager.play_pickup(get_tree())
	reroll_requested.emit()
