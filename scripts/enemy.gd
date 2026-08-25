class_name EnemyTank
extends CharacterBody2D

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const VFXAnimator = preload("res://scripts/vfx_animator.gd")

const LaserPiercer = preload("res://scripts/laser_piercer.gd")
const FlameJet = preload("res://scripts/flame_jet.gd")
const TrainFollowHelper = preload("res://scripts/train_follow_helper.gd")

signal enemy_destroyed(points: int, is_bonus: bool, drop_pos: Vector2)

enum EnemyType { BASIC, FAST, POWER, ARMOR, MISSILE, LASER, BOSS, DESERT, TRAIN_BOSS, BOMBER, SUICIDE, MIRAGE, BATTLESHIP, AIRCRAFT, WARP, FLAMETHROWER, CRUSHER, SNIPER, GATLING, SHOTGUN, SPLITTER, SPLIT_MINI, ENGINEER, SPIDER, FIREWALL, HUNTER, SANDWORM, CANNON }

## 奖励 (xp/gold/score) 的楼层缩放斜率。**只作用于奖励, 不作用于血量** ——
## 血量走下面的装甲板系统。
const FLOOR_SCALE_SLOPE := 0.08

# ---------------------------------------------------------------- 装甲板
#
# 这是坦克大战, 不是 RPG。敌人的强弱只能是**整数**, 而且必须看得出来。
#
# 之前的做法是 max_health = ceil(base * (1 + floor * 0.08)) —— 一个隐藏的
# 连续乘数: floor 12 的 enemy_basic 有 3 血, 和 floor 0 那只 1 血的长得一模
# 一样。玩家开两枪发现没死, 除了"这游戏在偷偷加数值"之外读不出任何信息, 而
# 这正是 Tank 1990 从来不做的事 —— 那边的装甲车就是要打四下, 而且它**长得
# 不一样**, 谁都看得出来。
#
# 现在: 每辆车带 0-3 层装甲板, 每层 +ARMOR_PLATE_HP 血 (整数加法, 没有 ceil,
# 没有浮点), 每一层都有对应的外观 (enemy_plate_t1/t2/t3.png 叠在车体上,
# 覆盖面积逐级变大)。血量 = 车种基础血 + 装甲层数 x 2。
#
# 关键的一条: **不给全场统一加血**, 而是让高楼层能刷出带装甲的变体。
# 加法式的统一加血会毁掉车种识别 —— BASIC 的 1 血被加成 7 血, "杂兵一发一个"
# 这条坦克大战的底子就没了。现在同一层里既有素车也有披甲车, 玩家看一眼就知道
# 哪辆要多打几发, 该先绕开谁。难度来自"场上多了看得见的硬目标", 而不是
# "所有东西都悄悄变厚了"。
#
# 楼层/精英/Boss/难度圈的作用方式是抬**装甲层数的上下界**, 而不是乘血量:
#   - 楼层越高, 上界越高 (能刷出更厚的车)
#   - 精英战 / Boss 战 / 第二第三圈, 抬的是**下界** (素车越来越少)
# 上下界都夹在 [0, MAX_ARMOR_PLATES] 内, 所以永远不会出现"有血量没外观"的层。
const ARMOR_PLATE_HP := 2
const MAX_ARMOR_PLATES := 3

## 楼层 -> 装甲层数上界。写成显式的门槛表而不是 floor/4 之类的算式, 是因为
## 这是一条设计曲线不是数学关系 —— 想让第 4 层第一次见到披甲车, 就该在这里
## 一眼看见 4。
const ARMOR_PLATE_FLOOR_GATE := [2, 5, 9] # 分别是拿到第 1/2/3 层上界的楼层

var armor_plates: int = 0
var plate_sprite: Sprite2D = null

@export var enemy_type: EnemyType = EnemyType.BASIC
@export var is_bonus: bool = false

var speed: float = 100.0
var max_health: int = 1
var health: int = 1
var is_dying: bool = false
var score_value: int = 100
var xp_value: int = 35
var gold_value: int = 20
var fire_interval: float = 1.2
var fire_timer: float = 0.0
var change_dir_timer: float = 0.0
var freeze_timer: float = 0.0
var is_on_sand: bool = false
var sand_overlap_count: int = 0
var is_on_ice: bool = false
var ice_overlap_count: int = 0

# 喷火兵的持续火舌与它的开合周期。
# 做成"喷 2.4 秒 / 停 1.2 秒"而不是常开: 常开的话玩家一旦被逼到它正面就没有任何
# 处理窗口, 只能等死; 有间歇才谈得上"看准换气的空档冲过去"。
# 喷嘴上的引燃火在冷却期也亮着 (见 build_flamethrower_assets.py), 是这个节奏的
# 视觉提示。
var flame_jet: FlameJet = null
var flame_cycle_t: float = 0.0
var flame_is_on: bool = false
const FLAME_BURN_TIME: float = 2.4
const FLAME_REST_TIME: float = 1.2

var is_camouflaged: bool = false
var still_timer: float = 0.0
var tree_tex: Texture2D = null
var is_suicide_detonated: bool = false
var plane_shadow: Sprite2D = null
var wake_timer: float = 0.0
var warp_blink_timer: float = 0.0
var build_timer: float = 0.0
const BUILD_COOLDOWN: float = 10.0
const BUILD_PREPARE_TIME: float = 1.5

var is_leaping: bool = false
var jump_cooldown_timer: float = 0.0
const JUMP_COOLDOWN: float = 3.5
var leap_shadow: Sprite2D = null

# 火墙坦克火墙轨迹
var firewall_trail_queue: Array[Node2D] = []
const MAX_FIREWALL_TRAIL_LENGTH: int = 10
var last_firewall_drop_pos: Vector2 = Vector2.ZERO
const FIREWALL_DROP_DISTANCE: float = 36.0

# 猎手坦克潜伏与伏击
var is_in_ambush: bool = false
var hunter_target_bush_pos: Vector2 = Vector2.INF
var ambush_check_timer: float = 0.0
var ambush_cooldown: float = 0.0

# 沙虫坦克潜地钻掘与破土突袭
var is_burrowed: bool = false
var is_burrowing: bool = false
var burrow_timer: float = 6.0
const BURROW_INTERVAL: float = 6.5

# 巨炮坦克 (Colossus Siege Cannon Tank) 变形驻扎固定要塞炮机制
var is_cannon_deployed: bool = false
var cannon_undeploy_timer: float = 0.0
var cannon_mobile_frames: Array[Texture2D] = []
var cannon_deploy_frames: Array[Texture2D] = []
const CANNON_DEPLOY_DIST: float = 192.0 # 离玩家 <= 4 格时主动变形驻扎为固定炮
const CANNON_UNDEPLOY_DIST: float = 270.0 # 玩家远离超 5.6 格且保持脱离时收起驻扎恢复巡航
const CANNON_UNDEPLOY_DELAY: float = 2.5

# 敌方护盾塔增益与护盾气泡
var shield_sources: Array = []
var shield_bubble_sprite: Sprite2D = null
var shield_bubble_textures: Array[Texture2D] = []
var shield_anim_timer: float = 0.0

var facing_direction: Vector2 = Vector2.DOWN
var tank_frames: Array[Texture2D] = []
var current_frame: int = 0

@onready var sprite: Sprite2D = $Sprite2D

var bullet_scene: PackedScene
var explosion_scene: PackedScene
var coin_scene: PackedScene
var carriage_scene: PackedScene
var attached_wagons: Array[Node2D] = []
var history_positions: Array[Vector2] = []
var history_rotations: Array[float] = []

var hit_tween: Tween
var recoil_tween: Tween

func _ready() -> void:
	add_to_group("enemies")
	bullet_scene = load("res://scenes/bullet.tscn")
	explosion_scene = load("res://scenes/explosion.tscn")
	coin_scene = load("res://scenes/gold_coin.tscn")
	carriage_scene = load("res://scenes/train_carriage.tscn")
	tree_tex = TextureHelper.get_tex("res://assets/sprites/tiles/tile_trees.png")
	for i in range(8):
		var s_tex = TextureHelper.get_tex("res://assets/sprites/effects/shield_bubble_%d.png" % i)
		if s_tex:
			shield_bubble_textures.append(s_tex)
	_setup_tank_type()
	rotation = facing_direction.angle() + PI / 2.0
	change_dir_timer = randf_range(1.0, 2.5)
	fire_timer = randf_range(1.2, 2.5)
	warp_blink_timer = randf_range(2.5, 4.0)
	if enemy_type == EnemyType.TRAIN_BOSS:
		call_deferred("_spawn_train_wagons")
	elif enemy_type == EnemyType.AIRCRAFT:
		z_index = 60
		collision_mask = 16 # Fly freely over walls/terrain
		var shd_tex = TextureHelper.get_tex("res://assets/sprites/effects/vfx_plane_shadow.png")
		if shd_tex:
			plane_shadow = Sprite2D.new()
			plane_shadow.texture = shd_tex
			plane_shadow.scale = Vector2(0.20, 0.20)
			plane_shadow.z_index = 5
			get_parent().call_deferred("add_child", plane_shadow)

func is_shielded() -> bool:
	return shield_sources.size() > 0

func add_shield_source(source: Node) -> void:
	if not shield_sources.has(source):
		shield_sources.append(source)
		_update_shield_state()

func remove_shield_source(source: Node) -> void:
	shield_sources.erase(source)
	_update_shield_state()

func _update_shield_state() -> void:
	if is_shielded():
		if shield_bubble_sprite == null:
			shield_bubble_sprite = Sprite2D.new()
			shield_bubble_sprite.z_index = 25
			var s_scale = Vector2(0.26, 0.26) if (enemy_type == EnemyType.BOSS or enemy_type == EnemyType.CRUSHER or enemy_type == EnemyType.SPLITTER) else (Vector2(0.16, 0.16) if enemy_type == EnemyType.SPLIT_MINI else Vector2(0.21, 0.21))
			shield_bubble_sprite.scale = s_scale
			if shield_bubble_textures.size() > 0:
				shield_bubble_sprite.texture = shield_bubble_textures[0]
			add_child(shield_bubble_sprite)
		shield_bubble_sprite.visible = true
	else:
		if shield_bubble_sprite:
			shield_bubble_sprite.visible = false

