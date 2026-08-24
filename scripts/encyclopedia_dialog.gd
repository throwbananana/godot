class_name EncyclopediaDialog
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const EncyclopediaData = preload("res://scripts/encyclopedia_data.gd")

signal closed

@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var left_list_panel: PanelContainer = $CenterContainer/MainPanel/VBox/ContentSplit/LeftListPanel
@onready var right_detail_panel: PanelContainer = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel
@onready var stats_section: PanelContainer = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/StatsSection
@onready var icon_container: PanelContainer = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/DetailHeader/IconContainer

@onready var btn_close_top: Button = $CenterContainer/MainPanel/VBox/Header/CloseTopBtn
@onready var btn_close_bottom: Button = $CenterContainer/MainPanel/VBox/BottomBar/BottomCloseBtn

@onready var btn_tab_upgrades: Button = $CenterContainer/MainPanel/VBox/TabsBar/BtnTabUpgrades
@onready var btn_tab_tanks: Button = $CenterContainer/MainPanel/VBox/TabsBar/BtnTabTanks
@onready var btn_tab_items: Button = $CenterContainer/MainPanel/VBox/TabsBar/BtnTabItems
@onready var btn_tab_buildings: Button = $CenterContainer/MainPanel/VBox/TabsBar/BtnTabBuildings
@onready var btn_tab_terrain: Button = $CenterContainer/MainPanel/VBox/TabsBar/BtnTabTerrain

@onready var item_list_vbox: VBoxContainer = $CenterContainer/MainPanel/VBox/ContentSplit/LeftListPanel/Margin/ScrollList/ItemListVBox
@onready var icon_texture: TextureRect = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/DetailHeader/IconContainer/IconTexture
@onready var detail_name: Label = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/DetailHeader/TitleBox/DetailName
@onready var detail_tag: Label = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/DetailHeader/TitleBox/DetailTag
@onready var stats_vbox: VBoxContainer = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/StatsSection/Margin/StatsVBox
@onready var desc_text: Label = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/DescText
@onready var tactics_text: Label = $CenterContainer/MainPanel/VBox/ContentSplit/RightDetailPanel/Margin/ScrollDetail/DetailVBox/TacticsText

var current_category: String = "UPGRADES"
var active_item_buttons: Array[Button] = []

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(main_panel, Color(0.16, 0.13, 0.18, 0.98), 16)
	UIThemeHelper.apply_clay_panel(left_list_panel, Color(0.12, 0.10, 0.14, 0.95), 10)
	UIThemeHelper.apply_clay_panel(right_detail_panel, Color(0.13, 0.11, 0.15, 0.95), 10)
	UIThemeHelper.apply_clay_panel(stats_section, Color(0.10, 0.08, 0.12, 0.8), 8)
	UIThemeHelper.apply_clay_panel(icon_container, Color(0.20, 0.17, 0.22, 1.0), 10)

	UIThemeHelper.apply_clay_button(btn_close_top, false)
	UIThemeHelper.apply_clay_button(btn_close_bottom, true)
	UIThemeHelper.apply_icon_button(btn_close_bottom, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(24, 24))

	btn_close_top.pressed.connect(close_dialog)
	btn_close_bottom.pressed.connect(close_dialog)

	btn_tab_upgrades.pressed.connect(func(): switch_category("UPGRADES"))
	btn_tab_tanks.pressed.connect(func(): switch_category("TANKS"))
	btn_tab_items.pressed.connect(func(): switch_category("ITEMS"))
	btn_tab_buildings.pressed.connect(func(): switch_category("BUILDINGS"))
	btn_tab_terrain.pressed.connect(func(): switch_category("TERRAIN"))

	switch_category("UPGRADES")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_dialog()

func switch_category(cat: String) -> void:
	current_category = cat
	SoundManager.play_shot(get_tree())

	# Update tab button highlights
	_update_tab_buttons_appearance()

	# Rebuild item list for this category
	_rebuild_item_list()

	# Focus first item in new category
	if active_item_buttons.size() > 0:
		active_item_buttons[0].grab_focus()

