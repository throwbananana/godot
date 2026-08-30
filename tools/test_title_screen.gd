extends SceneTree

## 标题界面的回归测试: 3D 黏土美术资源是否都挂上了, 以及两条隐藏暗号能不能真的
## 解锁 TEST MODE。
##
## 暗号那半是这个文件存在的主要理由。老版本只检查贴图非空 + 手动调一次
## _process(), 于是**手柄暗号整条路是死的却一路通过了**:
## title_screen.gd 当时把监听挂在 _unhandled_input(), 而标题界面永远有按钮持有
## 焦点, Godot 的 Viewport 会先拿 ui_up/ui_down/ui_left/ui_right 去做焦点导航并
## set_input_as_handled() —— D-pad 的方向键根本走不到 _unhandled_input。实测推
## 完整条 12 键序列, 缓冲区只收到 8 条。
##
## 所以这里断言的是**行为**而不是常量: 真的把 InputEventJoypadButton 推进
## Input, 真的等帧, 再看 GameState.debug_unlocked。换回 _unhandled_input 就会挂。
##
## 另外还钉死一条结构约束: 序列里不许出现 ui_accept / ui_cancel 绑的那两颗面键。
## A = ui_accept 会直接激活当前焦点按钮 (多半是 CONTINUE) 把场景切走, 暗号永远
## 输不完 —— 这条光靠推事件测不出来 (headless 里 Button 要按下+抬起才触发), 得
## 单独按名字拦。
##
## 跑法:
##   & $godot --headless --path . --script tools/test_title_screen.gd

const GameState = preload("res://scripts/game_state.gd")

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func _init() -> void:
	print("==================================================")
	print(">>> TITLE SCREEN (art / unlock sequences) TEST <<<")
	print("==================================================")
	call_deferred("_run")


func _run() -> void:
	await _test_art_wired_up()
	_test_gamepad_sequence_avoids_ui_buttons()
	await _test_keyboard_secret_unlocks()
	await _test_gamepad_secret_unlocks()
	await _test_test_mode_button_fits_grid()

	GameState.debug_unlocked = false

	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL TITLE SCREEN CHECKS PASSED! <<<")
		quit(0)


## 新建一个标题界面并等到布局/焦点都就绪 (UIThemeHelper.focus_first() 是 deferred
## 的, 立刻断言会拿到空焦点)。
func _fresh_title() -> Node:
	GameState.debug_unlocked = false
	var scn = load("res://scenes/title_screen.tscn").instantiate()
	root.add_child(scn)
	for _i in 20:
		await process_frame
	return scn


func _push_key(keycode: int) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	Input.parse_input_event(e)


