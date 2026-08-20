import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

os.makedirs(SPRITES_UI, exist_ok=True)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_render_settings(rx=256, ry=256):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    if hasattr(scene, 'cycles'):
        scene.cycles.samples = 20
        scene.cycles.adaptive_threshold = 0.04
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    
    # 采用 AgX 色彩管理柔和滚降
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        scene.view_settings.view_transform = 'Filmic'

def create_sokpop_warm_lighting(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunWarmCozy', type='SUN')
    sun_data.energy = 2.6
    sun_data.color = (1.0, 0.94, 0.86)
    sun_obj = bpy.data.objects.new('SunWarmCozy', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (2.5, -3.5, 7.5)
    sun_obj.rotation_euler = (math.radians(38), math.radians(18), math.radians(-32))

    fill_data = bpy.data.lights.new(name='ClayFillLight', type='POINT')
    fill_data.energy = 16.0
    fill_data.color = (0.92, 0.88, 0.98)
    fill_obj = bpy.data.objects.new('ClayFillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-3.5, 3.5, 5.5)

    rim_data = bpy.data.lights.new(name='ClayBounce', type='POINT')
    rim_data.energy = 10.0
    rim_data.color = (1.0, 0.96, 0.90)
    rim_obj = bpy.data.objects.new('ClayBounce', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 4.5, 3.5)

def create_sokpop_clay_mat(name, col, roughness=0.76, sss_weight=0.08, emission=None, emission_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = 0.0

    if 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = sss_weight
    elif 'Subsurface' in bsdf.inputs:
        bsdf.inputs['Subsurface'].default_value = sss_weight

    if emission and emission_str > 0:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission
            bsdf.inputs['Emission Strength'].default_value = emission_str
    out = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat

def add_smooth_clay_bevel(obj, width=0.15, segments=4):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
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
    print(f"Rendered Clay UI: {os.path.basename(out_path)}")

# ==================== SOKPOP CLAY UI BUILDERS ===================

def build_clay_title_banner():
    objs = []
    mat_banner = create_sokpop_clay_mat("m_uib", (0.96, 0.78, 0.22, 1.0))
    mat_border = create_sokpop_clay_mat("m_uibrd", (0.92, 0.52, 0.28, 1.0))
    mat_chick = create_sokpop_clay_mat("m_uichick", (0.98, 0.82, 0.22, 1.0))
    mat_blush = create_sokpop_clay_mat("m_uiblush", (0.98, 0.45, 0.55, 1.0))
    mat_eyes = create_sokpop_clay_mat("m_uieyes", (0.15, 0.15, 0.2, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    base = bpy.context.active_object
    base.scale = (4.8, 1.6, 0.35)
    base.data.materials.append(mat_border)
    add_smooth_clay_bevel(base, width=0.22, segments=4)
    objs.append(base)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    inner = bpy.context.active_object
    inner.scale = (4.4, 1.25, 0.35)
    inner.data.materials.append(mat_banner)
    add_smooth_clay_bevel(inner, width=0.18, segments=4)
    objs.append(inner)

    for sx in [-1.75, 1.75]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(sx, 0.15, 0.42))
        c = bpy.context.active_object
        c.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(c)

        for ex in [-0.08, 0.08]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx + ex, 0.42, 0.48))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_eyes)
            bpy.ops.object.shade_smooth()
            objs.append(eye)

        for bx in [-0.14, 0.14]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(sx + bx, 0.41, 0.40))
            bl = bpy.context.active_object
            bl.data.materials.append(mat_blush)
            bpy.ops.object.shade_smooth()
            objs.append(bl)

    return objs

def build_clay_button(state="normal"):
    objs = []
    col = (0.95, 0.82, 0.32, 1.0)
    col_rim = (0.90, 0.52, 0.25, 1.0)
    z_scale = 0.35
    if state == "hover":
        col = (0.98, 0.86, 0.38, 1.0)
        col_rim = (0.95, 0.60, 0.25, 1.0)
    elif state == "pressed":
        col = (0.90, 0.58, 0.28, 1.0)
        col_rim = (0.78, 0.42, 0.20, 1.0)
        z_scale = 0.22

    mat_b = create_sokpop_clay_mat(f"m_btn_{state}", col)
    mat_r = create_sokpop_clay_mat(f"m_btn_r_{state}", col_rim)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.scale = (3.8, 1.15, z_scale)
    rim.data.materials.append(mat_r)
    add_smooth_clay_bevel(rim, width=0.22, segments=4)
    objs.append(rim)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.12))
    inner = bpy.context.active_object
    inner.scale = (3.5, 0.9, z_scale)
    inner.data.materials.append(mat_b)
    add_smooth_clay_bevel(inner, width=0.18, segments=4)
    objs.append(inner)

    return objs

def build_clay_heart(full=True):
    objs = []
    col = (0.92, 0.32, 0.42, 1.0) if full else (0.42, 0.44, 0.50, 1.0)
    mat_h = create_sokpop_clay_mat(f"m_heart_{full}", col)

    for sx in [-0.38, 0.38]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.52, location=(sx, 0.25, 0))
        sph = bpy.context.active_object
        sph.data.materials.append(mat_h)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    bpy.ops.mesh.primitive_cone_add(radius1=0.74, depth=1.1, location=(0, -0.32, 0))
    cone = bpy.context.active_object
    cone.rotation_euler = (0, 0, math.radians(180))
    cone.data.materials.append(mat_h)
    add_smooth_clay_bevel(cone, width=0.15, segments=3)
    objs.append(cone)

    return objs

def main():
    clear_scene()
    setup_render_settings(rx=512, ry=200)
    create_sokpop_warm_lighting(ortho_scale=5.2)

    print(">>> Re-rendering Calibrated Sokpop Clay UI Assets...")
    render_and_clean(build_clay_title_banner(), os.path.join(SPRITES_UI, "title_banner.png"))

    setup_render_settings(rx=384, ry=96)
    create_sokpop_warm_lighting(ortho_scale=4.2)
    render_and_clean(build_clay_button("normal"), os.path.join(SPRITES_UI, "btn_clay_normal.png"))
    render_and_clean(build_clay_button("hover"), os.path.join(SPRITES_UI, "btn_clay_hover.png"))
    render_and_clean(build_clay_button("pressed"), os.path.join(SPRITES_UI, "btn_clay_pressed.png"))

    setup_render_settings(rx=128, ry=128)
    create_sokpop_warm_lighting(ortho_scale=2.2)
    render_and_clean(build_clay_heart(True), os.path.join(SPRITES_UI, "hp_heart_full.png"))
    render_and_clean(build_clay_heart(False), os.path.join(SPRITES_UI, "hp_heart_empty.png"))

    print("All UI Textures Calibrated and Rendered Successfully!")

if __name__ == "__main__":
    main()
