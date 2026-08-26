"""build_svg_assets_to_3d.py
自动将 assets/svg/ 目录下的 2D SVG 矢量原画转换为 2.5D 手作黏土 3D 模型并进行 Cycles 渲染。
遵循 sokpop_common 渲染法律与 blender-vector-graphics 规范。
"""

import bpy
import os
import sys
import math

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
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SVG_DIR = os.path.join(PROJECT_DIR, "assets", "svg")
OUT_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "svg_rendered")
os.makedirs(OUT_DIR, exist_ok=True)


def hex_to_rgb(hex_str):
    """转换十六进制颜色 (#RRGGBB) 到 (r, g, b, 1.0)"""
    hex_str = hex_str.lstrip('#')
    if len(hex_str) == 6:
        r = int(hex_str[0:2], 16) / 255.0
        g = int(hex_str[2:4], 16) / 255.0
        b = int(hex_str[4:6], 16) / 255.0
        return (r, g, b, 1.0)
    return (0.8, 0.8, 0.8, 1.0)


def build_3d_clay_from_svg(svg_filename, target_scale=2.8, base_extrude=0.12, base_bevel=0.03):
    svg_path = os.path.join(SVG_DIR, svg_filename)
    if not os.path.exists(svg_path):
        print(f"Error: SVG not found: {svg_path}")
        return []

    before_objs = set(bpy.context.scene.objects)
    bpy.ops.import_curve.svg(filepath=svg_path)
    imported_objs = [o for o in bpy.context.scene.objects if o not in before_objs]

    if not imported_objs:
        print(f"Failed to import curves from: {svg_filename}")
        return []

    # 1. 遍历曲线物体进行深度分层、倒角与尺寸归一化
    # 获取整体包围盒
    min_x = min(o.location.x for o in imported_objs)
    max_x = max(o.location.x + o.dimensions.x for o in imported_objs)
    min_y = min(o.location.y for o in imported_objs)
    max_y = max(o.location.y + o.dimensions.y for o in imported_objs)

    center_x = (min_x + max_x) * 0.5
    center_y = (min_y + max_y) * 0.5
    dim_max = max(max_x - min_x, max_y - min_y, 1e-4)
    scale_factor = target_scale / dim_max

    # 根容器
    root = bpy.data.objects.new(f"Root_{svg_filename}", None)
    bpy.context.collection.objects.link(root)
    root.location = (0, 0, 0)

    # 分层高度步进
    z_step = 0.08

    for idx, obj in enumerate(imported_objs):
        if obj.type != 'CURVE':
            continue
        
        # 居中对齐并等比放大
        obj.location.x = (obj.location.x - center_x) * scale_factor
        # SVG 坐标系 Y 轴向下，在 Blender 中翻转 Y 轴
        obj.location.y = -(obj.location.y - center_y) * scale_factor
        obj.location.z = idx * z_step
        obj.scale = (scale_factor, scale_factor, scale_factor)

        # 设置 2.5D 挤出与倒角
        c_data = obj.data
        c_data.dimensions = '2D'
        c_data.fill_mode = 'BOTH'
        c_data.extrude = base_extrude * (1.0 + idx * 0.15)
        c_data.bevel_depth = base_bevel
        c_data.bevel_resolution = 3
        c_data.resolution_u = 6

        # 材质处理：保留或增强为 Sokpop 黏土材质
        if obj.data.materials:
            orig_mat = obj.data.materials[0]
            # 读取原始颜色
            col = (0.8, 0.8, 0.8, 1.0)
            if orig_mat and orig_mat.use_nodes:
                bsdf = orig_mat.node_tree.nodes.get("Principled BSDF")
                if bsdf and "Base Color" in bsdf.inputs:
                    col = tuple(bsdf.inputs["Base Color"].default_value)
            
            clay_mat = create_clay_mat(f"m_svg_{idx}_{svg_filename}", col, roughness=0.62, bump_strength=0.08)
            obj.data.materials.clear()
            obj.data.materials.append(clay_mat)

        obj.parent = root

    return imported_objs + [root]


def render_all_svg_assets():
    print("==========================================================")
    print(">>> 启动 SVG 矢量原画 -> 2.5D 手作黏土 3D 转换与 Cycles 渲染 <<<")
    print("==========================================================")

    svg_files = [
        ("player_tank.svg", ORTHO_SCALE_TANK, "svg_player_tank.png"),
        ("base_eagle.svg", ORTHO_SCALE_DEFAULT, "svg_base_eagle.png"),
        ("tile_brick.svg", ORTHO_SCALE_DEFAULT, "svg_tile_brick.png"),
        ("tile_steel.svg", ORTHO_SCALE_DEFAULT, "svg_tile_steel.png"),
    ]

    for svg_name, ortho, out_name in svg_files:
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=28)
        create_sokpop_lighting(ortho_scale=ortho)
        
        objs = build_3d_clay_from_svg(svg_name, target_scale=2.6)
        if objs:
            out_path = os.path.join(OUT_DIR, out_name)
            render_and_clean(objs, out_path, label="Rendered 2.5D SVG Asset")
            print(f"  [SUCCESS] {svg_name} -> {out_path}")

    print("\n>>> 所有 SVG 矢量 2.5D 黏土模型转换渲染完成！ <<<")


if __name__ == "__main__":
    render_all_svg_assets()