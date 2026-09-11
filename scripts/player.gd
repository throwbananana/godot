class_name PlayerTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const PowerUp = preload("res://scripts/power_up.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")
const TrainLink = preload("res://scripts/train_link.gd")
const LaserPiercer = preload("res://scripts/laser_piercer.gd")
const LaserRingCutter = preload("res://scripts/laser_ring_cutter.gd")
const NetSession = preload("res://scripts/net_session.gd")
const NetPuppet = preload("res://scripts/net_puppet.gd")

signal destroyed(pid: int)
signal fired_bullet
signal powerup_collected(type_name: String)
signal health_changed(pid: int, curr: int, max_hp: int)

@export var player_id: int = 1 # 1=P1 (Yellow/Gold), 2=P2 (Green/Mint)
@export var base_speed: float = 125.0
@export var fire_cooldown: float = 0.65

var upgrade_tier: int = 0
var max_health: int = 1
var current_health: int = 1
var is_dying: bool = false
var can_fire: bool = true
var history_positions: Array[Vector2] = []
var history_rotations: Array[float] = []
var fire_timer: float = 0.0
var facing_direction: Vector2 = Vector2.UP
var is_invulnerable: bool = false
var invulnerable_timer: float = 0.0
var regen_accumulator: float = 0.0

## 受击之后多久内不回血。
##
## 纳米自愈原来是无条件每秒结算的, 于是它不是"回血", 而是一层看不见的额外
## 血量: 24 级时 1.5 HP/秒, 一场 45 秒的战斗能回 67.5 血, 而最大血才 9 ——
## 有效血量 76, 等于一场能挨 76 发。换算成敌人视角: 同屏 4 辆车、平均 2.2 秒
## 一发、1 点伤害, 理论最大输出 1.82 伤/秒, 也就是**敌人要有 83% 的命中率才
## 压得过回复**。坦克大战里玩家一直在动、地形还挡弹, 真实命中率远低于这个数,
## 所以后半幕的常规子弹根本打不死人, 只有自爆卡车和轰炸机那种爆发伤害才致命。
##
## 而且它是个隐藏数值 —— 回复速率不在任何 UI 上, 玩家只会觉得"我好像不太会死"。
##
## 加锁之后回复从"被动数值"变成"脱离交火才拿得到的奖励": 想回血就得退出去,
## 而退出去意味着让出场面。这才是坦克大战该有的取舍, 而不是站桩对射。
## 3 秒是量出来的 —— 见 tools/probe_player_power.gd 里按命中率折算的有效血量表。
##
## 硬核化调整: 3.0 -> 4.0。上次测的最难档 (30 级) 只需要 25% 命中率就能压过
## 回复, 而门禁上限留到 45% —— 中间那段余量意味着回复比"能被打穿"这条底线
## 还宽松不少。锁定拉长到 4 秒直接压缩这个余量, 不改变"打完就走能回血"的
## 基本设计, 只是让脱离交火这件事更值钱。
const REGEN_COMBAT_LOCKOUT := 4.0
var regen_lockout: float = 0.0
var is_on_sand: bool = false
var sand_overlap_count: int = 0
var is_on_ice: bool = false
var ice_overlap_count: int = 0
var is_on_water: bool = false
var water_overlap_count: int = 0
var amphibious_hull_applied: bool = false # avoids re-adding the same collision exceptions every _apply_rpg_stats() call
var is_jammed: bool = false
var jam_overlap_count: int = 0
var is_on_platform: bool = false
var slide_direction: Vector2 = Vector2.ZERO
var ice_particle_timer: float = 0.0
var is_stunned: bool = false
var stun_timer: float = 0.0

# Counter Tank Parry & Riposte Mechanics
var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_total_duration: float = 0.34
var parry_perfect_window: float = 0.14
var has_charged_counter_shot: bool = false
var parry_shield_sprite: Sprite2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var shield_sprite: Sprite2D = $ShieldSprite

var tank_frames: Array[Texture2D] = []
var current_frame: int = 0

## 履带动画按实际位移量驱动, 不是按挂钟时间。以前是 int(Time.get_ticks_msec()
## / 60) % 帧数 —— 只要 velocity 非零就以固定 16.67 帧/秒空转, 陷进流沙 (速度
## -50%) 履带照样疯转, 吃氮气/滑冰加速 (速度 +30%+) 履带反而显得转慢了,
## 呈现"太空步"般的廉价感, 和黏土重型坦克该有的机械厚重感相反。
## TREAD_PX_PER_FRAME 按 base_speed=125 px/s 换算到 60ms/帧的原始手感反推 ——
## 数值只是风格常数, 不需要精确, 只要"走多远关联换几帧"这个物理关系成立。
const TREAD_PX_PER_FRAME: float = 8.0
var tread_accum_dist: float = 0.0

var shield_textures: Array[Texture2D] = []
var shield_frame: int = 0

var bullet_scene: PackedScene
var explosion_scene: PackedScene
var carriage_scene: PackedScene
var attached_carriages: Array[Node2D] = []
var train_respawn_timer: float = 0.0
## 车厢阵亡后多久补回来。TrainCarriage.destroyed 信号原来完全没人接 ——
## 车厢一旦在战斗中被打掉, 剩下这一整局都不会再补, tier2 打到只剩机车裸奔
## 也是正常状态。设一个有感知的等待 (不是即时白给), 让车厢确实是"可以再战
## 一场"的资源而不是一次性的。
const TRAIN_CARRIAGE_RESPAWN_TIME := 12.0

## 主机这一帧算出来的有效移动速度, 随快照下发给客户端做本地预测的速度源
## (见 _net_predict_step)。单机时没人读它。
var net_effective_speed: float = 0.0

var base_color: Color = Color(1.0, 1.0, 1.0)
var hit_tween: Tween
var recoil_tween: Tween

func _ready() -> void:
	add_to_group("player")
	if player_id == 1:
		add_to_group("p1")
		base_color = Color(1.0, 1.0, 1.0)
	else:
		add_to_group("p2")
		base_color = Color(1.0, 1.0, 1.0)

	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	carriage_scene = load("res://scenes/train_carriage.tscn")
	
	for i in range(8):
		var s_tex = TextureHelper.get_tex("res://assets/sprites/effects/shield_bubble_%d.png" % i)
		if s_tex:
			shield_textures.append(s_tex)
	if shield_sprite:
		shield_sprite.scale = Vector2(0.24, 0.24)
		if shield_textures.size() > 0:
			shield_sprite.texture = shield_textures[0]

	# Dedicated energy buckler for counter branch parry
	parry_shield_sprite = Sprite2D.new()
	if shield_textures.size() > 0:
		parry_shield_sprite.texture = shield_textures[0]
	parry_shield_sprite.scale = Vector2(0.28, 0.28)
	parry_shield_sprite.visible = false
	parry_shield_sprite.z_index = 5
	add_child(parry_shield_sprite)

	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		main.rpg_mgr.branch_changed.connect(_on_branch_changed)

	_apply_rpg_stats()
	_update_tier_appearance()
	# 硬核化调整: 开局无敌 3.5 -> 2.5 秒。这只在战车第一次实例化时跑一次
	# (房间切换靠 _clear_all(keep_players=true) 保留玩家节点, 不会重新触发
	# _ready()), 所以缩短它影响的是"这一局怎么起手", 不会让每次开门都变得
	# 更危险。
	set_invulnerable(2.5)

