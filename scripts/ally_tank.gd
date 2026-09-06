class_name AllyTank
extends CharacterBody2D

## "escort" 挑战房里要保护的友军单位。
##
## 会自己四处游荡 (跟 enemy.gd 的基础巡逻 AI 同一套写法: 定时随机换向 + 撞到
## 障碍物立刻换向), 射程内有敌人时会转向瞄准并开火——但不会主动追逐或躲避,
## 纯粹是"边走边打", 不会为了追一个跑远的敌人而脱离玩家身边。保护目标本身
## 才是这个挑战模式的机制, 给它一整套追击/闪避 AI 只会分散玩法焦点 (照顾谁
## 去了、谁在打谁), 也会把工作量推到跟一整个新敌人类型一样重。移速刻意比
## 大多数敌人慢 (见 SPEED), 免得玩家一边打怪一边还要满地图追着自己的护送
## 对象跑。
##
## 加入 "player" 组是让它免费吃到一整套既有系统, 而不是重新发明一遍:
##   - enemy.gd::_find_target() 直接会把它当成候选目标, 敌人自然会朝它开火/推进,
##     不用另写一套"敌人该不该打友军"的判定。
##   - bullet.gd 里 "(player/p1/p2) and shooter_type==enemy -> take_damage" 那条
##     分支天然覆盖它, 不用在 bullet.gd 里再加一个阵营分支。它自己开火的子弹
##     同样标 shooter_type="player", 命中敌人会走 "(enemy/enemies) and
##     shooter_type==player -> take_damage" 那条分支, 不用另开一套判定;
##     万一误伤到真玩家, bullet.gd 会因为 shooter (它自己) 没有 player_id
##     而静默销毁子弹、不施加友伤僵直——跟 defense_turret.gd 的自动炮塔子弹
##     是一模一样的既有兜底路径, 不是新写的特例。
##   - KineticPushHelper 的推力/挤压判定同样天然把它当作有效目标。
##   - _update_tree_transparency() 会在它站进树丛时正确淡出遮挡。
## 唯一的副作用 (可接受): 电力/金币拾取物检测 body.is_in_group("player") 时会
## 认为它是候选者, 但它没有 apply_powerup()/player_id, 这两处既有代码已经用
## has_method() / TrainFollowHelper.resolve_train_owner() 兜底过 (见 CLAUDE.md
## "player 不等于玩家坦克"一节), 表现是道具留在地上不消失, 不会报错也不会
## 被偷偷吃掉。

signal ally_destroyed

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

const HEALTHY_COLOR := Color(0.35, 2.2, 0.65, 1.0) # 醒目翠绿, 跟玩家/敌人的配色都不撞
const CRITICAL_COLOR := Color(2.2, 0.55, 0.35, 1.0) # 残血偏警示红橙
const SPEED := 42.0 # 比大多数敌人慢 (enemy_basic 是 65), 玩家不用满地图追它
const TREAD_PX_PER_FRAME := 8.0 # 跟 enemy.gd/player.gd 同一个值, 履带滚动速率保持一致的观感
const FIRE_INTERVAL := 1.6 # 跟基础敌人档位 (1.2~2.0) 同一量级
const FIRE_RANGE := 260.0 # 约 5.4 格, 不是全图索敌——只打"顺路遇到"的敌人
const BULLET_DAMAGE := 1

@onready var sprite: Sprite2D = $Sprite2D

var max_health: int = 6
var health: int = 6
var is_dying: bool = false
var hit_tween: Tween = null

var facing_direction: Vector2 = Vector2.DOWN
var change_dir_timer: float = 0.0
var tank_frames: Array[Texture2D] = []
var current_frame: int = 0
var tread_accum_dist: float = 0.0

var bullet_scene: PackedScene
var fire_timer: float = 0.0

