class_name VFXAnimator
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")

@export var frame_textures: Array[Texture2D] = []
@export var fps: float = 16.0
@export var is_looping: bool = false
@export var auto_destroy: bool = true

var current_frame: int = 0
var timer: float = 0.0
var sprite: Sprite2D

func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	if frame_textures.size() > 0:
		sprite.texture = frame_textures[0]

func _process(delta: float) -> void:
	if frame_textures.is_empty():
		return
	
	timer += delta
	var frame_dur = 1.0 / fps
	if timer >= frame_dur:
		timer -= frame_dur
		current_frame += 1
		if current_frame >= frame_textures.size():
			if is_looping:
				current_frame = 0
			else:
				if auto_destroy:
					queue_free()
				return
		sprite.texture = frame_textures[current_frame]

const SelfScript = preload("res://scripts/vfx_animator.gd")

static func create_anim(tree_parent: Node, pos: Vector2, paths: Array[String], scale_factor: float = 0.1875, fps_val: float = 16.0, rot: float = 0.0) -> Node2D:
	var node = SelfScript.new()
	node.rotation = rot
	node.fps = fps_val
	node.scale = Vector2(scale_factor, scale_factor)
	for p in paths:
		var tex = TextureHelper.get_tex(p)
		if tex:
			node.frame_textures.append(tex)
	tree_parent.add_child(node)
	node.global_position = pos
	return node

static func _notify_darkness_flash(parent: Node, pos: Vector2, radius: float = 140.0, duration: float = 0.25) -> void:
	if not parent or not is_instance_valid(parent): return
	var tree = parent.get_tree()
	if not tree: return
	var main = tree.current_scene
	if main and "darkness_fog_instance" in main and main.darkness_fog_instance and is_instance_valid(main.darkness_fog_instance):
		var local_p = pos - main.game_area.global_position
		main.darkness_fog_instance.add_flash(local_p, radius, duration)

static func spawn_muzzle_flash(parent: Node, pos: Vector2, rot: float) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/muzzle_flash_0.png",
		"res://assets/sprites/effects/muzzle_flash_1.png",
		"res://assets/sprites/effects/muzzle_flash_2.png",
		"res://assets/sprites/effects/muzzle_flash_3.png",
		"res://assets/sprites/effects/muzzle_flash_4.png",
		"res://assets/sprites/effects/muzzle_flash_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 24.0, rot)
	_notify_darkness_flash(parent, pos, 90.0, 0.15)

static func spawn_clay_debris(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/clay_debris_0.png",
		"res://assets/sprites/effects/clay_debris_1.png",
		"res://assets/sprites/effects/clay_debris_2.png",
		"res://assets/sprites/effects/clay_debris_3.png",
		"res://assets/sprites/effects/clay_debris_4.png",
		"res://assets/sprites/effects/clay_debris_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 18.0)

static func spawn_dust_puff(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/dust_puff_0.png",
		"res://assets/sprites/effects/dust_puff_1.png",
		"res://assets/sprites/effects/dust_puff_2.png",
		"res://assets/sprites/effects/dust_puff_3.png",
		"res://assets/sprites/effects/dust_puff_4.png",
		"res://assets/sprites/effects/dust_puff_5.png"
	]
	create_anim(parent, pos, paths, 0.1875, 18.0)

static func spawn_wood_debris(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/wood_debris_f0.png",
		"res://assets/sprites/effects/wood_debris_f1.png",
		"res://assets/sprites/effects/wood_debris_f2.png",
		"res://assets/sprites/effects/wood_debris_f3.png"
	]
	create_anim(parent, pos, paths, 0.22, 18.0)

## 自爆卡车的爆炸 —— 全场最大的一声响。
##
## 刻意比通用爆炸大一圈也慢一点: 它的 AoE 是 84px (1.75 格), 画面得对得上伤害
## 范围, 否则玩家学不会该躲多远。scale 0.34 配 3.9 的渲染画幅, 屏幕上直径约
## 200px, 正好罩住杀伤圈。
##
## fps 给 14 而不是通用爆炸那种更快的节奏 —— 六帧铺开约 0.43 秒, 让"绿核烧尽
## 再塌成毒烟"这段能被看清。快了就只剩一团橘色闪光, 和普通爆炸分不出来。
static func spawn_suicide_blast(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_suicide_blast_f0.png",
		"res://assets/sprites/effects/vfx_suicide_blast_f1.png",
		"res://assets/sprites/effects/vfx_suicide_blast_f2.png",
		"res://assets/sprites/effects/vfx_suicide_blast_f3.png",
		"res://assets/sprites/effects/vfx_suicide_blast_f4.png",
		"res://assets/sprites/effects/vfx_suicide_blast_f5.png"
	]
	var node = create_anim(parent, pos, paths, 0.34, 14.0)
	if node:
		node.z_index = 50
	_notify_darkness_flash(parent, pos, 240.0, 0.45)

static func spawn_shockwave(parent: Node, pos: Vector2) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/shockwave_0.png",
		"res://assets/sprites/effects/shockwave_1.png",
		"res://assets/sprites/effects/shockwave_2.png",
		"res://assets/sprites/effects/shockwave_3.png",
		"res://assets/sprites/effects/shockwave_4.png",
		"res://assets/sprites/effects/shockwave_5.png"
	]
	create_anim(parent, pos, paths, 0.25, 16.0)
	_notify_darkness_flash(parent, pos, 180.0, 0.35)

