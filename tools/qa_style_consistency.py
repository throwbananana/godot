"""精灵风格一致性 QA —— 把 v0.06321~v0.06322 那轮排查里每一类真实事故固化成检查。

跑法 (不需要 Blender, 纯 Python + numpy + Pillow):

    python tools/qa_style_consistency.py                # 全部检查
    python tools/qa_style_consistency.py --check seam   # 只跑一项
    python tools/qa_style_consistency.py --vs HEAD      # 额外与某个 git 版本比对

有 [FAIL] 就以非零码退出, 和 tools/test_*.gd 的约定一致。

五项检查, 每一项都对应一个真出过的事故:

  blank    整张图方差极低 / alpha 覆盖率异常高。
           build_ui_character_art_replacements.py 漏调 clear_scene(), Blender
           出厂的默认立方体挡在镜头前, 九张 UI 图标全渲成同一块灰方块并上线,
           因为渲染本身"成功"了, 一直没人发现。

  seam     满幅地形瓦片铺开后顶点漏背景。tile_trees 没有底板 (main.gd 把它当
           独立 Sprite2D 画在 z_index=10), 树冠盖不到的角落直接透光, 网格每个
           顶点一个深色针孔。

  frame    同类资源的画幅是否一致。refine_*.py 用 ORTHO_SCALE_DEFAULT(3.3) 渲
           本该用 ORTHO_SCALE_PROP(2.7) 的道具, 八张精灵悄悄小了 0.82 倍 ——
           渲染不报错, 只是变小。

  clip     资源贴到画幅边缘 = 可能已经被裁掉。坦克画幅从 3.3 提到 3.6 就是为了
           解决前伸炮管和消焰器顶部被切。

  palette  饱和度过低的资源在浅色地形上没有轮廓。enemy_basic 曾是近白灰
           (饱和度 15.3%), 而同类都在 42~52%。

  --vs     与某个 git 版本逐张比对, 把"渲染参数变了"和"美术被回退了"分开。
           这是查陈旧 build 脚本的主力手段 —— tools/ 里有几个脚本已经无法复现
           仓库里已提交的美术 (见 CLAUDE.md "Stale build scripts")。
"""

import argparse
import io
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "tools" else SCRIPT_DIR
SPRITES = os.path.join(PROJECT_DIR, "assets", "sprites")

TILE_SCALE = 0.1875          # main.gd: TILE_SIZE 48 / 渲染 256
DISP = 48                    # 瓦片在屏幕上的实际边长

# 高斯半径必须大于 bump 波长 (256px 图上约 12px), 否则黏土颗粒会漏进低频,
# 被误判成"美术改动"。8px 不够, 24px 可以。
BLUR_LOW = 24

_fails = []
_warns = []


def fail(msg):
    _fails.append(msg)
    print(f"[FAIL] {msg}")


def warn(msg):
    _warns.append(msg)
    print(f"[WARN] {msg}")


def load(path):
    return Image.open(path).convert("RGBA")


def all_sprites(subdir=None):
    root = os.path.join(SPRITES, subdir) if subdir else SPRITES
    for dirpath, _, files in os.walk(root):
        for fn in sorted(files):
            if fn.endswith(".png"):
                yield os.path.join(dirpath, fn)


def rel_of(path):
    return os.path.relpath(path, PROJECT_DIR).replace("\\", "/")


# ---------------------------------------------------------------- blank

def check_blank():
    """整块单色 = 多半被什么东西挡住了镜头。

    判据要两个条件同时成立才报: 覆盖率极高 *且* 灰度方差极低。只看方差会误伤
    真的很平的图标; 只看覆盖率会误伤满幅瓦片 (它们本来就该 100% 覆盖)。
    """
    print("\n--- blank: 疑似被遮挡/空渲染 ---")
    n = 0
    for p in all_sprites():
        a = np.asarray(load(p), np.float32)
        cov = (a[..., 3] > 127).mean()
        m = a[..., 3] > 127
        if m.sum() < 16:
            fail(f"{rel_of(p)}: 几乎全透明 (覆盖率 {cov*100:.1f}%)")
            n += 1
            continue
        std = float(a[..., :3][m].std())
        if cov > 0.88 and std < 6.0:
            fail(f"{rel_of(p)}: 覆盖率 {cov*100:.1f}% 且灰度 std {std:.1f} "
                 f"—— 疑似整块单色, 检查是否漏了 clear_scene()")
            n += 1
    print(f"    检查 {sum(1 for _ in all_sprites())} 张, {n} 张异常")


