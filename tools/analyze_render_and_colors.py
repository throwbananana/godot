import os
from PIL import Image
import numpy as np

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot\assets\sprites"

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
                report.append((rel_path, w, h, 0.0, 0.0, 0.0, 0.0))
                continue
                
            rgb = arr[:, :, :3][opaque_mask]
            
            # 纯白/过曝像素 (RGB >= 250)
            blown_pixels = np.sum(np.all(rgb >= 250, axis=1))
            blown_pct = (blown_pixels / float(opaque_count)) * 100.0
            
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
            
            report.append((rel_path, w, h, blown_pct, avg_lum, avg_sat, warm_pct))

print(f"Total Analyzed PNGs: {total_pngs}")
print("=" * 95)
print(f"{'Asset Name':<38} | {'Resolution':<10} | {'Blown %':<8} | {'Avg Lum':<8} | {'Avg Sat %':<9} | {'Warm %':<8}")
print("=" * 95)

categories = ['tanks', 'tiles', 'buildings', 'powerups', 'effects', 'map', 'ui']
for cat in categories:
    print(f"\n--- [CATEGORY: {cat.upper()}] ---")
    cat_items = [item for item in report if item[0].startswith(cat)]
    for r in cat_items:
        print(f"{r[0]:<38} | {r[1]}x{r[2]:<6} | {r[3]:>7.2f}% | {r[4]:>7.1f} | {r[5]:>8.1f}% | {r[6]:>6.1f}%")
