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
    ORTHO_SCALE_PROP,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# 自爆爆炸专用画幅。比 ORTHO_SCALE_PROP(2.7) 宽, 因为这段动画最外圈要铺到
# 半径 1.63; 2.7 的半宽只有 1.35, 会把烟环齐齐切掉一圈。3.9 的半宽 1.95 留出
# 约 16% 余量。改这个数会等比缩放整段动画 —— 见 sokpop_common 里关于
# ORTHO_SCALE_* 是"承重常量"的说明。
ORTHO_SCALE_BLAST = 3.9

# 1. SUICIDE DEMOLITION TRUCK (enemy_suicide_truck_f0..f5.png)
def build_suicide_truck(frame=0):
    objs = []
    mat_cab = create_clay_mat("m_sui_cab", (0.92, 0.22, 0.18, 1.0), roughness=0.55) # Crimson Red Alert Truck
    mat_chassis = create_clay_mat("m_sui_chas", (0.16, 0.18, 0.20, 1.0), roughness=0.70)
    mat_ram = create_clay_mat("m_sui_ram", (0.85, 0.70, 0.15, 1.0), roughness=0.40) # Hazard Yellow Bullbar
    mat_wheel = create_clay_mat("m_sui_whl", (0.12, 0.12, 0.14, 1.0), roughness=0.80)
    mat_nuke = create_clay_mat("m_sui_nuke", (0.20, 0.95, 0.35, 1.0), emission=(0.20, 0.95, 0.35, 1.0), emission_str=4.5) # Glowing Toxic Core
    mat_cask = create_clay_mat("m_sui_cask", (0.28, 0.30, 0.35, 1.0), roughness=0.50)

    # 1. Heavy Armored 6-Wheel Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, -0.12))
    chas = bpy.context.active_object
    chas.scale = (1.10, 1.70, 0.35)
    chas.data.materials.append(mat_chassis)
    apply_uniform_clay_bevel(chas, width=0.05, segments=2)
    objs.append(chas)

    # 6 Wheels (3 left, 3 right) with frame rotation phase
    wheel_phase = (frame / 6.0) * math.pi * 2.0
    for wx in [-0.68, 0.68]:
        for wy in [-0.65, -0.10, 0.48]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=0.28, vertices=16, location=(wx, wy, -0.16))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), wheel_phase)
            wheel.data.materials.append(mat_wheel)
            apply_uniform_clay_bevel(wheel, width=0.03, segments=1)
            objs.append(wheel)

    # 2. Driver Armored Cab
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.45, 0.22))
    cab = bpy.context.active_object
    cab.scale = (1.00, 0.75, 0.55)
    cab.data.materials.append(mat_cab)
    apply_uniform_clay_bevel(cab, width=0.06, segments=2)
    objs.append(cab)

    # Spiked Heavy Battering Ram on front bumper
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.92, -0.05))
    ram = bpy.context.active_object
    ram.scale = (1.30, 0.20, 0.35)
    ram.data.materials.append(mat_ram)
    apply_uniform_clay_bevel(ram, width=0.03, segments=2)
    objs.append(ram)

    for sx in [-0.45, 0.0, 0.45]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.10, depth=0.32, vertices=12, location=(sx, 1.10, -0.05))
        spike = bpy.context.active_object
        spike.rotation_euler = (math.radians(90), 0, 0)
        spike.data.materials.append(mat_ram)
        apply_uniform_clay_bevel(spike, width=0.01, segments=1)
        objs.append(spike)

    # 3. Rear Massive Explosive Warhead Tank
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=1.05, vertices=24, location=(0, -0.38, 0.30))
    cask = bpy.context.active_object
    cask.rotation_euler = (math.radians(90), 0, 0)
    cask.data.materials.append(mat_cask)
    apply_uniform_clay_bevel(cask, width=0.04, segments=2)
    objs.append(cask)

    # Glowing Toxic Core Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.50, depth=0.35, vertices=24, location=(0, -0.38, 0.30))
    ring = bpy.context.active_object
    ring.rotation_euler = (math.radians(90), 0, 0)
    ring.data.materials.append(mat_nuke)
    objs.append(ring)

    return objs

