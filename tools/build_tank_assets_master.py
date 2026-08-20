import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
BLENDER_SAVE = os.path.join(PROJECT_DIR, "assets", "blender", "tank_battle_assets.blend")

for folder in [SPRITES_TANKS, SPRITES_TILES, SPRITES_EFFECTS, SPRITES_POWERUPS]:
    os.makedirs(folder, exist_ok=True)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_render_settings(res=256):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = 16
        scene.cycles.adaptive_threshold = 0.05
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'

def create_camera_and_lights(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera = cam_obj

    # Main Key Light
    light_data = bpy.data.lights.new(name='SunKey', type='SUN')
    light_data.energy = 4.8
    light_data.color = (1.0, 0.98, 0.94)
    light_obj = bpy.data.objects.new('SunKey', light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.location = (3, -3, 8)
    light_obj.rotation_euler = (math.radians(30), math.radians(20), math.radians(-35))

    # Cool Fill Light
    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 160.0
    fill_data.color = (0.7, 0.85, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

    # Rim Back Light
    rim_data = bpy.data.lights.new(name='RimLight', type='POINT')
    rim_data.energy = 90.0
    rim_data.color = (0.9, 0.95, 1.0)
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5, 4)

def create_material(name, color, roughness=0.25, metallic=0.1, emission_color=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission_color and emission_strength > 0:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission_color
            bsdf.inputs['Emission Strength'].default_value = emission_strength
    output = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    return mat

def render_and_clean(objects, output_path):
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered: {os.path.basename(output_path)}")

# ==================== TANK BUILDERS ====================
def build_custom_tank(name_prefix, body_col, turret_col, track_col, trim_col,
                      barrel_count=1, barrel_len=1.2, barrel_thick=0.16,
                      is_heavy=False, is_plasma=False, frame=0, is_bonus=False):
    objs = []
    if is_bonus:
        body_col = (1.0, 0.25, 0.25, 1.0)
        trim_col = (1.0, 0.9, 0.2, 1.0)

    mat_body = create_material(f"{name_prefix}_b", body_col, roughness=0.22, metallic=0.15)
    mat_turret = create_material(f"{name_prefix}_t", turret_col, roughness=0.18, metallic=0.2)
    mat_track = create_material(f"{name_prefix}_tr", track_col, roughness=0.55, metallic=0.35)
    mat_trim = create_material(f"{name_prefix}_tm", trim_col, roughness=0.25, metallic=0.25)
    mat_dark = create_material(f"{name_prefix}_d", (0.08, 0.08, 0.1, 1.0), roughness=0.7)
    mat_glow = create_material(f"{name_prefix}_gl", (0.2, 0.9, 1.0, 1.0), emission_color=(0.2, 0.9, 1.0, 1.0), emission_strength=4.0)

    hull_w = 1.55 if is_heavy else 1.35
    hull_l = 1.65 if is_heavy else 1.5
    track_w = 0.42 if is_heavy else 0.36
    track_x = hull_w * 0.5 + track_w * 0.5 - 0.02
    track_l = hull_l * 1.15

    # 1. Main Hull Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0))
    hull = bpy.context.active_object
    hull.scale = (hull_w, hull_l, 0.52)
    hull.data.materials.append(mat_body)
    objs.append(hull)

    # Front Beveled Armor Slopes
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, hull_l*0.46, 0.08))
    front = bpy.context.active_object
    front.scale = (hull_w * 0.88, 0.36, 0.42)
    front.data.materials.append(mat_trim)
    objs.append(front)

    # Side Skirt Armor Plates
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * (track_x + track_w*0.52), 0, 0.12))
        skirt = bpy.context.active_object
        skirt.scale = (0.08, track_l * 0.85, 0.35)
        skirt.data.materials.append(mat_trim)
        objs.append(skirt)

    # 2. Left & Right Tracks + Animated Treads
    for side, x_pos in [('L', -track_x), ('R', track_x)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (track_w, track_l, 0.58)
        tr.data.materials.append(mat_track)
        objs.append(tr)

        # Wheels (Cylinders)
        for wy in [-0.5, 0.0, 0.5]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=track_w*1.05, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_dark)
            objs.append(wh)

        # Treads Offset Animation
        offset = 0.13 if frame == 1 else 0.0
        num_treads = 8
        for i in range(num_treads):
            y_pos = -track_l*0.44 + (i / float(num_treads - 1)) * (track_l * 0.88) + offset
            if y_pos > track_l * 0.48:
                y_pos -= track_l * 0.92
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, y_pos, 0.32))
            tread = bpy.context.active_object
            tread.scale = (track_w * 1.06, 0.08, 0.08)
            tread.data.materials.append(mat_dark)
            objs.append(tread)

    # 3. Turret
    t_size = 0.95 if is_heavy else 0.85
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.48))
    turret = bpy.context.active_object
    turret.scale = (t_size, t_size, 0.48)
    turret.data.materials.append(mat_turret)
    objs.append(turret)

    # Turret Hatch Cupola
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.18, location=(0, -0.16, 0.76))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    objs.append(hatch)

    # 4. Barrels (Single, Dual, or Plasma Heavy)
    if barrel_count == 1:
        # Single cannon
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, location=(0, 0.38 + barrel_len/2.0, 0.48))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_trim)
        objs.append(barrel)

        # Muzzle brake
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick * 1.45, depth=0.2, location=(0, 0.38 + barrel_len, 0.48))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_dark)
        objs.append(muzzle)

        if is_plasma:
            # Glowing plasma ring coils
            for py in [0.8, 1.2, 1.6]:
                bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.4, minor_radius=0.04, location=(0, py, 0.48))
                coil = bpy.context.active_object
                coil.rotation_euler = (math.radians(90), 0, 0)
                coil.data.materials.append(mat_glow)
                objs.append(coil)

    elif barrel_count == 2:
        # Dual Twin Cannons
        for bx in [-0.25, 0.25]:
            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*0.85, depth=barrel_len, location=(bx, 0.38 + barrel_len/2.0, 0.48))
            barrel = bpy.context.active_object
            barrel.rotation_euler = (math.radians(90), 0, 0)
            barrel.data.materials.append(mat_trim)
            objs.append(barrel)

            bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick*1.2, depth=0.18, location=(bx, 0.38 + barrel_len, 0.48))
            muzzle = bpy.context.active_object
            muzzle.rotation_euler = (math.radians(90), 0, 0)
            muzzle.data.materials.append(mat_dark)
            objs.append(muzzle)

    return objs

