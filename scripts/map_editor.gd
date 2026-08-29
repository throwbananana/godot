class_name MapEditor
extends Control

## 关卡编辑器: 手绘一张 13x13 地形图, 存进 CustomMapStore, 并指定它出现在
## 战役的哪些 Act / 战斗类型 / 最低楼层 —— 跟 map_templates.gd 里内置模板
## 的 TEMPLATE_MIN_FLOOR + 各 actN_pool 是同一套分档语言, 只是数据来自玩家
## 而不是常量数组。整套界面在代码里现搭 (跟 shop_dialog.gd / event_dialog.gd
## 一样), map_editor.tscn 只挂了这一个脚本和背景色。

const GameState = preload("res://scripts/game_state.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")
const CustomMapStore = preload("res://scripts/custom_map_store.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

const GRID_SIZE := 13
const CELL_PX := 34

## 调色板数据, 对应 map_templates.gd 顶部的地形图例。38/39 在图例里是空号,
## 故意不出现在这里 —— 出现了也没有对应的行为场景, main.gd 的 tile_type
## 分派链根本没有这两个分支。
const TILE_INFO := {
	0: {"label": "空地", "color": Color(0.55, 0.58, 0.42)},
	1: {"label": "砖墙", "color": Color(0.72, 0.42, 0.28)},
	2: {"label": "钢墙", "color": Color(0.55, 0.58, 0.62)},
	3: {"label": "水域", "color": Color(0.25, 0.45, 0.75)},
	4: {"label": "树林", "color": Color(0.22, 0.50, 0.25)},
	5: {"label": "地雷", "color": Color(0.75, 0.15, 0.15)},
	6: {"label": "沙地", "color": Color(0.82, 0.72, 0.45)},
	7: {"label": "沙丘", "color": Color(0.70, 0.58, 0.32)},
	8: {"label": "硬黏土", "color": Color(0.60, 0.42, 0.32)},
	9: {"label": "浮冰", "color": Color(0.75, 0.88, 0.92)},
	10: {"label": "平台(横)", "color": Color(0.50, 0.50, 0.60)},
	11: {"label": "平台(竖)", "color": Color(0.50, 0.50, 0.60)},
	12: {"label": "虫洞", "color": Color(0.50, 0.20, 0.70)},
	13: {"label": "护盾站", "color": Color(0.30, 0.70, 0.85)},
	14: {"label": "风机↑", "color": Color(0.60, 0.75, 0.85)},
	15: {"label": "风机↓", "color": Color(0.60, 0.75, 0.85)},
	16: {"label": "风机←", "color": Color(0.60, 0.75, 0.85)},
	17: {"label": "风机→", "color": Color(0.60, 0.75, 0.85)},
	18: {"label": "传送带↑", "color": Color(0.65, 0.55, 0.30)},
	19: {"label": "传送带↓", "color": Color(0.65, 0.55, 0.30)},
	20: {"label": "传送带←", "color": Color(0.65, 0.55, 0.30)},
	21: {"label": "传送带→", "color": Color(0.65, 0.55, 0.30)},
	22: {"label": "跳板", "color": Color(0.85, 0.65, 0.25)},
	23: {"label": "平台(左)", "color": Color(0.50, 0.50, 0.60)},
	24: {"label": "路灯", "color": Color(0.90, 0.85, 0.50)},
	25: {"label": "电墙", "color": Color(0.80, 0.85, 0.20)},
	26: {"label": "油桶", "color": Color(0.85, 0.40, 0.10)},
	27: {"label": "干扰塔", "color": Color(0.55, 0.25, 0.55)},
	28: {"label": "工厂", "color": Color(0.45, 0.45, 0.50)},
	29: {"label": "浮桥补给", "color": Color(0.35, 0.55, 0.70)},
	30: {"label": "护盾塔(敌)", "color": Color(0.75, 0.25, 0.25)},
	31: {"label": "管道(左上)", "color": Color(0.40, 0.40, 0.75)},
	32: {"label": "管道(上右)", "color": Color(0.40, 0.40, 0.75)},
	33: {"label": "管道(右下)", "color": Color(0.40, 0.40, 0.75)},
	34: {"label": "管道(下左)", "color": Color(0.40, 0.40, 0.75)},
	35: {"label": "雷达站", "color": Color(0.35, 0.65, 0.60)},
	36: {"label": "弹药库", "color": Color(0.80, 0.30, 0.20)},
	37: {"label": "指挥部", "color": Color(0.40, 0.35, 0.55)},
	40: {"label": "碉堡↑", "color": Color(0.50, 0.42, 0.35)},
	41: {"label": "碉堡→", "color": Color(0.50, 0.42, 0.35)},
	42: {"label": "碉堡↓", "color": Color(0.50, 0.42, 0.35)},
	43: {"label": "碉堡←", "color": Color(0.50, 0.42, 0.35)},
	44: {"label": "木墙", "color": Color(0.55, 0.40, 0.22)},
}

const CATEGORY_TILES := {
	"TERRAIN": [0, 1, 2, 3, 4, 6, 7, 8, 9, 44],
	"MECHANIC": [10, 11, 12, 18, 19, 20, 21, 22, 23, 26, 27, 31, 32, 33, 34],
	"STRUCTURE": [5, 13, 14, 15, 16, 17, 24, 25, 28, 29, 30, 35, 36, 37, 40, 41, 42, 43],
}

## (col, row) —— 跟 MapDirector.reachable_from_base() 的 Vector2i(c, r) 约定
## 保持一致。main.gd::_spawn_base_and_walls() 自己在这些格子上生成鹰巢/围墙,
## main.gd::_place_players_at_entry() 自己在两个玩家出生格上落地坦克 ——
## 编辑器里画了也会被覆盖, 干脆锁死不给画, 比保存时才报错更直接。
const RESERVED_CELLS: Array = [
	Vector2i(5, 11), Vector2i(6, 11), Vector2i(7, 11),
	Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12),
	Vector2i(4, 12), Vector2i(8, 12),
	Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0),
]

