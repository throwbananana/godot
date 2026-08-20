import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

# 渲染管线 (色彩空间/视图变换/灯光标定/黏土材质/倒角抖动) 统一在 sokpop_common,
# 本文件只负责建模。改画风请改 sokpop_common, 不要在这里再复制一份。
from sokpop_common import (  # noqa: E402
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    reset_jitter_seed,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
    MAX_ASSET_RADIUS,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
BLENDER_SAVE = os.path.join(PROJECT_DIR, "assets", "blender", "tank_battle_assets.blend")

for folder in [SPRITES_TANKS, SPRITES_TILES, SPRITES_EFFECTS, SPRITES_POWERUPS, SPRITES_BUILDINGS, SPRITES_MAP, SPRITES_UI]:
    os.makedirs(folder, exist_ok=True)

def create_3d_star(r_out=1.15, r_in=0.52, depth=0.30, z_pos=0.0):
    mesh = bpy.data.meshes.new("StarMesh")
    obj = bpy.data.objects.new("StarObj", mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    for z in [-depth/2.0 + z_pos, depth/2.0 + z_pos]:
        for i in range(10):
            ang = i * (math.pi / 5.0) - math.pi / 2.0
            r = r_out if i % 2 == 0 else r_in
            verts.append((math.cos(ang)*r, math.sin(ang)*r, z))

    verts.append((0, 0, -depth/2.0 + z_pos))
    verts.append((0, 0, depth/2.0 + z_pos))

    faces = []
    for i in range(10):
        faces.append((20, (i+1)%10, i))
    for i in range(10):
        faces.append((21, 10 + i, 10 + (i+1)%10))
    for i in range(10):
        next_i = (i+1)%10
        faces.append((i, next_i, 10 + next_i, 10 + i))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return obj

def create_wavy_ribbon(name, y_base, amp, freq, phase, width_y=0.34, height_z=0.08, z_base=0.10, x_min=-1.32, x_max=1.32, steps=36, taper=True):
    """Generates a continuous smooth sinusoidal wavy ribbon of clay across the tile."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    for i in range(steps + 1):
        t = i / float(steps)
        x = x_min + t * (x_max - x_min)
        y_center = y_base + amp * math.sin(x * freq + phase)
        dy = amp * freq * math.cos(x * freq + phase)
        length = math.hypot(1.0, dy)
        nx = -dy / length
        ny = 1.0 / length

        # Smooth taper envelope at ends so ribbon stays neatly inside tile
        env = min(1.0, math.sin(t * math.pi) * 1.8) if taper else 1.0
        w_cur = width_y * env
        h_cur = height_z * max(0.4, env)

        half_w = w_cur * 0.5
        z_top = z_base + h_cur * 0.5
        z_bot = z_base - h_cur * 0.5

        # Cross section vertices
        lx = x + nx * half_w
        ly = y_center + ny * half_w
        rx = x - nx * half_w
        ry = y_center - ny * half_w

        verts.append((lx, ly, z_bot))  # 0: bot-left
        verts.append((lx, ly, z_top))  # 1: top-left
        verts.append((rx, ry, z_top))  # 2: top-right
        verts.append((rx, ry, z_bot))  # 3: bot-right

    faces = []
    for i in range(steps):
        v0 = i * 4
        v1 = (i + 1) * 4
        faces.append((v0 + 0, v1 + 0, v1 + 1, v0 + 1))  # Left side
        faces.append((v0 + 1, v1 + 1, v1 + 2, v0 + 2))  # Top surface
        faces.append((v0 + 2, v1 + 2, v1 + 3, v0 + 3))  # Right side
        faces.append((v0 + 3, v1 + 3, v1 + 0, v0 + 0))  # Bottom surface

    # End caps
    faces.append((0, 3, 2, 1))
    last_v = steps * 4
    faces.append((last_v + 1, last_v + 2, last_v + 3, last_v + 0))

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    # Apply light subdivision for organic clay smoothness
    sub = obj.modifiers.new(name="Subsurf", type='SUBSURF')
    sub.levels = 1
    sub.render_levels = 1

    return obj

def create_lily_pad(name, radius=0.44, depth=0.05, notch_angle=math.radians(35), z_pos=0.14, steps=28):
    """Creates a circular clay lily pad with an authentic V-cut notch and gentle dished curvature."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    verts = []
    z_bot = z_pos - depth * 0.5
    z_top = z_pos + depth * 0.5
    # Center vertices slightly lower for gentle cupping
    verts.append((0.0, 0.0, z_bot - 0.01))  # 0: center bottom
    verts.append((0.0, 0.0, z_top - 0.01))  # 1: center top

    start_ang = notch_angle * 0.5
    end_ang = 2.0 * math.pi - notch_angle * 0.5
    for i in range(steps + 1):
        ang = start_ang + (i / float(steps)) * (end_ang - start_ang)
        x = math.cos(ang) * radius
        y = math.sin(ang) * radius
        verts.append((x, y, z_bot))  # 2 + i*2 + 0
        verts.append((x, y, z_top))  # 2 + i*2 + 1

    faces = []
    for i in range(steps):
        b0 = 2 + i * 2
        t0 = b0 + 1
        b1 = 2 + (i + 1) * 2
        t1 = b1 + 1
        faces.append((1, t0, t1))          # Top fan
        faces.append((0, b1, b0))          # Bottom fan
        faces.append((b0, b1, t1, t0))      # Outer rim

    # Notch edge walls
    first_b = 2
    first_t = 3
    last_b = 2 + steps * 2
    last_t = last_b + 1
    faces.append((0, 1, first_t, first_b))  # Start notch wall
    faces.append((0, last_b, last_t, 1))    # End notch wall

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    sub = obj.modifiers.new(name="Subsurf", type='SUBSURF')
    sub.levels = 1
    sub.render_levels = 1

    return obj

# ==================== 1. SOKPOP TANKS ====================

def build_sokpop_tank(name_prefix, col_body, col_turret, col_trim,
                      barrel_count=1, barrel_len=0.95, barrel_thick=0.19,
                      is_heavy=False, is_plasma=False, frame=0):
    objs = []
    mat_body = create_clay_mat(f"{name_prefix}_b", col_body)
    mat_turret = create_clay_mat(f"{name_prefix}_t", col_turret)
    mat_track = create_clay_mat(f"{name_prefix}_tr", (0.32, 0.30, 0.36, 1.0), roughness=0.85)
    mat_trim = create_clay_mat(f"{name_prefix}_tm", col_trim)
    mat_eyes = create_clay_mat(f"{name_prefix}_ey", (0.15, 0.15, 0.2, 1.0), roughness=0.3)
    mat_bore = create_clay_mat(f"{name_prefix}_bore", (0.10, 0.10, 0.14, 1.0), roughness=0.9)
    mat_glow = create_clay_mat(f"{name_prefix}_gl", (0.35, 0.9, 1.0, 1.0), emission=(0.35, 0.9, 1.0, 1.0), emission_str=3.0)

    w = 1.45 if is_heavy else 1.3
    l = 1.55 if is_heavy else 1.4
    tw = 0.38 if is_heavy else 0.34
    tx = w * 0.5 + tw * 0.5 - 0.04
    tl = l * 1.1

    # 1. Main Hull with subtle chassis suspension bob
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.012
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.56)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # 2. Nose Wedge & Fender
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.42, depth=0.48, vertices=16, location=(0, l*0.42, 0.04 + bob_z))
    nose = bpy.context.active_object
    nose.rotation_euler = (0, math.radians(90), 0)
    nose.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nose, width=0.1, segments=3)
    objs.append(nose)

    # 3. Headlights
    for hx in [-w*0.28, w*0.28]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(hx, l*0.5, 0.12 + bob_z))
        hl = bpy.context.active_object
        hl.data.materials.append(mat_eyes)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

    # 4. Tracks & Wheels
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.6)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.16, segments=4)
        objs.append(tr)

        # 3 Hubcap Roadwheels with rotating rim studs
        wheel_rot = (frame / 6.0) * (2.0 * math.pi)
        for wy in [-0.45, 0.0, 0.45]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            apply_uniform_clay_bevel(wh, width=0.08, segments=3)
            objs.append(wh)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(x_pos + (0.08 if x_pos > 0 else -0.08), wy, 0))
            hub = bpy.context.active_object
            hub.data.materials.append(mat_body)
            bpy.ops.object.shade_smooth()
            objs.append(hub)

            # 3 Rotating Wheel Bolts/Studs per wheel
            for b_i in range(3):
                b_ang = wheel_rot + b_i * (2.0 * math.pi / 3.0)
                b_y = wy + math.sin(b_ang) * 0.14
                b_z = math.cos(b_ang) * 0.14
                b_x = x_pos + (0.09 if x_pos > 0 else -0.09)
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.032, location=(b_x, b_y, b_z))
                w_bolt = bpy.context.active_object
                w_bolt.data.materials.append(mat_trim)
                bpy.ops.object.shade_smooth()
                objs.append(w_bolt)

        # 6-Frame Continuous Tread Teeth animation offset
        num_treads = 6
        tread_spacing = (tl * 0.84) / float(num_treads)
        offset = (frame / 6.0) * tread_spacing
        for i in range(num_treads):
            y_pos = -tl*0.42 + (i / float(num_treads - 1)) * (tl * 0.84) + offset
            if y_pos > tl * 0.46: y_pos -= tl * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=tw*1.05, vertices=12, location=(x_pos, y_pos, 0.32))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            apply_uniform_clay_bevel(tread, width=0.04, segments=2)
            objs.append(tread)

    # 5. Turret Dome
    tsize = 0.92 if is_heavy else 0.82
    bpy.ops.mesh.primitive_uv_sphere_add(radius=tsize*0.58, location=(0, -0.06, 0.52 + bob_z))
    turret = bpy.context.active_object
    turret.scale = (1.0, 1.0, 0.75)
    turret.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(turret)

    # 6. Hatch & Periscope
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.15, vertices=16, location=(0, -0.16, 0.82))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(hatch, width=0.08, segments=3)
    objs.append(hatch)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.22, 0.06, 0.80))
    peri = bpy.context.active_object
    peri.scale = (0.16, 0.14, 0.16)
    peri.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(peri, width=0.04, segments=2)
    objs.append(peri)

    # 7. Cannons & Hollow Muzzle Bores
    if barrel_count == 1:
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, vertices=16, location=(0, 0.32 + barrel_len/2.0, 0.52))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_turret)
        apply_uniform_clay_bevel(barrel, width=0.06, segments=3)
        objs.append(barrel)

        bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.35, minor_radius=0.08, location=(0, 0.32 + barrel_len, 0.52))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.65, depth=0.12, vertices=12, location=(0, 0.32 + barrel_len + 0.02, 0.52))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

        if is_plasma:
            for py in [0.75, 1.15]:
                bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.4, minor_radius=0.05, location=(0, py, 0.52))
                ring = bpy.context.active_object
                ring.rotation_euler = (math.radians(90), 0, 0)
                ring.data.materials.append(mat_glow)
                bpy.ops.object.shade_smooth()
                objs.append(ring)

    elif barrel_count == 2:
        for bx in [-0.24, 0.24]:
            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.85, depth=barrel_len, vertices=16, location=(bx, 0.32 + barrel_len/2.0, 0.52))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_turret)
            apply_uniform_clay_bevel(barrel, width=0.05, segments=3)
            objs.append(barrel)

            bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.15, minor_radius=0.06, location=(bx, 0.32 + barrel_len, 0.52))
            muzzle = bpy.context.active_object
            muzzle.rotation_euler = (math.radians(90), 0, 0)
            muzzle.data.materials.append(mat_trim)
            bpy.ops.object.shade_smooth()
            objs.append(muzzle)

            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.55, depth=0.10, vertices=12, location=(bx, 0.32 + barrel_len + 0.02, 0.52))
            bore = bpy.context.active_object
            bore.rotation_euler = (math.radians(90), 0, 0)
            bore.data.materials.append(mat_bore)
            objs.append(bore)

    return objs