# ==================== TILES BUILDERS ====================
def build_brick_tile_hd():
    objs = []
    mat_brick_main = create_material("m_brk_m", (0.84, 0.33, 0.16, 1.0), roughness=0.68)
    mat_brick_dark = create_material("m_brk_d", (0.72, 0.25, 0.12, 1.0), roughness=0.75)
    mat_mortar = create_material("m_mortar", (0.22, 0.18, 0.15, 1.0), roughness=0.92)

    # Base Mortar Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (2.85, 2.85, 0.2)
    base.data.materials.append(mat_mortar)
    objs.append(base)

    # 4x4 Bricks with micro-bevels & staggered color tones
    for row in range(4):
        for col in range(4):
            x = -1.05 + col * 0.7
            y = -1.05 + row * 0.7
            mat = mat_brick_dark if (row + col) % 3 == 0 else mat_brick_main
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.1))
            brick = bpy.context.active_object
            brick.scale = (0.62, 0.62, 0.26)
            brick.data.materials.append(mat)
            objs.append(brick)
    return objs

def build_steel_tile_hd():
    objs = []
    mat_steel = create_material("m_stl", (0.76, 0.80, 0.85, 1.0), roughness=0.18, metallic=0.9)
    mat_dark_steel = create_material("m_dstl", (0.35, 0.38, 0.44, 1.0), roughness=0.25, metallic=0.92)
    mat_bolt = create_material("m_blt", (0.95, 0.98, 1.0, 1.0), roughness=0.12, metallic=0.98)

    for rx in [-0.7, 0.7]:
        for ry in [-0.7, 0.7]:
            # Plate bevel
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0))
            plate = bpy.context.active_object
            plate.scale = (1.3, 1.3, 0.32)
            plate.data.materials.append(mat_steel)
            objs.append(plate)

            # Embossed cross
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0.2))
            inner = bpy.context.active_object
            inner.scale = (0.95, 0.95, 0.1)
            inner.data.materials.append(mat_dark_steel)
            objs.append(inner)

            # 4 Hex Bolts
            for bx in [-0.46, 0.46]:
                for by in [-0.46, 0.46]:
                    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.12, location=(rx + bx, ry + by, 0.28))
                    bolt = bpy.context.active_object
                    bolt.data.materials.append(mat_bolt)
                    objs.append(bolt)
    return objs

