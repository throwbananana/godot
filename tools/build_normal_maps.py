"""build_normal_maps.py
为核心坦克、瓦片与建筑生成 2D 引擎专用相机空间法线贴图 (Camera-Space Normal Maps)。
用于 Godot 4.5+ CanvasTexture 动态 2D 局部光照 (PointLight2D / DirectionalLight2D)。
"""

import bpy
import os
import sys
import math

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_tank,
    build_sokpop_eagle,
    build_sokpop_brick,
    build_sokpop_steel,
    PLAYER_PALETTES,
    ENEMY_PALETTES,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")


def apply_camera_space_normal_material(objects):
    """为物体赋予相机空间法线材质 (RGB = (Normal + 1.0) * 0.5)"""
    mat = bpy.data.materials.new(name="M_CameraSpace_Normal")
    mat.use_nodes = True
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (600, 0)

    geo = nodes.new(type="ShaderNodeNewGeometry")
    geo.location = (-400, 0)

    vec_trans = nodes.new(type="ShaderNodeVectorTransform")
    vec_trans.location = (-150, 0)
    vec_trans.vector_type = 'NORMAL'
    vec_trans.convert_from = 'WORLD'
    vec_trans.convert_to = 'CAMERA'

    # Godot CanvasTexture 期待相机空间法线: R = X, G = -Y (向下为正或按标准绿色), B = Z
    math_mul = nodes.new(type="ShaderNodeVectorMath")
    math_mul.operation = 'MULTIPLY_ADD'
    math_mul.location = (120, 0)
    math_mul.inputs[1].default_value = (0.5, 0.5, 0.5)
    math_mul.inputs[2].default_value = (0.5, 0.5, 0.5)

    emission = nodes.new(type="ShaderNodeEmission")
    emission.location = (380, 0)

    links.new(geo.outputs["Normal"], vec_trans.inputs["Vector"])
    links.new(vec_trans.outputs["Vector"], math_mul.inputs[0])
    links.new(math_mul.outputs["Vector"], emission.inputs["Color"])
    links.new(emission.outputs["Emission"], out_node.inputs["Surface"])

    for obj in objects:
        if obj.type == 'MESH':
            obj.data.materials.clear()
            obj.data.materials.append(mat)


def render_core_normal_maps():
    print("==========================================================")
    print(">>> 启动相机空间法线贴图 (Camera-Space Normal Map) 批量生成 <<<")
    print("==========================================================")

    # 1. 玩家与基础敌方坦克 6 帧法线贴图
    tanks_to_bake = ["player_tier0", "player_tier1", "player_tier2", "player_tier3",
                     "enemy_basic", "enemy_fast", "enemy_power", "enemy_armor"]
    all_configs = {}
    all_configs.update(PLAYER_PALETTES)
    all_configs.update(ENEMY_PALETTES)

    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)

    for name in tanks_to_bake:
        cfg = all_configs.get(name)
        if not cfg:
            continue
        print(f"--- 正在生成坦克法线贴图: {name} (6 帧) ---")
        for frame in range(6):
            clear_scene()
            setup_render_settings(rx=256, ry=256, samples=16)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame
            )
            apply_camera_space_normal_material(objs)
            out_path = os.path.join(SPRITES_TANKS, f"{name}_f{frame}_n.png")
            render_and_clean(objs, out_path, label="Normal Map")

    # 2. 地形与基地法线贴图
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    tiles = {
        "tile_brick_n.png": build_sokpop_brick,
        "tile_steel_n.png": build_sokpop_steel,
        "base_eagle_n.png": lambda: build_sokpop_eagle(False),
        "base_damaged_n.png": lambda: build_sokpop_eagle(True),
    }

    for fname, builder in tiles.items():
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=16)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = builder()
        apply_camera_space_normal_material(objs)
        out_path = os.path.join(SPRITES_TILES, fname)
        render_and_clean(objs, out_path, label="Normal Map")

    print("\n>>> 核心相机空间 2D 法线贴图全部生成完毕！ <<<")


if __name__ == "__main__":
    render_core_normal_maps()