# ==================== 2. SOKPOP TILES ====================

def build_sokpop_brick():
    objs = []
    mat_clay = create_clay_mat("m_ub_c", (0.92, 0.48, 0.28, 1.0))
    mat_cream = create_clay_mat("m_ub_m", (0.94, 0.90, 0.82, 1.0))

    # 1. Full-Bleed Mortar Base Plate (3.34 units -> 0px gap between adjacent tiles)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.20)
    base.data.materials.append(mat_cream)
    apply_uniform_clay_bevel(base, width=0.08, segments=3, jitter=0.0)
    objs.append(base)

    # 2. 4 Rows of Clay Bricks spanning edge-to-edge
    row_configs = [
        [(-0.84, 1.54), (0.84, 1.54)],
        [(-1.26, 0.70), (0.0, 1.54), (1.26, 0.70)],
        [(-0.84, 1.54), (0.84, 1.54)],
        [(-1.26, 0.70), (0.0, 1.54), (1.26, 0.70)],
    ]
    y_coords = [-1.22, -0.41, 0.41, 1.22]
    for r_idx, row in enumerate(row_configs):
        y = y_coords[r_idx]
        for (x, w_size) in row:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.12))
            b = bpy.context.active_object
            b.scale = (w_size, 0.62, 0.28)
            b.data.materials.append(mat_clay)
            apply_uniform_clay_bevel(b, width=0.08, segments=3, jitter=0.012)
            objs.append(b)
    return objs

def build_sokpop_steel():
    objs = []
    mat_plate = create_clay_mat("m_us_p", (0.78, 0.82, 0.88, 1.0))
    mat_gold = create_clay_mat("m_us_g", (0.95, 0.78, 0.22, 1.0))
    mat_stripe = create_clay_mat("m_us_s", (0.95, 0.72, 0.18, 1.0))

    # 1. Full-Bleed Steel Base Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.35)
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.12, segments=4, jitter=0.0)
    objs.append(plate)

    # 2. Reinforcement Cross Ribs
    for (sx, sy) in [(TILE_FULL_BLEED, 0.46), (0.46, TILE_FULL_BLEED)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18))
        rib = bpy.context.active_object
        rib.scale = (sx, sy, 0.12)
        rib.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(rib, width=0.06, segments=2, jitter=0.0)
        objs.append(rib)

    # 3. Center Gold Insignia Boss
    bpy.ops.mesh.primitive_cylinder_add(radius=0.75, depth=0.18, vertices=16, location=(0, 0, 0.22))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_stripe)
    apply_uniform_clay_bevel(inner, width=0.08, segments=3, jitter=0.0)
    objs.append(inner)

    # 4. Corner Rivet Bolts
    for rx in [-1.25, 1.25]:
        for ry in [-1.25, 1.25]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(rx, ry, 0.20))
            bolt = bpy.context.active_object
            bolt.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(bolt)
    return objs

def build_sokpop_water(frame=0):
    objs = []
    mat_deep_water   = create_clay_mat("m_uw_dw", (0.12, 0.40, 0.68, 1.0), roughness=0.18, sss_weight=0.22)
    mat_mid_water    = create_clay_mat("m_uw_mw", (0.22, 0.64, 0.88, 1.0), roughness=0.16, sss_weight=0.24)
    mat_light_water  = create_clay_mat("m_uw_lw", (0.46, 0.88, 0.98, 1.0), roughness=0.14, sss_weight=0.26)
    mat_foam         = create_clay_mat("m_uw_fm", (0.96, 0.98, 1.0, 1.0), roughness=0.40)
    mat_bubble       = create_clay_mat("m_uw_bub", (0.88, 0.96, 1.0, 1.0), roughness=0.10)

    # 1. Full-Bleed Deep River Basin Base Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.06))
    base = bpy.context.active_object
    base.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.32)
    base.data.materials.append(mat_deep_water)
    apply_uniform_clay_bevel(base, width=0.10, segments=3, jitter=0.0)
    objs.append(base)

    # 2. 5-Tier Seamless Multi-Tile River Wave Ribbons
    # Frequency is calibrated exactly to 2 full periods across ORTHO_SCALE_DEFAULT (3.30)
    frame_phase = frame * (2.0 * math.pi / 6.0)
    tile_period = ORTHO_SCALE_DEFAULT  # 3.30
    freq = (2.0 * math.pi * 2.0) / tile_period  # exactly 2 periods per tile width -> seamless across borders

    half_span = TILE_FULL_BLEED * 0.5

    wave_tiers = [
        # (name, y_base, amp, phase_offset, width_y, height_z, z_base)
        ("WaveRow0",  1.26, 0.15, 0.0,  0.54, 0.11, 0.08),
        ("WaveRow1",  0.63, 0.18, 1.3,  0.58, 0.13, 0.10),
        ("WaveRow2",  0.00, 0.20, 2.6,  0.60, 0.14, 0.11),
        ("WaveRow3", -0.63, 0.18, 3.9,  0.58, 0.13, 0.10),
        ("WaveRow4", -1.26, 0.15, 5.2,  0.54, 0.11, 0.08),
    ]

    for name, y_base, amp, row_phase, wy, hz, zb in wave_tiers:
        cur_phase = row_phase + frame_phase

        # Main wave body ribbon spanning full tile width without tapering
        wv = create_wavy_ribbon(f"{name}_Body", y_base, amp, freq, cur_phase,
                                width_y=wy, height_z=hz, z_base=zb,
                                x_min=-half_span, x_max=half_span, steps=44, taper=False)
        wv.data.materials.append(mat_mid_water)
        objs.append(wv)

        # Upper wave crest highlight ribbon
        wv_crest = create_wavy_ribbon(f"{name}_Crest", y_base, amp, freq, cur_phase,
                                      width_y=wy * 0.38, height_z=hz * 0.60, z_base=zb + hz * 0.32,
                                      x_min=-half_span, x_max=half_span, steps=44, taper=False)
        wv_crest.data.materials.append(mat_light_water)
        objs.append(wv_crest)

        # Delicate white clay foam caps along the wave peaks inside the tile
        for peak_k in [0, 1]:
            target_ang = (0.5 + 2.0 * peak_k) * math.pi - cur_phase
            peak_x = target_ang / freq
            while peak_x < -half_span: peak_x += tile_period
            while peak_x > half_span:  peak_x -= tile_period

            flen = 0.52
            if -1.30 <= peak_x <= 1.30:
                fm = create_wavy_ribbon(f"{name}_Foam_{peak_k}", y_base, amp, freq, cur_phase,
                                        width_y=0.065, height_z=0.04, z_base=zb + hz * 0.45,
                                        x_min=peak_x - flen * 0.5, x_max=peak_x + flen * 0.5, steps=16, taper=True)
                fm.data.materials.append(mat_foam)
                objs.append(fm)

                # Sparkling bubble droplets beside foam cap
                bx = peak_x + flen * 0.30
                by = y_base + amp * math.sin(bx * freq + cur_phase) + 0.04
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(bx, by, zb + hz * 0.48))
                bub = bpy.context.active_object
                bub.data.materials.append(mat_bubble)
                bpy.ops.object.shade_smooth()
                objs.append(bub)

    return objs

