import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")
os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_MAP, exist_ok=True)

# ==================== 1. TREASURE CHEST (CLOSED) ====================
def build_treasure_chest():
    objs = []
    # Material palette: Royal Wood Brown, Imperial Gold Trim, Glowing Ruby Lock, Steel Hinges
    mat_wood = create_clay_mat("m_chest_wood", (0.42, 0.26, 0.16, 1.0), roughness=0.75)
    mat_gold = create_clay_mat("m_chest_gold", (0.98, 0.80, 0.20, 1.0), roughness=0.35)
    mat_metal = create_clay_mat("m_chest_metal", (0.28, 0.30, 0.36, 1.0), roughness=0.55)
    mat_ruby = create_clay_mat("m_chest_ruby", (0.95, 0.18, 0.28, 1.0), emission=(0.95, 0.18, 0.28, 1.0), emission_str=3.2)
    mat_glow = create_clay_mat("m_chest_glow", (0.30, 0.85, 1.0, 1.0), emission=(0.30, 0.85, 1.0, 1.0), emission_str=2.0)

    # 1. Main Chest Base Box
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.15))
    base = bpy.context.active_object
    base.scale = (1.55, 1.15, 0.70)
    base.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(base, width=0.08, segments=3)
    objs.append(base)

    # 2. Domed / Arched Chest Lid
    bpy.ops.mesh.primitive_cylinder_add(radius=0.58, depth=1.56, vertices=24, location=(0, 0, 0.22))
    lid = bpy.context.active_object
    lid.rotation_euler = (0, math.radians(90), 0)
    lid.scale = (1.0, 1.0, 0.78)
    lid.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(lid, width=0.06, segments=2)
    objs.append(lid)

    # 3. Gold Corner Reinforcement Plates & Straps
    for x_pos in [-0.55, 0.0, 0.55]:
        # Vertical Gold Band
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.05))
        band = bpy.context.active_object
        band.scale = (0.16, 1.18, 1.05)
        band.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(band, width=0.03, segments=2)
        objs.append(band)

    for (cx, cy) in [(-0.76, -0.56), (0.76, -0.56), (-0.76, 0.56), (0.76, 0.56)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, -0.15))
        corner = bpy.context.active_object
        corner.scale = (0.18, 0.18, 0.72)
        corner.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(corner, width=0.03, segments=2)
        objs.append(corner)

    # 4. Heavy Front Gold Lock Plate & Keyhole
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.58, 0.12))
    lock_plate = bpy.context.active_object
    lock_plate.scale = (0.38, 0.12, 0.38)
    lock_plate.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(lock_plate, width=0.04, segments=2)
    objs.append(lock_plate)

    # Glowing Ruby Gem in center of lock
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0, -0.64, 0.12))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_ruby)
    bpy.ops.object.shade_smooth()
    objs.append(gem)

    # Keyhole slot
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.10, vertices=12, location=(0, -0.63, 0.04))
    kh = bpy.context.active_object
    kh.rotation_euler = (math.radians(90), 0, 0)
    kh.data.materials.append(mat_metal)
    objs.append(kh)

    # 5. Side Lifting Handles
    for hx in [-0.80, 0.80]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.04, location=(hx, 0, -0.10))
        handle = bpy.context.active_object
        handle.rotation_euler = (0, math.radians(90), 0)
        handle.data.materials.append(mat_metal)
        bpy.ops.object.shade_smooth()
        objs.append(handle)

    return objs

