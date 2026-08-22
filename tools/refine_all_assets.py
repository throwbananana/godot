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
    ORTHO_SCALE_PROP,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")

os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_TILES, exist_ok=True)
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)
os.makedirs(SPRITES_TANKS, exist_ok=True)

# ==================== 1. POWER-UPS REFINEMENT ====================

def build_star():
    objs = []
    mat_gold = create_clay_mat("m_star_gold", (0.98, 0.82, 0.18, 1.0), roughness=0.30)
    mat_ruby = create_clay_mat("m_star_ruby", (0.95, 0.18, 0.28, 1.0), emission=(0.95, 0.18, 0.28, 1.0), emission_str=3.5)
    mat_spark = create_clay_mat("m_star_spark", (1.0, 0.98, 0.70, 1.0), emission=(1.0, 0.98, 0.70, 1.0), emission_str=4.0)

    # 5-Point Star Arms
    for i in range(5):
        ang = i * (2.0 * math.pi / 5.0) + math.pi / 2.0
        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.32, vertices=3, location=(0, 0, 0))
        arm = bpy.context.active_object
        arm.scale = (0.70, 1.45, 0.80)
        arm.rotation_euler = (0, 0, ang - math.pi / 2.0)
        arm.location = (math.cos(ang) * 0.45, math.sin(ang) * 0.45, 0)
        arm.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(arm, width=0.04, segments=2)
        objs.append(arm)

    # Center Star Body
    bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=0.34, vertices=10, location=(0, 0, 0))
    center = bpy.context.active_object
    center.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(center, width=0.05, segments=2)
    objs.append(center)

    # Center Ruby Gem Crystal
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, 0, 0.14))
    gem = bpy.context.active_object
    gem.scale = (1.0, 1.0, 0.7)
    gem.data.materials.append(mat_ruby)
    bpy.ops.object.shade_smooth()
    objs.append(gem)

    # Orbiting Sparkles
    for (sx, sy) in [(0.68, 0.68), (-0.68, 0.68), (0.75, -0.45), (-0.75, -0.45)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(sx, sy, 0.10))
        sp = bpy.context.active_object
        sp.data.materials.append(mat_spark)
        bpy.ops.object.shade_smooth()
        objs.append(sp)

    return objs

def build_bomb():
    objs = []
    mat_black = create_clay_mat("m_bomb_black", (0.16, 0.16, 0.20, 1.0), roughness=0.65)
    mat_hazard_y = create_clay_mat("m_bomb_hz_y", (0.98, 0.80, 0.12, 1.0), roughness=0.40)
    mat_hazard_k = create_clay_mat("m_bomb_hz_k", (0.12, 0.12, 0.14, 1.0), roughness=0.40)
    mat_brass = create_clay_mat("m_bomb_brass", (0.78, 0.58, 0.22, 1.0), roughness=0.35)
    mat_spark = create_clay_mat("m_bomb_spark", (1.0, 0.55, 0.08, 1.0), emission=(1.0, 0.55, 0.08, 1.0), emission_str=4.5)

    # Main Spherical Bomb
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.88, location=(0, -0.10, 0))
    body = bpy.context.active_object
    body.data.materials.append(mat_black)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    # Equator Hazard Ring Stripes
    for i in range(8):
        ang = i * (2.0 * math.pi / 8.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.87, math.sin(ang) * 0.87 - 0.10, 0))
        stripe = bpy.context.active_object
        stripe.scale = (0.24, 0.12, 0.35)
        stripe.rotation_euler = (0, 0, ang)
        stripe.data.materials.append(mat_hazard_y if i % 2 == 0 else mat_hazard_k)
        apply_uniform_clay_bevel(stripe, width=0.02, segments=2)
        objs.append(stripe)

    # Brass Top Collar
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.25, vertices=16, location=(0, 0.74, 0))
    collar = bpy.context.active_object
    collar.data.materials.append(mat_brass)
    apply_uniform_clay_bevel(collar, width=0.03, segments=2)
    objs.append(collar)

    # Curved Fuse Rope
    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.38, vertices=12, location=(0.12, 0.95, 0))
    fuse = bpy.context.active_object
    fuse.rotation_euler = (0, 0, math.radians(-35))
    fuse.data.materials.append(mat_brass)
    objs.append(fuse)

    # Flaming Spark Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0.24, 1.12, 0.05))
    spark = bpy.context.active_object
    spark.data.materials.append(mat_spark)
    bpy.ops.object.shade_smooth()
    objs.append(spark)

    return objs

