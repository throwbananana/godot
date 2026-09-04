import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")

for folder in [SPRITES_EFFECTS, SPRITES_TILES]:
    os.makedirs(folder, exist_ok=True)

# 鹰巢本体的建模属于 unified —— 这里只做待机位移, 不重写几何。
from build_all_sokpop_assets_unified import build_sokpop_eagle  # noqa: E402

# 渲染管线统一在 sokpop_common —— 见该文件顶部说明。
from sokpop_common import (  # noqa: E402
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    ORTHO_SCALE_DEFAULT,
    create_clay_mat,
    apply_uniform_clay_bevel as apply_bevel,
    reset_jitter_seed,
    render_and_clean as _render_and_clean,
)


def create_lighting(ortho_scale=ORTHO_SCALE_DEFAULT):
    create_sokpop_lighting(ortho_scale=ortho_scale)


def render_and_clean(objects, out_path):
    _render_and_clean(objects, out_path, label="Rendered Animation Asset")

# ==================== 1. 开火枪口火花 (MUZZLE FLASH 6 FRAMES) ====================

def build_muzzle_flash(frame_idx):
    objs = []
    mat_core = create_clay_mat(f"m_mf_c_{frame_idx}", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=2.5)
    mat_ring = create_clay_mat(f"m_mf_r_{frame_idx}", (0.98, 0.55, 0.18, 1.0), emission=(0.98, 0.55, 0.18, 1.0), emission_str=1.8)
    mat_smoke = create_clay_mat(f"m_mf_sm_{frame_idx}", (0.85, 0.82, 0.78, 1.0))

    scale_mult = [0.55, 1.25, 1.10, 0.90, 0.65, 0.40][frame_idx]
    rot = frame_idx * 0.35

    if frame_idx < 4:
        # Center Clay Fireball
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45 * scale_mult, location=(0, 0, 0))
        sph = bpy.context.active_object
        sph.data.materials.append(mat_core)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

        # 4-6 Fluffy Clay Starburst Spikes
        num_spikes = 6 if frame_idx in [1, 2] else 4
        for i in range(num_spikes):
            ang = rot + i * (2.0 * math.pi / float(num_spikes))
            bpy.ops.mesh.primitive_cone_add(radius1=0.20 * scale_mult, depth=0.75 * scale_mult,
                                            location=(math.cos(ang)*0.42*scale_mult, math.sin(ang)*0.42*scale_mult, 0))
            cone = bpy.context.active_object
            cone.rotation_euler = (0, math.radians(90), ang)
            cone.data.materials.append(mat_ring)
            apply_bevel(cone, width=0.03, segments=2, jitter=0.0)
            objs.append(cone)
    else:
        # Fading smoke puffs for late frames
        for i in range(4):
            ang = rot + i * (math.pi / 2.0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.25 * scale_mult,
                                                location=(math.cos(ang)*0.35*scale_mult, math.sin(ang)*0.35*scale_mult, 0))
            puff = bpy.context.active_object
            puff.data.materials.append(mat_smoke)
            bpy.ops.object.shade_smooth()
            objs.append(puff)

    return objs

# ==================== 2. 受击飞溅陶泥碎屑 (CLAY DEBRIS 6 FRAMES) ====================

def build_clay_debris(frame_idx):
    objs = []
    mat_clay = create_clay_mat(f"m_deb_{frame_idx}", (0.92, 0.48, 0.28, 1.0))
    mat_white = create_clay_mat(f"m_deb_w_{frame_idx}", (0.98, 0.85, 0.45, 1.0))
    mat_dark = create_clay_mat(f"m_deb_d_{frame_idx}", (0.55, 0.35, 0.22, 1.0))

    dist = 0.18 + frame_idx * 0.25
    scale_factor = max(0.18, 0.95 - frame_idx * 0.14)

    mats = [mat_clay, mat_white, mat_dark]
    for i in range(8):
        ang = i * (2.0 * math.pi / 8.0) + frame_idx * 0.25
        d = dist * (0.75 + (i % 3) * 0.25)
        r = (0.16 if i % 2 == 0 else 0.11) * scale_factor
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(ang)*d, math.sin(ang)*d, 0))
        sp = bpy.context.active_object
        sp.data.materials.append(mats[i % 3])
        bpy.ops.object.shade_smooth()
        objs.append(sp)

    return objs

# ==================== 3. 护盾力场泡泡 (SHIELD BUBBLE 8 SMOOTH FRAMES) ====================

