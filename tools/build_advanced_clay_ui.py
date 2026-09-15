"""build_advanced_clay_ui.py — 高级 3D 黏土 UI 资产建模与 Cycles 渲染管线

渲染以下与 Sokpop 黏土画风统一的 UI 界面资产：
  1. ui_minimap_frame: HUD 小地图战术黏土边框 (带黄铜角钉、深灰战术防眩光斜边)
  2. ui_card_bg_normal: 升级选择卡片常规黏土卡身 (圆角黏土板、浮雕暗纹凹槽)
  3. ui_card_bg_hover: 升级选择卡片高亮/焦点状态 (金黄微光包边、浮雕加深)
  4. ui_card_bg_branch: 转职分支专属典藏卡身 (尊贵双色黏土与镀金外框)
  5. perk_amphibious: 水陆两栖螺旋桨波纹战备徽章
  6. perk_piercing: 重型穿甲脱壳弹头徽章
  7. perk_frost: 极地防滑防冻履带钉齿徽章
  8. perk_ferry: 平台摆渡双联炮台增伤徽章
  9. ui_badge_key: 宝库钥匙计数黏土徽章
  10. ui_badge_streak: 连杀狂暴火焰奖章
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
    ORTHO_SCALE_PROP,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
os.makedirs(SPRITES_UI, exist_ok=True)


# ================================================================
# 1. MINIMAP TACTICAL FRAME (HUD 小地图战术边框)
# ================================================================

def build_minimap_frame():
    objs = []
    mat_outer = create_clay_mat("m_mm_out", (0.22, 0.18, 0.26, 1.0), roughness=0.55)
    mat_inner = create_clay_mat("m_mm_in", (0.12, 0.10, 0.15, 0.95), roughness=0.75)
    mat_gold  = create_clay_mat("m_mm_gld", (0.92, 0.74, 0.22, 1.0), roughness=0.35)
    mat_cyan  = create_clay_mat("m_mm_cyn", (0.35, 0.85, 0.95, 1.0), emission=(0.35, 0.85, 0.95, 1.0), emission_str=2.5)

    # 1. 外边框 (Outer Beveled Frame)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    outer = bpy.context.active_object
    outer.scale = (2.60, 2.60, 0.25)
    outer.data.materials.append(mat_outer)
    apply_uniform_clay_bevel(outer, width=0.12, segments=3)
    objs.append(outer)

    # 2. 内凹透视暗底 (Recessed Screen Bed)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.04))
    inner = bpy.context.active_object
    inner.scale = (2.20, 2.20, 0.18)
    inner.data.materials.append(mat_inner)
    apply_uniform_clay_bevel(inner, width=0.04, segments=2)
    objs.append(inner)

    # 3. 四角固定黄铜铆钉与防撞角包 (Corner Rivets & Brackets)
    for (cx, cy) in [(-1.12, -1.12), (1.12, -1.12), (-1.12, 1.12), (1.12, 1.12)]:
        # 角扣
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.08))
        brk = bpy.context.active_object
        brk.scale = (0.32, 0.32, 0.12)
        brk.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(brk, width=0.03, segments=2)
        objs.append(brk)

        # 铆钉
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.15, vertices=12, location=(cx, cy, 0.15))
        rvt = bpy.context.active_object
        rvt.data.materials.append(mat_gold)
        objs.append(rvt)

    # 4. 雷达顶部微型扫描指示绿灯 (Status Radar Diode)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, -1.18, 0.12))
    diode = bpy.context.active_object
    diode.data.materials.append(mat_cyan)
    objs.append(diode)

    return objs


# ================================================================
# 2. UPGRADE CARDS BACKGROUNDS (升级选择卡片背景)
# ================================================================

def build_card_bg(state="normal"):
    objs = []
    if state == "hover":
        col_rim = (0.98, 0.82, 0.25, 1.0)
        col_body = (0.24, 0.20, 0.28, 1.0)
        col_groove = (0.16, 0.14, 0.20, 1.0)
        em_color = (0.98, 0.82, 0.25, 1.0)
        em_str = 2.0
    elif state == "branch":
        col_rim = (0.95, 0.50, 0.22, 1.0)
        col_body = (0.30, 0.20, 0.32, 1.0)
        col_groove = (0.18, 0.12, 0.20, 1.0)
        em_color = (0.95, 0.50, 0.22, 1.0)
        em_str = 3.0
    else:
        col_rim = (0.38, 0.34, 0.42, 1.0)
        col_body = (0.18, 0.16, 0.22, 1.0)
        col_groove = (0.12, 0.10, 0.15, 1.0)
        em_color = (0, 0, 0, 1.0)
        em_str = 0.0

    mat_rim    = create_clay_mat(f"m_crd_rim_{state}", col_rim, roughness=0.45, emission=em_color, emission_str=em_str)
    mat_body   = create_clay_mat(f"m_crd_bdy_{state}", col_body, roughness=0.65)
    mat_groove = create_clay_mat(f"m_crd_grv_{state}", col_groove, roughness=0.75)
    mat_gold   = create_clay_mat(f"m_crd_gld_{state}", (0.95, 0.78, 0.20, 1.0), roughness=0.35)

    # 1. 竖向卡身外框 (Vertical Rectangular Clay Base)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.scale = (2.10, 2.50, 0.22)
    base.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(base, width=0.14, segments=4)
    objs.append(base)

    # 2. 内凹主卡面 (Inner Recessed Card Face)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.04))
    inner = bpy.context.active_object
    inner.scale = (1.80, 2.20, 0.16)
    inner.data.materials.append(mat_body)
    apply_uniform_clay_bevel(inner, width=0.08, segments=3)
    objs.append(inner)

    # 3. 顶部图标放置圆形凹槽 (Circular Badge Well)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.12, vertices=24, location=(0, -0.45, 0.08))
    well = bpy.context.active_object
    well.data.materials.append(mat_groove)
    apply_uniform_clay_bevel(well, width=0.03, segments=2)
    objs.append(well)

    # 4. 底部说明文字区域凹槽 (Description Panel Groove)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.55, 0.08))
    desc_p = bpy.context.active_object
    desc_p.scale = (1.55, 0.85, 0.10)
    desc_p.data.materials.append(mat_groove)
    apply_uniform_clay_bevel(desc_p, width=0.04, segments=2)
    objs.append(desc_p)

    # 5. 顶角金色角标 (Gold Trim Accents)
    for cx in [-0.92, 0.92]:
        for cy in [-1.12, 1.12]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.08))
            corn = bpy.context.active_object
            corn.scale = (0.24, 0.24, 0.10)
            corn.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(corn, width=0.02, segments=2)
            objs.append(corn)

    return objs


# ================================================================
# 3. MISSING PERK BADGES (缺失的被动战备专属徽章)
# ================================================================

def build_perk_amphibious():
    """水陆两栖装甲: 螺旋桨与水波纹"""
    objs = []
    mat_plate = create_clay_mat("m_pk_amp_p", (0.16, 0.35, 0.65, 1.0), roughness=0.55)
    mat_gold  = create_clay_mat("m_pk_amp_g", (0.95, 0.78, 0.22, 1.0), roughness=0.35)
    mat_brass = create_clay_mat("m_pk_amp_b", (0.85, 0.62, 0.18, 1.0), roughness=0.40)
    mat_water = create_clay_mat("m_pk_amp_w", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.5)

    # 圆盘底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.08, segments=3)
    objs.append(plate)

    # 外圈金色圆环
    bpy.ops.mesh.primitive_torus_add(major_radius=0.82, minor_radius=0.08, location=(0, 0, 0.12))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_gold)
    objs.append(ring)

    # 3 叶黄铜螺旋桨 (3-Blade Brass Propeller)
    for i in range(3):
        ang = i * (2.0 * math.pi / 3.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.35, math.sin(ang) * 0.35, 0.18))
        bld = bpy.context.active_object
        bld.scale = (0.18, 0.45, 0.08)
        bld.rotation_euler = (0, 0, ang + math.radians(25))
        bld.data.materials.append(mat_brass)
        apply_uniform_clay_bevel(bld, width=0.03, segments=2)
        objs.append(bld)

    # 桨毂圆球
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0, 0, 0.24))
    hub = bpy.context.active_object
    hub.data.materials.append(mat_gold)
    objs.append(hub)

    # 底部水波纹弧线
    for wy in [0.45, 0.65]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.35, minor_radius=0.05, location=(0, wy, 0.16))
        wave = bpy.context.active_object
        wave.scale = (1.2, 0.4, 1.0)
        wave.data.materials.append(mat_water)
        objs.append(wave)

    return objs


def build_perk_piercing():
    """穿甲脱壳弹: 尖锐钨芯穿甲弹头破甲"""
    objs = []
    mat_plate = create_clay_mat("m_pk_prc_p", (0.28, 0.20, 0.22, 1.0), roughness=0.55)
    mat_steel = create_clay_mat("m_pk_prc_s", (0.80, 0.84, 0.92, 1.0), roughness=0.35)
    mat_gold  = create_clay_mat("m_pk_prc_g", (0.95, 0.78, 0.22, 1.0), roughness=0.35)
    mat_fire  = create_clay_mat("m_pk_prc_f", (1.0, 0.30, 0.15, 1.0), emission=(1.0, 0.30, 0.15, 1.0), emission_str=3.0)

    # 八角盾形底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.20, vertices=8, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.08, segments=3)
    objs.append(plate)

    # 穿甲长弹体 (Sabot Core Body)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=1.10, vertices=16, location=(0, 0.05, 0.18))
    body = bpy.context.active_object
    body.rotation_euler = (math.radians(90), 0, 0)
    body.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(body, width=0.03, segments=2)
    objs.append(body)

    # 尖锐锥形弹头 (Sharp AP Tip)
    bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.02, depth=0.55, vertices=16, location=(0, -0.65, 0.18))
    tip = bpy.context.active_object
    tip.rotation_euler = (math.radians(-90), 0, 0)
    tip.data.materials.append(mat_gold)
    objs.append(tip)

    # 弹尾脱壳翼片 (Stabilizing Fins)
    for ang in [0, 90]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.55, 0.18))
        fin = bpy.context.active_object
        fin.scale = (0.55, 0.25, 0.06)
        fin.rotation_euler = (0, 0, math.radians(ang))
        fin.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(fin, width=0.02, segments=2)
        objs.append(fin)

    # 穿甲破裂火星
    for sx in [-0.25, 0.25]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(sx, -0.45, 0.22))
        spk = bpy.context.active_object
        spk.data.materials.append(mat_fire)
        objs.append(spk)

    return objs


def build_perk_frost():
    """极地防滑履带钉: 冰霜雪花与防滑钢爪"""
    objs = []
    mat_plate = create_clay_mat("m_pk_fst_p", (0.18, 0.32, 0.48, 1.0), roughness=0.55)
    mat_ice   = create_clay_mat("m_pk_fst_i", (0.45, 0.90, 1.0, 1.0), emission=(0.45, 0.90, 1.0, 1.0), emission_str=3.0)
    mat_steel = create_clay_mat("m_pk_fst_s", (0.85, 0.88, 0.94, 1.0), roughness=0.35)

    # 六角形冰霜底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.20, vertices=6, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.08, segments=3)
    objs.append(plate)

    # 6 轴发光冰晶雪花 (6-Axis Ice Snowflake)
    for i in range(3):
        ang = i * (math.pi / 3.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.16))
        bar = bpy.context.active_object
        bar.scale = (0.14, 1.40, 0.08)
        bar.rotation_euler = (0, 0, ang)
        bar.data.materials.append(mat_ice)
        apply_uniform_clay_bevel(bar, width=0.02, segments=2)
        objs.append(bar)

    # 履带防滑重钢爪 (Steel Tread Cleats)
    for (cx, cy) in [(-0.45, -0.45), (0.45, -0.45), (-0.45, 0.45), (0.45, 0.45)]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.12, radius2=0.03, depth=0.30, vertices=6, location=(cx, cy, 0.24))
        cleat = bpy.context.active_object
        cleat.data.materials.append(mat_steel)
        objs.append(cleat)

    return objs


def build_perk_ferry():
    """摆渡双联要塞炮: 浮动平台与双联重炮"""
    objs = []
    mat_plate = create_clay_mat("m_pk_fry_p", (0.35, 0.28, 0.20, 1.0), roughness=0.65)
    mat_wood  = create_clay_mat("m_pk_fry_w", (0.65, 0.45, 0.25, 1.0), roughness=0.70)
    mat_gun   = create_clay_mat("m_pk_fry_g", (0.75, 0.78, 0.85, 1.0), roughness=0.35)
    mat_gold  = create_clay_mat("m_pk_fry_d", (0.95, 0.78, 0.20, 1.0), roughness=0.35)

    # 圆盘底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.08, segments=3)
    objs.append(plate)

    # 浮动木筏平台 (Wooden Ferry Raft)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.25, 0.12))
    raft = bpy.context.active_object
    raft.scale = (1.20, 0.80, 0.15)
    raft.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(raft, width=0.04, segments=2)
    objs.append(raft)

    # 双联火炮管 (Twin Artillery Cannons)
    for bx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=1.00, vertices=16, location=(bx, -0.20, 0.22))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_gun)
        apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
        objs.append(barrel)

        # 炮口金箍
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.15, vertices=16, location=(bx, -0.65, 0.22))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(muzzle, width=0.02, segments=2)
        objs.append(muzzle)

    return objs


def build_badge_key():
    """宝库钥匙徽章"""
    objs = []
    mat_plate = create_clay_mat("m_bg_key_p", (0.18, 0.22, 0.32, 1.0), roughness=0.55)
    mat_gold  = create_clay_mat("m_bg_key_g", (0.98, 0.82, 0.22, 1.0), roughness=0.35)
    mat_gem   = create_clay_mat("m_bg_key_gem", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=3.0)

    # 底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=16, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.06, segments=2)
    objs.append(plate)

    # 黄金钥匙把手圆环 (Key Bow Ring)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.32, minor_radius=0.10, location=(0, -0.38, 0.16))
    bow = bpy.context.active_object
    bow.data.materials.append(mat_gold)
    objs.append(bow)

    # 钥匙柄身 (Key Shaft)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.75, vertices=12, location=(0, 0.12, 0.16))
    shaft = bpy.context.active_object
    shaft.rotation_euler = (math.radians(90), 0, 0)
    shaft.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(shaft, width=0.02, segments=2)
    objs.append(shaft)

    # 钥匙齿 (Key Bit Teeth)
    for ty in [0.28, 0.44]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.18, ty, 0.16))
        tooth = bpy.context.active_object
        tooth.scale = (0.22, 0.10, 0.12)
        tooth.data.materials.append(mat_gold)
        objs.append(tooth)

    # 钥匙柄宝石
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, -0.38, 0.22))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_gem)
    objs.append(gem)

    return objs


def build_badge_streak():
    """连击狂暴火焰勋章"""
    objs = []
    mat_shield = create_clay_mat("m_bg_stk_s", (0.25, 0.12, 0.15, 1.0), roughness=0.55)
    mat_gold   = create_clay_mat("m_bg_stk_g", (0.95, 0.78, 0.20, 1.0), roughness=0.35)
    mat_flame1 = create_clay_mat("m_bg_stk_f1", (1.0, 0.25, 0.10, 1.0), emission=(1.0, 0.25, 0.10, 1.0), emission_str=3.5)
    mat_flame2 = create_clay_mat("m_bg_stk_f2", (1.0, 0.85, 0.20, 1.0), emission=(1.0, 0.85, 0.20, 1.0), emission_str=4.0)

    # 盾形底板
    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=6, location=(0, 0, 0))
    shield = bpy.context.active_object
    shield.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(shield, width=0.06, segments=2)
    objs.append(shield)

    # 外部火焰 (Outer Flame)
    bpy.ops.mesh.primitive_cone_add(radius1=0.45, radius2=0.05, depth=1.10, vertices=12, location=(0, 0, 0.16))
    flm1 = bpy.context.active_object
    flm1.rotation_euler = (math.radians(-90), 0, 0)
    flm1.data.materials.append(mat_flame1)
    apply_uniform_clay_bevel(flm1, width=0.04, segments=2)
    objs.append(flm1)

    # 内部高亮核心火芯 (Inner Flame Core)
    bpy.ops.mesh.primitive_cone_add(radius1=0.25, radius2=0.02, depth=0.65, vertices=12, location=(0, 0.10, 0.24))
    flm2 = bpy.context.active_object
    flm2.rotation_euler = (math.radians(-90), 0, 0)
    flm2.data.materials.append(mat_flame2)
    objs.append(flm2)

    return objs


# ================================================================
# 主批处理管线
# ================================================================

ADVANCED_UI_ASSETS = [
    ("ui_minimap_frame", build_minimap_frame, ORTHO_SCALE_DEFAULT),
    ("ui_card_bg_normal", lambda: build_card_bg("normal"), ORTHO_SCALE_DEFAULT),
    ("ui_card_bg_hover", lambda: build_card_bg("hover"), ORTHO_SCALE_DEFAULT),
    ("ui_card_bg_branch", lambda: build_card_bg("branch"), ORTHO_SCALE_DEFAULT),
    ("perk_amphibious", build_perk_amphibious, ORTHO_SCALE_PROP),
    ("perk_piercing", build_perk_piercing, ORTHO_SCALE_PROP),
    ("perk_frost", build_perk_frost, ORTHO_SCALE_PROP),
    ("perk_ferry", build_perk_ferry, ORTHO_SCALE_PROP),
    ("ui_badge_key", build_badge_key, ORTHO_SCALE_PROP),
    ("ui_badge_streak", build_badge_streak, ORTHO_SCALE_PROP),
]

def main():
    print("==================================================")
    print(">>> 启动高级 3D 黏土 UI 资产渲染流水线 <<<")
    print("==================================================")
    reset_jitter_seed(6600)

    for (name, builder, ortho) in ADVANCED_UI_ASSETS:
        clear_scene()
        setup_render_settings(rx=256, ry=256, samples=32)
        create_sokpop_lighting(ortho_scale=ortho)
        objs = builder()
        out_path = os.path.join(SPRITES_UI, f"{name}.png")
        render_and_clean(objs, out_path, label="[UI Asset Rendered]")

    print("==================================================")
    print(">>> 全部高级 3D 黏土 UI 资产渲染完毕！ <<<")
    print("==================================================")

if __name__ == "__main__":
    main()