# ---------------------------------------------------------------- seam

def check_seam():
    """满幅地形瓦片铺开后不该漏出背景。"""
    print("\n--- seam: 瓦片铺开后的顶点漏光 ---")
    n = checked = 0
    for p in all_sprites("tiles"):
        im = load(p)
        a = np.asarray(im, np.float32)[..., 3]
        border = np.concatenate([a[0, :], a[-1, :], a[:, 0], a[:, -1]])
        if border.mean() < 200:
            continue          # 不是满幅瓦片 (道具型精灵), 不适用
        checked += 1
        t = im.resize((DISP, DISP), Image.LANCZOS)
        mosaic = Image.new("RGBA", (DISP * 3, DISP * 3), (0, 0, 0, 0))
        for y in range(3):
            for x in range(3):
                mosaic.alpha_composite(t, (x * DISP, y * DISP))
        A = np.asarray(mosaic, np.float32)[..., 3]
        inner = A[DISP // 2:DISP * 3 - DISP // 2, DISP // 2:DISP * 3 - DISP // 2]
        leak = int((inner < 250).sum())
        worst = float(255 - inner.min())
        if leak > 0 and worst > 120:
            fail(f"{rel_of(p)}: 铺开后 {leak} 个像素漏背景 (最大强度 {worst:.0f}/255) "
                 f"—— 边缘/角落没有被几何覆盖")
            n += 1
        elif leak > 100:
            warn(f"{rel_of(p)}: 铺开后 {leak} 个像素半透 (最大强度 {worst:.0f}/255)")
    print(f"    检查 {checked} 张满幅瓦片, {n} 张漏光")


# ---------------------------------------------------------------- tileseam

# 已知仍有接缝、但*故意不修*的瓦片。降级成 WARN 而不是直接从检查里排除, 也不是
# 放着让它 FAIL —— 一个总是红的门禁等于没有门禁, 很快就没人看了。
#
# 这三张的共同点是: 修它们需要的不是改代码, 而是先做一个美术决策。
TILESEAM_EXEMPT = {
    # tile_ice 曾以"孤儿资源"名义豁免在这里, 上下拼接梯度 30.41 —— 全项目最差,
    # 铺成一片冰湖就是一格一格的明暗方块。豁免的理由本身是错的: 那个"无脚本
    # 可复现"的判定是拿点光源年代的已提交 PNG 去比无缝布光的重渲, 比错了口
    # (用当年的渲法重跑 build_sokpop_ice() 得 d_rgb 0.20)。缺陷修完后
    # 上下 30.41 -> 1.83, 已从名单移除。
    #
    # 教训值得留着: **一条"已知未修"的豁免记录, 它的诊断也可能是错的。**
    # 豁免名单会让人停止追问, 而这一条把全项目最显眼的美术缺陷藏了很久。
    # 往这里加东西之前, 先确认诊断本身站得住。
    #
    # 传送带动画帧: 黄色箭头条横跨瓦片边缘做卷动动效, 接缝处的梯度是动画内容
    # 本身造成的, 不是底板打光导致的网格线。用 seamless=True 已去掉了点光源
    # 梯度; 剩下的梯度来自箭头几何体跨越边缘 —— 属于正常美术设计。
    "tile_conveyor.png":    "动画帧(静态兼容副本), 箭头几何跨边缘属正常动效",
    "tile_conveyor_f0.png": "动画帧0, 箭头几何跨边缘属正常动效",
    "tile_conveyor_f1.png": "动画帧1, 箭头几何跨边缘属正常动效",
    "tile_conveyor_f2.png": "动画帧2, 箭头几何跨边缘属正常动效",
    "tile_conveyor_f3.png": "动画帧3, 箭头几何跨边缘属正常动效",
    "tile_conveyor_f4.png": "动画帧4, 箭头几何跨边缘属正常动效",
    "tile_conveyor_f5.png": "动画帧5, 箭头几何跨边缘属正常动效",
    # 电墙发光动画瓦片: 等离子弧球体跨越瓦片边缘是动效内容。
    # 底板已换 TILE_PLATE_BLEED + seamless=True 修掉了基础网格线;
    # 剩余梯度来自闪光球几何体偶发落在边缘 —— 属于可接受的动画噪声。
    # (f1/f2 经验证梯度已在阈值内, 无需豁免)
    "tile_electric_wall_f3.png": "发光动画瓦片, 等离子弧偶发落在边缘属正常动效",
}


def check_tileseam():
    """满幅瓦片拼接处不该出现瓦片内部没有的*突变*。

    和 check_seam 抓的不是一回事: 那个抓的是 alpha 漏背景 (几何没盖住),
    这个抓的是颜色接不上 —— 图是不透明的, 但拼起来能看见一条网格线。

    为什么不能简单地比首行和末行: 瓦片上的东西是有高度的立体, 在定向光下
    "砖上方的砖缝"和"砖下方的砖缝"本来就该不一样, 拼起来这两半正好凑成完整
    的一条缝。直接相减会把这个正常现象报成巨大的接缝 (砖块实测 36)。
    所以改成看*梯度*: 接缝处的行间差, 和瓦片内部所有行间差的分布比。只要接缝
    的梯度落在内部梯度的正常范围里, 人眼就挑不出那条线。

    这条检查固化的是这一轮修掉的三个真实缺陷:
      - 底板倒角留在画幅内 (TILE_FULL_BLEED 3.34 只比画幅 3.30 多 0.02,
        而倒角宽 0.08~0.12), 每块瓦片自带一圈镶边 -> 绗缝被子;
      - 砖块投影长 0.371 > 砖缝 0.205, 而投影的施主砖属于邻居瓦片, 渲染时
        场景里没有它 -> 同一条砖缝上暗下亮;
      - 水波折线逼近的采样格不是波长的整数分之一 -> 左右两边波形对不上。
    """
    print("\n--- tileseam: 瓦片拼接处的颜色突变 ---")
    n = checked = 0
    exempt_hit = set()
    for p in all_sprites("tiles"):
        im = load(p)
        arr = np.asarray(im, np.float32)
        a = arr[..., 3]
        border = np.concatenate([a[0, :], a[-1, :], a[:, 0], a[:, -1]])
        if border.mean() < 200:
            continue          # 不是满幅瓦片
        checked += 1
        al = arr[..., 3:4] / 255.0
        c = arr[..., :3] * al + 128.0 * (1 - al)
        for axis, tag in ((0, "上下"), (1, "左右")):
            x = c if axis == 0 else np.transpose(c, (1, 0, 2))
            seam = float(np.abs(x[0] - x[-1]).mean())
            internal = np.abs(np.diff(x, axis=0)).mean(axis=(1, 2))
            p95 = float(np.percentile(internal, 95))
            mx = float(internal.max())
            # 容忍下限 6.0: 纯色瓦片内部梯度接近 0, 不给个地板任何渲染噪声都会报警
            name = os.path.basename(p)
            if seam > max(mx, 6.0):
                if name in TILESEAM_EXEMPT:
                    exempt_hit.add(name)
                    warn(f"{rel_of(p)}: {tag}拼接梯度 {seam:.1f} (已知未修, "
                         f"{TILESEAM_EXEMPT[name]})")
                else:
                    fail(f"{rel_of(p)}: {tag}拼接梯度 {seam:.1f}, 超过瓦片内部最大梯度 "
                         f"{mx:.1f} —— 铺开后是一条肉眼可见的网格线")
                    n += 1
            elif seam > max(p95, 6.0):
                warn(f"{rel_of(p)}: {tag}拼接梯度 {seam:.1f} (内部 p95={p95:.1f})")

    stale = sorted(set(TILESEAM_EXEMPT) - exempt_hit)
    if stale:
        print(f"    [提示] 豁免名单里这些已经不再接缝, 可以删掉了: {', '.join(stale)}")
    print(f"    检查 {checked} 张满幅瓦片, {n} 处可见接缝")


# ---------------------------------------------------------------- frame

# 同一组里的资源应当共用画幅, 因此包围盒尺寸不该差太多。
# 阈值放得比较松 (1.6x): 组内本来就允许有大小差别 (heavy 坦克比 speed 宽),
# 要抓的是"整组里蹦出一个明显小一圈的", 那通常意味着传错了 ortho_scale。
FRAME_GROUPS = {
    "powerups": ("powerups", 1.75),
    "tiles": ("tiles", 1.60),
}


def check_frame():
    """同组资源画幅是否一致 —— 抓 ortho_scale 传错。"""
    print("\n--- frame: 同组画幅一致性 ---")
    for label, (subdir, tol) in FRAME_GROUPS.items():
        sizes = {}
        for p in all_sprites(subdir):
            a = np.asarray(load(p))[..., 3] > 40
            ys, xs = np.where(a)
            if len(xs) == 0:
                continue
            sizes[rel_of(p)] = max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)
        if len(sizes) < 3:
            continue
        vals = np.array(list(sizes.values()), dtype=float)
        med = float(np.median(vals))
        for name, v in sorted(sizes.items(), key=lambda kv: kv[1]):
            if v < med / tol:
                warn(f"{name}: 最大边 {v}px, 组内中位 {med:.0f}px "
                     f"—— 比同组小 {(1-v/med)*100:.0f}%, 检查 ortho_scale 是否传错")
        print(f"    {label}: {len(sizes)} 张, 中位最大边 {med:.0f}px, "
              f"范围 {vals.min():.0f}-{vals.max():.0f}px")