## 摇这辆车带几层装甲。返回 0..MAX_ARMOR_PLATES 的整数。
##
## static 是为了可测: tools/test_armor_plating.gd 直接对着它扫全部楼层 x 战斗
## 类型 x 难度圈, 不用把整个 main.tscn 起起来。
##
## 上界随楼层长 (高层能刷出更厚的车), 下界随精英/Boss/难度圈长 (素车越来越少)。
## 两者都夹在 [0, MAX_ARMOR_PLATES]: 上界封顶保证不会出现"有血量却没有对应
## 外观"的情况 —— 那就退回成隐藏数值了。
static func armor_plate_range(floor_idx: int, battle_type: String, cycle: int) -> Vector2i:
	var hi := 0
	for gate in ARMOR_PLATE_FLOOR_GATE:
		if floor_idx >= gate:
			hi += 1

	# 精英战 +1, Boss 战 +2: 抬的是**下界**, 也就是"这一场几乎见不到素车"。
	# Boss 给 2 是为了让 Boss 层看着就和常规层不是一回事 —— 满场至少两层装甲,
	# 一眼能看出来, 而不是靠一个看不见的 x1.6。
	var bump := cycle
	if battle_type == "elite":
		bump += 1
	elif battle_type == "boss":
		bump += 2

	hi = clampi(hi + bump, 0, MAX_ARMOR_PLATES)
	var lo := clampi(bump, 0, hi)
	return Vector2i(lo, hi)


static func roll_armor_plates(floor_idx: int, battle_type: String, cycle: int) -> int:
	var r := armor_plate_range(floor_idx, battle_type, cycle)
	return randi_range(r.x, r.y)


## 把装甲板贴到车体上。挂成 sprite 的**子节点**, 所以缩放/旋转/后坐力位移/
## 受击挤压全都自动跟着走 —— 不需要每帧同步, 也就没有"车动了板子没动"这类
## 坐标不同步的 bug。
func _apply_armor_plate_visual() -> void:
	if plate_sprite:
		plate_sprite.queue_free()
		plate_sprite = null
	if armor_plates <= 0 or sprite == null:
		return
	var tex = TextureHelper.get_tex(
		"res://assets/sprites/tanks/enemy_plate_t%d.png" % armor_plates)
	if tex == null:
		return
	plate_sprite = Sprite2D.new()
	plate_sprite.texture = tex
	plate_sprite.z_index = 1
	sprite.add_child(plate_sprite)


func _setup_tank_type() -> void:
	var prefix = "enemy_basic"
	match enemy_type:
		EnemyType.BASIC:
			prefix = "enemy_basic"
			speed = 75.0
			max_health = 1
			score_value = 100
			xp_value = 25
			gold_value = 15
			fire_interval = 2.8
		EnemyType.FAST:
			prefix = "enemy_fast"
			speed = 120.0
			max_health = 1
			score_value = 200
			xp_value = 40
			gold_value = 25
			fire_interval = 2.2
		EnemyType.POWER:
			prefix = "enemy_power"
			speed = 85.0
			max_health = 2
			score_value = 300
			xp_value = 55
			gold_value = 35
			fire_interval = 1.6
		EnemyType.ARMOR:
			prefix = "enemy_armor"
			speed = 60.0
			max_health = 4
			score_value = 400
			xp_value = 80
			gold_value = 50
			fire_interval = 2.2
		EnemyType.FLAMETHROWER:
			prefix = "enemy_flame"
			# 慢、肉、近战。它的威胁来自"正面是一条持续的死亡区域", 不是靠数值,
			# 所以移动速度压到全场最慢之一, 给玩家留出绕侧面的时间。
			speed = 58.0
			max_health = 4
			score_value = 550
			xp_value = 100
			gold_value = 70
			# 火舌自己有开合周期 (FLAME_BURN_TIME/FLAME_REST_TIME), 不走 fire_timer,
			# 这里给个大值只是为了不让通用射击逻辑插进来放子弹。
			fire_interval = 999.0
		EnemyType.MISSILE:
			prefix = "enemy_missile"
			speed = 70.0
			max_health = 3
			score_value = 500
			xp_value = 95
			gold_value = 60
			fire_interval = 3.2
		EnemyType.LASER:
			prefix = "enemy_laser"
			speed = 75.0
			max_health = 3
			score_value = 600
			xp_value = 110
			gold_value = 75
			fire_interval = 3.8
		EnemyType.BOSS:
			prefix = "enemy_boss"
			speed = 55.0
			max_health = 10
			score_value = 1500
			xp_value = 250
			gold_value = 180
			fire_interval = 2.0
		EnemyType.DESERT:
			prefix = "tank_desert"
			speed = 95.0
			max_health = 2
			score_value = 450
			xp_value = 85
			gold_value = 55
			fire_interval = 2.0
		EnemyType.TRAIN_BOSS:
			prefix = "enemy_train_loco"
			speed = 55.0
			max_health = 14
			score_value = 2500
			xp_value = 400
			gold_value = 260
			fire_interval = 1.8
		EnemyType.BOMBER:
			prefix = "enemy_bomber"
			speed = 80.0
			max_health = 3
			score_value = 550
			xp_value = 100
			gold_value = 65
			fire_interval = 2.8
		EnemyType.SUICIDE:
			prefix = "enemy_suicide"
			speed = 155.0
			max_health = 2
			score_value = 450
			xp_value = 85
			gold_value = 50
			fire_interval = 999.0
		EnemyType.MIRAGE:
			prefix = "enemy_mirage"
			speed = 85.0
			max_health = 3
			score_value = 600
			xp_value = 115
			gold_value = 75
			fire_interval = 2.5
		EnemyType.BATTLESHIP:
			prefix = "enemy_battleship"
			speed = 65.0
			max_health = 6
			score_value = 750
			xp_value = 150
			gold_value = 90
			fire_interval = 2.4
		EnemyType.AIRCRAFT:
			prefix = "enemy_aircraft"
			speed = 160.0
			max_health = 2
			score_value = 500
			xp_value = 100
			gold_value = 60
			fire_interval = 1.6
		EnemyType.WARP:
			prefix = "enemy_warp"
			speed = 100.0
			max_health = 3
			score_value = 680
			xp_value = 130
			gold_value = 85
			fire_interval = 2.3
		EnemyType.CRUSHER:
			prefix = "enemy_crusher"
			speed = 40.0 # 行动缓慢的超重装粉碎机
			max_health = 10 # 极其厚重的重装陶泥装甲
			score_value = 1600
			xp_value = 260
			gold_value = 160
			fire_interval = 999.0 # 不发射子弹，靠碾碎一切物体推进
		EnemyType.SNIPER:
			prefix = "enemy_sniper"
			speed = 135.0 # 高机动巡航狙击车：移动速度极快，但射击间隔长
			max_health = 2 # 脆皮轻装甲
			score_value = 650
			xp_value = 125
			gold_value = 80
			fire_interval = 4.8 # 射击间隔极长（蓄力装填），但一旦射出便是超高速穿甲重弹
		EnemyType.GATLING:
			prefix = "enemy_gatling"
			speed = 42.0 # 重装压制机枪要塞：移动极慢，但射速极快
			max_health = 5 # 厚重装甲
			score_value = 850
			xp_value = 160
			gold_value = 95
			fire_interval = 0.40 # 极快连发高密压制弹幕
		EnemyType.SHOTGUN:
			prefix = "enemy_shotgun"
			speed = 95.0 # 中高速近身突击冲锋
			max_health = 3 # 适中装甲
			score_value = 600
			xp_value = 115
			gold_value = 75
			fire_interval = 2.4 # 扇形 3 路扩散破片霰弹
		EnemyType.SPLITTER:
			prefix = "enemy_splitter"
			speed = 52.0 # 沉重推进的大型母体战车
			max_health = 7 # 坚厚母体装甲，被摧毁后分裂出 4 辆小型战车
			score_value = 1000
			xp_value = 200
			gold_value = 120
			fire_interval = 2.2 # 双联重型火炮
		EnemyType.SPLIT_MINI:
			prefix = "enemy_split_mini"
			speed = 130.0 # 敏捷高速的小型分裂子战车
			max_health = 1 # 脆弱但迅速
			score_value = 150
			xp_value = 30
			gold_value = 15
			fire_interval = 1.8
		EnemyType.ENGINEER:
			prefix = "enemy_engineer"
			speed = 70.0 # 重型工程车速度平稳
			max_health = 4 # 坚固工程外壳
			score_value = 550
			xp_value = 110
			gold_value = 65
			fire_interval = 2.4 # 辅助自卫性开火
			build_timer = BUILD_COOLDOWN
		EnemyType.SPIDER:
			prefix = "enemy_spider"
			speed = 92.0 # 仿生机械8足敏捷高速移动
			max_health = 3 # 坚固几丁质仿生甲
			score_value = 600
			xp_value = 120
			gold_value = 70
			fire_interval = 1.6 # 头部双联毒针速射炮
			jump_cooldown_timer = 1.0 # 入场 1 秒后即可发动首次越障跳跃
		EnemyType.FIREWALL:
			prefix = "enemy_firewall"
			speed = 78.0 # 重型压迫机动
			max_health = 4 # 耐高温黑曜熔岩重甲
			score_value = 650
			xp_value = 130
			gold_value = 75
			fire_interval = 2.0 # 重型高压喷火自卫
			last_firewall_drop_pos = global_position
		EnemyType.HUNTER:
			prefix = "enemy_hunter"
			speed = 88.0 # 敏捷潜伏机动
			max_health = 2 # 隐蔽轻型战术甲
			score_value = 550
			xp_value = 110
			gold_value = 60
			fire_interval = 1.8 # 消音穿甲狙击炮
		EnemyType.SANDWORM:
			prefix = "enemy_sandworm"
			speed = 72.0 # 几丁质节肢地面蠕动巡逻
			max_health = 3 # 分段式几丁质硬壳装甲
			score_value = 600
			xp_value = 120
			gold_value = 70
			fire_interval = 2.0 # 背部双联沙爆迫击炮
			burrow_timer = 5.0 # 入场 5 秒后触发首次钻地
		EnemyType.CANNON:
			prefix = "enemy_cannon"
			speed = 65.0 # 重型要塞巡航移速
			max_health = 6 # 极其坚固的重装甲结构
			score_value = 800
			xp_value = 160
			gold_value = 95
			fire_interval = 2.4 # 巡航模式射击间隔
			is_cannon_deployed = false
			cannon_undeploy_timer = 0.0

	# 动态难度缩放 (Dynamic Scaling based on floor & encounter type)
	var floor_mult = 1.0 + float(GameState.current_floor) * FLOOR_SCALE_SLOPE
	var cycle = GameState.get_difficulty_cycle()

	# 血量: 车种基础血 + 装甲层数 x 2。整数, 而且每一层都看得见。
	# 详见文件顶部 ARMOR_PLATE_HP 那段。
	armor_plates = roll_armor_plates(
		GameState.current_floor, GameState.battle_type, cycle)
	max_health += armor_plates * ARMOR_PLATE_HP

	# 关于下面这些乘数, 有一条界线:
	#
	#   **强弱量 (血量、伤害) 必须是整数, 而且必须看得见** —— 见上面的装甲板。
	#   速率与时序 (射击间隔) 可以按比例缩放, 因为它本来就是连续量, 而且
	#   "弹幕变密"是玩家当场感觉得到的; 奖励 (xp/gold/score) 同理, 它显示在
	#   结算界面上, 本身就是可见的。
	#
	# 移动速度曾经也在这里挨乘 (精英/Boss x1.08, 每圈再 x1.07)。已删:
	# 75 -> 81 px/s, 过一格 48px 是 0.64 秒对 0.59 秒 —— 既感觉不到, 也读不出来,
	# 属于两头不占的隐藏数值。难度圈丢掉的那部分改由**遭遇规模**承担
	# (main.gd::encounter_size), 那是一个整数, 而且"这一场来了 20 辆而不是 12 辆"
	# 是一眼能看出来的。
	if GameState.battle_type == "elite":
		xp_value = int(xp_value * 1.6)
		gold_value = int(gold_value * 1.5)
		score_value = int(score_value * 1.5)
		fire_interval = fire_interval * 0.85
	elif GameState.battle_type == "boss":
		xp_value = int(xp_value * 1.8)
		gold_value = int(gold_value * 1.8)
		score_value = int(score_value * 1.8)
		fire_interval = fire_interval * 0.80
	else:
		xp_value = int(xp_value * floor_mult)
		gold_value = int(gold_value * floor_mult)
		score_value = int(score_value * floor_mult)

	# Acts beyond 3 re-lap the same 3 visual themes (GameState.get_visual_act()),
	# so without this they'd just be Acts 1-3 replayed at identical difficulty.
	# 强度部分由两处承担, 都是整数且可见: roll_armor_plates() 抬装甲下界
	# (素车越来越少), main.gd::encounter_size() 抬遭遇规模。这里只剩奖励。
	if cycle > 0:
		xp_value = int(xp_value * (1.0 + cycle * 0.15))
		gold_value = int(gold_value * (1.0 + cycle * 0.15))
		score_value = int(score_value * (1.0 + cycle * 0.15))

	_apply_armor_plate_visual()

	if enemy_type == EnemyType.FLAMETHROWER and flame_jet == null:
		# 挂成子节点, 位置和旋转由父变换自动带着走 —— 不需要每帧同步坐标。
		flame_jet = FlameJet.new()
		flame_jet.shooter = self
		add_child(flame_jet)
		flame_cycle_t = randf_range(0.0, FLAME_BURN_TIME)

	health = max_health
	tank_frames.clear()
	if enemy_type == EnemyType.CANNON:
		cannon_mobile_frames.clear()
		cannon_deploy_frames.clear()
		for i in range(6):
			var m_tex = TextureHelper.get_tex("res://assets/sprites/tanks/enemy_cannon_f%d.png" % i)
			if m_tex:
				cannon_mobile_frames.append(m_tex)
			var d_tex = TextureHelper.get_tex("res://assets/sprites/tanks/enemy_cannon_deploy_f%d.png" % i)
			if d_tex:
				cannon_deploy_frames.append(d_tex)
		tank_frames = cannon_mobile_frames
		sprite.scale = Vector2(0.20, 0.20)
	else:
		for i in range(6):
			var tex = TextureHelper.get_tex("res://assets/sprites/tanks/%s_f%d.png" % [prefix, i])
			if tex:
				tank_frames.append(tex)
			if enemy_type == EnemyType.BOSS or enemy_type == EnemyType.CRUSHER or enemy_type == EnemyType.SPLITTER:
				sprite.scale = Vector2(0.24, 0.24)
			elif enemy_type == EnemyType.SPLIT_MINI:
				sprite.scale = Vector2(0.14, 0.14)

