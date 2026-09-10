"""build_building_idle_anims.py — 有源建筑的待机循环动画 (各 6 帧)

    blender --background --python tools/build_building_idle_anims.py
    blender --background --python tools/build_building_idle_anims.py -- radar_station

输出:
    assets/sprites/buildings/radar_station_f0..f5.png   天线碟扇形扫描 + 顶灯明灭
    assets/sprites/buildings/emp_tower_f0..f5.png       电弧极绕塔旋转 + 线圈能量上行
    assets/sprites/buildings/factory_f0..f5.png         烟囱吐烟 + 天窗辉光呼吸

=== 为什么做这三个 ===

把每栋建筑的脚本挨个看了一遍: 绝大多数只有**事件动效** —— 被打了闪一下红、
开火闪一下、放下去弹一下。真正有"没事的时候也在动"的待机循环, 全项目只有
repair_station (自转)、shield_station (自转+脉动)、signal_jammer_tower (碟子
自转)、wormhole (自转) 四个, 外加水面/传送带/风机/履带这些地形与单位动效。

而这三栋的**建模注释里本来就写着它们会动**:

    build_radar_station.__doc__  "雷达站：六边形重型底座 + 旋转天线碟 + 警示灯"
    build_emp_tower.__doc__      "EMP电磁脉冲塔：三角形基座 + 旋转放电线圈 + ..."

建模的时候是按"这玩意儿在转"设计的, 只是从来没有人把那个转做出来。工厂同理:
它有两根烟囱和发光天窗, 却一缕烟都不冒。战场上水在流、风机在转、履带在滚,
这三栋钉在那里一动不动, 读起来像布景而不像设备。

=== 三条硬约束 (都是 base_eagle 待机动画那次踩出来的) ===

1. **地基逐帧必须完全一致。** 建筑压在固定格子上, 底座只要有一点点位移或缩放,
   播放时整栋楼就会看起来在地上漂 —— 而且因为周围的地形是静止的, 这个漂移会
   非常显眼。所以每段动画都只动"该动的那部分", 地基一帧都不碰。

2. **整段动画共用一个抖动种子。** apply_uniform_clay_bevel() 默认带
   jitter=0.014 的顶点抖动。如果按帧播种 (rerender_vfx.py 就是
   `reset_jitter_seed(JITTER_SEED + i)`), 地基的边缘每帧被捏成不一样的形状,
   播出来是整个基座的轮廓在沸腾 —— 恰好违反第 1 条。所以在函数里就地重置,
   而不是指望调用方。一段循环动画的逐帧一致性是**它自己的**性质。

3. **走包装器, 不重写几何。** 调属主的 build_radar_station() / build_emp_tower()
   / build_factory() 拿对象列表再做位移, 一行几何都不抄。理由同
   build_terrain_variants.py: 重复的几何会变成第二个会漂移的属主, 而这个仓库
   已经因为这件事吃过好几次亏 (见 CLAUDE.md "Stale build scripts")。

   包装器动手之前, 属主必须先能一比一复现已提交的静态图, 否则这 6 帧会连带把
   那张图**悄悄改样** —— 动画是新加的, 没有旧版可比, 改样不会有任何报错。
   qa_orphan_audit.py 里为这三条各加了一个条目, 实测 d_rgb 0.54~0.70。

4. **部件靠属性认, 不靠下标认。** 下标依赖属主的建模顺序, 属主中间插一个部件
   就会静默错位 (动到警示灯而不是天线碟), 而且不会报错。这里一律用坐标或材质名
   来认, 数目对不上就抛异常, 让属主的改动当场暴露, 而不是渲出一批动错部件的图。

=== 幅度是标定出来的, 不是拍脑袋 ===

参照现役循环动画的相邻帧整图 RGB 均差:

    tile_water 0.33 (最轻的环境动效) / roller_wall 1.55 / base_eagle 1.12 /
    bunker 3.62 / wind_blower 3.97 (旋转的风机, 最重)

鹰巢那次第一版只有 0.21 —— 比全项目最轻的动效还轻, 换算到 48px 显示尺寸不足
1 像素, 等于白做。这三段的目标区间取 [1.1, 4.5]: 雷达和 EMP 是**设备在工作**,
可以接近风机那一档; 工厂的烟要更柔一些。tools/test_building_idle_anims.gd
把这个区间钉成门禁。
"""

import math
import os
import sys

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_PROP,
)
from build_new_buildings_and_tanks import (
    build_radar_station,
    build_emp_tower,
    SPRITES_BUILDINGS,
)
from build_jammer_factory_assets import build_factory

