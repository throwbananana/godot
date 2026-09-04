class_name UIThemeHelper
extends RefCounted

const TextureHelper = preload("res://scripts/texture_helper.gd")

static var style_btn_normal: StyleBoxTexture
static var style_btn_hover: StyleBoxTexture
static var style_btn_pressed: StyleBoxTexture
static var style_btn_disabled: StyleBoxTexture

static var style_card_normal: StyleBoxTexture
static var style_card_hover: StyleBoxTexture
static var style_card_branch: StyleBoxTexture

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

static func _init_card_styles() -> void:
	if style_card_normal != null:
		return
	var tex_cn = TextureHelper.get_tex("res://assets/sprites/ui/ui_card_bg_normal.png")
	var tex_ch = TextureHelper.get_tex("res://assets/sprites/ui/ui_card_bg_hover.png")
	var tex_cb = TextureHelper.get_tex("res://assets/sprites/ui/ui_card_bg_branch.png")

	if tex_cn:
		style_card_normal = StyleBoxTexture.new()
		style_card_normal.texture = tex_cn
		style_card_normal.texture_margin_left = 20
		style_card_normal.texture_margin_right = 20
		style_card_normal.texture_margin_top = 20
		style_card_normal.texture_margin_bottom = 20
		style_card_normal.content_margin_left = 12
		style_card_normal.content_margin_right = 12
		style_card_normal.content_margin_top = 12
		style_card_normal.content_margin_bottom = 12

	if tex_ch:
		style_card_hover = StyleBoxTexture.new()
		style_card_hover.texture = tex_ch
		style_card_hover.texture_margin_left = 20
		style_card_hover.texture_margin_right = 20
		style_card_hover.texture_margin_top = 20
		style_card_hover.texture_margin_bottom = 20
		style_card_hover.content_margin_left = 12
		style_card_hover.content_margin_right = 12
		style_card_hover.content_margin_top = 12
		style_card_hover.content_margin_bottom = 12

	if tex_cb:
		style_card_branch = StyleBoxTexture.new()
		style_card_branch.texture = tex_cb
		style_card_branch.texture_margin_left = 20
		style_card_branch.texture_margin_right = 20
		style_card_branch.texture_margin_top = 20
		style_card_branch.texture_margin_bottom = 20
		style_card_branch.content_margin_left = 12
		style_card_branch.content_margin_right = 12
		style_card_branch.content_margin_top = 12
		style_card_branch.content_margin_bottom = 12

static func apply_clay_upgrade_card(btn: Button, is_branch: bool = false) -> void:
	_init_card_styles()
	if not btn: return
	var normal_box = style_card_branch if is_branch and style_card_branch else style_card_normal
	if normal_box:
		btn.add_theme_stylebox_override("normal", normal_box)
		btn.add_theme_stylebox_override("disabled", normal_box)
	if style_card_hover:
		btn.add_theme_stylebox_override("hover", style_card_hover)
		btn.add_theme_stylebox_override("focus", style_card_hover)
		btn.add_theme_stylebox_override("pressed", style_card_hover)

static func apply_clay_upgrade_card_themed(btn: Button, theme_type: String = "normal") -> void:
	if not btn: return
	var tex_path = "res://assets/sprites/ui/ui_card_bg_normal.png"
	match theme_type:
		"heavy", "red":
			tex_path = "res://assets/sprites/ui/ui_card_clay_heavy.png"
		"shield", "blue":
			tex_path = "res://assets/sprites/ui/ui_card_clay_shield.png"
		"speed", "green":
			tex_path = "res://assets/sprites/ui/ui_card_clay_speed.png"
		"branch":
			tex_path = "res://assets/sprites/ui/ui_card_bg_branch.png"

	var tex = TextureHelper.get_tex(tex_path)
	if tex:
		var sb = StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 26
		sb.texture_margin_right = 26
		sb.texture_margin_top = 26
		sb.texture_margin_bottom = 26
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("disabled", sb)

		var sb_h = sb.duplicate() as StyleBoxTexture
		sb_h.modulate_color = Color(1.15, 1.15, 1.05)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("focus", sb_h)

		var sb_p = sb.duplicate() as StyleBoxTexture
		sb_p.modulate_color = Color(0.92, 0.88, 0.85)
		btn.add_theme_stylebox_override("pressed", sb_p)
	else:
		apply_clay_upgrade_card(btn, theme_type == "branch")

static func apply_clay_event_card(btn: Button) -> void:
	_init_card_styles()
	if not btn: return
	if style_card_normal:
		btn.add_theme_stylebox_override("normal", style_card_normal)
		btn.add_theme_stylebox_override("disabled", style_card_normal)
	if style_card_hover:
		btn.add_theme_stylebox_override("hover", style_card_hover)
		btn.add_theme_stylebox_override("focus", style_card_hover)
		btn.add_theme_stylebox_override("pressed", style_card_hover)

static func apply_clay_event_button(btn: Button, opt_index: int = 1) -> void:
	if not btn: return
	var tex_name = "btn_event_opt%d_clay.png" % clampi(opt_index, 1, 3)
	var tex = TextureHelper.get_tex("res://assets/sprites/ui/" + tex_name)
	if tex:
		var sb = StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 20
		sb.texture_margin_right = 20
		sb.texture_margin_top = 14
		sb.texture_margin_bottom = 16
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("disabled", sb)

		var sb_h = sb.duplicate() as StyleBoxTexture
		sb_h.modulate_color = Color(1.15, 1.15, 1.05)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("focus", sb_h)

		var sb_p = sb.duplicate() as StyleBoxTexture
		sb_p.modulate_color = Color(0.9, 0.85, 0.8)
		btn.add_theme_stylebox_override("pressed", sb_p)

		btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.85, 1.0))
	else:
		apply_clay_button(btn)