func freeze(duration: float) -> void:
	freeze_timer = duration

func _physics_process(delta: float) -> void:
	if freeze_timer > 0.0:
		freeze_timer -= delta
		sprite.modulate = Color(0.5, 0.8, 1.2)
		return

	if is_bonus:
		var flash = int(Time.get_ticks_msec() / 120) % 2 == 0
		sprite.modulate = Color(2.0, 0.4, 0.4) if flash else Color(1.0, 1.0, 1.0)
	elif enemy_type == EnemyType.ARMOR:
		if health == 3:
			sprite.modulate = Color(1.2, 1.1, 0.6)
		elif health == 2:
			sprite.modulate = Color(1.3, 0.8, 0.4)
		elif health == 1:
			sprite.modulate = Color(1.5, 0.4, 0.4)
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0)
	elif enemy_type == EnemyType.SUICIDE:
		pass
	else:
		sprite.modulate = Color(1.0, 1.0, 1.0)

	# 1. Suicide Truck Dedicated High-Speed Intercept AI
	if enemy_type == EnemyType.SUICIDE:
		var target = _find_target()
		if target and is_instance_valid(target):
			var to_target = target.global_position - global_position
			var dist = to_target.length()
			if dist <= 42.0:
				_suicide_detonate()
				return

			if abs(to_target.x) > abs(to_target.y):
				facing_direction = Vector2.RIGHT if to_target.x > 0 else Vector2.LEFT
			else:
				facing_direction = Vector2.DOWN if to_target.y > 0 else Vector2.UP
			rotation = facing_direction.angle() + PI / 2.0

			var flash_spd = clampf(600.0 / max(40.0, dist), 8.0, 36.0)
			sprite.modulate = Color(2.5, 0.4, 0.4, 1.0) if int(Time.get_ticks_msec() * 0.001 * flash_spd) % 2 == 0 else Color(1.0, 1.0, 1.0, 1.0)
	else:
		change_dir_timer -= delta
		if change_dir_timer <= 0.0:
			_choose_new_direction()
			change_dir_timer = randf_range(1.5, 3.5)

	# 2. Mirage Tank Optical Camouflage State Machine
	if enemy_type == EnemyType.MIRAGE:
		if velocity.length_squared() < 10.0:
			still_timer += delta
			if still_timer >= 0.45 and not is_camouflaged:
				is_camouflaged = true
				_spawn_mirage_shimmer()
				if tree_tex:
					sprite.texture = tree_tex
					sprite.scale = Vector2(0.1875, 0.1875)
				# 装甲板必须跟着藏起来。伪装成树的车顶上还挂着一圈钢板,
				# 等于把自己的位置标出来 —— 潜行单位不能自己暴露自己
				# (同样的理由见 main.gd::_update_tree_transparency 里
				# "跳过伪装中的 MIRAGE"那段)。
				if plate_sprite:
					plate_sprite.visible = false
				rotation = 0.0
		else:
			if is_camouflaged:
				is_camouflaged = false
				still_timer = 0.0
				_spawn_mirage_shimmer()
				sprite.scale = Vector2(0.196, 0.196)
				rotation = facing_direction.angle() + PI / 2.0
				if plate_sprite:
					plate_sprite.visible = true
				if tank_frames.size() > 0:
					sprite.texture = tank_frames[current_frame]

	# 3. Aircraft High-Altitude Flight & Shadow Tracking
	if enemy_type == EnemyType.AIRCRAFT:
		if is_instance_valid(plane_shadow):
			plane_shadow.global_position = global_position + Vector2(18.0, 26.0)
			plane_shadow.rotation = rotation

		# Screen boundary patrol bounce
		if global_position.x < 48.0 and facing_direction == Vector2.LEFT:
			facing_direction = Vector2.RIGHT if randf() < 0.5 else Vector2.DOWN
			rotation = facing_direction.angle() + PI / 2.0
		elif global_position.x > 576.0 and facing_direction == Vector2.RIGHT:
			facing_direction = Vector2.LEFT if randf() < 0.5 else Vector2.DOWN
			rotation = facing_direction.angle() + PI / 2.0
		elif global_position.y < 48.0 and facing_direction == Vector2.UP:
			facing_direction = Vector2.DOWN
			rotation = facing_direction.angle() + PI / 2.0
		elif global_position.y > 576.0 and facing_direction == Vector2.DOWN:
			facing_direction = Vector2.UP if randf() < 0.5 else (Vector2.LEFT if randf() < 0.5 else Vector2.RIGHT)
			rotation = facing_direction.angle() + PI / 2.0

	# 4. Battleship Water Foam Wake Generation
	elif enemy_type == EnemyType.BATTLESHIP:
		wake_timer += delta
		if wake_timer >= 0.14:
			wake_timer = 0.0
			_spawn_water_wake()

	# 5. Warp Phantom Self-Teleport Blink (Act 3 signature: hard to pin down)
	elif enemy_type == EnemyType.WARP:
		warp_blink_timer -= delta
		if warp_blink_timer <= 0.0:
			warp_blink_timer = randf_range(3.5, 5.5)
			_warp_blink()

	# 6. 喷火兵: 火舌自成节奏, 不走 fire_timer 那套"攒够时间放一发"的逻辑
	elif enemy_type == EnemyType.FLAMETHROWER:
		if flame_jet:
			flame_cycle_t -= delta
			if flame_cycle_t <= 0.0:
				flame_is_on = not flame_is_on
				flame_cycle_t = FLAME_BURN_TIME if flame_is_on else FLAME_REST_TIME
				flame_jet.set_burning(flame_is_on)

	# 7. 粉碎者: 前方碾压扫荡，碾碎一切碰到的地形、建筑与坦克
	elif enemy_type == EnemyType.CRUSHER:
		_crush_sweep(delta)

	# 8. 狙击手: 射击前 0.6 秒停步锁定玩家方向并高亮闪烁蓄力
	elif enemy_type == EnemyType.SNIPER:
		if fire_timer <= 0.6:
			var target = _find_target()
			if target and is_instance_valid(target):
				var to_target = target.global_position - global_position
				if abs(to_target.x) > abs(to_target.y):
					facing_direction = Vector2.RIGHT if to_target.x > 0 else Vector2.LEFT
				else:
					facing_direction = Vector2.DOWN if to_target.y > 0 else Vector2.UP
				rotation = facing_direction.angle() + PI / 2.0
			var charge_flash = int(Time.get_ticks_msec() / 75) % 2 == 0
			sprite.modulate = Color(1.2, 2.4, 3.0) if charge_flash else Color(1.0, 1.0, 1.0)

	# 9. 工程坦克: 10 秒周期内在周围随机建造地形或建筑
	elif enemy_type == EnemyType.ENGINEER:
		build_timer -= delta
		if build_timer <= 0.0:
			_perform_engineer_build()
			build_timer = BUILD_COOLDOWN
		elif build_timer <= BUILD_PREPARE_TIME:
			# 施工预备提示：琥珀警示闪烁 + 施工蓄力高亮
			var prep_flash = int(Time.get_ticks_msec() / 100) % 2 == 0
			sprite.modulate = Color(1.8, 1.4, 0.4) if prep_flash else Color(1.0, 1.0, 1.0)
		else:
			sprite.modulate = Color(1.0, 1.0, 1.0)

	# 10. 跳蛛坦克: 越障跳跃判定与冷却处理
	elif enemy_type == EnemyType.SPIDER:
		if is_leaping:
			return # 滞空中由 Tween 驱动移动与演出，不执行常规地面碰撞
		if jump_cooldown_timer > 0.0:
			jump_cooldown_timer -= delta
		else:
			_check_and_trigger_spider_jump()

	# 11. 火墙坦克: 移动时在身后铺设最多 10 格火墙轨迹
	elif enemy_type == EnemyType.FIREWALL:
		if global_position.distance_to(last_firewall_drop_pos) >= FIREWALL_DROP_DISTANCE:
			_drop_firewall_hazard()

	# 12. 猎手坦克: 草丛搜寻、隐蔽潜伏与路过伏击突袭
	elif enemy_type == EnemyType.HUNTER:
		_process_hunter_ambush_behavior(delta)

	# 13. 沙虫坦克: 周期性钻地潜行与随机破土突袭
	elif enemy_type == EnemyType.SANDWORM:
		if is_burrowed or is_burrowing:
			return # 潜地状态中由协程与动画驱动，不执行常规地面碰撞
		burrow_timer -= delta
		if burrow_timer <= 0.0:
			_start_sandworm_burrow()

	# 14. 巨炮坦克: 接近玩家时变形驻扎为固定要塞炮，极大提升防御与火力
	elif enemy_type == EnemyType.CANNON:
		_process_cannon_siege_behavior(delta)

	# 15. 护盾发生气泡动画更新
	if is_shielded():
		shield_anim_timer += delta * 8.0
		if is_instance_valid(shield_bubble_sprite) and shield_bubble_textures.size() > 0:
			var s_idx = int(shield_anim_timer) % shield_bubble_textures.size()
			shield_bubble_sprite.texture = shield_bubble_textures[s_idx]
			shield_bubble_sprite.rotation += delta * 1.5

	# 喷火兵、自爆车与粉碎者不发射常规子弹；潜伏中的猎手坦克与钻地中的沙虫坦克静候触发
	if enemy_type != EnemyType.FLAMETHROWER and enemy_type != EnemyType.SUICIDE and enemy_type != EnemyType.CRUSHER and not is_in_ambush and not is_burrowed:
		fire_timer -= delta
		if fire_timer <= 0.0:
			_shoot()
			fire_timer = randf_range(fire_interval * 0.8, fire_interval * 1.3)

	var move_speed = speed
	if is_in_ambush or is_cannon_deployed:
		move_speed = 0.0 # 草丛潜伏期间或驻扎要塞形态下牢固抓地不移动
	elif enemy_type == EnemyType.SNIPER and fire_timer <= 0.6:
		move_speed = 0.0 # 狙击手开火前夕停步静止架枪蓄力
	elif is_on_ice:
		move_speed *= 1.35 # Enemies slide fast across ice
		if enemy_type == EnemyType.WARP:
			move_speed *= 1.15 # 虚空坦克在冰面上额外抓地增幅，呼应 Act3 主题
	elif is_on_sand:
		if enemy_type == EnemyType.DESERT:
			move_speed *= 1.45 # 沙漠坦克在沙地上获得45%速度增幅！
		else:
			move_speed *= 0.50 # 普通敌人在沙地上减速50%

	velocity = facing_direction * move_speed
	var collision = move_and_collide(velocity * delta)
	TrainFollowHelper.record_history(history_positions, history_rotations, global_position, rotation)
	if collision:
		var col_node = collision.get_collider()
		if enemy_type == EnemyType.SUICIDE:
			if col_node and (col_node.is_in_group("player") or col_node.is_in_group("base_eagle") or col_node.is_in_group("buildings")):
				_suicide_detonate()
				return
		elif enemy_type == EnemyType.CRUSHER:
			if col_node:
				var crushed = _crush_target(col_node)
				if not crushed:
					_choose_new_direction()
		else:
			if col_node and is_instance_valid(col_node) and col_node.has_method("take_push"):
				col_node.take_push(facing_direction, self)
			_choose_new_direction()

	if tank_frames.size() > 0 and not is_camouflaged:
		var f_idx = int(Time.get_ticks_msec() / 65) % tank_frames.size()
		if f_idx != current_frame:
			current_frame = f_idx
			sprite.texture = tank_frames[current_frame]

