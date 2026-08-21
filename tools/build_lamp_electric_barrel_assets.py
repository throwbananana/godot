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
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)
os.makedirs(SPRITES_TILES, exist_ok=True)

# ==============================================================================
# 1. STREET LAMP / LANTERN POST (路灯模型)
# ==============================================================================
def build_street_lamp(lit: bool = True):
    objs = []

    mat_iron = create_clay_mat("m_lamp_iron", (0.16, 0.17, 0.22, 1.0), roughness=0.65)
    mat_brass = create_clay_mat("m_lamp_brass", (0.85, 0.68, 0.25, 1.0), roughness=0.45)
    
    if lit:
        mat_glass = create_clay_mat("m_lamp_glass", (1.0, 0.92, 0.55, 1.0), emission=(1.0, 0.88, 0.35, 1.0), emission_str=4.5)
        mat_core = create_clay_mat("m_lamp_core", (1.0, 1.0, 0.85, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=6.0)
    else:
        mat_glass = create_clay_mat("m_lamp_glass_off", (0.35, 0.38, 0.42, 0.8), roughness=0.25)
        mat_core = create_clay_mat("m_lamp_core_off", (0.50, 0.50, 0.50, 1.0), roughness=0.50)

    # 1. Heavy Stepped Pedestal Base (Hexagonal)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.52, depth=0.18, vertices=8, location=(0, 0, -0.06))
    base1 = bpy.context.active_object
    base1.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(base1, width=0.03, segments=2)
    objs.append(base1)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.14, vertices=8, location=(0, 0, 0.08))
    base2 = bpy.context.active_object
    base2.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(base2, width=0.025, segments=2)
    objs.append(base2)

    # 2. Main Vertical Post Column & Fluted Rings
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=1.10, vertices=16, location=(0, 0, 0.65))
    post = bpy.context.active_object
    post.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(post, width=0.015, segments=2)
    objs.append(post)

    for ring_z in [0.25, 0.70, 1.15]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.16, minor_radius=0.04, location=(0, 0, ring_z))
        ring = bpy.context.active_object
        ring.data.materials.append(mat_brass)
        objs.append(ring)

    # 3. Ornate Lamp Bracket Arm / Crossbar
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.75, vertices=12, location=(0, 0, 1.05))
    crossbar = bpy.context.active_object
    crossbar.rotation_euler = (0, math.radians(90), 0)
    crossbar.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(crossbar, width=0.01, segments=2)
    objs.append(crossbar)

    for ex in [-0.36, 0.36]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex, 0, 1.05))
        fin = bpy.context.active_object
        fin.data.materials.append(mat_brass)
        objs.append(fin)

    # 4. Lantern Housing / Glass Chamber
    bpy.ops.mesh.primitive_cylinder_add(radius=0.34, depth=0.55, vertices=6, location=(0, 0, 1.42))
    glass = bpy.context.active_object
    glass.data.materials.append(mat_glass)
    apply_uniform_clay_bevel(glass, width=0.03, segments=2)
    objs.append(glass)

    # Internal Bright Glow Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0, 1.42))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    objs.append(core)

    # 5. Lantern Roof / Cap & Peak Finial
    bpy.ops.mesh.primitive_cone_add(radius1=0.42, radius2=0.08, depth=0.26, vertices=6, location=(0, 0, 1.76))
    roof = bpy.context.active_object
    roof.data.materials.append(mat_iron)
    apply_uniform_clay_bevel(roof, width=0.02, segments=2)
    objs.append(roof)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0, 0, 1.94))
    top_spire = bpy.context.active_object
    top_spire.data.materials.append(mat_brass)
    objs.append(top_spire)

    return objs


