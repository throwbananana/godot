class_name DefenseTurret
extends StaticBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

@export var max_health: int = 8
@export var attack_range: float = 220.0
@export var fire_interval: float = 0.65

## 无目标时的待机扫描。
##
## 原来没有目标时 `gun_sprite.rotation` 一行都不写, 炮管就**永远定格在最后一次
## 交战的朝向**上。炮塔是玩家最常放下的建筑 (商店 80G, 热键第一位), 一排朝向
## 各异、纹丝不动的炮管读起来像是坏了, 而不像在警戒。
##
## 扫描只在四个基本方向之间轮转, 不停在斜角 —— 沿用下面 _physics_process 里
## 那条规矩: 这个游戏里所有坦克和子弹都只上下左右, 自动炮塔不能是唯一一个
## 瞄自由角度的东西。转场过程是平滑的 (会路过斜角), 但**开火只发生在有目标的
## 分支里**, 那一支是硬置朝向的, 所以不存在斜着开火的可能。
const IDLE_SCAN_INTERVAL := 1.5
const IDLE_TURN_SPEED := 2.2
const IDLE_CARDINALS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

## 起始朝向逐座错开一格, 否则并排几座会像仪仗队一样同步转。
##
## 用静态计数器而不是 randi(): 每日挑战在 main.gd::start_game() 里给全局 RNG
## 播了种, 之后地图生成和敌人 roll 一路都在这条流上取数 —— 在 _ready() 里随手
## 取一个数会让当天所有人的 run 分叉。explosion.gd 轮转爆炸差分、
## sprite_idle_anim.gd 错开起始帧, 都是同一个理由。
static var _scan_stagger: int = 0

var current_health: int = 8
var fire_timer: float = 0.0
var target_enemy: Node2D = null
var idle_scan_idx: int = 0
var idle_scan_timer: float = 0.0

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var gun_sprite: Sprite2D = $GunSprite
# 这里原来还有一行 `@onready var range_area: Area2D = $RangeArea`。
# defense_turret.tscn 里**根本没有 RangeArea 这个节点** (只有 BaseSprite /
# GunSprite / CollisionShape2D), 所以它每放下一座炮塔就往日志里报一次
# "Node not found", 而这个变量全项目没有任何地方读过 —— 索敌走的是
# _find_nearest_target() 遍历 enemies 组 + attack_range 距离判断, 不是 Area2D。
# 删掉的是一条死引用, 不是功能。

var bullet_scene: PackedScene
var explosion_scene: PackedScene

func _ready() -> void:
	GameState.discover_encyclopedia_entry("bld_turret")
	# 外观差分 (通用战损贴花 + 战区覆盖层)。延迟调用: 有的建筑在 _ready() 里
	# 才创建 sprite / 才按 rpg_mgr 改 max_health, 立即调会读到还没成形的状态。
	BuildingSkin.attach.call_deferred(self)
	add_to_group("buildings")
	add_to_group("steel")
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		max_health = int(max_health * main.rpg_mgr.get_building_hp_mult())
	current_health = max_health
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")

	idle_scan_idx = _scan_stagger % IDLE_CARDINALS.size()
	_scan_stagger += 1

	var b_tex = TextureHelper.get_tex("res://assets/sprites/buildings/turret_base.png")
	var g_tex = TextureHelper.get_tex("res://assets/sprites/buildings/turret_gun.png")
	if b_tex: base_sprite.texture = b_tex
	if g_tex: gun_sprite.texture = g_tex

func _physics_process(delta: float) -> void:
	_find_nearest_target()
	
	if target_enemy and is_instance_valid(target_enemy):
		# Snap to whichever cardinal axis currently dominates toward the
		# target -- every other tank/bullet in this game only ever moves or
		# aims up/down/left/right, so the auto-turret can't be the one
		# exception that tracks a free diagonal angle.
		var to_target = target_enemy.global_position - global_position
		var target_dir = Vector2.RIGHT if to_target.x > 0.0 else Vector2.LEFT
		if absf(to_target.y) > absf(to_target.x):
			target_dir = Vector2.DOWN if to_target.y > 0.0 else Vector2.UP
		gun_sprite.rotation = target_dir.angle() + PI / 2.0
		
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = fire_interval
			_shoot(target_dir)
	else:
		fire_timer = maxf(0.0, fire_timer - delta)
		_idle_scan(delta)

## 无目标时在四个基本方向之间缓慢轮转, 见 IDLE_SCAN_INTERVAL 的注释。
##
## 刻意留在 _physics_process 里而不是改用 Tween 驱动: 联机时客户端上的炮塔是
## SCENE_NODE 傀儡, net_puppet.gd 会把 _process 和 _physics_process 一起关掉,
## 所以那边的炮管本来就不会瞄准 (瞄准也在这个函数所在的分支里)。待机扫描跟着
## 同一条路径走, 行为和现状完全一致; 改成 Tween 反而会造出新的分歧 —— 主机正
## 瞄着敌人打, 客户端上那座却在自顾自地扫。
func _idle_scan(delta: float) -> void:
	if not is_instance_valid(gun_sprite):
		return
	idle_scan_timer -= delta
	if idle_scan_timer <= 0.0:
		idle_scan_timer = IDLE_SCAN_INTERVAL
		idle_scan_idx = (idle_scan_idx + 1) % IDLE_CARDINALS.size()
	var want: float = (IDLE_CARDINALS[idle_scan_idx] as Vector2).angle() + PI / 2.0
	gun_sprite.rotation = rotate_toward(gun_sprite.rotation, want, IDLE_TURN_SPEED * delta)

func _find_nearest_target() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest_dist = attack_range
	target_enemy = null
	
	for e in enemies:
		if is_instance_valid(e):
			var dist = global_position.distance_to(e.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				target_enemy = e

func _shoot(dir: Vector2) -> void:
	if not bullet_scene:
		return
	var bullet = bullet_scene.instantiate()
	bullet.direction = dir
	bullet.speed = 520.0
	bullet.shooter = self
	bullet.shooter_type = "player"
	get_parent().add_child(bullet)
	var muzzle_pos = global_position + dir * 26.0
	bullet.global_position = muzzle_pos
	SoundManager.play_shot(get_tree())

	# 枪口后坐力与火花
	var tw = create_tween()
	tw.tween_property(gun_sprite, "position", -dir * 3.0, 0.04)
	tw.tween_property(gun_sprite, "position", Vector2.ZERO, 0.08)
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, gun_sprite.rotation)

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	var tween = create_tween()
	tween.tween_property(base_sprite, "modulate", Color(0.3, 2.0, 0.5), 0.1)
	tween.tween_property(base_sprite, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func take_damage(amount: int) -> void:
	current_health -= amount
	var tween = create_tween()
	tween.tween_property(base_sprite, "modulate", Color(2.5, 0.5, 0.5), 0.08)
	tween.tween_property(base_sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)
	if current_health <= 0:
		_destroy()

func _destroy() -> void:
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	queue_free()
