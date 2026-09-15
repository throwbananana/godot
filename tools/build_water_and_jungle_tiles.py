"""Regenerate water and jungle/trees tiles, replacing current assets and saving Blender source files.
"""

import os
import sys
import math
import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_water,
    build_sokpop_trees,
    SPRITES_TILES,
    PROJECT_DIR,
)

JITTER_SEED = 4200
BLENDER_DIR = os.path.join(PROJECT_DIR, "assets", "blender")
os.makedirs(BLENDER_DIR, exist_ok=True)
os.makedirs(SPRITES_TILES, exist_ok=True)

def generate_water():
    print("==================================================")
    print(">>> 正在生成水地块 (tile_water, 6 帧动画)...")
    print("==================================================")
    
    # 1. 渲染 6 帧动画精灵
    for i in range(6):
        clear_scene()
        setup_render_settings(rx=256, ry=256)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
        reset_jitter_seed(JITTER_SEED + i)
        objs = build_sokpop_water(frame=i)
        out_path = os.path.join(SPRITES_TILES, f"tile_water_f{i}.png")
        render_and_clean(objs, out_path, label=f"[Water Frame {i}]")
    
    # 2. 生成并保存独立的 Blender 源文件 (tile_water_clay.blend)
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
    reset_jitter_seed(JITTER_SEED)
    build_sokpop_water(frame=0)
    blend_path = os.path.join(BLENDER_DIR, "tile_water_clay.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"[OK] 已保存水地块 Blender 源文件: {blend_path}")


def generate_jungle():
    print("\n==================================================")
    print(">>> 正在生成丛林地块 (tile_trees)...")
    print("==================================================")
    
    # 1. 渲染丛林精灵
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
    reset_jitter_seed(JITTER_SEED)
    objs = build_sokpop_trees()
    out_path = os.path.join(SPRITES_TILES, "tile_trees.png")
    render_and_clean(objs, out_path, label="[Jungle Tile]")
    
    # 2. 生成并保存独立的 Blender 源文件 (tile_trees_clay.blend)
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
    reset_jitter_seed(JITTER_SEED)
    build_sokpop_trees()
    blend_path = os.path.join(BLENDER_DIR, "tile_trees_clay.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"[OK] 已保存丛林地块 Blender 源文件: {blend_path}")


def main():
    generate_water()
    generate_jungle()
    print("\n>>> 全部水地块与丛林地块生成完毕并已取代当前资源！ <<<")

if __name__ == "__main__":
    main()
