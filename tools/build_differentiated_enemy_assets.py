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
# 1. ENEMY SNIPER (侦察狙击坦克: 极速机动 + 超远超长装填蓄力狙击)
# ==============================================================================
def build_enemy_sniper(frame: int = 0):
    """Build a high-speed agile sniper tank with extended rail barrel & laser scope."""
    objs = []
    
    # Palette
    mat_hull = create_clay_mat(f"m_snp_hull_{frame}", (0.20, 0.28, 0.44, 1.0), roughness=0.45)
    mat_dark = create_clay_mat(f"m_snp_dark_{frame}", (0.12, 0.14, 0.18, 1.0), roughness=0.60)
    mat_gold = create_clay_mat(f"m_snp_gold_{frame}", (0.92, 0.72, 0.16, 1.0), roughness=0.35)
    mat_tread = create_clay_mat(f"m_snp_trd_{frame}", (0.10, 0.10, 0.12, 1.0), roughness=0.80)
    mat_lens = create_clay_mat(f"m_snp_lens_{frame}", (0.10, 0.85, 0.95, 1.0), emission=(0.10, 0.85, 0.95, 1.0), emission_str=4.5)

    vib = math.sin(frame * math.pi) * 0.012
    lens_pulse = (math.sin(frame * (math.pi / 3.0)) + 1.0) * 0.5

    # Sleek Lightweight Angular Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.16 + vib))
    hull = bpy.context.active_object
    hull.scale = (1.05, 1.30, 0.32)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.06, segments=2)
    objs.append(hull)

    # Front Slanted Nose Deflector
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.50, 0.14 + vib))
    nose = bpy.context.active_object
    nose.scale = (0.75, 0.45, 0.20)
    nose.rotation_euler = (math.radians(-18), 0, 0)
    nose.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(nose, width=0.04, segments=2)
    objs.append(nose)

    # High-Speed Narrow Treads
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.68, -0.08, 0.12))
        trd = bpy.context.active_object
        trd.scale = (0.24, 1.52, 0.32)
        trd.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(trd, width=0.03, segments=2)
        objs.append(trd)

        # Aerodynamic Mudguards
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.68, -0.08, 0.30 + vib))
        guard = bpy.context.active_object
        guard.scale = (0.26, 1.40, 0.08)
        guard.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(guard, width=0.02, segments=2)
        objs.append(guard)

    # Low-Profile Precision Sniper Turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.36, depth=0.26, vertices=16, location=(0, -0.15, 0.40 + vib))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # Ultra-Long High-Caliber Sniper Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.055, depth=1.55, vertices=12, location=(0, 0.65, 0.40 + vib))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(barrel, width=0.015, segments=2)
    objs.append(barrel)

    # Slotted Muzzle Brake at Barrel Tip
    bpy.ops.mesh.primitive_cylinder_add(radius=0.085, depth=0.22, vertices=12, location=(0, 1.40, 0.40 + vib))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90), 0, 0)
    muzzle.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(muzzle, width=0.02, segments=2)
    objs.append(muzzle)

    # Precision Optical Scope & Laser Targeter on Turret Roof
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.18, -0.05, 0.58 + vib))
    scope = bpy.context.active_object
    scope.scale = (0.16, 0.42, 0.14)
    scope.data.materials.append(mat_dark)
    apply_uniform_clay_bevel(scope, width=0.02, segments=2)
    objs.append(scope)

    # Glowing Cyan Sensor Lens
    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.08, vertices=12, location=(0.18, 0.18, 0.58 + vib))
    lens = bpy.context.active_object
    lens.rotation_euler = (math.radians(90), 0, 0)
    lens.data.materials.append(mat_lens)
    bpy.ops.object.shade_smooth()
    objs.append(lens)

    # Rear High-Gain Comm Antenna
    bpy.ops.mesh.primitive_cylinder_add(radius=0.018, depth=0.65, vertices=8, location=(-0.22, -0.42, 0.68 + vib))
    ant = bpy.context.active_object
    ant.rotation_euler = (math.radians(-12), math.radians(-8), 0)
    ant.data.materials.append(mat_gold)
    objs.append(ant)

    return objs

