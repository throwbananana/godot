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
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)

# ==================== 1. SHIELD RECHARGE STATION ====================
def build_shield_station():
    objs = []
    # Material palette: High-tech cobalt alloy, deep navy, radiant cyan plasma, luminous shield gold
    mat_base = create_clay_mat("m_shld_base", (0.22, 0.26, 0.35, 1.0), roughness=0.60)
    mat_metal = create_clay_mat("m_shld_metal", (0.35, 0.40, 0.52, 1.0), roughness=0.45)
    mat_gold = create_clay_mat("m_shld_gold", (0.95, 0.76, 0.20, 1.0), roughness=0.35)
    mat_plasma = create_clay_mat("m_shld_plasma", (0.20, 0.85, 1.0, 1.0), emission=(0.20, 0.85, 1.0, 1.0), emission_str=3.8)
    mat_ring = create_clay_mat("m_shld_ring", (0.35, 0.65, 0.95, 1.0), emission=(0.35, 0.65, 0.95, 1.0), emission_str=2.0)
    mat_indicator = create_clay_mat("m_shld_ind", (0.10, 0.95, 0.65, 1.0), emission=(0.10, 0.95, 0.65, 1.0), emission_str=3.0)

    # 1. Heavy Hexagonal Base Platform
    bpy.ops.mesh.primitive_cylinder_add(radius=1.28, depth=0.24, vertices=6, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.10, segments=3)
    objs.append(base)

    # Inner circular recess
    bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.18, vertices=24, location=(0, 0, 0.05))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(inner, width=0.06, segments=2)
    objs.append(inner)

    # Outer Energy Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.92, minor_radius=0.06, location=(0, 0, 0.12))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # 2. Triple Pylon Emitters (at 120 deg intervals)
    for i in range(3):
        angle = i * (2.0 * math.pi / 3.0)
        px = math.cos(angle) * 0.72
        py = math.sin(angle) * 0.72

        # Pylon post
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.55, vertices=12, location=(px, py, 0.28))
        pylon = bpy.context.active_object
        pylon.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(pylon, width=0.04, segments=2)
        objs.append(pylon)

        # Gold coil cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.12, vertices=12, location=(px, py, 0.50))
        cap = bpy.context.active_object
        cap.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(cap, width=0.03, segments=2)
        objs.append(cap)

        # Micro cyan emitter tip
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(px, py, 0.60))
        tip = bpy.context.active_object
        tip.data.materials.append(mat_plasma)
        bpy.ops.object.shade_smooth()
        objs.append(tip)

    # 3. Floating Central Plasma Crystal / Energy Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0, 0.35))
    core = bpy.context.active_object
    core.data.materials.append(mat_plasma)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # Surrounding orbital shield ring (tilted)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.48, minor_radius=0.045, location=(0, 0, 0.35))
    orb_ring = bpy.context.active_object
    orb_ring.rotation_euler = (math.radians(35), math.radians(25), 0)
    orb_ring.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(orb_ring)

    # 4. Status Indicator Lights
    for i in range(6):
        ang = i * (2.0 * math.pi / 6.0) + (math.pi / 6.0)
        lx = math.cos(ang) * 1.15
        ly = math.sin(ang) * 1.15
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.065, location=(lx, ly, 0.10))
        light = bpy.context.active_object
        light.data.materials.append(mat_indicator)
        bpy.ops.object.shade_smooth()
        objs.append(light)

    return objs

