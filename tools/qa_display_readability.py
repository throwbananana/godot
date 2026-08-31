"""在*实际显示尺寸*上量可读性 (Readability at the size the player actually sees).

为什么需要这个工具:

渲染出来的图是 256x256, 但游戏里按 TILE_SCALE = 0.1875 画成 48x48。中间隔着
一次 5.33 倍下采样, 而所有既有的美术 QA (analyze_render_and_colors /
qa_style_consistency / qa_tank_models_and_clipping) 都是在 256px 源图上跑的。
于是有一整类问题在源图上完全看不出来: 源图上分得清清楚楚的两辆坦克, 缩到
48px 可能就是两坨同色像素。

实测支撑 (2026-08-31):
  - 采样率 28 -> 128, 全部 826 张图的低频 RMS 变化 < 0.35 (8bit 量程), 连
    自发光 VFX 也一样 —— 这套光照方差极低, Cycles 几乎立刻收敛。
  - 源分辨率 256 -> 512, 缩到 48px 后与 1024 真值的差距 0.64 -> 0.40, 但两者
    都远低于 1.0-2.0 的人眼可觉察阈值。
  结论: 渲染侧已经饱和, 画质余量不在采样率也不在分辨率, 而在剪影与色块。
  这个工具量的就是后者。

三个指标:

  1. 细节浪费率 —— 源图的细节能量里, 有多大比例落在 48px 显示*根本表示不了*
     的尺度上。5.33 倍下采样意味着源图上任何细于 5.33px 的东西都会被平均掉,
     所以这个比例就是"白建的模"。

     注意别用"48px 梯度能量 / 256px 梯度能量"来算这件事 —— 梯度是按每像素
     算的, 图缩小 5.33 倍后同一条边界在每像素上自然更陡, 比值会得出 300%~450%
     这种没有意义的数字。要比的是*同一张源图*上粗尺度与细尺度的能量占比。

  2. 敌我混淆度 —— 两两之间的剪影 IoU 与主色距离合成。CLAUDE.md 的核心设计
     是"靠敌人种类而不是数值膨胀来提升难度", 而这条设计的前提是玩家一眼能
     分辨种类。48px 下分不出来, 这条设计就不成立。

  3. 剪影独特性 —— 每个资源与全体的最小距离。排在最后的那些就是"长得像别人"
     的, 也就是重新建模最该先动的对象。

只依赖 numpy + Pillow。这是*度量工具不是门禁*: 它不 [FAIL], 因为"两个敌人该
有多像"是美术决策, 不是可以拍死的阈值 —— 同 qa_style_consistency 里 clip /
palette 只报 [WARN] 的理由一样。

用法:
    python tools/qa_display_readability.py                 # 敌人 (默认)
    python tools/qa_display_readability.py --glob "tiles/*.png"
    python tools/qa_display_readability.py --top 20
"""

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(REPO, "assets", "sprites")

TILE_SIZE = 48          # 游戏里的实际显示边长 (main.gd::TILE_SIZE)
SOURCE_SIZE = 256       # 渲染分辨率


def load_display(path, size=TILE_SIZE):
    """按游戏的缩放链路把源图降到显示尺寸。

    用 Lanczos 近似 mipmap + Linear Mipmap 过滤 (project.godot 里
    default_texture_filter=3)。不是逐位一致, 但低频结构一致, 而这里量的正是
    低频结构。
    """
    img = Image.open(path).convert("RGBA")
    return img.resize((size, size), Image.LANCZOS)


def as_arrays(img):
    a = np.asarray(img, dtype=np.float32)
    alpha = a[..., 3] / 255.0
    # 合成到中灰再取 RGB: 透明区的垃圾颜色不应参与比较。
    flat = Image.new("RGBA", img.size, (128, 128, 128, 255))
    flat.alpha_composite(img)
    rgb = np.asarray(flat.convert("RGB"), dtype=np.float32)
    return alpha, rgb


def grad_energy(rgb):
    gy, gx = np.gradient(rgb.mean(axis=2))
    return float(np.sqrt(gx ** 2 + gy ** 2).mean())


# 48px 显示对应的源图像素尺度: 256/48 = 5.33。细于此的结构会被下采样平均掉。
NYQUIST_PX = SOURCE_SIZE / TILE_SIZE
FORM_BLUR = 24          # 粗形体尺度 (与 qa_rerender_diff 保持一致)


def _blur(rgb, radius):
    img = Image.fromarray(rgb.astype(np.uint8), "RGB")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32)


