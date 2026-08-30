class_name Minimap
extends Control

## HUD 上的楼层小地图与战术全景大地图系统。
##
## 支持两种显示模式:
## 1. 侧栏停靠模式 (Docked): 嵌入 HUD 侧栏，按 20px 网格清晰显示房间图标与探索迷雾。
## 2. 战术全景模式 (Maximized): 按 [M] 键或点击侧栏小地图展开居中大地图，显示完整
##    房间门道连接拓扑、44px 高清房间徽标、探索度统计与完整图例。

const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")
const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

## 侧栏停靠小地图网格尺寸 (从 14px 调整至 20px，显著提升可读性)
const CELL := 20.0
const GAP := 2.0
const DOCK_OFFSET := Vector2(14.0, 14.0)

## 全屏战术大地图网格尺寸
const BIG_CELL := 44.0
const BIG_GAP := 5.0

# 房型后备颜色 (贴图缺失时的 fallback)
const TYPE_DOTS := {
	"start": Color(0.40, 0.85, 0.50),
	"boss": Color(0.95, 0.30, 0.30),
	"elite": Color(0.85, 0.45, 0.95),
	"shop": Color(0.98, 0.82, 0.30),
	"treasure": Color(0.40, 0.88, 0.92),
	"challenge": Color(0.95, 0.60, 0.30),
	"event": Color(0.65, 0.50, 0.95),
	"rest": Color(0.45, 0.90, 0.70),
	"secret": Color(0.35, 0.90, 0.95),
	"normal": Color(0.85, 0.85, 0.85),
}

var _frame_tex: Texture2D
var _active_ring_tex: Texture2D
var _room_textures: Dictionary = {}

# 全屏大地图模态相关状态
var _is_maximized: bool = false
var _modal_root: Control = null
var _modal_big_canvas: Control = null
var _modal_title_lbl: Label = null
var _modal_stats_lbl: Label = null


func _init() -> void:
	position = DOCK_OFFSET
	custom_minimum_size = Vector2(FloorMap.GRID_COLS * CELL + 28.0, FloorMap.GRID_ROWS * CELL + 28.0)
	size = custom_minimum_size


func _ready() -> void:
	_frame_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_minimap_frame.png")
	_active_ring_tex = TextureHelper.get_tex("res://assets/sprites/map/node_active_ring.png")
	
	var types := ["start", "boss", "elite", "shop", "treasure", "challenge", "event", "rest", "secret", "normal"]
	for t in types:
		var icon_name := FloorMap.icon_for_type(t)
		if not _room_textures.has(icon_name):
			var tex := TextureHelper.get_tex("res://assets/sprites/map/" + icon_name + ".png")
			if tex:
				_room_textures[icon_name] = tex

	position = DOCK_OFFSET
	custom_minimum_size = Vector2(FloorMap.GRID_COLS * CELL + 28.0, FloorMap.GRID_ROWS * CELL + 28.0)
	size = custom_minimum_size
	
	# 允许点击侧栏小地图直接展开大地图
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "点击或按 [M] 键展开战术全景大地图"
	z_index = 40


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle_maximized()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle_maximized()
			get_viewport().set_input_as_handled()
			return
	
	if _is_maximized:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_SPACE]):
			toggle_maximized(false)
			get_viewport().set_input_as_handled()


func is_maximized() -> bool:
	return _is_maximized


## 切换全屏战术大地图展开/收起
func toggle_maximized(force_state: Variant = null) -> void:
	if force_state != null:
		_is_maximized = bool(force_state)
	else:
		_is_maximized = not _is_maximized
		
	if _is_maximized:
		if not _modal_root or not is_instance_valid(_modal_root):
			_build_maximized_modal()
		_update_modal_content()
		_modal_root.visible = true
		_modal_root.modulate.a = 1.0
		if is_inside_tree() and get_tree():
			var tw = create_tween()
			if tw:
				_modal_root.modulate.a = 0.0
				tw.tween_property(_modal_root, "modulate:a", 1.0, 0.15)
			SoundManager.play_shot(get_tree())
	else:
		if _modal_root and is_instance_valid(_modal_root) and _modal_root.visible:
			if is_inside_tree() and get_tree():
				var tw = create_tween()
				if tw:
					tw.tween_property(_modal_root, "modulate:a", 0.0, 0.12)
					tw.tween_callback(func(): _modal_root.visible = false)
				else:
					_modal_root.visible = false
				SoundManager.play_shot(get_tree())
			else:
				_modal_root.visible = false


func refresh() -> void:
	queue_redraw()
	if _is_maximized and _modal_root and _modal_root.visible:
		_update_modal_content()
		if _modal_big_canvas and is_instance_valid(_modal_big_canvas):
			_modal_big_canvas.queue_redraw()


