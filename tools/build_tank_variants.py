"""坦克差分叠加层。

产出 7 张:
    tank_dmg_t1 / t2            战损 (焦痕/凹陷 -> 撕裂口/断履带)
    tank_camo_a2 / a3           战区涂装 (沙漠 / 冰川)
    tank_marking_v1 / v2 / v3   编队标记

=== 为什么全部做成叠加层 ===

沿用 build_armor_plating.py 那条路 (装甲板 enemy_plate_t1/t2/t3 一套图覆盖全部
24 个车种), 理由在那个文件里写过, 这里只重述最要紧的一条: 敌人 24 种 x 6 帧,
任何"给每个车种各渲一版"的方案起步就是 144 张, 再乘差分档数, 并且**以后每加
一个车种都要跟着乘**。叠加层的代价是贴不合每辆车各自的轮廓, 所以形状一律画成
"外挂/涂上去/焊上去"的东西 —— 它本来就该看起来是附加在车体上的。

=== 画幅必须是 ORTHO_SCALE_TANK ===

坦克精灵用 3.6 的正交画幅 (ORTHO_SCALE_TANK), 装甲板也用 3.6, 这里同样。画幅
一错整张图就整体缩放, 而渲染本身照样"成功" —— CLAUDE.md 记过八张道具精灵因为
传错 ortho_scale 静默小了 0.82 倍的事故。叠加层错了更隐蔽: 它没有自己的轮廓可
供比对, 只会表现为"焦痕好像没贴在车上"。

坐标系和 build_sokpop_tank 对齐: 车体 w=1.3 / l=1.4, 履带中心 ±0.78, 车头朝 +Y。

=== 中心禁区: 叠加层不许盖住炮塔 ===

叠加层在游戏里是 sprite 的子节点, 无条件画在车体**之上**。而渲染这张叠加层时
场景里并没有炮塔, 所以任何落在中心的装饰在渲染图上都是完整的一块, 贴到游戏里
就直接糊住炮塔 —— 炮塔和炮管是玩家判断"这辆车朝哪、是什么车"的主要依据。
所以三类差分统统限制在 CENTER_KEEPOUT..OUTER_REACH 这个圆环里, 由 _in_ring()
强制。装甲板能放炮塔颈圈是因为那是**围着**炮塔的环, 不是盖在上面。

=== 三类差分各自占用不同的读数通道 ===

48px 下能同时叠 4 层 (装甲板 + 涂装 + 标记 + 战损) 而不糊成一团, 靠的是它们
读的不是同一个信号:

    装甲板  轮廓外扩 + 明度压暗   (已有, 见 build_armor_plating.py)
    涂装    大面积低对比色块      —— 只改色, 不改轮廓, 不加高频
    标记    极小面积高对比亮点    —— 面积小到不影响整体读数, 只提供"这两辆不是
                                     同一辆"的区分
    战损    小面积极暗 + 一处极亮  —— 靠明度极值, 和涂装的低对比正好错开

配色上避开金/黄: 按 CLAUDE.md 那是**敌人车种**的视觉词汇 (enemy_power /
enemy_armor / enemy_basic 的描边都用金色), 差分再用金色就会和车种识别抢通道。
战损因此走"极暗焦痕 + 亮金属撕裂面", 靠明度而不是色相 —— 和装甲板分档、
tile_steel 拿掉金盘是同一个道理。

用法:
    blender --background --python tools/build_tank_variants.py
    blender --background --python tools/build_tank_variants.py -- --list
"""

import math
import os
import sys

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    reset_jitter_seed,
    purge_orphans,
    ORTHO_SCALE_TANK,
)

PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "sprites", "tanks")

JITTER_SEED = 4300

# 和 build_sokpop_tank / build_armor_plating.py 对齐
HULL_W = 1.3
HULL_L = 1.4
TRACK_W = 0.34
TRACK_X = HULL_W * 0.5 + TRACK_W * 0.5 - 0.04   # ≈ 0.78

