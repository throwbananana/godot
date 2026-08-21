import os
from PIL import Image
import numpy as np

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TANKS_DIR = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")

print("================================================================================")
print("             TANK MODEL & SPRITE QA: BOUNDING BOX & CLIPPING CHECK              ")
print("================================================================================")

clipping_issues = []
all_tanks = sorted([f for f in os.listdir(TANKS_DIR) if f.endswith('.png')])

for fname in all_tanks:
    fpath = os.path.join(TANKS_DIR, fname)
    im = Image.open(fpath).convert('RGBA')
    arr = np.array(im)
    alpha = arr[:, :, 3]

    # Find non-transparent pixels (alpha > 15)
    opaque_y, opaque_x = np.where(alpha > 15)
    if len(opaque_x) == 0:
        print(f"[EMPTY] {fname} is completely transparent!")
        continue

    min_x, max_x = np.min(opaque_x), np.max(opaque_x)
    min_y, max_y = np.min(opaque_y), np.max(opaque_y)
    w, h = max_x - min_x + 1, max_y - min_y + 1

    # Check edge margin (is it touching the 0 or 255 border?)
    touch_left = (min_x <= 1)
    touch_right = (max_x >= 254)
    touch_top = (min_y <= 1)
    touch_bottom = (max_y >= 254)

    if touch_left or touch_right or touch_top or touch_bottom:
        clipping_issues.append((fname, min_x, max_x, min_y, max_y, touch_left, touch_right, touch_top, touch_bottom))

print(f"Total Tank Frames Analyzed: {len(all_tanks)}")
if len(clipping_issues) == 0:
    print(">>> SUCCESS: 0 Clipping or Border Overflow issues detected across all tank assets!")
    print(">>> All 3D models fit comfortably inside the 256x256 orthographic frustum.")
else:
    print(f">>> WARNING: Found {len(clipping_issues)} frames with potential edge clipping:")
    for c in clipping_issues:
        print(f"    - {c[0]}: bounds X[{c[1]}:{c[2]}], Y[{c[3]}:{c[4]}] (Touch: L={c[5]}, R={c[6]}, T={c[7]}, B={c[8]})")

print("\n================================================================================")
print("                CODE PATH RESOLUTION VERIFICATION                              ")
print("================================================================================")

# Check all paths referenced by player, enemy, carriage
referenced_prefixes = [
    # Speed
    "player_speed_t1", "player_speed_t2", "player2_speed_t1", "player2_speed_t2",
    # Heavy
    "player_heavy_t1", "player_heavy_t2", "player2_heavy_t1", "player2_heavy_t2",
    # Train
    "player_train_loco_t1", "player_train_loco_t2", "player2_train_loco_t1", "player2_train_loco_t2",
    # Wagons
    "train_wagon_turret", "train_wagon_armor", "train_wagon_rocket",
    # Enemy
    "enemy_basic", "enemy_fast", "enemy_power", "enemy_armor", "enemy_missile", "enemy_laser", "enemy_boss", "tank_desert",
    "enemy_train_loco", "enemy_train_wagon_gunner", "enemy_train_wagon_armor",
    # Classic
    "player_tier0", "player_tier1", "player_tier2", "player_tier3",
    "player2_tier0", "player2_tier1", "player2_tier2", "player2_tier3",
]

missing = []
for pfx in referenced_prefixes:
    for f in range(6):
        fn = f"{pfx}_f{f}.png"
        if not os.path.exists(os.path.join(TANKS_DIR, fn)):
            missing.append(fn)

if len(missing) == 0:
    print(">>> PERFECT: All 6-frame sets for every player branch, tier, enemy, and wagon exist on disk!")
else:
    print(f">>> MISSING {len(missing)} ASSETS:")
    for m in missing:
        print(f"    - {m}")