static func apply_clay_tab_button(btn: Button, is_active: bool = false) -> void:
	if not btn: return
	var tex_act = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_tab_active.png")
	var tex_inact = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_tab_inactive.png")
	var tex = tex_act if is_active else tex_inact
	if tex:
		var sb = StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = 18
		sb.texture_margin_right = 18
		sb.texture_margin_top = 12
		sb.texture_margin_bottom = 12
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)
		if is_active:
			btn.add_theme_color_override("font_color", Color(0.22, 0.15, 0.05, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(0.12, 0.08, 0.02, 1.0))
			btn.add_theme_color_override("font_pressed_color", Color(0.22, 0.15, 0.05, 1.0))
			btn.add_theme_color_override("font_focus_color", Color(0.22, 0.15, 0.05, 1.0))
		else:
			btn.add_theme_color_override("font_color", Color(0.85, 0.82, 0.88, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80, 1.0))
			btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.82, 0.88, 1.0))
			btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.80, 1.0))
		return
	
	var sb = StyleBoxFlat.new()
	if is_active:
		sb.bg_color = Color(0.85, 0.72, 0.35, 1.0)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1.0, 0.92, 0.65, 1.0)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)
		btn.add_theme_color_override("font_color", Color(0.18, 0.12, 0.05, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.18, 0.12, 0.05, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.18, 0.12, 0.05, 1.0))
	else:
		sb.bg_color = Color(0.20, 0.16, 0.24, 0.9)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.38, 0.32, 0.44, 0.8)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", sb)
		
		var sb_h = sb.duplicate()
		sb_h.bg_color = Color(0.30, 0.24, 0.36, 1.0)
		sb_h.border_color = Color(0.60, 0.50, 0.70, 1.0)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("focus", sb_h)
		btn.add_theme_stylebox_override("pressed", sb_h)
		
		btn.add_theme_color_override("font_color", Color(0.85, 0.80, 0.90, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.80, 1.0))

static func apply_clay_list_item(btn: Button, is_selected: bool = false) -> void:
	if not btn: return
	var sb = StyleBoxFlat.new()
	if is_selected:
		sb.bg_color = Color(0.32, 0.25, 0.40, 0.95)
		sb.border_width_left = 3
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.98, 0.82, 0.35, 1.0)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.50, 1.0))
	else:
		sb.bg_color = Color(0.16, 0.13, 0.20, 0.90)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.28, 0.23, 0.33, 0.8)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", sb)
		
		var sb_h = sb.duplicate()
		sb_h.bg_color = Color(0.24, 0.19, 0.30, 0.95)
		sb_h.border_color = Color(0.60, 0.50, 0.70, 0.9)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("focus", sb_h)
		btn.add_theme_stylebox_override("pressed", sb_h)
		btn.add_theme_color_override("font_color", Color(0.90, 0.88, 0.92, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70, 1.0))

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

## 把焦点交给界面里第一个可用控件, 让手柄/键盘一进来就能操作。
##
## 没有这一句, 整个游戏的菜单都只能用鼠标: Godot 不会自动给任何控件初始焦点,
## 而没有焦点就没有 ui_up/down/accept 的落点 —— 手柄玩家连"开始游戏"都按不到。
## 全项目此前一处 grab_focus() 都没有。
##
## 用 call_deferred: 各对话框都是在 _ready() 里用代码现搭控件的, 这一帧里它们
## 还没进入场景树、也还没算出布局, 此时 grab_focus() 会被静默丢弃。
##
## 相邻关系不用手动接 —— Godot 会按控件的实际布局自动推算上下左右邻居,
## 而这些界面都是规规矩矩的 VBox/GridContainer。
##
## 参数收 Node 而不是 Control: 界面根节点并不都是 Control ——
## upgrade_selection_dialog 是 CanvasLayer, 其余几个是 Control/PanelContainer。
## 反正下面本来就是向下遍历找 Control, 收窄类型只会把 CanvasLayer 挡在门外。
static func focus_first(root: Node) -> void:
	if not root:
		return
	var target := _first_focusable(root)
	if target:
		target.call_deferred("grab_focus")

static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			# 隐藏的分支整棵跳过: 标题界面的"继续游戏"在没有存档时是隐藏的,
			# 抓它会把焦点丢进一个看不见的按钮里。
			if not c.visible:
				continue
			if c is Button and not (c as Button).disabled and c.focus_mode != Control.FOCUS_NONE:
				return c
		var found := _first_focusable(child)
		if found:
			return found
	return null

static func apply_clay_panel(panel: Control, bg_color: Color = Color(0.18, 0.15, 0.20, 0.92), corner_radius: int = 14) -> void:
	if not panel: return
	var tex_panel = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_dialog_panel.png")
	if not tex_panel:
		tex_panel = TextureHelper.get_tex("res://assets/sprites/ui/ui_panel_bg.png")
	if tex_panel:
		var sbt = StyleBoxTexture.new()
		sbt.texture = tex_panel
		sbt.texture_margin_left = 32
		sbt.texture_margin_right = 32
		sbt.texture_margin_top = 28
		sbt.texture_margin_bottom = 28
		sbt.content_margin_left = 20
		sbt.content_margin_right = 20
		sbt.content_margin_top = 16
		sbt.content_margin_bottom = 16
		panel.add_theme_stylebox_override("panel", sbt)
		return

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

