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
        scene.cycles.samples = 24
        scene.cycles.adaptive_threshold = 0.04
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'

def create_studio_lighting():
    # Top-Down Ortho Camera
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.3
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera = cam_obj

    # 1. Main Sun Key Light
    sun_data = bpy.data.lights.new(name='SunKey', type='SUN')
    sun_data.energy = 5.0
    sun_data.color = (1.0, 0.98, 0.94)
    sun_obj = bpy.data.objects.new('SunKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(32), math.radians(18), math.radians(-38))

    # 2. Cool Sky Fill Light
    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 180.0
    fill_data.color = (0.7, 0.85, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

    # 3. Crisp Rim Backlight
    rim_data = bpy.data.lights.new(name='RimLight', type='POINT')
    rim_data.energy = 120.0
    rim_data.color = (0.9, 0.96, 1.0)
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5.5, 4.5)

# ==================== PROCEDURAL TEXTURE GENERATORS ====================

def create_camo_armor_material(name, col_primary, col_secondary, col_accent,
                               camo_scale=3.5, roughness=0.28, metallic=0.18, bump_strength=0.12):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic

    # Noise for camo blobs
    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = camo_scale
    noise.inputs['Detail'].default_value = 4.0
    noise.inputs['Roughness'].default_value = 0.55

    # ColorRamp to blend primary & secondary camo
    c_ramp = nodes.new(type='ShaderNodeValToRGB')
    c_ramp.color_ramp.elements[0].position = 0.38
    c_ramp.color_ramp.elements[0].color = col_primary
    c_ramp.color_ramp.elements[1].position = 0.62
    c_ramp.color_ramp.elements[1].color = col_secondary

    # Voronoi for micro armor plate chips / scratches
    voro = nodes.new(type='ShaderNodeTexVoronoi')
    voro.inputs['Scale'].default_value = 18.0

    # Bump for armor relief
    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = bump_strength
    bump.inputs['Distance'].default_value = 0.05

    links.new(noise.outputs['Fac'], c_ramp.inputs['Fac'])
    links.new(c_ramp.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_heavy_metal_material(name, base_col, roughness=0.4, metallic=0.7, bump_strength=0.2):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = base_col
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic

    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 15.0
    noise.inputs['Detail'].default_value = 6.0

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = bump_strength

    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_weathered_brick_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.72

    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 12.0
    noise.inputs['Detail'].default_value = 6.0

    c_ramp = nodes.new(type='ShaderNodeValToRGB')
    c_ramp.color_ramp.elements[0].position = 0.2
    c_ramp.color_ramp.elements[0].color = (0.65, 0.22, 0.10, 1.0) # burnt dark terracotta
    c_ramp.color_ramp.elements[1].position = 0.8
    c_ramp.color_ramp.elements[1].color = (0.88, 0.38, 0.18, 1.0) # bright clay red

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.35

    links.new(noise.outputs['Fac'], c_ramp.inputs['Fac'])
    links.new(c_ramp.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_industrial_steel_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0.78, 0.82, 0.88, 1.0)
    bsdf.inputs['Metallic'].default_value = 0.92
    bsdf.inputs['Roughness'].default_value = 0.22

    # Brushed steel anisotropic noise
    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 24.0
    noise.inputs['Detail'].default_value = 8.0

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.18

    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_caustic_water_material(name, offset=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0.08, 0.45, 0.95, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.08
    bsdf.inputs['Metallic'].default_value = 0.15

    # Voronoi caustics
    voro = nodes.new(type='ShaderNodeTexVoronoi')
    voro.inputs['Scale'].default_value = 6.5

    c_ramp = nodes.new(type='ShaderNodeValToRGB')
    c_ramp.color_ramp.elements[0].position = 0.2
    c_ramp.color_ramp.elements[0].color = (0.06, 0.38, 0.90, 1.0)
    c_ramp.color_ramp.elements[1].position = 0.85
    c_ramp.color_ramp.elements[1].color = (0.42, 0.85, 1.0, 1.0)

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.28

    links.new(voro.outputs['Distance'], c_ramp.inputs['Fac'])
    links.new(c_ramp.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(voro.outputs['Distance'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_foliage_trees_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.55

    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 10.0
    noise.inputs['Detail'].default_value = 4.0

    c_ramp = nodes.new(type='ShaderNodeValToRGB')
    c_ramp.color_ramp.elements[0].position = 0.25
    c_ramp.color_ramp.elements[0].color = (0.06, 0.42, 0.12, 1.0)
    c_ramp.color_ramp.elements[1].position = 0.75
    c_ramp.color_ramp.elements[1].color = (0.28, 0.80, 0.22, 1.0)

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.25

    links.new(noise.outputs['Fac'], c_ramp.inputs['Fac'])
    links.new(c_ramp.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_glacial_ice_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0.85, 0.95, 1.0, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.05
    bsdf.inputs['Metallic'].default_value = 0.2

    voro = nodes.new(type='ShaderNodeTexVoronoi')
    voro.inputs['Scale'].default_value = 8.0

    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.18

    links.new(voro.outputs['Distance'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_imperial_gold_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0.98, 0.82, 0.12, 1.0)
    bsdf.inputs['Metallic'].default_value = 0.92
    bsdf.inputs['Roughness'].default_value = 0.14

    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 16.0
    bump = nodes.new(type='ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.08

    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def create_dark_marble_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.35

    noise = nodes.new(type='ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 6.0
    noise.inputs['Detail'].default_value = 8.0

    c_ramp = nodes.new(type='ShaderNodeValToRGB')
    c_ramp.color_ramp.elements[0].position = 0.3
    c_ramp.color_ramp.elements[0].color = (0.15, 0.16, 0.18, 1.0)
    c_ramp.color_ramp.elements[1].position = 0.75
    c_ramp.color_ramp.elements[1].color = (0.35, 0.38, 0.42, 1.0)

    links.new(noise.outputs['Fac'], c_ramp.inputs['Fac'])
    links.new(c_ramp.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def render_and_clean(objects, output_path):
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered Rich: {os.path.basename(output_path)}")

# ==================== ADVANCED MODEL BUILDERS ====================

def build_rich_tank(name_prefix, col_pri, col_sec, col_acc,
                     barrel_count=1, barrel_len=1.2, barrel_thick=0.16,
                     is_heavy=False, is_plasma=False, frame=0, is_bonus=False):
    objs = []
    if is_bonus:
        col_pri = (1.0, 0.25, 0.25, 1.0)
        col_sec = (0.85, 0.15, 0.15, 1.0)
        col_acc = (1.0, 0.9, 0.2, 1.0)

    mat_body = create_camo_armor_material(f"{name_prefix}_body", col_pri, col_sec, col_acc, camo_scale=4.0, roughness=0.25, metallic=0.18)
    mat_turret = create_camo_armor_material(f"{name_prefix}_turret", col_sec, col_pri, col_acc, camo_scale=5.0, roughness=0.22, metallic=0.22)
    mat_track = create_heavy_metal_material(f"{name_prefix}_track", (0.22, 0.22, 0.25, 1.0), roughness=0.55, metallic=0.45, bump_strength=0.25)
    mat_trim = create_heavy_metal_material(f"{name_prefix}_trim", col_acc, roughness=0.25, metallic=0.35)
    mat_dark = create_heavy_metal_material(f"{name_prefix}_dark", (0.08, 0.08, 0.1, 1.0), roughness=0.6, metallic=0.5)
    
    mat_glow = bpy.data.materials.new(name=f"{name_prefix}_glow")
    mat_glow.use_nodes = True
    b_glow = mat_glow.node_tree.nodes.get('Principled BSDF')
    if b_glow:
        if 'Emission Color' in b_glow.inputs:
            b_glow.inputs['Emission Color'].default_value = (0.2, 0.95, 1.0, 1.0)
            b_glow.inputs['Emission Strength'].default_value = 5.0

    hull_w = 1.55 if is_heavy else 1.35
    hull_l = 1.65 if is_heavy else 1.5
    track_w = 0.42 if is_heavy else 0.36
    track_x = hull_w * 0.5 + track_w * 0.5 - 0.02
    track_l = hull_l * 1.15

    # 1. Main Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0))
    hull = bpy.context.active_object
    hull.scale = (hull_w, hull_l, 0.52)
    hull.data.materials.append(mat_body)
    objs.append(hull)

    # Front Beveled Armor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, hull_l*0.46, 0.08))
    front = bpy.context.active_object
    front.scale = (hull_w * 0.88, 0.36, 0.42)
    front.data.materials.append(mat_trim)
    objs.append(front)

    # Side Skirt Plates
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * (track_x + track_w*0.52), 0, 0.12))
        skirt = bpy.context.active_object
        skirt.scale = (0.08, track_l * 0.85, 0.35)
        skirt.data.materials.append(mat_trim)
        objs.append(skirt)

    # 2. Tracks & Wheels
    for side, x_pos in [('L', -track_x), ('R', track_x)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (track_w, track_l, 0.58)
        tr.data.materials.append(mat_track)
        objs.append(tr)

        for wy in [-0.5, 0.0, 0.5]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=track_w*1.05, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_dark)
            objs.append(wh)

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

    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.18, location=(0, -0.16, 0.76))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    objs.append(hatch)

    # 4. Cannons
    if barrel_count == 1:
        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, location=(0, 0.38 + barrel_len/2.0, 0.48))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_trim)
        objs.append(barrel)

        bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick * 1.45, depth=0.2, location=(0, 0.38 + barrel_len, 0.48))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_dark)
        objs.append(muzzle)

        if is_plasma:
            for py in [0.8, 1.2, 1.6]:
                bpy.ops.mesh.primitive_torus_add(major_radius=barrel_thick*1.4, minor_radius=0.04, location=(0, py, 0.48))
                coil = bpy.context.active_object
                coil.rotation_euler = (math.radians(90), 0, 0)
                coil.data.materials.append(mat_glow)
                objs.append(coil)

    elif barrel_count == 2:
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

def build_rich_brick_tile():
    objs = []
    mat_brick = create_weathered_brick_material("mat_rich_brick")
    mat_mortar = create_heavy_metal_material("mat_mortar", (0.22, 0.18, 0.15, 1.0), roughness=0.92, metallic=0.05)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (2.85, 2.85, 0.2)
    base.data.materials.append(mat_mortar)
    objs.append(base)

    for row in range(4):
        for col in range(4):
            x = -1.05 + col * 0.7
            y = -1.05 + row * 0.7
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.1))
            brick = bpy.context.active_object
            brick.scale = (0.62, 0.62, 0.26)
            brick.data.materials.append(mat_brick)
            objs.append(brick)
    return objs

def build_rich_steel_tile():
    objs = []
    mat_steel = create_industrial_steel_material("mat_rich_steel")
    mat_dark_steel = create_heavy_metal_material("mat_dstl", (0.35, 0.38, 0.44, 1.0), roughness=0.25, metallic=0.92)
    mat_bolt = create_heavy_metal_material("mat_blt", (0.95, 0.98, 1.0, 1.0), roughness=0.12, metallic=0.98)

    for rx in [-0.7, 0.7]:
        for ry in [-0.7, 0.7]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0))
            plate = bpy.context.active_object
            plate.scale = (1.3, 1.3, 0.32)
            plate.data.materials.append(mat_steel)
            objs.append(plate)

            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0.2))
            inner = bpy.context.active_object
            inner.scale = (0.95, 0.95, 0.1)
            inner.data.materials.append(mat_dark_steel)
            objs.append(inner)

            for bx in [-0.46, 0.46]:
                for by in [-0.46, 0.46]:
                    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.12, location=(rx + bx, ry + by, 0.28))
                    bolt = bpy.context.active_object
                    bolt.data.materials.append(mat_bolt)
                    objs.append(bolt)
    return objs

