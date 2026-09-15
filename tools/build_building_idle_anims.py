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
    apply_uniform_clay_bevel,
    srgb_to_linear,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_PROP,
)
from build_new_buildings_and_tanks import (
    build_radar_station,
    build_emp_tower,
    build_command_post,
    build_ammo_depot,
    build_sniper_nest,
    SPRITES_BUILDINGS,
)
from build_jammer_factory_assets import build_factory

## 每段动画自己的固定抖动种子 —— 全 6 帧共用, 见文件头第 2 条。
RADAR_IDLE_SEED = 8100
EMP_IDLE_SEED = 8200
FACTORY_IDLE_SEED = 8300
COMMAND_POST_IDLE_SEED = 8400
AMMO_DEPOT_IDLE_SEED = 8500
SNIPER_NEST_IDLE_SEED = 8600


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


## 与 sokpop_common.create_clay_mat 的 emission_peak 默认值一致。
EMISSION_PEAK = 0.85


def _pulse_str(em_col, u, lo=0.38):
    """把 0..1 的脉动量 u 映射成一个**不会被钳掉**的自发光强度。

    === 这个函数存在的理由: 全项目的自发光脉动通道原来一个都没生效 ===

    create_clay_mat 末尾有一道防过曝钳位:

        peak = max(线性化后的 emission 三通道)
        if peak * emission_str > emission_peak:      # emission_peak = 0.85
            emission_str = emission_peak / peak

    也就是说, 对任何线性峰值为 1.0 的颜色 (纯红/纯蓝/带 1.0 通道的暖黄, 本
    项目的发光件基本都是), **任何大于 0.85 的强度都会被压成同一个 0.85**。

    而现役三段待机动画给的强度是:

        radar   警示灯   4.5 * (1 ± 0.62)  = 1.71 ~ 7.29
        emp     电弧     5.5 * (1 ± 0.45)  = 3.03 ~ 7.98
        factory 天窗     3.2 * (1 ± 0.38)  = 1.98 ~ 4.42
        factory 烟囱口   3.5 * (1 ± 0.42)  = 2.03 ~ 4.97

    整个区间都在钳位线以上 —— 于是逐帧算出来的强度全都被压成 0.85, **四个
    "明灭 / 呼吸"通道逐帧完全没有变化**。这不是幅度不够, 是恒等于零。

    佐证是 factory 那串逐帧读数 `0.36 0.36 0.36 0.36 0.36 0.36`: 六个数一位
    小数都不差, 说明画面上只有烟 (纯几何) 在动, 两个辉光通道贡献恰好为 0。
    CLAUDE.md 里已经写过这个判读法 —— "一个在动画每一帧上都完全相同的 QA
    读数, 说明它量的东西根本没被动画碰到"。radar 的注释把顶灯的 0.01 归因于
    "灯只有 3 像素太小了", 真正的原因是它的亮度压根没变过。

    所以脉动必须做在**钳位以内**: 上界取 emission_peak / peak, 在 [lo, 1.0]
    的比例区间里摆。lo 默认 0.38 —— 再低灯就读成熄灭而不是变暗。
    """
    peak = max(srgb_to_linear(em_col)[:3])
    ceiling = EMISSION_PEAK / max(peak, 1e-6)
    return ceiling * (lo + (1.0 - lo) * max(0.0, min(1.0, u)))