# ---------------------------------------------------------------- clip

def check_clip():
    """资源贴边 = 可能已经被画幅裁掉。

    判据是*成对*的: 某个轴上两侧都贴住 = 该轴满幅设计; 只贴住一侧 = 形体被切断。

    先试过"有几条边贴满", 不行 —— btn_clay_* 是圆角按钮, 左右两边实心 88%,
    上下因为圆角不到 30%, 于是被误判成"只贴两条边=被裁"。但它左右成对, 明显
    是横向满幅。反过来 clock 的表圈只顶住上边、下边留着余量, 那才是真被削平。
    这一项只报 WARN, 不报 FAIL —— 它区分不了意图。diorama_* 是"下方地面铺满、
    上方天空透空"的构图 (下边 100% 实心、上边 0%), 单侧贴边是设计而不是事故;
    tile_electric_wall 是横向的墙, 同理。留给人看, 别让它挡住 CI。
    真阳性长这样: clock 的表圈上边 11.7% 实心而下边留有余量 (环被削平),
    ui_banner_victory 顶部的火焰被切掉。
    """
    print("\n--- clip: 是否被画幅裁切 ---")
    n = checked = 0
    for p in all_sprites():
        a = np.asarray(load(p), np.float32)[..., 3]
        checked += 1
        hot = {
            "上": float((a[0, :] > 200).mean()), "下": float((a[-1, :] > 200).mean()),
            "左": float((a[:, 0] > 200).mean()), "右": float((a[:, -1] > 200).mean()),
        }
        bad = []
        for lo, hi in (("上", "下"), ("左", "右")):
            a_hit, b_hit = hot[lo] > 0.06, hot[hi] > 0.06
            if a_hit and b_hit:
                continue                      # 该轴满幅, 是设计
            if a_hit != b_hit:
                side = lo if a_hit else hi
                bad.append((side, hot[side]))
        if bad:
            desc = ", ".join(f"{s} 边 {f*100:.0f}% 实心" for s, f in bad)
            warn(f"{rel_of(p)}: 单侧贴住画幅 ({desc}), 对侧留有余量 —— "
                 f"可能被裁, 也可能是单侧构图, 需人工判断")
            n += 1
    print(f"    检查 {checked} 张, {n} 张单侧贴边 (需人工判断)")