func _on_branch_changed(changed_player_id: int, _branch: String, _tier: int) -> void:
	if changed_player_id != player_id:
		return
	_apply_rpg_stats()
	_update_tier_appearance()

func _apply_rpg_stats() -> void:
	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		var prev_max = max_health
		max_health = main.rpg_mgr.get_player_max_hp(player_id)
		if current_health > max_health or max_health > prev_max:
			current_health = max_health
		health_changed.emit(player_id, current_health, max_health)

		# Amphibious Hull: let this tank physically enter water tiles. Exceptions
		# are additive and idempotent (Godot no-ops re-adding the same pair), so
		# it's safe to call this every _apply_rpg_stats() -- only actually does
		# anything the first time since the perk can't be un-bought this run.
		if not amphibious_hull_applied and main.rpg_mgr.has_perk("amphibious_hull", player_id) and "water_bodies" in main:
			for water_body in main.water_bodies:
				if is_instance_valid(water_body):
					add_collision_exception_with(water_body)
			amphibious_hull_applied = true

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(player_id, current_health, max_health)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 2.2, 0.6), 0.1)
	tween.tween_property(sprite, "modulate", base_color, 0.1)

func _update_tier_appearance() -> void:
	var main = get_tree().current_scene if (is_inside_tree() and get_tree()) else null
	var branch = "default"
	var b_tier = 0
	if main and main.rpg_mgr:
		branch = main.rpg_mgr.get_branch(player_id)
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		branch = GameState.tank_branch
		b_tier = GameState.branch_tier
	else:
		branch = GameState.p2_branch
		b_tier = GameState.p2_branch_tier

	var prefix = ""
	var p_prefix = "player" if player_id == 1 else "player2"

	if branch == "speed":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_speed_%s" % [p_prefix, t_str]
	elif branch == "heavy":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_heavy_%s" % [p_prefix, t_str]
	elif branch == "train":
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_train_loco_%s" % [p_prefix, t_str]
		_sync_train_carriages(b_tier)
	elif branch == "counter":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_counter_%s" % [p_prefix, t_str]
	elif branch == "trench":
		_clear_train_carriages()
		var t_str = "t1" if b_tier <= 1 else "t2"
		prefix = "%s_trench_%s" % [p_prefix, t_str]
	else:
		_clear_train_carriages()
		prefix = "%s_tier%d" % [p_prefix, upgrade_tier]

	tank_frames.clear()
	for i in range(6):
		var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
		if tex:
			tank_frames.append(tex)
	if tank_frames.size() > 0 and sprite:
		sprite.texture = tank_frames[0]
		sprite.modulate = base_color

func _sync_train_carriages(b_tier: int) -> void:
	if not carriage_scene or not is_inside_tree():
		return

	# Remove dead carriages
	var valid_carriages: Array[Node2D] = []
	for c in attached_carriages:
		if is_instance_valid(c):
			valid_carriages.append(c)
	attached_carriages = valid_carriages

	# 按类型判断缺哪节, 不是按数量。原来只看 size()==0 / size()==1, 在
	# "炮塔活着、火箭被打掉"这种情况下会算错: 剩下的那节车厢是炮塔, 但
	# size()==1 的分支会把它当成"还没长出来的炮塔", 拿它去当火箭的 leader
	# setup 出第二节火箭, 变成两节火箭、没有炮塔。
	var turret_carriage: Node2D = null
	var has_rocket := false
	for c in attached_carriages:
		if "carriage_type" in c:
			if c.carriage_type == "turret":
				turret_carriage = c
			elif c.carriage_type == "rocket":
				has_rocket = true

	# First carriage: Turret Wagon
	if turret_carriage == null:
		turret_carriage = carriage_scene.instantiate()
		get_parent().add_child(turret_carriage)
		turret_carriage.setup(self, "turret", false)
		turret_carriage.destroyed.connect(_on_carriage_destroyed)
		attached_carriages.append(turret_carriage)

	# Second carriage (Tier 2): Rocket Artillery Wagon
	if b_tier >= 2 and not has_rocket:
		var c2 = carriage_scene.instantiate()
		get_parent().add_child(c2)
		c2.setup(turret_carriage, "rocket", false)
		c2.destroyed.connect(_on_carriage_destroyed)
		attached_carriages.append(c2)

func _clear_train_carriages() -> void:
	for c in attached_carriages:
		if is_instance_valid(c):
			c.queue_free()
	attached_carriages.clear()
	train_respawn_timer = 0.0

## TrainCarriage.destroyed 信号的唯一接线端。之前这个信号发出去了但没人接,
## 车厢被打掉之后 attached_carriages 里那个失效引用要等下一次
## _sync_train_carriages() (选分支/升 tier/重新 _ready()) 才会被清掉, 而
## tier2 之后这三个触发点在一局内都不会再发生 —— 所以车厢就是打没了。
func _on_carriage_destroyed(c: Node2D) -> void:
	attached_carriages.erase(c)
	if is_dying:
		return # 机车自己也在死, _die() 会自己处理, 不需要再排一次重生
	train_respawn_timer = TRAIN_CARRIAGE_RESPAWN_TIME

## 由 _physics_process() 每帧调用。拆成独立函数方便测试直接快进
## (train_respawn_timer 12 秒, 不该也不需要在测试里真等 12 秒)。
func _process_train_respawn(delta: float) -> void:
	if train_respawn_timer <= 0.0:
		return
	train_respawn_timer -= delta
	if train_respawn_timer <= 0.0:
		train_respawn_timer = 0.0
		_update_tier_appearance()

const POWERUP_ENCYCLOPEDIA_IDS := {
	PowerUp.Type.STAR: "item_star",
	PowerUp.Type.BOMB: "item_bomb",
	PowerUp.Type.CLOCK: "item_clock",
	PowerUp.Type.HELMET: "item_helmet",
	PowerUp.Type.SHOVEL: "item_shovel",
	PowerUp.Type.LIFE: "item_life",
	PowerUp.Type.MISSILE: "item_missile",
	PowerUp.Type.TIMED_BOMB: "item_timed_bomb",
	PowerUp.Type.PISTON: "item_piston",
	PowerUp.Type.IFF_FLAG: "item_iff_flag",
}

