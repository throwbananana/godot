#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""平衡性日志的统计分析器 —— 读 logs/balance/*.jsonl, 出分布报告。

日志由 scripts/balance_log.gd 落盘: 采样探针 (tools/probe_balance_report.gd)、
若干 tools/test_*.gd、以及实机跑一局之后的 main.gd::_game_over() 都会往里追加。
本脚本只读不写, 只依赖 numpy。

为什么要看**分布**而不只是均值: 这个游戏的数值失衡历来不是"均值偏了", 而是
"分布塌了"。门禁把没解锁的类型一律砸成 FAST 时, floor 3 的敌人均血看着挺
正常, 实际 62% 的样本挤在同一个值上 —— 均值看不出来, 直方图一眼就看出来。
同理"一发秒杀率 100%"也是分布右侧被削平的结果。所以默认输出里, 每个指标都
带偏度 / 超额峰度 / Jarque-Bera 正态检验和一条 ASCII 直方图。

正态检验用 Jarque-Bera 而不是 Shapiro-Wilk: JB 只需要偏度和峰度, 二十行 numpy
就能算完, 不用把 scipy 拉进这套只有 numpy+Pillow 的工具链。JB 在 n>=2000 时
渐近服从 df=2 的卡方, 于是 p = exp(-JB/2)。注意小样本 (n<50) 下 JB 偏保守,
报告里会标出来。

另外要提醒的是: **这里大部分指标本来就不该是正态的**, 正态检验的用处是把
"我以为它连续"和"它其实是几个离散档位"区分开。敌人血量是 1/2/3/4/6/14 这样的
离散档, 天然多峰; 而"每幕收入"是十几层独立加起来的, 按中心极限该收敛到正态,
它要是不正态就说明某一层的权重过大 —— 那才是要查的信号。

用法:
    python tools/analyze_balance_log.py                     # 默认报告
    python tools/analyze_balance_log.py --cat enemy_roll --field hp --by floor
    python tools/analyze_balance_log.py --cat act_econ --field surplus_ratio
    python tools/analyze_balance_log.py --list              # 有哪些 category/字段
    python tools/analyze_balance_log.py --vs 3ff01d9692     # 和某次提交的数据对比
    python tools/analyze_balance_log.py --sessions          # 每次跑的会话清单
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from collections import Counter, defaultdict

import numpy as np

# Windows 控制台默认是 GBK, 直接 print 中文注释和 ▸/▇ 这类符号会 UnicodeEncodeError
# 把整个报告打断在半路。errors="replace" 保证最坏情况也只是某个符号变成 ?, 而不是
# 丢掉后面所有输出。
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(os.path.dirname(HERE), "logs", "balance")

# 默认报告看哪些指标。(category, field, by, 说明)
DEFAULT_VIEWS = [
    ("act_econ", "surplus_ratio", None,
     "全幕盈余倍率 = 收入 / 能花掉的上限。>1 就是钱花不完, 金币不再是资源"),
    ("act_econ", "income", None, "全幕收入 (最优路线, 假设金币全部捡到)"),
    ("act_econ", "shops", None, "最优路线上的商店数"),
    ("floor_econ", "stk", "bt",
     "平均几发打死一只 —— 整幕应缓慢上升; 持平就说明玩家伤害和敌人血量在并排跑"),
    ("floor_econ", "one_shot_pct", "bt",
     "一发秒杀率 —— 贴顶说明血量分层失效。整数伤害会让它上下抖, 看趋势请用 stk"),
    ("enemy_roll", "hp", "floor", "单只敌人血量 (离散档位, 看的是档位有没有被压平)"),
]


# ------------------------------------------------------------------ 载入

def load(cat: str | None = None) -> list[dict]:
    if not os.path.isdir(LOG_DIR):
        print("没有找到 %s —— 先跑一次采样探针:" % LOG_DIR)
        print("  godot --headless --path . --script tools/probe_balance_report.gd")
        sys.exit(1)
    rows: list[dict] = []
    for name in sorted(os.listdir(LOG_DIR)):
        if not name.endswith(".jsonl"):
            continue
        if cat and name != cat + ".jsonl":
            continue
        with open(os.path.join(LOG_DIR, name), "r", encoding="utf-8") as fh:
            for ln, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    # 进程被 Ctrl-C 掐断时最后一行可能是半条, 跳过而不是整份报错
                    print("  [warn] %s:%d 不是合法 JSON, 已跳过" % (name, ln))
    return rows


