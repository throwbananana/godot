"""build_engineer_tank.py — 工程坦克建模、6帧动效与 Cycles 黏土渲染管线

工程坦克 (Engineer Tank):
  - 工业安全黄 (0.90, 0.68, 0.12) + 哑光深灰底盘 + 黑黄警示条纹
  - 车头推土/排障铲 (Bulldozer Blade)
  - 顶部铰接式多轴工程吊臂 (Articulated Crane Boom) + 液压液爪 (3-Finger Hydraulic Claws)
  - 顶部旋转琥珀色警示灯 (Amber Beacon)
  - 车尾工件工具箱 (Tool Crate)

输出资源:
  - assets/sprites/tanks/tank_engineer_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_engineer_f0.png ~ f5.png
  - assets/sprites/tanks/tank_engineer.png
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


def build_engineer_tank(frame: int = 0, is_enemy: bool = False):
    """构建工程坦克 3D 模型与第 frame 帧动效"""
    objs = []

    # 1. 材质定义 (遵循 Sokpop 黏土着色)
    if not is_enemy:
        col_body   = srgb_to_linear((0.92, 0.68, 0.12, 1.0)) # 工业亮黄
        col_turret = srgb_to_linear((0.26, 0.28, 0.30, 1.0)) # 工业深灰
        col_trim   = srgb_to_linear((0.96, 0.78, 0.20, 1.0)) # 明黄点缀
    else:
        col_body   = srgb_to_linear((0.85, 0.42, 0.14, 1.0)) # 敌方警示橙红
        col_turret = srgb_to_linear((0.24, 0.20, 0.22, 1.0)) # 敌方暗铁
        col_trim   = srgb_to_linear((0.92, 0.55, 0.18, 1.0)) # 橙红点缀

    col_track  = srgb_to_linear((0.25, 0.25, 0.27, 1.0)) # 履带黑铁
    col_hazard = srgb_to_linear((0.10, 0.10, 0.12, 1.0)) # 警示黑纹
    col_beacon = srgb_to_linear((1.00, 0.60, 0.05, 1.0)) # 琥珀警示灯
    col_steel  = srgb_to_linear((0.62, 0.66, 0.68, 1.0)) # 液压杆金属

    mat_body   = create_clay_mat("m_eng_b", col_body, roughness=0.62)
    mat_turret = create_clay_mat("m_eng_t", col_turret, roughness=0.55)
    mat_track  = create_clay_mat("m_eng_tr", col_track, roughness=0.88)
    mat_trim   = create_clay_mat("m_eng_tm", col_trim, roughness=0.50)
    mat_hazard = create_clay_mat("m_eng_hz", col_hazard, roughness=0.70)
    mat_steel  = create_clay_mat("m_eng_st", col_steel, roughness=0.35)
    mat_crate  = create_clay_mat("m_eng_cr", srgb_to_linear((0.55, 0.38, 0.22, 1.0)), roughness=0.80)

    # 警示灯发光材质 (根据帧数产生旋转发光强弱呼吸)
    beacon_pulse = 3.5 + 2.5 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_beacon = create_clay_mat("m_eng_bc", col_beacon,
                                 emission=col_beacon, emission_str=beacon_pulse)

    # 动态参数
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015
    w, l = 1.36, 1.48
    tw = 0.34
    tx = w * 0.5 + tw * 0.5 - 0.03

    # ==================== 1. 主车体 (Hull) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.54)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.14, segments=4)
    objs.append(hull)

    # 车体侧面黑黄斑马安全警示斜条
    for hx in [-w * 0.49, w * 0.49]:
        for hy in [-0.35, 0.0, 0.35]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(hx, hy, 0.05 + bob_z))
            hz = bpy.context.active_object
            hz.scale = (0.04, 0.20, 0.22)
            hz.rotation_euler = (0, 0, math.radians(35 if hx > 0 else -35))
            hz.data.materials.append(mat_hazard)
            apply_uniform_clay_bevel(hz, width=0.015, segments=2)
            objs.append(hz)

    # ==================== 2. 车头推土排障铲 (Bulldozer Blade) ====================
    blade_y = l * 0.52 + 0.08
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, blade_y, -0.02 + bob_z))
    blade = bpy.context.active_object
    blade.scale = (w * 1.08, 0.12, 0.40)
    blade.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(blade, width=0.06, segments=3)
    objs.append(blade)

    # 推土铲固定液压杆
    for sx in [-0.45, 0.45]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.32, vertices=12,
                                             location=(sx, blade_y - 0.16, -0.02 + bob_z))
        arm = bpy.context.active_object
        arm.rotation_euler = (math.radians(90), 0, 0)
        arm.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(arm, width=0.015, segments=2)
        objs.append(arm)

    # ==================== 3. 履带与负重轮 (Tracks & Wheels) ====================
    for x_pos in [-tx, tx]:
        # 履带护甲框
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.01))
        tr = bpy.context.active_object
        tr.scale = (tw, l * 1.08, 0.56)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.14, segments=4)
        objs.append(tr)

        # 3 个大型负重轮
        for wy in [-0.42, 0.0, 0.42]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=tw * 1.05, vertices=16,
                                                 location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.06, segments=3)
            objs.append(wh)

        # 履带齿条循环移动
        for i in range(6):
            t_y = -l * 0.42 + (i / 5.0) * (l * 0.84) + (frame / 6.0) * (l * 0.84 / 6.0)
            if t_y > l * 0.46:
                t_y -= l * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=tw * 1.02, vertices=10,
                                                 location=(x_pos, t_y, 0.30))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.025, segments=2)
            objs.append(tread)

    # ==================== 4. 炮塔基座与旋转平台 ====================
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=0.38, vertices=20,
                                         location=(0, -0.06, 0.44 + bob_z))
    turret_base = bpy.context.active_object
    turret_base.scale = (1.0, 0.95, 0.70)
    turret_base.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret_base, width=0.08, segments=3)
    objs.append(turret_base)

    # ==================== 5. 铰接式多轴工程吊臂 (Articulated Crane Boom) ====================
    # 机械臂随帧数微幅上下摆动 (呼吸感)
    arm_pitch = math.radians(32.0 + 8.0 * math.sin(frame * (2.0 * math.pi / 6.0)))
    jib_pitch = math.radians(-45.0 - 6.0 * math.cos(frame * (2.0 * math.pi / 6.0)))

    # 主臂 (Main Boom)
    boom_len = 0.85
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.12, 0.65 + bob_z))
    boom = bpy.context.active_object
    boom.scale = (0.16, boom_len, 0.14)
    boom.rotation_euler = (arm_pitch, 0, 0)
    boom.data.materials.append(mat_body)
    apply_uniform_clay_bevel(boom, width=0.03, segments=2)
    objs.append(boom)

    # 铰接转轴球 (Joint Pivot)
    joint_pos = (0, 0.12 + boom_len * math.cos(arm_pitch) * 0.48,
                 0.65 + bob_z + boom_len * math.sin(arm_pitch) * 0.48)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=joint_pos)
    joint = bpy.context.active_object
    joint.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(joint)

    # 副臂/前臂 (Jib)
    jib_len = 0.65
    jib_center = (joint_pos[0],
                  joint_pos[1] + (jib_len * 0.5) * math.cos(arm_pitch + jib_pitch),
                  joint_pos[2] + (jib_len * 0.5) * math.sin(arm_pitch + jib_pitch))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=jib_center)
    jib = bpy.context.active_object
    jib.scale = (0.12, jib_len, 0.11)
    jib.rotation_euler = (arm_pitch + jib_pitch, 0, 0)
    jib.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(jib, width=0.02, segments=2)
    objs.append(jib)

    # 机械臂末端：三爪液压工程抓手 (Hydraulic 3-Finger Claws)
    claw_base_pos = (joint_pos[0],
                     joint_pos[1] + jib_len * math.cos(arm_pitch + jib_pitch),
                     joint_pos[2] + jib_len * math.sin(arm_pitch + jib_pitch))

    claw_rot_angles = [0, 120, 240]
    claw_open = 0.18 + 0.05 * math.sin(frame * (2.0 * math.pi / 6.0)) # 爪瓣张合动画

    for deg in claw_rot_angles:
        rad = math.radians(deg)
        cx = claw_base_pos[0] + math.sin(rad) * claw_open
        cy = claw_base_pos[1] + math.cos(rad) * claw_open * 0.5
        cz = claw_base_pos[2] - 0.12

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
        claw = bpy.context.active_object
        claw.scale = (0.05, 0.07, 0.22)
        claw.rotation_euler = (math.radians(-15), math.radians(15 * math.sin(rad)), 0)
        claw.data.materials.append(mat_turret)
        apply_uniform_clay_bevel(claw, width=0.015, segments=2)
        objs.append(claw)

    # ==================== 6. 顶部旋转琥珀警示灯 (Amber Beacon) ====================
    beacon_rot = frame * (2.0 * math.pi / 6.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.18, vertices=12,
                                         location=(-0.30, -0.22, 0.72 + bob_z))
    beacon = bpy.context.active_object
    beacon.rotation_euler = (0, 0, beacon_rot)
    beacon.data.materials.append(mat_beacon)
    apply_uniform_clay_bevel(beacon, width=0.02, segments=2)
    objs.append(beacon)

    # 警示灯黑色防护支架
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.06, vertices=12,
                                         location=(-0.30, -0.22, 0.62 + bob_z))
    beacon_stand = bpy.context.active_object
    beacon_stand.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(beacon_stand, width=0.015, segments=2)
    objs.append(beacon_stand)

    # ==================== 7. 车尾建筑构件与零件箱 (Material Crate) ====================
    for cx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, -0.52, 0.42 + bob_z))
        crate = bpy.context.active_object
        crate.scale = (0.28, 0.32, 0.26)
        crate.data.materials.append(mat_crate)
        apply_uniform_clay_bevel(crate, width=0.03, segments=2)
        objs.append(crate)

    return objs


def render_all_engineer_tanks():
    """渲染工程坦克全套 6 帧动画及图标"""
    print(">>> 正在初始化 Blender Cycles 工程坦克渲染场景...")

    # 1. 玩家/中立版工程坦克 6 帧 (tank_engineer_f0 ~ f5)
    print("\n--- 渲染工程坦克 6 帧动画 (tank_engineer_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_engineer_tank(frame=f, is_enemy=False)
        out_path = os.path.join(SPRITES_TANKS, f"tank_engineer_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染帧 {f}/5 -> {out_path}")

    # 2. 敌方工程坦克 6 帧 (enemy_engineer_f0 ~ f5)
    print("\n--- 渲染敌方工程坦克 6 帧动画 (enemy_engineer_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_engineer_tank(frame=f, is_enemy=True)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_engineer_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染敌方帧 {f}/5 -> {out_path}")

    # 3. 静态图鉴图标 (tank_engineer.png)
    clear_scene()
    setup_render_settings(rx=256, ry=256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_engineer_tank(frame=0, is_enemy=False)
    icon_path = os.path.join(SPRITES_TANKS, "tank_engineer.png")
    render_and_clean(objs, icon_path)
    print(f"  [OK] 渲染工程坦克静态图标 -> {icon_path}")

    print("\n>>> 所有工程坦克模型动效与渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_engineer_tanks()
