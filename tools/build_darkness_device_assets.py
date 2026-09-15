"""Build Darkness Device (暗幕装置 / Eclipse Shroud Device) building assets.

Generates:
- assets/sprites/buildings/darkness_device.png
- assets/sprites/buildings/darkness_device_lit.png

Adheres strictly to the game's Sokpop clay aesthetic:
- 256x256 RGBA format
- Soft organic clay forms with beveled highlights and cast shadows
- Padding from frame edges to pass qa_style_consistency.py
- Deep obsidian/indigo clay monolith with an ethereal glowing violet crystal core
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "tools" else SCRIPT_DIR
BUILDINGS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(BUILDINGS_DIR, exist_ok=True)

def draw_clay_circle(draw, center, radius, fill_col, hi_col, sh_col, bevel=4):
    cx, cy = center
    # Drop shadow
    draw.ellipse([cx - radius + 3, cy - radius + 5, cx + radius + 3, cy + radius + 5], fill=(20, 15, 30, 90))
    # Base
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=fill_col)
    # Highlight arc (top-left)
    for b in range(bevel):
        r = radius - b
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=135, end=315, fill=hi_col, width=2)
    # Shadow arc (bottom-right)
    for b in range(bevel):
        r = radius - b
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=315, end=135, fill=sh_col, width=2)

def draw_beveled_polygon(draw, points, fill_col, hi_col, sh_col, light_dir=(-0.707, -0.707)):
    draw.polygon(points, fill=fill_col)
    n = len(points)
    for i in range(n):
        p1 = points[i]
        p2 = points[(i + 1) % n]
        edge_vec = (p2[0] - p1[0], p2[1] - p1[1])
        normal = (edge_vec[1], -edge_vec[0])
        length = math.hypot(normal[0], normal[1])
        if length > 0.001:
            normal = (normal[0] / length, normal[1] / length)
            dot = normal[0] * light_dir[0] + normal[1] * light_dir[1]
            if dot > 0.2:
                draw.line([p1, p2], fill=hi_col, width=3)
            elif dot < -0.2:
                draw.line([p1, p2], fill=sh_col, width=3)

def render_darkness_device(lit: bool = False) -> Image.Image:
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Clay Palette - Dark Obsidian / Deep Midnight Violet Clay
    c_pedestal_base = (38, 34, 52, 255)
    c_pedestal_hi = (72, 65, 96, 255)
    c_pedestal_sh = (22, 18, 32, 255)

    c_pillar = (48, 42, 68, 255)
    c_pillar_hi = (92, 82, 126, 255)
    c_pillar_sh = (28, 24, 42, 255)

    # Heavy Bronze/Brass Binding Bands
    c_bronze = (158, 112, 54, 255)
    c_bronze_hi = (218, 172, 94, 255)
    c_bronze_sh = (102, 72, 32, 255)

    # Crystal Colors
    if not lit:
        c_crystal = (105, 55, 145, 255)
        c_crystal_hi = (165, 95, 215, 255)
        c_crystal_sh = (65, 30, 95, 255)
        c_core = (185, 120, 235, 255)
    else:
        c_crystal = (170, 75, 235, 255)
        c_crystal_hi = (245, 180, 255, 255)
        c_crystal_sh = (115, 40, 165, 255)
        c_core = (255, 230, 255, 255)

    # 1. Soft Ambient Ground Shadow
    draw.ellipse([46, 170, 210, 234], fill=(12, 10, 20, 110))
    draw.ellipse([58, 176, 198, 226], fill=(8, 6, 14, 150))

    # 2. Bottom Stepped Pedestal (Hexagonal Clay Base)
    slab1_pts = [
        (66, 188), (128, 166), (190, 188),
        (190, 210), (128, 228), (66, 210)
    ]
    draw_beveled_polygon(draw, slab1_pts, c_pedestal_base, c_pedestal_hi, c_pedestal_sh)

    slab2_pts = [
        (76, 172), (128, 154), (180, 172),
        (180, 192), (128, 208), (76, 192)
    ]
    draw_beveled_polygon(draw, slab2_pts, (44, 38, 60, 255), c_pedestal_hi, c_pedestal_sh)

    for stud_x, stud_y in [(82, 196), (128, 212), (174, 196)]:
        draw_clay_circle(draw, (stud_x, stud_y), 5, c_bronze, c_bronze_hi, c_bronze_sh, bevel=2)

    # 3. Main Obelisk Monolith Body (Tapered Pyramidal Spire)
    facet_left = [
        (128, 48), (128, 168), (86, 156), (98, 76)
    ]
    facet_right = [
        (128, 48), (158, 76), (170, 156), (128, 168)
    ]
    draw_beveled_polygon(draw, facet_left, c_pillar_hi, (115, 105, 152, 255), c_pillar, light_dir=(-0.8, -0.6))
    draw_beveled_polygon(draw, facet_right, c_pillar_sh, c_pillar, (18, 14, 28, 255), light_dir=(-0.8, -0.6))

    draw.line([(128, 48), (128, 168)], fill=(120, 110, 160, 255), width=2)

    # 4. Bronze Ornamental Ribs / Rune Brackets
    collar_pts = [(104, 134), (128, 142), (152, 134), (150, 144), (128, 152), (106, 144)]
    draw_beveled_polygon(draw, collar_pts, c_bronze, c_bronze_hi, c_bronze_sh)

    collar_top_pts = [(114, 82), (128, 88), (142, 82), (140, 90), (128, 96), (116, 90)]
    draw_beveled_polygon(draw, collar_top_pts, c_bronze, c_bronze_hi, c_bronze_sh)

    # 5. Central Void Crystal Core
    socket_pts = [
        (128, 96), (144, 114), (128, 132), (112, 114)
    ]
    draw.polygon(socket_pts, fill=(16, 12, 24, 255))
    draw.line([(112, 114), (128, 96), (144, 114)], fill=c_pillar_sh, width=2)
    draw.line([(112, 114), (128, 132), (144, 114)], fill=c_pillar_hi, width=2)

    gem_pts_left = [(128, 100), (116, 114), (128, 128)]
    gem_pts_right = [(128, 100), (140, 114), (128, 128)]
    draw.polygon(gem_pts_left, fill=c_crystal_hi)
    draw.polygon(gem_pts_right, fill=c_crystal)
    draw.line([(128, 100), (128, 128)], fill=c_core, width=2)

    draw.ellipse([125, 111, 131, 117], fill=c_core)

    apex_pts = [(128, 38), (133, 48), (128, 54), (123, 48)]
    draw.polygon(apex_pts, fill=c_crystal_hi if lit else c_crystal)
    draw.line([(128, 38), (128, 54)], fill=c_core if lit else c_crystal_hi, width=1)

    # 6. If LIT: Radiant aura and energy flares
    if lit:
        glow_layer = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow_layer)

        gdraw.ellipse([88, 74, 168, 154], fill=(160, 50, 240, 55))
        gdraw.ellipse([100, 86, 156, 142], fill=(210, 80, 255, 90))
        gdraw.ellipse([114, 100, 142, 128], fill=(255, 180, 255, 150))

        gdraw.ellipse([116, 26, 140, 50], fill=(180, 60, 255, 80))
        gdraw.ellipse([123, 33, 133, 43], fill=(255, 230, 255, 180))

        ray_len = 26
        cx, cy = 128, 114
        for angle in [0, 45, 90, 135, 180, 225, 270, 315]:
            rad = math.radians(angle)
            rx = cx + math.cos(rad) * ray_len
            ry = cy + math.sin(rad) * ray_len
            gdraw.line([(cx, cy), (rx, ry)], fill=(255, 200, 255, 140), width=2)

        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=5))
        img = Image.alpha_composite(img, glow_layer)

        draw = ImageDraw.Draw(img)
        draw.ellipse([126, 112, 130, 116], fill=(255, 255, 255, 255))
        draw.line([(120, 114), (136, 114)], fill=(255, 255, 255, 230), width=1)
        draw.line([(128, 106), (128, 122)], fill=(255, 255, 255, 230), width=1)

    return img

def main():
    print("Generating Darkness Device assets...")
    img_unlit = render_darkness_device(lit=False)
    p_unlit = os.path.join(BUILDINGS_DIR, "darkness_device.png")
    img_unlit.save(p_unlit, "PNG")
    print(f"Saved: {p_unlit}")

    img_lit = render_darkness_device(lit=True)
    p_lit = os.path.join(BUILDINGS_DIR, "darkness_device_lit.png")
    img_lit.save(p_lit, "PNG")
    print(f"Saved: {p_lit}")

if __name__ == "__main__":
    main()