var _grid: Array = []
var _cell_buttons: Array = []
var _palette_buttons: Dictionary = {}
var _palette_tab_buttons: Dictionary = {}
var _current_palette_cat: String = "ALL"
var _selected_tile: int = 1
var _current_id: String = ""

var level_list: ItemList
var status_label: Label
var name_edit: LineEdit
var chk_act: Dictionary = {}
var chk_type: Dictionary = {}
var spin_min_floor: SpinBox
var palette_grid_node: GridContainer = null


func _ready() -> void:
	_init_blank_grid()
	_build_ui()
	_refresh_level_list()
	_refresh_grid_visuals()
	_select_palette_tile(1)
	UIThemeHelper.focus_first(self)


func _init_blank_grid() -> void:
	_grid = []
	for r in range(GRID_SIZE):
		var row: Array = []
		row.resize(GRID_SIZE)
		row.fill(0)
		_grid.append(row)


# ---------------------------------------------------------------------------
# UI 搭建
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.14, 0.18, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	_build_top_bar(root_vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(hbox)

	_build_level_list_panel(hbox)
	_build_grid_panel(hbox)
	_build_palette_and_save_panel(hbox)


func _build_top_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)

	var title := Label.new()
	title.text = "LEVEL & MAP EDITOR (关卡编辑器)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.35, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	var btn_back := Button.new()
	btn_back.text = "BACK (返回)"
	btn_back.custom_minimum_size = Vector2(140, 38)
	UIThemeHelper.apply_icon_button(btn_back, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(22, 22))
	btn_back.pressed.connect(_on_back_pressed)
	bar.add_child(btn_back)


func _build_level_list_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	UIThemeHelper.apply_clay_panel(panel)
	parent.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var lbl := Label.new()
	lbl.text = "MY LEVELS (我的关卡)"
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	vb.add_child(lbl)

	level_list = ItemList.new()
	level_list.custom_minimum_size = Vector2(0, 260)
	level_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(level_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vb.add_child(btn_row)
	var btn_new := Button.new()
	btn_new.text = "新建"
	btn_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_new, "res://assets/sprites/ui/ui_icon_gift.png", Vector2(18, 18))
	btn_new.pressed.connect(_on_new_pressed)
	btn_row.add_child(btn_new)

	var btn_load := Button.new()
	btn_load.text = "载入"
	btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_load, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(18, 18))
	btn_load.pressed.connect(_on_load_pressed)
	btn_row.add_child(btn_load)

	var btn_row2 := HBoxContainer.new()
	btn_row2.add_theme_constant_override("separation", 6)
	vb.add_child(btn_row2)
	var btn_dup := Button.new()
	btn_dup.text = "克隆"
	btn_dup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_dup, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(18, 18))
	btn_dup.pressed.connect(_on_duplicate_pressed)
	btn_row2.add_child(btn_dup)

	var btn_del := Button.new()
	btn_del.text = "删除"
	btn_del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_del, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(18, 18))
	btn_del.pressed.connect(_on_delete_pressed)
	btn_row2.add_child(btn_del)


