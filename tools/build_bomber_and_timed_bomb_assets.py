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
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# 1. TIMED BOMB ENTITY (prop_timed_bomb.png)
def build_timed_bomb():
    objs = []
    mat_bomb = create_clay_mat("m_tb_body", (0.15, 0.16, 0.20, 1.0), roughness=0.60)
    mat_hz_y = create_clay_mat("m_tb_hzy", (0.98, 0.82, 0.12, 1.0), roughness=0.40)
    mat_hz_k = create_clay_mat("m_tb_hzk", (0.10, 0.10, 0.12, 1.0), roughness=0.40)
    mat_display = create_clay_mat("m_tb_disp", (0.05, 0.05, 0.08, 1.0), roughness=0.30)
    mat_digits = create_clay_mat("m_tb_digit", (1.0, 0.15, 0.15, 1.0), emission=(1.0, 0.15, 0.15, 1.0), emission_str=4.5)
    mat_fuse = create_clay_mat("m_tb_fuse", (0.85, 0.65, 0.25, 1.0), roughness=0.50)
    mat_spark = create_clay_mat("m_tb_spark", (1.0, 0.65, 0.10, 1.0), emission=(1.0, 0.65, 0.10, 1.0), emission_str=5.0)

    # Spherical Clay Bomb
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.88, location=(0, -0.05, 0))
    body = bpy.context.active_object
    body.data.materials.append(mat_bomb)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    # Equatorial Hazard Ring
    for i in range(8):
        ang = i * (math.pi / 4.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.88, math.sin(ang) * 0.88 - 0.05, 0))
        h = bpy.context.active_object
        h.scale = (0.22, 0.10, 0.38)
        h.rotation_euler = (0, 0, ang)
        h.data.materials.append(mat_hz_y if i % 2 == 0 else mat_hz_k)
        apply_uniform_clay_bevel(h, width=0.02, segments=2)
        objs.append(h)

    # Front Digital Timer Display
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.80, 0.15))
    disp = bpy.context.active_object
    disp.scale = (0.58, 0.14, 0.32)
    disp.data.materials.append(mat_display)
    apply_uniform_clay_bevel(disp, width=0.03, segments=2)
    objs.append(disp)

    # Glowing Red Digital Segment "03"
    for dx in [-0.15, 0.15]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(dx, 0.88, 0.15))
        dig = bpy.context.active_object
        dig.scale = (0.12, 0.05, 0.20)
        dig.data.materials.append(mat_digits)
        objs.append(dig)

    # Top Brass Collar & Sizzling Fuse Spark
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.22, vertices=16, location=(0, 0.76, 0))
    col = bpy.context.active_object
    col.data.materials.append(mat_fuse)
    apply_uniform_clay_bevel(col, width=0.02, segments=2)
    objs.append(col)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0.15, 1.05, 0.08))
    spk = bpy.context.active_object
    spk.data.materials.append(mat_spark)
    bpy.ops.object.shade_smooth()
    objs.append(spk)

    return objs

# 2. TIMED BOMB POWERUP PROP (powerup_timed_bomb.png)
def build_timed_bomb_powerup():
    objs = []
    mat_crate = create_clay_mat("m_tb_crate", (0.55, 0.35, 0.20, 1.0), roughness=0.75)
    mat_metal = create_clay_mat("m_tb_band", (0.28, 0.30, 0.35, 1.0), roughness=0.40)
    mat_bomb = create_clay_mat("m_tb_mini_b", (0.18, 0.18, 0.22, 1.0), roughness=0.60)
    mat_spark = create_clay_mat("m_tb_mini_s", (1.0, 0.55, 0.15, 1.0), emission=(1.0, 0.55, 0.15, 1.0), emission_str=4.0)

    # Wooden Clay Ammo Crate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, -0.05))
    crate = bpy.context.active_object
    crate.scale = (1.30, 1.05, 0.55)
    crate.data.materials.append(mat_crate)
    apply_uniform_clay_bevel(crate, width=0.06, segments=2)
    objs.append(crate)

    # Iron Corner Straps
    for sx in [-0.58, 0.58]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, -0.15, -0.05))
        band = bpy.context.active_object
        band.scale = (0.18, 1.08, 0.58)
        band.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(band, width=0.02, segments=1)
        objs.append(band)

    # 2 Mini Bombs Resting in Crate
    for bx in [-0.30, 0.30]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(bx, 0.05, 0.30))
        b = bpy.context.active_object
        b.data.materials.append(mat_bomb)
        bpy.ops.object.shade_smooth()
        objs.append(b)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(bx + 0.10, 0.38, 0.42))
        s = bpy.context.active_object
        s.data.materials.append(mat_spark)
        bpy.ops.object.shade_smooth()
        objs.append(s)

    return objs

