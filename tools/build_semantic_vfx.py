"""按*语义*拆分的新特效序列 —— 给一直共用通用冲击波的那批事件各自的读法。

为什么要有这批资源
------------------
统计过 `VFXAnimator.spawn_*` 的全部调用点: 12 个函数, 240 处调用, 而
`spawn_shockwave` / `spawn_clay_debris` / `spawn_dust_puff` 三个就占了 198 处。
后果是同一个灰色圆环同时在演: 胜利爆发、EMP 瘫痪、雷达扫描、护盾站充能、
宝箱开启、跳板弹射、钥匙拾取、虫洞、建筑爆破、鹰旗阵亡。这些事件的**语义
完全不同, 画面完全一样** —— 玩家没法从画面学到刚才发生了什么。

所以这里补的不是"更多好看的爆炸", 是**可区分的读法**。

设计约束: 换颜色不够, 换元素形状也不够, 必须换**整体剪影拓扑**
--------------------------------------------------------------
这条是量出来才知道的, 第一版就栽在这里。

第一版给六组各配了不同的元素形状 (球 / 方块 / 星芒 / 棱角碎片) 和不同的颜色,
在 256px 源图上区别很明显。但世界精灵按 TILE_SCALE=0.1875 画 (256 -> 48px),
`test_semantic_vfx.gd` 在 48px 下量两两距离, 结果**涉及新特效的最接近 10 对
全部低于现役基线 14.39** (现役特效之间最像的一对是 dust_puff vs clay_debris,
14.39; 中位 40)。最差的 emp vs reward 只有 7.83。

原因: 六组用的是同一个构图模板 —— 围绕中心、半径相近、大小相近的小元素放射状
散布。缩到 48px 后每个元素只剩 3~4 像素, 元素形状全糊掉, 六组只剩下"一圈小
亮点"这一个读法, 颜色也在 Lanczos 降采样 + 预乘 alpha 之后被稀释。

所以区分必须落在**整块图形的占位形状**上, 那是唯一能扛住 5.33 倍降采样的特征:

    heal      纵向光柱      窄而高, 全批唯一的竖向各向异性  <- "增益, 向上"
    emp       大空心环      中心空, 全批唯一的环形拓扑      <- "电子脉冲"
    reward    密核 + 长十字  实心核配细长射线                <- "战利品"
    frost     少量大碎块    4 块大的, 不规则块状剪影        <- "冰碎了"
    sand      低矮宽丘      宽而扁、重心贴底, 与 heal 相反  <- "地面被掀开"
    assemble  四方块合拢    向内收敛, 末帧最实              <- "造出来了"

顺带一个第一版没注意到的量级问题: 新特效峰值覆盖率只有 5~11%, 而现役 explosion
是 19%。48px 下 5% 只有约 115 个像素 —— 太稀薄, 本来就不容易读。重做时一并把
质量提上去了。

前五个遵守 CLAUDE.md 里那条"爆炸型序列必须消散"的规矩: 覆盖率在中段见峰,
末帧低于峰值一半 —— 靠**后期缩小单体、同时拉开间距**做到, 而不是整体等比放大。

`build_assemble` 是**故意的例外, 不要给它套消散断言**: 它演的是"建筑落成",
运动方向是收敛而不是扩散, 末帧本来就该是最实的一帧。这条差异写在这里, 免得
以后有人拿统一的断言去套它然后"修"坏它。

用法 (定向重渲走 rerender_vfx.py, 那里登记了这六组):
    blender --background --python tools/build_semantic_vfx.py
"""

import math
import os
import sys

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

from sokpop_common import (  # noqa: E402
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    render_and_clean,
    reset_jitter_seed,
    create_clay_mat,
    apply_clay_jitter,
    apply_uniform_clay_bevel,
    ORTHO_SCALE_DEFAULT,
)

JITTER_SEED = 5300
N_FRAMES = 6


def _ignition(frame, f0=0.55):
    """首帧衰减系数 —— "起爆过程"。

    `test_explosion_vfx.gd` 有一条断言: 首帧覆盖率必须低于峰值的 60%, 否则
    "缺少炸开的过程" (一上来就是一大团, 读作凭空出现而不是从一点炸开)。
    第一版的 emp_pulse / frost_shatter 实测首帧比是 0.63 / 0.61, 两个都会红。

    这是断言对、美术错: 修法是让首帧真的小一圈, 不是去放宽断言。做法沿用
    build_muzzle_flash 已有的 scale_mult 帧表写法。注意面积随半径平方走,
    所以 0.55 的线性系数对应约 0.30 的覆盖率 —— 别按线性去估。
    """
    return f0 if frame == 0 else 1.0


