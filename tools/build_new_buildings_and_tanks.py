"""build_new_buildings_and_tanks.py — 新增建筑与坦克建模渲染管线

新增资源:
  建筑 (Buildings):
    1. radar_station.png      — 雷达站 (旋转天线阵 + 六边形基座)
    2. ammo_depot.png         — 弹药仓库 (厚重方形弹药箱堆 + 危险条纹)
    3. command_post.png       — 指挥部 (带旗帜的多棱指挥楼)
    4. sniper_nest.png        — 狙击碉堡 (低矮掩体 + 瞭望孔)
    5. emp_tower.png          — EMP塔 (放电线圈 + 电弧发射器)

  坦克 (Tanks, 6帧旋转动画):
    1. tank_sniper_{f0-f5}.png   — 超长狙击炮坦克 (纤细超长炮管 + 消焰器)
    2. tank_flame_{f0-f5}.png    — 喷火坦克 (宽口喷火管 + 火焰瓶)
    3. tank_stealth_{f0-f5}.png  — 隐形坦克 (低矮扁平 + 菱形切面 + 哑光黑)
    4. tank_artillery_{f0-f5}.png — 自行火炮 (大仰角炮管 + 宽底盘)
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
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_PROP,
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_TANKS     = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")

for d in [SPRITES_BUILDINGS, SPRITES_TANKS]:
    os.makedirs(d, exist_ok=True)

# ══════════════════════════════════════════════════════════════════
#  BUILDINGS
# ══════════════════════════════════════════════════════════════════

def build_radar_station():
    """雷达站：六边形重型底座 + 旋转天线碟 + 警示灯"""
    objs = []
    mat_base   = create_clay_mat("m_rd_base", srgb_to_linear((0.22, 0.30, 0.24, 1.0)), roughness=0.65)
    mat_tower  = create_clay_mat("m_rd_tower", srgb_to_linear((0.55, 0.60, 0.58, 1.0)), roughness=0.50)
    mat_dish   = create_clay_mat("m_rd_dish", srgb_to_linear((0.85, 0.88, 0.82, 1.0)), roughness=0.35)
    mat_warn   = create_clay_mat("m_rd_warn", srgb_to_linear((0.95, 0.22, 0.15, 1.0)),
                                 emission=srgb_to_linear((1.0, 0.25, 0.10, 1.0)), emission_str=4.5)
    mat_green  = create_clay_mat("m_rd_green", srgb_to_linear((0.15, 0.95, 0.40, 1.0)),
                                 emission=srgb_to_linear((0.15, 0.95, 0.40, 1.0)), emission_str=3.0)
    mat_strut  = create_clay_mat("m_rd_strut", srgb_to_linear((0.38, 0.42, 0.40, 1.0)), roughness=0.55)

    # 1. 六边形重型底座
    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.28, vertices=6, location=(0, 0, -0.10))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    # 2. 四棱柱塔身 (稍微旋转45°给菱形感)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
    tower = bpy.context.active_object
    tower.scale = (0.44, 0.44, 0.60)
    tower.rotation_euler = (0, 0, math.radians(22.5))
    tower.data.materials.append(mat_tower)
    apply_uniform_clay_bevel(tower, width=0.06, segments=2)
    objs.append(tower)

    # 3. 天线旋转臂 (Y-boom)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.60))
    arm = bpy.context.active_object
    arm.scale = (0.06, 0.75, 0.05)
    arm.data.materials.append(mat_strut)
    apply_uniform_clay_bevel(arm, width=0.02, segments=2)
    objs.append(arm)

    # 水平反射镜 boom 另一轴
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.62))
    arm2 = bpy.context.active_object
    arm2.scale = (0.75, 0.06, 0.04)
    arm2.data.materials.append(mat_strut)
    apply_uniform_clay_bevel(arm2, width=0.02, segments=2)
    objs.append(arm2)

    # 4. 抛物面天线碟 (用扁球近似)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.50, location=(0, 0.30, 0.70))
    dish = bpy.context.active_object
    dish.scale = (1.0, 0.38, 0.82)
    dish.data.materials.append(mat_dish)
    bpy.ops.object.shade_smooth()
    objs.append(dish)

    # 5. 碟心馈源
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.24, vertices=12, location=(0, 0.42, 0.70))
    feed = bpy.context.active_object
    feed.rotation_euler = (math.radians(90), 0, 0)
    feed.data.materials.append(mat_strut)
    apply_uniform_clay_bevel(feed, width=0.02, segments=2)
    objs.append(feed)

    # 6. 顶部红色警告灯
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0, 0, 0.82))
    warn = bpy.context.active_object
    warn.data.materials.append(mat_warn)
    bpy.ops.object.shade_smooth()
    objs.append(warn)

    # 7. 底座四角绿色状态灯
    for ang in [0, math.pi/2, math.pi, 3*math.pi/2]:
        lx = math.cos(ang) * 0.72
        ly = math.sin(ang) * 0.72
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(lx, ly, 0.04))
        lamp = bpy.context.active_object
        lamp.data.materials.append(mat_green)
        bpy.ops.object.shade_smooth()
        objs.append(lamp)

    return objs


def build_ammo_depot():
    """弹药仓库：厚重方形弹药箱堆叠 + 危险条纹 + 防爆板"""
    objs = []
    mat_crate  = create_clay_mat("m_am_crate", srgb_to_linear((0.56, 0.50, 0.22, 1.0)), roughness=0.72)
    mat_stripe = create_clay_mat("m_am_stripe", srgb_to_linear((0.92, 0.20, 0.12, 1.0)), roughness=0.50)
    mat_band   = create_clay_mat("m_am_band", srgb_to_linear((0.12, 0.12, 0.14, 1.0)), roughness=0.65)
    mat_lid    = create_clay_mat("m_am_lid", srgb_to_linear((0.45, 0.40, 0.18, 1.0)), roughness=0.60)
    mat_latch  = create_clay_mat("m_am_latch", srgb_to_linear((0.75, 0.72, 0.68, 1.0)), roughness=0.30)
    mat_warn   = create_clay_mat("m_am_warn", srgb_to_linear((0.98, 0.82, 0.10, 1.0)),
                                 emission=srgb_to_linear((1.0, 0.85, 0.10, 1.0)), emission_str=2.0)

    # 底层大弹药箱 (3 个并排)
    for i, bx in enumerate([-0.52, 0, 0.52]):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.08, -0.12))
        box = bpy.context.active_object
        box.scale = (0.46, 0.72, 0.44)
        box.data.materials.append(mat_crate)
        apply_uniform_clay_bevel(box, width=0.05, segments=2)
        objs.append(box)

        # 箱子顶盖 (稍大稍亮)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.08, 0.12))
        lid = bpy.context.active_object
        lid.scale = (0.47, 0.73, 0.06)
        lid.data.materials.append(mat_lid)
        apply_uniform_clay_bevel(lid, width=0.02, segments=2)
        objs.append(lid)

        # 金属扣环
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.46, 0.06))
        latch = bpy.context.active_object
        latch.scale = (0.12, 0.06, 0.06)
        latch.data.materials.append(mat_latch)
        apply_uniform_clay_bevel(latch, width=0.01, segments=2)
        objs.append(latch)

    # 顶层较小弹药箱 (2 个, 错位堆叠)
    for bx in [-0.26, 0.26]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.05, 0.35))
        box2 = bpy.context.active_object
        box2.scale = (0.44, 0.60, 0.36)
        box2.data.materials.append(mat_crate)
        apply_uniform_clay_bevel(box2, width=0.04, segments=2)
        objs.append(box2)

        # 危险条纹贴片
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.36, 0.35))
        stripe = bpy.context.active_object
        stripe.scale = (0.30, 0.02, 0.22)
        stripe.data.materials.append(mat_stripe)
        apply_uniform_clay_bevel(stripe, width=0.01, segments=2)
        objs.append(stripe)

    # 防爆铁带 (横绑)
    for bz in [-0.05, 0.18]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.08, bz))
        band = bpy.context.active_object
        band.scale = (1.62, 0.73, 0.06)
        band.data.materials.append(mat_band)
        apply_uniform_clay_bevel(band, width=0.01, segments=2)
        objs.append(band)

    # 顶部警告灯
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(0, 0, 0.59))
    wl = bpy.context.active_object
    wl.data.materials.append(mat_warn)
    bpy.ops.object.shade_smooth()
    objs.append(wl)

    return objs


def build_command_post():
    """指挥部：多角形主楼 + 旗杆 + 通信天线 + 加固裙边"""
    objs = []
    mat_wall   = create_clay_mat("m_cp_wall", srgb_to_linear((0.78, 0.74, 0.62, 1.0)), roughness=0.68)
    mat_roof   = create_clay_mat("m_cp_roof", srgb_to_linear((0.24, 0.34, 0.26, 1.0)), roughness=0.60)
    mat_flag   = create_clay_mat("m_cp_flag", srgb_to_linear((0.90, 0.18, 0.18, 1.0)),
                                 emission=srgb_to_linear((0.90, 0.18, 0.18, 1.0)), emission_str=1.5)
    mat_pole   = create_clay_mat("m_cp_pole", srgb_to_linear((0.82, 0.80, 0.76, 1.0)), roughness=0.30)
    mat_base   = create_clay_mat("m_cp_base", srgb_to_linear((0.42, 0.40, 0.35, 1.0)), roughness=0.75)
    mat_window = create_clay_mat("m_cp_win", srgb_to_linear((0.30, 0.62, 0.90, 1.0)),
                                 emission=srgb_to_linear((0.30, 0.62, 0.90, 1.0)), emission_str=1.8)
    mat_antenna= create_clay_mat("m_cp_ant", srgb_to_linear((0.62, 0.60, 0.56, 1.0)), roughness=0.40)

    # 1. 加固裙边地基 (八边形)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.20, vertices=8, location=(0, 0, -0.28))
    fnd = bpy.context.active_object
    fnd.data.materials.append(mat_base)
    apply_uniform_clay_bevel(fnd, width=0.04, segments=2)
    objs.append(fnd)

    # 2. 主体楼墙 (八边形)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.82, vertices=8, location=(0, 0, 0.10))
    wall = bpy.context.active_object
    wall.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(wall, width=0.06, segments=2)
    objs.append(wall)

    # 3. 屋顶 (八边形, 略向前偏移)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.80, depth=0.22, vertices=8, location=(0, 0, 0.53))
    roof = bpy.context.active_object
    roof.data.materials.append(mat_roof)
    apply_uniform_clay_bevel(roof, width=0.05, segments=2)
    objs.append(roof)

    # 4. 发光窗户 (正面4个)
    for wx, wz in [(-0.38, 0.05), (0.38, 0.05), (-0.38, 0.32), (0.38, 0.32)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(wx, 0.75, wz))
        win = bpy.context.active_object
        win.scale = (0.16, 0.04, 0.18)
        win.data.materials.append(mat_window)
        apply_uniform_clay_bevel(win, width=0.01, segments=2)
        objs.append(win)

    # 5. 旗杆
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=1.10, vertices=12, location=(-0.38, -0.02, 0.90))
    pole = bpy.context.active_object
    pole.data.materials.append(mat_pole)
    apply_uniform_clay_bevel(pole, width=0.01, segments=2)
    objs.append(pole)

    # 6. 旗帜 (矩形色块)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.10, -0.02, 1.22))
    flag = bpy.context.active_object
    flag.scale = (0.38, 0.02, 0.22)
    flag.data.materials.append(mat_flag)
    apply_uniform_clay_bevel(flag, width=0.01, segments=2)
    objs.append(flag)

    # 7. 通信天线 (右侧细杆 + 两段折叠臂)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.68, vertices=8, location=(0.44, 0, 0.96))
    ant = bpy.context.active_object
    ant.data.materials.append(mat_antenna)
    apply_uniform_clay_bevel(ant, width=0.01, segments=2)
    objs.append(ant)

    for az in [0.70, 0.90, 1.10]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.44, 0, az))
        cross_bar = bpy.context.active_object
        cross_bar.scale = (0.22, 0.02, 0.02)
        cross_bar.data.materials.append(mat_antenna)
        objs.append(cross_bar)

    return objs


def build_sniper_nest():
    """狙击碉堡：低矮掩体弧形 + 瞭望孔 + 沙袋加固"""
    objs = []
    mat_concrete = create_clay_mat("m_sn_con", srgb_to_linear((0.58, 0.55, 0.48, 1.0)), roughness=0.80)
    mat_sand     = create_clay_mat("m_sn_sand", srgb_to_linear((0.82, 0.74, 0.52, 1.0)), roughness=0.78)
    mat_dark     = create_clay_mat("m_sn_dark", srgb_to_linear((0.10, 0.10, 0.12, 1.0)), roughness=0.90)
    mat_metal    = create_clay_mat("m_sn_metal", srgb_to_linear((0.42, 0.44, 0.48, 1.0)), roughness=0.45)
    mat_glass    = create_clay_mat("m_sn_glass", srgb_to_linear((0.28, 0.55, 0.80, 1.0)),
                                   emission=srgb_to_linear((0.28, 0.55, 0.80, 1.0)), emission_str=1.5)

    # 1. 半圆形主掩体 (正面弧)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.68, vertices=24, location=(0, 0, -0.05))
    main = bpy.context.active_object
    main.scale = (1.0, 0.62, 1.0)
    main.data.materials.append(mat_concrete)
    apply_uniform_clay_bevel(main, width=0.07, segments=2)
    objs.append(main)

    # 2. 顶板 (低矮水平)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.08, 0.31))
    roof = bpy.context.active_object
    roof.scale = (0.96, 0.72, 0.12)
    roof.data.materials.append(mat_concrete)
    apply_uniform_clay_bevel(roof, width=0.05, segments=2)
    objs.append(roof)

    # 3. 瞭望孔 (暗色细槽)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.56, 0.18))
    slit = bpy.context.active_object
    slit.scale = (0.42, 0.08, 0.06)
    slit.data.materials.append(mat_dark)
    objs.append(slit)

    # 4. 瞭望孔内发光镜片
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.56, 0.18))
    lens = bpy.context.active_object
    lens.scale = (0.38, 0.04, 0.04)
    lens.data.materials.append(mat_glass)
    objs.append(lens)

    # 5. 沙袋堆 (前方3个圆柱)
    for sx in [-0.44, 0, 0.44]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.26, vertices=16, location=(sx, 0.64, -0.12))
        sandbag = bpy.context.active_object
        sandbag.rotation_euler = (math.radians(90), 0, 0)
        sandbag.scale = (1.0, 0.72, 1.0)
        sandbag.data.materials.append(mat_sand)
        apply_uniform_clay_bevel(sandbag, width=0.05, segments=2)
        objs.append(sandbag)

    # 6. 金属枪架 (向正前方伸出)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.55, vertices=12, location=(0, 0.84, 0.18))
    gun_mount = bpy.context.active_object
    gun_mount.rotation_euler = (math.radians(90), 0, 0)
    gun_mount.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(gun_mount, width=0.01, segments=2)
    objs.append(gun_mount)

    return objs


def build_emp_tower():
    """EMP电磁脉冲塔：三角形基座 + 旋转放电线圈 + 蓝色电弧发射器"""
    objs = []
    mat_frame  = create_clay_mat("m_em_frame", srgb_to_linear((0.22, 0.24, 0.32, 1.0)), roughness=0.55)
    mat_coil   = create_clay_mat("m_em_coil", srgb_to_linear((0.48, 0.50, 0.58, 1.0)), roughness=0.40)
    mat_arc    = create_clay_mat("m_em_arc", srgb_to_linear((0.18, 0.55, 1.00, 1.0)),
                                 emission=srgb_to_linear((0.18, 0.55, 1.00, 1.0)), emission_str=5.5)
    mat_base   = create_clay_mat("m_em_base", srgb_to_linear((0.18, 0.20, 0.26, 1.0)), roughness=0.70)
    mat_insul  = create_clay_mat("m_em_ins", srgb_to_linear((0.95, 0.88, 0.22, 1.0)), roughness=0.40)

    # 1. 三角形重型基座 (3边棱柱)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.84, depth=0.30, vertices=3, location=(0, 0, -0.18))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.06, segments=2)
    objs.append(base)

    # 2. 中央塔身 (六棱柱)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.96, vertices=6, location=(0, 0, 0.34))
    tower = bpy.context.active_object
    tower.data.materials.append(mat_frame)
    apply_uniform_clay_bevel(tower, width=0.05, segments=2)
    objs.append(tower)

    # 3. 放电线圈 (3层螺旋环 - 用扁圆环近似)
    for cz, cr in [(0.12, 0.62), (0.38, 0.58), (0.62, 0.52)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=cr, minor_radius=0.06,
                                         major_segments=24, minor_segments=8,
                                         location=(0, 0, cz))
        coil = bpy.context.active_object
        coil.data.materials.append(mat_coil)
        bpy.ops.object.shade_smooth()
        objs.append(coil)

    # 4. 顶部电弧发射极 (3个分叉球体)
    for ang in [0, 2*math.pi/3, 4*math.pi/3]:
        ax = math.cos(ang) * 0.36
        ay = math.sin(ang) * 0.36
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(ax, ay, 0.90))
        arc_tip = bpy.context.active_object
        arc_tip.data.materials.append(mat_arc)
        bpy.ops.object.shade_smooth()
        objs.append(arc_tip)

        # 细线连接至塔中心
        bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.36, vertices=8,
                                             location=(ax*0.5, ay*0.5, 0.90))
        link = bpy.context.active_object
        link.rotation_euler = (0, 0, ang + math.radians(90))
        link.data.materials.append(mat_coil)
        objs.append(link)

    # 5. 绝缘体 (黄色短球，位于线圈上方)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, 0, 0.72))
    insul = bpy.context.active_object
    insul.scale = (1.0, 1.0, 1.5)
    insul.data.materials.append(mat_insul)
    bpy.ops.object.shade_smooth()
    objs.append(insul)

    # 6. 基座三角顶点处的接地棒
    for ang in [math.pi/6, math.pi/6 + 2*math.pi/3, math.pi/6 + 4*math.pi/3]:
        gx = math.cos(ang) * 0.70
        gy = math.sin(ang) * 0.70
        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.50, vertices=8,
                                             location=(gx, gy, -0.28))
        rod = bpy.context.active_object
        rod.data.materials.append(mat_frame)
        apply_uniform_clay_bevel(rod, width=0.01, segments=2)
        objs.append(rod)

    return objs


# ══════════════════════════════════════════════════════════════════
#  TANKS
# ══════════════════════════════════════════════════════════════════

def build_sniper_tank(frame=0):
    """超长炮管狙击坦克：纤细车体 + 超长单管 + 消焰器 + 双联瞄准镜"""
    objs = []
    col_body   = srgb_to_linear((0.18, 0.28, 0.20, 1.0))
    col_turret = srgb_to_linear((0.14, 0.24, 0.16, 1.0))
    col_trim   = srgb_to_linear((0.32, 0.30, 0.26, 1.0))
    mat_body   = create_clay_mat("m_snt_b", col_body)
    mat_turret = create_clay_mat("m_snt_t", col_turret)
    mat_track  = create_clay_mat("m_snt_tr", srgb_to_linear((0.28, 0.26, 0.30, 1.0)), roughness=0.88)
    mat_trim   = create_clay_mat("m_snt_tm", col_trim)
    mat_scope  = create_clay_mat("m_snt_sc", srgb_to_linear((0.10, 0.10, 0.12, 1.0)), roughness=0.20)
    mat_lens   = create_clay_mat("m_snt_lens", srgb_to_linear((0.18, 0.72, 1.0, 1.0)),
                                  emission=srgb_to_linear((0.18, 0.72, 1.0, 1.0)), emission_str=2.5)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.010
    w, l = 1.20, 1.48
    tw = 0.30
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. 车体
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.48)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.14, segments=4)
    objs.append(hull)

    # 2. 前鼻楔
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.38, depth=0.42, vertices=16,
                                         location=(0, l*0.44, 0.02 + bob_z))
    nose = bpy.context.active_object
    nose.rotation_euler = (0, math.radians(90), 0)
    nose.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nose, width=0.08, segments=3)
    objs.append(nose)

    # 3. 履带 + 轮
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, l * 1.08, 0.54)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.14, segments=4)
        objs.append(tr)

        for wy in [-0.42, 0.0, 0.42]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=tw*1.06, vertices=16,
                                                 location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.07, segments=3)
            objs.append(wh)

        for i in range(6):
            t_y = -l*0.42 + (i / 5.0) * (l * 0.84) + (frame / 6.0) * (l*0.84/6.0)
            if t_y > l * 0.46: t_y -= l * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=tw*1.03, vertices=10,
                                                 location=(x_pos, t_y, 0.30))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.03, segments=2)
            objs.append(tread)

    # 4. 扁平炮塔
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, -0.10, 0.46 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.0, 0.92, 0.60)
    turret.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(turret)

    # 5. 超长炮管
    barrel_len = 1.28
    barrel_r   = 0.11
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r, depth=barrel_len, vertices=16,
                                         location=(0, 0.25 + barrel_len/2.0, 0.48))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(barrel, width=0.04, segments=3)
    objs.append(barrel)

    # 炮管中部加强环
    for ry in [0.40, 0.72, 1.04]:
        bpy.ops.mesh.primitive_torus_add(major_radius=barrel_r*1.5, minor_radius=0.04,
                                          location=(0, 0.25 + ry, 0.48))
        ring = bpy.context.active_object
        ring.rotation_euler = (math.radians(90), 0, 0)
        ring.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(ring)

    # 消焰器
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r*1.6, depth=0.24, vertices=16,
                                         location=(0, 0.25 + barrel_len, 0.48))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90), 0, 0)
    muzzle.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(muzzle, width=0.03, segments=2)
    objs.append(muzzle)

    # 6. 炮塔侧面双联瞄准镜
    for sx in [-0.32, 0.32]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.36, vertices=12,
                                             location=(sx, 0.36, 0.52))
        scope = bpy.context.active_object
        scope.rotation_euler = (math.radians(90), 0, 0)
        scope.data.materials.append(mat_scope)
        apply_uniform_clay_bevel(scope, width=0.02, segments=2)
        objs.append(scope)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(sx, 0.56, 0.52))
        sl = bpy.context.active_object
        sl.data.materials.append(mat_lens)
        bpy.ops.object.shade_smooth()
        objs.append(sl)

    return objs


def build_flame_tank(frame=0):
    """喷火坦克：宽粗喷火管 + 背部油罐 + 橙红涂装"""
    objs = []
    col_body   = srgb_to_linear((0.60, 0.22, 0.08, 1.0))
    col_turret = srgb_to_linear((0.50, 0.16, 0.05, 1.0))
    col_trim   = srgb_to_linear((0.82, 0.42, 0.08, 1.0))
    mat_body   = create_clay_mat("m_ft_b", col_body)
    mat_turret = create_clay_mat("m_ft_t", col_turret)
    mat_track  = create_clay_mat("m_ft_tr", srgb_to_linear((0.28, 0.24, 0.28, 1.0)), roughness=0.88)
    mat_trim   = create_clay_mat("m_ft_tm", col_trim)
    mat_tank   = create_clay_mat("m_ft_tank", srgb_to_linear((0.38, 0.36, 0.32, 1.0)), roughness=0.60)
    mat_flame  = create_clay_mat("m_ft_fire", srgb_to_linear((1.0, 0.55, 0.05, 1.0)),
                                  emission=srgb_to_linear((1.0, 0.55, 0.05, 1.0)), emission_str=6.0)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012
    w, l = 1.40, 1.50
    tw = 0.36
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. 粗壮车体
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.58)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.16, segments=4)
    objs.append(hull)

    # 2. 履带 + 轮
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, l * 1.1, 0.60)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.15, segments=4)
        objs.append(tr)

        for wy in [-0.44, 0.0, 0.44]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.23, depth=tw*1.06, vertices=16,
                                                 location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.07, segments=3)
            objs.append(wh)

        for i in range(6):
            t_y = -l*0.43 + (i / 5.0) * (l * 0.86) + (frame / 6.0) * (l*0.86/6.0)
            if t_y > l * 0.48: t_y -= l * 0.90
            bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=tw*1.04, vertices=10,
                                                 location=(x_pos, t_y, 0.32))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.03, segments=2)
            objs.append(tread)

    # 3. 炮塔 (宽且低)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.76, location=(0, -0.06, 0.54 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.1, 1.0, 0.65)
    turret.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(turret)

    # 4. 喷火管 (短粗宽口)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.72, vertices=16,
                                         location=(0, 0.32 + 0.36, 0.52))
    nozzle = bpy.context.active_object
    nozzle.rotation_euler = (math.radians(90), 0, 0)
    nozzle.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nozzle, width=0.05, segments=3)
    objs.append(nozzle)

    # 喷管前端扩口
    bpy.ops.mesh.primitive_cylinder_add(radius=0.30, depth=0.22, vertices=16,
                                         location=(0, 0.32 + 0.72, 0.52))
    flare = bpy.context.active_object
    flare.rotation_euler = (math.radians(90), 0, 0)
    flare.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(flare, width=0.04, segments=2)
    objs.append(flare)

    # 火焰发光
    for fr_y, fr_r in [(0.32 + 0.84, 0.28), (0.32 + 0.98, 0.18)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=fr_r, location=(0, fr_y, 0.52))
        glow = bpy.context.active_object
        glow.scale = (1.0, 1.4, 1.0)
        glow.data.materials.append(mat_flame)
        bpy.ops.object.shade_smooth()
        objs.append(glow)

    # 5. 背部燃料油罐
    for tank_x, tank_y in [(-0.32, -0.65), (0.32, -0.65)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.60, vertices=16,
                                             location=(tank_x, tank_y, 0.42 + bob_z))
        tank = bpy.context.active_object
        tank.data.materials.append(mat_tank)
        apply_uniform_clay_bevel(tank, width=0.06, segments=2)
        objs.append(tank)

    # 6. 输油管
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.90, vertices=8,
                                         location=(0, -0.20, 0.62 + bob_z))
    pipe = bpy.context.active_object
    pipe.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(pipe, width=0.01, segments=2)
    objs.append(pipe)

    return objs


def build_stealth_tank(frame=0):
    """隐形坦克：极低矮扁平 + 菱形棱角切面 + 哑光黑涂装"""
    objs = []
    mat_body   = create_clay_mat("m_st_b", srgb_to_linear((0.08, 0.08, 0.10, 1.0)), roughness=0.92)
    mat_turret = create_clay_mat("m_st_t", srgb_to_linear((0.10, 0.10, 0.13, 1.0)), roughness=0.90)
    mat_track  = create_clay_mat("m_st_tr", srgb_to_linear((0.20, 0.20, 0.22, 1.0)), roughness=0.95)
    mat_trim   = create_clay_mat("m_st_tm", srgb_to_linear((0.22, 0.22, 0.26, 1.0)), roughness=0.85)
    mat_sensor = create_clay_mat("m_st_sens", srgb_to_linear((0.15, 0.80, 0.55, 1.0)),
                                  emission=srgb_to_linear((0.15, 0.80, 0.55, 1.0)), emission_str=3.5)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.008
    w, l = 1.35, 1.50
    tw = 0.30
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. 极扁平车体
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.38)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.10, segments=4)
    objs.append(hull)

    # 2. 前菱形楔形切面
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, l*0.38, 0.04 + bob_z))
    wedge = bpy.context.active_object
    wedge.scale = (w*0.88, 0.38, 0.28)
    wedge.rotation_euler = (math.radians(20), 0, 0)
    wedge.data.materials.append(mat_body)
    apply_uniform_clay_bevel(wedge, width=0.08, segments=3)
    objs.append(wedge)

    # 3. 两侧斜面裙甲
    for sx, ang_z in [(-1, -math.radians(8)), (1, math.radians(8))]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx * (w*0.58), 0, 0.02))
        skirt = bpy.context.active_object
        skirt.scale = (0.20, l*0.90, 0.34)
        skirt.rotation_euler = (0, 0, ang_z)
        skirt.data.materials.append(mat_body)
        apply_uniform_clay_bevel(skirt, width=0.06, segments=2)
        objs.append(skirt)

    # 4. 低履带
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.0))
        tr = bpy.context.active_object
        tr.scale = (tw, l * 1.08, 0.44)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.12, segments=3)
        objs.append(tr)

        for wy in [-0.42, 0.0, 0.42]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=tw*1.04, vertices=16,
                                                 location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.06, segments=3)
            objs.append(wh)

        for i in range(6):
            t_y = -l*0.42 + (i / 5.0) * (l * 0.84) + (frame / 6.0) * (l*0.84/6.0)
            if t_y > l * 0.46: t_y -= l * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=tw*1.03, vertices=10,
                                                 location=(x_pos, t_y, 0.26))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.03, segments=2)
            objs.append(tread)

    # 5. 极低炮塔 (扁菱形)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.06, 0.32 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (0.62, 0.72, 0.22)
    turret.rotation_euler = (0, 0, math.radians(45))
    turret.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret, width=0.08, segments=3)
    objs.append(turret)

    # 6. 低矮炮管
    barrel_len = 1.05
    barrel_r   = 0.10
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r, depth=barrel_len, vertices=16,
                                         location=(0, 0.32 + barrel_len/2.0, 0.34))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(barrel, width=0.03, segments=3)
    objs.append(barrel)

    # 炮口消声器
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r*1.4, depth=0.18, vertices=16,
                                         location=(0, 0.32 + barrel_len, 0.34))
    silencer = bpy.context.active_object
    silencer.rotation_euler = (math.radians(90), 0, 0)
    silencer.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(silencer, width=0.02, segments=2)
    objs.append(silencer)

    # 7. 顶部传感器点阵 (绿色)
    for sx in [-0.20, 0, 0.20]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx, -0.06, 0.46))
        sens = bpy.context.active_object
        sens.data.materials.append(mat_sensor)
        bpy.ops.object.shade_smooth()
        objs.append(sens)

    return objs


def build_artillery_tank(frame=0):
    """自行火炮：宽大底盘 + 大仰角炮管 + 后置推进装置 + 防盾"""
    objs = []
    mat_body   = create_clay_mat("m_art_b", srgb_to_linear((0.48, 0.44, 0.28, 1.0)))
    mat_turret = create_clay_mat("m_art_t", srgb_to_linear((0.40, 0.38, 0.22, 1.0)))
    mat_track  = create_clay_mat("m_art_tr", srgb_to_linear((0.30, 0.28, 0.30, 1.0)), roughness=0.88)
    mat_trim   = create_clay_mat("m_art_tm", srgb_to_linear((0.58, 0.52, 0.30, 1.0)))
    mat_exhaust= create_clay_mat("m_art_ex", srgb_to_linear((0.18, 0.16, 0.16, 1.0)), roughness=0.80)
    mat_scope  = create_clay_mat("m_art_sc", srgb_to_linear((0.10, 0.10, 0.12, 1.0)), roughness=0.25)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.010
    w, l = 1.50, 1.62
    tw = 0.40
    tx = w * 0.5 + tw * 0.5 - 0.04

    # 1. 宽大车体
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.06, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.56)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # 2. 前装甲板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, l*0.46, 0.06 + bob_z))
    front = bpy.context.active_object
    front.scale = (w*0.92, 0.16, 0.48)
    front.rotation_euler = (math.radians(15), 0, 0)
    front.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(front, width=0.05, segments=2)
    objs.append(front)

    # 3. 宽履带 + 轮
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, l * 1.12, 0.62)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.16, segments=4)
        objs.append(tr)

        for wy in [-0.50, 0.0, 0.50]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=tw*1.06, vertices=16,
                                                 location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.08, segments=3)
            objs.append(wh)

        for i in range(6):
            t_y = -l*0.44 + (i / 5.0) * (l * 0.88) + (frame / 6.0) * (l*0.88/6.0)
            if t_y > l * 0.48: t_y -= l * 0.92
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=tw*1.06, vertices=10,
                                                 location=(x_pos, t_y, 0.34))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.03, segments=2)
            objs.append(tread)

    # 4. 敞开式炮塔基座
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.12, 0.56 + bob_z))
    turret_base = bpy.context.active_object
    turret_base.scale = (0.90, 1.05, 0.28)
    turret_base.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret_base, width=0.08, segments=3)
    objs.append(turret_base)

    # 5. 大仰角炮管 (35°仰角)
    barrel_len = 1.30
    barrel_r   = 0.16
    elev = math.radians(35)
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r, depth=barrel_len, vertices=16,
                                         location=(0,
                                                   0.12 + math.cos(elev) * barrel_len * 0.5,
                                                   0.56 + math.sin(elev) * barrel_len * 0.5 + bob_z))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90) - elev, 0, 0)
    barrel.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(barrel, width=0.05, segments=3)
    objs.append(barrel)

    # 炮口制退器
    muzzle_y = 0.12 + math.cos(elev) * barrel_len
    muzzle_z = 0.56 + math.sin(elev) * barrel_len + bob_z
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_r*1.5, depth=0.28, vertices=16,
                                         location=(0, muzzle_y, muzzle_z))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90) - elev, 0, 0)
    muzzle.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(muzzle, width=0.04, segments=2)
    objs.append(muzzle)

    # 6. 防盾
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.42, 0.60 + bob_z))
    shield = bpy.context.active_object
    shield.scale = (0.76, 0.08, 0.44)
    shield.rotation_euler = (math.radians(10), 0, 0)
    shield.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(shield, width=0.05, segments=2)
    objs.append(shield)

    # 7. 后置排气管 (双管)
    for ex in [-0.32, 0.32]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.55, vertices=12,
                                             location=(ex, -0.78, 0.54 + bob_z))
        exhaust = bpy.context.active_object
        exhaust.data.materials.append(mat_exhaust)
        apply_uniform_clay_bevel(exhaust, width=0.02, segments=2)
        objs.append(exhaust)

    # 8. 瞄准镜
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.40, vertices=12,
                                         location=(-0.46, -0.08, 0.76))
    scope = bpy.context.active_object
    scope.data.materials.append(mat_scope)
    apply_uniform_clay_bevel(scope, width=0.02, segments=2)
    objs.append(scope)

    return objs


# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════

def main():
    print("=" * 60)
    print("  New Buildings & Tanks Render Pipeline")
    print("  雷达站 / 弹药仓库 / 指挥部 / 狙击碉堡 / EMP塔")
    print("  狙击坦克 / 喷火坦克 / 隐形坦克 / 自行火炮")
    print("=" * 60)

    # ──── BUILDINGS ────
    building_jobs = [
        ("radar_station",  build_radar_station,  "雷达站"),
        ("ammo_depot",     build_ammo_depot,     "弹药仓库"),
        ("command_post",   build_command_post,   "指挥部"),
        ("sniper_nest",    build_sniper_nest,    "狙击碉堡"),
        ("emp_tower",      build_emp_tower,      "EMP塔"),
    ]

    for i, (name, builder, label) in enumerate(building_jobs, 1):
        print(f"\n[{i}/{len(building_jobs)}] 渲染 {label} ({name}.png) ...")
        clear_scene()
        setup_render_settings(256, 256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, f"{name}.png"))
        print(f"  [OK] {name}.png")

    # ──── TANKS (6帧动画) ────
    tank_configs = [
        ("tank_sniper",    build_sniper_tank,    "狙击坦克"),
        ("tank_flame",     build_flame_tank,     "喷火坦克"),
        ("tank_stealth",   build_stealth_tank,   "隐形坦克"),
        ("tank_artillery", build_artillery_tank, "自行火炮"),
    ]

    for prefix, builder_fn, label in tank_configs:
        print(f"\n[TANK] 渲染 {label} ({prefix}_f0~f5)...")
        for f in range(6):
            clear_scene()
            setup_render_settings(256, 256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
            objs = builder_fn(frame=f)
            out = os.path.join(SPRITES_TANKS, f"{prefix}_f{f}.png")
            render_and_clean(objs, out)
            print(f"  [OK] {prefix}_f{f}.png")

    print("\n" + "=" * 60)
    print("  All renders complete!")
    print(f"  Buildings -> {SPRITES_BUILDINGS}")
    print(f"  Tanks     -> {SPRITES_TANKS}")
    print("=" * 60)


if __name__ == '__main__':
    main()
