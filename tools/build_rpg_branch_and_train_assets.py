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
    reset_jitter_seed,
    render_and_clean,
    purge_orphans,
    clear_material_cache,
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
os.makedirs(SPRITES_TANKS, exist_ok=True)

def get_track_mat(name):
    return create_clay_mat(f"{name}_trk", (0.30, 0.28, 0.34, 1.0), roughness=0.88)

def get_bore_mat(name):
    return create_clay_mat(f"{name}_bore", (0.08, 0.08, 0.12, 1.0), roughness=0.92)

# ==================== 1. SPEED / SCOUT TANKS ====================
def build_speed_tank(name_prefix, col_body, col_turret, col_trim, tier=1, frame=0):
    """
    Speed Tank: Aerodynamic wedge chassis, twin/triple needle cannons,
    dual nitro exhaust thrusters, lightweight high-speed roadwheels.
    """
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_turret = create_clay_mat(f"{name_prefix}_t", col_turret)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_track = get_track_mat(name_prefix)
    mat_bore = get_bore_mat(name_prefix)
    mat_glow = create_clay_mat(f"{name_prefix}_gl", (0.2, 0.95, 1.0, 1.0), emission=(0.2, 0.95, 1.0, 1.0), emission_str=4.0)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015
    w, l = 1.15, 1.35
    tw, tl = 0.28, 1.40
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. Sleek Wedge Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.02 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.44)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.14, segments=4)
    objs.append(hull)

    # 2. Aerodynamic Sloped Nose (Front wedge deflector)
    bpy.ops.mesh.primitive_cone_add(radius1=w*0.52, radius2=0.1, depth=0.55, vertices=4, location=(0, l*0.48, 0.02 + bob_z))
    nose = bpy.context.active_object
    nose.rotation_euler = (math.radians(90), 0, math.radians(45))
    nose.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nose, width=0.08, segments=3)
    objs.append(nose)

    # 3. Dual Nitro Exhaust Thrusters on the back
    for ex_x in [-0.34, 0.34]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.38, vertices=12, location=(ex_x, -l*0.50, 0.12 + bob_z))
        thruster = bpy.context.active_object
        thruster.rotation_euler = (math.radians(90), 0, 0)
        thruster.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(thruster, width=0.04, segments=2)
        objs.append(thruster)

        # Glowing nozzle core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex_x, -l*0.50 - 0.18, 0.12 + bob_z))
        core = bpy.context.active_object
        core.data.materials.append(mat_glow)
        bpy.ops.object.shade_smooth()
        objs.append(core)

    # 4. Narrow High-Speed Tracks & Wheels
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.48)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.12, segments=3)
        objs.append(tr)

        # 4 small roadwheels per track
        for wy in [-0.48, -0.16, 0.16, 0.48]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=tw*1.08, vertices=12, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), wheel_rot)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.06, segments=2)
            objs.append(wh)

    # 5. Low-profile Teardrop Turret
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, -0.06, 0.42 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (0.88, 1.25, 0.62)
    turret.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret, width=0.06, segments=3)
    objs.append(turret)

    # 6. High-Speed Cannons (Tier 1: Twin Rapid Cannons; Tier 2: Triple Gatling Needles + Side Fins)
    if tier == 1:
        for bx in [-0.16, 0.16]:
            blen, bthick = 1.25, 0.11
            bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=12, location=(bx, 0.30 + blen/2.0, 0.42))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(barrel, width=0.04, segments=2)
            objs.append(barrel)

            # Muzzle tip & bore
            bpy.ops.mesh.primitive_cylinder_add(radius=bthick*0.6, depth=0.08, vertices=10, location=(bx, 0.30 + blen + 0.02, 0.42))
            bore = bpy.context.active_object
            bore.rotation_euler = (math.radians(90), 0, 0)
            bore.data.materials.append(mat_bore)
            objs.append(bore)
    else:
        # Tier 2: Triple needle cannons + Side swept stabilizers
        for bx in [-0.22, 0.0, 0.22]:
            blen, bthick = 1.35 if bx == 0 else 1.20, 0.10
            bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=12, location=(bx, 0.30 + blen/2.0, 0.42))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(barrel, width=0.03, segments=2)
            objs.append(barrel)

        # Swept Side Wings / Fins
        for wing_x in [-0.62, 0.62]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(wing_x, -0.15, 0.36 + bob_z))
            wing = bpy.context.active_object
            wing.scale = (0.24, 0.65, 0.08)
            wing.rotation_euler = (0, math.radians(-15 if wing_x > 0 else 15), math.radians(20 if wing_x > 0 else -20))
            wing.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wing, width=0.04, segments=2)
            objs.append(wing)

    return objs