def _sphere(rad, loc, mat, squash=1.0, jitter=0.008):
    """一颗带手捏感的黏土球。squash<1 压扁成饼, 顶视下读作"贴地"。"""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=rad, location=loc)
    ob = bpy.context.active_object
    ob.scale = (1.0, 1.0, squash)
    ob.data.materials.append(mat)
    if jitter > 0.0:
        apply_clay_jitter(ob, strength=jitter)
    bpy.ops.object.shade_smooth()
    return ob


def _block(size, loc, mat, rot=(0.0, 0.0, 0.0), bevel=0.05):
    """一块倒角黏土方块 —— 棱角是它和球体的区别, 碎冰/土块靠它读出"硬"。"""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.scale = size
    ob.rotation_euler = rot
    ob.data.materials.append(mat)
    apply_uniform_clay_bevel(ob, width=bevel, segments=2, jitter=0.010)
    return ob


# ==================== 1. 治疗/修理脉冲 (HEAL PULSE) ====================
#
# 用在: repair_station / shield_station / bunker / ammo_depot 的补给脉冲。
# 母题是**向上飘的圆点**: 上行运动在这套俯视视角里是唯一不会和"爆炸向外炸开"
# 混淆的方向, 所以增益类效果全部走上行, 伤害类全部走放射。

def build_heal_pulse(frame):
    """剪影 = **窄而高的竖向光柱**。全批唯一的竖向各向异性图形。

    刻意不做成放射状: 放射状是这批里最拥挤的赛道 (emp/reward/frost 都在那),
    而一根竖柱在 48px 下即使糊成一团, 宽高比也还在, 这是能扛住降采样的特征。
    """
    objs = []
    t = frame / float(N_FRAMES - 1)
    ign = _ignition(frame, 0.60)

    mat_mote = create_clay_mat(f"m_heal_m_{frame}", (0.46, 0.92, 0.50, 1.0),
                               emission=(0.38, 0.96, 0.44, 1.0), emission_str=1.8)
    mat_core = create_clay_mat(f"m_heal_c_{frame}", (0.88, 1.00, 0.82, 1.0),
                               emission=(0.88, 1.00, 0.82, 1.0), emission_str=2.4)

    # 贴地的窄底座: 交代"从这里升起", 同时把重心压在下方
    if frame <= 3:
        base_w = 0.52 * (1.0 - t * 0.4) * ign
        objs.append(_sphere(base_w, (0, -1.05 + t * 0.25, -0.05), mat_core, squash=0.30))

    # 光柱本体: 一列上升的光点, 横向抖动很小 (±0.30), 纵向铺满画幅
    # 光点越接近画幅上沿越小, 到边之前就收没 —— 不能让它们撞着边界被切掉。
    #
    # 画幅半高 = ORTHO_SCALE_DEFAULT/2 = 1.65, 光点半径最大 0.30, 所以圆心超过
    # 1.35 就会贴边。早一版按 rise > 1.55 直接剔除, 于是 f3 顶边有 8% 实心被
    # 硬切 (qa_style_consistency.py 的 clip 检查报了出来), 播放时是"光点走到
    # 顶上被剪掉"而不是"升上去散掉"。
    TOP_FADE = 0.75      # 从这个高度开始收
    TOP_LIMIT = 1.32     # 到这个高度彻底消失 (1.65 - 最大半径 0.30, 留点余量)

    n = 11
    for i in range(n):
        jx = (-0.30 + 0.60 * (((i * 7) % 5) / 4.0))
        rise = -0.95 + t * 1.75 + (i / float(n)) * 1.55
        if rise > TOP_LIMIT:
            continue
        rad = (0.30 - t * 0.155) * (0.72 + 0.28 * (((i * 3) % 4) / 3.0)) * ign
        if rise > TOP_FADE:
            rad *= max(0.0, 1.0 - (rise - TOP_FADE) / (TOP_LIMIT - TOP_FADE))
        if rad <= 0.028:
            continue
        objs.append(_sphere(rad, (jx, rise, 0.05), mat_mote, squash=0.92))

    return objs


