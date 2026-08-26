import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

template = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/sprites/ui/{filename}"

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

files = [
    "ui_minimap_frame.png",
    "ui_card_bg_normal.png",
    "ui_card_bg_hover.png",
    "ui_card_bg_branch.png",
    "perk_amphibious.png",
    "perk_piercing.png",
    "perk_frost.png",
    "perk_ferry.png",
    "ui_badge_key.png",
    "ui_badge_streak.png",
]

for fn in files:
    import_path = os.path.join(SPRITES_UI, f"{fn}.import")
    with open(import_path, "w", encoding="utf-8") as f:
        f.write(template.format(filename=fn))
    print(f"Generated {fn}.import with mipmaps/generate=true")
