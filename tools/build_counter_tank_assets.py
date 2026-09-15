"""Build Counter Tank (反击坦克) 6-frame animation assets for P1 & P2, Tier 1 & Tier 2.

Generates 24 frames total:
- assets/sprites/tanks/player_counter_t1_f0..f5.png
- assets/sprites/tanks/player_counter_t2_f0..f5.png
- assets/sprites/tanks/player2_counter_t1_f0..f5.png
- assets/sprites/tanks/player2_counter_t2_f0..f5.png

Adheres strictly to the Sokpop clay aesthetic:
- 256x256 RGBA format
- Tank faces UP (+Y)
- Distinct silhouette: prominent frontal heavy reactive buckler shield, heavy treads, reinforced gun mantle
- Passes qa_style_consistency.py
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "tools" else SCRIPT_DIR
TANKS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
os.makedirs(TANKS_DIR, exist_ok=True)

def draw_shaded_bevel_rect(draw, bbox, fill, highlight, shadow, bevel=3):
    x0, y0, x1, y1 = bbox
    draw.rectangle([x0, y0, x1, y1], fill=fill)
    for i in range(bevel):
        draw.line([x0 + i, y0 + i, x1 - i, y0 + i], fill=highlight)
        draw.line([x0 + i, y0 + i, x0 + i, y1 - i], fill=highlight)
        draw.line([x0 + i, y1 - i, x1 - i, y1 - i], fill=shadow)
        draw.line([x1 - i, y0 + i, x1 - i, y1 - i], fill=shadow)

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
                draw.line([p1, p2], fill=hi_col, width=2)
            elif dot < -0.2:
                draw.line([p1, p2], fill=sh_col, width=2)

def draw_clay_circle(draw, center, radius, fill_col, hi_col, sh_col, bevel=3):
    cx, cy = center
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=fill_col)
    for b in range(bevel):
        r = radius - b
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=135, end=315, fill=hi_col, width=2)
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=315, end=135, fill=sh_col, width=2)

def render_counter_tank_frame(is_p2: bool, tier: int, frame: int) -> Image.Image:
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Color Schemes
    if not is_p2:
        # P1: Classic Golden-Amber / Warm Bronze Clay
        c_hull = (215, 155, 45, 255)
        c_hull_hi = (250, 195, 95, 255)
        c_hull_sh = (150, 95, 25, 255)

        c_turret = (235, 175, 60, 255) if tier == 1 else (245, 185, 70, 255)
        c_turret_hi = (255, 215, 120, 255)
        c_turret_sh = (170, 115, 30, 255)

        c_shield = (165, 170, 185, 255) if tier == 1 else (190, 195, 210, 255) # Polished Steel Shield
        c_shield_hi = (225, 230, 245, 255)
        c_shield_sh = (105, 110, 125, 255)

        c_energy = (255, 215, 50, 255) if tier == 1 else (60, 220, 255, 255) # Cyan capacitors on T2!
    else:
        # P2: Vibrant Emerald / Teal Mint Clay
        c_hull = (40, 165, 115, 255)
        c_hull_hi = (85, 210, 155, 255)
        c_hull_sh = (20, 105, 70, 255)

        c_turret = (50, 185, 130, 255) if tier == 1 else (60, 205, 145, 255)
        c_turret_hi = (100, 230, 175, 255)
        c_turret_sh = (25, 120, 80, 255)

        c_shield = (155, 165, 175, 255) if tier == 1 else (180, 190, 205, 255)
        c_shield_hi = (215, 225, 235, 255)
        c_shield_sh = (95, 105, 115, 255)

        c_energy = (255, 140, 40, 255) if tier == 1 else (255, 220, 60, 255)

    c_tread = (45, 45, 52, 255)
    c_tread_hi = (75, 75, 85, 255)
    c_tread_sh = (25, 25, 30, 255)

    c_barrel = (75, 78, 88, 255)
    c_barrel_hi = (115, 118, 130, 255)
    c_barrel_sh = (45, 48, 55, 255)

    # 1. Drop Shadows under treads and hull
    draw.ellipse([58, 70, 198, 212], fill=(15, 15, 22, 100))

    # 2. Heavy Dual Caterpillar Treads
    tread_w = 26 if tier == 1 else 30
    tread_h = 120
    t_top = 74
    t_bot = t_top + tread_h

    # Left Tread
    draw_shaded_bevel_rect(draw, [62, t_top, 62 + tread_w, t_bot], c_tread, c_tread_hi, c_tread_sh, bevel=3)
    # Right Tread
    draw_shaded_bevel_rect(draw, [194 - tread_w, t_top, 194, t_bot], c_tread, c_tread_hi, c_tread_sh, bevel=3)

    # Tread rolling teeth (6-frame cycle)
    tooth_spacing = 16
    y_offset = (frame * (tooth_spacing / 6.0)) % tooth_spacing
    for y in range(int(t_top + y_offset), int(t_bot - 4), tooth_spacing):
        draw.line([62, y, 62 + tread_w, y], fill=(70, 70, 80, 255), width=2)
        draw.line([194 - tread_w, y, 194, y], fill=(70, 70, 80, 255), width=2)

    # Road wheels inside tracks
    for wy in [t_top + 20, t_top + 50, t_top + 80, t_top + 105]:
        draw_clay_circle(draw, (62 + tread_w // 2, wy), 7, (55, 55, 62, 255), (85, 85, 95, 255), (35, 35, 40, 255), bevel=2)
        draw_clay_circle(draw, (194 - tread_w // 2, wy), 7, (55, 55, 62, 255), (85, 85, 95, 255), (35, 35, 40, 255), bevel=2)

    # 3. Main Armored Chassis Hull
    hx0, hy0, hx1, hy1 = 82, 86, 174, 190
    draw_shaded_bevel_rect(draw, [hx0, hy0, hx1, hy1], c_hull, c_hull_hi, c_hull_sh, bevel=4)

    # Rear engine exhaust grille
    draw_shaded_bevel_rect(draw, [96, 172, 160, 186], (40, 38, 46, 255), (70, 68, 76, 255), (25, 22, 30, 255), bevel=2)
    for gx in [104, 116, 128, 140, 152]:
        draw.line([gx, 174, gx, 184], fill=(95, 90, 105, 255), width=2)

    # 4. Heavy Counter Cannon Barrel (protrudes forward)
    bx0, by0, bx1, by1 = 122, 34, 134, 96
    draw_shaded_bevel_rect(draw, [bx0, by0, bx1, by1], c_barrel, c_barrel_hi, c_barrel_sh, bevel=2)
    # Reinforced Muzzle Brake
    draw_shaded_bevel_rect(draw, [118, 30, 138, 42], c_barrel_hi, (160, 165, 180, 255), c_barrel_sh, bevel=2)

    # 5. Turret Dome
    tx0, ty0, tx1, ty1 = 98, 96, 158, 154
    draw_shaded_bevel_rect(draw, [tx0, ty0, tx1, ty1], c_turret, c_turret_hi, c_turret_sh, bevel=4)

    # Commander's Hatch / Sensor
    draw_clay_circle(draw, (142, 118), 10, c_turret_sh, c_turret_hi, (30, 30, 35, 255), bevel=2)

    # 6. Prominent Frontal Reactive Parry Buckler / Deflector Shield!
    # In Tier 1: Heavy hexagonal frontal wedge shield
    # In Tier 2: Wide dual-wing reactive fortress buckler with energy conduits
    if tier == 1:
        # Angled Deflector Shield Wedge
        shield_pts = [
            (74, 82), (128, 54), (182, 82),
            (174, 98), (128, 76), (82, 98)
        ]
        draw_beveled_polygon(draw, shield_pts, c_shield, c_shield_hi, c_shield_sh)

        # Reactive Shield Studs & Center Emblem
        for sx, sy in [(92, 84), (128, 64), (164, 84)]:
            draw_clay_circle(draw, (sx, sy), 4, c_energy, (255, 255, 220, 255), (120, 90, 10, 255), bevel=1)

        # Reinforced Hydraulic Struts connecting Shield to Chassis
        draw.line([(88, 96), (88, 112)], fill=c_barrel, width=4)
        draw.line([(168, 96), (168, 112)], fill=c_barrel, width=4)

    else:
        # Tier 2: Advanced Wide Reactive Fortress Buckler
        shield_pts = [
            (64, 76), (128, 46), (192, 76),
            (186, 98), (128, 72), (70, 98)
        ]
        draw_beveled_polygon(draw, shield_pts, c_shield, c_shield_hi, c_shield_sh)

        # Secondary angled flank deflectors
        left_flank = [(58, 86), (70, 78), (72, 106), (60, 102)]
        right_flank = [(186, 78), (198, 86), (196, 102), (184, 106)]
        draw_beveled_polygon(draw, left_flank, c_shield_sh, c_shield_hi, (50, 55, 65, 255))
        draw_beveled_polygon(draw, right_flank, c_shield_sh, c_shield_hi, (50, 55, 65, 255))

        # Hyper-Conductive Glowing Energy Channels
        draw.line([(76, 84), (128, 58)], fill=c_energy, width=3)
        draw.line([(128, 58), (180, 84)], fill=c_energy, width=3)
        draw.line([(128, 58), (128, 72)], fill=c_energy, width=3)

        # Power Nodes on Shield Wings
        for sx, sy in [(74, 84), (128, 56), (182, 84)]:
            draw_clay_circle(draw, (sx, sy), 5, c_energy, (255, 255, 255, 255), (30, 80, 120, 255), bevel=2)

        # Heavy Double Hydraulic Shock Absorbers
        draw.line([(82, 96), (82, 116)], fill=(120, 125, 138, 255), width=5)
        draw.line([(174, 96), (174, 116)], fill=(120, 125, 138, 255), width=5)

    return img

def main():
    print("Generating Counter Tank 6-frame animations (P1 & P2, T1 & T2)...")
    configs = [
        ("player_counter_t1", False, 1),
        ("player_counter_t2", False, 2),
        ("player2_counter_t1", True, 1),
        ("player2_counter_t2", True, 2),
    ]

    for prefix, is_p2, tier in configs:
        for f in range(6):
            img = render_counter_tank_frame(is_p2, tier, f)
            out_path = os.path.join(TANKS_DIR, f"{prefix}_f{f}.png")
            img.save(out_path, "PNG")
        print(f"Saved: {prefix}_f0..f5.png")

if __name__ == "__main__":
    main()
