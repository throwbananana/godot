"""Build and export all tile scenes to Blender .blend project files, including an integrated Showcase scene.
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
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_water,
    build_sokpop_trees,
    build_sokpop_brick,
    build_sokpop_steel,
    build_sokpop_eagle,
    SPRITES_TILES,
    PROJECT_DIR,
)

JITTER_SEED = 4200
BLENDER_DIR = os.path.join(PROJECT_DIR, "assets", "blender")
os.makedirs(BLENDER_DIR, exist_ok=True)

def build_showcase_blend():
    print("==================================================")
    print(">>> 正在构建综合 Blender 工程 (tile_showcase_all.blend)...")
    print("==================================================")
    clear_scene()
    setup_render_settings(rx=1920, ry=1080)
    create_sokpop_lighting(ortho_scale=12.0, seamless=True)

    scene_coll = bpy.context.scene.collection

    # 1. 纯净水面集合 (Water Tile - Clean Water)
    coll_water = bpy.data.collections.new("01_Water_Tile_Clean")
    scene_coll.children.link(coll_water)
    reset_jitter_seed(JITTER_SEED)
    w_objs = build_sokpop_water(frame=0)
    for obj in w_objs:
        obj.location.x -= 2.2
        coll_water.objects.link(obj)

    # 2. 丛林地块集合 (Jungle Tile - Tropical Trees)
    coll_trees = bpy.data.collections.new("02_Jungle_Tile_Trees")
    scene_coll.children.link(coll_trees)
    reset_jitter_seed(JITTER_SEED)
    t_objs = build_sokpop_trees()
    for obj in t_objs:
        obj.location.x += 2.2
        coll_trees.objects.link(obj)

    # 3. 红砖地块 (Brick Tile)
    coll_brick = bpy.data.collections.new("03_Brick_Tile")
    scene_coll.children.link(coll_brick)
    b_objs = build_sokpop_brick()
    for obj in b_objs:
        obj.location.x -= 2.2
        obj.location.y -= 4.0
        coll_brick.objects.link(obj)

    # 4. 钢块地块 (Steel Tile)
    coll_steel = bpy.data.collections.new("04_Steel_Tile")
    scene_coll.children.link(coll_steel)
    s_objs = build_sokpop_steel()
    for obj in s_objs:
        obj.location.x += 2.2
        obj.location.y -= 4.0
        coll_steel.objects.link(obj)

    showcase_path = os.path.join(BLENDER_DIR, "tile_showcase_all.blend")
    bpy.ops.wm.save_as_mainfile(filepath=showcase_path)
    print(f"[OK] 已保存综合展示工程: {showcase_path}")

    # 同时更新独立的 tile_water_clay.blend
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
    reset_jitter_seed(JITTER_SEED)
    coll_w_single = bpy.data.collections.new("Water_Tile_Clean")
    scene_coll_w = bpy.context.scene.collection
    scene_coll_w.children.link(coll_w_single)
    w_single = build_sokpop_water(frame=0)
    for obj in w_single:
        coll_w_single.objects.link(obj)
    w_single_path = os.path.join(BLENDER_DIR, "tile_water_clay.blend")
    bpy.ops.wm.save_as_mainfile(filepath=w_single_path)
    print(f"[OK] 已更新水地块独立工程: {w_single_path}")

    # 同时更新独立的 tile_trees_clay.blend
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
    reset_jitter_seed(JITTER_SEED)
    coll_t_single = bpy.data.collections.new("Jungle_Tile_Trees")
    scene_coll_t = bpy.context.scene.collection
    scene_coll_t.children.link(coll_t_single)
    t_single = build_sokpop_trees()
    for obj in t_single:
        coll_t_single.objects.link(obj)
    t_single_path = os.path.join(BLENDER_DIR, "tile_trees_clay.blend")
    bpy.ops.wm.save_as_mainfile(filepath=t_single_path)
    print(f"[OK] 已更新丛林地块独立工程: {t_single_path}")

if __name__ == "__main__":
    build_showcase_blend()