def _tri(frame_idx, n_frames):
    """等步长三角波, 一个循环走 -1 -> +1 -> -1。

    === 往复动画不该用正弦, 这是撞帧问题的根治办法 ===

    6 帧均匀采相位时, sin 的取值是 0, .866, .866, 0, -.866, -.866 —— f1 与 f2
    同值、f4 与 f5 同值, 每循环白给两帧。这跟帧数无关: **任何偶对称函数均匀
    采样都会关于峰值成对撞上**。

    现役做法是再挂一个 cos 通道去填那两个坑 (雷达站的碟面俯仰)。那管用, 但要
    求两个通道的**幅度量级相当** —— 碉堡这边就翻过车: 枪架横扫贡献 0.37, 枪口
    指示灯只贡献 0.05, 比值 13%, 照样判卡帧。想靠加大指示灯来配平, 它就会大到
    喧宾夺主 (第一版正是一颗大蓝球插在枪杆上, 整个碉堡读成棒棒糖)。

    三角波直接绕开这件事: 相邻步长恒为 2/(n/2) —— n=6 时六个 Δ 全都是 0.667,
    一个都不撞。代价是端点处方向瞬时反转, 对**机械扫描** (雷达扇扫、枪架搜索)
    恰好是对的读法; 旗帜那种自然摆动仍然留给正弦。

    test_idle_anims.gd 的报错文案里写的"要么加一个二倍频/显式表格通道, 要么改
    成单调推进的整圈旋转"—— 三角波就是那个"显式表格"。
    """
    u = (frame_idx % n_frames) / float(n_frames)
    return -1.0 + 2.0 * (2.0 * u if u <= 0.5 else 2.0 * (1.0 - u))


def _spin_about(obj, cx, cy, ang):
    """绕过 (cx, cy) 的竖直轴转 ang 弧度 —— 位置和自身朝向一起转。

    只转朝向不转位置的话, 偏心的部件 (天线碟在 y=+0.30) 会原地打转而不是绕塔
    公转; 只转位置不转朝向的话, 碟子会平移着始终朝向同一边, 像被拖着走。

    轴心可指定, 是因为不是每个旋转部件都绕画面中心转: 旗帜绕的是旗杆
    (-0.38, -0.02), 碉堡枪架绕的是射孔 (0, 0.42)。拿原点当轴心去转旗帜, 旗子
    会绕着楼中心公转一圈, 而不是在旗杆上摆。

    注意 rotation_euler 的默认顺序是 'XYZ', 矩阵为 Rz·Ry·Rx —— 所以往 .z 上加
    角度是在**世界 Z** 上左乘一个偏航, 对已经绕 X 转了 90° 的枪架同样成立。
    """
    c, s = math.cos(ang), math.sin(ang)
    x, y = obj.location.x - cx, obj.location.y - cy
    obj.location.x = cx + x * c - y * s
    obj.location.y = cy + x * s + y * c
    obj.rotation_euler.z += ang


def _spin_z(obj, ang):
    """绕世界 Z 轴 (穿过原点) 转 —— _spin_about 的轴心在原点的特例。"""
    _spin_about(obj, 0.0, 0.0, ang)


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
    # 走 _pulse_str 而不是直接给一个大数 —— 原来那句 `4.5 * (1 ± 0.62)` 全程
    # 在 create_clay_mat 的钳位线以上, 逐帧被压成同一个 0.85, 这盏灯从来没有
    # 真的闪过。详见 _pulse_str 的注释。
    warn_em = (1.0, 0.25, 0.10, 1.0)
    warn[0].data.materials[0] = create_clay_mat(
        "m_rd_warn", (0.95, 0.22, 0.15, 1.0), emission=warn_em,
        emission_str=_pulse_str(warn_em, 0.5 + 0.5 * math.sin(phase + math.pi * 0.5)))

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

    # 电弧球辉光随公转呼吸 (强度走 _pulse_str, 原来的 5.5*(1±0.45) 全被钳平)
    arc_em = (0.18, 0.55, 1.00, 1.0)
    arc_mat = create_clay_mat("m_em_arc", (0.18, 0.55, 1.00, 1.0), emission=arc_em,
                              emission_str=_pulse_str(arc_em, 0.5 + 0.5 * math.sin(phase)))
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
    sky_em = (1.0, 0.80, 0.32, 1.0)
    sky_mat = create_clay_mat(
        "m_fac_sky", (1.0, 0.80, 0.32, 1.0), emission=sky_em,
        emission_str=_pulse_str(sky_em, 0.5 + 0.5 * math.sin(phase)))
    for o in sky:
        o.data.materials[0] = sky_mat

    # 烟囱口辉光 —— 和天窗反相, 于是"炉子烧起来"和"车间亮起来"交替, 而不是
    # 整栋楼一起明一起暗 (那会读成有人在拉总闸)
    caps = [o for o in objs if _mat_is(o, "m_fac_chim_glow")]
    if len(caps) != 2:
        raise RuntimeError(
            "[工厂待机] 按材质 m_fac_chim_glow 认出 %d 个烟囱口, 期望 2 个" % len(caps))
    cap_em = (1.0, 0.45, 0.15, 1.0)
    cap_mat = create_clay_mat(
        "m_fac_chim_glow", (1.0, 0.45, 0.15, 1.0), emission=cap_em,
        emission_str=_pulse_str(cap_em, 0.5 + 0.5 * math.sin(phase + math.pi)))
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
#  指挥部 —— 旗帜迎风 + 通信天线阵旋转
# ══════════════════════════════════════════════════════════════════

