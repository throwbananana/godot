class_name BuildingIdleAnim
extends RefCounted

## 有源建筑的待机循环播放器 (雷达站 / EMP 塔 / 工厂)。
##
## 帧由 tools/build_building_idle_anims.py 渲出, 命名 `<资源名>_f0..f5.png`。
##
## === 为什么单独抽一个 helper, 而不是在三个脚本里各写一遍 ===
##
## 三处逐帧推进的代码长得一模一样, 而这个仓库反复吃过"同一段逻辑抄了三份然后
## 慢慢漂移"的亏 (见 CLAUDE.md 里 sokpop_common / KineticPushHelper 那几段)。
## 更要紧的是下面这两条 "不能用 _process" 和 "不能用 randi()" 的理由都很不
## 直观, 抄三份就等于把这两个坑也埋三个地方。
##
## === 为什么用 Tween 而不是 _process ===
##
## 联机时, 客户端上由玩家建造的建筑是 NetSession.Kind.SCENE_NODE 傀儡, 而
## net_puppet.gd:58 对这类傀儡直接 `node.set_process(false)` —— 那条规矩本身
## 是对的 (一座傀儡自动炮塔如果在 _process 里开火, 会打出只有它自己客户端看得见
## 的子弹)。但它是按"逻辑"一刀切的, 待机动画是纯表现, 被一起关掉就变成: 客户端
## 上自己盖的雷达站站在那儿一动不动, 而地图自带的那座在转 —— 同一栋楼两种表现。
##
## create_tween() 挂在节点上, 由 SceneTree 统一推进, **不吃 set_process(false)**,
## 所以傀儡上照样播。base_eagle.gd 的光环呼吸早就是这么做的。
##
## 顺带: 节点被 free 时绑定的 Tween 会自动结束, 不需要额外收尾。
##
## === 起始帧要错开, 但绝不能用 randi() ===
##
## 一张图上几座同类建筑如果同相位, 会整齐划一地一起转, 读起来很假。但每日挑战
## 在 main.gd::start_game() 里给全局 RNG 播过种, 之后敌人生成一路都在从这条流上
## 取数 —— 在建筑 _ready() 里随手 randi() 一下会让当天所有人的run 不一样。
## 所以用静态计数器轮转, 和 explosion.gd 挑爆炸差分用的是同一招: 既错开了相位,
## 又保证连续两座建筑一定不同相 (真随机反而有 1/6 概率撞上)。

## 每帧 0.13 秒 —— 6 帧一循环约 0.78 秒。和 base_eagle.gd::IDLE_FRAME_TIME 取同一个
## 值: 这些都是常驻的环境动效, 比一次性特效 (0.17~0.26 秒播完 6 帧) 慢得多,
## 快了会一直勾着注意力。
const FRAME_TIME := 0.13

const DEFAULT_FRAMES := 6

## 见类注释"起始帧要错开"。静态的, 跨实例累加。
static var _stagger: int = 0


## 给 sprite 挂上待机循环。
##
## base_path 是不带 `_fN` 的完整路径, 例如
##   "res://assets/sprites/buildings/radar_station.png"
##
## alive 是一个返回 bool 的 Callable, 每帧问一次 —— 建筑炸了就别再翻帧了。
## 用回调而不是在这里猜字段名: 三个脚本的"我还活着"分别叫 is_destroyed 和
## is_destroyed_flag, 鸭子类型猜字段是下一次静默失效的来源。
##
## 帧取不到 (少于 2 张) 就原样返回 null, sprite 保持它原来的静态贴图 —— 静态图
## 一直保留正是为了这个退化路径。
static func attach(host: Node, sprite: Sprite2D, base_path: String,
		alive: Callable, n_frames: int = DEFAULT_FRAMES) -> Tween:
	if not is_instance_valid(host) or not is_instance_valid(sprite):
		return null

	var stem := base_path.trim_suffix(".png")
	var frames: Array[Texture2D] = []
	for i in range(n_frames):
		var tex := TextureHelper.get_tex("%s_f%d.png" % [stem, i])
		if tex:
			frames.append(tex)

	if frames.size() < 2:
		return null

	var idx := _stagger % frames.size()
	_stagger += 1
	sprite.texture = frames[idx]

	var tw := host.create_tween().set_loops()
	tw.tween_interval(FRAME_TIME)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(sprite) or not alive.call():
			return
		idx = (idx + 1) % frames.size()
		sprite.texture = frames[idx]
	)
	return tw
