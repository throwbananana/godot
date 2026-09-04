class_name Explosion
extends Node2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

@onready var sprite: Sprite2D = $Sprite2D

var textures: Array[Texture2D] = []
var current_frame: int = 0
var frame_timer: float = 0.0
var frame_duration: float = 0.055
var light: PointLight2D = null

## 爆炸差分。三套图是同一种火球的三次实例 (换角相位 + 换 wobble 种子, 见
## build_all_sokpop_assets_unified.py 的 EXPLOSION_VARIANTS), 不是三种爆炸。
const VARIANT_PREFIXES := ["explosion", "explosion_v1", "explosion_v2"]

## 轮流取, **不掷随机数**。两个理由:
##
## 1. 每日挑战在 start_game() 里 seed() 了全局 RNG, 之后整场战斗的敌人生成
##    (_request_spawn_enemy) 一直在从那条流里取数 —— 全服同一个种子跑出同一局
##    是这个模式的全部意义。爆炸是战斗中触发最频繁的事件之一, 在这里每次抽一个
##    randi 会让后续所有人的随机序列整体错位, 而且不报任何错。
##    (同 BalanceLog.session_id() 为什么用 ticks 而不是 randi。)
## 2. 轮流比随机**更符合目的**: 差分要解决的是"连着炸三辆车、三团火一模一样"
##    这个观感, 轮流保证相邻的爆炸必定不同, 随机则有 1/3 的概率撞上。
static var _variant_cursor: int = 0

func _ready() -> void:
	var v_idx := _variant_cursor % VARIANT_PREFIXES.size()
	_variant_cursor += 1
	for i in range(6):
		var tex = TextureHelper.get_tex(
			"res://assets/sprites/effects/%s_%d.png" % [VARIANT_PREFIXES[v_idx], i])
		if tex:
			textures.append(tex)
	# 变体图缺失 (没渲/没导入) 就退回基础序列。宁可全场同一朵火球, 也不要没有爆炸。
	if textures.size() < 6:
		textures.clear()
		for i in range(6):
			var tex = TextureHelper.get_tex("res://assets/sprites/effects/explosion_%d.png" % i)
			if tex:
				textures.append(tex)
	if textures.size() > 0:
		sprite.texture = textures[0]
	SoundManager.play_explosion(get_tree())

	_setup_dynamic_light()

	# 夜战闪光必须延到本帧末再打, 不能在 _ready() 里直接读 global_position。
	# _ready() 是在 add_child() 期间跑的, 而所有调用方 (油桶/地雷/子弹/鹰巢/
	# 炮塔/围墙) 都遵循"先入树、再设 global_position"的约定 —— 也就是说
	# _ready() 比赋值早一步, 这时读到的还是默认的 (0,0) 经父级变换的结果。
	# 父级是 GameArea 下的 ActorsContainer, 减掉 game_area.global_position
	# 正好抵消, 于是每一次爆炸都在地图左上角那格点灯, 而不是爆点。
	# call_deferred 排到当前调用栈退完之后, 那时坐标已经赋好了。
	call_deferred("_flash_darkness")

func _setup_dynamic_light() -> void:
	light = PointLight2D.new()
	light.color = Color(1.0, 0.62, 0.22, 1.0)
	light.energy = 1.8
	
	# 程序化生成径向衰减光照贴图
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
	
	light.texture = g_tex
	light.texture_scale = 1.5
	add_child(light)

func _flash_darkness() -> void:
	if not is_inside_tree():
		return
	var main = get_tree().current_scene
	if main and "darkness_fog_instance" in main and main.darkness_fog_instance and is_instance_valid(main.darkness_fog_instance):
		var local_p = global_position - main.game_area.global_position
		main.darkness_fog_instance.add_flash(local_p, 200.0, 0.4)

func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer >= frame_duration:
		frame_timer = 0.0
		current_frame += 1
		if current_frame < textures.size():
			sprite.texture = textures[current_frame]
			if light:
				var progress = float(current_frame) / float(textures.size())
				light.energy = lerp(1.8, 0.0, progress)
				light.texture_scale = lerp(1.5, 2.8, progress)
		else:
			queue_free()