# ==================== 2. HEAVY / STRENGTH TANKS ====================
def build_heavy_tank(name_prefix, col_body, col_turret, col_trim, tier=1, frame=0):
    """
    Heavy / Strength Tank: Ultra-wide heavy armor plates with bolt studs,
    massive howitzer siege cannon (huge bore + thick muzzle brake),
    wide heavy tracks / quad tracks.
    """
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_turret = create_clay_mat(f"{name_prefix}_t", col_turret)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_armor = create_clay_mat(f"{name_prefix}_arm", (col_body[0]*0.8, col_body[1]*0.8, col_body[2]*0.8, 1.0), roughness=0.82)
    mat_track = get_track_mat(name_prefix)
    mat_bore = get_bore_mat(name_prefix)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.010
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    w, l = 1.65, 1.60
    tw, tl = 0.45, 1.70
    tx = w * 0.5 + tw * 0.5 - 0.05

    # 1. Fortified Wide Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.08 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.68)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # 2. Side Reactive Armor Slabs with Rivet Studs
    for side_x in [-w*0.52, w*0.52]:
        for slab_y in [-0.45, 0.0, 0.45]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, slab_y, 0.12 + bob_z))
            slab = bpy.context.active_object
            slab.scale = (0.12, 0.38, 0.48)
            slab.data.materials.append(mat_armor)
            apply_uniform_clay_bevel(slab, width=0.04, segments=2)
            objs.append(slab)

            # Rivet Stud
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(side_x + (0.07 if side_x > 0 else -0.07), slab_y, 0.20 + bob_z))
            riv = bpy.context.active_object
            riv.data.materials.append(mat_trim)
            bpy.ops.object.shade_smooth()
            objs.append(riv)

    # 3. Front Heavy Battering Ram Wedge
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, l*0.52, 0.04 + bob_z))
    ram = bpy.context.active_object
    ram.scale = (w*0.92, 0.24, 0.46)
    ram.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(ram, width=0.10, segments=3)
    objs.append(ram)

    # 4. Super Wide Heavy Tracks
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.04))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.72)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.18, segments=4)
        objs.append(tr)

        # 4 Heavy Roadwheels with reinforced hubcaps
        for wy in [-0.55, -0.18, 0.18, 0.55]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0.02))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), wheel_rot)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.08, segments=3)
            objs.append(wh)

    # 5. Heavy Square Cast Turret
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.08, 0.62 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.05, 1.10, 0.65)
    turret.data.materials.append(mat_turret)
    apply_uniform_clay_bevel(turret, width=0.14, segments=4)
    objs.append(turret)

    # 6. Giant Heavy Siege Cannons
    if tier == 1:
        # Tier 1: Massive Single Heavy Howitzer
        blen, bthick = 1.10, 0.32
        bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=16, location=(0, 0.35 + blen/2.0, 0.62))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_turret)
        apply_uniform_clay_bevel(barrel, width=0.08, segments=3)
        objs.append(barrel)

        # Heavy Muzzle Brake Collar
        bpy.ops.mesh.primitive_torus_add(major_radius=bthick*1.38, minor_radius=0.12, location=(0, 0.35 + blen, 0.62))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        # Deep Hollow Bore
        bpy.ops.mesh.primitive_cylinder_add(radius=bthick*0.75, depth=0.16, vertices=14, location=(0, 0.35 + blen + 0.04, 0.62))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)
    else:
        # Tier 2: Twin Super-Heavy Siege Mortars
        for bx in [-0.32, 0.32]:
            blen, bthick = 1.18, 0.26
            bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=16, location=(bx, 0.35 + blen/2.0, 0.62))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(barrel, width=0.06, segments=3)
            objs.append(barrel)

            bpy.ops.mesh.primitive_torus_add(major_radius=bthick*1.32, minor_radius=0.10, location=(bx, 0.35 + blen, 0.62))
            muzzle = bpy.context.active_object
            muzzle.rotation_euler = (math.radians(90), 0, 0)
            muzzle.data.materials.append(mat_trim)
            bpy.ops.object.shade_smooth()
            objs.append(muzzle)

            bpy.ops.mesh.primitive_cylinder_add(radius=bthick*0.70, depth=0.14, vertices=14, location=(bx, 0.35 + blen + 0.03, 0.62))
            bore = bpy.context.active_object
            bore.rotation_euler = (math.radians(90), 0, 0)
            bore.data.materials.append(mat_bore)
            objs.append(bore)

    return objs

