class_name TitleScreen
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SettingsStore = preload("res://scripts/settings_store.gd")

@onready var bg_texture: TextureRect = $BackgroundTexture
@onready var halo_sprite: Sprite2D = $CenterContainer/VBox/LogoContainer/HaloSprite
@onready var logo_texture: TextureRect = $CenterContainer/VBox/LogoContainer/LogoTexture
@onready var sparkle_container: Control = $CenterContainer/VBox/LogoContainer/SparkleContainer
@onready var sub_title_label: Label = $CenterContainer/VBox/SubTitleLabel
@onready var menu_panel: PanelContainer = $CenterContainer/VBox/MenuPanel
@onready var primary_vbox: VBoxContainer = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox
@onready var secondary_grid: GridContainer = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid
@onready var footer_label: Label = $CenterContainer/VBox/FooterLabel

@onready var btn_continue: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox/ContinueButton
@onready var btn_1p_campaign: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox/Campaign1PButton
@onready var btn_2p_campaign: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox/Campaign2PButton
@onready var btn_2p_arcade: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox/Arcade2PButton
@onready var btn_daily_challenge: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/PrimaryButtonsBox/DailyChallengeButton
@onready var btn_encyclopedia: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/EncyclopediaButton
@onready var btn_map_editor: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/MapEditorButton
@onready var btn_settings: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/SettingsButton
@onready var btn_quit: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/QuitButton
@onready var btn_test_mode: Button = $CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/TestModeButton
@onready var encyclopedia_dialog: EncyclopediaDialog = $EncyclopediaDialog
@onready var settings_dialog: SettingsDialog = $SettingsDialog

var _sparkle_textures: Array[Texture2D] = []
var _sparkle_timer: float = 0.0
var _all_buttons: Array[Button] = []

## 隐藏测试模式的解锁暗号。键盘按"throwbanana" (逐字母比对 keycode, 与大小写/
## 输入法无关 —— Godot 里字母键的 Key 常量本身就是该字母的大写 ASCII 码);
## 手柄按 上上下下左左右右 X Y X Y (D-pad 方向键 + 两个安全面键)。
## 命中任意一种就置 GameState.debug_unlocked = true, 是本进程范围内一次性的——
## 见 game_state.gd 里 debug_unlocked 声明处的持久化理由。
##
## 尾巴上的四个面键是 X Y X Y 而**不是**经典的 X A B Y, 这不是随手改的:
## 标题界面永远有按钮持着焦点, 而 A 是 Godot 内置的 ui_accept —— 按下去会直接
## 激活当前焦点按钮 (多半是 CONTINUE), 场景当场切走, 暗号永远输不完。B 同理是
## ui_cancel。X/Y 在这个场景里没有任何 UI 绑定, 是仅剩的安全面键。
## (项目里 LB/X/Y/BACK 绑的是 p1_build_* 这类游戏内动作, 标题场景不监听。)
const SECRET_KEYWORD := "throwbanana"
const SECRET_GAMEPAD_SEQUENCE: Array[int] = [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_X, JOY_BUTTON_Y,
]
var _secret_key_buffer: String = ""
var _secret_pad_buffer: Array[int] = []

