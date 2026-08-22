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
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
    TILE_PLATE_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

for folder in [SPRITES_TANKS, SPRITES_TILES, SPRITES_UI]:
    os.makedirs(folder, exist_ok=True)

# ==================== 1. DESERT SAND TILE (TILE_SAND) ====================
def build_desert_sand_tile():
    """沙漠流沙地面：金黄细腻黏土，带微风波纹与微陷泥沙质感，100%满幅无缝拼接"""
    objs = []
    mat_sand = create_clay_mat("m_sand_ground", (0.88, 0.72, 0.40, 1.0), roughness=0.92, bump_strength=0.25)
    mat_ripple = create_clay_mat("m_sand_ripple", (0.80, 0.64, 0.34, 1.0), roughness=0.90, bump_strength=0.20)

    # 基础底板 (Full Bleed)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.1)
    base.data.materials.append(mat_sand)
    apply_uniform_clay_bevel(base, width=0.02, segments=2, jitter=0.008)
    objs.append(base)

    # 沙漠微波纹 (Ripples)
    ripple_data = [
        (-0.8, -0.6, 0.9, 0.18, 0.03, 0.2),
        (0.6, -0.7, 1.1, 0.20, 0.03, -0.15),
        (-0.3, 0.1, 1.4, 0.22, 0.03, 0.1),
        (0.7, 0.6, 0.8, 0.16, 0.03, -0.2),
        (-0.7, 0.7, 1.0, 0.18, 0.03, 0.25)
    ]
    for rx, ry, rw, rh, rz, rot in ripple_data:
        bpy.ops.mesh.primitive_cylinder_add(radius=1.0, depth=1.0, vertices=12, location=(rx, ry, 0.01))
        rip = bpy.context.active_object
        rip.scale = (rw * 0.5, rh * 0.5, rz)
        rip.rotation_euler = (0, 0, rot)
        rip.data.materials.append(mat_ripple)
        apply_uniform_clay_bevel(rip, width=0.04, segments=2, jitter=0.01)
        objs.append(rip)

    return objs

# ==================== 2. SAND DUNE BLOCK (TILE_SAND_DUNE) ====================
def build_sand_dune_block():
    """沙堆掩体：风蚀风化黏土沙丘块，整块受击整体坍塌"""
    objs = []
    mat_dune_main = create_clay_mat("m_dune_main", (0.85, 0.66, 0.35, 1.0), roughness=0.88, bump_strength=0.30)
    mat_dune_crest = create_clay_mat("m_dune_crest", (0.95, 0.78, 0.45, 1.0), roughness=0.85, bump_strength=0.20)
    mat_dune_shadow = create_clay_mat("m_dune_shade", (0.72, 0.54, 0.28, 1.0), roughness=0.92, bump_strength=0.25)

    # 隆起的沙丘主基座
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    mound = bpy.context.active_object
    mound.scale = (2.2, 2.2, 0.45)
    mound.data.materials.append(mat_dune_main)
    apply_uniform_clay_bevel(mound, width=0.25, segments=3, jitter=0.025)
    objs.append(mound)

    # 沙丘顶部风蚀山脊 (Crest Ridge)
    bpy.ops.mesh.primitive_cone_add(radius1=1.0, depth=1.0, vertices=16, location=(-0.1, 0.1, 0.45))
    crest = bpy.context.active_object
    crest.scale = (1.2, 0.9, 0.4)
    crest.rotation_euler = (0.1, -0.15, 0.3)
    crest.data.materials.append(mat_dune_crest)
    apply_uniform_clay_bevel(crest, width=0.18, segments=3, jitter=0.02)
    objs.append(crest)

    # 侧翼沙堆坡面 (Dune Skirt)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.4, -0.3, 0.2))
    skirt = bpy.context.active_object
    skirt.scale = (1.1, 1.1, 0.3)
    skirt.rotation_euler = (-0.15, 0.1, -0.2)
    skirt.data.materials.append(mat_dune_shadow)
    apply_uniform_clay_bevel(skirt, width=0.20, segments=3, jitter=0.02)
    objs.append(skirt)

    return objs

