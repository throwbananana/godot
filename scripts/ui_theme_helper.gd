class_name UIThemeHelper
extends RefCounted

const TextureHelper = preload("res://scripts/texture_helper.gd")

static var style_btn_normal: StyleBoxTexture
static var style_btn_hover: StyleBoxTexture
static var style_btn_pressed: StyleBoxTexture
static var style_btn_disabled: StyleBoxTexture

static func _init_styles() -> void:
	if style_btn_normal != null:
		return
	
	var tex_n = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_normal.png")
	var tex_h = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_hover.png")
	var tex_p = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_pressed.png")
	var tex_d = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_disabled.png")

	if tex_n:
		style_btn_normal = StyleBoxTexture.new()
		style_btn_normal.texture = tex_n
		style_btn_normal.texture_margin_left = 18
		style_btn_normal.texture_margin_right = 18
		style_btn_normal.texture_margin_top = 14
		style_btn_normal.texture_margin_bottom = 14
		style_btn_normal.content_margin_left = 12
		style_btn_normal.content_margin_right = 12
		style_btn_normal.content_margin_top = 8
		style_btn_normal.content_margin_bottom = 8

	if tex_h:
		style_btn_hover = StyleBoxTexture.new()
		style_btn_hover.texture = tex_h
		style_btn_hover.texture_margin_left = 18
		style_btn_hover.texture_margin_right = 18
		style_btn_hover.texture_margin_top = 14
		style_btn_hover.texture_margin_bottom = 14
		style_btn_hover.content_margin_left = 12
		style_btn_hover.content_margin_right = 12
		style_btn_hover.content_margin_top = 8
		style_btn_hover.content_margin_bottom = 8

	if tex_p:
		style_btn_pressed = StyleBoxTexture.new()
		style_btn_pressed.texture = tex_p
		style_btn_pressed.texture_margin_left = 18
		style_btn_pressed.texture_margin_right = 18
		style_btn_pressed.texture_margin_top = 14
		style_btn_pressed.texture_margin_bottom = 14
		style_btn_pressed.content_margin_left = 12
		style_btn_pressed.content_margin_right = 12
		style_btn_pressed.content_margin_top = 10
		style_btn_pressed.content_margin_bottom = 6

	if tex_d:
		style_btn_disabled = StyleBoxTexture.new()
		style_btn_disabled.texture = tex_d
		style_btn_disabled.texture_margin_left = 18
		style_btn_disabled.texture_margin_right = 18
		style_btn_disabled.texture_margin_top = 14
		style_btn_disabled.texture_margin_bottom = 14
		style_btn_disabled.content_margin_left = 12
		style_btn_disabled.content_margin_right = 12
		style_btn_disabled.content_margin_top = 8
		style_btn_disabled.content_margin_bottom = 8

static func apply_clay_button(btn: Button, dark_text: bool = true) -> void:
	_init_styles()
	if not btn: return
	if style_btn_normal:
		btn.add_theme_stylebox_override("normal", style_btn_normal)
	if style_btn_disabled:
		btn.add_theme_stylebox_override("disabled", style_btn_disabled)
	elif style_btn_normal:
		btn.add_theme_stylebox_override("disabled", style_btn_normal)
	if style_btn_hover:
		btn.add_theme_stylebox_override("hover", style_btn_hover)
		btn.add_theme_stylebox_override("focus", style_btn_hover)
	if style_btn_pressed:
		btn.add_theme_stylebox_override("pressed", style_btn_pressed)
	
	if dark_text:
		btn.add_theme_color_override("font_color", Color(0.2, 0.16, 0.12, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.3, 0.15, 0.1, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.2, 0.16, 0.12, 1.0))

static func apply_clay_panel(panel: PanelContainer, bg_color: Color = Color(0.18, 0.15, 0.20, 0.92), corner_radius: int = 14) -> void:
	if not panel: return
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.38, 0.32, 0.38, 0.95)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)

static func apply_clay_progressbar(bar: ProgressBar, fill_color: Color = Color(0.35, 0.82, 0.95, 1.0)) -> void:
	if not bar: return
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.12, 0.16, 0.9)
	bg.corner_radius_top_left = 5
	bg.corner_radius_top_right = 5
	bg.corner_radius_bottom_left = 5
	bg.corner_radius_bottom_right = 5
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.28, 0.24, 0.30, 0.8)
	bar.add_theme_stylebox_override("background", bg)

	var fill = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = 5
	fill.corner_radius_top_right = 5
	fill.corner_radius_bottom_left = 5
	fill.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("fill", fill)