## 每段动画自己的固定抖动种子 —— 全 6 帧共用, 见文件头第 2 条。
RADAR_IDLE_SEED = 8100
EMP_IDLE_SEED = 8200
FACTORY_IDLE_SEED = 8300


def _mat_is(obj, prefix):
    """材质名是否以 prefix 开头。

    用 startswith 而不是 == : create_clay_mat 里有一层材质缓存, 但
    clear_scene() 之后缓存可能失效并重建, 而 bpy 给重名材质自动加 `.001` 后缀。
    卡死等号会在第二帧开始莫名其妙地认不出部件。
    """
    if not obj.data or not getattr(obj.data, "materials", None):
        return False
    m = obj.data.materials[0]
    return bool(m) and m.name.startswith(prefix)


def _spin_z(obj, ang):
    """绕世界 Z 轴 (穿过原点) 转 ang 弧度 —— 位置和自身朝向一起转。

    只转朝向不转位置的话, 偏心的部件 (天线碟在 y=+0.30) 会原地打转而不是绕塔
    公转; 只转位置不转朝向的话, 碟子会平移着始终朝向同一边, 像被拖着走。
    """
    c, s = math.cos(ang), math.sin(ang)
    x, y = obj.location.x, obj.location.y
    obj.location.x = x * c - y * s
    obj.location.y = x * s + y * c
    obj.rotation_euler.z += ang


# ══════════════════════════════════════════════════════════════════
#  雷达站 —— 天线碟扇形扫描
# ══════════════════════════════════════════════════════════════════

def build_radar_station_idle(frame_idx, n_frames=6):
    """雷达站待机的一帧 —— 天线阵扇形扫描 + 顶部警示灯明灭。

    === 为什么是"扇形往复"而不是"整圈匀速转" ===

    6 帧转满一圈 = 每帧 60°。按 base_eagle 那档 0.13 秒/帧算就是 460°/秒, 而且
    每一帧之间跳 60° —— 在 48px 的显示尺寸上那不叫旋转, 那叫频闪, 眼睛只会看到
    碟子在几个位置之间瞬移。

    改成 `A*sin(phase)` 的扇形往复: 相邻帧最大跨度 A*(sin60°-sin0°) ≈ 0.87A,
    A=28° 时约 24°/帧, 读起来是连续的扫描而不是跳变。而且扇形扫描本身就是真实
    雷达的工作方式之一 (sector scan), 不是为了迁就帧数而编的动作。

    正弦还有一个附带好处: f5 -> f0 的跨度和别处一样大, 循环点不会突出来。用
    "转到底再倒回来"的锯齿就会在端点处出现两帧几乎不动、然后突然掉头。

    === 但光有正弦会掉两帧, 这是往复动画的通病 ===

    第一版只有扫描一个通道, 实测相邻帧 ΔRGB 是 `3.28 0.01 3.28 3.31 0.00 3.31`
    —— f1->f2 和 f4->f5 几乎没有变化, 6 帧里有 2 帧是白给的, 播出来每循环卡顿
    两次。

    原因是**正弦关于峰值对称**: 6 个均匀相位 (0° 60° 120° 180° 240° 300°) 的
    sin 值是 0, .866, .866, 0, -.866, -.866 —— f1 与 f2 同角度, f4 与 f5 同角度。
    这跟帧数无关, 任何偶对称的往复函数均匀采样都会成对撞上 (8 帧也一样)。

    解法是**再加一个奇对称的通道**: 角度走 sin, 另一个量走 cos。cos 在同样这
    6 个相位上是 1, .5, -.5, -1, -.5, .5 —— 恰好在 sin 撞车的地方岔开。

    这里让碟子"点头"来承担 cos: 碟面绕 boom 轴俯仰, 在正交俯视下就是碟子那个
    椭圆的短轴 (它的 scale.y) 变宽变窄。这既是真实雷达的仰角扫描, 又正好落在
    全图最大的那个运动部件上 —— 顶灯明灭其实也是 cos 驱动的, 但灯只有半径 0.10,
    换算到 48px 才 3 像素, 实测对整图均差的贡献只有 0.01, 撑不起这件事。
    """
    reset_jitter_seed(RADAR_IDLE_SEED)
    objs = build_radar_station()
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    # 旋转组: 天线臂 x2 + 碟 + 馈源 + 顶灯 (z >= 0.55)。
    # 六边形底座 (-0.10)、塔身 (0.22)、四角绿灯 (0.04) 全部留在原地。
    spin = [o for o in objs if o.location.z >= 0.55]
    if len(spin) != 5:
        raise RuntimeError(
            "[雷达站待机] 按 z>=0.55 只认出 %d 个旋转部件, 期望 5 个 "
            "(天线臂 x2 / 碟 / 馈源 / 顶灯) —— build_radar_station() 的建模大概"
            "改了, 请核对判据, 否则动画会动错部件" % len(spin))

    sweep = math.radians(28.0) * math.sin(phase)
    for o in spin:
        _spin_z(o, sweep)

    # 碟面俯仰 —— 走 cos, 把正弦撞车的那两对帧岔开, 见函数注释。
    # 碟子建模是 scale=(1.0, 0.38, 0.82) 的扁球, 短轴就是 Y, 所以直接乘 Y 分量:
    # 变宽 = 碟面抬起来正对天顶, 变窄 = 压低。
    dish = [o for o in objs if _mat_is(o, "m_rd_dish")]
    if len(dish) != 1:
        raise RuntimeError(
            "[雷达站待机] 按材质 m_rd_dish 认出 %d 个天线碟, 期望 1 个" % len(dish))
    dish[0].scale.y *= 1.0 + 0.55 * math.cos(phase)

    # 顶部警示灯明灭。相位比扫描早 90°, 于是"灯最亮"落在"碟子扫过正中"的时刻,
    # 两个通道读起来是同一台机器的同一个动作, 而不是各转各的。
    warn = [o for o in objs if _mat_is(o, "m_rd_warn")]
    if len(warn) != 1:
        raise RuntimeError(
            "[雷达站待机] 按材质 m_rd_warn 认出 %d 个警示灯, 期望 1 个" % len(warn))
    blink = 4.5 * (1.0 + 0.62 * math.sin(phase + math.pi * 0.5))
    warn[0].data.materials[0] = create_clay_mat(
        "m_rd_warn", (0.95, 0.22, 0.15, 1.0),
        emission=(1.0, 0.25, 0.10, 1.0), emission_str=blink)

    return objs