# ==================== 2. EMP / 干扰脉冲 (EMP PULSE) ====================
#
# 用在: emp_tower / signal_jammer_tower / radar_station。
# 母题是**断开的弧段**。和通用冲击波的关键区别就在"断": 一个完整的实心圆环
# 读作物理冲击, 一圈断续的弧段读作电流/扫描。48px 下这个区别仍然成立, 因为
# 缺口是剪影级别的特征, 而颜色不是。

def build_emp_pulse(frame):
    objs = []
    t = frame / float(N_FRAMES - 1)

    mat_arc = create_clay_mat(f"m_emp_a_{frame}", (0.34, 0.86, 1.00, 1.0),
                              emission=(0.30, 0.88, 1.00, 1.0), emission_str=2.4)
    mat_bolt = create_clay_mat(f"m_emp_b_{frame}", (0.86, 0.98, 1.00, 1.0),
                               emission=(0.86, 0.98, 1.00, 1.0), emission_str=3.0)

    ign = _ignition(frame, 0.46)

    # 剪影 = **大空心环**: 中心必须是空的, 那是这组唯一扛得住 48px 的特征。
    # 所以中心的电弧核只在 f0 出现一瞬 (交代脉冲从塔上发出), 之后彻底让位。
    r_cur = (0.34 + t * 1.12) * (0.55 if frame == 0 else 1.0)

    # 变细的速度必须压过半径变大的速度, 否则这组永远不消散。
    #
    # 这是环形特效独有的陷阱, 值得记一笔: 环的墨量 ~ 周长 x 粗细 ~ r x thick。
    # 第一版 thick 从 0.175 线性掉到 0.10 (x0.57), 而 r 从 0.34 涨到 1.46
    # (x4.3) —— 乘起来是*涨*的, 于是峰值跑到 f3、末帧还有峰值的 74%, 违反
    # "先胀后消"。要让 r x thick 下降, thick 至少得掉得比 1/r 更快。
    thick = max(0.026, 0.185 - t * 0.150) * ign

    n_seg = 5
    # 后段连点数一起减: 弧段散成零星几点, 比"整圈变细"更像电流耗尽
    n_dot = 5 if frame <= 2 else (4 if frame == 3 else 3)
    arc_span = 0.66
    for i in range(n_seg):
        base_ang = (i / float(n_seg)) * math.tau + frame * 0.26
        # 每段用几颗球串成圆弧 —— 段与段之间的缺口就是"断续", 整圈 torus 做不出
        for k in range(n_dot):
            a = base_ang + (k / float(max(1, n_dot - 1)) - 0.5) * arc_span
            objs.append(_sphere(thick,
                                (math.cos(a) * r_cur, math.sin(a) * r_cur, 0.0),
                                mat_arc, squash=0.60, jitter=0.005))

    if frame == 0:
        objs.append(_sphere(0.34, (0, 0, 0.10), mat_bolt, squash=0.7))

    return objs


# ==================== 3. 战利品爆发 (REWARD BURST) ====================
#
# 用在: treasure_chest / treasure_key / 金币与宝石拾取。
# 母题是**四角星芒**。星芒是全项目里只属于奖励的形状 —— 敌人词汇是金色描边
# (见 CLAUDE.md 关于 tile_steel 那段: 金色已经被"敌人"占用), 所以这里靠形状
# 而不是靠金色来承担辨识, 颜色只是加成。