static func spawn_teleport_burst(parent: Node, pos: Vector2) -> void:
	if not parent or not is_instance_valid(parent):
		return
	spawn_shockwave(parent, pos)
	
	var flare = Node2D.new()
	flare.z_index = 20
	parent.add_child(flare)
	flare.global_position = pos
	
	var ring_spr = Sprite2D.new()
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/shockwave_0.png")
	if tex:
		ring_spr.texture = tex
		ring_spr.modulate = Color(0.85, 0.45, 1.8, 1.0)
		ring_spr.scale = Vector2(0.05, 0.05)
		flare.add_child(ring_spr)
		
		var tw = flare.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring_spr, "scale", Vector2(0.42, 0.42), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring_spr, "modulate:a", 0.0, 0.35)
		tw.tween_property(ring_spr, "rotation", PI * 1.5, 0.35)
		tw.chain().tween_callback(flare.queue_free)
	else:
		flare.queue_free()

static func spawn_wormhole_swirl(parent: Node, pos: Vector2) -> void:
	if not parent or not is_instance_valid(parent):
		return
	var swirl = Node2D.new()
	swirl.z_index = 20
	parent.add_child(swirl)
	swirl.global_position = pos
	
	var spr = Sprite2D.new()
	var tex = TextureHelper.get_tex("res://assets/sprites/effects/shockwave_0.png")
	if tex:
		spr.texture = tex
		spr.modulate = Color(0.4, 1.8, 2.0, 1.0)
		spr.scale = Vector2(0.38, 0.38)
		swirl.add_child(spr)
		
		var tw = swirl.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "scale", Vector2(0.02, 0.02), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(spr, "rotation", -PI * 2.0, 0.22)
		tw.tween_property(spr, "modulate:a", 0.1, 0.22)
		tw.chain().tween_callback(swirl.queue_free)
	else:
		swirl.queue_free()


static func spawn_boss_plasma_nova(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/boss_plasma_nova_0.png",
		"res://assets/sprites/effects/boss_plasma_nova_1.png",
		"res://assets/sprites/effects/boss_plasma_nova_2.png",
		"res://assets/sprites/effects/boss_plasma_nova_3.png",
		"res://assets/sprites/effects/boss_plasma_nova_4.png",
		"res://assets/sprites/effects/boss_plasma_nova_5.png"
	]
	create_anim(parent, pos, paths, 0.28 * scale_mult, 16.0)
	_notify_darkness_flash(parent, pos, 180.0 * scale_mult, 0.35)

static func spawn_boss_frost_nova(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/boss_frost_nova_0.png",
		"res://assets/sprites/effects/boss_frost_nova_1.png",
		"res://assets/sprites/effects/boss_frost_nova_2.png",
		"res://assets/sprites/effects/boss_frost_nova_3.png",
		"res://assets/sprites/effects/boss_frost_nova_4.png",
		"res://assets/sprites/effects/boss_frost_nova_5.png"
	]
	create_anim(parent, pos, paths, 0.28 * scale_mult, 16.0)
	_notify_darkness_flash(parent, pos, 160.0 * scale_mult, 0.30)

static func spawn_tesla_arc_spark(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/tesla_arc_spark_0.png",
		"res://assets/sprites/effects/tesla_arc_spark_1.png",
		"res://assets/sprites/effects/tesla_arc_spark_2.png",
		"res://assets/sprites/effects/tesla_arc_spark_3.png",
		"res://assets/sprites/effects/tesla_arc_spark_4.png",
		"res://assets/sprites/effects/tesla_arc_spark_5.png"
	]
	create_anim(parent, pos, paths, 0.22 * scale_mult, 18.0)
	_notify_darkness_flash(parent, pos, 120.0 * scale_mult, 0.25)

## ---------------------------------------------------------------- 语义化特效
##
## 这六组存在的理由是量出来的, 不是想出来的: 统计过本文件全部 spawn_* 的调用点,
## 12 个函数 240 处调用, 而 spawn_shockwave / spawn_clay_debris / spawn_dust_puff
## 三个就占了 198 处。单是 spawn_shockwave 一个就同时在演 —— 胜利爆发、EMP 瘫痪、
## 雷达扫描、护盾站充能、宝箱开启、跳板弹射、钥匙拾取、虫洞、建筑爆破、鹰旗阵亡。
## 语义完全不同, 画面完全一样, 玩家没法从画面学到刚发生了什么。
##
## 美术侧的区分**不靠颜色**: 世界精灵按 TILE_SCALE=0.1875 画 (256px -> 48px),
## 那个尺寸下色相分辨力很差, 能读出来的是形状语法和运动方向。所以每组换的是
## 几何母题 —— 增益向上飘、伤害向外炸、电子是断续弧段、奖励是四角星芒、建造
## 是向内收敛。详见 tools/build_semantic_vfx.py 顶部。

