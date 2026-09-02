class_name TreasureChest
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lock_indicator: Label = $LockIndicator

var is_opened: bool = false
var shake_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("treasure_chest")
	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/treasure_chest.png")
	if tex:
		sprite.texture = tex
	body_entered.connect(_on_body_entered)

	# Initial spawn bounce
	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.10)

func _process(delta: float) -> void:
	if is_opened:
		return

	shake_cooldown = maxf(0.0, shake_cooldown - delta)
	var main = get_tree().current_scene
	var has_key = (main and main.get("has_treasure_key") == true)

	if has_key:
		# Radiant unlocked pulse
		var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.012) * 0.018
		sprite.scale = Vector2(pulse, pulse)
		sprite.modulate = Color(1.2, 1.8, 1.0, 1.0)
		if lock_indicator:
			lock_indicator.text = "[触碰开启]"
			lock_indicator.modulate = Color(0.4, 1.0, 0.5)
	else:
		var pulse = 0.1875 + sin(Time.get_ticks_msec() * 0.005) * 0.008
		sprite.scale = Vector2(pulse, pulse)
		sprite.modulate = Color(1.0, 0.95, 0.85, 1.0)
		if lock_indicator:
			lock_indicator.text = "[需金钥匙]"
			lock_indicator.modulate = Color(1.0, 0.8, 0.3)

func _on_body_entered(body: Node2D) -> void:
	if is_opened:
		return
	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		var main = get_tree().current_scene
		if main and main.get("has_treasure_key") == true:
			_open_chest(main)
		else:
			_denial_shake(main)

func _open_chest(main: Node) -> void:
	is_opened = true
	if lock_indicator:
		lock_indicator.visible = false

	# Victory Sound & Massive Shockwave Burst
	SoundManager.play_level_up(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_teleport_burst(get_parent(), global_position)

	# Open Chest scale pop
	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.26, 0.26), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

	# Deliver Generous Challenge Rewards
	if main:
		if main.has_method("add_gold"):
			main.add_gold(250)
		if main.has_method("add_life"):
			main.add_life(1)
		if main.has_method("show_toast"):
			main.show_toast("🎉 秘宝宝箱开启！获得 +250G 与 +1 额外生命！")

		# Spawn 8 outward flying gold coins
		var coin_scene = load("res://scenes/gold_coin.tscn")
		if coin_scene and main.actors_container:
			for i in range(8):
				var coin = coin_scene.instantiate()
				var angle = i * (2.0 * PI / 8.0)
				var dir = Vector2(cos(angle), sin(angle))
				# _open_chest() 是从 body_entered 里调的, 物理查询 flush 期间——
				# 同款问题见 drifting_supplies.gd::_collect() 的注释。
				coin.position = main.actors_container.to_local(global_position + dir * 28.0)
				main.actors_container.call_deferred("add_child", coin)

func _denial_shake(main: Node) -> void:
	if shake_cooldown > 0.0:
		return
	shake_cooldown = 1.0
	SoundManager.play_hit_steel(get_tree())
	if main and main.has_method("show_toast"):
		main.show_toast("🔒 宝箱紧锁！击破地图隐藏地块或击杀敌军寻找【金钥匙】！")

	var orig_x = sprite.position.x
	var tw = create_tween()
	tw.tween_property(sprite, "position:x", orig_x - 6.0, 0.04)
	tw.tween_property(sprite, "position:x", orig_x + 6.0, 0.04)
	tw.tween_property(sprite, "position:x", orig_x - 4.0, 0.04)
	tw.tween_property(sprite, "position:x", orig_x + 4.0, 0.04)
	tw.tween_property(sprite, "position:x", orig_x, 0.04)