def build_sokpop_trees():
    objs = []
    mat_matcha = create_clay_mat("m_ut_m", (0.34, 0.72, 0.30, 1.0))
    mat_lime = create_clay_mat("m_ut_l", (0.50, 0.82, 0.34, 1.0))
    mat_trunk = create_clay_mat("m_ut_tr", (0.45, 0.28, 0.18, 1.0))
    mat_berry = create_clay_mat("m_ut_b", (0.92, 0.30, 0.40, 1.0))

    # 1. Exposed Wooden Trunk/Stump Base
    for (tx, ty) in [(-0.65, -0.65), (0.65, 0.65)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.45, vertices=12, location=(tx, ty, 0.08))
        trunk = bpy.context.active_object
        trunk.data.materials.append(mat_trunk)
        apply_uniform_clay_bevel(trunk, width=0.06, segments=2)
        objs.append(trunk)

    # 2. Rich Layered Canopy Volumes spanning full footprint
    spheres = [
        # Base canopy layer (dark matcha)
        (-0.95, -0.95, 0.38, 0.88, mat_matcha), (0.95, -0.95, 0.38, 0.88, mat_matcha),
        (-0.95, 0.95, 0.38, 0.88, mat_matcha), (0.95, 0.95, 0.38, 0.88, mat_matcha),
        # Mid-tier lush foliage (vibrant lime)
        (-0.85, 0.0, 0.50, 0.85, mat_lime), (0.85, 0.0, 0.50, 0.85, mat_lime),
        (0.0, -0.85, 0.50, 0.85, mat_lime), (0.0, 0.85, 0.50, 0.85, mat_lime),
        # Crown summit dome
        (0.0, 0.0, 0.82, 1.15, mat_lime),
        (-0.25, 0.25, 1.12, 0.70, mat_matcha)
    ]
    for x, y, z, r, m in spheres:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(m)
        bpy.ops.object.shade_smooth()
        objs.append(b)

    # 3. Clustered Berry Bunches
    berry_clusters = [
        (-0.42, -0.32, 1.25), (-0.32, -0.42, 1.22),
        (0.52, 0.32, 1.18), (0.42, 0.45, 1.20),
        (0.12, -0.65, 1.12),
        (-0.22, 0.62, 1.28)
    ]
    for bx, by, bz in berry_clusters:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(bx, by, bz))
        berry = bpy.context.active_object
        berry.data.materials.append(mat_berry)
        bpy.ops.object.shade_smooth()
        objs.append(berry)

    return objs

def build_sokpop_ice():
    objs = []
    mat_sugar = create_clay_mat("m_ui_s", (0.76, 0.90, 0.96, 1.0), roughness=0.22, sss_weight=0.12)
    mat_fracture = create_clay_mat("m_ui_fr", (0.60, 0.78, 0.88, 1.0))
    mat_sparkle = create_clay_mat("m_ui_sp", (0.95, 0.98, 1.0, 1.0))

    # 1. Full-Bleed Main Ice Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.30)
    ice.data.materials.append(mat_sugar)
    apply_uniform_clay_bevel(ice, width=0.10, segments=3, jitter=0.0)
    objs.append(ice)

    # 2. Crystalline Fracture Veins
    fractures = [
        (-0.65, -0.55, 1.05, 28),
        (0.55, 0.62, 0.92, -35),
        (-0.35, 0.78, 0.75, 55),
        (0.70, -0.65, 0.65, -65)
    ]
    for (px, py, l, angle) in fractures:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 0.16))
        s = bpy.context.active_object
        s.scale = (l, 0.08, 0.04)
        s.rotation_euler = (0, 0, math.radians(angle))
        s.data.materials.append(mat_fracture)
        apply_uniform_clay_bevel(s, width=0.02, segments=2, jitter=0.0)
        objs.append(s)

    # 3. Four-pointed Glint Sparkles
    for (gx, gy) in [(-0.35, 0.25), (0.50, -0.20)]:
        star = create_3d_star(r_out=0.32, r_in=0.12, depth=0.08, z_pos=0.18)
        star.location = (gx, gy, 0)
        star.data.materials.append(mat_sparkle)
        apply_uniform_clay_bevel(star, width=0.02, segments=2)
        objs.append(star)

    return objs

def build_sokpop_eagle(destroyed=False):
    objs = []
    mat_ped = create_clay_mat("m_ue_p", (0.85, 0.80, 0.74, 1.0) if not destroyed else (0.42, 0.40, 0.45, 1.0))
    mat_chick = create_clay_mat("m_ue_c", (0.98, 0.82, 0.22, 1.0))
    mat_beak = create_clay_mat("m_ue_b", (0.98, 0.52, 0.15, 1.0))
    mat_crown = create_clay_mat("m_ue_cr", (0.98, 0.76, 0.15, 1.0))
    mat_ruby = create_clay_mat("m_ue_rb", (0.92, 0.20, 0.30, 1.0))
    mat_blush = create_clay_mat("m_ue_bl", (0.98, 0.42, 0.52, 1.0))
    mat_eyes = create_clay_mat("m_ue_e", (0.15, 0.15, 0.2, 1.0), roughness=0.2)
    mat_sparkle = create_clay_mat("m_ue_sp", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.35, vertices=16, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.data.materials.append(mat_ped)
    apply_uniform_clay_bevel(ped, width=0.12, segments=3)
    objs.append(ped)

    if not destroyed:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(0, 0.05, 0.65))
        body = bpy.context.active_object
        body.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        for sign in [-1, 1]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(sign * 0.75, 0.05, 0.65))
            w = bpy.context.active_object
            w.scale = (0.5, 1.0, 0.7)
            w.rotation_euler = (0, 0, math.radians(sign * -25))
            w.data.materials.append(mat_chick)
            bpy.ops.object.shade_smooth()
            objs.append(w)

        bpy.ops.mesh.primitive_cone_add(radius1=0.22, depth=0.35, location=(0, 0.85, 0.65))
        beak = bpy.context.active_object
        beak.rotation_euler = (math.radians(90), 0, 0)
        beak.data.materials.append(mat_beak)
        apply_uniform_clay_bevel(beak, width=0.06, segments=2)
        objs.append(beak)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.22, vertices=12, location=(0, 0.05, 1.42))
        crown = bpy.context.active_object
        crown.data.materials.append(mat_crown)
        apply_uniform_clay_bevel(crown, width=0.04, segments=2)
        objs.append(crown)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, 0.32, 1.45))
        gem = bpy.context.active_object
        gem.data.materials.append(mat_ruby)
        bpy.ops.object.shade_smooth()
        objs.append(gem)

        for sx in [-0.28, 0.28]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(sx, 0.72, 0.82))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_eyes)
            bpy.ops.object.shade_smooth()
            objs.append(eye)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx + 0.04, 0.82, 0.88))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_sparkle)
            bpy.ops.object.shade_smooth()
            objs.append(sp)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(sx * 1.35, 0.68, 0.62))
            bl = bpy.context.active_object
            bl.data.materials.append(mat_blush)
            bpy.ops.object.shade_smooth()
            objs.append(bl)
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.6, -0.3, 0.3, 0.5), (0.5, 0.3, 0.3, 0.55), (0, 0.1, 0.35, 0.65)]):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=s*0.8, location=(rx, ry, rz))
            rub = bpy.context.active_object
            rub.data.materials.append(mat_ped)
            bpy.ops.object.shade_smooth()
            objs.append(rub)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.20, vertices=12, location=(0.4, -0.4, 0.25))
        fc = bpy.context.active_object
        fc.rotation_euler = (math.radians(35), math.radians(20), math.radians(-45))
        fc.data.materials.append(mat_crown)
        apply_uniform_clay_bevel(fc, width=0.04, segments=2)
        objs.append(fc)

    return objs

# ==================== 3. SOKPOP BUILDINGS ====================

def build_sokpop_turret_base():
    objs = []
    mat_b = create_clay_mat("m_ubld_tb", (0.35, 0.38, 0.45, 1.0))
    mat_plate = create_clay_mat("m_ubld_tp", (0.50, 0.55, 0.62, 1.0))
    mat_r = create_clay_mat("m_ubld_tr", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.0)
    mat_gold = create_clay_mat("m_ubld_tg_bolt", (0.95, 0.78, 0.22, 1.0))

    # 1. Octagonal Anchor Base Plate
    bpy.ops.mesh.primitive_cylinder_add(radius=1.22, depth=0.18, vertices=8, location=(0, 0, -0.04))
    b = bpy.context.active_object
    b.data.materials.append(mat_b)
    apply_uniform_clay_bevel(b, width=0.08, segments=3)
    objs.append(b)

    # 4 Corner Anchor Feet with Bolts
    for (fx, fy) in [(-0.95, -0.95), (0.95, -0.95), (-0.95, 0.95), (0.95, 0.95)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(fx, fy, 0.04))
        foot = bpy.context.active_object
        foot.scale = (0.36, 0.36, 0.14)
        foot.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(foot, width=0.04, segments=2)
        objs.append(foot)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(fx, fy, 0.12))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(bolt)

    # 2. Turntable Ring & Glowing Track
    bpy.ops.mesh.primitive_cylinder_add(radius=0.98, depth=0.18, vertices=20, location=(0, 0, 0.08))
    ring_mount = bpy.context.active_object
    ring_mount.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(ring_mount, width=0.06, segments=3)
    objs.append(ring_mount)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.07, location=(0, 0, 0.18))
    r = bpy.context.active_object
    r.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(r)

    return objs