func _ready() -> void:
	SettingsStore.load_and_apply()

	# 1. 加载 3D 黏土主界面背景
	if bg_texture:
		var bg_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_background_clay.png")
		if bg_tex:
			bg_texture.texture = bg_tex

	# 2. 加载 3D 黏土徽标与 Halo 光环
	if halo_sprite:
		var h_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_logo_halo.png")
		if h_tex:
			halo_sprite.texture = h_tex
		halo_sprite.modulate = Color(1.0, 0.9, 0.5, 0.45)

	if logo_texture:
		var b_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_logo_banner.png")
		if not b_tex:
			b_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_title_crest.png")
		if b_tex:
			logo_texture.texture = b_tex
		logo_texture.pivot_offset = Vector2(230.0, 70.0)

	# 预加载 3D 闪烁星芒序列
	for i in range(6):
		var spk_tex = TextureHelper.get_tex("res://assets/sprites/effects/vfx_sparkle_glint_f%d.png" % i)
		if spk_tex:
			_sparkle_textures.append(spk_tex)

	# 3. 装饰主菜单面板 (Clay Panel)
	if menu_panel:
		var panel_sb := StyleBoxFlat.new()
		panel_sb.bg_color = Color(0.10, 0.08, 0.15, 0.92)
		panel_sb.border_color = Color(0.58, 0.46, 0.72, 0.85)
		panel_sb.border_width_left = 2
		panel_sb.border_width_top = 2
		panel_sb.border_width_right = 2
		panel_sb.border_width_bottom = 2
		panel_sb.corner_radius_top_left = 16
		panel_sb.corner_radius_top_right = 16
		panel_sb.corner_radius_bottom_left = 16
		panel_sb.corner_radius_bottom_right = 16
		panel_sb.shadow_size = 18
		panel_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
		panel_sb.content_margin_left = 18
		panel_sb.content_margin_right = 18
		panel_sb.content_margin_top = 14
		panel_sb.content_margin_bottom = 14
		menu_panel.add_theme_stylebox_override("panel", panel_sb)

	# 4. 配置所有按钮与高阶交互动效 (Elastic Punch & Sound)
	_all_buttons = [
		btn_continue, btn_1p_campaign, btn_2p_campaign, btn_2p_arcade, btn_daily_challenge,
		btn_encyclopedia, btn_map_editor, btn_settings, btn_quit, btn_test_mode
	]

	UIThemeHelper.apply_icon_button(btn_continue, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(24, 24))
	UIThemeHelper.apply_icon_button(btn_1p_campaign, "res://assets/sprites/ui/ui_icon_mode_1p.png", Vector2(24, 24))
	UIThemeHelper.apply_icon_button(btn_2p_campaign, "res://assets/sprites/ui/ui_icon_mode_2p.png", Vector2(24, 24))
	UIThemeHelper.apply_icon_button(btn_2p_arcade, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_daily_challenge, "res://assets/sprites/ui/ui_icon_score_trophy.png", Vector2(22, 22))
	UIThemeHelper.apply_icon_button(btn_encyclopedia, "res://assets/sprites/powerups/star.png", Vector2(20, 20))
	UIThemeHelper.apply_icon_button(btn_map_editor, "res://assets/sprites/powerups/shovel.png", Vector2(20, 20))
	UIThemeHelper.apply_icon_button(btn_settings, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(20, 20))
	UIThemeHelper.apply_icon_button(btn_quit, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(20, 20))
	UIThemeHelper.apply_icon_button(btn_test_mode, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(18, 18))

	for btn in _all_buttons:
		_setup_button_juice(btn)

	var today_best = GameState.get_daily_best_score()
	if today_best > 0:
		btn_daily_challenge.text = "DAILY CHALLENGE (每日挑战) - BEST %06d" % today_best

	var has_save = GameState.has_saved_game()
	btn_continue.visible = has_save
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_1p_campaign.pressed.connect(func(): _start_campaign(1))
	btn_2p_campaign.pressed.connect(func(): _start_campaign(2))
	btn_2p_arcade.pressed.connect(_start_arcade_2p)
	btn_daily_challenge.pressed.connect(_start_daily_challenge)
	btn_encyclopedia.pressed.connect(_on_encyclopedia_pressed)
	btn_map_editor.pressed.connect(_on_map_editor_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_test_mode.pressed.connect(_on_test_mode_pressed)
	# 本进程之前已经输对过暗号 (比如从测试菜单/对局里 "返回标题" 回来的) ——
	# 按钮保持解锁状态, 不需要重新输一遍。
	btn_test_mode.visible = GameState.debug_unlocked

	if encyclopedia_dialog:
		encyclopedia_dialog.closed.connect(func(): btn_encyclopedia.grab_focus())
	if settings_dialog:
		settings_dialog.closed.connect(func(): btn_settings.grab_focus())

	# 5. 执行入场级联弹簧动效 (Entrance Stagger)
	_play_entrance_animation()

	# 手柄/键盘自动对焦
	UIThemeHelper.focus_first(self)


func _process(delta: float) -> void:
	var t = Time.get_ticks_msec() * 0.001
	
	# 1. Logo Halo 光环慢速旋转与呼吸
	if halo_sprite:
		halo_sprite.rotation += delta * 0.35
		var halo_pulse = 0.42 + sin(t * 2.2) * 0.15
		halo_sprite.modulate.a = halo_pulse
		var halo_scale = 1.1 + sin(t * 1.5) * 0.05
		halo_sprite.scale = Vector2(halo_scale, halo_scale)

	# 2. Logo 本身 3D 多维呼吸晃动 (Vertical Float + Subtle Tilt)
	if logo_texture:
		var float_y = sin(t * 2.2) * 3.5
		var tilt_deg = sin(t * 1.4) * 0.8
		logo_texture.position.y = float_y
		logo_texture.rotation_degrees = tilt_deg

	# 3. 周期性在 Logo 金字与徽章上生成 3D 星芒闪烁特效。
	#    图鉴/设置对话框是全屏盖在标题上的, 那时候整个 Logo 一个像素都看不见,
	#    再每 0.35-0.75 s 新建一个 Sprite2D + 3 条 tween 纯属白烧 —— 图鉴可以
	#    翻很久, 这些节点会一直生成一直析构。
	if _is_dialog_open():
		return
	_sparkle_timer -= delta
	if _sparkle_timer <= 0.0:
		_sparkle_timer = randf_range(0.35, 0.75)
		_spawn_logo_sparkle()


func _is_dialog_open() -> bool:
	if encyclopedia_dialog and encyclopedia_dialog.visible:
		return true
	if settings_dialog and settings_dialog.visible:
		return true
	return false


## 为按钮配置高阶微交互动效 (Elastic Scale Punch, Micro-Glow)
##
## 缩放中心 (pivot_offset) 必须在 resized 里按**实际尺寸**重算, 不能在这里拿
## custom_minimum_size 算一次就完事: 这些按钮都带 size_flags_horizontal = 3,
## 真实宽度由容器拉伸决定, 而 _ready() 跑的时候容器还没布局。用最小尺寸的一半
## 当轴心, 按钮就不是"原地放大"而是"朝右下涨出去"。
func _setup_button_juice(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(func(): btn.pivot_offset = btn.size * 0.5)

	btn.mouse_entered.connect(func(): _juice_highlight(btn, true))
	btn.mouse_exited.connect(func(): _juice_highlight(btn, false))
	btn.focus_entered.connect(func(): _juice_highlight(btn, true))
	btn.focus_exited.connect(func(): _juice_highlight(btn, false))

	btn.button_down.connect(func():
		var tw = _fresh_juice_tween(btn)
		tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)

	btn.button_up.connect(func():
		var tw = _fresh_juice_tween(btn)
		tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


## 同一颗按钮同一时刻只允许有一条动效 tween。
##
## 原来 6 个信号各自 create_tween(), 谁都不管别人 —— 鼠标快速划过一排按钮, 或者
## 手柄焦点扫过去的同时鼠标还悬在上面 (focus_entered + mouse_exited 同帧), 就会有
## 两条以上的 tween 同时往 scale/modulate 上写值, 结果取决于哪条后结束, 按钮会卡在
## 放大或者变亮的状态上下不来。
func _fresh_juice_tween(btn: Button, parallel: bool = false) -> Tween:
	var prev = btn.get_meta("juice_tween", null)
	if prev is Tween and prev.is_valid():
		prev.kill()
	var tw = create_tween()
	if parallel:
		tw.set_parallel(true)
	btn.set_meta("juice_tween", tw)
	return tw


func _juice_highlight(btn: Button, on: bool) -> void:
	# 鼠标移开但手柄焦点还在这颗按钮上时不该掉高亮 —— 否则用手柄选中一颗按钮、
	# 顺手把鼠标挪开, 按钮就暗回去了, 看上去像失去了焦点。
	if not on and btn.has_focus():
		return
	var tw = _fresh_juice_tween(btn, true)
	if on:
		tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.15)
	else:
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.14)


## 在 Logo 随机金字/星徽处生成 3D 星芒闪烁
func _spawn_logo_sparkle() -> void:
	if not sparkle_container or _sparkle_textures.is_empty():
		return
		
	var spk = Sprite2D.new()
	spk.texture = _sparkle_textures[0]
	# 集中在徽标中心金色文字与老鹰/星星区域 (460x140)
	var sx = randf_range(80.0, 380.0)
	var sy = randf_range(25.0, 115.0)
	spk.position = Vector2(sx, sy)
	spk.scale = Vector2(0.4, 0.4)
	spk.rotation = randf_range(0.0, TAU)
	sparkle_container.add_child(spk)
	
	var tw = create_tween()
	var frame_dur = 0.06
	for i in range(1, _sparkle_textures.size()):
		tw.tween_callback(func():
			if is_instance_valid(spk):
				spk.texture = _sparkle_textures[i]
		).set_delay(frame_dur)
		
	# 伴随轻微旋转放大淡出
	var tw_rot = create_tween().set_parallel(true)
	tw_rot.tween_property(spk, "rotation", spk.rotation + 0.8, 0.36)
	tw_rot.tween_property(spk, "scale", Vector2(0.85, 0.85), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_rot.chain().tween_property(spk, "scale", Vector2(0.1, 0.1), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	tw.chain().tween_callback(func():
		if is_instance_valid(spk):
			spk.queue_free()
	)


## 入场级联弹性动效
func _play_entrance_animation() -> void:
	if logo_texture:
		logo_texture.scale = Vector2(0.82, 0.82)
		logo_texture.modulate.a = 0.0
		var tw_logo = create_tween().set_parallel(true)
		tw_logo.tween_property(logo_texture, "scale", Vector2(1.0, 1.0), 0.65).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw_logo.tween_property(logo_texture, "modulate:a", 1.0, 0.35)

	if sub_title_label:
		sub_title_label.modulate.a = 0.0
		var tw_sub = create_tween()
		tw_sub.tween_interval(0.20)
		tw_sub.tween_property(sub_title_label, "modulate:a", 1.0, 0.30)

	if menu_panel:
		menu_panel.scale = Vector2(0.92, 0.92)
		menu_panel.modulate.a = 0.0
		var tw_pnl = create_tween().set_parallel(true)
		tw_pnl.tween_property(menu_panel, "scale", Vector2(1.0, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
		tw_pnl.tween_property(menu_panel, "modulate:a", 1.0, 0.35).set_delay(0.15)

	# 按钮依次级联滑入
	var delay = 0.25
	for btn in _all_buttons:
		if btn.visible:
			btn.modulate.a = 0.0
			var tw_btn = create_tween()
			tw_btn.tween_interval(delay)
			tw_btn.tween_property(btn, "modulate:a", 1.0, 0.15)
			delay += 0.035


func _on_continue_pressed() -> void:
	SoundManager.play_shot(get_tree())
	if GameState.load_campaign():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		_start_campaign(1)


func _start_campaign(p_count: int) -> void:
	SoundManager.play_shot(get_tree())
	GameState.reset_campaign(p_count)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _start_arcade_2p() -> void:
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _start_daily_challenge() -> void:
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.DAILY_CHALLENGE
	GameState.player_count = 1
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_encyclopedia_pressed() -> void:
	if encyclopedia_dialog:
		encyclopedia_dialog.open_dialog()


func _on_map_editor_pressed() -> void:
	SoundManager.play_shot(get_tree())
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")


func _on_settings_pressed() -> void:
	if settings_dialog:
		settings_dialog.open_dialog()


func _on_quit_pressed() -> void:
	get_tree().quit()


## 暗号监听必须挂在 _input() 而不是 _unhandled_input()。
##
## 标题界面永远有一颗按钮持有焦点, 而 Godot 的 Viewport 在把事件交给
## _unhandled_input 之前就会拿 ui_up/ui_down/ui_left/ui_right 去做焦点导航,
## 只要找得到相邻控件就 set_input_as_handled() —— D-pad 的方向键因此根本走不到
## _unhandled_input。实测推完整条 12 键序列, 缓冲区只收到 8 条 (顶部按钮没有上
## 邻居, 所以只有"上"漏了过来), 手柄这条路 100% 解锁不了。键盘那条一直是好的,
## 因为字母键不参与焦点导航 —— 这也是为什么这个 bug 能带着一个通过的
## test_title_screen.gd 一起进仓库。
##
## 挂 _input() 只是"先看一眼", 不消费事件: 焦点该怎么移还怎么移, 正常手柄
## 玩家的菜单操作完全不受影响。
func _input(event: InputEvent) -> void:
	if GameState.debug_unlocked:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# 字母键的 Key 常量本身就等于该字母的大写 ASCII 码 (KEY_A=65..KEY_Z=90),
		# 所以直接从 keycode 转字符可以拿到跟 Shift/输入法/大小写都无关的字母,
		# 不用去解析 event.unicode (那个会被布局和修饰键污染)。
		if event.keycode >= KEY_A and event.keycode <= KEY_Z:
			_secret_key_buffer += char(event.keycode).to_lower()
			if _secret_key_buffer.length() > SECRET_KEYWORD.length():
				_secret_key_buffer = _secret_key_buffer.substr(_secret_key_buffer.length() - SECRET_KEYWORD.length())
			if _secret_key_buffer == SECRET_KEYWORD:
				_unlock_test_mode()
	elif event is InputEventJoypadButton and event.pressed:
		_secret_pad_buffer.append(event.button_index)
		if _secret_pad_buffer.size() > SECRET_GAMEPAD_SEQUENCE.size():
			_secret_pad_buffer.remove_at(0)
		if _secret_pad_buffer == SECRET_GAMEPAD_SEQUENCE:
			_unlock_test_mode()


func _unlock_test_mode() -> void:
	if GameState.debug_unlocked:
		return
	GameState.debug_unlocked = true
	SoundManager.play_level_up(get_tree())
	if btn_test_mode:
		btn_test_mode.visible = true
		btn_test_mode.modulate.a = 0.0
		btn_test_mode.scale = Vector2(0.85, 0.85)
		var tw = create_tween().set_parallel(true)
		tw.tween_property(btn_test_mode, "modulate:a", 1.0, 0.3)
		tw.tween_property(btn_test_mode, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_test_mode_pressed() -> void:
	SoundManager.play_shot(get_tree())
	get_tree().change_scene_to_file("res://scenes/debug_test_menu.tscn")
