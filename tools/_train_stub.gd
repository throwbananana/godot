extends Node2D

## test_train_teleport.gd / test_train_pickup.gd / test_player_power.gd 用的
## 最小替身。
##
## 只暴露 TrainFollowHelper 会碰到的那几个成员 —— 它全程走鸭子类型
## (`"history_positions" in node`), 所以不需要真的实例化 CharacterBody2D、
## 加载贴图、或者把整张 main.tscn 跑起来。

var history_positions: Array[Vector2] = []
var history_rotations: Array[float] = []
var follow_distance: float = 38.0
var leader_node: Node2D = null

## 下面两个是给"车头"用的。TrainFollowHelper.resolve_train_owner() 顺着
## leader_node 往上爬, 直到找到一个 has_method("apply_powerup") 的节点 ——
## 也就是说"车头"的判定条件就是它有这个方法。车厢的伤害计算
## (train_carriage.gd::_carriage_damage) 之后还要读车头的 player_id。
var player_id: int = 1

func apply_powerup(_type) -> void:
	pass
