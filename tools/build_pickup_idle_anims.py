"""build_pickup_idle_anims.py — 战场拾取物的待机循环动画 (各 6 帧)

    blender --background --python tools/build_pickup_idle_anims.py
    blender --background --python tools/build_pickup_idle_anims.py -- star gold_coin

输出 (assets/sprites/powerups/):
    star_f0..f5        双层星缓慢反向自转 + 呼吸
    gold_coin_f0..f5   绕竖直轴整圈翻转 (真 3D, 会看到厚度)
    clock_f0..f5       指针扫动 + 闹铃抖动
    helmet_f0..f5      星徽自转 + 整体轻微起伏
    shovel_f0..f5      以铲尖为支点左右摇摆
    bomb_f0..f5        引信火花跳动 + 弹体微胀
    life_f0..f5        心跳 (lub-dub 双搏, 非正弦)

=== 为什么是这七个 ===

把 scripts/ 里每个拾取物挨个看了一遍, 程序动画的密度差得很远:
diamond_gem / treasure_chest / treasure_key / drifting_supplies 都有 6~9 处
tween/rotation/pulse, 而 **power_up.gd 只有一句 `position.y += sin(...)` 的
微幅浮动, gold_coin.gd 只有一句 2D 自转**。也就是说玩家整场都在追的那十种道具
基本是钉在地上的静图。

这是全项目"不动"的最大一块, 而且是玩家注意力最集中的一块 —— 坦克大战里
闪烁的☆本来就是这个类型最有辨识度的一件事。

gold_coin 的 2D 自转要一并去掉 (见 scripts/gold_coin.gd): 一枚正对镜头的圆盘
绕画面法线转, 读起来是"转的盘子"而不是"翻的硬币" —— 它没有厚度变化。真正的
翻转只能在 3D 里渲。

=== 沿用建筑待机那套规矩 ===

包装器调属主的 build_sokpop_powerup(类型) 拿对象再位移, 一行几何都不抄;
整段动画共用一个抖动种子; 部件靠材质名 + 坐标认, 数目对不上就抛异常。
详见 build_building_idle_anims.py 的文件头。

**属主是 unified 那个 build_sokpop_powerup, 不是 refine_all_assets.py。**
这七张图有两个脚本都能渲, 实测 (qa_orphan_audit.py):

    build_sokpop_powerup(...)          d_rgb 0.22 ~ 1.14   <- 属主
    refine_all_assets.py::build_star   d_rgb 8.58 ~ 26.51, d_cov 0.011~0.084

后者连剪影都对不上。CLAUDE.md 曾记着 refine_*.py "修好画幅后与已提交版本逐像素
一致", 那句话对现在的仓库不成立了 —— 跑它会静默改掉这六张道具图。

=== 拾取物和建筑的约束不一样 ===

建筑那边的硬约束是"地基逐帧不能动"(它压在固定格子上, 一动整栋楼像在漂)。
拾取物是自由摆放的道具, 没有地基, 所以那条不适用。换成两条它自己的:

  1. **不能越出画幅。** 道具本来就把画幅占得比较满 (shovel 的包围盒 88x207,
     star 169x160), 动起来一旦超出 256px 就会被裁掉一角, 而裁切在动画里表现为
     "边缘一闪一闪", 比不动还难看。每个函数的幅度都是按各自的包围盒余量定的。
  2. **不能整体漂移。** 循环动画的各帧质心要基本重合, 否则道具会在地上缓慢
     游走 —— 而 power_up.gd 自己还有一层 sin 浮动, 两者叠加会变成随机游走。
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
)
from build_all_sokpop_assets_unified import build_sokpop_powerup, SPRITES_POWERUPS

## 每组自己的固定抖动种子 —— 全 6 帧共用。
SEEDS = {
    "star": 9100, "gold_coin": 9200, "clock": 9300, "helmet": 9400,
    "shovel": 9500, "bomb": 9600, "life": 9700,
}


def _mat_is(obj, prefix):
    """材质名是否以 prefix 开头 (create_clay_mat 有缓存, 重名会被 bpy 加 .001)。"""
    if not obj.data or not getattr(obj.data, "materials", None):
        return False
    m = obj.data.materials[0]
    return bool(m) and m.name.startswith(prefix)


def _need(objs, n, what, how):
    if len(objs) != n:
        raise RuntimeError(
            "[道具待机] %s: 按 %s 认出 %d 个, 期望 %d 个 —— "
            "build_sokpop_powerup() 的建模大概改了, 请核对判据, "
            "否则动画会动错部件" % (what, how, len(objs), n))
    return objs


def _spin_z(obj, ang, pivot=(0.0, 0.0)):
    """绕平行于 Z 轴、过 pivot 的直线转 ang 弧度 (位置和自身朝向一起转)。"""
    c, s = math.cos(ang), math.sin(ang)
    x = obj.location.x - pivot[0]
    y = obj.location.y - pivot[1]
    obj.location.x = pivot[0] + x * c - y * s
    obj.location.y = pivot[1] + x * s + y * c
    obj.rotation_euler.z += ang


def _spin_y(obj, ang):
    """绕世界 Y 轴 (画面竖直方向) 转 —— 硬币翻转用这个, 会看到厚度。"""
    c, s = math.cos(ang), math.sin(ang)
    x, z = obj.location.x, obj.location.z
    obj.location.x = x * c + z * s
    obj.location.z = -x * s + z * c
    obj.rotation_euler.y += ang


def _tilt_x(obj, ang):
    """绕世界 X 轴 (画面水平方向) 转 —— 给正对镜头的扁平物一个倾角, 露出厚度。"""
    c, si = math.cos(ang), math.sin(ang)
    y, z = obj.location.y, obj.location.z
    obj.location.y = y * c - z * si
    obj.location.z = y * si + z * c
    obj.rotation_euler.x += ang


def _is_star_mesh(obj):
    """是不是 create_3d_star() 造出来的星形。

    必须按**网格数据块的名字**认, 不能按 location 认: create_3d_star 把 z_pos
    直接烘进了顶点坐标 (build_all_sokpop_assets_unified.py:48), 对象的
    location 仍然停在原点。头盔前脸那颗星徽写着 z_pos=0.88, 但 o.location.z
    读出来是 0.0 —— 第一版就是这么把判据写错的, 好在判据数目对不上会抛异常,
    渲出来的不是错的图而是一个报错。
    """
    return bool(obj.data) and getattr(obj.data, "name", "").startswith("StarMesh")


def _scale_about_origin(objs, s):
    """整组绕世界原点做均匀缩放。

    **必须同时改 location 和 scale**, 而且顺序无关 —— 这两类对象的行为不一样:

      - 普通图元 (primitive_*_add) 的顶点是围绕自身原点的, 位置全在 location 里。
        只改 scale 的话它在原地胖瘦, 不会跟着一起离开/靠近中心。
      - create_3d_star() 造的星形把偏移烘进了顶点, location 恒为 (0,0,0)。
        只改 location 的话它纹丝不动。

    两样都改, 对两类对象就都退化成正确的"绕原点整体缩放"。这也是 build_life_idle
    的心跳能对一堆混合部件同时生效的原因。
    """
    for o in objs:
        o.location = (o.location.x * s, o.location.y * s, o.location.z * s)
        o.scale = (o.scale.x * s, o.scale.y * s, o.scale.z * s)


# ══════════════════════════════════════════════════════════════════

def build_star_idle(frame_idx, n_frames=6):
    """☆ 双层星反向自转 + 呼吸。

    五角星有 72° 的旋转对称, 所以一个循环只需要转 72° —— 6 帧各 12°, 步子很小,
    却是严丝合缝的闭环。这和 EMP 塔用三重对称换 120° 是同一招: 对称性让你用更小
    的步长走完一个完整周期, 而不是被迫每帧跳 60°。

    但只转 72° 幅度不够, 所以内外两层**反向**转, 相对角速度翻倍; 再叠一层
    呼吸缩放。呼吸幅度定在 3.0%: 第一版给了 7.5%, 48px 下相邻帧均差冲到 12.9,
    比全项目最闹腾的风机 (3.8) 还高三倍多 —— 一颗躺在地上的道具不该比机器还抢眼。
    """
    reset_jitter_seed(SEEDS["star"])
    objs = build_sokpop_powerup("star")
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))
    step = (2.0 * math.pi / 5.0) * (frame_idx / float(n_frames))   # 72° 一圈

    outer = _need([o for o in objs if _mat_is(o, "m_upw_g")], 1, "☆外层", "材质 m_upw_g")[0]
    inner = _need([o for o in objs if _mat_is(o, "m_upw_w")], 1, "☆内层", "材质 m_upw_w")[0]

    # 内层**同向**转两倍速 (144° = 2x72°, 同样是闭环), 相对角速度 72°/循环。
    # 第一版是反向转, 相对角速度 144°/循环 = 每帧 24° —— 两层高对比的星形
    # 互相错动这么快, 48px 下相邻帧均差 12.8, 读起来是闪烁而不是转动。
    # 实测这一项才是幅度的主导因素: 把呼吸从 7.5% 收到 3.0% 几乎没让数字动
    # (12.91 -> 12.79), 换成同向才真正降下来。
    _spin_z(outer, step)
    _spin_z(inner, 2.0 * step)

    _scale_about_origin(objs, 1.0 + 0.030 * math.sin(phase))
    return objs


def build_gold_coin_idle(frame_idx, n_frames=6):
    """金币: 固定倾角 + 绕自身轴自转 (露出厚度和边圈)。

    === 为什么必须在 3D 里做 ===

    gold_coin.gd 原来是 `sprite.rotation += delta * 4.0`, 也就是让一枚**正对
    镜头**的圆盘绕画面法线自转。圆盘绕自己的对称轴转, 轮廓完全不变 —— 读起来是
    一个转着的盘子, 而不是一枚有厚度的硬币。这里给它一个 34° 的固定倾角, 币身
    的厚度和那圈边缘就露出来了, 这在 2D 里怎么转都变不出来。

    === 为什么不是整圈翻转 ===

    第一版是绕 Y 轴翻满 360° (每帧 60°)。听上去更"硬币", 实测却不行:
    投影宽度按 cos 走 1 / .5 / .5 / 1 / .5 / .5, 于是帧间运动量是
    3.70 / 0.76 / 3.60 / 3.75 / 0.76 / 3.90 像素 —— **5 倍的不均匀**, 播起来是
    "啪啪-停-啪啪-停"。而且 180° 那帧转到的是背面, 而属主只在正面刻了星,
    背面是一片空白的金盘。

    改成倾角自转之后: 轮廓是一个不变的椭圆, 变的是星和高光的朝向, 每帧运动量
    均匀; 五角星的 72° 对称让 6 帧刚好闭环 (币身和边圈是回转体, 本来就任意角
    闭环)。躺在战场上被子弹乱飞包围的东西, 节奏稳一点比抢眼一点重要。
    """
    reset_jitter_seed(SEEDS["gold_coin"])
    objs = build_sokpop_powerup("gold_coin")
    if not objs:
        return objs
    _need(objs, 3, "金币", "属主返回的对象数 (币身/边圈/星)")

    # === 转满 360° 而不是 72°, 因为抖动不是旋转不变的 ===
    #
    # 币身是 20 边形回转体、正面那颗星是五重对称, 所以按几何算转 72° 就闭环了。
    # 但 apply_uniform_clay_bevel 会把随机顶点抖动**烘进网格**, 那层抖动没有任何
    # 对称性 —— 转 72° 之后抖动图案和起点对不上, 于是 f5->f0 那一步比其它步大
    # 2.6 倍 (1.69 px vs 0.65 px), 播起来每个循环打一个嗝。
    #
    # 360° 对抖动才是恒等变换。而且不会因此变快: 币身是回转体, 转多少度轮廓都
    # 一样; 那颗星每帧实际挪的是 60° mod 72° = -12°, 和原来一模一样。
    spin = 2.0 * math.pi * (frame_idx / float(n_frames))
    for o in objs:
        _spin_z(o, spin)
        _tilt_x(o, math.radians(34.0))
    return objs


def build_clock_idle(frame_idx, n_frames=6):
    """⏰ 指针扫动 + 闹铃抖动。

    时钟是"冻结时间"道具, 指针飞转正好是它的语义。分针一个循环转满 360°
    (每帧 60°), 时针只转 60° —— 两针不同速才读得出是钟在走, 同速的话看起来
    像整个表盘在转。

    指针要和刻度点区分开: 两者都是 m_upw_d 深色材质。判据用**离表盘中心的
    距离**: 指针挂在中心 (< 0.35), 12 个刻度点在半径 0.68 上。用下标去认会在
    属主插一个部件时静默错位。
    """
    reset_jitter_seed(SEEDS["clock"])
    objs = build_sokpop_powerup("clock")
    if not objs:
        return objs

    CY = -0.26          # 属主里表盘整体下移的量
    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    dark = [o for o in objs if _mat_is(o, "m_upw_d")]
    hands = _need([o for o in dark
                   if math.hypot(o.location.x, o.location.y - CY) < 0.35],
                  2, "⏰指针", "材质 m_upw_d + 距表盘中心 < 0.35")
    # 长的是分针 —— 属主给的是 depth 0.40 (时针) 和 0.48 (分针), 走 dimensions
    hands.sort(key=lambda o: max(o.dimensions))
    hour_hand, minute_hand = hands[0], hands[1]

    _spin_z(minute_hand, 2.0 * math.pi * (frame_idx / float(n_frames)), pivot=(0.0, CY))
    _spin_z(hour_hand, (2.0 * math.pi / 6.0) * (frame_idx / float(n_frames)), pivot=(0.0, CY))

    # 闹铃左右抖 —— 相位比指针早 90°(cos), 顺带把正弦采样会撞车的帧岔开
    bells = [o for o in objs if _mat_is(o, "m_upw_g") and abs(o.location.x) > 0.5]
    _need(bells, 2, "⏰闹铃", "材质 m_upw_g + |x| > 0.5")
    shake = math.radians(9.0) * math.cos(phase)
    for b in bells:
        b.rotation_euler.z += shake * (1.0 if b.location.x > 0 else -1.0)
        b.location.y += 0.035 * math.cos(phase)

    # === 整只钟跟着一起晃, 否则幅度根本不够 ===
    #
    # 只动指针和闹铃时, 48px 下相邻帧均差只有 1.02 —— 比鹰巢待机 (1.04) 还低,
    # 属于"做了等于没做"。原因是指针是两根半径 0.045 的细杆, 转一圈能改动的
    # 像素太少, 而它又恰恰是这个道具语义上最该动的部件。
    #
    # 解法不是把指针加粗 (那会改掉道具本身的读法), 而是让**整只闹钟**跟着响铃
    # 一起震 —— 钟体半径 1.05, 转 4° 扫过的像素比指针转一整圈还多。这也符合
    # 直觉: 一只正在打铃的闹钟本来就在桌上跳。
    body_shake = math.radians(4.0) * math.sin(phase + math.pi * 0.5)
    for o in objs:
        _spin_z(o, body_shake, pivot=(0.0, CY))
    return objs


def build_helmet_idle(frame_idx, n_frames=6):
    """🪖 星徽自转 + 整体轻微起伏。

    头盔是个实心壳, 没有可以单独动起来的机械部件, 所以动效交给前脸那颗星徽
    (同样吃五角星的 72° 对称) 加一层整体的轻微浮沉。幅度刻意压得比其它几个低:
    防护类道具的语义是"稳", 抖得厉害反而不像护具。

    星徽要和铆钉区分: 都是 m_upw_w 白色材质。判据**不能用高度** —— 星徽是
    create_3d_star() 造的, z_pos 烘在顶点里, o.location.z 读出来是 0 而不是
    0.88 (第一版就栽在这里)。改用网格数据块名 StarMesh, 见 _is_star_mesh。

    第二个通道用整体呼吸而不是"绕 Y 轴倾斜": 倾斜要靠 rotation_euler, 而普通
    图元绕的是**自身原点**、烘死几何的星徽绕的是**世界原点** —— 同一句代码对
    两类对象做的是两件事, 渲出来是头盔各部件各转各的。均匀缩放走
    _scale_about_origin 就没有这个问题。
    """
    reset_jitter_seed(SEEDS["helmet"])
    objs = build_sokpop_powerup("helmet")
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))
    badge = _need([o for o in objs if _mat_is(o, "m_upw_w") and _is_star_mesh(o)],
                  1, "🪖星徽", "材质 m_upw_w + 网格名 StarMesh")[0]
    _spin_z(badge, (2.0 * math.pi / 5.0) * (frame_idx / float(n_frames)))

    _scale_about_origin(objs, 1.0 + 0.045 * math.cos(phase))
    for o in objs:
        o.location.z += 0.055 * math.sin(phase)
    return objs


def build_shovel_idle(frame_idx, n_frames=6):
    """🪓 以铲尖为支点左右摇摆。

    铲子的读法是"插在地上", 所以支点放在铲尖 (0, -0.85) 而不是几何中心 ——
    支点在下, 摆动读作"戳在土里晃"; 支点在中间, 读作"悬空转"。

    正弦摆动会让 6 帧中的两对撞上同一个角度 (见 build_building_idle_anims.py
    雷达站那段), 所以再叠一个 cos 驱动的沿轴伸缩, 把那两对岔开。
    """
    reset_jitter_seed(SEEDS["shovel"])
    objs = build_sokpop_powerup("shovel")
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))
    PIVOT = (0.0, -0.85)
    # 摆幅 4.0° + 浮动 0.040: 铲子细长 (包围盒 88x207), 一摆起来包围盒还会
    # 因为倾斜而变大。7.5°/0.075 那版画幅余量只剩 4px, 而画幅裁切在动画里
    # 表现为"边缘一闪一闪", 比不动还难看。
    sway = math.radians(4.0) * math.sin(phase)
    for o in objs:
        _spin_z(o, sway, pivot=PIVOT)
    # cos 通道, 把正弦撞车的两对帧分开。用**刚性上下浮动**而不是沿轴伸缩:
    # 伸缩会把手柄推向画幅边缘 (它已经贴得很近了), 而平移是整体的, 余量不变。
    for o in objs:
        o.location.y += 0.040 * math.cos(phase)
    return objs


## 引信火焰的逐帧缩放 —— 六个各不相同的值, 刻意不规则。
BOMB_CRACKLE = [1.00, 1.34, 1.06, 1.26, 0.90, 1.15]


def build_bomb_idle(frame_idx, n_frames=6):
    """💣 引信火花跳动 + 弹体微胀。

    炸弹的全部动效集中在引信那一点火上 —— 那是它唯一"活着"的部件, 也是玩家
    需要看懂的信息 (这玩意儿要炸)。火焰球和高亮芯做不同相位的缩放, 再让高亮芯
    的自发光强度跟着跳, 于是火花读起来是**噼啪**的而不是匀速呼吸的。

    弹体只做很小的胀缩 (2%): 一个铸铁球胀得明显就不像铁了。
    """
    reset_jitter_seed(SEEDS["bomb"])
    objs = build_sokpop_powerup("bomb")
    if not objs:
        return objs

    phase = 2.0 * math.pi * (frame_idx / float(n_frames))

    core = _need([o for o in objs if _mat_is(o, "m_upw_spkc")], 1,
                 "💣火花芯", "材质 m_upw_spkc")[0]
    # 火焰球: 红色材质里位置最高的那个 (另一处红色是没有的, 但留个判据更稳)
    flame = _need([o for o in objs if _mat_is(o, "m_upw_r") and o.location.y > 1.0],
                  1, "💣火焰", "材质 m_upw_r + y > 1.0")[0]
    body = _need([o for o in objs if _mat_is(o, "m_upw_d")], 1, "💣弹体", "材质 m_upw_d")[0]

    # 火焰用**显式表格**而不是正弦。任何单一正弦在 6 个均匀相位上都会成对
    # 撞上同一个值 (见 build_building_idle_anims.py 雷达站那段), 而火焰是这个
    # 道具里最大的那个运动部件 —— 它一撞车, 整帧就几乎没有变化。
    # a*sin + b*cos 也没用: 那仍然是一条正弦, 只是换了相位。
    # 顺带, 引信噼啪本来就该是不规则的, 匀速呼吸反而不像在烧。
    f_puls = BOMB_CRACKLE[frame_idx % len(BOMB_CRACKLE)]
    flame.scale = (f_puls, f_puls, f_puls)

    # === 高亮芯本来是看不见的, 得先把它挪出来 ===
    #
    # 属主把火花芯建在 (0.42, 1.34, 0.06) 半径 0.10, 火焰球建在 (0.42, 1.34, 0)
    # 半径 0.18 —— 芯的最高点 z=0.16 低于火焰的 z=0.18, 而且横向也完全在火焰
    # 里面。正交俯视下 Cycles 不透光, 所以**这颗芯从来没被渲出来过**, 已提交的
    # bomb.png 里也没有。第一版动画照着原位置去缩放它, 于是那一路改动全打在
    # 看不见的东西上, 只剩火焰的纯 sin 通道 —— 结果 f1/f2 完全重复 (相邻帧差
    # 0.00), 而 sin 在 6 个均匀相位上正好成对撞车。
    #
    # 这里把芯抬到火焰之上 (z 随相位在 0.24~0.30 之间), 它才真正成为"火花"。
    # 动画帧因此和无后缀的静态图长得不完全一样 —— 这是可以的, 静态图只是
    # 取不到帧时的退化路径 (鹰巢待机同理)。
    c_puls = 1.0 + 0.42 * math.cos(phase)          # cos: 把 sin 撞车的两对帧岔开
    core.scale = (c_puls, c_puls, c_puls)
    core.location.z = 0.27 + 0.03 * math.cos(phase)
    core.location.x += 0.10 * math.cos(phase)
    core.location.y += 0.09 * math.sin(phase * 2.0)

    core.data.materials[0] = create_clay_mat(
        "m_upw_spkc", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0),
        emission_str=3.0 * (1.0 + 0.55 * math.cos(phase)))

    b = 1.0 + 0.02 * math.sin(phase)
    body.scale = (b, b, b)
    return objs


## 心跳的逐帧缩放。**显式表格而不是正弦**, 理由和爆炸的形状表是同一个:
## 心跳的节奏本来就不是正弦 —— 它是"咚-哒"两下然后一段静默 (lub-dub)。
## 用 sin 渲出来是匀速的一胀一缩, 读作"呼吸"而不是"心跳", 而且 6 帧均匀采样
## 正弦还会有两对帧撞上同一个值。这张表刻意让 f1 和 f3 是两个不同高度的峰,
## 中间 f2 回落但不到底, f4/f5 是舒张期 —— 六帧各不相同。
LIFE_BEAT = [1.00, 1.19, 1.045, 1.11, 0.985, 0.965]


def build_life_idle(frame_idx, n_frames=6):
    """❤️ 心跳 (lub-dub 双搏)。

    支点放在心形下尖 (0, -0.9) 而不是重心: 支点在下, 缩放读作"鼓起来";
    支点在重心的话上下同时胀缩, 读成整颗心在忽大忽小。这条和鹰巢待机把呼吸
    支点放在底座顶面是同一个道理。
    """
    reset_jitter_seed(SEEDS["life"])
    objs = build_sokpop_powerup("life")
    if not objs:
        return objs

    beat = LIFE_BEAT[frame_idx % len(LIFE_BEAT)]
    # 支点靠下: 先把整组按原点缩放, 再整体下移, 等价于绕 (0, -0.90) 缩放。
    # 走 _scale_about_origin 而不是手写, 是因为它同时处理 location 和 scale ——
    # 心形是普通图元, 但这个模式对烘死几何的部件同样成立 (见该函数注释)。
    _scale_about_origin(objs, beat)
    PIVOT_Y = -0.90
    for o in objs:
        o.location.y += PIVOT_Y * (1.0 - beat)
    return objs


# ══════════════════════════════════════════════════════════════════

# name -> (builder, 输出名模板)
#
# 画幅一律 ORTHO_SCALE_DEFAULT: 实测属主的七张图都是在 3.3 下渲的
# (qa_orphan_audit.py, d_rgb 0.22~1.14)。传错画幅会让这 6 帧整体比无后缀的
# 静态图大一圈或小一圈, 而那两者在游戏里是同一个精灵的两条取图路径。
GROUPS = {
    "star":      (build_star_idle,      "star_f{i}.png"),
    "gold_coin": (build_gold_coin_idle, "gold_coin_f{i}.png"),
    "clock":     (build_clock_idle,     "clock_f{i}.png"),
    "helmet":    (build_helmet_idle,    "helmet_f{i}.png"),
    "shovel":    (build_shovel_idle,    "shovel_f{i}.png"),
    "bomb":      (build_bomb_idle,      "bomb_f{i}.png"),
    "life":      (build_life_idle,      "life_f{i}.png"),
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
    print("  拾取物待机循环动画 (各 %d 帧)" % N_FRAMES)
    print("=" * 60)

    for name in names:
        builder, tmpl = GROUPS[name]
        print("\n[%s] 渲染 %d 帧 ..." % (name, N_FRAMES))
        for i in range(N_FRAMES):
            clear_scene()
            setup_render_settings(256, 256, samples=32)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
            objs = builder(i, N_FRAMES)
            out = os.path.join(SPRITES_POWERUPS, tmpl.format(i=i))
            render_and_clean(objs, out)
            print("  [OK] %s" % tmpl.format(i=i))

    print("\n" + "=" * 60)
    print("  完成 -> %s" % SPRITES_POWERUPS)
    print("  别忘了: 重导 -> fix_sprite_mipmaps.py -> 重导 -> 跑测试")


if __name__ == "__main__":
    main()