def build_sokpop_turret_gun():
    objs = []
    mat_g = create_clay_mat("m_ubld_tg", (0.32, 0.62, 0.92, 1.0))
    mat_mantlet = create_clay_mat("m_ubld_tmantlet", (0.26, 0.48, 0.75, 1.0))
    mat_m = create_clay_mat("m_ubld_tm", (0.98, 0.80, 0.22, 1.0))
    mat_bore = create_clay_mat("m_ubld_tbore", (0.10, 0.10, 0.14, 1.0))
    mat_optic = create_clay_mat("m_ubld_toptic", (0.98, 0.35, 0.45, 1.0), emission=(0.98, 0.35, 0.45, 1.0), emission_str=2.0)

    # 1. Main Dome (EXACT CENTERED PIVOT AT (0, 0, 0.2))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0, 0.2))
    d = bpy.context.active_object
    d.scale = (1.0, 1.0, 0.85)
    d.data.materials.append(mat_g)
    bpy.ops.object.shade_smooth()
    objs.append(d)

    # 2. Top Hatch
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.12, vertices=16, location=(0, -0.10, 0.74))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_m)
    apply_uniform_clay_bevel(hatch, width=0.04, segments=2)
    objs.append(hatch)

    # 3. Optical Targeting Sensor / Eye
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0.50, 0.55))
    eye = bpy.context.active_object
    eye.data.materials.append(mat_optic)
    bpy.ops.object.shade_smooth()
    objs.append(eye)

    # 4. Gun Mantlet (Protective recoil collar block spanning the front)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.45, 0.20))
    mantlet = bpy.context.active_object
    mantlet.scale = (0.72, 0.32, 0.36)
    mantlet.data.materials.append(mat_mantlet)
    apply_uniform_clay_bevel(mantlet, width=0.06, segments=3)
    objs.append(mantlet)

    # 5. Dual Cannons emerging cleanly from Mantlet
    for bx in [-0.22, 0.22]:
        # Barrel
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.05, vertices=16, location=(bx, 0.60, 0.20))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_g)
        apply_uniform_clay_bevel(barrel, width=0.04, segments=2)
        objs.append(barrel)

        # Recoil Collar Ring at the base of the barrel
        bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.04, location=(bx, 0.52, 0.20))
        rc = bpy.context.active_object
        rc.rotation_euler = (math.radians(90), 0, 0)
        rc.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(rc)

        # Muzzle Brake
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.06, location=(bx, 1.12, 0.20))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        # Bore Hole
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.10, vertices=12, location=(bx, 1.14, 0.20))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

    return objs

def build_sokpop_fortified_wall():
    objs = []
    mat_wall = create_clay_mat("m_ubld_w", (0.36, 0.42, 0.50, 1.0))
    mat_steel = create_clay_mat("m_ubld_ws", (0.75, 0.80, 0.88, 1.0))
    mat_gold = create_clay_mat("m_ubld_wg", (0.95, 0.78, 0.22, 1.0))
    mat_core = create_clay_mat("m_ubld_wc", (0.98, 0.35, 0.48, 1.0), emission=(0.98, 0.35, 0.48, 1.0), emission_str=2.5)

    # 1. Main Base Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    w = bpy.context.active_object
    w.scale = (2.85, 2.85, 0.38)
    w.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(w, width=0.20, segments=4)
    objs.append(w)

    # 2. Heavy Corner Steel Brackets (4 corners)
    bracket_pos = [(-1.15, -1.15), (1.15, -1.15), (-1.15, 1.15), (1.15, 1.15)]
    for (bx, by) in bracket_pos:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, 0.16))
        brk = bpy.context.active_object
        brk.scale = (0.65, 0.65, 0.14)
        brk.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(brk, width=0.08, segments=3)
        objs.append(brk)

        # Rivet on each bracket
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(bx, by, 0.24))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(bolt)

    # 3. Cross-brace Ribs (Diagonal steel plates)
    for (sx, sy) in [(2.2, 0.32), (0.32, 2.2)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        rib = bpy.context.active_object
        rib.scale = (sx, sy, 0.12)
        rib.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(rib, width=0.05, segments=2)
        objs.append(rib)

    # 4. Central Shield Medallion Bezel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.18, vertices=16, location=(0, 0, 0.18))
    bezel = bpy.context.active_object
    bezel.data.materials.append(mat_steel)
    apply_uniform_clay_bevel(bezel, width=0.06, segments=3)
    objs.append(bezel)

    # 5. Glowing Power Crystal Core (Octagonal / Shield core)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.60, depth=0.14, vertices=8, location=(0, 0, 0.24))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    apply_uniform_clay_bevel(core, width=0.05, segments=2)
    objs.append(core)

    return objs

def build_sokpop_landmine():
    objs = []
    mat_base = create_clay_mat("m_ubld_mb", (0.30, 0.34, 0.40, 1.0))
    mat_metal = create_clay_mat("m_ubld_mm", (0.55, 0.60, 0.66, 1.0))
    mat_hazard = create_clay_mat("m_ubld_mh", (0.98, 0.78, 0.18, 1.0))
    mat_core = create_clay_mat("m_ubld_mc", (0.95, 0.28, 0.35, 1.0), emission=(0.95, 0.28, 0.35, 1.0), emission_str=2.5)

    # 1. Stepped Base Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.18, vertices=20, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.08, segments=3)
    objs.append(base)

    # 2. Upper Armored Hull Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.16, vertices=16, location=(0, 0, 0.10))
    hull = bpy.context.active_object
    hull.data.materials.append(mat_metal)
    apply_uniform_clay_bevel(hull, width=0.06, segments=3)
    objs.append(hull)

    # 3. Hazard Warning Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.76, minor_radius=0.06, location=(0, 0, 0.18))
    hr = bpy.context.active_object
    hr.data.materials.append(mat_hazard)
    bpy.ops.object.shade_smooth()
    objs.append(hr)

    # 4. 4 Radial Pressure Trigger Prongs / Studs
    for i in range(4):
        ang = i * (math.pi / 2.0) + math.pi / 4.0
        bx = math.cos(ang) * 0.76
        by = math.sin(ang) * 0.76
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, by, 0.19))
        stud = bpy.context.active_object
        stud.scale = (0.22, 0.22, 0.10)
        stud.rotation_euler = (0, 0, ang)
        stud.data.materials.append(mat_hazard)
        apply_uniform_clay_bevel(stud, width=0.03, segments=2)
        objs.append(stud)

    # 5. Core Collar & Glowing Detonator Core
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.14, vertices=16, location=(0, 0, 0.19))
    col = bpy.context.active_object
    col.data.materials.append(mat_base)
    apply_uniform_clay_bevel(col, width=0.04, segments=2)
    objs.append(col)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34, location=(0, 0, 0.22))
    c = bpy.context.active_object
    c.scale = (1.0, 1.0, 0.7)
    c.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(c)

    return objs

def build_sokpop_repair_station():
    objs = []
    mat_pad = create_clay_mat("m_ubld_rp", (0.88, 0.90, 0.94, 1.0))
    mat_steel = create_clay_mat("m_ubld_rs", (0.35, 0.40, 0.48, 1.0))
    mat_cross_rim = create_clay_mat("m_ubld_rcr", (0.25, 0.65, 0.40, 1.0))
    mat_cross = create_clay_mat("m_ubld_rc", (0.28, 0.88, 0.50, 1.0), emission=(0.28, 0.88, 0.50, 1.0), emission_str=2.5)
    mat_ring = create_clay_mat("m_ubld_rr", (0.30, 0.82, 0.95, 1.0), emission=(0.30, 0.82, 0.95, 1.0), emission_str=2.0)
    mat_gold = create_clay_mat("m_ubld_rg", (0.98, 0.80, 0.22, 1.0))

    # 1. Main Octagonal/Circular Pad Base
    bpy.ops.mesh.primitive_cylinder_add(radius=1.25, depth=0.22, vertices=24, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_pad)
    apply_uniform_clay_bevel(p, width=0.08, segments=3)
    objs.append(p)

    # 2. Outer Concentric Energy Runway Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=1.05, minor_radius=0.06, location=(0, 0, 0.10))
    r = bpy.context.active_object
    r.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(r)

    # 3. Medical Cross Recessed Bezel
    for (sx, sy) in [(1.35, 0.52), (0.52, 1.35)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.10))
        c_rim = bpy.context.active_object
        c_rim.scale = (sx, sy, 0.12)
        c_rim.data.materials.append(mat_cross_rim)
        apply_uniform_clay_bevel(c_rim, width=0.04, segments=2)
        objs.append(c_rim)

    # 4. Glowing Medical Cross Center
    for (sx, sy) in [(1.15, 0.38), (0.38, 1.15)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        c = bpy.context.active_object
        c.scale = (sx, sy, 0.12)
        c.data.materials.append(mat_cross)
        apply_uniform_clay_bevel(c, width=0.04, segments=2)
        objs.append(c)

    # 5. 4 Corner Nanite Emitter Pylons
    for (px, py) in [(-0.85, -0.85), (0.85, -0.85), (-0.85, 0.85), (0.85, 0.85)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.30, vertices=12, location=(px, py, 0.15))
        pyl = bpy.context.active_object
        pyl.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(pyl, width=0.03, segments=2)
        objs.append(pyl)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(px, py, 0.32))
        tip = bpy.context.active_object
        tip.data.materials.append(mat_cross)
        bpy.ops.object.shade_smooth()
        objs.append(tip)

    return objs

# ==================== 4. SOKPOP MAP TOKENS ====================