# ------------------------------------------------------------------ 统计

def describe(x: np.ndarray) -> dict:
    n = x.size
    mean = float(x.mean())
    # 总体标准差还是样本标准差: 用 ddof=1 (样本), 因为这些数据都是从一个
    # 更大的可能空间里抽出来的样本, 不是总体本身。
    sd = float(x.std(ddof=1)) if n > 1 else 0.0
    d = {
        "n": n, "mean": mean, "sd": sd,
        "cv": (sd / mean) if abs(mean) > 1e-12 else float("nan"),
        "min": float(x.min()), "max": float(x.max()),
    }
    for q in (10, 25, 50, 75, 90):
        d["p%d" % q] = float(np.percentile(x, q))
    if n > 2 and sd > 1e-12:
        z = (x - mean) / sd
        g1 = float((z ** 3).mean())
        g2 = float((z ** 4).mean()) - 3.0
        d["skew"] = g1
        d["kurt"] = g2
        # Jarque-Bera: n/6 * (g1^2 + g2^2/4), 渐近 chi2(df=2) -> p = exp(-JB/2)
        jb = n / 6.0 * (g1 ** 2 + (g2 ** 2) / 4.0)
        d["jb"] = jb
        d["p_value"] = math.exp(-jb / 2.0) if jb < 1400 else 0.0
    else:
        d["skew"] = d["kurt"] = d["jb"] = float("nan")
        d["p_value"] = float("nan")
    d["distinct"] = int(np.unique(x).size)
    return d


def spark(x: np.ndarray, bins: int = 24) -> str:
    """一行 ASCII 直方图。多峰/塌成一根柱子这类问题, 看这个比看均值快得多。"""
    if x.size == 0:
        return ""
    lo, hi = float(x.min()), float(x.max())
    if hi - lo < 1e-12:
        return "▇" + " (全部样本都是同一个值 %.4g)" % lo
    counts, _ = np.histogram(x, bins=bins, range=(lo, hi))
    blocks = " ▁▂▃▄▅▆▇█"
    top = counts.max()
    return "".join(blocks[min(8, int(round(c / top * 8)))] for c in counts)


def verdict(d: dict) -> str:
    """把正态检验翻译成一句人话, 顺带标注小样本与离散档位这两种误读来源。"""
    if math.isnan(d["p_value"]):
        return "样本太少, 不做判断"
    bits = []
    if d["distinct"] <= 12:
        bits.append("只有 %d 个不同取值(离散档位, 正态检验对它没意义)" % d["distinct"])
    if d["p_value"] >= 0.05:
        bits.append("不能拒绝正态 (JB=%.2f, p=%.3f)" % (d["jb"], d["p_value"]))
    else:
        shape = []
        if abs(d["skew"]) > 0.5:
            shape.append("右偏" if d["skew"] > 0 else "左偏")
        if d["kurt"] > 1.0:
            shape.append("尖峰厚尾")
        elif d["kurt"] < -1.0:
            shape.append("平顶/多峰")
        bits.append("显著偏离正态 (JB=%.1f, p=%.4f%s)"
                    % (d["jb"], d["p_value"], ", " + "+".join(shape) if shape else ""))
    if d["n"] < 50:
        bits.append("n<50, JB 偏保守")
    return "; ".join(bits)


def print_stat(label: str, x: np.ndarray, indent: str = "  ") -> None:
    d = describe(x)
    print("%s%-22s n=%-5d 均值 %9.3f  标准差 %8.3f  CV %5.2f" %
          (indent, label, d["n"], d["mean"], d["sd"], d["cv"]))
    print("%s%-22s p10 %8.3f  p50 %8.3f  p90 %8.3f  [%.3f, %.3f]" %
          (indent, "", d["p10"], d["p50"], d["p90"], d["min"], d["max"]))
    print("%s%-22s 偏度 %6.2f  超额峰度 %6.2f  %s" %
          (indent, "", d["skew"], d["kurt"], verdict(d)))
    print("%s%-22s %s" % (indent, "", spark(x)))


# ------------------------------------------------------------------ 视图

def values(rows: list[dict], cat: str, field: str) -> np.ndarray:
    out = [r[field] for r in rows
           if r.get("_cat") == cat and isinstance(r.get(field), (int, float))
           and not isinstance(r.get(field), bool)]
    return np.asarray(out, dtype=float)


