class_name KineticPushHelper
extends RefCounted

## 统一动能推力与墙体挤压结算系统 (Kinetic Push & Squeeze Elimination Helper)
## 
## 核心规则：
## 1. 炮弹或单位推动方块/建筑的类型，严格取决于炮弹的破坏等级（与破坏等级相同）：
##    - 普通动能弹 (can_destroy_steel == false): 可推木墙、滑轮墙、砖块、硬泥块、油桶、路灯等非钢体建筑。
##    - 破钢动能弹 (can_destroy_steel == true):  额外可推重型钢墙、强化墙、电墙、掩体堡垒、炮塔等钢质建筑。
##    - 地图外围边框 (border): 绝对不可推移。
## 2. 挤压消灭机制 (Squeeze Elimination):
##    - 当被推移的方块/建筑朝目标格推进时，若目标格存在单位（敌军、玩家或老鹰）：
##    - 检查该单位正后方（推移方向下一格）。若后方为死角（实心墙体、钢墙、建筑、地图边界）：
##      两面夹击触发【挤压粉碎处决 (Squeeze Kill)】！对敌人造成 999 毁灭性伤害并碎裂消散，
##      对玩家造成 3 点高额碾压伤害并僵直，伴随强烈陶泥碎片特效与屏幕震颤！
##    - 若后方为空旷地面，则单位被强行向后击退一格，承受轻度撞击伤害与眩晕。

const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

## 判断目标是否允许被推移（受破坏等级制约）
static func can_push(target: Node, can_destroy_steel: bool = false) -> bool:
	if not is_instance_valid(target) or not (target is Node2D):
		return false
	if not target.is_inside_tree():
		return false

	# 地图边框永不可推移
	if target.is_in_group("border"):
		return false

	# 已经在移动中
	if "is_moving" in target and target.is_moving:
		return false

	# 钢制障碍与重型钢质建筑：严格取决于破坏等级是否可破钢
	if target.is_in_group("steel"):
		return can_destroy_steel

	# 砖块、硬泥、木墙、滑轮墙、普通建筑与路障道具：普通动能弹即可推移
	if target.is_in_group("brick") or target.is_in_group("hard_clay") or \
	   target.is_in_group("roller_wall") or target.is_in_group("wooden_wall") or \
	   target.is_in_group("buildings") or target.is_in_group("building") or \
	   target.is_in_group("oil_barrel") or target.is_in_group("street_lamp") or \
	   target.is_in_group("pipe_conduit"):
		return true

	return false