# ==============================================================================
# 2. ELECTRIC WALL / TESLA BARRIER (电墙模型 - 4 帧放电动画)
# ==============================================================================
def build_electric_wall(frame_idx: int = 0):
    objs = []
    tw = TILE_FULL_BLEED
    th = TILE_FULL_BLEED

    mat_base = create_clay_mat("m_elec_base", (0.22, 0.24, 0.30, 1.0), roughness=0.60)
    mat_pillar = create_clay_mat("m_elec_pyl", (0.35, 0.38, 0.45, 1.0), roughness=0.45)
    mat_insulator = create_clay_mat("m_elec_ins", (0.15, 0.55, 0.85, 1.0), roughness=0.30)
    mat_copper = create_clay_mat("m_elec_cop", (0.88, 0.55, 0.22, 1.0), roughness=0.40)
    
    # Pulsating electric energy
    arc_colors = [
        (0.25, 0.85, 1.0, 1.0),
        (0.40, 0.95, 1.0, 1.0),
        (0.15, 0.75, 1.0, 1.0),
        (0.70, 0.98, 1.0, 1.0)
    ]
    mat_plasma = create_clay_mat("m_elec_plasma", arc_colors[frame_idx % 4], emission=arc_colors[frame_idx % 4], emission_str=5.5)

    # 1. Sturdy Foundation Bed
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    base = bpy.context.active_object
    base.scale = (tw, th, 0.16)
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.04, segments=2)
    objs.append(base)

    # 2. Left & Right High-Voltage Insulator Pylons
    for px in [-tw * 0.38, tw * 0.38]:
        # Pylon Column
        bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.85, vertices=12, location=(px, 0, 0.38))
        pyl = bpy.context.active_object
        pyl.data.materials.append(mat_pillar)
        apply_uniform_clay_bevel(pyl, width=0.03, segments=2)
        objs.append(pyl)

        # Insulator ceramic ribbed rings
        for iz in [0.15, 0.35, 0.55]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.08, vertices=12, location=(px, 0, iz))
            ins = bpy.context.active_object
            ins.data.materials.append(mat_insulator)
            apply_uniform_clay_bevel(ins, width=0.02, segments=2)
            objs.append(ins)

        # Top Tesla Emitter Sphere
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(px, 0, 0.86))
        sph = bpy.context.active_object
        sph.data.materials.append(mat_copper)
        objs.append(sph)

    # 3. Horizontal Conductor Coils / Bars
    for bz in [0.22, 0.52]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=tw * 0.72, vertices=12, location=(0, 0, bz))
        bar = bpy.context.active_object
        bar.rotation_euler = (0, math.radians(90), 0)
        bar.data.materials.append(mat_copper)
        apply_uniform_clay_bevel(bar, width=0.015, segments=2)
        objs.append(bar)

    # 4. Animated Lightning Electric Plasma Arcs (Randomized per frame)
    offsets = [
        [(-0.4, 0.05, 0.38), (0.0, -0.08, 0.42), (0.4, 0.06, 0.36)],
        [(-0.35, -0.06, 0.36), (0.05, 0.09, 0.45), (0.38, -0.05, 0.40)],
        [(-0.38, 0.08, 0.42), (0.0, -0.05, 0.35), (0.35, 0.07, 0.44)],
        [(-0.36, -0.04, 0.44), (-0.05, 0.08, 0.38), (0.4, -0.07, 0.37)]
    ]
    cur_pts = offsets[frame_idx % 4]

    for p in cur_pts:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=p)
        spark = bpy.context.active_object
        spark.data.materials.append(mat_plasma)
        objs.append(spark)

    # Electric Arc connecting lines
    for i in range(len(cur_pts) - 1):
        p1 = cur_pts[i]
        p2 = cur_pts[i + 1]
        mid = ((p1[0] + p2[0]) * 0.5, (p1[1] + p2[1]) * 0.5, (p1[2] + p2[2]) * 0.5)
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        dz = p2[2] - p1[2]
        length = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=length, vertices=8, location=mid)
        arc = bpy.context.active_object
        
        # Calculate rotation towards target
        phi = math.atan2(dy, dx)
        theta = math.acos(dz / length) if length > 0.001 else 0.0
        arc.rotation_euler = (0, theta, phi)
        arc.data.materials.append(mat_plasma)
        objs.append(arc)

    return objs


