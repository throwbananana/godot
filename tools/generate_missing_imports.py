import glob
import os

all_pngs = glob.glob('assets/sprites/**/*.png', recursive=True)
missing_imports = [p for p in all_pngs if not os.path.exists(p + '.import')]
print(f'PNGs missing .import: {len(missing_imports)}')

template = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{rel_path}"

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
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

for p in missing_imports:
    rel = p.replace('\\', '/')
    with open(p + '.import', 'w', encoding='utf-8') as f:
        f.write(template.format(rel_path=rel))
    print(f"  Created: {p}.import")

print("Created all missing .import files with mipmaps/generate=true")
