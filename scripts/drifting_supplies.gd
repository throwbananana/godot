class_name DriftingSupplies
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var is_opened: bool = false
var bob_phase: float = 0.0
var base_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("drifting_supplies")
	add_to_group("collectibles")
	bob_phase = randf() * TAU # desync multiple crates so they don't bob in lockstep
	base_pos = position

	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/drifting_supplies.png")
	if tex and sprite:
		sprite.texture = tex
	body_entered.connect(_on_body_entered)

	scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _process(delta: float) -> void:
	if is_opened:
		return
	# Gentle drift-on-water bob + sway -- purely cosmetic, the crate's actual
	# grid position (and its walkable "treated as ground" cell) never moves,
	# only the sprite offset does.
	bob_phase += delta * 1.6
	position = base_pos + Vector2(sin(bob_phase * 0.6) * 3.0, sin(bob_phase) * 2.5)
	if sprite:
		sprite.rotation = sin(bob_phase * 0.7) * 0.10

func _on_body_entered(body: Node2D) -> void:
	if is_opened:
		return
	if body.is_in_group("player") or body.is_in_group("p1") or body.is_in_group("p2"):
		_collect()

func _collect() -> void:
	is_opened = true
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	SoundManager.play_pickup(get_tree())
	VFXAnimator.spawn_teleport_burst(get_parent(), global_position)

	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.26, 0.26), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)

	var main = get_tree().current_scene
	if main:
		var gold_amt = randi_range(40, 80)
		var xp_amt = randi_range(20, 45)
		if main.has_method("add_gold"):
			main.add_gold(gold_amt)
		if main.rpg_mgr:
			main.rpg_mgr.add_xp(xp_amt)
		if main.has_method("show_toast"):
			main.show_toast("打捞漂流物资！+%dG & +%d XP！" % [gold_amt, xp_amt])

		var coin_scene = load("res://scenes/gold_coin.tscn")
		if coin_scene and main.actors_container:
			for i in range(4):
				var coin = coin_scene.instantiate()
				var angle = i * (2.0 * PI / 4.0)
				var dir = Vector2(cos(angle), sin(angle))
				main.actors_container.add_child(coin)
				coin.global_position = global_position + dir * 22.0
