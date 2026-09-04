"""地形瓦片差分 (variety + act theme)。

产出 20 张:
    tile_brick_v1/v2                  平原砖的两种"磨损差分"
    tile_brick_a2 / a2_v1 / a2_v2     沙漠主题砖 (3 张)
    tile_brick_a3 / a3_v1 / a3_v2     冰川主题砖 (3 张)
    tile_steel_*                      同上, 8 张
    tile_sand_v1/v2                   沙地波纹差分
    tile_trees_v1/v2                  树丛树冠差分

=== 为什么是包装器, 不是第二套几何 ===

这里**一行几何都不抄**: 每个变体都先调属主脚本的 builder (build_sokpop_brick /
build_sokpop_steel / build_desert_sand_tile / build_sokpop_trees), 拿到对象列表
之后再做两件事 —— 换材质、往画幅内部加装饰。

理由是 CLAUDE.md "陈旧 build 脚本"那一节反复踩过的坑: 没有任何机制规定谁是某
张图的属主, 重叠的脚本互相覆盖, 谁最后跑谁赢。砖块的排布更是出了名的娇气 ——
砖长/砖缝/行距全部由画幅周期 P 推导, 骑缝那块砖的左右两半必须严丝合缝, 还要
补一圈周期副本才能让影子接得上。把这套东西复制一份到变体脚本里, 等于给自己
埋第二个会漂移的属主。走包装器则相反: 属主脚本以后怎么改, 变体自动跟着改。

=== 无缝约束: 变体只准动画幅内部 ===

瓦片是自己挨着自己铺的, 而**同一张地图上相邻两格可能是不同变体**。所以变体
之间必须在边界上逐像素一致, 否则任意两个不同变体贴在一起就是一道缝 —— 这比
"某张图自己不无缝"更隐蔽, 因为单张图铺开测试是过的。

具体到实现, 有三条硬规矩:

1. **骑缝的几何一律不碰。** 砖块奇数行的砖心落在 ±H 上, 那块砖左右各画半块,
   拼起来才是一整块跨缝的顺砌砖; 钢板的 8 颗铆钉同样骑在画幅边线和边中点上,
   四块瓦片各出四分之一颗, 拼成网格顶点上的一颗。动它们任何一个 —— 挪位置、
   换大小、甚至只是"锈蚀掉一颗" —— 都会让变体 A 的半颗对不上变体 B 的半颗。
   代码里靠 `_interior_objects()` 按坐标筛出内部件, 只在内部件上做文章。

2. **装饰的*影子*也不能越界。** 太阳仰角 35°, 影长 = 高/tan(35°) ≈ 1.43×高。
   所以装饰限高 (DECO_MAX_H) 并限制在 |xy| ≤ DECO_REACH 之内, 两者之和留足
   余量到 H=1.65。这跟砖块补周期副本是同一件事的两面: 那边是"画幅外的东西
   要投影进来", 这边是"画幅内的东西不许投影出去"。

3. **换材质只换颜色, 不换粗糙度/凹凸强度。** 主题差分要的是"同一块砖在不同
   气候下的样子", 不是另一种材料。凹凸强度一变, 颗粒尺度跟着变, 而
   CLAUDE.md 记过颗粒是按 Generated 坐标走的 —— 同一块砖的两个主题会呈现
   不同的表面颗粒, 在 48px 下反而比颜色更扎眼。

=== 主题为什么只给砖和钢 ===

沙/冰/树本身就是主题地形 (沙漠出沙、冰川出冰、平原出树), 它们的"主题差分"
就是彼此。砖和钢是仅有的两种在三个 act 的模板里都会出现的瓦片, 也就只有这
两种需要靠配色说明"这是第几幕"。给沙再出一版"冰川的沙"没有对应的模板会用。

配色上有一条不能违反的既有约束 (见 build_sokpop_steel 的注释): 钢和冰是靠
**明度**分开的, 不是靠色相 —— 原先那块金盘顺带承担了这个功能, 拿掉之后交给
了明度。所以 a3 (冰川) 的钢必须比 a1 更*暗*而不是更亮, 否则在满是冰面的冰川
图上, 不可摧毁的钢墙和可以开车压过去的冰面会糊成一片。同理 a2 (沙漠) 的砖
不能往沙色靠 —— 那会让"可摧毁的砖"消失在沙地背景里, 所以走的是加深的赤陶色
而不是顺理成章的沙岩色。

用法:
    blender --background --python tools/build_terrain_variants.py
    blender --background --python tools/build_terrain_variants.py -- tile_brick
    blender --background --python tools/build_terrain_variants.py -- --list
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
    render_and_clean,
    reset_jitter_seed,
    purge_orphans,
    ORTHO_SCALE_DEFAULT,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_brick,
    build_sokpop_steel,
    build_sokpop_trees,
    SPRITES_TILES,
)
from build_desert_mechanics import build_desert_sand_tile

# 和 rerender_tiles.py 同一个基准种子。变体各自偏移, 好让带 jitter 的部件
# (沙地波纹) 在不同变体上呈现不同的微观形状; 砖/钢的 jitter 本来就是 0
# (周期性不允许抖动), 种子对它们没有影响。
JITTER_SEED = 4200

P = ORTHO_SCALE_DEFAULT       # 画幅周期 3.30
H = P * 0.5                   # 半幅 1.65

# 装饰的活动范围与限高。DECO_REACH + DECO_MAX_H * 1.43 (35° 太阳的影长系数)
# 必须小于 H, 否则装饰的影子会甩出画幅, 在拼缝处露出来。
#   1.34 + 0.13 * 1.43 = 1.526 < 1.65  ✓
DECO_REACH = 1.34
DECO_MAX_H = 0.13


# ==================== 主题配色 ====================
#
# 键是属主脚本里的材质名 (m_ub_c = unified brick clay, m_us_p = unified steel
# plate, 依此类推)。Blender 在重名时会加 .001 后缀, 所以匹配前要剥掉。
#
# 覆盖率是被强制的: _retheme() 遇到表里没有的材质名会直接抛异常, 而不是
# 静默跳过。属主脚本改了材质名的话, 这里会当场炸, 而不是渲出一批"某个部件
# 忘了换色"的图 —— 后者正是 CLAUDE.md 里那种"渲染成功了但没人发现不对"的
# 事故形态。
THEME_PALETTES = {
    "a2": {   # 沙漠: 曝晒褪色 + 沙尘覆盖
        # 砖走*加深*的赤陶色而不是沙岩色 —— 见文件头的说明, 往沙色靠会让砖
        # 在沙地背景上消失。砖缝也压暗, 免得浅砖缝自己变成沙色。
        "m_ub_c": (0.80, 0.42, 0.26, 1.0),
        "m_ub_m": (0.72, 0.60, 0.46, 1.0),
        # 钢被沙尘打磨成暖调中灰, 明显暗于浅沙地。
        "m_us_p": (0.66, 0.62, 0.55, 1.0),
        "m_us_r": (0.56, 0.52, 0.46, 1.0),
        "m_us_b": (0.40, 0.37, 0.32, 1.0),
        "m_us_v": (0.86, 0.82, 0.72, 1.0),
    },
    "a3": {   # 冰川: 冷光 + 霜白砖缝
        "m_ub_c": (0.78, 0.42, 0.34, 1.0),
        "m_ub_m": (0.88, 0.92, 0.96, 1.0),
        # 必须比 a1 更暗 —— 冰川图上满地都是 tile_ice (0.76,0.90,0.96 的浅冰
        # 蓝), 钢一旦提亮就和冰撞明度, 而这两者一个不可摧毁一个能开过去。
        "m_us_p": (0.58, 0.64, 0.76, 1.0),
        "m_us_r": (0.49, 0.55, 0.67, 1.0),
        "m_us_b": (0.35, 0.40, 0.52, 1.0),
        "m_us_v": (0.80, 0.86, 0.95, 1.0),
    },
}

# 装饰件自己的配色也随主题走, 否则沙漠砖上长出平原的青苔。
DECO_PALETTES = {
    "a1": {"moss": (0.42, 0.62, 0.30, 1.0), "chip": (0.66, 0.30, 0.18, 1.0),
           "rust": (0.62, 0.36, 0.20, 1.0), "scar": (0.40, 0.44, 0.55, 1.0)},
    "a2": {"moss": (0.72, 0.66, 0.38, 1.0), "chip": (0.56, 0.28, 0.16, 1.0),
           "rust": (0.70, 0.48, 0.24, 1.0), "scar": (0.34, 0.32, 0.27, 1.0)},
    "a3": {"moss": (0.80, 0.88, 0.92, 1.0), "chip": (0.54, 0.28, 0.22, 1.0),
           "rust": (0.52, 0.42, 0.34, 1.0), "scar": (0.30, 0.35, 0.46, 1.0)},
}


def _base_mat_name(mat):
    """剥掉 Blender 的 .001 重名后缀。"""
    name = mat.name
    if len(name) > 4 and name[-4] == '.' and name[-3:].isdigit():
        name = name[:-4]
    return name


def _retheme(objs, theme):
    """把整批对象的材质换成主题配色。

    不改 roughness / bump_strength —— 只换 Base Color。见文件头第 3 条。
    """
    if theme == "a1":
        return
    palette = THEME_PALETTES[theme]
    for obj in objs:
        if obj.type != 'MESH':
            continue
        for slot_i, slot in enumerate(obj.material_slots):
            if slot.material is None:
                continue
            key = _base_mat_name(slot.material)
            if key not in palette:
                raise RuntimeError(
                    f"[主题配色表缺项] 材质 {key!r} (对象 {obj.name}) 不在 "
                    f"THEME_PALETTES[{theme!r}] 里。属主脚本大概改了材质名 —— "
                    f"把新名字补进表里, 别让它静默地保持原色渲出去。")
            obj.material_slots[slot_i].material = create_clay_mat(
                f"{key}_{theme}", palette[key])


def _interior_objects(objs, reach=DECO_REACH, min_z=0.05):
    """筛出"完全在画幅内部"的部件 —— 骑缝的那些一概排除。

    砖块奇数行有两块砖心在 ±H 上 (骑缝), 钢板 8 颗铆钉全部骑在边线/边中点上。
    这些是相邻瓦片拼合的接口, 变体之间必须逐像素一致, 所以不参与任何差分。
    """
    out = []
    for o in objs:
        if o.type != 'MESH':
            continue
        loc = o.location
        if abs(loc.x) <= reach and abs(loc.y) <= reach and loc.z >= min_z:
            out.append(o)
    return out


def _deco_box(loc, scale, mat, bevel=0.03, rot_z=0.0):
    """加一块装饰用小体块, 并强制限高 —— 影子不许甩出画幅。"""
    x, y, z = loc
    if abs(x) > DECO_REACH or abs(y) > DECO_REACH:
        raise RuntimeError(f"装饰件 {loc} 超出 DECO_REACH={DECO_REACH}, 影子会越过拼缝")
    if scale[2] > DECO_MAX_H:
        raise RuntimeError(f"装饰件高 {scale[2]} 超出 DECO_MAX_H={DECO_MAX_H}")
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z))
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = (0, 0, rot_z)
    o.data.materials.append(mat)
    apply_uniform_clay_bevel(o, width=bevel, segments=2, jitter=0.0)
    return o


# ==================== 砖块差分 ====================

def brick_variant(variant, theme):
    """v0=原样, v1=崩角磨损, v2=苔藓/风化附着。"""
    objs = build_sokpop_brick()
    _retheme(objs, theme)
    if variant == 0:
        return objs

    pal = DECO_PALETTES[theme]
    inner = _interior_objects(objs)
    # 砖顶面在 z=0.26, 砖缝面在 z=0.0 (见 build_sokpop_brick 的尺寸)。
    inner.sort(key=lambda o: (round(o.location.y, 3), round(o.location.x, 3)))

    if variant == 1:
        # 崩角: 在内部砖的角上抠掉一块 —— 这里不做布尔运算 (布尔会改砖的
        # 网格, 而砖的网格是周期副本共享的模板), 而是贴一块压暗的"缺口填充
        # 块", 低于砖面。48px 下缺角读出来的是轮廓上的一个暗点, 效果一样,
        # 代价小得多。
        mat_chip = create_clay_mat(f"m_bv_chip_{theme}", pal["chip"], roughness=0.88)
        for i, b in enumerate(inner[:4]):
            sx = 0.34 if i % 2 == 0 else 0.28
            ox = (0.52 if i % 2 == 0 else -0.48)
            oy = (0.20 if i < 2 else -0.20)
            _deco_box((b.location.x + ox, b.location.y + oy, 0.22),
                      (sx, 0.26, 0.10), mat_chip, bevel=0.04,
                      rot_z=math.radians(6 * (1 if i % 2 else -1)))
            objs.append(bpy.context.active_object)
        # 两块整砖换成压暗的"旧砖", 让整面墙出现色斑而不是均匀一片。
        mat_old = create_clay_mat(f"m_bv_old_{theme}", pal["chip"], roughness=0.90)
        for b in inner[1::3][:2]:
            b.material_slots[0].material = mat_old

    elif variant == 2:
        # 苔藓/霜/沙尘: 沿*内部*砖缝铺低矮附着物。砖缝在 y = 砖心 ± 0.4125,
        # 这里直接取内部砖的相对偏移, 不重算行距 —— 行距是从画幅周期推导的,
        # 抄一遍就是又一处会漂移的常量。
        mat_moss = create_clay_mat(f"m_bv_moss_{theme}", pal["moss"],
                                   roughness=0.94, bump_strength=0.34)
        for i, b in enumerate(inner):
            side = 1.0 if i % 2 == 0 else -1.0
            bx = b.location.x + (0.30 * side)
            by = b.location.y + (0.33 * side)
            if abs(bx) > DECO_REACH or abs(by) > DECO_REACH:
                continue
            _deco_box((bx, by, 0.045), (0.62 + 0.1 * (i % 3), 0.16, 0.06),
                      mat_moss, bevel=0.03, rot_z=math.radians(3 * side))
            objs.append(bpy.context.active_object)
        # 几簇爬上砖面的
        for i, b in enumerate(inner[::2]):
            _deco_box((b.location.x - 0.30, b.location.y, 0.30),
                      (0.30, 0.22, 0.05), mat_moss, bevel=0.03)
            objs.append(bpy.context.active_object)

    return objs


# ==================== 钢板差分 ====================

def steel_variant(variant, theme):
    """v0=原样, v1=锈蚀/沙蚀斑, v2=焊补与刻痕。"""
    objs = build_sokpop_steel()
    _retheme(objs, theme)
    if variant == 0:
        return objs

    pal = DECO_PALETTES[theme]
    # 钢板中央有个半径 0.52 的凸台, 十字加强筋半宽 0.23 —— 装饰要避开,
    # 否则叠在凸台上读起来像"钢板中间长了个东西"而不是"钢板锈了"。
    def _free(x, y):
        if math.hypot(x, y) < 0.72:
            return False
        if abs(y) < 0.32 or abs(x) < 0.32:
            return False
        return abs(x) <= DECO_REACH and abs(y) <= DECO_REACH

    if variant == 1:
        mat_rust = create_clay_mat(f"m_sv_rust_{theme}", pal["rust"],
                                   roughness=0.95, bump_strength=0.36)
        spots = [(-1.02, -0.92, 0.62, 0.48), (0.96, 0.88, 0.54, 0.40),
                 (1.05, -0.78, 0.40, 0.52), (-0.82, 1.02, 0.44, 0.36),
                 (0.62, -1.15, 0.34, 0.30)]
        for (x, y, sx, sy) in spots:
            if not _free(x, y):
                continue
            _deco_box((x, y, 0.38), (sx, sy, 0.05), mat_rust, bevel=0.05,
                      rot_z=math.radians(18 if x > 0 else -14))
            objs.append(bpy.context.active_object)

    elif variant == 2:
        mat_scar = create_clay_mat(f"m_sv_scar_{theme}", pal["scar"],
                                   roughness=0.62, bump_strength=0.20)
        # 刻痕: 细长压暗条, 明确不与画幅边相交
        scars = [(-0.95, -0.95, math.radians(38), 1.05),
                 (0.90, 0.72, math.radians(-24), 0.85),
                 (0.98, -0.95, math.radians(62), 0.70)]
        for (x, y, rot, length) in scars:
            if not _free(x, y):
                continue
            _deco_box((x, y, 0.375), (length, 0.09, 0.04), mat_scar,
                      bevel=0.02, rot_z=rot)
            objs.append(bpy.context.active_object)
        # 焊补板: 一块厚一点、带自己铆钉的补丁
        mat_patch = create_clay_mat(f"m_sv_patch_{theme}",
                                    THEME_PALETTES.get(theme, {}).get(
                                        "m_us_r", (0.60, 0.64, 0.75, 1.0)),
                                    roughness=0.55)
        _deco_box((-0.95, 0.92, 0.40), (0.70, 0.62, 0.09), mat_patch,
                  bevel=0.05, rot_z=math.radians(-10))
        objs.append(bpy.context.active_object)
        mat_rivet = create_clay_mat(f"m_sv_prv_{theme}", (0.88, 0.90, 0.95, 1.0),
                                    roughness=0.40)
        for (dx, dy) in [(-0.24, 0.20), (0.24, 0.20), (-0.24, -0.20), (0.24, -0.20)]:
            bpy.ops.mesh.primitive_uv_sphere_add(
                radius=0.075, location=(-0.95 + dx, 0.92 + dy, 0.45))
            r = bpy.context.active_object
            r.data.materials.append(mat_rivet)
            bpy.ops.object.shade_smooth()
            objs.append(r)

    return objs


# ==================== 沙地差分 ====================

def sand_variant(variant, theme="a1"):
    """v0=原样, v1=风蚀沙脊, v2=干裂龟纹 + 碎石。

    === 为什么沙地的装饰必须做得比砖/钢重得多 ===

    沙地是全项目唯一一块"几乎没有内部结构"的满幅瓦片, 这让它撞上了黏土管线
    的一个结构性限制: create_clay_mat 的凹凸/色斑噪声挂在 Generated (包围盒
    归一化) 坐标上, **不是周期的** —— 瓦片首行和末行采到的是两处不相干的
    噪声值。砖和钢无所谓, 它们内部本来就有 20~35 的梯度, 噪声那点差异淹没在
    里面; 沙地内部梯度只有 1.5~3.7, 于是噪声本底 (实测 6.0) 反而成了最大的
    行间差。

    实测过, 也排除过别的解释: 把底板的顶点抖动关掉 (jitter 0.008 -> 0) 拼接
    梯度反而从 5.99 变成 6.25, 所以不是抖动把底板抻歪了; 上下 6.0 而左右只有
    1.6, 也符合"噪声 + 定向光"而不是几何越界。把噪声改成世界坐标周期的那条路
    CLAUDE.md 已经试过并否决 (48px 显示尺寸下离散更差、瓦片质感掉 21%)。

    所以这里不放宽 qa_style_consistency 的容忍地板 (那会让真接缝也漏过去),
    而是把差分做到**内部梯度盖过噪声本底** —— 检查用的是
    `seam > max(内部最大梯度, 6.0)`, 内部梯度一旦超过 6 就按真规则判定。

    这个约束顺带是个好事: 48px 下一处压不出 6/255 行间差的装饰, 本来就等于
    没画。所以沙脊做成近水平的宽条 (风成沙纹本来就是垂直于风向的平行脊),
    龟裂缝压深到接近阴影色 —— 两者都是"看得见"的下限, 不是为了过检查凑数。
    """
    objs = build_desert_sand_tile()
    if variant == 0:
        return objs

    if variant == 1:
        # 风蚀沙脊。近水平 (±14°) 是有依据的: 检查分上下/左右两轴独立算,
        # 出问题的是*上下*轴 (行间差), 而近水平的脊才会在行方向上造出锐利的
        # 明暗跳变。斜 45° 的脊每一行只切过一点点, 行均值几乎不动。
        mat_ridge = create_clay_mat("m_sand_ridge", (0.70, 0.54, 0.28, 1.0),
                                    roughness=0.93, bump_strength=0.28)
        ridges = [(-0.30, -1.02, math.radians(9),  1.70, 0.26),
                  (0.34, -0.42, math.radians(-13), 1.62, 0.30),
                  (-0.24, 0.34, math.radians(11),  1.72, 0.28),
                  (0.30, 1.02, math.radians(-8),  1.58, 0.24)]
        for (x, y, rot, length, width) in ridges:
            _deco_box((x, y, 0.035), (length, width, 0.09), mat_ridge,
                      bevel=0.04, rot_z=rot)
            objs.append(bpy.context.active_object)
        # 脊间的碎石 —— 纯粹是打破规律性, 不承担可见度指标
        mat_peb = create_clay_mat("m_sand_pebble", (0.62, 0.50, 0.30, 1.0),
                                  roughness=0.88)
        for (x, y, r) in [(-0.95, 0.72, 0.10), (0.92, -0.86, 0.08),
                          (0.18, 1.24, 0.07), (-1.10, -0.66, 0.09)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, 0.03))
            p = bpy.context.active_object
            p.scale = (1.0, 1.0, 0.55)
            p.data.materials.append(mat_peb)
            bpy.ops.object.shade_smooth()
            objs.append(p)

    elif variant == 2:
        # 干裂龟纹。缝色压到接近阴影 (0.48,0.34,0.18 对底沙 0.88,0.72,0.40,
        # 红通道差约 100/255) —— 浅一点的缝在 48px 下会被降采样抹平。
        mat_crack = create_clay_mat("m_sand_crack", (0.48, 0.34, 0.18, 1.0),
                                    roughness=0.96, bump_strength=0.34)
        cracks = [(-0.18, -0.80, math.radians(7),   2.10, 0.115),
                  (0.22, 0.16, math.radians(-10),  2.20, 0.105),
                  (-0.10, 0.98, math.radians(6),    1.95, 0.100),
                  (-0.78, -0.10, math.radians(78),  1.30, 0.085),
                  (0.86, 0.58, math.radians(72),   1.20, 0.080)]
        for (x, y, rot, length, width) in cracks:
            _deco_box((x, y, 0.012), (length, width, 0.02), mat_crack,
                      bevel=0.012, rot_z=rot)
            objs.append(bpy.context.active_object)

    return objs


# ==================== 树丛差分 ====================

def _rotate_group(objs, ang):
    """整组绕原点转 —— 位置和自转都要转, 否则只是各自原地打转。"""
    ca, sa = math.cos(ang), math.sin(ang)
    for o in objs:
        x, y = o.location.x, o.location.y
        o.location.x = x * ca - y * sa
        o.location.y = x * sa + y * ca
        o.rotation_euler.z += ang


def trees_variant(variant, theme="a1"):
    """v0=原样, v1=转向 + 换花果, v2=更疏的树冠 + 换配色。

    树丛不是满幅瓦片 —— 它没有底板, 四周是透明的, main.gd 把它当 z_index=10
    的纯 Sprite2D 画在坦克*上面*。所以它没有无缝约束, 变体可以整体旋转、可以
    改轮廓。唯一要守住的是遮挡面积: 这块瓦片的战术作用就是藏坦克 (见 CLAUDE.md
    "Trees conceal, but must not erase"), 树冠一稀就不再是掩体了, 所以 v2 只
    动顶层高光和装饰, 不动 (B)(C) 那两层负责遮挡的大体块。
    """
    objs = build_sokpop_trees()
    if variant == 0:
        return objs

    if variant == 1:
        _rotate_group(objs, math.radians(63))
        # 白雏菊换成粉的, 杏果换成红的 —— 48px 下花果是仅有的高频色点,
        # 换掉它们比换树冠绿更能让两丛树看起来不是同一丛。
        for o in objs:
            for i, slot in enumerate(o.material_slots):
                if slot.material is None:
                    continue
                key = _base_mat_name(slot.material)
                if key == "m_tree_petal":
                    o.material_slots[i].material = create_clay_mat(
                        "m_tree_petal_v1", (0.96, 0.72, 0.80, 1.0), roughness=0.65)
                elif key == "m_tree_fruit":
                    o.material_slots[i].material = create_clay_mat(
                        "m_tree_fruit_v1", (0.88, 0.24, 0.22, 1.0), roughness=0.60)

    elif variant == 2:
        _rotate_group(objs, math.radians(-38))
        # 秋色: 顶层高光和中层往黄橙偏, 底层深色阴影层保持不动 —— 遮挡体量
        # 靠的是那一层, 它一变浅整丛树就"透"了。
        remap = {
            "m_tree_light": (0.82, 0.78, 0.34, 1.0),
            "m_tree_cream": (0.94, 0.86, 0.52, 1.0),
            "m_tree_mid":   (0.60, 0.62, 0.28, 1.0),
            "m_tree_fruit": (0.94, 0.68, 0.20, 1.0),
        }
        for o in objs:
            for i, slot in enumerate(o.material_slots):
                if slot.material is None:
                    continue
                key = _base_mat_name(slot.material)
                if key in remap:
                    o.material_slots[i].material = create_clay_mat(
                        f"{key}_v2", remap[key], roughness=0.74)

    return objs


# ==================== 批次定义 ====================

# name -> (builder, [(variant, theme, 输出名), ...])
GROUPS = {
    "tile_brick": (brick_variant, [
        (1, "a1", "tile_brick_v1.png"),
        (2, "a1", "tile_brick_v2.png"),
        (0, "a2", "tile_brick_a2.png"),
        (1, "a2", "tile_brick_a2_v1.png"),
        (2, "a2", "tile_brick_a2_v2.png"),
        (0, "a3", "tile_brick_a3.png"),
        (1, "a3", "tile_brick_a3_v1.png"),
        (2, "a3", "tile_brick_a3_v2.png"),
    ]),
    "tile_steel": (steel_variant, [
        (1, "a1", "tile_steel_v1.png"),
        (2, "a1", "tile_steel_v2.png"),
        (0, "a2", "tile_steel_a2.png"),
        (1, "a2", "tile_steel_a2_v1.png"),
        (2, "a2", "tile_steel_a2_v2.png"),
        (0, "a3", "tile_steel_a3.png"),
        (1, "a3", "tile_steel_a3_v1.png"),
        (2, "a3", "tile_steel_a3_v2.png"),
    ]),
    "tile_sand": (sand_variant, [
        (1, "a1", "tile_sand_v1.png"),
        (2, "a1", "tile_sand_v2.png"),
    ]),
    "tile_trees": (trees_variant, [
        (1, "a1", "tile_trees_v1.png"),
        (2, "a1", "tile_trees_v2.png"),
    ]),
}


def parse_targets(argv):
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return []


def main():
    targets = parse_targets(sys.argv)
    if "--list" in targets:
        print("可渲的地形差分组:")
        for k, (_, jobs) in sorted(GROUPS.items()):
            print(f"  {k}  ({len(jobs)} 张)")
        return
    if not targets:
        targets = sorted(GROUPS)

    unknown = [t for t in targets if t not in GROUPS]
    if unknown:
        print(f"[ERROR] 未知的组: {', '.join(unknown)}")
        print(f"[ERROR] 可选: {', '.join(sorted(GROUPS))}")
        raise SystemExit(1)

    total = 0
    for name in targets:
        builder, jobs = GROUPS[name]
        print(f">>> {name}: {len(jobs)} 张差分")
        for idx, (variant, theme, out_name) in enumerate(jobs):
            clear_scene()
            setup_render_settings(rx=256, ry=256)
            # 满幅地形一律走 seamless 布光 —— 点光源会在瓦片内造出位置梯度,
            # 铺开就是网格线。树丛不满幅, 但跟着基准图 (rerender_tiles.py 也
            # 是对全部瓦片用 seamless) 走, 免得变体和原图的光照对不上。
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=True)
            reset_jitter_seed(JITTER_SEED + idx * 17)
            objs = builder(variant, theme)
            render_and_clean(objs, os.path.join(SPRITES_TILES, out_name))
            purge_orphans()
            total += 1

    print(f"\n[OK] 已渲 {len(targets)} 组地形差分, 共 {total} 张。")
    print("[NEXT] godot --headless --path . --editor --quit"
          " -> python tools/fix_sprite_mipmaps.py -> 再 import 一次 -> test_texture_mipmaps.gd")
    print("[NEXT] python tools/qa_style_consistency.py   (新瓦片会自动进 seam/tileseam 检查)")


if __name__ == "__main__":
    main()