func _build_grid_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	UIThemeHelper.apply_clay_panel(panel)
	parent.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	vb.add_child(toolbar)

	var lbl := Label.new()
	lbl.text = "CANVAS (13x13 地形)"
	lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.40, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(lbl)

	var btn_brick := Button.new()
	btn_brick.text = "砖墙"
	UIThemeHelper.apply_clay_button(btn_brick)
	btn_brick.pressed.connect(func(): _select_palette_tile(1))
	toolbar.add_child(btn_brick)

	var btn_steel := Button.new()
	btn_steel.text = "钢墙"
	UIThemeHelper.apply_clay_button(btn_steel)
	btn_steel.pressed.connect(func(): _select_palette_tile(2))
	toolbar.add_child(btn_steel)

	var btn_erase := Button.new()
	btn_erase.text = "橡皮"
	UIThemeHelper.apply_clay_button(btn_erase)
	btn_erase.pressed.connect(func(): _select_palette_tile(0))
	toolbar.add_child(btn_erase)

	var btn_fill := Button.new()
	btn_fill.text = "铺满"
	UIThemeHelper.apply_clay_button(btn_fill)
	btn_fill.pressed.connect(func(): _fill_canvas(_selected_tile))
	toolbar.add_child(btn_fill)

	var btn_clr := Button.new()
	btn_clr.text = "清空"
	UIThemeHelper.apply_clay_button(btn_clr)
	btn_clr.pressed.connect(_clear_canvas)
	toolbar.add_child(btn_clr)

	var grid := GridContainer.new()
	grid.columns = GRID_SIZE
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	vb.add_child(grid)

	_cell_buttons = []
	for r in range(GRID_SIZE):
		var row_buttons: Array = []
		for c in range(GRID_SIZE):
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
			btn.focus_mode = Control.FOCUS_NONE
			btn.gui_input.connect(_on_cell_gui_input.bind(r, c))
			grid.add_child(btn)
			row_buttons.append(btn)
		_cell_buttons.append(row_buttons)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	vb.add_child(status_label)


func _build_palette_and_save_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 0)
	UIThemeHelper.apply_clay_panel(panel)
	parent.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var lbl_p := Label.new()
	lbl_p.text = "PALETTE (地形调色板)"
	lbl_p.add_theme_color_override("font_color", Color(0.98, 0.85, 0.40, 1))
	vb.add_child(lbl_p)

	# Category Tabs
	var cat_tabs := HBoxContainer.new()
	cat_tabs.add_theme_constant_override("separation", 4)
	vb.add_child(cat_tabs)

	_palette_tab_buttons = {}
	for cat_info in [["ALL", "全部"], ["TERRAIN", "地形"], ["MECHANIC", "机关"], ["STRUCTURE", "建筑"]]:
		var cat_id = cat_info[0]
		var cat_label = cat_info[1]
		var tab_btn := Button.new()
		tab_btn.text = cat_label
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIThemeHelper.apply_clay_tab_button(tab_btn, cat_id == _current_palette_cat)
		tab_btn.pressed.connect(func(): _filter_palette(cat_id))
		cat_tabs.add_child(tab_btn)
		_palette_tab_buttons[cat_id] = tab_btn

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	palette_grid_node = GridContainer.new()
	palette_grid_node.columns = 2
	palette_grid_node.add_theme_constant_override("h_separation", 4)
	palette_grid_node.add_theme_constant_override("v_separation", 4)
	scroll.add_child(palette_grid_node)

	_palette_buttons = {}
	var ids: Array = TILE_INFO.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = TILE_INFO[id]
		var btn := Button.new()
		btn.text = "%d %s" % [id, info["label"]]
		btn.custom_minimum_size = Vector2(120, 28)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = info["color"]
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		var sb_sel: StyleBoxFlat = sb.duplicate()
		sb_sel.border_width_left = 3
		sb_sel.border_width_top = 3
		sb_sel.border_width_right = 3
		sb_sel.border_width_bottom = 3
		sb_sel.border_color = Color(1, 1, 1, 1)
		btn.add_theme_stylebox_override("pressed", sb_sel)
		btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.05, 0.05, 0.05, 1))
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_palette_pressed.bind(id))
		palette_grid_node.add_child(btn)
		_palette_buttons[id] = btn

	vb.add_child(HSeparator.new())

	var lbl_s := Label.new()
	lbl_s.text = "SAVE AS (保存到关卡池)"
	lbl_s.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	vb.add_child(lbl_s)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "关卡名称"
	vb.add_child(name_edit)

	var acts_lbl := Label.new()
	acts_lbl.text = "出现在哪些 Act (视觉主题):"
	acts_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(acts_lbl)
	var acts_row := HBoxContainer.new()
	vb.add_child(acts_row)
	chk_act = {}
	for pair in [[1, "Act1 平原"], [2, "Act2 沙漠"], [3, "Act3 极地"]]:
		var cb := CheckBox.new()
		cb.text = pair[1]
		acts_row.add_child(cb)
		chk_act[pair[0]] = cb
	chk_act[1].button_pressed = true

	var types_lbl := Label.new()
	types_lbl.text = "出现在哪些战斗类型:"
	types_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(types_lbl)
	var types_row := HBoxContainer.new()
	vb.add_child(types_row)
	chk_type = {}
	for pair in [["battle", "普通"], ["elite", "精英"], ["boss", "Boss"], ["shop", "商店"]]:
		var cb2 := CheckBox.new()
		cb2.text = pair[1]
		types_row.add_child(cb2)
		chk_type[pair[0]] = cb2
	chk_type["battle"].button_pressed = true

	var floor_row := HBoxContainer.new()
	vb.add_child(floor_row)
	var floor_lbl := Label.new()
	floor_lbl.text = "最低楼层 (Min Floor, 0-14): "
	floor_lbl.add_theme_font_size_override("font_size", 11)
	floor_row.add_child(floor_lbl)
	spin_min_floor = SpinBox.new()
	spin_min_floor.min_value = 0
	spin_min_floor.max_value = 14
	spin_min_floor.step = 1
	spin_min_floor.value = 0
	floor_row.add_child(spin_min_floor)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	vb.add_child(save_row)
	var btn_save := Button.new()
	btn_save.text = "SAVE (保存)"
	btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_save, "res://assets/sprites/ui/ui_badge_key.png", Vector2(20, 20))
	btn_save.pressed.connect(_on_save_pressed)
	save_row.add_child(btn_save)

	var btn_test := Button.new()
	btn_test.text = "TEST (试玩)"
	btn_test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.apply_icon_button(btn_test, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(20, 20))
	btn_test.pressed.connect(_on_test_pressed)
	save_row.add_child(btn_test)


