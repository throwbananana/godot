class_name StagePreviewDialog
extends PanelContainer

const TextureHelper = preload("res://scripts/texture_helper.gd")
const SoundManager = preload("res://scripts/sound_manager.gd")
const GameState = preload("res://scripts/game_state.gd")
const UIThemeHelper = preload("res://scripts/ui_theme_helper.gd")

signal mission_started(node_id: String)
signal cancelled

@onready var title_label: Label = $VBox/Header/TitleLabel
@onready var sub_title_label: Label = $VBox/Header/SubTitleLabel

@onready var terrain_container: HBoxContainer = $VBox/Sections/TerrainSection/TerrainList
@onready var enemy_container: HBoxContainer = $VBox/Sections/EnemySection/EnemyList
@onready var drop_container: HBoxContainer = $VBox/Sections/DropSection/DropList

@onready var btn_start: Button = $VBox/Actions/StartButton
@onready var btn_cancel: Button = $VBox/Actions/CancelButton

var current_node_id: String = ""

func _ready() -> void:
	UIThemeHelper.apply_clay_panel(self, Color(0.15, 0.13, 0.17, 0.98), 16)
	UIThemeHelper.apply_icon_button(btn_start, "res://assets/sprites/ui/ui_icon_mode_continue.png", Vector2(20, 20))
	UIThemeHelper.apply_icon_button(btn_cancel, "res://assets/sprites/ui/ui_icon_mode_exit.png", Vector2(20, 20))

	btn_start.pressed.connect(_on_start_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)

func setup_preview(node_id: String) -> void:
	current_node_id = node_id
	visible = true
	var node_data = GameState.spire_nodes.get(node_id, {})
	var floor_idx = int(node_data.get("floor", GameState.current_floor))
	var n_type = str(node_data.get("type", "battle"))

	var stage_names = [
		"OUTSKIRTS PATROL (外围巡逻哨区)",
		"URBAN RUINS DEFENSE (废墟城镇阻击线)",
		"MINEFIELD CROSSING (雷区纵深交叉口)",
		"HIGH-TECH ARSENAL (高科技军备堡垒)",
		"ELITE FORTRESS CORE (精英近卫军防线)",
		"SUMMIT COLOSSUS CITADEL (巅峰要塞总决战)"
	]
	var stage_name = stage_names[clamp(floor_idx, 0, stage_names.size() - 1)]

	var c_mode = str(node_data.get("challenge_mode", "bomb_rain"))

	if n_type == "elite":
		title_label.text = "ELITE BATTLE: " + stage_name
		title_label.modulate = Color(1.0, 0.45, 0.45)
		sub_title_label.text = "THREAT LEVEL: HIGH RISK | ENEMY BATTALION: 18 HEAVY UNITS"
	elif n_type == "challenge":
		if c_mode == "bomb_rain":
			title_label.text = "AIR-DROP HAZARD (空投定时炸弹挑战): " + stage_name
			title_label.modulate = Color(1.0, 0.55, 0.25)
			sub_title_label.text = "CHALLENGE OBJECTIVE: 天空将持续空投定时高爆炸弹！巧妙走位诱敌轰杀，躲避十字爆炎！"
		elif c_mode == "night_ops":
			title_label.text = "NIGHT OPERATIONS (黑夜突袭战术挑战): " + stage_name
			title_label.modulate = Color(0.65, 0.78, 1.0)
			sub_title_label.text = "CHALLENGE OBJECTIVE: 战场陷入漆黑夜幕！仅依靠战车车灯与基地灯塔视野侦察潜伏敌军！"
		elif c_mode == "night_bombs":
			title_label.text = "NIGHTMARE RAID (暗夜空投极限防守): " + stage_name
			title_label.modulate = Color(1.0, 0.35, 0.35)
			sub_title_label.text = "CHALLENGE OBJECTIVE: 在漆黑夜幕中躲避天降定时炸弹并歼灭敌军！极限生存！"
		else:
			title_label.text = "SECRET VAULT (隐秘宝藏挑战): " + stage_name
			title_label.modulate = Color(0.98, 0.82, 0.25)
			sub_title_label.text = "CHALLENGE OBJECTIVE: 击破隐藏地块或消灭敌军寻找【金钥匙】，开启战场秘宝宝箱！"
	elif n_type == "boss":
		title_label.text = "BOSS RAID: " + stage_name
		title_label.modulate = Color(1.0, 0.85, 0.3)
		sub_title_label.text = "THREAT LEVEL: MAXIMUM DANGER | TITANIC SUMMIT COLOSSUS"
	else:
		title_label.text = "TACTICAL ENGAGEMENT: " + stage_name
		title_label.modulate = Color(0.9, 0.92, 0.98)
		var enemy_count = 12 + floor_idx * 2
		sub_title_label.text = "THREAT LEVEL: SECTOR %d | ENEMY FORCE: %d TANKS" % [floor_idx + 1, enemy_count]

	_populate_terrain(floor_idx, n_type, c_mode)
	_populate_enemies(floor_idx, n_type)
	_populate_drops(floor_idx, n_type, c_mode)

