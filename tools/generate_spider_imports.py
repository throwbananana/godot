import os

template = """[remap]

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

tanks = ['tank_spider', 'enemy_spider']
for t in tanks:
    for f in range(6):
        fn = f"{t}_f{f}.png"
        import_fn = os.path.join('assets', 'sprites', 'tanks', f"{fn}.import")
        content = template.format(filename=fn)
        with open(import_fn, 'w', encoding='utf-8') as fp:
            fp.write(content)

# 静态图标
fn = "tank_spider.png"
import_fn = os.path.join('assets', 'sprites', 'tanks', f"{fn}.import")
content = template.format(filename=fn)
with open(import_fn, 'w', encoding='utf-8') as fp:
    fp.write(content)

print('Generated 13 .import files for spider tank successfully.')
