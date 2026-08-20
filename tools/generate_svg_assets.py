import os

SVG_DIR = r"G:\Users\123\Documents\GitHub\godot\assets\svg"
os.makedirs(SVG_DIR, exist_ok=True)

# 1. Player Tank SVG
svg_player = '''<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <!-- Left Track -->
  <rect x="12" y="16" width="24" height="96" rx="6" fill="#2B2D42" stroke="#1A1B26" stroke-width="2"/>
  <line x1="12" y1="32" x2="36" y2="32" stroke="#4A4E69" stroke-width="3"/>
  <line x1="12" y1="48" x2="36" y2="48" stroke="#4A4E69" stroke-width="3"/>
  <line x1="12" y1="64" x2="36" y2="64" stroke="#4A4E69" stroke-width="3"/>
  <line x1="12" y1="80" x2="36" y2="80" stroke="#4A4E69" stroke-width="3"/>
  <line x1="12" y1="96" x2="36" y2="96" stroke="#4A4E69" stroke-width="3"/>

  <!-- Right Track -->
  <rect x="92" y="16" width="24" height="96" rx="6" fill="#2B2D42" stroke="#1A1B26" stroke-width="2"/>
  <line x1="92" y1="32" x2="116" y2="32" stroke="#4A4E69" stroke-width="3"/>
  <line x1="92" y1="48" x2="116" y2="48" stroke="#4A4E69" stroke-width="3"/>
  <line x1="92" y1="64" x2="116" y2="64" stroke="#4A4E69" stroke-width="3"/>
  <line x1="92" y1="80" x2="116" y2="80" stroke="#4A4E69" stroke-width="3"/>
  <line x1="92" y1="96" x2="116" y2="96" stroke="#4A4E69" stroke-width="3"/>

  <!-- Main Chassis -->
  <rect x="32" y="24" width="64" height="80" rx="8" fill="#F4A261" stroke="#E76F51" stroke-width="3"/>
  <!-- Armor plating -->
  <polygon points="36,28 92,28 84,40 44,40" fill="#E76F51"/>

  <!-- Gun Barrel -->
  <rect x="58" y="4" width="12" height="44" rx="3" fill="#2A9D8F" stroke="#264653" stroke-width="2"/>
  <rect x="55" y="2" width="18" height="8" rx="2" fill="#264653"/>

  <!-- Turret -->
  <rect x="42" y="42" width="44" height="44" rx="8" fill="#E9C46A" stroke="#E76F51" stroke-width="3"/>
  <circle cx="64" cy="64" r="12" fill="#2A9D8F" stroke="#264653" stroke-width="2"/>
</svg>'''

with open(os.path.join(SVG_DIR, "player_tank.svg"), "w", encoding="utf-8") as f:
    f.write(svg_player)

# 2. Brick Tile SVG
svg_brick = '''<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <rect width="128" height="128" fill="#2B1E17"/>
  <!-- Row 1 -->
  <rect x="2" y="2" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <rect x="66" y="2" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <!-- Row 2 -->
  <rect x="2" y="34" width="28" height="28" fill="#B03A2E" stroke="#C84B31" stroke-width="2" rx="2"/>
  <rect x="34" y="34" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <rect x="98" y="34" width="28" height="28" fill="#B03A2E" stroke="#C84B31" stroke-width="2" rx="2"/>
  <!-- Row 3 -->
  <rect x="2" y="66" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <rect x="66" y="66" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <!-- Row 4 -->
  <rect x="2" y="98" width="28" height="28" fill="#B03A2E" stroke="#C84B31" stroke-width="2" rx="2"/>
  <rect x="34" y="98" width="60" height="28" fill="#C84B31" stroke="#D9534F" stroke-width="2" rx="2"/>
  <rect x="98" y="98" width="28" height="28" fill="#B03A2E" stroke="#C84B31" stroke-width="2" rx="2"/>
</svg>'''

with open(os.path.join(SVG_DIR, "tile_brick.svg"), "w", encoding="utf-8") as f:
    f.write(svg_brick)

# 3. Steel Tile SVG
svg_steel = '''<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <rect width="128" height="128" fill="#1C2833"/>
  <rect x="4" y="4" width="58" height="58" fill="#85929E" stroke="#BDC3C7" stroke-width="3" rx="4"/>
  <rect x="66" y="4" width="58" height="58" fill="#85929E" stroke="#BDC3C7" stroke-width="3" rx="4"/>
  <rect x="4" y="66" width="58" height="58" fill="#85929E" stroke="#BDC3C7" stroke-width="3" rx="4"/>
  <rect x="66" y="66" width="58" height="58" fill="#85929E" stroke="#BDC3C7" stroke-width="3" rx="4"/>
  <!-- Rivets -->
  <circle cx="12" cy="12" r="3" fill="#EAEDED"/><circle cx="54" cy="12" r="3" fill="#EAEDED"/>
  <circle cx="12" cy="54" r="3" fill="#EAEDED"/><circle cx="54" cy="54" r="3" fill="#EAEDED"/>
  <circle cx="74" cy="12" r="3" fill="#EAEDED"/><circle cx="116" cy="12" r="3" fill="#EAEDED"/>
  <circle cx="74" cy="54" r="3" fill="#EAEDED"/><circle cx="116" cy="54" r="3" fill="#EAEDED"/>
  <circle cx="12" cy="74" r="3" fill="#EAEDED"/><circle cx="54" cy="74" r="3" fill="#EAEDED"/>
  <circle cx="12" cy="116" r="3" fill="#EAEDED"/><circle cx="54" cy="116" r="3" fill="#EAEDED"/>
  <circle cx="74" cy="74" r="3" fill="#EAEDED"/><circle cx="116" cy="74" r="3" fill="#EAEDED"/>
  <circle cx="74" cy="116" r="3" fill="#EAEDED"/><circle cx="116" cy="116" r="3" fill="#EAEDED"/>
</svg>'''

with open(os.path.join(SVG_DIR, "tile_steel.svg"), "w", encoding="utf-8") as f:
    f.write(svg_steel)

# 4. Eagle Base SVG
svg_eagle = '''<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <rect width="128" height="128" fill="#17202A" rx="8"/>
  <polygon points="64,12 84,40 114,32 94,64 116,92 76,84 64,116 52,84 12,92 34,64 14,32 44,40" fill="#F1C40F" stroke="#B7950B" stroke-width="4"/>
  <circle cx="64" cy="60" r="18" fill="#E67E22" stroke="#B7950B" stroke-width="3"/>
  <polygon points="64,48 68,58 78,58 70,64 73,74 64,68 55,74 58,64 50,58 60,58" fill="#FFFFFF"/>
</svg>'''

with open(os.path.join(SVG_DIR, "base_eagle.svg"), "w", encoding="utf-8") as f:
    f.write(svg_eagle)

print("SVG vector assets created successfully.")
