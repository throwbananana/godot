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

static func apply_clay_panel(panel: Control, bg_color: Color = Color(0.18, 0.15, 0.20, 0.92), corner_radius: int = 14) -> void:
	if not panel: return
	var tex_panel = TextureHelper.get_tex("res://assets/sprites/ui/ui_panel_bg.png")
	if tex_panel:
		var sbt = StyleBoxTexture.new()
		sbt.texture = tex_panel
		sbt.texture_margin_left = 22
		sbt.texture_margin_right = 22
		sbt.texture_margin_top = 22
		sbt.texture_margin_bottom = 22
		sbt.content_margin_left = 16
		sbt.content_margin_right = 16
		sbt.content_margin_top = 14
		sbt.content_margin_bottom = 14
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
	root.custom_minimum_size = Vector2(480, 56)
	root.anchors_preset = Control.PRESET_TOP_WIDE
	root.position = Vector2(120, 18)
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
	prog.custom_minimum_size = Vector2(480, 48)
	prog.position = Vector2(0, 8)
	# Fixed-size widget (never resized), so nine-patch corner stretching buys
	# nothing here and previously used margins (24px) that didn't line up
	# with the actual rendered content bounds -- a plain proportional crop is
	# simpler and correct now that ui_boss_bar_fill.png has ~1px of padding.
	prog.nine_patch_stretch = false
	root.add_child(prog)

	var lbl = Label.new()
	lbl.name = "BossName"
	lbl.text = "👑 BOSS"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, -14)
	lbl.custom_minimum_size = Vector2(480, 20)
	lbl.add_theme_font_size_override("font_size", 13)
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
	elif opt_type == "tier_up":
		var name_str = str(opt.get("name", ""))
		if "Speed" in name_str or "暴风" in name_str:
			icon_name = "perk_speed"
		elif "Heavy" in name_str or "重型" in name_str:
			icon_name = "perk_atk"
		elif "Train" in name_str or "列车" in name_str:
			icon_name = "perk_missile"
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
			"frost_cleats": icon_name = "perk_speed"
			"ferry_artillery": icon_name = "perk_atk"
			"clay_crusher": icon_name = "perk_ricochet"
			"magnetic_salvage": icon_name = "perk_gold"
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