# ==============================================================================
# 3. EXPLOSIVE OIL BARREL / FUEL DRUM (汽油桶模型)
# ==============================================================================
def build_oil_barrel(burning: bool = False):
    objs = []

    mat_barrel = create_clay_mat("m_barrel_red", (0.85, 0.18, 0.16, 1.0), roughness=0.45)
    mat_rim = create_clay_mat("m_barrel_rim", (0.65, 0.12, 0.10, 1.0), roughness=0.50)
    mat_hazard = create_clay_mat("m_barrel_haz", (0.98, 0.82, 0.15, 1.0), roughness=0.40)
    mat_cap = create_clay_mat("m_barrel_cap", (0.45, 0.48, 0.54, 1.0), roughness=0.35)
    
    if burning:
        mat_flame = create_clay_mat("m_barrel_flame", (1.0, 0.45, 0.10, 1.0), emission=(1.0, 0.40, 0.05, 1.0), emission_str=5.0)
        mat_ember = create_clay_mat("m_barrel_ember", (1.0, 0.90, 0.20, 1.0), emission=(1.0, 0.85, 0.10, 1.0), emission_str=6.5)

    # 1. Main Drum Body Cylinder
    bpy.ops.mesh.primitive_cylinder_add(radius=0.56, depth=1.05, vertices=24, location=(0, 0, 0.48))
    body = bpy.context.active_object
    body.data.materials.append(mat_barrel)
    apply_uniform_clay_bevel(body, width=0.035, segments=2)
    objs.append(body)

    # 2. Reinforcing Metal Hoops / Ribs (Top, Mid, Bottom)
    for rz in [0.15, 0.48, 0.82]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.58, minor_radius=0.04, location=(0, 0, rz))
        rib = bpy.context.active_object
        rib.data.materials.append(mat_rim)
        objs.append(rib)

    # 3. Yellow Hazard Warning Stripe Band
    bpy.ops.mesh.primitive_cylinder_add(radius=0.57, depth=0.22, vertices=24, location=(0, 0, 0.48))
    haz_band = bpy.context.active_object
    haz_band.data.materials.append(mat_hazard)
    apply_uniform_clay_bevel(haz_band, width=0.015, segments=2)
    objs.append(haz_band)

    # 4. Top Recessed Lid & Spout Bung Cap
    bpy.ops.mesh.primitive_cylinder_add(radius=0.52, depth=0.06, vertices=24, location=(0, 0, 0.98))
    lid = bpy.context.active_object
    lid.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(lid, width=0.02, segments=2)
    objs.append(lid)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.10, vertices=12, location=(0.24, 0.15, 1.04))
    cap = bpy.context.active_object
    cap.data.materials.append(mat_cap)
    apply_uniform_clay_bevel(cap, width=0.015, segments=2)
    objs.append(cap)

    # 5. Optional Burning Flames & Sizzling Fuse (If ignited)
    if burning:
        for fx, fy, fz, fr in [(-0.1, -0.1, 1.15, 0.22), (0.12, 0.05, 1.26, 0.18), (0.0, 0.15, 1.35, 0.14)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=fr, location=(fx, fy, fz))
            flame = bpy.context.active_object
            flame.data.materials.append(mat_flame)
            objs.append(flame)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0.0, 0.0, 1.18))
        ember = bpy.context.active_object
        ember.data.materials.append(mat_ember)
        objs.append(ember)

    return objs


# ==============================================================================
# MAIN BATCH RENDERING PIPELINE
# ==============================================================================
def main():
    print("=== Starting 3D Modeling & Rendering for Street Lamp, Electric Wall, and Oil Barrel ===")
    setup_render_settings(rx=256, ry=256)

    # 1. Street Lamp (Lit & Unlit)
    print("Rendering: street_lamp.png...")
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_street_lamp(lit=True)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "street_lamp.png"))

    print("Rendering: street_lamp_lit.png...")
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_street_lamp(lit=True)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "street_lamp_lit.png"))

    # 2. Electric Wall (4 Animation Frames)
    for f in range(4):
        out_name = "tile_electric_wall_f%d.png" % f
        print("Rendering: %s..." % out_name)
        clear_scene()
        create_sokpop_lighting(ortho_scale=TILE_FULL_BLEED)
        objs = build_electric_wall(frame_idx=f)
        render_and_clean(objs, os.path.join(SPRITES_TILES, out_name))

    # 3. Oil Barrel (Standard & Burning)
    print("Rendering: oil_barrel.png...")
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_oil_barrel(burning=False)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "oil_barrel.png"))

    print("Rendering: oil_barrel_burning.png...")
    clear_scene()
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_oil_barrel(burning=True)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "oil_barrel_burning.png"))

    print("=== All 3D Assets Successfully Rendered to assets/sprites/! ===")

if __name__ == "__main__":
    main()