# ==================== 3. TRAIN TANK LOCOMOTIVE (列车车头) ====================
def build_train_locomotive(name_prefix, col_body, col_cab, col_trim, is_enemy=False, tier=1, frame=0):
    """
    Train Locomotive Tank: Heavy armored engine locomotive with cowcatcher wedge,
    boiler rivets, smokestack chimney, armored engineer cabin, searchlights, and rear hitch.
    """
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_cab = create_clay_mat(f"{name_prefix}_c", col_cab)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_track = get_track_mat(name_prefix)
    mat_bore = get_bore_mat(name_prefix)
    mat_glow = create_clay_mat(f"{name_prefix}_gl", (1.0, 0.2, 0.2, 1.0) if is_enemy else (1.0, 0.9, 0.3, 1.0), emission=(1.0, 0.2, 0.2, 1.0) if is_enemy else (1.0, 0.9, 0.3, 1.0), emission_str=4.0)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012
    w, l = 1.35, 1.75
    tw, tl = 0.34, 1.85
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. Locomotive Chassis Deck
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.04 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.52)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.14, segments=4)
    objs.append(hull)

    # 2. Front Heavy Cowcatcher (排障三角铁铲 / 铁道撞角)
    bpy.ops.mesh.primitive_cone_add(radius1=w*0.58, radius2=0.08, depth=0.60, vertices=4, location=(0, l*0.50, -0.02 + bob_z))
    cow = bpy.context.active_object
    cow.rotation_euler = (math.radians(90), 0, math.radians(45))
    cow.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(cow, width=0.08, segments=3)
    objs.append(cow)

    # Cowcatcher Grill Slats
    for slat_z in [-0.10, 0.02, 0.14]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, l*0.52, slat_z + bob_z))
        slat = bpy.context.active_object
        slat.scale = (w*0.82, 0.08, 0.06)
        slat.data.materials.append(mat_body)
        apply_uniform_clay_bevel(slat, width=0.02, segments=2)
        objs.append(slat)

    # 3. Cylindrical Locomotive Boiler (车体锅炉段)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=1.0, vertices=16, location=(0, 0.18, 0.44 + bob_z))
    boiler = bpy.context.active_object
    boiler.rotation_euler = (math.radians(90), 0, 0)
    boiler.data.materials.append(mat_body)
    apply_uniform_clay_bevel(boiler, width=0.08, segments=3)
    objs.append(boiler)

    # Boiler Rivet Straps
    for strap_y in [-0.15, 0.18, 0.50]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.52, minor_radius=0.045, location=(0, strap_y, 0.44 + bob_z))
        strap = bpy.context.active_object
        strap.rotation_euler = (math.radians(90), 0, 0)
        strap.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(strap)

    # 4. Smokestack Chimney (烟囱)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.42, vertices=14, location=(0, 0.46, 0.88 + bob_z))
    chimney = bpy.context.active_object
    chimney.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(chimney, width=0.05, segments=3)
    objs.append(chimney)

    # Smokestack Rim
    bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.05, location=(0, 0.46, 1.08 + bob_z))
    ch_rim = bpy.context.active_object
    ch_rim.data.materials.append(mat_trim)
    bpy.ops.object.shade_smooth()
    objs.append(ch_rim)

    # 5. Rear Armored Engineer Cabin (后方驾驶室)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.48, 0.58 + bob_z))
    cab = bpy.context.active_object
    cab.scale = (w*0.90, 0.65, 0.68)
    cab.data.materials.append(mat_cab)
    apply_uniform_clay_bevel(cab, width=0.10, segments=3)
    objs.append(cab)

    # Front Big Searchlight (车头巨型探照灯 / 独眼)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.16, vertices=16, location=(0, 0.70, 0.46 + bob_z))
    light_cup = bpy.context.active_object
    light_cup.rotation_euler = (math.radians(90), 0, 0)
    light_cup.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(light_cup, width=0.03, segments=2)
    objs.append(light_cup)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0.76, 0.46 + bob_z))
    light_lens = bpy.context.active_object
    light_lens.data.materials.append(mat_glow)
    bpy.ops.object.shade_smooth()
    objs.append(light_lens)

    # 6. Heavy Iron Tracks (6 Train Wheels per track)
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.62)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.14, segments=4)
        objs.append(tr)

        # 5 Steel Train Driving Wheels
        for wy in [-0.60, -0.30, 0.0, 0.30, 0.60]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), wheel_rot)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.06, segments=2)
            objs.append(wh)

    # 7. Rear Coupling Hitch (挂钩)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.24, vertices=12, location=(0, -l*0.52, 0.08 + bob_z))
    hitch = bpy.context.active_object
    hitch.rotation_euler = (math.radians(90), 0, 0)
    hitch.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(hitch, width=0.02, segments=2)
    objs.append(hitch)

    # Main Front Gun (Locomotive Forward Cannon)
    blen, bthick = 0.95, 0.22
    bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=14, location=(0, 0.72 + blen/2.0, 0.46))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_cab)
    apply_uniform_clay_bevel(gun, width=0.04, segments=2)
    objs.append(gun)

    return objs