def build_rich_water_tile(frame=0):
    objs = []
    mat_water = create_caustic_water_material(f"mat_rich_water_{frame}")
    mat_crest = create_heavy_metal_material("mat_crest", (0.45, 0.88, 1.0, 1.0), roughness=0.05, metallic=0.1)

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

def build_rich_trees_tile():
    objs = []
    mat_foliage = create_foliage_trees_material("mat_rich_foliage")
    spheres = [
        (-0.7, -0.7, 0.4, 0.7), (0.7, -0.7, 0.4, 0.65),
        (-0.7, 0.7, 0.4, 0.68), (0.7, 0.7, 0.4, 0.72),
        (0, 0, 0.6, 0.85),
        (-0.25, 0.25, 0.9, 0.55), (0.25, -0.25, 0.85, 0.5)
    ]
    for x, y, z, r in spheres:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        b = bpy.context.active_object
        b.data.materials.append(mat_foliage)
        objs.append(b)
    return objs

def build_rich_ice_tile():
    objs = []
    mat_ice = create_glacial_ice_material("mat_rich_ice")
    mat_frost = create_heavy_metal_material("mat_frost", (1.0, 1.0, 1.0, 1.0), roughness=0.1)

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

def build_rich_eagle_base(destroyed=False):
    objs = []
    mat_ped = create_dark_marble_material("mat_rich_marble" if not destroyed else "mat_rubble_ped")
    mat_gold = create_imperial_gold_material("mat_rich_gold")
    mat_rubble = create_heavy_metal_material("mat_rub", (0.35, 0.18, 0.12, 1.0), roughness=0.9, metallic=0.1)

    # Altar
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.scale = (2.7, 2.7, 0.38)
    ped.data.materials.append(mat_ped)
    objs.append(ped)

    if not destroyed:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0.45))
        body = bpy.context.active_object
        body.scale = (0.75, 1.1, 0.45)
        body.data.materials.append(mat_gold)
        objs.append(body)

        for sign in [-1, 1]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * 0.82, 0.1, 0.45))
            w = bpy.context.active_object
            w.scale = (0.75, 0.6, 0.38)
            w.rotation_euler = (0, 0, math.radians(sign * -28))
            w.data.materials.append(mat_gold)
            objs.append(w)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=0.35, location=(0, 0.6, 0.5))
        head = bpy.context.active_object
        head.data.materials.append(mat_gold)
        objs.append(head)
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.7, -0.4, 0.3, 0.5), (0.6, 0.3, 0.3, 0.55), (0, -0.2, 0.35, 0.7), (-0.3, 0.6, 0.25, 0.4)]):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, rz))
            rub = bpy.context.active_object
            rub.scale = (s, s, s * 0.8)
            rub.rotation_euler = (math.radians(i*35), math.radians(i*40), math.radians(i*15))
            rub.data.materials.append(mat_rubble)
            objs.append(rub)

    return objs

