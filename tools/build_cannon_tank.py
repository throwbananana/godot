"""build_cannon_tank.py — 巨炮坦克 (Colossus Siege Cannon Tank) 3D 建模、变形驻扎动效与 Cycles 黏土渲染管线

巨炮坦克 (Colossus Siege Cannon Tank / Howitzer Fortress Tank):
  - 移动巡逻形态 (Mobile Mode):
      * 坚重履带装甲底盘 + 巨型重榴弹攻城主炮管 (Heavy Howitzer Cannon) + 炮口多孔消焰制退器
      * 车身四角收起折叠的液压驻锄支架 (Folded Hydraulic Outriggers)
      * 炮塔两侧折叠合拢的厚重弧面防盾 (Folded Blast Shields)
  - 固定要塞炮形态 (Deployed Siege Mode):
      * 四角重型液压驻锄支架向外强力伸展并深深打入地面 (Extended Stabilizer Claw Anchors)
      * 炮塔两侧防弹重盾向前展开闭锁，构成半包围要塞碉堡重型装甲面 (Fortified Bastion Mantlet)
      * 巨炮主炮管前伸架起，蓄能线圈与散热格栅高亮脉冲充能 (Pulsing Energy Coils & Heat Vents)
      * 防御力大幅提升，转为远程高爆巨炮重型攻城压制

输出资源:
  - assets/sprites/tanks/tank_cannon_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_cannon_f0.png ~ f5.png
  - assets/sprites/tanks/tank_cannon_deploy_f0.png ~ f5.png
  - assets/sprites/tanks/enemy_cannon_deploy_f0.png ~ f5.png
  - assets/sprites/tanks/tank_cannon.png
  - assets/sprites/tanks/enemy_cannon.png
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
os.makedirs(SPRITES_TANKS, exist_ok=True)


def build_cannon_tank(frame: int = 0, is_enemy: bool = True, is_deployed: bool = False):
    """构建巨炮坦克 3D 模型

    is_deployed: False 为移动形态，True 为变形后的固定驻扎要塞炮形态
    """
    objs = []

    # 1. 材质定义 (Sokpop 黏土重型铸造装甲与合金着色)
    if is_enemy:
        col_hull    = srgb_to_linear((0.32, 0.16, 0.18, 1.0)) # 敌方深铁锈血红
        col_shield  = srgb_to_linear((0.24, 0.10, 0.12, 1.0)) # 敌方重型暗黑钢盾
        col_trim    = srgb_to_linear((0.85, 0.35, 0.15, 1.0)) # 炽红预警标线
        col_energy  = srgb_to_linear((1.00, 0.45, 0.10, 1.0)) # 巨炮充能高能烈焰金橙
    else:
        col_hull    = srgb_to_linear((0.18, 0.28, 0.42, 1.0)) # 友方战术苍蓝
        col_shield  = srgb_to_linear((0.12, 0.18, 0.28, 1.0)) # 友方深钢防盾
        col_trim    = srgb_to_linear((0.25, 0.85, 0.95, 1.0)) # 青蓝亮标
        col_energy  = srgb_to_linear((0.20, 0.90, 1.00, 1.0)) # 等离子能量脉冲蓝

    col_track   = srgb_to_linear((0.18, 0.18, 0.20, 1.0)) # 重型履带暗铁
    col_steel   = srgb_to_linear((0.45, 0.48, 0.52, 1.0)) # 炮身加固合金钢
    col_brass   = srgb_to_linear((0.88, 0.65, 0.22, 1.0)) # 铸造黄铜铆钉与制退器饰环
    col_anchor  = srgb_to_linear((0.35, 0.36, 0.40, 1.0)) # 液压驻锄重钢

    mat_hull    = create_clay_mat("m_cn_hl", col_hull, roughness=0.60)
    mat_shield  = create_clay_mat("m_cn_shd", col_shield, roughness=0.50)
    mat_trim    = create_clay_mat("m_cn_tm", col_trim, roughness=0.45)
    mat_track   = create_clay_mat("m_cn_tk", col_track, roughness=0.85)
    mat_steel   = create_clay_mat("m_cn_st", col_steel, roughness=0.35)
    mat_brass   = create_clay_mat("m_cn_brs", col_brass, roughness=0.40)
    mat_anchor  = create_clay_mat("m_cn_anc", col_anchor, roughness=0.45)

    # 动态充能与散热脉冲
    pulse = 3.0 + 2.5 * math.sin(frame * (2.0 * math.pi / 6.0)) if is_deployed else 1.5
    mat_energy  = create_clay_mat("m_cn_eng", col_energy, emission=col_energy, emission_str=pulse)

    # 动画起伏控制
    phase = frame * (2.0 * math.pi / 6.0)
    bob_z = (math.sin(phase) * 0.015) if not is_deployed else 0.0
    recoil_y = (math.sin(phase) * 0.02) if is_deployed else 0.0

    # ==================== 1. 重型双履带装甲底盘 (Chassis & Tracks) ====================
    for side in [-0.62, 0.62]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side, 0, 0.16 + bob_z))
        track = bpy.context.active_object
        track.scale = (0.34, 1.48, 0.28)
        track.data.materials.append(mat_track)
        apply_uniform_clay_bevel(track, width=0.04, segments=2)
        objs.append(track)

        # 履带护板 (Track Skirt Armor)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 1.05, 0, 0.28 + bob_z))
        skirt = bpy.context.active_object
        skirt.scale = (0.10, 1.40, 0.14)
        skirt.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(skirt, width=0.03, segments=2)
        objs.append(skirt)

    # 主车体平台 (Main Hull Deck)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.24 + bob_z))
    deck = bpy.context.active_object
    deck.scale = (1.05, 1.35, 0.26)
    deck.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(deck, width=0.06, segments=3)
    objs.append(deck)

    # 车头倾斜防弹挡板 (Front Sloped Glacis)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.65, 0.26 + bob_z))
    glacis = bpy.context.active_object
    glacis.scale = (0.95, 0.32, 0.22)
    glacis.rotation_euler = (math.radians(-25), 0, 0)
    glacis.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(glacis, width=0.04, segments=2)
    objs.append(glacis)

    # ==================== 2. 四角液压驻锄支架 (Hydraulic Outrigger Anchors) ====================
    anchor_corners = [
        (-0.72, -0.68, -135),
        ( 0.72, -0.68,  135),
        (-0.72,  0.68,  -45),
        ( 0.72,  0.68,   45)
    ]
    for ax, ay, base_ang in anchor_corners:
        if is_deployed:
            # 驻扎形态：支架向外大力展开并抓地
            spread_x = ax * 1.25
            spread_y = ay * 1.20
            # 液压伸缩臂 (Piston Arm)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.55, vertices=12,
                                                 location=((ax + spread_x) / 2.0, (ay + spread_y) / 2.0, 0.16))
            piston = bpy.context.active_object
            piston.rotation_euler = (math.radians(20 if ay > 0 else -20), math.radians(-25 if ax > 0 else 25), 0)
            piston.data.materials.append(mat_steel)
            objs.append(piston)

            # 重型地面咬合抓地脚盘 (Anchor Ground Claw Pad)
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(spread_x, spread_y, 0.05))
            pad = bpy.context.active_object
            pad.scale = (0.28, 0.28, 0.10)
            pad.data.materials.append(mat_anchor)
            apply_uniform_clay_bevel(pad, width=0.03, segments=2)
            objs.append(pad)

            # 抓地地钉 (Spike Pin)
            bpy.ops.mesh.primitive_cone_add(radius1=0.10, depth=0.18, vertices=8,
                                            location=(spread_x, spread_y, -0.04))
            spike = bpy.context.active_object
            spike.data.materials.append(mat_anchor)
            objs.append(spike)
        else:
            # 移动形态：支架向上折叠收拢在底盘四角
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ax, ay, 0.32 + bob_z))
            stow = bpy.context.active_object
            stow.scale = (0.16, 0.18, 0.24)
            stow.rotation_euler = (0, 0, math.radians(base_ang))
            stow.data.materials.append(mat_anchor)
            apply_uniform_clay_bevel(stow, width=0.02, segments=2)
            objs.append(stow)

    # ==================== 3. 巨炮旋转要塞炮塔 (Siege Turret Ring & Housing) ====================
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.35, vertices=16, location=(0, 0, 0.44 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.10, 1.15, 1.0)
    turret.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(turret, width=0.05, segments=3)
    objs.append(turret)

    # 炮塔顶盖防护舱 (Turret Commander Cupola)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.14, vertices=14, location=(0, -0.15, 0.65 + bob_z))
    cupola = bpy.context.active_object
    cupola.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(cupola, width=0.02, segments=2)
    objs.append(cupola)

    # 炮塔战术标线
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.15, 0.63 + bob_z))
    turret_stripe = bpy.context.active_object
    turret_stripe.scale = (0.50, 0.12, 0.04)
    turret_stripe.data.materials.append(mat_trim)
    objs.append(turret_stripe)

    # ==================== 4. 巨型攻城榴弹炮管 (Colossus Howitzer Barrel) ====================
    gun_len = 1.65 if not is_deployed else 1.78 # 驻扎形态炮管前伸架出
    gun_y   = 0.72 + (recoil_y if is_deployed else 0.0)

    # 粗硕根部炮膛套筒 (Breech Sleeve Housing)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.60, vertices=16,
                                         location=(0, 0.35 + (recoil_y if is_deployed else 0.0), 0.46 + bob_z))
    breech = bpy.context.active_object
    breech.rotation_euler = (math.radians(90), 0, 0)
    breech.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(breech, width=0.03, segments=2)
    objs.append(breech)

    # 巨型长主炮管 (Heavy Howitzer Main Barrel)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=gun_len, vertices=16,
                                         location=(0, gun_y, 0.46 + bob_z))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
    objs.append(barrel)

    # 炮身蓄能环与散热线圈 (Energy Heat Coils)
    coil_positions = [0.45, 0.75, 1.05]
    for cy in coil_positions:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.16, minor_radius=0.03,
                                         location=(0, cy + (recoil_y if is_deployed else 0.0), 0.46 + bob_z))
        coil = bpy.context.active_object
        coil.rotation_euler = (math.radians(90), 0, 0)
        coil.data.materials.append(mat_energy)
        objs.append(coil)

    # 巨型重型炮口制退消焰器 (Massive Slotted Muzzle Brake)
    muzzle_y = gun_y + gun_len / 2.0 + 0.08
    bpy.ops.mesh.primitive_cylinder_add(radius=0.19, depth=0.28, vertices=16,
                                         location=(0, muzzle_y, 0.46 + bob_z))
    brake = bpy.context.active_object
    brake.rotation_euler = (math.radians(90), 0, 0)
    brake.data.materials.append(mat_brass)
    apply_uniform_clay_bevel(brake, width=0.03, segments=2)
    objs.append(brake)

    # 炮口侧向排气排焰槽 (Muzzle Vents)
    for vx in [-0.20, 0.20]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(vx, muzzle_y, 0.46 + bob_z))
        vent = bpy.context.active_object
        vent.scale = (0.05, 0.20, 0.16)
        vent.data.materials.append(mat_energy if is_deployed else mat_steel)
        objs.append(vent)

    # ==================== 5. 变形展开重型防盾面 (Deployable Bastion Mantlet) ====================
    if is_deployed:
        # 驻扎形态：两侧重盾向前呈弧形完全展开并锁死，包围正面和侧面，形成铜墙铁壁
        shield_specs = [
            (-0.48, 0.42, math.radians(-22)), # 左正面侧盾
            ( 0.48, 0.42, math.radians( 22)), # 右正面侧盾
            (-0.65, 0.05, math.radians(-55)), # 左侧翼重盾
            ( 0.65, 0.05, math.radians( 55))  # 右侧翼重盾
        ]
        for sx, sy, s_rot in shield_specs:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, sy, 0.48))
            shield = bpy.context.active_object
            shield.scale = (0.12, 0.58, 0.52)
            shield.rotation_euler = (0, 0, s_rot)
            shield.data.materials.append(mat_shield)
            apply_uniform_clay_bevel(shield, width=0.04, segments=2)
            objs.append(shield)

            # 防盾上的加固铆钉
            for rz in [0.32, 0.62]:
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.04, location=(sx * 1.08, sy * 1.08, rz))
                rivet = bpy.context.active_object
                rivet.data.materials.append(mat_brass)
                bpy.ops.object.shade_smooth()
                objs.append(rivet)
    else:
        # 移动形态：防盾服帖紧收在炮塔两侧
        for sx in [-0.55, 0.55]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.05, 0.46 + bob_z))
            folded_sh = bpy.context.active_object
            folded_sh.scale = (0.10, 0.70, 0.36)
            folded_sh.data.materials.append(mat_shield)
            apply_uniform_clay_bevel(folded_sh, width=0.03, segments=2)
            objs.append(folded_sh)

    return objs


def render_all_cannon_assets():
    """全量渲染巨炮坦克移动形态与驻扎固定炮形态资源"""
    print("==================================================================")
    print(" 正在启动 Blender Cycles 渲染管线：巨炮坦克 (Colossus Siege Tank) ")
    print("==================================================================")

    # 1. 敌方与友方移动形态 (enemy_cannon_f0..f5 / tank_cannon_f0..f5)
    for is_en, prefix in [(True, "enemy_cannon"), (False, "tank_cannon")]:
        for f in range(6):
            clear_scene()
            setup_render_settings(256, 256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
            objs = build_cannon_tank(frame=f, is_enemy=is_en, is_deployed=False)
            out_path = os.path.join(SPRITES_TANKS, f"{prefix}_f{f}.png")
            render_and_clean(objs, out_path)
            print(f"  [OK] 移动形态 {prefix} 帧 {f} -> {out_path}")

    # 2. 敌方与友方固定要塞炮变形形态 (enemy_cannon_deploy_f0..f5 / tank_cannon_deploy_f0..f5)
    for is_en, prefix in [(True, "enemy_cannon_deploy"), (False, "tank_cannon_deploy")]:
        for f in range(6):
            clear_scene()
            setup_render_settings(256, 256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
            objs = build_cannon_tank(frame=f, is_enemy=is_en, is_deployed=True)
            out_path = os.path.join(SPRITES_TANKS, f"{prefix}_f{f}.png")
            render_and_clean(objs, out_path)
            print(f"  [OK] 驻扎要塞炮形态 {prefix} 帧 {f} -> {out_path}")

    # 3. 默认静态图标
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_cannon_tank(frame=0, is_enemy=True, is_deployed=False)
    static_en = os.path.join(SPRITES_TANKS, "enemy_cannon.png")
    render_and_clean(objs, static_en)
    print(f"  [OK] 敌方默认图标 -> {static_en}")

    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    objs = build_cannon_tank(frame=0, is_enemy=False, is_deployed=False)
    static_pl = os.path.join(SPRITES_TANKS, "tank_cannon.png")
    render_and_clean(objs, static_pl)
    print(f"  [OK] 友方默认图标 -> {static_pl}")

    print("\n[SUCCESS] 巨炮坦克移动与固定要塞炮双形态 3D 渲染资产生成完毕！")


if __name__ == "__main__":
    render_all_cannon_assets()