def build_reward_burst(frame):
    objs = []
    t = frame / float(N_FRAMES - 1)

    mat_star = create_clay_mat(f"m_rw_s_{frame}", (1.00, 0.86, 0.34, 1.0),
                               emission=(1.00, 0.82, 0.28, 1.0), emission_str=2.0)
    mat_hot = create_clay_mat(f"m_rw_h_{frame}", (1.00, 0.98, 0.82, 1.0),
                              emission=(1.00, 0.98, 0.82, 1.0), emission_str=2.8)

    ign = _ignition(frame, 0.58)

    # 剪影 = **实心亮核 + 四根细长射线**。和 emp 的空心环正好互补 (中心实 vs
    # 中心空), 和 frost 的散块也不一样 (那边没有中心质量)。
    core = (0.62 - t * 0.40) * ign
    if core > 0.05:
        objs.append(_sphere(core, (0, 0, 0.10), mat_hot, squash=0.80))

    # 四根贯穿画幅的细射线: 长度随帧增长, 粗细随帧变细 —— 长而细的十字在 48px
    # 下仍然读作"星", 而一圈小点只会读作"一堆点"。
    n_ray = 4
    for i in range(n_ray):
        ang = i * (math.tau / 4.0) + 0.39 + frame * 0.16
        L = (0.75 + t * 0.95) * ign
        w = max(0.030, (0.155 - t * 0.098)) * ign
        objs.append(_block((L, w, w), (math.cos(ang) * L * 0.62, math.sin(ang) * L * 0.62, 0.06),
                           mat_star, rot=(0, 0, ang), bevel=0.02))

    # 少量外飞的碎星, 让末段不至于只剩一个核
    for i in range(4):
        ang = i * (math.tau / 4.0) + 0.79
        d = 0.35 + t * 0.95
        s = (0.20 - t * 0.135) * ign
        if s <= 0.026:
            continue
        objs.append(_sphere(s, (math.cos(ang) * d, math.sin(ang) * d, 0.04), mat_hot, squash=0.85))

    return objs


# ==================== 4. 冰霜碎裂 (FROST SHATTER) ====================
#
# 用在: MAMMOTH_BOSS 的冰霜新星命中、冰面碎裂。
# 母题是**带棱角的碎片**。和 clay_debris 的圆润碎块刻意相反 —— 冰要"锐",
# 靠倒角宽度 (0.02 对 clay_debris 的圆润) 和随机旋转把棱角留在剪影上。

def build_frost_shatter(frame):
    objs = []
    t = frame / float(N_FRAMES - 1)

    # 要**亮**且饱和的冰蓝, 不是压暗的深蓝 —— 这里踩过一次反直觉的坑。
    #
    # 碎冰和通用 dust_puff (暖白灰) 在 48px 下一度只差 12.0, 贴着门槛。第一反应
    # 是"把蓝色压深拉开对比", 结果距离**反而掉到 11.7**。原因在指标本身:
    # test_semantic_vfx.gd 比的是*预乘 alpha* 的通道差, 把颜色压暗会让预乘值
    # 趋近 0, 也就是趋近空背景 —— 而扬尘本来就稀疏, 于是两者更像了。
    #
    # 拉开的正确方向是提高预乘幅值并把色相拉到红通道的反面: 亮的高饱和蓝在 R
    # 通道上和暖白灰差最多, 同时整体不掉亮度。
    mat_ice = create_clay_mat(f"m_fr_i_{frame}", (0.30, 0.74, 1.00, 1.0),
                              roughness=0.22, sss_weight=0.30,
                              emission=(0.26, 0.72, 1.00, 1.0), emission_str=1.70)
    mat_rime = create_clay_mat(f"m_fr_r_{frame}", (0.55, 0.88, 1.00, 1.0),
                               roughness=0.30, sss_weight=0.26,
                               emission=(0.45, 0.82, 1.00, 1.0), emission_str=0.90)

    ign = _ignition(frame, 0.56)

    # 剪影 = **少数几块大碎片**, 不是一圈小碎屑。
    #
    # 第一版用了 9 块小的, 缩到 48px 之后和 emp 的一圈小点、reward 的一圈小星
    # 全糊成同一个东西 (实测两两距离 8.4 / 9.9, 低于现役基线 14.4)。改成 4 块
    # 大的之后, 不规则的块状剪影本身就是识别特征 —— 大块扛得住降采样, 小块不行。
    n = 4
    for i in range(n):
        ang = (i / float(n)) * math.tau + 0.42
        dist = 0.16 + t * 0.98
        s = (0.76 - t * 0.485) * (0.78 + 0.22 * ((i * 7) % 3) / 2.0) * ign
        if s <= 0.040:
            continue
        objs.append(_block((s * 1.35, s * 0.92, s * 0.58),
                           (math.cos(ang) * dist, math.sin(ang) * dist, 0.05 + t * 0.10),
                           mat_ice if i % 2 else mat_rime,
                           rot=(0.30 * i, 0.20 * i, ang + frame * 0.22),
                           bevel=0.025))

    # 几片小的填在大块之间, 避免剪影过于规整
    for i in range(3):
        ang = (i / 3.0) * math.tau - 0.55
        d = 0.30 + t * 0.72
        s = (0.24 - t * 0.16) * ign
        if s <= 0.028:
            continue
        objs.append(_block((s * 1.3, s * 0.9, s * 0.55),
                           (math.cos(ang) * d, math.sin(ang) * d, 0.04),
                           mat_rime, rot=(0.4 * i, 0.3 * i, ang), bevel=0.02))

    return objs