def build_sokpop_map_node(type_name):
    objs = []
    mat_base = create_clay_mat("m_um_base", (0.86, 0.80, 0.72, 1.0))
    mat_rim = create_clay_mat("m_um_rim", (0.75, 0.68, 0.58, 1.0))

    # Base Disc Pedestal with Beveled Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.25, depth=0.28, vertices=24, location=(0, 0, 0))
    disc = bpy.context.active_object
    disc.data.materials.append(mat_base)
    apply_uniform_clay_bevel(disc, width=0.10, segments=3)
    objs.append(disc)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.12, minor_radius=0.06, location=(0, 0, 0.12))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim)
    bpy.ops.object.shade_smooth()
    objs.append(rim)

    if type_name == "battle":
        mat_blade = create_clay_mat("m_um_blade", (0.85, 0.88, 0.94, 1.0))
        mat_guard = create_clay_mat("m_um_guard", (0.95, 0.75, 0.20, 1.0))
        mat_grip = create_clay_mat("m_um_grip", (0.65, 0.25, 0.22, 1.0))
        mat_pommel = create_clay_mat("m_um_pommel", (0.95, 0.75, 0.20, 1.0))

        # Crossed Dual Broadswords
        for ang in [-38, 38]:
            rad = math.radians(ang)
            # Blade
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.28, 0.26))
            blade = bpy.context.active_object
            blade.scale = (0.22, 1.15, 0.10)
            blade.rotation_euler = (0, 0, rad)
            blade.data.materials.append(mat_blade)
            apply_uniform_clay_bevel(blade, width=0.04, segments=2)
            objs.append(blade)

            # Blade Point Tip
            tip_y = 0.28 + math.cos(rad) * 0.65
            tip_x = -math.sin(rad) * 0.65
            bpy.ops.mesh.primitive_cone_add(radius1=0.15, depth=0.32, location=(tip_x, tip_y, 0.26))
            tip = bpy.context.active_object
            tip.rotation_euler = (0, 0, rad)
            tip.scale = (1.0, 0.6, 0.6)
            tip.data.materials.append(mat_blade)
            apply_uniform_clay_bevel(tip, width=0.03, segments=2)
            objs.append(tip)

            # Crossguard
            guard_y = 0.28 - math.cos(rad) * 0.35
            guard_x = math.sin(rad) * 0.35
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(guard_x, guard_y, 0.28))
            guard = bpy.context.active_object
            guard.scale = (0.46, 0.12, 0.14)
            guard.rotation_euler = (0, 0, rad)
            guard.data.materials.append(mat_guard)
            apply_uniform_clay_bevel(guard, width=0.03, segments=2)
            objs.append(guard)

            # Grip Handle
            grip_y = 0.28 - math.cos(rad) * 0.58
            grip_x = math.sin(rad) * 0.58
            bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.35, vertices=12, location=(grip_x, grip_y, 0.28))
            grip = bpy.context.active_object
            grip.rotation_euler = (math.radians(90) * math.cos(rad), -math.radians(90) * math.sin(rad), rad)
            grip.data.materials.append(mat_grip)
            apply_uniform_clay_bevel(grip, width=0.02, segments=2)
            objs.append(grip)

            # Pommel
            pommel_y = 0.28 - math.cos(rad) * 0.78
            pommel_x = math.sin(rad) * 0.78
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(pommel_x, pommel_y, 0.28))
            pommel = bpy.context.active_object
            pommel.data.materials.append(mat_pommel)
            bpy.ops.object.shade_smooth()
            objs.append(pommel)

    elif type_name == "elite":
        mat_skull = create_clay_mat("m_um_sk", (0.92, 0.88, 0.82, 1.0))
        mat_dark = create_clay_mat("m_um_skd", (0.16, 0.16, 0.22, 1.0))
        mat_horn = create_clay_mat("m_um_skh", (0.85, 0.22, 0.28, 1.0))
        mat_horn_tip = create_clay_mat("m_um_skht", (0.98, 0.80, 0.22, 1.0))

        # Skull Cranium Dome
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.62, location=(0, 0.12, 0.32))
        skull = bpy.context.active_object
        skull.scale = (1.05, 0.95, 0.85)
        skull.data.materials.append(mat_skull)
        bpy.ops.object.shade_smooth()
        objs.append(skull)

        # Upper Jaw / Teeth Block
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.32, 0.26))
        jaw = bpy.context.active_object
        jaw.scale = (0.50, 0.35, 0.32)
        jaw.data.materials.append(mat_skull)
        apply_uniform_clay_bevel(jaw, width=0.06, segments=2)
        objs.append(jaw)

        # Deep Eye Sockets (Left & Right)
        for sx in [-0.26, 0.26]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.18, vertices=16, location=(sx, -0.06, 0.40))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_dark)
            apply_uniform_clay_bevel(eye, width=0.03, segments=2)
            objs.append(eye)

        # Nasal Cavity
        bpy.ops.mesh.primitive_cone_add(radius1=0.08, depth=0.15, location=(0, -0.22, 0.35))
        nose = bpy.context.active_object
        nose.rotation_euler = (0, 0, math.radians(180))
        nose.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(nose, width=0.02, segments=2)
        objs.append(nose)

        # Menacing Curved Horns (Left & Right)
        for hx in [-1, 1]:
            # Horn Base Segment
            bpy.ops.mesh.primitive_cone_add(radius1=0.20, depth=0.55, location=(hx * 0.52, 0.45, 0.38))
            h1 = bpy.context.active_object
            h1.rotation_euler = (math.radians(-15), math.radians(hx * 45), math.radians(hx * -35))
            h1.data.materials.append(mat_horn)
            apply_uniform_clay_bevel(h1, width=0.04, segments=2)
            objs.append(h1)

            # Horn Gold Tip
            bpy.ops.mesh.primitive_cone_add(radius1=0.12, depth=0.40, location=(hx * 0.78, 0.65, 0.48))
            h2 = bpy.context.active_object
            h2.rotation_euler = (math.radians(-25), math.radians(hx * 65), math.radians(hx * -50))
            h2.data.materials.append(mat_horn_tip)
            apply_uniform_clay_bevel(h2, width=0.03, segments=2)
            objs.append(h2)

    elif type_name == "rest":
        mat_wood = create_clay_mat("m_um_wood", (0.45, 0.28, 0.18, 1.0))
        mat_flame_out = create_clay_mat("m_um_fo", (0.95, 0.35, 0.15, 1.0), emission=(0.95, 0.35, 0.15, 1.0), emission_str=1.8)
        mat_flame_in = create_clay_mat("m_um_fi", (0.98, 0.85, 0.25, 1.0), emission=(0.98, 0.85, 0.25, 1.0), emission_str=2.8)
        mat_ember = create_clay_mat("m_um_emb", (0.98, 0.45, 0.18, 1.0), emission=(0.98, 0.45, 0.18, 1.0), emission_str=2.0)

        # 4 Criss-Cross Campfire Logs
        log_angles = [25, -65, 115, -155]
        for ang in log_angles:
            rad = math.radians(ang)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=1.05, vertices=12, location=(math.cos(rad)*0.18, math.sin(rad)*0.18, 0.18))
            log = bpy.context.active_object
            log.rotation_euler = (math.radians(90)*math.cos(rad), -math.radians(90)*math.sin(rad), rad)
            log.data.materials.append(mat_wood)
            apply_uniform_clay_bevel(log, width=0.03, segments=2)
            objs.append(log)

        # Main Outer Flame Tongue
        bpy.ops.mesh.primitive_cone_add(radius1=0.52, depth=0.95, location=(0, 0, 0.42))
        f_out = bpy.context.active_object
        f_out.scale = (1.0, 0.85, 1.0)
        f_out.data.materials.append(mat_flame_out)
        apply_uniform_clay_bevel(f_out, width=0.08, segments=3)
        objs.append(f_out)

        # Side Licking Flame Tongue
        bpy.ops.mesh.primitive_cone_add(radius1=0.32, depth=0.65, location=(0.22, -0.15, 0.38))
        f_side = bpy.context.active_object
        f_side.rotation_euler = (math.radians(15), math.radians(-20), 0)
        f_side.data.materials.append(mat_flame_out)
        apply_uniform_clay_bevel(f_side, width=0.05, segments=2)
        objs.append(f_side)

        # Bright Glowing Flame Core
        bpy.ops.mesh.primitive_cone_add(radius1=0.34, depth=0.68, location=(0, 0, 0.38))
        f_in = bpy.context.active_object
        f_in.data.materials.append(mat_flame_in)
        apply_uniform_clay_bevel(f_in, width=0.05, segments=2)
        objs.append(f_in)

        # Glowing Embers at base
        for (ex, ey) in [(-0.45, 0.35), (0.45, 0.30), (0.05, -0.48)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(ex, ey, 0.20))
            emb = bpy.context.active_object
            emb.data.materials.append(mat_ember)
            bpy.ops.object.shade_smooth()
            objs.append(emb)

    elif type_name == "shop":
        mat_chest = create_clay_mat("m_um_ch", (0.55, 0.32, 0.18, 1.0))
        mat_gold = create_clay_mat("m_um_chg", (0.95, 0.78, 0.22, 1.0))
        mat_iron = create_clay_mat("m_um_chi", (0.35, 0.38, 0.45, 1.0))
        mat_ruby = create_clay_mat("m_um_chrb", (0.95, 0.25, 0.35, 1.0), emission=(0.95, 0.25, 0.35, 1.0), emission_str=1.5)

        # Treasure Chest Body
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
        body = bpy.context.active_object
        body.scale = (1.10, 0.78, 0.38)
        body.data.materials.append(mat_chest)
        apply_uniform_clay_bevel(body, width=0.08, segments=3)
        objs.append(body)

        # Arched Chest Lid (Curved Cylinder)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.40, depth=1.12, vertices=16, location=(0, 0, 0.44))
        lid = bpy.context.active_object
        lid.rotation_euler = (0, math.radians(90), 0)
        lid.scale = (1.0, 0.75, 1.0)
        lid.data.materials.append(mat_chest)
        apply_uniform_clay_bevel(lid, width=0.06, segments=3)
        objs.append(lid)

        # Metal Corner Reinforcement Bands (Left & Right)
        for bx in [-0.42, 0.42]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0, 0.32))
            band = bpy.context.active_object
            band.scale = (0.16, 0.82, 0.52)
            band.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(band, width=0.03, segments=2)
            objs.append(band)

        # Front Lock Latch / Keyhole Clasp
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.41, 0.34))
        lock = bpy.context.active_object
        lock.scale = (0.24, 0.10, 0.22)
        lock.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(lock, width=0.03, segments=2)
        objs.append(lock)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(0, -0.46, 0.34))
        keyhole = bpy.context.active_object
        keyhole.data.materials.append(mat_iron)
        bpy.ops.object.shade_smooth()
        objs.append(keyhole)

        # Gold Coins / Gems beside the chest
        for (cx, cy) in [(-0.68, -0.32), (-0.75, 0.15), (0.72, -0.25)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.08, vertices=12, location=(cx, cy, 0.20))
            coin = bpy.context.active_object
            coin.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(coin, width=0.02, segments=2)
            objs.append(coin)

    elif type_name == "event":
        mat_q = create_clay_mat("m_um_q", (0.62, 0.28, 0.88, 1.0))
        mat_q_glow = create_clay_mat("m_um_qgl", (0.88, 0.55, 1.0, 1.0), emission=(0.88, 0.55, 1.0, 1.0), emission_str=2.0)
        mat_gold = create_clay_mat("m_um_qg", (0.95, 0.78, 0.22, 1.0))

        # Real 3D Question Mark "?" Structure
        # Upper Loop Arc
        bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.14, location=(0, 0.32, 0.28))
        loop = bpy.context.active_object
        loop.scale = (1.0, 0.95, 1.0)
        loop.data.materials.append(mat_q)
        bpy.ops.object.shade_smooth()
        objs.append(loop)

        # Middle Hook Stem
        bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=0.45, vertices=16, location=(0.04, 0.05, 0.28))
        stem = bpy.context.active_object
        stem.rotation_euler = (0, 0, math.radians(25))
        stem.data.materials.append(mat_q)
        apply_uniform_clay_bevel(stem, width=0.04, segments=2)
        objs.append(stem)

        # Central mask block (cuts the left side of torus to turn loop into a clean '?')
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.35, 0.22, 0.28))
        mask = bpy.context.active_object
        mask.scale = (0.35, 0.40, 0.35)
        mask.data.materials.append(mat_base)
        apply_uniform_clay_bevel(mask, width=0.04, segments=2)
        objs.append(mask)

        # Question Mark Bottom Dot
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, -0.42, 0.28))
        dot = bpy.context.active_object
        dot.data.materials.append(mat_q_glow)
        bpy.ops.object.shade_smooth()
        objs.append(dot)

        # Magical Sparkle Stars
        for (sx, sy, sz) in [(-0.62, 0.45, 0.30), (0.65, 0.42, 0.30)]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(sx, sy, sz))
            sp = bpy.context.active_object
            sp.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(sp)

    elif type_name == "boss":
        mat_cr = create_clay_mat("m_um_cr", (0.98, 0.78, 0.15, 1.0))
        mat_cushion = create_clay_mat("m_um_cush", (0.85, 0.18, 0.25, 1.0))
        mat_ruby = create_clay_mat("m_um_crub", (0.95, 0.22, 0.35, 1.0), emission=(0.95, 0.22, 0.35, 1.0), emission_str=2.0)
        mat_pearl = create_clay_mat("m_um_cprl", (0.95, 0.95, 0.98, 1.0))

        # Royal Velvet Interior Dome Cushion
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.62, location=(0, 0, 0.28))
        cush = bpy.context.active_object
        cush.scale = (1.0, 1.0, 0.75)
        cush.data.materials.append(mat_cushion)
        bpy.ops.object.shade_smooth()
        objs.append(cush)

        # Crown Base Rim
        bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=20, location=(0, 0, 0.20))
        band = bpy.context.active_object
        band.data.materials.append(mat_cr)
        apply_uniform_clay_bevel(band, width=0.06, segments=3)
        objs.append(band)

        # 5 Crenelated Crown Peaks (Front Center Tall, Sides Medium, Back Peaks)
        peak_angles = [0, 0.65, -0.65, 1.35, -1.35]
        for idx, ang in enumerate(peak_angles):
            px = math.sin(ang) * 0.68
            py = math.cos(ang) * 0.32 - 0.10
            h = 0.55 if idx == 0 else (0.45 if idx < 3 else 0.38)
            r = 0.18 if idx == 0 else 0.14
            bpy.ops.mesh.primitive_cone_add(radius1=r, depth=h, location=(px, py, 0.38 + h/2.0))
            pk = bpy.context.active_object
            pk.data.materials.append(mat_cr)
            apply_uniform_clay_bevel(pk, width=0.03, segments=2)
            objs.append(pk)

            # Pearl / Gem on top of each peak
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09 if idx == 0 else 0.07, location=(px, py, 0.38 + h + 0.04))
            pearl = bpy.context.active_object
            pearl.data.materials.append(mat_ruby if idx == 0 else mat_pearl)
            bpy.ops.object.shade_smooth()
            objs.append(pearl)

        # Center Huge Ruby Medallion
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(0, -0.72, 0.26))
        c_gem = bpy.context.active_object
        c_gem.data.materials.append(mat_ruby)
        bpy.ops.object.shade_smooth()
        objs.append(c_gem)

    return objs

