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
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")

def build_refined_repair_station():
    objs = []
    mat_chassis = create_clay_mat("m_rep_base", (0.24, 0.32, 0.28, 1.0), roughness=0.60)
    mat_panel = create_clay_mat("m_rep_pnl", (0.85, 0.88, 0.90, 1.0), roughness=0.45)
    mat_green = create_clay_mat("m_rep_green", (0.25, 0.95, 0.45, 1.0), emission=(0.25, 0.95, 0.45, 1.0), emission_str=3.8)
    mat_antenna = create_clay_mat("m_rep_ant", (0.88, 0.75, 0.20, 1.0), roughness=0.35)

    # 1. Hexagonal Heavy Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.94, depth=0.30, vertices=6, location=(0, 0, -0.08))
    base = bpy.context.active_object
    base.data.materials.append(mat_chassis)
    apply_uniform_clay_bevel(base, width=0.06, segments=2)
    objs.append(base)

    # 2. Medical Cross Panel Platform
    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.14, vertices=6, location=(0, 0, 0.12))
    pnl = bpy.context.active_object
    pnl.data.materials.append(mat_panel)
    apply_uniform_clay_bevel(pnl, width=0.03, segments=2)
    objs.append(pnl)

    # 3. Luminous Medical Cross in Center
    for ang in [0, math.pi / 2.0]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
        cross_arm = bpy.context.active_object
        cross_arm.scale = (0.20, 0.65, 0.08)
        cross_arm.rotation_euler = (0, 0, ang)
        cross_arm.data.materials.append(mat_green)
        apply_uniform_clay_bevel(cross_arm, width=0.02, segments=2)
        objs.append(cross_arm)

    # 4. Triple Green Repair Lasers & Antenna Pylons
    for i in range(3):
        ang = i * (2.0 * math.pi / 3.0) + math.pi / 6.0
        px = math.cos(ang) * 0.68
        py = math.sin(ang) * 0.68
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.48, vertices=12, location=(px, py, 0.28))
        pylon = bpy.context.active_object
        pylon.data.materials.append(mat_antenna)
        apply_uniform_clay_bevel(pylon, width=0.02, segments=2)
        objs.append(pylon)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(px, py, 0.52))
        bulb = bpy.context.active_object
        bulb.data.materials.append(mat_green)
        bpy.ops.object.shade_smooth()
        objs.append(bulb)

    return objs

def build_refined_turret_gun():
    objs = []
    mat_chassis = create_clay_mat("m_trt_base", (0.28, 0.30, 0.36, 1.0), roughness=0.55)
    mat_metal = create_clay_mat("m_trt_gun", (0.18, 0.20, 0.24, 1.0), roughness=0.35)
    mat_hazard = create_clay_mat("m_trt_hz", (0.96, 0.78, 0.18, 1.0), roughness=0.40)
    mat_rocket = create_clay_mat("m_trt_rkt", (0.95, 0.22, 0.25, 1.0), emission=(0.95, 0.22, 0.25, 1.0), emission_str=2.5)

    # 1. Swivel Base Turret Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.82, depth=0.28, vertices=24, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.data.materials.append(mat_chassis)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    # 2. Main Turret Gun Mantlet Box
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.18))
    box = bpy.context.active_object
    box.scale = (0.78, 0.88, 0.38)
    box.data.materials.append(mat_hazard)
    apply_uniform_clay_bevel(box, width=0.06, segments=2)
    objs.append(box)

    # 3. Twin-Barrel Heavy Rotary Gatling Cannons
    for gx in [-0.14, 0.14]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=1.15, vertices=16, location=(gx, 0.65, 0.18))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
        objs.append(barrel)

        # Muzzle Flash Suppressors
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.22, vertices=16, location=(gx, 1.18, 0.18))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(muzzle, width=0.02, segments=2)
        objs.append(muzzle)

    # 4. Dual Side Micro-Missile Pods
    for mx in [-0.55, 0.55]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(mx, 0.05, 0.22))
        pod = bpy.context.active_object
        pod.scale = (0.28, 0.55, 0.32)
        pod.data.materials.append(mat_chassis)
        apply_uniform_clay_bevel(pod, width=0.03, segments=2)
        objs.append(pod)

        # Missile Tips
        for rz in [0.15, 0.28]:
            bpy.ops.mesh.primitive_cone_add(radius1=0.06, depth=0.18, vertices=12, location=(mx, 0.36, rz))
            tip = bpy.context.active_object
            tip.rotation_euler = (math.radians(90), 0, 0)
            tip.data.materials.append(mat_rocket)
            objs.append(tip)

    return objs

def main():
    print("==================================================")
    print(" Executing Refined Buildings Render Pipeline... ")
    print("==================================================")

    # 1. Refine Repair Station
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_refined_repair_station()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "repair_station.png"))
    print("[OK] Repair Station Refined.")

    # 2. Refine Defense Turret Gun
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_refined_turret_gun()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    print("[OK] Defense Turret Gun Refined.")

if __name__ == '__main__':
    main()
