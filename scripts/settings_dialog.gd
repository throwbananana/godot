class_name SettingsDialog
extends Control

## 分辨率/全屏/音量的设置弹窗, 跟 encyclopedia_dialog.gd 走同一套模态惯例
## (DimBackground + CenterContainer + PanelContainer, open_dialog()/close_dialog(),
## ESC 关闭, closed 信号)。这份脚本不认场景 —— 只碰 SettingsStore/DisplayServer/
## AudioServer, 所以能同时被 title_screen.tscn 和 main.tscn(暂停菜单里) 各实例化
## 一份, 互不干扰。

const SoundManager = preload("res://scripts/sound_manager.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")
const SettingsStore = preload("res://scripts/settings_store.gd")

signal closed

@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var resolution_option: OptionButton = $CenterContainer/MainPanel/VBox/ResolutionRow/ResolutionOption
@onready var fullscreen_check: CheckBox = $CenterContainer/MainPanel/VBox/FullscreenRow/FullscreenCheck
@onready var volume_label: Label = $CenterContainer/MainPanel/VBox/VolumeLabel
@onready var volume_slider: HSlider = $CenterContainer/MainPanel/VBox/VolumeSlider
@onready var btn_close: Button = $CenterContainer/MainPanel/VBox/CloseButton

var _window_w: int = SettingsStore.DEFAULT_WINDOW_W
var _window_h: int = SettingsStore.DEFAULT_WINDOW_H
var _fullscreen: bool = SettingsStore.DEFAULT_FULLSCREEN
var _volume: float = SettingsStore.DEFAULT_VOLUME


func _ready() -> void:
	UIThemeHelper.apply_clay_panel(main_panel, Color(0.12, 0.10, 0.16, 0.98), 16)
	UIThemeHelper.apply_clay_button(btn_close, true)
	UIThemeHelper.apply_icon_button(btn_close, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(20, 20))
	UIThemeHelper.apply_clay_option_button(resolution_option)
	UIThemeHelper.apply_clay_check_box(fullscreen_check)
	UIThemeHelper.apply_clay_slider(volume_slider)

	for res in SettingsStore.RESOLUTIONS:
		resolution_option.add_item("%d x %d" % [res.x, res.y])

	btn_close.pressed.connect(close_dialog)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	resolution_option.item_selected.connect(_on_resolution_selected)
	volume_slider.value_changed.connect(_on_volume_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_dialog()


## 打开时把当前生效值 (SettingsStore.load_settings() 读到的存档, load_and_apply()
## 已经在游戏启动时应用过了) 回填进控件, 而不是假设控件的默认值就是当前状态 ——
## 否则第二次打开设置会显示 100% 音量, 即便玩家上次调到了 40%。
func open_dialog() -> void:
	visible = true
	SoundManager.play_shot(get_tree())

	var d := SettingsStore.load_settings()
	_window_w = d["window_w"]
	_window_h = d["window_h"]
	_fullscreen = d["fullscreen"]
	_volume = d["master_volume"]

	var res_idx := 0
	for i in range(SettingsStore.RESOLUTIONS.size()):
		if SettingsStore.RESOLUTIONS[i] == Vector2i(_window_w, _window_h):
			res_idx = i
			break
	resolution_option.select(res_idx)
	resolution_option.disabled = _fullscreen
	fullscreen_check.button_pressed = _fullscreen
	volume_slider.value = _volume * 100.0
	_update_volume_label()

	UIThemeHelper.focus_first(self)


func close_dialog() -> void:
	SoundManager.play_shot(get_tree())
	SettingsStore.save(_window_w, _window_h, _fullscreen, _volume)
	visible = false
	emit_signal("closed")


func _on_resolution_selected(idx: int) -> void:
	var res: Vector2i = SettingsStore.RESOLUTIONS[idx]
	_window_w = res.x
	_window_h = res.y
	if not _fullscreen:
		SettingsStore.apply_window(_window_w, _window_h, false)


func _on_fullscreen_toggled(pressed: bool) -> void:
	_fullscreen = pressed
	resolution_option.disabled = pressed
	SettingsStore.apply_window(_window_w, _window_h, pressed)


func _on_volume_changed(value: float) -> void:
	_volume = value / 100.0
	SettingsStore.apply_volume(_volume)
	_update_volume_label()


func _update_volume_label() -> void:
	volume_label.text = "音量 Volume: %d%%" % int(round(_volume * 100.0))