def build_shield_bubble(frame_idx):
    objs = []
    mat_ring = create_clay_mat(f"m_sh_{frame_idx}", (0.28, 0.88, 0.78, 1.0), emission=(0.28, 0.88, 0.78, 1.0), emission_str=2.0)
    mat_spark = create_clay_mat(f"m_sh_sp_{frame_idx}", (0.72, 0.98, 0.95, 1.0), emission=(0.72, 0.98, 0.95, 1.0), emission_str=2.2)

    # 8-Frame Ultra-Smooth Rotational Pulse (45 degrees per step)
    pulse_scale = 1.25 + math.sin(frame_idx * (math.pi / 4.0)) * 0.08
    rot = frame_idx * (math.pi / 4.0)

    # Outer Torus Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=pulse_scale, minor_radius=0.12, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # 4 Orbiting Energy Beads
    for i in range(4):
        ang = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(math.cos(ang)*pulse_scale, math.sin(ang)*pulse_scale, 0))
        bead = bpy.context.active_object
        bead.data.materials.append(mat_spark)
        bpy.ops.object.shade_smooth()
        objs.append(bead)

    return objs

# ==================== 4. 等离子冲击波 (SHOCKWAVE 6 FRAMES) ====================

def build_shockwave(frame_idx):
    objs = []
    mat_wave = create_clay_mat(f"m_sw_{frame_idx}", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.2)
    rad = 0.28 + frame_idx * 0.20
    thick = max(0.025, 0.12 - frame_idx * 0.016)

    bpy.ops.mesh.primitive_torus_add(major_radius=rad, minor_radius=thick, location=(0, 0, 0))
    tor = bpy.context.active_object
    tor.data.materials.append(mat_wave)
    bpy.ops.object.shade_smooth()
    objs.append(tor)

    # Secondary inner energy ring on early-to-mid frames
    if 1 <= frame_idx <= 3:
        mat_inner = create_clay_mat(f"m_sw_in_{frame_idx}", (0.75, 0.95, 1.0, 1.0), emission=(0.75, 0.95, 1.0, 1.0), emission_str=1.8)
        bpy.ops.mesh.primitive_torus_add(major_radius=rad * 0.70, minor_radius=thick * 0.65, location=(0, 0, 0))
        tor_in = bpy.context.active_object
        tor_in.data.materials.append(mat_inner)
        bpy.ops.object.shade_smooth()
        objs.append(tor_in)

    return objs

# ==================== 5. 砖块击碎尘埃烟团 (DUST PUFF 6 FRAMES) ====================

# 和爆炸同一类毛病、同一个修法: 老版本 scale_factor 和 dist 都是单调递增
# (0.35->1.25 / 0.12->1.02), 于是尘埃越飘越*大*, 最后两帧变成六颗分得很开、
# 带明显球面明暗的大球 —— 读起来是沙滩球, 不是扬尘。
#
# 尘埃的物理直觉正好相反: 它应该越飘越散、越飘越薄。所以 r_puff 从 f2 起
# 反向收缩, 个数增加, 总墨量 (n * r_puff^2) 一路下降。
DUST_FRAMES = [
    # dist  r_puff  n
    dict(dist=0.10, r_puff=0.26, n=5),
    dict(dist=0.26, r_puff=0.30, n=6),
    dict(dist=0.44, r_puff=0.28, n=8),
    dict(dist=0.62, r_puff=0.22, n=9),
    dict(dist=0.78, r_puff=0.16, n=10),
    dict(dist=0.92, r_puff=0.11, n=8),
]


def build_dust_puff(frame_idx):
    objs = []
    mat_dust = create_clay_mat(f"m_dp_{frame_idx}", (0.85, 0.78, 0.72, 1.0))
    mat_dust_dark = create_clay_mat(f"m_dp_d_{frame_idx}", (0.65, 0.58, 0.52, 1.0))
    cfg = DUST_FRAMES[frame_idx]

    num_spheres = cfg["n"]
    for i in range(num_spheres):
        ang = i * (2.0 * math.pi / float(num_spheres)) + frame_idx * 0.22
        # 每颗错开一点距离, 免得渲成一个标准圆环
        d = cfg["dist"] * (1.0 + (0.18 if i % 3 == 0 else -0.12))
        r = cfg["r_puff"] * (1.0 if i % 2 == 0 else 0.78)
        mat_curr = mat_dust if i % 2 == 0 else mat_dust_dark
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(ang)*d, math.sin(ang)*d, 0))
        puff = bpy.context.active_object
        puff.data.materials.append(mat_curr)
        bpy.ops.object.shade_smooth()
        objs.append(puff)

    return objs

# ==================== 6. 基地受损晕厥表情 (BASE DAMAGED) ====================

