class_name FallingBombHazard
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var duration: float = 1.2
@export var bomb_countdown: float = 2.4
@export var blast_range: int = 3
@export var damage: int = 3

const TILE_SIZE_REF = 48.0

var elapsed: float = 0.0
var is_landed: bool = false

var reticle_sprite: Sprite2D
var bomb_sprite: Sprite2D
var shadow_sprite: Sprite2D

# Locked-on reticle radius derived from blast_range so the warning telegraph
# actually covers the bomb's real cross-blast reach instead of a fixed size
# (the old hardcoded 0.50->0.22 shrunk to ~1 tile no matter how many tiles
# the detonation cross actually reaches).
var reticle_start_scale: float = 0.50
var reticle_lock_scale: float = 0.22

var timed_bomb_scene: PackedScene

func _ready() -> void:
	timed_bomb_scene = load("res://scenes/timed_bomb.tscn")

	# reticle_target.png is a 256px render; scale the locked-on ring to the
	# bomb's actual blast diameter (a blast_range-tile cross in each direction)
	# so the warning honestly telegraphs how much ground it's about to cover.
	var danger_diameter_px = float(blast_range) * TILE_SIZE_REF * 2.0
	reticle_lock_scale = clampf(danger_diameter_px / 256.0, 0.22, 1.6)
	reticle_start_scale = reticle_lock_scale + 0.30

	# 1. Warning Reticle
	reticle_sprite = Sprite2D.new()
	var ret_tex = TextureHelper.get_tex("res://assets/sprites/effects/reticle_target.png")
	if ret_tex:
		reticle_sprite.texture = ret_tex
	reticle_sprite.scale = Vector2(reticle_start_scale, reticle_start_scale)
	reticle_sprite.modulate = Color(2.5, 0.5, 0.2, 0.95)
	add_child(reticle_sprite)

	# 2. Expanding Shadow
	shadow_sprite = Sprite2D.new()
	var b_tex = TextureHelper.get_tex("res://assets/sprites/buildings/prop_timed_bomb.png")
	if b_tex:
		shadow_sprite.texture = b_tex
	shadow_sprite.scale = Vector2(0.04, 0.04)
	shadow_sprite.modulate = Color(0.0, 0.0, 0.0, 0.5)
	add_child(shadow_sprite)

	# 3. Plunging Bomb
	bomb_sprite = Sprite2D.new()
	if b_tex:
		bomb_sprite.texture = b_tex
	bomb_sprite.scale = Vector2(0.20, 0.20)
	bomb_sprite.position = Vector2(0.0, -420.0)
	add_child(bomb_sprite)

	SoundManager.play_missile(get_tree())

func _process(delta: float) -> void:
	if is_landed:
		return

	elapsed += delta
	var progress = clampf(elapsed / duration, 0.0, 1.0)

	# Reticle pulses and rotates faster
	reticle_sprite.rotation += delta * 4.0
	var pulse = sin(elapsed * 20.0) * 0.05
	var r_scale = lerpf(reticle_start_scale, reticle_lock_scale, progress) + pulse
	reticle_sprite.scale = Vector2(r_scale, r_scale)
	
	var flash_alarm = 1.0 + sin(elapsed * 28.0) * 0.5
	reticle_sprite.modulate = Color(2.5 * flash_alarm, 0.4, 0.2, 0.95)

	# Descending bomb position with gravity acceleration
	var plunge_t = progress * progress
	bomb_sprite.position.y = lerpf(-420.0, 0.0, plunge_t)
	bomb_sprite.rotation = sin(elapsed * 12.0) * 0.25

	# Shadow expands as bomb nears ground
	var s_scale = lerpf(0.04, 0.20, plunge_t)
	shadow_sprite.scale = Vector2(s_scale, s_scale)
	shadow_sprite.modulate.a = lerpf(0.1, 0.6, progress)

	# Trail smoke puffs
	if int(elapsed * 24.0) % 2 == 0:
		VFXAnimator.spawn_dust_puff(get_parent(), global_position + bomb_sprite.position)

	if elapsed >= duration:
		_land()

func _land() -> void:
	is_landed = true
	reticle_sprite.visible = false
	bomb_sprite.visible = false
	shadow_sprite.visible = false

	# Landing effects
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.18)

	# Instantiate the active Timed Bomb
	if timed_bomb_scene:
		var bomb = timed_bomb_scene.instantiate()
		bomb.position = position
		bomb.countdown = bomb_countdown
		bomb.blast_range = blast_range
		bomb.damage = damage
		get_parent().add_child(bomb)

	queue_free()
