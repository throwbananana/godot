"""Build Trench Tank (壕沟战坦克) Assets:
- Enemy Trench Tank: assets/sprites/tanks/enemy_trench_f0..f5.png (6 frames)
- Player Trench Tank P1 Tier 1 & Tier 2: assets/sprites/tanks/player_trench_t1_f0..f5.png, player_trench_t2_f0..f5.png
- Player Trench Tank P2 Tier 1 & Tier 2: assets/sprites/tanks/player2_trench_t1_f0..f5.png, player2_trench_t2_f0..f5.png
- Laser Ring Cutter VFX: assets/sprites/effects/laser_ring_cutter.png (256x256 RGBA)
- UI Icon: assets/sprites/ui/perk_trench.png (256x256 RGBA)

Strictly adheres to Sokpop clay aesthetic and passes qa_style_consistency.py.
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == "tools" else SCRIPT_DIR
TANKS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
EFFECTS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
UI_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

for d in [TANKS_DIR, EFFECTS_DIR, UI_DIR]:
    os.makedirs(d, exist_ok=True)

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

def apply_clay_texture(img: Image.Image, roughness=8.0) -> Image.Image:
    arr = np.array(img).astype(np.float32)
    alpha = arr[:, :, 3] / 255.0
    h, w = arr.shape[:2]
    np.random.seed(42)
    noise = np.random.normal(0, roughness, (h, w, 1))
    arr[:, :, :3] = np.clip(arr[:, :, :3] + noise * alpha[:, :, np.newaxis], 0, 255)
    return Image.fromarray(arr.astype(np.uint8))

def render_trench_tank(kind: str, tier: int, frame: int) -> Image.Image:
    """kind: 'enemy', 'player', 'player2'"""
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if kind == "enemy":
        c_hull = (78, 92, 74, 255)         # Deep Trench Mud-Olive
        c_hull_hi = (108, 126, 102, 255)
        c_hull_sh = (48, 58, 45, 255)

        c_turret = (88, 102, 82, 255)
        c_turret_hi = (120, 138, 112, 255)
        c_turret_sh = (55, 65, 52, 255)

        c_projector = (140, 145, 155, 255) # Rugged Gunmetal Emitter
        c_projector_hi = (185, 192, 205, 255)
        c_projector_sh = (85, 90, 100, 255)

        c_energy = (255, 130, 45, 255)      # Amber-Crimson Laser Plasma
        c_energy_hi = (255, 220, 120, 255)

    elif kind == "player":
        # P1: Warm Golden-Amber / Bronze
        c_hull = (210, 152, 45, 255)
        c_hull_hi = (248, 192, 92, 255)
        c_hull_sh = (145, 92, 25, 255)

        c_turret = (230, 172, 58, 255) if tier == 1 else (242, 182, 68, 255)
        c_turret_hi = (255, 212, 118, 255)
        c_turret_sh = (165, 112, 30, 255)

        c_projector = (155, 160, 175, 255) if tier == 1 else (185, 190, 208, 255)
        c_projector_hi = (215, 222, 240, 255)
        c_projector_sh = (95, 100, 115, 255)

        c_energy = (50, 210, 255, 255) if tier == 1 else (80, 245, 255, 255) # Cyan Plasma
        c_energy_hi = (200, 255, 255, 255)

    else:
        # P2: Emerald / Mint Teal
        c_hull = (38, 162, 112, 255)
        c_hull_hi = (82, 208, 152, 255)
        c_hull_sh = (20, 102, 68, 255)

        c_turret = (48, 182, 126, 255) if tier == 1 else (58, 202, 142, 255)
        c_turret_hi = (98, 228, 172, 255)
        c_turret_sh = (24, 118, 78, 255)

        c_projector = (150, 160, 170, 255) if tier == 1 else (178, 188, 202, 255)
        c_projector_hi = (210, 220, 232, 255)
        c_projector_sh = (92, 102, 112, 255)

        c_energy = (255, 180, 50, 255) if tier == 1 else (255, 235, 90, 255)
        c_energy_hi = (255, 255, 200, 255)

    c_tread = (44, 44, 50, 255)
    c_tread_hi = (72, 72, 82, 255)
    c_tread_sh = (24, 24, 28, 255)

    # 1. Soft ground contact drop shadow
    draw.ellipse([54, 68, 202, 218], fill=(16, 16, 24, 110))

    # 2. Heavy Trench Caterpillar Tracks (Extended Rhomboid profile)
    tread_w = 28 if tier == 1 else 32
    t_top = 68
    t_bot = 202

    # Left Track
    draw_shaded_bevel_rect(draw, [58, t_top, 58 + tread_w, t_bot], c_tread, c_tread_hi, c_tread_sh, bevel=3)
    # Right Track
    draw_shaded_bevel_rect(draw, [198 - tread_w, t_top, 198, t_bot], c_tread, c_tread_hi, c_tread_sh, bevel=3)

    # Rolling Trench Cleats / Barbed Claws (6 frames)
    tooth_spacing = 16
    y_offset = (frame * (tooth_spacing / 6.0)) % tooth_spacing
    for y in range(int(t_top + y_offset), int(t_bot - 4), tooth_spacing):
        draw.line([58, y, 58 + tread_w, y], fill=(68, 68, 78, 255), width=3)
        draw.line([198 - tread_w, y, 198, y], fill=(68, 68, 78, 255), width=3)

    # Heavy Bogie Wheels
    for wy in [t_top + 22, t_top + 54, t_top + 86, t_top + 118]:
        draw_clay_circle(draw, (58 + tread_w // 2, wy), 8, (52, 52, 60, 255), (82, 82, 94, 255), (32, 32, 38, 255), bevel=2)
        draw_clay_circle(draw, (198 - tread_w // 2, wy), 8, (52, 52, 60, 255), (82, 82, 94, 255), (32, 32, 38, 255), bevel=2)

    # 3. Main Trench Chassis Hull (Angled Frontal Wedge)
    hx0, hy0, hx1, hy1 = 80, 80, 176, 194
    draw_shaded_bevel_rect(draw, [hx0, hy0, hx1, hy1], c_hull, c_hull_hi, c_hull_sh, bevel=4)

    # Rear Trench Crossing Tail Spud / Skid
    draw_shaded_bevel_rect(draw, [96, 188, 160, 206], (40, 42, 48, 255), (65, 68, 76, 255), (25, 26, 30, 255), bevel=2)
    draw.line([106, 190, 106, 204], fill=(80, 84, 94, 255), width=2)
    draw.line([150, 190, 150, 204], fill=(80, 84, 94, 255), width=2)

    # 4. Trench Prow & Heavy Cutter Housing
    # Forward Armor Wedge
    wedge_pts = [(78, 88), (128, 56), (178, 88), (168, 106), (128, 80), (88, 106)]
    draw_beveled_polygon(draw, wedge_pts, c_hull, c_hull_hi, c_hull_sh)

    # 5. Low Profile Trench Turret
    tx0, ty0, tx1, ty1 = 96, 96, 160, 154
    draw_shaded_bevel_rect(draw, [tx0, ty0, tx1, ty1], c_turret, c_turret_hi, c_turret_sh, bevel=4)

    # Commander's Periscope Cupola
    draw_clay_circle(draw, (142, 116), 11, c_turret_sh, c_turret_hi, (28, 28, 34, 255), bevel=2)

    # 6. SIGNATURE: Forward Laser Ring Cutting Projector!
    # Central High-Frequency Projector Lens
    lens_center = (128, 62)
    draw_clay_circle(draw, lens_center, 14 if tier == 1 else 17, c_projector, c_projector_hi, c_projector_sh, bevel=3)
    # Glowing Laser Core
    draw_clay_circle(draw, lens_center, 8 if tier == 1 else 10, c_energy, c_energy_hi, (100, 50, 10, 255), bevel=2)
    # Bright Energy Sparkle
    draw_clay_circle(draw, (126, 60), 3, (255, 255, 255, 255), (255, 255, 255, 255), c_energy, bevel=1)

    # Dual Arc Focusing Emitter Horns (Flanking the lens)
    horn_l = [(104, 76), (108, 48), (116, 52), (116, 76)]
    horn_r = [(140, 76), (140, 52), (148, 48), (152, 76)]
    draw_beveled_polygon(draw, horn_l, c_projector, c_projector_hi, c_projector_sh)
    draw_beveled_polygon(draw, horn_r, c_projector, c_projector_hi, c_projector_sh)

    # Emitter Horn Tips (Laser Focus Crystals)
    draw_clay_circle(draw, (112, 50), 3, c_energy, c_energy_hi, c_projector_sh, bevel=1)
    draw_clay_circle(draw, (144, 50), 3, c_energy, c_energy_hi, c_projector_sh, bevel=1)

    # Laser induction coils connecting to turret
    draw.line([(114, 76), (114, 98)], fill=(65, 70, 80, 255), width=3)
    draw.line([(142, 76), (142, 98)], fill=(65, 70, 80, 255), width=3)

    if tier >= 2:
        # Tier 2: Flank Fortress Armor Plates & Dual Plasma Emitters
        flank_l = [(50, 88), (64, 80), (66, 126), (52, 122)]
        flank_r = [(190, 80), (204, 88), (202, 122), (188, 126)]
        draw_beveled_polygon(draw, flank_l, c_projector, c_projector_hi, c_projector_sh)
        draw_beveled_polygon(draw, flank_r, c_projector, c_projector_hi, c_projector_sh)

        # Super-conducting conduits on flanks
        draw.line([(58, 92), (58, 116)], fill=c_energy, width=3)
        draw.line([(196, 92), (196, 116)], fill=c_energy, width=3)

    return apply_clay_texture(img, roughness=7.0)

def render_laser_ring_cutter_vfx() -> Image.Image:
    """256x256 RGBA High-Frequency Laser Ring Blade VFX"""
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = 128, 128

    # Outer Energy Glow (radiating gradient rings)
    for r in range(98, 70, -2):
        alpha = int(90 * ((r - 70) / 28.0))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(40, 180, 255, alpha), width=3)

    # Main High-Intensity Laser Ring
    r_core = 76
    draw.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], outline=(60, 225, 255, 240), width=10)
    draw.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], outline=(230, 255, 255, 255), width=5)

    # Cutting Teeth / Saw Blades along the perimeter
    num_teeth = 16
    for i in range(num_teeth):
        angle = (i / float(num_teeth)) * 2.0 * math.pi
        x0 = cx + math.cos(angle) * 72
        y0 = cy + math.sin(angle) * 72
        x1 = cx + math.cos(angle + 0.12) * 88
        y1 = cy + math.sin(angle + 0.12) * 88
        x2 = cx + math.cos(angle + 0.06) * 76
        y2 = cy + math.sin(angle + 0.06) * 76
        draw.polygon([(x0, y0), (x1, y1), (x2, y2)], fill=(200, 250, 255, 230))

    # Inner Energy Radiance
    for r in [52, 38, 24]:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(80, 210, 255, 140), width=2)

    # Crescent Plasma Arc Highlight
    draw.arc([cx - 80, cy - 80, cx + 80, cy + 80], start=-30, end=110, fill=(255, 255, 255, 255), width=4)

    return img.filter(ImageFilter.GaussianBlur(radius=0.7))

def render_perk_trench_icon() -> Image.Image:
    """256x256 RGBA Perk Icon for Trench Warfare branch"""
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = 128, 128

    # Outer Clay Hexagon / Circular Shield Base
    draw_clay_circle(draw, (cx, cy), 108, (38, 42, 52, 255), (75, 82, 98, 255), (20, 22, 28, 255), bevel=5)
    draw_clay_circle(draw, (cx, cy), 94, (28, 32, 40, 255), (55, 60, 72, 255), (15, 17, 22, 255), bevel=3)

    # Laser Ring Blade in center
    draw.ellipse([cx - 62, cy - 62, cx + 62, cy + 62], outline=(45, 190, 245, 220), width=8)
    draw.ellipse([cx - 62, cy - 62, cx + 62, cy + 62], outline=(230, 255, 255, 255), width=4)

    # Sawtooth cutting teeth
    for i in range(12):
        angle = (i / 12.0) * 2.0 * math.pi
        x0 = cx + math.cos(angle) * 58
        y0 = cy + math.sin(angle) * 58
        x1 = cx + math.cos(angle + 0.15) * 74
        y1 = cy + math.sin(angle + 0.15) * 74
        draw.line([(x0, y0), (x1, y1)], fill=(255, 255, 220, 240), width=3)

    # Sliced Wall / Obstacle Silhouette in background
    draw_shaded_bevel_rect(draw, [cx - 24, cy - 24, cx + 24, cy + 24], (165, 82, 45, 255), (215, 120, 68, 255), (105, 48, 25, 255), bevel=2)
    # Clean diagonal laser slice mark through the block
    draw.line([cx - 32, cy - 32, cx + 32, cy + 32], fill=(255, 255, 255, 255), width=4)

    return apply_clay_texture(img, roughness=6.0)

def main():
    print("=== Generating Trench Tank Assets ===")
    
    # 1. Enemy Trench Tank (6 frames)
    for f in range(6):
        out = os.path.join(TANKS_DIR, f"enemy_trench_f{f}.png")
        img = render_trench_tank("enemy", 1, f)
        img.save(out, "PNG")
        print(f"Generated {out}")

    # 2. Player 1 Trench Tank Tier 1 & Tier 2 (12 frames)
    for f in range(6):
        out1 = os.path.join(TANKS_DIR, f"player_trench_t1_f{f}.png")
        render_trench_tank("player", 1, f).save(out1, "PNG")
        out2 = os.path.join(TANKS_DIR, f"player_trench_t2_f{f}.png")
        render_trench_tank("player", 2, f).save(out2, "PNG")
        print(f"Generated {out1} & {out2}")

    # 3. Player 2 Trench Tank Tier 1 & Tier 2 (12 frames)
    for f in range(6):
        out1 = os.path.join(TANKS_DIR, f"player2_trench_t1_f{f}.png")
        render_trench_tank("player2", 1, f).save(out1, "PNG")
        out2 = os.path.join(TANKS_DIR, f"player2_trench_t2_f{f}.png")
        render_trench_tank("player2", 2, f).save(out2, "PNG")
        print(f"Generated {out1} & {out2}")

    # 4. Laser Ring Cutter VFX
    vfx_out = os.path.join(EFFECTS_DIR, "laser_ring_cutter.png")
    render_laser_ring_cutter_vfx().save(vfx_out, "PNG")
    print(f"Generated {vfx_out}")

    # 5. UI Perk Icon
    icon_out = os.path.join(UI_DIR, "perk_trench.png")
    render_perk_trench_icon().save(icon_out, "PNG")
    print(f"Generated {icon_out}")

    print("All Trench Tank visual assets generated successfully!")

if __name__ == "__main__":
    main()
