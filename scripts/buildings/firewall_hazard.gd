class_name FirewallHazard
extends Area2D

## 地面烈焰火墙 (Firewall Hazard)
## 机制：
## 1. 由火墙坦克行驶时在身后铺设，最多维持 10 格火墙队列。
## 2. 任何战车触碰或停留在火墙上时，会受到火焰灼烧伤害 (1 点伤害/次)。
## 3. 4 帧地表火焰跳动动效与灼烧音效。
## 4. 队列溢出或坦克消亡时执行平滑熄灭淡出销毁。

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var flame_textures: Array[Texture2D] = []
var anim_timer: float = 0.0
var burn_tick_timer: float = 0.0
var is_fading: bool = false
var damage: int = 1

func _ready() -> void:
	add_to_group("hazard")
	add_to_group("firewall")
	body_entered.connect(_on_body_entered)

	# 加载 4 帧地表火焰动效
	for f in range(4):
		var p = "res://assets/sprites/buildings/firewall_flame_f%d.png" % f
		var tex = TextureHelper.get_tex(p)
		if tex:
			flame_textures.append(tex)

	if not flame_textures.is_empty() and sprite:
		sprite.texture = flame_textures[0]

	# 出生拔地而起动效
	scale = Vector2(0.1, 0.1)
	var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18)

func _process(delta: float) -> void:
	if is_fading:
		return

	# 1. 火焰动画循环 (10 FPS)
	if not flame_textures.is_empty() and sprite:
		anim_timer += delta * 10.0
		var frame_idx = int(anim_timer) % flame_textures.size()
		sprite.texture = flame_textures[frame_idx]

	# 2. 持续灼烧判定 (每 0.75 秒对内部重叠实体造成灼烧)
	burn_tick_timer += delta
	if burn_tick_timer >= 0.75:
		burn_tick_timer = 0.0
		var overlapping = get_overlapping_bodies()
		for body in overlapping:
			_apply_burn_damage(body)

func _on_body_entered(body: Node2D) -> void:
	if is_fading:
		return
	_apply_burn_damage(body)

func _apply_burn_damage(body: Node2D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return

	# 对玩家坦克或脆弱目标造成火焰伤害
	if body.is_in_group("player") or body.is_in_group("players"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
			SoundManager.play_hit_steel(get_tree())
			VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	elif body.has_method("take_damage") and not body.is_in_group("enemy"):
		body.take_damage(damage)

func fade_out_and_destroy() -> void:
	if is_fading:
		return
	is_fading = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.30)
	tw.chain().tween_callback(queue_free)
