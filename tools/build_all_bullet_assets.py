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
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

ORTHO_SCALE_BULLET = 2.4

# =========================================================================
# 1. MAIN TANK CANNON SHELL (bullet.png)
# High-explosive / kinetic armor-piercing artillery projectile
# Oriented facing +Y (Upwards in 2D space)
# =========================================================================
def build_standard_bullet():
    objs = []
    
    mat_shell = create_clay_mat("m_std_shell", (0.96, 0.42, 0.08, 1.0), roughness=0.30)
    mat_cap   = create_clay_mat("m_std_cap", (0.98, 0.94, 0.78, 1.0), emission=(1.0, 0.90, 0.60, 1.0), emission_str=2.2)
    mat_core  = create_clay_mat("m_std_core", (1.0, 0.98, 0.88, 1.0), emission=(1.0, 0.98, 0.85, 1.0), emission_str=4.5)
    mat_brass = create_clay_mat("m_std_brass", (1.0, 0.80, 0.18, 1.0), roughness=0.20)
    mat_steel = create_clay_mat("m_std_steel", (0.28, 0.26, 0.32, 1.0), roughness=0.45)
    mat_flame = create_clay_mat("m_std_flame", (1.0, 0.75, 0.15, 1.0), emission=(1.0, 0.80, 0.20, 1.0), emission_str=5.0)

    # 1. Main Cylindrical Shell Body
    bpy.ops.mesh.primitive_cylinder_add(radius=0.29, depth=0.85, vertices=24, location=(0, 0.02, 0.10))
    body = bpy.context.active_object
    body.rotation_euler = (math.radians(90), 0, 0)
    body.data.materials.append(mat_shell)
    apply_uniform_clay_bevel(body, width=0.03, segments=3)
    objs.append(body)

    # 2. Aerodynamic Ogive / Nosecone (+Y)
    bpy.ops.mesh.primitive_cone_add(radius1=0.29, radius2=0.06, depth=0.54, vertices=24, location=(0, 0.71, 0.10))
    nose = bpy.context.active_object
    nose.rotation_euler = (math.radians(-90), 0, 0)
    nose.data.materials.append(mat_cap)
    apply_uniform_clay_bevel(nose, width=0.03, segments=3)
    objs.append(nose)

    # 3. Extreme Kinetic Penetrator Tip (+Y 0.99)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085, location=(0, 0.99, 0.10))
    tip_sp = bpy.context.active_object
    tip_sp.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(tip_sp)

    # 4. Upper Brass Driving Band (+Y 0.30)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.315, minor_radius=0.048, location=(0, 0.30, 0.10))
    band_top = bpy.context.active_object
    band_top.rotation_euler = (math.radians(90), 0, 0)
    band_top.data.materials.append(mat_brass)
    bpy.ops.object.shade_smooth()
    objs.append(band_top)

    # 5. Lower Brass Driving Band (-Y 0.22)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.315, minor_radius=0.048, location=(0, -0.22, 0.10))
    band_bot = bpy.context.active_object
    band_bot.rotation_euler = (math.radians(90), 0, 0)
    band_bot.data.materials.append(mat_brass)
    bpy.ops.object.shade_smooth()
    objs.append(band_bot)

    # 6. Longitudinal Ballistic Flutes
    for ang in [math.pi/4, 3*math.pi/4, 5*math.pi/4, 7*math.pi/4]:
        fx = math.cos(ang) * 0.28
        fz = math.sin(ang) * 0.28 + 0.10
        bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.46, vertices=12, location=(fx, 0.04, fz))
        flute = bpy.context.active_object
        flute.rotation_euler = (math.radians(90), 0, 0)
        flute.data.materials.append(mat_brass)
        apply_uniform_clay_bevel(flute, width=0.01, segments=2)
        objs.append(flute)

    # 7. Boat-Tail Base Taper
    bpy.ops.mesh.primitive_cone_add(radius1=0.29, radius2=0.22, depth=0.22, vertices=20, location=(0, -0.51, 0.10))
    taper = bpy.context.active_object
    taper.rotation_euler = (math.radians(-90), 0, 0)
    taper.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(taper, width=0.02, segments=2)
    objs.append(taper)

    # 8. Steel Base Cup
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.08, vertices=18, location=(0, -0.64, 0.10))
    base_cup = bpy.context.active_object
    base_cup.rotation_euler = (math.radians(90), 0, 0)
    base_cup.data.materials.append(mat_steel)
    objs.append(base_cup)

    # 9. Glowing Tracer Flare Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(0, -0.70, 0.10))
    flare = bpy.context.active_object
    flare.scale = (0.9, 1.6, 0.9)
    flare.data.materials.append(mat_flame)
    bpy.ops.object.shade_smooth()
    objs.append(flare)

    return objs


