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

    # 1. Main Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.56)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # 2. Nose Wedge & Fender
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.42, depth=0.48, vertices=16, location=(0, l*0.42, 0.04))
    nose = bpy.context.active_object
    nose.rotation_euler = (0, math.radians(90), 0)
    nose.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(nose, width=0.1, segments=3)
    objs.append(nose)

    # 3. Headlights
    for hx in [-w*0.28, w*0.28]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(hx, l*0.5, 0.12))
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

        # 3 Hubcap Roadwheels
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

        # Tread Teeth animation offset
        offset = 0.14 if frame == 1 else 0.0
        num_treads = 6
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
    bpy.ops.mesh.primitive_uv_sphere_add(radius=tsize*0.58, location=(0, -0.06, 0.52))
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

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (2.85, 2.85, 0.2)
    base.data.materials.append(mat_cream)
    apply_uniform_clay_bevel(base, width=0.1, segments=3)
    objs.append(base)

    row_configs = [
        [(-0.72, 1.25), (0.72, 1.25)],
        [(-1.18, 0.48), (0.0, 1.35), (1.18, 0.48)],
        [(-0.72, 1.25), (0.72, 1.25)],
        [(-1.18, 0.48), (0.0, 1.35), (1.18, 0.48)],
    ]
    y_coords = [-0.95, -0.32, 0.32, 0.95]
    for r_idx, row in enumerate(row_configs):
        y = y_coords[r_idx]
        for (x, w_size) in row:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.12))
            b = bpy.context.active_object
            b.scale = (w_size, 0.52, 0.28)
            b.data.materials.append(mat_clay)
            apply_uniform_clay_bevel(b, width=0.10, segments=3)
            objs.append(b)
    return objs

def build_sokpop_steel():
    objs = []
    mat_plate = create_clay_mat("m_us_p", (0.78, 0.82, 0.88, 1.0))
    mat_gold = create_clay_mat("m_us_g", (0.95, 0.78, 0.22, 1.0))
    mat_stripe = create_clay_mat("m_us_s", (0.95, 0.72, 0.18, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.scale = (2.85, 2.85, 0.35)
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.2, segments=4)
    objs.append(plate)

    for (sx, sy) in [(2.4, 0.4), (0.4, 2.4)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18))
        rib = bpy.context.active_object
        rib.scale = (sx, sy, 0.12)
        rib.data.materials.append(mat_plate)
        apply_uniform_clay_bevel(rib, width=0.06, segments=2)
        objs.append(rib)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.65, depth=0.16, vertices=16, location=(0, 0, 0.22))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_stripe)
    apply_uniform_clay_bevel(inner, width=0.08, segments=3)
    objs.append(inner)

    for rx in [-1.0, 1.0]:
        for ry in [-1.0, 1.0]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(rx, ry, 0.2))
            bolt = bpy.context.active_object
            bolt.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(bolt)
    return objs

