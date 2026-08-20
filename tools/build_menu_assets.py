import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")

for folder in [SPRITES_UI, SPRITES_MAP]:
    os.makedirs(folder, exist_ok=True)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_render_settings(rx=256, ry=256):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = 16
        scene.cycles.adaptive_threshold = 0.05
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'

def create_studio_lighting(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunKey', type='SUN')
    sun_data.energy = 5.0
    sun_data.color = (1.0, 0.98, 0.94)
    sun_obj = bpy.data.objects.new('SunKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(30), math.radians(20), math.radians(-35))

    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 160.0
    fill_data.color = (0.7, 0.85, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

def create_mat(name, col, roughness=0.22, metallic=0.4, emission=None, emission_str=0.0):
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

def render_and_clean(objects, out_path):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered: {os.path.basename(out_path)}")

# ==================== SPIRE MAP NODES ====================

def build_node_base(frame_col=(0.2, 0.22, 0.26, 1.0), glow_col=(0.1, 0.7, 1.0, 1.0), is_active=False):
    objs = []
    mat_plate = create_mat("m_nb_p", (0.1, 0.12, 0.15, 1.0), roughness=0.3, metallic=0.7)
    mat_rim = create_mat("m_nb_r", frame_col, roughness=0.2, metallic=0.85)
    mat_glow = create_mat("m_nb_g", glow_col, emission=glow_col, emission_str=4.5 if is_active else 0.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.22, vertices=8, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    objs.append(plate)

    bpy.ops.mesh.primitive_torus_add(major_radius=1.05, minor_radius=0.08, location=(0, 0, 0.12))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim if not is_active else mat_glow)
    objs.append(rim)
    return objs

def build_node_battle():
    objs = build_node_base()
    mat_sword = create_mat("m_sw", (0.9, 0.92, 0.95, 1.0), metallic=0.9)
    mat_hilt = create_mat("m_hl", (0.95, 0.75, 0.15, 1.0), metallic=0.8)

    # Crossed swords
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.2))
        blade = bpy.context.active_object
        blade.scale = (0.12, 1.2, 0.08)
        blade.rotation_euler = (0, 0, math.radians(sign * 45))
        blade.data.materials.append(mat_sword)
        objs.append(blade)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * -0.32, -0.32, 0.22))
        hilt = bpy.context.active_object
        hilt.scale = (0.35, 0.1, 0.1)
        hilt.rotation_euler = (0, 0, math.radians(sign * 45))
        hilt.data.materials.append(mat_hilt)
        objs.append(hilt)
    return objs

def build_node_elite():
    objs = build_node_base(frame_col=(0.7, 0.15, 0.15, 1.0), glow_col=(1.0, 0.2, 0.2, 1.0), is_active=False)
    mat_skull = create_mat("m_sk", (0.95, 0.25, 0.25, 1.0), emission=(0.95, 0.25, 0.25, 1.0), emission_str=2.5)
    mat_horn = create_mat("m_hn", (0.98, 0.8, 0.1, 1.0), metallic=0.8)

    # Skull
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(0, 0.05, 0.2))
    head = bpy.context.active_object
    head.scale = (1.0, 0.9, 0.8)
    head.data.materials.append(mat_skull)
    objs.append(head)

    # Horns
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.1, depth=0.6, location=(sign * 0.45, 0.45, 0.22))
        horn = bpy.context.active_object
        horn.rotation_euler = (0, 0, math.radians(sign * -35))
        horn.data.materials.append(mat_horn)
        objs.append(horn)
    return objs

def build_node_rest():
    objs = build_node_base(frame_col=(0.15, 0.65, 0.35, 1.0))
    mat_fire = create_mat("m_fr", (0.2, 0.95, 0.4, 1.0), emission=(0.2, 0.95, 0.4, 1.0), emission_str=4.0)
    mat_wood = create_mat("m_wd", (0.5, 0.3, 0.15, 1.0))

    # Campfire logs
    for angle in [30, -30, 90]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.1, depth=0.8, location=(0, -0.1, 0.16))
        log = bpy.context.active_object
        log.rotation_euler = (0, math.radians(90), math.radians(angle))
        log.data.materials.append(mat_wood)
        objs.append(log)

    # Campfire flame
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0.15, 0.26))
    flame = bpy.context.active_object
    flame.scale = (0.75, 1.2, 0.75)
    flame.data.materials.append(mat_fire)
    objs.append(flame)
    return objs

