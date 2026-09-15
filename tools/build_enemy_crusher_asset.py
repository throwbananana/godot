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

# ==================== ENEMY CRUSHER (粉碎者大型装甲碾压车) ====================
def build_enemy_crusher(frame: int = 0):
    """Build a giant clay Crusher tank with revolving spiked roller drum.
    
    frame: 0..5 animates 360-deg rotation of the spiked roller drum,
    hydraulic ram pulsation, and heavy exhaust vibration.
    """
    objs = []

    # Material Palette:
    # 1. Heavy Crimson/Rust Armor Hull Clay
    mat_hull = create_clay_mat(f"m_cr_hull_{frame}", (0.68, 0.22, 0.24, 1.0), roughness=0.50)
    # 2. Dark Cast-Iron Chassis & Structural Frames
    mat_iron = create_clay_mat(f"m_cr_iron_{frame}", (0.22, 0.22, 0.26, 1.0), roughness=0.60)
    # 3. Spiked Crushing Drum Body
    mat_drum = create_clay_mat(f"m_cr_drum_{frame}", (0.16, 0.16, 0.20, 1.0), roughness=0.70)
    # 4. Hardened Bronze Crushing Teeth / Spikes
    mat_teeth = create_clay_mat(f"m_cr_teeth_{frame}", (0.95, 0.68, 0.18, 1.0), roughness=0.35)
    # 5. Glowing Furnace Heat Engine Core
    mat_furnace = create_clay_mat(f"m_cr_furn_{frame}", (1.0, 0.30, 0.05, 1.0), emission=(1.0, 0.30, 0.05, 1.0), emission_str=3.8)
    # 6. Heavy Tread Rubber
    mat_tread = create_clay_mat(f"m_cr_tread_{frame}", (0.12, 0.12, 0.14, 1.0), roughness=0.85)
    # 7. Bronze Armor Rivets & Side Plates
    mat_bronze = create_clay_mat(f"m_cr_brz_{frame}", (0.85, 0.55, 0.18, 1.0), roughness=0.40)

    drum_rot = frame * (2.0 * math.pi / 6.0)
    piston_bob = math.sin(frame * (math.pi / 3.0)) * 0.035
    vib = math.sin(frame * math.pi) * 0.015

    # 1. Main Heavy Armored Super-Chassis (Large wide body)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.25, 0.15 + vib))
    chassis = bpy.context.active_object
    chassis.scale = (1.60, 1.35, 0.55)
    chassis.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(chassis, width=0.08, segments=3)
    objs.append(chassis)

    # Upper Slanted Armor Deck
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.35, 0.48 + vib))
    deck = bpy.context.active_object
    deck.scale = (1.30, 1.05, 0.35)
    deck.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(deck, width=0.06, segments=2)
    objs.append(deck)

    # 2. Dual Mega-Treads (Left & Right)
    for side in [-1, 1]:
        # Main Tread Box
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.92, -0.22, 0.08))
        tread = bpy.context.active_object
        tread.scale = (0.34, 1.70, 0.46)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.04, segments=2)
        objs.append(tread)

        # Tread Armor Skirts
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.93, -0.22, 0.34 + vib))
        skirt = bpy.context.active_object
        skirt.scale = (0.36, 1.55, 0.12)
        skirt.data.materials.append(mat_bronze)
        apply_uniform_clay_bevel(skirt, width=0.03, segments=2)
        objs.append(skirt)

        # Road Wheel Hubs
        for wy in [-0.80, -0.35, 0.10, 0.50]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.38, vertices=12, location=(side * 0.92, wy, 0.08))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), 0)
            wheel.data.materials.append(mat_iron)
            apply_uniform_clay_bevel(wheel, width=0.02, segments=2)
            objs.append(wheel)

    # 3. Giant Front Revolving Spiked Crushing Drum
    drum_center_y = 0.65
    drum_center_z = 0.18

    # Heavy Drum Roller Cylinder (Oriented horizontally along X-axis)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=1.65, vertices=24, location=(0, drum_center_y, drum_center_z))
    drum = bpy.context.active_object
    drum.rotation_euler = (0, math.radians(90), drum_rot)
    drum.data.materials.append(mat_drum)
    apply_uniform_clay_bevel(drum, width=0.04, segments=2)
    objs.append(drum)

    # Heavy Crushing Spikes / Teeth on the revolving drum (3 rings of 6 spikes)
    for ring_x in [-0.55, -0.18, 0.18, 0.55]:
        for i in range(6):
            ang = drum_rot + i * (2.0 * math.pi / 6.0) + (0.3 if ring_x < 0 else 0.0)
            sp_y = drum_center_y + math.cos(ang) * 0.38
            sp_z = drum_center_z + math.sin(ang) * 0.38
            bpy.ops.mesh.primitive_cone_add(radius1=0.08, depth=0.22, vertices=8, location=(ring_x, sp_y, sp_z))
            spike = bpy.context.active_object
            # Point outward from drum axis
            spike.rotation_euler = (-ang + math.pi / 2.0, 0, 0)
            spike.data.materials.append(mat_teeth)
            apply_uniform_clay_bevel(spike, width=0.015, segments=2)
            objs.append(spike)

    # 4. Heavy Hydraulic Support Arms & Shock Absorbers
    for side in [-1, 1]:
        # Main Forward Swing Arm
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.88, 0.28, 0.22 + piston_bob))
        arm = bpy.context.active_object
        arm.scale = (0.15, 0.85, 0.20)
        arm.rotation_euler = (math.radians(-8 * side), 0, 0)
        arm.data.materials.append(mat_iron)
        apply_uniform_clay_bevel(arm, width=0.03, segments=2)
        objs.append(arm)

        # Hydraulic Cylinder Piston
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.45 + piston_bob, vertices=12, location=(side * 0.65, 0.26, 0.40))
        piston = bpy.context.active_object
        piston.rotation_euler = (math.radians(45), 0, 0)
        piston.data.materials.append(mat_teeth)
        apply_uniform_clay_bevel(piston, width=0.02, segments=2)
        objs.append(piston)

    # 5. Rear Heavy Engine Furnace & Grille
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.78, 0.35 + vib))
    furnace_box = bpy.context.active_object
    furnace_box.scale = (0.90, 0.38, 0.32)
    furnace_box.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(furnace_box, width=0.03, segments=2)
    objs.append(furnace_box)

    # Glowing Furnace Heat Cores
    for gx in [-0.26, 0.0, 0.26]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.20, vertices=12, location=(gx, -0.92, 0.35 + vib))
        vent = bpy.context.active_object
        vent.rotation_euler = (math.radians(90), 0, 0)
        vent.data.materials.append(mat_furnace)
        bpy.ops.object.shade_smooth()
        objs.append(vent)

    # Dual Heavy Exhaust Chimneys
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.50, vertices=12, location=(side * 0.38, -0.65, 0.68 + vib))
        exhaust = bpy.context.active_object
        exhaust.rotation_euler = (math.radians(-15), math.radians(side * 8), 0)
        exhaust.data.materials.append(mat_iron)
        apply_uniform_clay_bevel(exhaust, width=0.02, segments=2)
        objs.append(exhaust)

        # Exhaust Glowing Ring
        bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.025, location=(side * 0.38, -0.65, 0.90 + vib))
        ex_ring = bpy.context.active_object
        ex_ring.rotation_euler = (math.radians(-15), math.radians(side * 8), 0)
        ex_ring.data.materials.append(mat_furnace)
        bpy.ops.object.shade_smooth()
        objs.append(ex_ring)

    return objs

def main():
    print("==================================================")
    print(" Rendering Enemy Crusher (粉碎者) 6-Frame Animation")
    print("==================================================")

    # Render 6 Animated Looping Frames (enemy_crusher_f0..f5.png)
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_enemy_crusher(frame=f)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_crusher_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"[OK] Enemy Crusher frame {f} rendered -> {out_path}")

    print("\n[SUCCESS] Enemy Crusher asset generation finished.")

if __name__ == '__main__':
    main()
