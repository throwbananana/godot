class_name TitleScreen
extends Control

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

const DEFAULT_PORT := 24567
const MAX_CLIENTS := 2

@onready var banner_sprite: Sprite2D = $CenterContainer/VBox/BannerContainer/BannerSprite
@onready var btn_1p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign1PButton
@onready var btn_2p_campaign: Button = $CenterContainer/VBox/ButtonsBox/Campaign2PButton
@onready var btn_2p_arcade: Button = $CenterContainer/VBox/ButtonsBox/Arcade2PButton
@onready var btn_quit: Button = $CenterContainer/VBox/ButtonsBox/QuitButton
@onready var buttons_box: VBoxContainer = $CenterContainer/VBox/ButtonsBox

var network_status: Label
var address_input: LineEdit
var host_button: Button
var join_button: Button
var _transition_started := false

func _ready() -> void:
	var b_tex = TextureHelper.get_tex("res://assets/sprites/ui/title_banner.png")
	if b_tex and banner_sprite:
		banner_sprite.texture = b_tex

	UIThemeHelper.apply_clay_button(btn_1p_campaign)
	UIThemeHelper.apply_clay_button(btn_2p_campaign)
	UIThemeHelper.apply_clay_button(btn_2p_arcade)
	UIThemeHelper.apply_clay_button(btn_quit)

	btn_1p_campaign.pressed.connect(func(): _start_campaign(1))
	btn_2p_campaign.pressed.connect(func(): _start_campaign(2))
	btn_2p_arcade.pressed.connect(_start_arcade_2p)
	btn_quit.pressed.connect(_on_quit_pressed)

	_build_online_controls()
	_bind_multiplayer_signals()

func _build_online_controls() -> void:
	var separator := HSeparator.new()
	buttons_box.add_child(separator)

	network_status = Label.new()
	network_status.text = "ONLINE CO-OP (ENet)"
	network_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buttons_box.add_child(network_status)

	address_input = LineEdit.new()
	address_input.placeholder_text = "Host IP (e.g. 192.168.1.20)"
	address_input.text = "127.0.0.1"
	address_input.tooltip_text = "For internet play, enter the host's reachable public/VPN IP. Default UDP port: %d" % DEFAULT_PORT
	buttons_box.add_child(address_input)

	host_button = Button.new()
	host_button.text = "HOST ONLINE CO-OP"
	UIThemeHelper.apply_clay_button(host_button)
	host_button.pressed.connect(_host_online_game)
	buttons_box.add_child(host_button)

	join_button = Button.new()
	join_button.text = "JOIN ONLINE CO-OP"
	UIThemeHelper.apply_clay_button(join_button)
	join_button.pressed.connect(_join_online_game)
	buttons_box.add_child(join_button)

func _bind_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _host_online_game() -> void:
	_disconnect_existing_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		_set_network_status("HOST FAILED: %s" % error_string(err), true)
		return

	multiplayer.multiplayer_peer = peer
	GameState.configure_online(true, "0.0.0.0", DEFAULT_PORT)
	GameState.network_peer_id = multiplayer.get_unique_id()
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	_set_network_status("HOSTING UDP %d — WAITING FOR PLAYER..." % DEFAULT_PORT)
	_set_online_controls_enabled(false)

func _join_online_game() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	_disconnect_existing_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, DEFAULT_PORT)
	if err != OK:
		_set_network_status("JOIN FAILED: %s" % error_string(err), true)
		return

	multiplayer.multiplayer_peer = peer
	GameState.configure_online(false, address, DEFAULT_PORT)
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	_set_network_status("CONNECTING TO %s:%d..." % [address, DEFAULT_PORT])
	_set_online_controls_enabled(false)

func _on_peer_connected(peer_id: int) -> void:
	if not GameState.online_mode or not GameState.is_network_host:
		return
	if peer_id <= 1:
		return
	GameState.network_peer_id = multiplayer.get_unique_id()
	GameState.network_remote_peer_id = peer_id
	_set_network_status("PLAYER CONNECTED — STARTING ONLINE ARCADE")
	_start_online_arcade()

func _on_connected_to_server() -> void:
	if not GameState.online_mode or GameState.is_network_host:
		return
	GameState.network_peer_id = multiplayer.get_unique_id()
	GameState.network_remote_peer_id = 1
	_set_network_status("CONNECTED — STARTING ONLINE ARCADE")
	_start_online_arcade()

func _on_connection_failed() -> void:
	_set_network_status("CONNECTION FAILED", true)
	GameState.reset_network()
	_disconnect_existing_peer()
	_set_online_controls_enabled(true)

func _on_server_disconnected() -> void:
	_set_network_status("HOST DISCONNECTED", true)
	GameState.reset_network()
	_disconnect_existing_peer()
	_set_online_controls_enabled(true)

func _start_online_arcade() -> void:
	if _transition_started:
		return
	_transition_started = true
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _set_network_status(message: String, is_error: bool = false) -> void:
	if network_status:
		network_status.text = message
		network_status.modulate = Color(1.0, 0.45, 0.45) if is_error else Color.WHITE

func _set_online_controls_enabled(enabled: bool) -> void:
	if host_button:
		host_button.disabled = not enabled
	if join_button:
		join_button.disabled = not enabled
	if address_input:
		address_input.editable = enabled

func _disconnect_existing_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _start_campaign(p_count: int) -> void:
	_disconnect_existing_peer()
	GameState.reset_network()
	SoundManager.play_shot(get_tree())
	GameState.reset_campaign(p_count)
	get_tree().change_scene_to_file("res://scenes/spire_map.tscn")

func _start_arcade_2p() -> void:
	_disconnect_existing_peer()
	GameState.reset_network()
	SoundManager.play_shot(get_tree())
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	_disconnect_existing_peer()
	get_tree().quit()