func _crush_sweep(_delta: float) -> void:
	if not is_inside_tree() or get_world_2d() == null:
		return
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(44.0, 44.0)
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + facing_direction * 22.0)
	query.collision_mask = 1 | 2 | 16
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hits = space_state.intersect_shape(query, 8)
	for hit in hits:
		var col = hit.get("collider")
		if not is_instance_valid(col) or col == self:
			continue
		_crush_target(col)

func _crush_target(col: Object) -> bool:
	if not is_instance_valid(col) or col == self:
		return false

	# 1. 砖块、硬泥、树木、冰块、沙丘、陷阱地刺等地形障碍
	if col.is_in_group("brick") or col.is_in_group("hard_clay") or col.is_in_group("trees") or col.is_in_group("ice") or col.is_in_group("sand_dune") or col.is_in_group("hazard") or col.is_in_group("hazards") or col.is_in_group("obstacle") or col.is_in_group("destructible"):
		if col.has_method("take_hit"):
			col.take_hit(99)
		elif col.has_method("detonate"):
			col.detonate()
		elif col.has_method("take_damage"):
			col.take_damage(99)
		else:
			VFXAnimator.spawn_clay_debris(get_parent(), col.global_position)
			col.queue_free()
		SoundManager.play_hit_brick(get_tree())
		return true

	# 2. 钢铁墙体 (非边界) —— 粉碎者可硬生生碾破钢墙！
	if col.is_in_group("steel") and not col.is_in_group("border") and not col.is_in_group("buildings") and not col.is_in_group("building"):
		VFXAnimator.spawn_shockwave(get_parent(), col.global_position)
		SoundManager.play_hit_steel(get_tree())
		col.queue_free()
		return true

	# 3. 各种防御建筑 (防御塔、电墙、强化墙、维修站、护盾站、风力涡轮、路灯、油桶、滑轮墙、地雷、定时炸弹等)
	if col.is_in_group("buildings") or col.is_in_group("building") or col.is_in_group("landmines") or col.is_in_group("landmine") or col.is_in_group("oil_barrel") or col.is_in_group("timed_bomb"):
		VFXAnimator.spawn_shockwave(get_parent(), col.global_position)
		SoundManager.play_hit_steel(get_tree())
		if col.has_method("destroy"):
			col.destroy()
		elif col.has_method("detonate"):
			col.detonate()
		elif col.has_method("take_damage"):
			col.take_damage(999)
		elif col.has_method("take_hit"):
			col.take_hit(99)
		else:
			col.queue_free()
		return true

	# 4. 玩家坦克与车厢 (P1/P2/Train Carriage)
	if col.is_in_group("player") or col.is_in_group("p1") or col.is_in_group("p2") or col.is_in_group("player_carriage"):
		VFXAnimator.spawn_shockwave(get_parent(), col.global_position)
		SoundManager.play_hit_steel(get_tree())
		if col.has_method("take_damage"):
			col.take_damage(4)
		if col.has_method("stun"):
			col.stun(1.2)
		return true

	# 5. 基地老鹰
	if col.is_in_group("base") or col.is_in_group("base_eagle"):
		if col.has_method("destroy"):
			col.destroy()
		elif col.has_method("take_damage_hit"):
			col.take_damage_hit()
		elif col.has_method("take_damage"):
			col.take_damage(999)
		return true

	return false

