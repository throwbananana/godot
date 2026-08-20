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
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
os.makedirs(SPRITES_TANKS, exist_ok=True)

# Common materials helper
def get_track_mat(name, col=(0.28, 0.26, 0.32, 1.0)):
    return create_clay_mat(f"{name}_trk", col, roughness=0.88)

def get_bore_mat(name):
    return create_clay_mat(f"{name}_bore", (0.08, 0.08, 0.10, 1.0), roughness=0.92)

# ==================== 1. PLAYER TIER 0: SCOUT PEBBLE TANK ====================
def build_player_tier0(frame=0, is_p2=False):
    objs = []
    pfx = f"p2_t0_{frame}" if is_p2 else f"p1_t0_{frame}"
    col_body = (0.24, 0.72, 0.42, 1.0) if is_p2 else (0.98, 0.80, 0.22, 1.0)
    col_tur = (0.40, 0.88, 0.58, 1.0) if is_p2 else (1.0, 0.86, 0.35, 1.0)
    col_trim = (0.96, 0.52, 0.24, 1.0) if is_p2 else (0.38, 0.75, 0.45, 1.0)

    mat_b = create_clay_mat(f"{pfx}_b", col_body)
    mat_t = create_clay_mat(f"{pfx}_t", col_tur)
    mat_tm = create_clay_mat(f"{pfx}_tm", col_trim)
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)
    mat_glass = create_clay_mat(f"{pfx}_gl", (0.65, 0.90, 1.0, 1.0), roughness=0.15, sss_weight=0.35)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Compact Rounded Pebble Chassis
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.72, location=(0, -0.02, 0.06 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (0.95, 1.05, 0.46)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.10, segments=3)
    objs.append(hull)

    # 2. Cute Dual Tracks with 2 Big Roadwheels each
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    for x_pos in [-0.68, 0.68]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (0.28, 1.22, 0.52)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.14, segments=3)
        objs.append(tr)

        for wy in [-0.35, 0.35]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.30, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_tm)
            apply_uniform_clay_bevel(wh, width=0.06, segments=2)
            objs.append(wh)

    # 3. Spherical Ball Turret + Glass Bubble Hatch
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0.05, 0.36 + bob_z))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.08, segments=3)
    objs.append(tur)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(0, -0.08, 0.58 + bob_z))
    dome = bpy.context.active_object
    dome.data.materials.append(mat_glass)
    bpy.ops.object.shade_smooth()
    objs.append(dome)

    # 4. Antenna on Rear Deck with Animated Sway
    ant_sway = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.08
    bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.45, vertices=8, location=(-0.25, -0.38, 0.48 + bob_z))
    ant = bpy.context.active_object
    ant.rotation_euler = (ant_sway, 0, 0)
    ant.data.materials.append(mat_tm)
    objs.append(ant)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(-0.25, -0.38 + ant_sway * 0.4, 0.72 + bob_z))
    star = bpy.context.active_object
    star.data.materials.append(mat_tm)
    bpy.ops.object.shade_smooth()
    objs.append(star)

    # 5. Peashooter Tapered Barrel with Trumpet Muzzle
    bpy.ops.mesh.primitive_cone_add(radius1=0.14, radius2=0.09, depth=0.82, location=(0, 0.52, 0.36 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(-90), 0, 0)
    gun.data.materials.append(mat_b)
    apply_uniform_clay_bevel(gun, width=0.03, segments=2)
    objs.append(gun)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.035, location=(0, 0.92, 0.36 + bob_z))
    m_ring = bpy.context.active_object
    m_ring.rotation_euler = (math.radians(90), 0, 0)
    m_ring.data.materials.append(mat_tm)
    objs.append(m_ring)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.06, vertices=12, location=(0, 0.94, 0.36 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== 2. PLAYER TIER 1: HUNTER ASSAULT WEDGE ====================
def build_player_tier1(frame=0, is_p2=False):
    objs = []
    pfx = f"p2_t1_{frame}" if is_p2 else f"p1_t1_{frame}"
    col_body = (0.18, 0.60, 0.36, 1.0) if is_p2 else (0.98, 0.58, 0.26, 1.0)
    col_tur = (0.52, 0.85, 0.40, 1.0) if is_p2 else (1.0, 0.70, 0.36, 1.0)
    col_trim = (0.96, 0.82, 0.22, 1.0) if is_p2 else (0.98, 0.38, 0.48, 1.0)

    mat_b = create_clay_mat(f"{pfx}_b", col_body)
    mat_t = create_clay_mat(f"{pfx}_t", col_tur)
    mat_tm = create_clay_mat(f"{pfx}_tm", col_trim)
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Sleek Angular Wedge Hull with Front Arrow Prow
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.02 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.30, 1.48, 0.52)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.16, segments=3)
    objs.append(hull)

    # Sharp Triangular Nose Prow
    bpy.ops.mesh.primitive_cone_add(radius1=0.62, radius2=0.06, depth=0.65, location=(0, 0.82, 0.02 + bob_z))
    prow = bpy.context.active_object
    prow.scale = (1.0, 0.5, 0.75)
    prow.rotation_euler = (math.radians(-90), 0, 0)
    prow.data.materials.append(mat_tm)
    apply_uniform_clay_bevel(prow, width=0.06, segments=2)
    objs.append(prow)

    # 2. Side Tracks
    for x_pos in [-0.75, 0.75]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (0.32, 1.50, 0.58)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.14, segments=3)
        objs.append(tr)

    # 3. Twin Diagonal Hot-Rod Exhaust Pipes on Rear Deck
    for ex in [-0.36, 0.36]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.45, vertices=12, location=(ex, -0.62, 0.35 + bob_z))
        pipe = bpy.context.active_object
        pipe.rotation_euler = (math.radians(-32), (math.radians(-15) if ex < 0 else math.radians(15)), 0)
        pipe.data.materials.append(mat_tm)
        apply_uniform_clay_bevel(pipe, width=0.02, segments=2)
        objs.append(pipe)

    # 4. Low-Profile Angular Wedge Turret
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.02, 0.38 + bob_z))
    tur = bpy.context.active_object
    tur.scale = (0.78, 0.95, 0.36)
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.12, segments=3)
    objs.append(tur)

    # 5. Long Sniper Fluted Cannon + Arrowhead Muzzle Brake
    bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.18, vertices=16, location=(0, 0.62, 0.38 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_b)
    apply_uniform_clay_bevel(gun, width=0.03, segments=2)
    objs.append(gun)

    # Arrowhead Muzzle Brake
    bpy.ops.mesh.primitive_cone_add(radius1=0.16, radius2=0.08, depth=0.22, location=(0, 1.20, 0.38 + bob_z))
    mb = bpy.context.active_object
    mb.rotation_euler = (math.radians(-90), 0, 0)
    mb.data.materials.append(mat_tm)
    apply_uniform_clay_bevel(mb, width=0.03, segments=2)
    objs.append(mb)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.06, vertices=12, location=(0, 1.30, 0.38 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== 3. PLAYER TIER 2: TWIN FORTRESS SIEGE ====================
def build_player_tier2(frame=0, is_p2=False):
    objs = []
    pfx = f"p2_t2_{frame}" if is_p2 else f"p1_t2_{frame}"
    col_body = (0.16, 0.55, 0.52, 1.0) if is_p2 else (0.38, 0.78, 0.45, 1.0)
    col_tur = (0.32, 0.78, 0.72, 1.0) if is_p2 else (0.48, 0.85, 0.55, 1.0)
    col_trim = (0.92, 0.32, 0.38, 1.0) if is_p2 else (0.98, 0.80, 0.25, 1.0)

    mat_b = create_clay_mat(f"{pfx}_b", col_body)
    mat_t = create_clay_mat(f"{pfx}_t", col_tur)
    mat_tm = create_clay_mat(f"{pfx}_tm", col_trim)
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Wide Heavy Fortress Hull with Side Stowage Boxes
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.04 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.52, 1.58, 0.58)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # Extra Wide Heavy Treads
    for x_pos in [-0.85, 0.85]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (0.38, 1.62, 0.65)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.16, segments=4)
        objs.append(tr)

    # 2. Rotating Radar Dish on Left Rear Deck
    rad_ang = frame * (2.0 * math.pi / 6.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=0.30, vertices=8, location=(-0.48, -0.52, 0.45 + bob_z))
    r_post = bpy.context.active_object
    r_post.data.materials.append(mat_tm)
    objs.append(r_post)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.06, vertices=16, location=(-0.48, -0.52, 0.62 + bob_z))
    dish = bpy.context.active_object
    dish.rotation_euler = (math.radians(35), 0, rad_ang)
    dish.data.materials.append(mat_tm)
    apply_uniform_clay_bevel(dish, width=0.03, segments=2)
    objs.append(dish)

    # 3. Gold Searchlight on Right Front Cheek
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0.48, 0.45, 0.42 + bob_z))
    sl = bpy.context.active_object
    sl.data.materials.append(mat_tm)
    bpy.ops.object.shade_smooth()
    objs.append(sl)

    # 4. Wide Dual-Turret Fortress Box
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.05, 0.42 + bob_z))
    tur = bpy.context.active_object
    tur.scale = (1.05, 0.88, 0.45)
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.14, segments=3)
    objs.append(tur)

    # 5. Parallel Dual Heavy Cannons
    for bx in [-0.26, 0.26]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=1.10, vertices=16, location=(bx, 0.62, 0.42 + bob_z))
        gun = bpy.context.active_object
        gun.rotation_euler = (math.radians(90), 0, 0)
        gun.data.materials.append(mat_b)
        apply_uniform_clay_bevel(gun, width=0.03, segments=2)
        objs.append(gun)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 1.15, 0.42 + bob_z))
        mb = bpy.context.active_object
        mb.scale = (0.24, 0.16, 0.24)
        mb.data.materials.append(mat_tm)
        apply_uniform_clay_bevel(mb, width=0.03, segments=2)
        objs.append(mb)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.06, vertices=12, location=(bx, 1.23, 0.42 + bob_z))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

    return objs