func _ready() -> void:
	health = max_health
	for i in range(6):
		var f_tex = TextureHelper.get_tex("res://assets/sprites/tanks/player_tier0_f%d.png" % i)
		if f_tex:
			tank_frames.append(f_tex)
	if sprite:
		if tank_frames.size() > 0:
			sprite.texture = tank_frames[0]
		sprite.modulate = HEALTHY_COLOR
	rotation = facing_direction.angle() + PI / 2.0
	change_dir_timer = randf_range(1.0, 2.0)
	bullet_scene = load("res://scenes/bullet.tscn")
	fire_timer = randf_range(0.3, 1.0)

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	change_dir_timer -= delta
	if change_dir_timer <= 0.0:
		_choose_new_direction()
		change_dir_timer = randf_range(1.5, 3.5)

	velocity = facing_direction * SPEED
	var collision = move_and_collide(velocity * delta)
	if collision:
		# 撞上推不动的障碍物 (墙/建筑/其他坦克) 立刻换方向, 不要卡在原地抖动——
		# 跟 enemy.gd 的基础巡逻 AI 是同一处理方式。
		_choose_new_direction()

	if tank_frames.size() > 0:
		tread_accum_dist += SPEED * delta
		var f_idx = int(tread_accum_dist / TREAD_PX_PER_FRAME) % tank_frames.size()
		if f_idx != current_frame:
			current_frame = f_idx
			sprite.texture = tank_frames[current_frame]

	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = FIRE_INTERVAL
		var target := _find_nearest_enemy()
		if target:
			var to_target: Vector2 = target.global_position - global_position
			if absf(to_target.x) > absf(to_target.y):
				facing_direction = Vector2.RIGHT if to_target.x > 0.0 else Vector2.LEFT
			else:
				facing_direction = Vector2.DOWN if to_target.y > 0.0 else Vector2.UP
			rotation = facing_direction.angle() + PI / 2.0
			_shoot()

func _choose_new_direction() -> void:
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	facing_direction = dirs[randi() % dirs.size()]
	rotation = facing_direction.angle() + PI / 2.0

## 只在 FIRE_RANGE 内找目标, 而不是索敌全图——它是"边走边打"的护送对象,
## 不是一台追猎坦克, 射程外的敌人交给玩家自己处理。同一个坑见 enemy.gd 的
## 分组单复数漂移: train_carriage.gd 的敌方车厢只挂 "enemies"(复数), 只查
## "enemy"(单数) 会漏掉它们, 所以两个组都要查。
func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := FIRE_RANGE
	for grp in ["enemy", "enemies"]:
		for e in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(e) or not (e is Node2D):
				continue
			var d: float = global_position.distance_to(e.global_position)
			if d <= nearest_dist:
				nearest = e
				nearest_dist = d
	return nearest

func _shoot() -> void:
	if not bullet_scene:
		return
	var b = bullet_scene.instantiate()
	b.direction = facing_direction
	b.speed = 380.0
	b.damage = BULLET_DAMAGE
	b.shooter = self
	b.shooter_type = "player"
	get_parent().add_child(b)
	var muzzle_pos: Vector2 = global_position + facing_direction * 26.0
	b.global_position = muzzle_pos
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

func take_damage(amount: int) -> void:
	if is_dying:
		return
	health -= amount
	_flash_hit()
	_update_health_tint()
	if health <= 0:
		_die()

func _flash_hit() -> void:
	if not sprite:
		return
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	var base_scale = Vector2(0.196, 0.196)
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", base_scale * Vector2(1.3, 0.7), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", base_scale, 0.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## 血量越低越偏警示色——跟 enemy.gd 里 ARMOR 按三档血量切换色调是同一手法,
## 这里连续插值而不是离散三档, 因为友军没有装甲板贴图可以换。
func _update_health_tint() -> void:
	if not sprite:
		return
	var t = clampf(float(health) / float(max_health), 0.0, 1.0)
	sprite.modulate = CRITICAL_COLOR.lerp(HEALTHY_COLOR, t)

func _die() -> void:
	if is_dying:
		return
	is_dying = true
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	if is_inside_tree() and get_tree():
		SoundManager.play_explosion(get_tree())
	ally_destroyed.emit()
	queue_free()
