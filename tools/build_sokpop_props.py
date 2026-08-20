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

def create_sokpop_warm_lighting(ortho_scale=3.2):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunWarmKey', type='SUN')
    sun_data.energy = 4.8
    sun_data.color = (1.0, 0.93, 0.82)
    sun_obj = bpy.data.objects.new('SunWarmKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (2.5, -3.5, 7.5)
    sun_obj.rotation_euler = (math.radians(38), math.radians(18), math.radians(-32))

    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 180.0
    fill_data.color = (0.95, 0.90, 0.98)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-3.5, 3.5, 5.5)

def create_sokpop_clay_mat(name, col, roughness=0.76, emission=None, emission_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = 0.0
    if 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = 0.08
    elif 'Subsurface' in bsdf.inputs:
        bsdf.inputs['Subsurface'].default_value = 0.08

    if emission and emission_str > 0:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission
            bsdf.inputs['Emission Strength'].default_value = emission_str
    out = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def add_smooth_clay_bevel(obj, width=0.12, segments=3):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    mod = obj.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(22)

def render_and_clean(objects, out_path):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered Sokpop Clay: {os.path.basename(out_path)}")

# ==================== BUILDINGS ====================

def build_sokpop_turret_base():
    objs = []
    mat_b = create_sokpop_clay_mat("m_sctb", (0.38, 0.42, 0.48, 1.0))
    mat_r = create_sokpop_clay_mat("m_sctr", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.25, vertices=16, location=(0, 0, 0))
    b = bpy.context.active_object
    b.data.materials.append(mat_b)
    add_smooth_clay_bevel(b, width=0.08, segments=3)
    objs.append(b)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.9, minor_radius=0.08, location=(0, 0, 0.12))
    r = bpy.context.active_object
    r.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(r)
    return objs

def build_sokpop_turret_gun():
    objs = []
    mat_g = create_sokpop_clay_mat("m_sctg", (0.32, 0.65, 0.95, 1.0))
    mat_m = create_sokpop_clay_mat("m_sctm", (1.0, 0.82, 0.22, 1.0))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, -0.08, 0.2))
    d = bpy.context.active_object
    d.scale = (1.0, 1.0, 0.85)
    d.data.materials.append(mat_g)
    bpy.ops.object.shade_smooth()
    objs.append(d)

    for bx in [-0.22, 0.22]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.1, depth=1.2, vertices=16, location=(bx, 0.5, 0.2))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_g)
        add_smooth_clay_bevel(barrel, width=0.04, segments=2)
        objs.append(barrel)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.06, location=(bx, 1.1, 0.2))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_m)
        bpy.ops.object.shade_smooth()
        objs.append(muzzle)
    return objs

def build_sokpop_fortified_wall():
    objs = []
    mat_w = create_sokpop_clay_mat("m_scfw", (0.38, 0.46, 0.55, 1.0))
    mat_heart = create_sokpop_clay_mat("m_scfwh", (1.0, 0.42, 0.55, 1.0), emission=(1.0, 0.42, 0.55, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    w = bpy.context.active_object
    w.scale = (2.8, 2.8, 0.38)
    w.data.materials.append(mat_w)
    add_smooth_clay_bevel(w, width=0.22, segments=4)
    objs.append(w)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.8, depth=0.12, vertices=16, location=(0, 0, 0.22))
    c = bpy.context.active_object
    c.data.materials.append(mat_heart)
    add_smooth_clay_bevel(c, width=0.06, segments=2)
    objs.append(c)
    return objs

def build_sokpop_landmine():
    objs = []
    mat_m = create_sokpop_clay_mat("m_sclm", (0.32, 0.35, 0.40, 1.0))
    mat_core = create_sokpop_clay_mat("m_sclmc", (1.0, 0.35, 0.42, 1.0), emission=(1.0, 0.35, 0.42, 1.0), emission_str=3.5)
    mat_eyes = create_sokpop_clay_mat("m_scley", (0.15, 0.15, 0.2, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.95, depth=0.2, vertices=16, location=(0, 0, 0))
    m = bpy.context.active_object
    m.data.materials.append(mat_m)
    add_smooth_clay_bevel(m, width=0.08, segments=3)
    objs.append(m)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0, 0, 0.15))
    c = bpy.context.active_object
    c.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(c)

    # Sokpop Cute Smiley Face Eyes (^.^) on Landmine
    for ex in [-0.25, 0.25]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(ex, 0.15, 0.52))
        eye = bpy.context.active_object
        eye.data.materials.append(mat_eyes)
        bpy.ops.object.shade_smooth()
        objs.append(eye)

    return objs

def build_sokpop_repair_station():
    objs = []
    mat_p = create_sokpop_clay_mat("m_scrp", (0.92, 0.94, 0.96, 1.0))
    mat_cross = create_sokpop_clay_mat("m_scrpc", (0.32, 0.85, 0.45, 1.0), emission=(0.32, 0.85, 0.45, 1.0), emission_str=3.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.2, vertices=16, location=(0, 0, 0))
    p = bpy.context.active_object
    p.data.materials.append(mat_p)
    add_smooth_clay_bevel(p, width=0.08, segments=3)
    objs.append(p)

    for (sx, sy) in [(1.3, 0.4), (0.4, 1.3)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        c = bpy.context.active_object
        c.scale = (sx, sy, 0.12)
        c.data.materials.append(mat_cross)
        add_smooth_clay_bevel(c, width=0.06, segments=2)
        objs.append(c)
    return objs

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_warm_lighting(ortho_scale=3.2)

    render_and_clean(build_sokpop_turret_base(), os.path.join(SPRITES_BUILDINGS, "turret_base.png"))
    render_and_clean(build_sokpop_turret_gun(), os.path.join(SPRITES_BUILDINGS, "turret_gun.png"))
    render_and_clean(build_sokpop_fortified_wall(), os.path.join(SPRITES_BUILDINGS, "fortified_wall.png"))
    render_and_clean(build_sokpop_landmine(), os.path.join(SPRITES_BUILDINGS, "landmine.png"))
    render_and_clean(build_sokpop_repair_station(), os.path.join(SPRITES_BUILDINGS, "repair_station.png"))

if __name__ == "__main__":
    main()