## 治疗/补给脉冲。向上飘的绿色光点 —— 上行是这套俯视视角里唯一不会和"爆炸
## 向外炸开"混淆的方向, 所以增益类一律走上行。
static func spawn_heal_pulse(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_heal_pulse_f0.png",
		"res://assets/sprites/effects/vfx_heal_pulse_f1.png",
		"res://assets/sprites/effects/vfx_heal_pulse_f2.png",
		"res://assets/sprites/effects/vfx_heal_pulse_f3.png",
		"res://assets/sprites/effects/vfx_heal_pulse_f4.png",
		"res://assets/sprites/effects/vfx_heal_pulse_f5.png"
	]
	create_anim(parent, pos, paths, 0.22 * scale_mult, 15.0)

## EMP / 干扰 / 雷达扫描。断开的青色弧段 —— "断"是它和通用冲击波的关键区别:
## 实心圆环读作物理冲击, 断续弧段读作电流。缺口是剪影级特征, 48px 下仍成立。
static func spawn_emp_pulse(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_emp_pulse_f0.png",
		"res://assets/sprites/effects/vfx_emp_pulse_f1.png",
		"res://assets/sprites/effects/vfx_emp_pulse_f2.png",
		"res://assets/sprites/effects/vfx_emp_pulse_f3.png",
		"res://assets/sprites/effects/vfx_emp_pulse_f4.png",
		"res://assets/sprites/effects/vfx_emp_pulse_f5.png"
	]
	create_anim(parent, pos, paths, 0.26 * scale_mult, 18.0)
	_notify_darkness_flash(parent, pos, 130.0 * scale_mult, 0.22)

## 战利品爆发。四角星芒 —— 靠形状而不是金色承担辨识, 因为金色在本项目里
## 已经是*敌人*词汇 (见 CLAUDE.md 关于 tile_steel 那段)。
static func spawn_reward_burst(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_reward_burst_f0.png",
		"res://assets/sprites/effects/vfx_reward_burst_f1.png",
		"res://assets/sprites/effects/vfx_reward_burst_f2.png",
		"res://assets/sprites/effects/vfx_reward_burst_f3.png",
		"res://assets/sprites/effects/vfx_reward_burst_f4.png",
		"res://assets/sprites/effects/vfx_reward_burst_f5.png"
	]
	create_anim(parent, pos, paths, 0.20 * scale_mult, 16.0)

## 冰霜碎裂。带棱角的碎片, 和 clay_debris 的圆润碎块刻意相反 —— 冰要"锐"。
static func spawn_frost_shatter(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_frost_shatter_f0.png",
		"res://assets/sprites/effects/vfx_frost_shatter_f1.png",
		"res://assets/sprites/effects/vfx_frost_shatter_f2.png",
		"res://assets/sprites/effects/vfx_frost_shatter_f3.png",
		"res://assets/sprites/effects/vfx_frost_shatter_f4.png",
		"res://assets/sprites/effects/vfx_frost_shatter_f5.png"
	]
	create_anim(parent, pos, paths, 0.22 * scale_mult, 17.0)

## 破土喷发。土丘鼓起再塌成抛飞的土块 —— SANDWORM 钻地/破土专用。
static func spawn_sand_burst(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_sand_burst_f0.png",
		"res://assets/sprites/effects/vfx_sand_burst_f1.png",
		"res://assets/sprites/effects/vfx_sand_burst_f2.png",
		"res://assets/sprites/effects/vfx_sand_burst_f3.png",
		"res://assets/sprites/effects/vfx_sand_burst_f4.png",
		"res://assets/sprites/effects/vfx_sand_burst_f5.png"
	]
	create_anim(parent, pos, paths, 0.26 * scale_mult, 16.0)

## 建筑落成。**唯一向内收敛的一组** —— 别的都向外扩散并消散, 它末帧最实,
## 因为"东西被造出来了"这件事要靠收束感传达。别拿爆炸那条消散断言套它。
static func spawn_build_assemble(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_build_assemble_f0.png",
		"res://assets/sprites/effects/vfx_build_assemble_f1.png",
		"res://assets/sprites/effects/vfx_build_assemble_f2.png",
		"res://assets/sprites/effects/vfx_build_assemble_f3.png",
		"res://assets/sprites/effects/vfx_build_assemble_f4.png",
		"res://assets/sprites/effects/vfx_build_assemble_f5.png"
	]
	create_anim(parent, pos, paths, 0.24 * scale_mult, 16.0)

static func spawn_toxic_splash(parent: Node, pos: Vector2, scale_mult: float = 1.0) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/toxic_splash_0.png",
		"res://assets/sprites/effects/toxic_splash_1.png",
		"res://assets/sprites/effects/toxic_splash_2.png",
		"res://assets/sprites/effects/toxic_splash_3.png",
		"res://assets/sprites/effects/toxic_splash_4.png",
		"res://assets/sprites/effects/toxic_splash_5.png"
	]
	create_anim(parent, pos, paths, 0.24 * scale_mult, 16.0)