# 2. MIRAGE TANK (enemy_mirage_f0..f5.png)
def build_mirage_tank(frame=0):
    objs = []
    mat_stealth = create_clay_mat("m_mir_body", (0.30, 0.55, 0.65, 1.0), roughness=0.45) # Prism French Cyan Blue
    mat_tread = create_clay_mat("m_mir_trd", (0.18, 0.20, 0.22, 1.0), roughness=0.70)
    mat_prism = create_clay_mat("m_mir_prism", (0.35, 0.95, 1.0, 1.0), emission=(0.35, 0.95, 1.0, 1.0), emission_str=3.8) # Glowing Prism Emitter
    mat_gun = create_clay_mat("m_mir_gun", (0.22, 0.24, 0.28, 1.0), roughness=0.35)

    # 1. Dual Track Chassis
    tread_phase = (frame / 6.0) * math.pi
    for tx in [-0.80, 0.80]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.15))
        tread = bpy.context.active_object
        tread.scale = (0.42, 1.65, 0.45)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.05, segments=2)
        objs.append(tread)

        for wy in [-0.50, 0.0, 0.50]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.44, vertices=16, location=(tx, wy, -0.15))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), tread_phase)
            wheel.data.materials.append(mat_tread)
            objs.append(wheel)

    # 2. Angled Stealth Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.08))
    hull = bpy.context.active_object
    hull.scale = (1.20, 1.35, 0.42)
    hull.data.materials.append(mat_stealth)
    apply_uniform_clay_bevel(hull, width=0.08, segments=2)
    objs.append(hull)

    # 3. Turret with Dual Camouflage Prisms
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.32, vertices=8, location=(0, -0.05, 0.38))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_stealth)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # Dual Mirage Optical Prism Nodes on turret sides
    for px in [-0.48, 0.48]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.25, vertices=6, location=(px, -0.05, 0.44))
        p = bpy.context.active_object
        p.data.materials.append(mat_prism)
        apply_uniform_clay_bevel(p, width=0.02, segments=1)
        objs.append(p)

    # 4. Long Thermal Disrupter Cannon
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=1.35, vertices=16, location=(0, 0.82, 0.38))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_gun)
    apply_uniform_clay_bevel(barrel, width=0.02, segments=2)
    objs.append(barrel)

    # Muzzle Prism Shroud
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.25, vertices=8, location=(0, 1.42, 0.38))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90), 0, 0)
    muzzle.data.materials.append(mat_prism)
    objs.append(muzzle)

    return objs

# 3. SUICIDE MUSHROOM BLAST VFX (vfx_suicide_blast_f0..f5.png)
# 自爆卡车的爆炸 —— 全场最大的一声响, 所以它得是一段动画, 不是一张图。
#
# 老版本只有*一张* vfx_suicide_blast.png, 靠 Godot 那边 tween 缩放来充当动画。
# 结果是: 整个游戏里唯一一个"存在意义就是爆炸"的敌人, 反而拥有最不动的爆炸。
# 而且那张图本身读不出爆炸 —— 正中一颗绿球, 外面八个橘瓣均匀排一圈, 加一圈
# 灰底盘, 看起来像一朵花或者辐射标志。
#
# 新的读法保留绿色, 但把它当成*会熄灭的核心闪光*而不是常驻的绿球: 卡车身上
# 那颗 mat_nuke 一直在发绿光 (见 build_suicide_truck), 所以"绿色的东西炸了"
# 是有前因的视觉连续性, 玩家能把爆炸和肇事者对上。绿只在前两帧, 之后被橘红
# 火球盖住, 最后剩毒烟。
#
# 尺寸上刻意比通用爆炸大一圈 —— 它的 AoE 是 84px (1.75 格), 画面必须对得上
# 伤害范围, 否则玩家学不会该躲多远。
#
# `green` 只作用于*内圈*, 外圈永远不绿 —— 前两版都栽在这上面。第一版
# green=1.0 把整团涂绿, f0/f1 渲成一颗光滑的绿色黏液球; 第二版把绿散进外圈,
# 结果绿橘相间, 读起来是迷彩布或者糖果, 还是不像爆炸。
#
# 绿必须*聚在中心*: 核心 + 内圈是毒光, 外壳一律橘红火焰。这样"绿色的东西在
# 中间烧完了"才是一句能被看懂的话 —— 而这正是这段动画要讲的事, 因为卡车身上
# 那颗 mat_nuke 一直在发绿光, 玩家能把爆炸和肇事者对上。
SUICIDE_BLAST_FRAMES = [
    # span    r_puff  n   inner green fire  core  glow  spikes spike_len
    dict(span=0.34, r_puff=0.30, n=8,  inner=0, green=1.00, fire=1.00, core=0.46, glow=4.0, spikes=8, spike_len=0.55),
    dict(span=0.68, r_puff=0.40, n=10, inner=6, green=0.85, fire=1.00, core=0.46, glow=3.4, spikes=8, spike_len=0.80),
    dict(span=1.02, r_puff=0.40, n=13, inner=7, green=0.55, fire=0.95, core=0.40, glow=2.2, spikes=5, spike_len=0.60),
    dict(span=1.22, r_puff=0.34, n=15, inner=6, green=0.15, fire=0.66, core=0.26, glow=1.0, spikes=0, spike_len=0.0),
    dict(span=1.32, r_puff=0.26, n=15, inner=0, green=0.00, fire=0.26, core=0.0,  glow=0.0, spikes=0, spike_len=0.0),
    dict(span=1.38, r_puff=0.18, n=11, inner=0, green=0.00, fire=0.00, core=0.0,  glow=0.0, spikes=0, spike_len=0.0),
]


