import os
from PIL import Image
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
ROOT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
PROJECT_DIR = os.path.join(ROOT_DIR, "assets", "sprites")

report = []
total_pngs = 0

for root, dirs, files in os.walk(PROJECT_DIR):
    for f in sorted(files):
        if f.endswith('.png'):
            total_pngs += 1
            path = os.path.join(root, f)
            rel_path = os.path.relpath(path, PROJECT_DIR)
            im = Image.open(path).convert('RGBA')
            arr = np.array(im)
            
            w, h = im.size
            alpha = arr[:, :, 3]
            opaque_mask = alpha > 25
            opaque_count = np.sum(opaque_mask)
            
            if opaque_count == 0:
                report.append((rel_path, w, h, 0.0, 0.0, 0.0, 0.0, 0.0))
                continue
                
            rgb = arr[:, :, :3][opaque_mask]
            
            # 纯白/过曝像素 (RGB 三通道同时 >= 250)
            blown_pixels = np.sum(np.all(rgb >= 250, axis=1))
            blown_pct = (blown_pixels / float(opaque_count)) * 100.0

            # 单通道裁剪 (任一通道 >= 250)。上面那个"全白"指标会漏报单通道溢出:
            # 自发光资源常见 R 还很低、G/B 早就撞顶, 于是 blown% 显示 0.00 却已经
            # 丢了色彩细节。判断有没有过曝要看这一列。
            clipped_pixels = np.sum(np.any(rgb >= 250, axis=1))
            clipped_pct = (clipped_pixels / float(opaque_count)) * 100.0
            
            # 平均亮度 (Luminance)
            lum = 0.299 * rgb[:, 0] + 0.587 * rgb[:, 1] + 0.114 * rgb[:, 2]
            avg_lum = np.mean(lum)
            
            # 饱和度 (HSV S)
            max_c = np.max(rgb, axis=1).astype(float)
            min_c = np.min(rgb, axis=1).astype(float)
            diff = max_c - min_c
            s = np.zeros_like(max_c)
            non_zero = max_c > 0
            s[non_zero] = diff[non_zero] / max_c[non_zero]
            avg_sat = np.mean(s) * 100.0
            
            # 暖色比例 (R >= B)
            warm_count = np.sum(rgb[:, 0] >= rgb[:, 2])
            warm_pct = (warm_count / float(opaque_count)) * 100.0
            
            report.append((rel_path, w, h, blown_pct, clipped_pct, avg_lum, avg_sat, warm_pct))

print(f"Total Analyzed PNGs: {total_pngs}")
print("=" * 108)
print(f"{'Asset Name':<38} | {'Resolution':<10} | {'Blown %':<8} | {'Clip %':<8} | {'Avg Lum':<8} | {'Avg Sat %':<9} | {'Warm %':<8}")
print("=" * 108)

categories = ['tanks', 'tiles', 'buildings', 'powerups', 'effects', 'map', 'ui']
for cat in categories:
    print(f"\n--- [CATEGORY: {cat.upper()}] ---")
    cat_items = [item for item in report if item[0].startswith(cat)]
    for r in cat_items:
        print(f"{r[0]:<38} | {r[1]}x{r[2]:<6} | {r[3]:>7.2f}% | {r[4]:>7.2f}% | {r[5]:>7.1f} | {r[6]:>8.1f}% | {r[7]:>6.1f}%")

# 两列的读法不一样, 别拿 Clip% 当过曝告警:
#   Clip%  = 任一通道触顶。饱和色天然会触顶 —— 纯黄就是 R=255,G=255 —— 所以
#            高 Clip% 配高 Sat% 是正常的鲜艳色块, 不是缺陷。
#   Blown% = 三通道同时触顶, 即像素退化成纯白, 色相彻底丢失。这一列才是告警。
worst = sorted(report, key=lambda r: -r[3])[:8]
print("\n" + "=" * 108)
print("最严重的纯白过曝 (Top 8) —— Blown% >2% 才需要压自发光或降灯光:")
for r in worst:
    flag = "  <-- 需处理" if r[3] > 2.0 else ""
    print(f"  {r[0]:<38} blown {r[3]:>6.2f}%   clip {r[4]:>6.2f}%   sat {r[6]:>5.1f}%{flag}")
sat_vals = [r[6] for r in report if r[6] > 0]
print(f"\n全体平均饱和度: {sum(sat_vals)/len(sat_vals):.1f}%  (共 {len(sat_vals)} 张)")
print(f"纯白过曝 >2% 的资源数: {sum(1 for r in report if r[3] > 2.0)} / {len(report)}")
