"""build_normal_maps.py
为核心坦克、瓦片与建筑生成 2D 引擎专用相机空间法线贴图 (Camera-Space Normal Maps)。
用于 Godot 4.5+ CanvasTexture 动态 2D 局部光照 (PointLight2D / DirectionalLight2D)。

    blender --background --python tools/build_normal_maps.py
    blender --background --python tools/build_normal_maps.py -- base_eagle   # 只渲某一组

=== 法线贴图必须逐帧配齐, 否则一播动画就静默失效 ===

TextureHelper.get_tex() 是按**文件名**找法线的: 加载 foo.png 之后去找同目录的
foo_n.png, 找到才包成 CanvasTexture。所以一张有动画帧的资源, 法线也必须按
`<名字>_f<N>_n.png` 逐帧渲 —— 坦克一直是这么做的 (enemy_basic_f0_n.png ~ f5)。

鹰巢曾经漏了这一条。它只有一张 base_eagle_n.png, 而 base_eagle.gd 加了待机
动画之后, _ready() 里第一件事就是 `sprite.texture = idle_frames[0]` ——
base_eagle_f0.png 没有 _n 兄弟, 于是拿到的是裸 Texture2D。**那张
base_eagle_n.png 从此再也不会被用到**: 它只在"取不到动画帧"的退化路径上还有效,
而动画帧一直都在。鹰巢身上恰好挂着一盏 PointLight2D 光环, 本该照出黏土表面的
起伏, 实际照在一张平贴图上。

没有任何报错 —— 法线丢了只是光照变平, 而"变平"和"这个资源本来就没做法线"
长得一模一样。加动画帧的时候要连带问一句: 这张图有没有 _n 兄弟?
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
from build_sokpop_animations import build_base_eagle_idle
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

    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = [a for a in argv if not a.startswith("-")]

    def wanted(name):
        """没点名就全渲; 点了名就只渲名字对得上的那些。

        加这个过滤是因为本脚本一跑就是 48 张坦克法线 + 4 张地形 + 6 张鹰巢,
        而补一组漏掉的法线不该顺手把另外 52 张也重渲一遍 —— 那正是
        CLAUDE.md "Never run the unified script just to change one asset"
        说的那种爆炸半径。"""
        return (not only) or any(a in name for a in only)

    # 1. 玩家与基础敌方坦克 6 帧法线贴图
    tanks_to_bake = ["player_tier0", "player_tier1", "player_tier2", "player_tier3",
                     "enemy_basic", "enemy_fast", "enemy_power", "enemy_armor"]
    tanks_to_bake = [t for t in tanks_to_bake if wanted(t)]
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
        if not wanted(fname):
            continue
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=16)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = builder()
        apply_camera_space_normal_material(objs)
        out_path = os.path.join(SPRITES_TILES, fname)
        render_and_clean(objs, out_path, label="Normal Map")

    # 3. 鹰巢待机 6 帧的法线贴图
    #
    # 必须逐帧渲, 理由见文件头 —— base_eagle.gd 一进 _ready() 就把贴图换成了
    # base_eagle_f0, 只有一张 base_eagle_n.png 的话法线从此再也接不上。
    #
    # 这里调 build_base_eagle_idle() 而不是 build_sokpop_eagle(), 是因为法线
    # 记录的是**几何朝向**: 待机动画每一帧的小鸟位置、翅膀角度、呼吸缩放都不同,
    # 拿静止姿态的法线去配动着的漫反射图, 光照会和形体对不上。
    # 那个函数自己会 reset_jitter_seed 成固定值, 所以逐帧的底座依然完全一致。
    for i in range(6):
        fname = f"base_eagle_f{i}_n.png"
        if not wanted(fname):
            continue
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=16)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = build_base_eagle_idle(i)
        apply_camera_space_normal_material(objs)
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname), label="Normal Map")


    print("\n>>> 核心相机空间 2D 法线贴图全部生成完毕！ <<<")


if __name__ == "__main__":
    render_core_normal_maps()