# ==================== 2. INDUSTRIAL WIND TURBINE BLOWER ====================
def build_wind_blower(frame: int = 0):
    """Build wind blower turbine. frame 0-5 rotates the 4 impeller blades.
    
    Each frame adds frame*(PI/3) to the blade base rotation so the rotor
    completes a full 360° spin over 6 frames (6 * 60° = 360°).
    """
    objs = []
    # Material palette: Industrial Heavy Steel, Hazard Yellow & Black, Cyan Rotor, Exhaust Grille
    mat_casing = create_clay_mat("m_fan_case", (0.28, 0.30, 0.36, 1.0), roughness=0.55)
    mat_hazard = create_clay_mat("m_fan_haz", (0.95, 0.72, 0.15, 1.0), roughness=0.50)
    mat_stripes = create_clay_mat("m_fan_str", (0.15, 0.15, 0.18, 1.0), roughness=0.60)
    mat_rotor = create_clay_mat("m_fan_rotor", (0.18, 0.75, 0.90, 1.0), roughness=0.40)
    mat_grille = create_clay_mat("m_fan_grille", (0.12, 0.14, 0.18, 1.0), roughness=0.70)
    mat_glow = create_clay_mat("m_fan_glow", (0.40, 0.90, 1.0, 1.0), emission=(0.40, 0.90, 1.0, 1.0), emission_str=2.4)
    mat_motor = create_clay_mat("m_fan_motor", (0.42, 0.46, 0.54, 1.0), roughness=0.45)

    # 1. Main Industrial Square Chassis Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    case = bpy.context.active_object
    case.scale = (1.92, 1.92, 0.44)
    case.data.materials.append(mat_casing)
    apply_uniform_clay_bevel(case, width=0.12, segments=3)
    objs.append(case)

    # Hazard Chevron Corner Guards
    for (cx, cy) in [(-0.82, -0.82), (0.82, -0.82), (-0.82, 0.82), (0.82, 0.82)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.12))
        guard = bpy.context.active_object
        guard.scale = (0.34, 0.34, 0.28)
        guard.data.materials.append(mat_hazard)
        apply_uniform_clay_bevel(guard, width=0.06, segments=2)
        objs.append(guard)

        # Inner dark stripe
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.22))
        strp = bpy.context.active_object
        strp.scale = (0.22, 0.22, 0.12)
        strp.data.materials.append(mat_stripes)
        objs.append(strp)

    # 2. Circular Fan Duct / Shroud Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.78, depth=0.42, vertices=24, location=(0, 0, 0.08))
    duct = bpy.context.active_object
    duct.data.materials.append(mat_casing)
    apply_uniform_clay_bevel(duct, width=0.06, segments=3)
    objs.append(duct)

    # Recessed Dark Air Chamber
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.35, vertices=24, location=(0, 0, 0.12))
    chamber = bpy.context.active_object
    chamber.data.materials.append(mat_grille)
    objs.append(chamber)

    # 3. Rotating 4-Blade Impeller Fan Rotor
    # Center Spinner Nose Cone
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.32, vertices=16, location=(0, 0, 0.26))
    hub = bpy.context.active_object
    hub.data.materials.append(mat_motor)
    apply_uniform_clay_bevel(hub, width=0.04, segments=2)
    objs.append(hub)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.40))
    nose = bpy.context.active_object
    nose.data.materials.append(mat_glow)
    bpy.ops.object.shade_smooth()
    objs.append(nose)

    # 4 Curved Aerodynamic Impeller Blades (animated: frame adds 60deg per step)
    # P1 FIX: Each frame rotates blades by frame*(PI/3) so 6 frames = full revolution
    blade_spin = frame * (math.pi / 3.0)
    for i in range(4):
        rot_ang = i * (math.pi / 2.0) + blade_spin
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.24))
        blade = bpy.context.active_object
        blade.scale = (0.16, 0.44, 0.05)
        blade.location = (math.cos(rot_ang) * 0.36, math.sin(rot_ang) * 0.36, 0.24)
        blade.rotation_euler = (math.radians(22), math.radians(-15), rot_ang)
        blade.data.materials.append(mat_rotor)
        apply_uniform_clay_bevel(blade, width=0.03, segments=2)
        objs.append(blade)

    # 4. Protective Front Wire Grille Bars (Cross Pattern)
    for (gx, gy) in [(0.72, 0.04), (0.04, 0.72)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.36))
        bar = bpy.context.active_object
        bar.scale = (gx * 1.8, gy * 1.8, 0.04)
        bar.data.materials.append(mat_grille)
        objs.append(bar)

    # Directional Flow Arrow Indicator on top frame
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.10, vertices=3, location=(0, 0.76, 0.24))
    arrow = bpy.context.active_object
    arrow.rotation_euler = (0, 0, math.radians(90))
    arrow.data.materials.append(mat_glow)
    objs.append(arrow)

    return objs

def main():
    print("==================================================")
    print(" Rendering Shield Station & Wind Blower Assets... ")
    print("==================================================")

    # 1. Render Shield Recharge Station (unchanged -- single static frame)
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    shld_objs = build_shield_station()
    shld_out = os.path.join(SPRITES_BUILDINGS, "shield_station.png")
    render_and_clean(shld_objs, shld_out)
    print(f"[OK] Shield Station rendered -> {shld_out}")

    # 2. Render Wind Blower Turbine (6 animated frames: wind_blower_f0..f5.png)
    # P1 FIX: Was single static frame. Blades now spin 60° per frame over 6 frames.
    # Game script (wind_blower.gd) currently loads a static png; see note below about
    # updating it to cycle frames for the full animation effect.
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        blower_objs = build_wind_blower(frame=f)
        blower_out = os.path.join(SPRITES_BUILDINGS, f"wind_blower_f{f}.png")
        render_and_clean(blower_objs, blower_out)
        print(f"[OK] Wind Blower frame {f} rendered -> {blower_out}")

    # Keep backwards-compat static copy (frame 0) so existing wind_blower.gd still loads
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    blower_objs = build_wind_blower(frame=0)
    blower_out_static = os.path.join(SPRITES_BUILDINGS, "wind_blower.png")
    render_and_clean(blower_objs, blower_out_static)
    print(f"[OK] Wind Blower static (compat) rendered -> {blower_out_static}")

if __name__ == '__main__':
    main()