# ══════════════════════════════════════════════════════════════════
#  EMP 塔 —— 电弧极绕塔旋转 + 线圈能量上行
# ══════════════════════════════════════════════════════════════════

def build_emp_tower_idle(frame_idx, n_frames=6):
    """EMP 塔待机的一帧 —— 顶部电弧极绕塔公转 + 三层线圈依次亮起。

    === 120° 而不是 360°: 用三重对称换一个无缝循环 ===

    顶部是 3 个电弧极, 互成 120°。所以整组转过 120° 之后, 构型和起点**完全
    重合** —— 于是 6 帧只需要各转 20°, 就能得到一个严丝合缝的循环。要是照直
    转满 360°, 每帧就得跳 60°, 和雷达那边一样会读成频闪。

    对称性在这里是白拿的: 不是把动作压慢了将就, 而是这个几何本来就允许用更小的
    步长走完一个完整周期。

    === 线圈为什么不转 ===

    三层线圈是圆环 (torus), 圆环绕自己的轴转在图上**完全没有变化** —— 转了也
    白转。所以能量感改用"沿塔身上行的行波"来表达: 三层各带 120° 相位差做微小的
    竖直起伏, 看起来像有东西一层层往上走。这是把"这个部件适合怎么动"和"注释里
    写了它转"分开看的结果; 注释说的是设计意图, 具体动作得服从投影后的可见性。
    """
    reset_jitter_seed(EMP_IDLE_SEED)
    objs = build_emp_tower()
    if not objs:
        return objs

    # 顶部电弧组: 3 个放电球 + 3 根连接杆, 都在 z=0.90
    top = [o for o in objs if o.location.z > 0.85]
    if len(top) != 6:
        raise RuntimeError(
            "[EMP待机] 按 z>0.85 认出 %d 个顶部部件, 期望 6 个 (3 电弧球 + 3 连杆) "
            "—— build_emp_tower() 的建模大概改了" % len(top))

    # 放电线圈: 材质 m_em_coil 且在塔身高度以下 (连接杆同材质但在 0.90)
    coils = [o for o in objs if _mat_is(o, "m_em_coil") and o.location.z < 0.70]
    if len(coils) != 3:
        raise RuntimeError(
            "[EMP待机] 按材质 m_em_coil + z<0.70 认出 %d 层线圈, 期望 3 层" % len(coils))

    # 三重对称 -> 一个循环只需转 120°
    spin = (2.0 * math.pi / 3.0) * (frame_idx / float(n_frames))
    for o in top:
        _spin_z(o, spin)

    # 沿塔身上行的行波。0.022 是量出来的: 再大线圈会脱离塔身读成"环在往上飘",
    # 再小到 48px 下不足半像素。
    phase = 2.0 * math.pi * (frame_idx / float(n_frames))
    for k, coil in enumerate(sorted(coils, key=lambda o: o.location.z)):
        coil.location.z += 0.022 * math.sin(phase - k * (2.0 * math.pi / 3.0))

    # 电弧球辉光随公转呼吸
    glow = 5.5 * (1.0 + 0.45 * math.sin(phase))
    arc_mat = create_clay_mat("m_em_arc", (0.18, 0.55, 1.00, 1.0),
                              emission=(0.18, 0.55, 1.00, 1.0), emission_str=glow)
    for o in top:
        if _mat_is(o, "m_em_arc"):
            o.data.materials[0] = arc_mat

    return objs