def build_node_shop():
    objs = build_node_base(frame_col=(0.85, 0.65, 0.15, 1.0))
    mat_sack = create_mat("m_sk", (0.98, 0.8, 0.15, 1.0), emission=(0.98, 0.8, 0.15, 1.0), emission_str=2.0)
    mat_coin = create_mat("m_cn", (1.0, 0.95, 0.4, 1.0), metallic=0.9)

    # Gold Sack / Chest
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.2))
    chest = bpy.context.active_object
    chest.scale = (0.85, 0.75, 0.45)
    chest.data.materials.append(mat_sack)
    objs.append(chest)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.15, location=(0, 0.05, 0.45))
    coin = bpy.context.active_object
    coin.data.materials.append(mat_coin)
    objs.append(coin)
    return objs

def build_node_event():
    objs = build_node_base(frame_col=(0.6, 0.3, 0.85, 1.0))
    mat_q = create_mat("m_q", (0.75, 0.35, 0.95, 1.0), emission=(0.75, 0.35, 0.95, 1.0), emission_str=3.5)

    # Question mark shape
    bpy.ops.mesh.primitive_torus_add(major_radius=0.35, minor_radius=0.1, location=(0, 0.25, 0.2))
    q_top = bpy.context.active_object
    q_top.data.materials.append(mat_q)
    objs.append(q_top)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.2))
    q_stem = bpy.context.active_object
    q_stem.scale = (0.18, 0.3, 0.12)
    q_stem.data.materials.append(mat_q)
    objs.append(q_stem)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, -0.42, 0.2))
    q_dot = bpy.context.active_object
    q_dot.data.materials.append(mat_q)
    objs.append(q_dot)
    return objs

def build_node_boss():
    objs = build_node_base(frame_col=(0.95, 0.2, 0.1, 1.0), glow_col=(1.0, 0.3, 0.1, 1.0), is_active=True)
    mat_crown = create_mat("m_cr", (0.98, 0.82, 0.12, 1.0), emission=(0.98, 0.82, 0.12, 1.0), emission_str=3.0)
    mat_gem = create_mat("m_gm", (0.95, 0.15, 0.15, 1.0), emission=(0.95, 0.15, 0.15, 1.0), emission_str=4.0)

    # Crown
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.3, vertices=5, location=(0, 0, 0.2))
    crown = bpy.context.active_object
    crown.data.materials.append(mat_crown)
    objs.append(crown)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0, 0.42))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_gem)
    objs.append(gem)
    return objs

def build_title_banner():
    objs = []
    mat_gold = create_mat("m_tb_gld", (0.98, 0.82, 0.12, 1.0), roughness=0.15, metallic=0.9, emission=(0.98, 0.82, 0.12, 1.0), emission_str=2.0)
    mat_steel = create_mat("m_tb_stl", (0.2, 0.25, 0.3, 1.0), roughness=0.25, metallic=0.85)
    mat_glow = create_mat("m_tb_glw", (0.1, 0.75, 1.0, 1.0), emission=(0.1, 0.75, 1.0, 1.0), emission_str=5.0)

    # Background Banner Shield
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.scale = (5.5, 2.2, 0.3)
    plate.data.materials.append(mat_steel)
    objs.append(plate)

    # Glowing Cyber Borders
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, sign * 1.05, 0.16))
        strip = bpy.context.active_object
        strip.scale = (5.3, 0.1, 0.1)
        strip.data.materials.append(mat_glow)
        objs.append(strip)

    # Twin Emblem Cannons
    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=2.8, location=(sign * 1.5, 0, 0.2))
        cannon = bpy.context.active_object
        cannon.rotation_euler = (0, 0, math.radians(sign * -25))
        cannon.data.materials.append(mat_gold)
        objs.append(cannon)

    return objs

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_studio_lighting(ortho_scale=3.2)

    print(">>> Rendering Slay the Spire Map Node Icons...")
    render_and_clean(build_node_battle(), os.path.join(SPRITES_MAP, "node_battle.png"))
    render_and_clean(build_node_elite(), os.path.join(SPRITES_MAP, "node_elite.png"))
    render_and_clean(build_node_rest(), os.path.join(SPRITES_MAP, "node_rest.png"))
    render_and_clean(build_node_shop(), os.path.join(SPRITES_MAP, "node_shop.png"))
    render_and_clean(build_node_event(), os.path.join(SPRITES_MAP, "node_event.png"))
    render_and_clean(build_node_boss(), os.path.join(SPRITES_MAP, "node_boss.png"))
    render_and_clean(build_node_base(is_active=True), os.path.join(SPRITES_MAP, "node_active_ring.png"))

    print(">>> Rendering Title Banner Logo...")
    setup_render_settings(rx=512, ry=256)
    create_studio_lighting(ortho_scale=6.0)
    render_and_clean(build_title_banner(), os.path.join(SPRITES_UI, "title_banner.png"))

if __name__ == "__main__":
    main()
