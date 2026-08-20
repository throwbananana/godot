import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
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

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_render_settings(rx=256, ry=256):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = 24
        scene.cycles.adaptive_threshold = 0.04
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'

def create_warm_toon_lighting(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    # Main Sunshine
    sun_data = bpy.data.lights.new(name='SunWarmKey', type='SUN')
    sun_data.energy = 5.2
    sun_data.color = (1.0, 0.94, 0.84)
    sun_obj = bpy.data.objects.new('SunWarmKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(35), math.radians(20), math.radians(-35))

    # Pastel Lavender Fill
    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 160.0
    fill_data.color = (0.92, 0.85, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

    # Champagne Rim
    rim_data = bpy.data.lights.new(name='RimLight', type='POINT')
    rim_data.energy = 110.0
    rim_data.color = (1.0, 0.98, 0.92)
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5, 4.5)

def create_toon_mat(name, col, roughness=0.35, metallic=0.08, emission=None, emission_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission and emission_str > 0:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission
            bsdf.inputs['Emission Strength'].default_value = emission_str
    out = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def add_smooth_bevel(obj, width=0.12, segments=3):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    mod = obj.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(25)

def render_and_clean(objects, out_path):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered No-Sharp-Edges Cute: {os.path.basename(out_path)}")

# ==================== 100% NO SHARP EDGES CUTE TANK ====================

def build_no_sharp_edges_tank(name_prefix, col_body, col_turret, col_trim,
                              barrel_count=1, barrel_len=0.95, barrel_thick=0.18,
                              is_heavy=False, is_plasma=False, frame=0, is_bonus=False):
    objs = []
    if is_bonus:
        col_body = (1.0, 0.35, 0.42, 1.0)
        col_turret = (1.0, 0.48, 0.55, 1.0)
        col_trim = (1.0, 0.88, 0.25, 1.0)

    mat_body = create_toon_mat(f"{name_prefix}_b", col_body, roughness=0.32)
    mat_turret = create_toon_mat(f"{name_prefix}_t", col_turret, roughness=0.30)
    mat_track = create_toon_mat(f"{name_prefix}_tr", (0.28, 0.26, 0.32, 1.0), roughness=0.5)
    mat_trim = create_toon_mat(f"{name_prefix}_tm", col_trim, roughness=0.25)
    mat_glow = create_toon_mat(f"{name_prefix}_gl", (0.3, 0.9, 1.0, 1.0), emission=(0.3, 0.9, 1.0, 1.0), emission_str=4.0)

    w = 1.45 if is_heavy else 1.3
    l = 1.55 if is_heavy else 1.4
    tw = 0.38 if is_heavy else 0.34
    tx = w * 0.5 + tw * 0.5 - 0.04
    tl = l * 1.1

    # 1. Hull with Heavy Bevel (Marshmallow Squircle)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.56)
    hull.data.materials.append(mat_body)
    add_smooth_bevel(hull, width=0.16, segments=4)
    objs.append(hull)

    # Rounded Nose Bumper
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.42, depth=0.48, vertices=16, location=(0, l*0.42, 0.04))
    nose = bpy.context.active_object
    nose.rotation_euler = (0, math.radians(90), 0)
    nose.data.materials.append(mat_trim)
    add_smooth_bevel(nose, width=0.1, segments=3)
    objs.append(nose)

    # 2. Pill Tracks & Chunky Rounded Wheels
    for side, x_pos in [('L', -tx), ('R', tx)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.6)
        tr.data.materials.append(mat_track)
        add_smooth_bevel(tr, width=0.15, segments=3)
        objs.append(tr)

        # Smooth Spherical/Cylinder Wheels
        for wy in [-0.45, 0.0, 0.45]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.24, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_trim)
            add_smooth_bevel(wh, width=0.08, segments=3)
            objs.append(wh)

        offset = 0.14 if frame == 1 else 0.0
        num_treads = 6
        for i in range(num_treads):
            y_pos = -tl*0.42 + (i / float(num_treads - 1)) * (tl * 0.84) + offset
            if y_pos > tl * 0.46: y_pos -= tl * 0.88
            bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=tw*1.05, vertices=12, location=(x_pos, y_pos, 0.32))
            tread = bpy.context.active_object
            tread.rotation_euler = (0, math.radians(90), 0)
            tread.data.materials.append(mat_body)
            add_smooth_bevel(tread, width=0.04, segments=2)
            objs.append(tread)

    # 3. Cute Spherical Dome Turret (100% Smooth)
    tsize = 0.92 if is_heavy else 0.82
    bpy.ops.mesh.primitive_uv_sphere_add(radius=tsize*0.58, location=(0, -0.06, 0.52))
    turret = bpy.context.active_object
    turret.scale = (1.0, 1.0, 0.75)
    turret.data.materials.append(mat_turret)
    bpy.ops.object.shade_smooth()
    objs.append(turret)

    # Cute Round Beveled Hatch
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.15, vertices=16, location=(0, -0.16, 0.82))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    add_smooth_bevel(hatch, width=0.08, segments=3)
    objs.append(hatch)

    # 4. Smooth Donut & Capsule Barrels
    if barrel_count == 1:
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, vertices=16, location=(0, 0.32 + barrel_len/2.0, 0.52))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_turret)
        add_smooth_bevel(barrel, width=0.06, segments=3)
        objs.append(barrel)

        # Smooth Donut Torus Muzzle
        bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.35, minor_radius=0.08, location=(0, 0.32 + barrel_len, 0.52))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_trim)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)

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
            add_smooth_bevel(barrel, width=0.05, segments=3)
            objs.append(barrel)

            bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.15, minor_radius=0.06, location=(bx, 0.32 + barrel_len, 0.52))
            muzzle = bpy.context.active_object
            muzzle.rotation_euler = (math.radians(90), 0, 0)
            muzzle.data.materials.append(mat_trim)
            bpy.ops.object.shade_smooth()
            objs.append(muzzle)

    return objs