# ==================== 4. PLAYER TIER 3: PLASMA DREADNOUGHT ====================
def build_player_tier3(frame=0, is_p2=False):
    objs = []
    pfx = f"p2_t3_{frame}" if is_p2 else f"p1_t3_{frame}"
    col_body = (0.20, 0.78, 0.65, 1.0) if is_p2 else (0.28, 0.62, 0.95, 1.0)
    col_tur = (0.35, 0.88, 0.82, 1.0) if is_p2 else (0.38, 0.72, 0.98, 1.0)
    col_trim = (0.98, 0.65, 0.18, 1.0) if is_p2 else (0.98, 0.82, 0.22, 1.0)
    col_plasma = (0.45, 0.95, 1.0, 1.0) if not is_p2 else (0.40, 1.0, 0.85, 1.0)

    mat_b = create_clay_mat(f"{pfx}_b", col_body)
    mat_t = create_clay_mat(f"{pfx}_t", col_tur)
    mat_tm = create_clay_mat(f"{pfx}_tm", col_trim)
    mat_tr = get_track_mat(pfx)
    mat_plasma = create_clay_mat(f"{pfx}_pl", col_plasma, emission=col_plasma, emission_str=2.8)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # 1. Central Hover Core Platform
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.05 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.20, 1.40, 0.55)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.16, segments=4)
    objs.append(hull)

    # 2. Quad Independent Outrigger Track Pods (4 separate angled track pods!)
    for qx, qy in [(-0.80, 0.55), (0.80, 0.55), (-0.80, -0.65), (0.80, -0.65)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(qx, qy, 0.02))
        pod = bpy.context.active_object
        pod.scale = (0.32, 0.65, 0.58)
        pod.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(pod, width=0.12, segments=3)
        objs.append(pod)

        # Gold Connecting Suspension Struts
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.45, vertices=12, location=(qx * 0.55, qy, 0.12 + bob_z))
        strut = bpy.context.active_object
        strut.rotation_euler = (0, math.radians(90 if qx > 0 else -90), 0)
        strut.data.materials.append(mat_tm)
        apply_uniform_clay_bevel(strut, width=0.02, segments=2)
        objs.append(strut)

    # 3. Rear Deck Rotating Tesla Arc Reactor Ring
    t_rot = frame * (2.0 * math.pi / 6.0)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.08, location=(0, -0.55, 0.42 + bob_z))
    ring = bpy.context.active_object
    ring.rotation_euler = (math.radians(25), 0, t_rot)
    ring.data.materials.append(mat_tm)
    objs.append(ring)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, -0.55, 0.42 + bob_z))
    orb = bpy.context.active_object
    orb.data.materials.append(mat_plasma)
    bpy.ops.object.shade_smooth()
    objs.append(orb)

    # 4. Futuristic Railgun Turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=0.45, vertices=6, location=(0, 0.08, 0.44 + bob_z))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.12, segments=3)
    objs.append(tur)

    # 5. Dual Tesla Railgun Prongs with Floating Plasma Core
    for rx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, 0.65, 0.44 + bob_z))
        prong = bpy.context.active_object
        prong.scale = (0.10, 1.15, 0.18)
        prong.data.materials.append(mat_tm)
        apply_uniform_clay_bevel(prong, width=0.03, segments=2)
        objs.append(prong)

    # Floating Charging Plasma Ball between the rails
    p_pulse = 0.16 + math.sin(frame * (2.0 * math.pi / 6.0)) * 0.03
    bpy.ops.mesh.primitive_uv_sphere_add(radius=p_pulse, location=(0, 0.85, 0.44 + bob_z))
    pl_ball = bpy.context.active_object
    pl_ball.data.materials.append(mat_plasma)
    bpy.ops.object.shade_smooth()
    objs.append(pl_ball)

    return objs