def build_sokpop_active_ring():
    objs = []
    # Use lower roughness + low emission_str so top faces don't blow out
    mat_r    = create_clay_mat("m_um_ar",  (0.25, 0.88, 0.48, 1.0), roughness=0.55, emission=(0.25, 0.88, 0.48, 1.0), emission_str=0.6)
    mat_r2   = create_clay_mat("m_um_ar2", (0.42, 0.95, 0.65, 1.0), roughness=0.60, emission=(0.42, 0.95, 0.65, 1.0), emission_str=0.4)
    mat_stud = create_clay_mat("m_um_ars", (0.92, 0.96, 0.98, 1.0), roughness=0.45, emission=(0.85, 0.95, 0.90, 1.0), emission_str=0.7)

    # Outer glowing main orbit ring
    bpy.ops.mesh.primitive_torus_add(major_radius=1.35, minor_radius=0.12, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # Inner secondary orbit ring (slightly smaller, different shade)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.08, minor_radius=0.07, location=(0, 0, 0))
    ring2 = bpy.context.active_object
    ring2.data.materials.append(mat_r2)
    bpy.ops.object.shade_smooth()
    objs.append(ring2)

    # 4 Cardinal direction diamond studs — smaller radius to avoid big blown patches
    for ang_deg in [0, 90, 180, 270]:
        ang = math.radians(ang_deg)
        sx, sy = math.cos(ang) * 1.35, math.sin(ang) * 1.35
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(sx, sy, 0))
        stud = bpy.context.active_object
        stud.data.materials.append(mat_stud)
        bpy.ops.object.shade_smooth()
        objs.append(stud)

    return objs

# ==================== 5. SOKPOP POWERUPS ====================