func apply_powerup(type: PowerUp.Type) -> void:
	if POWERUP_ENCYCLOPEDIA_IDS.has(type):
		GameState.discover_encyclopedia_entry(POWERUP_ENCYCLOPEDIA_IDS[type])
	var main = get_tree().current_scene
	var p_name = "P1" if player_id == 1 else "P2"
	match type:
		PowerUp.Type.STAR:
			# upgrade_tier only does anything in the "default" branch weapon
			# path (_shoot()'s default match arm) -- once a branch is picked
			# (which happens at the player's very first level-up, no skip
			# option), bumping it further is a silent no-op. Redirect to a
			# live +1 ATK on the same RPGManager instance the battle already
			# reads from, mirroring GameState.grant_star_tier_reward's logic
			# for the shop/event entry points that touch GameState directly
			# instead (no live RPGManager exists on the spire map).
			var branch = main.rpg_mgr.get_branch(player_id) if (main and main.rpg_mgr) else "default"
			if branch == "default":
				upgrade_tier = mini(upgrade_tier + 1, 3)
				_update_tier_appearance()
				VFXAnimator.spawn_shockwave(get_parent(), global_position)
				var rank_name = ["BASIC", "SCOUT+", "TWIN-CANNON", "PLASMA DREADNOUGHT"][upgrade_tier]
				powerup_collected.emit("[%s] STAR UPGRADE: %s!" % [p_name, rank_name])
			else:
				if main and main.rpg_mgr:
					main.rpg_mgr.atk_bonus += 1
					main.rpg_mgr.sync_to_game_state()
					main.rpg_mgr.stats_changed.emit()
				VFXAnimator.spawn_shockwave(get_parent(), global_position)
				powerup_collected.emit("[%s] STAR UPGRADE: +1 永久攻击力!" % p_name)
			# 战车等级只有这一个入口: 没有经验条, 击杀/拾取/事件/商店都不再暗中
			# 攒经验, 吃到几颗星就升几级 (RPGManager.add_level, 1 颗 = 1 级)。
			# 这一份是队伍共享的 (rpg_mgr.level 本来就不分玩家), 谁捡到都一样。
			if main and main.rpg_mgr:
				main.rpg_mgr.add_level(1)
		PowerUp.Type.HELMET:
			# 硬核化调整: 10.0 -> 7.0 秒。头盔本来就是稀有度和 STAR/BOMB 同级的
			# 道具, 10 秒无敌在敌人 2.2 秒一发的节奏下相当于白吃 4-5 发, 分量
			# 偏重; 收到 7 秒仍然是一段扎实的免伤窗口, 只是不再接近"这段时间
			# 里房间基本清空了"。
			set_invulnerable(7.0)
			powerup_collected.emit("[%s] HELMET SHIELD (7s)" % p_name)
		PowerUp.Type.BOMB:
			if main and main.has_method("trigger_bomb"):
				main.trigger_bomb()
			powerup_collected.emit("[%s] SCREEN BOMB TRIGGERED!" % p_name)
		PowerUp.Type.CLOCK:
			if main and main.has_method("trigger_freeze"):
				main.trigger_freeze(7.5)
			powerup_collected.emit("[%s] TIME FROZEN (7.5s)" % p_name)
		PowerUp.Type.SHOVEL:
			if main and main.has_method("trigger_shovel"):
				main.trigger_shovel(15.0)
			powerup_collected.emit("[%s] STEEL BASE FORTIFIED!" % p_name)
		PowerUp.Type.LIFE:
			if main and main.has_method("add_life"):
				main.add_life(1)
			powerup_collected.emit("[%s] +1 EXTRA LIFE!" % p_name)
		PowerUp.Type.MISSILE:
			var strike_scene = load("res://scenes/missile_strike.tscn")
			if strike_scene:
				var enemies = get_tree().get_nodes_in_group("enemies")
				var targets: Array[Vector2] = []
				for e in enemies:
					if is_instance_valid(e) and e is Node2D:
						targets.append(e.global_position)
				if targets.size() == 0:
					targets.append(global_position + facing_direction * 180.0)

				# Call 3 tactical missile strikes on enemy clusters
				for i in range(mini(3, max(1, targets.size()))):
					var strike = strike_scene.instantiate()
					strike.team = "player"
					strike.aim_duration = 1.4
					strike.damage = 5
					get_parent().add_child(strike)
					strike.global_position = targets[i % targets.size()] + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
			powerup_collected.emit("[%s] 🚀 战术导弹群空袭支援！" % p_name)
		PowerUp.Type.TIMED_BOMB:
			var bomb_scene = load("res://scenes/timed_bomb.tscn")
			if bomb_scene:
				# Deploys 2 linked bombs ahead in facing direction
				for offset in [32.0, 72.0]:
					var bomb = bomb_scene.instantiate()
					bomb.team = "player"
					bomb.countdown = 2.0
					bomb.blast_range = 4 # Extended 4-tile blast for powerup!
					bomb.damage = 5
					# add_child 是 deferred 的; 这里原来先赋 global_position 再
					# deferred add_child, 节点入树前赋值等同赋 position, 真正
					# 入树后再叠一次父级偏移, 炸弹落点比玩家前方目标点多偏右下
					# 一格。上面 MISSILE 分支是先 add_child 再赋 global_position
					# (顺序对), 只有这个分支反了。用 to_local() 提前换算, 不受
					# 入树时机影响。
					bomb.position = get_parent().to_local(global_position + facing_direction * offset)
					get_parent().call_deferred("add_child", bomb)
			SoundManager.play_build(get_tree())
			powerup_collected.emit("[%s] 💣 强化十字连环定时炸弹！" % p_name)
		PowerUp.Type.PISTON:
			if main and main.rpg_mgr:
				main.rpg_mgr.add_perk("kinetic_piston_rounds", player_id)
			VFXAnimator.spawn_shockwave(get_parent(), global_position)
			powerup_collected.emit("[%s] 🚜 活塞冲压弹就绪！主炮获得推墙与挤压处决能力！" % p_name)
		PowerUp.Type.IFF_FLAG:
			if main and main.has_method("trigger_iff_flag"):
				main.trigger_iff_flag(40.0)
			VFXAnimator.spawn_shockwave(get_parent(), global_position)
			powerup_collected.emit("[%s] 🚩 友军标识旗已部署！我方火力绝对豁免基地伤害！" % p_name)

func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	invulnerable_timer = duration
	if shield_sprite:
		shield_sprite.visible = true

func stun(duration: float = 2.5) -> void:
	if is_invulnerable:
		return
	is_stunned = true
	stun_timer = duration
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

