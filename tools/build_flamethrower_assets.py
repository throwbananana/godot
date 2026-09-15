import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_TANK,
    ORTHO_SCALE_DEFAULT,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# ---------------------------------------------------------------------------
# FLAMETHROWER TANK (enemy_flame_f0..f5.png)
#
# 配色: 焦黑车体 + 黄铜燃料罐。
# 这是审计过全部现有配色之后剩下的空档 —— 敌方已占紫罗兰(basic)/青(fast)/
# 红(power)/绿(armor)/靛紫(warp)/红黄(suicide)/青灰(mirage), 玩家占黄橙绿蓝,
# 地形占赤陶/薰衣草灰/沙黄/冰蓝/树绿。
# 更要紧的是明度而不是色相: 上一轮做 qa_style_consistency.py 的 palette 检查时
# 实测过, enemy_missile 饱和度只有 16% 却在沙地上非常清楚 (深色车体, 明度差极大),
# 反倒是饱和度 44% 的中明度绿 enemy_armor 最容易糊进地形。所以这里刻意压低明度,
# 让它在任何地形上都靠明暗分离, 橙色交给火焰 VFX 去承担。
#
# 剪影上的识别点是"没有长炮管": 换成又粗又短的喷嘴 + 两个背在车体两侧的燃料罐。
# 玩家隔着半张地图就该看出"这个不能正面靠近"。
# 前方 = +Y (和 build_sokpop_tank 的炮管一致, 精灵朝上绘制)。
# ---------------------------------------------------------------------------
def build_flamethrower_tank(frame=0):
    objs = []
    # 车体是"烧焦的锈褐"而不是纯黑: 第一版把车体压到 (0.17,0.14,0.13), 和履带的
    # (0.11,0.10,0.11) 只差一点点, 渲出来整辆车糊成"两个黑块夹两个铜罐", 完全看不出
    # 是辆车。车体必须比履带亮一档才能分出层次, 同时仍远低于任何地形的明度。
    mat_hull = create_clay_mat("m_flm_hull", (0.34, 0.24, 0.19, 1.0), roughness=0.82)
    mat_tread = create_clay_mat("m_flm_trd", (0.10, 0.09, 0.10, 1.0), roughness=0.88)
    mat_brass = create_clay_mat("m_flm_brs", (0.78, 0.50, 0.16, 1.0), roughness=0.42)
    mat_brass_dk = create_clay_mat("m_flm_brsd", (0.52, 0.32, 0.10, 1.0), roughness=0.55)
    mat_nozzle = create_clay_mat("m_flm_noz", (0.30, 0.27, 0.28, 1.0), roughness=0.60)
    # 常明的引燃火 —— 即使在冷却期也亮着, 提示"这东西随时会喷"
    mat_pilot = create_clay_mat("m_flm_plt", (1.0, 0.62, 0.16, 1.0),
                                emission=(1.0, 0.55, 0.12, 1.0), emission_str=5.0)

    # 1. 履带底盘
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    for tx in [-0.78, 0.78]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.10))
        tread = bpy.context.active_object
        tread.scale = (0.40, 1.62, 0.50)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.06, segments=2)
        objs.append(tread)

        for wy in [-0.52, 0.0, 0.52]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.44, vertices=16,
                                                location=(tx, wy, -0.10))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), wheel_rot)
            wheel.data.materials.append(mat_brass_dk)
            objs.append(wheel)

        # 履带齿 —— 俯视下轮子完全被履带挡住, 只转轮子的话六帧看起来是静止的。
        # 把齿块沿 Y 平移一个齿距, 履带才有可见的爬行感。
        cleat_pitch = 0.36
        cleat_off = (frame / 6.0) * cleat_pitch
        for ci in range(-5, 6):
            cy = ci * cleat_pitch + cleat_off
            if abs(cy) > 0.80:
                continue
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, cy, 0.16))
            cleat = bpy.context.active_object
            cleat.scale = (0.44, 0.11, 0.10)
            cleat.data.materials.append(mat_brass_dk)
            objs.append(cleat)

    # 2. 低矮的焦黑车体 —— 压得比其它坦克扁, 强化"贴地推进"的观感
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.14))
    hull = bpy.context.active_object
    hull.scale = (1.10, 1.34, 0.40)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.10, segments=3)
    objs.append(hull)

    # 3. 两个黄铜燃料罐, 横躺在车体后半段 —— 主要的识别特征
    for tx in [-0.40, 0.40]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.27, depth=0.86, vertices=16,
                                            location=(tx, -0.42, 0.46))
        tank = bpy.context.active_object
        tank.rotation_euler = (math.radians(90), 0, 0)
        tank.data.materials.append(mat_brass)
        apply_uniform_clay_bevel(tank, width=0.05, segments=3)
        objs.append(tank)

        # 罐口端盖
        for cy in [-0.85, 0.01]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.29, depth=0.09, vertices=16,
                                                location=(tx, cy, 0.46))
            cap = bpy.context.active_object
            cap.rotation_euler = (math.radians(90), 0, 0)
            cap.data.materials.append(mat_brass_dk)
            objs.append(cap)

    # 4. 从燃料罐通到喷嘴的输油管
    for tx in [-0.40, 0.40]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=1.00, vertices=10,
                                            location=(tx * 0.62, 0.24, 0.52))
        pipe = bpy.context.active_object
        pipe.rotation_euler = (math.radians(90), 0, math.radians(-14 if tx > 0 else 14))
        pipe.data.materials.append(mat_brass_dk)
        objs.append(pipe)

    # 5. 又粗又短的喷嘴 —— 刻意不做长炮管, 这是剪影上最重要的区别
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.46, vertices=16,
                                        location=(0, 0.76, 0.50))
    noz = bpy.context.active_object
    noz.rotation_euler = (math.radians(90), 0, 0)
    noz.data.materials.append(mat_nozzle)
    apply_uniform_clay_bevel(noz, width=0.05, segments=3)
    objs.append(noz)

    # 喇叭口
    bpy.ops.mesh.primitive_cone_add(radius1=0.20, radius2=0.34, depth=0.30, vertices=16,
                                    location=(0, 1.06, 0.50))
    flare = bpy.context.active_object
    flare.rotation_euler = (math.radians(-90), 0, 0)
    flare.data.materials.append(mat_nozzle)
    objs.append(flare)

    # 6. 引燃火 —— 每帧轻微跳动, 让待机状态也有生命感
    pilot_r = 0.10 + 0.035 * math.sin(frame / 6.0 * 2.0 * math.pi)
    pilot_y = 1.20 + 0.03 * math.cos(frame / 6.0 * 2.0 * math.pi)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=pilot_r, location=(0, pilot_y, 0.50))
    pilot = bpy.context.active_object
    pilot.data.materials.append(mat_pilot)
    bpy.ops.object.shade_smooth()
    objs.append(pilot)

    return objs