def build_base_damaged():
    objs = []
    mat_ped = create_clay_mat("m_bd_p", (0.85, 0.80, 0.74, 1.0))
    mat_chick = create_clay_mat("m_bd_c", (0.98, 0.78, 0.25, 1.0))
    mat_beak = create_clay_mat("m_bd_b", (0.98, 0.52, 0.15, 1.0))
    mat_blush = create_clay_mat("m_bd_bl", (0.98, 0.42, 0.52, 1.0))
    mat_spiral = create_clay_mat("m_bd_sp", (0.2, 0.2, 0.25, 1.0))
    mat_patch = create_clay_mat("m_bd_pch", (0.95, 0.88, 0.75, 1.0))
    mat_patch_cross = create_clay_mat("m_bd_pchr", (0.90, 0.35, 0.35, 1.0))

    # Marble Pedestal
    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.35, vertices=16, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.data.materials.append(mat_ped)
    apply_bevel(ped, width=0.12, segments=3)
    objs.append(ped)

    # Dizzy Chick Body
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(0, 0.05, 0.65))
    body = bpy.context.active_object
    body.data.materials.append(mat_chick)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    # Drooped Wings (Shocked)
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(sign * 0.75, 0.05, 0.55))
        w = bpy.context.active_object
        w.scale = (0.5, 1.0, 0.7)
        w.rotation_euler = (0, 0, math.radians(sign * -55))
        w.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(w)

    # Beak Open
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.35, vertices=16, location=(0, 0.85, 0.65))
    beak = bpy.context.active_object
    beak.rotation_euler = (math.radians(90), 0, 0)
    beak.data.materials.append(mat_beak)
    apply_bevel(beak, width=0.06, segments=2)
    objs.append(beak)

    # Cute Forehead Bandage (Cross Patch)
    for (px, py, sx, sy) in [(0.22, 0.45, 0.32, 0.12), (0.22, 0.45, 0.12, 0.32)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 1.35))
        pch = bpy.context.active_object
        pch.scale = (sx, sy, 0.06)
        pch.rotation_euler = (math.radians(25), math.radians(20), math.radians(15))
        pch.data.materials.append(mat_patch)
        apply_bevel(pch, width=0.02, segments=2)
        objs.append(pch)

    # Cartoon Dizzy Spiral Eyes
    for sx in [-0.28, 0.28]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.05, location=(sx, 0.72, 0.82))
        eye = bpy.context.active_object
        eye.rotation_euler = (math.radians(90), 0, 0)
        eye.data.materials.append(mat_spiral)
        bpy.ops.object.shade_smooth()
        objs.append(eye)

        # Blush
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(sx * 1.35, 0.68, 0.62))
        bl = bpy.context.active_object
        bl.data.materials.append(mat_blush)
        bpy.ops.object.shade_smooth()
        objs.append(bl)

    return objs

## 鹰巢待机动画的固定抖动种子。见函数内的说明 —— 全 6 帧共用同一个值。
EAGLE_IDLE_JITTER_SEED = 7100