def grouped(rows: list[dict], cat: str, field: str, by: str) -> dict:
    g: dict = defaultdict(list)
    for r in rows:
        if r.get("_cat") != cat:
            continue
        v = r.get(field)
        if not isinstance(v, (int, float)) or isinstance(v, bool):
            continue
        if by not in r:
            continue
        g[r[by]].append(float(v))
    return {k: np.asarray(v, dtype=float) for k, v in g.items()}


def sort_key(k):
    return (0, k) if isinstance(k, (int, float)) else (1, str(k))


def view(rows: list[dict], cat: str, field: str, by: str | None, note: str = "") -> None:
    print("\n" + "=" * 78)
    print("%s.%s%s" % (cat, field, ("  按 %s 分组" % by) if by else ""))
    if note:
        print("  ▸ %s" % note)
    print("=" * 78)
    allv = values(rows, cat, field)
    if allv.size == 0:
        print("  (没有数据)")
        return
    print_stat("全部", allv)
    if by:
        g = grouped(rows, cat, field, by)
        print("")
        for k in sorted(g.keys(), key=sort_key):
            print_stat("%s=%s" % (by, k), g[k])


def report_types(rows: list[dict]) -> None:
    """敌人类型占比 —— 这个不是连续量, 用频次表而不是分布统计。"""
    per_floor: dict = defaultdict(Counter)
    for r in rows:
        if r.get("_cat") != "enemy_roll" or r.get("bt") != "battle":
            continue
        per_floor[int(r["floor"])][str(r["type"])] += 1
    if not per_floor:
        return
    print("\n" + "=" * 78)
    print("常规战敌人类型占比 (按楼层)")
    print("  ▸ 单一类型占比过半 = 门禁把 roll 表砸平了; 类型数太少 = 那一层没花样")
    print("=" * 78)
    for f in sorted(per_floor):
        c = per_floor[f]
        tot = sum(c.values())
        top = c.most_common(4)
        share = "  ".join("%s %.0f%%" % (t, 100.0 * n / tot) for t, n in top)
        flag = "  <== 单一类型过半" if top and top[0][1] / tot > 0.5 else ""
        print("  floor %2d  %2d 种  %s%s" % (f, len(c), share, flag))


def report_sessions(rows: list[dict]) -> None:
    sess: dict = defaultdict(Counter)
    meta: dict = {}
    for r in rows:
        s = r.get("_session", "?")
        sess[s][r.get("_cat", "?")] += 1
        meta.setdefault(s, (r.get("_ts", "?"), r.get("_commit", "?")))
    print("会话清单 (每次跑一条):")
    for s in sorted(sess, key=lambda k: meta[k][0]):
        ts, sha = meta[s]
        parts = "  ".join("%s=%d" % (k, v) for k, v in sorted(sess[s].items()))
        print("  %s  %s  commit=%s  %s" % (ts, s, sha, parts))


def report_tests(rows: list[dict]) -> None:
    """测试执行记录。关心两件事: 谁在失败, 谁在变慢。

    "变慢"值得单列, 因为这个项目的测试挂起过一次而且伪装成了超时 —— 一个
    平时 3 秒的测试忽然跑 90 秒, 是断言挂了的第一个信号, 但只看单次输出看不
    出来 (你不记得它上次是几秒)。
    """
    per: dict = defaultdict(list)
    for r in rows:
        if r.get("_cat") != "testrun":
            continue
        per[str(r.get("test"))].append(r)
    if not per:
        print("还没有测试执行记录 —— 用 tools/run_tests.ps1 跑一次")
        return
    runs = len({r["_session"] for v in per.values() for r in v})
    print("测试执行记录: %d 个测试, %d 次运行\n" % (len(per), runs))
    print("%-46s %6s %8s %8s  %s" % ("测试", "通过率", "中位耗时", "最近耗时", "最近状态"))
    for name in sorted(per, key=lambda k: -np.median([r["duration_s"] for r in per[k]])):
        v = sorted(per[name], key=lambda r: r["_ts"])
        d = np.asarray([float(r["duration_s"]) for r in v])
        rate = 100.0 * sum(1 for r in v if r.get("ok")) / len(v)
        last = v[-1]
        med = float(np.median(d))
        # 最近一次比历史中位数慢一倍以上就点出来
        slow = "  <== 比平时慢 %.1fx" % (last["duration_s"] / med) if med > 0.5 and last["duration_s"] > med * 2 else ""
        print("%-46s %5.0f%% %7.2fs %7.2fs  %s%s"
              % (name, rate, med, last["duration_s"], last.get("status", "?"), slow))