# 3. BOMBERMAN FLAME CROSS BEAM (flame_cross_beam.png)
def build_flame_cross_beam():
    objs = []
    mat_fire_core = create_clay_mat("m_flm_core", (1.0, 0.95, 0.40, 1.0), emission=(1.0, 0.95, 0.40, 1.0), emission_str=4.8)
    mat_fire_mid = create_clay_mat("m_flm_mid", (1.0, 0.45, 0.10, 1.0), emission=(1.0, 0.45, 0.10, 1.0), emission_str=3.8)
    mat_fire_outer = create_clay_mat("m_flm_out", (0.90, 0.18, 0.15, 1.0), emission=(0.90, 0.18, 0.15, 1.0), emission_str=2.5)

    # Elongated Fiery Clay Shock Plume
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=1.60, vertices=16, location=(0, 0, 0))
    plume = bpy.context.active_object
    plume.data.materials.append(mat_fire_mid)
    apply_uniform_clay_bevel(plume, width=0.08, segments=2)
    objs.append(plume)

    # Core Luminous Plasma Beam
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=1.70, vertices=16, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_fire_core)
    apply_uniform_clay_bevel(core, width=0.04, segments=2)
    objs.append(core)

    # Fiery Bulbous Puffs on the side
    for (py, ps) in [(-0.55, 0.35), (0.0, 0.42), (0.55, 0.38)]:
        for px in [-0.42, 0.42]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=ps, location=(px, py, 0))
            puff = bpy.context.active_object
            puff.data.materials.append(mat_fire_outer)
            bpy.ops.object.shade_smooth()
            objs.append(puff)

    return objs

# 4. ENEMY BOMBER TANK (enemy_bomber_f0..f5.png)
def build_bomber_tank(frame=0):
    objs = []
    mat_camo = create_clay_mat("m_btk_body", (0.85, 0.45, 0.18, 1.0), roughness=0.60) # Demolition Orange
    mat_hazard = create_clay_mat("m_btk_hz", (0.16, 0.16, 0.18, 1.0), roughness=0.50)
    mat_tread = create_clay_mat("m_btk_trd", (0.20, 0.20, 0.24, 1.0), roughness=0.75)
    mat_chute = create_clay_mat("m_btk_cht", (0.35, 0.36, 0.40, 1.0), roughness=0.45)
    mat_bomb = create_clay_mat("m_btk_bmb", (0.14, 0.14, 0.16, 1.0), roughness=0.60)
    mat_spark = create_clay_mat("m_btk_spk", (1.0, 0.60, 0.10, 1.0), emission=(1.0, 0.60, 0.10, 1.0), emission_str=4.0)

    # 1. Dual Track Units
    tread_phase = (frame / 6.0) * math.pi
    for tx in [-0.85, 0.85]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.15))
        tread = bpy.context.active_object
        tread.scale = (0.44, 1.75, 0.48)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.05, segments=2)
        objs.append(tread)

        for wy in [-0.55, 0.0, 0.55]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.46, vertices=16, location=(tx, wy, -0.15))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), tread_phase)
            wheel.data.materials.append(mat_tread)
            objs.append(wheel)

    # 2. Main Tank Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.08))
    hull = bpy.context.active_object
    hull.scale = (1.25, 1.45, 0.48)
    hull.data.materials.append(mat_camo)
    apply_uniform_clay_bevel(hull, width=0.08, segments=2)
    objs.append(hull)

    # Front Demolition Dozer Blade
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.82, -0.05))
    dozer = bpy.context.active_object
    dozer.scale = (1.45, 0.22, 0.45)
    dozer.data.materials.append(mat_hazard)
    apply_uniform_clay_bevel(dozer, width=0.04, segments=2)
    objs.append(dozer)

    # 3. Rear Bomb Dispenser Chute Rack
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.55, 0.42))
    rack = bpy.context.active_object
    rack.scale = (0.85, 0.75, 0.38)
    rack.rotation_euler = (math.radians(22), 0, 0)
    rack.data.materials.append(mat_chute)
    apply_uniform_clay_bevel(rack, width=0.04, segments=2)
    objs.append(rack)

    # Loaded Bombs in Chute
    for by in [-0.45, -0.72]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.26, location=(0, by, 0.55))
        bm = bpy.context.active_object
        bm.data.materials.append(mat_bomb)
        bpy.ops.object.shade_smooth()
        objs.append(bm)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0.10, by + 0.15, 0.70))
        sp = bpy.context.active_object
        sp.data.materials.append(mat_spark)
        bpy.ops.object.shade_smooth()
        objs.append(sp)

    return objs

def main():
    print("==================================================")
    print(" Executing Bomber & Timed Bomb Asset Pipeline.. ")
    print("==================================================")

    # 1. Render Timed Bomb Entity
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    objs = build_timed_bomb()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "prop_timed_bomb.png"))
    print("[OK] Timed Bomb Entity Rendered.")

    # 2. Render Timed Bomb Powerup Crate
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    objs = build_timed_bomb_powerup()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "powerup_timed_bomb.png"))
    print("[OK] Timed Bomb Powerup Rendered.")

    # 3. Render Flame Cross Beam
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.70)
    objs = build_flame_cross_beam()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "flame_cross_beam.png"))
    print("[OK] Flame Cross Beam Rendered.")

    # 4. Render 6-Frame Enemy Bomber Tank
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_bomber_tank(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_bomber_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Enemy Bomber Tank Frame {f} Rendered.")

if __name__ == '__main__':
    main()