def build_shovel():
    objs = []
    mat_steel = create_clay_mat("m_shv_steel", (0.75, 0.78, 0.85, 1.0), roughness=0.30)
    mat_trim = create_clay_mat("m_shv_trim", (0.95, 0.80, 0.20, 1.0), roughness=0.35)
    mat_wood = create_clay_mat("m_shv_wood", (0.50, 0.32, 0.18, 1.0), roughness=0.75)
    mat_spark = create_clay_mat("m_shv_spark", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=3.5)

    # Shovel Blade Spade (Pointed Beveled Metal)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.42, 0))
    blade = bpy.context.active_object
    blade.scale = (1.05, 0.95, 0.12)
    blade.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(blade, width=0.06, segments=2)
    objs.append(blade)

    # Blade Reinforced Gold Rim
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.85, 0))
    tip = bpy.context.active_object
    tip.scale = (0.75, 0.15, 0.14)
    tip.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(tip, width=0.03, segments=2)
    objs.append(tip)

    # Wood Shaft
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=1.35, vertices=16, location=(0, 0.35, 0))
    shaft = bpy.context.active_object
    shaft.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(shaft, width=0.02, segments=2)
    objs.append(shaft)

    # D-Grip Handle on top
    bpy.ops.mesh.primitive_torus_add(major_radius=0.24, minor_radius=0.06, location=(0, 1.05, 0))
    grip = bpy.context.active_object
    grip.data.materials.append(mat_steel)
    bpy.ops.object.shade_smooth()
    objs.append(grip)

    # Sparkle Star
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0.42, -0.75, 0.10))
    sp = bpy.context.active_object
    sp.data.materials.append(mat_spark)
    bpy.ops.object.shade_smooth()
    objs.append(sp)

    return objs

def build_clock():
    objs = []
    mat_brass = create_clay_mat("m_clk_brass", (0.88, 0.68, 0.22, 1.0), roughness=0.35)
    mat_dial = create_clay_mat("m_clk_dial", (0.94, 0.95, 0.98, 1.0), roughness=0.50)
    mat_gear = create_clay_mat("m_clk_gear", (0.25, 0.75, 0.95, 1.0), emission=(0.25, 0.75, 0.95, 1.0), emission_str=2.5)
    mat_hand = create_clay_mat("m_clk_hand", (0.15, 0.15, 0.20, 1.0), roughness=0.40)

    # Brass Outer Watch Case
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.28, vertices=32, location=(0, -0.05, 0))
    case = bpy.context.active_object
    case.data.materials.append(mat_brass)
    apply_uniform_clay_bevel(case, width=0.06, segments=2)
    objs.append(case)

    # Watch Dial Face
    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.10, vertices=32, location=(0, -0.05, 0.12))
    dial = bpy.context.active_object
    dial.data.materials.append(mat_dial)
    apply_uniform_clay_bevel(dial, width=0.02, segments=2)
    objs.append(dial)

    # Top Winder & Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.22, vertices=16, location=(0, 0.95, 0))
    winder = bpy.context.active_object
    winder.data.materials.append(mat_brass)
    apply_uniform_clay_bevel(winder, width=0.03, segments=2)
    objs.append(winder)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.05, location=(0, 1.18, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_brass)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # Glowing Cyan Clock Hands & Center Pin
    for (ang, length) in [(math.radians(30), 0.46), (math.radians(120), 0.32)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18))
        hand = bpy.context.active_object
        hand.scale = (0.06, length, 0.04)
        hand.rotation_euler = (0, 0, ang)
        hand.location = (math.cos(ang + math.pi / 2.0) * length * 0.5, math.sin(ang + math.pi / 2.0) * length * 0.5 - 0.05, 0.18)
        hand.data.materials.append(mat_hand)
        apply_uniform_clay_bevel(hand, width=0.01, segments=1)
        objs.append(hand)

    # Glowing Ice Core Center
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, -0.05, 0.20))
    pin = bpy.context.active_object
    pin.data.materials.append(mat_gear)
    bpy.ops.object.shade_smooth()
    objs.append(pin)

    return objs

