class_name PowerUp
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

enum Type { STAR, BOMB, CLOCK, HELMET, SHOVEL, LIFE, MISSILE, TIMED_BOMB, PISTON }

@export var power_up_type: Type = Type.STAR

@onready var sprite: Sprite2D = $Sprite2D

var lifetime: float = 20.0
var flash_timer: float = 0.0

func _ready() -> void:
	add_to_group("powerups")
	body_entered.connect(_on_body_entered)
	_update_texture()

func setup(type: Type) -> void:
	power_up_type = type
	_update_texture()

func _update_texture() -> void:
	if not sprite:
		return
	var tex_name = "star"
	match power_up_type:
		Type.STAR: tex_name = "star"
		Type.BOMB: tex_name = "bomb"
		Type.CLOCK: tex_name = "clock"
		Type.HELMET: tex_name = "helmet"
		Type.SHOVEL: tex_name = "shovel"
		Type.LIFE: tex_name = "life"
		Type.MISSILE: tex_name = "missile_strike"
		Type.TIMED_BOMB: tex_name = "powerup_timed_bomb"
		Type.PISTON: tex_name = "piston_rounds"
	
	var path = "res://assets/sprites/powerups/%s.png" % tex_name
	var tex = TextureHelper.get_tex(path)
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/powerups/%s.svg" % tex_name)
	if tex:
		sprite.texture = tex

func _process(delta: float) -> void:
	lifetime -= delta
	flash_timer += delta * 6.0
	
	# 上下浮动
	position.y += sin(flash_timer) * 0.4
	
	# 快消失时闪烁
	if lifetime < 5.0:
		modulate.a = 0.3 if int(lifetime * 6.0) % 2 == 0 else 1.0
	
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# "player"组里不只有坦克: train 分支的跟随车厢也在里面 (它必须在, 否则
	# 敌方火力不认它)。以前这里是 has_method 判一下就完事, 车厢没有
	# apply_powerup, 于是道具被销毁、音效照播、效果为零 —— 车队越长, 被自己
	# 尾巴白吃掉的道具越多, 而且完全无声。
	# 现在沿 leader_node 解析回车头那辆坦克, 由它来吃。
	var owner_tank := TrainFollowHelper.resolve_train_owner(body)
	if owner_tank == null:
		return   # 不是坦克也不是车队的一部分 -> 道具留在原地, 不被消耗
	owner_tank.apply_powerup(power_up_type)
	SoundManager.play_pickup(get_tree())
	queue_free()