func _choose_new_direction() -> void:
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var weights = [1.0, 3.0, 2.0, 2.0] # 倾向于向下推进
	var total_w = 8.0
	var r = randf() * total_w
	var accum = 0.0
	var chosen = Vector2.DOWN
	for i in range(dirs.size()):
		accum += weights[i]
		if r <= accum:
			chosen = dirs[i]
			break

	facing_direction = chosen
	rotation = facing_direction.angle() + PI / 2.0

func _shoot() -> void:
	if not bullet_scene:
		return

	var muzzle_pos = global_position + facing_direction * 26.0

	if enemy_type == EnemyType.BOSS:
		# Twin Super Siege Cannons Firing
		var right_vec = facing_direction.rotated(PI / 2.0)
		for side in [-1.0, 1.0]:
			var b = bullet_scene.instantiate()
			b.direction = facing_direction
			b.speed = 460.0
			b.damage = 1
			b.can_destroy_steel = true
			b.shooter = self
			b.shooter_type = "enemy"
			get_parent().add_child(b)
			var m_pos = global_position + facing_direction * 30.0 + right_vec * (side * 8.0)
			b.global_position = m_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), m_pos, rotation)
		
		# Boss occasional homing missile barrage
		if randf() < 0.35:
			var target = _find_target()
			if target:
				var mb = bullet_scene.instantiate()
				mb.direction = facing_direction
				mb.speed = 320.0
				mb.damage = 2
				mb.is_homing = true
				mb.target = target
				mb.shooter = self
				mb.shooter_type = "enemy"
				get_parent().add_child(mb)
				mb.global_position = global_position + facing_direction * 32.0
	elif enemy_type == EnemyType.MISSILE:
		var target = _find_player_target()
		var target_pos = target.global_position if target else (global_position + facing_direction * 180.0)
		var strike_scene = load("res://scenes/missile_strike.tscn")
		if strike_scene:
			var strike = strike_scene.instantiate()
			strike.team = "enemy"
			strike.aim_duration = 1.8 # 1.8s telegraph with shrinking reticle gives players time to dodge!
			strike.damage = 2
			get_parent().add_child(strike)
			strike.global_position = target_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
	elif enemy_type == EnemyType.BOMBER:
		var bomb_scene = load("res://scenes/timed_bomb.tscn")
		if bomb_scene:
			var bomb = bomb_scene.instantiate()
			bomb.team = "enemy"
			bomb.countdown = 2.4
			bomb.blast_range = 3
			bomb.damage = 3
			get_parent().add_child(bomb)
			bomb.global_position = global_position - facing_direction * 24.0
		SoundManager.play_build(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
	elif enemy_type == EnemyType.SUICIDE:
		# Suicide trucks don't shoot, they ram and explode!
		return
	elif enemy_type == EnemyType.MIRAGE:
		# Fires high-powered thermal laser from tree or tank form!
		LaserPiercer.fire_linear_laser(get_parent(), muzzle_pos, facing_direction, self, "enemy", 2)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
		if is_camouflaged:
			VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	elif enemy_type == EnemyType.BATTLESHIP:
		# Dual Heavy Naval Gun Turrets Firing AoE Explosive Shells
		var right_vec = facing_direction.rotated(PI / 2.0)
		for side in [-10.0, 10.0]:
			var b = bullet_scene.instantiate()
			b.direction = facing_direction
			b.speed = 420.0
			b.damage = 2
			b.is_aoe = true
			b.aoe_radius = 42.0
			b.can_destroy_steel = false
			b.shooter = self
			b.shooter_type = "enemy"
			get_parent().add_child(b)
			var m_pos = global_position + facing_direction * 32.0 + right_vec * side
			b.global_position = m_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), m_pos, rotation)
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
	elif enemy_type == EnemyType.AIRCRAFT:
		# Dual Forward High-Velocity Machine Guns
		var right_vec = facing_direction.rotated(PI / 2.0)
		for side in [-12.0, 12.0]:
			var b = bullet_scene.instantiate()
			b.direction = facing_direction
			b.speed = 520.0
			b.damage = 1
			b.can_destroy_steel = false
			b.shooter = self
			b.shooter_type = "enemy"
			get_parent().add_child(b)
			var m_pos = global_position + facing_direction * 24.0 + right_vec * side
			b.global_position = m_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), m_pos, rotation)
		
		# 40% chance to drop bomb while strafing
		if randf() < 0.40:
			var bomb_scene = load("res://scenes/timed_bomb.tscn")
			if bomb_scene:
				var bomb = bomb_scene.instantiate()
				bomb.team = "enemy"
				bomb.countdown = 1.5
				bomb.blast_range = 2
				bomb.damage = 3
				get_parent().add_child(bomb)
				bomb.global_position = global_position
	elif enemy_type == EnemyType.LASER:
		var tw = create_tween()
		tw.tween_property(sprite, "modulate", Color(0.2, 2.5, 3.0), 0.12)
		tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.12)
		LaserPiercer.fire_linear_laser(get_parent(), muzzle_pos, facing_direction, self, "enemy", 2)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
	elif enemy_type == EnemyType.SNIPER:
		# 超高速超远穿甲狙击弹
		var bullet = bullet_scene.instantiate()
		bullet.direction = facing_direction
		bullet.speed = 620.0
		bullet.damage = 2
		bullet.can_destroy_steel = true
		bullet.shooter = self
		bullet.shooter_type = "enemy"
		get_parent().add_child(bullet)
		bullet.global_position = muzzle_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
		SoundManager.play_shot(get_tree())
	elif enemy_type == EnemyType.GATLING:
		# 极速轻量压制机枪弹 (微小散布角度)
		var spread_angle = randf_range(-0.06, 0.06)
		var dir = facing_direction.rotated(spread_angle)
		var bullet = bullet_scene.instantiate()
		bullet.direction = dir
		bullet.speed = 380.0
		bullet.damage = 1
		bullet.can_destroy_steel = false
		bullet.shooter = self
		bullet.shooter_type = "enemy"
		get_parent().add_child(bullet)
		bullet.global_position = muzzle_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, dir.angle() + PI/2.0)
		SoundManager.play_shot(get_tree())
	elif enemy_type == EnemyType.SHOTGUN:
		# 扇形三路破片霰弹齐射 (-20°, 0°, +20°)
		for ang_deg in [-20.0, 0.0, 20.0]:
			var dir = facing_direction.rotated(deg_to_rad(ang_deg))
			var bullet = bullet_scene.instantiate()
			bullet.direction = dir
			bullet.speed = 400.0
			bullet.damage = 1
			bullet.can_destroy_steel = false
			bullet.shooter = self
			bullet.shooter_type = "enemy"
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
		SoundManager.play_shot(get_tree())
	elif enemy_type == EnemyType.SPLITTER:
		# 双联重型破甲火炮齐射
		var right_vec = facing_direction.rotated(PI / 2.0)
		for side in [-9.0, 9.0]:
			var b = bullet_scene.instantiate()
			b.direction = facing_direction
			b.speed = 420.0
			b.damage = 1
			b.can_destroy_steel = false
			b.shooter = self
			b.shooter_type = "enemy"
			get_parent().add_child(b)
			var m_pos = global_position + facing_direction * 28.0 + right_vec * side
			b.global_position = m_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), m_pos, rotation)
		VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
		SoundManager.play_shot(get_tree())
	elif enemy_type == EnemyType.SPLIT_MINI:
		var bullet = bullet_scene.instantiate()
		bullet.direction = facing_direction
		bullet.speed = 400.0
		bullet.damage = 1
		bullet.can_destroy_steel = false
		bullet.shooter = self
		bullet.shooter_type = "enemy"
		get_parent().add_child(bullet)
		bullet.global_position = muzzle_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
		SoundManager.play_shot(get_tree())
	elif enemy_type == EnemyType.CANNON:
		var bullet = bullet_scene.instantiate()
		bullet.direction = facing_direction
		bullet.shooter = self
		bullet.shooter_type = "enemy"
		if is_cannon_deployed:
			# 驻扎要塞巨炮: 超高威力 2 伤害 + 54px 范围重型高爆 AoE + 破钢穿障
			bullet.speed = 460.0
			bullet.damage = 2
			bullet.is_aoe = true
			bullet.aoe_radius = 54.0
			bullet.can_destroy_steel = true
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
			VFXAnimator.spawn_shockwave(get_parent(), muzzle_pos)
			SoundManager.play_shot(get_tree())
		else:
			# 移动巡航形态: 基础重型榴弹 (1 伤害 + 36px 范围 AoE)
			bullet.speed = 380.0
			bullet.damage = 1
			bullet.is_aoe = true
			bullet.aoe_radius = 36.0
			bullet.can_destroy_steel = false
			get_parent().add_child(bullet)
			bullet.global_position = muzzle_pos
			VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)
			SoundManager.play_shot(get_tree())
	else:
		var bullet = bullet_scene.instantiate()
		bullet.direction = facing_direction
		bullet.speed = 360.0 if enemy_type != EnemyType.POWER else 480.0
		bullet.damage = 1
		bullet.can_destroy_steel = false
		bullet.shooter = self
		bullet.shooter_type = "enemy"
		get_parent().add_child(bullet)
		bullet.global_position = muzzle_pos
		VFXAnimator.spawn_muzzle_flash(get_parent(), muzzle_pos, rotation)

	# 枪口后坐力与火花
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
	recoil_tween = create_tween()
	recoil_tween.tween_property(sprite, "position", Vector2(0, 4.0), 0.04)
	recoil_tween.tween_property(sprite, "position", Vector2.ZERO, 0.08)

func _find_target() -> Node2D:
	var candidates: Array[Node2D] = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			candidates.append(p)
	for b in get_tree().get_nodes_in_group("base_eagle"):
		if is_instance_valid(b) and not b.is_destroyed:
			candidates.append(b)

	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return candidates[0]