# ==================== 5. 破土喷发 (SAND BURST) ====================
#
# 用在: SANDWORM 的钻地/破土、沙漠地形受击。
# 母题是**上抛后沉降的土块**: 前段一个隆起的土丘, 中段炸开成分离的小块,
# 末段小块缩小并落回 —— 这条曲线就是 CLAUDE.md 要求的"消散", 末帧的总墨量
# 必须明显低于峰值, 否则动画会以全序列最大最实的一团收尾。

def build_sand_burst(frame):
    objs = []
    t = frame / float(N_FRAMES - 1)

    mat_sand = create_clay_mat(f"m_sd_s_{frame}", (0.86, 0.70, 0.42, 1.0), roughness=0.88)
    mat_dark = create_clay_mat(f"m_sd_d_{frame}", (0.62, 0.47, 0.28, 1.0), roughness=0.90)

    ign = _ignition(frame, 0.55)

    # 剪影 = **宽而扁、重心贴底的土丘**。和 heal 的窄高光柱正好是相反的
    # 各向异性 —— 一个 2.4:1 横，一个 1:2.5 竖, 这两个在 48px 下绝不会认错。
    #
    # 土丘必须*渐次*收掉, 不能说没就没: 早一版让它只存在于 f0/f1, 实测覆盖率
    # 13.7% -> 2.6% 一帧掉 5 倍, 播出来是一次硬切而不是喷发。
    if frame <= 3:
        mound_w = [0.55, 1.15, 0.92, 0.52][frame]
        mound_z = [-0.60, -0.52, -0.62, -0.78][frame]
        bpy.ops.mesh.primitive_uv_sphere_add(radius=mound_w, location=(0, mound_z, -0.05))
        mound = bpy.context.active_object
        mound.scale = (1.35, 0.62, 0.34)   # 横向拉宽、纵向压扁
        mound.data.materials.append(mat_dark)
        apply_clay_jitter(mound, strength=0.012)
        bpy.ops.object.shade_smooth()
        objs.append(mound)

    # 抛飞的土块也压在下半幅, 横向铺开 —— 保持"宽而低"的整体占位。
    #
    # 扩散幅度要收着点: 早一版 dist 到 1.49 再乘 1.35 横向系数 = 2.0, 而画幅
    # 半宽只有 ORTHO_SCALE_DEFAULT/2 = 1.65 —— 末帧土块全飞出画外, 覆盖率只剩
    # 0.27%, test_explosion_vfx.gd 判为"几乎全透明"。消散不等于清空: 末帧要
    # 还看得见几块正在落地的土, 否则播出来是啪一下消失而不是散掉。
    n = 9
    for i in range(n):
        ang = (i / float(n)) * math.pi + 0.14      # 只用上半圆 -> 向上抛
        dist = 0.24 + t * 0.92
        lift = math.sin(min(1.0, t * 1.1) * math.pi) * 0.55 - 0.35
        s = (0.30 - t * 0.150) * (0.65 + 0.35 * ((i * 5) % 4) / 3.0) * ign
        if s <= 0.028:
            continue
        objs.append(_block((s * 1.30, s * 1.05, s * 0.78),
                           (math.cos(ang) * dist * 1.25, math.sin(ang) * dist * 0.55 + lift, 0.05),
                           mat_sand if i % 3 else mat_dark,
                           rot=(0.4 * i, 0.3 * i, ang),
                           bevel=0.035))

    return objs


# ==================== 6. 建造合拢 (BUILD ASSEMBLE) ====================
#
# 用在: builder_controller 放置建筑的落成瞬间。
#
# **这一组是故意反着来的。** 别的都向外扩散并消散, 它向内收敛并在末帧最实 ——
# 因为它演的是"东西被造出来了", 收束感就是它要传达的全部内容。不要给它套
# 那条"末帧必须小于峰值一半"的爆炸断言, 那会把它改坏。

