extends Node2D

## BuildingSkin 的测试替身 —— 只暴露那个组件真正读的几样东西。
##
## 和 tools/_train_stub.gd 是同一个套路 (见 CLAUDE.md 里 test_train_teleport
## 那段): BuildingSkin 全程鸭子类型 (读 `sprite` / `max_health` /
## `current_health`), 所以不需要为了测它去实例化某个真建筑的场景 —— 那会连带
## 拉进 rpg_mgr、爆炸场景、音效, 而这些和"贴花档位跟不跟血量走"毫无关系,
## 只会让测试更容易因为不相干的原因红掉。
##
## region_enabled 是**故意**打开的: fortified_wall 是 2x2 个用 region_rect
## 切象限的 Piece, 贴花不抄这个 region 的话四个象限会各贴一整张完整贴花。
## 替身默认就带 region, 保证那条断言一直被真的执行到。

var max_health: int = 6
var current_health: int = 6
var sprite: Sprite2D


func _init() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 128, 128)
	add_child(sprite)