def build_water_tile_hd(frame=0):
    objs = []
    mat_water = create_material("m_wtr", (0.08, 0.42, 0.92, 1.0), roughness=0.08, metallic=0.12)
    mat_crest = create_material("m_crst", (0.4, 0.85, 1.0, 1.0), roughness=0.1, emission_color=(0.3, 0.8, 1.0, 1.0), emission_strength=2.2)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    water = bpy.context.active_object
    water.scale = (2.85, 2.85, 0.3)
    water.data.materials.append(mat_water)
    objs.append(water)

    offset = 0.35 if frame == 1 else 0.0
    for y_pos in [-0.95 + offset, -0.15 + offset, 0.65 + offset]:
        if y_pos > 1.2: y_pos -= 2.4
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=2.5, location=(0, y_pos, 0.2))
        wave = bpy.context.active_object
        wave.rotation_euler = (0, math.radians(90), 0)
        wave.data.materials.append(mat_crest)
        objs.append(wave)
    return objs

def build_trees_tile_hd():
    objs = []
    mat_dark = create_material("m_tr_d", (0.06, 0.42, 0.10, 1.0), roughness=0.65)
    mat_med = create_material("m_tr_m", (0.16, 0.68, 0.18, 1.0), roughness=0.55)
    mat_light = create_material("m_tr_l", (0.35, 0.88, 0.28, 1.0), roughness=0.45)

    spheres = [
        (-0.7, -0.7, 0.4, 0.7, mat_dark), (0.7, -0.7, 0.4, 0.65, mat_dark),
        (-0.7, 0.7, 0.4, 0.68, mat_dark), (0.7, 0.7, 0.4, 0.72, mat_dark),
        (0, 0, 0.6, 0.85, mat_med),
        (-0.25, 0.25, 0.9, 0.55, mat_light), (0.25, -0.25, 0.85, 0.5, mat_light)
    ]
    for x, y, z, r, m in spheres:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(m)
        objs.append(b)
    return objs

def build_ice_tile_hd():
    objs = []
    mat_ice = create_material("m_ice", (0.84, 0.95, 1.0, 1.0), roughness=0.04, metallic=0.15)
    mat_frost = create_material("m_frst", (1.0, 1.0, 1.0, 1.0), roughness=0.08, emission_color=(0.9, 0.96, 1.0, 1.0), emission_strength=1.2)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (2.85, 2.85, 0.3)
    ice.data.materials.append(mat_ice)
    objs.append(ice)

    for (px, py, l, angle) in [(-0.5, -0.4, 1.2, 35), (0.4, 0.5, 0.9, -45), (-0.2, 0.3, 0.8, 60), (0.2, -0.6, 0.7, -25)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, 0.18))
        s = bpy.context.active_object
        s.scale = (l, 0.12, 0.05)
        s.rotation_euler = (0, 0, math.radians(angle))
        s.data.materials.append(mat_frost)
        objs.append(s)
    return objs

