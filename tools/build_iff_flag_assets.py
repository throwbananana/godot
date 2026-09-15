#!/usr/bin/env python3
"""
Build assets for Friendly IFF Flag (友军标识旗).
Generates assets/sprites/powerups/iff_flag.png adhering strictly to Sokpop clay aesthetic.
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter

ASSETS_DIR = "assets/sprites/powerups"
os.makedirs(ASSETS_DIR, exist_ok=True)

def render_iff_flag_powerup() -> Image.Image:
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = 128, 128
    r_outer = 102
    r_inner = 88

    # 1. Soft clay drop shadow
    shadow_mask = Image.new("L", (256, 256), 0)
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.ellipse([cx - r_outer, cy - r_outer + 10, cx + r_outer, cy + r_outer + 10], fill=150)
    shadow_blur = shadow_mask.filter(ImageFilter.GaussianBlur(10))
    shadow_layer = Image.new("RGBA", (256, 256), (15, 12, 22, 0))
    shadow_layer.putalpha(shadow_blur)
    img.alpha_composite(shadow_layer)

    # 2. Circular Clay Plate Rim (Gold/Bronze)
    c_rim = (212, 162, 48, 255)
    c_rim_hi = (255, 225, 115, 255)
    c_rim_sh = (138, 92, 22, 255)
    draw.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=c_rim, outline=c_rim_hi, width=4)
    # Inner clay bevel circle
    c_bg = (32, 44, 58, 255) # Deep navy/slate clay
    draw.ellipse([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner], fill=c_bg, outline=c_rim_sh, width=3)

    # 3. Concentric IFF Signal Waves (broadcasting friendly beacon)
    wave_center = (90, 56)
    for rad, alpha in [(36, 110), (52, 160), (68, 100)]:
        wave_box = [wave_center[0] - rad, wave_center[1] - rad, wave_center[0] + rad, wave_center[1] + rad]
        draw.arc(wave_box, start=290, end=410, fill=(80, 230, 140, alpha), width=3)

    # 4. Brass Flagpole
    pole_base = (78, 206)
    pole_top = (90, 52)
    # Draw pole with highlight and shadow
    draw.line([pole_base[0] + 1, pole_base[1] + 1, pole_top[0] + 1, pole_top[1] + 1], fill=(90, 60, 15, 255), width=7)
    draw.line([pole_base[0], pole_base[1], pole_top[0], pole_top[1]], fill=(225, 180, 50, 255), width=5)
    draw.line([pole_base[0] - 1, pole_base[1] - 1, pole_top[0] - 1, pole_top[1] - 1], fill=(255, 235, 130, 255), width=2)

    # Golden Sphere Finial
    draw.ellipse([pole_top[0] - 8, pole_top[1] - 8, pole_top[0] + 8, pole_top[1] + 8], fill=(245, 195, 55, 255), outline=(255, 240, 160, 255), width=2)
    # Finial specular dot
    draw.ellipse([pole_top[0] - 4, pole_top[1] - 5, pole_top[0], pole_top[1] - 1], fill=(255, 255, 230, 255))

    # 5. Heraldic IFF Flag Fabric (Heroic Emerald & Gold trim with clay wave ripples)
    flag_points = [
        (88, 62),
        (135, 58),
        (185, 68),
        (196, 115),
        (148, 108),
        (192, 152),
        (140, 144),
        (86, 154)
    ]
    # Fabric shadow
    draw.polygon([(p[0] + 3, p[1] + 4) for p in flag_points], fill=(18, 70, 38, 255))
    # Fabric main emerald green body
    c_flag = (42, 168, 92, 255)
    c_flag_hi = (75, 218, 132, 255)
    c_flag_sh = (24, 115, 60, 255)
    draw.polygon(flag_points, fill=c_flag, outline=c_flag_hi, width=3)

    # Fabric wavy fold lines
    draw.line([(135, 58), (148, 108), (140, 144)], fill=c_flag_sh, width=4)
    draw.line([(138, 59), (151, 109), (143, 145)], fill=c_flag_hi, width=2)

    # Gold embroidered fringe/border on outer edge
    fringe = [(185, 68), (196, 115), (148, 108), (192, 152), (140, 144)]
    draw.line(fringe, fill=(255, 215, 65, 255), width=4)

    # 6. Center Emblem: Iconic Base Eagle Silhouette & Shield (Friend-or-Foe Identity)
    # Scaled eagle symbol on flag center
    ex, ey = 136, 102
    eagle_poly = [
        (ex, ey - 20),      # Top beak/crest
        (ex + 8, ey - 13),  # Head right
        (ex + 22, ey - 18), # Right wing tip
        (ex + 25, ey - 3),  # Wing fold right
        (ex + 14, ey + 8),  # Right wing base
        (ex + 16, ey + 18), # Tail right
        (ex, ey + 22),      # Tail tip
        (ex - 16, ey + 18), # Tail left
        (ex - 14, ey + 8),  # Left wing base
        (ex - 25, ey - 3),  # Wing fold left
        (ex - 22, ey - 18), # Left wing tip
        (ex - 8, ey - 13)   # Head left
    ]
    # Eagle shadow
    draw.polygon([(p[0] + 2, p[1] + 2) for p in eagle_poly], fill=(15, 50, 30, 255))
    # Eagle gold clay fill
    draw.polygon(eagle_poly, fill=(255, 220, 65, 255), outline=(255, 245, 140, 255), width=2)

    # Heart/Shield of the Eagle (White/Cyan Star for Friendly IFF)
    draw.ellipse([ex - 6, ey - 4, ex + 6, ey + 8], fill=(240, 250, 255, 255), outline=(120, 210, 255, 255), width=2)
    # Mini checkmark or star
    draw.line([ex - 3, ey + 2, ex, ey + 5, ex + 4, ey - 1], fill=(30, 140, 70, 255), width=2)

    # Add subtle clay tactile texture
    noise = Image.effect_noise((256, 256), 6)
    noise_rgba = Image.new("RGBA", (256, 256), (255, 255, 255, 0))
    n_data = []
    for val in noise.getdata():
        if val > 160:
            n_data.append((255, 255, 255, 14))
        elif val < 95:
            n_data.append((0, 0, 0, 14))
        else:
            n_data.append((0, 0, 0, 0))
    noise_rgba.putdata(n_data)
    img.alpha_composite(noise_rgba)

    return img

if __name__ == "__main__":
    out_path = os.path.join(ASSETS_DIR, "iff_flag.png")
    flag_img = render_iff_flag_powerup()
    flag_img.save(out_path)
    print(f"Successfully rendered Friendly IFF Flag: {out_path} ({flag_img.size})")
