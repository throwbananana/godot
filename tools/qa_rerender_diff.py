"""重渲前后逐张比对 (Per-sprite re-render diff against a git ref).

用途: 全量/批量重渲之后, 回答唯一重要的那个问题 ——
"这张图变了, 是因为我调了渲染质量, 还是因为某个陈旧脚本把它换成了别的东西?"

CLAUDE.md 规定用两个*互相独立*的信号来区分这两件事, 因为单看一个都会骗人:

  1. alpha 覆盖率 + 包围盒 —— shader 动不了这两个数。它们一旦变了, 变的就是
     几何或画幅 (ortho_scale), 也就是"另一个脚本用自己的建模覆盖了这张图"。
     提采样率绝不可能改变剪影。

  2. 大半径高斯模糊后的 RMS —— 形体与光照。模糊半径必须*大于*凹凸波长
     (256px 下约 12px), 否则蒙特卡洛噪点和 bump 颗粒会漏进低频带, 被误读成
     "美术变了"。8px 太小, 这里用 24px。

第三个信号是这一轮特有的, 用来*证明*提质生效而不是白跑:

  3. 高频能量 (原图 - 模糊图 的标准差) —— 噪点住在这个带里。采样率提高后它
     应该*下降*。如果没降, 说明质量地板没起作用 (比如调用点绕过了
     setup_render_settings, 或者 adaptive_threshold 仍在提前收敛)。

分类规则:
  GEOMETRY  剪影变了 -> 极可能是陈旧脚本覆盖, 建议 git checkout 回退
  LOOKSHIFT 剪影没变但形体/光照明显位移 -> 需要人工过目
  QUALITY   剪影没变, 低频稳定, 高频下降 -> 这就是想要的结果
  FLAT      三个信号都没动 -> 这张图这次根本没被重渲 (脚本没覆盖到)

用法:
    python tools/qa_rerender_diff.py                    # 工作区 vs HEAD, 全部
    python tools/qa_rerender_diff.py --ref 2f05c19      # 换个基线
    python tools/qa_rerender_diff.py --filter tiles     # 只看路径含 tiles 的
    python tools/qa_rerender_diff.py --json out.json    # 机器可读, 供后续回退用

只依赖 numpy + Pillow, 与 qa_style_consistency.py 一致; 有 [FAIL] 时退出码非零。
"""

import argparse
import io
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITE_DIR = os.path.join(REPO, "assets", "sprites")

# 判定阈值。覆盖率是比例 (0..1), RGB 距离是 0..255。
COV_EPS       = 0.0015   # 剪影容差: 256x256 下约 98 像素, 足够吸收抗锯齿边缘的采样抖动
BBOX_EPS      = 2        # 包围盒容差 (像素)
BLUR_RADIUS   = 24       # 必须 > 凹凸波长(~12px), 见文件头
LOOKSHIFT_RMS = 6.0      # 低频 RMS 超过这个数就要人工看
FLAT_RMS      = 0.35     # 低于这个数视为"没重渲"


def git_show(ref, relpath):
    """取出 ref 版本的文件字节; 不存在则返回 None (新增资源)。"""
    rel = relpath.replace(os.sep, "/")
    try:
        return subprocess.run(
            ["git", "show", f"{ref}:{rel}"],
            cwd=REPO, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        ).stdout
    except subprocess.CalledProcessError:
        return None


def load_rgba(data_or_path):
    if isinstance(data_or_path, bytes):
        img = Image.open(io.BytesIO(data_or_path))
    else:
        img = Image.open(data_or_path)
    return img.convert("RGBA")


def metrics(img):
    """返回 (覆盖率, 包围盒, 低频图, 高频标准差)。

    低频图刻意在*合成到中灰之后*再模糊: 直接模糊带 alpha 的 RGB 会把透明区域
    的垃圾颜色卷进来, 让边缘外侧主导 RMS。合成到固定背景后, 形状变化和颜色
    变化都会如实体现, 且两张图用的是同一个背景, 不引入偏差。
    """
    a = np.asarray(img, dtype=np.float32)
    alpha = a[..., 3] / 255.0
    cov = float(alpha.mean())

    ys, xs = np.nonzero(alpha > 0.5)
    if len(xs):
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    else:
        bbox = (0, 0, 0, 0)

    flat = Image.new("RGBA", img.size, (128, 128, 128, 255))
    flat.alpha_composite(img)
    rgb = flat.convert("RGB")

    low = np.asarray(rgb.filter(ImageFilter.GaussianBlur(BLUR_RADIUS)), dtype=np.float32)
    full = np.asarray(rgb, dtype=np.float32)
    high_sd = float((full - low).std())
    return cov, bbox, low, high_sd