def report_list(rows: list[dict]) -> None:
    cats: dict = defaultdict(Counter)
    for r in rows:
        for k, v in r.items():
            if k.startswith("_"):
                continue
            if isinstance(v, bool):
                continue
            cats[r.get("_cat", "?")][k] += 1 if isinstance(v, (int, float)) else 0
    for c in sorted(cats):
        num = [k for k, n in cats[c].items() if n > 0]
        cat_fields = [k for k in cats[c] if k not in num]
        print("%s:" % c)
        print("   数值字段: %s" % ", ".join(sorted(num)))
        if cat_fields:
            print("   分组字段: %s" % ", ".join(sorted(cat_fields)))


def report_vs(rows: list[dict], ref: str) -> None:
    """把日志按 commit/session 切成"基准"和"其余", 逐指标对比。

    这是这套工具真正的用处: 单看一次快照说不出好坏, 只有"改之前 38%, 改之后
    21%"才是能拿来做决定的信息。差异显著性用 Welch t 检验 (不假设等方差)。
    """
    def is_base(r: dict) -> bool:
        return r.get("_commit", "").startswith(ref) or r.get("_session", "") == ref

    # 按谓词分一次流, 不要写成 `r not in base` —— 那是对每一行做一次列表线性
    # 扫描 + 逐字段 dict 比较, 几千行就已经是几百万次比较了。
    base = [r for r in rows if is_base(r)]
    curr = [r for r in rows if not is_base(r)]
    if not base or not curr:
        print("对比需要两组数据: 基准 %d 行, 其余 %d 行" % (len(base), len(curr)))
        return
    print("\n基准 = %s (%d 行)   对照 = 其余 (%d 行)" % (ref, len(base), len(curr)))
    print("=" * 78)
    for cat, field, _by, _note in DEFAULT_VIEWS:
        a, b = values(base, cat, field), values(curr, cat, field)
        if a.size < 3 or b.size < 3:
            continue
        da, db = describe(a), describe(b)
        # Welch t
        se = math.sqrt(da["sd"] ** 2 / da["n"] + db["sd"] ** 2 / db["n"])
        t = (db["mean"] - da["mean"]) / se if se > 1e-12 else 0.0
        delta = db["mean"] - da["mean"]
        pct = 100.0 * delta / da["mean"] if abs(da["mean"]) > 1e-12 else float("nan")
        sig = "显著" if abs(t) > 2.0 else "不显著"
        print("  %-28s %9.3f -> %9.3f   Δ %+9.3f (%+6.1f%%)  t=%+6.2f %s"
              % ("%s.%s" % (cat, field), da["mean"], db["mean"], delta, pct, t, sig))


# ------------------------------------------------------------------ main

def main() -> int:
    ap = argparse.ArgumentParser(description="平衡性日志分布分析")
    ap.add_argument("--cat", help="只看某个 category")
    ap.add_argument("--field", help="只看某个数值字段")
    ap.add_argument("--by", help="按某个字段分组 (floor / bt / type ...)")
    ap.add_argument("--list", action="store_true", help="列出有哪些 category 和字段")
    ap.add_argument("--sessions", action="store_true", help="列出每次跑的会话")
    ap.add_argument("--tests", action="store_true",
                    help="测试执行记录 (由 tools/run_tests.ps1 写入): 通过率与耗时")
    ap.add_argument("--vs", metavar="COMMIT_OR_SESSION", help="和某次提交/会话的数据对比")
    args = ap.parse_args()

    rows = load()
    if not rows:
        print("logs/balance 里还没有数据")
        return 1

    if args.list:
        report_list(rows)
        return 0
    if args.sessions:
        report_sessions(rows)
        return 0
    if args.tests:
        report_tests(rows)
        return 0
    if args.vs:
        report_vs(rows, args.vs)
        return 0

    if args.cat and args.field:
        view(rows, args.cat, args.field, args.by)
        return 0

    print("平衡性日志: %d 行, 来自 %d 次会话"
          % (len(rows), len({r.get("_session") for r in rows})))
    for cat, field, by, note in DEFAULT_VIEWS:
        view(rows, cat, field, by, note)
    report_types(rows)
    print("\n提示: --cat/--field/--by 看单项, --vs <commit> 做改动前后对比")
    return 0


if __name__ == "__main__":
    sys.exit(main())