# ==================== 4. TRAIN WAGONS / CARRIAGES (后节车厢) ====================
def build_train_carriage(name_prefix, col_body, col_trim, wagon_type="turret", is_enemy=False, frame=0):
    """
    Train Wagon / Carriage: Follower vehicle attached behind the locomotive.
    wagon_type:
      - 'turret': 360-degree rotating machine-gun/cannon turret
      - 'armor': Heavy defensive wagon with shield emitter
      - 'rocket': Twin missile/mortar pods
      - 'enemy_gunner': Carriage with mounted enemy gunner aiming
    """
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_track = get_track_mat(name_prefix)
    mat_bore = get_bore_mat(name_prefix)
    mat_glow = create_clay_mat(f"{name_prefix}_gl", (1.0, 0.25, 0.25, 1.0) if is_enemy else (0.3, 0.9, 1.0, 1.0), emission=(1.0, 0.25, 0.25, 1.0) if is_enemy else (0.3, 0.9, 1.0, 1.0), emission_str=3.5)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.010
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    w, l = 1.25, 1.35
    tw, tl = 0.30, 1.45
    tx = w * 0.5 + tw * 0.5 - 0.03

    # 1. Carriage Chassis Platform
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.04 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.48)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.12, segments=4)
    objs.append(hull)

    # 2. Side Armored Guardrails & Bolted Ribs
    for side_x in [-w*0.48, w*0.48]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side_x, 0, 0.34 + bob_z))
        rail = bpy.context.active_object
        rail.scale = (0.10, l*0.88, 0.22)
        rail.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(rail, width=0.03, segments=2)
        objs.append(rail)

    # Front and Rear Hitch Couplings
    for hy in [-l*0.52, l*0.52]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.20, vertices=10, location=(0, hy, 0.06 + bob_z))
        hitch = bpy.context.active_object
        hitch.rotation_euler = (math.radians(90), 0, 0)
        hitch.data.materials.append(mat_trim)
        objs.append(hitch)

    # 3. Tracks & 3 Wheels per side
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.54)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.12, segments=3)
        objs.append(tr)

        for wy in [-0.42, 0.0, 0.42]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=tw*1.06, vertices=12, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), wheel_rot)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.05, segments=2)
            objs.append(wh)

    # 4. Mounted Module according to wagon_type
    if wagon_type == "turret":
        # Rotating Turret Dome
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0, 0.46 + bob_z))
        turret = bpy.context.active_object
        turret.scale = (1.0, 1.0, 0.70)
        turret.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(turret, width=0.06, segments=3)
        objs.append(turret)

        # Dual Auto-Cannons
        for bx in [-0.14, 0.14]:
            blen, bthick = 0.95, 0.12
            bpy.ops.mesh.primitive_cylinder_add(radius=bthick, depth=blen, vertices=12, location=(bx, 0.20 + blen/2.0, 0.46))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_body)
            apply_uniform_clay_bevel(barrel, width=0.03, segments=2)
            objs.append(barrel)

    elif wagon_type == "armor":
        # Heavy Shield Generator / Reinforced Armor Block
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.42 + bob_z))
        bunker = bpy.context.active_object
        bunker.scale = (0.90, 0.95, 0.48)
        bunker.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(bunker, width=0.10, segments=3)
        objs.append(bunker)

        # Energy Shield Coil Core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.24, location=(0, 0, 0.72 + bob_z))
        orb = bpy.context.active_object
        orb.data.materials.append(mat_glow)
        bpy.ops.object.shade_smooth()
        objs.append(orb)

    elif wagon_type == "rocket":
        # Twin Rocket Artillery Pods
        for px in [-0.28, 0.28]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, -0.05, 0.48 + bob_z))
            pod = bpy.context.active_object
            pod.scale = (0.34, 0.75, 0.42)
            pod.rotation_euler = (math.radians(-15), 0, 0)
            pod.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(pod, width=0.04, segments=2)
            objs.append(pod)

            # 4 Rocket tubes
            for rx in [-0.08, 0.08]:
                for rz in [0.42, 0.54]:
                    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.12, vertices=10, location=(px + rx, 0.30, rz + bob_z))
                    tube = bpy.context.active_object
                    tube.rotation_euler = (math.radians(75), 0, 0)
                    tube.data.materials.append(mat_bore)
                    objs.append(tube)

    elif wagon_type == "enemy_gunner":
        # Open-top carriage with mounted enemy soldier aiming gun
        mat_soldier = create_clay_mat(f"{name_prefix}_sol", (0.92, 0.30, 0.35, 1.0))
        mat_helmet = create_clay_mat(f"{name_prefix}_hlm", (0.28, 0.32, 0.38, 1.0))

        # Soldier Body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, -0.05, 0.42 + bob_z))
        sol_body = bpy.context.active_object
        sol_body.data.materials.append(mat_soldier)
        apply_uniform_clay_bevel(sol_body, width=0.04, segments=2)
        objs.append(sol_body)

        # Soldier Helmet
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, -0.05, 0.65 + bob_z))
        helmet = bpy.context.active_object
        helmet.scale = (1.05, 1.05, 0.85)
        helmet.data.materials.append(mat_helmet)
        apply_uniform_clay_bevel(helmet, width=0.04, segments=2)
        objs.append(helmet)

        # Mounted Heavy Machine Gun on Tripod
        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.85, vertices=12, location=(0, 0.28, 0.52 + bob_z))
        mg = bpy.context.active_object
        mg.rotation_euler = (math.radians(90), 0, 0)
        mg.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(mg, width=0.02, segments=2)
        objs.append(mg)

    return objs