## 执行推移与挤压结算
static func try_push(target_node: Node2D, push_dir: Vector2, can_destroy_steel: bool = false, pusher: Node = null, step: float = 48.0) -> bool:
	if not can_push(target_node, can_destroy_steel):
		_shake_blocked(target_node)
		return false

	# 1. 贴合至主要正交轴向 (Cardinal Direction)
	var cardinal := Vector2.ZERO
	if absf(push_dir.x) > absf(push_dir.y):
		cardinal = Vector2.RIGHT if push_dir.x > 0.0 else Vector2.LEFT
	else:
		cardinal = Vector2.DOWN if push_dir.y > 0.0 else Vector2.UP

	var target_pos := target_node.global_position + cardinal * step
	var behind_pos := target_pos + cardinal * step

	# 2. 地图战区边界检查
	var main = target_node.get_tree().current_scene if target_node.is_inside_tree() else null
	var min_b := 24.0
	var max_b := 13.0 * 48.0 - 24.0
	if main and "game_area" in main and main.game_area:
		var local_target: Vector2 = main.game_area.to_local(target_pos)
		if local_target.x < min_b - 6.0 or local_target.x > max_b + 6.0 or \
		   local_target.y < min_b - 6.0 or local_target.y > max_b + 6.0:
			_shake_blocked(target_node)
			return false

	# 3. 检测目标格物理实体
	var space_state := target_node.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var box_shape := RectangleShape2D.new()
	box_shape.size = Vector2(36.0, 36.0)
	query.shape = box_shape
	query.transform = Transform2D(0.0, target_pos)
	query.collision_mask = 1 | 2 | 16 # Walls, terrain, border, buildings, enemies, players
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var excludes: Array[RID] = [target_node.get_rid()]
	if pusher and is_instance_valid(pusher) and pusher is CollisionObject2D:
		excludes.append(pusher.get_rid())
	query.exclude = excludes

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 8)
	var blocked_by_solid := false
	var parent_node := target_node.get_parent() if target_node.get_parent() else target_node

	for hit in hits:
		var collider: Object = hit.get("collider")
		if not is_instance_valid(collider) or collider == target_node:
			continue

		# A. 单位检测（敌人、玩家、车厢、基地老鹰）
		var is_enemy = collider.is_in_group("enemy") or collider.is_in_group("enemies")
		var is_player = collider.is_in_group("player") or collider.is_in_group("p1") or collider.is_in_group("p2") or collider.is_in_group("player_carriage")
		var is_eagle = collider.is_in_group("base") or collider.is_in_group("base_eagle")

		if is_enemy or is_player or is_eagle:
			# 检查该单位正后方是否存在实心死角（两面受力挤压判定）
			var is_pinned := _is_position_blocked_solid(target_node, behind_pos, collider, main, min_b, max_b)

			if is_pinned:
				# ========= 💥 核心：挤压粉碎消灭 (SQUEEZE KILL) =========
				_trigger_squeeze_kill(collider, target_node, main, is_enemy, is_player, is_eagle, pusher)
			elif not is_eagle:
				# 后方空旷：强行击退单位并造成震荡（基地老鹰固定于阵地，不受推击击退）
				_trigger_knockback_unit(collider, behind_pos, parent_node)

		# B. 可撞碎的脆弱地形（砖块、硬泥、陷阱等）
		elif collider.is_in_group("brick") or collider.is_in_group("hard_clay") or collider.is_in_group("destructible") or collider.is_in_group("hazard"):
			if collider.has_method("take_hit"):
				collider.take_hit(99)
			elif collider.has_method("take_damage"):
				collider.take_damage(99)
			else:
				VFXAnimator.spawn_dust_puff(parent_node, collider.global_position)
				VFXAnimator.spawn_clay_debris(parent_node, collider.global_position)
				collider.queue_free()

		# C. 坚硬实心障碍物
		elif collider.is_in_group("border") or collider.is_in_group("steel") or collider.is_in_group("buildings") or collider.is_in_group("base"):
			blocked_by_solid = true

	if blocked_by_solid:
		_shake_blocked(target_node)
		return false

	# 4. 执行平滑推移位移动画
	_perform_push_animation(target_node, target_pos, cardinal, parent_node)
	return true

## 检测坐标点是否被不可穿透的硬物/边界阻挡（夹击死角判定）
static func _is_position_blocked_solid(context_node: Node2D, pos: Vector2, ignore_collider: Object, main: Node, min_b: float, max_b: float) -> bool:
	# 1. 边界死角检查
	if main and "game_area" in main and main.game_area:
		var local_pos: Vector2 = main.game_area.to_local(pos)
		if local_pos.x < min_b - 4.0 or local_pos.x > max_b + 4.0 or \
		   local_pos.y < min_b - 4.0 or local_pos.y > max_b + 4.0:
			return true

	# 2. 物理空间障碍物探测
	var space_state := context_node.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var test_shape := RectangleShape2D.new()
	test_shape.size = Vector2(32.0, 32.0)
	query.shape = test_shape
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1 | 2 | 16
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var excludes: Array[RID] = [context_node.get_rid()]
	if ignore_collider and ignore_collider is CollisionObject2D:
		excludes.append(ignore_collider.get_rid())
	query.exclude = excludes

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 6)
	for hit in hits:
		var col: Object = hit.get("collider")
		if not is_instance_valid(col) or col == context_node or col == ignore_collider:
			continue
		if col.is_in_group("border") or col.is_in_group("steel") or col.is_in_group("brick") or \
		   col.is_in_group("hard_clay") or col.is_in_group("buildings") or col.is_in_group("building") or \
		   col.is_in_group("base"):
			return true

	return false

