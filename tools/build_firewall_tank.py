"""build_firewall_tank.py — 火墙坦克 (Firewall Tank) 3D 建模、动效与 Cycles 黏土渲染管线

火墙坦克 (Firewall Tank / Pyro Trail Tank):
  - 车体：黑曜石暗铁重甲 + 熔岩赤橙色高温警示涂装 (Lava Orange / Obsidian Armor)
  - 车尾：双联重油凝固汽油点火喷槽 (Twin Napalm Ground Dropper / Igniters)，向后下方喷吐火种
  - 炮塔：重型熔岩投射炮塔 + 顶部高压储油罐与发光熔岩核心 (Glowing Lava Core)
  - 动效：6 帧履带传动、车尾点火器橙红呼吸、顶部熔岩核心脉冲高亮

输出资源:
  - assets/sprites/tanks/tank_firewall_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_firewall_f0.png ~ f5.png
  - assets/sprites/tanks/tank_firewall.png
  - assets/sprites/buildings/firewall_flame_f0.png ~ f3.png (火墙地面烈焰 4 帧)
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
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)


def build_firewall_tank(frame: int = 0, is_enemy: bool = True):
    """构建火墙坦克 3D 模型与第 frame 帧动效"""
    objs = []

    # 1. 材质定义
    if is_enemy:
        col_hull    = srgb_to_linear((0.26, 0.12, 0.10, 1.0)) # 敌方黑曜焦黑底盘
        col_armor   = srgb_to_linear((0.85, 0.28, 0.08, 1.0)) # 熔岩高热烈火橙红
        col_accent  = srgb_to_linear((1.00, 0.65, 0.10, 1.0)) # 亮金黄高热防热护板
        col_core    = srgb_to_linear((1.00, 0.40, 0.05, 1.0)) # 熔岩核心发光
    else:
        col_hull    = srgb_to_linear((0.18, 0.20, 0.24, 1.0)) # 友方深钢青黑
        col_armor   = srgb_to_linear((0.15, 0.65, 0.85, 1.0)) # 友方苍蓝等离子焰
        col_accent  = srgb_to_linear((0.40, 0.85, 1.00, 1.0)) # 苍蓝防热板
        col_core    = srgb_to_linear((0.20, 0.80, 1.00, 1.0)) # 苍蓝能量核心

    col_track   = srgb_to_linear((0.18, 0.18, 0.20, 1.0)) # 重履带深铁
    col_steel   = srgb_to_linear((0.45, 0.48, 0.52, 1.0)) # 管道与排气金属
    col_igniter = srgb_to_linear((0.95, 0.35, 0.05, 1.0)) # 点火嘴高热发光

    mat_hull   = create_clay_mat("m_fw_hl", col_hull, roughness=0.60)
    mat_armor  = create_clay_mat("m_fw_ar", col_armor, roughness=0.45)
    mat_accent = create_clay_mat("m_fw_ac", col_accent, roughness=0.40)
    mat_track  = create_clay_mat("m_fw_tk", col_track, roughness=0.75)
    mat_steel  = create_clay_mat("m_fw_st", col_steel, roughness=0.35)

    # 动态脉冲发光强度
    glow_pulse = 5.0 + 3.0 * math.sin(frame * (2.0 * math.pi / 6.0))
    mat_core = create_clay_mat("m_fw_core", col_core, emission=col_core, emission_str=glow_pulse)
    mat_igniter = create_clay_mat("m_fw_ig", col_igniter, emission=col_igniter, emission_str=glow_pulse * 1.2)

    # 车身轻微颠簸
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015
    pitch = math.sin(frame * (2.0 * math.pi / 6.0)) * math.radians(1.5)

    # ==================== 1. 底盘履带 (Heavy Tracks) ====================
    for side in [-0.62, 0.62]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, 0, 0.18))
        track = bpy.context.active_object
        track.scale = (0.34, 1.55, 0.32)
        track.data.materials.append(mat_track)
        apply_uniform_clay_bevel(track, width=0.06, segments=3)
        objs.append(track)

        # 侧面高温防热护板 (Heat Skirts)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 1.08, 0, 0.22))
        skirt = bpy.context.active_object
        skirt.scale = (0.06, 1.42, 0.22)
        skirt.data.materials.append(mat_armor)
        apply_uniform_clay_bevel(skirt, width=0.02, segments=2)
        objs.append(skirt)

    # ==================== 2. 主车体装甲 (Chassis Hull) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.34 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (0.95, 1.35, 0.32)
    hull.rotation_euler = (pitch, 0, 0)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.08, segments=3)
    objs.append(hull)

    # 车头倾斜防撞排热铲 (Front Heat Plow)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.72, 0.28 + bob_z))
    plow = bpy.context.active_object
    plow.scale = (1.05, 0.22, 0.28)
    plow.rotation_euler = (math.radians(-25) + pitch, 0, 0)
    plow.data.materials.append(mat_accent)
    apply_uniform_clay_bevel(plow, width=0.04, segments=2)
    objs.append(plow)

    # ==================== 3. 车尾双联重油火墙喷槽 (Twin Napalm Ground Igniters) ====================
    for ix in [-0.34, 0.34]:
        # 喷管外壳
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.42, vertices=12,
                                             location=(ix, -0.74, 0.22 + bob_z))
        igniter_pipe = bpy.context.active_object
        igniter_pipe.rotation_euler = (math.radians(35) + pitch, 0, 0) # 向后下方倾斜喷火
        igniter_pipe.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(igniter_pipe, width=0.02, segments=2)
        objs.append(igniter_pipe)

        # 喷口高热炽热核心
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(ix, -0.88, 0.12 + bob_z))
        nozzle = bpy.context.active_object
        nozzle.data.materials.append(mat_igniter)
        bpy.ops.object.shade_smooth()
        objs.append(nozzle)

    # 车尾燃油增压储罐 (Fuel Tanker Reservoir)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=0.75, vertices=16,
                                         location=(0, -0.42, 0.52 + bob_z))
    fuel_tank = bpy.context.active_object
    fuel_tank.rotation_euler = (0, math.radians(90), 0)
    fuel_tank.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(fuel_tank, width=0.04, segments=2)
    objs.append(fuel_tank)

    # ==================== 4. 炮塔与高温熔岩核心 (Turret & Lava Core) ====================
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.12, 0.56 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (0.76, 0.76, 0.28)
    turret.rotation_euler = (pitch, 0, 0)
    turret.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(turret, width=0.06, segments=3)
    objs.append(turret)

    # 炮塔顶部发光熔岩球核心 (Pulsing Lava Core Sphere)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0, 0.12, 0.74 + bob_z))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 前主炮：重型高压喷火巨炮 (Heavy Flamethrower Projector Barrel)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.75, vertices=14,
                                         location=(0, 0.75, 0.56 + bob_z))
    cannon = bpy.context.active_object
    cannon.rotation_euler = (math.radians(90) + pitch, 0, 0)
    cannon.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(cannon, width=0.02, segments=2)
    objs.append(cannon)

    # 炮口扩口消焰增压套筒
    bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=0.20, vertices=14,
                                         location=(0, 1.10, 0.56 + bob_z))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90) + pitch, 0, 0)
    muzzle.data.materials.append(mat_accent)
    apply_uniform_clay_bevel(muzzle, width=0.02, segments=2)
    objs.append(muzzle)

    return objs


def build_firewall_flame_tile(frame: int = 0):
    """构建单格火墙烈焰 (Firewall Flame Tile) 3D 模型与动画"""
    objs = []

    col_flame_outer = srgb_to_linear((0.95, 0.25, 0.05, 1.0)) # 浓烈外焰赤红
    col_flame_core  = srgb_to_linear((1.00, 0.85, 0.15, 1.0)) # 白热内焰金黄
    col_ember       = srgb_to_linear((0.30, 0.12, 0.08, 1.0)) # 焦黑灰烬底座

    phase = frame * (2.0 * math.pi / 4.0)
    glow_str = 6.0 + 3.0 * math.sin(phase)

    mat_ember = create_clay_mat("m_fw_emb", col_ember, roughness=0.90)
    mat_outer = create_clay_mat("m_fw_fl_out", col_flame_outer, emission=col_flame_outer, emission_str=glow_str)
    mat_inner = create_clay_mat("m_fw_fl_in", col_flame_core, emission=col_flame_core, emission_str=glow_str * 1.5)

    # 1. 焦黑熔岩余烬底座
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.scale = (1.45, 1.45, 0.10)
    base.data.materials.append(mat_ember)
    apply_uniform_clay_bevel(base, width=0.03, segments=2)
    objs.append(base)

    # 2. 燃烧火焰簇 (多瓣随机跳动火焰柱)
    flame_offsets = [
        ( 0.00,  0.00, 0.70, 0.28), # 中央主焰
        (-0.35,  0.25, 0.55, 0.22),
        ( 0.35,  0.25, 0.52, 0.20),
        (-0.25, -0.30, 0.48, 0.18),
        ( 0.30, -0.28, 0.56, 0.22),
    ]

    for idx, (fx, fy, fh, fr) in enumerate(flame_offsets):
        anim_h = fh * (0.85 + 0.30 * math.sin(phase + idx * 1.3))
        # 外焰圆锥
        bpy.ops.mesh.primitive_cone_add(radius1=fr, depth=anim_h, vertices=10,
                                         location=(fx, fy, anim_h * 0.5))
        flame_cone = bpy.context.active_object
        flame_cone.data.materials.append(mat_outer)
        apply_uniform_clay_bevel(flame_cone, width=0.02, segments=2)
        objs.append(flame_cone)

        # 内焰高温白热球
        bpy.ops.mesh.primitive_uv_sphere_add(radius=fr * 0.55, location=(fx, fy, anim_h * 0.35))
        core_sp = bpy.context.active_object
        core_sp.data.materials.append(mat_inner)
        bpy.ops.object.shade_smooth()
        objs.append(core_sp)

    return objs


def render_all_firewall_assets():
    """渲染火墙坦克 6 帧动画、图标与火墙燃烧帧"""
    print(">>> 正在初始化 Blender Cycles 火墙坦克渲染场景...")

    # clear_scene() 是 bpy.ops.wm.read_factory_settings(use_empty=True) —— 整份出厂
    # 设置重置，不只清 mesh，连 scene.render 分辨率也会被冲回 Blender 默认的
    # 1920x1080。所以 setup_render_settings() 必须在每次 clear_scene() *之后*
    # 重新调用一次，不能只在批次开头调一次（这正是本文件曾经的 bug）。

    # 1. 玩家/中立版火墙坦克 6 帧 (tank_firewall_f0 ~ f5)
    print("\n--- 渲染火墙坦克 6 帧动画 (tank_firewall_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_firewall_tank(frame=f, is_enemy=False)
        out_path = os.path.join(SPRITES_TANKS, f"tank_firewall_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染玩家帧 {f}/5 -> {out_path}")

    # 2. 敌方火墙坦克 6 帧 (enemy_firewall_f0 ~ f5)
    print("\n--- 渲染敌方火墙坦克 6 帧动画 (enemy_firewall_f0~f5.png) ---")
    for f in range(6):
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_firewall_tank(frame=f, is_enemy=True)
        out_path = os.path.join(SPRITES_TANKS, f"enemy_firewall_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] 渲染敌方帧 {f}/5 -> {out_path}")

    # 3. 静态图鉴图标 (tank_firewall.png)
    clear_scene()
    setup_render_settings(rx=256, ry=256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_firewall_tank(frame=0, is_enemy=True)
    icon_path = os.path.join(SPRITES_TANKS, "tank_firewall.png")
    render_and_clean(objs, icon_path)
    print(f"  [OK] 渲染火墙坦克静态图标 -> {icon_path}")

    # 4. 地面烈焰火墙 4 帧动画 (firewall_flame_f0 ~ f3)
    print("\n--- 渲染地面烈焰火墙 4 帧动效 (firewall_flame_f0~f3.png) ---")
    for f in range(4):
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_firewall_flame_tile(frame=f)
        f_path = os.path.join(SPRITES_BUILDINGS, f"firewall_flame_f{f}.png")
        render_and_clean(objs, f_path)
        print(f"  [OK] 渲染火墙地表帧 {f}/3 -> {f_path}")

    print("\n>>> 所有火墙坦克与火墙地表模型渲染已全部成功完成！ <<<")


if __name__ == "__main__":
    render_all_firewall_assets()