# =========================================================================
# 2. PLASMA BOLT (bullet_plasma.png)
# High-energy hyper-condensed plasma slug that destroys steel
# Oriented facing +Y (Upwards in 2D space)
# =========================================================================
def build_plasma_bullet():
    objs = []

    mat_outer = create_clay_mat("m_pl_out", (0.12, 0.78, 1.0, 1.0), emission=(0.18, 0.88, 1.0, 1.0), emission_str=3.8)
    mat_core  = create_clay_mat("m_pl_core", (0.92, 0.98, 1.0, 1.0), emission=(0.95, 1.0, 1.0, 1.0), emission_str=6.8)
    mat_coil  = create_clay_mat("m_pl_coil", (0.50, 0.95, 1.0, 1.0), emission=(0.55, 0.98, 1.0, 1.0), emission_str=5.2)
    mat_tail  = create_clay_mat("m_pl_tail", (0.08, 0.42, 0.92, 1.0), emission=(0.10, 0.50, 0.95, 1.0), emission_str=2.8)

    # 1. Main Plasma Teardrop Body (Facing +Y)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0.15, 0.1))
    body = bpy.context.active_object
    body.scale = (0.88, 1.65, 0.88)
    body.data.materials.append(mat_outer)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    # 2. White-Hot Energy Singularity Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, 0.35, 0.12))
    core = bpy.context.active_object
    core.scale = (0.85, 1.35, 0.85)
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 3. Leading Plasma Focus Tip Cone (+Y)
    bpy.ops.mesh.primitive_cone_add(radius1=0.24, radius2=0.02, depth=0.45, vertices=16, location=(0, 0.82, 0.1))
    tip = bpy.context.active_object
    tip.rotation_euler = (math.radians(-90), 0, 0)
    tip.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(tip)

    # 4. Three Superconducting Energy Containment Rings
    for y_pos, ring_r in [(0.30, 0.36), (-0.05, 0.34), (-0.40, 0.28)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=ring_r, minor_radius=0.045, location=(0, y_pos, 0.1))
        ring = bpy.context.active_object
        ring.rotation_euler = (math.radians(90), 0, 0)
        ring.data.materials.append(mat_coil)
        bpy.ops.object.shade_smooth()
        objs.append(ring)

    # 5. Tapered Ion Trailing Comet Sheath (-Y)
    bpy.ops.mesh.primitive_cone_add(radius1=0.26, depth=0.65, vertices=16, location=(0, -0.65, 0.1))
    tail = bpy.context.active_object
    tail.rotation_euler = (math.radians(90), 0, 0)
    tail.data.materials.append(mat_tail)
    bpy.ops.object.shade_smooth()
    objs.append(tail)

    return objs


