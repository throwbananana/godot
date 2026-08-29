import os

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="res://.godot/imported/{filename}-{md5}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://{rel_path}"
dest_files=["res://.godot/imported/{filename}-{md5}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
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
detect_3d/decompress_to_gpu=false
svg/scale=1.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
"""

def generate_imports_for_dir(target_dir, prefix_list):
    count = 0
    for root, dirs, files in os.walk(target_dir):
        for f in files:
            if not f.endswith(".png"):
                continue
            matches = any(f.startswith(p) for p in prefix_list)
            if not matches:
                continue
            
            full_path = os.path.join(root, f)
            import_path = full_path + ".import"
            
            rel_path = os.path.relpath(full_path, "G:/Users/123/Documents/GitHub/godot").replace("\\", "/")
            import hashlib
            h = hashlib.md5(f.encode('utf-8')).hexdigest()[:12]
            uid = f"uid://ne_{h}"
            
            content = IMPORT_TEMPLATE.format(
                uid=uid,
                filename=f,
                md5=h,
                rel_path=rel_path
            )
            with open(import_path, "w", encoding="utf-8") as imp_f:
                imp_f.write(content)
            count += 1
            print(f"Generated .import for {f}")
    print(f"Total .import files generated: {count}")

if __name__ == "__main__":
    tanks_dir = "G:/Users/123/Documents/GitHub/godot/assets/sprites/tanks"
    vfx_dir = "G:/Users/123/Documents/GitHub/godot/assets/sprites/effects"
    
    tank_prefixes = ["enemy_tesla", "enemy_toxic", "enemy_drone_carrier", "enemy_drone_mini"]
    vfx_prefixes = ["tesla_arc_spark", "toxic_splash"]
    
    generate_imports_for_dir(tanks_dir, tank_prefixes)
    generate_imports_for_dir(vfx_dir, vfx_prefixes)
