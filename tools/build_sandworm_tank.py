"""build_sandworm_tank.py — 沙虫坦克 (Sandworm Tank / Burrowing Dune Tank) 3D 建模、动效与 Cycles 黏土渲染管线

沙虫坦克 (Sandworm Tank / Tremor Dune Tank):
  - 车体：砂岩土黄 (Desert Ochre) + 几丁质硬壳砂褐 (Chitin Brown) + 环状节肢分段式甲壳
  - 车头：巨型旋风硬岩钻掘头 (Rotary Cone Drill Mandibles)
  - 车背：节肢隆起甲壳 + 双联沙爆迫击炮管 (Twin Sand Mortar Nozzles)
  - 侧面：琥珀色震地感知发光晶体 (Glowing Amber Tremor Nodes)
  - 动效：6 帧钻头旋转、节肢甲壳蠕动伸缩、琥珀晶体脉冲呼吸发光

输出资源:
  - assets/sprites/tanks/tank_sandworm_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_sandworm_f0.png ~ f5.png
  - assets/sprites/tanks/tank_sandworm.png
"""

import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
os.makedirs(SPRITES_TANKS, exist_ok=True)


def build_sandworm_tank(frame: int = 0, is_enemy: bool = True):
    """构建沙虫坦克 3D 模型与第 frame 帧动效"""
    objs = []

    # 1. 材质定义
    if is_enemy:
        col_hull    = srgb_to_linear((0.36, 0.24, 0.14, 1.0)) # 敌方深砂岩土褐
        col_chitin  = srgb_to_linear((0.78, 0.52, 0.20, 1.0)) # 几丁质砂丘金褐
        col_drill   = srgb_to_linear((0.48, 0.45, 0.42, 1.0)) # 硬岩高锰钢钻头
        col_amber   = srgb_to_linear((1.00, 0.65, 0.10, 1.0)) # 琥珀震波感知晶体 (金橙)
    else:
        col_hull    = srgb_to_linear((0.18, 0.22, 0.26, 1.0)) # 友方深蓝岩底盘
        col_chitin  = srgb_to_linear((0.25, 0.60, 0.75, 1.0)) # 友方晶石青蓝甲
        col_drill   = srgb_to_linear((0.55, 0.60, 0.65, 1.0)) # 友方白钢钻头
        col_amber   = srgb_to_linear((0.30, 0.90, 1.00, 1.0)) # 友方苍蓝晶体

    col_track = srgb_to_linear((0.20, 0.18, 0.16, 1.0)) # 埋地防卡死履带暗泥

    mat_hull   = create_clay_mat("m_sw_hl", col_hull, roughness=0.70)
    mat_chitin = create_clay_mat("m_sw_ch", col_chitin, roughness=0.55)
    mat_drill  = create_clay_mat("m_sw_dr", col_drill, roughness=0.35)
    mat_track  = create_clay_mat("m_sw_tk", col_track, roughness=0.85)

    # 动态脉冲发光琥珀晶体
    glow_pulse = 4.5 + 3.0 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_amber = create_clay_mat("m_sw_am", col_amber, emission=col_amber, emission_str=glow_pulse)

    # 蠕动伸缩与微震
    phase = frame * (2.0 * math.pi / 6.0)
    crawl_stretch = 1.0 + 0.05 * math.sin(phase)
    drill_spin = frame * (math.pi / 3.0) # 钻头每帧高速旋转 60 度
    bob_z = math.sin(phase) * 0.015

    # ==================== 1. 埋地多段履带 (Burrow Tracks) ====================
    for side in [-0.58, 0.58]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, 0, 0.16))
        track = bpy.context.active_object
        track.scale = (0.28, 1.50 * crawl_stretch, 0.26)
        track.data.materials.append(mat_track)
        apply_uniform_clay_bevel(track, width=0.04, segments=2)
        objs.append(track)

    # ==================== 2. 分段节肢甲壳车体 (Segmented Chitin Hull) ====================
    # 3 节互相重叠的环状甲壳 (Segment 1~3)
    segment_y = [0.25, -0.10, -0.45]
    segment_scale = [
        (0.92, 0.42, 0.30),
        (0.86, 0.40, 0.32),
        (0.78, 0.38, 0.28),
    ]

    for idx, (sy, sc) in enumerate(zip(segment_y, segment_scale)):
        seg_bob = math.sin(phase + idx * 1.2) * 0.02
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, sy * crawl_stretch, 0.34 + bob_z + seg_bob))
        seg = bpy.context.active_object
        seg.scale = sc
        seg.data.materials.append(mat_chitin if idx % 2 == 0 else mat_hull)
        apply_uniform_clay_bevel(seg, width=0.06, segments=3)
        objs.append(seg)

        # 甲壳两侧的琥珀震波感知晶体 (Amber Tremor Nodes)
        for s_side in [-sc[0] * 0.52, sc[0] * 0.52]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(s_side, sy * crawl_stretch, 0.38 + bob_z + seg_bob))
            node = bpy.context.active_object
            node.data.materials.append(mat_amber)
            bpy.ops.object.shade_smooth()
            objs.append(node)

    # ==================== 3. 车头硬岩旋风巨钻 (Front Heavy Cone Drill) ====================
    bpy.ops.mesh.primitive_cone_add(radius1=0.28, depth=0.68, vertices=12,
                                     location=(0, 0.85 * crawl_stretch, 0.32 + bob_z))
    drill = bpy.context.active_object
    drill.rotation_euler = (math.radians(-90), 0, drill_spin)
    drill.data.materials.append(mat_drill)
    apply_uniform_clay_bevel(drill, width=0.03, segments=2)
    objs.append(drill)

    # 钻头两侧环形研磨副齿 (Grinding Mandibles)
    for side_m in [-0.34, 0.34]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.10, depth=0.38, vertices=8,
                                         location=(side_m, 0.72 * crawl_stretch, 0.30 + bob_z))
        mandible = bpy.context.active_object
        mandible.rotation_euler = (math.radians(-80), math.radians(20 * (1 if side_m > 0 else -1)), 0)
        mandible.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(mandible, width=0.02, segments=2)
        objs.append(mandible)

    # ==================== 4. 背部双联沙爆迫击炮管 (Twin Sand Mortar Nozzles) ====================
    for mx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.45, vertices=12,
                                             location=(mx, -0.05 * crawl_stretch, 0.56 + bob_z))
        mortar = bpy.context.active_object
        mortar.rotation_euler = (math.radians(25), 0, 0) # 向上前方仰角射击
        mortar.data.materials.append(mat_drill)
        apply_uniform_clay_bevel(mortar, width=0.02, segments=2)
        objs.append(mortar)

    return objs