# =========================================================================
# 3. TACTICAL HOMING MISSILE (bullet_missile.png)
# Aerodynamic supersonic missile with 4 cross-stabilizer fins & rocket exhaust
# Oriented facing +Y (Upwards in 2D space)
# =========================================================================
def build_missile_bullet():
    objs = []

    mat_fuselage = create_clay_mat("m_mis_fuse", (0.92, 0.28, 0.22, 1.0), roughness=0.35)
    mat_radome   = create_clay_mat("m_mis_radome", (0.98, 0.88, 0.25, 1.0), roughness=0.25)
    mat_hazard   = create_clay_mat("m_mis_haz", (0.18, 0.16, 0.20, 1.0), roughness=0.50)
    mat_fin      = create_clay_mat("m_mis_fin", (0.28, 0.26, 0.32, 1.0), roughness=0.45)
    mat_thrust   = create_clay_mat("m_mis_thr", (1.0, 0.92, 0.50, 1.0), emission=(1.0, 0.75, 0.20, 1.0), emission_str=5.5)

    # 1. Main Cylindrical Fuselage
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.95, vertices=18, location=(0, -0.05, 0.1))
    fuse = bpy.context.active_object
    fuse.rotation_euler = (math.radians(90), 0, 0)
    fuse.data.materials.append(mat_fuselage)
    apply_uniform_clay_bevel(fuse, width=0.02, segments=2)
    objs.append(fuse)

    # 2. Sleek Ceramic Guidance Radome Nosecone (+Y)
    bpy.ops.mesh.primitive_cone_add(radius1=0.20, radius2=0.03, depth=0.55, vertices=18, location=(0, 0.65, 0.1))
    radome = bpy.context.active_object
    radome.rotation_euler = (math.radians(-90), 0, 0)
    radome.data.materials.append(mat_radome)
    apply_uniform_clay_bevel(radome, width=0.02, segments=2)
    objs.append(radome)

    # 3. Hazard Stripe Band Ring (+Y 0.35)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.21, depth=0.12, vertices=18, location=(0, 0.35, 0.1))
    haz_ring = bpy.context.active_object
    haz_ring.rotation_euler = (math.radians(90), 0, 0)
    haz_ring.data.materials.append(mat_hazard)
    objs.append(haz_ring)

    # 4. Forward Canard Guidance Fins (+Y 0.40)
    for x_dir in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_dir * 0.22, 0.40, 0.1))
        canard = bpy.context.active_object
        canard.scale = (0.16, 0.10, 0.03)
        canard.rotation_euler = (0, 0, math.radians(-x_dir * 25))
        canard.data.materials.append(mat_fin)
        apply_uniform_clay_bevel(canard, width=0.01, segments=2)
        objs.append(canard)

    # 5. Rear Swept-Wing Delta Stabilizer Fins (-Y 0.42)
    for x_dir in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_dir * 0.30, -0.42, 0.1))
        fin_h = bpy.context.active_object
        fin_h.scale = (0.28, 0.36, 0.035)
        fin_h.rotation_euler = (0, 0, math.radians(-x_dir * 30))
        fin_h.data.materials.append(mat_fin)
        apply_uniform_clay_bevel(fin_h, width=0.015, segments=2)
        objs.append(fin_h)

    for z_dir in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.42, 0.1 + z_dir * 0.26))
        fin_v = bpy.context.active_object
        fin_v.scale = (0.035, 0.36, 0.24)
        fin_v.rotation_euler = (math.radians(z_dir * 30), 0, 0)
        fin_v.data.materials.append(mat_fin)
        apply_uniform_clay_bevel(fin_v, width=0.015, segments=2)
        objs.append(fin_v)

    # 6. Rocket Engine Nozzle (-Y 0.58)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.14, vertices=16, location=(0, -0.58, 0.1))
    nozzle = bpy.context.active_object
    nozzle.rotation_euler = (math.radians(90), 0, 0)
    nozzle.data.materials.append(mat_hazard)
    objs.append(nozzle)

    # 7. Fiery Rocket Jet Flame Exhaust (-Y 0.82)
    bpy.ops.mesh.primitive_cone_add(radius1=0.18, depth=0.48, vertices=14, location=(0, -0.82, 0.1))
    flame = bpy.context.active_object
    flame.rotation_euler = (math.radians(90), 0, 0)
    flame.scale = (0.85, 1.2, 0.85)
    flame.data.materials.append(mat_thrust)
    bpy.ops.object.shade_smooth()
    objs.append(flame)

    return objs


