import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")

template = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/sprites/buildings/{filename}"

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

doors = [
    "door_normal_locked.png",
    "door_normal_open.png",
    "door_boss_locked.png",
    "door_boss_open.png",
    "door_shop_locked.png",
    "door_shop_open.png",
    "door_treasure_locked.png",
    "door_treasure_open.png",
    "door_challenge_locked.png",
    "door_challenge_open.png",
    "door_secret_cracked.png",
    "door_secret_open.png",
    "door_event_locked.png",
    "door_event_open.png",
]

for fn in doors:
    import_path = os.path.join(SPRITES_BUILDINGS, f"{fn}.import")
    with open(import_path, "w", encoding="utf-8") as f:
        f.write(template.format(filename=fn))
    print(f"Generated {fn}.import with mipmaps/generate=true")