# 中心禁区半径。守的是**炮塔中心和炮管根部** —— 那是玩家判断"这辆车朝哪、
# 是什么车"的地方。炮塔盘本身约 0.5 (装甲板 t3 的颈圈就绕在 0.50 上), 允许
# 叠加件蹭到炮塔外沿, 但不许进到 0.46 以内。
CENTER_KEEPOUT = 0.46
# 外缘。履带外沿约 0.78 + 0.17 = 0.95; 上限对齐装甲板侧裙的最外沿 (那边
# px≈1.005 + 半宽 0.10 = 1.105), 保证两类叠加层的外轮廓在一个量级上。
OUTER_REACH = 1.12

# 叠加件的高度。比车体顶面 (~0.5) 略高, 保证在渲染里不被自己遮挡;
# 具体值不影响 2D 合成, 只影响自投影。
DECK_Z = 0.56


def _in_ring(x, y, extent, what):
    """校验必须带上装饰件自己的外扩量, 只查中心点是不够的。

    第一版只查了中心: 一块中心在 r=0.70 的涂装块, 半对角 0.27, 实际最内点在
    0.43 —— 已经压到炮塔上了, 而中心检查照样通过。叠加层在游戏里无条件画在
    车体之上, 这种越界不会报错, 只会表现为"炮塔糊了一块"。
    """
    r = math.hypot(x, y)
    if r - extent < CENTER_KEEPOUT:
        raise RuntimeError(
            f"{what} 中心 ({x:.2f},{y:.2f}) 半径 {r:.2f}, 外扩 {extent:.2f}, "
            f"最内点 {r - extent:.2f} < CENTER_KEEPOUT={CENTER_KEEPOUT} "
            f"—— 会盖住炮塔中心")
    if r + extent > OUTER_REACH:
        raise RuntimeError(
            f"{what} 中心 ({x:.2f},{y:.2f}) 半径 {r:.2f}, 外扩 {extent:.2f}, "
            f"最外点 {r + extent:.2f} > OUTER_REACH={OUTER_REACH} "
            f"—— 会飘在车体之外")
    return True


def _patch(loc, scale, mat, bevel=0.04, rot_z=0.0, what="patch"):
    x, y, z = loc
    # 用半对角作外扩 —— 偏保守 (旋转后径向上通常只有半边长), 但保守的那一侧
    # 是安全的那一侧。
    _in_ring(x, y, math.hypot(scale[0] * 0.5, scale[1] * 0.5), what)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z))
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = (0, 0, rot_z)
    o.data.materials.append(mat)
    apply_uniform_clay_bevel(o, width=bevel, segments=2, jitter=0.0)
    return o


def _blob(loc, r, mat, flatten=0.32, what="blob"):
    x, y, z = loc
    _in_ring(x, y, r, what)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, flatten)
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


# ==================== 战损 ====================

# 焦痕近黑, 撕裂面近白 —— 明度两极, 才能在 48px 下压过下面那层车体色。
SCORCH = (0.09, 0.08, 0.09, 1.0)
CHAR = (0.20, 0.17, 0.17, 1.0)
TORN_METAL = (0.88, 0.89, 0.93, 1.0)
VOID = (0.04, 0.04, 0.05, 1.0)