static func apply_clay_subpanel(panel: Control, bg_color: Color = Color(0.12, 0.10, 0.15, 0.92)) -> void:
	if not panel: return
	var tex_sub = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_subpanel_tray.png")
	if tex_sub:
		var sbt = StyleBoxTexture.new()
		sbt.texture = tex_sub
		sbt.texture_margin_left = 24
		sbt.texture_margin_right = 24
		sbt.texture_margin_top = 22
		sbt.texture_margin_bottom = 22
		sbt.content_margin_left = 14
		sbt.content_margin_right = 14
		sbt.content_margin_top = 10
		sbt.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", sbt)
		return

	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.35, 0.28, 0.40, 0.8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
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

static func apply_clay_slider(slider: HSlider) -> void:
	if not slider: return
	var tex_track = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_slider_track.png")
	var tex_grab = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_slider_grabber.png")
	if tex_grab:
		slider.add_theme_icon_override("grabber", tex_grab)
		slider.add_theme_icon_override("grabber_highlight", tex_grab)
	if tex_track:
		var sbt = StyleBoxTexture.new()
		sbt.texture = tex_track
		sbt.texture_margin_left = 16
		sbt.texture_margin_right = 16
		sbt.texture_margin_top = 8
		sbt.texture_margin_bottom = 8
		sbt.content_margin_top = 6
		sbt.content_margin_bottom = 6
		slider.add_theme_stylebox_override("slider", sbt)
		var sbt_area = sbt.duplicate() as StyleBoxTexture
		sbt_area.modulate_color = Color(1.2, 1.1, 0.9)
		slider.add_theme_stylebox_override("grabber_area", sbt_area)
		slider.add_theme_stylebox_override("grabber_area_highlight", sbt_area)
		return

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.11, 0.18, 0.95)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.48, 0.38, 0.58, 0.85)
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", bg)
	
	var grab_sb := StyleBoxFlat.new()
	grab_sb.bg_color = Color(0.98, 0.82, 0.35, 1.0)
	grab_sb.corner_radius_top_left = 6
	grab_sb.corner_radius_top_right = 6
	grab_sb.corner_radius_bottom_left = 6
	grab_sb.corner_radius_bottom_right = 6
	grab_sb.border_width_left = 1
	grab_sb.border_width_top = 1
	grab_sb.border_width_right = 1
	grab_sb.border_width_bottom = 1
	grab_sb.border_color = Color(1.0, 0.95, 0.70, 1.0)
	grab_sb.content_margin_left = 6
	grab_sb.content_margin_right = 6
	grab_sb.content_margin_top = 6
	grab_sb.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area", grab_sb)
	slider.add_theme_stylebox_override("grabber_area_highlight", grab_sb)

static func apply_clay_check_box(cb: CheckBox) -> void:
	if not cb: return
	var tex_chk = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_checkbox_checked.png")
	var tex_unchk = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_checkbox_unchecked.png")
	if tex_chk:
		cb.add_theme_icon_override("checked", tex_chk)
	if tex_unchk:
		cb.add_theme_icon_override("unchecked", tex_unchk)
	cb.add_theme_color_override("font_color", Color(0.92, 0.88, 0.95, 1.0))
	cb.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.60, 1.0))
	cb.add_theme_color_override("font_pressed_color", Color(0.98, 0.85, 0.35, 1.0))
	cb.add_theme_color_override("font_focus_color", Color(1.0, 0.92, 0.60, 1.0))
	cb.add_theme_constant_override("h_separation", 10)

static func apply_clay_option_button(opt: OptionButton) -> void:
	if not opt: return
	apply_clay_button(opt, true)
	var popup = opt.get_popup()
	if popup:
		var p_sb := StyleBoxFlat.new()
		p_sb.bg_color = Color(0.12, 0.10, 0.16, 0.98)
		p_sb.corner_radius_top_left = 10
		p_sb.corner_radius_top_right = 10
		p_sb.corner_radius_bottom_left = 10
		p_sb.corner_radius_bottom_right = 10
		p_sb.border_width_left = 2
		p_sb.border_width_top = 2
		p_sb.border_width_right = 2
		p_sb.border_width_bottom = 2
		p_sb.border_color = Color(0.55, 0.45, 0.68, 0.9)
		p_sb.content_margin_left = 8
		p_sb.content_margin_right = 8
		p_sb.content_margin_top = 8
		p_sb.content_margin_bottom = 8
		popup.add_theme_stylebox_override("panel", p_sb)