func _push_pad(button_index: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button_index
	e.pressed = true
	Input.parse_input_event(e)


func _test_art_wired_up() -> void:
	print("\n[1] 标题界面美术资源")
	var scn = await _fresh_title()

	var checks := {
		"BackgroundTexture": "背景",
		"CenterContainer/VBox/LogoContainer/HaloSprite": "Logo 光环",
		"CenterContainer/VBox/LogoContainer/LogoTexture": "主徽标",
	}
	for path in checks:
		var node = scn.get_node_or_null(path)
		if node == null:
			fail("%s 节点缺失: %s" % [checks[path], path])
		elif node.texture == null:
			fail("%s 没有贴图: %s" % [checks[path], path])
		else:
			ok("%s: %s" % [checks[path], node.texture.resource_path])

	if scn.get_node_or_null("CenterContainer/VBox/LogoContainer/SparkleContainer") == null:
		fail("SparkleContainer 节点缺失, 星芒特效无处挂载")
	else:
		ok("SparkleContainer 存在")

	# 星芒序列 6 帧必须全部预加载成功, 否则 _spawn_logo_sparkle() 会静默空转。
	if scn._sparkle_textures.size() != 6:
		fail("星芒序列应预加载 6 帧, 实际 %d 帧" % scn._sparkle_textures.size())
	else:
		ok("星芒序列 6 帧全部加载")

	scn.free()


## A = ui_accept, B = ui_cancel。序列里放这两颗, 玩家输到那一步就会把焦点按钮
## 按下去 (CONTINUE -> 直接进战役), 暗号永远输不完。
func _test_gamepad_sequence_avoids_ui_buttons() -> void:
	print("\n[2] 手柄序列不得占用 ui_accept / ui_cancel")
	var TitleScreen = load("res://scripts/title_screen.gd")
	var seq: Array = TitleScreen.SECRET_GAMEPAD_SEQUENCE

	if JOY_BUTTON_A in seq:
		fail("序列含 JOY_BUTTON_A (ui_accept) —— 按到这一步会激活焦点按钮把场景切走")
	else:
		ok("不含 JOY_BUTTON_A")

	if JOY_BUTTON_B in seq:
		fail("序列含 JOY_BUTTON_B (ui_cancel)")
	else:
		ok("不含 JOY_BUTTON_B")


func _test_keyboard_secret_unlocks() -> void:
	print("\n[3] 键盘暗号")
	var scn = await _fresh_title()
	var TitleScreen = load("res://scripts/title_screen.gd")

	for ch in TitleScreen.SECRET_KEYWORD:
		_push_key(ch.to_upper().unicode_at(0))
		await process_frame

	if not GameState.debug_unlocked:
		fail("输入 \"%s\" 后 debug_unlocked 仍为 false" % TitleScreen.SECRET_KEYWORD)
	else:
		ok("键盘暗号解锁成功")
		var btn = scn.get_node_or_null("CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid/TestModeButton")
		if btn == null or not btn.visible:
			fail("解锁后 TestModeButton 仍不可见")
		else:
			ok("TestModeButton 已显示")

	scn.free()


## 这条就是老版本漏掉的那条。焦点在按钮上时 D-pad 会被焦点导航吃掉, 挂
## _unhandled_input 的实现在这里必挂。
func _test_gamepad_secret_unlocks() -> void:
	print("\n[4] 手柄暗号 (焦点在按钮上)")
	var scn = await _fresh_title()
	var TitleScreen = load("res://scripts/title_screen.gd")

	var focused = scn.get_viewport().gui_get_focus_owner()
	if focused == null:
		fail("标题界面没有任何控件持有焦点 —— 这条测试的前提不成立了")
	else:
		ok("当前焦点: %s (D-pad 会被焦点导航消费)" % focused.name)

	for b in TitleScreen.SECRET_GAMEPAD_SEQUENCE:
		_push_pad(b)
		await process_frame

	if not GameState.debug_unlocked:
		fail("推完整条手柄序列后 debug_unlocked 仍为 false (缓冲区只收到 %d/%d 条) —— 监听多半又挂回 _unhandled_input 了" % [
			scn._secret_pad_buffer.size(), TitleScreen.SECRET_GAMEPAD_SEQUENCE.size()])
	else:
		ok("手柄暗号解锁成功")

	scn.free()


## TestModeButton 藏在一个 columns=2 的 GridContainer 里, 最小宽度必须跟同格的
## 兄弟一致 —— 它曾经是 400 而兄弟是 197, 一解锁就把整列顶宽, 菜单面板横向跳一下。
func _test_test_mode_button_fits_grid() -> void:
	print("\n[5] TestModeButton 不撑破菜单网格")
	var scn = await _fresh_title()
	var grid = scn.get_node_or_null("CenterContainer/VBox/MenuPanel/MenuVBox/SecondaryGrid")
	if grid == null:
		fail("SecondaryGrid 缺失")
		scn.free()
		return

	var widths := {}
	for child in grid.get_children():
		if child is Button:
			widths[child.name] = child.custom_minimum_size.x

	var test_w = widths.get("TestModeButton", -1.0)
	var sibling_w := -1.0
	for name in widths:
		if name != "TestModeButton":
			sibling_w = widths[name]
			break

	if test_w != sibling_w:
		fail("TestModeButton 最小宽度 %.0f 与同格兄弟 %.0f 不一致, 显示后会撑宽整列" % [test_w, sibling_w])
	else:
		ok("TestModeButton 与兄弟同宽 (%.0f)" % test_w)

	scn.free()