func _update_tab_buttons_appearance() -> void:
	var tabs = [
		{"btn": btn_tab_upgrades, "id": "UPGRADES"},
		{"btn": btn_tab_tanks, "id": "TANKS"},
		{"btn": btn_tab_items, "id": "ITEMS"},
		{"btn": btn_tab_buildings, "id": "BUILDINGS"},
		{"btn": btn_tab_terrain, "id": "TERRAIN"}
	]

	for tab in tabs:
		var btn: Button = tab["btn"]
		var is_selected: bool = (tab["id"] == current_category)
		UIThemeHelper.apply_clay_button(btn, not is_selected)
		if is_selected:
			btn.modulate = Color(1.3, 1.2, 0.7, 1.0)
		else:
			btn.modulate = Color(0.85, 0.85, 0.9, 1.0)

func _rebuild_item_list() -> void:
	# Clear old list buttons
	for child in item_list_vbox.get_children():
		child.queue_free()
	active_item_buttons.clear()

	var entries = EncyclopediaData.get_entries_by_category(current_category)
	if entries.is_empty():
		return

	for i in range(entries.size()):
		var entry = entries[i]
		var item_btn = Button.new()
		item_btn.custom_minimum_size = Vector2(0, 46)
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.text = "  " + entry.get("name", "Unknown")
		item_btn.clip_text = true

		# Add small icon if available
		var icon_path = str(entry.get("icon", ""))
		if not icon_path.is_empty():
			var tex = TextureHelper.get_tex(icon_path)
			if tex:
				item_btn.icon = tex
				item_btn.expand_icon = true
				item_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

		UIThemeHelper.apply_clay_button(item_btn, true)
		item_btn.pressed.connect(func(): _select_entry(entry, item_btn))
		item_btn.focus_entered.connect(func(): _select_entry(entry, item_btn))

		item_list_vbox.add_child(item_btn)
		active_item_buttons.append(item_btn)

	# Auto display first entry
	if entries.size() > 0 and active_item_buttons.size() > 0:
		_select_entry(entries[0], active_item_buttons[0])

func _select_entry(entry: Dictionary, selected_btn: Button = null) -> void:
	# Highlight selected button
	for btn in active_item_buttons:
		if btn == selected_btn:
			btn.modulate = Color(1.2, 1.15, 0.7, 1.0)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Update Icon
	var icon_path = str(entry.get("icon", ""))
	if not icon_path.is_empty():
		var tex = TextureHelper.get_tex(icon_path)
		icon_texture.texture = tex
	else:
		icon_texture.texture = null

	# Update Name & Tag
	detail_name.text = str(entry.get("name", "UNKNOWN"))
	detail_tag.text = "【 " + str(entry.get("tag", "GENERAL")) + " 】"

	# Update Stats Grid
	for child in stats_vbox.get_children():
		child.queue_free()

	var stats: Dictionary = entry.get("stats", {})
	for k in stats.keys():
		var row = HBoxContainer.new()
		row.theme_override_constants.separation = 8

		var lbl_k = Label.new()
		lbl_k.text = "• " + str(k) + ":"
		lbl_k.custom_minimum_size = Vector2(90, 0)
		lbl_k.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45, 1.0))
		lbl_k.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl_k)

		var lbl_v = Label.new()
		lbl_v.text = str(stats[k])
		lbl_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_v.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
		lbl_v.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl_v)

		stats_vbox.add_child(row)

	# Update Descriptions & Tactical Tips
	desc_text.text = str(entry.get("desc", "No archive records available."))
	tactics_text.text = str(entry.get("tactics", "No tactical notes recorded."))

func open_dialog() -> void:
	visible = true
	SoundManager.play_shot(get_tree())
	switch_category("TANKS")
	UIThemeHelper.focus_first(self)

func close_dialog() -> void:
	SoundManager.play_shot(get_tree())
	visible = false
	emit_signal("closed")