# ==============================================================================
# 2. ENEMY GATLING (加特林重坦: 极缓移动 + 极高速连发压制弹幕)
# ==============================================================================
def build_enemy_gatling(frame: int = 0):
    """Build a slow armored Gatling gun fortress tank with rotating 6-barrel cannon."""
    objs = []

    # Palette
    mat_hull = create_clay_mat(f"m_gat_hull_{frame}", (0.34, 0.40, 0.28, 1.0), roughness=0.55)
    mat_iron = create_clay_mat(f"m_gat_iron_{frame}", (0.18, 0.18, 0.22, 1.0), roughness=0.65)
    mat_brass = create_clay_mat(f"m_gat_brs_{frame}", (0.86, 0.62, 0.18, 1.0), roughness=0.30)
    mat_tread = create_clay_mat(f"m_gat_trd_{frame}", (0.11, 0.11, 0.13, 1.0), roughness=0.85)
    mat_hot = create_clay_mat(f"m_gat_hot_{frame}", (1.0, 0.45, 0.10, 1.0), emission=(1.0, 0.45, 0.10, 1.0), emission_str=3.5)

    gat_rot = frame * (2.0 * math.pi / 6.0)
    vib = math.sin(frame * math.pi) * 0.018

    # Heavy Reinforced Octagonal Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0.18 + vib))
    hull = bpy.context.active_object
    hull.scale = (1.45, 1.40, 0.42)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.08, segments=3)
    objs.append(hull)

    # Massive Armor Treads
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.88, -0.15, 0.12))
        trd = bpy.context.active_object
        trd.scale = (0.32, 1.62, 0.38)
        trd.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(trd, width=0.04, segments=2)
        objs.append(trd)

        # Heavy Riveted Side Skirts
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.90, -0.15, 0.32 + vib))
        skirt = bpy.context.active_object
        skirt.scale = (0.34, 1.48, 0.14)
        skirt.data.materials.append(mat_brass)
        apply_uniform_clay_bevel(skirt, width=0.03, segments=2)
        objs.append(skirt)

    # Large Heavy Rotor Turret Core
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.34, vertices=16, location=(0, -0.08, 0.48 + vib))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # Giant Rear Drum Ammo Feeder (Ammunition Magazine)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.30, vertices=16, location=(0, -0.62, 0.46 + vib))
    drum = bpy.context.active_object
    drum.rotation_euler = (0, 0, frame * (math.pi / 6.0))
    drum.data.materials.append(mat_brass)
    apply_uniform_clay_bevel(drum, width=0.03, segments=2)
    objs.append(drum)

    # Ammo Feed Belt Chute into Turret
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.25, -0.36, 0.48 + vib))
    chute = bpy.context.active_object
    chute.scale = (0.16, 0.32, 0.12)
    chute.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(chute, width=0.02, segments=2)
    objs.append(chute)

    # 6-Barrel Gatling Rotary Assembly
    gat_y = 0.55
    gat_z = 0.48
    # Center Hub Rotor
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.85, vertices=16, location=(0, gat_y, gat_z + vib))
    hub = bpy.context.active_object
    hub.rotation_euler = (math.radians(90), 0, 0)
    hub.data.materials.append(mat_iron)
    objs.append(hub)

    # 6 Surrounding Gatling Gun Barrels
    for i in range(6):
        ang = gat_rot + i * (2.0 * math.pi / 6.0)
        bx = math.cos(ang) * 0.14
        bz = gat_z + math.sin(ang) * 0.14 + vib
        bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.95, vertices=8, location=(bx, gat_y + 0.10, bz))
        bar = bpy.context.active_object
        bar.rotation_euler = (math.radians(90), 0, 0)
        bar.data.materials.append(mat_iron)
        apply_uniform_clay_bevel(bar, width=0.01, segments=1)
        objs.append(bar)

    # Muzzle Clamp Ring at Barrel Ends
    bpy.ops.mesh.primitive_torus_add(major_radius=0.15, minor_radius=0.028, location=(0, gat_y + 0.52, gat_z + vib))
    clamp_ring = bpy.context.active_object
    clamp_ring.rotation_euler = (math.radians(90), 0, 0)
    clamp_ring.data.materials.append(mat_brass)
    objs.append(clamp_ring)

    # Heated Glowing Central Core Vent
    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.08, vertices=12, location=(0, gat_y + 0.54, gat_z + vib))
    heat_core = bpy.context.active_object
    heat_core.rotation_euler = (math.radians(90), 0, 0)
    heat_core.data.materials.append(mat_hot)
    bpy.ops.object.shade_smooth()
    objs.append(heat_core)

    return objs

