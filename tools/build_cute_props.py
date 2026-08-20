import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

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

def create_warm_lighting(ortho_scale=3.2):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunWarmKey', type='SUN')
    sun_data.energy = 5.2
    sun_data.color = (1.0, 0.94, 0.84)
    sun_obj = bpy.data.objects.new('SunWarmKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(35), math.radians(20), math.radians(-35))

    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 160.0
    fill_data.color = (0.92, 0.85, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

def create_toon_mat(name, col, roughness=0.3, metallic=0.08, emission=None, emission_str=0.0):
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

# ==================== CUTE BUILDINGS ====================

def build_cute_turret_base():
    objs = []
    mat_b = create_toon_mat("m_ctb", (0.35, 0.4, 0.48, 1.0))
    mat_r = create_toon_mat("m_ctr", (0.3, 0.85, 1.0, 1.0), emission=(0.3, 0.85, 1.0, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.25, vertices=12, location=(0, 0, 0))
    b = bpy.context.active_object
    b.data.materials.append(mat_b)
    objs.append(b)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.9, minor_radius=0.08, location=(0, 0, 0.12))
    r = bpy.context.active_object
    r.data.materials.append(mat_r)
    objs.append(r)
    return objs

def build_cute_turret_gun():
    objs = []
    mat_g = create_toon_mat("m_ctg", (0.28, 0.65, 0.98, 1.0))
    mat_m = create_toon_mat("m_ctm", (1.0, 0.85, 0.22, 1.0))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, -0.08, 0.2))
    d = bpy.context.active_object
    d.scale = (1.0, 1.0, 0.85)
    d.data.materials.append(mat_g)
    objs.append(d)

    for bx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.1, depth=1.2, vertices=10, location=(bx, 0.5, 0.2))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_g)
        objs.append(barrel)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.06, location=(bx, 1.1, 0.2))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_m)
        objs.append(muzzle)
    return objs

def build_cute_fortified_wall():
    objs = []
    mat_w = create_toon_mat("m_cfw", (0.35, 0.45, 0.55, 1.0))
    mat_heart = create_toon_mat("m_cfwh", (1.0, 0.35, 0.55, 1.0), emission=(1.0, 0.35, 0.55, 1.0), emission_str=3.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    w = bpy.context.active_object
    w.scale = (2.8, 2.8, 0.38)
    w.data.materials.append(mat_w)
    objs.append(w)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.8, depth=0.12, vertices=12, location=(0, 0, 0.22))
    c = bpy.context.active_object
    c.data.materials.append(mat_heart)
    objs.append(c)
    return objs

def build_cute_landmine():
    objs = []
    mat_m = create_toon_mat("m_clm", (0.3, 0.32, 0.38, 1.0))
    mat_core = create_toon_mat("m_clmc", (1.0, 0.32, 0.38, 1.0), emission=(1.0, 0.32, 0.38, 1.0), emission_str=4.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.95, depth=0.2, vertices=12, location=(0, 0, 0))
    m = bpy.context.active_object
    m.data.materials.append(mat_m)
    objs.append(m)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, 0, 0.15))
    c = bpy.context.active_object
    c.data.materials.append(mat_core)
    objs.append(c)
    return objs

def build_cute_repair_station():
    objs = []
    mat_p = create_toon_mat("m_crp", (0.85, 0.9, 0.95, 1.0))
    mat_cross = create_toon_mat("m_crpc", (0.25, 0.88, 0.45, 1.0), emission=(0.25, 0.88, 0.45, 1.0), emission_str=3.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.2, vertices=12, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_p)
    objs.append(p)

    for (sx, sy) in [(1.3, 0.4), (0.4, 1.3)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        c = bpy.context.active_object
        c.scale = (sx, sy, 0.12)
        c.data.materials.append(mat_cross)
        objs.append(c)
    return objs

def build_cute_gold_coin():
    objs = []
    mat_gold = create_toon_mat("m_cgc", (1.0, 0.82, 0.2, 1.0), emission=(1.0, 0.82, 0.2, 1.0), emission_str=2.0)
    mat_star = create_toon_mat("m_cgcs", (1.0, 0.98, 0.6, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.9, depth=0.25, vertices=12, location=(0, 0, 0))
    coin = bpy.context.active_object
    coin.data.materials.append(mat_gold)
    objs.append(coin)

    for i in range(5):
        angle = i * (2.0 * math.pi / 5.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.5, vertices=8, location=(math.cos(angle)*0.32, math.sin(angle)*0.32, 0.15))
        pt = bpy.context.active_object
        pt.rotation_euler = (math.radians(90), 0, angle)
        pt.data.materials.append(mat_star)
        objs.append(pt)
    return objs

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_warm_lighting(ortho_scale=3.2)

    render_and_clean(build_cute_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_cute_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_cute_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_cute_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_cute_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))
    render_and_clean(build_cute_gold_coin(), os.path.join(SPRITES_POWERUPS, "gold_coin.png"))

if __name__ == "__main__":
    main()