def build_sokpop_powerup(p_type):
    objs = []
    mat_gold = create_clay_mat("m_upw_g", (0.98, 0.80, 0.18, 1.0))
    mat_red = create_clay_mat("m_upw_r", (0.92, 0.32, 0.38, 1.0))
    mat_cyan = create_clay_mat("m_upw_c", (0.28, 0.72, 0.92, 1.0))
    mat_white = create_clay_mat("m_upw_w", (0.95, 0.95, 0.98, 1.0))
    mat_dark = create_clay_mat("m_upw_d", (0.28, 0.30, 0.35, 1.0))
    mat_metal = create_clay_mat("m_upw_m", (0.75, 0.78, 0.84, 1.0))
    mat_wood = create_clay_mat("m_upw_wd", (0.55, 0.35, 0.22, 1.0))

    if p_type == "star":
        star_outer = create_3d_star(r_out=1.15, r_in=0.52, depth=0.32, z_pos=0.0)
        star_outer.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(star_outer, width=0.05, segments=3)
        objs.append(star_outer)

        star_inner = create_3d_star(r_out=0.75, r_in=0.34, depth=0.14, z_pos=0.18)
        star_inner.data.materials.append(mat_white)
        apply_uniform_clay_bevel(star_inner, width=0.03, segments=2)
        objs.append(star_inner)

    elif p_type == "gold_coin":
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.3, vertices=20, location=(0, 0, 0))
        coin = bpy.context.active_object
        coin.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(coin, width=0.08, segments=3)
        objs.append(coin)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.92, minor_radius=0.08, location=(0, 0, 0.16))
        rim = bpy.context.active_object
        rim.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(rim)

        coin_star = create_3d_star(r_out=0.62, r_in=0.28, depth=0.12, z_pos=0.16)
        coin_star.data.materials.append(mat_white)
        apply_uniform_clay_bevel(coin_star, width=0.03, segments=2)
        objs.append(coin_star)

    elif p_type == "helmet":
        # 1. Helmet Dome
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.90, location=(0, -0.05, 0.15))
        h = bpy.context.active_object
        h.scale = (1.05, 1.15, 0.85)
        h.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(h)

        # 2. Central Raised Crest Ridge
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.65))
        crest = bpy.context.active_object
        crest.scale = (0.20, 1.10, 0.20)
        crest.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(crest, width=0.04, segments=2)
        objs.append(crest)

        # 3. Flared Contoured Brow Brim
        bpy.ops.mesh.primitive_cylinder_add(radius=0.96, depth=0.16, vertices=20, location=(0, 0.38, 0.08))
        brim = bpy.context.active_object
        brim.scale = (1.05, 0.50, 1.0)
        brim.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(brim, width=0.06, segments=2)
        objs.append(brim)

        # 4. Ear Covers with Retaining Straps
        for sx in [-0.98, 0.98]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.20, vertices=16, location=(sx, -0.08, 0.15))
            ear = bpy.context.active_object
            ear.rotation_euler = (0, math.radians(90), 0)
            ear.data.materials.append(mat_red)
            apply_uniform_clay_bevel(ear, width=0.05, segments=2)
            objs.append(ear)

            # Rivet
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(sx * 1.10, -0.08, 0.15))
            rivet = bpy.context.active_object
            rivet.data.materials.append(mat_white)
            bpy.ops.object.shade_smooth()
            objs.append(rivet)

        # 5. Star Badge on Front
        top_badge = create_3d_star(r_out=0.38, r_in=0.18, depth=0.10, z_pos=0.88)
        top_badge.data.materials.append(mat_white)
        apply_uniform_clay_bevel(top_badge, width=0.02, segments=2)
        objs.append(top_badge)

    elif p_type == "bomb":
        # 1. Spherical Cast Iron Body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.92, location=(0, -0.12, 0))
        b = bpy.context.active_object
        b.data.materials.append(mat_dark)
        bpy.ops.object.shade_smooth()
        objs.append(b)

        # 2. Threaded Brass Fuse Collar / Cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.22, vertices=16, location=(0, 0.76, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(c, width=0.04, segments=2)
        objs.append(c)

        # 3. Naturally Curved Fuse Twine (Multi-Segment Arc)
        fuse_nodes = [
            (0.04, 0.94, 0.0, -15),
            (0.14, 1.12, 0.0, -35),
            (0.30, 1.25, 0.0, -60),
        ]
        for fx, fy, fz, fang in fuse_nodes:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.065, depth=0.24, vertices=12, location=(fx, fy, fz))
            fuse_seg = bpy.context.active_object
            fuse_seg.rotation_euler = (0, 0, math.radians(fang))
            fuse_seg.data.materials.append(mat_white)
            apply_uniform_clay_bevel(fuse_seg, width=0.02, segments=2)
            objs.append(fuse_seg)

        # 4. Crackling Spark Flame & Spark Beads
        mat_spark_core = create_clay_mat("m_upw_spkc", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=3.0)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0.42, 1.34, 0))
        flame = bpy.context.active_object
        flame.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(flame)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0.42, 1.34, 0.06))
        spark_core = bpy.context.active_object
        spark_core.data.materials.append(mat_spark_core)
        bpy.ops.object.shade_smooth()
        objs.append(spark_core)

    elif p_type == "clock":
        # 1. Main Cylinder Body
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.32, vertices=24, location=(0, -0.08, 0))
        clk = bpy.context.active_object
        clk.data.materials.append(mat_cyan)
        apply_uniform_clay_bevel(clk, width=0.10, segments=3)
        objs.append(clk)

        # 2. Twin Top Alarm Bells (Left & Right)
        for (bx, by, rot) in [(-0.75, 0.88, 30), (0.75, 0.88, -30)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.22, vertices=16, location=(bx, by, 0))
            bell = bpy.context.active_object
            bell.rotation_euler = (0, 0, math.radians(rot))
            bell.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(bell, width=0.04, segments=2)
            objs.append(bell)

        # 3. Top Striker Button
        bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.06, location=(0, 1.05, 0))
        btn = bpy.context.active_object
        btn.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(btn)

        # 4. Dial Face
        bpy.ops.mesh.primitive_cylinder_add(radius=0.82, depth=0.10, vertices=24, location=(0, -0.08, 0.16))
        face = bpy.context.active_object
        face.data.materials.append(mat_white)
        objs.append(face)

        # 5. 12 Hour Dial Tick Dots
        for i in range(12):
            ang = i * (math.pi / 6.0)
            tx = math.sin(ang) * 0.68
            ty = math.cos(ang) * 0.68 - 0.08
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(tx, ty, 0.22))
            dot = bpy.context.active_object
            dot.data.materials.append(mat_dark)
            bpy.ops.object.shade_smooth()
            objs.append(dot)

        # 6. Hour & Minute Hands
        for (hx, hy, hl, ang) in [(-0.14, 0.12, 0.40, -40), (0.16, 0.12, 0.48, 45)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=hl, vertices=8, location=(hx, hy - 0.08, 0.23))
            h = bpy.context.active_object
            h.rotation_euler = (0, 0, math.radians(ang))
            h.data.materials.append(mat_dark)
            objs.append(h)

        # Center Pin Cap
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, -0.08, 0.25))
        pin = bpy.context.active_object
        pin.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(pin)

    elif p_type == "shovel":
        # 1. Beveled Spade Scoop Blade
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.28, 0))
        b = bpy.context.active_object
        b.scale = (1.10, 0.95, 0.22)
        b.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(b, width=0.10, segments=3)
        objs.append(b)

        # Tapered Spade Point
        bpy.ops.mesh.primitive_cone_add(radius1=0.55, depth=0.52, location=(0, -0.85, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.scale = (1.0, 0.55, 0.45)
        cone.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(cone, width=0.05, segments=2)
        objs.append(cone)

        # Center Reinforcing Spine Ridge
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.05, vertices=12, location=(0, -0.42, 0.12))
        spine = bpy.context.active_object
        spine.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(spine, width=0.03, segments=2)
        objs.append(spine)

        # 2. Steel Collar Sleeve Socket
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.35, vertices=16, location=(0, 0.25, 0))
        collar = bpy.context.active_object
        collar.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(collar, width=0.04, segments=2)
        objs.append(collar)

        # 3. Wooden Shaft
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.85, vertices=12, location=(0, 0.68, 0))
        handle = bpy.context.active_object
        handle.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(handle, width=0.03, segments=2)
        objs.append(handle)

        # 4. Ergonomic D-Grip Handle (Torus + Cross-Bar)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.26, minor_radius=0.07, location=(0, 1.18, 0))
        d_grip = bpy.context.active_object
        d_grip.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(d_grip)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.065, depth=0.45, vertices=12, location=(0, 1.18, 0))
        d_bar = bpy.context.active_object
        d_bar.rotation_euler = (0, math.radians(90), 0)
        d_bar.data.materials.append(mat_wood)
        apply_uniform_clay_bevel(d_bar, width=0.02, segments=2)
        objs.append(d_bar)

    elif p_type == "life":
        # Sculpted Organic Clay Heart
        for sx in [-0.38, 0.38]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(sx, 0.25, 0))
            sph = bpy.context.active_object
            sph.scale = (1.0, 1.0, 0.75)
            sph.data.materials.append(mat_red)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        bpy.ops.mesh.primitive_cone_add(radius1=0.78, depth=1.18, location=(0, -0.32, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.scale = (1.0, 0.85, 0.75)
        cone.data.materials.append(mat_red)
        apply_uniform_clay_bevel(cone, width=0.14, segments=3)
        objs.append(cone)

        # Glossy White Clay Reflection Highlight
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(-0.35, 0.45, 0.32))
        hl = bpy.context.active_object
        hl.scale = (1.0, 1.0, 0.6)
        hl.data.materials.append(mat_white)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

    return objs

# ==================== 6. SOKPOP VFX ====================

def build_sokpop_explosion(frame_idx):
    objs = []
    mat_fire   = create_clay_mat("m_uexp_f",  (0.98, 0.42, 0.12, 1.0))
    mat_yellow = create_clay_mat("m_uexp_y",  (0.98, 0.88, 0.22, 1.0))
    mat_smoke  = create_clay_mat("m_uexp_s",  (0.88, 0.84, 0.80, 1.0))
    mat_dark   = create_clay_mat("m_uexp_d",  (0.35, 0.33, 0.38, 1.0))

    scale_factor = 0.38 + frame_idx * 0.24

    if frame_idx <= 1:
        # Early: compact fiery core + white-yellow hot center + pointed shard spikes
        num_puffs = 5
        for i in range(num_puffs):
            angle = i * (2.0 * math.pi / float(num_puffs)) + frame_idx * 0.3
            dist  = 0.12 + frame_idx * 0.14
            r     = (0.38 + (0.08 if i % 2 == 0 else -0.06)) * scale_factor
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0))
            sph = bpy.context.active_object
            sph.data.materials.append(mat_fire)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        # White-hot central core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22 * scale_factor, location=(0, 0, 0))
        core = bpy.context.active_object
        core.data.materials.append(mat_yellow)
        bpy.ops.object.shade_smooth()
        objs.append(core)

        # 4 Radial spark shard spikes
        for i in range(4):
            ang = i * (math.pi / 2.0) + frame_idx * 0.5
            bpy.ops.mesh.primitive_cone_add(radius1=0.08*scale_factor, depth=0.42*scale_factor,
                                             location=(math.cos(ang)*0.48*scale_factor,
                                                       math.sin(ang)*0.48*scale_factor, 0))
            shard = bpy.context.active_object
            shard.rotation_euler = (math.radians(90), 0, ang + math.pi/2)
            shard.data.materials.append(mat_yellow)
            apply_uniform_clay_bevel(shard, width=0.02, segments=2)
            objs.append(shard)

    elif frame_idx <= 3:
        # Mid: expanding orange fireball puffs with inner lighter layer
        num_puffs = 6 + frame_idx
        for i in range(num_puffs):
            angle = i * (2.0 * math.pi / float(num_puffs)) + frame_idx * 0.15
            dist  = 0.16 + frame_idx * 0.18
            r     = (0.34 + (0.10 if i % 2 == 0 else -0.04)) * scale_factor
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0))
            sph = bpy.context.active_object
            sph.data.materials.append(mat_fire if i % 3 != 2 else mat_smoke)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        # Fading ember center
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20 * scale_factor, location=(0, 0, 0))
        center = bpy.context.active_object
        center.data.materials.append(mat_fire)
        bpy.ops.object.shade_smooth()
        objs.append(center)

    else:
        # Late: billowing dark smoke tufts with pale ash wisps
        num_puffs = 7 + (frame_idx - 4)
        for i in range(num_puffs):
            angle = i * (2.0 * math.pi / float(num_puffs)) + frame_idx * 0.2
            dist  = 0.24 + (frame_idx - 4) * 0.22
            r     = (0.32 + (0.12 if i % 2 == 0 else -0.05)) * scale_factor
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0))
            sph = bpy.context.active_object
            sph.data.materials.append(mat_dark if i % 3 == 0 else mat_smoke)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        # Tiny residual ember core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12 * scale_factor, location=(0, 0, 0))
        ember = bpy.context.active_object
        ember.data.materials.append(mat_fire)
        bpy.ops.object.shade_smooth()
        objs.append(ember)

    return objs

