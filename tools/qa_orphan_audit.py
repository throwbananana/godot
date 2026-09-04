"""复核"孤儿资源": 某张已提交的美术, 现存脚本到底还复不复现得出来。

    blender --background --python tools/qa_orphan_audit.py
    blender --background --python tools/qa_orphan_audit.py -- tile_hard_clay

=== 为什么需要这个工具 ===

CLAUDE.md 曾经记着一份"16 张孤儿资源"的名单 —— 剪影对得上 (d_cov 0.00) 但
着色对不上 (d_rgb 高到 31), 结论是"渲出它们的脚本已经被删了", 于是这些资源
被划进禁区: 不许重渲, 因为那等于拿已知可用的美术去换一版没人审过的。

那份名单**至少有三条是错的**, 而且错得很有代表性。tile_ice 名下写着
d_rgb 24.08; 用它属主函数当年的渲法 (点光源布光 + TILE_FULL_BLEED 底板 +
平滑着色) 重跑一遍, d_rgb 掉到 **0.20** —— 脚本一直忠实复现着已提交的美术,
24.08 全部是**比对口不对**造成的。同类误判还有 tile_conveyor (1.03) 和
shield_station (1.93, 它要的是 ORTHO_SCALE_PROP 2.7 而不是默认的 3.3)。

代价不只是记错一笔账: tile_ice 因此被排除在 rerender_tiles.py 之外, 又被
qa_style_consistency 的豁免名单以"孤儿资源"名义放行, 于是它带着全项目最差的
拼接梯度 (上下 30.41, 铺开就是一格一格的明暗方块) 一直留在冰川图上没人动。
**一条错误的"已知未修"记录, 比没有记录更能挡住修复。**

=== 这个工具做的事 ===

不拿单一固定的渲染设置去比, 而是对每张图试一组候选的 (布光, 画幅) 组合, 取
最优匹配。这两个参数正是当年最容易配错的:

  - **布光**: create_sokpop_lighting(seamless=?) 决定要不要那两盏点光源。满幅
    地形瓦片后来陆续改成了 seamless (点光源会在瓦片内造出位置梯度, 铺开就是
    网格线), 但改的时间点各不相同, 而已提交的 PNG 停在它被渲出来的那一刻。
  - **画幅**: ortho_scale 直接线性缩放整张图。项目里同时存在 3.3 (默认) /
    3.6 (坦克) / 2.7 (道具) / 2.6 (HUD 徽章) / 5.2 (立体场景) 五档。拿 3.3 去
    比一张 5.2 渲出来的立体场景, d_rgb 必然巨大, 而这跟"脚本丢没丢"毫无关系。

判定口径 (VERDICT_*): d_rgb < 3 视为复现 —— Cycles 每次渲染的采样噪声本身就
有 1~2 的量级, 卡到 0 是不现实的。

**这个工具只往临时目录写, 绝不碰 assets/。** 它是审计, 不是重渲。确认某张图
可复现之后, 要不要真的重渲、以及重渲成什么样, 仍然是单独的美术决策。
"""

import os
import sys
import tempfile

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_PROP,
    TILE_PLATE_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SPRITES = os.path.join(PROJECT_DIR, "assets", "sprites")
TMP = os.path.join(tempfile.gettempdir(), "orphan_audit")

JITTER_SEED = 4200
VERDICT_OK = 3.0        # d_rgb 低于此视为"复现得出来"(渲染噪声本底 1~2)
VERDICT_ORPHAN = 8.0    # 高于此视为"确实复现不出来"; 中间地带留给人看


def _lazy(module_name, func_name, *args):
    """延迟导入 —— 属主脚本在 import 时就可能做事 (建目录之类),
    没被点名的条目不该被拖进来。"""
    def make():
        mod = __import__(module_name)
        return getattr(mod, func_name)(*args)
    return make


