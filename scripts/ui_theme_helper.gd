class_name UIThemeHelper
extends RefCounted

const TextureHelper = preload("res://scripts/texture_helper.gd")

static var style_btn_normal: StyleBoxTexture
static var style_btn_hover: StyleBoxTexture
static var style_btn_pressed: StyleBoxTexture

static func _init_styles() -> void:
	if style_btn_normal != null:
		return
	
	var tex_n = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_normal.png")
	var tex_h = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_hover.png")
	var tex_p = TextureHelper.get_tex("res://assets/sprites/ui/btn_clay_pressed.png")

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

static func apply_clay_button(btn: Button, dark_text: bool = true) -> void:
	_init_styles()
	if not btn: return
	if style_btn_normal:
		btn.add_theme_stylebox_override("normal", style_btn_normal)
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