def build_eagle_base_hd(destroyed=False):
    objs = []
    mat_ped = create_material("m_ped", (0.22, 0.22, 0.26, 1.0) if not destroyed else (0.12, 0.10, 0.10, 1.0), roughness=0.6)
    mat_gold = create_material("m_gld", (0.98, 0.82, 0.12, 1.0), roughness=0.15, metallic=0.85)
    mat_ruby = create_material("m_rby", (0.95, 0.1, 0.15, 1.0), roughness=0.1, emission_color=(0.95, 0.1, 0.15, 1.0), emission_strength=3.0)
    mat_rubble = create_material("m_rub", (0.35, 0.18, 0.12, 1.0), roughness=0.9)

    # Base Pedestal
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.scale = (2.7, 2.7, 0.38)
    ped.data.materials.append(mat_ped)
    objs.append(ped)

    if not destroyed:
        # Eagle Body
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0.45))
        body = bpy.context.active_object
        body.scale = (0.75, 1.1, 0.45)
        body.data.materials.append(mat_gold)
        objs.append(body)

        # Wings
        for sign in [-1, 1]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * 0.82, 0.1, 0.45))
            w = bpy.context.active_object
            w.scale = (0.75, 0.6, 0.38)
            w.rotation_euler = (0, 0, math.radians(sign * -28))
            w.data.materials.append(mat_gold)
            objs.append(w)

        # Head & Ruby Eyes
        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.35, location=(0, 0.6, 0.5))
        head = bpy.context.active_object
        head.data.materials.append(mat_gold)
        objs.append(head)

        for sx in [-0.15, 0.15]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, location=(sx, 0.72, 0.6))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_ruby)
            objs.append(eye)
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.7, -0.4, 0.3, 0.5), (0.6, 0.3, 0.3, 0.55), (0, -0.2, 0.35, 0.7), (-0.3, 0.6, 0.25, 0.4)]):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, rz))
            rub = bpy.context.active_object
            rub.scale = (s, s, s * 0.8)
            rub.rotation_euler = (math.radians(i*35), math.radians(i*40), math.radians(i*15))
            rub.data.materials.append(mat_rubble)
            objs.append(rub)

    return objs

# ==================== POWER-UPS BUILDERS ====================
def build_powerup_token(name, icon_builder):
    objs = []
    mat_plate = create_material("m_pw_plt", (0.12, 0.15, 0.18, 1.0), roughness=0.3, metallic=0.4)
    mat_rim = create_material("m_pw_rim", (0.85, 0.75, 0.2, 1.0), roughness=0.15, metallic=0.8)

    # 3D Base Medal Token
    bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.22, location=(0, 0, 0))
    token = bpy.context.active_object
    token.data.materials.append(mat_plate)
    objs.append(token)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.98, minor_radius=0.07, location=(0, 0, 0.11))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim)
    objs.append(rim)

    # Add icon geometry
    icon_objs = icon_builder()
    objs.extend(icon_objs)
    return objs

def make_star_icon():
    objs = []
    mat = create_material("m_i_str", (1.0, 0.85, 0.1, 1.0), emission_color=(1.0, 0.85, 0.1, 1.0), emission_strength=2.8)
    for i in range(5):
        angle = i * (2.0 * math.pi / 5.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.45, math.sin(angle)*0.45, 0.18))
        pt = bpy.context.active_object
        pt.scale = (0.28, 0.72, 0.16)
        pt.rotation_euler = (0, 0, angle + math.radians(90))
        pt.data.materials.append(mat)
        objs.append(pt)
    return objs

def make_bomb_icon():
    objs = []
    mat_bomb = create_material("m_i_bmb", (0.95, 0.22, 0.18, 1.0), emission_color=(0.95, 0.22, 0.18, 1.0), emission_strength=1.8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, -0.08, 0.22))
    b = bpy.context.active_object
    b.data.materials.append(mat_bomb)
    objs.append(b)
    return objs