# ---------------------------------------------------------------- palette

# 坦克实际会压在这些地形上。轮廓读不读得出来, 取决于和*脚下那块地*的对比,
# 而不是坦克自己有多鲜艳。
TERRAIN_TILES = ["tile_sand.png", "tile_brick.png", "tile_ice.png",
                 "tile_trees.png", "tile_steel.png", "tile_hard_clay.png"]

# 明度加权: 人眼对明度差远比对色相差敏感, 所以轮廓主要靠明度撑。
# 权重取 2.0 是让"深色 vs 浅地形"这种一眼可辨的组合不会被色相接近拖下去 ——
# enemy_missile 饱和度只有 16% 却在沙地上非常清楚, 就是纯靠明度差。
_LUMA_W = 2.0


def _mean_rgb(im):
    a = np.asarray(im, np.float32)
    m = a[..., 3] > 127
    if m.sum() < 16:
        return None
    return a[..., :3][m].mean(0)


def _contrast(c1, c2):
    """明度加权的颜色距离。不是严格的 ΔE, 但足够排序 '谁在谁上面看不清'。"""
    l1 = float(0.299 * c1[0] + 0.587 * c1[1] + 0.114 * c1[2])
    l2 = float(0.299 * c2[0] + 0.587 * c2[1] + 0.114 * c2[2])
    chroma = float(np.linalg.norm((c1 - c1.mean()) - (c2 - c2.mean())))
    return float(np.hypot(_LUMA_W * (l1 - l2), chroma))