## 旗杆与天线杆的位置, 取自 build_command_post() 的建模坐标。
## 写成常量而不是就地硬编码, 是因为这两个数**必须**和属主一致: 轴心偏了,
## 旗子就不是在杆上摆而是绕着楼公转。
CP_POLE = (-0.38, -0.02)
CP_ANT = (0.44, 0.0)


def build_command_post_idle(frame_idx, n_frames=6):
    """指挥部待机的一帧 —— 旗帜绕旗杆摆动 + 天线阵旋转 + 窗户呼吸。

    === 为什么挑这栋 ===

    它的建模注释写着"多角形主楼 + **旗杆** + **通信天线** + 加固裙边", 三件会动
    的东西造出来了却一件都没动。一面不飘的旗子比没有旗子更显眼。

    === 俯视正交下, 旗帜该怎么"飘" ===

    相机是俯视, 所以侧视思维里的"旗子上下翻卷"完全看不见 (同 build_factory_idle
    的烟)。俯视下一面旗的可见运动只有两件事:

      1. **绕旗杆偏航** —— 旗面在 XY 平面里扫, 这是最大的那个通道;
      2. **迎风鼓起** —— 旗面本来是 y 向只有 0.02 的一片薄板, 鼓起来就是这个
         厚度变大。0.02 -> 0.064 在 256px 上是 4px -> 12px, 是真的看得见。

    这两件事恰好还解决了往复动画的撞帧问题, 见下。

    === 两个通道必须一个走 sin 一个走 cos ===

    6 帧均匀采相位, sin 的取值是 0, .866, .866, 0, -.866, -.866 —— f1 与 f2
    同值、f4 与 f5 同值, 于是每循环有两帧原地不动 (雷达站第一版就栽在这里,
    实测 `3.28 0.01 3.28 3.31 0.00 3.31`)。cos 在这 6 个相位上是
    1, .5, -.5, -1, -.5, .5, 它的**逐帧跨度在 sin 撞车的那两处恰好取到最大值**,
    正好把坑填上。所以: 偏航走 sin, 鼓起走 cos。

    === 天线阵为什么是单调整圈转, 而且只转 180° ===

    横杆是个长条, **绕自己中心转 180° 后与自身重合** (2 重对称)。所以一个完整
    循环只需要转 180°, 每帧 30° —— 而不是转满 360° 每帧跳 60°, 那在 48px 下
    是频闪不是旋转。这跟 EMP 塔用 3 重对称把每帧压到 20° 是同一招: 对称性是
    白拿的, 不是把动作放慢来将就帧数。

    单调旋转还有个好处: 它根本不会有上面那种撞帧问题 —— 撞帧是**偶对称**函数
    的毛病, 匀速旋转是单调的。

    三根横杆各错开 25°, 于是俯视下读成一个张开的天线阵而不是一根棍子。错开量
    刻意**不取 60°**: 3 根杆错开 60°、每帧转 30° 的话, 整组构型在 f0/f2/f4 会
    完全重合 (集合 {0,60,120} 与 {60,120,180=0} 相同), 6 帧里有 3 帧是白给的。
    """
    reset_jitter_seed(COMMAND_POST_IDLE_SEED)
    objs = build_command_post()
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    # ── 旗帜 ──
    flag = [o for o in objs if _mat_is(o, "m_cp_flag")]
    if len(flag) != 1:
        raise RuntimeError(
            "[指挥部待机] 按材质 m_cp_flag 认出 %d 面旗帜, 期望 1 面 "
            "—— build_command_post() 的建模大概改了" % len(flag))
    # 旗面加长 1.4 倍。原长 0.38 在 48px 下只有 6.8 像素 —— 比旗杆粗不了多少,
    # 摆得再起劲也看不出是一面旗。同天线横杆, 只在待机帧里加长, 静态图不动。
    # 加长后旗尖离原点最远约 0.32 (旗杆在 x=-0.38, 旗面朝 +X 伸, 即朝画面中心),
    # 远在地基环带 r>=0.74 之外, 不会被门禁判成地基在动。
    flag[0].scale.x *= 1.4
    _spin_about(flag[0], CP_POLE[0], CP_POLE[1],
                math.radians(32.0) * math.sin(phase))
    # 鼓起: 1.0 (贴杆垂下) -> 4.6 (完全迎风)。旗面被倒角烘过缩放, 所以这里的
    # scale 是在已烘进网格的 0.02 上再乘。
    #
    # 第一版偏航 24° / 鼓起 3.2 倍, 实测整段只有 0.14 px/帧, 勉强压在门禁下限
    # 0.12 上; 更要命的是逐帧读数 `0.20 0.06 0.14 0.14 0.07 0.21` —— f1->f2 与
    # f4->f5 那两处正是 sin 撞车的位置, 说明 cos 通道 (鼓起 + 窗户) 只贡献了
    # 0.06, 没能把坑填上。这栋楼的八边形底盘有 r=0.92 (87px), 归一化的分母很大,
    # 旗子那点面积必须给够才抬得动。
    flag[0].scale.y *= 1.0 + 3.6 * (0.5 + 0.5 * math.cos(phase))

    # ── 通信天线阵 ──
    # 横杆没有走 apply_uniform_clay_bevel (属主里只 append 没倒角), 所以它保留
    # 着建模时的 scale (0.22, 0.02, 0.02); 天线主杆倒过角, transform_apply 把
    # 缩放烘进网格后 scale 归 1。拿 scale.x 认部件正好把两者分开, 而且不依赖
    # 属主的建模顺序。
    bars = [o for o in objs
            if _mat_is(o, "m_cp_ant") and abs(o.scale.x - 0.22) < 1e-3]
    if len(bars) != 3:
        raise RuntimeError(
            "[指挥部待机] 按材质 m_cp_ant + scale.x≈0.22 认出 %d 根天线横杆, "
            "期望 3 根 —— 属主的建模或倒角调用大概改了" % len(bars))
    spin = math.pi * (frame_idx / float(n_frames))   # 2 重对称 -> 每循环 180°
    for k, bar in enumerate(sorted(bars, key=lambda o: o.location.z)):
        # 横杆原长 0.22 (48px 下才 4 像素), 转起来基本看不见。拉到 1.45 倍让
        # 天线阵在显示尺寸上真的扫得动 —— 这是待机帧里的加长, 静态图不受影响。
        bar.scale.x *= 1.45
        _spin_about(bar, CP_ANT[0], CP_ANT[1], spin + math.radians(25.0 * k))

    # ── 窗户呼吸 ──
    # 只改自发光, 不动几何 —— 窗户在 r≈0.84 (地基环带里), 动几何会被待机门禁
    # 判成"地基在动"。改材质不影响 alpha 掩码, 所以是安全的。
    wins = [o for o in objs if _mat_is(o, "m_cp_win")]
    if len(wins) != 4:
        raise RuntimeError(
            "[指挥部待机] 按材质 m_cp_win 认出 %d 扇窗, 期望 4 扇" % len(wins))
    win_em = (0.30, 0.62, 0.90, 1.0)
    win_mat = create_clay_mat(
        "m_cp_win", (0.30, 0.62, 0.90, 1.0), emission=win_em,
        emission_str=_pulse_str(win_em, 0.5 + 0.5 * math.cos(phase)))
    for o in wins:
        o.data.materials[0] = win_mat

    return objs


