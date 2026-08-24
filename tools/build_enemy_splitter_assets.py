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

# ==============================================================================
# 1. ENEMY SPLITTER MOTHER TANK (大型母体分裂坦克)
# ==============================================================================
def build_enemy_splitter(frame: int = 0):
    """Build a massive modular mother tank with 4 distinct sub-pod docks on corners."""
    objs = []
    
    # Palette: Dark Teal Hull, Slate Trim, Gold Reinforcement, Orange Core
    mat_hull = create_clay_mat(f"m_spt_hull_{frame}", (0.18, 0.36, 0.38, 1.0), roughness=0.45)
    mat_dark = create_clay_mat(f"m_spt_dark_{frame}", (0.12, 0.16, 0.18, 1.0), roughness=0.60)
    mat_gold = create_clay_mat(f"m_spt_gold_{frame}", (0.92, 0.72, 0.16, 1.0), roughness=0.35)
    mat_tread = create_clay_mat(f"m_spt_trd_{frame}", (0.10, 0.11, 0.12, 1.0), roughness=0.80)
    mat_core = create_clay_mat(f"m_spt_core_{frame}", (0.98, 0.45, 0.15, 1.0), emission=(0.98, 0.45, 0.15, 1.0), emission_str=4.0)
    mat_pod = create_clay_mat(f"m_spt_pod_{frame}", (0.24, 0.45, 0.48, 1.0), roughness=0.40)

    vib = math.sin(frame * math.pi) * 0.015

    # Main Heavy Chassis Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.18 + vib))
    hull = bpy.context.active_object
    hull.scale = (1.50, 1.60, 0.36)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.08, segments=2)
    objs.append(hull)

    # Heavy Quad Tread Units (Wide stable base)
    for x_side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side * 0.95, -0.05, 0.14))
        trd = bpy.context.active_object
        trd.scale = (0.34, 1.80, 0.36)
        trd.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(trd, width=0.04, segments=2)
        objs.append(trd)

        # Armored Tread Guards
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_side * 0.95, -0.05, 0.34 + vib))
        guard = bpy.context.active_object
        guard.scale = (0.36, 1.70, 0.10)
        guard.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(guard, width=0.03, segments=2)
        objs.append(guard)

    # 4 Sub-Tank Docking Pods (Front-Left, Front-Right, Rear-Left, Rear-Right)
    pod_locs = [
        (-0.52, 0.48),  # Front-Left
        (0.52, 0.48),   # Front-Right
        (-0.52, -0.52), # Rear-Left
        (0.52, -0.52),  # Rear-Right
    ]
    for px, py in pod_locs:
        # Pod Housing Base
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 0.38 + vib))
        pod = bpy.context.active_object
        pod.scale = (0.42, 0.46, 0.22)
        pod.data.materials.append(mat_pod)
        apply_uniform_clay_bevel(pod, width=0.03, segments=2)
        objs.append(pod)

        # Pod Mini Turret Dome
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.12, vertices=12, location=(px, py, 0.52 + vib))
        p_dome = bpy.context.active_object
        p_dome.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(p_dome, width=0.02, segments=2)
        objs.append(p_dome)

        # Mini Barrel pointing outward
        b_angle = math.atan2(py, px)
        b_dist = 0.22
        bx = px + math.cos(b_angle) * b_dist
        by = py + math.sin(b_angle) * b_dist
        bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.16, vertices=8, location=(bx, by, 0.52 + vib))
        p_bar = bpy.context.active_object
        p_bar.rotation_euler = (math.radians(90), 0, b_angle - math.pi/2)
        p_bar.data.materials.append(mat_dark)
        objs.append(p_bar)

    # Central Reactor Core / Heavy Command Tower
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.32, vertices=16, location=(0, -0.05, 0.44 + vib))
    core_tower = bpy.context.active_object
    core_tower.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(core_tower, width=0.05, segments=2)
    objs.append(core_tower)

    # Glowing Fissure / Splitter Core Indicator
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.36, vertices=16, location=(0, -0.05, 0.46 + vib))
    core_glow = bpy.context.active_object
    core_glow.data.materials.append(mat_core)
    objs.append(core_glow)

    # Dual Heavy Siege Cannons
    for c_side in [-0.18, 0.18]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=0.85, vertices=12, location=(c_side, 0.50, 0.46 + vib))
        c_bar = bpy.context.active_object
        c_bar.rotation_euler = (math.radians(90), 0, 0)
        c_bar.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(c_bar, width=0.02, segments=2)
        objs.append(c_bar)

        # Muzzle Rings
        bpy.ops.mesh.primitive_cylinder_add(radius=0.095, depth=0.12, vertices=12, location=(c_side, 0.90, 0.46 + vib))
        c_mzl = bpy.context.active_object
        c_mzl.rotation_euler = (math.radians(90), 0, 0)
        c_mzl.data.materials.append(mat_gold)
        objs.append(c_mzl)

    return objs


