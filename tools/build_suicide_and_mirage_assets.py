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
    ORTHO_SCALE_PROP,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# 1. SUICIDE DEMOLITION TRUCK (enemy_suicide_truck_f0..f5.png)
def build_suicide_truck(frame=0):
    objs = []
    mat_cab = create_clay_mat("m_sui_cab", (0.92, 0.22, 0.18, 1.0), roughness=0.55) # Crimson Red Alert Truck
    mat_chassis = create_clay_mat("m_sui_chas", (0.16, 0.18, 0.20, 1.0), roughness=0.70)
    mat_ram = create_clay_mat("m_sui_ram", (0.85, 0.70, 0.15, 1.0), roughness=0.40) # Hazard Yellow Bullbar
    mat_wheel = create_clay_mat("m_sui_whl", (0.12, 0.12, 0.14, 1.0), roughness=0.80)
    mat_nuke = create_clay_mat("m_sui_nuke", (0.20, 0.95, 0.35, 1.0), emission=(0.20, 0.95, 0.35, 1.0), emission_str=4.5) # Glowing Toxic Core
    mat_cask = create_clay_mat("m_sui_cask", (0.28, 0.30, 0.35, 1.0), roughness=0.50)

    # 1. Heavy Armored 6-Wheel Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, -0.12))
    chas = bpy.context.active_object
    chas.scale = (1.10, 1.70, 0.35)
    chas.data.materials.append(mat_chassis)
    apply_uniform_clay_bevel(chas, width=0.05, segments=2)
    objs.append(chas)

    # 6 Wheels (3 left, 3 right) with frame rotation phase
    wheel_phase = (frame / 6.0) * math.pi * 2.0
    for wx in [-0.68, 0.68]:
        for wy in [-0.65, -0.10, 0.48]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=0.28, vertices=16, location=(wx, wy, -0.16))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), wheel_phase)
            wheel.data.materials.append(mat_wheel)
            apply_uniform_clay_bevel(wheel, width=0.03, segments=1)
            objs.append(wheel)

    # 2. Driver Armored Cab
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.45, 0.22))
    cab = bpy.context.active_object
    cab.scale = (1.00, 0.75, 0.55)
    cab.data.materials.append(mat_cab)
    apply_uniform_clay_bevel(cab, width=0.06, segments=2)
    objs.append(cab)

    # Spiked Heavy Battering Ram on front bumper
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.92, -0.05))
    ram = bpy.context.active_object
    ram.scale = (1.30, 0.20, 0.35)
    ram.data.materials.append(mat_ram)
    apply_uniform_clay_bevel(ram, width=0.03, segments=2)
    objs.append(ram)

    for sx in [-0.45, 0.0, 0.45]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.10, depth=0.32, vertices=12, location=(sx, 1.10, -0.05))
        spike = bpy.context.active_object
        spike.rotation_euler = (math.radians(90), 0, 0)
        spike.data.materials.append(mat_ram)
        apply_uniform_clay_bevel(spike, width=0.01, segments=1)
        objs.append(spike)

    # 3. Rear Massive Explosive Warhead Tank
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=1.05, vertices=24, location=(0, -0.38, 0.30))
    cask = bpy.context.active_object
    cask.rotation_euler = (math.radians(90), 0, 0)
    cask.data.materials.append(mat_cask)
    apply_uniform_clay_bevel(cask, width=0.04, segments=2)
    objs.append(cask)

    # Glowing Toxic Core Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.50, depth=0.35, vertices=24, location=(0, -0.38, 0.30))
    ring = bpy.context.active_object
    ring.rotation_euler = (math.radians(90), 0, 0)
    ring.data.materials.append(mat_nuke)
    objs.append(ring)

    return objs