# ==================== MASTER BATCH RENDER ====================
def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(2026)

    print(">>> 1. Rendering Speed Branch Tanks (P1 & P2, T1 & T2, 6 Frames)...")
    speed_configs = {
        # P1 Gold / Cyan Speed
        "player_speed_t1": {"body": (0.98, 0.82, 0.25, 1.0), "tur": (1.0, 0.88, 0.38, 1.0), "trim": (0.22, 0.78, 0.95, 1.0), "tier": 1},
        "player_speed_t2": {"body": (0.98, 0.70, 0.20, 1.0), "tur": (1.0, 0.80, 0.30, 1.0), "trim": (0.15, 0.88, 1.0, 1.0), "tier": 2},
        # P2 Mint / Orange Speed
        "player2_speed_t1": {"body": (0.35, 0.85, 0.55, 1.0), "tur": (0.45, 0.92, 0.65, 1.0), "trim": (0.98, 0.55, 0.25, 1.0), "tier": 1},
        "player2_speed_t2": {"body": (0.25, 0.78, 0.48, 1.0), "tur": (0.35, 0.86, 0.58, 1.0), "trim": (1.0, 0.45, 0.18, 1.0), "tier": 2},
    }
    for name, cfg in speed_configs.items():
        for frame in range(6):
            objs = build_speed_tank(f"{name}_f{frame}", cfg["body"], cfg["tur"], cfg["trim"], tier=cfg["tier"], frame=frame)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))
    purge_orphans()

    print(">>> 2. Rendering Heavy / Strength Branch Tanks (P1 & P2, T1 & T2, 6 Frames)...")
    heavy_configs = {
        # P1 Heavy Rust/Iron Gold
        "player_heavy_t1": {"body": (0.88, 0.48, 0.20, 1.0), "tur": (0.95, 0.58, 0.26, 1.0), "trim": (0.32, 0.30, 0.36, 1.0), "tier": 1},
        "player_heavy_t2": {"body": (0.80, 0.35, 0.18, 1.0), "tur": (0.90, 0.45, 0.22, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "tier": 2},
        # P2 Heavy Forest Armor
        "player2_heavy_t1": {"body": (0.22, 0.55, 0.35, 1.0), "tur": (0.30, 0.65, 0.42, 1.0), "trim": (0.32, 0.30, 0.36, 1.0), "tier": 1},
        "player2_heavy_t2": {"body": (0.16, 0.48, 0.28, 1.0), "tur": (0.24, 0.58, 0.36, 1.0), "trim": (0.95, 0.60, 0.22, 1.0), "tier": 2},
    }
    for name, cfg in heavy_configs.items():
        for frame in range(6):
            objs = build_heavy_tank(f"{name}_f{frame}", cfg["body"], cfg["tur"], cfg["trim"], tier=cfg["tier"], frame=frame)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))
    purge_orphans()

    print(">>> 3. Rendering Train Locomotives (Player P1 & P2, Enemy Train Boss)...")
    train_loco_configs = {
        "player_train_loco_t1": {"body": (0.95, 0.72, 0.22, 1.0), "cab": (0.28, 0.62, 0.88, 1.0), "trim": (0.32, 0.30, 0.36, 1.0), "is_enemy": False, "tier": 1},
        "player_train_loco_t2": {"body": (0.98, 0.60, 0.18, 1.0), "cab": (0.20, 0.55, 0.95, 1.0), "trim": (0.98, 0.85, 0.25, 1.0), "is_enemy": False, "tier": 2},
        "player2_train_loco_t1": {"body": (0.32, 0.75, 0.48, 1.0), "cab": (0.95, 0.55, 0.25, 1.0), "trim": (0.32, 0.30, 0.36, 1.0), "is_enemy": False, "tier": 1},
        "player2_train_loco_t2": {"body": (0.24, 0.68, 0.40, 1.0), "cab": (0.98, 0.45, 0.18, 1.0), "trim": (0.38, 0.85, 0.55, 1.0), "is_enemy": False, "tier": 2},
        # Enemy Armored Train Boss Locomotive (Dark Crimson Iron)
        "enemy_train_loco": {"body": (0.32, 0.30, 0.36, 1.0), "cab": (0.85, 0.22, 0.28, 1.0), "trim": (0.95, 0.35, 0.38, 1.0), "is_enemy": True, "tier": 2},
    }
    for name, cfg in train_loco_configs.items():
        for frame in range(6):
            objs = build_train_locomotive(f"{name}_f{frame}", cfg["body"], cfg["cab"], cfg["trim"], is_enemy=cfg["is_enemy"], tier=cfg["tier"], frame=frame)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))
    purge_orphans()

    print(">>> 4. Rendering Train Wagons (Turret, Armor, Rocket, Enemy Gunner, Enemy Spawner)...")
    wagon_configs = {
        # Player Wagons
        "train_wagon_turret": {"body": (0.95, 0.75, 0.25, 1.0), "trim": (0.28, 0.62, 0.88, 1.0), "type": "turret", "is_enemy": False},
        "train_wagon_armor": {"body": (0.92, 0.68, 0.22, 1.0), "trim": (0.35, 0.85, 0.50, 1.0), "type": "armor", "is_enemy": False},
        "train_wagon_rocket": {"body": (0.95, 0.55, 0.20, 1.0), "trim": (0.95, 0.35, 0.35, 1.0), "type": "rocket", "is_enemy": False},
        # Enemy Wagons
        "enemy_train_wagon_gunner": {"body": (0.32, 0.30, 0.36, 1.0), "trim": (0.85, 0.25, 0.28, 1.0), "type": "enemy_gunner", "is_enemy": True},
        "enemy_train_wagon_armor": {"body": (0.28, 0.26, 0.32, 1.0), "trim": (0.92, 0.30, 0.35, 1.0), "type": "armor", "is_enemy": True},
    }
    for name, cfg in wagon_configs.items():
        for frame in range(6):
            objs = build_train_carriage(f"{name}_f{frame}", cfg["body"], cfg["trim"], wagon_type=cfg["type"], is_enemy=cfg["is_enemy"], frame=frame)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))
    purge_orphans()

    print(">>> ALL RPG BRANCH & TRAIN 3D ASSETS RENDERED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