func _filter_palette(cat: String) -> void:
	_current_palette_cat = cat
	for cid in _palette_tab_buttons:
		UIThemeHelper.apply_clay_tab_button(_palette_tab_buttons[cid], cid == cat)

	var allowed: Array = []
	if cat in CATEGORY_TILES:
		allowed = CATEGORY_TILES[cat]

	for id in _palette_buttons:
		var btn: Button = _palette_buttons[id]
		btn.visible = (cat == "ALL" or id in allowed)


func _fill_canvas(tile_id: int) -> void:
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			if Vector2i(c, r) not in RESERVED_CELLS:
				_grid[r][c] = tile_id
	_refresh_grid_visuals()


func _clear_canvas() -> void:
	_init_blank_grid()
	_refresh_grid_visuals()
	status_label.text = "已清空画布。"


# ---------------------------------------------------------------------------
# 画布交互
# ---------------------------------------------------------------------------

func _on_cell_gui_input(event: InputEvent, r: int, c: int) -> void:
	if Vector2i(c, r) in RESERVED_CELLS:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_paint_cell(r, c, _selected_tile)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_paint_cell(r, c, 0)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_paint_cell(r, c, _selected_tile)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_paint_cell(r, c, 0)


func _paint_cell(r: int, c: int, tile_id: int) -> void:
	if _grid[r][c] == tile_id:
		return
	_grid[r][c] = tile_id
	_style_one_cell(r, c)


func _on_palette_pressed(id: int) -> void:
	_select_palette_tile(id)


func _select_palette_tile(id: int) -> void:
	_selected_tile = id
	for pid in _palette_buttons:
		_palette_buttons[pid].button_pressed = (pid == id)


func _style_one_cell(r: int, c: int) -> void:
	var btn: Button = _cell_buttons[r][c]
	var tile_id: int = _grid[r][c]
	var info: Dictionary = TILE_INFO.get(tile_id, {"label": "?", "color": Color(1, 0, 1)})
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	if Vector2i(c, r) in RESERVED_CELLS:
		sb.bg_color = Color(0.25, 0.25, 0.28, 1.0)
		btn.text = "X"
		btn.disabled = true
		btn.tooltip_text = "保留格 (鹰巢/出生点), main.gd 自动生成, 不可编辑"
	else:
		sb.bg_color = info["color"]
		btn.text = str(tile_id) if tile_id != 0 else ""
		btn.disabled = false
		btn.tooltip_text = "%d %s" % [tile_id, info.get("label", "?")]
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1))
	btn.add_theme_font_size_override("font_size", 11)


