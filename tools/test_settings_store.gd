extends SceneTree

## SettingsStore 的存档往返测试。跟 tools/test_custom_map_editor.gd 里
## CustomMapStore 的存档往返测试是同一套惯例: 全程重定向到临时文件, 绝不碰
## 玩家真实的 user://settings.json。
##
## 不测 DisplayServer/AudioServer 的实际生效 —— headless 没有真实显示器,
## apply_window() 在 DisplayServer.get_name() == "headless" 时直接跳过 (见
## settings_store.gd), 这里只验证 JSON 读写往返本身和默认值兜底逻辑。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_settings_store.gd

const SettingsStore = preload("res://scripts/settings_store.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> SETTINGS STORE TEST <<<")
	print("==================================================")

	var real_path := SettingsStore.save_path
	SettingsStore.save_path = "user://test_settings_tmp.json"

	_test_save_load_roundtrip()
	_test_missing_file_defaults()
	_test_corrupt_file_defaults()
	_test_out_of_range_volume_clamps()

	# 清理临时文件, 恢复真实路径 —— 顺序跟 CustomMapStore 的测试一样:
	# 先删文件, 再切回真实路径, 避免弄脏玩家的 settings.json。
	var tmp_global := ProjectSettings.globalize_path(SettingsStore.save_path)
	if FileAccess.file_exists(SettingsStore.save_path):
		DirAccess.remove_absolute(tmp_global)
	SettingsStore.save_path = real_path

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL SETTINGS STORE CHECKS PASSED! <<<")
		quit(0)


func _test_save_load_roundtrip() -> void:
	print("\n--- save() -> load_settings() 往返 ---")
	SettingsStore.save(1600, 1200, true, 0.42)
	var d := SettingsStore.load_settings()
	if d["window_w"] != 1600 or d["window_h"] != 1200 or d["fullscreen"] != true:
		fail("窗口字段没能穿过往返: %s" % str(d))
	elif not is_equal_approx(d["master_volume"], 0.42):
		fail("音量没能穿过往返: %s" % str(d["master_volume"]))
	else:
		ok("窗口尺寸/全屏/音量全部正确落盘并读回")


func _test_missing_file_defaults() -> void:
	print("\n--- 存档文件不存在时回落到默认值 ---")
	var tmp_global := ProjectSettings.globalize_path(SettingsStore.save_path)
	if FileAccess.file_exists(SettingsStore.save_path):
		DirAccess.remove_absolute(tmp_global)

	var d := SettingsStore.load_settings()
	if d["window_w"] != SettingsStore.DEFAULT_WINDOW_W or d["window_h"] != SettingsStore.DEFAULT_WINDOW_H:
		fail("文件缺失时窗口尺寸没有回落到默认值: %s" % str(d))
	elif d["fullscreen"] != SettingsStore.DEFAULT_FULLSCREEN:
		fail("文件缺失时全屏没有回落到默认值")
	elif not is_equal_approx(d["master_volume"], SettingsStore.DEFAULT_VOLUME):
		fail("文件缺失时音量没有回落到默认值")
	else:
		ok("文件不存在时安全回落到默认值, 不崩溃")


func _test_corrupt_file_defaults() -> void:
	print("\n--- 存档文件损坏(非法 JSON)时回落到默认值 ---")
	var f := FileAccess.open(SettingsStore.save_path, FileAccess.WRITE)
	f.store_string("{ this is not valid json ]]]")
	f = null  # 显式释放句柄, 确保内容落盘

	var d := SettingsStore.load_settings()
	if d["window_w"] != SettingsStore.DEFAULT_WINDOW_W or d["window_h"] != SettingsStore.DEFAULT_WINDOW_H:
		fail("损坏 JSON 没有回落到默认窗口尺寸: %s" % str(d))
	else:
		ok("损坏的 JSON 不会崩溃, 安全回落到默认值")


func _test_out_of_range_volume_clamps() -> void:
	print("\n--- 手改出界的音量值在读盘时被夹回 [0,1] ---")
	var f := FileAccess.open(SettingsStore.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"window_w": 1024, "window_h": 768,
		"fullscreen": false, "master_volume": 7.5,
	}))
	f = null

	var d := SettingsStore.load_settings()
	if d["master_volume"] > 1.0 or d["master_volume"] < 0.0:
		fail("出界音量 7.5 没有被夹回 [0,1]: 读到 %s" % str(d["master_volume"]))
	else:
		ok("出界音量被正确夹回 [0,1]: %s" % str(d["master_volume"]))

	# 负数同理
	f = FileAccess.open(SettingsStore.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"window_w": 1024, "window_h": 768,
		"fullscreen": false, "master_volume": -3.0,
	}))
	f = null
	var d2 := SettingsStore.load_settings()
	if d2["master_volume"] < 0.0:
		fail("负数音量没有被夹回 [0,1]: 读到 %s" % str(d2["master_volume"]))
	else:
		ok("负数音量同样被正确夹回")