def build_build_assemble(frame):
    objs = []
    t = frame / float(N_FRAMES - 1)

    mat_clay = create_clay_mat(f"m_ba_c_{frame}", (0.80, 0.62, 0.44, 1.0), roughness=0.82)
    mat_edge = create_clay_mat(f"m_ba_e_{frame}", (0.55, 0.72, 0.86, 1.0),
                               emission=(0.45, 0.70, 0.95, 1.0), emission_str=1.3)

    # 四块从外向内合拢的构件, 末帧拼成一个整块。
    #
    # 块要够大: 用小块时实测和通用 dust_puff 只差 11.7 (低于现役基线 14.4),
    # 因为"几团中等大小的软斑"在 48px 下和扬尘没区别。四个明确的方形色块才
    # 有几何感 —— 直角是扬尘/碎屑永远做不出的剪影特征。
    n = 4
    for i in range(n):
        ang = (i / float(n)) * math.tau + math.pi / 4.0
        dist = 1.05 * (1.0 - t) + 0.30 * t          # 1.05 -> 0.30, 收敛
        s = 0.40 + t * 0.20                          # 越靠近越大, 强化"落位"
        objs.append(_block((s * 1.05, s * 1.05, s * 0.70),
                           (math.cos(ang) * dist, math.sin(ang) * dist, 0.06),
                           mat_clay, rot=(0, 0, ang * (1.0 - t)), bevel=0.06))

    # 落位提示环: 和 heal 的扩散环相反, 这个是*收紧*的
    r_ring = 1.20 * (1.0 - t) + 0.52 * t
    bpy.ops.mesh.primitive_torus_add(major_radius=r_ring, minor_radius=0.072,
                                     location=(0, 0, -0.10))
    ring = bpy.context.active_object
    ring.scale = (1.0, 1.0, 0.5)
    ring.data.materials.append(mat_edge)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    return objs


# ==================== 7. 弹开 / 打不穿 (RICOCHET SPARK) ====================
#
# 用在: 子弹打在 border / steel / 有壳建筑上 —— 也就是**打了但没用**。
#
# 为什么值得单独出一组: 数过调用点, spawn_shockwave 有 82 处, 其中"命中
# border/steel/buildings"占 17 处, "建筑被摧毁"占 10 处 —— 同一个灰环既在说
# "你打不动这个", 又在说"这个被你打没了"。这两件事玩家的下一步动作完全相反
# (换目标 vs 继续推进), 却长得一模一样。
#
# 母题是**冷钢火星**: 短粗的放射钉 + 一颗只活两帧的硬芯。三处刻意的取舍:
#   - 颜色走冷白偏青 (0.88,0.96,1.0), 不走暖橙。全批的暖色都归"燃烧/伤害",
#     金属撞金属该是冷的; 顺带这也是 48px 下和 muzzle_flash / explosion 拉开
#     距离的主要手段 —— 指标比的是预乘 RGB, 色相差是实打实的距离。
#   - 钉子**短而粗**, 不做成 reward_burst 那种细长射线。两者都是"核心 + 放射",
#     区分只能落在长细比上。
#   - 硬芯到 f2 就没了, 之后只剩钉子向外散。reward_burst 反过来, 核心一直在。
#     这是运动上的区别, 静帧指标看不见, 但播放时一眼可辨。

