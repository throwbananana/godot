class_name DebugTestMenu
extends Control

## 隐藏测试模式的关卡跳转台。只能从 title_screen.gd 那颗解锁后才可见的
## TEST MODE 按钮进来 (GameState.debug_unlocked), 跟 map_editor.gd 一样整块
## UI 在代码里现搭 (不额外维护一份深层嵌套的 .tscn)。
##
## 核心思路是"复用房间系统本来就有的机关, 不另起一套战斗入口":
## 1. GameState.reset_campaign() + 指定 act 的 generate_floor() 生成一层
##    正常的、连通性合法的楼层 —— 跳关不代表可以跳过房间图这一层验收。
## 2. 直接把生成出来的起始房 (它默认 type="start", cleared=true, 不会刷怪)
##    在代码里改写成想测试的战斗类型, 并把 cleared 拨回 false —— 这正是
##    main.gd::enter_room() 判定 is_combat / 战斗奖励 / 商店货架池的唯一依据
##    (GameState.battle_type_for_room()), 不用另写一条"调试专用"的建图路径。
## 3. 如果测试者选了具体的内置模板或自建地图, 走 GameState.playtest_layout ——
##    这是关卡编辑器"试玩"按钮已经在用的一次性图层覆盖 (main.gd::_build_map()
##    最高优先级分支, 用完自动清空), 同一个机关刚好也能承载"跳关时强制这张图"。
##
## 进了战斗之后想开金币/加等级/杀光本房敌人这些, 走 main.gd 里另一半的隐藏
## 面板 (F1 呼出, 同样挂 GameState.debug_unlocked 门槛), 这个场景只负责
## "去哪一关"。

const GameState = preload("res://scripts/game_state.gd")
const MapTemplates = preload("res://scripts/map_templates.gd")
const CustomMapStore = preload("res://scripts/custom_map_store.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")

## OptionButton 里 "战斗类型" 的显示项, 对应 GameState.battle_type_for_room()
## 认得的 room["type"] 取值 (第一个是 room["type"] 要写的值, 第二个是显示文字)。
const BATTLE_TYPE_OPTIONS := [
	["normal", "⚔️ 普通战斗 (Normal Battle)"],
	["elite", "🔥 精英战斗 (Elite Battle)"],
	["boss", "👑 Boss 战 (Boss Fight)"],
	["shop", "🛒 商店房 (Shop Room)"],
	["challenge", "☠️ 挑战房 (Challenge Room)"],
]

const CHALLENGE_MODE_OPTIONS := [
	["bomb_rain", "💣 炸弹雨 (Bomb Rain)"],
	["night_ops", "🌑 夜战 (Night Ops)"],
	["night_bombs", "🌑💣 夜战+炸弹雨 (Night + Bombs)"],
]

var status_label: Label
var spin_act: SpinBox
var opt_players: OptionButton
var opt_battle_type: OptionButton
var opt_challenge_mode: OptionButton
var opt_layout: OptionButton
var challenge_row: HBoxContainer

## opt_layout 每一项对应的 (kind, value): kind 是 "random"/"builtin"/"custom",
## value 是内置模板常量名 (String) 或自定义地图 id (String); "random" 不用 value。
var _layout_choices: Array = []


