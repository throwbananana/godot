import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

for folder in [SPRITES_BUILDINGS, SPRITES_POWERUPS, SPRITES_EFFECTS]:
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

def create_studio_lighting():
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.3
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

def create_mat(name, col, roughness=0.25, metallic=0.3, emission=None, emission_str=0.0):
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

# ==================== BUILDINGS ====================

def build_turret_base():
    objs = []
    mat_base = create_mat("m_tb", (0.2, 0.22, 0.26, 1.0), roughness=0.35, metallic=0.7)
    mat_ring = create_mat("m_tr", (0.1, 0.6, 0.95, 1.0), emission=(0.1, 0.6, 0.95, 1.0), emission_str=3.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.25, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    objs.append(base)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.9, minor_radius=0.08, location=(0, 0, 0.13))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_ring)
    objs.append(ring)
    return objs

def build_turret_gun():
    objs = []
    mat_gun = create_mat("m_tg", (0.15, 0.45, 0.85, 1.0), roughness=0.2, metallic=0.6)
    mat_barrel = create_mat("m_tgb", (0.1, 0.1, 0.12, 1.0), metallic=0.9)
    mat_glow = create_mat("m_tgl", (0.2, 0.9, 1.0, 1.0), emission=(0.2, 0.9, 1.0, 1.0), emission_str=4.0)

    # Dome
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, -0.1, 0.2))
    dome = bpy.context.active_object
    dome.data.materials.append(mat_gun)
    objs.append(dome)

    # Twin Barrels
    for bx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.1, depth=1.4, location=(bx, 0.6, 0.2))
        b = bpy.context.active_object
        b.rotation_euler = (math.radians(90), 0, 0)
        b.data.materials.append(mat_barrel)
        objs.append(b)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.2, location=(bx, 1.3, 0.2))
        m = bpy.context.active_object
        m.rotation_euler = (math.radians(90), 0, 0)
        m.data.materials.append(mat_glow)
        objs.append(m)
    return objs

def build_fortified_wall():
    objs = []
    mat_wall = create_mat("m_fw", (0.25, 0.28, 0.32, 1.0), roughness=0.25, metallic=0.85)
    mat_shield_grid = create_mat("m_fws", (0.1, 0.8, 1.0, 1.0), emission=(0.1, 0.8, 1.0, 1.0), emission_str=3.5)
    mat_corner = create_mat("m_fwc", (0.85, 0.65, 0.15, 1.0), roughness=0.2, metallic=0.9)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    wall = bpy.context.active_object
    wall.scale = (2.8, 2.8, 0.4)
    wall.data.materials.append(mat_wall)
    objs.append(wall)

    # Glowing shield emitter strip
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
    strip = bpy.context.active_object
    strip.scale = (2.4, 0.4, 0.1)
    strip.data.materials.append(mat_shield_grid)
    objs.append(strip)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
    strip_v = bpy.context.active_object
    strip_v.scale = (0.4, 2.4, 0.1)
    strip_v.data.materials.append(mat_shield_grid)
    objs.append(strip_v)

    # 4 Heavy Steel Corner Brackets
    for cx in [-1.15, 1.15]:
        for cy in [-1.15, 1.15]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.25))
            c = bpy.context.active_object
            c.scale = (0.5, 0.5, 0.18)
            c.data.materials.append(mat_corner)
            objs.append(c)
    return objs

def build_landmine():
    objs = []
    mat_body = create_mat("m_lm_b", (0.15, 0.16, 0.18, 1.0), roughness=0.4, metallic=0.7)
    mat_core = create_mat("m_lm_c", (1.0, 0.2, 0.2, 1.0), emission=(1.0, 0.2, 0.2, 1.0), emission_str=4.0)
    mat_pad = create_mat("m_lm_p", (0.85, 0.75, 0.15, 1.0), roughness=0.3, metallic=0.8)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.0, depth=0.18, vertices=6, location=(0, 0, 0))
    body = bpy.context.active_object
    body.data.materials.append(mat_body)
    objs.append(body)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.25, location=(0, 0, 0.08))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    objs.append(core)

    for i in range(3):
        angle = i * (2.0 * math.pi / 3.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.75, math.sin(angle)*0.75, 0.12))
        pad = bpy.context.active_object
        pad.scale = (0.25, 0.25, 0.1)
        pad.data.materials.append(mat_pad)
        objs.append(pad)
    return objs

def build_repair_station():
    objs = []
    mat_plate = create_mat("m_rp_p", (0.15, 0.2, 0.22, 1.0), roughness=0.35, metallic=0.6)
    mat_cross = create_mat("m_rp_c", (0.1, 0.95, 0.45, 1.0), emission=(0.1, 0.95, 0.45, 1.0), emission_str=4.5)
    mat_beacon = create_mat("m_rp_b", (0.9, 0.95, 1.0, 1.0), metallic=0.9)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.2, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_plate)
    objs.append(p)

    # Green Cross
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    c1 = bpy.context.active_object
    c1.scale = (1.4, 0.4, 0.12)
    c1.data.materials.append(mat_cross)
    objs.append(c1)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    c2 = bpy.context.active_object
    c2.scale = (0.4, 1.4, 0.12)
    c2.data.materials.append(mat_cross)
    objs.append(c2)
    return objs

def build_gold_coin():
    objs = []
    mat_gold = create_mat("m_gc", (0.98, 0.82, 0.12, 1.0), roughness=0.12, metallic=0.92, emission=(0.98, 0.82, 0.12, 1.0), emission_str=1.5)
    mat_star = create_mat("m_gcs", (1.0, 0.95, 0.5, 1.0), roughness=0.1, metallic=0.95)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.9, depth=0.25, location=(0, 0, 0))
    coin = bpy.context.active_object
    coin.data.materials.append(mat_gold)
    objs.append(coin)

    # Star Emblem
    for i in range(5):
        angle = i * (2.0 * math.pi / 5.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.35, math.sin(angle)*0.35, 0.15))
        pt = bpy.context.active_object
        pt.scale = (0.2, 0.55, 0.1)
        pt.rotation_euler = (0, 0, angle + math.radians(90))
        pt.data.materials.append(mat_star)
        objs.append(pt)
    return objs

def main():
    clear_scene()
    setup_render_settings(res=256)
    create_studio_lighting()

    print(">>> Rendering Building & RPG Assets...")
    render_and_clean(build_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))
    render_and_clean(build_gold_coin(), os.path.join(SPRITES_POWERUPS, "gold_coin.png"))

if __name__ == "__main__":
    main()