def build_ricochet_spark(frame):
    """剪影 = **短粗放射钉的星芒**, 冷白偏青, 硬芯只活到 f2。"""
    objs = []
    mat_spike = create_clay_mat(f"m_ric_s_{frame}", (0.88, 0.96, 1.00, 1.0),
                                emission=(0.82, 0.94, 1.00, 1.0), emission_str=2.6)
    mat_core = create_clay_mat(f"m_ric_c_{frame}", (1.00, 1.00, 1.00, 1.0),
                               emission=(0.94, 0.99, 1.00, 1.0), emission_str=3.0)

    # 逐帧手写而不是用连续公式 —— 覆盖率要同时满足三条硬约束 (首帧 < 峰值 60%、
    # 峰值在中段、末帧 < 峰值 50%), 而覆盖率随长x宽走, 连续公式很难三条都卡住。
    # 见 tools/test_explosion_vfx.gd::_check_sequence。
    #        内半径  钉长   钉宽   芯半径
    TABLE = [(0.16,  0.16,  0.18,  0.20),   # f0 撞击瞬间: 一小团, 钉还没抽出来
             (0.30,  0.44,  0.24,  0.15),   # f1
             (0.42,  0.58,  0.19,  0.09),   # f2 峰值
             (0.56,  0.62,  0.13,  0.00),   # f3 芯没了
             (0.68,  0.66,  0.085, 0.00),   # f4
             (0.78,  0.70,  0.055, 0.00)]   # f5 只剩细屑
    r0, spike_len, spike_w, core_r = TABLE[frame]

    if core_r > 0.0:
        objs.append(_sphere(core_r, (0, 0, 0.06), mat_core, squash=0.85, jitter=0.0))

    # 6 根钉。角度上加一点固定偏移, 免得正好水平/垂直 —— 正交轴向的直线在
    # 降采样后会和瓦片网格的方向对齐, 读起来像界面元素而不是碎屑。
    n = 6
    for i in range(n):
        ang = (i / float(n)) * 2.0 * math.pi + 0.26
        cx = math.cos(ang) * (r0 + spike_len * 0.5)
        cy = math.sin(ang) * (r0 + spike_len * 0.5)
        objs.append(_block((spike_len, spike_w, 0.10), (cx, cy, 0.05), mat_spike,
                           rot=(0.0, 0.0, ang), bevel=0.03))
    return objs


# ==================== 8. 受伤未死 (HIT SPALL) ====================
#
# 用在: take_damage —— 打中了、掉血了, 但目标还站着。
#
# 现在这件事和"目标被摧毁"共用 spawn_clay_debris (74 处调用里 take_damage 占
# 14 处、destroy/_destroy 占 13 处)。"还能打" 和 "已经没了" 是玩家最需要区分的
# 一对反馈, 却是同一张图。
#
# 母题是**偏心**: 碎块全部甩向一侧, 加上撞击点那道短弧。整批特效只有这一组不是
# 中心对称的 —— 而偏心是极少数能扛住 5.33 倍降采样的特征之一 (同 heal_pulse 的
# 竖向各向异性、sand_burst 的重心贴底是同一类手段)。
#
# 方向固定不跟着弹道转, 这是有意的: VFXAnimator 的接口只收位置不收方向, 而
# sand_burst / heal_pulse 同样是固定朝向, 已经证明在这套俯视视角下读得通。
# 真要跟着弹道转, 得先给整个 VFXAnimator 加一个方向参数, 那是另一件事。