func _ready() -> void:
	_build_ui()
	UIThemeHelper.focus_first(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


# ---------------------------------------------------------------------------
# UI 搭建
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.16, 0.10, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	UIThemeHelper.apply_clay_panel(panel, Color(0.13, 0.18, 0.13, 0.97), 16)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "🧪 HIDDEN TEST MODE (隐藏测试模式)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "跳转到任意 Act / 战斗类型 / 地形进行测试。进入战斗后按 F1 呼出调试工具面板 (加金币/加等级/无敌/清空敌人/夜战开关)。"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75, 1))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(subtitle)

	vb.add_child(HSeparator.new())

	# 玩家人数
	var row_players := _make_row(vb, "玩家人数 (Players):")
	opt_players = OptionButton.new()
	UIThemeHelper.apply_clay_option_button(opt_players)
	opt_players.add_item("1P 单人")
	opt_players.add_item("2P 双人")
	row_players.add_child(opt_players)

	# Act
	var row_act := _make_row(vb, "幕数 Act (1-%d):" % GameState.max_acts)
	spin_act = SpinBox.new()
	spin_act.min_value = 1
	spin_act.max_value = GameState.max_acts
	spin_act.step = 1
	spin_act.value = 1
	spin_act.custom_minimum_size = Vector2(120, 0)
	row_act.add_child(spin_act)

	# 战斗类型
	var row_type := _make_row(vb, "战斗类型 (Room Type):")
	opt_battle_type = OptionButton.new()
	UIThemeHelper.apply_clay_option_button(opt_battle_type)
	for pair in BATTLE_TYPE_OPTIONS:
		opt_battle_type.add_item(pair[1])
	opt_battle_type.item_selected.connect(_on_battle_type_selected)
	row_type.add_child(opt_battle_type)

	# 挑战子模式 (只有选了"挑战房"才用得上, 但常驻显示避免切换时布局跳动)
	challenge_row = _make_row(vb, "挑战子类型 (Challenge Mode):")
	opt_challenge_mode = OptionButton.new()
	UIThemeHelper.apply_clay_option_button(opt_challenge_mode)
	for pair in CHALLENGE_MODE_OPTIONS:
		opt_challenge_mode.add_item(pair[1])
	challenge_row.add_child(opt_challenge_mode)
	challenge_row.visible = false

	# 地形/地图
	var row_layout := _make_row(vb, "地形 Layout:")
	opt_layout = OptionButton.new()
	UIThemeHelper.apply_clay_option_button(opt_layout)
	_populate_layout_options()
	row_layout.add_child(opt_layout)

	vb.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(status_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var btn_back := Button.new()
	btn_back.text = "BACK (返回)"
	btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_back.custom_minimum_size = Vector2(0, 40)
	UIThemeHelper.apply_icon_button(btn_back, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(20, 20))
	btn_back.pressed.connect(_on_back_pressed)
	btn_row.add_child(btn_back)

	var btn_jump := Button.new()
	btn_jump.text = "🚀 JUMP & START (跳转开始)"
	btn_jump.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_jump.custom_minimum_size = Vector2(0, 40)
	UIThemeHelper.apply_clay_button(btn_jump, false)
	btn_jump.pressed.connect(_on_jump_pressed)
	btn_row.add_child(btn_jump)


func _make_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(190, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9, 1))
	row.add_child(lbl)
	return row


func _populate_layout_options() -> void:
	_layout_choices = []

	opt_layout.add_item("🎲 随机 (按选中的战斗类型正常抽池/程序生成)")
	_layout_choices.append(["random", ""])

	# 必须走 load() 拿 Script *对象*, 直接写 MapTemplates.get_script_constant_map()
	# 会被解析成"在类上调用非静态方法"编译失败 (class_name 标识符指类本身,
	# 不是脚本资源) —— 跟 tools/test_map_templates_and_base_fit.gd 踩的是
	# 同一个坑, 那边已经记录过原因。
	var template_names: Array = []
	var map_templates_script: Script = load("res://scripts/map_templates.gd")
	for key in map_templates_script.get_script_constant_map().keys():
		if str(key).begins_with("TEMPLATE_"):
			template_names.append(str(key))
	template_names.sort()
	for name in template_names:
		opt_layout.add_item("📐 " + name.trim_prefix("TEMPLATE_"))
		_layout_choices.append(["builtin", name])

	for entry in CustomMapStore.load_all():
		var nm := str(entry.get("name", "(未命名)"))
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		opt_layout.add_item("✏️ " + nm)
		_layout_choices.append(["custom", id])


func _on_battle_type_selected(idx: int) -> void:
	var type_id: String = BATTLE_TYPE_OPTIONS[idx][0]
	challenge_row.visible = (type_id == "challenge")


# ---------------------------------------------------------------------------
# 跳转
# ---------------------------------------------------------------------------

func _on_jump_pressed() -> void:
	SoundManager.play_shot(get_tree())

	var p_count := 1 if opt_players.selected == 0 else 2
	var act := int(spin_act.value)
	var type_idx := opt_battle_type.selected
	if type_idx < 0:
		type_idx = 0
	var room_type: String = BATTLE_TYPE_OPTIONS[type_idx][0]
	var challenge_kind := ""
	if room_type == "challenge":
		var c_idx := opt_challenge_mode.selected
		if c_idx < 0:
			c_idx = 0
		challenge_kind = CHALLENGE_MODE_OPTIONS[c_idx][0]

	# 干净重开一份战役状态再指定 act —— 跳关是"去测某一关", 不是要延续存档
	# 里的战备/关卡进度; 顺带把 run_seed 重新摇出来 (0 是 _pick_from_pool()
	# 认的"没有种子"哨兵值, 不重置的话新进程首次直接跳关会撞上它)。
	GameState.reset_campaign(p_count)
	GameState.current_act = act
	GameState.generate_floor()

	var room_key := GameState.current_room
	if not GameState.floor_rooms.has(room_key):
		_show_status("生成楼层失败, 找不到起始房。", false)
		return
	var room: Dictionary = GameState.floor_rooms[room_key]
	room["type"] = room_type
	room["challenge_mode"] = challenge_kind
	# 起始房默认 cleared=true (它本来就是空房, 不需要打) —— 强制改成战斗类型后
	# 必须拨回 false, 否则 FloorMap.is_combat_room() 会认为这仗已经打完,
	# main.gd::enter_room() 就不会刷怪, 门也不会锁。
	room["cleared"] = false
	GameState.floor_rooms[room_key] = room

	var layout_choice: Array = _layout_choices[opt_layout.selected] if opt_layout.selected >= 0 else ["random", ""]
	match layout_choice[0]:
		"builtin":
			var map_templates_script: Script = load("res://scripts/map_templates.gd")
			var consts := map_templates_script.get_script_constant_map()
			var name: String = layout_choice[1]
			if consts.has(name):
				GameState.playtest_layout = (consts[name] as Array).duplicate(true)
		"custom":
			var entry := CustomMapStore.get_by_id(layout_choice[1])
			var layout: Array = entry.get("layout", [])
			if layout.size() == 13:
				GameState.playtest_layout = layout.duplicate(true)
		_:
			GameState.playtest_layout = []

	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_status(msg: String, ok: bool) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55) if ok else Color(0.95, 0.45, 0.45))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