def render_all_sandworm_assets():
    """渲染沙虫坦克 6 帧动画与静态图标"""
    print(">>> 正在初始化 Blender Cycles 沙虫坦克渲染场景...")
    setup_render_settings(rx=256, ry=256, samples=32)

    # 1. 玩家/中立版沙虫坦克 6 帧 (tank_sandworm_f0 ~ f5)
    print("\n--- 渲染沙虫坦克 6 帧动画 (tank_sandworm_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_sandworm_tank(frame=f, is_enemy=False)
        out_path = os.path.join(SPRITES_TANKS, f"tank_sandworm_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染玩家帧 {f}/5 -> {out_path}")

    # 2. 敌方沙虫坦克 6 帧 (enemy_sandworm_f0 ~ f5)
    print("\n--- 渲染敌方沙虫坦克 6 帧动画 (enemy_sandworm_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_sandworm_tank(frame=f, is_enemy=True)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_sandworm_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染敌方帧 {f}/5 -> {out_path}")

    # 3. 静态图鉴图标 (tank_sandworm.png)
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_sandworm_tank(frame=0, is_enemy=True)
    icon_path = os.path.join(SPRITES_TANKS, "tank_sandworm.png")
    render_and_clean(objs, icon_path)
    print(f"  [OK] 渲染沙虫坦克静态图标 -> {icon_path}")

    print("\n>>> 所有沙虫坦克 3D 模型渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_sandworm_assets()
