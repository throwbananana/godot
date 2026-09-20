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

## 每次播放的朝向/大小微抖, 让同一个效果连着出现时不像同一枚图章。
##
## 之前除 spawn_muzzle_flash 外的**全部**效果都是轴对齐、固定尺寸播放的, 所以
## 同一种反馈每次都逐像素相同 —— 连打一堵砖墙, 碎屑团一帧不差地重复。
## explosion.gd 早就为这件事准备了三套差分贴图并轮着用, 但那个办法只覆盖了爆炸,
## 剩下二十个效果都还是单一图章。这里用的是更便宜的一招: 不换图, 只把同一张图
## 随播随转一点、缩一点, 视觉上足够打破重复感, 且一张新图都不用渲。
##
## **用轮换游标而不是 randf()**: 每日挑战在 start_game() 里 seed() 了全局 RNG
## 流并全程依赖它确定, 而特效是战斗中触发最频繁的东西之一 —— 在这里抽数会让
## 所有人的当日局面错位, 且不报任何错。同一条规矩见 explosion.gd 的变体游标、
## SoundManager 的噪声变体, 以及 VFXParticles 的发射种子。
const JITTER_ROT := [0.0, 0.21, -0.14, 0.33, -0.27, 0.09, -0.35, 0.17]
const JITTER_SCALE := [1.0, 0.93, 1.08, 0.96, 1.05, 0.90, 1.11, 0.98]
static var _jitter_cursor: int = 0

## 取下一组抖动。返回 [额外旋转, 缩放系数]。
static func _next_jitter() -> Array:
	var i := _jitter_cursor
	_jitter_cursor += 1
	# 两张表长度不同 (8 和 8 会同步循环), 所以错开取: 旋转走 i, 缩放走 i*3,
	# 于是组合周期是 8 而不是"每 8 次完全重复同一对"。
	return [JITTER_ROT[i % JITTER_ROT.size()], JITTER_SCALE[(i * 3) % JITTER_SCALE.size()]]

static func create_anim(tree_parent: Node, pos: Vector2, paths: Array[String], scale_factor: float = 0.1875, fps_val: float = 16.0, rot: float = 0.0, apply_jitter: bool = true) -> Node2D:
	# 抖动在回声**之前**施加, 所以发给客户端的是已经抖好的 rot/scale ——
	# 两端看到的是同一枚。客户端重放时必须传 apply_jitter = false, 否则它会在
	# 主机抖过的值上再抖一次, 两边的同一个特效长得不一样 (而且没有任何报错)。
	var use_rot := rot
	var use_scale := scale_factor
	if apply_jitter:
		var j := _next_jitter()
		use_rot += float(j[0])
		use_scale *= float(j[1])

	var node = SelfScript.new()
	node.rotation = use_rot
	node.fps = fps_val
	node.scale = Vector2(use_scale, use_scale)
	for p in paths:
		var tex = TextureHelper.get_tex(p)
		if tex:
			node.frame_textures.append(tex)
	tree_parent.add_child(node)
	node.global_position = pos
	_net_echo(tree_parent, pos, paths, use_scale, fps_val, use_rot)
	return node

## 把一个方向向量转成贴图朝向。
##
## 传 Vector2.ZERO 表示"没有方向", 返回 0 —— 调用方不需要自己判空。
## 这是 spawn_hit_spall / spawn_ricochet_spark 这类**撞击**特效需要的:
## 它们的美术本来就是偏心构图 (见 CLAUDE.md 里 vfx_hit_spall 的"崩落团偏向
## 一侧 + 同侧冲击弧"), 设计意图就是指示撞击来向 —— 但在此之前 spawn 接口
## 根本没有方向参数, 那份不对称永远指着屏幕的同一边。
static func dir_to_rot(dir: Vector2) -> float:
	if dir.length_squared() < 0.0001:
		return 0.0
	return dir.angle()