def build_sokpop_water(frame=0):
    objs = []
    mat_water = create_clay_mat("m_uw_w", (0.28, 0.70, 0.88, 1.0), roughness=0.28, sss_weight=0.15)
    mat_foam = create_clay_mat("m_uw_f", (0.95, 0.95, 0.98, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    water = bpy.context.active_object
    water.scale = (2.95, 2.95, 0.3)
    water.data.materials.append(mat_water)
    apply_uniform_clay_bevel(water, width=0.12, segments=3)
    objs.append(water)

    offset = 0.40 if frame == 1 else 0.0
    wave_data = [
        (-0.7, -0.6 + offset, 0.95, 20),
        (0.7, -0.2 - offset, 0.85, -15),
        (-0.3, 0.5 + offset, 1.10, 10),
        (0.6, 0.8 - offset, 0.75, -25)
    ]
    for (wx, wy, wl, rot) in wave_data:
        if wy > 1.3: wy -= 2.6
        if wy < -1.3: wy += 2.6
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=wl, vertices=16, location=(wx, wy, 0.16))
        w = bpy.context.active_object
        w.rotation_euler = (0, math.radians(90), math.radians(rot))
        w.data.materials.append(mat_foam)
        apply_uniform_clay_bevel(w, width=0.04, segments=2)
        objs.append(w)
    return objs

def build_sokpop_trees():
    objs = []
    mat_matcha = create_clay_mat("m_ut_m", (0.36, 0.74, 0.32, 1.0))
    mat_lime = create_clay_mat("m_ut_l", (0.52, 0.82, 0.35, 1.0))
    mat_berry = create_clay_mat("m_ut_b", (0.92, 0.32, 0.42, 1.0))

    spheres = [
        (-0.85, -0.85, 0.35, 0.85, mat_matcha), (0.85, -0.85, 0.35, 0.85, mat_matcha),
        (-0.85, 0.85, 0.35, 0.85, mat_matcha), (0.85, 0.85, 0.35, 0.85, mat_matcha),
        (-0.75, 0.0, 0.45, 0.80, mat_lime), (0.75, 0.0, 0.45, 0.80, mat_lime),
        (0.0, -0.75, 0.45, 0.80, mat_lime), (0.0, 0.75, 0.45, 0.80, mat_lime),
        (0.0, 0.0, 0.75, 1.05, mat_lime),
        (-0.25, 0.25, 1.05, 0.60, mat_matcha)
    ]
    for x, y, z, r, m in spheres:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(m)
        bpy.ops.object.shade_smooth()
        objs.append(b)

    for bx, by, bz in [(-0.4, -0.3, 1.2), (0.5, 0.3, 1.15), (0.1, -0.6, 1.1), (-0.2, 0.6, 1.25)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=(bx, by, bz))
        berry = bpy.context.active_object
        berry.data.materials.append(mat_berry)
        bpy.ops.object.shade_smooth()
        objs.append(berry)

    return objs

def build_sokpop_ice():
    objs = []
    mat_sugar = create_clay_mat("m_ui_s", (0.78, 0.90, 0.96, 1.0), roughness=0.25)
    mat_sparkle = create_clay_mat("m_ui_sp", (0.95, 0.98, 1.0, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (2.85, 2.85, 0.3)
    ice.data.materials.append(mat_sugar)
    apply_uniform_clay_bevel(ice, width=0.22, segments=4)
    objs.append(ice)

    for (px, py, l, angle) in [(-0.4, -0.3, 0.9, 30), (0.4, 0.4, 0.7, -40), (-0.2, 0.6, 0.6, 60)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=l, vertices=12, location=(px, py, 0.18))
        s = bpy.context.active_object
        s.rotation_euler = (0, math.radians(90), math.radians(angle))
        s.data.materials.append(mat_sparkle)
        apply_uniform_clay_bevel(s, width=0.04, segments=2)
        objs.append(s)
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
    mat_b = create_clay_mat("m_ubld_tb", (0.38, 0.42, 0.48, 1.0))
    mat_r = create_clay_mat("m_ubld_tr", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.25, vertices=16, location=(0, 0, 0))
    b = bpy.context.active_object
    b.data.materials.append(mat_b)
    apply_uniform_clay_bevel(b, width=0.08, segments=3)
    objs.append(b)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.92, minor_radius=0.08, location=(0, 0, 0.12))
    r = bpy.context.active_object
    r.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(r)
    return objs

def build_sokpop_turret_gun():
    objs = []
    mat_g = create_clay_mat("m_ubld_tg", (0.32, 0.62, 0.92, 1.0))
    mat_m = create_clay_mat("m_ubld_tm", (0.98, 0.80, 0.22, 1.0))
    mat_bore = create_clay_mat("m_ubld_tbore", (0.10, 0.10, 0.14, 1.0))

    # EXACT CENTERED PIVOT AT (0, 0, 0.2)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0, 0.2))
    d = bpy.context.active_object
    d.scale = (1.0, 1.0, 0.85)
    d.data.materials.append(mat_g)
    bpy.ops.object.shade_smooth()
    objs.append(d)

    for bx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=1.1, vertices=16, location=(bx, 0.55, 0.2))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_g)
        apply_uniform_clay_bevel(barrel, width=0.04, segments=2)
        objs.append(barrel)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.06, location=(bx, 1.1, 0.2))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.10, vertices=12, location=(bx, 1.12, 0.2))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

    return objs