def _blast_wobble(seed, span):
    """确定性的不规则抖动 —— 完美的圆环读起来是机械的。"""
    h = (seed * 2654435761) % 1000
    return (h / 1000.0 - 0.5) * span * 0.40


def build_suicide_blast_vfx(frame=0):
    objs = []
    cfg = SUICIDE_BLAST_FRAMES[frame]
    glow = cfg["glow"]

    mat_toxic = create_clay_mat(
        f"m_sui_fx_core{frame}", (0.42, 1.0, 0.48, 1.0),
        emission=(0.40, 1.0, 0.45, 1.0), emission_str=glow)
    mat_fire = create_clay_mat(
        f"m_sui_fx_fire{frame}", (1.0, 0.45, 0.10, 1.0),
        emission=(1.0, 0.48, 0.12, 1.0), emission_str=max(0.0, glow * 0.42))
    # 同通用爆炸: 别烧成奶白, 那读起来像个洞而不是高温
    mat_hot = create_clay_mat(
        f"m_sui_fx_hot{frame}", (1.0, 0.84, 0.32, 1.0),
        emission=(1.0, 0.86, 0.38, 1.0), emission_str=max(0.0, glow * 0.50))
    # 毒烟偏黄绿, 不是中性灰 —— 收尾这几帧也得让人知道刚才炸的是那辆绿卡车。
    # 明度不能压太低: 第一版用 (0.26,0.28,0.24), 在夜战和深色地形上直接糊成一片
    # 看不见的脏点。烟要能在深色背景上读出来。
    mat_smoke = create_clay_mat(f"m_sui_fx_smk{frame}", (0.74, 0.76, 0.62, 1.0), roughness=0.85)
    mat_dark  = create_clay_mat(f"m_sui_fx_drk{frame}", (0.46, 0.48, 0.38, 1.0), roughness=0.88)

    span = cfg["span"]
    n = cfg["n"]
    f_cut = int(cfg["fire"] * 10.0)
    g_cut = int(cfg["green"] * 10.0)
    for i in range(n):
        ang = i * (2.0 * math.pi / float(n)) + frame * 0.31
        d = span + _blast_wobble(i + frame * 23, span)
        r = cfg["r_puff"] * (1.0 + (0.18 if i % 3 == 0 else -0.11))
        # 外圈: 只有火和烟, 没有绿 (见上面表格的说明)
        if ((i * 7) % 10) < f_cut:
            mat = mat_hot if (glow > 2.0 and i % 6 == 0) else mat_fire
        else:
            mat = mat_dark if i % 3 == 0 else mat_smoke
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=r, location=(math.cos(ang) * d, math.sin(ang) * d, (i % 3 - 1) * 0.07))
        sph = bpy.context.active_object
        sph.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    # 内圈: 把中心填实 (否则 f2/f3 会渲成一串珠子围一个圈), 同时让团块凹凸不平
    for i in range(cfg["inner"]):
        ang = i * (2.0 * math.pi / float(cfg["inner"])) - frame * 0.44
        d = span * 0.45 + _blast_wobble(i * 3 + frame * 13, span) * 0.5
        r = cfg["r_puff"] * (0.92 if i % 2 == 0 else 0.78)
        # 内圈: 绿聚在这里
        slot = (i * 3) % 10
        if slot < g_cut:
            mat = mat_toxic
        elif slot < f_cut:
            mat = mat_fire
        else:
            mat = mat_smoke
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=r, location=(math.cos(ang) * d, math.sin(ang) * d, 0.05))
        sph = bpy.context.active_object
        sph.data.materials.append(mat)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    if cfg["core"] > 0.0:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=cfg["core"], location=(0, 0, 0.12))
        core = bpy.context.active_object
        # 核心是绿的一直到 f2 —— 绿色的"熄灭"就是这段动画的主线, 由核心讲,
        # 不是靠外壳。f3 之后核心已经烧成白热, 绿只剩烟里那点黄绿味。
        core.data.materials.append(mat_toxic if frame <= 2 else mat_hot)
        bpy.ops.object.shade_smooth()
        objs.append(core)

    for i in range(cfg["spikes"]):
        ang = i * (2.0 * math.pi / float(cfg["spikes"])) + frame * 0.42
        ln = cfg["spike_len"]
        # 尖端落在 span + ln (圆锥以中心定位), 便于直接对画幅半宽验出框
        d = span + ln * 0.5
        bpy.ops.mesh.primitive_cone_add(
            radius1=0.13, depth=ln,
            location=(math.cos(ang) * d, math.sin(ang) * d, 0))
        shard = bpy.context.active_object
        shard.rotation_euler = (math.radians(90), 0, ang + math.pi / 2)
        shard.data.materials.append(mat_toxic if frame <= 1 else mat_hot)
        apply_uniform_clay_bevel(shard, width=0.02, segments=2)
        objs.append(shard)

    return objs