def check_palette():
    """坦克压在地形上时读不读得出轮廓。

    刻意*不*用饱和度。饱和度低不等于看不清: enemy_missile 只有 16% 饱和度, 但
    它是深橄榄色, 压在浅沙地上明度差极大, 轮廓非常清楚; 反倒是 enemy_armor
    饱和度 44% 的中明度绿, 和沙地明度接近, 才是最容易糊掉的那个。
    当年 enemy_basic 的真问题是"近白色压在浅地形上", 那是明度问题, 只是碰巧
    伴随低饱和 —— 拿饱和度当判据会同时放过真问题和冤枉好资源。

    这一项也只报 WARN。整体均色对比只是个粗糙代理: 坦克有深色履带和描边,
    这些*内部*对比本身就把轮廓撑起来了, 所以"整体颜色接近地形"未必真看不清。
    按 <中位*0.35 报, 报出来的是色相确实撞车的组合 (橙色坦克压在赤陶砖上、
    绿色坦克压在树上), 交给人判断值不值得改配色。
    """
    print("\n--- palette: 坦克压在地形上的轮廓对比 ---")
    terr = {}
    for t in TERRAIN_TILES:
        p = os.path.join(SPRITES, "tiles", t)
        if os.path.exists(p):
            c = _mean_rgb(load(p))
            if c is not None:
                terr[t[5:-4]] = c
    if not terr:
        print("    找不到地形瓦片, 跳过")
        return

    worst = {}
    for p in all_sprites("tanks"):
        if not p.endswith("_f0.png"):
            continue
        c = _mean_rgb(load(p))
        if c is None:
            continue
        d = {k: _contrast(c, v) for k, v in terr.items()}
        k = min(d, key=d.get)
        worst[os.path.basename(p)[:-7]] = (d[k], k)
    if not worst:
        return
    vals = np.array([v[0] for v in worst.values()])
    med = float(np.median(vals))
    for name, (v, on) in sorted(worst.items(), key=lambda kv: kv[1][0]):
        if v < med * 0.35:
            warn(f"tanks/{name}: 压在 {on} 上对比度 {v:.0f} (同类中位 {med:.0f}) "
                 f"—— 色相与该地形撞车, 人工确认轮廓是否还读得出来")
    print(f"    检查 {len(worst)} 种坦克 x {len(terr)} 种地形, "
          f"最差对比度 {vals.min():.0f}-{vals.max():.0f}, 中位 {med:.0f}")