# 每条: (资源相对路径, 构建器, [(标签, seamless, ortho_scale), ...])
#
# 候选组合里**第一条一律是属主脚本 main() 里自己写的那套设置** —— 如果连它都
# 对不上, 才轮得到怀疑别的。后面几条是历史上出现过的其它可能。
CANDIDATES = [
    ("tiles/tile_ice.png",
     _lazy("build_all_sokpop_assets_unified", "build_sokpop_ice"),
     [("seamless/3.3", True, ORTHO_SCALE_DEFAULT),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("tiles/tile_hard_clay.png",
     _lazy("build_hard_clay_tile_asset", "build_hard_clay_tile"),
     [("point/3.3", False, ORTHO_SCALE_DEFAULT),
      ("seamless/3.3", True, ORTHO_SCALE_DEFAULT),
      ("seamless/PLATE", True, TILE_PLATE_BLEED)]),

    ("tiles/tile_conveyor_f0.png",
     _lazy("build_conveyor_and_jump_pad", "build_conveyor_tile", 0),
     [("seamless/3.3", True, ORTHO_SCALE_DEFAULT),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT),
      ("seamless/PLATE", True, TILE_PLATE_BLEED)]),

    ("tiles/tile_jump_pad.png",
     _lazy("build_conveyor_and_jump_pad", "build_jump_pad_tile"),
     [("seamless/PLATE", True, TILE_PLATE_BLEED),
      ("seamless/3.3", True, ORTHO_SCALE_DEFAULT),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("tiles/tile_platform.png",
     _lazy("build_ice_and_platform_assets", "build_moving_platform_tile"),
     [("point/3.3", False, ORTHO_SCALE_DEFAULT),
      ("seamless/3.3", True, ORTHO_SCALE_DEFAULT)]),

    ("buildings/shield_station.png",
     _lazy("build_shield_and_wind_assets", "build_shield_station"),
     [("point/PROP", False, ORTHO_SCALE_PROP),
      ("seamless/PROP", True, ORTHO_SCALE_PROP),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("buildings/wind_blower_f0.png",
     _lazy("build_shield_and_wind_assets", "build_wind_blower", 0),
     [("point/PROP", False, ORTHO_SCALE_PROP),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("powerups/treasure_chest.png",
     _lazy("build_treasure_and_challenge_assets", "build_treasure_chest"),
     [("point/PROP", False, ORTHO_SCALE_PROP),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("powerups/treasure_key.png",
     _lazy("build_treasure_and_challenge_assets", "build_treasure_key"),
     [("point/PROP", False, ORTHO_SCALE_PROP),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    ("map/node_challenge.png",
     _lazy("build_treasure_and_challenge_assets", "build_challenge_node_icon"),
     [("point/PROP", False, ORTHO_SCALE_PROP),
      ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),

    # 立体场景和 HUD 徽章画幅特殊 (5.2 / 2.6), 拿默认的 3.3 去比必然天差地别
    # —— 这两组最能说明"比对口不对"是怎么被读成"脚本丢了"的。
    ("ui/diorama_shop.png",
     _lazy("build_expansion_sokpop_assets", "build_diorama_shop"),
     [("point/5.2", False, 5.2), ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),
    ("ui/diorama_event.png",
     _lazy("build_expansion_sokpop_assets", "build_diorama_event"),
     [("point/5.2", False, 5.2), ("point/3.3", False, ORTHO_SCALE_DEFAULT)]),
]
for _ic in ("atk", "speed", "armor", "regen"):
    CANDIDATES.append((
        "ui/icon_%s.png" % _ic,
        _lazy("build_expansion_sokpop_assets", "build_hud_icon", _ic),
        [("point/2.6", False, 2.6), ("point/3.3", False, ORTHO_SCALE_DEFAULT)]))


def _load_rgba(path):
    """只用 Blender 自带的 bpy.data.images 读图 —— 这个脚本跑在 Blender 里,
    不该额外要求装 numpy/Pillow。"""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = list(img.pixels)
    bpy.data.images.remove(img)
    return w, h, px


def _compare(path_a, path_b):
    wa, ha, pa = _load_rgba(path_a)
    wb, hb, pb = _load_rgba(path_b)
    if (wa, ha) != (wb, hb):
        return None
    n = wa * ha
    d_rgb = 0.0
    cov_a = 0
    cov_b = 0
    for i in range(n):
        o = i * 4
        for k in range(3):
            d_rgb += abs(pa[o + k] - pb[o + k])
        if pa[o + 3] > 0.03:
            cov_a += 1
        if pb[o + 3] > 0.03:
            cov_b += 1
    return {
        # 像素是 0..1 线性浮点; x255 只是为了和项目里其它工具的口径一致
        "d_rgb": 255.0 * d_rgb / float(n * 3),
        "d_cov": abs(cov_a - cov_b) / float(n),
    }


def audit_one(rel_path, builder, combos):
    committed = os.path.join(SPRITES, rel_path.replace("/", os.sep))
    if not os.path.isfile(committed):
        print("  [SKIP] 找不到已提交的图: %s" % rel_path)
        return None

    ref = bpy.data.images.load(committed, check_existing=False)
    rx, ry = ref.size
    bpy.data.images.remove(ref)

    best = None
    for (tag, seamless, ortho) in combos:
        clear_scene()
        # 分辨率跟着已提交的图走 —— 立体场景是 480x240, HUD 徽章是 128x128,
        # 一律按 256 渲的话尺寸都对不上, 更别提比像素了。
        setup_render_settings(rx=rx, ry=ry)
        create_sokpop_lighting(ortho_scale=ortho, seamless=seamless)
        reset_jitter_seed(JITTER_SEED)
        try:
            objs = builder()
        except Exception as exc:
            print("  [SKIP] %s (%s): 构建器抛异常 %s" % (rel_path, tag, exc))
            continue
        out = os.path.join(TMP, rel_path.replace("/", "_"))
        render_and_clean(objs, out, label="  probe")
        res = _compare(committed, out)
        if res is None:
            continue
        res["tag"] = tag
        if best is None or res["d_rgb"] < best["d_rgb"]:
            best = res
    return best


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(TMP, exist_ok=True)

    targets = CANDIDATES
    if argv:
        targets = [c for c in CANDIDATES
                   if any(a in c[0] for a in argv)]
        if not targets:
            print("[ERROR] 没有匹配的资源。可选:")
            for c in CANDIDATES:
                print("   ", c[0])
            raise SystemExit(1)

    print("=" * 74)
    print(">>> 孤儿资源复核 —— 逐个 (布光 x 画幅) 组合试渲, 取最优匹配 <<<")
    print("=" * 74)

    rows = []
    for (rel, builder, combos) in targets:
        print("\n>>> %s" % rel)
        best = audit_one(rel, builder, combos)
        if best is None:
            continue
        if best["d_rgb"] < VERDICT_OK:
            verdict = "可复现"
        elif best["d_rgb"] < VERDICT_ORPHAN:
            verdict = "存疑"
        else:
            verdict = "真孤儿"
        rows.append((rel, best["tag"], best["d_rgb"], best["d_cov"], verdict))
        print("    最优 %-14s d_rgb=%6.2f  d_cov=%.4f  -> %s"
              % (best["tag"], best["d_rgb"], best["d_cov"], verdict))

    print("\n" + "=" * 74)
    print("%-30s %-14s %8s %8s  %s" % ("资源", "最优组合", "d_rgb", "d_cov", "判定"))
    print("-" * 74)
    for (rel, tag, d, c, v) in sorted(rows, key=lambda r: r[2]):
        print("%-30s %-14s %8.2f %8.4f  %s" % (rel, tag, d, c, v))
    n_ok = sum(1 for r in rows if r[4] == "可复现")
    print("-" * 74)
    print("%d/%d 可复现。判定为'真孤儿'的那些, 重渲前需要先做美术决策。"
          % (n_ok, len(rows)))
    print("渲出来的探针图在: %s (只写这里, 不碰 assets/)" % TMP)


if __name__ == "__main__":
    main()