# ==================== 5. ENEMY BASIC: CYCLOPS DRONE TANK ====================
def build_enemy_basic(frame=0):
    objs = []
    pfx = f"eb_{frame}"
    mat_b = create_clay_mat(f"{pfx}_b", (0.75, 0.78, 0.84, 1.0))
    mat_t = create_clay_mat(f"{pfx}_t", (0.84, 0.86, 0.90, 1.0))
    mat_tm = create_clay_mat(f"{pfx}_tm", (0.95, 0.42, 0.52, 1.0))
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)
    mat_eye = create_clay_mat(f"{pfx}_eye", (0.98, 0.25, 0.35, 1.0), emission=(0.98, 0.25, 0.35, 1.0), emission_str=2.6)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Utilitarian Boxy Trapezoid Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.02 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.25, 1.35, 0.52)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.14, segments=3)
    objs.append(hull)

    for x_pos in [-0.70, 0.70]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (0.30, 1.40, 0.56)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.14, segments=3)
        objs.append(tr)

    # 2. Smooth Dome Turret with Big Glowing Cyclops Eye
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0.02, 0.38 + bob_z))
    tur = bpy.context.active_object
    tur.scale = (1.0, 1.0, 0.65)
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.10, segments=3)
    objs.append(tur)

    # Glowing Red Optic Eye in center
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0.40, 0.38 + bob_z))
    eye = bpy.context.active_object
    eye.data.materials.append(mat_eye)
    bpy.ops.object.shade_smooth()
    objs.append(eye)

    # 3. Compact Standard Gun
    bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.92, vertices=16, location=(0, 0.58, 0.22 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_b)
    apply_uniform_clay_bevel(gun, width=0.03, segments=2)
    objs.append(gun)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.06, vertices=12, location=(0, 1.04, 0.22 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== 6. ENEMY FAST: TRIKE SPEEDSTER RAIDER ====================
def build_enemy_fast(frame=0):
    objs = []
    pfx = f"ef_{frame}"
    mat_b = create_clay_mat(f"{pfx}_b", (0.26, 0.75, 0.88, 1.0))
    mat_t = create_clay_mat(f"{pfx}_t", (0.42, 0.82, 0.95, 1.0))
    mat_tm = create_clay_mat(f"{pfx}_tm", (0.98, 0.95, 0.95, 1.0))
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)
    mat_jet = create_clay_mat(f"{pfx}_jet", (0.35, 0.88, 1.0, 1.0), emission=(0.35, 0.88, 1.0, 1.0), emission_str=3.0)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # 1. Triangular Speedster Arrowhead Chassis (Narrow front, wide rear)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.02 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.30, 1.45, 0.48)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.16, segments=3)
    objs.append(hull)

    # 2. Trike Track Architecture (Single front guide track + Dual rear outriggers!)
    # Single Front Center Track
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.55, 0.0))
    tr_f = bpy.context.active_object
    tr_f.scale = (0.32, 0.65, 0.52)
    tr_f.data.materials.append(mat_tr)
    apply_uniform_clay_bevel(tr_f, width=0.12, segments=3)
    objs.append(tr_f)

    # Dual Rear Outrigger Tracks
    for rx in [-0.75, 0.75]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, -0.45, 0.0))
        tr_r = bpy.context.active_object
        tr_r.scale = (0.28, 0.80, 0.54)
        tr_r.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr_r, width=0.12, segments=3)
        objs.append(tr_r)

    # 3. Dual Rocket Afterburner Nozzles on Tail
    jet_pulse = 0.12 + math.sin(frame * (2.0 * math.pi / 6.0)) * 0.02
    for jx in [-0.30, 0.30]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.35, vertices=12, location=(jx, -0.80, 0.08 + bob_z))
        noz = bpy.context.active_object
        noz.rotation_euler = (math.radians(90), 0, 0)
        noz.data.materials.append(mat_tm)
        apply_uniform_clay_bevel(noz, width=0.03, segments=2)
        objs.append(noz)

        bpy.ops.mesh.primitive_cone_add(radius1=jet_pulse, radius2=0.02, depth=0.45, location=(jx, -1.02, 0.08 + bob_z))
        flame = bpy.context.active_object
        flame.rotation_euler = (math.radians(-90), 0, 0)
        flame.data.materials.append(mat_jet)
        objs.append(flame)

    # 4. Sleek Needle Dart Turret
    bpy.ops.mesh.primitive_cone_add(radius1=0.46, radius2=0.15, depth=0.85, location=(0, 0.05, 0.36 + bob_z))
    tur = bpy.context.active_object
    tur.rotation_euler = (math.radians(-90), 0, 0)
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.06, segments=2)
    objs.append(tur)

    # Slender Needle Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=1.15, vertices=16, location=(0, 0.65, 0.36 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_tm)
    objs.append(gun)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.06, vertices=12, location=(0, 1.22, 0.36 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== 7. ENEMY POWER: CASEMATE SIEGE HOWITZER ====================
def build_enemy_power(frame=0):
    objs = []
    pfx = f"ep_{frame}"
    mat_b = create_clay_mat(f"{pfx}_b", (0.92, 0.32, 0.38, 1.0))
    mat_casemate = create_clay_mat(f"{pfx}_c", (0.98, 0.45, 0.48, 1.0))
    mat_tm = create_clay_mat(f"{pfx}_tm", (0.98, 0.82, 0.22, 1.0))
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)
    mat_wood = create_clay_mat(f"{pfx}_wd", (0.55, 0.35, 0.22, 1.0))

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Heavy Jagdpanzer Hull with Casemate Superstructure (Turretless Sloped Fortress!)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.05 + bob_z))
    hull = bpy.context.active_object
    hull.scale = (1.45, 1.62, 0.62)
    hull.data.materials.append(mat_b)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # Massive Sloping Fixed Casemate Box
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.12, 0.45 + bob_z))
    cas = bpy.context.active_object
    cas.scale = (1.10, 0.95, 0.48)
    cas.data.materials.append(mat_casemate)
    apply_uniform_clay_bevel(cas, width=0.14, segments=3)
    objs.append(cas)

    # 2. Side Heavy Tracks
    for x_pos in [-0.80, 0.80]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (0.35, 1.65, 0.65)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.16, segments=4)
        objs.append(tr)

    # 3. Ammo Crates Strapped on Rear Engine Deck
    for cx, cy in [(-0.35, -0.55), (0.35, -0.55)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.42 + bob_z))
        crate = bpy.context.active_object
        crate.scale = (0.35, 0.35, 0.22)
        crate.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(crate, width=0.03, segments=2)
        objs.append(crate)

    # 4. GIGANTIC Super-Bore Siege Howitzer
    # Reinforced Ball Mantlet
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(0, 0.58, 0.45 + bob_z))
    mant = bpy.context.active_object
    mant.data.materials.append(mat_tm)
    bpy.ops.object.shade_smooth()
    objs.append(mant)

    # Massive Thick Cannon Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=1.15, vertices=16, location=(0, 0.72, 0.45 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_b)
    apply_uniform_clay_bevel(gun, width=0.04, segments=2)
    objs.append(gun)

    # Massive Squared Muzzle Brake
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 1.25, 0.45 + bob_z))
    mb = bpy.context.active_object
    mb.scale = (0.42, 0.22, 0.42)
    mb.data.materials.append(mat_tm)
    apply_uniform_clay_bevel(mb, width=0.05, segments=2)
    objs.append(mb)

    # Giant Gun Bore Hole
    bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.08, vertices=16, location=(0, 1.36, 0.45 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== 8. ENEMY ARMOR: TURTLE CARAPACE HEAVY TANK ====================
def build_enemy_armor(frame=0):
    objs = []
    pfx = f"ea_{frame}"
    mat_b = create_clay_mat(f"{pfx}_b", (0.28, 0.62, 0.38, 1.0))
    mat_t = create_clay_mat(f"{pfx}_t", (0.38, 0.72, 0.48, 1.0))
    mat_tm = create_clay_mat(f"{pfx}_tm", (0.90, 0.85, 0.35, 1.0))
    mat_era = create_clay_mat(f"{pfx}_era", (0.85, 0.75, 0.30, 1.0))
    mat_tr = get_track_mat(pfx)
    mat_bore = get_bore_mat(pfx)

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012

    # 1. Heavy Turtle Dome Carapace (Curved armor completely shrouding the chassis!)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.92, location=(0, -0.02, 0.08 + bob_z))
    turtle = bpy.context.active_object
    turtle.scale = (0.95, 1.05, 0.52)
    turtle.data.materials.append(mat_b)
    apply_uniform_clay_bevel(turtle, width=0.16, segments=4)
    objs.append(turtle)

    # Exposed Track Bottoms
    for x_pos in [-0.78, 0.78]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, -0.08))
        tr = bpy.context.active_object
        tr.scale = (0.35, 1.55, 0.45)
        tr.data.materials.append(mat_tr)
        apply_uniform_clay_bevel(tr, width=0.14, segments=3)
        objs.append(tr)

    # 2. Explosive Reactive Armor (ERA) Clay Bricks over Front Glacis
    for ex in [-0.42, 0.0, 0.42]:
        for ey in [0.45, 0.65]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ex, ey, 0.18 + bob_z))
            brick = bpy.context.active_object
            brick.scale = (0.24, 0.16, 0.10)
            brick.rotation_euler = (math.radians(-25), 0, 0)
            brick.data.materials.append(mat_era)
            apply_uniform_clay_bevel(brick, width=0.02, segments=2)
            objs.append(brick)

    # 3. Cast Iron Low Ball Turret
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.52, location=(0, 0.02, 0.40 + bob_z))
    tur = bpy.context.active_object
    tur.scale = (1.0, 0.95, 0.55)
    tur.data.materials.append(mat_t)
    apply_uniform_clay_bevel(tur, width=0.12, segments=3)
    objs.append(tur)

    # Heavy Cast Steel Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.52, minor_radius=0.06, location=(0, 0.02, 0.32 + bob_z))
    t_ring = bpy.context.active_object
    t_ring.data.materials.append(mat_tm)
    objs.append(t_ring)

    # 4. Stubby Reinforced Heavy Cannon
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.95, vertices=16, location=(0, 0.55, 0.40 + bob_z))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_b)
    apply_uniform_clay_bevel(gun, width=0.04, segments=2)
    objs.append(gun)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.06, vertices=12, location=(0, 1.02, 0.40 + bob_z))
    bore = bpy.context.active_object
    bore.rotation_euler = (math.radians(90), 0, 0)
    bore.data.materials.append(mat_bore)
    objs.append(bore)

    return objs