static func apply_hud_sidepanel(panel: Control) -> void:
	if not panel: return
	var tex_side = TextureHelper.get_tex("res://assets/sprites/ui/ui_clay_hud_sidepanel.png")
	if tex_side:
		var sbt = StyleBoxTexture.new()
		sbt.texture = tex_side
		sbt.texture_margin_left = 22
		sbt.texture_margin_right = 22
		sbt.texture_margin_top = 26
		sbt.texture_margin_bottom = 26
		sbt.content_margin_left = 14
		sbt.content_margin_right = 14
		sbt.content_margin_top = 14
		sbt.content_margin_bottom = 14
		panel.add_theme_stylebox_override("panel", sbt)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.14, 0.92)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 0
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 0
	sb.border_width_bottom = 2
	sb.border_color = Color(0.48, 0.38, 0.62, 0.85)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(-2, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

static func apply_pause_menu_theme(menu_panel: PanelContainer, buttons: Array) -> void:
	if not menu_panel: return
	apply_clay_panel(menu_panel)
	for b in buttons:
		if b is Button:
			apply_clay_button(b, true)

# Full catalog for the hotbar -- "id" must match builder_controller.gd's
# structure_ids / shop_dialog.gd::BUILDING_ITEMS exactly. Structures are
# shop-only stock now (GameState.structure_inventory), not a battle-gold
# cost, and the hotbar only ever shows what's actually owned (stock > 0) --
# see _rebuild_hotbar_slots.
const HOTBAR_CATALOG := [
	{"id": "turret", "icon": "res://assets/sprites/buildings/turret_gun.png"},
	{"id": "fortified_wall", "icon": "res://assets/sprites/buildings/fortified_wall.png"},
	{"id": "electric_wall", "icon": "res://assets/sprites/tiles/tile_electric_wall_f0.png"},
	{"id": "street_lamp", "icon": "res://assets/sprites/buildings/street_lamp.png"},
	{"id": "oil_barrel", "icon": "res://assets/sprites/buildings/oil_barrel.png"},
	{"id": "landmine", "icon": "res://assets/sprites/buildings/landmine.png"},
	{"id": "repair_station", "icon": "res://assets/sprites/buildings/repair_station.png"},
	{"id": "shield_station", "icon": "res://assets/sprites/buildings/shield_station.png"},
	{"id": "wind_blower", "icon": "res://assets/sprites/buildings/wind_blower.png"},
	{"id": "missile_strike", "icon": "res://assets/sprites/powerups/missile_strike.png"},
	{"id": "timed_bomb", "icon": "res://assets/sprites/buildings/prop_timed_bomb.png"},
	{"id": "roller_wall", "icon": "res://assets/sprites/buildings/roller_wall.png"},
	{"id": "pipe_conduit", "icon": "res://assets/sprites/buildings/pipe_conduit.png"},
	{"id": "bunker", "icon": "res://assets/sprites/buildings/bunker.png"},
	{"id": "wooden_wall", "icon": "res://assets/sprites/buildings/wooden_wall.png"},
	{"id": "darkness_device", "icon": "res://assets/sprites/buildings/darkness_device.png"},
]

static func create_hotbar_ui(parent: Node) -> Control:
	var dock = PanelContainer.new()
	dock.name = "TacticalHotbar"
	dock.custom_minimum_size = Vector2(580, 72)
	dock.anchors_preset = Control.PRESET_BOTTOM_LEFT
	dock.position = Vector2(72, 680)
	apply_clay_panel(dock, Color(0.12, 0.10, 0.14, 0.95), 10)
	parent.add_child(dock)

	var hbox = HBoxContainer.new()
	hbox.name = "SlotContainer"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	dock.add_child(hbox)

	_rebuild_hotbar_slots(dock)
	return dock

## Clears and rebuilds every slot from GameState.structure_inventory, showing
## ONLY structures currently owned (stock > 0) -- called at creation and
## again any time stock changes, so a structure's slot appears/disappears
## live instead of always showing all 11 regardless of what you actually have.
static func _rebuild_hotbar_slots(dock: Control) -> void:
	var hbox = dock.get_node_or_null("SlotContainer")
	if not hbox: return
	# free() (not queue_free()) -- this isn't running inside any of these
	# children's own callback, so immediate removal is safe, and it matters
	# here: queue_free() defers to end-of-frame, so a caller that checks
	# hbox's children right after this call (e.g. builder_controller.gd
	# reacting to a placement that just hit 0 stock) would still see the
	# stale, about-to-die slot for one more frame.
	for child in hbox.get_children():
		child.free()

	var slot_tex_norm = TextureHelper.get_tex("res://assets/sprites/ui/ui_hotbar_slot.png")

	for item in HOTBAR_CATALOG:
		var stock = GameState.get_structure_stock(item["id"])
		if stock <= 0:
			continue

		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(56, 56)
		slot_panel.name = "Slot_%s" % item["id"]
		slot_panel.set_meta("structure_id", item["id"])

		var sbt = StyleBoxTexture.new()
		sbt.texture = slot_tex_norm if slot_tex_norm else null
		sbt.texture_margin_left = 6
		sbt.texture_margin_right = 6
		sbt.texture_margin_top = 6
		sbt.texture_margin_bottom = 6
		slot_panel.add_theme_stylebox_override("panel", sbt)

		var v_inner = VBoxContainer.new()
		v_inner.name = "Inner"
		v_inner.alignment = BoxContainer.ALIGNMENT_CENTER
		v_inner.add_theme_constant_override("separation", 2)
		slot_panel.add_child(v_inner)

		var icon_tex = TextureHelper.get_tex(item["icon"])
		if icon_tex:
			var icon_rect = TextureRect.new()
			icon_rect.texture = icon_tex
			icon_rect.custom_minimum_size = Vector2(28, 28)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			v_inner.add_child(icon_rect)

		var stock_lbl = Label.new()
		stock_lbl.name = "StockLabel"
		stock_lbl.text = "x%d" % stock
		stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stock_lbl.add_theme_font_size_override("font_size", 9)
		stock_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.35, 1.0))
		v_inner.add_child(stock_lbl)

		hbox.add_child(slot_panel)