## 触发挤压粉碎处决 (Squeeze Kill Execution)
static func _trigger_squeeze_kill(victim: Object, target_node: Node2D, main: Node, is_enemy: bool, is_player: bool, is_eagle: bool, pusher: Node = null) -> void:
	var tree = target_node.get_tree()
	var parent_node = target_node.get_parent() if target_node.get_parent() else target_node
	var v_pos: Vector2 = victim.global_position if "global_position" in victim else target_node.global_position

	# 重型撞击音效与震荡波
	SoundManager.play_hit_steel(tree)
	SoundManager.play_hit_brick(tree)
	VFXAnimator.spawn_shockwave(parent_node, v_pos)
	VFXAnimator.spawn_clay_debris(parent_node, v_pos)

	if is_enemy:
		# 敌方单位：999点毁灭伤害或直接处决消灭
		if main and main.has_method("add_trauma"):
			main.add_trauma(0.35)
		if main and main.has_method("show_toast"):
			main.show_toast("💥 墙壁挤压处决！敌方单位被夹击碾碎！")
		if victim.has_method("take_damage"):
			victim.take_damage(999)
		elif victim.has_method("destroy"):
			victim.destroy()
		else:
			victim.queue_free()

	elif is_player:
		# 玩家单位：承受高额碾压伤害与强力僵直
		if main and main.has_method("add_trauma"):
			main.add_trauma(0.50)
		if main and main.has_method("show_toast"):
			main.show_toast("⚠️ 遭遇致命墙体挤压！承受重度碾压伤害！")
		if victim.has_method("take_damage"):
			victim.take_damage(3)
		if victim.has_method("stun"):
			victim.stun(2.0)

	elif is_eagle:
		var iff_active: bool = (victim.get("is_iff_active") == true) or (main and main.has_method("is_iff_flag_active") and main.is_iff_flag_active()) or ("has_iff_flag" in GameState and GameState.has_iff_flag)
		var is_pusher_player: bool = (pusher != null and (pusher.is_in_group("player") or ("shooter_type" in pusher and pusher.shooter_type == "player")))
		if is_pusher_player and iff_active:
			if main and main.has_method("show_toast"):
				main.show_toast("🚩 友军标识旗生效：基地免受友军推挤挤压！")
			return
		# 基地老鹰被两面挤压：毁灭
		if victim.has_method("destroy"):
			victim.destroy()
		elif victim.has_method("take_damage_hit"):
			victim.take_damage_hit()

## 击退单位
static func _trigger_knockback_unit(victim: Object, new_pos: Vector2, parent_node: Node) -> void:
	if "global_position" in victim:
		var tween = victim.create_tween() if victim is Node else null
		if tween:
			tween.tween_property(victim, "global_position", new_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			victim.global_position = new_pos
	if victim.has_method("take_damage"):
		victim.take_damage(2)
	if victim.has_method("freeze"):
		victim.freeze(0.8)
	elif victim.has_method("stun"):
		victim.stun(0.8)
	VFXAnimator.spawn_dust_puff(parent_node, new_pos)

## 平滑推移动画
static func _perform_push_animation(target_node: Node2D, target_pos: Vector2, _dir: Vector2, parent_node: Node) -> void:
	target_node.set("is_moving", true)
	VFXAnimator.spawn_dust_puff(parent_node, target_node.global_position)
	SoundManager.play_hit_steel(target_node.get_tree())

	var tween := target_node.create_tween()
	tween.tween_property(target_node, "global_position", target_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if is_instance_valid(target_node):
			target_node.set("is_moving", false)
			VFXAnimator.spawn_dust_puff(parent_node, target_node.global_position)
			if target_node.has_method("_update_visual_state"):
				target_node._update_visual_state()
	)

## 受阻震颤
static func _shake_blocked(node: Node2D) -> void:
	SoundManager.play_hit_steel(node.get_tree())
	var spr = node.get_node_or_null("Sprite2D")
	if not spr and "sprite" in node and is_instance_valid(node.sprite):
		spr = node.sprite
	if spr:
		var tween := node.create_tween()
		var orig_scale: Vector2 = spr.scale
		tween.tween_property(spr, "scale", orig_scale * 1.15, 0.05)
		tween.tween_property(spr, "scale", orig_scale, 0.05)
