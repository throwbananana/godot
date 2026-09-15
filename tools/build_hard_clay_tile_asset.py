import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    TILE_FULL_BLEED,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    clear_scene,
)

ROOT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(ROOT_DIR, "assets", "sprites", "tiles")
os.makedirs(OUTPUT_DIR, exist_ok=True)

def build_hard_clay_tile():
    objs = []
    # Rich hardened terracotta materials
    mat_clay = create_clay_mat("m_hc_c", (0.84, 0.44, 0.22, 1.0))        # Hardened terracotta brick
    mat_dark_clay = create_clay_mat("m_hc_d", (0.68, 0.34, 0.18, 1.0))   # Dense compressed clay brick
    mat_mortar = create_clay_mat("m_hc_m", (0.35, 0.30, 0.26, 1.0))      # Dark reinforced stone mortar
    mat_iron_band = create_clay_mat("m_hc_i", (0.42, 0.40, 0.44, 1.0))   # Iron reinforcement band
    mat_rivet = create_clay_mat("m_hc_r", (0.92, 0.70, 0.24, 1.0))       # Bronze/Brass rivet studs

    # 1. Full-Bleed Dark Mortar Base Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.22)
    base.data.materials.append(mat_mortar)
    apply_uniform_clay_bevel(base, width=0.08, segments=3, jitter=0.0)
    objs.append(base)

    # 2. 4 Rows of Heavy Bricks (Terracotta + Dark Compacted Clay)
    row_configs = [
        [(-0.84, 1.54), (0.84, 1.54)],
        [(-1.26, 0.70), (0.0, 1.54), (1.26, 0.70)],
        [(-0.84, 1.54), (0.84, 1.54)],
        [(-1.26, 0.70), (0.0, 1.54), (1.26, 0.70)],
    ]
    y_coords = [-1.22, -0.41, 0.41, 1.22]
    for r_idx, row in enumerate(row_configs):
        y = y_coords[r_idx]
        for b_idx, (x, w_size) in enumerate(row):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.14))
            b = bpy.context.active_object
            b.scale = (w_size, 0.62, 0.32)
            # Alternating brick shades for dense structural look
            use_mat = mat_clay if (r_idx + b_idx) % 2 == 0 else mat_dark_clay
            b.data.materials.append(use_mat)
            apply_uniform_clay_bevel(b, width=0.09, segments=3, jitter=0.012)
            objs.append(b)

    # 3. Cross Iron Reinforcement Bands (Central Cross & Corner Braces)
    # Horizontal iron band
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
    band_h = bpy.context.active_object
    band_h.scale = (3.10, 0.22, 0.08)
    band_h.data.materials.append(mat_iron_band)
    apply_uniform_clay_bevel(band_h, width=0.04, segments=2, jitter=0.0)
    objs.append(band_h)

    # Vertical iron band
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
    band_v = bpy.context.active_object
    band_v.scale = (0.22, 3.10, 0.08)
    band_v.data.materials.append(mat_iron_band)
    apply_uniform_clay_bevel(band_v, width=0.04, segments=2, jitter=0.0)
    objs.append(band_v)

    # 4. Bronze Corner & Center Reinforcement Rivet Studs
    rivet_coords = [
        (-1.25, -1.25), (1.25, -1.25),
        (-1.25, 1.25), (1.25, 1.25),
        (0.0, 0.0),
        (-0.75, 0.0), (0.75, 0.0),
        (0.0, -0.75), (0.0, 0.75)
    ]
    for rx, ry in rivet_coords:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.12, location=(rx, ry, 0.33))
        riv = bpy.context.active_object
        riv.data.materials.append(mat_rivet)
        apply_uniform_clay_bevel(riv, width=0.03, segments=2, jitter=0.0)
        objs.append(riv)

    return objs

def main():
    print(">>> Rendering 3D Sokpop Hard Clay / Fortified Dirt Tile...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting()
    objs = build_hard_clay_tile()

    out_file = os.path.join(OUTPUT_DIR, "tile_hard_clay.png")
    render_and_clean(objs, out_file)
    print(f">>> Hard Clay Tile rendered successfully to: {out_file}")

if __name__ == "__main__":
    main()
