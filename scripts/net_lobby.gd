class_name NetLobby
extends Control

## 局域网联机大厅。整块 UI 在代码里搭出来, 不走 .tscn ——
## 跟 main.gd::_build_debug_panel() / UIThemeHelper.create_victory_defeat_modal()
## 是同一个做法: 这种全靠 UIThemeHelper 上样式、结构又完全线性的面板,
## 手写 .tscn 只会多一份需要跟着改的东西。
##
## 状态机只有三档, 每一档决定哪些控件可见:
##   BROWSE  —— 在看房间列表 (客户端视角), 可以建房或加入
##   HOSTING —— 已开房, 等人进来
##   JOINED  —— 已连上主机, 等主机开始

const SoundManager = preload("res://scripts/sound_manager.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const GameState = preload("res://scripts/game_state.gd")
const NetSession = preload("res://scripts/net_session.gd")

enum Phase { BROWSE, HOSTING, JOINED }

signal closed()

var phase: Phase = Phase.BROWSE

var _net: Node = null
var _title: Label
var _status: Label
var _list_box: VBoxContainer
var _ip_edit: LineEdit
var _btn_host: Button
var _btn_join: Button
var _btn_start: Button
var _btn_start_campaign: Button
var _btn_close: Button
var _hint: Label


func _ready() -> void:
	_net = get_node_or_null("/root/Net")
	_build_ui()
	visible = false
	set_process(false)


func _build_ui() -> void:
	# 整块铺满屏幕并吃掉鼠标事件 —— 否则大厅开着的时候, 底下标题菜单的
	# "开始战役"之类的按钮仍然点得到, 玩家可以在等对方连进来的同时把自己
	# 切进单机对局, 会话就悬在那里没人关。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 440)
	UIThemeHelper.apply_clay_panel(panel)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	_title = Label.new()
	_title.text = "🛰  局域网联机"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	root.add_child(_title)

	_hint = Label.new()
	_hint.text = "主机 = P1，客户端 = P2。两台机器都用 WASD + 空格 操作自己那辆坦克。"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.72)
	root.add_child(_hint)

	var list_panel := PanelContainer.new()
	UIThemeHelper.apply_clay_subpanel(list_panel)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(list_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 170)
	list_panel.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	var manual := HBoxContainer.new()
	manual.add_theme_constant_override("separation", 8)
	root.add_child(manual)

	var ip_label := Label.new()
	ip_label.text = "直连 IP:"
	manual.add_child(ip_label)

	# 局域网发现覆盖不到的情况仍然要能玩 —— 有些无线路由默认拦 UDP 广播,
	# 虚拟机/VPN 网卡也经常把广播吃掉。手输 IP 是那种时候唯一的出路,
	# 所以它不是"高级选项", 一直摆在这儿。
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.10"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual.add_child(_ip_edit)

	_btn_join = Button.new()
	_btn_join.text = "加入"
	UIThemeHelper.apply_clay_button(_btn_join)
	_btn_join.pressed.connect(_on_join_manual)
	manual.add_child(_btn_join)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)
	root.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)

	_btn_host = Button.new()
	_btn_host.text = "创建房间"
	UIThemeHelper.apply_clay_button(_btn_host)
	_btn_host.pressed.connect(_on_host)
	actions.add_child(_btn_host)

	_btn_start = Button.new()
	_btn_start.text = "开始街机"
	UIThemeHelper.apply_clay_button(_btn_start)
	_btn_start.pressed.connect(_on_start_arcade)
	actions.add_child(_btn_start)

	_btn_start_campaign = Button.new()
	_btn_start_campaign.text = "开始战役"
	UIThemeHelper.apply_clay_button(_btn_start_campaign)
	_btn_start_campaign.pressed.connect(_on_start_campaign)
	actions.add_child(_btn_start_campaign)

	_btn_close = Button.new()
	_btn_close.text = "返回"
	UIThemeHelper.apply_clay_button(_btn_close)
	_btn_close.pressed.connect(_on_close)
	actions.add_child(_btn_close)


