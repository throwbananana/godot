extends SceneTree

## actors_container 生成站点的联机审计。
##
## 背景: 联机把 actors_container 变成了一条有语义的边界 ——
## net_manager::_send_snapshot() 每帧扫这个容器, 把非 IGNORED 的一律登记下发。
## 于是"往这里加个节点"这件事有了一个此前不存在的判据:
##
##   确定性地图内容 (两端都会各建一份) -> _add_map_furniture(), 不进复制层,
##                                        只复制它的状态变化;
##   主机逻辑动态生成的 (敌人/子弹/掉落/友军) -> 裸 add_child(), 让复制层接管。
##
## **两个方向的误用都不报错**: 家具漏标 -> 客户端拿到双份 (完全重叠, 肉眼
## 看不出来, 直到你朝它开一枪); 动态物误标成家具 -> 客户端永远看不见它
## (护送友军被误标的话, 要保护的目标就是隐形的)。
##
## 这个文件从两个方向钉住那条判据。
##
## 按项目惯例: 不用 assert, print("[FAIL] …") 记全局标志, 最后只 quit 一次。

const NetSession = preload("res://scripts/net_session.gd")
const GameState = preload("res://scripts/game_state.gd")

const MAIN_GD := "res://scripts/main.gd"

## 已复核过的生成站点: 函数名 -> 它为什么不会在客户端上被触达。
##
## **用函数名当键而不是行号** —— 行号一次编辑就全废了, 而函数名跟着重命名走
## 的概率低得多, 真改了名字这里也会红, 正好逼你重新想一遍。
##
## 这份清单的作用不是"运行时查表"(那种表会烂, 见 CLAUDE.md "What gets
## replicated is a rule, not a list"), 而是**一道复核闸**: 往
## actors_container 里加新的生成点时这个测试会红, 你必须回答"客户端会不会
## 也跑到这里", 而不是默默加完了事。
const REVIEWED_SPAWN_SITES := {
	"_add_map_furniture":
		"家具助手本体 —— 它就是打标记的那个函数",
	"_grant_treasure_room_reward":
		"_on_enter_non_combat_room() 的主机分支; 客户端在该 match 里 early-return",
	"_drop_treasure_key":
		"由 check_key_drop() 从地形破坏路径调用; 客户端不跑伤害/碰撞逻辑",
	"try_spawn_block_loot":
		"同上 —— 调用方是 bullet/hard_clay_block/laser_ring_cutter/missile_strike 的 take_hit 路径, 且都不在 _exit_tree 里 (客户端的 net_remove_tile 只 queue_free, 不会掉落)",
	"_spawn_escort_ally":
		"_begin_room_encounter() 内, 客户端整段跳过 (见 test_net_room_variants.gd)",
	"_spawn_player":
		"_place_players_at_entry() 与重生路径, 都在 is_authority() 判定之后",
	"_spawn_falling_bomb":
		"_process() 内的 night_bombs 计时器; 客户端 _process 早退",
	"_request_spawn_enemy":
		"_process() 内的刷怪循环; 客户端 _process 早退",
	"_instantiate_enemy":
		"spawn_star 的 finished 回调; 而星星本身只在主机生成",
	"_on_enemy_destroyed":
		"敌人死亡信号; 客户端的敌人是傀儡 (_physics_process 关掉), 不跑死亡逻辑",
	"_grant_room_clear_reward":
		"清房判定在 _process() 内; 客户端 _process 早退",
	"_on_player_destroyed":
		"玩家死亡信号; 伤害结算在权威侧, 客户端不会自己判死",
}

var _failed := false


func fail(msg: String) -> void:
	_failed = true
	print("[FAIL] %s" % msg)


func ok(msg: String) -> void:
	print("  [ok] %s" % msg)


