class_name EventDialog
extends PanelContainer

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")

signal closed

@onready var title_label: Label = $VBox/TitleLabel
@onready var desc_label: Label = $VBox/DescLabel
@onready var icon_sprite: Sprite2D = $VBox/IconContainer/IconSprite
@onready var btn_1: Button = $VBox/Button1
@onready var btn_2: Button = $VBox/Button2
@onready var btn_3: Button = $VBox/Button3

var dialog_type: String = "rest" # "rest", "shop", "event"

func _ready() -> void:
	btn_1.pressed.connect(func(): _on_choice(1))
	btn_2.pressed.connect(func(): _on_choice(2))
	btn_3.pressed.connect(func(): _on_choice(3))

func setup(type: String) -> void:
	dialog_type = type
	visible = true
	var icon_path = "res://assets/sprites/map/node_rest.png"
	
	if type == "rest":
		icon_path = "res://assets/sprites/map/node_rest.png"
		title_label.text = "FORWARD REPAIR OUTPOST (CAMPFIRE)"
		desc_label.text = "You reached a secured allied outpost. Choose your preparation for the battles ahead:"
		btn_1.text = "1. 🛠 Full Vehicle Overhaul (Restore HP & Fortify)"
		btn_2.text = "2. ⚡ Gunsmith Calibration (+1 ATK Bonus)"
		btn_3.text = "3. ❤️ Request Reinforcements (+1 Extra Life)"
	elif type == "shop":
		icon_path = "res://assets/sprites/map/node_shop.png"
		title_label.text = "BLACK MARKET ARMS DEALER"
		desc_label.text = "The arms dealer offers military-grade prototypes. (Current Gold: %dG)" % GameState.gold
		btn_1.text = "1. ⭐ Star Weapon Module (100G) -> Tier Up!"
		btn_2.text = "2. 🛡 Forcefield Generator (60G) -> +2 Max HP"
		btn_3.text = "3. ❤️ Heavy Supply Crate (80G) -> +2 Extra Lives"
	elif type == "event":
		icon_path = "res://assets/sprites/map/node_event.png"
		title_label.text = "UNEXPLORED COMBAT ZONE (MYSTERY)"
		desc_label.text = "You discovered an abandoned enemy munitions depot in the ruins:"
		btn_1.text = "1. 📦 Scavenge Munitions (+80 Gold, +50 XP)"
		btn_2.text = "2. 🧪 Overclock Engine Reactor (+15% SPD Permanent)"
		btn_3.text = "3. ⏩ Scout Ahead and Secure Perimeter (+1 Star Upgrade)"

	var tex = TextureHelper.get_tex(icon_path)
	if tex and icon_sprite:
		icon_sprite.texture = tex

func _on_choice(idx: int) -> void:
	SoundManager.play_hit_steel(get_tree())
	if dialog_type == "rest":
		match idx:
			1:
				GameState.max_hp += 1
			2:
				GameState.atk_bonus += 1
			3:
				GameState.player_lives += 1
	elif dialog_type == "shop":
		match idx:
			1:
				if GameState.gold >= 100:
					GameState.gold -= 100
					GameState.player_tier = mini(GameState.player_tier + 1, 3)
			2:
				if GameState.gold >= 60:
					GameState.gold -= 60
					GameState.max_hp += 2
			3:
				if GameState.gold >= 80:
					GameState.gold -= 80
					GameState.player_lives += 2
	elif dialog_type == "event":
		match idx:
			1:
				GameState.gold += 80
				GameState.player_xp += 50
			2:
				GameState.speed_bonus += 1
			3:
				GameState.player_tier = mini(GameState.player_tier + 1, 3)

	visible = false
	closed.emit()