def make_clock_icon():
    objs = []
    mat_c = create_material("m_i_clk", (0.25, 0.65, 1.0, 1.0), emission_color=(0.25, 0.65, 1.0, 1.0), emission_strength=2.0)
    mat_face = create_material("m_i_cfc", (0.95, 0.98, 1.0, 1.0))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.65, depth=0.15, location=(0, 0, 0.16))
    c = bpy.context.active_object
    c.data.materials.append(mat_c)
    objs.append(c)
    return objs

def make_helmet_icon():
    objs = []
    mat = create_material("m_i_hlm", (0.2, 0.9, 0.45, 1.0), emission_color=(0.2, 0.9, 0.45, 1.0), emission_strength=2.5)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.16, vertices=6, location=(0, 0, 0.18))
    sh = bpy.context.active_object
    sh.data.materials.append(mat)
    objs.append(sh)
    return objs

def make_shovel_icon():
    objs = []
    mat_m = create_material("m_i_shv", (0.9, 0.92, 0.95, 1.0), metallic=0.9)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.25, 0.25, 0.2))
    blade = bpy.context.active_object
    blade.scale = (0.55, 0.55, 0.1)
    blade.rotation_euler = (0, 0, math.radians(45))
    blade.data.materials.append(mat_m)
    objs.append(blade)
    return objs

def make_life_icon():
    objs = []
    mat = create_material("m_i_lf", (0.95, 0.72, 0.15, 1.0), emission_color=(0.95, 0.72, 0.15, 1.0), emission_strength=2.0)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.2))
    tank = bpy.context.active_object
    tank.scale = (0.6, 0.7, 0.15)
    tank.data.materials.append(mat)
    objs.append(tank)
    return objs

# ==================== VFX & PROJECTILES ====================
def build_bullet_hd(plasma=False):
    objs = []
    col = (0.2, 0.9, 1.0, 1.0) if plasma else (1.0, 0.85, 0.2, 1.0)
    mat = create_material("m_blt", col, roughness=0.1, emission_color=col, emission_strength=3.5)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.36, location=(0, 0, 0))
    b = bpy.context.active_object
    b.scale = (0.7, 1.4, 0.7)
    b.data.materials.append(mat)
    objs.append(b)
    return objs

def build_explosion_frame_hd(stage=0):
    objs = []
    mat_fire = create_material(f"m_f_{stage}", (1.0, 0.38, 0.05, 1.0), emission_color=(1.0, 0.5, 0.0, 1.0), emission_strength=4.0)
    mat_core = create_material(f"m_c_{stage}", (1.0, 0.98, 0.5, 1.0), emission_color=(1.0, 0.98, 0.6, 1.0), emission_strength=5.5)
    mat_smoke = create_material(f"m_s_{stage}", (0.18, 0.18, 0.22, 1.0), roughness=0.9)

    radius = 0.45 + stage * 0.42
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_core if stage < 2 else (mat_fire if stage < 4 else mat_smoke))
    objs.append(core)

    num_sparks = 6 + stage * 2
    for i in range(num_sparks):
        angle = i * (2.0 * math.pi / num_sparks)
        dist = radius * 0.92
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius * 0.38, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0.1))
        sp = bpy.context.active_object
        sp.data.materials.append(mat_fire if stage < 4 else mat_smoke)
        objs.append(sp)
    return objs

def build_spawn_star_hd(frame=0):
    objs = []
    mat_star = create_material(f"m_spk_{frame}", (0.15, 0.95, 1.0, 1.0), emission_color=(0.15, 0.95, 1.0, 1.0), emission_strength=5.0)
    offset_rot = frame * math.radians(22.5)
    for i in range(8):
        angle = i * (2.0 * math.pi / 8.0) + offset_rot
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.55, math.sin(angle)*0.55, 0))
        pt = bpy.context.active_object
        pt.scale = (0.16, 0.92, 0.12)
        pt.rotation_euler = (0, 0, angle + math.radians(90))
        pt.data.materials.append(mat_star)
        objs.append(pt)
    return objs