func check(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print(">>> ACTORS_CONTAINER SPAWN AUDIT <<<")
	print("==================================================")

	_test_all_sites_reviewed()
	await _test_client_builds_only_furniture()

	NetSession.reset()
	print("==================================================")
	if _failed:
		print("[FAIL] 生成站点审计未通过")
		quit(1)
	else:
		print(">>> ALL SPAWN AUDIT CHECKS PASSED! <<<")
		quit(0)


## 静态半: main.gd 里每一处往 actors_container 加节点的地方, 都必须在
## REVIEWED_SPAWN_SITES 里有一条说明。
func _test_all_sites_reviewed() -> void:
	print("\n[1] 所有生成站点都已复核")
	var f := FileAccess.open(MAIN_GD, FileAccess.READ)
	if f == null:
		fail("读不到 %s" % MAIN_GD)
		return
	var lines := f.get_as_text().split("\n")
	f.close()

	var current_fn := ""
	var found := {}
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("func "):
			current_fn = stripped.substr(5).split("(")[0].strip_edges()
		# 注释行不算 —— 文档里提到这个调用不等于真的调了。
		if stripped.begins_with("#"):
			continue
		if line.find("actors_container.add_child(") >= 0 \
				or line.find("actors_container.call_deferred(\"add_child\"") >= 0:
			if not found.has(current_fn):
				found[current_fn] = []
			found[current_fn].append(i + 1)

	check(found.size() > 0, "扫到了生成站点 (%d 个函数)" % found.size())

	var unreviewed: Array = []
	for fn in found:
		if not REVIEWED_SPAWN_SITES.has(fn):
			unreviewed.append("%s (行 %s)" % [fn, str(found[fn])])
	if unreviewed.is_empty():
		ok("%d 个函数全部有复核说明" % found.size())
	else:
		fail("以下函数往 actors_container 生成节点但没有复核说明 —— 请判断客户端会不会也跑到这里, 是确定性地图内容就改用 _add_map_furniture(), 否则在 REVIEWED_SPAWN_SITES 里补一条说明它为什么只在主机侧发生:\n      %s" % "\n      ".join(unreviewed))

	# 反向: 清单里有、代码里已经没有的条目要清掉, 否则这份清单会慢慢变成
	# 一堆没人敢删的死条目 (跟 CLAUDE.md 记的那些豁免名单同一个病)。
	var stale: Array = []
	for fn in REVIEWED_SPAWN_SITES:
		if not found.has(fn):
			stale.append(str(fn))
	if stale.is_empty():
		ok("清单里没有失效条目")
	else:
		fail("REVIEWED_SPAWN_SITES 里这些函数在 main.gd 里已经不生成节点了, 请删掉: %s" % str(stale))


## 运行期半 —— 这一条是**规则**而不是清单, 新增的生成点自动被它管到。
##
## 客户端不跑任何战斗逻辑, 所以它的 actors_container 里能出现的东西只有两类:
## 自己按种子建出来的地图家具, 或主机下发的傀儡。出现第三类, 就说明有一条
## 本该只在主机侧发生的生成路径漏到了客户端。
func _test_client_builds_only_furniture() -> void:
	print("\n[2] 客户端只会本地建出家具 (规则, 非清单)")
	NetSession.reset()
	NetSession.role = NetSession.Role.CLIENT
	NetSession.local_player_id = 2
	NetSession.match_seed = 12345
	GameState.mode = GameState.GameMode.ARCADE
	GameState.player_count = 2
	# 强制一张摆满 actors_container 家具的图。默认街机图随机抽出来可能只有
	# 一两件家具, 那样这条不变式几乎没被压到 —— "跑过了"和"测到了"是两回事
	# (见 [[test-assertions-can-be-vacuous]] 那次 0 vs 0 的教训)。
	GameState.playtest_layout = _furnished_layout()

	var packed := load("res://scenes/main.tscn")
	if packed == null:
		fail("main.tscn 加载失败")
		return
	var m: Node = packed.instantiate()
	root.add_child(m)
	for i in range(5):
		m._process(0.016)

	var built: int = m.actors_container.get_children().size()
	check(built >= 6, "客户端确实建出了成规模的家具 (%d 件, 否则这条断言是空转的)" % built)
	_assert_only_furniture_or_puppets(m, "建图后")

	# 再跑一段时间。客户端的 _process 早退, 所以刷怪/掉落/清房奖励一个都不该
	# 冒出来 —— 有的话就是某条路径绕过了那个早退。
	for i in range(60):
		m._process(0.016)
	_assert_only_furniture_or_puppets(m, "跑了 60 帧之后")

	m.free()


func _assert_only_furniture_or_puppets(m: Node, phase: String) -> void:
	var bad: Array = []
	for ch in m.actors_container.get_children():
		if ch.has_meta(NetSession.FURNITURE_META):
			continue
		if ch.has_meta("net_id") or ch.has_meta("net_puppet"):
			continue
		var scr = ch.get_script()
		bad.append(scr.resource_path.get_file() if scr else ch.get_class())
	if bad.is_empty():
		ok("%s: 没有本地生成的非家具节点" % phase)
	else:
		fail("%s: 客户端本地生成了既非家具也非傀儡的节点 %s —— 说明有一条主机侧路径漏到了客户端" % [phase, str(bad)])


## 一张摆满 actors_container 家具的 13x13。避开老鹰砖圈 (11-12 行) 和三个
## 敌人出生点 (0 行的 0/6/12 列), 免得被基地/出生点开路逻辑覆盖掉。
## 选的都是走 _add_map_furniture() 的瓦片类型, 覆盖到不同的生成函数。
func _furnished_layout() -> Array:
	var g: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		g.append(row)
	g[2][2] = 26   # 油桶
	g[2][4] = 27   # 干扰塔
	g[2][6] = 24   # 路灯
	g[4][2] = 13   # 充能站
	g[4][4] = 46   # 压力板
	g[4][6] = 52   # 炸开关
	g[6][2] = 35   # 雷达站
	g[6][4] = 39   # EMP 塔
	g[6][6] = 44   # 可移动木墙
	return g
