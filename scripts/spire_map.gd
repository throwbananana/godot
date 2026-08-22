class_name SpireMap
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const EventDialog = preload("res://scripts/event_dialog.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

@onready var map_scroll: ScrollContainer = $MapArea/MapScroll
@onready var map_inner: Control = $MapArea/MapScroll/MapInner
@onready var map_canvas: Control = $MapArea/MapScroll/MapInner/MapCanvas
@onready var lines_draw: Control = $MapArea/MapScroll/MapInner/LinesDraw

# Floor nodes are positioned by pos_ratio.y (0..1) scaled against this
# canvas's height (see game_state.gd::_generate_spire_map). With a fixed,
# non-scrolling canvas that ratio math packed however many floors existed
# into one fixed viewport height -- fine at the original max_floors=6, but
# once floors went to 15 the same 0.78 fraction of height had to fit more
# than double the rows, squeezing them closer together than the 64px node
# buttons are tall (they started overlapping). Instead of shrinking nodes,
# the canvas now grows with floor count and sits in a ScrollContainer.
const ROW_HEIGHT_PX := 90.0
const MIN_CANVAS_HEIGHT := 660.0
@onready var event_dialog: PanelContainer = $EventDialog
@onready var stage_preview_dialog: PanelContainer = $StagePreviewDialog
@onready var shop_dialog: PanelContainer = $ShopDialog
@onready var top_bar: PanelContainer = $TopBar
@onready var hud_floor: Label = $TopBar/HBox/FloorBox/FloorLabel
@onready var hud_gold: Label = $TopBar/HBox/GoldBox/GoldLabel
@onready var hud_lives: Label = $TopBar/HBox/LivesBox/LivesLabel
@onready var hud_tier: Label = $TopBar/HBox/TierBox/TierLabel
@onready var icon_floor: TextureRect = $TopBar/HBox/FloorBox/FloorIcon
@onready var icon_gold: TextureRect = $TopBar/HBox/GoldBox/GoldIcon
@onready var icon_lives: TextureRect = $TopBar/HBox/LivesBox/LivesIcon
@onready var icon_tier: TextureRect = $TopBar/HBox/TierBox/TierIcon
@onready var btn_back: Button = $TopBar/HBox/BackToMenuButton

var node_buttons: Dictionary = {}
var active_rings: Array[Sprite2D] = []

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(top_bar, Color(0.18, 0.15, 0.20, 0.95), 12)
	UIThemeHelper.apply_icon_button(btn_back, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(22, 22))
	
	if icon_floor: icon_floor.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_terrain.png")
	if icon_gold: icon_gold.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_badge_gold.png")
	if icon_lives: icon_lives.texture = TextureHelper.get_tex("res://assets/sprites/ui/hp_heart_full.png")
	if icon_tier: icon_tier.texture = TextureHelper.get_tex("res://assets/sprites/ui/ui_icon_tank_p1.png")
	
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
	hud_floor.text = "[ACT %d/%d] %s  |  FLOOR: %d/%d" % [GameState.current_act, GameState.max_acts, act_name, GameState.current_floor + 1, GameState.max_floors]
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
			return "SPEED T%d" % tier
		"heavy":
			return "HEAVY T%d" % tier
		"train":
			return "TRAIN T%d" % tier
		_:
			var tier_names = ["SCOUT", "STRIKER", "TWIN-GUN", "PLASMA DREAD"]
			return tier_names[default_tier_idx]

## Viewport width (stable regardless of container layout timing) x a canvas
## height that grows with GameState.max_floors, so per-floor spacing stays
## constant instead of shrinking as more floors get added. Also stamps the
## computed height onto MapInner so the ScrollContainer knows how far it can
## scroll -- callers don't need to do that separately.
func _compute_map_size() -> Vector2:
	var w = get_viewport().get_visible_rect().size.x
	if w <= 0:
		w = 1024.0
	var h = maxf(MIN_CANVAS_HEIGHT, float(GameState.max_floors) * ROW_HEIGHT_PX)
	map_inner.custom_minimum_size = Vector2(w, h)
	return Vector2(w, h)

func _build_spire_ui() -> void:
	for child in map_canvas.get_children():
		child.queue_free()
	node_buttons.clear()
	active_rings.clear()

	var map_size = _compute_map_size()

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
	_scroll_to_current_floor(map_size)

## Floor 0 sits near the bottom of the canvas and the boss floor near the
## top (see the pos_ratio formula in game_state.gd). ScrollContainer opens
## scrolled to the top by default, which on a 15-floor map means the player
## lands on the boss end of the climb instead of where they actually are --
## center the view on their current (or starting) floor instead.
func _scroll_to_current_floor(map_size: Vector2) -> void:
	var target_node_id = GameState.current_node_id
	if target_node_id == "" :
		for node_id in GameState.spire_nodes.keys():
			if GameState.spire_nodes[node_id]["floor"] == 0:
				target_node_id = node_id
				break
	if not GameState.spire_nodes.has(target_node_id):
		return

	var target_y = GameState.spire_nodes[target_node_id]["pos_ratio"].y * map_size.y
	var viewport_h = map_scroll.size.y if map_scroll.size.y > 0 else 600.0
	var max_scroll = maxf(0.0, map_size.y - viewport_h)
	map_scroll.scroll_vertical = int(clampf(target_y - viewport_h / 2.0, 0.0, max_scroll))

func _on_draw_lines() -> void:
	var map_size = _compute_map_size()

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
	GameState.challenge_mode = str(node_data.get("challenge_mode", ""))
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_event_closed() -> void:
	GameState.save_campaign()
	_update_top_bar()
	_build_spire_ui()
