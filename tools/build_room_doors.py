"""build_room_doors.py — 房间门 (Room Doors) 3D 建模与 Cycles 黏土渲染管线

为以撒式房间系统渲染各类型房间的进出门美术资产 (256x256 正交 Cycles 黏土渲染)：
  1. 普通战斗房门 (Normal Combat Door):
     - door_normal_locked: 重型防爆加固钢闸门，红光锁定指示灯，黄色警示防爆条纹，阻挡进出
     - door_normal_open: 敞开式通行大门拱门，双侧导轨滑槽，地面发光绿色导航箭头通道 (>>>)
  2. Boss 房大门 (Boss Gateway):
     - door_boss_locked: 恶魔骷髅黑曜石重闸，熔岩血红发光核心，尖角铁栅
     - door_boss_open: 狰狞巨角暗黑传送门，地面血红符文与深渊通道光晕
  3. 商店大门 (Shop Gateway):
     - door_shop_locked: 百叶木格栅门，黄铜大挂锁与金币浮雕
     - door_shop_open: 经典红白条纹黏土遮阳雨篷，黄金迎宾地毯与金币发光徽标
  4. 宝物/精英大门 (Treasure Gateway):
     - door_treasure_locked: 皇家青金石与镀金穹顶大门，中央发光天蓝钻石大锁
     - door_treasure_open: 璀璨金色拱门，水晶立柱与晶蓝闪烁地面通道
  5. 挑战大门 (Challenge Gateway):
     - door_challenge_locked: 暗紫尖刺重装闸门，交叉战刃与紫晶警告能量锁
     - door_challenge_open: 紫色战备竞技场拱门，紫色突击导航光条
  6. 隐藏密室门 (Secret Room Door):
     - door_secret_cracked: 砖墙暗门，隐蔽的泥石裂纹与缝隙微光
     - door_secret_open: 炸毁崩塌的破损碎石通道，通向未知幽暗密室
  7. 事件/休息大门 (Event/Rest Gateway):
     - door_event_locked: 密林翡翠藤木大门，绿玉能量锁
     - door_event_open: 翠绿营地拱门，温暖营火绿光地毯
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
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
    TILE_PLATE_BLEED,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)


# ================================================================
# 1. NORMAL COMBAT DOOR (普通门: 锁闭重闸 / 敞开绿标通道)
# ================================================================

def build_door_normal_locked():
    objs = []
    # 材质定义
    mat_plate = create_clay_mat("m_dnl_plate", (0.52, 0.55, 0.62, 1.0), roughness=0.60)
    mat_jamb  = create_clay_mat("m_dnl_jamb", (0.36, 0.38, 0.45, 1.0), roughness=0.50)
    mat_door  = create_clay_mat("m_dnl_door", (0.64, 0.67, 0.74, 1.0), roughness=0.55)
    mat_warn  = create_clay_mat("m_dnl_warn", (0.92, 0.72, 0.16, 1.0), roughness=0.65)
    mat_dark  = create_clay_mat("m_dnl_dark", (0.20, 0.20, 0.24, 1.0), roughness=0.70)
    mat_rivet = create_clay_mat("m_dnl_rivet", (0.85, 0.88, 0.94, 1.0), roughness=0.35)
    mat_lock  = create_clay_mat("m_dnl_lock", (0.28, 0.30, 0.35, 1.0), roughness=0.45)
    mat_red   = create_clay_mat("m_dnl_red", (1.0, 0.15, 0.15, 1.0), emission=(1.0, 0.15, 0.15, 1.0), emission_str=3.5)

    # 1. 底板 (Steel Base Plate)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 两侧坚固门框立柱 (Door Frame Jambs)
    for x_jamb in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_jamb, 0, 0.08))
        jamb = bpy.context.active_object
        jamb.scale = (0.55, 3.20, 0.40)
        jamb.data.materials.append(mat_jamb)
        apply_uniform_clay_bevel(jamb, width=0.08, segments=3)
        objs.append(jamb)

        # 立柱铆钉
        for y_r in [-1.1, -0.4, 0.4, 1.1]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.12, vertices=12, location=(x_jamb, y_r, 0.30))
            riv = bpy.context.active_object
            riv.data.materials.append(mat_rivet)
            apply_uniform_clay_bevel(riv, width=0.02, segments=2)
            objs.append(riv)

    # 3. 门梁横档 (Top & Bottom Lintels)
    for y_lin in [-1.30, 1.30]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_lin, 0.08))
        lin = bpy.context.active_object
        lin.scale = (2.20, 0.45, 0.35)
        lin.data.materials.append(mat_jamb)
        apply_uniform_clay_bevel(lin, width=0.06, segments=2)
        objs.append(lin)

    # 4. 中央双开重型防爆装甲门扇 (Interlocking Blast Door Panels)
    for x_door in [-0.48, 0.48]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_door, 0, 0.04))
        pnl = bpy.context.active_object
        pnl.scale = (0.88, 2.15, 0.28)
        pnl.data.materials.append(mat_door)
        apply_uniform_clay_bevel(pnl, width=0.06, segments=2)
        objs.append(pnl)

    # 5. 防爆警示条纹板 (Hazard Warning Plates)
    for y_warn in [-0.60, 0.60]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_warn, 0.18))
        wp = bpy.context.active_object
        wp.scale = (1.80, 0.32, 0.10)
        wp.data.materials.append(mat_warn)
        apply_uniform_clay_bevel(wp, width=0.04, segments=2)
        objs.append(wp)

        # 黑色警示嵌条
        for x_stripe in [-0.6, -0.2, 0.2, 0.6]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_stripe, y_warn, 0.24))
            st = bpy.context.active_object
            st.scale = (0.14, 0.30, 0.05)
            st.rotation_euler = (0, 0, math.radians(25))
            st.data.materials.append(mat_dark)
            objs.append(st)

    # 6. 中央六边形重型机械锁闭齿轮 (Hexagonal Heavy Lock)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.22, vertices=6, location=(0, 0, 0.22))
    lock_body = bpy.context.active_object
    lock_body.data.materials.append(mat_lock)
    apply_uniform_clay_bevel(lock_body, width=0.04, segments=2)
    objs.append(lock_body)

    # 7. 红色锁定警示发光核心 (Glowing Red Lock Indicator)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0, 0, 0.32))
    core = bpy.context.active_object
    core.scale = (1.0, 1.0, 0.6)
    core.data.materials.append(mat_red)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 8. 锁定插销横梁 (Cross Locking Bars)
    for sx in [-0.65, 0.65]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0, 0.20))
        bar = bpy.context.active_object
        bar.scale = (0.50, 0.16, 0.16)
        bar.data.materials.append(mat_rivet)
        apply_uniform_clay_bevel(bar, width=0.03, segments=2)
        objs.append(bar)

    return objs


def build_door_normal_open():
    objs = []
    # 材质定义
    mat_base  = create_clay_mat("m_dno_base", (0.35, 0.38, 0.44, 1.0), roughness=0.75)
    mat_floor = create_clay_mat("m_dno_floor", (0.24, 0.26, 0.30, 1.0), roughness=0.80)
    mat_jamb  = create_clay_mat("m_dno_jamb", (0.48, 0.52, 0.60, 1.0), roughness=0.55)
    mat_trim  = create_clay_mat("m_dno_trim", (0.68, 0.72, 0.80, 1.0), roughness=0.45)
    mat_track = create_clay_mat("m_dno_track", (0.16, 0.17, 0.20, 1.0), roughness=0.60)
    mat_green = create_clay_mat("m_dno_green", (0.20, 1.0, 0.45, 1.0), emission=(0.20, 1.0, 0.45, 1.0), emission_str=3.5)
    mat_lit   = create_clay_mat("m_dno_lit", (0.40, 0.95, 0.60, 1.0), emission=(0.40, 0.95, 0.60, 1.0), emission_str=2.0)

    # 1. 基础边墙底板 (Base Floor Plate)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_base)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 凹陷的通行走道底面 (Recessed Runway Floor)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    r_floor = bpy.context.active_object
    r_floor.scale = (1.75, 3.20, 0.12)
    r_floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(r_floor, width=0.04, segments=2)
    objs.append(r_floor)

    # 3. 两侧滑动门收纳槽与立柱 (Gate Pillars with Recessed Door Slots)
    for x_jamb in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_jamb, 0, 0.10))
        jamb = bpy.context.active_object
        jamb.scale = (0.65, 3.20, 0.44)
        jamb.data.materials.append(mat_jamb)
        apply_uniform_clay_bevel(jamb, width=0.08, segments=3)
        objs.append(jamb)

        # 门扇收纳凹槽 (Door Pocket Slot)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_jamb * 0.78, 0, 0.12))
        slot = bpy.context.active_object
        slot.scale = (0.22, 2.20, 0.35)
        slot.data.materials.append(mat_track)
        objs.append(slot)

        # 门柱指示绿灯
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.14, vertices=16, location=(x_jamb, 0, 0.36))
        lamp = bpy.context.active_object
        lamp.data.materials.append(mat_green)
        objs.append(lamp)

    # 4. 上下门楣装饰框 (Lintel Trim)
    for y_lin in [-1.32, 1.32]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_lin, 0.12))
        lin = bpy.context.active_object
        lin.scale = (2.10, 0.42, 0.40)
        lin.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(lin, width=0.06, segments=2)
        objs.append(lin)

    # 5. 地面发光导航箭头 >>> (Glowing Neon-Green Navigation Chevrons)
    # 两组指向通行方向 (前/后通道指引)
    for y_pos in [-0.55, 0.55]:
        # 箭头主体由两个倾斜长方体组成一个 V 形/尖头
        for (side, angle) in [(-0.24, 35), (0.24, -35)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.42, 0.14, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_green)
            objs.append(chev)

    # 6. 通道两侧发光引导导轨条 (Illuminated Guide Rails)
    for x_rail in [-0.78, 0.78]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_rail, 0, 0.02))
        rail = bpy.context.active_object
        rail.scale = (0.08, 2.30, 0.06)
        rail.data.materials.append(mat_lit)
        objs.append(rail)

    return objs


# ================================================================
# 2. BOSS GATEWAY (Boss 房门: 恶魔骷髅锁闭重闸 / 熔岩符文深渊大门)
# ================================================================

def build_door_boss_locked():
    objs = []
    # 材质
    mat_obsidian = create_clay_mat("m_dbl_obs", (0.18, 0.16, 0.22, 1.0), roughness=0.60)
    mat_iron     = create_clay_mat("m_dbl_iron", (0.28, 0.22, 0.26, 1.0), roughness=0.55)
    mat_gold     = create_clay_mat("m_dbl_gold", (0.88, 0.68, 0.18, 1.0), roughness=0.35)
    mat_skull    = create_clay_mat("m_dbl_skull", (0.82, 0.78, 0.72, 1.0), roughness=0.65)
    mat_magma    = create_clay_mat("m_dbl_magma", (1.0, 0.18, 0.05, 1.0), emission=(1.0, 0.18, 0.05, 1.0), emission_str=4.0)

    # 1. 暗黑基座底板 (Obsidian Base)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_obsidian)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 哥特恶魔巨柱门框 (Gothic Demonic Pillars with Spikes)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.12))
        col = bpy.context.active_object
        col.scale = (0.60, 3.20, 0.48)
        col.data.materials.append(mat_obsidian)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 黄金镶边包角 (Gold Ornate Trims)
        for y_trim in [-1.2, 0, 1.2]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, y_trim, 0.25))
            gt = bpy.context.active_object
            gt.scale = (0.66, 0.35, 0.30)
            gt.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(gt, width=0.04, segments=2)
            objs.append(gt)

        # 门柱顶部暗黑尖角 (Horns / Spikes)
        for (y_sp, dir_sp) in [(-1.3, -1), (1.3, 1)]:
            bpy.ops.mesh.primitive_cone_add(radius1=0.16, radius2=0.02, depth=0.65, vertices=8, location=(x_p, y_sp, 0.50))
            spk = bpy.context.active_object
            spk.rotation_euler = (math.radians(dir_sp * 25), 0, 0)
            spk.data.materials.append(mat_gold)
            objs.append(spk)

    # 3. 铁铸重型栅栏 (Heavy Iron Portcullis Bars)
    for x_bar in [-0.60, -0.20, 0.20, 0.60]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=2.40, vertices=12, location=(x_bar, 0, 0.08))
        bar = bpy.context.active_object
        bar.rotation_euler = (math.radians(90), 0, 0)
        bar.data.materials.append(mat_iron)
        apply_uniform_clay_bevel(bar, width=0.02, segments=2)
        objs.append(bar)

    # 4. 交叉粗大锻铁锁链 (Forged Iron Chains)
    for angle in [28, -28]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.16))
        chn = bpy.context.active_object
        chn.scale = (1.65, 0.14, 0.14)
        chn.rotation_euler = (0, 0, math.radians(angle))
        chn.data.materials.append(mat_iron)
        apply_uniform_clay_bevel(chn, width=0.03, segments=2)
        objs.append(chn)

    # 5. 中央恶魔骷髅头锁盘 (Embossed Demonic Skull Emblem)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.36, location=(0, 0, 0.24))
    skull = bpy.context.active_object
    skull.scale = (0.9, 1.1, 0.6)
    skull.data.materials.append(mat_skull)
    apply_uniform_clay_bevel(skull, width=0.04, segments=2)
    objs.append(skull)

    # 骷髅下颌
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.28, 0.20))
    jaw = bpy.context.active_object
    jaw.scale = (0.35, 0.22, 0.25)
    jaw.data.materials.append(mat_skull)
    apply_uniform_clay_bevel(jaw, width=0.03, segments=2)
    objs.append(jaw)

    # 骷髅双角
    for (sx, h_ang) in [(-0.30, -35), (0.30, 35)]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.10, radius2=0.02, depth=0.45, vertices=8, location=(sx, -0.25, 0.32))
        horn = bpy.context.active_object
        horn.rotation_euler = (0, 0, math.radians(h_ang))
        horn.data.materials.append(mat_gold)
        objs.append(horn)

    # 骷髅眼窝：发光熔岩红光 (Glowing Magma Eyes)
    for ex in [-0.14, 0.14]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex, -0.06, 0.36))
        eye = bpy.context.active_object
        eye.data.materials.append(mat_magma)
        objs.append(eye)

    return objs


def build_door_boss_open():
    objs = []
    mat_obsidian = create_clay_mat("m_dbo_obs", (0.16, 0.14, 0.20, 1.0), roughness=0.65)
    mat_floor    = create_clay_mat("m_dbo_floor", (0.12, 0.10, 0.15, 1.0), roughness=0.85)
    mat_gold     = create_clay_mat("m_dbo_gold", (0.88, 0.68, 0.18, 1.0), roughness=0.35)
    mat_magma    = create_clay_mat("m_dbo_magma", (1.0, 0.20, 0.05, 1.0), emission=(1.0, 0.20, 0.05, 1.0), emission_str=4.0)
    mat_ember    = create_clay_mat("m_dbo_ember", (0.95, 0.45, 0.10, 1.0), emission=(0.95, 0.45, 0.10, 1.0), emission_str=2.5)

    # 1. 基础暗黑底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_obsidian)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 凹陷深渊通道地板 (Abyssal Floor Runway)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    r_floor = bpy.context.active_object
    r_floor.scale = (1.75, 3.20, 0.12)
    r_floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(r_floor, width=0.04, segments=2)
    objs.append(r_floor)

    # 3. 两侧恶魔拱门立柱 (Demonic Archway Pillars)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.12))
        col = bpy.context.active_object
        col.scale = (0.65, 3.20, 0.48)
        col.data.materials.append(mat_obsidian)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 燃烧熔岩火盆 (Brazier with Hellfire Embers)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.25, vertices=12, location=(x_p, 0, 0.32))
        braz = bpy.context.active_object
        braz.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(braz, width=0.03, segments=2)
        objs.append(braz)

        # 火盆内红焰余烬
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(x_p, 0, 0.46))
        flame = bpy.context.active_object
        flame.scale = (1.0, 1.0, 1.4)
        flame.data.materials.append(mat_magma)
        objs.append(flame)

        # 巨大向内弯曲的恶魔之角 (Curved Arch Horns)
        horn_curve = 30 if x_p < 0 else -30
        bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.03, depth=0.85, vertices=8, location=(x_p, 0, 0.65))
        horn = bpy.context.active_object
        horn.rotation_euler = (0, math.radians(horn_curve), 0)
        horn.data.materials.append(mat_gold)
        objs.append(horn)

    # 4. 地面熔岩符文发光指引箭头 >>> (Glowing Magma Runes)
    for y_pos in [-0.60, 0.60]:
        for (side, angle) in [(-0.25, 40), (0.25, -40)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.45, 0.16, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_magma)
            objs.append(chev)

    # 5. 走道两侧熔岩裂隙光槽 (Magma Fissure Lines)
    for x_f in [-0.78, 0.78]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_f, 0, 0.02))
        fis = bpy.context.active_object
        fis.scale = (0.10, 2.40, 0.06)
        fis.data.materials.append(mat_ember)
        objs.append(fis)

    return objs


# ================================================================
# 3. SHOP GATEWAY (商店门: 锁闭木百叶卷帘 / 红白遮阳篷金币迎宾大门)
# ================================================================

def build_door_shop_locked():
    objs = []
    mat_frame = create_clay_mat("m_dsl_frame", (0.42, 0.26, 0.14, 1.0), roughness=0.75) # 橡木门框
    mat_plank = create_clay_mat("m_dsl_plank", (0.68, 0.46, 0.26, 1.0), roughness=0.70) # 木百叶板
    mat_iron  = create_clay_mat("m_dsl_iron", (0.30, 0.30, 0.35, 1.0), roughness=0.55)
    mat_gold  = create_clay_mat("m_dsl_gold", (0.95, 0.76, 0.20, 1.0), roughness=0.35)  # 黄铜大锁
    mat_awning= create_clay_mat("m_dsl_awn", (0.85, 0.22, 0.22, 1.0), roughness=0.80)   # 收拢的雨篷

    # 1. 基础木门框底座
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_frame)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 两侧厚重木立柱 (Timber Doorposts)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.08))
        col = bpy.context.active_object
        col.scale = (0.58, 3.20, 0.40)
        col.data.materials.append(mat_frame)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 铁质加固包角 (Iron Brackets)
        for y_b in [-1.1, 1.1]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, y_b, 0.22))
            brk = bpy.context.active_object
            brk.scale = (0.64, 0.32, 0.22)
            brk.data.materials.append(mat_iron)
            apply_uniform_clay_bevel(brk, width=0.03, segments=2)
            objs.append(brk)

    # 3. 门梁上方收拢的红白遮阳篷 (Rolled Awning Header)
    for y_aw in [-1.30, 1.30]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=2.10, vertices=16, location=(0, y_aw, 0.24))
        awn = bpy.context.active_object
        awn.rotation_euler = (0, math.radians(90), 0)
        awn.data.materials.append(mat_awning)
        apply_uniform_clay_bevel(awn, width=0.04, segments=2)
        objs.append(awn)

    # 4. 百叶木门板 (Wooden Shutter Louvers)
    for y_s in [-0.8, -0.4, 0.0, 0.4, 0.8]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_s, 0.05))
        plk = bpy.context.active_object
        plk.scale = (1.80, 0.36, 0.16)
        plk.rotation_euler = (math.radians(15), 0, 0)
        plk.data.materials.append(mat_plank)
        apply_uniform_clay_bevel(plk, width=0.03, segments=2)
        objs.append(plk)

    # 5. 中央重型黄铜大挂锁与金币徽标 (Heavy Brass Padlock & Coin)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
    padlock = bpy.context.active_object
    padlock.scale = (0.60, 0.55, 0.22)
    padlock.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(padlock, width=0.05, segments=2)
    objs.append(padlock)

    # 挂锁圆环锁梁 (Shackle Loop)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.06, location=(0, -0.28, 0.22))
    shackle = bpy.context.active_object
    shackle.rotation_euler = (math.radians(90), 0, 0)
    shackle.data.materials.append(mat_iron)
    objs.append(shackle)

    # 锁面浮雕金币印记 (Embossed Coin Badge)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.08, vertices=16, location=(0, 0, 0.34))
    coin = bpy.context.active_object
    coin.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(coin, width=0.02, segments=2)
    objs.append(coin)

    return objs


def build_door_shop_open():
    objs = []
    mat_frame  = create_clay_mat("m_dso_frame", (0.46, 0.28, 0.16, 1.0), roughness=0.75) # 暖木门柱
    mat_floor  = create_clay_mat("m_dso_floor", (0.30, 0.20, 0.12, 1.0), roughness=0.85)
    mat_carpet = create_clay_mat("m_dso_carpet", (0.92, 0.76, 0.20, 1.0), roughness=0.65) # 黄金迎宾地毯
    mat_red_aw = create_clay_mat("m_dso_red_aw", (0.92, 0.20, 0.22, 1.0), roughness=0.70) # 红条纹
    mat_wht_aw = create_clay_mat("m_dso_wht_aw", (0.95, 0.94, 0.90, 1.0), roughness=0.70) # 白条纹
    mat_lamp   = create_clay_mat("m_dso_lamp", (1.0, 0.90, 0.40, 1.0), emission=(1.0, 0.90, 0.40, 1.0), emission_str=3.5) # 暖黄迎宾灯
    mat_coin   = create_clay_mat("m_dso_coin", (1.0, 0.85, 0.20, 1.0), emission=(1.0, 0.85, 0.20, 1.0), emission_str=2.5) # 发光金币徽章

    # 1. 基础木质底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_frame)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 迎宾黄金地毯通道 (Golden Welcome Carpet Runway)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.04))
    carp = bpy.context.active_object
    carp.scale = (1.65, 3.20, 0.10)
    carp.data.materials.append(mat_carpet)
    apply_uniform_clay_bevel(carp, width=0.04, segments=2)
    objs.append(carp)

    # 3. 两侧木制商店拱门立柱 (Shop Timber Pillars)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.62, 3.20, 0.44)
        col.data.materials.append(mat_frame)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 暖光迎宾提灯 (Cozy Welcome Lanterns)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(x_p, 0, 0.35))
        lamp = bpy.context.active_object
        lamp.data.materials.append(mat_lamp)
        objs.append(lamp)

    # 4. 经典红白条纹遮阳雨篷 (Striped Fabric Canopy Awning)
    for y_aw in [-1.30, 1.30]:
        # 篷布由多段交替条纹组成
        for (i, x_strip) in enumerate([-0.8, -0.48, -0.16, 0.16, 0.48, 0.8]):
            mat_s = mat_red_aw if i % 2 == 0 else mat_wht_aw
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_strip, y_aw, 0.28))
            aw_p = bpy.context.active_object
            aw_p.scale = (0.30, 0.45, 0.25)
            aw_p.rotation_euler = (math.radians(18 if y_aw < 0 else -18), 0, 0)
            aw_p.data.materials.append(mat_s)
            apply_uniform_clay_bevel(aw_p, width=0.03, segments=2)
            objs.append(aw_p)

    # 5. 地毯中央发光大金币徽标 (Glowing Gold Coin Insignia)
    for y_c in [-0.55, 0.55]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.06, vertices=20, location=(0, y_c, 0.03))
        coin = bpy.context.active_object
        coin.data.materials.append(mat_coin)
        apply_uniform_clay_bevel(coin, width=0.03, segments=2)
        objs.append(coin)

        # 金币中心星纹或方孔
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_c, 0.07))
        star = bpy.context.active_object
        star.scale = (0.16, 0.16, 0.04)
        star.rotation_euler = (0, 0, math.radians(45))
        star.data.materials.append(mat_lamp)
        objs.append(star)

    return objs


# ================================================================
# 4. TREASURE GATEWAY (宝物/精英房门: 青金石镶金宝库重闸 / 晶蓝璀璨大门)
# ================================================================

def build_door_treasure_locked():
    objs = []
    mat_lapis = create_clay_mat("m_dtl_lapis", (0.16, 0.32, 0.58, 1.0), roughness=0.55) # 皇家青金石
    mat_gold  = create_clay_mat("m_dtl_gold", (0.98, 0.80, 0.20, 1.0), roughness=0.30)  # 璀璨黄金
    mat_gem   = create_clay_mat("m_dtl_gem", (0.25, 0.90, 1.0, 1.0), emission=(0.25, 0.90, 1.0, 1.0), emission_str=4.0) # 钻石蓝发光晶石

    # 1. 基础青金石底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_lapis)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 巴洛克式镀金螺旋门柱 (Baroque Golden Ornate Pillars)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.58, 3.20, 0.44)
        col.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 柱顶与柱脚青金石装饰环
        for y_r in [-1.2, 0, 1.2]:
            bpy.ops.mesh.primitive_torus_add(major_radius=0.35, minor_radius=0.08, location=(x_p, y_r, 0.20))
            ring = bpy.context.active_object
            ring.data.materials.append(mat_lapis)
            objs.append(ring)

    # 3. 宝库大门中央金色星芒轮盘 (Radial Golden Vault Dial)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.75, depth=0.22, vertices=24, location=(0, 0, 0.10))
    dial = bpy.context.active_object
    dial.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(dial, width=0.06, segments=2)
    objs.append(dial)

    # 4. 八方锁死金辐条 (8 Vault Spokes)
    for i in range(8):
        ang = i * (math.pi / 4.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.55, math.sin(ang) * 0.55, 0.18))
        spk = bpy.context.active_object
        spk.scale = (0.16, 0.40, 0.12)
        spk.rotation_euler = (0, 0, ang)
        spk.data.materials.append(mat_lapis)
        objs.append(spk)

    # 5. 中央巨型发光钻石宝珠 (Glowing Diamond Gem Lock)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.20, vertices=8, location=(0, 0, 0.28))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_gem)
    apply_uniform_clay_bevel(gem, width=0.04, segments=2)
    objs.append(gem)

    return objs


def build_door_treasure_open():
    objs = []
    mat_lapis = create_clay_mat("m_dto_lapis", (0.14, 0.28, 0.52, 1.0), roughness=0.65)
    mat_floor = create_clay_mat("m_dto_floor", (0.10, 0.18, 0.35, 1.0), roughness=0.85)
    mat_gold  = create_clay_mat("m_dto_gold", (0.98, 0.80, 0.20, 1.0), roughness=0.30)
    mat_gem   = create_clay_mat("m_dto_gem", (0.25, 0.90, 1.0, 1.0), emission=(0.25, 0.90, 1.0, 1.0), emission_str=4.0)
    mat_spark = create_clay_mat("m_dto_spark", (0.80, 0.95, 1.0, 1.0), emission=(0.80, 0.95, 1.0, 1.0), emission_str=2.5)

    # 1. 基础青金石底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_lapis)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 晶蓝璀璨地毯通道 (Cyan Crystal Runway)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    r_floor = bpy.context.active_object
    r_floor.scale = (1.75, 3.20, 0.12)
    r_floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(r_floor, width=0.04, segments=2)
    objs.append(r_floor)

    # 3. 两侧镀金拱门立柱 (Golden Archway Pillars)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.65, 3.20, 0.44)
        col.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 柱顶发光蓝宝石水晶 (Crystal Sconce)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.35, vertices=6, location=(x_p, 0, 0.38))
        sconce = bpy.context.active_object
        sconce.data.materials.append(mat_gem)
        objs.append(sconce)

    # 4. 地面晶蓝发光钻石导航箭头 >>> (Glowing Cyan Diamond Chevrons)
    for y_pos in [-0.60, 0.60]:
        for (side, angle) in [(-0.25, 38), (0.25, -38)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.45, 0.15, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_gem)
            objs.append(chev)

    # 5. 通道两侧闪烁光斑 (Sparkling Inlays)
    for x_s in [-0.75, 0.75]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_s, 0, 0.02))
        spk = bpy.context.active_object
        spk.scale = (0.08, 2.40, 0.05)
        spk.data.materials.append(mat_spark)
        objs.append(spk)

    return objs


# ================================================================
# 5. CHALLENGE GATEWAY (挑战大门: 暗紫尖刺战刃重闸 / 紫能竞技场大门)
# ================================================================

def build_door_challenge_locked():
    objs = []
    mat_metal = create_clay_mat("m_dcl_metal", (0.22, 0.18, 0.28, 1.0), roughness=0.60)
    mat_blade = create_clay_mat("m_dcl_blade", (0.75, 0.70, 0.82, 1.0), roughness=0.40)
    mat_gold  = create_clay_mat("m_dcl_gold", (0.85, 0.65, 0.18, 1.0), roughness=0.45)
    mat_purp  = create_clay_mat("m_dcl_purp", (0.85, 0.25, 1.0, 1.0), emission=(0.85, 0.25, 1.0, 1.0), emission_str=4.0)

    # 1. 基础暗紫装甲底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 尖锐装甲立柱与尖刺 (Angular Spiked Pillars)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.60, 3.20, 0.44)
        col.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 侧面尖刺 (Side Armor Spikes)
        for y_sp in [-1.0, 0, 1.0]:
            bpy.ops.mesh.primitive_cone_add(radius1=0.12, radius2=0.02, depth=0.35, vertices=6, location=(x_p + (0.35 if x_p < 0 else -0.35), y_sp, 0.20))
            spk = bpy.context.active_object
            spk.rotation_euler = (0, math.radians(90 if x_p < 0 else -90), 0)
            spk.data.materials.append(mat_purp)
            objs.append(spk)

    # 3. 交叉双刃战剑 (Crossed Combat Broadswords)
    for (angle, x_offset) in [(35, -0.05), (-35, 0.05)]:
        # 剑刃
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_offset, 0, 0.12))
        blade = bpy.context.active_object
        blade.scale = (0.24, 2.20, 0.12)
        blade.rotation_euler = (0, 0, math.radians(angle))
        blade.data.materials.append(mat_blade)
        apply_uniform_clay_bevel(blade, width=0.03, segments=2)
        objs.append(blade)

        # 剑格护手 (Crossguard)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_offset, 0.70, 0.16))
        guard = bpy.context.active_object
        guard.scale = (0.60, 0.15, 0.15)
        guard.rotation_euler = (0, 0, math.radians(angle))
        guard.data.materials.append(mat_gold)
        objs.append(guard)

    # 4. 中央紫晶警告能量锁 (Purple Crystal Hazard Core)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.20, vertices=6, location=(0, 0, 0.25))
    core = bpy.context.active_object
    core.data.materials.append(mat_purp)
    apply_uniform_clay_bevel(core, width=0.04, segments=2)
    objs.append(core)

    return objs


def build_door_challenge_open():
    objs = []
    mat_metal = create_clay_mat("m_dco_metal", (0.20, 0.16, 0.25, 1.0), roughness=0.65)
    mat_floor = create_clay_mat("m_dco_floor", (0.14, 0.10, 0.18, 1.0), roughness=0.85)
    mat_trim  = create_clay_mat("m_dco_trim", (0.45, 0.35, 0.55, 1.0), roughness=0.55)
    mat_purp  = create_clay_mat("m_dco_purp", (0.85, 0.25, 1.0, 1.0), emission=(0.85, 0.25, 1.0, 1.0), emission_str=4.0)

    # 1. 基础底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 竞技场通道地板 (Arena Runway)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    r_floor = bpy.context.active_object
    r_floor.scale = (1.75, 3.20, 0.12)
    r_floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(r_floor, width=0.04, segments=2)
    objs.append(r_floor)

    # 3. 门柱与紫色能量晶石 (Pillars with Power Crystals)
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.65, 3.20, 0.44)
        col.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 紫色立柱晶体
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.30, vertices=6, location=(x_p, 0, 0.35))
        crys = bpy.context.active_object
        crys.data.materials.append(mat_purp)
        objs.append(crys)

    # 4. 地面紫色突击导航箭头 >>> (Glowing Neon-Purple Chevrons)
    for y_pos in [-0.60, 0.60]:
        for (side, angle) in [(-0.25, 40), (0.25, -40)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.45, 0.15, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_purp)
            objs.append(chev)

    return objs


# ================================================================
# 6. SECRET ROOM DOOR (隐藏密室门: 裂纹暗石砖墙 / 碎石炸裂通道)
# ================================================================

def build_door_secret_cracked():
    objs = []
    # 颜色紧贴 tile_brick 砖墙红棕色, 保证隐蔽但仔细看有缝隙与碎石
    mat_mortar = create_clay_mat("m_dsc_mortar", (0.56, 0.48, 0.42, 1.0), roughness=0.85)
    mat_brick  = create_clay_mat("m_dsc_brick", (0.76, 0.34, 0.22, 1.0), roughness=0.75)
    mat_crack  = create_clay_mat("m_dsc_crack", (0.25, 0.15, 0.12, 1.0), roughness=0.90)
    mat_gleam  = create_clay_mat("m_dsc_gleam", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.5) # 裂缝透出的微光

    # 1. 砂浆底板 (Mortar Base Plate)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_mortar)
    apply_uniform_clay_bevel(plate, width=0.08, segments=3)
    objs.append(plate)

    # 2. 砖块排列 (Brick Array)
    brick_coords = [
        (-0.75, -0.85), (0.75, -0.85),
        (-0.85, 0.0), (0.0, 0.0), (0.85, 0.0),
        (-0.75, 0.85), (0.75, 0.85)
    ]
    for (bx, by) in brick_coords:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, 0.06))
        b = bpy.context.active_object
        b.scale = (1.30, 0.68, 0.22)
        b.data.materials.append(mat_brick)
        apply_uniform_clay_bevel(b, width=0.06, segments=2)
        objs.append(b)

    # 3. 凹陷裂纹与裂隙 (Fractured Stone Fissures)
    for (cx, cy, rot) in [(-0.15, -0.30, 25), (0.10, 0.25, -35), (-0.05, 0.45, 15)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.18))
        crk = bpy.context.active_object
        crk.scale = (0.12, 0.85, 0.12)
        crk.rotation_euler = (0, 0, math.radians(rot))
        crk.data.materials.append(mat_crack)
        objs.append(crk)

    # 4. 裂缝深处隐约透出的微弱蓝光 (Gleam of Mystery inside)
    for (gx, gy) in [(0.0, -0.15), (0.12, 0.35)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(gx, gy, 0.20))
        gleam = bpy.context.active_object
        gleam.data.materials.append(mat_gleam)
        objs.append(gleam)

    return objs


def build_door_secret_open():
    objs = []
    mat_mortar = create_clay_mat("m_dso_mortar", (0.50, 0.42, 0.36, 1.0), roughness=0.85)
    mat_void   = create_clay_mat("m_dso_void", (0.10, 0.08, 0.14, 1.0), roughness=0.90)
    mat_rubble = create_clay_mat("m_dso_rubble", (0.72, 0.32, 0.20, 1.0), roughness=0.80)
    mat_magic  = create_clay_mat("m_dso_magic", (0.40, 0.85, 1.0, 1.0), emission=(0.40, 0.85, 1.0, 1.0), emission_str=3.0)

    # 1. 破损砂浆底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_mortar)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 炸出的幽暗洞穴通道 (Dark Void Tunnel)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    tunnel = bpy.context.active_object
    tunnel.scale = (1.75, 3.20, 0.12)
    tunnel.data.materials.append(mat_void)
    apply_uniform_clay_bevel(tunnel, width=0.04, segments=2)
    objs.append(tunnel)

    # 3. 两侧被炸碎的残破砖墙断壁 (Blasted Wall Edges)
    for x_w in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_w, 0, 0.10))
        wall = bpy.context.active_object
        wall.scale = (0.65, 3.20, 0.44)
        wall.data.materials.append(mat_rubble)
        apply_uniform_clay_bevel(wall, width=0.08, segments=3)
        objs.append(wall)

        # 散落碎石块 (Debris Rubble)
        for y_r in [-0.8, 0.1, 0.9]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_w * 0.70, y_r, 0.15))
            rub = bpy.context.active_object
            rub.scale = (0.22, 0.25, 0.18)
            rub.rotation_euler = (math.radians(20), math.radians(15), math.radians(35))
            rub.data.materials.append(mat_rubble)
            apply_uniform_clay_bevel(rub, width=0.03, segments=2)
            objs.append(rub)

    # 4. 通道内的神秘微光导向箭头 >>> (Mystic Guidance Path)
    for y_pos in [-0.55, 0.55]:
        for (side, angle) in [(-0.25, 38), (0.25, -38)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.45, 0.15, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_magic)
            objs.append(chev)

    return objs


# ================================================================
# 7. EVENT / REST GATEWAY (事件/休息大门: 翡翠藤木大门 / 营地暖绿通道)
# ================================================================

def build_door_event_locked():
    objs = []
    mat_wood = create_clay_mat("m_del_wood", (0.35, 0.22, 0.12, 1.0), roughness=0.80)
    mat_vine = create_clay_mat("m_del_vine", (0.28, 0.58, 0.22, 1.0), roughness=0.65)
    mat_jade = create_clay_mat("m_del_jade", (0.30, 0.95, 0.45, 1.0), emission=(0.30, 0.95, 0.45, 1.0), emission_str=3.5)

    # 1. 基础木门框底座
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.25)
    plate.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 两侧立柱与藤蔓
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.08))
        col = bpy.context.active_object
        col.scale = (0.58, 3.20, 0.40)
        col.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 绿色翡翠晶石
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(x_p, 0, 0.32))
        jade = bpy.context.active_object
        jade.data.materials.append(mat_jade)
        objs.append(jade)

    # 3. 交叉密林藤木板
    for (angle, y_offset) in [(30, -0.1), (-30, 0.1)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, y_offset, 0.10))
        vn = bpy.context.active_object
        vn.scale = (1.70, 0.35, 0.18)
        vn.rotation_euler = (0, 0, math.radians(angle))
        vn.data.materials.append(mat_vine)
        apply_uniform_clay_bevel(vn, width=0.04, segments=2)
        objs.append(vn)

    # 4. 中央翡翠生命徽记
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.18, vertices=8, location=(0, 0, 0.24))
    core = bpy.context.active_object
    core.data.materials.append(mat_jade)
    apply_uniform_clay_bevel(core, width=0.04, segments=2)
    objs.append(core)

    return objs


def build_door_event_open():
    objs = []
    mat_wood  = create_clay_mat("m_deo_wood", (0.38, 0.24, 0.14, 1.0), roughness=0.75)
    mat_floor = create_clay_mat("m_deo_floor", (0.18, 0.28, 0.16, 1.0), roughness=0.85)
    mat_green = create_clay_mat("m_deo_green", (0.35, 0.95, 0.50, 1.0), emission=(0.35, 0.95, 0.50, 1.0), emission_str=3.5)
    mat_warm  = create_clay_mat("m_deo_warm", (0.95, 0.85, 0.35, 1.0), emission=(0.95, 0.85, 0.35, 1.0), emission_str=2.0)

    # 1. 基础木质底板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.18))
    plate = bpy.context.active_object
    plate.scale = (TILE_PLATE_BLEED, TILE_PLATE_BLEED, 0.22)
    plate.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(plate, width=0.10, segments=3)
    objs.append(plate)

    # 2. 翠绿生机通道地板
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    r_floor = bpy.context.active_object
    r_floor.scale = (1.75, 3.20, 0.12)
    r_floor.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(r_floor, width=0.04, segments=2)
    objs.append(r_floor)

    # 3. 两侧藤木立柱
    for x_p in [-1.22, 1.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_p, 0, 0.10))
        col = bpy.context.active_object
        col.scale = (0.65, 3.20, 0.44)
        col.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(col, width=0.08, segments=3)
        objs.append(col)

        # 暖光灯笼
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(x_p, 0, 0.35))
        lamp = bpy.context.active_object
        lamp.data.materials.append(mat_warm)
        objs.append(lamp)

    # 4. 地面生机绿光导航箭头 >>>
    for y_pos in [-0.60, 0.60]:
        for (side, angle) in [(-0.25, 38), (0.25, -38)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, y_pos, 0.02))
            chev = bpy.context.active_object
            chev.scale = (0.45, 0.15, 0.06)
            chev.rotation_euler = (0, 0, math.radians(angle))
            chev.data.materials.append(mat_green)
            objs.append(chev)

    return objs


# ================================================================
# 8. 批处理主渲染管线 (Main Batch Render Pipeline)
# ================================================================

DOOR_ASSETS = [
    ("door_normal_locked", build_door_normal_locked),
    ("door_normal_open",   build_door_normal_open),
    ("door_boss_locked",   build_door_boss_locked),
    ("door_boss_open",     build_door_boss_open),
    ("door_shop_locked",   build_door_shop_locked),
    ("door_shop_open",     build_door_shop_open),
    ("door_treasure_locked", build_door_treasure_locked),
    ("door_treasure_open",   build_door_treasure_open),
    ("door_challenge_locked", build_door_challenge_locked),
    ("door_challenge_open",   build_door_challenge_open),
    ("door_secret_cracked",   build_door_secret_cracked),
    ("door_secret_open",     build_door_secret_open),
    ("door_event_locked",     build_door_event_locked),
    ("door_event_open",       build_door_event_open),
]

def main():
    print("==================================================")
    print(">>> 启动房间门 3D 建模与 Cycles 渲染流水线 <<<")
    print("==================================================")
    reset_jitter_seed(5500)

    for (name, builder) in DOOR_ASSETS:
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = builder()
        out_path = os.path.join(SPRITES_BUILDINGS, f"{name}.png")
        render_and_clean(objs, out_path, label="[Door Rendered]")

    print("==================================================")
    print(">>> 全部 14 种房间门 3D 资产渲染完毕！ <<<")
    print("==================================================")

if __name__ == "__main__":
    main()
