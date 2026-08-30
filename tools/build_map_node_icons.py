import os, glob
import numpy as np
from PIL import Image, ImageFilter
from collections import deque

brain_dir = r"C:\Users\123\.gemini\antigravity-cli\brain\e6b7ebf3-be08-4bef-bc66-190f6222dfc8"
target_dir = r"assets/sprites/map"

node_mappings = {
    "node_start.png": "node_start_clay*.jpg",
    "node_battle.png": "node_battle_clay*.jpg",
    "node_elite.png": "node_elite_clay*.jpg",
    "node_boss.png": "node_boss_clay*.jpg",
    "node_shop.png": "node_shop_clay*.jpg",
    "node_treasure.png": "node_treasure_clay*.jpg",
    "node_challenge.png": "node_challenge_clay*.jpg",
    "node_event.png": "node_event_clay*.jpg",
    "node_rest.png": "node_rest_clay*.jpg",
    "node_secret.png": "node_secret_clay*.jpg",
}

def extract_clean_icon(img_path):
    im = Image.open(img_path).convert('RGB')
    arr = np.array(im, dtype=np.int32)
    h, w, _ = arr.shape
    
    r, g, b = arr[:,:,0], arr[:,:,1], arr[:,:,2]
    max_c = np.maximum(np.maximum(r, g), b)
    min_c = np.minimum(np.minimum(r, g), b)
    color_diff = max_c - min_c
    
    corners = [arr[0,0], arr[0,w-1], arr[h-1,0], arr[h-1,w-1]]
    avg_corner_brightness = np.mean([np.mean(c) for c in corners])
    is_light_bg = avg_corner_brightness > 100
    
    bg_mask = np.zeros((h, w), dtype=bool)
    queue = deque()
    
    for x in range(w):
        for y in [0, h-1]:
            if color_diff[y, x] < 22:
                bg_mask[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w-1]:
            if not bg_mask[y, x] and color_diff[y, x] < 22:
                bg_mask[y, x] = True
                queue.append((y, x))
                
    while queue:
        cy, cx = queue.popleft()
        for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and not bg_mask[ny, nx]:
                if color_diff[ny, nx] < 22:
                    if is_light_bg:
                        if min_c[ny, nx] > 130:
                            bg_mask[ny, nx] = True
                            queue.append((ny, nx))
                    else:
                        if max_c[ny, nx] < 100:
                            bg_mask[ny, nx] = True
                            queue.append((ny, nx))
    
    alpha = np.where(bg_mask, 0, 255).astype(np.uint8)
    
    # Clean up isolated noise
    alpha_img = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(1.2))
    alpha_arr = np.array(alpha_img)
    alpha_final = np.clip((alpha_arr.astype(float) - 40) * (255.0 / (215.0 - 40)), 0, 255).astype(np.uint8)
    
    res = Image.new('RGBA', (w, h))
    res.paste(im, (0, 0))
    res.putalpha(Image.fromarray(alpha_final))
    
    # Crop to bounding box of content
    bbox = res.getbbox()
    if bbox:
        cropped = res.crop(bbox)
        # Place centered in a square canvas with ~10% padding
        bw = bbox[2] - bbox[0]
        bh = bbox[3] - bbox[1]
        max_dim = max(bw, bh)
        target_canvas_size = int(max_dim * 1.15)
        canvas = Image.new('RGBA', (target_canvas_size, target_canvas_size), (0, 0, 0, 0))
        offset_x = (target_canvas_size - bw) // 2
        offset_y = (target_canvas_size - bh) // 2
        canvas.paste(cropped, (offset_x, offset_y), cropped)
        # Resize to 256x256
        final_img = canvas.resize((256, 256), Image.Resampling.LANCZOS)
        return final_img
    else:
        return res.resize((256, 256), Image.Resampling.LANCZOS)

for out_name, pattern in node_mappings.items():
    matches = glob.glob(os.path.join(brain_dir, pattern))
    if matches:
        src = matches[0]
        out_path = os.path.join(target_dir, out_name)
        icon = extract_clean_icon(src)
        icon.save(out_path, 'PNG')
        print(f"[OK] Processed {out_name} (256x256 RGBA) from {os.path.basename(src)}")
    else:
        print(f"[ERR] No source image found for {out_name} matching {pattern}")