## 傀儡坦克每帧做的全部事情: 跟着快照走 (或者本地预测), 外加履带动画。
##
## 履带帧特意保留 —— 它由**实际位移量**驱动 (见 TREAD_PX_PER_FRAME 的注释),
## 而傀儡的位移量就是主机的位移量, 所以客户端看到的履带节奏和主机完全一致,
## 不需要额外同步一个动画帧号。预测的那辆同理: 位移是本地算的, 履带自然跟上。
## 被拖着走的那一帧 —— 双人合体的后车 (train_link.gd)。
##
## 位置/车身来自机车整列车最后一节的尾迹, 转向来自自己的方向键。
##
## **不调 move_and_slide()。** 和 train_carriage.gd 一样直接写 global_position:
## 跟随是"重放一条已经走过的路径", 让物理再解一次碰撞只会把后车挤到路径之外,
## 下一帧又被拽回来。代价是后车挂载期间不参与碰撞解算 —— 这正是现有 AI 车厢
## 的行为, 两者保持一致。
##
## 拿不到尾迹 (机车刚生成, 历史还是空的) 就原地不动, 而不是跳到机车身上。
func _towed_step(delta: float, input_vec: Vector2) -> void:
	var main = get_tree().current_scene
	var leader: Node = null
	if main:
		leader = main.p1_instance if TrainLink.leader_id == 1 else main.p2_instance

	var before := global_position
	var target := TrainLink.follower_target(leader)
	if not target.is_empty():
		global_position = target["position"]

	# 车身朝自己瞄的方向。没按方向键时保持上一帧的朝向 —— 归零会让后车在
	# 松手的瞬间弹回默认朝向。
	if input_vec != Vector2.ZERO:
		facing_direction = input_vec
	rotation = facing_direction.angle() + PI / 2.0

	velocity = Vector2.ZERO
	# 上报 0: 这个值是随快照下发给客户端做移动预测的速度源。挂载期间客户端那边
	# 由 F_TOWED 关掉了预测, 所以它其实没人读 —— 但留一个上一帧的陈旧速度在
	# 那里, 是在等下一个读它的人踩坑。
	net_effective_speed = 0.0
	TrainFollowHelper.record_history(history_positions, history_rotations, global_position, rotation)

	if tank_frames.size() > 0:
		tread_accum_dist += before.distance_to(global_position)
		var f_idx := int(tread_accum_dist / TREAD_PX_PER_FRAME) % tank_frames.size()
		if f_idx != current_frame:
			current_frame = f_idx
			sprite.texture = tank_frames[current_frame]


func _net_puppet_step(delta: float) -> void:
	var before := position
	if NetPuppet.is_predicted(self):
		_net_predict_step(delta)
	else:
		NetPuppet.update(self, delta)
	if tank_frames.size() > 0:
		tread_accum_dist += position.distance_to(before)
		var f_idx := int(tread_accum_dist / TREAD_PX_PER_FRAME) % tank_frames.size()
		if f_idx != current_frame:
			current_frame = f_idx
			sprite.texture = tank_frames[current_frame]


## 客户端**自己那辆**坦克: 按本地输入立刻走, 再往主机给的权威位置回拉。
##
## 这里刻意只做移动, 不做开火 —— 见 NetSession 里 prediction_enabled 那段。
##
## 速度取自主机 (`net_speed`, 快照的 extra 字段), 不是本地重算的。这一点是
## 整个预测能成立的关键: 影响速度的东西有升级倍率、分支、流沙、冰面、
## 两栖装甲、氮气、眩晕……全在 RPGManager 和一堆 Area2D 重叠计数里, 想在
## 客户端重算一遍就等于把半个战斗系统复制过去, 而**漏掉任何一项都会让预测
## 稳定地偏一个方向**, 表现为持续的橡皮筋。让主机直接告诉客户端"你现在多快"
## 就没有这一类问题: 眩晕时主机报 0, 客户端自然就不动了。
func _net_predict_step(delta: float) -> void:
	var bits := NetSession.pack_input("p1")

	# 挂载期间**不预测移动**。后车的位置由主机按机车尾迹算, 而预测是按本地
	# 方向键算的 —— 两者每帧都对不上, 于是每帧都会触发一次 NetPuppet.reconcile
	# 的拉回, 表现为后车原地高频抖动。这一位只置在后车身上, 所以机车 (哪怕
	# 机车就是客户端这辆) 照常预测。
	#
	# 开火反馈仍然预测: 后车保留手动开火, 那部分和位置无关。
	if (int(get_meta("net_flags", 0)) & NetSession.F_TOWED) != 0:
		NetPuppet.update(self, delta)
		_net_predict_fire_feedback(bits)
		return

	var dir := NetSession.dir_from_bits(bits)
	var spd: float = float(get_meta("net_speed", 0.0))

	if dir != Vector2.ZERO and spd > 0.0:
		facing_direction = dir
		velocity = dir * spd
		rotation = facing_direction.angle() + PI / 2.0
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	# 必须在 move_and_slide 之后: 反过来的话这一帧的纠偏会被移动直接覆盖掉。
	NetPuppet.reconcile(self, delta)

	_net_predict_fire_feedback(bits)


## 开火**反馈**的预测: 按下开火键的当帧就播后坐力和枪口火焰。
##
## 子弹本身完全不预测。客户端没有 rpg_mgr, 不知道伤害、分支、射速、天赋,
## 更不知道这一枪允不允许开; 预测出一颗随后被主机否掉的子弹 (冷却中、被
## 眩晕、已阵亡), 表现是子弹凭空出现又凭空消失 —— 比慢一个来回难看得多。
## 而开火反馈没有这个风险: 最坏情况只是闪了一下而子弹晚到, 那正是玩家对
## "网络有点卡"的正常预期。
##
## F_CAN_FIRE 是主机下发的"现在能不能开火"。有它才敢本地播 —— 否则冷却期间
## 狂按开火键会一路闪光, 而主机一枪都没出。
##
## 一个冷却周期只预测一次: 播完上闩, 等主机那边 can_fire 落下 (说明这一枪
## 被认下了) 再解闩。按住不放时节奏因此完全跟着主机的射速走, 不会自己乱闪。
func _net_predict_fire_feedback(bits: int) -> void:
	var flags: int = int(get_meta("net_flags", 0))
	var host_can_fire := (flags & NetSession.F_CAN_FIRE) != 0
	if not host_can_fire:
		_net_fire_latched = false
		return
	if _net_fire_latched:
		return
	if not NetSession.has_bit(bits, NetSession.IN_FIRE):
		return

	_net_fire_latched = true
	NetSession.predicted_fire_msec = Time.get_ticks_msec()

	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.03)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.06)

	var muzzle_pos := global_position + facing_direction * 28.0
	NetSession.predicted_fire_pos = muzzle_pos
	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)


