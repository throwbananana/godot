class_name TitleScreen
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SettingsStore = preload("res://scripts/settings_store.gd")

@onready var banner_sprite: Sprite2D = $CenterContainer/VBox/BannerContainer/BannerSprite
@onready var btn_continue: Button = $CenterContainer/VBox/ButtonsBox/ContinueButton
@onready var btn_1p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign1PButton
@onready var btn_2p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign2PButton
@onready var btn_2p_arcade: Button = $CenterContainer/VBox/ButtonsBox/Arcade2PButton
@onready var btn_daily_challenge: Button = $CenterContainer/VBox/ButtonsBox/DailyChallengeButton
@onready var btn_encyclopedia: Button = $CenterContainer/VBox/ButtonsBox/EncyclopediaButton
@onready var btn_map_editor: Button = $CenterContainer/VBox/ButtonsBox/MapEditorButton
@onready var btn_settings: Button = $CenterContainer/VBox/ButtonsBox/SettingsButton
@onready var btn_quit: Button = $CenterContainer/VBox/ButtonsBox/QuitButton
@onready var encyclopedia_dialog: EncyclopediaDialog = $EncyclopediaDialog
@onready var settings_dialog: SettingsDialog = $SettingsDialog

func _ready() -> void:
	# 分辨率/全屏/音量是引擎级别的状态, 跟场景无关, 只需要在游戏启动的第一个
	# 场景里应用一次 —— 见 settings_store.gd 头部注释。
	SettingsStore.load_and_apply()

	var b_tex = TextureHelper.get_tex("res://assets/sprites/ui/ui_title_crest.png")
	if not b_tex:
		b_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_banner.png")
	if b_tex and banner_sprite:
		banner_sprite.texture = b_tex
		banner_sprite.scale = Vector2(0.85, 0.85)

	UIThemeHelper.apply_icon_button(btn_continue, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_1p_campaign, "res://assets/sprites/ui/ui_icon_mode_1p.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_2p_campaign, "res://assets/sprites/ui/ui_icon_mode_2p.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_2p_arcade, "res://assets/sprites/ui/ui_icon_mode_arcade.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_daily_challenge, "res://assets/sprites/ui/ui_icon_score_trophy.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_encyclopedia, "res://assets/sprites/powerups/star.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_map_editor, "res://assets/sprites/powerups/shovel.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_settings, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(28, 28))
	UIThemeHelper.apply_icon_button(btn_quit, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(28, 28))

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

	if encyclopedia_dialog:
		encyclopedia_dialog.closed.connect(func(): btn_encyclopedia.grab_focus())
	if settings_dialog:
		settings_dialog.closed.connect(func(): btn_settings.grab_focus())

	# 让手柄/键盘一进来就有焦点; 没有这一句菜单只能用鼠标。
	UIThemeHelper.focus_first(self)

func _process(_delta: float) -> void:
	if banner_sprite:
		var float_y = 70.0 + sin(Time.get_ticks_msec() * 0.003) * 4.0
		banner_sprite.position.y = float_y

## 战役直接进 main.tscn。
##
## 以前中间隔着一个 spire_map.tscn (分支路线图, 点节点才进战斗,
## 打完又退回来)。以撒化之后整层楼都在 main.tscn 里跑 —— 房间之间
## 是原地重建而不是换场景, 路线图被 HUD 上的小地图取代, 那个中间
## 场景就没有存在的必要了。
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