## 房间可见度判定: 0=完全未知, 1=邻近已知未探索, 2=已探索
func _room_visibility(room_key: String, room: Dictionary) -> int:
	if bool(room.get("secret", false)) and not GameState.secret_room_found:
		return 0 # 秘密房在被炸开之前隐藏
	if bool(room.get("visited", false)):
		return 2
	var c := FloorMap.parse_key(room_key)
	for d in range(4):
		var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
		var n = GameState.floor_rooms.get(nk)
		if n != null and bool(n.get("visited", false)):
			return 1
	return 0


# ==============================================================================
# 侧栏小地图渲染
# ==============================================================================
func _draw() -> void:
	if GameState.floor_rooms.is_empty():
		return

	var w := FloorMap.GRID_COLS * CELL
	var h := FloorMap.GRID_ROWS * CELL
	if _frame_tex:
		draw_texture_rect(_frame_tex, Rect2(Vector2(-14, -14), Vector2(w + 28, h + 28)), false)
	else:
		draw_rect(Rect2(Vector2(-4, -4), Vector2(w + 8, h + 8)), Color(0.06, 0.05, 0.08, 0.55), true)

	for room_key in GameState.floor_rooms.keys():
		var room: Dictionary = GameState.floor_rooms[room_key]
		var vis := _room_visibility(str(room_key), room)
		if vis == 0:
			continue

		var c := FloorMap.parse_key(str(room_key))
		var cell_rect := Rect2(
			Vector2(c.x * CELL + GAP * 0.5, c.y * CELL + GAP * 0.5),
			Vector2(CELL - GAP, CELL - GAP))

		if vis == 1:
			# 已知但未进入: 暗色底板与冷灰边框
			draw_rect(cell_rect, Color(0.12, 0.10, 0.16, 0.65), true)
			draw_rect(cell_rect, Color(0.42, 0.45, 0.55, 0.70), false, 1.0)
			continue

		var is_current := str(room_key) == GameState.current_room
		var fill: Color
		var border_color: Color
		if is_current:
			fill = Color(0.24, 0.22, 0.32, 0.95)
			border_color = Color(1.0, 0.88, 0.35, 1.0)
		elif bool(room.get("cleared", false)):
			fill = Color(0.14, 0.16, 0.20, 0.88)
			border_color = Color(0.38, 0.42, 0.50, 0.85)
		else:
			fill = Color(0.30, 0.14, 0.14, 0.90)
			border_color = Color(0.85, 0.40, 0.40, 0.85)
			
		draw_rect(cell_rect, fill, true)
		draw_rect(cell_rect, border_color, false, 1.0)

		# 绘制专属房型黏土立体图标
		var room_type: String = str(room.get("type", "normal"))
		var icon_name := FloorMap.icon_for_type(room_type)
		var tex: Texture2D = _room_textures.get(icon_name)
		if tex:
			var icon_pad := 1.5
			var icon_rect := Rect2(
				cell_rect.position + Vector2(icon_pad, icon_pad),
				cell_rect.size - Vector2(icon_pad * 2.0, icon_pad * 2.0)
			)
			draw_texture_rect(tex, icon_rect, false)
		else:
			var dot: Variant = TYPE_DOTS.get(room_type)
			if dot != null:
				draw_circle(cell_rect.get_center(), (CELL - GAP) * 0.24, dot)

		if is_current:
			if _active_ring_tex:
				var ring_pad := 2.5
				var ring_rect := Rect2(
					cell_rect.position - Vector2(ring_pad, ring_pad),
					cell_rect.size + Vector2(ring_pad * 2.0, ring_pad * 2.0)
				)
				draw_texture_rect(_active_ring_tex, ring_rect, false)
			else:
				draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 0.95), false, 1.5)


