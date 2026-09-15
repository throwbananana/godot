import bpy
import math
import os
import sys
import shutil

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
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)

# ==============================================================================
# ENEMY SHIELD TOWER (敌方护盾发生塔)
# ==============================================================================
def build_enemy_shield_tower(frame: int = 0):
    """Build a fortified hostile shield generator pylon with rotating energy emitter."""
    objs = []

    # Palette
    mat_base = create_clay_mat(f"m_st_base_{frame}", (0.16, 0.15, 0.19, 1.0), roughness=0.55)
    mat_armor = create_clay_mat(f"m_st_arm_{frame}", (0.24, 0.22, 0.28, 1.0), roughness=0.50)
    mat_crimson = create_clay_mat(f"m_st_crim_{frame}", (0.85, 0.20, 0.16, 1.0), roughness=0.35)
    mat_gold = create_clay_mat(f"m_st_gold_{frame}", (0.92, 0.72, 0.16, 1.0), roughness=0.30)
    mat_core = create_clay_mat(f"m_st_core_{frame}", (0.15, 0.85, 1.0, 1.0), emission=(0.15, 0.85, 1.0, 1.0), emission_str=4.8)
    mat_field_ring = create_clay_mat(f"m_st_ring_{frame}", (0.25, 0.70, 0.95, 1.0), emission=(0.25, 0.70, 0.95, 1.0), emission_str=2.5)

    spin_angle = frame * (math.pi / 2.0)
    float_vib = math.sin(frame * (math.pi / 2.0)) * 0.03

    # 1. Heavy Octagonal Bunker Base Platform
    bpy.ops.mesh.primitive_cylinder_add(radius=1.25, depth=0.30, vertices=8, location=(0, 0, 0.12))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.08, segments=2)
    objs.append(base)

    # 2. Fortified Armor Plating with Crimson Trim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.22, vertices=8, location=(0, 0, 0.32))
    armor_tier = bpy.context.active_object
    armor_tier.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(armor_tier, width=0.06, segments=2)
    objs.append(armor_tier)

    # 3. Four Corner Support Pylons
    for i in range(4):
        p_ang = i * (math.pi / 2.0) + math.pi / 4.0
        px = math.cos(p_ang) * 0.82
        py = math.sin(p_ang) * 0.82

        # Pylon strut
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 0.45))
        pylon = bpy.context.active_object
        pylon.scale = (0.26, 0.26, 0.50)
        pylon.rotation_euler = (0, 0, p_ang)
        pylon.data.materials.append(mat_crimson)
        apply_uniform_clay_bevel(pylon, width=0.03, segments=2)
        objs.append(pylon)

        # Gold Conduit Node cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.16, vertices=8, location=(px, py, 0.72))
        node = bpy.context.active_object
        node.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(node, width=0.02, segments=2)
        objs.append(node)

    # 4. Central Reactor Spire Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=0.45, vertices=16, location=(0, 0, 0.52))
    spire_base = bpy.context.active_object
    spire_base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(spire_base, width=0.04, segments=2)
    objs.append(spire_base)

    # 5. Floating / Levitating Radiant Plasma Core (Animated Float & Glow)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34, location=(0, 0, 0.95 + float_vib))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 6. Rotating Concentric Shield Resonator Rings
    # Outer Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.62, minor_radius=0.045, location=(0, 0, 0.95 + float_vib))
    r_outer = bpy.context.active_object
    r_outer.rotation_euler = (math.radians(25), math.radians(20), spin_angle)
    r_outer.data.materials.append(mat_field_ring)
    bpy.ops.object.shade_smooth()
    objs.append(r_outer)

    # Inner Cross Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.48, minor_radius=0.035, location=(0, 0, 0.95 + float_vib))
    r_inner = bpy.context.active_object
    r_inner.rotation_euler = (math.radians(-35), math.radians(15), -spin_angle * 1.5)
    r_inner.data.materials.append(mat_gold)
    bpy.ops.object.shade_smooth()
    objs.append(r_inner)

    return objs


def main():
    print("==================================================================")
    print(">>> RENDERING ENEMY SHIELD TOWER SPRITES <<<")
    print("==================================================================")

    for f in range(4):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)

        objs = build_enemy_shield_tower(frame=f)

        frame_path = os.path.join(SPRITES_BUILDINGS, f"enemy_shield_tower_f{f}.png")
        render_and_clean(objs, frame_path)
        print(f"  [OK] enemy_shield_tower frame {f} -> {frame_path}")

    # Copy frame 0 as primary static sprite
    primary_path = os.path.join(SPRITES_BUILDINGS, "enemy_shield_tower.png")
    shutil.copyfile(os.path.join(SPRITES_BUILDINGS, "enemy_shield_tower_f0.png"), primary_path)
    print(f"  [OK] primary static sprite -> {primary_path}")

    print("\n>>> ENEMY SHIELD TOWER RENDER COMPLETED! <<<")

if __name__ == "__main__":
    main()