# ══════════════════════════════════════════════════════════════════
#  工厂 —— 烟囱吐烟 + 天窗辉光
# ══════════════════════════════════════════════════════════════════

## 每根烟囱同时存在几缕烟。3 缕 + 6 帧 => 相位间隔正好 2 帧, 循环闭合。
FACTORY_PUFFS = 3


def build_factory_idle(frame_idx, n_frames=6):
    """工厂待机的一帧 —— 两根烟囱交替吐烟 + 天窗辉光呼吸。

    === 正交俯视下"烟往上飘"是看不见的 ===

    相机是正交俯视, Z 轴指向镜头。所以把烟往 +Z 挪**在画面上完全不动** —— 正交
    投影没有近大远小, 挪 Z 只影响遮挡关系和受光。这是这条管线里很容易想当然错
    的一点: 侧视思维下"上升"是天经地义的运动, 到了顶视就成了原地不动。

    所以烟的可见运动全部交给三件事: 半径涨大、沿 XY 往一个固定风向飘、以及末尾
    缩回零。三缕烟错开相位, 于是任何一帧都同时能看到"刚冒出来的小团"和"快散掉
    的大团", 读起来是连续的一股烟而不是一团东西在闪。

    === 烟必须真的散掉 ===

    末段把半径收回 0 而不是让它停在最大 —— 和爆炸序列同一条规矩 (见 CLAUDE.md
    "Explosion-type sequences must dissipate"): 一段以"最大最实的一团"收尾的
    动画, 循环回 f0 的时候会啪地消失, 那一下比不做动画还显眼。

    风向取 +X 并且行程压在 0.34: 烟囱在 x=-0.58, 涨到最大半径 0.30 时最远也才
    到 |−0.58+0.34|+0.30 = 0.54, 离半画幅 1.65 还很远, 不会被画幅裁掉。

    === 幅度是调过一次的: 第一版 0.60, 比水面还轻 ===

    第一版半径封顶 0.20、烟色 (0.72,0.70,0.68), 实测相邻帧 ΔRGB 只有 0.60 ——
    参照系里 tile_water 是 0.33、base_eagle 1.12、roller_wall 1.55、
    wind_blower 3.97、bunker 5.21, 也就是说它比全项目最轻的环境动效高不了多少,
    换算到 48px 显示尺寸几乎看不出在动。这跟鹰巢待机第一版栽的是同一个跟头:
    在 256px 的渲染图上看着挺明显, 一降到 48px 就没了。

    两个方向一起加: 半径封顶 0.20 -> 0.30 (烟团在画面上的面积翻一倍多), 烟色
    提亮到接近白 —— 屋顶本身是 (0.34,0.36,0.40) 的深灰, 烟压在上面靠的是明度差,
    原来那个 0.72 的灰跟屋顶差得不够远。
    """
    reset_jitter_seed(FACTORY_IDLE_SEED)
    objs = build_factory()
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    # 天窗辉光呼吸
    sky = [o for o in objs if _mat_is(o, "m_fac_sky")]
    if len(sky) != 2:
        raise RuntimeError(
            "[工厂待机] 按材质 m_fac_sky 认出 %d 块天窗, 期望 2 块" % len(sky))
    sky_mat = create_clay_mat(
        "m_fac_sky", (1.0, 0.80, 0.32, 1.0), emission=(1.0, 0.80, 0.32, 1.0),
        emission_str=3.2 * (1.0 + 0.38 * math.sin(phase)))
    for o in sky:
        o.data.materials[0] = sky_mat

    # 烟囱口辉光 —— 和天窗反相, 于是"炉子烧起来"和"车间亮起来"交替, 而不是
    # 整栋楼一起明一起暗 (那会读成有人在拉总闸)
    caps = [o for o in objs if _mat_is(o, "m_fac_chim_glow")]
    if len(caps) != 2:
        raise RuntimeError(
            "[工厂待机] 按材质 m_fac_chim_glow 认出 %d 个烟囱口, 期望 2 个" % len(caps))
    cap_mat = create_clay_mat(
        "m_fac_chim_glow", (1.0, 0.45, 0.15, 1.0), emission=(1.0, 0.45, 0.15, 1.0),
        emission_str=3.5 * (1.0 + 0.42 * math.sin(phase + math.pi)))
    for o in caps:
        o.data.materials[0] = cap_mat

    # 烟。位置直接取自烟囱口, 而不是把 (-0.58, ±0.32) 再抄一遍 —— 属主挪了烟囱,
    # 烟自己会跟着走。
    mat_smoke = create_clay_mat("m_fac_smoke", (0.90, 0.88, 0.86, 1.0),
                                roughness=0.92, mottle=0.14)
    for cap in caps:
        cx, cy = cap.location.x, cap.location.y
        for k in range(FACTORY_PUFFS):
            t = ((frame_idx / float(n_frames)) + k / float(FACTORY_PUFFS)) % 1.0
            # 半径: 涨到 t=0.62 见顶再收回 0, 保证末段真的散掉
            if t <= 0.62:
                r = 0.065 + (0.30 - 0.065) * (t / 0.62)
            else:
                r = 0.30 * (1.0 - (t - 0.62) / 0.38)
            if r < 0.012:
                continue
            bpy.ops.mesh.primitive_uv_sphere_add(
                radius=r,
                location=(cx + 0.34 * t, cy + 0.06 * math.sin(t * math.pi * 2.0),
                          0.95 + 0.45 * t))
            puff = bpy.context.active_object
            puff.data.materials.append(mat_smoke)
            bpy.ops.object.shade_smooth()
            objs.append(puff)

    return objs