# ==============================================================================
# 3. ENEMY SHOTGUN (散弹突击车: 中速冲锋 + 扇形三路破片喷射)
# ==============================================================================
def build_enemy_shotgun(frame: int = 0):
    """Build an aggressive assault shotgun tank with flared multi-bore spread muzzle."""
    objs = []

    # Palette
    mat_hull = create_clay_mat(f"m_sg_hull_{frame}", (0.82, 0.40, 0.16, 1.0), roughness=0.45)
    mat_steel = create_clay_mat(f"m_sg_stl_{frame}", (0.24, 0.25, 0.28, 1.0), roughness=0.55)
    mat_trim = create_clay_mat(f"m_sg_trm_{frame}", (0.95, 0.65, 0.18, 1.0), roughness=0.35)
    mat_tread = create_clay_mat(f"m_sg_trd_{frame}", (0.12, 0.12, 0.14, 1.0), roughness=0.85)
    mat_flame = create_clay_mat(f"m_sg_flm_{frame}", (1.0, 0.25, 0.05, 1.0), emission=(1.0, 0.25, 0.05, 1.0), emission_str=4.0)

    vib = math.sin(frame * math.pi) * 0.015
    spread_breath = math.sin(frame * (math.pi / 3.0)) * 0.02

    # Wedge Assault Hull with Heavy Front Dozer Angle
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.16 + vib))
    hull = bpy.context.active_object
    hull.scale = (1.20, 1.35, 0.38)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.06, segments=2)
    objs.append(hull)

    # Front Heavy Breaching Wedge/Plow
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.55, 0.12 + vib))
    plow = bpy.context.active_object
    plow.scale = (1.00, 0.35, 0.24)
    plow.rotation_euler = (math.radians(-25), 0, 0)
    plow.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(plow, width=0.04, segments=2)
    objs.append(plow)

    # Aggressive Chevron Treads
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.76, -0.08, 0.12))
        trd = bpy.context.active_object
        trd.scale = (0.28, 1.55, 0.34)
        trd.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(trd, width=0.03, segments=2)
        objs.append(trd)

        # Flared Side Armor Plates
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.78, -0.08, 0.30 + vib))
        plate = bpy.context.active_object
        plate.scale = (0.30, 1.40, 0.10)
        plate.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(plate, width=0.02, segments=2)
        objs.append(plate)

    # Wide Heavy Box Turret
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.44 + vib))
    turret = bpy.context.active_object
    turret.scale = (0.85, 0.78, 0.28)
    turret.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # Triple Flared Spread Shotgun Barrels (-18 deg, 0 deg, +18 deg)
    angles = [-18.0, 0.0, 18.0]
    for i, ang_deg in enumerate(angles):
        rad = math.radians(ang_deg)
        bx = math.sin(rad) * 0.45
        by = 0.35 + math.cos(rad) * 0.42
        
        # Barrel Tube
        bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=0.65, vertices=12, location=(bx, by, 0.44 + vib))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, -rad)
        barrel.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(barrel, width=0.015, segments=2)
        objs.append(barrel)

        # Flared Blunderbuss Muzzle Ring
        fx = bx + math.sin(rad) * 0.32
        fy = by + math.cos(rad) * 0.32
        bpy.ops.mesh.primitive_cone_add(radius1=0.115, radius2=0.075, depth=0.18, vertices=12, location=(fx, fy, 0.44 + vib))
        cone = bpy.context.active_object
        cone.rotation_euler = (math.radians(-90), 0, -rad)
        cone.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(cone, width=0.015, segments=2)
        objs.append(cone)

    # Dual Heavy Exhaust Stacks on Rear Deck
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.42, vertices=12, location=(side * 0.32, -0.55, 0.50 + vib))
        exh = bpy.context.active_object
        exh.rotation_euler = (math.radians(-18), math.radians(side * 10), 0)
        exh.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(exh, width=0.02, segments=2)
        objs.append(exh)

        # Exhaust Glowing Ember
        bpy.ops.mesh.primitive_torus_add(major_radius=0.10, minor_radius=0.025, location=(side * 0.32, -0.55, 0.68 + vib))
        glow = bpy.context.active_object
        glow.rotation_euler = (math.radians(-18), math.radians(side * 10), 0)
        glow.data.materials.append(mat_flame)
        bpy.ops.object.shade_smooth()
        objs.append(glow)

    return objs

# ==============================================================================
# MAIN RENDER ENTRY POINT
# ==============================================================================
def main():
    print("==================================================================")
    print(" Rendering Differentiated Archetype Enemies (SNIPER, GATLING, SHOTGUN)")
    print("==================================================================")

    roster = [
        ("enemy_sniper", build_enemy_sniper),
        ("enemy_gatling", build_enemy_gatling),
        ("enemy_shotgun", build_enemy_shotgun),
    ]

    for name, builder_func in roster:
        print(f"\n>>> Rendering {name} (6 Animated Frames)...")
        for f in range(6):
            clear_scene()
            setup_render_settings(256, 256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
            objs = builder_func(frame=f)
            out_path = os.path.join(SPRITES_TANKS, f"{name}_f{f}.png")
            render_and_clean(objs, out_path)
            print(f"  [OK] {name} frame {f} -> {out_path}")

    print("\n[SUCCESS] All differentiated enemy assets rendered successfully.")

if __name__ == '__main__':
    main()