## Player-only variant of _find_target(), for siege units (MISSILE) that
## should hunt the tank in front of them instead of beelining the base the
## moment it's the nearest node. Falls back to _find_target() (which
## includes base_eagle) only when no player is currently alive/valid, so a
## missile truck never just sits idle with nothing to fire at.
func _find_player_target() -> Node2D:
	var players: Array[Node2D] = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			players.append(p)
	if players.is_empty():
		return _find_target()
	players.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return players[0]

func take_damage(amount: int) -> void:
	if is_shielded():
		SoundManager.play_shield_hit(get_tree())
		if is_instance_valid(shield_bubble_sprite):
			shield_bubble_sprite.modulate = Color(3.0, 3.0, 3.5, 1.0)
			var tw = create_tween()
			tw.tween_property(shield_bubble_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		return

	# 巨炮坦克驻扎要塞形态下：前展重盾与地钉咬合，防御力大幅度上升 (免伤 65%，单次受击伤害至少削减至 1)
	if enemy_type == EnemyType.CANNON and is_cannon_deployed:
		var reduced_amount = maxi(1, int(ceil(float(amount) * 0.35)))
		amount = reduced_amount
		SoundManager.play_hit_steel(get_tree())
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		var flash_tw = create_tween()
		flash_tw.tween_property(sprite, "modulate", Color(2.5, 1.8, 1.2), 0.06)
		flash_tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.08)

	health -= amount
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	# 按敌人类型追加额外特效
	if enemy_type == EnemyType.ARMOR or enemy_type == EnemyType.BOSS or enemy_type == EnemyType.CRUSHER or enemy_type == EnemyType.SPLITTER:
		VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	elif enemy_type == EnemyType.POWER:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)

	if enemy_type == EnemyType.BOSS or enemy_type == EnemyType.CRUSHER or enemy_type == EnemyType.SPLITTER:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)

	# 受击形变晃动
	var base_scale = Vector2(0.24, 0.24) if (enemy_type == EnemyType.BOSS or enemy_type == EnemyType.CRUSHER or enemy_type == EnemyType.SPLITTER or (enemy_type == EnemyType.CANNON and is_cannon_deployed)) else (Vector2(0.14, 0.14) if enemy_type == EnemyType.SPLIT_MINI else Vector2(0.196, 0.196))
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween()
	hit_tween.tween_property(sprite, "scale", base_scale * Vector2(1.3, 0.7), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(sprite, "scale", base_scale * Vector2(0.8, 1.2), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hit_tween.tween_property(sprite, "scale", base_scale, 0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if health <= 0:
		_die()

func _spawn_train_wagons() -> void:
	if not carriage_scene or not is_inside_tree():
		return
	var w1 = carriage_scene.instantiate()
	get_parent().add_child(w1)
	w1.setup(self, "enemy_gunner", true)
	
	var w2 = carriage_scene.instantiate()
	get_parent().add_child(w2)
	w2.setup(w1, "armor", true)
	
	attached_wagons = [w1, w2]

func _spawn_mirage_shimmer() -> void:
	var shim_tex = TextureHelper.get_tex("res://assets/sprites/effects/vfx_mirage_shimmer.png")
	if shim_tex:
		var shim_spr = Sprite2D.new()
		shim_spr.texture = shim_tex
		shim_spr.scale = Vector2(0.25, 0.25)
		shim_spr.z_index = 48
		get_parent().add_child(shim_spr)
		shim_spr.global_position = global_position
		var tw = shim_spr.create_tween()
		tw.tween_property(shim_spr, "scale", Vector2(0.40, 0.40), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shim_spr, "modulate:a", 0.0, 0.20)
		tw.tween_callback(shim_spr.queue_free)

func _suicide_detonate() -> void:
	if is_suicide_detonated:
		return
	is_suicide_detonated = true

	for w in attached_wagons:
		if is_instance_valid(w):
			if w.has_method("take_damage"):
				w.take_damage(999)
	attached_wagons.clear()

	# 1. 毒性爆炸 VFX —— 六帧真动画。
	# 以前这里是*一张*静态图靠 tween 缩放假装动画: 全游戏唯一一个"存在意义就是
	# 爆炸"的敌人, 反而拥有最不动的爆炸。
	#
	# 顺便去掉了叠在上面的那个通用 explosion.tscn。它现在是纯粹的减分项:
	#   - 专用爆炸更大更久, 通用那团小橘火只会糊在中间, 冲淡"绿核"这个辨识点;
	#   - explosion.gd::_ready() 自己会调一次 play_explosion(), 和下面这句撞车,
	#     同一个采样叠放两遍只会变响和相位发糊, 并不会更有气势。
	VFXAnimator.spawn_suicide_blast(get_parent(), global_position)

	SoundManager.play_explosion(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var main = get_tree().current_scene
	if main and main.has_method("add_trauma"):
		main.add_trauma(0.80)

	# 2. AoE 84px Blast Damage
	var radius = 84.0
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D and global_position.distance_to(p.global_position) <= radius:
			if p.has_method("take_damage"):
				p.take_damage(3)
	for be in get_tree().get_nodes_in_group("base_eagle"):
		if is_instance_valid(be) and not be.is_destroyed and global_position.distance_to(be.global_position) <= radius:
			be.take_damage(3)
	for b in get_tree().get_nodes_in_group("brick"):
		if is_instance_valid(b) and b is Node2D and global_position.distance_to(b.global_position) <= radius:
			if main and main.has_method("check_key_drop"):
				main.check_key_drop(b, b.global_position)
			b.queue_free()

	enemy_destroyed.emit(score_value, is_bonus, global_position)
	queue_free()

func _spawn_water_wake() -> void:
	var wake_tex = TextureHelper.get_tex("res://assets/sprites/effects/vfx_water_wake.png")
	if wake_tex:
		var w_spr = Sprite2D.new()
		w_spr.texture = wake_tex
		w_spr.rotation = rotation
		w_spr.scale = Vector2(0.20, 0.20)
		w_spr.z_index = 6
		get_parent().add_child(w_spr)
		w_spr.global_position = global_position - facing_direction * 22.0
		var tw = w_spr.create_tween()
		tw.tween_property(w_spr, "scale", Vector2(0.32, 0.32), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(w_spr, "modulate:a", 0.0, 0.25)
		tw.tween_callback(w_spr.queue_free)

func _warp_blink() -> void:
	# Same implode/relocate/pop-in technique as the Wormhole tile (wormhole.gd),
	# reused here so the Warp Phantom can self-teleport without needing an
	# actual wormhole tile nearby -- a short, unpredictable hop rather than a
	# full-map jump, so it reads as "hard to pin down" instead of arbitrary.
	var angle = randf() * TAU
	var dist = randf_range(110.0, 190.0)
	var target = global_position + Vector2(cos(angle), sin(angle)) * dist
	target.x = clampf(target.x, 48.0, 576.0)
	target.y = clampf(target.y, 48.0, 576.0)

	SoundManager.play_teleport(get_tree())
	VFXAnimator.spawn_wormhole_swirl(get_parent(), global_position)

	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(0.01, 0.01), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		global_position = target
		SoundManager.play_teleport(get_tree())
		VFXAnimator.spawn_teleport_burst(get_parent(), target)
	)
	tw.tween_property(self, "scale", Vector2(1.20, 1.20), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _die() -> void:
	if is_dying:
		return
	is_dying = true
	if is_instance_valid(plane_shadow):
		plane_shadow.queue_free()

	if enemy_type == EnemyType.SUICIDE:
		_suicide_detonate()
		return

	for w in attached_wagons:
		if is_instance_valid(w):
			if w.has_method("take_damage"):
				w.take_damage(999)
	attached_wagons.clear()

	if explosion_scene:
		var exp_inst = explosion_scene.instantiate()
		get_parent().add_child(exp_inst)
		exp_inst.global_position = global_position

	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	if enemy_type == EnemyType.ARMOR or enemy_type == EnemyType.POWER or enemy_type == EnemyType.TRAIN_BOSS:
		VFXAnimator.spawn_shockwave(get_parent(), global_position)
		# Delayed second shockwave for dramatic heavy-tank destruction
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(get_parent()):
				VFXAnimator.spawn_shockwave(get_parent(), global_position)
		)

	if coin_scene and randf() < 0.4:
		var coin = coin_scene.instantiate()
		var spawn_parent = get_parent()
		coin.position = spawn_parent.to_local(global_position)
		coin.value = gold_value
		spawn_parent.call_deferred("add_child", coin)

	if enemy_type == EnemyType.SPLITTER:
		_split_into_mini_tanks()

	if enemy_type == EnemyType.FIREWALL:
		for fire in firewall_trail_queue:
			if is_instance_valid(fire) and fire.has_method("fade_out_and_destroy"):
				fire.fade_out_and_destroy()
		firewall_trail_queue.clear()

	enemy_destroyed.emit(score_value, is_bonus, global_position)
	queue_free()

func _split_into_mini_tanks() -> void:
	if not is_inside_tree() or get_parent() == null:
		return

	# 4 个对角线方向向外弹射
	var spawn_dirs = [
		Vector2(-1.0, -1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(1.0, 1.0).normalized()
	]

	var enemy_scene = load("res://scenes/enemy.tscn")
	if not enemy_scene:
		return

	VFXAnimator.spawn_shockwave(get_parent(), global_position)

	for dir in spawn_dirs:
		var mini_tank = enemy_scene.instantiate()
		mini_tank.enemy_type = EnemyType.SPLIT_MINI
		mini_tank.facing_direction = dir
		mini_tank.rotation = dir.angle() + PI / 2.0
		get_parent().add_child(mini_tank)

		var target_pos = global_position + dir * 28.0
		target_pos.x = clampf(target_pos.x, 32.0, 592.0)
		target_pos.y = clampf(target_pos.y, 32.0, 592.0)
		mini_tank.global_position = target_pos

		VFXAnimator.spawn_dust_puff(get_parent(), target_pos)
		VFXAnimator.spawn_clay_debris(get_parent(), target_pos)

func get_points() -> int:
	return score_value

func get_xp() -> int:
	return xp_value

func get_gold() -> int:
	return gold_value

func on_enter_sand() -> void:
	sand_overlap_count += 1
	is_on_sand = true

func on_exit_sand() -> void:
	sand_overlap_count = max(0, sand_overlap_count - 1)
	is_on_sand = (sand_overlap_count > 0)

func on_enter_ice() -> void:
	ice_overlap_count += 1
	is_on_ice = true

func on_exit_ice() -> void:
	ice_overlap_count = max(0, ice_overlap_count - 1)
	is_on_ice = (ice_overlap_count > 0)

func _perform_engineer_build() -> void:
	if not is_inside_tree() or get_parent() == null:
		return

	# 获取游戏主场景与容器
	var tree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	var main_node = tree.current_scene
	var actors_container = main_node.get_node_or_null("GameArea/ActorsContainer")
	if actors_container == null:
		actors_container = get_parent()

	# 在周围寻找合法的 48x48 格子 (8 方向随机选空格)
	var offsets = [
		Vector2(-48, 0), Vector2(48, 0), Vector2(0, -48), Vector2(0, 48),
		Vector2(-48, -48), Vector2(48, -48), Vector2(-48, 48), Vector2(48, 48)
	]
	offsets.shuffle()

	var target_pos: Vector2 = Vector2.ZERO
	var found_pos := false

	var space_state = get_world_2d().direct_space_state
	for off in offsets:
		var check_p = global_position + off
		# 约束在游戏区网格范围 [48, 576]
		if check_p.x < 48.0 or check_p.x > 576.0 or check_p.y < 48.0 or check_p.y > 576.0:
			continue
		# 避开鹰巢核心区 (底部中心)
		if check_p.y > 520.0 and check_p.x >= 240.0 and check_p.x <= 384.0:
			continue

		# 检测是否有物理碰撞体占用
		var query = PhysicsPointQueryParameters2D.new()
		query.position = check_p
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.collision_mask = 1 | 2 | 16
		var result = space_state.intersect_point(query, 1)
		if result.is_empty():
			target_pos = check_p
			found_pos = true
			break

	if not found_pos:
		return

	# 随机建造地形或建筑 (0..9)
	var choice = randi() % 10
	var spawned_node: Node2D = null

	match choice:
		0: # 砖墙
			if main_node.has_method("_spawn_tile"):
				main_node._spawn_tile("brick", target_pos)
		1: # 钢墙
			if main_node.has_method("_spawn_tile"):
				main_node._spawn_tile("steel", target_pos)
		2: # 硬黏土
			if main_node.has_method("_spawn_tile"):
				main_node._spawn_tile("hard_clay", target_pos)
		3: # 反坦克地雷
			if main_node.has_method("_spawn_tile"):
				main_node._spawn_tile("landmine", target_pos)
		4: # 导流管道
			var pipe_scene = load("res://scenes/buildings/pipe_conduit.tscn")
			if pipe_scene:
				var pipe = pipe_scene.instantiate()
				pipe.position = target_pos
				if pipe.has_method("set_orientation"):
					pipe.set_orientation(randi() % 4)
				actors_container.add_child(pipe)
				spawned_node = pipe
		5: # 爆破油桶
			var barrel_scene = load("res://scenes/buildings/oil_barrel.tscn")
			if barrel_scene:
				var barrel = barrel_scene.instantiate()
				barrel.position = target_pos
				actors_container.add_child(barrel)
				spawned_node = barrel
		6: # 敌方护盾塔
			var shield_scene = load("res://scenes/buildings/enemy_shield_tower.tscn")
			if shield_scene:
				var tower = shield_scene.instantiate()
				tower.position = target_pos
				actors_container.add_child(tower)
				spawned_node = tower
		7: # EMP电磁塔
			var emp_scene = load("res://scenes/buildings/emp_tower.tscn")
			if emp_scene:
				var emp = emp_scene.instantiate()
				emp.position = target_pos
				actors_container.add_child(emp)
				spawned_node = emp
		8: # 简易狙击碉堡
			var nest_scene = load("res://scenes/buildings/sniper_nest.tscn")
			if nest_scene:
				var nest = nest_scene.instantiate()
				nest.position = target_pos
				if nest.has_method("set_fire_direction"):
					var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
					nest.set_fire_direction(dirs[randi() % dirs.size()])
				actors_container.add_child(nest)
				spawned_node = nest
		9: # 战术防御堡垒
			var bunker_scene = load("res://scenes/buildings/bunker.tscn")
			if bunker_scene:
				var bunker = bunker_scene.instantiate()
				bunker.position = target_pos
				if bunker.has_method("set_facing"):
					bunker.set_facing(randi() % 4)
				actors_container.add_child(bunker)
				spawned_node = bunker

	# 施工反馈：音效、扬尘与弹性弹出动效
	SoundManager.play_build(get_tree())
	VFXAnimator.spawn_dust_puff(actors_container, target_pos)
	if is_instance_valid(spawned_node):
		spawned_node.scale = Vector2(0.1, 0.1)
		var tw = spawned_node.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(spawned_node, "scale", Vector2(1.0, 1.0), 0.35)

func _check_and_trigger_spider_jump() -> void:
	if not is_inside_tree() or get_world_2d() == null or is_leaping or is_dying:
		return

	var space_state = get_world_2d().direct_space_state
	var forward_dir = facing_direction
	if forward_dir == Vector2.ZERO:
		forward_dir = Vector2.DOWN

	var pos_obstacle = global_position + forward_dir * 48.0 # 前方第 1 格 (阻挡物)
	var pos_landing  = global_position + forward_dir * 96.0 # 前方第 2 格 (落地空地)

	# 1. 落地范围必须在游戏区边界内 [48, 576]
	if pos_landing.x < 48.0 or pos_landing.x > 576.0 or pos_landing.y < 48.0 or pos_landing.y > 576.0:
		return

	# 2. 检测前方第 1 格是否有阻挡物 (墙体/水/建筑/静态阻挡)
	var q_obs = PhysicsPointQueryParameters2D.new()
	q_obs.position = pos_obstacle
	q_obs.collide_with_bodies = true
	q_obs.collide_with_areas = true
	q_obs.collision_mask = 1 | 2 | 16
	var obs_hits = space_state.intersect_point(q_obs, 2)
	if obs_hits.is_empty():
		return # 前方无阻挡物，直接正常行走即可

	# 3. 检测前方第 2 格是否是合法落脚空地
	var q_land = PhysicsPointQueryParameters2D.new()
	q_land.position = pos_landing
	q_land.collide_with_bodies = true
	q_land.collide_with_areas = true
	q_land.collision_mask = 1 | 2 | 16
	var land_hits = space_state.intersect_point(q_land, 2)
	var is_blocked = false
	for h in land_hits:
		var col = h.collider
		if col and (col.is_in_group("brick") or col.is_in_group("steel") or col.is_in_group("buildings") or col.is_in_group("water") or col.is_in_group("base_eagle")):
			is_blocked = true
			break

	if is_blocked:
		return # 落地格也是死路，不可跳

	# 触发跳跃！
	_start_spider_leap(pos_landing)

func _start_spider_leap(target_landing_pos: Vector2) -> void:
	is_leaping = true
	jump_cooldown_timer = JUMP_COOLDOWN

	# 1. 蓄力蹲伏阶段 (0.12s)
	SoundManager.play_shot(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

	var crouch_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	crouch_tw.tween_property(sprite, "scale", Vector2(1.25, 0.75), 0.10)
	crouch_tw.tween_property(sprite, "modulate", Color(2.0, 1.2, 2.4), 0.10)

	await crouch_tw.finished
	if not is_instance_valid(self) or is_dying:
		return

	# 2. 腾空飞跃阶段 (0.45s 滞空)
	set_collision_layer_value(2, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	set_collision_mask_value(5, false)

	# 创建地面投影阴影
	if not is_instance_valid(leap_shadow):
		leap_shadow = Sprite2D.new()
		leap_shadow.texture = sprite.texture
		leap_shadow.modulate = Color(0, 0, 0, 0.45)
		leap_shadow.z_index = -1
		get_parent().add_child(leap_shadow)
		leap_shadow.global_position = global_position
		leap_shadow.rotation = rotation

	var leap_duration = 0.45

	# 抛物线位移 + 缩放放大模拟 3D 腾空
	var leap_tw = create_tween().set_parallel(true)
	leap_tw.tween_property(self, "global_position", target_landing_pos, leap_duration).set_trans(Tween.TRANS_LINEAR)

	if is_instance_valid(leap_shadow):
		leap_tw.tween_property(leap_shadow, "global_position", target_landing_pos, leap_duration).set_trans(Tween.TRANS_LINEAR)
		leap_tw.tween_property(leap_shadow, "scale", Vector2(0.65, 0.65), leap_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		leap_tw.tween_property(leap_shadow, "scale", Vector2(1.0, 1.0), leap_duration * 0.5).set_delay(leap_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 高空缩放 (1.0 -> 1.45 -> 1.0) 呈现离地跃向镜头的立体视觉！
	leap_tw.tween_property(sprite, "scale", Vector2(1.45, 1.45), leap_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	leap_tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), leap_duration * 0.5).set_delay(leap_duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	leap_tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), leap_duration * 0.3)

	await leap_tw.finished

	if is_instance_valid(leap_shadow):
		leap_shadow.queue_free()
		leap_shadow = null

	if not is_instance_valid(self) or is_dying:
		return

	# 3. 落地重踏与震撼演出
	global_position = target_landing_pos
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(5, true)

	is_leaping = false

	# 落地弹性回弹 (Elastic Bounce)
	sprite.scale = Vector2(1.3, 0.7)
	var land_tw = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	land_tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.35)

	# 落地冲击波、扬尘、黏土破片与屏幕微震
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var tree = get_tree()
	if tree and tree.current_scene and tree.current_scene.has_method("add_trauma"):
		tree.current_scene.add_trauma(0.16)

func _drop_firewall_hazard() -> void:
	if not is_inside_tree() or is_dying:
		return
	var hazard_scene = load("res://scenes/buildings/firewall_hazard.tscn")
	if not hazard_scene:
		return

	var fire = hazard_scene.instantiate() as Node2D
	var drop_pos = global_position - facing_direction * 22.0
	fire.global_position = drop_pos

	var parent_container = get_parent()
	if parent_container:
		parent_container.add_child(fire)
		firewall_trail_queue.append(fire)
		last_firewall_drop_pos = global_position

		# 维护最多 10 格火墙队列 (FIFO)，超过时最老的一格自然熄灭
		if firewall_trail_queue.size() > MAX_FIREWALL_TRAIL_LENGTH:
			var oldest_fire = firewall_trail_queue.pop_front()
			if is_instance_valid(oldest_fire) and oldest_fire.has_method("fade_out_and_destroy"):
				oldest_fire.fade_out_and_destroy()

func _process_hunter_ambush_behavior(delta: float) -> void:
	if is_dying:
		return

	if ambush_cooldown > 0.0:
		ambush_cooldown -= delta

	# 1. 如果正在草丛潜伏中
	if is_in_ambush:
		# 保持草丛半透明伪装
		sprite.modulate = Color(0.85, 1.15, 0.85, 0.35)

		# 伏击触发判定：检测附近路过的玩家
		var target_player = _get_closest_player()
		if is_instance_valid(target_player):
			var to_player = target_player.global_position - global_position
			var dist = to_player.length()

			# 玩家进入伏击警戒圈 (<= 200px) 且在十字视线内 (横向或纵向对齐 <= 28px) 或近身 (<= 48px)
			if dist <= 200.0 and (absf(to_player.x) <= 28.0 or absf(to_player.y) <= 28.0 or dist <= 48.0):
				_trigger_hunter_ambush_strike(target_player)
		return

	# 2. 尚未潜伏：定期搜寻最近草丛
	ambush_check_timer -= delta
	if ambush_check_timer <= 0.0:
		ambush_check_timer = 0.5
		if ambush_cooldown <= 0.0:
			hunter_target_bush_pos = _find_nearest_jungle_tile()

	# 3. 若找到草丛目标且不在冷却中，导航朝草丛移动
	if hunter_target_bush_pos != Vector2.INF and ambush_cooldown <= 0.0:
		var diff = hunter_target_bush_pos - global_position
		if diff.length() <= 16.0:
			# 进驻草丛！
			is_in_ambush = true
			global_position = hunter_target_bush_pos
			sprite.modulate = Color(0.85, 1.15, 0.85, 0.35)
		else:
			# 选择朝向草丛的主轴方向 (4 向移动)
			if absf(diff.x) > absf(diff.y):
				facing_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
			else:
				facing_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
			rotation = facing_direction.angle() - PI / 2.0
	else:
		# 没有草丛或处于冷却，完全恢复为普通坦克逻辑与完全不透明度
		is_in_ambush = false
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _trigger_hunter_ambush_strike(target_player: Node2D) -> void:
	if not is_instance_valid(target_player):
		return

	# 瞄准玩家
	var diff = target_player.global_position - global_position
	if absf(diff.x) > absf(diff.y):
		facing_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
	else:
		facing_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
	rotation = facing_direction.angle() - PI / 2.0

	# 破隐高亮与声光警示
	is_in_ambush = false
	ambush_cooldown = 3.5 # 伏击后冷却
	sprite.modulate = Color(2.5, 0.5, 0.5, 1.0)
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)

	# 立即开火
	_shoot()
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)

func _find_nearest_jungle_tile() -> Vector2:
	var tree_nodes = get_tree().get_nodes_in_group("trees")
	if tree_nodes.is_empty():
		return Vector2.INF

	var nearest_pos: Vector2 = Vector2.INF
	var min_dist: float = INF

	for node in tree_nodes:
		if is_instance_valid(node) and node is Node2D:
			var d = global_position.distance_to(node.global_position)
			if d < min_dist:
				min_dist = d
				nearest_pos = node.global_position

	return nearest_pos

func _get_closest_player() -> Node2D:
	var players: Array[Node2D] = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D:
			players.append(p)
	if players.is_empty():
		return null
	players.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return players[0]

func _start_sandworm_burrow() -> void:
	if not is_inside_tree() or is_dying or is_burrowing or is_burrowed:
		return

	is_burrowing = true

	# 1. 钻地前兆：沙尘碎屑扬起、车身收缩下潜入地表
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var burrow_tw = create_tween().set_parallel(true)
	burrow_tw.tween_property(sprite, "scale:y", 0.05, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	burrow_tw.tween_property(sprite, "modulate:a", 0.0, 0.35)

	await burrow_tw.finished

	if not is_instance_valid(self) or is_dying:
		return

	# 完全潜入地下：关闭碰撞层（避弹无敌）
	is_burrowed = true
	is_burrowing = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(1, false)

	# 2. 在地下潜行等待 (1.2 秒)，计算目标破土空地
	await get_tree().create_timer(1.2).timeout

	if not is_instance_valid(self) or is_dying:
		return

	var target_pos = _find_valid_burrow_target_pos()

	# 3. 目标地点沙尘翻滚预警 (0.35 秒)
	VFXAnimator.spawn_dust_puff(get_parent(), target_pos)
	await get_tree().create_timer(0.35).timeout

	if not is_instance_valid(self) or is_dying:
		return

	# 4. 破土而出！(Breach Emerge)
	global_position = target_pos
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	is_burrowed = false
	burrow_timer = BURROW_INTERVAL

	# 恢复朝向面对玩家
	var player = _get_closest_player()
	if is_instance_valid(player):
		var diff = player.global_position - global_position
		if absf(diff.x) > absf(diff.y):
			facing_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		else:
			facing_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
		rotation = facing_direction.angle() - PI / 2.0

	# 破土弹出动画
	sprite.scale = Vector2(0.2, 0.2)
	sprite.modulate = Color(2.2, 1.6, 0.6, 1.0)
	var emerge_tw = create_tween().set_parallel(true)
	emerge_tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	emerge_tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)

	# 破土声光与震波
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	VFXAnimator.spawn_clay_debris(get_parent(), global_position)

	var tree = get_tree()
	if tree and tree.current_scene and tree.current_scene.has_method("add_trauma"):
		tree.current_scene.add_trauma(0.18)

	# 破土瞬间突袭发射子弹！
	_shoot()

func _find_valid_burrow_target_pos() -> Vector2:
	var space_state = get_world_2d().direct_space_state if (is_inside_tree() and get_world_2d()) else null
	var player = _get_closest_player()

	# 候选网格尝试（在 13x13 范围或玩家周围 3~6 格内随机挑选）
	for _attempt in range(12):
		var candidate_col: int
		var candidate_row: int

		if is_instance_valid(player) and randf() < 0.7:
			# 围绕玩家周围 3~5 格探测
			var p_col = int(player.global_position.x / 48.0)
			var p_row = int(player.global_position.y / 48.0)
			candidate_col = clampi(p_col + randi_range(-4, 4), 1, 11)
			candidate_row = clampi(p_row + randi_range(-4, 4), 1, 10)
		else:
			# 全图随机合法空地
			candidate_col = randi_range(1, 11)
			candidate_row = randi_range(1, 10)

		# 避开老鹰基地保护区 (row 11..12, col 5..7)
		if candidate_row >= 11 and candidate_col >= 5 and candidate_col <= 7:
			continue

		var candidate_pos = Vector2((candidate_col + 0.5) * 48.0, (candidate_row + 0.5) * 48.0)

		# 碰撞检测确认空格无障碍阻挡
		if space_state:
			var query = PhysicsPointQueryParameters2D.new()
			query.position = candidate_pos
			query.collision_mask = 1 | 2 | 16
			query.collide_with_bodies = true
			var hits = space_state.intersect_point(query, 1)
			if hits.is_empty():
				return candidate_pos
		else:
			return candidate_pos

	return global_position + Vector2(randf_range(-96, 96), randf_range(-96, 96))

# =========================================================================
# 15. 巨炮坦克变形要塞固定炮机制 (Colossus Siege Cannon Deployed Mode)
# =========================================================================
func _process_cannon_siege_behavior(delta: float) -> void:
	var player = _find_player_target()
	if not is_instance_valid(player):
		return

	var dist = global_position.distance_to(player.global_position)
	if not is_cannon_deployed:
		# 离玩家接近（4格内）主动变形驻扎为固定要塞炮
		if dist <= CANNON_DEPLOY_DIST:
			_deploy_cannon_siege_mode()
	else:
		# 驻扎固定炮形态：炮口紧密瞄准锁定玩家方位
		var diff = player.global_position - global_position
		if absf(diff.x) > absf(diff.y):
			facing_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		else:
			facing_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
		rotation = facing_direction.angle() + PI / 2.0

		# 玩家远遁脱离射程时延时收起驻扎恢复巡航
		if dist > CANNON_UNDEPLOY_DIST:
			cannon_undeploy_timer += delta
			if cannon_undeploy_timer >= CANNON_UNDEPLOY_DELAY:
				_undeploy_cannon_siege_mode()
		else:
			cannon_undeploy_timer = 0.0

func _deploy_cannon_siege_mode() -> void:
	if is_cannon_deployed:
		return
	is_cannon_deployed = true
	cannon_undeploy_timer = 0.0
	tank_frames = cannon_deploy_frames
	fire_interval = 1.6 # 驻扎后攻城重炮速射压制
	fire_timer = 0.3 # 变形完成迅速进入射击准备
	SoundManager.play_build(get_tree())
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_shockwave(get_parent(), global_position)
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.24, 0.24), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _undeploy_cannon_siege_mode() -> void:
	if not is_cannon_deployed:
		return
	is_cannon_deployed = false
	tank_frames = cannon_mobile_frames
	fire_interval = 2.4
	SoundManager.play_hit_steel(get_tree())
	VFXAnimator.spawn_dust_puff(get_parent(), global_position)
	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.20, 0.20), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)