def build_damage(tier):
    """tier 1..2。t2 **包含** t1 的全部部件, 覆盖面积因此严格递增 ——
    和装甲板同一条不变量, tools/test_asset_variants.gd 断言它。"""
    objs = []
    mat_scorch = create_clay_mat(f"tv_scorch_t{tier}", SCORCH, roughness=0.95,
                                 bump_strength=0.34, mottle=0.14)
    mat_char = create_clay_mat(f"tv_char_t{tier}", CHAR, roughness=0.92,
                               bump_strength=0.30)

    # t1: 车体两侧/后部的焦痕 + 一处凹陷
    for (x, y, r) in [(-0.74, -0.34, 0.27), (0.66, -0.52, 0.22), (0.30, 0.62, 0.18)]:
        objs.append(_blob((x, y, DECK_Z), r, mat_scorch, what="焦痕"))
    objs.append(_patch((-0.58, 0.58, DECK_Z), (0.34, 0.22, 0.07), mat_char,
                       rot_z=math.radians(28), what="凹陷"))

    if tier >= 2:
        # t2 追加: 撕裂口 —— 一圈亮金属边包着一个黑洞。
        # 这是全图唯一的亮部, 和焦痕的近黑构成明度两极; 单靠"焦痕更多"在
        # 48px 下分不出两档 (深色块糊在一起就是一坨深色块)。
        mat_torn = create_clay_mat("tv_torn", TORN_METAL, roughness=0.42)
        mat_void = create_clay_mat("tv_void", VOID, roughness=0.98, mottle=0.0)
        cx, cy = -0.76, 0.20
        _in_ring(cx, cy, 0.23 + 0.062, "撕裂口")
        bpy.ops.mesh.primitive_torus_add(
            location=(cx, cy, DECK_Z + 0.02),
            major_radius=0.23, minor_radius=0.062,
            major_segments=16, minor_segments=8)
        rim = bpy.context.active_object
        rim.scale = (1.0, 1.0, 0.62)
        rim.data.materials.append(mat_torn)
        bpy.ops.object.shade_smooth()
        objs.append(rim)
        objs.append(_blob((cx, cy, DECK_Z - 0.01), 0.19, mat_void,
                          flatten=0.25, what="洞"))
        # 断掉的履带段: 车侧多一块塌下去的暗块, 轮廓上读起来是"瘸了"
        objs.append(_patch((0.78, 0.30, DECK_Z - 0.06), (0.20, 0.46, 0.06),
                           mat_char, rot_z=math.radians(-9), what="断履带"))
        for (x, y, r) in [(0.86, -0.16, 0.17), (-0.32, -0.80, 0.20)]:
            objs.append(_blob((x, y, DECK_Z), r, mat_scorch, what="焦痕2"))

    return objs


# ==================== 战区涂装 ====================

CAMO_PALETTES = {
    # (主色, 次色)。刻意选低对比的一对 —— 涂装要读成"这辆车属于这个战区",
    # 不能盖过车种自己的配色。实心大块 + 低对比 = 只改色不改轮廓。
    "a2": ((0.86, 0.74, 0.48, 1.0), (0.70, 0.58, 0.34, 1.0)),   # 沙漠
    "a3": ((0.92, 0.94, 0.97, 1.0), (0.72, 0.79, 0.88, 1.0)),   # 冰川
}


def build_camo(theme):
    """战区涂装。只在圆环内铺低矮色块, 不加轮廓、不加高频。"""
    main_col, sec_col = CAMO_PALETTES[theme]
    mat_a = create_clay_mat(f"tv_camo_{theme}_a", main_col, roughness=0.86,
                            bump_strength=0.22, mottle=0.10)
    mat_b = create_clay_mat(f"tv_camo_{theme}_b", sec_col, roughness=0.88,
                            bump_strength=0.22, mottle=0.10)
    objs = []
    # 沿圆环铺 7 块不规则色斑。角度和半径手挑, 避开正前方 (+Y 的炮管方向,
    # 涂装糊在炮管上会让"朝向"这个最要紧的读数变糊)。
    patches = [
        (math.radians(28),  0.76, 0.44, 0.34, mat_a),
        (math.radians(78),  0.76, 0.36, 0.40, mat_b),
        (math.radians(132), 0.78, 0.42, 0.32, mat_a),
        (math.radians(176), 0.78, 0.34, 0.44, mat_b),
        (math.radians(216), 0.80, 0.46, 0.30, mat_a),
        (math.radians(262), 0.76, 0.38, 0.38, mat_b),
        (math.radians(310), 0.77, 0.40, 0.34, mat_a),
    ]
    for (ang, rad, sx, sy, mat) in patches:
        x, y = math.cos(ang) * rad, math.sin(ang) * rad
        objs.append(_patch((x, y, DECK_Z - 0.02), (sx, sy, 0.05), mat,
                           bevel=0.06, rot_z=ang, what=f"涂装块@{math.degrees(ang):.0f}°"))
    return objs