# 4. MIRAGE CAMOUFLAGE SHIMMER VFX (vfx_mirage_shimmer.png)
def build_mirage_shimmer_vfx():
    objs = []
    mat_shimmer = create_clay_mat("m_mir_shim", (0.45, 0.90, 1.0, 0.85), emission=(0.45, 0.90, 1.0, 1.0), emission_str=4.0)
    mat_leaf = create_clay_mat("m_mir_leaf", (0.35, 0.78, 0.25, 1.0), roughness=0.60)

    # Hexagonal Cloaking Grid Prisms
    for i in range(6):
        ang = i * (math.pi / 3.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=0.12, vertices=6, location=(math.cos(ang) * 0.72, math.sin(ang) * 0.72, 0))
        hex_p = bpy.context.active_object
        hex_p.data.materials.append(mat_shimmer)
        apply_uniform_clay_bevel(hex_p, width=0.02, segments=1)
        objs.append(hex_p)

    # Center Camouflage Leaf Pattern
    bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=0.14, vertices=6, location=(0, 0, 0.05))
    leaf = bpy.context.active_object
    leaf.data.materials.append(mat_leaf)
    apply_uniform_clay_bevel(leaf, width=0.03, segments=1)
    objs.append(leaf)

    return objs

def main():
    print("==================================================")
    print(" Executing Suicide Truck & Mirage Asset Pipeline.. ")
    print("==================================================")

    # 1. Render Suicide Truck 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_suicide_truck(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_suicide_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Suicide Truck Frame {f} Rendered.")

    # 2. Render Mirage Tank 6-Frame Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_mirage_tank(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_mirage_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Mirage Tank Frame {f} Rendered.")

    # 3. Render Suicide Blast VFX (6 帧)
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_BLAST)
        objs = build_suicide_blast_vfx(frame=f)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"vfx_suicide_blast_f{f}.png"))
        print(f"[OK] Suicide Blast VFX Frame {f} Rendered.")

    # 4. Render Mirage Shimmer VFX
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_mirage_shimmer_vfx()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "vfx_mirage_shimmer.png"))
    print("[OK] Mirage Shimmer VFX Rendered.")

if __name__ == '__main__':
    main()
