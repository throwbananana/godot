class_name RoomDoor
extends Area2D

## 房间的一扇门。开在 13x13 棋盘四条边墙的正中一格 (col/row 6), 位置落在
## 边墙那一圈 48px 的带子里。
##
## 一扇门同时是两样东西, 这是它必须自成一个节点而不是"边墙上少放一块"的原因:
##   - 关着的时候是**碰撞体**, 挡住玩家和敌人 (以撒的门闩: 房间没清空就出不去)
##   - 开着的时候是**触发器**, 玩家碰到就切房
## 两者不能同时生效, 否则玩家会卡在门框里 —— 触发切房的同一帧还被碰撞体推回来。
##
## 没有专门的门美术。三种状态都用现成的地块贴图改色: 关着是压暗的钢板, 开着是
## 一个空洞加一圈框, 秘密门是砖墙 (裂缝靠色调暗示)。加新美术要走 Blender 离线
## 渲染那一整套流程 (见 CLAUDE.md "Regenerating art"), 为一扇门不值当。

const TextureHelper = preload("res://scripts/texture_helper.gd")

enum State { LOCKED, OPEN, SECRET }

## d 是 FloorMap 的方向常量 (0=N 1=E 2=S 3=W)。切房时 main.gd 要靠它知道
## 玩家往哪走, 以及到了新房间该从哪扇门进来。
signal player_entered(direction: int)
## 秘密门的裂缝墙被炸开。main.gd 收到之后写进 GameState 并把门转成 OPEN。
signal secret_breached(direction: int)

const TILE_SIZE := 48.0
const TILE_SCALE := TILE_SIZE / 256.0

## 门开在哪一格。**不是边的中点** —— 中点会和老鹰基地撞上。
##
## 13x13 的棋盘上, 基地那一坨占掉:
##   [12][6]        老鹰本体
##   [12][5] [12][7]        左右两块砖
##   [11][5] [11][6] [11][7]  上面三块砖
## 也就是 col 5-7 x row 11-12 这个 3x2 的实心区域。南边的门如果开在中点
## (col 6), 门廊正好顶在老鹰脸上: 玩家从南门进来会卡在基地里, 从房间里想
## 走南门出去也要先穿过老鹰所在的那一格。
##
## 另外 [12][4] 和 [12][8] 是两个玩家的出生点 (手搓模板硬性要求为空), 所以
## col 4 和 col 8 也不能用。剩下能选的是 0-3 和 9-12, 去掉贴角的 0/12,
## 取 3 —— 在合法范围里离中线最近。
##
## 东西向的门没有这个问题: 基地在第 11-12 行, 而横向门开在第 6 行 (正中),
## 离得远。所以只有纵向门是偏心的, 这份不对称是基地位置逼出来的, 不是随手定的。
##
## 两个常量对**所有房间**统一生效, 所以出门和进门永远对得上 —— 从这间房的
## 南门 (col 3) 出去, 落点就是下一间房的北门 (col 3), 不需要额外对齐逻辑。
const DOOR_COL := 3  # 北/南门所在的列
const DOOR_ROW := 6  # 东/西门所在的行

## 下面这组是给"大房间"(26x26/52x52, 由若干张 13x13 拼成一整间) 用的通用
## 几何公式。DOOR_COL/DOOR_ROW 两个 const 保持原样不动 (13x13 房间和已有的
## 调用点、测试都直接认这两个字面量), 这里只是把同一套推导写成能吃任意
## grid_w/grid_h 的版本, 在 13 上退化成完全相同的数字:
##   center_col_for(13) == 6 == 隐含的中心列
##   door_col_for(13)   == 3 == DOOR_COL
##   door_row_for(13)   == 6 == DOOR_ROW
## 26/52 是偶数, 没有单一居中格, 这里统一取"中心偏左上"的那一格
## ((n-1)/2 整除), 跟房间大小是奇是偶无关地给出一个确定答案。
static func center_col_for(grid_w: int) -> int:
	return (grid_w - 1) / 2


static func center_row_for(grid_h: int) -> int:
	return (grid_h - 1) / 2


## 南北门所在列 —— 复用 DOOR_COL 那条"中心减 3"的避让逻辑 (老鹰基地占中心
## 左右各 1 格, 两个玩家出生点各再占 1 格, 中心-3 是留出这圈之后离中线最近
## 的合法列)。13 宽时等于 6-3=3, 和 DOOR_COL 完全一致。
static func door_col_for(grid_w: int) -> int:
	return center_col_for(grid_w) - 3


