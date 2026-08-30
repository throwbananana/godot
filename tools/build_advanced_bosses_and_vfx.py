"""build_advanced_bosses_and_vfx.py — Blender 5.2+ LTS Boss 建模、动作与动效渲染管线

渲染 3 大史诗级 Boss 及其 6 帧动画序列，以及 2 套专属 Boss 动效：
  1. enemy_titan_boss (巨型无畏战列泰坦 Boss - Act 1 平原/遗迹终极首领)
     - 6 帧履带行进、双联主炮交替后坐力动画、等离子核心脉冲发光、顶部雷达旋转
  2. enemy_scorpion_boss (沙漠机械巨蝎 Boss - Act 2 沙漠终极首领)
     - 6 帧多节机械毒刺尾摆动、双前螯机械爪张合开火、六足三角步态行走动作
  3. enemy_mammoth_boss (极地猛犸重装机甲 Boss - Act 3 极地终极首领)
     - 6 帧四足重型液压步行步态、双联极寒榴弹炮、霜冻巨牙与极寒冰晶核心
  4. boss_plasma_nova (Boss 耀斑等离子爆震动效 - 6 帧扩散耗散特效)
  5. boss_frost_nova (Boss 极地极寒冰霜新星动效 - 6 帧冰晶碎裂与冰雾耗散特效)
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
    ORTHO_SCALE_DEFAULT,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)


# ==============================================================================
# 1. MEGA DREADNOUGHT TITAN BOSS (巨型无畏战列泰坦)
# ==============================================================================

def build_titan_boss(frame=0):
    objs = []
    # Palette
    mat_hull  = create_clay_mat(f"tt_hull_{frame}",  (0.18, 0.20, 0.26, 1.0), roughness=0.65)
    mat_armor = create_clay_mat(f"tt_armor_{frame}", (0.28, 0.32, 0.40, 1.0), roughness=0.55)
    mat_gold  = create_clay_mat(f"tt_gold_{frame}",  (0.96, 0.78, 0.22, 1.0), roughness=0.40)
    mat_track = create_clay_mat(f"tt_track_{frame}", (0.16, 0.15, 0.18, 1.0), roughness=0.88)
    mat_dark  = create_clay_mat(f"tt_dark_{frame}",  (0.08, 0.08, 0.10, 1.0), roughness=0.92)

    # Core pulse formula
    core_pulse = 2.2 + 1.2 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_core  = create_clay_mat(f"tt_core_{frame}",  (0.35, 0.88, 0.98, 1.0), emission=(0.35, 0.88, 0.98, 1.0), emission_str=core_pulse)
    mat_glow_red = create_clay_mat(f"tt_red_{frame}", (1.0, 0.25, 0.25, 1.0), emission=(1.0, 0.25, 0.25, 1.0), emission_str=2.5)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # 1.1 Massive Hull Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.68, 1.76, 0.58)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.16, segments=4)
    objs.append(hull)

    # Sloped Front Ram Glacis Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.78, 0.04 + bob_z))
    glacis = bpy.context.active_object
    glacis.scale = (1.52, 0.44, 0.38)
    glacis.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(glacis, width=0.10, segments=3)
    objs.append(glacis)

    # Central Glowing Energy Core Vents
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.18, vertices=16, location=(0, 0.15, 0.32 + bob_z))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    apply_uniform_clay_bevel(core, width=0.04, segments=2)
    objs.append(core)

    # Gold Vent Grille over reactor
    for gy in [-0.08, 0.0, 0.08]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.15 + gy, 0.42 + bob_z))
        grille = bpy.context.active_object
        grille.scale = (0.52, 0.04, 0.06)
        grille.data.materials.append(mat_gold)
        objs.append(grille)

    # 1.2 Quad Heavy Tread Pods (Left and Right)
    for x_side in [-1.02, 1.02]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side, 0, 0))
        tpod = bpy.context.active_object
        tpod.scale = (0.42, 1.95, 0.68)
        tpod.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tpod, width=0.15, segments=4)
        objs.append(tpod)

        # 4 Roadwheels per side
        for wy in [-0.70, -0.23, 0.23, 0.70]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=0.46, vertices=16, location=(x_side, wy, 0))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), 0)
            wheel.data.materials.append(mat_armor)
            apply_uniform_clay_bevel(wheel, width=0.06, segments=2)
            objs.append(wheel)

            # Wheel Cap
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(x_side + (0.12 if x_side > 0 else -0.12), wy, 0))
            cap = bpy.context.active_object
            cap.data.materials.append(mat_gold)
            objs.append(cap)

    # 1.3 Heavy Turret Base
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.25, 0.42 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.20, 1.25, 0.46)
    turret.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(turret, width=0.14, segments=3)
    objs.append(turret)

    # Dual Massive Siege Barrels (Alternating recoil)
    # Left barrel recoils during frame 0, 1, 2
    # Right barrel recoils during frame 3, 4, 5
    l_recoil = -0.15 * math.sin((frame % 3) * (math.pi / 2.0)) if frame < 3 else 0.0
    r_recoil = -0.15 * math.sin(((frame - 3) % 3) * (math.pi / 2.0)) if frame >= 3 else 0.0

    for bx, rec in [(-0.35, l_recoil), (0.35, r_recoil)]:
        # Mantlet
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.35 + rec, 0.42 + bob_z))
        mnt = bpy.context.active_object
        mnt.scale = (0.34, 0.38, 0.32)
        mnt.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(mnt, width=0.06, segments=2)
        objs.append(mnt)

        # Long Heavy Siege Barrel
        bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=1.20, vertices=16, location=(bx, 0.90 + rec, 0.42 + bob_z))
        bar = bpy.context.active_object
        bar.rotation_euler = (math.radians(90), 0, 0)
        bar.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(bar, width=0.03, segments=2)
        objs.append(bar)

        # Muzzle Brake
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.24, vertices=16, location=(bx, 1.48 + rec, 0.42 + bob_z))
        mb = bpy.context.active_object
        mb.rotation_euler = (math.radians(90), 0, 0)
        mb.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(mb, width=0.04, segments=2)
        objs.append(mb)

        # Bore hole
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.12, vertices=12, location=(bx, 1.56 + rec, 0.42 + bob_z))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_dark)
        objs.append(bore)

    # 1.4 Rotating Radar Dish & Command Antenna
    radar_rot = frame * (2.0 * math.pi / 6.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.08, vertices=16, location=(-0.36, -0.65, 0.72 + bob_z))
    radar = bpy.context.active_object
    radar.rotation_euler = (math.radians(35), 0, radar_rot)
    radar.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(radar, width=0.03, segments=2)
    objs.append(radar)

    # Flashing warning beacon on turret
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0.38, -0.65, 0.74 + bob_z))
    beacon = bpy.context.active_object
    beacon.data.materials.append(mat_glow_red if (frame % 2 == 0) else mat_gold)
    objs.append(beacon)

    return objs


# ==============================================================================
# 2. DESERT SCORPION MECH BOSS (沙漠机械巨蝎)
# ==============================================================================

def build_scorpion_boss(frame=0):
    objs = []
    # Camo Terracotta & Dark Brass palette
    mat_body   = create_clay_mat(f"sc_body_{frame}",   (0.76, 0.46, 0.24, 1.0), roughness=0.68)
    mat_plate  = create_clay_mat(f"sc_plate_{frame}",  (0.88, 0.62, 0.32, 1.0), roughness=0.58)
    mat_metal  = create_clay_mat(f"sc_metal_{frame}",  (0.24, 0.22, 0.26, 1.0), roughness=0.50)
    mat_gold   = create_clay_mat(f"sc_gold_{frame}",   (0.92, 0.72, 0.22, 1.0), roughness=0.40)
    mat_stinger= create_clay_mat(f"sc_sting_{frame}",  (1.00, 0.45, 0.12, 1.0), emission=(1.0, 0.45, 0.12, 1.0), emission_str=3.0)
    mat_eye    = create_clay_mat(f"sc_eye_{frame}",    (0.98, 0.88, 0.20, 1.0), emission=(0.98, 0.88, 0.20, 1.0), emission_str=2.5)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.02

    # 2.1 Main Thorax / Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.08 + bob_z))
    body = bpy.context.active_object
    body.scale = (1.35, 1.45, 0.52)
    body.data.materials.append(mat_body)
    apply_uniform_clay_bevel(body, width=0.16, segments=4)
    objs.append(body)

    # Segmented Armor Carapace Plates
    for idx, py in enumerate([-0.50, -0.15, 0.20, 0.50]):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, py, 0.35 + bob_z))
        plate = bpy.context.active_object
        plate.scale = (1.18 - idx * 0.08, 0.28, 0.14)
        plate.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(plate, width=0.05, segments=2)
        objs.append(plate)

    # Glowing Sensor Eyes (Cluster of 4)
    for ex in [-0.28, -0.10, 0.10, 0.28]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex, 0.64, 0.18 + bob_z))
        eye = bpy.context.active_object
        eye.data.materials.append(mat_eye)
        objs.append(eye)

    # 2.2 Articulated Scorpion Stinger Tail (5 Segments arching up and forward)
    tail_sway_x = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.10
    tail_curve_y = math.cos(frame * (2.0 * math.pi / 6.0)) * 0.06

    tail_nodes = [
        (0.0, -0.75, 0.25),
        (tail_sway_x * 0.2, -1.05, 0.55),
        (tail_sway_x * 0.5, -1.15, 0.95),
        (tail_sway_x * 0.8, -0.85 + tail_curve_y, 1.30),
        (tail_sway_x, -0.35 + tail_curve_y, 1.42),
    ]

    for i in range(len(tail_nodes) - 1):
        p1 = tail_nodes[i]
        p2 = tail_nodes[i+1]
        mid = ((p1[0]+p2[0])*0.5, (p1[1]+p2[1])*0.5, (p1[2]+p2[2])*0.5)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=mid)
        seg = bpy.context.active_object
        seg.scale = (0.42 - i*0.04, 0.42 - i*0.04, 0.42 - i*0.04)
        seg.data.materials.append(mat_body if i % 2 == 0 else mat_plate)
        apply_uniform_clay_bevel(seg, width=0.08, segments=3)
        objs.append(seg)

    # Heavy Stinger Cannon at the tip
    tip_pos = tail_nodes[-1]
    bpy.ops.mesh.primitive_cone_add(radius1=0.22, radius2=0.04, depth=0.62, location=(tip_pos[0], tip_pos[1] + 0.32, tip_pos[2]))
    stinger = bpy.context.active_object
    stinger.rotation_euler = (math.radians(-90), 0, 0)
    stinger.data.materials.append(mat_stinger)
    apply_uniform_clay_bevel(stinger, width=0.05, segments=2)
    objs.append(stinger)

    # 2.3 Dual Front Pincer Turrets (Left & Right)
    claw_ang = math.radians(16 + 12 * math.cos(frame * (2.0 * math.pi / 6.0)))
    for side in [-1, 1]:
        # Shoulder Joint
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(side * 0.72, 0.45, 0.12 + bob_z))
        sh = bpy.context.active_object
        sh.data.materials.append(mat_metal)
        objs.append(sh)

        # Forearm
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.95, 0.85, 0.12 + bob_z))
        arm = bpy.context.active_object
        arm.scale = (0.28, 0.65, 0.26)
        arm.rotation_euler = (0, 0, side * math.radians(-25))
        arm.data.materials.append(mat_body)
        apply_uniform_clay_bevel(arm, width=0.06, segments=2)
        objs.append(arm)

        # Outer Claw
        bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.04, depth=0.55, location=(side * 1.05, 1.25, 0.12 + bob_z))
        c_out = bpy.context.active_object
        c_out.rotation_euler = (math.radians(90), 0, side * claw_ang)
        c_out.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(c_out, width=0.04, segments=2)
        objs.append(c_out)

        # Inner Claw
        bpy.ops.mesh.primitive_cone_add(radius1=0.16, radius2=0.03, depth=0.48, location=(side * 0.85, 1.22, 0.12 + bob_z))
        c_in = bpy.context.active_object
        c_in.rotation_euler = (math.radians(90), 0, side * -claw_ang)
        c_in.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(c_in, width=0.04, segments=2)
        objs.append(c_in)

    # 2.4 Six Walking Legs (3 per side with walking gait)
    for l_idx, (ly, phase) in enumerate([(-0.45, 0), (0.0, math.pi), (0.45, 0)]):
        leg_step = math.sin(frame * (2.0 * math.pi / 6.0) + phase) * 0.12
        for side in [-1, 1]:
            # Hip to Knee
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * (0.85 + abs(leg_step)*0.5), ly + leg_step, 0.10 + bob_z))
            upper = bpy.context.active_object
            upper.scale = (0.55, 0.16, 0.14)
            upper.rotation_euler = (0, side * math.radians(-30), 0)
            upper.data.materials.append(mat_metal)
            objs.append(upper)

            # Knee to Foot
            bpy.ops.mesh.primitive_cone_add(radius1=0.12, radius2=0.04, depth=0.58, location=(side * 1.22, ly + leg_step * 1.2, -0.16 + bob_z))
            lower = bpy.context.active_object
            lower.rotation_euler = (0, side * math.radians(45), 0)
            lower.data.materials.append(mat_plate)
            apply_uniform_clay_bevel(lower, width=0.03, segments=2)
            objs.append(lower)

    return objs


# ==============================================================================
# 3. GLACIAL MAMMOTH HEAVY MECH BOSS (极地猛犸重装机甲)
# ==============================================================================

def build_mammoth_boss(frame=0):
    objs = []
    # Frost White, Cryo Cyan, Dark Titanium & Cobalt Blue
    mat_white = create_clay_mat(f"mm_w_{frame}",    (0.86, 0.90, 0.95, 1.0), roughness=0.60)
    mat_blue  = create_clay_mat(f"mm_b_{frame}",    (0.24, 0.48, 0.78, 1.0), roughness=0.55)
    mat_metal = create_clay_mat(f"mm_m_{frame}",    (0.18, 0.20, 0.25, 1.0), roughness=0.75)
    mat_ice   = create_clay_mat(f"mm_ice_{frame}",  (0.40, 0.82, 0.95, 1.0), roughness=0.25)
    mat_cryo  = create_clay_mat(f"mm_cryo_{frame}", (0.50, 0.95, 1.00, 1.0), emission=(0.50, 0.95, 1.00, 1.0), emission_str=2.8)
    mat_gold  = create_clay_mat(f"mm_g_{frame}",    (0.92, 0.78, 0.30, 1.0), roughness=0.45)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.02

    # 3.1 Super-Heavy Colossus Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.35 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.50, 1.80, 0.85)
    hull.data.materials.append(mat_white)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # Front Sloped Heavy Ice Ram Armor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.85, 0.30 + bob_z))
    ram = bpy.context.active_object
    ram.scale = (1.35, 0.50, 0.65)
    ram.data.materials.append(mat_blue)
    apply_uniform_clay_bevel(ram, width=0.12, segments=3)
    objs.append(ram)

    # Dual Massive Frost Tusks in Front
    for side in [-1, 1]:
        # Tusk base
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.35, vertices=16, location=(side * 0.52, 0.95, 0.15 + bob_z))
        tb = bpy.context.active_object
        tb.rotation_euler = (math.radians(45), 0, side * math.radians(-15))
        tb.data.materials.append(mat_gold)
        objs.append(tb)

        # Sweeping Curved Tusk Blade (Cryo Ice Crystal)
        bpy.ops.mesh.primitive_cone_add(radius1=0.15, radius2=0.02, depth=0.92, location=(side * 0.65, 1.25, 0.38 + bob_z))
        tusk = bpy.context.active_object
        tusk.rotation_euler = (math.radians(70), side * math.radians(-25), side * math.radians(-15))
        tusk.data.materials.append(mat_ice)
        apply_uniform_clay_bevel(tusk, width=0.04, segments=3)
        objs.append(tusk)

    # 3.2 Dual Top Cryo-Howitzer Cannons
    for bx in [-0.42, 0.42]:
        # Howitzer Mount
        bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.38, vertices=16, location=(bx, -0.20, 0.85 + bob_z))
        hm = bpy.context.active_object
        hm.data.materials.append(mat_blue)
        apply_uniform_clay_bevel(hm, width=0.05, segments=2)
        objs.append(hm)

        # Heavy Short Cryo Barrel
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.75, vertices=16, location=(bx, 0.25, 0.85 + bob_z))
        bar = bpy.context.active_object
        bar.rotation_euler = (math.radians(90), 0, 0)
        bar.data.materials.append(mat_white)
        apply_uniform_clay_bevel(bar, width=0.04, segments=2)
        objs.append(bar)

        # Ice Crown Muzzle
        bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.20, vertices=16, location=(bx, 0.65, 0.85 + bob_z))
        mz = bpy.context.active_object
        mz.rotation_euler = (math.radians(90), 0, 0)
        mz.data.materials.append(mat_ice)
        apply_uniform_clay_bevel(mz, width=0.03, segments=2)
        objs.append(mz)

    # Central Cryo Pulsing Gemstone
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, -0.45, 0.82 + bob_z))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_cryo)
    objs.append(gem)

    # 3.3 Four Colossal Hydraulic Walker Legs (Walking Gait)
    leg_coords = [
        (-0.95,  0.65, 0),
        ( 0.95,  0.65, math.pi),
        (-0.95, -0.65, math.pi),
        ( 0.95, -0.65, 0),
    ]

    for (lx, ly, phase) in leg_coords:
        step = math.sin(frame * (2.0 * math.pi / 6.0) + phase) * 0.15
        lift = max(0.0, math.cos(frame * (2.0 * math.pi / 6.0) + phase)) * 0.10

        # Hip Joint
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lx, ly, 0.25 + bob_z))
        hip = bpy.context.active_object
        hip.scale = (0.42, 0.42, 0.42)
        hip.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(hip, width=0.08, segments=2)
        objs.append(hip)

        # Pillar Leg
        bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.75, vertices=16, location=(lx, ly + step, -0.05 + lift + bob_z))
        leg = bpy.context.active_object
        leg.data.materials.append(mat_white)
        apply_uniform_clay_bevel(leg, width=0.05, segments=2)
        objs.append(leg)

        # Hydraulic Armor Pad / Foot
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lx, ly + step, -0.42 + lift + bob_z))
        foot = bpy.context.active_object
        foot.scale = (0.48, 0.52, 0.18)
        foot.data.materials.append(mat_blue)
        apply_uniform_clay_bevel(foot, width=0.06, segments=2)
        objs.append(foot)

    return objs


# ==============================================================================
# 4. BOSS PROCEDURAL VFX 1: PLASMA NOVA (等离子爆震动效 - 6 Frames)
# ==============================================================================

def build_boss_plasma_nova(frame=0):
    objs = []
    alpha = max(0.05, 1.0 - (frame / 5.0) * 0.85)
    em_str = max(0.2, 3.5 - frame * 0.65)

    mat_core = create_clay_mat(f"pn_c_{frame}", (0.95, 0.98, 1.0, alpha), emission=(0.4, 0.9, 1.0, 1.0), emission_str=em_str)
    mat_ring = create_clay_mat(f"pn_r_{frame}", (0.25, 0.65, 0.95, alpha), emission=(0.25, 0.65, 0.95, 1.0), emission_str=em_str * 0.7)

    if frame == 0:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(6):
            ang = i * (2.0 * math.pi / 6.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(math.cos(ang)*0.55, math.sin(ang)*0.55, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    elif frame == 1:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_cone_add(radius1=0.22, radius2=0.03, depth=0.75, location=(math.cos(ang)*0.85, math.sin(ang)*0.85, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    elif frame == 2:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_core)
        objs.append(c)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(math.cos(ang)*1.15, math.sin(ang)*1.15, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    elif frame == 3:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(math.cos(ang)*1.40, math.sin(ang)*1.40, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    elif frame == 4:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0) + 0.15
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(math.cos(ang)*1.62, math.sin(ang)*1.62, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    elif frame == 5:
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.25
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(math.cos(ang)*1.78, math.sin(ang)*1.78, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_ring)
            objs.append(sp)

    return objs


# ==============================================================================
# 5. BOSS PROCEDURAL VFX 2: FROST NOVA (极寒冰霜新星动效 - 6 Frames)
# ==============================================================================

def build_boss_frost_nova(frame=0):
    objs = []
    alpha = max(0.05, 1.0 - (frame / 5.0) * 0.85)
    em_str = max(0.15, 3.2 - frame * 0.60)

    mat_crystal = create_clay_mat(f"fn_c_{frame}", (0.90, 0.98, 1.0, alpha), emission=(0.6, 0.95, 1.0, 1.0), emission_str=em_str)
    mat_frost   = create_clay_mat(f"fn_f_{frame}", (0.45, 0.80, 0.95, alpha), roughness=0.35)

    if frame == 0:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_crystal)
        objs.append(c)
        for i in range(6):
            ang = i * (2.0 * math.pi / 6.0)
            bpy.ops.mesh.primitive_cone_add(radius1=0.15, radius2=0.02, depth=0.55, location=(math.cos(ang)*0.52, math.sin(ang)*0.52, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_frost)
            objs.append(sp)

    elif frame == 1:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.58, location=(0, 0, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_crystal)
        objs.append(c)
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.85, vertices=6, location=(math.cos(ang)*0.88, math.sin(ang)*0.88, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_frost)
            objs.append(sp)

    elif frame == 2:
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.03, depth=0.62, location=(math.cos(ang)*1.15, math.sin(ang)*1.15, 0))
            sp = bpy.context.active_object
            sp.rotation_euler = (0, math.radians(90), ang)
            sp.data.materials.append(mat_crystal)
            objs.append(sp)

    elif frame == 3:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(math.cos(ang)*1.38, math.sin(ang)*1.38, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_frost)
            objs.append(sp)

    elif frame == 4:
        for i in range(10):
            ang = i * (2.0 * math.pi / 10.0) + 0.12
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(math.cos(ang)*1.58, math.sin(ang)*1.58, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_frost)
            objs.append(sp)

    elif frame == 5:
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0) + 0.22
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(math.cos(ang)*1.74, math.sin(ang)*1.74, 0))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_frost)
            objs.append(sp)

    return objs


# ==============================================================================
# MAIN BATCH RENDERER
# ==============================================================================

def main():
    clear_scene()
    reset_jitter_seed(3500)

    # 1. Titan Dreadnought Boss (6 Frames + Base Icon)
    print(">>> 1. Rendering Titan Dreadnought Boss (6 Frames)...")
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=3.85)
    for frame in range(6):
        objs = build_titan_boss(frame)
        out_fn = f"enemy_titan_boss_f{frame}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, out_fn))
        if frame == 0:
            render_and_clean(build_titan_boss(0), os.path.join(SPRITES_TANKS, "enemy_titan_boss.png"))

    # 2. Desert Mech Scorpion Boss (6 Frames + Base Icon)
    # 之前误用了 ORTHO_SCALE_TANK (3.6, 普通坦克的窄镜头), 跟同批的另外两个
    # boss (titan/mammoth) 不一致 —— 它们都用更宽的 3.85 给魁梧的 boss 几何
    # 留出画幅余量。镜头太窄导致 scorpion_boss 包围盒吃到画布的 66%
    # (210x206px), 而 mammoth_boss 只有 44% (162x179px)、经典 enemy_boss
    # 48% (178x178px) —— 摆在一起 scorpion_boss 明显鼓出来一截。
    print(">>> 2. Rendering Desert Mech Scorpion Boss (6 Frames)...")
    create_sokpop_lighting(ortho_scale=3.85)
    for frame in range(6):
        objs = build_scorpion_boss(frame)
        out_fn = f"enemy_scorpion_boss_f{frame}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, out_fn))
        if frame == 0:
            render_and_clean(build_scorpion_boss(0), os.path.join(SPRITES_TANKS, "enemy_scorpion_boss.png"))

    # 3. Glacial Mammoth Mech Boss (6 Frames + Base Icon)
    print(">>> 3. Rendering Glacial Mammoth Mech Boss (6 Frames)...")
    create_sokpop_lighting(ortho_scale=3.85)
    for frame in range(6):
        objs = build_mammoth_boss(frame)
        out_fn = f"enemy_mammoth_boss_f{frame}.png"
        render_and_clean(objs, os.path.join(SPRITES_TANKS, out_fn))
        if frame == 0:
            render_and_clean(build_mammoth_boss(0), os.path.join(SPRITES_TANKS, "enemy_mammoth_boss.png"))

    # 4. Boss Plasma Nova VFX (6 Frames)
    print(">>> 4. Rendering Boss Plasma Nova VFX (6 Frames)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    for frame in range(6):
        objs = build_boss_plasma_nova(frame)
        out_fn = f"boss_plasma_nova_{frame}.png"
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, out_fn))

    # 5. Boss Frost Nova VFX (6 Frames)
    print(">>> 5. Rendering Boss Frost Nova VFX (6 Frames)...")
    for frame in range(6):
        objs = build_boss_frost_nova(frame)
        out_fn = f"boss_frost_nova_{frame}.png"
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, out_fn))

    print("\n>>> ALL ADVANCED BOSSES AND VFX RENDERED SUCCESSFULLY! <<<")


if __name__ == "__main__":
    main()
