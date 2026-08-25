"""build_spider_tank.py — 跳蛛坦克 (Spider Tank) 建模、6 帧仿生步态动效与 Cycles 黏土渲染管线

跳蛛坦克 (Spider Tank / Jumping Spider Tank):
  - 仿生蛛形战车底盘 (Cephalothorax Hull) + 剧毒暗紫/暗影黑涂装 + 荧光红复眼 (Multiple Glowing Ocelli)
  - 4 对分节机械液压蜘蛛腿 (8-Legged Articulated Suspension)，对角交替爬行步态
  - 背部跳跃高压液压储能囊 / 脉冲喷射器 (Jump Booster Pack)
  - 头部双联刺针毒素火炮 (Dual Needle Cannons)

输出资源:
  - assets/sprites/tanks/tank_spider_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_spider_f0.png ~ f5.png
  - assets/sprites/tanks/tank_spider.png
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


def build_spider_tank(frame: int = 0, is_enemy: bool = False):
    """构建跳蛛坦克 3D 模型与第 frame 帧 8 足爬行步态动效"""
    objs = []

    # 1. 材质定义
    if not is_enemy:
        col_body   = srgb_to_linear((0.35, 0.18, 0.48, 1.0)) # 幽能暗紫
        col_carapace = srgb_to_linear((0.20, 0.10, 0.30, 1.0)) # 几丁质深黑紫
        col_trim   = srgb_to_linear((0.75, 0.35, 0.95, 1.0)) # 荧光紫边缘
        col_eye    = srgb_to_linear((0.15, 0.95, 0.85, 1.0)) # 青色明眸复眼
    else:
        col_body   = srgb_to_linear((0.42, 0.12, 0.18, 1.0)) # 敌方暗血紫红
        col_carapace = srgb_to_linear((0.22, 0.08, 0.10, 1.0)) # 敌方暗骨黑
        col_trim   = srgb_to_linear((0.95, 0.25, 0.30, 1.0)) # 猩红反光边
        col_eye    = srgb_to_linear((1.00, 0.18, 0.10, 1.0)) # 凶煞猩红发光眼

    col_joint  = srgb_to_linear((0.28, 0.28, 0.32, 1.0)) # 液压球铰链金属
    col_steel  = srgb_to_linear((0.55, 0.58, 0.62, 1.0)) # 腿节液压杆
    col_booster= srgb_to_linear((0.85, 0.50, 0.10, 1.0)) # 跳跃推进喷口

    mat_body     = create_clay_mat("m_spd_b", col_body, roughness=0.55)
    mat_carapace = create_clay_mat("m_spd_cp", col_carapace, roughness=0.45)
    mat_trim     = create_clay_mat("m_spd_tm", col_trim, roughness=0.40)
    mat_joint    = create_clay_mat("m_spd_jt", col_joint, roughness=0.50)
    mat_steel    = create_clay_mat("m_spd_st", col_steel, roughness=0.35)

    # 发光复眼
    eye_glow = 4.5 + 2.0 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_eye = create_clay_mat("m_spd_eye", col_eye, emission=col_eye, emission_str=eye_glow)

    # 推进器喷口微光
    mat_booster = create_clay_mat("m_spd_bst", col_booster,
                                  emission=col_booster, emission_str=3.0)

    # 车身轻微呼吸起伏
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.016
    pitch = math.sin(frame * (2.0 * math.pi / 6.0)) * math.radians(1.8)

    # ==================== 1. 主车体：头胸装甲壳 (Cephalothorax) ====================
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0.05, 0.40 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.05, 1.25, 0.55)
    hull.rotation_euler = (pitch, 0, 0)
    hull.data.materials.append(mat_body)
    bpy.ops.object.shade_smooth()
    objs.append(hull)

    # 头部覆甲前端 (Chelicerae/Forehead Plate)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.62, 0.38 + bob_z))
    head_plate = bpy.context.active_object
    head_plate.scale = (0.72, 0.35, 0.30)
    head_plate.rotation_euler = (math.radians(-15) + pitch, 0, 0)
    head_plate.data.materials.append(mat_carapace)
    apply_uniform_clay_bevel(head_plate, width=0.06, segments=3)
    objs.append(head_plate)

    # ==================== 2. 蜘蛛发光复眼矩阵 (Cluster of 6 Ocelli) ====================
    eye_coords = [
        # (x, y, z, radius)
        (-0.18, 0.74, 0.45, 0.075), # 主眼中左
        ( 0.18, 0.74, 0.45, 0.075), # 主眼中右
        (-0.32, 0.68, 0.48, 0.055), # 侧眼上左
        ( 0.32, 0.68, 0.48, 0.055), # 侧眼上右
        (-0.34, 0.65, 0.38, 0.045), # 侧眼下左
        ( 0.34, 0.65, 0.38, 0.045), # 侧眼下右
    ]
    for ex, ey, ez, er in eye_coords:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=er, location=(ex, ey, ez + bob_z))
        eye = bpy.context.active_object
        eye.data.materials.append(mat_eye)
        bpy.ops.object.shade_smooth()
        objs.append(eye)

    # ==================== 3. 头部双联刺针毒素火炮 (Dual Needler Guns) ====================
    for bx in [-0.14, 0.14]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.055, depth=0.65, vertices=12,
                                             location=(bx, 0.88, 0.32 + bob_z))
        gun = bpy.context.active_object
        gun.rotation_euler = (math.radians(90) + pitch, 0, 0)
        gun.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(gun, width=0.015, segments=2)
        objs.append(gun)

        # 炮管枪口消焰套
        bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=0.14, vertices=12,
                                             location=(bx, 1.18, 0.32 + bob_z))
        tip = bpy.context.active_object
        tip.rotation_euler = (math.radians(90) + pitch, 0, 0)
        tip.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(tip, width=0.02, segments=2)
        objs.append(tip)

    # ==================== 4. 背部跳跃高压储能推进包 (Jump Booster Abdomen) ====================
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, -0.52, 0.48 + bob_z))
    booster = bpy.context.active_object
    booster.scale = (0.92, 1.15, 0.65)
    booster.rotation_euler = (math.radians(10) + pitch, 0, 0)
    booster.data.materials.append(mat_carapace)
    bpy.ops.object.shade_smooth()
    objs.append(booster)

    # 4 个倾斜脉冲矢量跳跃喷口
    thruster_positions = [
        (-0.25, -0.85, 0.38),
        ( 0.25, -0.85, 0.38),
        (-0.22, -0.78, 0.58),
        ( 0.22, -0.78, 0.58),
    ]
    for tx, ty, tz in thruster_positions:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.22, vertices=12,
                                             location=(tx, ty, tz + bob_z))
        nozzle = bpy.context.active_object
        nozzle.rotation_euler = (math.radians(-65), 0, math.radians(-15 if tx > 0 else 15))
        nozzle.data.materials.append(mat_booster)
        apply_uniform_clay_bevel(nozzle, width=0.02, segments=2)
        objs.append(nozzle)

    # ==================== 5. 仿生机械 8 爪 (8 Articulated Spider Legs) ====================
    # 4 对腿基座位置分布在身体两侧
    # 采用交替四足步态 (Alternating Tetrapod):
    # 组 A (左1, 左3, 右2, 右4) vs 组 B (左2, 左4, 右1, 右3)
    leg_anchors = [
        # (side_sign, base_y, base_rot_deg, group_id, len_mult)
        ( 1.0,  0.36,   40.0, 0, 1.05), # 右前腿 1
        ( 1.0,  0.10,   80.0, 1, 1.00), # 右中前腿 2
        ( 1.0, -0.16,  115.0, 0, 1.02), # 右中后腿 3
        ( 1.0, -0.42,  145.0, 1, 1.10), # 右后腿 4
        (-1.0,  0.36,  -40.0, 1, 1.05), # 左前腿 1
        (-1.0,  0.10,  -80.0, 0, 1.00), # 左中前腿 2
        (-1.0, -0.16, -115.0, 1, 1.02), # 左中后腿 3
        (-1.0, -0.42, -145.0, 0, 1.10), # 左后腿 4
    ]

    for side, ay, arot, grp, lmult in leg_anchors:
        # 相位步态偏移
        step_phase = (frame / 6.0) * (2.0 * math.pi) + (0.0 if grp == 0 else math.pi)
        leg_lift = max(0.0, math.sin(step_phase)) * 0.12 # 抬腿高度
        leg_swing = math.cos(step_phase) * math.radians(12.0) # 前后摆动

        # 1. 髋关节基座 (Coxa)
        cx = side * 0.48
        cy = ay
        cz = 0.32 + bob_z
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(cx, cy, cz))
        joint1 = bpy.context.active_object
        joint1.data.materials.append(mat_joint)
        bpy.ops.object.shade_smooth()
        objs.append(joint1)

        # 2. 大腿骨 (Femur) —— 向上向外拱起
        femur_len = 0.58 * lmult
        f_rot_yaw = math.radians(arot) + leg_swing
        f_rot_pitch = math.radians(35.0) + math.radians(leg_lift * 80.0)

        fx = cx + (femur_len * 0.5) * math.sin(f_rot_yaw) * math.cos(f_rot_pitch)
        fy = cy + (femur_len * 0.5) * math.cos(f_rot_yaw) * math.cos(f_rot_pitch)
        fz = cz + (femur_len * 0.5) * math.sin(f_rot_pitch)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(fx, fy, fz))
        femur = bpy.context.active_object
        femur.scale = (0.11, femur_len, 0.09)
        femur.rotation_euler = (f_rot_pitch, 0, -f_rot_yaw)
        femur.data.materials.append(mat_body)
        apply_uniform_clay_bevel(femur, width=0.02, segments=2)
        objs.append(femur)

        # 膝关节 (Knee Joint)
        kx = cx + femur_len * math.sin(f_rot_yaw) * math.cos(f_rot_pitch)
        ky = cy + femur_len * math.cos(f_rot_yaw) * math.cos(f_rot_pitch)
        kz = cz + femur_len * math.sin(f_rot_pitch)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085, location=(kx, ky, kz))
        knee = bpy.context.active_object
        knee.data.materials.append(mat_joint)
        bpy.ops.object.shade_smooth()
        objs.append(knee)

        # 3. 小腿/爪尖 (Tibia & Tarsus Claw) —— 向下插入地面
        tibia_len = 0.68 * lmult
        t_rot_pitch = math.radians(-62.0) + math.radians(leg_lift * 30.0)

        tx_pos = kx + (tibia_len * 0.5) * math.sin(f_rot_yaw) * math.cos(t_rot_pitch)
        ty_pos = ky + (tibia_len * 0.5) * math.cos(f_rot_yaw) * math.cos(t_rot_pitch)
        tz_pos = kz + (tibia_len * 0.5) * math.sin(t_rot_pitch)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=tibia_len, vertices=10,
                                             location=(tx_pos, ty_pos, tz_pos))
        tibia = bpy.context.active_object
        tibia.rotation_euler = (t_rot_pitch, 0, -f_rot_yaw)
        tibia.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(tibia, width=0.015, segments=2)
        objs.append(tibia)

        # 爪尖锋利针垫 (Claw Tip)
        tip_x = kx + tibia_len * math.sin(f_rot_yaw) * math.cos(t_rot_pitch)
        tip_y = ky + tibia_len * math.cos(f_rot_yaw) * math.cos(t_rot_pitch)
        tip_z = kz + tibia_len * math.sin(t_rot_pitch)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.04, location=(tip_x, tip_y, tip_z))
        foot = bpy.context.active_object
        foot.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(foot)

    return objs


def render_all_spider_tanks():
    """渲染跳蛛坦克全套 6 帧动画及图标"""
    print(">>> 正在初始化 Blender Cycles 跳蛛坦克渲染场景...")
    setup_render_settings(rx=256, ry=256, samples=32)

    # 1. 玩家/中立版跳蛛坦克 6 帧 (tank_spider_f0 ~ f5)
    print("\n--- 渲染跳蛛坦克 6 帧动画 (tank_spider_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_spider_tank(frame=f, is_enemy=False)
        out_path = os.path.join(SPRITES_TANKS, f"tank_spider_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染帧 {f}/5 -> {out_path}")

    # 2. 敌方跳蛛坦克 6 帧 (enemy_spider_f0 ~ f5)
    print("\n--- 渲染敌方跳蛛坦克 6 帧动画 (enemy_spider_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_spider_tank(frame=f, is_enemy=True)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_spider_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染敌方帧 {f}/5 -> {out_path}")

    # 3. 静态图鉴图标 (tank_spider.png)
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_spider_tank(frame=0, is_enemy=False)
    icon_path = os.path.join(SPRITES_TANKS, "tank_spider.png")
    render_and_clean(objs, icon_path)
    print(f"  [OK] 渲染跳蛛坦克静态图标 -> {icon_path}")

    print("\n>>> 所有跳蛛坦克模型动效与渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_spider_tanks()