# 2. MIRAGE TANK (enemy_mirage_f0..f5.png)
def build_mirage_tank(frame=0):
    objs = []
    mat_stealth = create_clay_mat("m_mir_body", (0.30, 0.55, 0.65, 1.0), roughness=0.45) # Prism French Cyan Blue
    mat_tread = create_clay_mat("m_mir_trd", (0.18, 0.20, 0.22, 1.0), roughness=0.70)
    mat_prism = create_clay_mat("m_mir_prism", (0.35, 0.95, 1.0, 1.0), emission=(0.35, 0.95, 1.0, 1.0), emission_str=3.8) # Glowing Prism Emitter
    mat_gun = create_clay_mat("m_mir_gun", (0.22, 0.24, 0.28, 1.0), roughness=0.35)

    # 1. Dual Track Chassis
    tread_phase = (frame / 6.0) * math.pi
    for tx in [-0.80, 0.80]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.15))
        tread = bpy.context.active_object
        tread.scale = (0.42, 1.65, 0.45)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.05, segments=2)
        objs.append(tread)

        for wy in [-0.50, 0.0, 0.50]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.44, vertices=16, location=(tx, wy, -0.15))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), tread_phase)
            wheel.data.materials.append(mat_tread)
            objs.append(wheel)

    # 2. Angled Stealth Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.08))
    hull = bpy.context.active_object
    hull.scale = (1.20, 1.35, 0.42)
    hull.data.materials.append(mat_stealth)
    apply_uniform_clay_bevel(hull, width=0.08, segments=2)
    objs.append(hull)

    # 3. Turret with Dual Camouflage Prisms
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.32, vertices=8, location=(0, -0.05, 0.38))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_stealth)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # Dual Mirage Optical Prism Nodes on turret sides
    for px in [-0.48, 0.48]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.25, vertices=6, location=(px, -0.05, 0.44))
        p = bpy.context.active_object
        p.data.materials.append(mat_prism)
        apply_uniform_clay_bevel(p, width=0.02, segments=1)
        objs.append(p)

    # 4. Long Thermal Disrupter Cannon
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=1.35, vertices=16, location=(0, 0.82, 0.38))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_gun)
    apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
    objs.append(barrel)

    # Muzzle Prism Shroud
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.25, vertices=8, location=(0, 1.42, 0.38))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90), 0, 0)
    muzzle.data.materials.append(mat_prism)
    objs.append(muzzle)

    return objs

# 3. SUICIDE MUSHROOM BLAST VFX (vfx_suicide_blast.png)
def build_suicide_blast_vfx():
    objs = []
    mat_toxic_core = create_clay_mat("m_sui_fx_core", (0.35, 1.0, 0.45, 1.0), emission=(0.35, 1.0, 0.45, 1.0), emission_str=5.0)
    mat_fire_outer = create_clay_mat("m_sui_fx_fire", (1.0, 0.45, 0.10, 1.0), emission=(1.0, 0.45, 0.10, 1.0), emission_str=3.5)
    mat_smoke = create_clay_mat("m_sui_fx_smk", (0.22, 0.20, 0.24, 1.0), roughness=0.85)

    # Center Energy Sphere
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, location=(0, 0, 0.10))
    core = bpy.context.active_object
    core.data.materials.append(mat_toxic_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # Outer Bulbous Blast Clouds
    for ang in range(8):
        a = ang * (math.pi / 4.0)
        bx = math.cos(a) * 0.85
        by = math.sin(a) * 0.85
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(bx, by, 0))
        cloud = bpy.context.active_object
        cloud.data.materials.append(mat_fire_outer if ang % 2 == 0 else mat_smoke)
        bpy.ops.object.shade_smooth()
        objs.append(cloud)

    return objs

# 4. MIRAGE CAMOUFLAGE SHIMMER VFX (vfx_mirage_shimmer.png)
def build_mirage_shimmer_vfx():
    objs = []
    mat_shimmer = create_clay_mat("m_mir_shim", (0.45, 0.90, 1.0, 0.85), emission=(0.45, 0.90, 1.0, 1.0), emission_str=4.0)
    mat_leaf = create_clay_mat("m_mir_leaf", (0.35, 0.78, 0.25, 1.0), roughness=0.60)

    # Hexagonal Cloaking Grid Prisms
    for i in range(6):
        ang = i * (math.pi / 3.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=0.12, vertices=6, location=(math.cos(ang) * 0.72, math.sin(ang) * 0.72, 0))
        hex_p = bpy.context.active_object
        hex_p.data.materials.append(mat_shimmer)
        apply_uniform_clay_bevel(hex_p, width=0.02, segments=1)
        objs.append(hex_p)

    # Center Camouflage Leaf Pattern
    bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=0.14, vertices=6, location=(0, 0, 0.05))
    leaf = bpy.context.active_object
    leaf.data.materials.append(mat_leaf)
    apply_uniform_clay_bevel(leaf, width=0.03, segments=1)
    objs.append(leaf)

    return objs

def main():
    print("==================================================")
    print(" Executing Suicide Truck & Mirage Asset Pipeline.. ")
    print("==================================================")

    # 1. Render Suicide Truck 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_suicide_truck(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_suicide_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Suicide Truck Frame {f} Rendered.")

    # 2. Render Mirage Tank 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_mirage_tank(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_mirage_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Mirage Tank Frame {f} Rendered.")

    # 3. Render Suicide Blast VFX
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_suicide_blast_vfx()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "vfx_suicide_blast.png"))
    print("[OK] Suicide Blast VFX Rendered.")

    # 4. Render Mirage Shimmer VFX
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_mirage_shimmer_vfx()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "vfx_mirage_shimmer.png"))
    print("[OK] Mirage Shimmer VFX Rendered.")

if __name__ == '__main__':
    main()
