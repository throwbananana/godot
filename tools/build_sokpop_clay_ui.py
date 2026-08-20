import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
SPRITES_MAP = os.path.join(PROJECT_DIR, "assets", "sprites", "map")
BLENDER_SAVE = os.path.join(PROJECT_DIR, "assets", "blender", "tank_battle_assets.blend")

for folder in [SPRITES_UI, SPRITES_MAP]:
    os.makedirs(folder, exist_ok=True)

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
    scene.view_settings.view_transform = 'Standard'

def create_sokpop_warm_lighting(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunWarmCozy', type='SUN')
    sun_data.energy = 4.8
    sun_data.color = (1.0, 0.93, 0.82)
    sun_obj = bpy.data.objects.new('SunWarmCozy', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (2.5, -3.5, 7.5)
    sun_obj.rotation_euler = (math.radians(38), math.radians(18), math.radians(-32))

    fill_data = bpy.data.lights.new(name='ClayFillLight', type='POINT')
    fill_data.energy = 180.0
    fill_data.color = (0.95, 0.90, 0.98)
    fill_obj = bpy.data.objects.new('ClayFillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-3.5, 3.5, 5.5)

    rim_data = bpy.data.lights.new(name='ClayBounce', type='POINT')
    rim_data.energy = 90.0
    rim_data.color = (1.0, 0.96, 0.88)
    rim_obj = bpy.data.objects.new('ClayBounce', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 4.5, 3.5)

def create_sokpop_clay_mat(name, col, roughness=0.76, sss_weight=0.10, emission=None, emission_str=0.0):
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

# ==================== SOKPOP CLAY UI BUILDERS ====================

def build_clay_title_banner():
    objs = []
    mat_banner = create_sokpop_clay_mat("m_uib", (0.96, 0.78, 0.22, 1.0)) # Butter Clay
    mat_border = create_sokpop_clay_mat("m_uibrd", (0.92, 0.52, 0.28, 1.0)) # Terracotta Biscuit Clay
    mat_chick = create_sokpop_clay_mat("m_uichick", (1.0, 0.86, 0.25, 1.0))
    mat_blush = create_sokpop_clay_mat("m_uiblush", (1.0, 0.45, 0.55, 1.0))
    mat_eyes = create_sokpop_clay_mat("m_uieyes", (0.15, 0.15, 0.2, 1.0))

    # Outer Biscuit Clay Base
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    base = bpy.context.active_object
    base.scale = (4.8, 1.6, 0.35)
    base.data.materials.append(mat_border)
    add_smooth_clay_bevel(base, width=0.22, segments=4)
    objs.append(base)

    # Inner Butter Clay Crest
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    inner = bpy.context.active_object
    inner.scale = (4.4, 1.25, 0.35)
    inner.data.materials.append(mat_banner)
    add_smooth_clay_bevel(inner, width=0.18, segments=4)
    objs.append(inner)

    # Little mascot chick on top left & top right
    for sx in [-1.75, 1.75]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(sx, 0.15, 0.42))
        c = bpy.context.active_object
        c.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(c)

        # Dot eyes
        for ex in [-0.08, 0.08]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx + ex, 0.42, 0.48))
            eye = bpy.context.active_object
            eye.data.materials.append(mat_eyes)
            bpy.ops.object.shade_smooth()
            objs.append(eye)

        # Pink Blush
        for bx in [-0.14, 0.14]:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(sx + bx, 0.41, 0.40))
            bl = bpy.context.active_object
            bl.data.materials.append(mat_blush)
            bpy.ops.object.shade_smooth()
            objs.append(bl)

    return objs

def build_clay_button(state="normal"):
    objs = []
    # normal, hover, pressed
    col = (0.95, 0.82, 0.32, 1.0) # Butter Yellow Clay
    col_rim = (0.90, 0.52, 0.25, 1.0)
    z_scale = 0.35
    if state == "hover":
        col = (0.98, 0.88, 0.42, 1.0)
        col_rim = (1.0, 0.65, 0.30, 1.0)
    elif state == "pressed":
        col = (0.90, 0.58, 0.28, 1.0) # Terracotta
        col_rim = (0.78, 0.42, 0.20, 1.0)
        z_scale = 0.22

    mat_b = create_sokpop_clay_mat(f"m_btn_{state}", col)
    mat_r = create_sokpop_clay_mat(f"m_btn_r_{state}", col_rim)

    # Base Rim
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.scale = (3.8, 1.15, z_scale)
    rim.data.materials.append(mat_r)
    add_smooth_clay_bevel(rim, width=0.22, segments=4)
    objs.append(rim)

    # Inner Pillow Clay
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.12))
    inner = bpy.context.active_object
    inner.scale = (3.5, 0.9, z_scale)
    inner.data.materials.append(mat_b)
    add_smooth_clay_bevel(inner, width=0.18, segments=4)
    objs.append(inner)

    return objs

def build_clay_panel(w=5.0, h=4.0):
    objs = []
    mat_frame = create_sokpop_clay_mat("m_p_frame", (0.32, 0.35, 0.42, 1.0)) # Cozy Slate Clay
    mat_inner = create_sokpop_clay_mat("m_p_inner", (0.16, 0.18, 0.22, 1.0)) # Dark Clay Slate

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    frame = bpy.context.active_object
    frame.scale = (w, h, 0.35)
    frame.data.materials.append(mat_frame)
    add_smooth_clay_bevel(frame, width=0.25, segments=4)
    objs.append(frame)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.1))
    inner = bpy.context.active_object
    inner.scale = (w - 0.5, h - 0.5, 0.3)
    inner.data.materials.append(mat_inner)
    add_smooth_clay_bevel(inner, width=0.18, segments=4)
    objs.append(inner)

    return objs