# ══════════════════════════════════════════════════════════════════
#  弹药仓库 —— 顶部警示灯旋转扫光
# ══════════════════════════════════════════════════════════════════

def build_ammo_depot_idle(frame_idx, n_frames=6):
    """弹药仓库待机的一帧 —— 顶部危险警示灯脉动 (涨缩 + 明灭)。

    === 会动的只有那盏灯, 这是想清楚之后的结论, 不是偷懒 ===

    先看这栋楼在游戏里是什么: ammo_depot.gd 是一个**纯可破坏道具** —— 6 点血,
    打掉了就炸, 没有任何主动功能、没有作用半径、没有周期。建模注释也只写了
    "厚重方形弹药箱堆叠 + 危险条纹 + 防爆板", 没有一个会动的部件。

    对照这个文件自己的选型标准: 雷达站和 EMP 塔之所以入选, 是因为**它们的建模
    注释里本来就写着"旋转天线碟"/"旋转放电线圈"**, 建模时就是按"这玩意儿在转"
    设计的。弹药仓库没有这样的部件。箱子更是明确**不该动** —— 一垛会自己挪动
    的弹药箱读起来是地震。

    所以唯一说得通的动作就是那盏黄色警示灯 (m_am_warn): 现实里弹药库顶上确实
    有一盏, 而且它的作用正是"提醒你这东西会炸"。

    === 中间走过一版旋转光束, 渲出来是个黄色蝴蝶结 ===

    因为纯改自发光撑不起幅度 (雷达站实测过: 半径 0.10 的顶灯只贡献 0.01),
    第一版给灯加了一对锥形旋转光束去扫面积。实测幅度确实上去了 (0.10 -> 1.29),
    但**渲出来完全不能看**: Cycles 里的自发光锥是一个实心不透明物体, 画面上
    是一个黄色蝴蝶结压在箱子上, 把资产本身全盖住了, 根本读不成"光"。

    这是"照着指标调"的典型翻车 —— 数字进了合法区间, 美术却坏了。改回让灯珠
    **自己涨缩**: 半径 0.09 -> 0.185 是真实的面积变化 (48px 下 1.6px -> 3.4px),
    而不是只改亮度; 一盏会呼吸的警示灯本来就是它该有的样子。

    === 涨缩走 sin, 亮度走 cos ===

    6 帧均匀采相位时 sin 会成对撞值 (f1=f2, f4=f5), 见指挥部那段的详细推导。
    cos 的逐帧跨度恰好在那两处取到最大, 所以亮度通道必须走 cos。

    === 全部运动都在地基环带以内 ===

    灯珠在原点, 最大半径 0.185 = 18px; 待机门禁的地基环带从 70px 起算。箱子、
    防爆铁带 (半宽 0.81 = 77px, 正落在环带里) 一律不碰。
    """
    reset_jitter_seed(AMMO_DEPOT_IDLE_SEED)
    objs = build_ammo_depot()
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    warn = [o for o in objs if _mat_is(o, "m_am_warn")]
    if len(warn) != 1:
        raise RuntimeError(
            "[弹药仓库待机] 按材质 m_am_warn 认出 %d 盏警示灯, 期望 1 盏 "
            "—— build_ammo_depot() 的建模大概改了" % len(warn))
    lamp = warn[0]

    # 涨缩 —— 主通道, 真实的面积变化。灯珠建模半径 0.09, 没走倒角所以 scale
    # 还是 1, 这里直接乘。1.0 -> 2.05 即半径 0.09 -> 0.185。
    #
    # 走三角波而不是正弦 (见 _tri): 正弦版实测逐帧 `0.23 0.11 0.26 0.16 0.05
    # 0.22` —— 两个 sin 撞帧处只剩亮度在动, 而亮度对整图的贡献又受灯珠当时
    # 大小影响 (灯大时改亮度动的像素多, 灯小时少), 于是那两帧一个 0.11 一个
    # 0.05, 后者直接掉出卡帧线。三角波让六个 Δ 天然相等。
    # 系数是在"看得见"和"不抢戏"之间标出来的, 两头都撞过:
    #   0.9 (半径 0.171) -> 0.14 px/帧, 合法但和全项目最含蓄的 base_eagle(0.13)
    #                      同档, 一盏"提醒你这东西会炸"的灯不该最难察觉;
    #   1.3 (半径 0.207) -> 0.23 px/帧, 但峰值那一帧是一颗黄球压在箱垛正中,
    #                      把两个弹药箱的接缝全盖住, 读成球而不是灯。
    # 1.05 (半径 0.185) 取中。
    lamp.scale *= 1.0 + 1.05 * (0.5 + 0.5 * _tri(frame_idx, n_frames))

    # 亮度 (cos) —— 填 sin 撞车的那两帧, 见函数注释。强度必须走 _pulse_str:
    # 第一版写的是 2.0*(1±0.62), 整个区间都在钳位线以上, 逐帧被压成同一个值,
    # 实测最小帧间运动直接掉到 0.00 (两帧完全一样)。
    lamp_em = (1.0, 0.85, 0.10, 1.0)
    lamp.data.materials[0] = create_clay_mat(
        "m_am_warn", (0.98, 0.82, 0.10, 1.0), emission=lamp_em,
        emission_str=_pulse_str(lamp_em, 0.5 + 0.5 * math.cos(phase), lo=0.25))

    return objs


