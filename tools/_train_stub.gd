extends Node2D

## test_train_teleport.gd 用的最小替身。
##
## 只暴露 TrainFollowHelper 会碰到的那几个成员 —— 它全程走鸭子类型
## (`"history_positions" in node`), 所以不需要真的实例化 CharacterBody2D、
## 加载贴图、或者把整张 main.tscn 跑起来。

var history_positions: Array[Vector2] = []
var history_rotations: Array[float] = []
var follow_distance: float = 38.0
var leader_node: Node2D = null