def main():
    clear_scene()
    setup_render_settings(res=256)
    create_camera_and_lights(ortho_scale=3.3)

    print(">>> 1. Rendering Player Tank Tiers (0 to 3)...")
    player_tiers = {
        "player_tier0": {"body": (0.94, 0.72, 0.12, 1.0), "turret": (0.98, 0.78, 0.18, 1.0), "trim": (0.18, 0.65, 0.28, 1.0), "b_cnt": 1, "blen": 1.2, "bthick": 0.15, "heavy": False, "plasma": False},
        "player_tier1": {"body": (0.96, 0.78, 0.14, 1.0), "turret": (1.0, 0.85, 0.2, 1.0), "trim": (0.85, 0.22, 0.18, 1.0), "b_cnt": 1, "blen": 1.45, "bthick": 0.18, "heavy": False, "plasma": False},
        "player_tier2": {"body": (0.22, 0.72, 0.28, 1.0), "turret": (0.28, 0.82, 0.35, 1.0), "trim": (0.95, 0.78, 0.18, 1.0), "b_cnt": 2, "blen": 1.35, "bthick": 0.14, "heavy": True, "plasma": False},
        "player_tier3": {"body": (0.15, 0.45, 0.88, 1.0), "turret": (0.22, 0.55, 0.98, 1.0), "trim": (0.98, 0.82, 0.15, 1.0), "b_cnt": 1, "blen": 1.65, "bthick": 0.22, "heavy": True, "plasma": True},
    }

    for name, cfg in player_tiers.items():
        for frame in [0, 1]:
            objs = build_custom_tank(
                name_prefix=f"{name}_f{frame}",
                body_col=cfg["body"], turret_col=cfg["turret"],
                track_col=(0.25, 0.25, 0.28, 1.0), trim_col=cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. Rendering Enemy Tank Archetypes & Bonus Variants...")
    enemies = {
        "enemy_basic": {"body": (0.68, 0.72, 0.78, 1.0), "turret": (0.78, 0.82, 0.88, 1.0), "trim": (0.85, 0.25, 0.22, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.14, "heavy": False},
        "enemy_fast": {"body": (0.22, 0.58, 0.96, 1.0), "turret": (0.32, 0.68, 1.0, 1.0), "trim": (1.0, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.38, "bthick": 0.13, "heavy": False},
        "enemy_power": {"body": (0.90, 0.20, 0.20, 1.0), "turret": (0.98, 0.30, 0.26, 1.0), "trim": (0.98, 0.82, 0.18, 1.0), "b_cnt": 1, "blen": 1.68, "bthick": 0.16, "heavy": False},
        "enemy_armor": {"body": (0.12, 0.44, 0.26, 1.0), "turret": (0.18, 0.54, 0.34, 1.0), "trim": (0.78, 0.88, 0.25, 1.0), "b_cnt": 1, "blen": 1.48, "bthick": 0.22, "heavy": True},
    }

    for name, cfg in enemies.items():
        for frame in [0, 1]:
            # Normal variant
            objs = build_custom_tank(
                name_prefix=f"{name}_f{frame}",
                body_col=cfg["body"], turret_col=cfg["turret"],
                track_col=(0.25, 0.25, 0.28, 1.0), trim_col=cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=False, frame=frame, is_bonus=False
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

            # Red Flashing Bonus variant
            objs_bonus = build_custom_tank(
                name_prefix=f"{name}_bonus_f{frame}",
                body_col=cfg["body"], turret_col=cfg["turret"],
                track_col=(0.25, 0.25, 0.28, 1.0), trim_col=cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=False, frame=frame, is_bonus=True
            )
            render_and_clean(objs_bonus, os.path.join(SPRITES_TANKS, f"{name}_bonus_f{frame}.png"))

    print(">>> 3. Rendering HD Map Tiles...")
    tiles = {
        "tile_brick.png": build_brick_tile_hd,
        "tile_steel.png": build_steel_tile_hd,
        "tile_water_f0.png": lambda: build_water_tile_hd(0),
        "tile_water_f1.png": lambda: build_water_tile_hd(1),
        "tile_trees.png": build_trees_tile_hd,
        "tile_ice.png": build_ice_tile_hd,
        "base_eagle.png": lambda: build_eagle_base_hd(False),
        "base_destroyed.png": lambda: build_eagle_base_hd(True)
    }
    for fname, builder in tiles.items():
        objs = builder()
        render_and_clean(objs, os.path.join(SPRITES_TILES, fname))

    # Backward compatibility tile_water.png
    objs_w = build_water_tile_hd(0)
    render_and_clean(objs_w, os.path.join(SPRITES_TILES, "tile_water.png"))

    print(">>> 4. Rendering HD Power-Up 3D Tokens...")
    powerups = {
        "star.png": make_star_icon,
        "bomb.png": make_bomb_icon,
        "clock.png": make_clock_icon,
        "helmet.png": make_helmet_icon,
        "shovel.png": make_shovel_icon,
        "life.png": make_life_icon
    }
    for fname, icon_fn in powerups.items():
        objs = build_powerup_token(fname, icon_fn)
        render_and_clean(objs, os.path.join(SPRITES_POWERUPS, fname))

    print(">>> 5. Rendering HD VFX & Projectiles...")
    render_and_clean(build_bullet_hd(False), os.path.join(SPRITES_EFFECTS, "bullet.png"))
    render_and_clean(build_bullet_hd(True), os.path.join(SPRITES_EFFECTS, "bullet_plasma.png"))

    for stage in range(6):
        objs = build_explosion_frame_hd(stage)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"explosion_{stage}.png"))

    for f in range(4):
        objs = build_spawn_star_hd(f)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"spawn_star_{f}.png"))

    # Backward compatibility spawn_star.png
    objs_s = build_spawn_star_hd(0)
    render_and_clean(objs_s, os.path.join(SPRITES_EFFECTS, "spawn_star.png"))

    # Also map player_tank_yellow / green to tier0 / tier2 for compatibility
    for f in [0, 1]:
        src_y = os.path.join(SPRITES_TANKS, f"player_tier0_f{f}.png")
        dst_y = os.path.join(SPRITES_TANKS, f"player_tank_yellow_f{f}.png")
        if os.path.exists(src_y):
            import shutil; shutil.copyfile(src_y, dst_y)

        src_g = os.path.join(SPRITES_TANKS, f"player_tier2_f{f}.png")
        dst_g = os.path.join(SPRITES_TANKS, f"player_tank_green_f{f}.png")
        if os.path.exists(src_g):
            import shutil; shutil.copyfile(src_g, dst_g)

    print(">>> 6. Rebuilding Showcase Scene & Saving .blend...")
    coll_tanks = bpy.data.collections.new("Player_and_Enemy_Tanks")
    coll_tiles = bpy.data.collections.new("Map_Tiles")
    coll_powerups = bpy.data.collections.new("PowerUp_Badges")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)
    bpy.context.scene.collection.children.link(coll_powerups)

    # Add showcase objects into collections
    showcase_player = build_custom_tank("ShowcaseDreadnought", (0.15, 0.45, 0.88, 1.0), (0.22, 0.55, 0.98, 1.0), (0.25, 0.25, 0.28, 1.0), (0.98, 0.82, 0.15, 1.0), 1, 1.65, 0.22, True, True)
    for obj in showcase_player: coll_tanks.objects.link(obj)

    showcase_base = build_eagle_base_hd(False)
    for obj in showcase_base:
        obj.location.x += 4.0
        coll_tiles.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Successfully saved Master .blend file: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