def build_sokpop_fortified_wall():
    objs = []
    mat_w = create_clay_mat("m_ubld_w", (0.38, 0.46, 0.55, 1.0))
    mat_heart = create_clay_mat("m_ubld_wh", (0.95, 0.38, 0.50, 1.0), emission=(0.95, 0.38, 0.50, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    w = bpy.context.active_object
    w.scale = (2.8, 2.8, 0.38)
    w.data.materials.append(mat_w)
    apply_uniform_clay_bevel(w, width=0.22, segments=4)
    objs.append(w)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.8, depth=0.12, vertices=16, location=(0, 0, 0.22))
    c = bpy.context.active_object
    c.data.materials.append(mat_heart)
    apply_uniform_clay_bevel(c, width=0.06, segments=2)
    objs.append(c)
    return objs

def build_sokpop_landmine():
    objs = []
    mat_m = create_clay_mat("m_ubld_m", (0.32, 0.35, 0.40, 1.0))
    mat_core = create_clay_mat("m_ubld_mc", (0.95, 0.32, 0.38, 1.0), emission=(0.95, 0.32, 0.38, 1.0), emission_str=2.5)
    mat_rim = create_clay_mat("m_ubld_mr", (0.98, 0.78, 0.22, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.95, depth=0.2, vertices=16, location=(0, 0, 0))
    m = bpy.context.active_object
    m.data.materials.append(mat_m)
    apply_uniform_clay_bevel(m, width=0.08, segments=3)
    objs.append(m)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.75, minor_radius=0.06, location=(0, 0, 0.12))
    hr = bpy.context.active_object
    hr.data.materials.append(mat_rim)
    bpy.ops.object.shade_smooth()
    objs.append(hr)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, 0, 0.15))
    c = bpy.context.active_object
    c.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(c)

    return objs

def build_sokpop_repair_station():
    objs = []
    mat_p = create_clay_mat("m_ubld_rp", (0.88, 0.90, 0.92, 1.0))
    mat_cross = create_clay_mat("m_ubld_rc", (0.30, 0.82, 0.42, 1.0), emission=(0.30, 0.82, 0.42, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.2, vertices=16, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_p)
    apply_uniform_clay_bevel(p, width=0.08, segments=3)
    objs.append(p)

    for (sx, sy) in [(1.3, 0.4), (0.4, 1.3)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        c = bpy.context.active_object
        c.scale = (sx, sy, 0.12)
        c.data.materials.append(mat_cross)
        apply_uniform_clay_bevel(c, width=0.06, segments=2)
        objs.append(c)
    return objs

# ==================== 4. SOKPOP MAP TOKENS ====================

def build_sokpop_map_node(type_name):
    objs = []
    mat_base = create_clay_mat("m_um_base", (0.86, 0.80, 0.72, 1.0))
    bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=0.35, vertices=16, location=(0, 0, 0))
    disc = bpy.context.active_object
    disc.data.materials.append(mat_base)
    apply_uniform_clay_bevel(disc, width=0.12, segments=3)
    objs.append(disc)

    if type_name == "battle":
        mat_sw = create_clay_mat("m_um_sw", (0.92, 0.38, 0.18, 1.0))
        for ang in [-35, 35]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=1.6, vertices=12, location=(0, 0, 0.25))
            sw = bpy.context.active_object
            sw.rotation_euler = (0, 0, math.radians(ang))
            sw.data.materials.append(mat_sw)
            apply_uniform_clay_bevel(sw, width=0.04, segments=2)
            objs.append(sw)
    elif type_name == "elite":
        mat_sk = create_clay_mat("m_um_sk", (0.85, 0.18, 0.25, 1.0))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, 0.15, 0.25))
        sk = bpy.context.active_object
        sk.data.materials.append(mat_sk)
        bpy.ops.object.shade_smooth()
        objs.append(sk)
        for hx in [-0.45, 0.45]:
            bpy.ops.mesh.primitive_cone_add(radius1=0.15, depth=0.45, location=(hx, 0.55, 0.25))
            horn = bpy.context.active_object
            horn.rotation_euler = (0, 0, math.radians(hx * -40))
            horn.data.materials.append(mat_sk)
            objs.append(horn)
    elif type_name == "rest":
        mat_f = create_clay_mat("m_um_f", (0.98, 0.55, 0.12, 1.0))
        bpy.ops.mesh.primitive_cone_add(radius1=0.45, depth=0.8, location=(0, 0.1, 0.28))
        fl = bpy.context.active_object
        fl.data.materials.append(mat_f)
        bpy.ops.object.shade_smooth()
        objs.append(fl)
    elif type_name == "shop":
        mat_g = create_clay_mat("m_um_g", (0.92, 0.72, 0.15, 1.0))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.25))
        box = bpy.context.active_object
        box.scale = (0.9, 0.7, 0.5)
        box.data.materials.append(mat_g)
        apply_uniform_clay_bevel(box, width=0.1, segments=3)
        objs.append(box)
    elif type_name == "event":
        mat_q = create_clay_mat("m_um_q", (0.58, 0.28, 0.85, 1.0))
        bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.12, location=(0, 0.22, 0.25))
        tor = bpy.context.active_object
        tor.data.materials.append(mat_q)
        bpy.ops.object.shade_smooth()
        objs.append(tor)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, -0.4, 0.25))
        dot = bpy.context.active_object
        dot.data.materials.append(mat_q)
        bpy.ops.object.shade_smooth()
        objs.append(dot)
    elif type_name == "boss":
        mat_cr = create_clay_mat("m_um_cr", (0.98, 0.76, 0.12, 1.0))
        bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.45, vertices=16, location=(0, 0, 0.25))
        cr = bpy.context.active_object
        cr.data.materials.append(mat_cr)
        apply_uniform_clay_bevel(cr, width=0.1, segments=3)
        objs.append(cr)
        for i in range(3):
            angle = (i - 1) * 0.4
            bpy.ops.mesh.primitive_cone_add(radius1=0.18, depth=0.4, location=(math.sin(angle)*0.55, math.cos(angle)*0.2 + 0.1, 0.52))
            pt = bpy.context.active_object
            pt.data.materials.append(mat_cr)
            objs.append(pt)

    return objs

