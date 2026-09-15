class_name BalanceLog
extends RefCounted

## 平衡性数据的落盘器 —— 把每次调试/测试跑出来的数值写成 JSONL, 交给
## tools/analyze_balance_log.py 做分布统计。
##
## 为什么要有这个东西: 这个项目的调参常数散在五个文件里 (enemy.gd 的
## _setup_tank_type、main.gd 的 ENEMY_MIN_FLOOR 与 start_game、rpg_manager.gd
## 的等级曲线、shop_dialog.gd 的价格表、event_dialog.gd 的事件产出), 而且是
## 相乘关系。历史上好几个严重失衡 —— 一发秒杀率 100%、幕内强度十层不动、
## 门禁把 roll 表砸成 62% FAST —— 每一个单看常数都合理, 只有**测**出来才看得见。
## 每次改完手动跑一遍再肉眼看输出, 是记不住上一次是多少的; 落盘之后才谈得上
## "这次改动把秒杀率从 38% 压到了 21%", 以及"这一层的血量分布到底是不是正态"。
##
## 格式: 每个 category 一个 .jsonl, 一行一条记录, 永远追加不覆盖。JSONL 而不是
## CSV, 是因为不同 category 的字段集不一样, 而且以后加字段不能让旧行失效。
##
## 落盘位置优先 res://logs/balance/ (就在仓库里, 方便直接看和 diff), 打不开时
## 退到 user://logs/balance/。logs/ 已在 .gitignore 里 —— 日志是本地测量记录,
## 不是仓库资产。

const DIR_PRIMARY := "res://logs/balance"
const DIR_FALLBACK := "user://logs/balance"

static var _dir: String = ""
static var _session: String = ""
static var _commit: String = ""
static var _enabled: int = -1  # -1=未决定, 0=关, 1=开
static var _counts: Dictionary = {}


## 关闭开关: 导出的正式包不写, 环境变量 TANK_BALANCE_LOG=0 也能强制关掉
## (跑性能剖析或者不想污染日志的时候用)。
static func is_enabled() -> bool:
	if _enabled == -1:
		if OS.get_environment("TANK_BALANCE_LOG") == "0":
			_enabled = 0
		elif OS.has_feature("editor") or OS.is_debug_build():
			_enabled = 1
		else:
			_enabled = 0
	return _enabled == 1


## 本次进程的标识。**不能用 randi()** —— 每日挑战会先 seed() 再依赖全局 RNG
## 流的确定性 (main.gd::start_game), 在任意时刻从那条流里抽一个数就会让同一天
## 的挑战不再一致。用微秒时钟, 不碰 RNG。
static func session_id() -> String:
	if _session == "":
		_session = "%d_%03d" % [
			int(Time.get_unix_time_from_system()),
			int(Time.get_ticks_usec()) % 1000,
		]
	return _session


## 当前 HEAD 的短 sha, 用来把某一批数据钉死在某次提交上 —— 没有这个, 隔几天
## 回头看日志就分不清"这批是改之前还是改之后跑的"。
static func commit() -> String:
	if _commit != "":
		return _commit
	_commit = "unknown"
	var root_dir := ProjectSettings.globalize_path("res://")
	var head := FileAccess.open(root_dir.path_join(".git/HEAD"), FileAccess.READ)
	if head == null:
		return _commit
	var line := head.get_line().strip_edges()
	head.close()
	if line.begins_with("ref: "):
		var ref_path := root_dir.path_join(".git/" + line.substr(5))
		var rf := FileAccess.open(ref_path, FileAccess.READ)
		if rf != null:
			line = rf.get_line().strip_edges()
			rf.close()
		else:
			# packed-refs: 分支被打包过就没有独立的 ref 文件了
			var pf := FileAccess.open(root_dir.path_join(".git/packed-refs"), FileAccess.READ)
			if pf != null:
				var want := line.substr(5)
				while not pf.eof_reached():
					var l := pf.get_line().strip_edges()
					if l.ends_with(" " + want):
						line = l.split(" ")[0]
						break
				pf.close()
	if line.length() >= 7 and not line.begins_with("ref: "):
		_commit = line.substr(0, 10)
	return _commit


static func _ensure_dir() -> String:
	if _dir != "":
		return _dir
	for d in [DIR_PRIMARY, DIR_FALLBACK]:
		var abs := ProjectSettings.globalize_path(d)
		if DirAccess.make_dir_recursive_absolute(abs) == OK or DirAccess.dir_exists_absolute(abs):
			_dir = abs
			return _dir
	_dir = "unavailable"
	return _dir


## 追加一条记录。fields 里的键会和公共元数据合并; 公共元数据用 `_` 前缀,
## 这样业务字段永远不会被元数据顶掉。
static func emit(category: String, fields: Dictionary) -> void:
	if not is_enabled():
		return
	var d := _ensure_dir()
	if d == "unavailable":
		return

	var row := {
		"_ts": Time.get_datetime_string_from_system(true),
		"_session": session_id(),
		"_commit": commit(),
		"_cat": category,
	}
	for k in fields:
		row[str(k)] = fields[k]

	var path := d.path_join(category + ".jsonl")
	# Godot 没有 APPEND 模式: READ_WRITE 打开已存在的文件再 seek_end,
	# 文件不存在时 READ_WRITE 会返回 null, 这时才用 WRITE 新建。
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(row))
	f.close()

	_counts[category] = int(_counts.get(category, 0)) + 1


## 批量写, 给采样探针用 —— 几千行逐条 open/close 会慢得离谱。
static func emit_batch(category: String, rows: Array) -> void:
	if not is_enabled() or rows.is_empty():
		return
	var d := _ensure_dir()
	if d == "unavailable":
		return

	var ts := Time.get_datetime_string_from_system(true)
	var sid := session_id()
	var sha := commit()
	var buf := PackedStringArray()
	for r in rows:
		var row := {"_ts": ts, "_session": sid, "_commit": sha, "_cat": category}
		for k in r:
			row[str(k)] = r[k]
		buf.append(JSON.stringify(row))

	var path := d.path_join(category + ".jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string("\n".join(buf) + "\n")
	f.close()

	_counts[category] = int(_counts.get(category, 0)) + rows.size()


static func summary() -> String:
	if not is_enabled():
		return "[balance-log] 已关闭"
	if _counts.is_empty():
		return "[balance-log] 本次没有写入任何记录"
	var parts := PackedStringArray()
	for k in _counts:
		parts.append("%s=%d" % [k, int(_counts[k])])
	return "[balance-log] %s -> %s" % [" ".join(parts), _ensure_dir()]
