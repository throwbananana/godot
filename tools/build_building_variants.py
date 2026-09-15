"""建筑差分。

产出 6 张:
    building_dmg_t1 / t2        通用战损贴花 (裂纹/焦痕 -> 破洞/塌角)
    building_theme_a2 / a3      战区覆盖层 (沙尘 / 积雪)
    fortified_wall_v1 / v2      加固墙的两个外观变体

=== 战损/主题为什么是"通用贴花"而不是逐建筑重渲 ===

有血量的建筑现在有 12 种 (ammo_depot / bunker / command_post / defense_turret /
emp_tower / fortified_wall / pipe_conduit / radar_station / roller_wall /
sniper_nest / wooden_wall, 以及各自的衍生)。逐个渲两档战损是 24 张, 而且其中
好几张的属主脚本按 CLAUDE.md 的记录已经无法复现已提交的美术 —— 重渲它们等于
拿已知可用的图去换一版没人审过的。

贴花绕开了这个问题: 它是**新美术**, 不需要复现任何东西, 也就不碰那 12 张已
提交的图。两张覆盖全部 12 种, 以后加建筑零成本。这和 enemy_plate / tank_dmg
是同一条路线。

wooden_wall 已经有自己的三档战损贴图 (wooden_wall_dmg0..2), 那是专门画的, 比
通用贴花贴合; 接入时它保持原样, 不叠通用贴花 —— 见 scripts/building_skin.gd。

=== 贴花靠 clip_children 裁进建筑剪影 ===

通用贴花的死穴是建筑轮廓差别极大 (street_lamp 细高, bunker 方阔), 一张固定
形状的贴花必然有一部分飘在建筑外面, 读起来是"地上多了几道裂纹"而不是"这座
建筑裂了"。

Godot 的 CanvasItem.clip_children 正好解决这个: 把建筑的 Sprite2D 设成
CLIP_CHILDREN_AND_DRAW, 子节点就会被按父节点的 alpha 裁剪。所以这里可以放心
把贴花铺满画幅中段, 超出建筑轮廓的部分由引擎裁掉。**贴花必须画得比任何单个
建筑都大**, 否则小建筑上会露出贴花自己的边 —— 那比飘在外面更假, 因为它是一
条与建筑无关的直边。

画幅用 ORTHO_SCALE_DEFAULT = 3.3, 和 build_all_sokpop_assets_unified.py::main()
渲建筑时一致 (那边整批建筑都是 3.3)。画幅错了贴花就整体缩放, 而渲染照样成功
—— CLAUDE.md 记过八张道具因为传错 ortho_scale 静默小了 0.82 倍的事故。

=== fortified_wall 为什么单独出变体 ===

其余建筑一张图上通常只出现一两次, "重复感"不构成问题; 加固墙不同 —— 它是
玩家用建造系统一排排摆出来的, 一道八格长的墙就是同一张图连贴八次。这是建筑
里唯一真正撞上"平铺重复"问题的一个, 所以给它出两个变体, 由
builder_controller 按格子确定性挑图。

用法:
    blender --background --python tools/build_building_variants.py
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
    ORTHO_SCALE_DEFAULT,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_fortified_wall,
    SPRITES_BUILDINGS,
)

JITTER_SEED = 4400

# 贴花的铺设半径。画幅半宽 1.65 —— 铺到 1.5 是刻意的: 要比最大的建筑
# (fortified_wall 半宽 1.425) 还大, 保证任何建筑上都看不到贴花自己的边界。
DECAL_REACH = 1.50


def _slab(loc, scale, mat, bevel=0.05, rot_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = (0, 0, rot_z)
    o.data.materials.append(mat)
    apply_uniform_clay_bevel(o, width=bevel, segments=2, jitter=0.0)
    return o


def _dome(loc, r, mat, flatten=0.30):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, flatten)
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


# ==================== 通用战损贴花 ====================

CRACK = (0.16, 0.15, 0.17, 1.0)
SCORCH = (0.10, 0.09, 0.10, 1.0)
RUBBLE = (0.42, 0.40, 0.42, 1.0)
EXPOSED = (0.86, 0.87, 0.91, 1.0)
VOID = (0.04, 0.04, 0.05, 1.0)


def build_building_damage(tier):
    """tier 1..2。t2 包含 t1 的全部部件 —— 覆盖面积严格递增, 和
    enemy_plate / tank_dmg 同一条不变量, test_asset_variants.gd 断言它。"""
    objs = []
    mat_crack = create_clay_mat(f"bv_crack_t{tier}", CRACK, roughness=0.94,
                                bump_strength=0.30)
    mat_scorch = create_clay_mat(f"bv_scorch_t{tier}", SCORCH, roughness=0.96,
                                 bump_strength=0.34, mottle=0.14)

    # t1: 一张贯穿的裂纹网 + 两处焦痕。裂纹刻意从画幅一侧走到另一侧,
    # 这样无论被裁成什么形状, 建筑上看到的都是"一道穿过去的裂缝",
    # 而不是"中间摆了一小段裂纹"。
    cracks = [(-0.10, -0.15, math.radians(28), 2.90, 0.115),
              (0.25, 0.35, math.radians(-52), 2.60, 0.100),
              (-0.55, 0.60, math.radians(76), 1.90, 0.085),
              (0.70, -0.55, math.radians(8), 1.70, 0.080)]
    for (x, y, rot, length, width) in cracks:
        objs.append(_slab((x, y, 0.30), (length, width, 0.06), mat_crack,
                          bevel=0.02, rot_z=rot))
    for (x, y, r) in [(-0.95, -0.80, 0.42), (0.88, 0.72, 0.34)]:
        objs.append(_dome((x, y, 0.30), r, mat_scorch))

    if tier >= 2:
        # t2 追加: 破洞 (亮金属边 + 黑心) + 塌落的碎块。
        # 亮边是全图唯一的亮部 —— 两档不能只靠"暗块更多"区分, 那在 48px 下
        # 会糊成同一坨暗块 (和 tank_dmg 同一个道理)。
        mat_exp = create_clay_mat("bv_exposed", EXPOSED, roughness=0.44)
        mat_void = create_clay_mat("bv_void", VOID, roughness=0.98, mottle=0.0)
        mat_rub = create_clay_mat("bv_rubble", RUBBLE, roughness=0.92,
                                  bump_strength=0.32)
        bpy.ops.mesh.primitive_torus_add(
            location=(0.30, -0.25, 0.33),
            major_radius=0.46, minor_radius=0.10,
            major_segments=20, minor_segments=8)
        rim = bpy.context.active_object
        rim.scale = (1.0, 1.0, 0.60)
        rim.data.materials.append(mat_exp)
        bpy.ops.object.shade_smooth()
        objs.append(rim)
        objs.append(_dome((0.30, -0.25, 0.29), 0.40, mat_void, flatten=0.22))
        # 碎块散在洞的周围, 全部落在 DECAL_REACH 内
        for (x, y, s, rot) in [(-0.72, 0.18, 0.30, 0.5), (0.95, -0.92, 0.26, -0.8),
                               (-1.10, 0.95, 0.24, 1.2), (0.55, 1.05, 0.22, 0.2),
                               (-0.35, -1.15, 0.28, -0.4)]:
            objs.append(_slab((x, y, 0.32), (s, s * 0.78, 0.09), mat_rub,
                              bevel=0.04, rot_z=rot))
        for (x, y, r) in [(-0.20, 0.95, 0.36), (1.05, 0.10, 0.30)]:
            objs.append(_dome((x, y, 0.30), r, mat_scorch))

    return objs


# ==================== 战区覆盖层 ====================

THEME_LAYERS = {
    # (主色, 次色)。低对比 —— 覆盖层要读成"这座建筑落了沙/落了雪",
    # 不能盖掉建筑本身的形。
    "a2": ((0.88, 0.76, 0.50, 1.0), (0.76, 0.63, 0.38, 1.0)),
    "a3": ((0.95, 0.96, 0.98, 1.0), (0.80, 0.86, 0.93, 1.0)),
}


def build_building_theme(theme):
    """沙尘/积雪覆盖层。铺满画幅中段, 由 clip_children 裁进建筑剪影。"""
    main_col, sec_col = THEME_LAYERS[theme]
    mat_a = create_clay_mat(f"bv_th_{theme}_a", main_col, roughness=0.88,
                            bump_strength=0.24, mottle=0.12)
    mat_b = create_clay_mat(f"bv_th_{theme}_b", sec_col, roughness=0.90,
                            bump_strength=0.24, mottle=0.12)
    objs = []
    # 不铺成整块 —— 整块会把建筑刷成一片纯色, 形就没了。铺成互相错开的
    # 大色斑, 留出约四成的空隙让建筑本体透出来。
    blobs = [(-0.85, 0.85, 0.78, mat_a), (0.62, 1.02, 0.62, mat_b),
             (1.05, 0.15, 0.70, mat_a), (0.35, -0.85, 0.66, mat_b),
             (-0.55, -1.00, 0.60, mat_a), (-1.15, -0.10, 0.58, mat_b),
             (0.05, 0.30, 0.52, mat_a)]
    # 守的是"铺得够远", 不是"别铺出去"。贴花本来就该盖得比任何建筑都大 ——
    # 超出画幅的部分被相机切掉、超出建筑的部分被 clip_children 裁掉, 两者都
    # 不会留下痕迹; 真正会露馅的是反过来: 贴花自己的外缘落在建筑*里面*, 那
    # 就是一条与建筑无关的弧边横在墙上。所以这里要求至少五块色斑的外缘越过
    # 最大建筑的半宽 (fortified_wall 2.85/2 = 1.425)。
    far = sum(1 for (x, y, r, _) in blobs if math.hypot(x, y) + r >= 1.425)
    if far < 5:
        raise RuntimeError(
            f"覆盖层只有 {far} 块色斑铺到了 1.425 以外 —— 贴到大建筑上会露出"
            f"贴花自己的边缘, 需要至少 5 块")
    for (x, y, r, mat) in blobs:
        objs.append(_dome((x, y, 0.30), r, mat, flatten=0.16))
    return objs


# ==================== 加固墙变体 ====================

def _remap_materials(objs, remap, suffix):
    """按材质名换色。名字对不上就抛异常, 不静默保持原色 —— 属主脚本改了
    材质名的话要当场知道, 而不是渲出一批"某个部件忘了换"的图。"""
    hit = set()
    for o in objs:
        if o.type != 'MESH':
            continue
        for i, slot in enumerate(o.material_slots):
            if slot.material is None:
                continue
            name = slot.material.name
            if len(name) > 4 and name[-4] == '.' and name[-3:].isdigit():
                name = name[:-4]
            if name in remap:
                spec = remap[name]
                o.material_slots[i].material = create_clay_mat(
                    f"{name}_{suffix}", spec[0], **spec[1])
                hit.add(name)
    missing = set(remap) - hit
    if missing:
        raise RuntimeError(
            f"[加固墙变体] 这些材质名在属主脚本里找不到了: {sorted(missing)} "
            f"—— build_sokpop_fortified_wall 大概改了材质名, 把新名字补进 remap。")


def build_fortified_wall_variant(variant):
    """v1 = 冷蓝护盾型, v2 = 土黄沙袋型。

    只换色 + 加装饰, 不动主体尺寸 —— 加固墙是按格摆的建筑, 外形一变就和
    builder_controller 的落位预览对不上。
    """
    objs = build_sokpop_fortified_wall()

    if variant == 1:
        _remap_materials(objs, {
            "m_ubld_w":  ((0.30, 0.40, 0.52, 1.0), {}),
            "m_ubld_ws": ((0.68, 0.78, 0.90, 1.0), {}),
            "m_ubld_wc": ((0.32, 0.82, 0.96, 1.0),
                          {"emission": (0.32, 0.82, 0.96, 1.0), "emission_str": 2.5}),
        }, "v1")
        # 四边加一圈散热鳍, 轮廓上和原版分得开
        mat_fin = create_clay_mat("m_fw_fin_v1", (0.58, 0.70, 0.84, 1.0))
        for i in range(4):
            a = math.radians(45 + i * 90)
            objs.append(_slab((math.cos(a) * 1.05, math.sin(a) * 1.05, 0.22),
                              (0.62, 0.20, 0.14), mat_fin, bevel=0.05, rot_z=a))

    elif variant == 2:
        _remap_materials(objs, {
            "m_ubld_w":  ((0.52, 0.44, 0.30, 1.0), {}),
            "m_ubld_ws": ((0.72, 0.66, 0.52, 1.0), {}),
            "m_ubld_wc": ((0.96, 0.52, 0.24, 1.0),
                          {"emission": (0.96, 0.52, 0.24, 1.0), "emission_str": 2.2}),
        }, "v2")
        # 堆叠的沙袋: 沿两条边码一排圆角块
        mat_bag = create_clay_mat("m_fw_bag_v2", (0.74, 0.66, 0.48, 1.0),
                                  roughness=0.92, bump_strength=0.34)
        for i in range(4):
            t = -0.95 + i * 0.63
            objs.append(_dome((t, -1.18, 0.24), 0.34, mat_bag, flatten=0.42))
            objs.append(_dome((-1.18, t, 0.24), 0.34, mat_bag, flatten=0.42))

    else:
        raise ValueError(f"未知加固墙变体 {variant}")

    return objs


# ==================== 批次 ====================

JOBS = [
    ("building_dmg_t1.png",    lambda: build_building_damage(1)),
    ("building_dmg_t2.png",    lambda: build_building_damage(2)),
    ("building_theme_a2.png",  lambda: build_building_theme("a2")),
    ("building_theme_a3.png",  lambda: build_building_theme("a3")),
    ("fortified_wall_v1.png",  lambda: build_fortified_wall_variant(1)),
    ("fortified_wall_v2.png",  lambda: build_fortified_wall_variant(2)),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--list" in argv:
        for name, _ in JOBS:
            print(" ", name)
        return

    os.makedirs(SPRITES_BUILDINGS, exist_ok=True)
    for idx, (name, builder) in enumerate(JOBS):
        clear_scene()
        setup_render_settings(256, 256)
        # 和 unified::main() 渲建筑时同一画幅
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        reset_jitter_seed(JITTER_SEED + idx * 13)
        render_and_clean(builder(), os.path.join(SPRITES_BUILDINGS, name))
        purge_orphans()

    print(f"\n[OK] 建筑差分 {len(JOBS)} 张 -> {SPRITES_BUILDINGS}")


if __name__ == "__main__":
    main()