# ==============================================================================
# 全屏战术大地图模态构建与绘制
# ==============================================================================
func _build_maximized_modal() -> void:
	var target_parent: Node = null
	if is_inside_tree() and get_tree() and get_tree().root:
		target_parent = get_tree().root.find_child("HUD", true, false)
	if not target_parent:
		var p = get_parent()
		while p:
			if p.name == "HUD" or p is CanvasLayer:
				target_parent = p
				break
			p = p.get_parent()
	if not target_parent:
		target_parent = get_parent() if get_parent() else self
		
	_modal_root = Control.new()
	_modal_root.name = "MaximizedMapModal"
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.z_index = 60
	_modal_root.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# 半透明深色遮罩
	var bg_overlay := ColorRect.new()
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_overlay.color = Color(0.04, 0.03, 0.07, 0.86)
	bg_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	bg_overlay.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			toggle_maximized(false)
	)
	_modal_root.add_child(bg_overlay)
	
	# 中央主面板
	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(center_box)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 620)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.16, 0.98)
	sb.border_color = Color(0.60, 0.48, 0.75, 0.95)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	center_box.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	# 顶部标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)
	
	_modal_title_lbl = Label.new()
	_modal_title_lbl.text = "🗺️ 战役战术全景地图"
	_modal_title_lbl.add_theme_font_size_override("font_size", 16)
	_modal_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	_modal_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_modal_title_lbl)
	
	_modal_stats_lbl = Label.new()
	_modal_stats_lbl.text = "已探索: 0/0 房间"
	_modal_stats_lbl.add_theme_font_size_override("font_size", 12)
	_modal_stats_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	header.add_child(_modal_stats_lbl)
	
	var btn_close := Button.new()
	btn_close.text = " ✖ "
	btn_close.custom_minimum_size = Vector2(28, 28)
	UIThemeHelper.apply_clay_button(btn_close)
	btn_close.pressed.connect(func(): toggle_maximized(false))
	header.add_child(btn_close)
	
	vbox.add_child(HSeparator.new())
	
	# 中部大地图画布
	var map_center := CenterContainer.new()
	map_center.custom_minimum_size = Vector2(430, 420)
	vbox.add_child(map_center)
	
	var canvas_w := FloorMap.GRID_COLS * BIG_CELL
	var canvas_h := FloorMap.GRID_ROWS * BIG_CELL
	_modal_big_canvas = Control.new()
	_modal_big_canvas.custom_minimum_size = Vector2(canvas_w, canvas_h)
	_modal_big_canvas.draw.connect(_draw_big_map_canvas)
	map_center.add_child(_modal_big_canvas)
	
	vbox.add_child(HSeparator.new())
	
	# 底部图例栏 (完整展示 10 种房型)
	var legend_box := HFlowContainer.new()
	legend_box.add_theme_constant_override("h_separation", 10)
	legend_box.add_theme_constant_override("v_separation", 4)
	legend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(legend_box)
	
	var legend_items = [
		{"type": "start", "name": "基地起点"},
		{"type": "normal", "name": "普通战斗"},
		{"type": "elite", "name": "精英要塞"},
		{"type": "boss", "name": "关底BOSS"},
		{"type": "shop", "name": "军备商店"},
		{"type": "treasure", "name": "宝物强化"},
		{"type": "challenge", "name": "极限挑战"},
		{"type": "event", "name": "神秘事件"},
		{"type": "rest", "name": "战备整备"},
		{"type": "secret", "name": "隐藏密室"},
	]
	
	for item in legend_items:
		var item_hbox := HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 4)
		
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_name: String = FloorMap.icon_for_type(item["type"])
		var tex: Texture2D = _room_textures.get(icon_name)
		if tex: icon_rect.texture = tex
		item_hbox.add_child(icon_rect)
		
		var name_lbl := Label.new()
		name_lbl.text = item["name"]
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.90))
		item_hbox.add_child(name_lbl)
		
		legend_box.add_child(item_hbox)
		
	var footer_lbl := Label.new()
	footer_lbl.text = "👉 操作提示: 按 [M] 键、[ESC] 或点击背景空白处即可关闭地图"
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_lbl.add_theme_font_size_override("font_size", 11)
	footer_lbl.add_theme_color_override("font_color", Color(0.70, 0.65, 0.78))
	vbox.add_child(footer_lbl)
	
	target_parent.add_child(_modal_root)
	_modal_root.visible = false


func _update_modal_content() -> void:
	if not _modal_root: return
	
	var total_rooms := GameState.floor_rooms.size()
	var visited_count := 0
	var cleared_count := 0
	
	for rk in GameState.floor_rooms.keys():
		var r: Dictionary = GameState.floor_rooms[rk]
		if bool(r.get("visited", false)):
			visited_count += 1
		if bool(r.get("cleared", false)):
			cleared_count += 1
			
	var act_name := "关卡"
	match GameState.current_act:
		1: act_name = "森林荒原 (FOREST BATTLEFIELD)"
		2: act_name = "沙漠要塞 (DESERT FORTRESS)"
		3: act_name = "雪原极地 (FROZEN TUNDRA)"
		_: act_name = "深入战区 (DEEP WARZONE)"
		
	if _modal_title_lbl:
		_modal_title_lbl.text = "🗺️ 战役战术全景地图 - ACT %d: %s" % [GameState.current_act, act_name]
	if _modal_stats_lbl:
		_modal_stats_lbl.text = "探索进度: %d / %d 房间 (已清空: %d)" % [visited_count, total_rooms, cleared_count]