func _populate_terrain(floor_idx: int, n_type: String, c_mode: String = "") -> void:
	for child in terrain_container.get_children():
		child.queue_free()

	var terrains = []
	if n_type == "challenge":
		if c_mode in ["bomb_rain", "night_bombs"]:
			terrains.append({"name": "天降定时炸弹\n(Airdrop Bomb)", "icon": "res://assets/sprites/buildings/prop_timed_bomb.png", "desc": "高空不定期空投炸弹，十字烈焰"})
			terrains.append({"name": "连锁引爆机制\n(Chain Blast)", "icon": "res://assets/sprites/effects/flame_cross_beam.png", "desc": "子弹击中炸弹可瞬间引爆炸死敌军"})
		if c_mode in ["night_ops", "night_bombs"]:
			terrains.append({"name": "黑夜作战迷雾\n(Dark Fog)", "icon": "res://assets/sprites/map/node_challenge.png", "desc": "全图漆黑，仅车灯与基地照亮周围"})
			terrains.append({"name": "战车车灯探照\n(Headlights)", "icon": "res://assets/sprites/tiles/tile_wormhole.png", "desc": "移动与开火可照亮潜伏敌军"})
		if c_mode == "vault":
			terrains.append({"name": "隐秘秘宝箱\n(Treasure Vault)", "icon": "res://assets/sprites/powerups/gold_coin.png", "desc": "藏于地图中，金钥匙可解锁"})
			terrains.append({"name": "潜藏金钥匙\n(Golden Key)", "icon": "res://assets/sprites/powerups/star.png", "desc": "击破特定地块或消灭敌军掉落"})

	terrains.append({"name": "细分红砖墙\n(2x2 拆分破坏)", "icon": "res://assets/sprites/ui/badge_brick.png", "desc": "可部分破坏掩体"})
	terrains.append({"name": "天然钢铁要塞\n(高抗性铁壁)", "icon": "res://assets/sprites/ui/badge_steel.png", "desc": "等离子炮可击穿"})

	if floor_idx >= 1:
		terrains.append({"name": "战术水域/河流\n(阻断坦克通行)", "icon": "res://assets/sprites/tiles/tile_water_f0.png", "desc": "炮弹可飞跃"})
		terrains.append({"name": "隐蔽丛林\n(隐匿视野)", "icon": "res://assets/sprites/tiles/tile_trees.png", "desc": "天然战术掩护"})

	if floor_idx >= 2 or n_type in ["elite", "boss"]:
		terrains.append({"name": "沙漠流沙地面\n(移速降低50%)", "icon": "res://assets/sprites/ui/badge_desert.png", "desc": "流沙阻滞履带，沙漠坦加速"})
		terrains.append({"name": "风蚀沙堆掩体\n(单发整块坍塌)", "icon": "res://assets/sprites/tiles/tile_sand_dune.png", "desc": "受击瞬间整体塌陷"})
		terrains.append({"name": "反坦克雷区\n(踩踏剧烈爆炸)", "icon": "res://assets/sprites/ui/badge_mine.png", "desc": "重创坦克毁伤周围"})

	if floor_idx >= 3 or n_type in ["elite", "boss"]:
		terrains.append({"name": "激光防线\n(直线贯穿熔毁)", "icon": "res://assets/sprites/ui/badge_laser.png", "desc": "直线熔毁所有掩体"})

	for t in terrains:
		_add_badge_card(terrain_container, t["name"], t["icon"], t["desc"])