## 本地已经为这一发预测过反馈了, 等主机确认 (can_fire 落下) 再放行下一发。
var _net_fire_latched: bool = false


func _physics_process(delta: float) -> void:
	# 联机客户端上的坦克 (包括自己那辆) 是傀儡: 位置完全由主机的快照决定,
	# 下面这一整套输入/移动/开火/回血逻辑一行都不跑。履带动画例外, 它是
	# 纯表现, 由位移量驱动, 放在 _net_puppet_step() 里。
	if NetPuppet.is_puppet(self):
		_net_puppet_step(delta)
		return

	if is_stunned:
		# 眩晕期间上报 0。客户端的本地预测读的就是这个值, 于是"被电晕了动不了"
		# 不需要单独同步一个状态位 —— 速度是 0, 按方向键也不动。
		net_effective_speed = 0.0
		stun_timer -= delta
		# Dizzy vibration & yellow electric stun flash
		sprite.rotation = sin(Time.get_ticks_msec() * 0.04) * 0.20
		sprite.modulate = Color(2.5, 2.5, 0.4, 1.0) if int(stun_timer * 10.0) % 2 == 0 else Color(1.0, 1.0, 0.5, 1.0)
		velocity = Vector2.ZERO
		move_and_slide()
		if stun_timer <= 0.0:
			is_stunned = false
			sprite.rotation = facing_direction.angle() + PI / 2.0
			sprite.modulate = base_color
		return

	if regen_lockout > 0.0:
		regen_lockout -= delta

	_process_train_respawn(delta)

	var main = get_tree().current_scene
	if main and main.rpg_mgr:
		var regen = main.rpg_mgr.get_regen_rate(player_id)
		if regen > 0.0 and current_health < max_health and regen_lockout <= 0.0:
			regen_accumulator += regen * delta
			if regen_accumulator >= 1.0:
				regen_accumulator -= 1.0
				heal(1)

	if is_invulnerable:
		invulnerable_timer -= delta
		if shield_sprite and shield_textures.size() > 0:
			shield_sprite.rotation += delta * 4.0
			var s_idx = int(Time.get_ticks_msec() / 100) % shield_textures.size()
			shield_sprite.texture = shield_textures[s_idx]
		if invulnerable_timer <= 0.0:
			is_invulnerable = false
			if shield_sprite:
				shield_sprite.visible = false
	
	if is_parrying:
		parry_timer -= delta
		if parry_shield_sprite:
			parry_shield_sprite.visible = true
			var buckler_dist = 22.0
			parry_shield_sprite.global_position = global_position + facing_direction * buckler_dist
			parry_shield_sprite.rotation = facing_direction.angle() + PI / 2.0
			var b_tier = 1
			if main and main.rpg_mgr:
				b_tier = main.rpg_mgr.get_branch_tier(player_id)
			elif player_id == 1:
				b_tier = GameState.branch_tier
			else:
				b_tier = GameState.p2_branch_tier
			var cur_window = parry_perfect_window if b_tier <= 1 else (parry_perfect_window + 0.04)
			if parry_timer > (parry_total_duration - cur_window):
				# Golden / Cyan energy for perfect parry window
				parry_shield_sprite.modulate = Color(2.6, 2.2, 0.4, 0.95)
				parry_shield_sprite.scale = Vector2(0.32, 0.32)
			else:
				# Electric blue for normal parry window
				var fade_ratio = clampf(parry_timer / maxf(0.01, parry_total_duration - cur_window), 0.0, 1.0)
				parry_shield_sprite.modulate = Color(0.6, 1.4, 2.4, 0.8 * fade_ratio)
				parry_shield_sprite.scale = Vector2(0.26, 0.26)
		if parry_timer <= 0.0:
			is_parrying = false
			if parry_shield_sprite:
				parry_shield_sprite.visible = false

	if not can_fire:
		fire_timer -= delta
		if fire_timer <= 0.0:
			can_fire = true

	# 输入的唯一来源。离线时 input_for() 就是原来那串
	# Input.is_action_pressed("p{id}_move_*"), 逐位等价; 联机主机上 2 号玩家
	# 的位来自客户端的 RPC。方向的优先级 (上>下>左>右) 由 dir_from_bits()
	# 保证和原来一致 —— 见那个函数的注释。
	var in_bits := NetSession.input_for(player_id)
	var input_vec := NetSession.dir_from_bits(in_bits)

	# Signal Jammer Tower map hazard: inverting input_vec here reverses both
	# movement AND firing in one place, since facing_direction (which drives
	# rotation, bullet spawn direction, and ice-slide direction below) is
	# always derived from input_vec, never read independently.
	if is_jammed:
		input_vec = -input_vec

	# === 双人合体: 这一帧我是被拖着走的后车 ===
	#
	# 位置和车身朝向交给机车的尾迹, 但**方向键仍然改 facing_direction** ——
	# 后车保留手动开火, 所以它得能瞄。等于把"走位"和"瞄准"拆给了两个人:
	# 一个人负责躲, 一个人负责打。
	#
	# 放在信号干扰反转**之后**: 干扰塔的语义是"这辆车的操作全部反向", 而后车
	# 仅存的操作就是瞄准, 跳过反转等于挂载期间对干扰塔免疫。
	#
	# 提前 return 而不是往下走: 下面整段是速度倍率、流沙冰面、推箱子和
	# move_and_slide, 对一辆被拖着的车全都不适用。履带动画和历史记录在这里
	# 自己做掉 —— 历史必须照记, 否则后车自己那几节 AI 车厢会跟丢。
	if TrainLink.is_follower(player_id):
		_towed_step(delta, input_vec)
		return

	var speed_mult = 1.0
	var is_speed_branch = (main and main.rpg_mgr and main.rpg_mgr.get_branch(player_id) == "speed")

	if main and main.rpg_mgr:
		speed_mult *= main.rpg_mgr.get_speed_multiplier(player_id)
	else:
		speed_mult *= (1.0 + float(upgrade_tier) * 0.12)

	# Sand slow resistance for speed branch / nitro booster perk
	if is_on_sand:
		if is_speed_branch or (main and main.rpg_mgr and main.rpg_mgr.has_perk("nitro_booster", player_id)):
			speed_mult *= 0.90 # Minimal sand drag
		else:
			speed_mult *= 0.50 # Normal sand drag

	# Amphibious Hull shop perk: the tradeoff for being able to enter water at
	# all is a permanent -50% speed penalty everywhere else (heavier hull,
	# sealed hatches). Only applies on land -- no penalty while actually
	# swimming, since the whole point of the upgrade is to be capable there.
	if not is_on_water and main and main.rpg_mgr and main.rpg_mgr.has_perk("amphibious_hull", player_id):
		speed_mult *= 0.50

	var current_speed = base_speed * speed_mult
	# 联机: 主机把这个值放进快照, 客户端的本地预测直接拿它当速度 ——
	# 所有速度修正 (等级/分支/流沙/冰面/两栖装甲/氮气) 因此自动生效,
	# 不需要在客户端重算一遍。见 _net_predict_step()。
	net_effective_speed = current_speed

	var has_frost_cleats = (main and main.rpg_mgr and main.rpg_mgr.has_perk("frost_cleats", player_id))

	if is_on_ice and not has_frost_cleats:
		# Slipper ice physics: input steers slide direction; releasing input keeps sliding uncontrollably!
		if input_vec != Vector2.ZERO:
			facing_direction = input_vec
			slide_direction = input_vec
			velocity = input_vec * (current_speed * 1.30)
			rotation = facing_direction.angle() + PI / 2.0
		elif slide_direction != Vector2.ZERO:
			velocity = slide_direction * (current_speed * 1.30)
			rotation = slide_direction.angle() + PI / 2.0
			
			ice_particle_timer += delta
			if ice_particle_timer >= 0.08:
				ice_particle_timer = 0.0
				if is_inside_tree() and get_parent():
					VFXAnimator.spawn_dust_puff(get_parent(), global_position - slide_direction * 14.0)
		else:
			velocity = Vector2.ZERO

		if tank_frames.size() > 0 and velocity.length_squared() > 0.0:
			tread_accum_dist += velocity.length() * delta
			var f_idx = int(tread_accum_dist / TREAD_PX_PER_FRAME) % tank_frames.size()
			if f_idx != current_frame:
				current_frame = f_idx
				sprite.texture = tank_frames[current_frame]
	else:
		slide_direction = Vector2.ZERO
		if input_vec != Vector2.ZERO:
			facing_direction = input_vec
			velocity = input_vec * current_speed
			rotation = facing_direction.angle() + PI / 2.0

			if tank_frames.size() > 0:
				tread_accum_dist += velocity.length() * delta
				var f_idx = int(tread_accum_dist / TREAD_PX_PER_FRAME) % tank_frames.size()
				if f_idx != current_frame:
					current_frame = f_idx
					sprite.texture = tank_frames[current_frame]
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	TrainFollowHelper.record_history(history_positions, history_rotations, global_position, rotation)

	# Handle pushing physical contact structures (e.g. Wooden Wall)
	if input_vec != Vector2.ZERO:
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if is_instance_valid(collider) and collider.has_method("take_push"):
				collider.take_push(facing_direction, self)

	# Hitting a solid obstacle stops ice sliding
	if is_on_ice and get_slide_collision_count() > 0:
		slide_direction = Vector2.ZERO

	# 鼠标右键开火只对"本机操作的那辆坦克"成立。离线时 local_player_id 恒为 1,
	# 于是这个条件和原来的 `player_id == 1` 完全一样; 联机时它跟着走到客户端
	# 那辆 2 号坦克上, 而不是让客户端的鼠标去开主机的炮。
	var wants_fire = NetSession.has_bit(in_bits, NetSession.IN_FIRE) \
		or (player_id == NetSession.local_player_id and not NetSession.is_client() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if wants_fire and can_fire:
		_shoot()

func _shoot() -> void:
	if not bullet_scene:
		return
	var main = get_tree().current_scene
	var branch: String
	var b_tier: int
	if main and main.rpg_mgr:
		branch = main.rpg_mgr.get_branch(player_id)
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		branch = GameState.tank_branch
		b_tier = GameState.branch_tier
	else:
		branch = GameState.p2_branch
		b_tier = GameState.p2_branch_tier

	var cd = fire_cooldown
	if main and main.rpg_mgr:
		cd *= main.rpg_mgr.get_fire_cooldown_mult(player_id)
	# 冷却地板引用 RPGManager 的常量, 不要在这里重写一遍字面量 —— 曾经真的
	# 出过岔子: RPGManager.FIRE_CD_FLOOR_COUNTER/TRENCH 分别写着 0.95/0.38,
	# 而这里实际生效的地板是 1.10/0.40, 两边一直没对上。这不是无害的重复:
	# RPGManager.is_fire_rate_capped() 就是靠它自己那份常量判断"这次射速强化
	# 还有没有用", 用来在商店/升级面板拦掉卖零的 autoloader/rapid_loader (见
	# RPGManager 里"不卖零"那条原则)。常数对不上, 拦截阈值就和这里真正的
	# clamp 不一致, 可能在还没到底时拦掉有效的强化, 或者到底之后仍然放行。
	var floor_v := RPGManager.FIRE_CD_FLOOR_SPEED
	if branch == "trench":
		floor_v = RPGManager.FIRE_CD_FLOOR_TRENCH
	elif branch == "counter":
		floor_v = RPGManager.FIRE_CD_FLOOR_COUNTER
	elif branch != "speed":
		floor_v = RPGManager.FIRE_CD_FLOOR_OTHER
	cd = maxf(floor_v, cd)
	can_fire = false
	fire_timer = cd

	var dmg = main.rpg_mgr.get_atk_damage(player_id) if (main and main.rpg_mgr) else 1
	if is_on_platform and main and main.rpg_mgr and main.rpg_mgr.has_perk("ferry_artillery", player_id):
		dmg = int(dmg * 1.5)
	var muzzle_pos = global_position + facing_direction * 28.0

	# 开炮后坐力动画与枪口火焰
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.03)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.06)

	VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

	match branch:
		"trench":
			# 壕沟战坦克：前方短距离激光环形切割攻击！
			# 切割等级和当前炮弹等级相等 (Tier 2/3 或 b_tier >= 2 具备破钢切割，并能拦截切割敌方炮弹)
			var can_cut_steel = (upgrade_tier >= 3 or b_tier >= 2)
			var cut_rad = 54.0 if b_tier >= 2 else 42.0
			# 别在这里再加一次 +1/+2 —— dmg 已经在 get_atk_damage() 里吃过
			# TRENCH_DMG_BONUS 了, 这里以前又叠一次, 相当于同一个加成算了
			# 两遍。maxi(dmg, N) 只保留原来的保底值 (2/4), 不再额外加成。
			var cut_dmg = maxi(dmg, 4) if b_tier >= 2 else maxi(dmg, 2)
			LaserRingCutter.create_cut(get_parent(), global_position, facing_direction, self, "player", cut_dmg, can_cut_steel, cut_rad)

		"counter":
			# Deploy reactive energy parry buckler
			is_parrying = true
			parry_timer = parry_total_duration
			if parry_shield_sprite:
				parry_shield_sprite.visible = true
				parry_shield_sprite.global_position = global_position + facing_direction * 22.0
				parry_shield_sprite.rotation = facing_direction.angle() + PI / 2.0
				parry_shield_sprite.modulate = Color(2.6, 2.2, 0.4, 0.95)
				parry_shield_sprite.scale = Vector2(0.32, 0.32)

			# Immediate frontal sweep parry for close incoming shells
			_sweep_immediate_parry()

			# Fire forward kinetic cannon or empowered Charged Counter Shot (+1 Tier)
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos

			if has_charged_counter_shot:
				# Charged Counter Shot upgraded +1 tier!
				has_charged_counter_shot = false
				bullet.damage = maxi(4, dmg * 2 + 2 + b_tier)
				bullet.speed = 720.0
				bullet.can_destroy_steel = true
				bullet.armor_piercing = true
				bullet.modulate = Color(2.5, 2.0, 0.4, 1.0)
				VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
				if is_inside_tree() and get_tree():
					SoundManager.play_hit_steel(get_tree())
			else:
				bullet.damage = dmg
				bullet.speed = 520.0
				bullet.can_destroy_steel = (b_tier >= 2)

		"speed":
			# High speed needle cannons
			var b_speed = 720.0
			if b_tier >= 2:
				# Triple needle fan shot
				for ang_deg in [-10.0, 0.0, 10.0]:
					var shot_dir = facing_direction.rotated(deg_to_rad(ang_deg))
					var bullet = bullet_scene.instantiate()
					bullet.direction = shot_dir
					bullet.speed = b_speed
					bullet.damage = dmg
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = muzzle_pos
			else:
				# Dual needle shot
				for offset_x in [-8.0, 8.0]:
					var right_vec = facing_direction.rotated(PI / 2.0)
					var bullet = bullet_scene.instantiate()
					bullet.direction = facing_direction
					bullet.speed = b_speed
					bullet.damage = dmg
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = muzzle_pos + right_vec * offset_x

		"heavy":
			# Massive Heavy Siege Mortar with AoE splash & screen shake
			VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.speed = 460.0
			bullet.damage = dmg # get_atk_damage() already folds in the heavy-branch bonus
			bullet.is_aoe = true
			bullet.aoe_radius = 64.0 if b_tier <= 1 else 84.0
			bullet.can_destroy_steel = (b_tier >= 2)
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos
			if main and main.has_method("add_trauma"):
				main.add_trauma(0.18)

		"train":
			# Heavy Train Locomotive Forward Cannon
			var bullet = bullet_scene.instantiate()
			bullet.direction = facing_direction
			bullet.speed = 580.0
			bullet.damage = dmg # get_atk_damage() already folds in RPGManager.TRAIN_DMG_BONUS
			bullet.can_destroy_steel = (b_tier >= 2)
			bullet.shooter = self
			bullet.shooter_type = "player"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos

		_:
			# Default classical tiers
			var is_plasma = (upgrade_tier >= 3)
			var can_break_steel = is_plasma
			# tier0 (每局开局默认值, upgrade_tier 从 0 起) 曾是 480 px/s, 在一次
			# 美术资产提交 (5d54593) 里顺手涨到 520, 不属于任何记录在案的平衡性
			# 改动。玩家反馈开局炮弹偏快, 改回原值 —— 660 (tier3+) 是后续经
			# star 升级换来的, 没有类似反馈, 不动。
			var b_speed = 480.0 if upgrade_tier == 0 else 660.0
			if is_plasma:
				VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)

			if upgrade_tier == 2:
				for offset_x in [-10.0, 10.0]:
					var right_vec = facing_direction.rotated(PI / 2.0)
					var bullet = bullet_scene.instantiate()
					bullet.direction = facing_direction
					bullet.speed = b_speed
					bullet.damage = dmg
					bullet.can_destroy_steel = can_break_steel
					bullet.shooter = self
					bullet.shooter_type = "player"
					get_parent().add_child(bullet)
					bullet.global_position = global_position + facing_direction * 28.0 + right_vec * offset_x
			else:
				var bullet = bullet_scene.instantiate()
				bullet.direction = facing_direction
				bullet.speed = b_speed
				bullet.damage = dmg
				bullet.can_destroy_steel = can_break_steel
				bullet.shooter = self
				bullet.shooter_type = "player"
				get_parent().add_child(bullet)
				bullet.global_position = muzzle_pos

	SoundManager.play_shot(get_tree())
	fired_bullet.emit()