def main():
    clear_scene()
    setup_render_settings(res=256)
    create_studio_lighting()

    print(">>> 1. Rich Textures: Rendering Player Tanks...")
    player_tiers = {
        "player_tier0": {"pri": (0.94, 0.72, 0.12, 1.0), "sec": (0.85, 0.62, 0.08, 1.0), "acc": (0.18, 0.65, 0.28, 1.0), "b_cnt": 1, "blen": 1.2, "bthick": 0.15, "heavy": False, "plasma": False},
        "player_tier1": {"pri": (0.96, 0.78, 0.14, 1.0), "sec": (0.88, 0.68, 0.10, 1.0), "acc": (0.85, 0.22, 0.18, 1.0), "b_cnt": 1, "blen": 1.45, "bthick": 0.18, "heavy": False, "plasma": False},
        "player_tier2": {"pri": (0.22, 0.72, 0.28, 1.0), "sec": (0.15, 0.55, 0.18, 1.0), "acc": (0.95, 0.78, 0.18, 1.0), "b_cnt": 2, "blen": 1.35, "bthick": 0.14, "heavy": True, "plasma": False},
        "player_tier3": {"pri": (0.15, 0.45, 0.88, 1.0), "sec": (0.10, 0.32, 0.72, 1.0), "acc": (0.98, 0.82, 0.15, 1.0), "b_cnt": 1, "blen": 1.65, "bthick": 0.22, "heavy": True, "plasma": True},
    }

    for name, cfg in player_tiers.items():
        for frame in [0, 1]:
            objs = build_rich_tank(
                f"{name}_f{frame}", cfg["pri"], cfg["sec"], cfg["acc"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(">>> 2. Rich Textures: Rendering Enemy Tanks...")
    enemies = {
        "enemy_basic": {"pri": (0.68, 0.72, 0.78, 1.0), "sec": (0.55, 0.58, 0.64, 1.0), "acc": (0.85, 0.25, 0.22, 1.0), "b_cnt": 1, "blen": 1.15, "bthick": 0.14, "heavy": False},
        "enemy_fast": {"pri": (0.22, 0.58, 0.96, 1.0), "sec": (0.15, 0.42, 0.80, 1.0), "acc": (1.0, 0.95, 0.95, 1.0), "b_cnt": 1, "blen": 1.38, "bthick": 0.13, "heavy": False},
        "enemy_power": {"pri": (0.90, 0.20, 0.20, 1.0), "sec": (0.72, 0.12, 0.12, 1.0), "acc": (0.98, 0.82, 0.18, 1.0), "b_cnt": 1, "blen": 1.68, "bthick": 0.16, "heavy": False},
        "enemy_armor": {"pri": (0.12, 0.44, 0.26, 1.0), "sec": (0.08, 0.32, 0.18, 1.0), "acc": (0.78, 0.88, 0.25, 1.0), "b_cnt": 1, "blen": 1.48, "bthick": 0.22, "heavy": True},
    }

    for name, cfg in enemies.items():
        for frame in [0, 1]:
            objs = build_rich_tank(
                f"{name}_f{frame}", cfg["pri"], cfg["sec"], cfg["acc"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame, is_bonus=False
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

            objs_b = build_rich_tank(
                f"{name}_b_f{frame}", cfg["pri"], cfg["sec"], cfg["acc"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], frame=frame, is_bonus=True
            )
            render_and_clean(objs_b, os.path.join(SPRITES_TANKS, f"{name}_bonus_f{frame}.png"))

    print(">>> 3. Rich Textures: Rendering Map Tiles...")
    tiles = {
        "tile_brick.png": build_rich_brick_tile,
        "tile_steel.png": build_rich_steel_tile,
        "tile_water_f0.png": lambda: build_rich_water_tile(0),
        "tile_water_f1.png": lambda: build_rich_water_tile(1),
        "tile_trees.png": build_rich_trees_tile,
        "tile_ice.png": build_rich_ice_tile,
        "base_eagle.png": lambda: build_rich_eagle_base(False),
        "base_destroyed.png": lambda: build_rich_eagle_base(True),
        "tile_water.png": lambda: build_rich_water_tile(0)
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
    coll_tanks = bpy.data.collections.new("Rich_Tanks")
    coll_tiles = bpy.data.collections.new("Rich_Tiles")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)

    p_dread = build_rich_tank("ShowcasePlasma", (0.15, 0.45, 0.88, 1.0), (0.10, 0.32, 0.72, 1.0), (0.98, 0.82, 0.15, 1.0), 1, 1.65, 0.22, True, True)
    for obj in p_dread: coll_tanks.objects.link(obj)

    t_altar = build_rich_eagle_base(False)
    for obj in t_altar:
        obj.location.x += 4.0
        coll_tiles.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Master .blend with Rich Procedural Shaders Saved: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