func open_dialog() -> void:
	if _net == null:
		_net = get_node_or_null("/root/Net")
	if _net == null:
		_set_status("联机模块未加载 —— 检查 project.godot 的 [autoload] 里是否有 Net")
		visible = true
		return

	_connect_net_signals()
	_net.leave()
	phase = Phase.BROWSE
	_net.start_listening()
	if NetSession.last_error != "":
		_set_status("⚠ " + NetSession.last_error)
	else:
		_set_status("正在搜索局域网内的房间…")
	_refresh_list()
	_refresh_phase()
	visible = true
	set_process(true)
	_btn_host.grab_focus()


func close_dialog() -> void:
	if _net:
		_net.stop_listening()
	visible = false
	set_process(false)
	closed.emit()


func _connect_net_signals() -> void:
	if _net.lobby_list_changed.is_connected(_refresh_list):
		return
	_net.lobby_list_changed.connect(_refresh_list)
	_net.peer_joined.connect(_on_peer_joined)
	_net.peer_left.connect(_on_peer_left)
	_net.connected_to_host.connect(_on_connected)
	_net.connection_failed.connect(_on_failed)
	_net.match_begin.connect(_on_match_begin)


func _process(_delta: float) -> void:
	# 房间列表靠 lobby_list_changed 驱动刷新, 这里只负责把"等待中"的状态
	# 文案里的省略号动起来 —— 一个静止不动的"等待玩家加入…"很容易被当成卡死。
	if phase == Phase.HOSTING and NetSession.remote_peer_id == 0:
		var dots := 1 + int(Time.get_ticks_msec() / 400) % 3
		_set_status("房间已开启，等待玩家加入" + ".".repeat(dots) + "\n本机地址：" + _local_ips())


func _local_ips() -> String:
	var out: Array[String] = []
	for addr in IP.get_local_addresses():
		# 只列 IPv4 私网地址 —— 全量列表里混着回环、IPv6 和一堆虚拟网卡,
		# 对着念的人分不出该报哪一个。
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			out.append(addr)
	return ", ".join(out) if not out.is_empty() else "(未找到局域网地址)"


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


func _refresh_phase() -> void:
	_btn_host.visible = phase == Phase.BROWSE
	_btn_join.visible = phase == Phase.BROWSE
	_ip_edit.visible = phase == Phase.BROWSE
	# 只有主机能开始, 而且必须等对方真的连上 —— 一个人的"联机对战"没有意义,
	# 而按下去之后客户端才连进来会让它错过 begin_match 那个包。
	_btn_start.visible = phase == Phase.HOSTING
	_btn_start.disabled = NetSession.remote_peer_id == 0
	_btn_start_campaign.visible = phase == Phase.HOSTING
	_btn_start_campaign.disabled = NetSession.remote_peer_id == 0
	_btn_close.text = "返回" if phase == Phase.BROWSE else "断开"


func _refresh_list() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		c.queue_free()
	if phase != Phase.BROWSE:
		return
	var lobbies: Array = _net.get_lobbies() if _net else []
	if lobbies.is_empty():
		var empty := Label.new()
		empty.text = "  未发现房间。让对方点「创建房间」，或直接在下面填他的 IP。"
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(1, 1, 1, 0.6)
		_list_box.add_child(empty)
		return
	for lobby in lobbies:
		var btn := Button.new()
		var full: bool = int(lobby.get("players", 1)) >= 2
		var compatible: bool = bool(lobby.get("compatible", true))
		var suffix := ""
		if not compatible:
			suffix = "  [版本不匹配 v%d]" % int(lobby.get("version", 0))
		elif full:
			suffix = "  [已满]"
		btn.text = "%s  —  %s%s" % [lobby.get("name", "?"), lobby.get("ip", "?"), suffix]
		btn.disabled = full or not compatible
		UIThemeHelper.apply_clay_list_item(btn)
		btn.pressed.connect(_on_join_lobby.bind(lobby))
		_list_box.add_child(btn)

# ================================================================ 动作

func _on_host() -> void:
	SoundManager.play_button_click(get_tree())
	_net.stop_listening()
	if not _net.host_game(OS.get_environment("COMPUTERNAME")):
		_set_status("⚠ " + NetSession.last_error)
		_net.start_listening()
		return
	phase = Phase.HOSTING
	_refresh_phase()
	_refresh_list()