func _refresh_grid_visuals() -> void:
	for r in range(GRID_SIZE):
		for c in range(GRID_SIZE):
			_style_one_cell(r, c)


# ---------------------------------------------------------------------------
# 关卡列表 (左侧面板)
# ---------------------------------------------------------------------------

func _refresh_level_list() -> void:
	level_list.clear()
	for entry in CustomMapStore.load_all():
		var idx := level_list.add_item(entry.get("name", "(未命名)"))
		level_list.set_item_metadata(idx, entry.get("id", ""))


func _get_selected_entry() -> Dictionary:
	var sel := level_list.get_selected_items()
	if sel.is_empty():
		return {}
	var id = level_list.get_item_metadata(sel[0])
	return CustomMapStore.get_by_id(id)


func _on_new_pressed() -> void:
	_current_id = ""
	name_edit.text = ""
	spin_min_floor.value = 0
	for k in chk_act:
		chk_act[k].button_pressed = (k == 1)
	for k in chk_type:
		chk_type[k].button_pressed = (k == "battle")
	_init_blank_grid()
	_refresh_grid_visuals()
	status_label.text = ""


func _load_entry(entry: Dictionary, as_duplicate: bool) -> void:
	_current_id = "" if as_duplicate else str(entry.get("id", ""))
	name_edit.text = (str(entry.get("name", "")) + " (副本)") if as_duplicate else str(entry.get("name", ""))
	spin_min_floor.value = int(entry.get("min_floor", 0))
	var acts: Array = entry.get("acts", [])
	for k in chk_act:
		chk_act[k].button_pressed = acts.has(k)
	var types: Array = entry.get("battle_types", [])
	for k in chk_type:
		chk_type[k].button_pressed = types.has(k)
	var layout: Array = entry.get("layout", [])
	if layout.size() == GRID_SIZE:
		_grid = layout.duplicate(true)
	else:
		_init_blank_grid()
	_refresh_grid_visuals()
	status_label.text = ""


func _on_load_pressed() -> void:
	var entry := _get_selected_entry()
	if entry.is_empty():
		_show_status("请先在左侧列表选一个关卡", false)
		return
	_load_entry(entry, false)


func _on_duplicate_pressed() -> void:
	var entry := _get_selected_entry()
	if entry.is_empty():
		_show_status("请先在左侧列表选一个关卡", false)
		return
	_load_entry(entry, true)


func _on_delete_pressed() -> void:
	var sel := level_list.get_selected_items()
	if sel.is_empty():
		return
	var id = level_list.get_item_metadata(sel[0])
	CustomMapStore.delete(id)
	if id == _current_id:
		_on_new_pressed()
	_refresh_level_list()


# ---------------------------------------------------------------------------
# 保存 / 试玩
# ---------------------------------------------------------------------------

func _collect_acts() -> Array:
	var out: Array = []
	for k in chk_act:
		if chk_act[k].button_pressed:
			out.append(k)
	return out


func _collect_types() -> Array:
	var out: Array = []
	for k in chk_type:
		if chk_type[k].button_pressed:
			out.append(k)
	return out


func _show_status(msg: String, ok: bool) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55) if ok else Color(0.95, 0.45, 0.45))


func _on_save_pressed() -> void:
	var errs := MapTemplates.validate_layout(_grid)
	if not errs.is_empty():
		_show_status("地图不合法: " + "; ".join(errs), false)
		return
	var types := _collect_types()
	if types.is_empty():
		_show_status("请至少选择一种战斗类型", false)
		return
	var acts := _collect_acts()
	var non_shop: Array = types.filter(func(t): return t != "shop")
	if not non_shop.is_empty() and acts.is_empty():
		_show_status("普通/精英/Boss 至少要选一个 Act", false)
		return

	var nm := name_edit.text.strip_edges()
	if nm.is_empty():
		nm = "自定义地图"
	var id := _current_id if not _current_id.is_empty() else CustomMapStore.next_id()
	var entry := {
		"id": id,
		"name": nm,
		"layout": _grid.duplicate(true),
		"acts": acts,
		"battle_types": types,
		"min_floor": int(spin_min_floor.value),
	}
	CustomMapStore.upsert(entry)
	_current_id = id
	_refresh_level_list()
	_show_status("已保存: %s" % nm, true)


func _on_test_pressed() -> void:
	var errs := MapTemplates.validate_layout(_grid)
	if not errs.is_empty():
		_show_status("地图不合法, 无法试玩: " + "; ".join(errs), false)
		return
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 1
	GameState.playtest_layout = _grid.duplicate(true)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
