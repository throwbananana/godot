import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

template_tanks = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/sprites/tanks/{filename}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

template_effects = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/sprites/effects/{filename}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

tank_files = []
for prefix in ["enemy_titan_boss", "enemy_scorpion_boss", "enemy_mammoth_boss"]:
    tank_files.append(f"{prefix}.png")
    for f in range(6):
        tank_files.append(f"{prefix}_f{f}.png")

for fn in tank_files:
    import_path = os.path.join(SPRITES_TANKS, f"{fn}.import")
    with open(import_path, "w", encoding="utf-8") as f:
        f.write(template_tanks.format(filename=fn))
    print(f"Generated {import_path}")

effect_files = []
for prefix in ["boss_plasma_nova", "boss_frost_nova"]:
    for f in range(6):
        effect_files.append(f"{prefix}_{f}.png")

for fn in effect_files:
    import_path = os.path.join(SPRITES_EFFECTS, f"{fn}.import")
    with open(import_path, "w", encoding="utf-8") as f:
        f.write(template_effects.format(filename=fn))
    print(f"Generated {import_path}")

print(">>> ALL IMPORT FILES GENERATED! <<<")
