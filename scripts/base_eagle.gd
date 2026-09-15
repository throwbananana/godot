class_name BaseEagle
extends Area2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

signal destroyed

@onready var sprite: Sprite2D = $Sprite2D
var is_destroyed: bool = false

var tex_alive: Texture2D
var tex_damaged: Texture2D
var tex_destroyed: Texture2D
var explosion_scene: PackedScene
var aura_light: PointLight2D = null
var is_iff_active: bool = false
var iff_flag_sprite: Sprite2D = null

## 待机动画 (tools/build_sokpop_animations.py::build_base_eagle_idle)。
##
## 鹰巢是整局的防守核心, 玩家全程盯着它, 而它以前是**一张完全静止的单图** ——
## 战场上水面/传送带/风机/坦克履带全在动, 唯独要保护的那个不动, 读起来像布景
## 而不是"活的、会没的东西"。
##
## 只在**完好状态**下播。受损和被毁是静态图, 因为那两个状态要传达的正是
## "它不动了"; 让残骸继续呼吸会把这个信号毁掉。
var idle_frames: Array[Texture2D] = []
var idle_frame: int = 0
var idle_timer: float = 0.0
var is_damaged: bool = false

## 每帧 0.13 秒 —— 6 帧一个循环约 0.78 秒, 大致是一次平静呼吸的节奏。
## 比一般特效慢得多 (那些是 0.17~0.26 秒播完 6 帧), 因为这是常驻的环境动效,
## 快了会变成持续吸引注意力的干扰。
const IDLE_FRAME_TIME := 0.13

func _ready() -> void:
	add_to_group("base_eagle")
	tex_alive = TextureHelper.get_tex("res://assets/sprites/tiles/base_eagle.png")
	tex_damaged = TextureHelper.get_tex("res://assets/sprites/tiles/base_damaged.png")
	tex_destroyed = TextureHelper.get_tex("res://assets/sprites/tiles/base_destroyed.png")
	explosion_scene = load("res://scenes/explosion.tscn")
	# 待机帧。取不到就退回单图 —— base_eagle.png 一直保留着正是为了这个,
	# 它也是 unified 那边的产物, 不该被动画帧取代。
	idle_frames.clear()
	for i in range(6):
		var f_tex = TextureHelper.get_tex("res://assets/sprites/tiles/base_eagle_f%d.png" % i)
		if f_tex:
			idle_frames.append(f_tex)
	if idle_frames.size() > 0:
		sprite.texture = idle_frames[0]
	elif tex_alive:
		sprite.texture = tex_alive
	set_process(idle_frames.size() > 1)
	_setup_aura_light()
	var main = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	if ("has_iff_flag" in GameState and GameState.has_iff_flag) or (main and main.has_method("is_iff_flag_active") and main.is_iff_flag_active()):
		set_iff_active(true)

func set_iff_active(active: bool) -> void:
	is_iff_active = active
	if is_iff_active:
		if not iff_flag_sprite:
			iff_flag_sprite = Sprite2D.new()
			var flag_tex = TextureHelper.get_tex("res://assets/sprites/powerups/iff_flag.png")
			if flag_tex:
				iff_flag_sprite.texture = flag_tex
			iff_flag_sprite.scale = Vector2(0.15, 0.15)
			iff_flag_sprite.position = Vector2(14.0, -14.0)
			iff_flag_sprite.z_index = 8
			add_child(iff_flag_sprite)
		iff_flag_sprite.visible = true
		if aura_light and is_instance_valid(aura_light):
			aura_light.color = Color(0.35, 1.0, 0.65, 0.95)
	else:
		if iff_flag_sprite:
			iff_flag_sprite.visible = false
		if aura_light and is_instance_valid(aura_light):
			aura_light.color = Color(1.0, 0.85, 0.45, 0.8)

func _setup_aura_light() -> void:
	aura_light = PointLight2D.new()
	aura_light.color = Color(1.0, 0.85, 0.45, 0.8)
	aura_light.energy = 0.85
	
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var g_tex = GradientTexture2D.new()
	g_tex.gradient = grad
	g_tex.fill = GradientTexture2D.FILL_RADIAL
	g_tex.fill_from = Vector2(0.5, 0.5)
	g_tex.fill_to = Vector2(0.5, 0.0)
	g_tex.width = 128
	g_tex.height = 128
	
	aura_light.texture = g_tex
	aura_light.texture_scale = 1.6
	add_child(aura_light)
	
	var tw = create_tween().set_loops()
	tw.tween_property(aura_light, "energy", 1.15, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(aura_light, "energy", 0.75, 1.2).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	if is_destroyed or is_damaged or idle_frames.size() < 2:
		return
	idle_timer += delta
	if idle_timer < IDLE_FRAME_TIME:
		return
	idle_timer -= IDLE_FRAME_TIME
	idle_frame = (idle_frame + 1) % idle_frames.size()
	sprite.texture = idle_frames[idle_frame]

func take_damage_hit() -> void:
	if is_destroyed: return
	# 受损即停待机 —— "它不动了"本身就是这个状态要传达的信息。
	is_damaged = true
	set_process(false)
	if tex_damaged:
		sprite.texture = tex_damaged
	# 挨了一下但还在 —— 走崩落而不是碎屑, 碎屑现在专表"被摧毁"。
	VFXAnimator.spawn_hit_spall(get_parent(), global_position)
	var tw = create_tween()
	tw.tween_property(sprite, "position", Vector2(randf_range(-4, 4), randf_range(-4, 4)), 0.05)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.05)

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	set_process(false)
	if aura_light and is_instance_valid(aura_light):
		aura_light.queue_free()
	if tex_destroyed:
		sprite.texture = tex_destroyed
	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	SoundManager.play_game_over(get_tree())
	destroyed.emit()