## Call after any purchase or placement changes a structure's count -- fully
## rebuilds so a slot whose stock just hit 0 disappears (and one that just
## went from 0 to 1 appears), not just its label text.
static func update_hotbar_stock(dock: Control) -> void:
	if not dock: return
	_rebuild_hotbar_slots(dock)

## struct_id: the GameState.structure_inventory key of the currently
## selected structure ("" for none). Matches by id instead of a positional
## index -- the slot list can change shape at any time (items appear/vanish
## as stock changes), so a remembered numeric index would drift out of sync
## with what's actually on screen.
static func update_hotbar_selection(dock: Control, struct_id: String) -> void:
	if not dock: return
	var hbox = dock.get_node_or_null("SlotContainer")
	if not hbox: return

	var slot_tex_norm = TextureHelper.get_tex("res://assets/sprites/ui/ui_hotbar_slot.png")
	var slot_tex_act = TextureHelper.get_tex("res://assets/sprites/ui/ui_hotbar_slot_active.png")

	for slot_p in hbox.get_children():
		if not (slot_p is PanelContainer):
			continue
		var is_active = slot_p.has_meta("structure_id") and slot_p.get_meta("structure_id") == struct_id and struct_id != ""
		var sbt = StyleBoxTexture.new()
		sbt.texture = slot_tex_act if is_active else slot_tex_norm
		sbt.texture_margin_left = 8 if is_active else 6
		sbt.texture_margin_right = 8 if is_active else 6
		sbt.texture_margin_top = 8 if is_active else 6
		sbt.texture_margin_bottom = 8 if is_active else 6
		slot_p.add_theme_stylebox_override("panel", sbt)
		slot_p.modulate = Color(1.3, 1.3, 1.1) if is_active else Color(1.0, 1.0, 1.0)

static func create_boss_bar(parent: Node) -> Dictionary:
	var root = Control.new()
	root.name = "BossHealthBar"
	root.custom_minimum_size = Vector2(480, 42)
	root.anchors_preset = Control.PRESET_TOP_WIDE
	# GameArea (战场) 从屏幕 y=48 开始, y<48 是纯 HUD 边距, 从来没有战场内容。
	# 解法是把整条血条 (含名字) 严格收进这 48px 高的边距里 (y=3..45),
	# 启用九宫格拉伸使其缩放生效, 绝不侵占战场第一行 (Row 0, y=48..96) 刷新点与视野。
	root.position = Vector2(120, 3)
	root.visible = false
	parent.add_child(root)

	var frame_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_boss_bar_frame.png")
	var track_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_boss_bar_track.png")
	var fill_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_boss_bar_fill.png")

	var prog = TextureProgressBar.new()
	prog.name = "Progress"
	prog.texture_under = track_tex
	prog.texture_progress = fill_tex
	prog.texture_over = frame_tex
	prog.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	prog.nine_patch_stretch = true
	prog.stretch_margin_left = 32
	prog.stretch_margin_right = 32
	prog.stretch_margin_top = 8
	prog.stretch_margin_bottom = 8
	prog.custom_minimum_size = Vector2(480, 42)
	prog.size = Vector2(480, 42)
	prog.position = Vector2(0, 0)
	root.add_child(prog)

	# 名字与血条同高叠在一起显示, 限制在 42px 内居中
	var lbl = Label.new()
	lbl.name = "BossName"
	lbl.text = "👑 BOSS"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(0, 0)
	lbl.custom_minimum_size = Vector2(480, 42)
	lbl.size = Vector2(480, 42)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	root.add_child(lbl)

	return {"root": root, "prog": prog, "label": lbl}

static func apply_icon_button(btn: Button, icon_path: String, icon_size: Vector2 = Vector2(28, 28), dark_text: bool = true) -> void:
	if not btn: return
	apply_clay_button(btn, dark_text)
	var tex = TextureHelper.get_tex(icon_path)
	if tex:
		btn.icon = tex
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", int(icon_size.x))
		btn.add_theme_constant_override("h_separation", 12)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

static func get_perk_icon(opt: Dictionary) -> Texture2D:
	var opt_type = str(opt.get("type", ""))
	var perk_id = str(opt.get("id", ""))
	var branch = str(opt.get("branch", ""))
	
	var icon_name = "perk_tactical"
	
	if opt_type == "branch":
		match branch:
			"speed": icon_name = "perk_speed"
			"heavy": icon_name = "perk_armor"
			"train": icon_name = "perk_train"
			"counter": icon_name = "perk_shield"
			"trench": icon_name = "perk_trench"
	elif opt_type == "tier_up":
		var name_str = str(opt.get("name", ""))
		if "Speed" in name_str or "暴风" in name_str:
			icon_name = "perk_speed"
		elif "Heavy" in name_str or "重型" in name_str:
			icon_name = "perk_atk"
		elif "Train" in name_str or "列车" in name_str:
			icon_name = "perk_missile"
		elif "Counter" in name_str or "反击" in name_str:
			icon_name = "perk_shield"
		elif "Trench" in name_str or "战壕" in name_str or "壕沟" in name_str:
			icon_name = "perk_trench"
	elif opt_type == "gold_heal":
		icon_name = "perk_gold"
	else:
		match perk_id:
			"titan_plating": icon_name = "perk_shield"
			"rapid_loader": icon_name = "perk_speed"
			"nitro_booster": icon_name = "perk_speed"
			"nano_repair": icon_name = "perk_regen"
			"high_explosive": icon_name = "perk_bomb"
			"warp_drive": icon_name = "perk_laser"
			"frost_cleats": icon_name = "perk_frost"
			"ferry_artillery": icon_name = "perk_ferry"
			"clay_crusher": icon_name = "perk_ricochet"
			"magnetic_salvage": icon_name = "perk_gold"
			"amphibious_hull": icon_name = "perk_amphibious"
			"armor_piercing_rounds": icon_name = "perk_piercing"
			"kinetic_piston_rounds": icon_name = "perk_tactical"
			"iff_flag": icon_name = "perk_shield"
			_:
				icon_name = "perk_tactical"

	var tex = TextureHelper.get_tex("res://assets/sprites/ui/%s.png" % icon_name)
	if not tex:
		tex = TextureHelper.get_tex("res://assets/sprites/ui/perk_tactical.png")
	return tex