# ==================== 3. DESERT TANK (TANK_DESERT) ====================
def build_desert_tank(frame=0):
    """沙漠突击坦克：宽体沙漠履带、耐沙防尘装甲罩、双联装沙漠速射主炮"""
    objs = []
    mat_hull = create_clay_mat(f"m_dst_h_{frame}", (0.84, 0.65, 0.36, 1.0))
    mat_turret = create_clay_mat(f"m_dst_t_{frame}", (0.92, 0.74, 0.42, 1.0))
    mat_camo = create_clay_mat(f"m_dst_c_{frame}", (0.58, 0.42, 0.22, 1.0))
    mat_track = create_clay_mat(f"m_dst_tr_{frame}", (0.35, 0.28, 0.20, 1.0))
    mat_barrel = create_clay_mat(f"m_dst_b_{frame}", (0.28, 0.24, 0.22, 1.0))

    w, l = 1.35, 1.40
    tw, tx, tl = 0.42, 0.72, 1.50 # 宽体沙漠履带
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # 车体 (Hull)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.46)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.09, segments=2, jitter=0.012)
    objs.append(hull)

    # 迷彩涂装条带 (Camo Stripes)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.25, -0.15, 0.24 + bob_z))
    camo1 = bpy.context.active_object
    camo1.scale = (0.7, 0.35, 0.06)
    camo1.rotation_euler = (0, 0, 0.25)
    camo1.data.materials.append(mat_camo)
    apply_uniform_clay_bevel(camo1, width=0.03, segments=2)
    objs.append(camo1)

    # 炮塔 (Turret)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.52, depth=0.40, vertices=16, location=(0, -0.05, 0.32 + bob_z))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret, width=0.07, segments=2, jitter=0.01)
    objs.append(turret)

    # 宽体沙漠履带 (Wide Desert Tracks)
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * tx, 0, bob_z))
        track = bpy.context.active_object
        track.scale = (tw, tl, 0.40)
        track.data.materials.append(mat_track)
        apply_uniform_clay_bevel(track, width=0.07, segments=2)
        objs.append(track)

        # 防沙防尘侧裙护板 (Sand Skirts)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * (tx + 0.04), 0, 0.12 + bob_z))
        skirt = bpy.context.active_object
        skirt.scale = (0.10, tl * 0.95, 0.20)
        skirt.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(skirt, width=0.03, segments=2)
        objs.append(skirt)

        # 履带轮齿齿凸 (Track Cleats)
        for t_idx in range(4):
            y_pos = -0.55 + t_idx * 0.36
            y_shift = (frame / 6.0) * 0.12 if side == 1 else -(frame / 6.0) * 0.12
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * tx, y_pos + y_shift, 0.21 + bob_z))
            cleat = bpy.context.active_object
            cleat.scale = (tw * 0.85, 0.10, 0.05)
            cleat.data.materials.append(mat_camo)
            objs.append(cleat)

    # 双联装沙漠主炮 (Dual High-Velocity Barrels)
    for side in [-0.18, 0.18]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=0.88, vertices=12, location=(side, 0.60, 0.32 + bob_z))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_barrel)
        apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
        objs.append(barrel)

        # 炮口制退消焰器
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.14, vertices=12, location=(side, 1.02, 0.32 + bob_z))
        brake = bpy.context.active_object
        brake.rotation_euler = (math.radians(90), 0, 0)
        brake.data.materials.append(mat_camo)
        objs.append(brake)

    return objs

# ==================== 4. UI BADGES ====================
def build_badge_desert():
    """UI 徽章：沙漠地形与烈日标志"""
    objs = []
    mat_sun = create_clay_mat("m_ui_sun", (1.0, 0.82, 0.25, 1.0), roughness=0.4, emission=(1.0, 0.82, 0.25), emission_str=1.2)
    mat_dune = create_clay_mat("m_ui_bdune", (0.86, 0.65, 0.32, 1.0), roughness=0.88)

    # 烈日 (Sun)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.75, depth=0.2, vertices=24, location=(0, 0.4, 0.1))
    sun = bpy.context.active_object
    sun.data.materials.append(mat_sun)
    objs.append(sun)

    # 前景沙丘 (Dune)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.4, 0.25))
    dune = bpy.context.active_object
    dune.scale = (2.2, 1.2, 0.5)
    dune.rotation_euler = (0, 0, 0.15)
    dune.data.materials.append(mat_dune)
    apply_uniform_clay_bevel(dune, width=0.15, segments=3)
    objs.append(dune)

    return objs

def build_badge_desert_tank():
    """UI 徽章：沙漠坦克头像"""
    return build_desert_tank(frame=0)

# ==================== MAIN RENDER PIPELINE ====================
def main():
    print("\n=======================================================")
    print(">>> RENDERING DESERT TERRAIN, DUNES & DESERT TANK  <<<")
    print("=======================================================\n")

    # 1. Desert Sand Tile
    print("Rendering tile_sand.png...")
    reset_jitter_seed(901)
    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, sun_energy=0.9, ambient_strength=0.85)
    sand_objs = build_desert_sand_tile()
    render_and_clean(sand_objs, os.path.join(SPRITES_TILES, "tile_sand.png"))

    # 2. Sand Dune Block
    print("Rendering tile_sand_dune.png...")
    reset_jitter_seed(902)
    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, sun_energy=0.9, ambient_strength=0.85)
    dune_objs = build_sand_dune_block()
    render_and_clean(dune_objs, os.path.join(SPRITES_TILES, "tile_sand_dune.png"))

    # 3. Desert Tank (6 Frames)
    print("Rendering tank_desert_f0..f5.png...")
    for f in range(6):
        reset_jitter_seed(910 + f)
        clear_scene()
        setup_render_settings(256, 256)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK, sun_energy=0.9, ambient_strength=0.85)
        tank_objs = build_desert_tank(frame=f)
        render_and_clean(tank_objs, os.path.join(SPRITES_TANKS, f"tank_desert_f{f}.png"))

    # 4. Badges
    print("Rendering badge_desert.png & badge_desert_tank.png...")
    reset_jitter_seed(920)
    clear_scene()
    setup_render_settings(128, 128)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, sun_energy=0.9, ambient_strength=0.85)
    badge_objs = build_badge_desert()
    render_and_clean(badge_objs, os.path.join(SPRITES_UI, "badge_desert.png"))

    reset_jitter_seed(921)
    clear_scene()
    setup_render_settings(128, 128)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK, sun_energy=0.9, ambient_strength=0.85)
    tank_badge_objs = build_badge_desert_tank()
    render_and_clean(tank_badge_objs, os.path.join(SPRITES_UI, "badge_desert_tank.png"))

    print("\n🎉 ALL DESERT TERRAIN & TANK RENDERS COMPLETE! 🎉\n")

if __name__ == "__main__":
    main()