# ==================== 编队标记 ====================

# 白 + 一点暖灰。面积极小, 所以这里*可以*用高对比 —— 它读的是"点", 不是"面"。
MARK_COLOR = (0.95, 0.95, 0.93, 1.0)
MARK_SHADOW = (0.22, 0.22, 0.26, 1.0)


def build_marking(variant):
    """v1 双条纹 / v2 三点 / v3 人字。

    统统画在车尾甲板 (-Y), 位置固定、只有图形不同 —— 位置也跟着变的话,
    48px 下读到的就只是"某处有个白点", 提供不了"这两辆不是同一辆"的信息。
    底下垫一层深色影子, 保证白标记落在浅色车体上 (如 enemy_basic 的紫灰)
    时也有边界。
    """
    mat_m = create_clay_mat(f"tv_mark_{variant}", MARK_COLOR, roughness=0.55,
                            bump_strength=0.16)
    mat_s = create_clay_mat(f"tv_marks_{variant}", MARK_SHADOW, roughness=0.90,
                            bump_strength=0.16)
    objs = []
    base_y = -0.72        # 车尾甲板, 半径 0.72 > CENTER_KEEPOUT

    def stamp(dx, dy, sx, sy, rot=0.0):
        # 影子比标记大一圈, 压在下面
        objs.append(_patch((dx, base_y + dy, DECK_Z - 0.03),
                           (sx + 0.07, sy + 0.07, 0.035), mat_s,
                           bevel=0.02, rot_z=rot, what="标记影"))
        objs.append(_patch((dx, base_y + dy, DECK_Z),
                           (sx, sy, 0.045), mat_m,
                           bevel=0.02, rot_z=rot, what="标记"))

    if variant == 1:
        stamp(-0.13, 0.0, 0.10, 0.34)
        stamp(0.13, 0.0, 0.10, 0.34)
    elif variant == 2:
        for dx in (-0.20, 0.0, 0.20):
            stamp(dx, 0.0, 0.13, 0.13)
    elif variant == 3:
        stamp(-0.13, 0.05, 0.09, 0.30, rot=math.radians(34))
        stamp(0.13, 0.05, 0.09, 0.30, rot=math.radians(-34))
    else:
        raise ValueError(f"未知标记变体 {variant}")
    return objs


# ==================== 批次 ====================

JOBS = [
    ("tank_dmg_t1.png",     lambda: build_damage(1)),
    ("tank_dmg_t2.png",     lambda: build_damage(2)),
    ("tank_camo_a2.png",    lambda: build_camo("a2")),
    ("tank_camo_a3.png",    lambda: build_camo("a3")),
    ("tank_marking_v1.png", lambda: build_marking(1)),
    ("tank_marking_v2.png", lambda: build_marking(2)),
    ("tank_marking_v3.png", lambda: build_marking(3)),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--list" in argv:
        for name, _ in JOBS:
            print(" ", name)
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    for idx, (name, builder) in enumerate(JOBS):
        clear_scene()
        setup_render_settings(256, 256)
        # 必须和坦克精灵同画幅, 否则叠上去对不齐 (见文件头)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        reset_jitter_seed(JITTER_SEED + idx * 11)
        render_and_clean(builder(), os.path.join(OUT_DIR, name))
        purge_orphans()

    print(f"\n[OK] 坦克差分 {len(JOBS)} 张 -> {OUT_DIR}")
    print("[NEXT] import -> python tools/fix_sprite_mipmaps.py -> import -> "
          "godot --headless --path . --script tools/test_asset_variants.gd")


if __name__ == "__main__":
    main()
