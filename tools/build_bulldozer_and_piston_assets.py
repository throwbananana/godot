"""Build bulldozer enemy 6-frame animation and piston rounds powerup assets.

Adheres strictly to the game's Sokpop clay aesthetic:
- 256x256 RGBA format
- Tank faces UP (+Y)
- Distinct silhouette: wide heavy bulldozer plow with hydraulic pistons, caterpillar tracks, warning hazard stripes
- 6-frame animation loop (tread roll, hydraulic pulse, piston cycle)
- Passes qa_style_consistency.py and qa_tank_models_and_clipping.py
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "tools" else SCRIPT_DIR
TANKS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
POWERUPS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
EFFECTS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(TANKS_DIR, exist_ok=True)
os.makedirs(POWERUPS_DIR, exist_ok=True)
os.makedirs(EFFECTS_DIR, exist_ok=True)

def draw_shaded_bevel_rect(draw, bbox, fill, highlight, shadow, bevel=3):
    x0, y0, x1, y1 = bbox
    # Base fill
    draw.rectangle([x0, y0, x1, y1], fill=fill)
    # Highlight (top and left)
    for i in range(bevel):
        draw.line([x0 + i, y0 + i, x1 - i, y0 + i], fill=highlight)
        draw.line([x0 + i, y0 + i, x0 + i, y1 - i], fill=highlight)
    # Shadow (bottom and right)
    for i in range(bevel):
        draw.line([x0 + i, y1 - i, x1 - i, y1 - i], fill=shadow)
        draw.line([x1 - i, y0 + i, x1 - i, y1 - i], fill=shadow)

def render_enemy_bulldozer_frame(frame: int) -> Image.Image:
    """Render 1 frame of the 6-frame Bulldozer tank animation."""
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Color Palette: Industrial Heavy Terracotta / Hazard Bulldozer
    c_hull = (195, 110, 45, 255)         # Industrial Amber/Orange Clay Hull
    c_hull_hi = (235, 155, 80, 255)
    c_hull_sh = (140, 70, 25, 255)

    c_tread = (45, 45, 52, 255)          # Dark Cast Iron Treads
    c_tread_hi = (75, 75, 85, 255)
    c_tread_sh = (25, 25, 30, 255)

    c_plow = (175, 160, 145, 255)        # Heavy Steel Ramming Blade / Plow
    c_plow_hi = (225, 215, 205, 255)
    c_plow_sh = (105, 95, 85, 255)

    c_piston = (210, 175, 55, 255)       # Brass / Gold Hydraulic Cylinders
    c_piston_hi = (250, 220, 110, 255)
    c_piston_sh = (150, 115, 30, 255)

    c_hazard_yellow = (240, 195, 40, 255)

    # Animation offsets
    tread_cycle = (frame % 6) / 6.0
    piston_ext = math.sin(frame * (math.pi / 3.0)) * 3.5 # Hydraulic pulse forward/back
    vibe = math.sin(frame * math.pi) * 1.0

    # 1. Soft Clay Ground Contact Drop Shadow
    shadow_mask = Image.new("L", (256, 256), 0)
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.rounded_rectangle([45, 55, 211, 215], radius=24, fill=150)
    shadow_blur = shadow_mask.filter(ImageFilter.GaussianBlur(10))
    shadow_layer = Image.new("RGBA", (256, 256), (15, 12, 18, 0))
    shadow_layer.putalpha(shadow_blur)
    img.alpha_composite(shadow_layer)

    # 2. Heavy Dual Caterpillar Treads (Left & Right)
    tread_w = 34
    tread_h = 135
    for tx in [52, 170]:
        draw_shaded_bevel_rect(draw, [tx, 72, tx + tread_w, 72 + tread_h], c_tread, c_tread_hi, c_tread_sh, bevel=3)
        # Tread segment ridges
        step = 18
        for sy in range(0, tread_h, step):
            ry = 72 + int((sy + tread_cycle * step) % tread_h)
            draw.line([tx + 2, ry, tx + tread_w - 2, ry], fill=c_tread_sh, width=2)
            draw.line([tx + 2, ry + 2, tx + tread_w - 2, ry + 2], fill=c_tread_hi, width=1)

    # 3. Armored Main Chassis
    chassis_box = [76, 85 + int(vibe), 180, 195 + int(vibe)]
    draw_shaded_bevel_rect(draw, chassis_box, c_hull, c_hull_hi, c_hull_sh, bevel=5)

    # Rear engine exhaust grilles
    for ey in range(165, 186, 7):
        draw.line([95, ey, 161, ey], fill=c_hull_sh, width=3)
        draw.line([95, ey + 1, 161, ey + 1], fill=c_hull_hi, width=1)

    # 4. Heavy Turret Base & Hydraulic Mount
    turret_box = [98, 105, 158, 160]
    draw_shaded_bevel_rect(draw, turret_box, c_hull_sh, c_hull_hi, (90, 40, 15, 255), bevel=4)

    # Reinforced Cupola / Commander Hatch
    draw.ellipse([113, 118, 143, 148], fill=c_hull, outline=c_hull_hi, width=2)
    draw.ellipse([120, 125, 136, 141], fill=c_hull_sh)

    # 5. Dual Hydraulic Ram Cylinders (Left and Right of Plow)
    p_y0 = 85
    p_y1 = 52 - int(piston_ext)
    for px in [82, 162]:
        # Outer hydraulic cylinder
        draw_shaded_bevel_rect(draw, [px - 5, p_y0 - 20, px + 5, p_y0 + 15], c_hull_sh, c_hull_hi, (70, 30, 10, 255), bevel=2)
        # Piston rod extending forward
        draw_shaded_bevel_rect(draw, [px - 3, p_y1, px + 3, p_y0 - 15], c_piston, c_piston_hi, c_piston_sh, bevel=1)

    # 6. Heavy Front Bulldozer Shovel / Blade (Pushed slightly forward by piston_ext)
    blade_top = 40 - int(piston_ext)
    blade_bot = 68 - int(piston_ext)
    blade_left = 46
    blade_right = 210

    # Curved front bulldozer blade with heavy reinforcement
    draw.polygon([
        (blade_left, blade_bot),
        (blade_left + 8, blade_top),
        (blade_right - 8, blade_top),
        (blade_right, blade_bot),
        (blade_right - 14, blade_bot + 6),
        (blade_left + 14, blade_bot + 6)
    ], fill=c_plow, outline=c_plow_hi)

    # Upper rim highlight
    draw.line([blade_left + 8, blade_top, blade_right - 8, blade_top], fill=c_plow_hi, width=4)
    # Lower scraper edge (hardened dark steel)
    draw.line([blade_left, blade_bot, blade_right, blade_bot], fill=c_plow_sh, width=4)

    # Hazard stripes on the blade front
    stripe_w = 12
    for sx in range(blade_left + 14, blade_right - 20, stripe_w * 2):
        draw.polygon([
            (sx, blade_top + 2),
            (sx + stripe_w, blade_top + 2),
            (sx + stripe_w - 6, blade_bot - 2),
            (sx - 6, blade_bot - 2)
        ], fill=c_hazard_yellow)

    # Bulldozer breaker teeth along bottom edge
    for tx in range(blade_left + 18, blade_right - 18, 24):
        draw.polygon([
            (tx - 6, blade_bot),
            (tx + 6, blade_bot),
            (tx, blade_bot + 10)
        ], fill=c_plow_sh, outline=c_plow_hi)

    return img

def render_piston_rounds_powerup() -> Image.Image:
    """Render the 256x256 Piston Rounds Power-Up Icon."""
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Circular Clay Badge Foundation
    cx, cy = 128, 128
    r_outer = 100
    r_inner = 88

    # Outer drop shadow
    shadow_mask = Image.new("L", (256, 256), 0)
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.ellipse([cx - r_outer, cy - r_outer + 8, cx + r_outer, cy + r_outer + 8], fill=160)
    shadow_blur = shadow_mask.filter(ImageFilter.GaussianBlur(10))
    shadow_layer = Image.new("RGBA", (256, 256), (18, 15, 24, 0))
    shadow_layer.putalpha(shadow_blur)
    img.alpha_composite(shadow_layer)

    # Gold/Bronze Clay Plate Rim
    c_rim = (210, 160, 45, 255)
    c_rim_hi = (255, 220, 110, 255)
    c_rim_sh = (140, 95, 20, 255)
    draw.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=c_rim, outline=c_rim_hi, width=4)
    draw.ellipse([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner], fill=(42, 38, 50, 255), outline=c_rim_sh, width=3)

    # Center Motif: Heavy Industrial Kinetic Piston & Crushing Ram
    c_steel = (180, 185, 195, 255)
    c_steel_hi = (235, 240, 250, 255)
    c_steel_sh = (100, 105, 115, 255)

    c_ram = (240, 105, 35, 255)
    c_ram_hi = (255, 165, 80, 255)

    # Dual kinetic force arrows / piston ram head
    draw_shaded_bevel_rect(draw, [cx - 24, cy - 20, cx + 24, cy + 55], c_steel, c_steel_hi, c_steel_sh, bevel=3)
    # Shaft bands
    draw.line([cx - 22, cy, cx + 22, cy], fill=c_steel_sh, width=3)
    draw.line([cx - 22, cy + 25, cx + 22, cy + 25], fill=c_steel_sh, width=3)

    # Extended Heavy Ramming Piston Hammer Head (Arrow shape pointing UP)
    ram_head = [
        (cx, cy - 65),
        (cx + 42, cy - 25),
        (cx + 22, cy - 25),
        (cx + 22, cy - 10),
        (cx - 22, cy - 10),
        (cx - 22, cy - 25),
        (cx - 42, cy - 25)
    ]
    draw.polygon(ram_head, fill=c_ram, outline=c_ram_hi)

    # Impact shockwave arcs
    for arc_r in [65, 78]:
        draw.arc([cx - arc_r, cy - 70 - arc_r/2, cx + arc_r, cy - 70 + arc_r/2], start=210, end=330, fill=c_rim_hi, width=4)

    return img

def render_bullet_kinetic() -> Image.Image:
    """Render bullet_kinetic.png: heavy kinetic ram shell with piston fins."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Bullet travels UP (+Y is forward)
    aura = Image.new("L", (64, 64), 0)
    a_draw = ImageDraw.Draw(aura)
    a_draw.ellipse([18, 10, 46, 54], fill=120)
    aura_blur = aura.filter(ImageFilter.GaussianBlur(4))
    aura_layer = Image.new("RGBA", (64, 64), (255, 150, 40, 0))
    aura_layer.putalpha(aura_blur)
    img.alpha_composite(aura_layer)

    # Heavy Solid Bullet Core
    c_core = (245, 175, 45, 255)
    c_tip = (255, 240, 180, 255)
    c_sh = (180, 90, 20, 255)

    # Bullet capsule
    draw.polygon([
        (32, 8),
        (42, 22),
        (42, 50),
        (22, 50),
        (22, 22)
    ], fill=c_core, outline=c_tip)

    # Impact ram crown tip
    draw.polygon([(32, 6), (38, 16), (26, 16)], fill=c_tip)

    # Rear kinetic stabilization fins
    draw.polygon([(22, 42), (14, 52), (22, 50)], fill=c_sh)
    draw.polygon([(42, 42), (50, 52), (42, 50)], fill=c_sh)

    return img

def main():
    print("Building Enemy Bulldozer 6-frame animations...")
    for f in range(6):
        frame_img = render_enemy_bulldozer_frame(f)
        out_path = os.path.join(TANKS_DIR, f"enemy_bulldozer_f{f}.png")
        frame_img.save(out_path, "PNG")
        print(f"  [OK] Saved {out_path}")

    print("Building Piston Rounds powerup icon...")
    piston_img = render_piston_rounds_powerup()
    piston_path = os.path.join(POWERUPS_DIR, "piston_rounds.png")
    piston_img.save(piston_path, "PNG")
    print(f"  [OK] Saved {piston_path}")

    print("Building Kinetic bullet effect sprite...")
    bullet_img = render_bullet_kinetic()
    bullet_path = os.path.join(EFFECTS_DIR, "bullet_kinetic.png")
    bullet_img.save(bullet_path, "PNG")
    print(f"  [OK] Saved {bullet_path}")

    print("Asset generation complete!")

if __name__ == "__main__":
    main()
