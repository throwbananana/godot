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
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)

# ==================== ROLLER WALL / PULLEY MOVABLE WALL ====================
def build_roller_wall(frame: int = 0):
    """Build a fortified clay Roller Wall mounted on 4 heavy caster wheels.
    
    frame: 0..3 animates wheel rotation (90 deg / frame) and suspension compression.
    """
    objs = []

    # Material Palette:
    # 1. Fortified Slate-Blue Steel Clay Body
    mat_wall = create_clay_mat(f"m_rw_wall_{frame}", (0.28, 0.32, 0.42, 1.0), roughness=0.55)
    # 2. Heavy Cast-Iron Wheel Rim & Brackets
    mat_metal = create_clay_mat(f"m_rw_iron_{frame}", (0.20, 0.20, 0.24, 1.0), roughness=0.65)
    # 3. Bronze/Gold Corner Reinforcements
    mat_bronze = create_clay_mat(f"m_rw_brz_{frame}", (0.90, 0.62, 0.20, 1.0), roughness=0.40)
    # 4. Industrial Orange Warning Bumpers
    mat_bumper = create_clay_mat(f"m_rw_bmp_{frame}", (0.95, 0.50, 0.12, 1.0), roughness=0.45)
    # 5. Luminous Kinetic Storage Core
    mat_core = create_clay_mat(f"m_rw_core_{frame}", (0.25, 0.88, 1.0, 1.0), emission=(0.25, 0.88, 1.0, 1.0), emission_str=3.2)
    # 6. Wheel Rubber Tread
    mat_rubber = create_clay_mat(f"m_rw_rub_{frame}", (0.12, 0.12, 0.15, 1.0), roughness=0.80)

    # Frame animation parameters:
    wheel_rot = frame * (math.pi / 2.0)
    suspension_bob = math.sin(frame * (math.pi / 2.0)) * 0.02

    # 1. Main Fortified Wall Block (Central Clay Cube)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18 + suspension_bob))
    wall_body = bpy.context.active_object
    wall_body.scale = (1.50, 1.50, 0.85)
    wall_body.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(wall_body, width=0.08, segments=3)
    objs.append(wall_body)

    # Top Cap Plate (slanted bevel)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.64 + suspension_bob))
    top_cap = bpy.context.active_object
    top_cap.scale = (1.30, 1.30, 0.14)
    top_cap.data.materials.append(mat_bronze)
    apply_uniform_clay_bevel(top_cap, width=0.04, segments=2)
    objs.append(top_cap)

    # 2. Kinetic Core Emitter in Center Top
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.18, vertices=16, location=(0, 0, 0.72 + suspension_bob))
    core_housing = bpy.context.active_object
    core_housing.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(core_housing, width=0.03, segments=2)
    objs.append(core_housing)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, 0, 0.78 + suspension_bob))
    core_sphere = bpy.context.active_object
    core_sphere.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core_sphere)

    # 3. Four Corner Heavy Iron Wheel Casters / Rollers
    caster_positions = [
        (-0.64, -0.64),
        (0.64, -0.64),
        (-0.64, 0.64),
        (0.64, 0.64)
    ]
    for (cx, cy) in caster_positions:
        # Vertical Suspension Strut
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.45, vertices=12, location=(cx, cy, -0.15 + suspension_bob * 0.5))
        strut = bpy.context.active_object
        strut.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(strut, width=0.02, segments=2)
        objs.append(strut)

        # Wheel Hub / Axle
        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.16, vertices=16, location=(cx, cy, -0.36))
        wheel = bpy.context.active_object
        # Wheel orientation: rolling along Y axis (rotated around X)
        wheel.rotation_euler = (wheel_rot, math.radians(90), 0)
        wheel.data.materials.append(mat_rubber)
        apply_uniform_clay_bevel(wheel, width=0.03, segments=2)
        objs.append(wheel)

        # Wheel Bronze Center Cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.19, vertices=12, location=(cx, cy, -0.36))
        wheel_cap = bpy.context.active_object
        wheel_cap.rotation_euler = (wheel_rot, math.radians(90), 0)
        wheel_cap.data.materials.append(mat_bronze)
        apply_uniform_clay_bevel(wheel_cap, width=0.02, segments=2)
        objs.append(wheel_cap)

    # 4. Four Directional Heavy Impact Bumpers (Front, Back, Left, Right)
    bumper_specs = [
        ((0, -0.80, 0.12 + suspension_bob), (1.40, 0.16, 0.40)),  # Front
        ((0, 0.80, 0.12 + suspension_bob), (1.40, 0.16, 0.40)),   # Back
        ((-0.80, 0, 0.12 + suspension_bob), (0.16, 1.40, 0.40)),  # Left
        ((0.80, 0, 0.12 + suspension_bob), (0.16, 1.40, 0.40)),   # Right
    ]
    for loc, sc in bumper_specs:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        bmp = bpy.context.active_object
        bmp.scale = sc
        bmp.data.materials.append(mat_bumper)
        apply_uniform_clay_bevel(bmp, width=0.04, segments=2)
        objs.append(bmp)

    # 5. Reinforcement Corner Armor Rivets
    for (rx, ry) in [(-0.76, -0.76), (0.76, -0.76), (-0.76, 0.76), (0.76, 0.76)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.90, vertices=8, location=(rx, ry, 0.18 + suspension_bob))
        armor_corner = bpy.context.active_object
        armor_corner.data.materials.append(mat_bronze)
        apply_uniform_clay_bevel(armor_corner, width=0.03, segments=2)
        objs.append(armor_corner)

    return objs

def main():
    print("==================================================")
    print(" Rendering Roller Wall (滑轮墙) 3D Building Assets ")
    print("==================================================")

    # 1. Render 4 Animated Rolling Frames (roller_wall_f0..f3.png)
    for f in range(4):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = build_roller_wall(frame=f)
        out_path = os.path.join(SPRITES_BUILDINGS, f"roller_wall_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"[OK] Roller Wall frame {f} rendered -> {out_path}")

    # 2. Render Static Base / Hotbar Icon (roller_wall.png)
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_roller_wall(frame=0)
    static_out = os.path.join(SPRITES_BUILDINGS, "roller_wall.png")
    render_and_clean(objs, static_out)
    print(f"[OK] Roller Wall static copy rendered -> {static_out}")

    print("\n[SUCCESS] Roller Wall asset generation finished.")

if __name__ == '__main__':
    main()