def build_helmet():
    objs = []
    mat_olive = create_clay_mat("m_hlm_olive", (0.32, 0.44, 0.28, 1.0), roughness=0.65)
    mat_rim = create_clay_mat("m_hlm_rim", (0.20, 0.28, 0.18, 1.0), roughness=0.60)
    mat_goggle = create_clay_mat("m_hlm_goggle", (0.20, 0.70, 0.95, 1.0), emission=(0.20, 0.70, 0.95, 1.0), emission_str=2.2)
    mat_strap = create_clay_mat("m_hlm_strap", (0.18, 0.16, 0.14, 1.0), roughness=0.70)
    mat_gold = create_clay_mat("m_hlm_star", (0.98, 0.82, 0.18, 1.0), roughness=0.35)

    # Helmet Dome
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.88, location=(0, 0.05, 0.15))
    dome = bpy.context.active_object
    dome.scale = (1.0, 1.15, 0.85)
    dome.data.materials.append(mat_olive)
    bpy.ops.object.shade_smooth()
    objs.append(dome)

    # Extended Flared Brim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.14, vertices=32, location=(0, 0.05, -0.22))
    brim = bpy.context.active_object
    brim.scale = (1.0, 1.18, 1.0)
    brim.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(brim, width=0.04, segments=2)
    objs.append(brim)

    # Goggles Strap & Lenses on front brow
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.75, 0.08))
    g_strap = bpy.context.active_object
    g_strap.scale = (1.30, 0.14, 0.18)
    g_strap.data.materials.append(mat_strap)
    apply_uniform_clay_bevel(g_strap, width=0.03, segments=2)
    objs.append(g_strap)

    for gx in [-0.32, 0.32]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.16, vertices=16, location=(gx, 0.80, 0.08))
        lens = bpy.context.active_object
        lens.rotation_euler = (math.radians(90), 0, 0)
        lens.data.materials.append(mat_goggle)
        apply_uniform_clay_bevel(lens, width=0.03, segments=2)
        objs.append(lens)

    # Gold Star Emblem
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0.78, 0.38))
    star = bpy.context.active_object
    star.data.materials.append(mat_gold)
    bpy.ops.object.shade_smooth()
    objs.append(star)

    return objs

def build_life():
    objs = []
    mat_heart = create_clay_mat("m_lif_heart", (0.95, 0.18, 0.28, 1.0), roughness=0.30)
    mat_glow = create_clay_mat("m_lif_glow", (1.0, 0.35, 0.45, 1.0), emission=(1.0, 0.35, 0.45, 1.0), emission_str=3.0)
    mat_gold = create_clay_mat("m_lif_gold", (0.98, 0.82, 0.18, 1.0), roughness=0.35)
    mat_cross = create_clay_mat("m_lif_cross", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=3.5)

    # Dual Lobes of Heart
    for lx in [-0.36, 0.36]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.52, location=(lx, 0.24, 0))
        lobe = bpy.context.active_object
        lobe.data.materials.append(mat_heart)
        bpy.ops.object.shade_smooth()
        objs.append(lobe)

    # Bottom Cone of Heart
    bpy.ops.mesh.primitive_cone_add(radius1=0.82, radius2=0.08, depth=1.05, vertices=24, location=(0, -0.32, 0))
    cone = bpy.context.active_object
    cone.rotation_euler = (math.radians(180), 0, 0)
    cone.data.materials.append(mat_heart)
    apply_uniform_clay_bevel(cone, width=0.06, segments=2)
    objs.append(cone)

    # Golden Winglets on sides
    for wx in [-0.85, 0.85]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(wx, 0.15, -0.08))
        wing = bpy.context.active_object
        wing.scale = (0.42, 0.26, 0.12)
        wing.rotation_euler = (0, 0, math.radians(-30 if wx > 0 else 30))
        wing.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(wing, width=0.03, segments=2)
        objs.append(wing)

    # Luminous White Medical Cross Crest in Center
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.05, 0.36))
    c1 = bpy.context.active_object
    c1.scale = (0.14, 0.42, 0.08)
    c1.data.materials.append(mat_cross)
    objs.append(c1)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.05, 0.36))
    c2 = bpy.context.active_object
    c2.scale = (0.42, 0.14, 0.08)
    c2.data.materials.append(mat_cross)
    objs.append(c2)

    return objs

# ==================== 2. BASE EAGLE REFINEMENT ====================