# ---------------------------------------------------------------------------
# FLAME CONE (vfx_flame_f0..f3.png)
#
# 火焰画成朝 +Y 的锥形羽流, 由几团逐渐变大、逐渐变红的球构成 —— 和本项目其它
# VFX 一样是预渲染序列帧, 不用粒子系统 (VFXAnimator 全是序列帧)。
#
# 关键约束: 羽流必须*填满*画幅的纵向, 且根部贴着画幅底边。游戏里这张图会被
# 拉伸到"喷嘴 -> 射程末端"的长度, 如果上下留白, 火焰看起来就会从离喷嘴一段
# 距离的地方才开始 —— 这正是上一轮激光那个"射出点不对"的翻版。
# ---------------------------------------------------------------------------
def build_flame_cone(frame=0):
    objs = []
    # 白热 -> 橙 -> 深红, 越往前越冷越暗, 符合真实火焰也符合"末端伤害递减"的读法。
    #
    # 第一版是五个大球串成一条线, 渲出来轮廓平滑得像气球 —— 火焰的识别特征恰恰
    # 是*不规则的轮廓*, 光靠颜色渐变救不回来。改成每一段用一簇小球, 半径和位置
    # 都带相位偏移, 让边缘出现缺口和凸起。
    stages = [
        # (y,     r,    颜色(sRGB),            发光强度, 该段的小球数)
        (-1.00, 0.26, (1.00, 0.96, 0.78), 7.2, 2),
        (-0.62, 0.34, (1.00, 0.84, 0.34), 6.4, 3),
        (-0.20, 0.44, (1.00, 0.62, 0.16), 5.4, 4),
        (0.26,  0.50, (0.98, 0.42, 0.10), 4.4, 4),
        (0.74,  0.44, (0.90, 0.26, 0.08), 3.4, 3),
        (1.12,  0.28, (0.78, 0.18, 0.06), 2.6, 2),
    ]
    phase = frame / 4.0 * 2.0 * math.pi
    for i, (y, r, col, em, count) in enumerate(stages):
        mat = create_clay_mat(f"m_fcone_{frame}_{i}", col + (1.0,),
                              emission=col + (1.0,), emission_str=em,
                              roughness=0.9, mottle=0.0)
        for k in range(count):
            # 一簇里的小球横向铺开并各自抖动, 这才是不规则轮廓的来源
            spread = (k - (count - 1) / 2.0) / max(count - 1, 1) * 2.0   # -1..1
            wob = 0.72 + 0.34 * (0.5 + 0.5 * math.sin(phase + i * 1.7 + k * 2.3))
            bx = spread * r * 0.86 + 0.05 * math.sin(phase * 1.3 + i + k)
            by = y + 0.13 * math.cos(phase + i * 0.9 + k * 1.6)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r * wob, location=(bx, by, 0.0))
            blob = bpy.context.active_object
            blob.scale = (1.0, 1.24, 1.0)   # 沿前进方向拉长, 火舌不是一串圆球
            blob.data.materials.append(mat)
            bpy.ops.object.shade_smooth()
            objs.append(blob)

        # 甩离主体的火星, 进一步打散轮廓
        if i >= 2:
            for s in (-1, 1):
                sp_x = s * (r * 1.18 + 0.06 * math.sin(phase + i))
                sp_y = y + 0.16 * math.cos(phase * 1.1 + i * s)
                sp_r = 0.07 + 0.04 * (0.5 + 0.5 * math.sin(phase + i * s * 1.4))
                bpy.ops.mesh.primitive_uv_sphere_add(radius=sp_r, location=(sp_x, sp_y, 0.0))
                spark = bpy.context.active_object
                spark.data.materials.append(mat)
                bpy.ops.object.shade_smooth()
                objs.append(spark)

    return objs


def main():
    reset_jitter_seed(4200)

    print(">>> 1. Rendering Flamethrower Tank (enemy_flame_f0..f5)...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for f in range(6):
        objs = build_flamethrower_tank(frame=f)
        render_and_clean(objs, os.path.join(SPRITES_TANKS, f"enemy_flame_f{f}.png"))
        print(f"[OK] enemy_flame_f{f}.png")

    print(">>> 2. Rendering Flame Cone VFX (vfx_flame_f0..f3)...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    # 画幅按羽流的实际跨度收紧 (y 从 -1.25 到 +1.42, 约 2.7 单位), 让火焰纵向填满
    create_sokpop_lighting(ortho_scale=3.05)
    for f in range(4):
        objs = build_flame_cone(frame=f)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"vfx_flame_f{f}.png"))
        print(f"[OK] vfx_flame_f{f}.png")

    print(">>> FLAMETHROWER ASSETS DONE")


if __name__ == '__main__':
    main()