# ══════════════════════════════════════════════════════════════════

# name -> (builder, 输出名模板, ortho_scale)
#
# 画幅必须和属主 main() 渲静态图时用的那一档一致, 否则这 6 帧会比静态图整体
# 大一圈或小一圈 —— 而 *_f0 和无后缀的静态图在游戏里是同一个精灵的两种取图路径
# (取不到帧就退回静态图), 尺寸对不上会在退化时突然跳一下。
# 实测口径见 qa_orphan_audit.py: radar/emp 是 PROP(2.7), factory 是 3.3。
GROUPS = {
    "radar_station": (build_radar_station_idle, "radar_station_f{i}.png", ORTHO_SCALE_PROP),
    "emp_tower":     (build_emp_tower_idle,     "emp_tower_f{i}.png",     ORTHO_SCALE_PROP),
    "factory":       (build_factory_idle,       "factory_f{i}.png",       ORTHO_SCALE_DEFAULT),
}

N_FRAMES = 6


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("-")] or sorted(GROUPS)
    unknown = [n for n in names if n not in GROUPS]
    if unknown:
        print("[ERROR] 不认识: %s" % ", ".join(unknown))
        print("        可选: %s" % ", ".join(sorted(GROUPS)))
        raise SystemExit(1)

    print("=" * 60)
    print("  建筑待机循环动画 (各 %d 帧)" % N_FRAMES)
    print("=" * 60)

    for name in names:
        builder, tmpl, ortho = GROUPS[name]
        print("\n[%s] 渲染 %d 帧 ..." % (name, N_FRAMES))
        for i in range(N_FRAMES):
            clear_scene()
            setup_render_settings(256, 256, samples=32)
            create_sokpop_lighting(ortho_scale=ortho)
            objs = builder(i, N_FRAMES)
            out = os.path.join(SPRITES_BUILDINGS, tmpl.format(i=i))
            render_and_clean(objs, out)
            print("  [OK] %s" % tmpl.format(i=i))

    print("\n" + "=" * 60)
    print("  完成 -> %s" % SPRITES_BUILDINGS)
    print("  别忘了: python tools/fix_sprite_mipmaps.py, 然后 --editor --quit 重导")


if __name__ == "__main__":
    main()
