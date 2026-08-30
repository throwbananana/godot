class_name GoldCoin
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

@export var value: int = 25
@onready var sprite: Sprite2D = $Sprite2D

var lifetime: float = 25.0
## 没有 magnetic_salvage 战术芯片时基础磁吸为 0 —— 该芯片的描述就是
## "战车自动牵引回收战备物资", 磁吸应该是它给的能力, 不是每个人白送的。
## 之前这里是 120.0 恒定生效, 芯片只是在这基础上加成, 于是"开局就有磁铁"
## 和"买了资源芯片"在手感上几乎没区别, 拾取判定形同虚设。
var magnet_range: float = 0.0
var move_speed: float = 0.0

func _ready() -> void:
	add_to_group("collectibles")
	var tex = TextureHelper.get_tex("res://assets/sprites/powerups/gold_coin.png")
	if tex: sprite.texture = tex
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	sprite.rotation += delta * 4.0
	
	# 磁吸追踪玩家 (结合 magnetic_salvage 战术芯片)
	var main = get_tree().current_scene
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p is Node2D:
			var effective_range = magnet_range
			if main and main.rpg_mgr and ("player_id" in p):
				effective_range += main.rpg_mgr.get_perk_value("magnetic_salvage", 130.0, p.player_id)
			var dist = global_position.distance_to(p.global_position)
			if dist < effective_range:
				move_speed = move_toward(move_speed, 540.0, 1600.0 * delta)
				var dir = (p.global_position - global_position).normalized()
				position += dir * move_speed * delta
				break

	if lifetime < 4.0:
		modulate.a = 0.4 if int(lifetime * 8.0) % 2 == 0 else 1.0
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var main = get_tree().current_scene
		var final_val = value
		# 车厢也在"player"组里但没有 player_id, 直接读会让 magnetic_salvage
		# 的加成在"金币被尾巴捡到"时静默消失。先解析回车头那辆坦克。
		var picker := TrainFollowHelper.resolve_train_owner(body)
		if main and main.rpg_mgr and picker and ("player_id" in picker):
			final_val = int(float(value) * (1.0 + main.rpg_mgr.get_perk_value("magnetic_salvage", 0.35, picker.player_id)))
		if main and main.has_method("add_gold"):
			main.add_gold(final_val)
		SoundManager.play_pickup(get_tree())
		queue_free()
