class_name TitleScreen
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

@onready var banner_sprite: Sprite2D = $CenterContainer/VBox/BannerContainer/BannerSprite
@onready var btn_continue: Button = $CenterContainer/VBox/ButtonsBox/ContinueButton
@onready var btn_1p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign1PButton
@onready var btn_2p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign2PButton
@onready var btn_2p_arcade: Button = $CenterContainer/VBox/ButtonsBox/Arcade2PButton
@onready var btn_quit: Button = $CenterContainer/VBox/ButtonsBox/QuitButton

func _ready() -> void:
	var b_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_banner.png")
	if b_tex and banner_sprite:
		banner_sprite.texture = b_tex

	UIThemeHelper.apply_clay_button(btn_continue)
	UIThemeHelper.apply_clay_button(btn_1p_campaign)
	UIThemeHelper.apply_clay_button(btn_2p_campaign)
	UIThemeHelper.apply_clay_button(btn_2p_arcade)
	UIThemeHelper.apply_clay_button(btn_quit)

	var has_save = GameState.has_saved_game()
	btn_continue.visible = has_save
	btn_continue.pressed.connect(_on_continue_pressed)

	btn_1p_campaign.pressed.connect(func(): _start_campaign(1))
	btn_2p_campaign.pressed.connect(func(): _start_campaign(2))
	btn_2p_arcade.pressed.connect(_start_arcade_2p)
	btn_quit.pressed.connect(_on_quit_pressed)

func _on_continue_pressed() -> void:
	SoundManager.play_shot(get_tree())
	if GameState.load_campaign():
		get_tree().change_scene_to_file("res://scenes/spire_map.tscn")
	else:
		_start_campaign(1)

func _start_campaign(p_count: int) -> void:
	SoundManager.play_shot(get_tree())
	GameState.reset_campaign(p_count)
	get_tree().change_scene_to_file("res://scenes/spire_map.tscn")

func _start_arcade_2p() -> void:
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