# ---------------------------------------------------------------- vs <ref>

def check_vs(ref):
    """与某个 git 版本逐张比对, 分开"渲染参数变了"和"美术被回退了"。

    两个信号互相独立:
      alpha 覆盖率 —— shader 动不了它, 变了就是几何或画幅;
      大半径模糊后的 RMS —— 形体与光照。半径必须大于 bump 波长, 见 BLUR_LOW。
    """
    print(f"\n--- vs {ref}: 与已提交版本比对 ---")
    art = grain = same = 0
    for p in all_sprites():
        rel = rel_of(p)
        try:
            blob = subprocess.run(["git", "show", f"{ref}:{rel}"], cwd=PROJECT_DIR,
                                  capture_output=True, check=True).stdout
        except subprocess.CalledProcessError:
            continue
        old = Image.open(io.BytesIO(blob)).convert("RGBA")
        new = load(p)
        if old.size != new.size:
            fail(f"{rel}: 分辨率从 {old.size} 变成 {new.size}")
            continue
        A, B = np.asarray(old, np.float32), np.asarray(new, np.float32)
        d_cov = (B[..., 3].mean() - A[..., 3].mean()) / 2.55
        m = (A[..., 3] > 127) & (B[..., 3] > 127)
        if m.sum() < 64:
            continue
        la = np.asarray(old.filter(ImageFilter.GaussianBlur(BLUR_LOW)), np.float32)[..., :3]
        lb = np.asarray(new.filter(ImageFilter.GaussianBlur(BLUR_LOW)), np.float32)[..., :3]
        d_low = float(np.sqrt((((la - lb) ** 2).mean(2))[m].mean()))
        if abs(d_cov) > 1.5 or d_low > 6.0:
            warn(f"{rel}: 美术变了 (d_cov {d_cov:+.2f}pp, d_low {d_low:.1f}) "
                 f"—— 若非有意, 说明跑到了陈旧脚本")
            art += 1
        elif d_low > 0.5:
            grain += 1
        else:
            same += 1
    print(f"    美术变化 {art} 张 / 仅细节差异 {grain} 张 / 基本一致 {same} 张")


CHECKS = {
    "blank": check_blank,
    "seam": check_seam,
    "tileseam": check_tileseam,
    "frame": check_frame,
    "clip": check_clip,
    "palette": check_palette,
}


def main():
    ap = argparse.ArgumentParser(description="精灵风格一致性 QA")
    ap.add_argument("--check", choices=sorted(CHECKS), action="append",
                    help="只跑指定检查 (可重复); 默认全跑")
    ap.add_argument("--vs", metavar="REF",
                    help="额外与某个 git 版本比对 (如 HEAD)")
    args = ap.parse_args()

    if not os.path.isdir(SPRITES):
        print(f"[FAIL] 找不到精灵目录: {SPRITES}")
        return 1

    for name in (args.check or sorted(CHECKS)):
        CHECKS[name]()
    if args.vs:
        check_vs(args.vs)

    # 只用 ASCII 标记: Windows 控制台默认 GBK, 打 emoji 会抛 UnicodeEncodeError
    # 把整个脚本带崩 —— QA 工具本身不该成为失败源。
    print("\n" + "=" * 56)
    if _fails:
        print(f"[FAIL] {len(_fails)} 项 FAIL, {len(_warns)} 项 WARN")
        return 1
    print(f"[OK] 全部通过 ({len(_warns)} 项 WARN)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
