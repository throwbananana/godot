"""build_bunker_assets.py — 战术防御堡垒 (Tactical Bunker) 3D 建模与 Cycles 黏土渲染管线

战术防御堡垒 (Bunker):
  - 正面：加厚倾斜重型防盾 + 梯形内凹射击孔 (Embrasure / Firing Slit) + 钢铆钉加固
  - 侧面与后方：开放式掩体矮墙 + 支撑角铁 (露出薄弱侧翼)
  - 内部平台：防滑网纹踏板，供坦克躲在掩体后方架枪
  - 顶部：正面方向警示标牌 / 射击孔引导槽

输出资源:
  - assets/sprites/buildings/bunker.png
  - assets/sprites/buildings/bunker_f0.png (朝上 UP)
  - assets/sprites/buildings/bunker_f1.png (朝右 RIGHT)
  - assets/sprites/buildings/bunker_f2.png (朝下 DOWN)
  - assets/sprites/buildings/bunker_f3.png (朝左 LEFT)
"""

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
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)


def build_bunker(rot_deg: float = 0.0):
    """构建战术防御堡垒 3D 模型"""
    objs = []

    # 1. 材质定义 (Sokpop 黏土着色)
    col_concrete = srgb_to_linear((0.48, 0.50, 0.46, 1.0)) # 堡垒厚重混泥土/装甲灰绿
    col_steel    = srgb_to_linear((0.30, 0.32, 0.35, 1.0)) # 重型加固角钢与射击孔边缘
    col_shield   = srgb_to_linear((0.24, 0.38, 0.32, 1.0)) # 正面重装甲防盾深绿
    col_trim     = srgb_to_linear((0.85, 0.65, 0.15, 1.0)) # 正面射击孔引导金黄标线
    col_floor    = srgb_to_linear((0.36, 0.35, 0.32, 1.0)) # 掩体内部踏板
    col_sandbag  = srgb_to_linear((0.68, 0.58, 0.38, 1.0)) # 侧后方沙袋/掩体墙

    mat_concrete = create_clay_mat("m_bk_conc", col_concrete, roughness=0.75)
    mat_steel    = create_clay_mat("m_bk_stl", col_steel, roughness=0.50)
    mat_shield   = create_clay_mat("m_bk_shd", col_shield, roughness=0.55)
    mat_trim     = create_clay_mat("m_bk_tm", col_trim, roughness=0.45)
    mat_floor    = create_clay_mat("m_bk_flr", col_floor, roughness=0.85)
    mat_sandbag  = create_clay_mat("m_bk_sb", col_sandbag, roughness=0.80)

    # 根节点空物体用于统一旋转朝向
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    root_empty = bpy.context.active_object
    root_empty.rotation_euler = (0, 0, math.radians(rot_deg))
    objs.append(root_empty)

    # ==================== 1. 掩体底座地坪 (Floor Base) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.10))
    floor = bpy.context.active_object
    floor.scale = (1.52, 1.52, 0.18)
    floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(floor, width=0.04, segments=2)
    floor.parent = root_empty
    objs.append(floor)

    # ==================== 2. 正面重装甲主防盾 (Front Heavy Shield) ====================
    # 正面分为左右两堵厚盾，中间留出射击缝 (Embrasure)
    shield_w = 0.58
    shield_h = 0.72
    shield_d = 0.38
    shield_y = 0.52

    # 正面左主盾
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.45, shield_y, 0.28))
    sh_left = bpy.context.active_object
    sh_left.scale = (shield_w, shield_d, shield_h)
    sh_left.rotation_euler = (math.radians(-10), 0, 0) # 倾斜防弹装甲面
    sh_left.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(sh_left, width=0.08, segments=3)
    sh_left.parent = root_empty
    objs.append(sh_left)

    # 正面右主盾
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.45, shield_y, 0.28))
    sh_right = bpy.context.active_object
    sh_right.scale = (shield_w, shield_d, shield_h)
    sh_right.rotation_euler = (math.radians(-10), 0, 0)
    sh_right.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(sh_right, width=0.08, segments=3)
    sh_right.parent = root_empty
    objs.append(sh_right)

    # 正面上横梁顶盖 (Lintel Beam over Embrasure)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, shield_y + 0.02, 0.54))
    lintel = bpy.context.active_object
    lintel.scale = (1.48, shield_d * 1.05, 0.20)
    lintel.rotation_euler = (math.radians(-10), 0, 0)
    lintel.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(lintel, width=0.05, segments=3)
    lintel.parent = root_empty
    objs.append(lintel)

    # 射击孔引导金黄反光标 (Embrasure Directional Accent)
    for tx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, shield_y + 0.16, 0.24))
        tab = bpy.context.active_object
        tab.scale = (0.06, 0.10, 0.38)
        tab.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(tab, width=0.02, segments=2)
        tab.parent = root_empty
        objs.append(tab)

    # ==================== 3. 正面防盾外侧重型角钢支架与铆钉 ====================
    for sx in [-0.70, 0.70]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, shield_y - 0.05, 0.26))
        col = bpy.context.active_object
        col.scale = (0.16, 0.28, 0.68)
        col.data.materials.append(mat_concrete)
        apply_uniform_clay_bevel(col, width=0.04, segments=2)
        col.parent = root_empty
        objs.append(col)

        # 加固圆铆钉
        for rz in [0.08, 0.32, 0.52]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(sx, shield_y + 0.12, rz))
            rivet = bpy.context.active_object
            rivet.data.materials.append(mat_steel)
            bpy.ops.object.shade_smooth()
            rivet.parent = root_empty
            objs.append(rivet)

    # ==================== 4. 侧面矮掩体墙 (Flank Walls - 薄弱侧) ====================
    # 侧墙明显低矮且带有砖缝/沙袋结构，直观体现出侧面的弱点
    for side_x in [-0.68, 0.68]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, -0.15, 0.12))
        swall = bpy.context.active_object
        swall.scale = (0.22, 0.90, 0.38)
        swall.data.materials.append(mat_sandbag)
        apply_uniform_clay_bevel(swall, width=0.04, segments=2)
        swall.parent = root_empty
        objs.append(swall)

    # ==================== 5. 后方开放式进出通道 (Open Rear Entry) ====================
    # 后方两角设置两只小型支撑角铁，中间完全开敞，方便己方坦克紧贴掩体后部架枪
    for rx in [-0.60, 0.60]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.45, vertices=12,
                                             location=(rx, -0.62, 0.15))
        post = bpy.context.active_object
        post.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(post, width=0.02, segments=2)
        post.parent = root_empty
        objs.append(post)

    # 内部沙袋踏板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, -0.02))
    in_pad = bpy.context.active_object
    in_pad.scale = (0.95, 0.70, 0.08)
    in_pad.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(in_pad, width=0.02, segments=2)
    in_pad.parent = root_empty
    objs.append(in_pad)

    return objs


def render_all_bunker_assets():
    """渲染战术防御堡垒 4 个朝向与默认图标"""
    print(">>> 正在初始化 Blender Cycles 战术防御堡垒渲染场景...")
    setup_render_settings(rx=256, ry=256, samples=32)

    # 1. 默认图标 (bunker.png - 正面朝上)
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_bunker(rot_deg=0.0)
    out_path = os.path.join(SPRITES_BUILDINGS, "bunker.png")
    render_and_clean(objs, out_path)
    print(f"  [OK] 渲染默认堡垒图标 -> {out_path}")

    # 2. 4 个朝向帧 (bunker_f0 ~ f3)
    # f0 = UP (0°), f1 = RIGHT (270°), f2 = DOWN (180°), f3 = LEFT (90°)
    angles = [0.0, 270.0, 180.0, 90.0]
    for f, deg in enumerate(angles):
        clear_scene()
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_bunker(rot_deg=deg)
        f_path = os.path.join(SPRITES_BUILDINGS, f"bunker_f{f}.png")
        render_and_clean(objs, f_path)
        print(f"  [OK] 渲染朝向帧 {f} ({deg}°) -> {f_path}")

    print("\n>>> 所有战术防御堡垒模型与渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_bunker_assets()