func take_damage(amount: int) -> void:
	if is_invulnerable:
		SoundManager.play_shield_hit(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		return
	current_health -= amount
	health_changed.emit(player_id, current_health, max_health)

	# 挨了打就断掉回复的读条, 并清空累计进度 —— 不清的话连续挨打反而会在
	# 锁定结束的瞬间"攒"出一格血来。见 REGEN_COMBAT_LOCKOUT 那段。
	regen_lockout = REGEN_COMBAT_LOCKOUT
	regen_accumulator = 0.0

	# 黏土受击挤压形变动画 + 崩落。
	# 活着走崩落 (spawn_hit_spall), 死了才走碎屑 —— 同 enemy.gd::take_damage,
	# "受伤"和"被摧毁"不能是同一张图。
	if current_health > 0:
		VFXAnimator.spawn_hit_spall(get_parent(), global_position)
	else:
		VFXAnimator.spawn_clay_debris(get_parent(), global_position)
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", Vector2(0.24, 0.12), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", Vector2(0.15, 0.22), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hit_tween.tween_property(sprite, "scale", Vector2(0.18, 0.18), 0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hit_tween.parallel().tween_property(sprite, "modulate", Color(2.8, 0.6, 0.6), 0.05)
	hit_tween.chain().tween_property(sprite, "modulate", base_color, 0.08)

	if current_health <= 0:
		_die()

func _die() -> void:
	if is_dying:
		return
	is_dying = true
	# 强制走每节车厢自己的 take_damage()/_die() 链路 (爆炸+冲击波+destroyed
	# 信号), 和 enemy.gd::TRAIN_BOSS 死亡时对自己车厢做的处理一致 —— 直接
	# queue_free() 车厢会跳过它自己的死亡表现, 看起来像凭空消失。复制一份
	# 数组再遍历: take_damage() 会同步触发 _on_carriage_destroyed(), 它会
	# 从 attached_carriages 里 erase(c), 直接遍历原数组会在迭代时改动它。
	for c in attached_carriages.duplicate():
		if is_instance_valid(c):
			c.take_damage(999)
	attached_carriages.clear()
	train_respawn_timer = 0.0

	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	destroyed.emit(player_id)
	queue_free()

func on_enter_sand() -> void:
	sand_overlap_count += 1
	is_on_sand = true

func on_exit_sand() -> void:
	sand_overlap_count = max(0, sand_overlap_count - 1)
	is_on_sand = (sand_overlap_count > 0)

func on_enter_ice() -> void:
	ice_overlap_count += 1
	is_on_ice = true
	slide_direction = facing_direction

func on_exit_ice() -> void:
	ice_overlap_count = max(0, ice_overlap_count - 1)
	is_on_ice = (ice_overlap_count > 0)
	if not is_on_ice:
		slide_direction = Vector2.ZERO

func on_enter_water() -> void:
	water_overlap_count += 1
	is_on_water = true

func on_exit_water() -> void:
	water_overlap_count = max(0, water_overlap_count - 1)
	is_on_water = (water_overlap_count > 0)

func on_enter_jam() -> void:
	jam_overlap_count += 1
	is_jammed = true

func on_exit_jam() -> void:
	jam_overlap_count = max(0, jam_overlap_count - 1)
	is_jammed = (jam_overlap_count > 0)

func _sweep_immediate_parry() -> void:
	if not is_inside_tree():
		return
	var bullets = get_tree().get_nodes_in_group("bullets")
	var candidates: Array[Node2D] = []
	for b in bullets:
		if is_instance_valid(b) and b is Node2D:
			candidates.append(b)
	if candidates.size() == 0 and get_parent():
		for ch in get_parent().get_children():
			if ch is Node2D and (ch.is_in_group("bullets") or ch.has_method("_try_ricochet")):
				candidates.append(ch)

	for b in candidates:
		if is_instance_valid(b) and "shooter_type" in b and b.shooter_type == "enemy":
			var to_b = b.global_position - global_position
			var dist = to_b.length()
			if dist <= 58.0:
				if facing_direction.dot(to_b.normalized()) > -0.2 or dist <= 28.0:
					check_parry_bullet(b)

func check_parry_bullet(bullet: Node2D) -> bool:
	if not is_parrying or not is_instance_valid(bullet):
		return false

	var b_dir: Vector2 = bullet.direction if "direction" in bullet else Vector2.ZERO
	var to_bullet = (bullet.global_position - global_position).normalized()
	# Parry valid if bullet is in front of player or heading towards player
	if facing_direction.dot(b_dir) > 0.6 and facing_direction.dot(to_bullet) < -0.3:
		# Bullet moving same direction from behind - not frontal parry
		return false

	var main = get_tree().current_scene if is_inside_tree() else null
	var b_tier = 1
	if main and main.rpg_mgr:
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		b_tier = GameState.branch_tier
	else:
		b_tier = GameState.p2_branch_tier

	var cur_window = parry_perfect_window if b_tier <= 1 else (parry_perfect_window + 0.04)
	var is_perfect: bool = (parry_timer >= (parry_total_duration - cur_window))

	# Deflect bullet
	bullet.direction = facing_direction
	bullet.rotation = facing_direction.angle() + PI / 2.0
	bullet.shooter = self
	bullet.shooter_type = "player"
	bullet.global_position = global_position + facing_direction * 32.0

	if is_perfect:
		# +1 Bullet Tier upgrade!
		bullet.can_destroy_steel = true
		bullet.armor_piercing = true
		var cur_dmg: int = bullet.damage if "damage" in bullet else 1
		bullet.damage = maxi(4, int(cur_dmg * 2.2) + 2 + b_tier)
		var cur_spd: float = bullet.speed if "speed" in bullet else 500.0
		bullet.speed = maxf(720.0, cur_spd * 1.6)
		bullet.modulate = Color(2.6, 2.2, 0.4, 1.0)

		# Empower next shot & instant cooldown reset
		has_charged_counter_shot = true
		can_fire = true
		fire_timer = 0.0

		VFXAnimator.spawn_shockwave(get_parent(), bullet.global_position)
		VFXAnimator.spawn_clay_debris(get_parent(), bullet.global_position)
		if is_inside_tree() and get_tree():
			SoundManager.play_hit_steel(get_tree())
		if main and main.has_method("add_trauma"):
			main.add_trauma(0.28)
		if main and main.has_method("show_toast"):
			main.show_toast("⚡ PERFECT PARRY! 弹反升阶·破钢穿甲！⚡")
	else:
		# Standard deflection
		bullet.damage = maxi(1, bullet.damage if "damage" in bullet else 1)
		bullet.speed = maxf(520.0, bullet.speed if "speed" in bullet else 500.0)
		VFXAnimator.spawn_dust_puff(get_parent(), bullet.global_position)
		if is_inside_tree() and get_tree():
			SoundManager.play_shield_hit(get_tree())

	return true

func try_parry_laser(start_pos: Vector2, laser_dir: Vector2, beam_damage: int) -> bool:
	if not is_parrying:
		return false

	# Laser parry only from frontal hemisphere
	if laser_dir.dot(facing_direction) > 0.4:
		return false

	var main = get_tree().current_scene if is_inside_tree() else null
	var b_tier = 1
	if main and main.rpg_mgr:
		b_tier = main.rpg_mgr.get_branch_tier(player_id)
	elif player_id == 1:
		b_tier = GameState.branch_tier
	else:
		b_tier = GameState.p2_branch_tier

	var cur_window = parry_perfect_window if b_tier <= 1 else (parry_perfect_window + 0.04)
	var is_perfect: bool = (parry_timer >= (parry_total_duration - cur_window))

	if is_perfect:
		# Prism Counter Refraction (棱镜全反射)
		has_charged_counter_shot = true
		can_fire = true
		fire_timer = 0.0

		var ref_origin = global_position + facing_direction * 20.0
		var counter_dmg = maxi(3, beam_damage * 2 + b_tier)
		LaserPiercer.fire_linear_laser(get_parent(), ref_origin, facing_direction, self, "player", counter_dmg)
		if b_tier >= 2:
			# Tier 2: Triple Prism Refraction Fan
			LaserPiercer.fire_linear_laser(get_parent(), ref_origin, facing_direction.rotated(deg_to_rad(-18.0)), self, "player", maxi(2, beam_damage + 1))
			LaserPiercer.fire_linear_laser(get_parent(), ref_origin, facing_direction.rotated(deg_to_rad(18.0)), self, "player", maxi(2, beam_damage + 1))

		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		if is_inside_tree() and get_tree():
			SoundManager.play_hit_steel(get_tree())
		if main and main.has_method("add_trauma"):
			main.add_trauma(0.32)
		if main and main.has_method("show_toast"):
			main.show_toast("⚡ PERFECT PARRY! 棱镜全反射！(PRISM REFRACTION) ⚡")
	else:
		# Normal parry: block laser at buckler
		VFXAnimator.spawn_dust_puff(get_parent(), global_position)
		if is_inside_tree() and get_tree():
			SoundManager.play_shield_hit(get_tree())

	return true


