"""渲染敌方坦克的装甲板叠加层 enemy_plate_t1/t2/t3.png。

这是 enemy.gd 装甲板系统的外观部分。机制那边是"血量 = 车种基础血 + 装甲层数
x 2"（整数加法），这里负责让那个整数**看得出来** —— 坦克大战里装甲车就该长得
不一样，而不是靠一个隐藏的乘数悄悄变厚。

为什么做成叠加层而不是给每个车种各渲一套装甲版本：敌人有 16 种、每种 6 帧，
再乘 3 个装甲档就是 288 张图，而且以后每加一个车种都要跟着乘 3。叠加层只要
3 张，对所有车种通用，加新车种时零成本。代价是它不能贴合每辆车各自的轮廓，
所以这里的形状刻意画成"外挂的附加装甲"——本来就该看起来是焊上去的。

三档的读法（在 48px 下能看出来的只有**覆盖面积**和**轮廓**，颜色排第二）：

    t1  两侧裙板              —— 车身两侧多出两条厚板
    t2  t1 + 前部首上装甲     —— 正面多一块斜板，轮廓变"尖"
    t3  t2 + 炮塔颈圈         —— 中间多一圈，三层一眼分得开

覆盖面积逐级严格变大，这条是 tools/test_armor_plating.gd 断言的不变量 ——
它是唯一在 48px 缩略尺寸下仍然可靠的信号。

配色刻意避开金色/黄色：按 CLAUDE.md，金色是**敌人车种**的视觉词汇
（enemy_power / enemy_armor / enemy_basic 的描边都用它），装甲板要是也用金色，
就会和车种识别抢同一个通道。这里走冷灰钢 + 逐级压暗，靠明度而不是色相分档，
和 tile_steel 当初把金色徽记换成暗化钢板是同一个道理。

坐标系对齐：相机是正交顶视 (ORTHO_SCALE_TANK = 3.6)，和坦克精灵同一画幅，
所以这里的 (x, y) 和 build_sokpop_tank 里的车体尺寸直接可比 ——
车身 w=1.3 / l=1.4，履带中心 tx≈0.78、宽 tw=0.34。板子挂在履带外侧。

用法:
    blender --background --python tools/build_armor_plating.py
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
    render_and_clean,
    reset_jitter_seed,
    apply_uniform_clay_bevel,
    create_clay_mat,
    ORTHO_SCALE_TANK,
)

PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
# 和敌方坦克精灵同一个目录。这个项目里目录名是有约定的 (enemy.gd 靠
# "res://assets/sprites/tanks/%s_f%d.png" 拼路径取图), 单独开一个 enemies/
# 只会多一处需要记住的例外。
OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "sprites", "tanks")

JITTER_SEED = 4100

# 和 build_sokpop_tank 里的车体尺寸对齐（那边 is_heavy=False 的一档）
HULL_W = 1.3
HULL_L = 1.4
TRACK_W = 0.34
TRACK_X = HULL_W * 0.5 + TRACK_W * 0.5 - 0.04   # ≈ 0.78

# 逐级压暗：靠明度分档，不靠色相（金/黄是敌人车种的词汇，不能拿来当装甲档位）
PLATE_COLORS = [
    (0.62, 0.65, 0.72, 1.0),   # t1 冷灰钢
    (0.44, 0.46, 0.53, 1.0),   # t2 暗钢
    (0.28, 0.29, 0.35, 1.0),   # t3 近黑铁
]
RIVET_COLOR = (0.86, 0.88, 0.92, 1.0)


def _rivet(mat, x, y, r=0.052):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, 0.40))
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, 0.55)
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def build_side_skirts(mat_plate, mat_rivet):
    """t1: 两条侧裙板，挂在履带外侧。"""
    objs = []
    px = TRACK_X + TRACK_W * 0.5 + 0.055
    for sx in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx * px, -0.04, 0.30))
        o = bpy.context.active_object
        o.scale = (0.20, HULL_L * 1.02, 0.44)
        o.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(o, width=0.055, segments=3)
        objs.append(o)
        # 每侧一颗铆钉 —— 档位越高铆钉越多，是覆盖面积之外的第二重读数
        objs.append(_rivet(mat_rivet, sx * px, 0.30))
    return objs


def build_glacis(mat_plate, mat_rivet):
    """t2 追加：正面首上装甲。倾斜 18°，让轮廓从"方"变"尖"。"""
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, HULL_L * 0.5 + 0.10, 0.34))
    o = bpy.context.active_object
    o.scale = (HULL_W * 0.94, 0.24, 0.42)
    o.rotation_euler = (math.radians(-18.0), 0.0, 0.0)
    o.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(o, width=0.06, segments=3)
    objs.append(o)
    for sx in (-1.0, 1.0):
        objs.append(_rivet(mat_rivet, sx * HULL_W * 0.30, HULL_L * 0.5 + 0.10))
    return objs


def build_turret_collar(mat_plate, mat_rivet):
    """t3 追加：炮塔颈圈。放在正中，三档在缩略尺寸下也分得开。"""
    objs = []
    bpy.ops.mesh.primitive_torus_add(
        location=(0.0, -0.05, 0.52),
        major_radius=0.50, minor_radius=0.115,
        major_segments=28, minor_segments=12,
    )
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, 0.72)
    o.data.materials.append(mat_plate)
    bpy.ops.object.shade_smooth()
    objs.append(o)
    for i in range(2):
        a = math.pi * 0.25 + i * math.pi
        objs.append(_rivet(mat_rivet, math.cos(a) * 0.50, -0.05 + math.sin(a) * 0.50))
    return objs


def build_plate(tier):
    """tier 是 1..3；高档位**包含**低档位的部件，覆盖面积因此严格递增。"""
    mat_plate = create_clay_mat(f"plate_t{tier}", PLATE_COLORS[tier - 1], roughness=0.62)
    mat_rivet = create_clay_mat(f"plate_rivet_t{tier}", RIVET_COLOR, roughness=0.45)

    objs = build_side_skirts(mat_plate, mat_rivet)
    if tier >= 2:
        objs += build_glacis(mat_plate, mat_rivet)
    if tier >= 3:
        objs += build_turret_collar(mat_plate, mat_rivet)
    return objs


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clear_scene()
    setup_render_settings(256, 256)
    # 和坦克同一画幅，叠上去才对得齐
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(JITTER_SEED)

    for tier in (1, 2, 3):
        objs = build_plate(tier)
        out = os.path.join(OUT_DIR, f"enemy_plate_t{tier}.png")
        render_and_clean(objs, out, label=f"Armor plate T{tier}")

    print("装甲板渲染完成 ->", OUT_DIR)
    print("接着跑: godot --headless --path . --import")
    print("        godot --headless --path . --script tools/test_armor_plating.gd")


if __name__ == "__main__":
    main()