def build_sokpop_active_ring():
    objs = []
    mat_r = create_clay_mat("m_um_ar", (0.25, 0.88, 0.48, 1.0), emission=(0.25, 0.88, 0.48, 1.0), emission_str=2.0)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.35, minor_radius=0.14, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(ring)
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
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.90, location=(0, -0.05, 0.15))
        h = bpy.context.active_object
        h.scale = (1.05, 1.15, 0.85)
        h.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(h)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.15, vertices=16, location=(0, 0.42, 0.08))
        brim = bpy.context.active_object
        brim.scale = (1.05, 0.45, 1.0)
        brim.data.materials.append(mat_dark)
        apply_uniform_clay_bevel(brim, width=0.06, segments=2)
        objs.append(brim)

        for sx in [-0.98, 0.98]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.20, vertices=16, location=(sx, -0.08, 0.15))
            ear = bpy.context.active_object
            ear.rotation_euler = (0, math.radians(90), 0)
            ear.data.materials.append(mat_red)
            apply_uniform_clay_bevel(ear, width=0.05, segments=2)
            objs.append(ear)

        top_badge = create_3d_star(r_out=0.35, r_in=0.16, depth=0.08, z_pos=0.88)
        top_badge.data.materials.append(mat_white)
        apply_uniform_clay_bevel(top_badge, width=0.02, segments=2)
        objs.append(top_badge)

    elif p_type == "bomb":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.92, location=(0, -0.1, 0))
        b = bpy.context.active_object
        b.data.materials.append(mat_dark)
        bpy.ops.object.shade_smooth()
        objs.append(b)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.25, vertices=16, location=(0, 0.80, 0))
        c = bpy.context.active_object
        c.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(c, width=0.04, segments=2)
        objs.append(c)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.45, vertices=12, location=(0.08, 1.05, 0))
        fuse = bpy.context.active_object
        fuse.rotation_euler = (0, 0, math.radians(-25))
        fuse.data.materials.append(mat_white)
        apply_uniform_clay_bevel(fuse, width=0.02, segments=2)
        objs.append(fuse)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18, location=(0.18, 1.28, 0))
        flame = bpy.context.active_object
        flame.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(flame)

    elif p_type == "clock":
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.3, vertices=20, location=(0, -0.08, 0))
        clk = bpy.context.active_object
        clk.data.materials.append(mat_cyan)
        apply_uniform_clay_bevel(clk, width=0.1, segments=3)
        objs.append(clk)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.26, minor_radius=0.08, location=(0, 1.08, 0))
        btn = bpy.context.active_object
        btn.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(btn)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.78, depth=0.08, vertices=20, location=(0, -0.08, 0.16))
        face = bpy.context.active_object
        face.data.materials.append(mat_white)
        objs.append(face)

        for (hx, hy, hl, ang) in [(-0.14, 0.12, 0.40, -40), (0.16, 0.12, 0.46, 45)]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=hl, vertices=8, location=(hx, hy - 0.08, 0.22))
            h = bpy.context.active_object
            h.rotation_euler = (0, 0, math.radians(ang))
            h.data.materials.append(mat_dark)
            objs.append(h)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(0, -0.08, 0.24))
        pin = bpy.context.active_object
        pin.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(pin)

    elif p_type == "shovel":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.32, 0))
        b = bpy.context.active_object
        b.scale = (1.05, 0.95, 0.24)
        b.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(b, width=0.12, segments=3)
        objs.append(b)

        bpy.ops.mesh.primitive_cone_add(radius1=0.52, depth=0.45, location=(0, -0.85, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.scale = (1.0, 0.5, 0.5)
        cone.data.materials.append(mat_metal)
        apply_uniform_clay_bevel(cone, width=0.05, segments=2)
        objs.append(cone)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=1.1, vertices=12, location=(0, 0.50, 0))
        handle = bpy.context.active_object
        handle.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(handle, width=0.04, segments=2)
        objs.append(handle)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.07, location=(0, 1.15, 0))
        d_grip = bpy.context.active_object
        d_grip.data.materials.append(mat_red)
        bpy.ops.object.shade_smooth()
        objs.append(d_grip)

    elif p_type == "life":
        for sx in [-0.38, 0.38]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.54, location=(sx, 0.25, 0))
            sph = bpy.context.active_object
            sph.data.materials.append(mat_red)
            bpy.ops.object.shade_smooth()
            objs.append(sph)

        bpy.ops.mesh.primitive_cone_add(radius1=0.76, depth=1.15, location=(0, -0.32, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, math.radians(180))
        cone.data.materials.append(mat_red)
        apply_uniform_clay_bevel(cone, width=0.15, segments=3)
        objs.append(cone)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(-0.35, 0.45, 0.42))
        hl = bpy.context.active_object
        hl.data.materials.append(mat_white)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

    return objs

