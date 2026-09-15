"""build_new_enemies_and_vfx.py — Blender 5.2+ LTS 新型特色敌人与动效建模渲染管线

渲染 4 种全新战术敌人及其 6 帧完整动作动画，以及 2 套专属程序化 2D VFX 动效：
  1. enemy_tesla (特斯拉电弧磁暴战车 - 战术控场/连锁闪电)
     - 6 帧双特斯拉放电线圈高频电弧脉冲、磁通环旋转、履带驱动
  2. enemy_toxic (剧毒生化布雷车 - 区域封锁/酸液腐蚀)
     - 6 帧三联生化酸液储液罐波动、喷头液压泵动与排气、履带行进
  3. enemy_drone_carrier (蜂巢无人机航母战车 - 召唤系重甲母舰)
     - 6 帧背部蜂巢机库升降导轨开合、扫描天线旋转、信标灯闪烁
  4. enemy_drone_mini (四旋翼自爆轻型无人机 - 空中高速自爆单位)
     - 6 帧高速四旋翼旋转、悬停气动俯仰、红色自爆引信脉冲
  5. tesla_arc_spark (特斯拉高压电弧火花动效 - 6 帧电弧耗散特效)
  6. toxic_splash (生化剧毒酸液飞溅动效 - 6 帧酸液空心环耗散特效)
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
    reset_jitter_seed,
    render_and_clean,
    ORTHO_SCALE_TANK,
    ORTHO_SCALE_DEFAULT,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)


# ==============================================================================
# 1. TESLA COIL TANK (特斯拉电弧磁暴战车)
# ==============================================================================

def build_tesla_tank(frame=0):
    objs = []
    mat_hull   = create_clay_mat(f"ts_hull_{frame}",   (0.20, 0.22, 0.35, 1.0), roughness=0.60)
    mat_copper = create_clay_mat(f"ts_copper_{frame}", (0.85, 0.55, 0.25, 1.0), roughness=0.35)
    mat_dark   = create_clay_mat(f"ts_dark_{frame}",   (0.12, 0.12, 0.15, 1.0), roughness=0.85)
    mat_insul  = create_clay_mat(f"ts_insul_{frame}",  (0.92, 0.90, 0.82, 1.0), roughness=0.45)

    # Arc pulse brightness
    arc_pulse = 2.5 + 1.8 * math.sin(frame * (2.0 * math.pi / 6.0) * 2.0)
    mat_plasma = create_clay_mat(f"ts_plasma_{frame}", (0.30, 0.85, 1.0, 1.0), emission=(0.30, 0.85, 1.0, 1.0), emission_str=arc_pulse)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.01

    # 1.1 Main Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.42, 1.48, 0.48)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.12, segments=3)
    objs.append(hull)

    # 1.2 Dual Tread Pods
    for x_side in [-0.85, 0.85]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side, 0, 0))
        tpod = bpy.context.active_object
        tpod.scale = (0.35, 1.62, 0.52)
        tpod.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(tpod, width=0.08, segments=3)
        objs.append(tpod)

        # Wheels
        for wy in [-0.55, -0.18, 0.18, 0.55]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.38, vertices=12, location=(x_side, wy, -0.04))
            w = bpy.context.active_object
            w.rotation_euler = (0, math.radians(90), frame * math.radians(60))
            w.data.materials.append(mat_copper)
            objs.append(w)

    # 1.3 Central Capacitor Generator
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.32, vertices=16, location=(0, 0.0, 0.32 + bob_z))
    cap = bpy.context.active_object
    cap.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(cap, width=0.05, segments=2)
    objs.append(cap)

    # 1.4 Dual Tesla Coil Towers (Left & Right)
    for x_coil in [-0.42, 0.42]:
        # Ceramic insulator base
        for iz in [0.38, 0.50, 0.62]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.09, vertices=12, location=(x_coil, 0.10, iz + bob_z))
            ins = bpy.context.active_object
            ins.data.materials.append(mat_insul)
            objs.append(ins)

        # Central copper core rod
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.45, vertices=10, location=(x_coil, 0.10, 0.52 + bob_z))
        rod = bpy.context.active_object
        rod.data.materials.append(mat_copper)
        objs.append(rod)

        # Top Discharge Toroid Ring
        bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.07, location=(x_coil, 0.10, 0.74 + bob_z))
        torus = bpy.context.active_object
        torus.data.materials.append(mat_copper)
        objs.append(torus)

        # Glowing Plasma Core Spark inside Toroid
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(x_coil, 0.10, 0.74 + bob_z))
        spark = bpy.context.active_object
        spark.data.materials.append(mat_plasma)
        objs.append(spark)

    # 1.5 Animated Electric Arc Jump Between Coils
    arc_idx = frame % 3
    if arc_idx != 0:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.84, vertices=8, location=(0, 0.10 + (arc_idx - 1)*0.06, 0.75 + bob_z))
        arc = bpy.context.active_object
        arc.rotation_euler = (0, math.radians(90), 0)
        arc.data.materials.append(mat_plasma)
        objs.append(arc)

    return objs


# ==============================================================================
# 2. TOXIC ACID CHEMICAL SPREADER TANK (剧毒生化布雷车)
# ==============================================================================

def build_toxic_tank(frame=0):
    objs = []
    mat_hull   = create_clay_mat(f"tx_hull_{frame}",   (0.24, 0.35, 0.22, 1.0), roughness=0.65)
    mat_yellow = create_clay_mat(f"tx_yellow_{frame}", (0.92, 0.78, 0.15, 1.0), roughness=0.45)
    mat_dark   = create_clay_mat(f"tx_dark_{frame}",   (0.12, 0.14, 0.12, 1.0), roughness=0.88)
    mat_glass  = create_clay_mat(f"tx_glass_{frame}",  (0.35, 0.65, 0.40, 0.85), roughness=0.20)

    # Acid Glow Pulse
    acid_glow = 2.4 + 1.2 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_acid = create_clay_mat(f"tx_acid_{frame}", (0.45, 0.95, 0.15, 1.0), emission=(0.45, 0.95, 0.15, 1.0), emission_str=acid_glow)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 2.1 Heavy Sloped Low Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.45, 1.55, 0.46)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.12, segments=3)
    objs.append(hull)

    # Hazard Stripe Decals on Front Glacis
    for hx in [-0.45, -0.15, 0.15, 0.45]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(hx, 0.65, 0.15 + bob_z))
        hstr = bpy.context.active_object
        hstr.scale = (0.10, 0.32, 0.10)
        hstr.rotation_euler = (0, 0, math.radians(45))
        hstr.data.materials.append(mat_yellow)
        objs.append(hstr)

    # 2.2 Dual Tread Pods
    for x_side in [-0.86, 0.86]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side, 0, 0))
        tpod = bpy.context.active_object
        tpod.scale = (0.34, 1.68, 0.50)
        tpod.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(tpod, width=0.08, segments=3)
        objs.append(tpod)

    # 2.3 Triple Chemical Acid Tanks (Rear)
    tank_coords = [(-0.38, -0.38), (0.0, -0.44), (0.38, -0.38)]
    for tx, ty in tank_coords:
        # Outer steel frame
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.62, vertices=16, location=(tx, ty, 0.38 + bob_z))
        canister = bpy.context.active_object
        canister.rotation_euler = (math.radians(90), 0, 0)
        canister.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(canister, width=0.03, segments=2)
        objs.append(canister)

        # Glowing Acid Viewport Core
        bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=0.48, vertices=12, location=(tx, ty, 0.38 + bob_z))
        core = bpy.context.active_object
        core.rotation_euler = (math.radians(90), 0, 0)
        core.data.materials.append(mat_acid)
        objs.append(core)

    # 2.4 Front Dual Chemical Spray Mortar Nozzles
    spray_ext = 0.04 * math.sin(frame * (2.0 * math.pi / 6.0))
    for nx in [-0.26, 0.26]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.55, vertices=12, location=(nx, 0.70 + spray_ext, 0.22 + bob_z))
        nozzle = bpy.context.active_object
        nozzle.rotation_euler = (math.radians(90), 0, 0)
        nozzle.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(nozzle, width=0.03, segments=2)
        objs.append(nozzle)

        # Nozzle rim
        bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.03, location=(nx, 0.98 + spray_ext, 0.22 + bob_z))
        rim = bpy.context.active_object
        rim.rotation_euler = (math.radians(90), 0, 0)
        rim.data.materials.append(mat_yellow)
        objs.append(rim)

    return objs


# ==============================================================================
# 3. DRONE CARRIER HIVE TANK (蜂巢无人机航母母舰战车)
# ==============================================================================

def build_drone_carrier(frame=0):
    objs = []
    mat_hull   = create_clay_mat(f"dc_hull_{frame}",   (0.65, 0.52, 0.32, 1.0), roughness=0.62)
    mat_armor  = create_clay_mat(f"dc_armor_{frame}",  (0.32, 0.28, 0.24, 1.0), roughness=0.55)
    mat_metal  = create_clay_mat(f"dc_metal_{frame}",  (0.18, 0.18, 0.20, 1.0), roughness=0.75)
    mat_yellow = create_clay_mat(f"dc_yellow_{frame}", (0.95, 0.75, 0.12, 1.0), roughness=0.40)
    mat_beacon = create_clay_mat(f"dc_beacon_{frame}", (1.0, 0.20, 0.20, 1.0), emission=(1.0, 0.20, 0.20, 1.0), emission_str=3.0)
    mat_cyan   = create_clay_mat(f"dc_cyan_{frame}",   (0.20, 0.90, 0.95, 1.0), emission=(0.20, 0.90, 0.95, 1.0), emission_str=2.0)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.01

    # 3.1 Wide Hexagonal Command Hull
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.48, vertices=6, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.18, 1.35, 1.0)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.10, segments=3)
    objs.append(hull)

    # 3.2 Heavy Tread Track Pods
    for x_side in [-0.94, 0.94]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side, 0, 0))
        tpod = bpy.context.active_object
        tpod.scale = (0.38, 1.82, 0.54)
        tpod.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(tpod, width=0.08, segments=3)
        objs.append(tpod)

    # 3.3 Hexagonal Drone Hangar Launch Bay (Top Deck)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.22, vertices=6, location=(0, -0.08, 0.32 + bob_z))
    bay = bpy.context.active_object
    bay.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(bay, width=0.04, segments=2)
    objs.append(bay)

    # Hangar Bay Door / Lift Platform Animation
    lift_z = 0.36 + 0.08 * math.sin(frame * (2.0 * math.pi / 6.0))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.34, depth=0.08, vertices=6, location=(0, -0.08, lift_z + bob_z))
    lift = bpy.context.active_object
    lift.data.materials.append(mat_yellow)
    objs.append(lift)

    # Interior Micro-Drone Silhouette on Launch Platform
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.08, lift_z + 0.08 + bob_z))
    d_mini = bpy.context.active_object
    d_mini.scale = (0.24, 0.24, 0.06)
    d_mini.data.materials.append(mat_metal)
    objs.append(d_mini)

    # 3.4 Rotating Command Radar & Sensor Array
    radar_ang = frame * (2.0 * math.pi / 6.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.15, vertices=12, location=(0, 0.58, 0.32 + bob_z))
    rad_base = bpy.context.active_object
    rad_base.data.materials.append(mat_armor)
    objs.append(rad_base)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.05, vertices=16, location=(0, 0.58, 0.44 + bob_z))
    dish = bpy.context.active_object
    dish.rotation_euler = (math.radians(25), 0, radar_ang)
    dish.data.materials.append(mat_cyan)
    objs.append(dish)

    # Blinking Signal Mast Beacon
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.28, vertices=8, location=(0.42, 0.38, 0.46 + bob_z))
    mast = bpy.context.active_object
    mast.data.materials.append(mat_metal)
    objs.append(mast)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(0.42, 0.38, 0.62 + bob_z))
    beacon = bpy.context.active_object
    beacon.data.materials.append(mat_beacon)
    objs.append(beacon)

    return objs


# ==============================================================================
# 4. ASSAULT MINI DRONE (四旋翼自爆轻型无人机)
# ==============================================================================

def build_drone_mini(frame=0):
    objs = []
    mat_body  = create_clay_mat(f"dm_body_{frame}",  (0.20, 0.20, 0.24, 1.0), roughness=0.50)
    mat_blade = create_clay_mat(f"dm_blade_{frame}", (0.85, 0.85, 0.90, 0.70), roughness=0.30)
    mat_arm   = create_clay_mat(f"dm_arm_{frame}",   (0.12, 0.12, 0.14, 1.0), roughness=0.80)
    mat_warn  = create_clay_mat(f"dm_warn_{frame}",  (0.95, 0.70, 0.10, 1.0), roughness=0.40)

    # Flashing Detonator Red Eye
    det_flash = 3.0 + 2.0 * math.sin(frame * (2.0 * math.pi / 6.0) * 3.0)
    mat_eye   = create_clay_mat(f"dm_eye_{frame}",   (1.0, 0.15, 0.15, 1.0), emission=(1.0, 0.15, 0.15, 1.0), emission_str=det_flash)

    # Hover bobbing & slight tilt
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.04
    tilt_y = math.radians(math.sin(frame * (2.0 * math.pi / 6.0)) * 4.0)

    # 4.1 Central Aerodynamic Fuselage
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, bob_z))
    body = bpy.context.active_object
    body.scale = (0.52, 0.64, 0.28)
    body.rotation_euler = (tilt_y, 0, 0)
    body.data.materials.append(mat_body)
    apply_uniform_clay_bevel(body, width=0.08, segments=3)
    objs.append(body)

    # Central Eye / Sensor Dome
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, 0.28, 0.04 + bob_z))
    eye = bpy.context.active_object
    eye.data.materials.append(mat_eye)
    objs.append(eye)

    # 4.2 4 Carbon Rotor Arms (X-Configuration)
    arm_positions = [
        (-0.48,  0.48),
        ( 0.48,  0.48),
        (-0.48, -0.48),
        ( 0.48, -0.48)
    ]

    prop_rot = frame * math.radians(120)  # High speed propeller blur rotation

    for ax, ay in arm_positions:
        # Arm strut
        bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.72, vertices=8, location=(ax*0.5, ay*0.5, bob_z))
        arm = bpy.context.active_object
        ang = math.atan2(ay, ax)
        arm.rotation_euler = (0, math.radians(90), ang)
        arm.data.materials.append(mat_arm)
        objs.append(arm)

        # Motor pod
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.16, vertices=12, location=(ax, ay, 0.05 + bob_z))
        motor = bpy.context.active_object
        motor.data.materials.append(mat_arm)
        objs.append(motor)

        # 2-Blade Propeller
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ax, ay, 0.14 + bob_z))
        prop = bpy.context.active_object
        prop.scale = (0.42, 0.07, 0.02)
        prop.rotation_euler = (0, 0, prop_rot + ang)
        prop.data.materials.append(mat_blade)
        objs.append(prop)

    # 4.3 Underbelly High-Explosive Charge Warhead
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0, -0.06, -0.16 + bob_z))
    warhead = bpy.context.active_object
    warhead.scale = (1.0, 1.25, 0.85)
    warhead.data.materials.append(mat_warn)
    apply_uniform_clay_bevel(warhead, width=0.03, segments=2)
    objs.append(warhead)

    return objs


# ==============================================================================
# 5. PROCEDURAL 2D VFX 1: TESLA ARC SPARK (特斯拉高压电弧火花 - 6 Frames)
# ==============================================================================

def build_tesla_arc_spark(frame=0):
    objs = []
    alpha = max(0.08, 1.0 - (frame / 5.0) * 0.82)
    em_str = max(0.20, 3.6 - frame * 0.65)

    mat_core = create_clay_mat(f"ts_c_{frame}", (0.95, 1.0, 1.0, alpha), emission=(0.95, 1.0, 1.0, 1.0), emission_str=em_str)
    mat_arc  = create_clay_mat(f"ts_a_{frame}", (0.25, 0.85, 1.0, alpha), emission=(0.25, 0.85, 1.0, 1.0), emission_str=em_str*0.8)

    if frame == 0:
        # Initial intense spark origin
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(4):
            ang = i * (2.0 * math.pi / 4.0) + 0.2
            bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.45, vertices=6, location=(math.cos(ang)*0.30, math.sin(ang)*0.30, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    elif frame == 1:
        # Peak branch lightning explosion
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.82, vertices=6, location=(math.cos(ang)*0.62, math.sin(ang)*0.62, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    elif frame == 2:
        # Center collapses, jagged electric ring
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.15
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.65, vertices=6, location=(math.cos(ang)*0.95, math.sin(ang)*0.95, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    elif frame == 3:
        # Expanding spark satellites
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(math.cos(ang)*1.25, math.sin(ang)*1.25, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    elif frame == 4:
        # Fading sparks
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.20
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(math.cos(ang)*1.52, math.sin(ang)*1.52, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    elif frame == 5:
        # Dissipated residual sparks (<20% peak coverage)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.35
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(math.cos(ang)*1.70, math.sin(ang)*1.70, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_arc)
            objs.append(sp)

    return objs


# ==============================================================================
# 6. PROCEDURAL 2D VFX 2: TOXIC ACID SPLASH (生化剧毒酸液飞溅 - 6 Frames)
# ==============================================================================

def build_toxic_splash(frame=0):
    objs = []
    alpha = max(0.06, 1.0 - (frame / 5.0) * 0.85)
    em_str = max(0.15, 3.0 - frame * 0.55)

    mat_core  = create_clay_mat(f"txs_c_{frame}", (0.90, 1.0, 0.40, alpha), emission=(0.90, 1.0, 0.40, 1.0), emission_str=em_str)
    mat_toxic = create_clay_mat(f"txs_t_{frame}", (0.42, 0.92, 0.15, alpha), roughness=0.35)

    if frame == 0:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(5):
            ang = i * (2.0 * math.pi / 5.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(math.cos(ang)*0.40, math.sin(ang)*0.40, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    elif frame == 1:
        # Peak area splash
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(math.cos(ang)*0.82, math.sin(ang)*0.82, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    elif frame == 2:
        # Hollow ring expansion
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.12
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(math.cos(ang)*1.12, math.sin(ang)*1.12, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    elif frame == 3:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(math.cos(ang)*1.36, math.sin(ang)*1.36, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    elif frame == 4:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0) + 0.15
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(math.cos(ang)*1.58, math.sin(ang)*1.58, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    elif frame == 5:
        # Final residual droplet dissipation (<20% peak coverage)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.25
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(math.cos(ang)*1.74, math.sin(ang)*1.74, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_toxic)
            objs.append(sp)

    return objs


# ==============================================================================
# MAIN RENDER PIPELINE
# ==============================================================================

def main():
    clear_scene()
    reset_jitter_seed(4200)

    print("==================================================")
    print(">>> BLENDER 5.2 NEW ENEMIES & VFX PIPELINE <<<")
    print("==================================================")

    setup_render_settings(rx=256, ry=256)

    # 1. Tesla Tank (6 Frames + Base Icon)
    print(">>> 1. Rendering Tesla Shock Tank (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for f in range(6):
        objs = build_tesla_tank(f)
        fn = f"enemy_tesla_f{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, fn))
        if f == 0:
            render_and_clean(build_tesla_tank(0), os.path.join(SPRITES_TANKS, "enemy_tesla.png"))
        print(f"Rendered: {fn}")

    # 2. Toxic Acid Spreader Tank (6 Frames + Base Icon)
    print(">>> 2. Rendering Toxic Acid Tank (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for f in range(6):
        objs = build_toxic_tank(f)
        fn = f"enemy_toxic_f{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, fn))
        if f == 0:
            render_and_clean(build_toxic_tank(0), os.path.join(SPRITES_TANKS, "enemy_toxic.png"))
        print(f"Rendered: {fn}")

    # 3. Drone Carrier Hive Tank (6 Frames + Base Icon)
    print(">>> 3. Rendering Drone Carrier Tank (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for f in range(6):
        objs = build_drone_carrier(f)
        fn = f"enemy_drone_carrier_f{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, fn))
        if f == 0:
            render_and_clean(build_drone_carrier(0), os.path.join(SPRITES_TANKS, "enemy_drone_carrier.png"))
        print(f"Rendered: {fn}")

    # 4. Assault Mini Drone (6 Frames + Base Icon)
    # 之前误用了 ORTHO_SCALE_DEFAULT (3.3, 道具用的窄镜头), 跟同批的
    # tesla/toxic/drone_carrier 三个坦克不一致 (它们都是 ORTHO_SCALE_TANK=3.6)。
    # ortho_scale 越小镜头拉得越近, 结果 drone_mini 的原始几何在画布里比例
    # 偏大了约 9% —— 而 enemy.gd::is_mini_scale_unit() 早就靠 sprite.scale
    # (0.14 对比普通敌人的 0.196) 把"迷你机"缩小了, 这个缩放系数是按"跟其它
    # 坦克同一套渲染基准"调的, 镜头错了就是在已经缩小的基础上再叠加一层。
    print(">>> 4. Rendering Assault Mini Drone (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for f in range(6):
        objs = build_drone_mini(f)
        fn = f"enemy_drone_mini_f{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, fn))
        if f == 0:
            render_and_clean(build_drone_mini(0), os.path.join(SPRITES_TANKS, "enemy_drone_mini.png"))
        print(f"Rendered: {fn}")

    # 5. Tesla Arc Spark VFX (6 Frames)
    print(">>> 5. Rendering Tesla Arc Spark VFX (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    for f in range(6):
        objs = build_tesla_arc_spark(f)
        fn = f"tesla_arc_spark_{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, fn))
        print(f"Rendered: {fn}")

    # 6. Toxic Splash VFX (6 Frames)
    print(">>> 6. Rendering Toxic Splash VFX (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    for f in range(6):
        objs = build_toxic_splash(f)
        fn = f"toxic_splash_{f}.png"
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, fn))
        print(f"Rendered: {fn}")

    print("\n>>> ALL NEW ENEMIES AND VFX RENDERED SUCCESSFULLY! <<<")


if __name__ == "__main__":
    main()