## 东西门所在行 —— 基地在底边, 横向门离得远, 直接取中心行即可。
static func door_row_for(grid_h: int) -> int:
	return center_row_for(grid_h)


## 老鹰基地所在行 (房间最底一行)。
static func base_row_for(grid_h: int) -> int:
	return grid_h - 1


## 顶边 count 个敌人出生点的列号, 首尾对齐两侧边缘、中间等距分布。
## count=3, grid_w=13 时返回 [0, 6, 12], 和现在写死的三个出生点完全一致。
static func enemy_spawn_cols_for(grid_w: int, count: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 1:
		out.append(center_col_for(grid_w))
		return out
	for i in range(count):
		out.append(int(round(float(i) * float(grid_w - 1) / float(count - 1))))
	return out

var direction: int = 0
var state: int = State.LOCKED
var room_type: String = "normal"

var _sprite: Sprite2D
var _blocker: StaticBody2D
var _shape: CollisionShape2D


func setup(dir: int, initial_state: int, target_type: String = "normal") -> void:
	direction = dir
	state = initial_state
	room_type = target_type


func _ready() -> void:
	add_to_group("room_doors")

	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(TILE_SCALE, TILE_SCALE)
	# 门根据朝向旋转，使通道发光指引箭头正对房间内部
	match direction:
		0: _sprite.rotation = 0.0
		1: _sprite.rotation = PI * 0.5
		2: _sprite.rotation = PI
		3: _sprite.rotation = -PI * 0.5
	# 画在地块之上、坦克之下。树冠是 z_index 10 (见 main.gd 的
	# _update_tree_transparency), 门比树低才不会盖住"坦克钻进树林"的表现。
	_sprite.z_index = 2
	add_child(_sprite)

	# 触发区。门是 1 格宽, 但触发盒刻意做得**薄**(沿通行方向 20px): 做成整格
	# 的话玩家沿着边墙擦过去就会误触发切房, 而那不是他想做的事。
	_shape = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	if direction == 0 or direction == 2: # N / S -> 水平的门, 薄在竖直方向
		box.size = Vector2(TILE_SIZE * 0.8, 20.0)
	else:
		box.size = Vector2(20.0, TILE_SIZE * 0.8)
	_shape.shape = box
	add_child(_shape)

	_blocker = StaticBody2D.new()
	# 关着的门在物理上就是边墙的一部分: steel + border。border 让它对所有
	# 爆炸物免疫 —— 否则玩家一颗地雷就能把没清空的房间炸出个出口, 门闩形同虚设
	# (见 CLAUDE.md "border must survive everything")。
	_blocker.add_to_group("steel")
	_blocker.add_to_group("border")
	_blocker.add_to_group("room_door_blocker")
	var b_col := CollisionShape2D.new()
	var b_box := RectangleShape2D.new()
	b_box.size = Vector2(TILE_SIZE, TILE_SIZE)
	b_col.shape = b_box
	_blocker.add_child(b_col)
	add_child(_blocker)

	body_entered.connect(_on_body_entered)
	_apply_state()


## 秘密门的裂缝墙是另一个节点: 它必须**能被炸开**, 所以不能挂 border, 而
## 上面那个 _blocker 必须挂 border。同一个物体没法两者兼具, 于是分开做。
var _crack_wall: StaticBody2D = null


func _apply_state() -> void:
	var prefix := "normal"
	match room_type:
		"boss": prefix = "boss"
		"shop": prefix = "shop"
		"treasure", "elite": prefix = "treasure"
		"challenge": prefix = "challenge"
		"event", "rest": prefix = "event"
		"secret": prefix = "secret"
		_: prefix = "normal"

	match state:
		State.OPEN:
			_blocker.process_mode = Node.PROCESS_MODE_DISABLED
			_set_blocker_enabled(false)
			_set_trigger_enabled(true)
			_sprite.texture = TextureHelper.get_tex("res://assets/sprites/buildings/door_%s_open.png" % prefix)
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_clear_crack_wall()
		State.LOCKED:
			_set_blocker_enabled(true)
			_set_trigger_enabled(false)
			var lock_prefix := "normal" if prefix == "secret" else prefix
			_sprite.texture = TextureHelper.get_tex("res://assets/sprites/buildings/door_%s_locked.png" % lock_prefix)
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_clear_crack_wall()
		State.SECRET:
			# 秘密门在被炸开之前为带裂缝的暗门砖墙
			_set_blocker_enabled(false)
			_set_trigger_enabled(false)
			_sprite.texture = TextureHelper.get_tex("res://assets/sprites/buildings/door_secret_cracked.png")
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_ensure_crack_wall()


func _set_blocker_enabled(on: bool) -> void:
	_blocker.collision_layer = 1 if on else 0
	_blocker.collision_mask = 1 if on else 0
	_blocker.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _set_trigger_enabled(on: bool) -> void:
	# set_deferred: 触发区的开关经常发生在 body_entered 回调里 (走进门 -> 切房
	# -> 关掉旧门), 而 Godot 不允许在物理回调期间直接改碰撞状态。
	_shape.set_deferred("disabled", not on)
	monitoring = on


func _ensure_crack_wall() -> void:
	if _crack_wall and is_instance_valid(_crack_wall):
		return
	_crack_wall = StaticBody2D.new()
	# steel 而非 brick: 想要的效果是"普通子弹打不穿, 炸弹和三级穿甲弹能"。
	# 这套判定 bullet.gd 和四种爆炸物已经实现好了 (steel 组 + 非 border),
	# 复用它比在这里再写一遍终端判定可靠 —— 那正是 CLAUDE.md 里
	# "explosives are four more paths and they drifted apart" 说的那种分叉。
	_crack_wall.add_to_group("steel")
	_crack_wall.add_to_group("secret_door_wall")
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(TILE_SIZE, TILE_SIZE)
	col.shape = box
	_crack_wall.add_child(col)
	add_child(_crack_wall)
	# 谁把它打掉的都算数 (子弹 queue_free、爆炸物 queue_free、CRUSHER 撞碎),
	# 所以不去挨个对接那些路径, 只监听"这个节点没了"。
	_crack_wall.tree_exited.connect(_on_crack_wall_gone)


func _clear_crack_wall() -> void:
	if _crack_wall and is_instance_valid(_crack_wall):
		var w := _crack_wall
		_crack_wall = null
		w.tree_exited.disconnect(_on_crack_wall_gone)
		w.queue_free()


func _on_crack_wall_gone() -> void:
	# 房间被 _clear_all() 整体拆掉时这个信号也会响。此时门自己也在被删,
	# 不该当成"玩家炸开了秘密房"上报。
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_crack_wall = null
	secret_breached.emit(direction)


func open() -> void:
	if state == State.OPEN:
		return
	state = State.OPEN
	_apply_state()


func lock() -> void:
	if state == State.LOCKED:
		return
	state = State.LOCKED
	_apply_state()


func _on_body_entered(body: Node2D) -> void:
	if state != State.OPEN:
		return
	# 只有玩家能触发切房。车厢 (train_carriage) 也在 player 组里 —— 让尾巴
	# 触发切房的话, 一条火车会在两个房间之间来回抽搐 (见 CLAUDE.md
	# "player is not the same set as the player tank")。这里要的是车头,
	# 所以用 PlayerTank 类型而不是组名。
	if not (body is PlayerTank):
		return
	player_entered.emit(direction)


## 门在棋盘局部坐标系里的位置 (门本体落在边墙那一圈里)。放在 static 是因为
## main.gd 造边墙时要先知道缺口开在哪, 那时门还没实例化。
static func local_position_for(dir: int, grid_w: int, grid_h: int) -> Vector2:
	var col_x := (door_col_for(grid_w) + 0.5) * TILE_SIZE
	var row_y := (door_row_for(grid_h) + 0.5) * TILE_SIZE
	match dir:
		0: return Vector2(col_x, -TILE_SIZE * 0.5)                      # N
		1: return Vector2(grid_w * TILE_SIZE + TILE_SIZE * 0.5, row_y)  # E
		2: return Vector2(col_x, grid_h * TILE_SIZE + TILE_SIZE * 0.5)  # S
		_: return Vector2(-TILE_SIZE * 0.5, row_y)                      # W


## 从 dir 方向的门走进房间后, 玩家该站在哪 (棋盘局部坐标) —— 门内侧那一格。
## 注意传进来的 dir 是**这个房间的门**的朝向, 不是玩家的行进方向。
static func entry_position_for(dir: int, grid_w: int, grid_h: int) -> Vector2:
	var col_x := (door_col_for(grid_w) + 0.5) * TILE_SIZE
	var row_y := (door_row_for(grid_h) + 0.5) * TILE_SIZE
	match dir:
		0: return Vector2(col_x, 0.5 * TILE_SIZE)
		1: return Vector2((grid_w - 0.5) * TILE_SIZE, row_y)
		2: return Vector2(col_x, (grid_h - 0.5) * TILE_SIZE)
		_: return Vector2(0.5 * TILE_SIZE, row_y)