# ==================== 6. SOKPOP VFX ====================

def build_sokpop_explosion(frame_idx):
    objs = []
    mat_fire = create_clay_mat("m_uexp_f", (0.98, 0.45, 0.15, 1.0))
    mat_smoke = create_clay_mat("m_uexp_s", (0.88, 0.85, 0.82, 1.0))
    mat_outer = create_clay_mat("m_uexp_o", (0.42, 0.40, 0.45, 1.0))

    scale_factor = 0.4 + frame_idx * 0.22
    mat_curr = mat_fire if frame_idx < 2 else (mat_smoke if frame_idx < 4 else mat_outer)

    num_puffs = 5 + frame_idx
    for i in range(num_puffs):
        angle = i * (2.0 * math.pi / float(num_puffs))
        dist = 0.15 + frame_idx * 0.18
        r = 0.35 + (0.1 if i % 2 == 0 else -0.05)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r * scale_factor, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0))
        sph = bpy.context.active_object
        sph.data.materials.append(mat_curr)
        bpy.ops.object.shade_smooth()
        objs.append(sph)
    return objs

def build_sokpop_spawn_star(frame_idx):
    objs = []
    mat_star = create_clay_mat("m_ustar", (0.98, 0.82, 0.22, 1.0), emission=(0.98, 0.82, 0.22, 1.0), emission_str=2.0)
    rot = frame_idx * (math.pi / 4.0)
    scale_factor = 0.4 + (frame_idx % 2) * 0.45
    for i in range(4):
        angle = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16 * scale_factor, depth=1.6 * scale_factor, vertices=10, location=(0, 0, 0))
        pt = bpy.context.active_object
        pt.rotation_euler = (math.radians(90), 0, angle)
        pt.data.materials.append(mat_star)
        apply_uniform_clay_bevel(pt, width=0.04, segments=2)
        objs.append(pt)
    return objs

def build_sokpop_bullet(is_plasma=False):
    objs = []
    col = (0.28, 0.85, 1.0, 1.0) if is_plasma else (0.95, 0.52, 0.22, 1.0)
    mat_b = create_clay_mat("m_ubull", col, emission=col if is_plasma else None, emission_str=3.0 if is_plasma else 0.0)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, 0, 0))
    sph = bpy.context.active_object
    sph.data.materials.append(mat_b)
    bpy.ops.object.shade_smooth()
    objs.append(sph)
    return objs

