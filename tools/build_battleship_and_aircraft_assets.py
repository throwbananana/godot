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

# 1. NAVAL BATTLESHIP (enemy_battleship_f0..f5.png)
def build_battleship(frame=0):
    objs = []
    mat_hull = create_clay_mat("m_shp_hull", (0.32, 0.35, 0.40, 1.0), roughness=0.55) # Naval Grey
    mat_deck = create_clay_mat("m_shp_deck", (0.58, 0.42, 0.26, 1.0), roughness=0.75) # Teak Wood Deck
    mat_bridge = create_clay_mat("m_shp_bdg", (0.80, 0.82, 0.85, 1.0), roughness=0.45)
    mat_turret = create_clay_mat("m_shp_trt", (0.24, 0.26, 0.30, 1.0), roughness=0.40)
    mat_wake = create_clay_mat("m_shp_wake", (0.75, 0.95, 1.0, 1.0), emission=(0.75, 0.95, 1.0, 1.0), emission_str=2.2)

    # 1. Armored Ship Hull (Boat Shape)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, -0.05))
    hull = bpy.context.active_object
    hull.scale = (1.10, 1.85, 0.45)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.08, segments=3)
    objs.append(hull)

    # Pointed Bow Wedge (Front of ship)
    bpy.ops.mesh.primitive_cone_add(radius1=0.55, depth=0.85, vertices=16, location=(0, 0.95, -0.05))
    bow = bpy.context.active_object
    bow.rotation_euler = (math.radians(-90), 0, 0)
    bow.scale = (1.0, 0.55, 1.0)
    bow.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(bow, width=0.04, segments=2)
    objs.append(bow)

    # Wood Deck Insert
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.18))
    deck = bpy.context.active_object
    deck.scale = (0.88, 1.70, 0.08)
    deck.data.materials.append(mat_deck)
    apply_uniform_clay_bevel(deck, width=0.02, segments=2)
    objs.append(deck)

    # 2. Central Bridge Superstructure & Radar Mast
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.0, 0.38))
    bridge = bpy.context.active_object
    bridge.scale = (0.55, 0.65, 0.35)
    bridge.data.materials.append(mat_bridge)
    apply_uniform_clay_bevel(bridge, width=0.03, segments=2)
    objs.append(bridge)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.55, vertices=12, location=(0, -0.10, 0.65))
    mast = bpy.context.active_object
    mast.data.materials.append(mat_turret)
    objs.append(mast)

    # 3. Dual Heavy Naval Gun Turrets (Fore & Aft)
    for (ty, fang) in [(0.58, 0), (-0.68, math.pi)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.18, vertices=16, location=(0, ty, 0.30))
        trt = bpy.context.active_object
        trt.data.materials.append(mat_turret)
        apply_uniform_clay_bevel(trt, width=0.03, segments=2)
        objs.append(trt)

        # Twin Long Barrels
        for bx in [-0.08, 0.08]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.85, vertices=12, location=(bx, ty + (0.42 if ty > 0 else -0.42), 0.32))
            bar = bpy.context.active_object
            bar.rotation_euler = (math.radians(90), 0, 0)
            bar.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(bar, width=0.01, segments=1)
            objs.append(bar)

    # 4. Animated Water Foam Wake Bow Wave
    wake_phase = (frame / 6.0) * math.pi * 2.0
    for side in [-1, 1]:
        for i in range(3):
            wy = 0.85 - i * 0.45 + math.sin(wake_phase + i) * 0.08
            wx = side * (0.65 + i * 0.12)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12 + i * 0.04, location=(wx, wy, -0.15))
            foam = bpy.context.active_object
            foam.data.materials.append(mat_wake)
            bpy.ops.object.shade_smooth()
            objs.append(foam)

    return objs