def build_base_eagle_idle(frame_idx, n_frames=6):
    """鹰巢待机动画的一帧 —— 呼吸起伏 + 双翼微振 + 眼神光轻闪。

    为什么要给它做动画: 鹰巢是整局游戏的防守核心, 玩家全程都在盯着它, 而它
    一直是**一张完全静止的单图**。战场上其它东西 (水面、传送带、风机、坦克履带)
    全都在动, 唯独要保护的那个不动 —— 读起来像块布景, 不像"活的、会没的东西"。

    === 底座逐帧必须完全一致 ===

    这是这段动画唯一的硬约束。鹰巢压在固定的格子上 (main.gd::_spawn_base_and_walls
    把它摆在 cols 5-7 x rows 11-12), 底座只要有一点点位移或缩放, 播放时整个
    基地就会看起来在地上漂 —— 而且因为周围五块砖是静止的, 这个漂移会非常显眼。
    所以这里**只动底座以上的部分**, 底座本身一帧都不碰。

    === 走包装器, 不重写几何 ===

    调属主的 build_sokpop_eagle(False) 拿到对象列表再做位移, 一行几何都不抄。
    理由同 build_terrain_variants.py: 重复的几何会变成第二个会漂移的属主。

    翅膀靠**坐标**认而不是靠下标认: 下标依赖属主的建模顺序, 属主插一个部件就
    会静默错位 (动到眼睛而不是翅膀, 而且不会报错)。翅膀是全身唯一 |x| > 0.5 的
    部件, 用这个判据; 找不到正好两片就抛异常, 让属主的改动当场暴露而不是渲出
    一批错误的动画。
    """
    # **整段动画必须用同一个抖动种子。**
    #
    # apply_uniform_clay_bevel() 默认带 jitter=0.014 的顶点抖动, 而
    # rerender_vfx.py 是按 `reset_jitter_seed(JITTER_SEED + i)` 逐帧播种的 ——
    # 于是底座的边缘每一帧被捏成不一样的形状。实测底座外圈 (r 88~104px, 小鸟
    # 够不到的地方) 的 alpha 掩码逐帧要变 160~240 个像素, 而且四个象限都在变
    # (排除了"是小鸟的投影在动"这个解释)。播放出来就是整个基座的轮廓在沸腾,
    # 比小鸟本身的动静还大 —— 恰好违反了本函数唯一的硬约束。
    #
    # 在这里就地重置而不是去改调用方: 一段循环动画的逐帧一致性是**它自己的**
    # 性质, 不该取决于谁来渲、怎么播种。
    reset_jitter_seed(EAGLE_IDLE_JITTER_SEED)

    objs = build_sokpop_eagle(False)
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    # === 幅度是标定出来的, 不是拍的 ===
    #
    # 拿现役的循环动画做参照 (相邻帧整图 RGB 均差的中位数):
    #   tile_water 0.33 (最轻的环境动效) / roller_wall 1.55 / bunker 3.62 /
    #   wind_blower 3.97 (旋转的风机, 最重)
    # 第一版 dz=0.05 只有 0.21 —— **比全项目最轻的动效还轻**, 换算到 48px
    # 显示尺寸不足 1 像素, 等于白做。现在落在水面和滚墙之间: 鹰巢是待机呼吸,
    # 不该跟机器一样显眼, 但也必须看得见。
    #
    # 三个通道叠加, 而不是把单一的起伏量拉大: 光靠竖直位移要做到同样的可见度
    # 得挪到 3~4 像素, 那就读成"鹰在原地跳"了。位移 + 扇翅 + 呼吸缩放各出一点,
    # 总的可见度够, 每一项都还在"轻微"的范围内。
    dz = 0.16 * math.sin(phase)                        # ≈ 2.3px @48
    wing_extra = math.radians(10.0) * math.sin(phase + 0.7)
    breathe = 1.0 + 0.030 * math.sin(phase + math.pi * 0.5)

    pedestal = objs[0]
    wings = [o for o in objs[1:]
             if abs(o.location.x) > 0.5 and o.location.z > 0.4]
    if len(wings) != 2:
        raise RuntimeError(
            f"[鹰巢待机] 按 |x|>0.5 只认出 {len(wings)} 片翅膀, 期望 2 片 —— "
            f"build_sokpop_eagle() 的建模大概改了, 请核对判据, 否则动画会动错部件")

    # 呼吸缩放的支点放在底座顶面 (z=0.175) 而不是小鸟的重心 —— 支点在脚下,
    # 缩放读起来是"鼓起来"; 支点在重心的话上下同时胀缩, 读成整只鸟在忽大忽小。
    PIVOT = (0.0, 0.05, 0.175)

    for o in objs:
        if o is pedestal:
            continue          # 底座一帧都不动, 见函数注释
        o.location = (
            PIVOT[0] + (o.location.x - PIVOT[0]) * breathe,
            PIVOT[1] + (o.location.y - PIVOT[1]) * breathe,
            PIVOT[2] + (o.location.z - PIVOT[2]) * breathe + dz,
        )
        o.scale = (o.scale.x * breathe, o.scale.y * breathe, o.scale.z * breathe)
        if o in wings:
            # 翅膀比身体多一点行程, 并绕 Z 轴微扇 —— 顶视下扇动只能靠这个轴,
            # 绕 X/Y 转在正交俯视里几乎看不出来。
            o.location.z += dz * 0.6
            o.rotation_euler.z += wing_extra * (1.0 if o.location.x > 0 else -1.0)

    return objs


def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)

    print(">>> Rendering Sokpop Animations & VFX (All 6+ Frames)...")
    # 1. Muzzle Flash (6 frames)
    for i in range(6):
        objs = build_muzzle_flash(i)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"muzzle_flash_{i}.png"))

    # 2. Clay Debris (6 frames)
    for i in range(6):
        objs = build_clay_debris(i)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"clay_debris_{i}.png"))

    # 3. Shield Bubble (8 frames)
    for i in range(8):
        objs = build_shield_bubble(i)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"shield_bubble_{i}.png"))

    # 4. Shockwave (6 frames)
    for i in range(6):
        objs = build_shockwave(i)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"shockwave_{i}.png"))

    # 5. Dust Puff (6 frames)
    for i in range(6):
        objs = build_dust_puff(i)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"dust_puff_{i}.png"))

    # 6. Damaged Base Eagle
    objs = build_base_damaged()
    render_and_clean(objs, os.path.join(SPRITES_TILES, "base_damaged.png"))

    # 7. 鹰巢待机动画 (6 帧循环)。
    #    base_eagle.png 保持不动 —— 它是 base_eagle.gd 取不到帧序列时的兜底,
    #    也是 unified 那边的产物, 不该由这个脚本覆盖。
    for i in range(6):
        objs = build_base_eagle_idle(i)
        render_and_clean(objs, os.path.join(SPRITES_TILES, f"base_eagle_f{i}.png"))

    print("All Sokpop Clay Animations Rendered Successfully!")

if __name__ == "__main__":
    main()
