extends Node

## test_player_power.gd 用的 current_scene 替身。
##
## train_carriage.gd::_carriage_damage() 通过 get_tree().current_scene 拿
## rpg_mgr —— 这是这个项目里到处都在用的鸭子类型耦合方式 (见 CLAUDE.md 的
## "Cross-node coupling")。测一节车厢的伤害不需要真的把 main.tscn 跑起来,
## 只需要一个身上挂着 rpg_mgr 的节点。

var rpg_mgr = null