def build_clay_heart(full=True):
    objs = []
    col = (0.95, 0.35, 0.45, 1.0) if full else (0.4, 0.42, 0.48, 1.0)
    mat_h = create_sokpop_clay_mat(f"m_heart_{full}", col)

    # 2 round spheres + 1 cone base = Cute Clay Heart
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

# ==================== SOKPOP CLAY MAP TOKENS ====================

def build_clay_map_node(type_name):
    objs = []
    # Token Disc Base
    mat_base = create_sokpop_clay_mat("m_nt_b", (0.92, 0.88, 0.82, 1.0))
    bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=0.35, vertices=16, location=(0, 0, 0))
    disc = bpy.context.active_object
    disc.data.materials.append(mat_base)
    add_smooth_clay_bevel(disc, width=0.12, segments=3)
    objs.append(disc)

    if type_name == "battle":
        # Crossed Clay Swords
        mat_sw = create_sokpop_clay_mat("m_nt_sw", (0.95, 0.45, 0.28, 1.0))
        for ang in [-35, 35]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=1.6, vertices=12, location=(0, 0, 0.25))
            sw = bpy.context.active_object
            sw.rotation_euler = (0, 0, math.radians(ang))
            sw.data.materials.append(mat_sw)
            add_smooth_clay_bevel(sw, width=0.04, segments=2)
            objs.append(sw)
    elif type_name == "elite":
        # Cute Red Skull
        mat_sk = create_sokpop_clay_mat("m_nt_sk", (0.95, 0.32, 0.38, 1.0))
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
        # Cute Campfire
        mat_f = create_sokpop_clay_mat("m_nt_f", (1.0, 0.65, 0.15, 1.0))
        bpy.ops.mesh.primitive_cone_add(radius1=0.45, depth=0.8, location=(0, 0.1, 0.28))
        fl = bpy.context.active_object
        fl.data.materials.append(mat_f)
        bpy.ops.object.shade_smooth()
        objs.append(fl)
    elif type_name == "shop":
        # Gold Chest / Coin
        mat_g = create_sokpop_clay_mat("m_nt_g", (1.0, 0.82, 0.22, 1.0))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.25))
        box = bpy.context.active_object
        box.scale = (0.9, 0.7, 0.5)
        box.data.materials.append(mat_g)
        add_smooth_clay_bevel(box, width=0.1, segments=3)
        objs.append(box)
    elif type_name == "event":
        # Question Token
        mat_q = create_sokpop_clay_mat("m_nt_q", (0.65, 0.45, 0.95, 1.0))
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
        # Golden Royal Crown
        mat_cr = create_sokpop_clay_mat("m_nt_cr", (1.0, 0.85, 0.22, 1.0))
        mat_rb = create_sokpop_clay_mat("m_nt_rb", (0.95, 0.25, 0.35, 1.0))
        bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.45, vertices=16, location=(0, 0, 0.25))
        cr = bpy.context.active_object
        cr.data.materials.append(mat_cr)
        add_smooth_clay_bevel(cr, width=0.1, segments=3)
        objs.append(cr)
        for i in range(3):
            angle = (i - 1) * 0.4
            bpy.ops.mesh.primitive_cone_add(radius1=0.18, depth=0.4, location=(math.sin(angle)*0.55, math.cos(angle)*0.2 + 0.1, 0.52))
            pt = bpy.context.active_object
            pt.data.materials.append(mat_cr)
            objs.append(pt)

    return objs

def build_clay_active_ring():
    objs = []
    mat_r = create_sokpop_clay_mat("m_ar_r", (0.35, 0.95, 0.55, 1.0), emission=(0.35, 0.95, 0.55, 1.0), emission_str=2.5)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.35, minor_radius=0.14, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_r)
    bpy.ops.object.shade_smooth()
    objs.append(ring)
    return objs

def main():
    clear_scene()
    setup_render_settings(rx=512, ry=200)
    create_sokpop_warm_lighting(ortho_scale=5.2)

    print(">>> Rendering Sokpop Clay UI Assets...")
    # 1. Title Banner
    render_and_clean(build_clay_title_banner(), os.path.join(SPRITES_UI, "title_banner.png"))

    # 2. Buttons
    setup_render_settings(rx=384, ry=96)
    create_sokpop_warm_lighting(ortho_scale=4.2)
    render_and_clean(build_clay_button("normal"), os.path.join(SPRITES_UI, "btn_clay_normal.png"))
    render_and_clean(build_clay_button("hover"), os.path.join(SPRITES_UI, "btn_clay_hover.png"))
    render_and_clean(build_clay_button("pressed"), os.path.join(SPRITES_UI, "btn_clay_pressed.png"))

    # 3. Hearts
    setup_render_settings(rx=128, ry=128)
    create_sokpop_warm_lighting(ortho_scale=2.2)
    render_and_clean(build_clay_heart(True), os.path.join(SPRITES_UI, "hp_heart_full.png"))
    render_and_clean(build_clay_heart(False), os.path.join(SPRITES_UI, "hp_heart_empty.png"))

    # 4. Spire Map Nodes
    setup_render_settings(rx=256, ry=256)
    create_sokpop_warm_lighting(ortho_scale=3.2)
    for node_type in ["battle", "elite", "rest", "shop", "event", "boss"]:
        render_and_clean(build_clay_map_node(node_type), os.path.join(SPRITES_MAP, f"node_{node_type}.png"))
    render_and_clean(build_clay_active_ring(), os.path.join(SPRITES_MAP, "node_active_ring.png"))

    print("All Sokpop Clay UI Assets Successfully Rendered!")

if __name__ == "__main__":
    main()
