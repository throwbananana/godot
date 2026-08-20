import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# Generate Power-Up SVGs & Blender / PIL rendered icons
# 1. Star (Upgrade)
svg_star = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <polygon points="32,8 38,24 55,24 41,35 46,51 32,41 18,51 23,35 9,24 26,24" fill="#F1C40F" stroke="#F39C12" stroke-width="2"/>
</svg>'''

# 2. Bomb (Grenade)
svg_bomb = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <circle cx="32" cy="38" r="18" fill="#E74C3C" stroke="#C0392B" stroke-width="2"/>
  <rect x="28" y="14" width="8" height="8" rx="2" fill="#95A5A6"/>
  <path d="M 32 14 Q 38 6 46 10" stroke="#E67E22" stroke-width="3" fill="none"/>
  <circle cx="48" cy="10" r="3" fill="#F1C40F"/>
</svg>'''

# 3. Clock (Freeze)
svg_clock = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <circle cx="32" cy="32" r="22" fill="#3498DB" stroke="#2980B9" stroke-width="3"/>
  <circle cx="32" cy="32" r="17" fill="#EBF5FB"/>
  <line x1="32" y1="32" x2="32" y2="20" stroke="#2C3E50" stroke-width="3" stroke-linecap="round"/>
  <line x1="32" y1="32" x2="42" y2="32" stroke="#E74C3C" stroke-width="2" stroke-linecap="round"/>
  <circle cx="32" cy="32" r="3" fill="#2C3E50"/>
</svg>'''

# 4. Helmet (Shield)
svg_helmet = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <path d="M 32 10 Q 52 14 52 32 Q 52 50 32 58 Q 12 50 12 32 Q 12 14 32 10 Z" fill="#2ECC71" stroke="#27AE60" stroke-width="3"/>
  <path d="M 32 16 Q 46 20 46 32 Q 46 44 32 50 Q 18 44 18 32 Q 18 20 32 16 Z" fill="#A9DFBF"/>
</svg>'''

# 5. Shovel (Fortify Base)
svg_shovel = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <line x1="18" y1="18" x2="40" y2="40" stroke="#BDC3C7" stroke-width="4" stroke-linecap="round"/>
  <path d="M 38 38 L 52 44 L 44 52 Z" fill="#7F8C8D" stroke="#BDC3C7" stroke-width="2"/>
  <rect x="14" y="14" width="8" height="8" rx="2" fill="#D35400"/>
</svg>'''

# 6. Tank Life
svg_tank_life = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <rect width="64" height="64" rx="12" fill="#1C2833"/>
  <!-- Small tank icon -->
  <rect x="14" y="18" width="8" height="28" rx="2" fill="#34495E"/>
  <rect x="42" y="18" width="8" height="28" rx="2" fill="#34495E"/>
  <rect x="20" y="22" width="24" height="20" rx="3" fill="#F39C12"/>
  <rect x="29" y="12" width="6" height="14" fill="#27AE60"/>
  <circle cx="32" cy="32" r="5" fill="#E67E22"/>
</svg>'''

# 7. Spawn Star Indicator
svg_spawn_star = '''<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <polygon points="32,4 39,23 58,16 46,32 58,48 39,41 32,60 25,41 6,48 18,32 6,16 25,23" fill="#00FFFF" stroke="#FFFFFF" stroke-width="2"/>
  <circle cx="32" cy="32" r="8" fill="#FFFFFF"/>
</svg>'''

powerups = {
    "star.svg": svg_star,
    "bomb.svg": svg_bomb,
    "clock.svg": svg_clock,
    "helmet.svg": svg_helmet,
    "shovel.svg": svg_shovel,
    "life.svg": svg_tank_life,
    "spawn_star.svg": svg_spawn_star
}

for name, content in powerups.items():
    folder = SPRITES_EFFECTS if name == "spawn_star.svg" else SPRITES_POWERUPS
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        f.write(content)

print("Power-up SVGs written successfully.")
