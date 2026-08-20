class_name TitleScreen
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")

@onready var banner_sprite: Sprite2D = $CenterContainer/VBox/BannerContainer/BannerSprite
@onready var btn_campaign: Button = $CenterContainer/VBox/ButtonsBox/CampaignButton
@onready var btn_arcade: Button = $CenterContainer/VBox/ButtonsBox/ArcadeButton
@onready var btn_quit: Button = $CenterContainer/VBox/ButtonsBox/QuitButton

func _ready() -> void:
	var b_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_banner.png")
	if b_tex and banner_sprite:
		banner_sprite.texture = b_tex

	btn_campaign.pressed.connect(_on_campaign_pressed)
	btn_arcade.pressed.connect(_on_arcade_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

func _on_campaign_pressed() -> void:
	SoundManager.play_shot(get_tree())
	GameState.reset_campaign()
	get_tree().change_scene_to_file("res://scenes/spire_map.tscn")

func _on_arcade_pressed() -> void:
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