# ==================== 2. GOLDEN MYSTERY KEY ====================
def build_treasure_key():
    objs = []
    # Material palette: Polished Gold, Royal Ruby Crown, Gleaming Specular
    mat_gold = create_clay_mat("m_key_gold", (0.98, 0.82, 0.18, 1.0), roughness=0.30)
    mat_ruby = create_clay_mat("m_key_ruby", (0.95, 0.15, 0.25, 1.0), emission=(0.95, 0.15, 0.25, 1.0), emission_str=3.5)
    mat_glow = create_clay_mat("m_key_glow", (1.0, 0.95, 0.50, 1.0), emission=(1.0, 0.95, 0.50, 1.0), emission_str=2.5)

    # 1. Main Key Shaft
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=1.35, vertices=16, location=(0, -0.15, 0))
    shaft = bpy.context.active_object
    shaft.rotation_euler = (math.radians(90), 0, 0)
    shaft.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(shaft, width=0.02, segments=2)
    objs.append(shaft)

    # 2. Ornate Bow / Ring Handle at Top
    bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.08, location=(0, 0.65, 0))
    bow = bpy.context.active_object
    bow.data.materials.append(mat_gold)
    bpy.ops.object.shade_smooth()
    objs.append(bow)

    # Inner Heart / Gem Mount
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0, 0.65, 0))
    gem = bpy.context.active_object
    gem.scale = (1.0, 1.0, 0.60)
    gem.data.materials.append(mat_ruby)
    bpy.ops.object.shade_smooth()
    objs.append(gem)

    # Crown Finial on top of bow
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.16, vertices=6, location=(0, 1.08, 0))
    crown = bpy.context.active_object
    crown.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(crown, width=0.03, segments=2)
    objs.append(crown)

    # 3. Key Bit / Teeth at Bottom
    for (ty, tx_len) in [(-0.62, 0.28), (-0.46, 0.20), (-0.30, 0.26)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx_len * 0.5 + 0.08, ty, 0))
        tooth = bpy.context.active_object
        tooth.scale = (tx_len, 0.10, 0.12)
        tooth.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(tooth, width=0.02, segments=2)
        objs.append(tooth)

    # Sparkling Energy Glint
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(0.28, -0.62, 0.08))
    glint = bpy.context.active_object
    glint.data.materials.append(mat_glow)
    bpy.ops.object.shade_smooth()
    objs.append(glint)

    return objs

# ==================== 3. SPIRE MAP CHALLENGE NODE ICON ====================
def build_challenge_node_icon():
    objs = []
    # Material palette: Royal Purple Hex Base, Gold Border, Crossed Silver Swords, Golden Chest
    mat_hex = create_clay_mat("m_chn_hex", (0.32, 0.18, 0.42, 1.0), roughness=0.60)
    mat_gold = create_clay_mat("m_chn_gold", (0.98, 0.80, 0.20, 1.0), roughness=0.35)
    mat_sword = create_clay_mat("m_chn_blade", (0.85, 0.88, 0.94, 1.0), roughness=0.30)
    mat_ruby = create_clay_mat("m_chn_ruby", (0.95, 0.20, 0.30, 1.0), emission=(0.95, 0.20, 0.30, 1.0), emission_str=3.0)

    # Hexagonal Node Base Platform
    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.22, vertices=6, location=(0, 0, 0))
    hex_base = bpy.context.active_object
    hex_base.data.materials.append(mat_hex)
    apply_uniform_clay_bevel(hex_base, width=0.08, segments=3)
    objs.append(hex_base)

    # Gold Outer Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.22, depth=0.12, vertices=6, location=(0, 0, -0.06))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(rim, width=0.04, segments=2)
    objs.append(rim)

    # Crossed Combat Blades behind chest
    for ang in [math.radians(45), math.radians(-45)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        blade = bpy.context.active_object
        blade.scale = (0.16, 1.45, 0.06)
        blade.rotation_euler = (0, 0, ang)
        blade.data.materials.append(mat_sword)
        apply_uniform_clay_bevel(blade, width=0.02, segments=2)
        objs.append(blade)

    # Center Mini Golden Treasure Chest
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.26))
    c_box = bpy.context.active_object
    c_box.scale = (0.78, 0.58, 0.40)
    c_box.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(c_box, width=0.05, segments=2)
    objs.append(c_box)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.44))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_ruby)
    bpy.ops.object.shade_smooth()
    objs.append(gem)

    return objs

def main():
    print("==================================================")
    print(" Rendering Treasure Chest, Key & Challenge Node.. ")
    print("==================================================")

    # 1. Render Treasure Chest
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    chest_objs = build_treasure_chest()
    chest_out = os.path.join(SPRITES_POWERUPS, "treasure_chest.png")
    render_and_clean(chest_objs, chest_out)
    print(f"[OK] Treasure Chest rendered -> {chest_out}")

    # 2. Render Golden Mystery Key
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    key_objs = build_treasure_key()
    key_out = os.path.join(SPRITES_POWERUPS, "treasure_key.png")
    render_and_clean(key_objs, key_out)
    print(f"[OK] Golden Key rendered -> {key_out}")

    # 3. Render Spire Challenge Node Icon
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    node_objs = build_challenge_node_icon()
    node_out = os.path.join(SPRITES_MAP, "node_challenge.png")
    render_and_clean(node_objs, node_out)
    print(f"[OK] Challenge Node rendered -> {node_out}")

if __name__ == '__main__':
    main()
