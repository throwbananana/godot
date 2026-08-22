class_name EventDialog
extends PanelContainer

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

signal closed

@onready var title_label: Label = $VBox/TitleLabel
@onready var desc_label: Label = $VBox/DescLabel
@onready var icon_sprite: Sprite2D = $VBox/IconContainer/IconSprite
@onready var btn_1: Button = $VBox/Button1
@onready var btn_2: Button = $VBox/Button2
@onready var btn_3: Button = $VBox/Button3

var dialog_type: String = "rest"

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(self, Color(0.16, 0.14, 0.18, 0.96), 16)
	UIThemeHelper.apply_clay_button(btn_1)
	UIThemeHelper.apply_clay_button(btn_2)
	UIThemeHelper.apply_clay_button(btn_3)

	btn_1.pressed.connect(func(): _on_choice(1))
	btn_2.pressed.connect(func(): _on_choice(2))
	btn_3.pressed.connect(func(): _on_choice(3))

var current_event_id: String = ""

func setup(type: String) -> void:
	dialog_type = type
	visible = true
	var icon_path = "res://assets/sprites/ui/diorama_rest.png"
	
	if type == "rest":
		icon_path = "res://assets/sprites/ui/diorama_rest.png"
		title_label.text = "FORWARD REPAIR OUTPOST (CAMPFIRE)"
		desc_label.text = "You reached a secured allied outpost. Choose your preparation for the battles ahead:"
		btn_1.text = "1. Full Vehicle Overhaul (+1 Max HP & Fortify)"
		btn_2.text = "2. Gunsmith Calibration (+1 ATK Bonus)"
		btn_3.text = "3. Request Reinforcements (+1 Extra Life)"
		UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/perk_armor.png", Vector2(22, 22))
		UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_atk.png", Vector2(22, 22))
		UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/hp_heart_full.png", Vector2(22, 22))
	elif type == "shop":
		icon_path = "res://assets/sprites/ui/diorama_shop.png"
		title_label.text = "BLACK MARKET ARMS DEALER"
		desc_label.text = "The arms dealer offers military-grade prototypes. (Current Gold: %dG)" % GameState.gold
		btn_1.text = "1. Star Weapon Module (100G) -> Tier Up!"
		btn_2.text = "2. Forcefield Generator (60G) -> +2 Max HP"
		btn_3.text = "3. Heavy Supply Crate (80G) -> +2 Extra Lives"
		UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/powerups/star.png", Vector2(22, 22))
		UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_shield.png", Vector2(22, 22))
		UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/hp_heart_full.png", Vector2(22, 22))
	elif type == "event":
		icon_path = "res://assets/sprites/ui/diorama_event.png"
		var event_types = ["depot", "mechanic", "singularity", "glacier_cache", "bounty"]
		current_event_id = event_types[randi() % event_types.size()]
		
		match current_event_id:
			"depot":
				title_label.text = "ABANDONED MUNITIONS DEPOT (MYSTERY)"
				desc_label.text = "You discovered an intact munitions vault buried beneath the ruins:"
				btn_1.text = "1. Scavenge High-Caliber Ammo (+100G, +60 XP)"
				btn_2.text = "2. Overclock Engine Reactor (+1 SPD Permanent)"
				btn_3.text = "3. Weapon Star Upgrade (+1 Tier Upgrade)"
				UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/ui_icon_gift.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_speed.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/powerups/star.png", Vector2(22, 22))
			"mechanic":
				title_label.text = "WANDERING COMBAT MECHANIC (ENCOUNTER)"
				desc_label.text = "A friendly scavenger engineer offers to upgrade your chassis on the spot:"
				btn_1.text = "1. Heavy Exoskeleton Plating (+2 Max HP)"
				btn_2.text = "2. Calibrate Fire Control (+1 Fire Rate Level)"
				btn_3.text = "3. Tactical Clay Crusher Perk (Gain Clay Crusher)"
				UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/perk_armor.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_laser.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/perk_ricochet.png", Vector2(22, 22))
			"singularity":
				title_label.text = "COSMIC SINGULARITY ANOMALY (EVENT)"
				desc_label.text = "A pulsating dimensional rift hums with unstable spatial energy:"
				btn_1.text = "1. Siphon Warp Energy (Gain Warp Drive Perk)"
				btn_2.text = "2. Spatial Transmutation (+150 Gold, +80 XP)"
				btn_3.text = "3. Dimensional Blessing (+2 Extra Lives)"
				UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/perk_laser.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/ui_badge_gold.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/hp_heart_full.png", Vector2(22, 22))
			"glacier_cache":
				title_label.text = "FROZEN GLACIER SUPPLY CRATE (DISCOVERY)"
				desc_label.text = "You broke through an icy glacier wall revealing cryo-preserved tech:"
				btn_1.text = "1. Equip Frost Cleats Perk (Gain Frost Cleats)"
				btn_2.text = "2. Cryo-Powered Capacitor (+1 ATK Bonus)"
				btn_3.text = "3. Defrost & Emergency Repair (+1 Life, +50G)"
				UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/perk_speed.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_atk.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/ui_icon_wrench.png", Vector2(22, 22))
			"bounty":
				title_label.text = "ROGUE COMBAT CONTRACT (BLACK OPS)"
				desc_label.text = "An encrypted distress beacon broadcasts a high-priority bounty assignment:"
				btn_1.text = "1. Accept Elite Bounty (+140 Gold, +100 XP)"
				btn_2.text = "2. Install Magnetic Salvage Core (Gain Magnetic Salvage)"
				btn_3.text = "3. Acquire Ferry Artillery Module (Gain Ferry Artillery)"
				UIThemeHelper.apply_icon_button(btn_1, "res://assets/sprites/ui/ui_badge_gold.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_2, "res://assets/sprites/ui/perk_gold.png", Vector2(22, 22))
				UIThemeHelper.apply_icon_button(btn_3, "res://assets/sprites/ui/perk_atk.png", Vector2(22, 22))

	var tex = TextureHelper.get_tex(icon_path)
	if tex and icon_sprite:
		icon_sprite.texture = tex

	# 让手柄/键盘一进来就有焦点; 没有这一句菜单只能用鼠标。
	UIThemeHelper.focus_first(self)

func _grant_life(amount: int) -> void:
	GameState.player_lives += amount
	if GameState.player_count == 2:
		GameState.p2_lives += amount

func _grant_tier_up() -> void:
	GameState.grant_star_tier_reward(1)
	if GameState.player_count == 2:
		GameState.grant_star_tier_reward(2)

func _grant_perk(perk_name: String) -> void:
	GameState.grant_perk_stack(perk_name, 1)
	if GameState.player_count == 2:
		GameState.grant_perk_stack(perk_name, 2)

func _on_choice(idx: int) -> void:
	SoundManager.play_hit_steel(get_tree())
	if dialog_type == "rest":
		match idx:
			1: GameState.max_hp_lvl += 1
			2: GameState.atk_bonus += 1
			3: _grant_life(1)
	elif dialog_type == "shop":
		match idx:
			1:
				if GameState.gold >= 100:
					GameState.gold -= 100
					_grant_tier_up()
			2:
				if GameState.gold >= 60:
					GameState.gold -= 60
					GameState.max_hp_lvl += 2
			3:
				if GameState.gold >= 80:
					GameState.gold -= 80
					_grant_life(2)
	elif dialog_type == "event":
		match current_event_id:
			"depot":
				match idx:
					1:
						GameState.gold += 100
						GameState.player_xp += 60
					2:
						GameState.speed_lvl += 1
					3:
						_grant_tier_up()
			"mechanic":
				match idx:
					1:
						GameState.max_hp_lvl += 2
					2:
						GameState.fire_rate_lvl += 1
					3:
						_grant_perk("clay_crusher")
			"singularity":
				match idx:
					1:
						_grant_perk("warp_drive")
					2:
						GameState.gold += 150
						GameState.player_xp += 80
					3:
						_grant_life(2)
			"glacier_cache":
				match idx:
					1:
						_grant_perk("frost_cleats")
					2:
						GameState.atk_bonus += 1
					3:
						_grant_life(1)
						GameState.gold += 50
			"bounty":
				match idx:
					1:
						GameState.gold += 140
						GameState.player_xp += 100
					2:
						_grant_perk("magnetic_salvage")
					3:
						_grant_perk("ferry_artillery")
			_:
				match idx:
					1: GameState.gold += 80
					2: GameState.speed_lvl += 1
					3: _grant_tier_up()

	visible = false
	closed.emit()