static func create_victory_defeat_modal(parent: Node) -> Dictionary:
	var root = Control.new()
	root.name = "VictoryDefeatModal"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	parent.add_child(root)

	var blocker = ColorRect.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(0.08, 0.06, 0.10, 0.75)
	root.add_child(blocker)

	var panel = PanelContainer.new()
	panel.name = "ModalCard"
	panel.custom_minimum_size = Vector2(460, 420)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.position = Vector2(282, 174)
	apply_clay_panel(panel, Color(0.18, 0.15, 0.20, 0.98), 16)
	root.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var banner_rect = TextureRect.new()
	banner_rect.name = "BannerRect"
	banner_rect.custom_minimum_size = Vector2(380, 110)
	banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(banner_rect)

	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40))
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.90))
	vbox.add_child(desc_lbl)

	var stats_box = VBoxContainer.new()
	stats_box.name = "StatsBox"
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_box.add_theme_constant_override("separation", 6)
	vbox.add_child(stats_box)

	var btn_action = Button.new()
	btn_action.name = "ActionButton"
	btn_action.custom_minimum_size = Vector2(280, 48)
	btn_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_icon_button(btn_action, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(24, 24))
	vbox.add_child(btn_action)

	return {
		"root": root,
		"banner": banner_rect,
		"title": title_lbl,
		"desc": desc_lbl,
		"stats_box": stats_box,
		"button": btn_action
	}

static func get_category_info(category_code: String, item_id: String = "") -> Dictionary:
	match category_code:
		"BUILD":
			return {
				"tag": "【战备建筑】",
				"color": Color(0.40, 0.88, 0.98),
				"bg": Color(0.12, 0.28, 0.36, 0.9)
			}
		"WEAPON":
			return {
				"tag": "【核心武装】",
				"color": Color(1.0, 0.75, 0.35),
				"bg": Color(0.38, 0.22, 0.10, 0.9)
			}
		"HULL":
			return {
				"tag": "【装甲强化】",
				"color": Color(0.45, 0.92, 0.65),
				"bg": Color(0.12, 0.32, 0.20, 0.9)
			}
		"FIREPOWER":
			return {
				"tag": "【火力调校】",
				"color": Color(1.0, 0.85, 0.35),
				"bg": Color(0.35, 0.28, 0.10, 0.9)
			}
		"MOBILITY":
			return {
				"tag": "【机动引擎】",
				"color": Color(0.50, 0.80, 1.0),
				"bg": Color(0.15, 0.25, 0.38, 0.9)
			}
		"SUPPORT":
			return {
				"tag": "【后勤增援】",
				"color": Color(0.95, 0.60, 0.85),
				"bg": Color(0.35, 0.15, 0.30, 0.9)
			}
		"BASE":
			return {
				"tag": "【基地工程】",
				"color": Color(0.85, 0.75, 0.55),
				"bg": Color(0.30, 0.24, 0.16, 0.9)
			}
		"TACTICAL":
			return {
				"tag": "【战术特种】",
				"color": Color(0.95, 0.88, 0.45),
				"bg": Color(0.32, 0.28, 0.12, 0.9)
			}
		"RISK":
			return {
				"tag": "【高风险改造】",
				"color": Color(1.0, 0.45, 0.45),
				"bg": Color(0.40, 0.12, 0.12, 0.95)
			}
		_:
			return {
				"tag": "【战术强化】",
				"color": Color(0.85, 0.85, 0.90),
				"bg": Color(0.20, 0.18, 0.24, 0.9)
			}