# ==================== MASTER BATCH RENDERER ====================
def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(3000)

    print(">>> RENDERING 8 RADICALLY DISTINCT TANK ARCHITECTURES (6 FRAMES EACH) <<<")

    # 1P Tiers
    p1_builders = {
        "player_tier0": build_player_tier0,
        "player_tier1": build_player_tier1,
        "player_tier2": build_player_tier2,
        "player_tier3": build_player_tier3,
    }
    for name, builder in p1_builders.items():
        print(f"  Rendering {name} (6 frames)...")
        for f in range(6):
            objs = builder(f, is_p2=False)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{f}.png"))

    # 2P Tiers
    p2_builders = {
        "player2_tier0": build_player_tier0,
        "player2_tier1": build_player_tier1,
        "player2_tier2": build_player_tier2,
        "player2_tier3": build_player_tier3,
    }
    for name, builder in p2_builders.items():
        print(f"  Rendering {name} (6 frames)...")
        for f in range(6):
            objs = builder(f, is_p2=True)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{f}.png"))

    # Enemies
    enemies = {
        "enemy_basic": build_enemy_basic,
        "enemy_fast": build_enemy_fast,
        "enemy_power": build_enemy_power,
        "enemy_armor": build_enemy_armor,
    }
    for name, builder in enemies.items():
        print(f"  Rendering {name} (6 frames)...")
        for f in range(6):
            objs = builder(f)
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{f}.png"))

    print(">>> ALL 72 DIVERSE TANK FRAMES RENDERED SUCCESSFULLY! <<<")

if __name__ == "__main__":
    main()