def detail_waste(rgb_src):
    """源图细节能量里, 有多少落在 48px 表示不了的尺度上。

    分子: 细于 Nyquist 的能量 (下采样必然抹掉的部分)
    分母: 粗形体之上的全部细节能量
    比值越高, 说明建模时堆的细节越多是在屏幕上看不到的。
    """
    fine = rgb_src - _blur(rgb_src, NYQUIST_PX)
    allf = rgb_src - _blur(rgb_src, FORM_BLUR)
    den = float(allf.std())
    if den < 1e-6:
        return 0.0
    return float(fine.std()) / den


def dominant_color(alpha, rgb):
    """不透明区域的加权平均色。"""
    w = alpha[..., None]
    tot = w.sum()
    if tot < 1e-6:
        return np.zeros(3, dtype=np.float32)
    return (rgb * w).sum(axis=(0, 1)) / tot


def silhouette_iou(a1, a2, thr=0.5):
    m1, m2 = a1 > thr, a2 > thr
    union = np.logical_or(m1, m2).sum()
    if union == 0:
        return 1.0
    return float(np.logical_and(m1, m2).sum() / union)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glob", default="tanks/enemy_*_f0.png",
                    help="相对 assets/sprites 的匹配式 (默认: 各敌人第 0 帧)")
    ap.add_argument("--top", type=int, default=15, help="列出多少条")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(SPRITES, args.glob.replace("/", os.sep))))
    # 排除装甲板叠加图: 它们是覆盖层, 不是独立单位, 拿来两两比较没有意义。
    paths = [p for p in paths if "_plate_" not in os.path.basename(p)]
    if not paths:
        print(f"[WARN] 没有匹配到任何图: {args.glob}")
        return

    names, disp, srcs = [], [], []
    for p in paths:
        names.append(os.path.splitext(os.path.basename(p))[0])
        disp.append(as_arrays(load_display(p)))
        srcs.append(as_arrays(load_display(p, SOURCE_SIZE)))

    # ---------------------------------------------------------- 1. 细节浪费率
    print(f"== 指标 1: 细节浪费率 (源图细于 {NYQUIST_PX:.2f}px 的能量占比) ==")
    print(f"{'asset':<26} {'浪费率':>8}")
    print("-" * 36)
    waste = []
    for n, (sa, sr) in zip(names, srcs):
        w = detail_waste(sr)
        waste.append(w)
        print(f"{n:<26} {w*100:>7.1f}%")
    print("-" * 36)
    print(f"浪费率中位数: {np.median(waste)*100:.1f}%  "
          f"(越高说明建模时堆的细节越多是玩家看不到的)")

    # ---------------------------------------------------------- 2. 两两混淆度
    n = len(names)
    conf = np.zeros((n, n), dtype=np.float32)
    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            iou = silhouette_iou(disp[i][0], disp[j][0])
            ci = dominant_color(*disp[i])
            cj = dominant_color(*disp[j])
            # 主色距离归一化到 0..1 (255*sqrt(3) 是理论最大值, 实际远小于此,
            # 所以除以 120 做经验缩放, 让两项量级可比)。
            cdist = min(1.0, float(np.linalg.norm(ci - cj)) / 120.0)
            # 混淆度 = 剪影重合 且 颜色接近
            conf[i, j] = iou * (1.0 - cdist)

    pairs = [(conf[i, j], names[i], names[j])
             for i in range(n) for j in range(i + 1, n)]
    pairs.sort(reverse=True)

    print(f"\n== 指标 2: {TILE_SIZE}px 下最容易混淆的组合 (剪影重合 x 颜色接近) ==")
    print(f"{'混淆度':>7}  {'A':<24} {'B':<24}")
    print("-" * 60)
    for score, a, b in pairs[:args.top]:
        print(f"{score:>7.3f}  {a:<24} {b:<24}")

    # ---------------------------------------------------------- 3. 剪影独特性
    print(f"\n== 指标 3: 独特性最差的资源 (与最像的那个之间的距离) ==")
    worst = sorted(((float(conf[i].max()), names[i]) for i in range(n)), reverse=True)
    print(f"{'最高混淆':>8}  {'asset':<26} {'最像的是'}")
    print("-" * 62)
    for score, nm in worst[:args.top]:
        i = names.index(nm)
        j = int(np.argmax(conf[i]))
        print(f"{score:>8.3f}  {nm:<26} {names[j]}")

    print("\n注: 这是度量工具, 不是门禁 —— 阈值是美术决策, 不由脚本拍板。")


if __name__ == "__main__":
    main()