def build_sokpop_spawn_star(frame_idx):
    objs = []
    mat_star = create_clay_mat("m_ustar", (0.98, 0.82, 0.22, 1.0), emission=(0.98, 0.82, 0.22, 1.0), emission_str=2.0)
    mat_core = create_clay_mat("m_ustarc", (1.0, 0.98, 0.80, 1.0), emission=(1.0, 0.98, 0.80, 1.0), emission_str=3.0)
    rot = frame_idx * (math.pi / 6.0)
    scale_factor = 0.45 + math.sin(frame_idx * (math.pi / 3.0)) * 0.35
    for i in range(4):
        angle = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16 * scale_factor, depth=1.6 * scale_factor, vertices=10, location=(0, 0, 0))
        pt = bpy.context.active_object
        pt.rotation_euler = (math.radians(90), 0, angle)
        pt.data.materials.append(mat_star)
        apply_uniform_clay_bevel(pt, width=0.04, segments=2)
        objs.append(pt)

    # Bright central glow core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28 * scale_factor, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)
    return objs

def build_sokpop_bullet(is_plasma=False):
    objs = []
    if not is_plasma:
        # Regular Shell: beveled oval cannonball shape
        mat_shell  = create_clay_mat("m_ubull_s", (0.92, 0.50, 0.20, 1.0))
        mat_tip    = create_clay_mat("m_ubull_t", (0.85, 0.85, 0.90, 1.0))
        mat_base   = create_clay_mat("m_ubull_b", (0.32, 0.32, 0.38, 1.0))
        mat_band   = create_clay_mat("m_ubull_bd", (0.95, 0.78, 0.22, 1.0))

        # Oval body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0, 0))
        body = bpy.context.active_object
        body.scale = (1.0, 0.78, 1.0)
        body.data.materials.append(mat_shell)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        # Pointed steel cap tip
        bpy.ops.mesh.primitive_cone_add(radius1=0.32, depth=0.52, location=(0, 0.46, 0))
        tip = bpy.context.active_object
        tip.rotation_euler = (math.radians(90), 0, 0)
        tip.scale = (1.0, 1.0, 0.85)
        tip.data.materials.append(mat_tip)
        apply_uniform_clay_bevel(tip, width=0.04, segments=2)
        objs.append(tip)

        # Flat brass base cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.16, vertices=14, location=(0, -0.45, 0))
        base_cap = bpy.context.active_object
        base_cap.rotation_euler = (math.radians(90), 0, 0)
        base_cap.data.materials.append(mat_base)
        apply_uniform_clay_bevel(base_cap, width=0.04, segments=2)
        objs.append(base_cap)

        # Gold driving band ring at equator
        bpy.ops.mesh.primitive_torus_add(major_radius=0.50, minor_radius=0.06, location=(0, 0, 0))
        band = bpy.context.active_object
        band.rotation_euler = (math.radians(90), 0, 0)
        band.data.materials.append(mat_band)
        bpy.ops.object.shade_smooth()
        objs.append(band)

    else:
        # Plasma Bolt: cyan teardrop body + energy coil rings + glowing core
        mat_plasma = create_clay_mat("m_ubull_pl", (0.28, 0.88, 1.0, 1.0), emission=(0.28, 0.88, 1.0, 1.0), emission_str=3.5)
        mat_core   = create_clay_mat("m_ubull_plc", (0.85, 0.98, 1.0, 1.0), emission=(0.85, 0.98, 1.0, 1.0), emission_str=5.0)
        mat_tail   = create_clay_mat("m_ubull_plt", (0.15, 0.55, 0.82, 1.0), emission=(0.15, 0.55, 0.82, 1.0), emission_str=2.0)

        # Elongated teardrop body
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.50, location=(0, 0, 0))
        body = bpy.context.active_object
        body.scale = (1.0, 1.38, 1.0)
        body.data.materials.append(mat_plasma)
        bpy.ops.object.shade_smooth()
        objs.append(body)

        # Bright glowing core
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, 0.05, 0))
        core = bpy.context.active_object
        core.data.materials.append(mat_core)
        bpy.ops.object.shade_smooth()
        objs.append(core)

        # 3 Energy coil rings along the tail
        for ry in [-0.18, -0.40, -0.60]:
            bpy.ops.mesh.primitive_torus_add(major_radius=0.38 + abs(ry) * 0.2, minor_radius=0.055, location=(0, ry, 0))
            coil = bpy.context.active_object
            coil.rotation_euler = (math.radians(90), 0, 0)
            coil.data.materials.append(mat_tail)
            bpy.ops.object.shade_smooth()
            objs.append(coil)

    return objs

# ==================== MASTER BATCH RENDER ====================

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(1000)

    print(">>> 1. Rendering Unified Sokpop Tanks (6-Frame Smooth Loop, Ortho Scale 3.6)...")
    player_palettes = {
        "player_tier0": {"body": (0.98, 0.80, 0.22, 1.0), "turret": (1.0, 0.86, 0.35, 1.0), "trim": (0.38, 0.75, 0.45, 1.0), "b_cnt": 1, "blen": 0.95, "bthick": 0.19, "heavy": False, "plasma": False},
        "player_tier1": {"body": (0.98, 0.58, 0.26, 1.0), "turret": (1.0, 0.70, 0.36, 1.0), "trim": (0.98, 0.38, 0.48, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.20, "heavy": False, "plasma": False},
        "player_tier2": {"body": (0.38, 0.78, 0.45, 1.0), "turret": (0.48, 0.85, 0.55, 1.0), "trim": (0.98, 0.80, 0.25, 1.0), "b_cnt": 2, "blen": 1.08, "bthick": 0.16, "heavy": True, "plasma": False},
        "player_tier3": {"body": (0.28, 0.62, 0.95, 1.0), "turret": (0.38, 0.72, 0.98, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.25, "bthick": 0.24, "heavy": True, "plasma": True},
    }
    for name, cfg in player_palettes.items():
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    enemies = {
        "enemy_basic": {"body": (0.75, 0.78, 0.84, 1.0), "turret": (0.84, 0.86, 0.90, 1.0), "trim": (0.95, 0.42, 0.52, 1.0), "b_cnt": 1, "blen": 0.92, "bthick": 0.16, "heavy": False},
        "enemy_fast": {"body": (0.26, 0.75, 0.88, 1.0), "turret": (0.42, 0.82, 0.95, 1.0), "trim": (0.98, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.15, "heavy": False},
        "enemy_power": {"body": (0.92, 0.32, 0.38, 1.0), "turret": (0.98, 0.45, 0.48, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.25, "bthick": 0.22, "heavy": False},
        "enemy_armor": {"body": (0.28, 0.62, 0.38, 1.0), "turret": (0.38, 0.72, 0.48, 1.0), "trim": (0.90, 0.85, 0.35, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.24, "heavy": True},
    }
    for name, cfg in enemies.items():
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. Rendering Unified Sokpop Tiles (6-Frame Water Flow, Ortho Scale 3.3)...")
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    tiles = {
        "tile_brick.png": build_sokpop_brick,
        "tile_steel.png": build_sokpop_steel,
        "tile_trees.png": build_sokpop_trees,
        "tile_ice.png": build_sokpop_ice,
        "base_eagle.png": lambda: build_sokpop_eagle(False),
        "base_destroyed.png": lambda: build_sokpop_eagle(True),
    }
    for fname, builder in tiles.items():
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))

    # 6-Frame Continuous Looping Water River
    for w_f in range(6):
        objs = build_sokpop_water(w_f)
        render_and_clean(objs, os.path.join(SPRITES_TILES, f"tile_water_f{w_f}.png"))

    print(">>> 3. Rendering Unified Sokpop Buildings...")
    render_and_clean(build_sokpop_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_sokpop_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_sokpop_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_sokpop_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_sokpop_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))

    print(">>> 4. Rendering Unified Sokpop Power-Ups & Gold Coin...")
    for p in ["star", "bomb", "clock", "helmet", "shovel", "life", "gold_coin"]:
        render_and_clean(build_sokpop_powerup(p), os.path.join(SPRITES_POWERUPS, f"{p}.png" if p != "gold_coin" else "gold_coin.png"))

    print(">>> 5. Rendering Unified Sokpop VFX (Explosions 6f, Stars 6f, Projectiles)...")
    for e_idx in range(6):
        render_and_clean(build_sokpop_explosion(e_idx), os.path.join(SPRITES_EFFECTS, f"explosion_{e_idx}.png"))
    for s_idx in range(6):
        render_and_clean(build_sokpop_spawn_star(s_idx), os.path.join(SPRITES_EFFECTS, f"spawn_star_{s_idx}.png"))
    render_and_clean(build_sokpop_bullet(False), os.path.join(SPRITES_EFFECTS, "bullet.png"))
    render_and_clean(build_sokpop_bullet(True), os.path.join(SPRITES_EFFECTS, "bullet_plasma.png"))

    print(">>> 6. Rendering High-Contrast Sokpop Map Nodes...")
    for node_type in ["battle", "elite", "rest", "shop", "event", "boss"]:
        render_and_clean(build_sokpop_map_node(node_type), os.path.join(SPRITES_MAP, f"node_{node_type}.png"))
    create_sokpop_lighting(ortho_scale=4.2, sun_energy=1.4)  # Wider frame, dimmer sun for glow-heavy ring
    render_and_clean(build_sokpop_active_ring(), os.path.join(SPRITES_MAP, "node_active_ring.png"))
    create_sokpop_lighting(ortho_scale=3.3)

    # Master .blend clean and save
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)

    coll_tanks = bpy.data.collections.new("Sokpop_Clay_Tanks")
    coll_tiles = bpy.data.collections.new("Sokpop_Clay_Tiles")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)

    p_showcase = build_sokpop_tank("ShowcaseSokpopTank", (0.98, 0.80, 0.22, 1.0), (1.0, 0.86, 0.35, 1.0), (0.38, 0.75, 0.45, 1.0), 1, 1.1, 0.2, False, False)
    for obj in p_showcase: coll_tanks.objects.link(obj)

    t_showcase = build_sokpop_eagle(False)
    for obj in t_showcase:
        obj.location.x += 4.0
        coll_tiles.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Master Clean .blend Saved: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
