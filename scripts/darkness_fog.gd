class_name DarknessFog
extends ColorRect

const SHADER_CODE = """
shader_type canvas_item;

uniform vec2 p1_pos = vec2(312.0, 580.0);
uniform float p1_radius = 140.0;
uniform bool p1_active = true;

uniform vec2 p2_pos = vec2(312.0, 580.0);
uniform float p2_radius = 140.0;
uniform bool p2_active = false;

uniform vec2 base_pos = vec2(312.0, 600.0);
uniform float base_radius = 115.0;
uniform bool base_active = true;

uniform vec2 extra_lights_pos[32];
uniform float extra_lights_radius[32];
uniform int extra_lights_count = 0;

uniform vec4 ambient_darkness : source_color = vec4(0.015, 0.015, 0.035, 0.96);

void fragment() {
	vec2 local_pos = UV * vec2(624.0, 624.0);
	float total_light = 0.0;

	// Player 1 Vehicle Headlight
	if (p1_active && p1_radius > 0.0) {
		float d1 = distance(local_pos, p1_pos);
		float l1 = 1.0 - smoothstep(p1_radius * 0.35, p1_radius, d1);
		total_light = max(total_light, l1);
	}

	// Player 2 Vehicle Headlight (Co-op)
	if (p2_active && p2_radius > 0.0) {
		float d2 = distance(local_pos, p2_pos);
		float l2 = 1.0 - smoothstep(p2_radius * 0.35, p2_radius, d2);
		total_light = max(total_light, l2);
	}

	// Base Eagle Sanctuary Beacon
	if (base_active && base_radius > 0.0) {
		float db = distance(local_pos, base_pos);
		float lb = 1.0 - smoothstep(base_radius * 0.35, base_radius, db);
		total_light = max(total_light, lb);
	}

	// Dynamic light sources (Explosions, muzzle flashes, falling bombs, lasers)
	for (int i = 0; i < extra_lights_count; i++) {
		if (extra_lights_radius[i] > 0.0) {
			float de = distance(local_pos, extra_lights_pos[i]);
			float le = 1.0 - smoothstep(extra_lights_radius[i] * 0.25, extra_lights_radius[i], de);
			total_light = max(total_light, le);
		}
	}

	total_light = clamp(total_light, 0.0, 1.0);
	float alpha = ambient_darkness.a * (1.0 - total_light);
	COLOR = vec4(ambient_darkness.rgb, alpha);
}
"""

var shader_mat: ShaderMaterial
var p1_ref: Node2D = null
var p2_ref: Node2D = null
var base_ref: Node2D = null

var flashes: Array[Dictionary] = [] # {"pos": Vector2, "radius": float, "duration": float, "elapsed": float}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(624.0, 624.0)
	size = Vector2(624.0, 624.0)
	z_index = 45 # Above tiles & tanks, below HUD
	
	var shader = Shader.new()
	shader.code = SHADER_CODE
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = shader
	material = shader_mat

func setup_trackers(p1: Node2D, p2: Node2D, base: Node2D) -> void:
	p1_ref = p1
	p2_ref = p2
	base_ref = base

func add_flash(pos: Vector2, radius: float = 160.0, duration: float = 0.35) -> void:
	flashes.append({
		"pos": pos,
		"radius": radius,
		"duration": maxf(0.05, duration),
		"elapsed": 0.0
	})