func _on_join_lobby(lobby: Dictionary) -> void:
	SoundManager.play_button_click(get_tree())
	_do_join(String(lobby.get("ip", "")), int(lobby.get("port", NetSession.DEFAULT_PORT)))


func _on_join_manual() -> void:
	SoundManager.play_button_click(get_tree())
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_set_status("⚠ 请先填入主机的局域网 IP")
		return
	_do_join(ip, NetSession.DEFAULT_PORT)


func _do_join(ip: String, port: int) -> void:
	_net.stop_listening()
	if not _net.join_game(ip, port):
		_set_status("⚠ " + NetSession.last_error)
		_net.start_listening()
		return
	_set_status("正在连接 %s:%d …" % [ip, port])


func _on_start_arcade() -> void:
	SoundManager.play_button_click(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	_net.start_match(int(GameState.GameMode.ARCADE), {})


## 战役合作固定开**新的一局**, 不接着主机的存档打。
##
## 接着打听起来更好, 但那一局的幕数、天赋、金币都是主机一个人攒的, 而战役
## 里两名玩家各有各的分支和天赋池 (p2_branch / p2_unlocked_perks) —— 半路
## 塞进来的第二个人会拿着一套空的成长面对一层为满配调好的难度。
## reset_campaign(2) 正是本地双人战役走的那条路。
func _on_start_campaign() -> void:
	SoundManager.play_button_click(get_tree())
	GameState.reset_campaign(2)
	# **楼层图在这里就生成好, 随开局包一起发下去。**
	# 让两端各自按种子生成同一张图也能做到, 但那要求 FloorMap 的生成过程对
	# 两台机器上的 RNG 状态完全一致 —— 而客户端此刻的 GameState 还是它自己
	# 那一局 (幕数/难度都可能不同), 生成函数读的正是这些。直接把生成好的
	# floor_rooms 发过去就没有这一类耦合。
	GameState.ensure_floor_ready()
	_net.start_match(int(GameState.GameMode.CAMPAIGN), GameState.campaign_to_dict())


func _on_close() -> void:
	SoundManager.play_button_click(get_tree())
	if _net:
		_net.leave()
	phase = Phase.BROWSE
	close_dialog()

# ================================================================ 网络回调

func _on_peer_joined(_id: int) -> void:
	_refresh_phase()
	_set_status("✅ 玩家已加入！可以开始对战了。")


func _on_peer_left(_id: int) -> void:
	if phase == Phase.JOINED:
		phase = Phase.BROWSE
		_set_status("⚠ 与主机断开连接")
		_net.start_listening()
	else:
		_set_status("⚠ 对方离开了房间")
	_refresh_phase()
	_refresh_list()


func _on_connected() -> void:
	phase = Phase.JOINED
	_set_status("✅ 已连上主机，等待对方开始对战…")
	_refresh_phase()
	_refresh_list()


func _on_failed(reason: String) -> void:
	phase = Phase.BROWSE
	_set_status("⚠ " + reason)
	_net.start_listening()
	_refresh_phase()
	_refresh_list()


## 两端都会收到。
##
## 客户端在这里**接管主机那一局**。做这件事之前必须先把自己那份 GameState
## 备份下来 —— 它全是静态变量, 打完回标题不会自己恢复, 不备份的话"陪朋友
## 打一局"会把自己的金币/天赋/建材/图鉴改成别人的。还原在
## net_manager.leave() 里 (见 NetSession.client_campaign_backup)。
##
## 街机也备份: 那条路虽然不发战役字典, 但状态包会覆盖建造库存。
func _on_match_begin(_match_seed: int, mode: int, campaign: Dictionary) -> void:
	if NetSession.is_client() and not NetSession.has_campaign_backup:
		NetSession.client_campaign_backup = GameState.campaign_to_dict()
		NetSession.has_campaign_backup = true

	if mode == int(GameState.GameMode.CAMPAIGN):
		if not campaign.is_empty():
			GameState.campaign_from_dict(campaign)
		GameState.player_count = 2
	else:
		GameState.mode = GameState.GameMode.ARCADE
		GameState.player_count = 2

	set_process(false)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
