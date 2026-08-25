"""build_hunter_tank.py — 猎手坦克 (Hunter Tank / Ambush Tank) 3D 建模、动效与 Cycles 黏土渲染管线

猎手坦克 (Hunter Tank / Jungle Ambush Tank):
  - 车体：丛林迷彩暗绿 (Forest Green) + 泥沼暗褐 (Mud Brown) + 哑光战术装甲
  - 车顶：伪装迷彩网架 (Camo Net / Ghillie Frame) + 战术潜望侦测红外眼 (Infrared Sensor)
  - 炮塔：消音长身管狙击炮 (Suppressed Long-barrel Sniper) + 扁平低矮隐蔽炮塔 (Low-profile Turret)
  - 动效：6 帧履带运转、红外潜望镜小幅侦测扫描、红外眼呼吸点亮

输出资源:
  - assets/sprites/tanks/tank_hunter_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_hunter_f0.png ~ f5.png
  - assets/sprites/tanks/tank_hunter.png
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


def build_hunter_tank(frame: int = 0, is_enemy: bool = True):
    """构建猎手坦克 3D 模型与第 frame 帧动效"""
    objs = []

    # 1. 材质定义
    if is_enemy:
        col_hull    = srgb_to_linear((0.16, 0.28, 0.16, 1.0)) # 敌方丛林迷彩暗绿
        col_camo    = srgb_to_linear((0.32, 0.22, 0.14, 1.0)) # 泥沼迷彩暗褐斑
        col_net     = srgb_to_linear((0.24, 0.38, 0.18, 1.0)) # 仿生草叶伪装
        col_sensor  = srgb_to_linear((0.95, 0.15, 0.15, 1.0)) # 红外热成像瞄准眼 (赤红)
    else:
        col_hull    = srgb_to_linear((0.14, 0.24, 0.32, 1.0)) # 友方战术苍青
        col_camo    = srgb_to_linear((0.20, 0.40, 0.50, 1.0)) # 友方暗蓝迷彩
        col_net     = srgb_to_linear((0.25, 0.55, 0.65, 1.0)) # 友方战术伪装
        col_sensor  = srgb_to_linear((0.20, 0.85, 1.00, 1.0)) # 友方蓝光传感器

    col_track = srgb_to_linear((0.18, 0.18, 0.20, 1.0)) # 潜行履带深铁灰
    col_steel = srgb_to_linear((0.40, 0.44, 0.46, 1.0)) # 消音管金属

    mat_hull   = create_clay_mat("m_ht_hl", col_hull, roughness=0.65)
    mat_camo   = create_clay_mat("m_ht_cm", col_camo, roughness=0.70)
    mat_net    = create_clay_mat("m_ht_net", col_net, roughness=0.85)
    mat_track  = create_clay_mat("m_ht_tk", col_track, roughness=0.80)
    mat_steel  = create_clay_mat("m_ht_st", col_steel, roughness=0.40)

    # 传感器脉冲发光
    sensor_glow = 4.0 + 2.5 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_sensor = create_clay_mat("m_ht_sn", col_sensor, emission=col_sensor, emission_str=sensor_glow)

    # 车身轻微潜行颠簸
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012
    pitch = math.sin(frame * (2.0 * math.pi / 6.0)) * math.radians(1.0)
    # 红外潜望镜小幅左右侦测扫描
    sensor_yaw = math.sin(frame * (2.0 * math.pi / 6.0)) * math.radians(12.0)

    # ==================== 1. 履带与低矮悬挂 (Stealth Tracks) ====================
    for side in [-0.56, 0.56]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, 0, 0.14))
        track = bpy.context.active_object
        track.scale = (0.28, 1.45, 0.24)
        track.data.materials.append(mat_track)
        apply_uniform_clay_bevel(track, width=0.04, segments=2)
        objs.append(track)

        # 迷彩侧裙护板 (Camo Skirts)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 1.05, 0, 0.18))
        skirt = bpy.context.active_object
        skirt.scale = (0.05, 1.35, 0.16)
        skirt.data.materials.append(mat_camo)
        apply_uniform_clay_bevel(skirt, width=0.02, segments=2)
        objs.append(skirt)

    # ==================== 2. 低矮倾斜车体 (Low-Profile Wedge Chassis) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.26 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (0.88, 1.30, 0.22)
    hull.rotation_euler = (pitch, 0, 0)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.06, segments=3)
    objs.append(hull)

    # 车头倾角迷彩楔形前装甲
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.58, 0.22 + bob_z))
    wedge = bpy.context.active_object
    wedge.scale = (0.92, 0.32, 0.18)
    wedge.rotation_euler = (math.radians(-30) + pitch, 0, 0)
    wedge.data.materials.append(mat_camo)
    apply_uniform_clay_bevel(wedge, width=0.04, segments=2)
    objs.append(wedge)

    # ==================== 3. 扁平隐蔽炮塔 (Low-Profile Turret) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.05, 0.42 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (0.68, 0.72, 0.18)
    turret.rotation_euler = (pitch, 0, 0)
    turret.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(turret, width=0.05, segments=3)
    objs.append(turret)

    # 伪装迷彩网架块 (Camo Ghillie Patches)
    patch_locs = [(-0.25, 0.18, 0.52), (0.22, -0.15, 0.52), (-0.18, -0.22, 0.52)]
    for plx, ply, plz in patch_locs:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(plx, ply, plz + bob_z))
        patch = bpy.context.active_object
        patch.scale = (0.24, 0.22, 0.08)
        patch.rotation_euler = (pitch, 0, math.radians(15 * plx))
        patch.data.materials.append(mat_net)
        apply_uniform_clay_bevel(patch, width=0.02, segments=2)
        objs.append(patch)

    # ==================== 4. 红外侦测潜望镜 (Infrared Ambush Periscope) ====================
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.22, vertices=10,
                                         location=(0.22, 0.20, 0.56 + bob_z))
    periscope = bpy.context.active_object
    periscope.rotation_euler = (pitch, 0, sensor_yaw)
    periscope.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(periscope, width=0.02, segments=2)
    objs.append(periscope)

    # 红外侦测大眼 (Glowing Infrared Eye)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.065, location=(0.22, 0.28, 0.58 + bob_z))
    eye = bpy.context.active_object
    eye.data.materials.append(mat_sensor)
    bpy.ops.object.shade_smooth()
    objs.append(eye)

    # ==================== 5. 消音长身管狙击炮 (Suppressed Long Barrel) ====================
    # 主炮管
    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.95, vertices=12,
                                         location=(0, 0.78, 0.42 + bob_z))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90) + pitch, 0, 0)
    barrel.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
    objs.append(barrel)

    # 炮口消音器套筒 (Barrel Silencer Shroud)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.32, vertices=12,
                                         location=(0, 1.15, 0.42 + bob_z))
    silencer = bpy.context.active_object
    silencer.rotation_euler = (math.radians(90) + pitch, 0, 0)
    silencer.data.materials.append(mat_camo)
    apply_uniform_clay_bevel(silencer, width=0.02, segments=2)
    objs.append(silencer)

    return objs


def render_all_hunter_assets():
    """渲染猎手坦克 6 帧动画与静态图标"""
    print(">>> 正在初始化 Blender Cycles 猎手坦克渲染场景...")
    setup_render_settings(rx=256, ry=256, samples=32)

    # 1. 玩家/中立版猎手坦克 6 帧 (tank_hunter_f0 ~ f5)
    print("\n--- 渲染猎手坦克 6 帧动画 (tank_hunter_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_hunter_tank(frame=f, is_enemy=False)
        out_path = os.path.join(SPRITES_TANKS, f"tank_hunter_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染玩家帧 {f}/5 -> {out_path}")

    # 2. 敌方猎手坦克 6 帧 (enemy_hunter_f0 ~ f5)
    print("\n--- 渲染敌方猎手坦克 6 帧动画 (enemy_hunter_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_hunter_tank(frame=f, is_enemy=True)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_hunter_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染敌方帧 {f}/5 -> {out_path}")

    # 3. 静态图鉴图标 (tank_hunter.png)
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_hunter_tank(frame=0, is_enemy=True)
    icon_path = os.path.join(SPRITES_TANKS, "tank_hunter.png")
    render_and_clean(objs, icon_path)
    print(f"  [OK] 渲染猎手坦克静态图标 -> {icon_path}")

    print("\n>>> 所有猎手坦克 3D 模型渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_hunter_assets()
