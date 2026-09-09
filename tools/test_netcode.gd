extends SceneTree

## 联机数据层的回归测试。**不开任何端口、不连任何东西** ——
## 能被 headless 测的部分全在 scripts/net_session.gd 里 (见那个文件顶部
## 关于为什么要这样切分的说明), 这里把它们全跑一遍。
##
## 按项目惯例用 print("[FAIL] …") + quit(1) 而不是 assert: assert 在
## headless 下会挂着等一个永远不会来的调试器, 表现为 TIMEOUT 而不是 FAIL,
## 而 TIMEOUT 不带任何诊断信息 (见 CLAUDE.md "An assert guarding anything
## randomised is a latent TIMEOUT")。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")

const SAVE_PATH := "user://campaign_save.json"
## 哨兵金币数, 取一个不可能自然出现的值。
const SENTINEL_GOLD := 987654

var failures: int = 0


func fail(msg: String) -> void:
	failures += 1
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func check(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func _init() -> void:
	print("==================================================")
	print(">>> NETCODE DATA-LAYER TEST <<<")
	print("==================================================")
	_test_role_predicates()
	_test_input_bits()
	_test_direction_priority()
	_test_snapshot_roundtrip()
	_test_snapshot_malformed()
	_test_entity_tables()
	_test_spawn_payload_roundtrip()
	_test_terrain_checksum()
	_test_input_seam_still_wired()
	_test_client_never_writes_save()
	print("==================================================")
	if failures > 0:
		print("[FAIL] %d 项失败" % failures)
		quit(1)
	else:
		print(">>> ALL NETCODE CHECKS PASSED! <<<")
		quit(0)


## is_authority() 是整套改造里最要命的一个谓词: main.gd 用它决定要不要跑
## 刷怪/判负, player/enemy/bullet 用它的兄弟 is_puppet 决定要不要跑逻辑。
## 它要是反了, 单机游戏会整个停摆 —— 所以真值表必须钉死。
func _test_role_predicates() -> void:
	print("\n[1] 角色谓词真值表")
	NetSession.reset()
	check(not NetSession.is_active(), "离线: is_active 为假")
	check(NetSession.is_authority(), "离线: is_authority 为真 (单机必须照跑)")
	check(not NetSession.is_host() and not NetSession.is_client(), "离线: 既不是主机也不是客户端")

	NetSession.role = NetSession.Role.HOST
	check(NetSession.is_active() and NetSession.is_host(), "主机: is_active / is_host")
	check(NetSession.is_authority(), "主机: is_authority 为真")

	NetSession.role = NetSession.Role.CLIENT
	check(NetSession.is_active() and NetSession.is_client(), "客户端: is_active / is_client")
	check(not NetSession.is_authority(), "客户端: is_authority 为假 (不跑权威逻辑)")
	NetSession.reset()


func _test_input_bits() -> void:
	print("\n[2] 输入位")
	var bits := NetSession.IN_UP | NetSession.IN_FIRE
	check(NetSession.has_bit(bits, NetSession.IN_UP), "UP 位读得出来")
	check(NetSession.has_bit(bits, NetSession.IN_FIRE), "FIRE 位读得出来")
	check(not NetSession.has_bit(bits, NetSession.IN_DOWN), "没设的 DOWN 位读不出来")

	# 九个位必须互不重叠 —— 手写移位常量最容易犯的错就是写重复一个数字,
	# 而重复之后"按前进"和"按建造"会互相触发, 现象离原因非常远。
	var all_bits := [
		NetSession.IN_UP, NetSession.IN_DOWN, NetSession.IN_LEFT, NetSession.IN_RIGHT,
		NetSession.IN_FIRE, NetSession.IN_BUILD_PREV, NetSession.IN_BUILD_NEXT,
		NetSession.IN_BUILD_PLACE, NetSession.IN_BUILD_CANCEL,
	]
	var seen := {}
	var dup := false
	for b in all_bits:
		if seen.has(b):
			dup = true
		seen[b] = true
	check(not dup, "九个输入位互不重复")

	NetSession.reset()
	NetSession.role = NetSession.Role.HOST
	NetSession.remote_input[2] = NetSession.IN_LEFT
	check(NetSession.input_for(2) == NetSession.IN_LEFT, "主机: 2 号玩家读到的是客户端发来的位")
	NetSession.role = NetSession.Role.CLIENT
	check(NetSession.input_for(1) == 0 and NetSession.input_for(2) == 0, "客户端: 任何玩家的输入都读成 0 (坦克是傀儡)")
	NetSession.reset()


## 方向优先级必须和 player.gd 原来那串 if/elif 逐条一致。
## 同时按住两个方向在坦克大战里是常态 (转弯的瞬间), 优先级一变, 联机下
## 同一套按键就会走出不同的轨迹 —— 而且只在两个人同时打的时候才看得出来。
func _test_direction_priority() -> void:
	print("\n[3] 方向优先级 (上 > 下 > 左 > 右)")
	check(NetSession.dir_from_bits(0) == Vector2.ZERO, "空输入 -> ZERO")
	check(NetSession.dir_from_bits(NetSession.IN_UP) == Vector2.UP, "UP -> UP")
	check(NetSession.dir_from_bits(NetSession.IN_DOWN) == Vector2.DOWN, "DOWN -> DOWN")
	check(NetSession.dir_from_bits(NetSession.IN_LEFT) == Vector2.LEFT, "LEFT -> LEFT")
	check(NetSession.dir_from_bits(NetSession.IN_RIGHT) == Vector2.RIGHT, "RIGHT -> RIGHT")
	check(NetSession.dir_from_bits(NetSession.IN_UP | NetSession.IN_DOWN) == Vector2.UP, "上+下 -> 上")
	check(NetSession.dir_from_bits(NetSession.IN_DOWN | NetSession.IN_LEFT) == Vector2.DOWN, "下+左 -> 下")
	check(NetSession.dir_from_bits(NetSession.IN_LEFT | NetSession.IN_RIGHT) == Vector2.LEFT, "左+右 -> 左")
	check(NetSession.dir_from_bits(NetSession.IN_FIRE) == Vector2.ZERO, "只按开火不产生位移")


func _test_snapshot_roundtrip() -> void:
	print("\n[4] 快照编解码往返")
	var src: Array = [
		{"id": 1, "flags": NetSession.F_VISIBLE, "pos": Vector2(120.5, -33.25), "rot": 1.5, "vel": Vector2(125.0, 0.0), "extra": 143.75},
		{"id": 7, "flags": NetSession.F_INVULNERABLE | NetSession.F_DYING, "pos": Vector2(0.0, 0.0), "rot": -3.0, "vel": Vector2(0.0, -720.0), "extra": 0.0},
		{"id": 99, "flags": 0, "pos": Vector2(-1.5, 2048.0), "rot": 0.0, "vel": Vector2.ZERO, "extra": -1.5},
	]
	var out := NetSession.decode_snapshot(NetSession.encode_snapshot(src))
	if out.size() != src.size():
		fail("往返之后条数变了: %d -> %d" % [src.size(), out.size()])
		return
	var bad := 0
	for i in range(src.size()):
		var a: Dictionary = src[i]
		var b: Dictionary = out[i]
		# 线格式是 float32, 所以不能比全等 —— 这里的容差就是 float32 在
		# 这个量级上的精度 (2048 处约 1.2e-4)。
		if int(a["id"]) != int(b["id"]) or int(a["flags"]) != int(b["flags"]):
			bad += 1
			fail("第 %d 条的 id/flags 变了: %s vs %s" % [i, a, b])
		elif (a["pos"] as Vector2).distance_to(b["pos"]) > 0.01 \
			or absf(float(a["rot"]) - float(b["rot"])) > 0.001 \
			or (a["vel"] as Vector2).distance_to(b["vel"]) > 0.01 \
			or absf(float(a["extra"]) - float(b["extra"])) > 0.01:
			bad += 1
			fail("第 %d 条的位置/旋转/速度/附加量超出 float32 容差: %s vs %s" % [i, a, b])
	if bad == 0:
		ok("3 条实体全部逐字段往返成功 (含 extra: 玩家的有效速度)")

	# 少写一个字段不能悄悄变成 0 —— extra 是本地预测的速度源, 它掉成 0 的
	# 症状是"客户端自己那辆坦克按键不动", 离原因非常远。
	var no_extra := NetSession.decode_snapshot(NetSession.encode_snapshot(
		[{"id": 3, "flags": 0, "pos": Vector2.ZERO, "rot": 0.0, "vel": Vector2.ZERO}]))
	check(no_extra.size() == 1 and float(no_extra[0]["extra"]) == 0.0, "没给 extra 时编成 0 且解得出来")

	check(NetSession.decode_snapshot(NetSession.encode_snapshot([])).is_empty(), "空快照往返成空")


## 快照走 unreliable 通道, 一个被截断/损坏的包不该把整局游戏带走。
func _test_snapshot_malformed() -> void:
	print("\n[5] 损坏的快照必须被安全丢弃")
	check(NetSession.decode_snapshot([]).is_empty(), "字段数不对 -> 空")
	check(NetSession.decode_snapshot([1, 2]).is_empty(), "只有两段 -> 空")
	var ids := PackedInt32Array([1, 2])
	var flags := PackedInt32Array([0, 0])
	var short_data := PackedFloat32Array([0.0, 0.0, 0.0])  # 应该是 2*SNAP_STRIDE 个
	check(NetSession.decode_snapshot([ids, flags, short_data]).is_empty(), "数据段长度对不上 -> 空")
	var mismatched := PackedInt32Array([0])
	check(NetSession.decode_snapshot([ids, mismatched, short_data]).is_empty(), "flags 段长度对不上 -> 空")


## SCRIPT_KIND / KIND_SCENE 是两张手写的表, 而"改名之后忘了改表"完全不会
## 报错 —— 只会表现为"那种敌人在客户端上根本不出现"。
func _test_entity_tables() -> void:
	print("\n[6] 实体表指向的文件都还在")
	for path in NetSession.SCRIPT_KIND:
		check(ResourceLoader.exists(path), "脚本存在: %s" % path)
	for kind in NetSession.KIND_SCENE:
		check(ResourceLoader.exists(NetSession.KIND_SCENE[kind]), "场景存在: %s" % NetSession.KIND_SCENE[kind])

	# 每一种能被识别的实体都必须有对应的场景, 否则客户端认得出它却造不出它。
	var missing: Array = []
	for path in NetSession.SCRIPT_KIND:
		var kind: int = NetSession.SCRIPT_KIND[path]
		if not NetSession.KIND_SCENE.has(kind):
			missing.append(path)
	check(missing.is_empty(), "SCRIPT_KIND 里的每一类都在 KIND_SCENE 里有场景 (缺: %s)" % str(missing))

	# VFX 都是代码里 new() 出来的, scene_file_path 是空的 —— 这正是把它们
	# 排除在复制之外的判据, 所以要钉住。
	var plain := Node2D.new()
	check(NetSession.classify(plain) == NetSession.Kind.IGNORED, "没有脚本也不是场景实例 -> IGNORED (VFX 不会被当成实体复制)")
	plain.free()

	# 兜底档: 从场景实例化出来的任何东西 (玩家造的建筑、火车车厢……) 都要
	# 被复制, 靠它自己的 scene_file_path, 不靠一张会过期的类型表。
	var from_scene := Node2D.new()
	from_scene.scene_file_path = "res://scenes/buildings/oil_barrel.tscn"
	check(NetSession.classify(from_scene) == NetSession.Kind.SCENE_NODE, "场景实例 -> SCENE_NODE")
	var sp := NetSession.spawn_payload(from_scene, NetSession.Kind.SCENE_NODE)
	check(String(sp.get("scene", "")) == "res://scenes/buildings/oil_barrel.tscn", "SCENE_NODE 的 payload 带着自己的场景路径")
	from_scene.free()

	# 已知类型优先于兜底档: 子弹是从 bullet.tscn 实例化的, 但它必须被认成
	# BULLET (才有方向/速度可以推算), 不能掉进 SCENE_NODE。
	check(not NetSession.SCRIPT_KIND.is_empty(), "SCRIPT_KIND 非空")
	check(NetSession.Kind.BULLET in NetSession.SELF_DRIVEN_KINDS, "BULLET 属于自驱类型 (net_manager 不能再替它跑一遍插值)")
	check(not (NetSession.Kind.SCENE_NODE in NetSession.SELF_DRIVEN_KINDS), "SCENE_NODE 不是自驱类型 (它的处理是关掉的, 必须由 net_manager 代跑)")


## 子弹的 payload 字段最多, 而少传一个字段的后果是"客户端那颗子弹长得不一样
## 或者飞得不一样", 不会报错。
func _test_spawn_payload_roundtrip() -> void:
	print("\n[7] 生成参数往返 (子弹)")
	var src := _BulletStub.new()
	src.direction = Vector2.LEFT
	src.speed = 720.0
	src.can_destroy_steel = true
	src.is_homing = true
	src.is_aoe = true
	src.is_kinetic_push = true
	src.bounces_remaining = 3
	src.custom_texture_path = "res://assets/sprites/effects/bullet_ricochet.png"

	var payload := NetSession.spawn_payload(src, NetSession.Kind.BULLET)
	var dst := _BulletStub.new()
	NetSession.apply_spawn_payload(dst, NetSession.Kind.BULLET, payload)

	check(dst.direction == src.direction, "direction 往返")
	check(is_equal_approx(dst.speed, src.speed), "speed 往返")
	check(dst.can_destroy_steel == src.can_destroy_steel, "can_destroy_steel 往返")
	check(dst.is_homing == src.is_homing, "is_homing 往返")
	check(dst.is_aoe == src.is_aoe, "is_aoe 往返")
	check(dst.is_kinetic_push == src.is_kinetic_push, "is_kinetic_push 往返")
	check(dst.bounces_remaining == src.bounces_remaining, "bounces_remaining 往返")
	check(dst.custom_texture_path == src.custom_texture_path, "custom_texture_path 往返")

	# 反过来: payload 里不该混进"客户端根本用不上"的东西。这不是洁癖 ——
	# 每个字段都是一次 RPC 的体积, 而生成包是 reliable 的。
	check(not payload.has("damage"), "payload 里没有 damage (客户端不做伤害判定)")
	src.free()
	dst.free()


func _test_terrain_checksum() -> void:
	print("\n[8] 地形校验和")
	var a := _make_terrain([[1, 1, "brick"], [2, 1, "brick"], [3, 5, "steel_"]])
	var b := _make_terrain([[1, 1, "brick"], [2, 1, "brick"], [3, 5, "steel_"]])
	var c := _make_terrain([[1, 1, "brick"], [2, 1, "brick"], [3, 5, "brick"]])  # 同一格换了类型
	var d := _make_terrain([[1, 1, "brick"], [2, 1, "brick"]])                   # 少一块
	var e := _make_terrain([[3, 5, "steel_"], [1, 1, "brick"], [2, 1, "brick"]]) # 顺序不同

	var ha := NetSession.terrain_checksum(a, 48.0)
	var hb := NetSession.terrain_checksum(b, 48.0)
	var hc := NetSession.terrain_checksum(c, 48.0)
	var hd := NetSession.terrain_checksum(d, 48.0)
	var he := NetSession.terrain_checksum(e, 48.0)

	check(ha == hb, "同样的地图 -> 同样的校验和")
	check(ha != hc, "同一格从 steel 变 brick -> 校验和变了 (只数节点数量抓不到这个)")
	check(ha != hd, "少一块砖 -> 校验和变了")
	check(ha == he, "建图顺序不同不影响校验和")
	for n in [a, b, c, d, e]:
		n.free()


func _make_terrain(cells: Array) -> Node2D:
	var root := Node2D.new()
	var i := 0
	for cell in cells:
		var tile := Node2D.new()
		# 摆在格心, 和 main.gd::_spawn_tile 一致 —— 用整格坐标的话就测不到
		# floor/round 那个格号折叠的坑。
		tile.position = Vector2((float(cell[0]) + 0.5) * 48.0, (float(cell[1]) + 0.5) * 48.0)
		# 校验和只取名字前 6 个字符 (类型标签), 后面的序号故意不同,
		# 用来验证它确实只看类型不看具体名字。
		tile.name = "%s_%d" % [cell[2], i]
		root.add_child(tile)
		i += 1
	return root


## 这不是在测数据, 是在测"接缝还接着"。
##
## player.gd 里那段输入读取很容易在后续改动中被"顺手"改回直接调
## Input.is_action_pressed —— 改回去之后单机毫无异常, 只有联机时客户端
## 的坦克不动, 而那时候没人会想到去看 player.gd。
func _test_input_seam_still_wired() -> void:
	print("\n[9] player.gd 的输入接缝")
	var src := FileAccess.get_file_as_string("res://scripts/player.gd")
	if src == "":
		fail("读不到 res://scripts/player.gd")
		return
	check(src.contains("NetSession.input_for(player_id)"), "移动输入仍然走 NetSession.input_for()")
	check(src.contains("NetPuppet.is_puppet(self)"), "_physics_process 顶上仍然有傀儡早退分支")
	check(not src.contains('Input.is_action_pressed("p2_move'), "没有绕过 NetSession 直接读 p2 移动键")
	check(not src.contains('Input.is_action_pressed(act_'), "没有残留旧的 act_* 直读路径")

	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	# 不带冒号: 那一行后面还挂着 `or _net_disconnected`, 而这里要钉住的是
	# "客户端会早退"这件事, 不是那行的确切写法。
	check(main_src.contains("if not NetSession.is_authority()"), "main.gd::_process 仍然有客户端早退")


## 联机战役里, 客户端的 GameState 装的是**主机那一局**, 而 save_campaign()
## 每过一道门就会被 visit_room() 调一次。不拦的话, "陪朋友打一局联机战役"
## 会把自己的 campaign_save.json 静默覆盖成别人的进度 —— 不可逆的数据丢失。
##
## **这条断言必须在单进程里做。** 端到端那个测试放不了它: 两个测试进程是
## 同一个项目, 共用同一个 user:// 目录也就是同一份存档文件, 而主机在联机
## 战役里本来就该存盘 —— "文件里是主机的数据"既可能是客户端违规、也可能是
## 主机正常存档, 分辨不了。
func _test_client_never_writes_save() -> void:
	print("\n[10] 联机客户端不许碰本机存档")
	# 这个测试会往真实的 user:// 写东西 (项目里 test_persistence_roundtrip
	# 等也是这么干的), 但还是备份一下, 别把开发者自己的存档弄没了。
	var had := FileAccess.file_exists(SAVE_PATH)
	var backup := ""
	if had:
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if bf:
			backup = bf.get_as_text()
			bf.close()

	NetSession.reset()
	GameState.reset_campaign(1)
	GameState.gold = SENTINEL_GOLD
	GameState.save_campaign()
	check(_saved_gold() == SENTINEL_GOLD, "离线时 save_campaign() 正常写盘")

	NetSession.role = NetSession.Role.CLIENT
	GameState.gold = 111111
	GameState.save_campaign()
	check(_saved_gold() == SENTINEL_GOLD, "客户端调 save_campaign() 不写盘 (盘上仍是 %d)" % _saved_gold())

	GameState.delete_saved_game()
	check(FileAccess.file_exists(SAVE_PATH), "客户端调 delete_saved_game() 不删档")

	# 回到离线: 拦截必须是**有条件**的, 而不是把存档功能整个关掉了。
	NetSession.reset()
	GameState.gold = 4242
	GameState.save_campaign()
	check(_saved_gold() == 4242, "退出联机后 save_campaign() 恢复正常")

	if had:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if wf:
			wf.store_string(backup)
			wf.close()
		ok("已还原开发者原本的存档")
	else:
		GameState.delete_saved_game()


func _saved_gold() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return -1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return -1
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return -1
	return int(parsed.get("gold", -1))


## spawn_payload 只读字段不调方法, 所以用一个裸对象当替身就够了 ——
## 真的去实例化 bullet.tscn 会连带加载贴图, 让这个测试依赖美术资源。
class _BulletStub extends Node:
	var direction: Vector2 = Vector2.UP
	var speed: float = 480.0
	var can_destroy_steel: bool = false
	var is_homing: bool = false
	var is_aoe: bool = false
	var is_kinetic_push: bool = false
	var bounces_remaining: int = 0
	var custom_texture_path: String = ""
