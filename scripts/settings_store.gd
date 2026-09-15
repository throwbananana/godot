class_name SettingsStore
extends RefCounted

## 窗口分辨率/全屏/音量的持久化, 跟 scripts/custom_map_store.gd 是同一套
## user:// JSON 惯例, 同样故意不放进 GameState —— 这些是引擎级别的显示器/
## 音频设置, 不属于某一局战役的存档, 不该被 reset_campaign() 或
## test_persistence_roundtrip.gd 的存档往返检查盯上。
##
## save_path 特意不是 const, 原因跟 CustomMapStore 一样: 测试要能把它指到
## 临时文件, 不能污染玩家真实的 settings.json。

static var save_path: String = "user://settings.json"

const DEFAULT_WINDOW_W := 1024
const DEFAULT_WINDOW_H := 768
const DEFAULT_FULLSCREEN := false
const DEFAULT_VOLUME := 1.0

## project.godot 的基准画布是 1024x768 (4:3)。以前这里被迫只能列 4:3 比例 ——
## window/stretch/aspect 当时是默认值 "keep", 选别的比例会露黑边。现在
## project.godot 改成了 "expand": 战场本身是 GameArea 里固定像素坐标搭出来的
## 13x13 网格, 不会跟着变宽, 但 expand 会在窗口比基准画布更宽/更高的那个方向
## 多显出一截画布 (右/下方向), 而不是拉伸或裁切原有画面, HUD 里锚定在
## 右/下边缘的控件 (小地图、结构快捷栏等) 会跟着挪到新的边缘, 用上多出来的
## 屏幕空间。所以宽屏 (16:9/21:9) 预设不再需要凑 4:3 比例。
## 1024x768 仍是第一项 = 默认值, 跟 DEFAULT_WINDOW_W/H 保持一致。
const RESOLUTIONS := [
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]


## 读盘, 缺字段/文件不存在/JSON 损坏都补默认值 —— 公开方法, settings_dialog.gd
## 打开时用它回填控件当前值 (不能叫 _load_dict, 下划线前缀在这个项目里是
## "只在本文件内部调" 的约定; test_shop_economy_2p.gd 就踩过反例: 调用方
## 越过下划线私有方法调了不存在的名字, Godot 只报错不 fail, 断言整段静默失效)。
static func load_settings() -> Dictionary:
	var w := DEFAULT_WINDOW_W
	var h := DEFAULT_WINDOW_H
	var fullscreen := DEFAULT_FULLSCREEN
	var volume := DEFAULT_VOLUME

	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				w = int(parsed.get("window_w", w))
				h = int(parsed.get("window_h", h))
				fullscreen = bool(parsed.get("fullscreen", fullscreen))
				volume = clampf(float(parsed.get("master_volume", volume)), 0.0, 1.0)

	if w <= 0 or h <= 0:
		w = DEFAULT_WINDOW_W
		h = DEFAULT_WINDOW_H

	return {"window_w": w, "window_h": h, "fullscreen": fullscreen, "master_volume": volume}


## 读盘并立刻生效 —— 分辨率/全屏是 DisplayServer 的进程级状态, 音量是
## AudioServer 主线的状态, 都跟场景无关, 只需要在游戏启动时 (title_screen
## ._ready() 最前面) 调用一次, 不需要像 GameState 那样每次切场景重新同步。
static func load_and_apply() -> void:
	var d := load_settings()
	apply_window(d["window_w"], d["window_h"], d["fullscreen"])
	apply_volume(d["master_volume"])


## headless 跑测试时没有真实显示器, DisplayServer 的窗口调用要么是空操作
## 要么会报错刷屏 —— 跳过它们不影响测试要验的 JSON 读写往返本身。
## 公开方法: settings_dialog.gd 在用户拖动/勾选控件时调它做即时预览。
static func apply_window(w: int, h: int, fullscreen: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(w, h))
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen_size - Vector2i(w, h)) / 2)


static func apply_volume(volume: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	if volume > 0.001:
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))


static func save(window_w: int, window_h: int, fullscreen: bool, master_volume: float) -> void:
	var d := {
		"window_w": window_w,
		"window_h": window_h,
		"fullscreen": fullscreen,
		"master_volume": clampf(master_volume, 0.0, 1.0),
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