## 构造高品质黏土风格货位商品悬浮说明卡
static func create_shop_explanation_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "ShopExplanationCard"
	card.custom_minimum_size = Vector2(240, 140)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 30
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.15, 0.96)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.48, 0.42, 0.54, 0.95)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)
	
	# Header: Icon + Title + Tag
	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	var icon_panel := PanelContainer.new()
	icon_panel.name = "IconPanel"
	icon_panel.custom_minimum_size = Vector2(34, 34)
	var icon_sb := StyleBoxFlat.new()
	icon_sb.bg_color = Color(0.20, 0.17, 0.24, 0.95)
	icon_sb.corner_radius_top_left = 6
	icon_sb.corner_radius_top_right = 6
	icon_sb.corner_radius_bottom_left = 6
	icon_sb.corner_radius_bottom_right = 6
	icon_sb.border_width_left = 1
	icon_sb.border_width_top = 1
	icon_sb.border_width_right = 1
	icon_sb.border_width_bottom = 1
	icon_sb.border_color = Color(0.45, 0.40, 0.50, 0.8)
	icon_panel.add_theme_stylebox_override("panel", icon_sb)
	header.add_child(icon_panel)
	
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = Vector2(28, 28)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_panel.add_child(icon_rect)
	
	var title_box := VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)
	
	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.50))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(title_lbl)
	
	var tag_lbl := Label.new()
	tag_lbl.name = "TagLabel"
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Color(0.40, 0.88, 0.98))
	title_box.add_child(tag_lbl)
	
	# Price and Status Row
	var price_row := HBoxContainer.new()
	price_row.name = "PriceRow"
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_theme_constant_override("separation", 8)
	vbox.add_child(price_row)
	
	var price_lbl := Label.new()
	price_lbl.name = "PriceLabel"
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	price_row.add_child(price_lbl)
	
	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_row.add_child(status_lbl)
	
	# Description Label
	var desc_lbl := Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.83, 0.88))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)
	
	# Progress / Stock Label
	var progress_lbl := Label.new()
	progress_lbl.name = "ProgressLabel"
	progress_lbl.add_theme_font_size_override("font_size", 10)
	progress_lbl.add_theme_color_override("font_color", Color(0.70, 0.95, 0.70))
	progress_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(progress_lbl)
	
	# Prompt Footer
	var prompt_lbl := Label.new()
	prompt_lbl.name = "PromptLabel"
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	prompt_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(prompt_lbl)
	
	return card

## 刷新货位商品悬浮说明卡的数据与状态
static func update_shop_explanation_card(card: Control, item_id: String, cost: int, sold: bool) -> void:
	if not card: return
	var ShopDialogClass = load("res://scripts/shop_dialog.gd")
	var GameStateClass = load("res://scripts/game_state.gd")
	if not ShopDialogClass or not GameStateClass: return
	
	var data: Dictionary = ShopDialogClass.item_by_id(item_id)
	if data.is_empty(): return
	
	var icon_rect: TextureRect = card.find_child("Icon", true, false)
	var title_lbl: Label = card.find_child("TitleLabel", true, false)
	var tag_lbl: Label = card.find_child("TagLabel", true, false)
	var price_lbl: Label = card.find_child("PriceLabel", true, false)
	var status_lbl: Label = card.find_child("StatusLabel", true, false)
	var desc_lbl: Label = card.find_child("DescLabel", true, false)
	var progress_lbl: Label = card.find_child("ProgressLabel", true, false)
	var prompt_lbl: Label = card.find_child("PromptLabel", true, false)
	
	var cat_code = str(data.get("category", "TACTICAL"))
	var cat_info = get_category_info(cat_code, item_id)
	
	if icon_rect:
		var tex = TextureHelper.get_tex(str(data.get("icon", "")))
		icon_rect.texture = tex
	
	if title_lbl:
		title_lbl.text = str(data.get("name", item_id))
	
	if tag_lbl:
		tag_lbl.text = cat_info["tag"]
		tag_lbl.add_theme_color_override("font_color", cat_info["color"])
		
	if desc_lbl:
		desc_lbl.text = str(data.get("desc", ""))
		if cat_code == "RISK":
			desc_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
		else:
			desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.83, 0.88))
	
	var can_afford: bool = (GameStateClass.gold >= cost)
	var can_buy_cond: bool = ShopDialogClass.can_buy_item(item_id)
	
	if price_lbl:
		price_lbl.text = "💰 %d G" % cost
	
	if sold:
		if status_lbl:
			status_lbl.text = "[已售罄 SOLD]"
			status_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		if prompt_lbl:
			prompt_lbl.text = "✖ 该货位商品已被购入"
			prompt_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	elif not can_buy_cond:
		if status_lbl:
			status_lbl.text = "[已达上限 MAX]"
			status_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
		if prompt_lbl:
			prompt_lbl.text = "✖ 已达到该强化的最大上限"
			prompt_lbl.add_theme_color_override("font_color", Color(0.90, 0.50, 0.45))
	elif not can_afford:
		if status_lbl:
			status_lbl.text = "[金币不足]"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40))
		if prompt_lbl:
			prompt_lbl.text = "✖ 缺少 %d G (持有 %d G)" % [cost - GameStateClass.gold, GameStateClass.gold]
			prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	else:
		if status_lbl:
			status_lbl.text = "[可购买 READY]"
			status_lbl.add_theme_color_override("font_color", Color(0.40, 0.95, 0.45))
		if prompt_lbl:
			prompt_lbl.text = "👉 开上货位即可立即购买"
			prompt_lbl.add_theme_color_override("font_color", Color(0.60, 0.90, 1.0))
			
	# Progress text
	if progress_lbl:
		if cat_code == "BUILD":
			var stock: int = GameStateClass.get_structure_stock(item_id)
			progress_lbl.text = "📦 当前战备库存: x%d" % stock
			progress_lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0))
		elif item_id in ShopDialogClass.PER_PLAYER_PERKS:
			var stacks: int = int(GameStateClass.unlocked_perks.get(item_id, 0))
			var max_s: int = GameStateClass.max_stacks_for_perk(item_id)
			progress_lbl.text = "⚡ 强化层数: %d / %d 层" % [stacks, max_s]
			progress_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
		elif item_id == "star_tier":
			if GameStateClass.tank_branch == "default":
				progress_lbl.text = "⭐ 当前战车阶级: Tier %d (上限: 3)" % GameStateClass.player_tier
			else:
				progress_lbl.text = "⭐ 分支专属转化: 永久攻击 +1 (当前加成: +%d)" % GameStateClass.atk_bonus
			progress_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
		elif item_id == "heavy_armor":
			progress_lbl.text = "🛡️ 当前装甲等级加成: +%d HP" % GameStateClass.max_hp_lvl
			progress_lbl.add_theme_color_override("font_color", Color(0.50, 0.95, 0.65))
		elif item_id == "autoloader":
			progress_lbl.text = "⚙️ 当前装填强化等级: Lv.%d" % GameStateClass.fire_rate_lvl
			progress_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		elif item_id == "turbo_engine":
			progress_lbl.text = "🚀 当前机动强化等级: Lv.%d" % GameStateClass.speed_lvl
			progress_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
		elif item_id == "extra_life":
			# 双人战役下 player_lives 是团队共享的生命池, 不再分 P1/P2 两个数。
			progress_lbl.text = "❤️ 备用生命: %d 条" % GameStateClass.player_lives
			progress_lbl.add_theme_color_override("font_color", Color(1.0, 0.60, 0.70))
		elif item_id == "steel_shovel":
			progress_lbl.text = "🏰 基地工程防御等级: Lv.%d" % GameStateClass.builder_lvl
			progress_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.60))
		elif item_id == "plasma_mod":
			progress_lbl.text = "💥 武器攻击加成: +%d" % GameStateClass.atk_bonus
			progress_lbl.add_theme_color_override("font_color", Color(1.0, 0.70, 0.40))
		elif item_id == "landmine_crate":
			progress_lbl.text = "🎖️ 反坦克地雷库存: %d 枚" % GameStateClass.get_structure_stock("landmine")
			progress_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.50))
		else:
			progress_lbl.text = ""