# ══════════════════════════════════════════════════════════════════
#  狙击碉堡 —— 枪架横扫 + 瞄具反光
# ══════════════════════════════════════════════════════════════════

## 枪架的回转轴 —— 射孔位置, 不是画面中心。绕中心转的话枪管会绕着整个碉堡
## 公转, 读起来像碉堡在转而不是枪在瞄。
SN_PIVOT = (0.0, 0.42)


def build_sniper_nest_idle(frame_idx, n_frames=6):
    """狙击碉堡待机的一帧 —— 枪架横扫搜索 + 瞄具反光随枪移动 + 枪口指示灯。

    === 语义: 它在"找目标", 不是在"开火" ===

    碉堡的动作应该读成搜索: 枪架缓慢横扫, 瞄具的反光跟着枪走。幅度刻意压住,
    一挺来回急甩的枪读起来是故障而不是警戒。

    === 横扫绕射孔转, 不绕画面中心 ===

    枪架建模在 (0, 0.84), 长 0.55 (y 向 0.565~1.115)。回转轴取 (0, 0.42) ——
    射孔位置 —— 于是它读起来是架在垛口上左右摇, 而不是整根棍子绕楼心画圆。

    === sin/cos 两通道 (同指挥部) + 一个真的有面积的部件 ===

    横扫走 sin。但枪管很细 (半径 0.04, 48px 下才 1.4px), 光靠它撑不起幅度,
    更要命的是 sin 在 f1/f2 与 f4/f5 上会撞帧。所以在枪口加一颗指示灯, 半径
    随 cos 在 0.05~0.14 之间涨缩 —— 这是一个**真的在改面积**的通道 (48px 下
    直径 1.8px -> 5px), 而不是又一个只改自发光的小点。雷达站那次已经量过:
    纯改自发光的小部件对整图均差的贡献是 0.01, 撑不起任何事。

    指示灯用 _spin_about 跟枪架做同一个变换, 而不是自己算一遍三角函数 ——
    这样它不可能和枪口错位。

    === 枪架落在门禁的"地基环带"里, 这是判据的问题不是动画的问题 ===

    枪架在 r=0.56~1.12, 和 test_idle_anims.gd 的地基环带 r=0.74~1.24 重叠。
    那个环带本来就只是"地基在哪"的**代理**, 对这栋楼不成立 —— 伸在外面的是
    武器, 不是地基。判据已改成按 churn 的角向分布来区分"整栋楼在动/轮廓沸腾"
    (churn 遍布全周) 和"某个附件在动" (churn 集中在一个扇区), 详见那边的注释。
    """
    reset_jitter_seed(SNIPER_NEST_IDLE_SEED)
    objs = build_sniper_nest()
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))
    # 横扫走三角波而不是正弦 —— 见 _tri 的注释: 正弦会让 f1/f2 与 f4/f5 撞在
    # 同一个角度, 而这里的补偿通道 (枪口指示灯) 太小, 配平不过来。机械扫描本来
    # 也该是匀速往返而不是两端放缓。
    sweep = math.radians(26.0) * _tri(frame_idx, n_frames)

    gun = [o for o in objs if _mat_is(o, "m_sn_metal")]
    if len(gun) != 1:
        raise RuntimeError(
            "[碉堡待机] 按材质 m_sn_metal 认出 %d 个枪架, 期望 1 个 "
            "—— build_sniper_nest() 的建模大概改了" % len(gun))
    _spin_about(gun[0], SN_PIVOT[0], SN_PIVOT[1], sweep)

    # 瞄具反光: 缩成一个亮点并沿射孔滑动, 和枪架**走同一条三角波**, 于是瞄具
    # 看的方向和枪指的方向始终一致。
    # 镜片没被倒角, 所以还保着建模时的 scale (0.38, 0.04, 0.04)。
    # 滑动量 0.115 + 收窄后的半长 0.0875 = 0.20, 压在射孔半长 0.21 以内,
    # 亮点不会滑出垛口。
    lens = [o for o in objs if _mat_is(o, "m_sn_glass")]
    if len(lens) != 1:
        raise RuntimeError(
            "[碉堡待机] 按材质 m_sn_glass 认出 %d 片瞄具, 期望 1 片" % len(lens))
    lens[0].scale.x *= 0.46
    lens[0].location.x += 0.115 * _tri(frame_idx, n_frames)

    # 枪口测距指示灯。先建在未偏航的枪口位置, 再套用和枪架**完全相同**的
    # _spin_about, 于是不可能和枪口错位。
    #
    # 半径 0.018 ~ 0.078, 走 cos —— 和上面那条三角波相位错开, 于是六帧里没有
    # 任何两帧是同一个构型 (三角波本身在 f1/f5 与 f2/f4 上取值相同, 单靠它
    # 一个循环只有四张不同的图)。
    #
    # 这个尺寸调过两轮, 两个方向都撞过:
    #   半径 0.095~0.14 —— 渲出来是一颗大蓝球插在灰色枪杆顶上, 指示灯比枪管
    #     (半径 0.04) 粗了三倍多, 整个碉堡读成一根棒棒糖;
    #   半径 0.060~0.015 —— 基准是收小了, 但**脉动量被一起收掉了**, 于是这条
    #     通道也跟着废掉 (最小帧间运动 0.16 -> 0.03, 判卡帧)。
    # 要收的是基准, 不是摆幅: 现在基准很小 (不喧宾夺主) 而相对摆幅拉满,
    # 读起来是一个一亮一灭的测距指示灯。
    #
    # 颜色从纯蓝改成暖琥珀: 瞄具镜片已经是蓝色 (m_sn_glass), 再来一个同色大
    # 亮点会和它抢读数; 琥珀在这套美术里是和警示灯一致的"待机/测距"语汇。
    flare_em = (1.0, 0.66, 0.16, 1.0)
    flare_r = 0.048 + 0.030 * math.cos(phase)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=flare_r, location=(0.0, 1.115, 0.18))
    flare = bpy.context.active_object
    flare.data.materials.append(create_clay_mat(
        "m_sn_flare", (1.0, 0.72, 0.22, 1.0), emission=flare_em,
        emission_str=_pulse_str(flare_em, 0.5 + 0.5 * math.cos(phase), lo=0.30)))
    bpy.ops.object.shade_smooth()
    _spin_about(flare, SN_PIVOT[0], SN_PIVOT[1], sweep)
    objs.append(flare)

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
    # 这三栋的静态图都是 build_new_buildings_and_tanks.py::main() 用 PROP(2.7)
    # 渲的, 实测见 qa_orphan_audit.py (d_rgb 0.59 / 0.89 / 1.26)。
    "command_post":  (build_command_post_idle,  "command_post_f{i}.png",  ORTHO_SCALE_PROP),
    "ammo_depot":    (build_ammo_depot_idle,    "ammo_depot_f{i}.png",    ORTHO_SCALE_PROP),
    "sniper_nest":   (build_sniper_nest_idle,   "sniper_nest_f{i}.png",   ORTHO_SCALE_PROP),
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
