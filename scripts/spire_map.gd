class_name SpireMap
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const EventDialog = preload("res://scripts/event_dialog.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

@onready var map_canvas: Control = $MapArea/MapCanvas
@onready var lines_draw: Control = $MapArea/LinesDraw
@onready var event_dialog: PanelContainer = $EventDialog
@onready var stage_preview_dialog: PanelContainer = $StagePreviewDialog
@onready var shop_dialog: PanelContainer = $ShopDialog
@onready var top_bar: PanelContainer = $TopBar
@onready var hud_floor: Label = $TopBar/HBox/FloorLabel
@onready var hud_gold: Label = $TopBar/HBox/GoldLabel
@onready var hud_lives: Label = $TopBar/HBox/LivesLabel
@onready var hud_tier: Label = $TopBar/HBox/TierLabel
@onready var btn_back: Button = $TopBar/HBox/BackToMenuButton

var node_buttons: Dictionary = {}
var active_rings: Array[Sprite2D] = []

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(top_bar, Color(0.18, 0.15, 0.20, 0.95), 12)
	UIThemeHelper.apply_clay_button(btn_back)
	btn_back.pressed.connect(_on_back_to_menu)
	event_dialog.closed.connect(_on_event_closed)
	event_dialog.visible = false
	
	stage_preview_dialog.mission_started.connect(_on_mission_started)
	stage_preview_dialog.visible = false

	shop_dialog.closed.connect(_on_event_closed)
	shop_dialog.visible = false
	
	lines_draw.draw.connect(_on_draw_lines)
	_build_spire_ui()
	_update_top_bar()

func _process(delta: float) -> void:
	for ring in active_rings:
		if is_instance_valid(ring):
			ring.rotation += delta * 2.0
			var pulse = 0.35 + sin(Time.get_ticks_msec() * 0.006) * 0.03
			ring.scale = Vector2(pulse, pulse)

func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _update_top_bar() -> void:
	var act_name = GameState.get_act_name()
	hud_floor.text = "[ACT %d/3] %s  |  FLOOR: %d/%d" % [GameState.current_act, act_name, GameState.current_floor + 1, GameState.max_floors]
	hud_gold.text = "GOLD: %d G" % GameState.gold
	if GameState.player_count == 1:
		hud_lives.text = "LIVES: %d" % GameState.player_lives
		hud_tier.text = "TANK: %s" % _branch_label(GameState.tank_branch, GameState.branch_tier, GameState.player_tier)
	else:
		hud_lives.text = "LIVES: P1:%d | P2:%d" % [GameState.player_lives, GameState.p2_lives]
		var p1_tag = _branch_label(GameState.tank_branch, GameState.branch_tier, GameState.player_tier)
		var p2_tag = _branch_label(GameState.p2_branch, GameState.p2_branch_tier, GameState.p2_tier)
		hud_tier.text = "P1: %s | P2: %s" % [p1_tag, p2_tag]

func _branch_label(branch: String, tier: int, default_tier_idx: int) -> String:
	match branch:
		"speed":
			return "⚡ SPEED T%d" % tier
		"heavy":
			return "💥 HEAVY T%d" % tier
		"train":
			return "🚂 TRAIN T%d" % tier
		_:
			var tier_names = ["SCOUT", "STRIKER", "TWIN-GUN", "PLASMA DREAD"]
			return tier_names[default_tier_idx]

func _build_spire_ui() -> void:
	for child in map_canvas.get_children():
		child.queue_free()
	node_buttons.clear()
	active_rings.clear()

	var map_size = map_canvas.size
	if map_size.x <= 0:
		map_size = Vector2(1024, 660)

	for node_id in GameState.spire_nodes.keys():
		var data = GameState.spire_nodes[node_id]
		var pos = Vector2(data["pos_ratio"].x * map_size.x, data["pos_ratio"].y * map_size.y)
		
		var btn = TextureButton.new()
		btn.custom_minimum_size = Vector2(64, 64)
		btn.size = Vector2(64, 64)
		btn.position = pos - Vector2(32, 32)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

		var icon_name = "node_battle"
		match data["type"]:
			"battle": icon_name = "node_battle"
			"elite": icon_name = "node_elite"
			"challenge": icon_name = "node_challenge"
			"rest": icon_name = "node_rest"
			"shop": icon_name = "node_shop"
			"event": icon_name = "node_event"
			"boss": icon_name = "node_boss"

		var tex = TextureHelper.get_tex("res://assets/sprites/map/%s.png" % icon_name)
		if tex:
			btn.texture_normal = tex

		var is_available = GameState.is_node_available(node_id)
		var is_visited = GameState.visited_node_ids.has(node_id)

		if is_visited:
			btn.modulate = Color(0.42, 0.45, 0.50, 0.7)
			btn.disabled = true
		elif is_available:
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
			btn.disabled = false
			var ring = Sprite2D.new()
			var r_tex = TextureHelper.get_tex("res://assets/sprites/map/node_active_ring.png")
			if r_tex: ring.texture = r_tex
			ring.position = Vector2(32, 32)
			ring.scale = Vector2(0.35, 0.35)
			ring.modulate = Color(0.58, 0.88, 0.62, 0.9)
			btn.add_child(ring)
			active_rings.append(ring)
		else:
			btn.modulate = Color(0.45, 0.48, 0.55, 0.45)
			btn.disabled = true

		btn.pressed.connect(func(): _on_node_clicked(node_id))
		map_canvas.add_child(btn)
		node_buttons[node_id] = btn

	lines_draw.queue_redraw()

func _on_draw_lines() -> void:
	var map_size = map_canvas.size
	if map_size.x <= 0: map_size = Vector2(1024, 660)

	for conn in GameState.spire_connections:
		var n_from = GameState.spire_nodes.get(conn["from"])
		var n_to = GameState.spire_nodes.get(conn["to"])
		if n_from and n_to:
			var p1 = Vector2(n_from["pos_ratio"].x * map_size.x, n_from["pos_ratio"].y * map_size.y)
			var p2 = Vector2(n_to["pos_ratio"].x * map_size.x, n_to["pos_ratio"].y * map_size.y)
			
			var is_active_path = (GameState.current_node_id == conn["from"] and GameState.is_node_available(conn["to"]))
			var col = Color(0.6, 0.8, 0.93, 0.85) if is_active_path else Color(0.42, 0.36, 0.40, 0.5)
			var width = 3.5 if is_active_path else 1.8
			lines_draw.draw_line(p1, p2, col, width, true)

func _on_node_clicked(node_id: String) -> void:
	if not GameState.is_node_available(node_id):
		return

	var node_data = GameState.spire_nodes[node_id]
	var n_type = node_data["type"]

	SoundManager.play_hit_steel(get_tree())

	if n_type in ["battle", "elite", "boss", "challenge"]:
		stage_preview_dialog.setup_preview(node_id)
	elif n_type == "shop":
		GameState.visit_node(node_id)
		shop_dialog.setup_shop()
	else:
		GameState.visit_node(node_id)
		event_dialog.setup(n_type)

func _on_mission_started(node_id: String) -> void:
	GameState.visit_node(node_id)
	var node_data = GameState.spire_nodes[node_id]
	GameState.battle_type = node_data["type"]
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_event_closed() -> void:
	GameState.save_campaign()
	_update_top_bar()
	_build_spire_ui()