## 构造高品质黏土风格换货机悬浮说明卡
static func create_reroll_explanation_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "RerollExplanationCard"
	card.custom_minimum_size = Vector2(250, 130)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 30
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.16, 0.96)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.55, 0.45, 0.68, 0.95)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)
	
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(34, 34)
	var icon_sb := StyleBoxFlat.new()
	icon_sb.bg_color = Color(0.22, 0.16, 0.28, 0.95)
	icon_sb.corner_radius_top_left = 6
	icon_sb.corner_radius_top_right = 6
	icon_sb.corner_radius_bottom_left = 6
	icon_sb.corner_radius_bottom_right = 6
	icon_sb.border_width_left = 1
	icon_sb.border_width_top = 1
	icon_sb.border_width_right = 1
	icon_sb.border_width_bottom = 1
	icon_sb.border_color = Color(0.60, 0.45, 0.75, 0.8)
	icon_panel.add_theme_stylebox_override("panel", icon_sb)
	header.add_child(icon_panel)
	
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = Vector2(28, 28)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var r_tex = TextureHelper.get_tex("res://assets/sprites/map/node_shop.png")
	if r_tex: icon_rect.texture = r_tex
	icon_panel.add_child(icon_rect)
	
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)
	
	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "军火商货物刷新机 (Shop Reroll Device)"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(title_lbl)
	
	var tag_lbl := Label.new()
	tag_lbl.name = "TagLabel"
	tag_lbl.text = "【货架重置】"
	tag_lbl.add_theme_font_size_override("font_size", 10)
	tag_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0))
	title_box.add_child(tag_lbl)
	
	var price_row := HBoxContainer.new()
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_theme_constant_override("separation", 8)
	vbox.add_child(price_row)
	
	var price_lbl := Label.new()
	price_lbl.name = "PriceLabel"
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	price_row.add_child(price_lbl)
	
	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_row.add_child(status_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.text = "支付金币向军火商请求调拨全新货架！清空当前货位并重新随机上架 3 种战术强化与 3 种战备建筑。（每次刷新费用递增）"
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.90))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)
	
	var prompt_lbl := Label.new()
	prompt_lbl.name = "PromptLabel"
	prompt_lbl.text = "👉 开上机器即可立即换货。"
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	prompt_lbl.add_theme_color_override("font_color", Color(0.50, 0.90, 1.0))
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(prompt_lbl)
	
	return card

## 刷新换货机悬浮说明卡数据与状态
static func update_reroll_explanation_card(card: Control, cost: int) -> void:
	if not card: return
	var GameStateClass = load("res://scripts/game_state.gd")
	if not GameStateClass: return
	
	var price_lbl: Label = card.find_child("PriceLabel", true, false)
	var status_lbl: Label = card.find_child("StatusLabel", true, false)
	var prompt_lbl: Label = card.find_child("PromptLabel", true, false)
	
	var can_afford: bool = (GameStateClass.gold >= cost)
	if price_lbl:
		price_lbl.text = "💰 %d G" % cost
		price_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if can_afford else Color(1.0, 0.45, 0.45))
	
	if status_lbl:
		if can_afford:
			status_lbl.text = "[可刷新 READY]"
			status_lbl.add_theme_color_override("font_color", Color(0.40, 0.95, 0.45))
		else:
			status_lbl.text = "[金币不足]"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40))
			
	if prompt_lbl:
		if can_afford:
			prompt_lbl.text = "👉 开上机器即可立即换货"
			prompt_lbl.add_theme_color_override("font_color", Color(0.50, 0.90, 1.0))
		else:
			prompt_lbl.text = "✖ 缺少 %d G (持有 %d G)" % [cost - GameStateClass.gold, GameStateClass.gold]
			prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))