## 联机: 把这一次特效回声给客户端。
##
## 全项目的特效都从 create_anim() 走, 所以这里是**唯一**需要挂钩子的地方 ——
## 二十多个 spawn_* 一个都不用改。客户端不跑战斗逻辑, 自己不会产生任何特效,
## 全靠这条回声。
##
## 坐标转成 tree_parent 的局部坐标再发: GameArea 的位置会随窗口分辨率变化
## (见 main.gd::_apply_layout_offset), 两端分辨率不同时全局坐标对不上,
## 特效会整体偏出画面。
static func _net_echo(tree_parent: Node, pos: Vector2, paths: Array[String], scale_factor: float, fps_val: float, rot: float) -> void:
	if tree_parent == null or not tree_parent.is_inside_tree():
		return
	var net = tree_parent.get_node_or_null("/root/Net")
	if net == null:
		return
	var local_pos: Vector2 = pos
	if tree_parent is Node2D:
		local_pos = (tree_parent as Node2D).to_local(pos)
	net.echo_vfx(paths, local_pos, scale_factor, fps_val, rot)

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

## 弹开 / 打不穿。冷钢火星 —— 子弹命中 border / steel / 有壳建筑时用。
##
## 和 spawn_shockwave 的分工是**结果不同**, 不是强度不同: 这个说"你打不动它",
## 冲击波说"它被打没了"。玩家看到之后的下一步动作完全相反 (换目标 vs 继续推进),
## 所以这两件事不能共用一张图。拆分前 spawn_shockwave 的 82 处调用里, 命中
## border/steel/buildings 占 17 处、建筑被摧毁占 10 处, 全是同一个灰环。
static func spawn_ricochet_spark(parent: Node, pos: Vector2, scale_mult: float = 1.0, dir: Vector2 = Vector2.ZERO) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_ricochet_spark_f0.png",
		"res://assets/sprites/effects/vfx_ricochet_spark_f1.png",
		"res://assets/sprites/effects/vfx_ricochet_spark_f2.png",
		"res://assets/sprites/effects/vfx_ricochet_spark_f3.png",
		"res://assets/sprites/effects/vfx_ricochet_spark_f4.png",
		"res://assets/sprites/effects/vfx_ricochet_spark_f5.png"
	]
	# 比别的组快: 火星是瞬时事件, 拖长了会读成"持续燃烧"。
	create_anim(parent, pos, paths, 0.17 * scale_mult, 18.0, dir_to_rot(dir))

## 受伤未死。偏心的崩落团 —— 目标掉血但还站着时用。
##
## 和 spawn_clay_debris 的分工同上: 那个现在专表"被摧毁"。"还能打"和"已经没了"
## 是玩家最需要区分的一对反馈, 拆分前它们是同一张图 (clay_debris 的 74 处调用里
## take_damage 占 14 处、destroy 占 13 处)。
## dir 传"撞击来向的反方向"时, 那团偏心的崩落就朝着子弹飞来的反侧崩 ——
## 这张图本来就是为此画的 (构图刻意偏向一侧并配同侧冲击弧), 只是以前没有
## 参数能把方向送进来。不传就退回原来的固定朝向, 老调用点不受影响。
static func spawn_hit_spall(parent: Node, pos: Vector2, scale_mult: float = 1.0, dir: Vector2 = Vector2.ZERO) -> void:
	var paths: Array[String] = [
		"res://assets/sprites/effects/vfx_hit_spall_f0.png",
		"res://assets/sprites/effects/vfx_hit_spall_f1.png",
		"res://assets/sprites/effects/vfx_hit_spall_f2.png",
		"res://assets/sprites/effects/vfx_hit_spall_f3.png",
		"res://assets/sprites/effects/vfx_hit_spall_f4.png",
		"res://assets/sprites/effects/vfx_hit_spall_f5.png"
	]
	create_anim(parent, pos, paths, 0.20 * scale_mult, 15.0, dir_to_rot(dir))

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


