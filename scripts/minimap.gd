class_name Minimap
extends Control

## HUD 上的楼层小地图。以撒式: 半透明地叠在画面右上角, 而不是单独一个地图界面。
##
## 全部用 _draw() 画几何图形, 不加载任何贴图。原因不是省事 —— 是这个项目的
## 美术全部要走 Blender 离线渲染并把 PNG 提交进仓库 (见 CLAUDE.md
## "Regenerating art"), 而小地图格子只有 14px, 256px 的渲染图缩到这个尺寸
## 只剩一团色块, 却要为此跑一整轮渲染流水线。房型改用**颜色**区分, 在 14px
## 下反而比图标可读。

const GameState = preload("res://scripts/game_state.gd")
const FloorMap = preload("res://scripts/floor_map.gd")

## 每格边长。14px 下 9x9 的网格是 126px, 正好塞进棋盘右上角而不压到中央战场。
const CELL := 14.0
const GAP := 2.0
const ORIGIN := Vector2(528.0, 56.0)

# 房型 -> 中心那个小点的颜色。boss 用红、商店用金、宝物用青 —— 和它们在
# 战斗里的语义一致。普通房不画点 (画了满屏都是点, 反而看不出哪个特殊)。
const TYPE_DOTS := {
	"boss": Color(0.95, 0.30, 0.30),
	"shop": Color(0.98, 0.82, 0.30),
	"treasure": Color(0.40, 0.88, 0.92),
	"challenge": Color(0.78, 0.50, 0.95),
	"event": Color(0.55, 0.90, 0.60),
	"rest": Color(0.55, 0.90, 0.60),
	"secret": Color(0.90, 0.90, 0.95),
}


func _ready() -> void:
	position = ORIGIN
	size = Vector2(FloorMap.GRID_COLS * CELL, FloorMap.GRID_ROWS * CELL)
	# 小地图纯属显示, 不能吃掉鼠标事件 —— 它盖在战场上方。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40


func refresh() -> void:
	queue_redraw()


## 一个房间在小地图上要不要画出来, 以及画成什么样。
##
## 三档 (已探索 / 已知未探索 / 完全未知) 是以撒的信息规则: 走过的房间全画,
## **相邻**于走过的房间的画成暗框 (你知道那边有扇门, 但没进去过), 其余不画。
## 少了中间那一档, 小地图就只能告诉你"来时的路", 对"接下来往哪走"毫无帮助。
func _room_visibility(room_key: String, room: Dictionary) -> int:
	if bool(room.get("secret", false)) and not GameState.secret_room_found:
		return 0 # 秘密房在被炸开之前不能出现在地图上, 否则就不是秘密了
	if bool(room.get("visited", false)):
		return 2
	var c := FloorMap.parse_key(room_key)
	for d in range(4):
		var nk := FloorMap.key(c + FloorMap.DIR_VECTORS[d])
		var n = GameState.floor_rooms.get(nk)
		if n != null and bool(n.get("visited", false)):
			return 1
	return 0


func _draw() -> void:
	if GameState.floor_rooms.is_empty():
		return

	var w := FloorMap.GRID_COLS * CELL
	var h := FloorMap.GRID_ROWS * CELL
	draw_rect(Rect2(Vector2(-4, -4), Vector2(w + 8, h + 8)), Color(0.06, 0.05, 0.08, 0.55), true)

	for room_key in GameState.floor_rooms.keys():
		var room: Dictionary = GameState.floor_rooms[room_key]
		var vis := _room_visibility(str(room_key), room)
		if vis == 0:
			continue

		var c := FloorMap.parse_key(str(room_key))
		var cell_rect := Rect2(
			Vector2(c.x * CELL + GAP * 0.5, c.y * CELL + GAP * 0.5),
			Vector2(CELL - GAP, CELL - GAP))

		if vis == 1:
			# 已知但没进去过: 只画一个暗框。
			draw_rect(cell_rect, Color(0.45, 0.47, 0.55, 0.55), false, 1.0)
			continue

		var is_current := str(room_key) == GameState.current_room
		var fill: Color
		if is_current:
			fill = Color(0.98, 0.94, 0.60, 0.95)
		elif bool(room.get("cleared", false)):
			fill = Color(0.62, 0.68, 0.78, 0.85)
		else:
			# 进去过但没打完 —— 偏红, 提醒这间还欠着一场仗。
			fill = Color(0.80, 0.52, 0.48, 0.85)
		draw_rect(cell_rect, fill, true)

		var dot: Variant = TYPE_DOTS.get(str(room.get("type", "normal")))
		if dot != null:
			draw_circle(cell_rect.get_center(), (CELL - GAP) * 0.24, dot)

		if is_current:
			draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 0.95), false, 1.5)