# =========================================================================
# 4. RICOCHET REFLEX ROUND (bullet_ricochet.png)
# Electric kinetic bouncing round with amber shock coils
# Oriented facing +Y (Upwards in 2D space)
# =========================================================================
def build_ricochet_bullet():
    objs = []

    mat_slug = create_clay_mat("m_ric_slug", (0.82, 0.98, 0.22, 1.0), emission=(0.80, 0.95, 0.20, 1.0), emission_str=2.8)
    mat_apex = create_clay_mat("m_ric_apex", (0.95, 1.0, 0.75, 1.0), emission=(0.95, 1.0, 0.70, 1.0), emission_str=4.5)
    mat_coil = create_clay_mat("m_ric_coil", (1.0, 0.55, 0.10, 1.0), emission=(1.0, 0.55, 0.10, 1.0), emission_str=3.0)
    mat_base = create_clay_mat("m_ric_base", (0.28, 0.32, 0.22, 1.0), roughness=0.45)

    # 1. Main Kinetic Reflex Body (Facing +Y)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.85, vertices=18, location=(0, 0.02, 0.1))
    body = bpy.context.active_object
    body.rotation_euler = (math.radians(90), 0, 0)
    body.data.materials.append(mat_slug)
    apply_uniform_clay_bevel(body, width=0.03, segments=2)
    objs.append(body)

    # 2. Faceted Diamond Kinetic Armor-Piercing Warhead (+Y)
    bpy.ops.mesh.primitive_cone_add(radius1=0.28, radius2=0.03, depth=0.55, vertices=8, location=(0, 0.70, 0.1))
    apex = bpy.context.active_object
    apex.rotation_euler = (math.radians(-90), math.radians(22.5), 0)
    apex.data.materials.append(mat_apex)
    apply_uniform_clay_bevel(apex, width=0.02, segments=2)
    objs.append(apex)

    # 3. High-Energy Kinetic Tip Sphere (+Y 0.98)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, 0.98, 0.1))
    tip_sp = bpy.context.active_object
    tip_sp.data.materials.append(mat_apex)
    bpy.ops.object.shade_smooth()
    objs.append(tip_sp)

    # 4. Upper & Lower Amber Impulse Coils
    for y_pos in [0.28, -0.22]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.30, minor_radius=0.045, location=(0, y_pos, 0.1))
        coil = bpy.context.active_object
        coil.rotation_euler = (math.radians(90), 0, 0)
        coil.data.materials.append(mat_coil)
        bpy.ops.object.shade_smooth()
        objs.append(coil)

    # 5. Heavy Grounding Base Cap (-Y 0.46)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.16, vertices=16, location=(0, -0.46, 0.1))
    base = bpy.context.active_object
    base.rotation_euler = (math.radians(90), 0, 0)
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.03, segments=2)
    objs.append(base)

    # 6. Spark Discharger Core (-Y 0.56)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, -0.56, 0.1))
    spark = bpy.context.active_object
    spark.data.materials.append(mat_slug)
    bpy.ops.object.shade_smooth()
    objs.append(spark)

    return objs


def main():
    print("==================================================")
    print(" Executing Master 3D Clay Bullet Render Pipeline  ")
    print("==================================================")

    reset_jitter_seed(42)
    clear_scene()
    setup_render_settings(256, 256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_BULLET)

    # 1. Standard Bullet
    print(">>> 1. Rendering Standard Cannon Shell (bullet.png)...")
    objs_std = build_standard_bullet()
    render_and_clean(objs_std, os.path.join(SPRITES_EFFECTS, "bullet.png"))

    # 2. Plasma Bullet
    print(">>> 2. Rendering Plasma Slug (bullet_plasma.png)...")
    objs_pl = build_plasma_bullet()
    render_and_clean(objs_pl, os.path.join(SPRITES_EFFECTS, "bullet_plasma.png"))

    # 3. Homing Missile
    print(">>> 3. Rendering Tactical Homing Missile (bullet_missile.png)...")
    objs_mis = build_missile_bullet()
    render_and_clean(objs_mis, os.path.join(SPRITES_EFFECTS, "bullet_missile.png"))

    # 4. Ricochet Bullet
    print(">>> 4. Rendering Ricochet Reflex Round (bullet_ricochet.png)...")
    objs_ric = build_ricochet_bullet()
    render_and_clean(objs_ric, os.path.join(SPRITES_EFFECTS, "bullet_ricochet.png"))

    print("==================================================")
    print(" [SUCCESS] All 4 Clay Bullet Assets Rendered OK!  ")
    print("==================================================")


if __name__ == '__main__':
    main()