func _populate_enemies(floor_idx: int, n_type: String) -> void:
	for child in enemy_container.get_children():
		child.queue_free()

	var enemies = []
	if n_type == "boss":
		enemies.append({"name": "巅峰首领巨兽\n(Summit Boss)", "icon": "res://assets/sprites/tanks/enemy_boss_f0.png", "desc": "双联要塞火炮+导弹"})
		enemies.append({"name": "沙漠突击坦\n(Desert Tank)", "icon": "res://assets/sprites/ui/badge_desert_tank.png", "desc": "沙地极速爆发+双联快炮"})
		enemies.append({"name": "巡航导弹坦\n(Missile Tank)", "icon": "res://assets/sprites/tanks/enemy_missile_f0.png", "desc": "自动追踪导弹"})
		enemies.append({"name": "高能激光坦\n(Laser Tank)", "icon": "res://assets/sprites/tanks/enemy_laser_f0.png", "desc": "直线熔解激光"})
	elif n_type == "elite":
		enemies.append({"name": "沙漠突击坦\n(Desert Tank)", "icon": "res://assets/sprites/ui/badge_desert_tank.png", "desc": "沙地极速爆发+双联快炮"})
		enemies.append({"name": "巡航导弹坦\n(Missile Tank)", "icon": "res://assets/sprites/tanks/enemy_missile_f0.png", "desc": "自动追踪导弹"})
		enemies.append({"name": "高能激光坦\n(Laser Tank)", "icon": "res://assets/sprites/tanks/enemy_laser_f0.png", "desc": "直线熔解激光"})
		enemies.append({"name": "重型铁甲坦\n(Armor Tank)", "icon": "res://assets/sprites/tanks/enemy_armor_f0.png", "desc": "4层装甲防护"})
	else:
		if floor_idx == 0:
			enemies.append({"name": "基础轻型坦\n(Basic Recon)", "icon": "res://assets/sprites/tanks/enemy_basic_f0.png", "desc": "轻装侦察作战"})
			enemies.append({"name": "疾风突击坦\n(Fast Raider)", "icon": "res://assets/sprites/tanks/enemy_fast_f0.png", "desc": "极速突防作战"})
		elif floor_idx == 1:
			enemies.append({"name": "疾风突击坦\n(Fast Raider)", "icon": "res://assets/sprites/tanks/enemy_fast_f0.png", "desc": "极速突防作战"})
			enemies.append({"name": "重炮强袭坦\n(Power Tank)", "icon": "res://assets/sprites/tanks/enemy_power_f0.png", "desc": "高伤极速射击"})
			enemies.append({"name": "基础轻型坦\n(Basic Recon)", "icon": "res://assets/sprites/tanks/enemy_basic_f0.png", "desc": "轻装侦察作战"})
		elif floor_idx == 2:
			enemies.append({"name": "沙漠突击坦\n(Desert Tank)", "icon": "res://assets/sprites/ui/badge_desert_tank.png", "desc": "沙地极速爆发+双联快炮"})
			enemies.append({"name": "重炮强袭坦\n(Power Tank)", "icon": "res://assets/sprites/tanks/enemy_power_f0.png", "desc": "高伤极速射击"})
			enemies.append({"name": "疾风突击坦\n(Fast Raider)", "icon": "res://assets/sprites/tanks/enemy_fast_f0.png", "desc": "极速突防作战"})
		elif floor_idx >= 3:
			enemies.append({"name": "沙漠突击坦\n(Desert Tank)", "icon": "res://assets/sprites/ui/badge_desert_tank.png", "desc": "沙地极速爆发+双联快炮"})
			enemies.append({"name": "巡航导弹坦\n(Missile Tank)", "icon": "res://assets/sprites/tanks/enemy_missile_f0.png", "desc": "自动追踪导弹"})
			enemies.append({"name": "高能激光坦\n(Laser Tank)", "icon": "res://assets/sprites/tanks/enemy_laser_f0.png", "desc": "直线熔解激光"})
			enemies.append({"name": "重型铁甲坦\n(Armor Tank)", "icon": "res://assets/sprites/tanks/enemy_armor_f0.png", "desc": "4层装甲防护"})

	for e in enemies:
		_add_badge_card(enemy_container, e["name"], e["icon"], e["desc"])

func _populate_drops(floor_idx: int, n_type: String, c_mode: String = "") -> void:
	for child in drop_container.get_children():
		child.queue_free()

	var drops = []
	if n_type == "challenge":
		drops.append({"name": "挑战通关赏金\n(+150G & +100XP)", "icon": "res://assets/sprites/powerups/gold_coin.png", "desc": "通关专属高额赏金"})
		if c_mode == "vault":
			drops.append({"name": "秘宝藏宝箱\n(Treasure Chest)", "icon": "res://assets/sprites/powerups/star.png", "desc": "巨量金币与满阶军备"})

	drops.append({"name": "星级升阶\n(Star Module)", "icon": "res://assets/sprites/powerups/star.png", "desc": "火力与射速升级"})
	drops.append({"name": "反坦克雷包\n(Landmines)", "icon": "res://assets/sprites/powerups/landmine_prop.png", "desc": "布设致命陷阱"})
	drops.append({"name": "直线激光核\n(Laser Core)", "icon": "res://assets/sprites/powerups/laser_cannon_prop.png", "desc": "直线穿透熔毁"})
	drops.append({"name": "全铁化铲子\n(Steel Shovel)", "icon": "res://assets/sprites/powerups/shovel.png", "desc": "基地全铁防御"})
	drops.append({"name": "定时秒表\n(Clock Freeze)", "icon": "res://assets/sprites/powerups/clock.png", "desc": "冻结敌军时间"})
	drops.append({"name": "高额黄金赏金\n(Gold Reward)", "icon": "res://assets/sprites/powerups/gold_coin.png", "desc": "+50~180G 金币"})

	for d in drops:
		_add_badge_card(drop_container, d["name"], d["icon"], d["desc"])

func _add_badge_card(parent_container: Control, name_str: String, icon_path: String, desc_str: String) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(96, 72)
	UIThemeHelper.apply_clay_panel(card, Color(0.20, 0.18, 0.24, 0.90), 6)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(26, 26)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex = TextureHelper.get_tex(icon_path)
	if tex:
		icon_rect.texture = tex
	vbox.add_child(icon_rect)

	var lbl_name = Label.new()
	lbl_name.text = name_str
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.add_theme_font_size_override("font_size", 9)
	lbl_name.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	vbox.add_child(lbl_name)

	parent_container.add_child(card)

func _on_start_pressed() -> void:
	visible = false
	SoundManager.play_hit_steel(get_tree())
	mission_started.emit(current_node_id)

func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