# ==================== 100% NO SHARP EDGES TILES ====================

def build_no_sharp_edges_brick():
    objs = []
    mat_clay = create_toon_mat("m_cb_c", (0.95, 0.48, 0.28, 1.0))
    mat_cream = create_toon_mat("m_cb_m", (0.98, 0.92, 0.85, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (2.85, 2.85, 0.2)
    base.data.materials.append(mat_cream)
    add_smooth_bevel(base, width=0.1, segments=3)
    objs.append(base)

    for r in range(3):
        for c in range(3):
            x = -0.92 + c * 0.92
            y = -0.92 + r * 0.92
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.1))
            b = bpy.context.active_object
            b.scale = (0.76, 0.76, 0.28)
            b.data.materials.append(mat_clay)
            add_smooth_bevel(b, width=0.18, segments=4) # Soft Biscuit Rounding
            objs.append(b)
    return objs

def build_no_sharp_edges_steel():
    objs = []
    mat_plate = create_toon_mat("m_cs_p", (0.82, 0.86, 0.92, 1.0))
    mat_gold = create_toon_mat("m_cs_g", (0.98, 0.82, 0.2, 1.0))
    mat_stripe = create_toon_mat("m_cs_s", (1.0, 0.75, 0.15, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.scale = (2.85, 2.85, 0.35)
    plate.data.materials.append(mat_plate)
    add_smooth_bevel(plate, width=0.2, segments=4) # Soft Pillow Cushion
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.75, depth=0.15, vertices=16, location=(0, 0, 0.2))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_stripe)
    add_smooth_bevel(inner, width=0.08, segments=3)
    objs.append(inner)

    for rx in [-1.0, 1.0]:
        for ry in [-1.0, 1.0]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(rx, ry, 0.2))
            bolt = bpy.context.active_object
            bolt.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(bolt)
    return objs

def build_no_sharp_edges_water(frame=0):
    objs = []
    mat_water = create_toon_mat("m_cw_w", (0.2, 0.75, 0.95, 1.0), roughness=0.15)
    mat_foam = create_toon_mat("m_cw_f", (1.0, 1.0, 1.0, 1.0), roughness=0.2, emission=(1.0, 1.0, 1.0, 1.0), emission_str=1.5)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    water = bpy.context.active_object
    water.scale = (2.85, 2.85, 0.3)
    water.data.materials.append(mat_water)
    add_smooth_bevel(water, width=0.15, segments=3)
    objs.append(water)

    offset = 0.35 if frame == 1 else 0.0
    for fx, fy in [(-0.8, -0.6 + offset), (0.6, 0.4 + offset), (-0.2, 0.7 - offset), (0.3, -0.7 + offset)]:
        if fy > 1.2: fy -= 2.4
        if fy < -1.2: fy += 2.4
        bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.08, vertices=16, location=(fx, fy, 0.18))
        f = bpy.context.active_object
        f.data.materials.append(mat_foam)
        add_smooth_bevel(f, width=0.04, segments=2)
        objs.append(f)
    return objs