def build_base_eagle(state="pristine"):
    # state: 'pristine', 'damaged', 'destroyed'
    objs = []
    mat_pedestal = create_clay_mat("m_bse_stone", (0.35, 0.36, 0.42, 1.0), roughness=0.70)
    mat_gold = create_clay_mat("m_bse_gold", (0.96, 0.80, 0.20, 1.0), roughness=0.35)
    mat_eye = create_clay_mat("m_bse_eye", (0.30, 0.85, 1.0, 1.0), emission=(0.30, 0.85, 1.0, 1.0), emission_str=3.5)
    mat_rubble = create_clay_mat("m_bse_rubble", (0.22, 0.20, 0.22, 1.0), roughness=0.85)
    mat_ember = create_clay_mat("m_bse_ember", (0.95, 0.35, 0.10, 1.0), emission=(0.95, 0.35, 0.10, 1.0), emission_str=4.0)

    if state == "pristine" or state == "damaged":
        # 1. Tiered Marble Pedestal
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.35, -0.15))
        ped = bpy.context.active_object
        ped.scale = (1.80, 1.20, 0.45)
        ped.data.materials.append(mat_pedestal)
        apply_uniform_clay_bevel(ped, width=0.08, segments=3)
        objs.append(ped)

        # 2. Eagle Body Torso
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.0, 0.10))
        torso = bpy.context.active_object
        torso.scale = (0.75, 0.65, 0.95)
        torso.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(torso, width=0.08, segments=2)
        objs.append(torso)

        # 3. Eagle Wings (Left & Right)
        for (wx, ang_z) in [(-0.78, 25), (0.78, -25)]:
            if state == "damaged" and wx < 0:
                continue # Shattered left wing in damaged state
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(wx, 0.12, 0.25))
            wing = bpy.context.active_object
            wing.scale = (0.85, 0.40, 0.80)
            wing.rotation_euler = (0, 0, math.radians(ang_z))
            wing.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(wing, width=0.06, segments=2)
            objs.append(wing)

        # 4. Eagle Head & Beak
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0.48, 0.45))
        head = bpy.context.active_object
        head.scale = (0.85, 1.0, 0.85)
        head.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(head)

        bpy.ops.mesh.primitive_cone_add(radius1=0.22, depth=0.45, vertices=16, location=(0, 0.82, 0.38))
        beak = bpy.context.active_object
        beak.rotation_euler = (math.radians(90), 0, 0)
        beak.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(beak, width=0.03, segments=2)
        objs.append(beak)

        # Glowing Eyes
        for ex in [-0.18, 0.18]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(ex, 0.64, 0.52))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_eye)
            bpy.ops.object.shade_smooth()
            objs.append(eye)

        if state == "damaged":
            # Add crack chunks and embers
            for (cx, cy) in [(-0.55, 0.1), (-0.3, -0.2), (0.4, -0.4)]:
                bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.05))
                chunk = bpy.context.active_object
                chunk.scale = (0.22, 0.22, 0.18)
                chunk.rotation_euler = (0.3, 0.4, 0.5)
                chunk.data.materials.append(mat_rubble)
                apply_uniform_clay_bevel(chunk, width=0.03, segments=1)
                objs.append(chunk)

    elif state == "destroyed":
        # Ruined Broken Pedestal
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.2, -0.15))
        ped = bpy.context.active_object
        ped.scale = (1.80, 1.20, 0.35)
        ped.data.materials.append(mat_rubble)
        apply_uniform_clay_bevel(ped, width=0.08, segments=2)
        objs.append(ped)

        # Broken Pillar Stumps
        for (px, py, pz, ps) in [(-0.45, -0.1, 0.1, 0.4), (0.5, 0.2, 0.15, 0.35)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=ps, vertices=12, location=(px, py, pz))
            stump = bpy.context.active_object
            stump.rotation_euler = (0.2, -0.3, 0.4)
            stump.data.materials.append(mat_rubble)
            apply_uniform_clay_bevel(stump, width=0.04, segments=1)
            objs.append(stump)

        # Fallen Shattered Eagle Head in Rubble
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(0.1, -0.35, 0.05))
        head = bpy.context.active_object
        head.rotation_euler = (1.2, 0.8, -0.5)
        head.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(head, width=0.04, segments=1)
        objs.append(head)

        # Smoldering Fire Embers
        for (ex, ey, ez) in [(-0.15, 0.25, 0.1), (0.35, -0.15, 0.08), (-0.45, -0.35, 0.05)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(ex, ey, ez))
            ember = bpy.context.active_object
            ember.data.materials.append(mat_ember)
            bpy.ops.object.shade_smooth()
            objs.append(ember)

    return objs

def main():
    print("==================================================")
    print(" Executing Master 3D Asset Refinement Pipeline... ")
    print("==================================================")

    # 1. Refine Star
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_star()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "star.png"))
    print("[OK] Star Refined.")

    # 2. Refine Bomb
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_bomb()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "bomb.png"))
    print("[OK] Bomb Refined.")

    # 3. Refine Shovel
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_shovel()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "shovel.png"))
    print("[OK] Shovel Refined.")

    # 4. Refine Clock
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_clock()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "clock.png"))
    print("[OK] Clock Refined.")

    # 5. Refine Helmet
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_helmet()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "helmet.png"))
    print("[OK] Helmet Refined.")

    # 6. Refine Life
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_life()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "life.png"))
    print("[OK] Life Refined.")

    # 7. Refine Base Eagle (Pristine, Damaged, Destroyed)
    for state, fname in [("pristine", "base_eagle.png"), ("damaged", "base_damaged.png"), ("destroyed", "base_destroyed.png")]:
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=TILE_FULL_BLEED)
        objs = build_base_eagle(state)
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))
        print(f"[OK] Base Eagle ({state}) Refined -> {fname}")

if __name__ == '__main__':
    main()