# 2. COMBAT AIRCRAFT / ATTACK JET (enemy_aircraft_f0..f5.png)
def build_aircraft(frame=0):
    objs = []
    mat_fuselage = create_clay_mat("m_air_fuse", (0.35, 0.38, 0.44, 1.0), roughness=0.45) # Tactical Camo
    mat_wing = create_clay_mat("m_air_wing", (0.28, 0.30, 0.35, 1.0), roughness=0.50)
    mat_glass = create_clay_mat("m_air_glass", (0.20, 0.80, 0.95, 1.0), emission=(0.20, 0.80, 0.95, 1.0), emission_str=2.5) # Glowing Cyan Canopy
    mat_afterburner = create_clay_mat("m_air_jet", (1.0, 0.55, 0.10, 1.0), emission=(1.0, 0.55, 0.10, 1.0), emission_str=5.0) # Fiery Jet Flame
    mat_missile = create_clay_mat("m_air_msl", (0.95, 0.20, 0.22, 1.0), roughness=0.40)

    # 1. Aerodynamic Jet Fuselage
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=1.85, vertices=24, location=(0, 0.05, 0))
    fuse = bpy.context.active_object
    fuse.rotation_euler = (math.radians(90), 0, 0)
    fuse.scale = (0.90, 1.0, 0.65)
    fuse.data.materials.append(mat_fuselage)
    apply_uniform_clay_bevel(fuse, width=0.03, segments=2)
    objs.append(fuse)

    # Sharp Nose Cone
    bpy.ops.mesh.primitive_cone_add(radius1=0.22, depth=0.65, vertices=24, location=(0, 1.15, 0))
    nose = bpy.context.active_object
    nose.rotation_euler = (math.radians(-90), 0, 0)
    nose.data.materials.append(mat_fuselage)
    apply_uniform_clay_bevel(nose, width=0.02, segments=2)
    objs.append(nose)

    # 2. Swept Delta Main Wings
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0))
    wings = bpy.context.active_object
    wings.scale = (2.20, 0.75, 0.06)
    wings.data.materials.append(mat_wing)
    apply_uniform_clay_bevel(wings, width=0.03, segments=2)
    objs.append(wings)

    # Vertical Twin Tail Stabilizers
    for tx in [-0.28, 0.28]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, -0.75, 0.25))
        tail = bpy.context.active_object
        tail.scale = (0.05, 0.38, 0.45)
        tail.rotation_euler = (0, math.radians(-15 if tx > 0 else 15), 0)
        tail.data.materials.append(mat_wing)
        apply_uniform_clay_bevel(tail, width=0.02, segments=1)
        objs.append(tail)

    # 3. Tinted Cyan Cockpit Canopy
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, 0.35, 0.16))
    canopy = bpy.context.active_object
    canopy.scale = (0.75, 1.55, 0.85)
    canopy.data.materials.append(mat_glass)
    bpy.ops.object.shade_smooth()
    objs.append(canopy)

    # 4. Underwing Ordnance Missiles
    for mx in [-0.75, 0.75]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.75, vertices=12, location=(mx, -0.10, -0.08))
        msl = bpy.context.active_object
        msl.rotation_euler = (math.radians(90), 0, 0)
        msl.data.materials.append(mat_missile)
        objs.append(msl)

    # 5. Twin Fiery Jet Afterburner Exhaust Plumes (animated pulse)
    jet_pulse = 0.45 + math.sin((frame / 6.0) * math.pi * 2.0) * 0.12
    for jx in [-0.14, 0.14]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.12, radius2=0.02, depth=jet_pulse, vertices=16, location=(jx, -1.05, 0))
        flame = bpy.context.active_object
        flame.rotation_euler = (math.radians(90), 0, 0)
        flame.data.materials.append(mat_afterburner)
        objs.append(flame)

    return objs

# 3. WATER WAKE VFX (vfx_water_wake.png)
def build_water_wake_vfx():
    objs = []
    mat_foam = create_clay_mat("m_wk_foam", (0.75, 0.95, 1.0, 0.90), emission=(0.75, 0.95, 1.0, 1.0), emission_str=2.5)
    mat_wave = create_clay_mat("m_wk_wave", (0.35, 0.70, 0.90, 0.80), roughness=0.30)

    # V-Shaped Expanding Foam Wake
    for side in [-1, 1]:
        for i in range(5):
            wy = 0.6 - i * 0.35
            wx = side * (0.3 + i * 0.22)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14 + i * 0.05, location=(wx, wy, 0))
            p = bpy.context.active_object
            p.data.materials.append(mat_foam if i % 2 == 0 else mat_wave)
            bpy.ops.object.shade_smooth()
            objs.append(p)

    return objs

# 4. AIRCRAFT SHADOW (vfx_plane_shadow.png)
def build_plane_shadow_vfx():
    objs = []
    mat_shadow = create_clay_mat("m_shd_plane", (0.05, 0.05, 0.08, 0.60), roughness=0.90)

    # Simplified Plane Silhouette Shadow
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    body_shd = bpy.context.active_object
    body_shd.scale = (0.35, 1.60, 0.05)
    body_shd.data.materials.append(mat_shadow)
    objs.append(body_shd)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0))
    wing_shd = bpy.context.active_object
    wing_shd.scale = (1.90, 0.65, 0.05)
    wing_shd.data.materials.append(mat_shadow)
    objs.append(wing_shd)

    return objs

def main():
    print("==================================================")
    print(" Executing Battleship & Aircraft Asset Pipeline.. ")
    print("==================================================")

    # 1. Render Battleship 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_battleship(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_battleship_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Battleship Frame {f} Rendered.")

    # 2. Render Aircraft 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_aircraft(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_aircraft_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Aircraft Frame {f} Rendered.")

    # 3. Render Water Wake VFX
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_water_wake_vfx()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "vfx_water_wake.png"))
    print("[OK] Water Wake VFX Rendered.")

    # 4. Render Plane Shadow VFX
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_plane_shadow_vfx()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "vfx_plane_shadow.png"))
    print("[OK] Plane Shadow VFX Rendered.")

if __name__ == '__main__':
    main()