## 绘制大地图拓扑网格与门道连线
func _draw_big_map_canvas() -> void:
	if not _modal_big_canvas or GameState.floor_rooms.is_empty():
		return
		
	var canvas := _modal_big_canvas
	var w := FloorMap.GRID_COLS * BIG_CELL
	var h := FloorMap.GRID_ROWS * BIG_CELL
	
	# 背景底板
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.08, 0.07, 0.11, 0.95), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.35, 0.30, 0.45, 0.70), false, 1.5)
	
	# 1. 绘制房间之间的门道连接通道 (Corridor Connectors)
	for rk in GameState.floor_rooms.keys():
		var room: Dictionary = GameState.floor_rooms[rk]
		var vis := _room_visibility(str(rk), room)
		if vis == 0: continue
		
		var c1 := FloorMap.parse_key(str(rk))
		var center1 := Vector2((c1.x + 0.5) * BIG_CELL, (c1.y + 0.5) * BIG_CELL)
		
		var doors: Array = room.get("doors", [false, false, false, false])
		var s_doors: Array = room.get("secret_doors", [false, false, false, false])
		
		for d in [FloorMap.DIR_E, FloorMap.DIR_S]: # 只画东向和南向避免重复绘制
			if d < doors.size() and bool(doors[d]):
				var n_coord := c1 + FloorMap.DIR_VECTORS[d]
				var nk := FloorMap.key(n_coord)
				if GameState.floor_rooms.has(nk):
					var n_room: Dictionary = GameState.floor_rooms[nk]
					var n_vis := _room_visibility(nk, n_room)
					if n_vis > 0:
						var center2 := Vector2((n_coord.x + 0.5) * BIG_CELL, (n_coord.y + 0.5) * BIG_CELL)
						var is_secret = (d < s_doors.size() and bool(s_doors[d]))
						var line_color := Color(0.50, 0.48, 0.60, 0.85) if (vis == 2 and n_vis == 2) else Color(0.28, 0.25, 0.38, 0.55)
						if is_secret:
							line_color = Color(0.30, 0.85, 0.95, 0.90)
						canvas.draw_line(center1, center2, line_color, 3.5 if is_secret else 2.5)

	# 2. 绘制每个房间的单元格与高清图标
	for rk in GameState.floor_rooms.keys():
		var room: Dictionary = GameState.floor_rooms[rk]
		var vis := _room_visibility(str(rk), room)
		if vis == 0: continue
		
		var c := FloorMap.parse_key(str(rk))
		var cell_rect := Rect2(
			Vector2(c.x * BIG_CELL + BIG_GAP * 0.5, c.y * BIG_CELL + BIG_GAP * 0.5),
			Vector2(BIG_CELL - BIG_GAP, BIG_CELL - BIG_GAP)
		)
		
		if vis == 1:
			# 已知但未探索
			canvas.draw_rect(cell_rect, Color(0.14, 0.12, 0.18, 0.80), true)
			canvas.draw_rect(cell_rect, Color(0.45, 0.40, 0.55, 0.80), false, 1.2)
			continue
			
		var is_current := str(rk) == GameState.current_room
		var fill: Color
		var border_color: Color
		
		if is_current:
			fill = Color(0.26, 0.24, 0.38, 0.98)
			border_color = Color(1.0, 0.88, 0.40, 1.0)
		elif bool(room.get("cleared", false)):
			fill = Color(0.14, 0.17, 0.22, 0.94)
			border_color = Color(0.40, 0.48, 0.60, 0.90)
		else:
			fill = Color(0.32, 0.15, 0.15, 0.95)
			border_color = Color(0.88, 0.40, 0.40, 0.90)
			
		canvas.draw_rect(cell_rect, fill, true)
		canvas.draw_rect(cell_rect, border_color, false, 1.5 if is_current else 1.0)
		
		# 绘制专属房型高清大图标 (32x32px)
		var room_type: String = str(room.get("type", "normal"))
		var icon_name := FloorMap.icon_for_type(room_type)
		var tex: Texture2D = _room_textures.get(icon_name)
		if tex:
			var icon_pad := 3.5
			var icon_rect := Rect2(
				cell_rect.position + Vector2(icon_pad, icon_pad),
				cell_rect.size - Vector2(icon_pad * 2.0, icon_pad * 2.0)
			)
			canvas.draw_texture_rect(tex, icon_rect, false)
		else:
			var dot: Variant = TYPE_DOTS.get(room_type)
			if dot != null:
				canvas.draw_circle(cell_rect.get_center(), (BIG_CELL - BIG_GAP) * 0.28, dot)
				
		# 当前房间高亮聚焦光环
		if is_current:
			if _active_ring_tex:
				var ring_pad := 4.0
				var ring_rect := Rect2(
					cell_rect.position - Vector2(ring_pad, ring_pad),
					cell_rect.size + Vector2(ring_pad * 2.0, ring_pad * 2.0)
				)
				canvas.draw_texture_rect(_active_ring_tex, ring_rect, false)
			else:
				canvas.draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 1.0), false, 2.0)
