extends Node2D

@export var radius: float = 180.0
@export var color: Color = Color(0.18, 0.65, 1.0, 0.10)
@export var ring_color: Color = Color(0.25, 0.80, 1.0, 0.55)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.03
	var r = radius * pulse
	# Inner translucent shield zone fill
	draw_circle(Vector2.ZERO, r, color)
	# Outer glowing energy barrier border
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, ring_color, 2.5, true)
	# Inner concentric harmonic ring
	draw_arc(Vector2.ZERO, r * 0.65, 0.0, TAU, 36, Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * 0.35), 1.5, true)