func _process(delta: float) -> void:
	if not shader_mat or not is_inside_tree():
		return

	# 1. Update Player 1 Light
	if p1_ref and is_instance_valid(p1_ref):
		var flicker = sin(Time.get_ticks_msec() * 0.008) * 3.0
		shader_mat.set_shader_parameter("p1_pos", p1_ref.position)
		shader_mat.set_shader_parameter("p1_radius", 145.0 + flicker)
		shader_mat.set_shader_parameter("p1_active", true)
	else:
		shader_mat.set_shader_parameter("p1_active", false)

	# 2. Update Player 2 Light
	if p2_ref and is_instance_valid(p2_ref):
		var flicker = sin(Time.get_ticks_msec() * 0.008 + 1.5) * 3.0
		shader_mat.set_shader_parameter("p2_pos", p2_ref.position)
		shader_mat.set_shader_parameter("p2_radius", 145.0 + flicker)
		shader_mat.set_shader_parameter("p2_active", true)
	else:
		shader_mat.set_shader_parameter("p2_active", false)

	# 3. Update Base Beacon Light
	if base_ref and is_instance_valid(base_ref):
		var beacon_pulse = sin(Time.get_ticks_msec() * 0.004) * 4.0
		shader_mat.set_shader_parameter("base_pos", base_ref.position)
		shader_mat.set_shader_parameter("base_radius", 120.0 + beacon_pulse)
		shader_mat.set_shader_parameter("base_active", true)
	else:
		shader_mat.set_shader_parameter("base_active", false)

	# 4. Collect Extra Dynamic Lights (Flashes, Bullets, Bombs)
	var pos_array: Array[Vector2] = []
	var radius_array: Array[float] = []

	# Update existing flashes
	#
	# 下面 lamp/bomb/bullet 三段收集都写了 pos_array.size() < 16 —— shader 那边
	# extra_lights_pos 是定长 16 的数组, 只有这一段漏写了同样的守卫。一次
	# blast_range=4 的定时炸弹十字火焰会沿 4 个方向各触发若干次
	# VFXAnimator.spawn_shockwave(), 每次都经 add_flash() 塞进 flashes,
	# 短时间内轻松超过 16 条, 不加守卫的话会把一个更长的数组喂给定长 16 的
	# shader uniform。仍然要给*所有*flash 累计 elapsed 并按到期与否过滤,
	# 只是不再把超出 16 条的部分也塞进 pos_array/radius_array。
	var remaining_flashes: Array[Dictionary] = []
	for f in flashes:
		f["elapsed"] += delta
		if f["elapsed"] < f["duration"]:
			if pos_array.size() < 32:
				var progress = f["elapsed"] / f["duration"]
				var cur_radius = f["radius"] * (1.0 - progress * 0.7)
				pos_array.append(f["pos"])
				radius_array.append(cur_radius)
			remaining_flashes.append(f)
	flashes = remaining_flashes

	# Dynamic light for active darkness shroud devices (the device itself emits an eerie pulsating glow)
	var darkness_devices = get_tree().get_nodes_in_group("darkness_device")
	for dev in darkness_devices:
		if is_instance_valid(dev) and dev.get("is_active") != false and pos_array.size() < 32:
			var d_radius = dev.get("light_radius") if dev.get("light_radius") != null else 105.0
			var d_pulse = d_radius + sin(Time.get_ticks_msec() * 0.006 + dev.position.x) * 6.0
			pos_array.append(dev.position)
			radius_array.append(d_pulse)

	# Dynamic light for active street lamps (illumination)
	var street_lamps = get_tree().get_nodes_in_group("street_lamp")
	for lamp in street_lamps:
		if is_instance_valid(lamp) and lamp.get("is_lit") == true and pos_array.size() < 32:
			var l_radius = lamp.get("light_radius") if lamp.get("light_radius") != null else 165.0
			var l_pulse = l_radius + sin(Time.get_ticks_msec() * 0.005 + lamp.position.x) * 4.0
			pos_array.append(lamp.position)
			radius_array.append(l_pulse)

	# Dynamic light for active timed bombs
	var timed_bombs = get_tree().get_nodes_in_group("timed_bomb")
	for bomb in timed_bombs:
		if is_instance_valid(bomb) and pos_array.size() < 32:
			var bomb_pulse = 75.0 + sin(Time.get_ticks_msec() * 0.02) * 15.0
			pos_array.append(bomb.position)
			radius_array.append(bomb_pulse)

	# Dynamic light for active bullets / missiles
	var bullets = get_tree().get_nodes_in_group("bullet")
	for b in bullets:
		if is_instance_valid(b) and pos_array.size() < 32:
			pos_array.append(b.position)
			radius_array.append(42.0)

	# Fill up to 32 slots
	var count = mini(pos_array.size(), 32)
	while pos_array.size() < 32:
		pos_array.append(Vector2.ZERO)
		radius_array.append(0.0)

	shader_mat.set_shader_parameter("extra_lights_count", count)
	shader_mat.set_shader_parameter("extra_lights_pos", pos_array)
	shader_mat.set_shader_parameter("extra_lights_radius", radius_array)
