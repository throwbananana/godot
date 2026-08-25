"""build_wooden_wall_assets.py — 可移动木墙 (Movable Wooden Wall / Timber Barricade) 3D 建模与 Cycles 黏土渲染管线

木墙 (Wooden Wall):
  - 材质结构：重型横向与纵向原木圆木 (Round Cedar/Oak Timber Logs) + 侧翼削尖防御桩
  - 加固件：熟铁箍带 (Forged Iron Straps) + 锻造方头铆钉 (Heavy Bolts) + 粗麻绳交叉绑扎 (Rope Lashings)
  - 结构强化：对角斜拉支撑木梁 (Cross Bracing Timber)
  - 底部移动滑靴：双侧防卡滑轨木撬 (Heavy Sled Skids)，使其支持接触推移与撞击滑行
  - 动效与阶段：
      1. 基础图标与静止展示图 (wooden_wall.png)
      2. 4 帧移动/推移动态形变与木构应力动效 (wooden_wall_f0..f3.png)
      3. 3 级结构耐久破损状态图 (wooden_wall_dmg0..dmg2.png)
      4. 4 帧木屑崩解飞溅爆炸特效 (wood_debris_f0..f3.png)
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
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)


def build_wooden_wall(frame: int = 0, damage_stage: int = 0):
    """构建可移动木墙 3D 模型

    frame: 0..3 控制移动挤压、滑行晃动与受力弹性
    damage_stage: 0=完好(Intact), 1=受损裂痕(Cracked), 2=重创破损碎裂(Splintered)
    """
    objs = []

    # 1. 材质定义 (Sokpop 原木黏土与锻铁着色)
    col_wood_bark  = srgb_to_linear((0.54, 0.34, 0.18, 1.0)) # 树皮深棕
    col_wood_core  = srgb_to_linear((0.74, 0.52, 0.28, 1.0)) # 原木截面年轮暖黄
    col_wood_brace = srgb_to_linear((0.64, 0.44, 0.22, 1.0)) # 交叉斜撑木条
    col_iron_strap = srgb_to_linear((0.26, 0.27, 0.30, 1.0)) # 加固锻铁箍带
    col_bolt       = srgb_to_linear((0.85, 0.65, 0.22, 1.0)) # 黄铜/硬铁铆钉
    col_rope       = srgb_to_linear((0.76, 0.68, 0.48, 1.0)) # 麻绳系带
    col_skid       = srgb_to_linear((0.40, 0.26, 0.14, 1.0)) # 底部滑靴木橇
    col_moss       = srgb_to_linear((0.36, 0.50, 0.24, 1.0)) # 边角青苔细节

    mat_bark  = create_clay_mat(f"m_ww_bark_{frame}_{damage_stage}", col_wood_bark, roughness=0.75)
    mat_core  = create_clay_mat(f"m_ww_core_{frame}_{damage_stage}", col_wood_core, roughness=0.65)
    mat_brace = create_clay_mat(f"m_ww_brc_{frame}_{damage_stage}", col_wood_brace, roughness=0.70)
    mat_strap = create_clay_mat(f"m_ww_stp_{frame}_{damage_stage}", col_iron_strap, roughness=0.45)
    mat_bolt  = create_clay_mat(f"m_ww_blt_{frame}_{damage_stage}", col_bolt, roughness=0.40)
    mat_rope  = create_clay_mat(f"m_ww_rop_{frame}_{damage_stage}", col_rope, roughness=0.80)
    mat_skid  = create_clay_mat(f"m_ww_skd_{frame}_{damage_stage}", col_skid, roughness=0.80)
    mat_moss  = create_clay_mat(f"m_ww_mos_{frame}_{damage_stage}", col_moss, roughness=0.85)

    # 动态位移与弹性晃动 (Frame animation)
    wobble_y = math.sin(frame * (math.pi / 2.0)) * 0.04 if frame > 0 else 0.0
    tilt_x = math.sin(frame * (math.pi / 2.0)) * 0.05 if frame > 0 else 0.0
    squash_z = 1.0 + math.cos(frame * math.pi) * 0.03 if frame > 0 else 1.0

    # 根节点空物体用于统一形变控制
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, wobble_y, 0))
    root = bpy.context.active_object
    root.rotation_euler = (tilt_x, 0, 0)
    root.scale = (1.0, 1.0, squash_z)
    objs.append(root)

    # ==================== 1. 底部滑动撬板 (Base Sled Skids) ====================
    # 允许木墙在受到撞击和推力时顺畅滑移
    for sx in [-0.55, 0.55]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0, -0.28))
        skid = bpy.context.active_object
        skid.scale = (0.24, 1.40, 0.14)
        skid.data.materials.append(mat_skid)
        apply_uniform_clay_bevel(skid, width=0.04, segments=2)
        skid.parent = root
        objs.append(skid)

        # 滑橇前后两端倾斜弧口
        for sy in [-0.65, 0.65]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, sy, -0.22))
            tip = bpy.context.active_object
            tip.scale = (0.22, 0.20, 0.16)
            tip.rotation_euler = (math.radians(-25 if sy > 0 else 25), 0, 0)
            tip.data.materials.append(mat_skid)
            apply_uniform_clay_bevel(tip, width=0.03, segments=2)
            tip.parent = root
            objs.append(tip)

    # ==================== 2. 两侧竖向重型支撑原木柱 (Vertical Timber Posts) ====================
    for px in [-0.60, 0.60]:
        h_scale = 1.0 if damage_stage < 2 or px < 0 else 0.75 # 破损阶段右柱削减
        bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.35 * h_scale, vertices=14,
                                             location=(px, 0, 0.35 * h_scale - 0.10))
        post = bpy.context.active_object
        post.data.materials.append(mat_bark)
        apply_uniform_clay_bevel(post, width=0.04, segments=3)
        post.parent = root
        objs.append(post)

        # 顶部木桩截面圆环
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.04, vertices=12,
                                             location=(px, 0, 0.35 * h_scale - 0.10 + 0.68 * h_scale))
        post_top = bpy.context.active_object
        post_top.data.materials.append(mat_core)
        post_top.parent = root
        objs.append(post_top)

        # 削尖防御桩头 (Sharpened Stake Spike)
        if damage_stage < 2 or px < 0:
            bpy.ops.mesh.primitive_cone_add(radius1=0.20, depth=0.35, vertices=12,
                                            location=(px, 0, 0.35 * h_scale - 0.10 + 0.78 * h_scale))
            spike = bpy.context.active_object
            spike.data.materials.append(mat_bark)
            apply_uniform_clay_bevel(spike, width=0.03, segments=2)
            spike.parent = root
            objs.append(spike)

    # ==================== 3. 主体 3 根横向咬合原木 (Horizontal Interlocking Logs) ====================
    # Log 1: 底层原木
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=1.46, vertices=14, location=(0, 0, -0.10))
    log_bot = bpy.context.active_object
    log_bot.rotation_euler = (0, math.radians(90), 0)
    log_bot.data.materials.append(mat_bark)
    apply_uniform_clay_bevel(log_bot, width=0.04, segments=3)
    log_bot.parent = root
    objs.append(log_bot)

    # Log 2: 中层原木 (受损时有裂口/断损)
    mid_depth = 1.46 if damage_stage < 1 else 1.32
    bpy.ops.mesh.primitive_cylinder_add(radius=0.21, depth=mid_depth, vertices=14, location=(0, 0, 0.22))
    log_mid = bpy.context.active_object
    log_mid.rotation_euler = (0, math.radians(90), math.radians(2 if damage_stage > 0 else 0))
    log_mid.data.materials.append(mat_bark)
    apply_uniform_clay_bevel(log_mid, width=0.04, segments=3)
    log_mid.parent = root
    objs.append(log_mid)

    # Log 3: 顶层原木 (严重受损时断为两半且露出尖锐碎屑)
    if damage_stage == 2:
        # 碎裂顶木左半截
        bpy.ops.mesh.primitive_cylinder_add(radius=0.19, depth=0.65, vertices=12, location=(-0.35, 0, 0.52))
        log_top_l = bpy.context.active_object
        log_top_l.rotation_euler = (0, math.radians(82), math.radians(5))
        log_top_l.data.materials.append(mat_bark)
        apply_uniform_clay_bevel(log_top_l, width=0.03, segments=2)
        log_top_l.parent = root
        objs.append(log_top_l)

        # 飞裂木刺 (Splinters)
        for sp_x, sp_z, ang in [(-0.02, 0.54, 35), (0.08, 0.48, -25), (0.28, 0.44, 45)]:
            bpy.ops.mesh.primitive_cone_add(radius1=0.08, depth=0.32, vertices=8, location=(sp_x, 0, sp_z))
            splinter = bpy.context.active_object
            splinter.rotation_euler = (0, math.radians(90 + ang), 0)
            splinter.data.materials.append(mat_core)
            splinter.parent = root
            objs.append(splinter)
    else:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.19, depth=1.46, vertices=14, location=(0, 0, 0.54))
        log_top = bpy.context.active_object
        log_top.rotation_euler = (0, math.radians(90), 0)
        log_top.data.materials.append(mat_bark)
        apply_uniform_clay_bevel(log_top, width=0.04, segments=3)
        log_top.parent = root
        objs.append(log_top)

    # 横向原木两端年轮截面
    for lx in [-0.73, 0.73]:
        for lz in [-0.10, 0.22]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.03, vertices=12, location=(lx, 0, lz))
            cap = bpy.context.active_object
            cap.rotation_euler = (0, math.radians(90), 0)
            cap.data.materials.append(mat_core)
            cap.parent = root
            objs.append(cap)

    # ==================== 4. 正反面对角 X 型斜撑加固木梁 (Cross Bracing) ====================
    for brace_side in [-0.22, 0.22]:
        # 斜撑 A
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, brace_side, 0.22))
        br_a = bpy.context.active_object
        br_a.scale = (0.16, 0.08, 0.96)
        br_a.rotation_euler = (0, math.radians(40), 0)
        br_a.data.materials.append(mat_brace)
        apply_uniform_clay_bevel(br_a, width=0.02, segments=2)
        br_a.parent = root
        objs.append(br_a)

        # 斜撑 B
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, brace_side, 0.22))
        br_b = bpy.context.active_object
        br_b.scale = (0.16, 0.08, 0.96)
        br_b.rotation_euler = (0, math.radians(-40), 0)
        br_b.data.materials.append(mat_brace)
        apply_uniform_clay_bevel(br_b, width=0.02, segments=2)
        br_b.parent = root
        objs.append(br_b)

        # 中心固定大铁栓
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.12, vertices=10, location=(0, brace_side * 1.1, 0.22))
        c_bolt = bpy.context.active_object
        c_bolt.rotation_euler = (math.radians(90), 0, 0)
        c_bolt.data.materials.append(mat_bolt)
        c_bolt.parent = root
        objs.append(c_bolt)

    # ==================== 5. 双道重型锻铁箍带与固定铆钉 (Iron Straps & Rivets) ====================
    strap_z_list = [0.05, 0.40]
    for sz in strap_z_list:
        if damage_stage == 2 and sz == 0.40:
            # 顶部箍带断裂效果
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.30, 0, sz))
            st_broken = bpy.context.active_object
            st_broken.scale = (0.75, 0.48, 0.07)
            st_broken.rotation_euler = (0, 0, math.radians(-6))
            st_broken.data.materials.append(mat_strap)
            apply_uniform_clay_bevel(st_broken, width=0.02, segments=2)
            st_broken.parent = root
            objs.append(st_broken)
            continue

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, sz))
        strap = bpy.context.active_object
        strap.scale = (1.48, 0.46, 0.07)
        strap.data.materials.append(mat_strap)
        apply_uniform_clay_bevel(strap, width=0.02, segments=2)
        strap.parent = root
        objs.append(strap)

        # 箍带上的坚固锻铁铆钉
        for bx in [-0.55, -0.22, 0.22, 0.55]:
            for by in [-0.24, 0.24]:
                bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.08, vertices=8, location=(bx, by, sz))
                b_obj = bpy.context.active_object
                b_obj.rotation_euler = (math.radians(90), 0, 0)
                b_obj.data.materials.append(mat_bolt)
                b_obj.parent = root
                objs.append(b_obj)

    # ==================== 6. 麻绳捆扎与青苔点缀 (Rope Binding & Moss Details) ====================
    for rx in [-0.58, 0.58]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.24, minor_radius=0.04, location=(rx, 0, 0.06))
        rp = bpy.context.active_object
        rp.data.materials.append(mat_rope)
        rp.parent = root
        objs.append(rp)

    # 底部青苔
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(-0.52, -0.22, -0.20))
    moss = bpy.context.active_object
    moss.scale = (1.2, 0.8, 0.5)
    moss.data.materials.append(mat_moss)
    bpy.ops.object.shade_smooth()
    moss.parent = root
    objs.append(moss)

    return objs


def build_wood_debris_effect(frame_idx: int):
    """构建受损击碎时的木屑木刺飞溅特效 (Wood Splinter Debris VFX 4 Frames)"""
    objs = []
    col_bark   = srgb_to_linear((0.54, 0.34, 0.18, 1.0))
    col_splint = srgb_to_linear((0.78, 0.56, 0.30, 1.0))
    col_iron   = srgb_to_linear((0.26, 0.27, 0.30, 1.0))
    col_dust   = srgb_to_linear((0.85, 0.78, 0.65, 0.8))

    mat_bark   = create_clay_mat(f"m_wdeb_b_{frame_idx}", col_bark)
    mat_splint = create_clay_mat(f"m_wdeb_s_{frame_idx}", col_splint)
    mat_iron   = create_clay_mat(f"m_wdeb_i_{frame_idx}", col_iron)
    mat_dust   = create_clay_mat(f"m_wdeb_d_{frame_idx}", col_dust, roughness=0.90)

    # 膨胀扩散与衰减
    dist = 0.22 + frame_idx * 0.32
    scale_factor = max(0.15, 0.95 - frame_idx * 0.18)

    # 1. 8 根四散飞溅的尖锐木刺与原木碎块
    for i in range(8):
        ang = i * (2.0 * math.pi / 8.0) + frame_idx * 0.20
        d = dist * (0.80 + (i % 3) * 0.20)
        lx = math.cos(ang) * d
        ly = math.sin(ang) * d
        lz = math.sin(i * 1.5) * 0.15

        if i % 2 == 0:
            # 细长木刺 (Pointed Splinter)
            bpy.ops.mesh.primitive_cone_add(radius1=0.10 * scale_factor, depth=0.55 * scale_factor,
                                            location=(lx, ly, lz))
            sp = bpy.context.active_object
            sp.rotation_euler = (math.radians(rand_rot := (i * 45)), math.radians(30), ang)
            sp.data.materials.append(mat_splint)
            apply_uniform_clay_bevel(sp, width=0.02, segments=2)
            objs.append(sp)
        else:
            # 粗原木块 (Chunk of Log)
            bpy.ops.mesh.primitive_cube_add(size=0.28 * scale_factor, location=(lx, ly, lz))
            ck = bpy.context.active_object
            ck.rotation_euler = (math.radians(i * 30), math.radians(i * 60), 0)
            ck.data.materials.append(mat_bark)
            apply_uniform_clay_bevel(ck, width=0.03, segments=2)
            objs.append(ck)

    # 2. 飞脱的锻铁铆钉与碎铁片
    for i in range(3):
        ang = (i * 2.1) + frame_idx * 0.4
        d = dist * 1.15
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08 * scale_factor, depth=0.12 * scale_factor, vertices=8,
                                             location=(math.cos(ang)*d, math.sin(ang)*d, 0.05))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_iron)
        objs.append(bolt)

    # 3. 伴生飞扬的陶泥木尘 (Wood Dust Puffs)
    if frame_idx < 3:
        for i in range(4):
            ang = i * (math.pi / 2.0) + 0.35
            d = dist * 0.65
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22 * scale_factor,
                                                location=(math.cos(ang)*d, math.sin(ang)*d, -0.05))
            puff = bpy.context.active_object
            puff.data.materials.append(mat_dust)
            bpy.ops.object.shade_smooth()
            objs.append(puff)

    return objs


def render_all_wooden_wall_assets():
    """全量渲染木墙所有动效、破坏阶段、基础图标与飞溅特效"""
    print("================================================================")
    print(" 正在启动 Blender Cycles 渲染管线：可移动木墙 (Wooden Wall) 3D 模型 ")
    print("================================================================")

    # 1. 渲染基础静态/热键栏图标 (wooden_wall.png)
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_wooden_wall(frame=0, damage_stage=0)
    static_path = os.path.join(SPRITES_BUILDINGS, "wooden_wall.png")
    render_and_clean(objs, static_path)
    print(f"[OK] 基础木墙图标渲染完成 -> {static_path}")

    # 2. 渲染 4 帧移动/推移动态形变与应力动效 (wooden_wall_f0..f3.png)
    for f in range(4):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = build_wooden_wall(frame=f, damage_stage=0)
        f_path = os.path.join(SPRITES_BUILDINGS, f"wooden_wall_f{f}.png")
        render_and_clean(objs, f_path)
        print(f"[OK] 移动动效帧 {f} 渲染完成 -> {f_path}")

    # 3. 渲染 3 级耐久破坏状态图 (wooden_wall_dmg0..dmg2.png)
    for dmg in range(3):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = build_wooden_wall(frame=0, damage_stage=dmg)
        dmg_path = os.path.join(SPRITES_BUILDINGS, f"wooden_wall_dmg{dmg}.png")
        render_and_clean(objs, dmg_path)
        print(f"[OK] 破损状态阶段 {dmg} 渲染完成 -> {dmg_path}")

    # 4. 渲染 4 帧木屑木刺崩解破坏特效 (wood_debris_f0..f3.png)
    for ef in range(4):
        clear_scene()
        setup_render_settings(256, 256, samples=24)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        objs = build_wood_debris_effect(frame_idx=ef)
        ef_path = os.path.join(SPRITES_EFFECTS, f"wood_debris_f{ef}.png")
        render_and_clean(objs, ef_path)
        print(f"[OK] 木屑破坏特效帧 {ef} 渲染完成 -> {ef_path}")

    print("\n[SUCCESS] 木墙 3D 建模与全套渲染资产生成完毕！")


if __name__ == "__main__":
    render_all_wooden_wall_assets()