def classify(d_cov, d_bbox, rms_low, d_high):
    if d_cov > COV_EPS or d_bbox > BBOX_EPS:
        return "GEOMETRY"
    if rms_low > LOOKSHIFT_RMS:
        return "LOOKSHIFT"
    if rms_low < FLAT_RMS and abs(d_high) < FLAT_RMS:
        return "FLAT"
    return "QUALITY"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD", help="对比基线 git ref (默认 HEAD)")
    ap.add_argument("--filter", default="", help="只比对路径包含该子串的图")
    ap.add_argument("--json", default="", help="把结果写成 JSON")
    ap.add_argument("--quiet", action="store_true", help="只打印非 FLAT 的行")
    args = ap.parse_args()

    rows = []
    for root, _dirs, files in os.walk(SPRITE_DIR):
        for fn in sorted(files):
            if not fn.lower().endswith(".png"):
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, REPO)
            if args.filter and args.filter not in rel.replace(os.sep, "/"):
                continue

            old_bytes = git_show(args.ref, rel)
            if old_bytes is None:
                rows.append(dict(path=rel.replace(os.sep, "/"), verdict="NEW",
                                 d_cov=0.0, d_bbox=0, rms_low=0.0, d_high=0.0))
                continue

            new_img = load_rgba(full)
            old_img = load_rgba(old_bytes)
            if new_img.size != old_img.size:
                rows.append(dict(path=rel.replace(os.sep, "/"), verdict="GEOMETRY",
                                 d_cov=1.0, d_bbox=999, rms_low=0.0, d_high=0.0,
                                 note=f"尺寸 {old_img.size} -> {new_img.size}"))
                continue

            n_cov, n_box, n_low, n_high = metrics(new_img)
            o_cov, o_box, o_low, o_high = metrics(old_img)

            d_cov = abs(n_cov - o_cov)
            d_bbox = max(abs(a - b) for a, b in zip(n_box, o_box))
            rms_low = float(np.sqrt(((n_low - o_low) ** 2).mean()))
            d_high = n_high - o_high   # 负数 = 高频能量下降 = 噪点减少

            rows.append(dict(path=rel.replace(os.sep, "/"),
                             verdict=classify(d_cov, d_bbox, rms_low, d_high),
                             d_cov=round(d_cov, 5), d_bbox=int(d_bbox),
                             rms_low=round(rms_low, 3), d_high=round(d_high, 3)))

    order = {"GEOMETRY": 0, "LOOKSHIFT": 1, "QUALITY": 2, "NEW": 3, "FLAT": 4}
    rows.sort(key=lambda r: (order.get(r["verdict"], 9), -r["rms_low"]))

    print(f"{'verdict':<10} {'d_cov':>8} {'d_box':>6} {'rms_low':>8} {'d_high':>8}  path")
    print("-" * 96)
    for r in rows:
        if args.quiet and r["verdict"] == "FLAT":
            continue
        print(f"{r['verdict']:<10} {r['d_cov']:>8.5f} {r['d_bbox']:>6} "
              f"{r['rms_low']:>8.3f} {r['d_high']:>8.3f}  {r['path']}"
              + (f"   [{r['note']}]" if r.get("note") else ""))

    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print("-" * 96)
    print("汇总: " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    quality = [r for r in rows if r["verdict"] == "QUALITY"]
    if quality:
        med = float(np.median([r["d_high"] for r in quality]))
        print(f"QUALITY 组高频能量变化中位数: {med:+.3f}  "
              + ("(噪点下降, 提质生效)" if med < 0 else "(未下降 —— 质量地板可能没起作用)"))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=1)
        print(f"已写入 {args.json}")

    geo = counts.get("GEOMETRY", 0)
    if geo:
        print(f"[FAIL] {geo} 张图的剪影发生变化 —— 极可能是陈旧脚本覆盖, 逐张核实后再提交。")
        return 1
    print("[OK] 没有剪影级别的变化。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