def build_no_sharp_edges_trees():
    objs = []
    mat_matcha = create_toon_mat("m_ct_m", (0.35, 0.78, 0.32, 1.0))
    mat_lime = create_toon_mat("m_ct_l", (0.55, 0.88, 0.35, 1.0))
    mat_berry = create_toon_mat("m_ct_b", (1.0, 0.35, 0.45, 1.0))

    spheres = [
        (-0.65, -0.65, 0.4, 0.75, mat_matcha), (0.65, -0.65, 0.4, 0.7, mat_matcha),
        (-0.65, 0.65, 0.4, 0.72, mat_matcha), (0.65, 0.65, 0.4, 0.78, mat_matcha),
        (0, 0, 0.65, 0.9, mat_lime),
        (-0.25, 0.25, 0.95, 0.55, mat_lime)
    ]
    for x, y, z, r, m in spheres:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(m)
        bpy.ops.object.shade_smooth()
        objs.append(b)

    for bx, by in [(-0.4, -0.3), (0.5, 0.3), (0.1, -0.6)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(bx, by, 1.1))
        berry = bpy.context.active_object
        berry.data.materials.append(mat_berry)
        bpy.ops.object.shade_smooth()
        objs.append(berry)

    return objs

def build_no_sharp_edges_ice():
    objs = []
    mat_sugar = create_toon_mat("m_ci_s", (0.85, 0.96, 1.0, 1.0), roughness=0.1)
    mat_sparkle = create_toon_mat("m_ci_sp", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=2.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (2.85, 2.85, 0.3)
    ice.data.materials.append(mat_sugar)
    add_smooth_bevel(ice, width=0.22, segments=4) # Soft Rounded Gummy Ice
    objs.append(ice)

    for (px, py, l, angle) in [(-0.4, -0.3, 0.9, 30), (0.4, 0.4, 0.7, -40)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=l, vertices=12, location=(px, py, 0.18))
        s = bpy.context.active_object
        s.rotation_euler = (0, math.radians(90), math.radians(angle))
        s.data.materials.append(mat_sparkle)
        add_smooth_bevel(s, width=0.04, segments=2)
        objs.append(s)
    return objs

def build_no_sharp_edges_eagle(destroyed=False):
    objs = []
    mat_ped = create_toon_mat("m_ce_p", (0.88, 0.82, 0.75, 1.0) if not destroyed else (0.4, 0.38, 0.42, 1.0))
    mat_chick = create_toon_mat("m_ce_c", (1.0, 0.85, 0.22, 1.0))
    mat_beak = create_toon_mat("m_ce_b", (1.0, 0.55, 0.15, 1.0))
    mat_eyes = create_toon_mat("m_ce_e", (0.15, 0.15, 0.2, 1.0))
    mat_sparkle = create_toon_mat("m_ce_sp", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=3.0)

    # Soft Pill Altar Base
    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.35, vertices=16, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.data.materials.append(mat_ped)
    add_smooth_bevel(ped, width=0.12, segments=3)
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
        add_smooth_bevel(beak, width=0.06, segments=2)
        objs.append(beak)

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
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.6, -0.3, 0.3, 0.5), (0.5, 0.3, 0.3, 0.55), (0, 0.1, 0.35, 0.65)]):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=s*0.8, location=(rx, ry, rz))
            rub = bpy.context.active_object
            rub.data.materials.append(mat_ped)
            bpy.ops.object.shade_smooth()
            objs.append(rub)

    return objs

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_warm_toon_lighting(ortho_scale=3.3)

    print(">>> 1. No Sharp Edges: Rendering Player Tanks...")
    player_palettes = {
        "player_tier0": {"body": (1.0, 0.82, 0.22, 1.0), "turret": (1.0, 0.88, 0.35, 1.0), "trim": (0.35, 0.75, 0.45, 1.0), "b_cnt": 1, "blen": 0.95, "bthick": 0.18, "heavy": False, "plasma": False},
        "player_tier1": {"body": (1.0, 0.62, 0.25, 1.0), "turret": (1.0, 0.72, 0.35, 1.0), "trim": (1.0, 0.35, 0.45, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.20, "heavy": False, "plasma": False},
        "player_tier2": {"body": (0.38, 0.82, 0.45, 1.0), "turret": (0.48, 0.88, 0.55, 1.0), "trim": (1.0, 0.82, 0.25, 1.0), "b_cnt": 2, "blen": 1.08, "bthick": 0.16, "heavy": True, "plasma": False},
        "player_tier3": {"body": (0.25, 0.65, 0.98, 1.0), "turret": (0.35, 0.75, 1.0, 1.0), "trim": (1.0, 0.85, 0.22, 1.0), "b_cnt": 1, "blen": 1.35, "bthick": 0.24, "heavy": True, "plasma": True},
    }

    for name, cfg in player_palettes.items():
        for frame in [0, 1]:
            objs = build_no_sharp_edges_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. No Sharp Edges: Rendering Enemy Tanks...")
    enemies = {
        "enemy_basic": {"body": (0.75, 0.78, 0.85, 1.0), "turret": (0.85, 0.88, 0.92, 1.0), "trim": (1.0, 0.45, 0.55, 1.0), "b_cnt": 1, "blen": 0.92, "bthick": 0.16, "heavy": False},
        "enemy_fast": {"body": (0.25, 0.78, 0.92, 1.0), "turret": (0.42, 0.85, 0.98, 1.0), "trim": (1.0, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.15, "heavy": False},
        "enemy_power": {"body": (0.95, 0.32, 0.38, 1.0), "turret": (1.0, 0.45, 0.48, 1.0), "trim": (1.0, 0.85, 0.22, 1.0), "b_cnt": 1, "blen": 1.38, "bthick": 0.22, "heavy": False},
        "enemy_armor": {"body": (0.28, 0.65, 0.38, 1.0), "turret": (0.38, 0.75, 0.48, 1.0), "trim": (0.92, 0.88, 0.35, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.24, "heavy": True},
    }

    for name, cfg in enemies.items():
        for frame in [0, 1]:
            objs = build_no_sharp_edges_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame, is_bonus=False
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

            objs_b = build_no_sharp_edges_tank(
                f"{name}_b_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame, is_bonus=True
            )
            render_and_clean(objs_b, os.path.join(SPRITES_TANKS, f"{name}_bonus_f{frame}.png"))

    print(">>> 3. No Sharp Edges: Rendering Map Tiles...")
    tiles = {
        "tile_brick.png": build_no_sharp_edges_brick,
        "tile_steel.png": build_no_sharp_edges_steel,
        "tile_water_f0.png": lambda: build_no_sharp_edges_water(0),
        "tile_water_f1.png": lambda: build_no_sharp_edges_water(1),
        "tile_trees.png": build_no_sharp_edges_trees,
        "tile_ice.png": build_no_sharp_edges_ice,
        "base_eagle.png": lambda: build_no_sharp_edges_eagle(False),
        "base_destroyed.png": lambda: build_no_sharp_edges_eagle(True),
        "tile_water.png": lambda: build_no_sharp_edges_water(0)
    }
    for fname, builder in tiles.items():
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))

    # Compatibility copies
    for f in [0, 1]:
        src_y = os.path.join(SPRITES_TANKS, f"player_tier0_f{f}.png")
        dst_y = os.path.join(SPRITES_TANKS, f"player_tank_yellow_f{f}.png")
        if os.path.exists(src_y):
            import shutil; shutil.copyfile(src_y, dst_y)

        src_g = os.path.join(SPRITES_TANKS, f"player_tier2_f{f}.png")
        dst_g = os.path.join(SPRITES_TANKS, f"player_tank_green_f{f}.png")
        if os.path.exists(src_g):
            import shutil; shutil.copyfile(src_g, dst_g)

    # Master .blend save
    coll_tanks = bpy.data.collections.new("No_Sharp_Edges_Tanks")
    coll_tiles = bpy.data.collections.new("No_Sharp_Edges_Tiles")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)

    p_showcase = build_no_sharp_edges_tank("ShowcaseBevelTank", (1.0, 0.82, 0.22, 1.0), (1.0, 0.88, 0.35, 1.0), (0.35, 0.75, 0.45, 1.0), 1, 1.1, 0.2, False, False)
    for obj in p_showcase: coll_tanks.objects.link(obj)

    t_showcase = build_no_sharp_edges_eagle(False)
    for obj in t_showcase:
        obj.location.x += 4.0
        coll_tiles.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Master 100% No-Sharp-Edges Cute .blend Saved: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