# ==============================================================================
# 2. ENEMY SPLIT MINI TANK (小型分裂战车)
# ==============================================================================
def build_enemy_split_mini(frame: int = 0):
    """Build an agile, compact mini-tank spawned when Splitter explodes."""
    objs = []
    
    # Palette matching mother tank
    mat_hull = create_clay_mat(f"m_min_hull_{frame}", (0.24, 0.45, 0.48, 1.0), roughness=0.40)
    mat_dark = create_clay_mat(f"m_min_dark_{frame}", (0.12, 0.16, 0.18, 1.0), roughness=0.60)
    mat_gold = create_clay_mat(f"m_min_gold_{frame}", (0.92, 0.72, 0.16, 1.0), roughness=0.35)
    mat_tread = create_clay_mat(f"m_min_trd_{frame}", (0.10, 0.11, 0.12, 1.0), roughness=0.80)
    mat_eye = create_clay_mat(f"m_min_eye_{frame}", (0.98, 0.45, 0.15, 1.0), emission=(0.98, 0.45, 0.15, 1.0), emission_str=3.5)

    vib = math.sin(frame * math.pi) * 0.02
    
    # Compact Agile Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.16 + vib))
    hull = bpy.context.active_object
    hull.scale = (0.75, 0.85, 0.28)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.05, segments=2)
    objs.append(hull)

    # Front Wedge Nose
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.38, 0.14 + vib))
    nose = bpy.context.active_object
    nose.scale = (0.55, 0.25, 0.18)
    nose.rotation_euler = (math.radians(-15), 0, 0)
    nose.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(nose, width=0.03, segments=2)
    objs.append(nose)

    # Speedy Mini Treads
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.48, -0.04, 0.12))
        trd = bpy.context.active_object
        trd.scale = (0.18, 0.95, 0.26)
        trd.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(trd, width=0.02, segments=2)
        objs.append(trd)

    # Mini Turret Dome
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.20, vertices=12, location=(0, -0.05, 0.34 + vib))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(turret, width=0.03, segments=2)
    objs.append(turret)

    # Glowing Optical Sensor Eye
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.16, 0.36 + vib))
    eye = bpy.context.active_object
    eye.scale = (0.18, 0.08, 0.08)
    eye.data.materials.append(mat_eye)
    objs.append(eye)

    # Fast Peashooter Gun Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.55, vertices=8, location=(0, 0.38, 0.34 + vib))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(barrel, width=0.012, segments=2)
    objs.append(barrel)

    return objs


# ==============================================================================
# MAIN BATCH RENDER ORCHESTRATOR
# ==============================================================================
def main():
    print("==================================================================")
    print(">>> RENDERING SPLITTER & MINI SPLIT TANK SPRITE FRAMES <<<")
    print("==================================================================")

    render_tasks = [
        ("enemy_splitter", build_enemy_splitter),
        ("enemy_split_mini", build_enemy_split_mini),
    ]

    for prefix, builder_func in render_tasks:
        print(f"\n[BUILDING & RENDERING] {prefix} (6 frames)...")
        for frame in range(6):
            clear_scene()
            setup_render_settings(256, 256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)

            objs = builder_func(frame=frame)

            out_file = os.path.join(SPRITES_TANKS, f"{prefix}_f{frame}.png")
            render_and_clean(objs, out_file)
            print(f"  [OK] {prefix} frame {frame} -> {out_file}")

    print("\n>>> ALL SPLITTER & MINI TANK SPRITES SUCCESSFULLY RENDERED! <<<")

if __name__ == "__main__":
    main()