# ==================== MASTER BATCH RENDER ====================

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=3.3)
    reset_jitter_seed(1000)

    print(">>> 1. Rendering Unified Sokpop Tanks...")
    player_palettes = {
        "player_tier0": {"body": (0.98, 0.80, 0.22, 1.0), "turret": (1.0, 0.86, 0.35, 1.0), "trim": (0.38, 0.75, 0.45, 1.0), "b_cnt": 1, "blen": 0.95, "bthick": 0.19, "heavy": False, "plasma": False},
        "player_tier1": {"body": (0.98, 0.58, 0.26, 1.0), "turret": (1.0, 0.70, 0.36, 1.0), "trim": (0.98, 0.38, 0.48, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.20, "heavy": False, "plasma": False},
        "player_tier2": {"body": (0.38, 0.78, 0.45, 1.0), "turret": (0.48, 0.85, 0.55, 1.0), "trim": (0.98, 0.80, 0.25, 1.0), "b_cnt": 2, "blen": 1.08, "bthick": 0.16, "heavy": True, "plasma": False},
        "player_tier3": {"body": (0.28, 0.62, 0.95, 1.0), "turret": (0.38, 0.72, 0.98, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.35, "bthick": 0.24, "heavy": True, "plasma": True},
    }
    for name, cfg in player_palettes.items():
        for frame in [0, 1]:
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    enemies = {
        "enemy_basic": {"body": (0.75, 0.78, 0.84, 1.0), "turret": (0.84, 0.86, 0.90, 1.0), "trim": (0.95, 0.42, 0.52, 1.0), "b_cnt": 1, "blen": 0.92, "bthick": 0.16, "heavy": False},
        "enemy_fast": {"body": (0.26, 0.75, 0.88, 1.0), "turret": (0.42, 0.82, 0.95, 1.0), "trim": (0.98, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.15, "heavy": False},
        "enemy_power": {"body": (0.92, 0.32, 0.38, 1.0), "turret": (0.98, 0.45, 0.48, 1.0), "trim": (0.98, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.38, "bthick": 0.22, "heavy": False},
        "enemy_armor": {"body": (0.28, 0.62, 0.38, 1.0), "turret": (0.38, 0.72, 0.48, 1.0), "trim": (0.90, 0.85, 0.35, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.24, "heavy": True},
    }
    for name, cfg in enemies.items():
        for frame in [0, 1]:
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. Rendering Unified Sokpop Tiles...")
    tiles = {
        "tile_brick.png": build_sokpop_brick,
        "tile_steel.png": build_sokpop_steel,
        "tile_water_f0.png": lambda: build_sokpop_water(0),
        "tile_water_f1.png": lambda: build_sokpop_water(1),
        "tile_trees.png": build_sokpop_trees,
        "tile_ice.png": build_sokpop_ice,
        "base_eagle.png": lambda: build_sokpop_eagle(False),
        "base_destroyed.png": lambda: build_sokpop_eagle(True),
    }
    for fname, builder in tiles.items():
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))

    print(">>> 3. Rendering Unified Sokpop Buildings...")
    render_and_clean(build_sokpop_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_sokpop_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_sokpop_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_sokpop_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_sokpop_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))

    print(">>> 4. Rendering Unified Sokpop Power-Ups & Gold Coin...")
    for p in ["star", "bomb", "clock", "helmet", "shovel", "life", "gold_coin"]:
        render_and_clean(build_sokpop_powerup(p), os.path.join(SPRITES_POWERUPS, f"{p}.png" if p != "gold_coin" else "gold_coin.png"))

    print(">>> 5. Rendering Unified Sokpop VFX (Explosions, Stars, Projectiles)...")
    for e_idx in range(6):
        render_and_clean(build_sokpop_explosion(e_idx), os.path.join(SPRITES_EFFECTS, f"explosion_{e_idx}.png"))
    for s_idx in range(4):
        render_and_clean(build_sokpop_spawn_star(s_idx), os.path.join(SPRITES_EFFECTS, f"spawn_star_{s_idx}.png"))
    render_and_clean(build_sokpop_bullet(False), os.path.join(SPRITES_EFFECTS, "bullet.png"))
    render_and_clean(build_sokpop_bullet(True), os.path.join(SPRITES_EFFECTS, "bullet_plasma.png"))

    print(">>> 6. Rendering High-Contrast Sokpop Map Nodes...")
    for node_type in ["battle", "elite", "rest", "shop", "event", "boss"]:
        render_and_clean(build_sokpop_map_node(node_type), os.path.join(SPRITES_MAP, f"node_{node_type}.png"))
    render_and_clean(build_sokpop_active_ring(), os.path.join(SPRITES_MAP, "node_active_ring.png"))

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