def build_hit_spall(frame):
    """剪影 = **整团偏向一侧的崩落**。全批唯一重心明显离开画幅中心的图形。

    第一版没做到这一点, 而且是量出来才发现的: 碎块甩向右下, 撞击弧却放在左上,
    两者正好抵消 —— 实测重心只偏了 (1.4, 0.6) 像素, 等于中心对称。于是它和
    clay_debris 在 48px 下只差 11.9, 低于阈值 12.0。

    更要紧的是搞清了**为什么**撞: clay_debris 峰值覆盖率只有 2.8%, 是个稀疏
    散点效果; 第一版的 spall 同样是几块彼此分开的小碎块散在相近半径上。两者
    共用"稀疏散布"这个足迹, 而颜色差再大也盖不过足迹 —— spall 的平均色已经是
    (255,255,246) 纯白、clay_debris 是 (167,115,74) 暖棕, 差到不能再差, 距离
    还是不够。**这个指标里足迹压过颜色。**

    所以第二版改的是拓扑而不是配色: 碎块收紧、放大、互相重叠成**一整团**
    (连续块 vs 散点), 撞击弧移到同一侧的内缘, 让重心真的甩出去。
    """
    objs = []
    # 骨白偏暖 —— 是被削下来的材料本身, 不是火。刻意不压暗: CLAUDE.md 记过
    # 把特效调暗反而让它更难区分 (指标是预乘 RGB, 变暗就是朝透明背景靠)。
    # 自发光从 0.9 降到 0.55: 第一版整团糊成纯白, 连黏土的明暗都没了。
    mat_chip = create_clay_mat(f"m_spall_p_{frame}", (0.95, 0.92, 0.86, 1.0),
                               emission=(0.88, 0.84, 0.76, 1.0), emission_str=0.55)
    mat_arc = create_clay_mat(f"m_spall_a_{frame}", (1.00, 0.96, 0.88, 1.0),
                              emission=(1.00, 0.95, 0.86, 1.0), emission_str=2.0)

    #        团心距离 碎块尺寸 弧半径 弧珠半径
    TABLE = [(0.20,   0.30,   0.16,  0.13),   # f0
             (0.44,   0.52,   0.30,  0.24),   # f1
             (0.60,   0.62,   0.38,  0.26),   # f2 峰值
             (0.78,   0.50,   0.46,  0.18),   # f3
             (0.94,   0.34,   0.52,  0.11),   # f4
             (1.08,   0.20,   0.58,  0.06)]   # f5
    throw, chip, arc_r, bead = TABLE[frame]

    # 碎块: 张角收到 ±26°, 距离扰动也收窄, 七块因此互相重叠成一整团而不是
    # 一堆散点 —— 这是和 clay_debris 拉开距离的主要手段之一。
    #
    # 另一半是**把量做够**, 这条是第二次量完才想明白的: 两个稀疏且几乎不重叠
    # 的特效, 这个指标其实由双方的总墨量决定 (差值 ≈ 各自亮度之和), 跟"看起来
    # 像不像"关系不大。第二版把重心从 (1.4,0.6) 甩到 (37,31) 像素、拓扑彻底
    # 变了, 距离却只从 11.9 动到 11.8 —— 因为峰值覆盖率还是 3.7%, 对方
    # clay_debris 也只有 2.8%, 两个都太薄。峰值提到 ~9% 之后才真正拉开。
    # 参照: 现役 dust_puff 11.6%、explosion 19%; 本文件顶部记的"新特效太稀薄"
    # 说的就是这件事。
    base_ang = math.radians(-40.0)
    for i in range(7):
        ang = base_ang + math.radians(-26.0 + 8.7 * i)
        d = throw * (0.84 + 0.16 * ((i * 3) % 4) / 3.0)
        k = chip * (0.80 + 0.20 * ((i * 5) % 3) / 2.0)
        objs.append(_block((k, k * 0.76, 0.12),
                           (math.cos(ang) * d, math.sin(ang) * d, 0.05),
                           mat_chip, rot=(0.0, 0.0, ang + 0.4), bevel=0.04))

    # 撞击短弧: 和碎块**同侧**, 压在团的内缘。第一版放在反侧, 把偏心抵消掉了。
    if bead > 0.03:
        for j in (-1, 0, 1):
            a = base_ang + j * 0.40
            objs.append(_sphere(bead * (1.0 if j == 0 else 0.78),
                                (math.cos(a) * arc_r, math.sin(a) * arc_r, 0.06),
                                mat_arc, squash=0.75, jitter=0.006))
    return objs


# ---------------------------------------------------------------- 注册表

GROUPS = {
    "heal_pulse":     (build_heal_pulse,     "vfx_heal_pulse_f{i}.png"),
    "emp_pulse":      (build_emp_pulse,      "vfx_emp_pulse_f{i}.png"),
    "reward_burst":   (build_reward_burst,   "vfx_reward_burst_f{i}.png"),
    "frost_shatter":  (build_frost_shatter,  "vfx_frost_shatter_f{i}.png"),
    "sand_burst":     (build_sand_burst,     "vfx_sand_burst_f{i}.png"),
    "build_assemble": (build_build_assemble, "vfx_build_assemble_f{i}.png"),
    "ricochet_spark": (build_ricochet_spark, "vfx_ricochet_spark_f{i}.png"),
    "hit_spall":      (build_hit_spall,      "vfx_hit_spall_f{i}.png"),
}


def main():
    print(">>> 渲染语义化特效序列 (6 组 x 6 帧)...")
    total = 0
    for name, (builder, tmpl) in GROUPS.items():
        print(f">>> {name}")
        for i in range(N_FRAMES):
            # 每帧重建场景。clear_scene() 不是可选项: 少了它上一帧的网格会留在
            # 画面里 —— 当年九张 UI 图渲成同一个灰方块就是这么来的。
            clear_scene()
            setup_render_settings(rx=256, ry=256, samples=28)
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
            reset_jitter_seed(JITTER_SEED + i)
            objs = builder(i)
            render_and_clean(objs, os.path.join(SPRITES_EFFECTS, tmpl.format(i=i)))
            total += 1
    print(f"\n[OK] 已渲染 {len(GROUPS)} 组, 共 {total} 帧。")


if __name__ == "__main__":
    main()
