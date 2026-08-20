import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def setup_render_settings(res=128):
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

def create_camera_and_lights():
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.0
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera = cam_obj

    light_data = bpy.data.lights.new(name='SunLight', type='SUN')
    light_data.energy = 4.5
    light_data.color = (1.0, 0.98, 0.95)
    light_obj = bpy.data.objects.new('SunLight', light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.location = (2, -3, 8)
    light_obj.rotation_euler = (math.radians(25), math.radians(15), math.radians(-35))

def create_material(name, color, roughness=0.2, metallic=0.1, emission_color=None, emission_strength=0.0):
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
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered: {os.path.basename(output_path)}")

def build_star():
    objs = []
    mat = create_material("mat_star", (1.0, 0.82, 0.1, 1.0), emission_color=(1.0, 0.8, 0.1, 1.0), emission_strength=2.0)
    mat_plate = create_material("mat_plate", (0.12, 0.15, 0.18, 1.0), roughness=0.5)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    plate = bpy.context.active_object
    plate.scale = (2.2, 2.2, 0.2)
    plate.data.materials.append(mat_plate)
    objs.append(plate)

    # 5-pointed star made with cylinders/cubes
    for i in range(5):
        angle = i * (2.0 * math.pi / 5.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.5, math.sin(angle)*0.5, 0.15))
        pt = bpy.context.active_object
        pt.scale = (0.35, 0.8, 0.2)
        pt.rotation_euler = (0, 0, angle + math.radians(90))
        pt.data.materials.append(mat)
        objs.append(pt)
    return objs

def build_bomb():
    objs = []
    mat_bomb = create_material("mat_bomb", (0.9, 0.2, 0.15, 1.0), roughness=0.2, emission_color=(0.9, 0.2, 0.15, 1.0), emission_strength=1.5)
    mat_plate = create_material("mat_plate_b", (0.12, 0.15, 0.18, 1.0))
    
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    plate = bpy.context.active_object
    plate.scale = (2.2, 2.2, 0.2)
    plate.data.materials.append(mat_plate)
    objs.append(plate)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.7, location=(0, -0.1, 0.2))
    bomb = bpy.context.active_object
    bomb.data.materials.append(mat_bomb)
    objs.append(bomb)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.3, location=(0, 0.6, 0.2))
    cap = bpy.context.active_object
    cap.data.materials.append(mat_plate)
    objs.append(cap)
    return objs

def build_clock():
    objs = []
    mat_clock = create_material("mat_clock", (0.2, 0.6, 0.95, 1.0), roughness=0.1, emission_color=(0.2, 0.6, 0.95, 1.0), emission_strength=1.5)
    mat_face = create_material("mat_face", (0.95, 0.98, 1.0, 1.0), roughness=0.2)
    mat_needle = create_material("mat_needle", (0.1, 0.1, 0.15, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.95, depth=0.25, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_clock)
    objs.append(rim)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.8, depth=0.1, location=(0, 0, 0.1))
    face = bpy.context.active_object
    face.data.materials.append(mat_face)
    objs.append(face)

    # Needles
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.25, 0.2))
    n1 = bpy.context.active_object
    n1.scale = (0.08, 0.5, 0.05)
    n1.data.materials.append(mat_needle)
    objs.append(n1)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.2, 0, 0.2))
    n2 = bpy.context.active_object
    n2.scale = (0.4, 0.08, 0.05)
    n2.data.materials.append(mat_needle)
    objs.append(n2)
    return objs

def build_helmet():
    objs = []
    mat_shield = create_material("mat_shield", (0.18, 0.85, 0.45, 1.0), roughness=0.15, emission_color=(0.18, 0.85, 0.45, 1.0), emission_strength=2.0)
    mat_inner = create_material("mat_inner", (0.8, 1.0, 0.85, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.9, depth=0.2, vertices=6, location=(0, 0, 0))
    sh = bpy.context.active_object
    sh.data.materials.append(mat_shield)
    objs.append(sh)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.1, vertices=6, location=(0, 0, 0.1))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_inner)
    objs.append(inner)
    return objs

def build_shovel():
    objs = []
    mat_plate = create_material("mat_plate_s", (0.12, 0.15, 0.18, 1.0))
    mat_metal = create_material("mat_metal_s", (0.85, 0.88, 0.92, 1.0), metallic=0.9, roughness=0.2)
    mat_handle = create_material("mat_handle", (0.85, 0.5, 0.15, 1.0))

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    plate = bpy.context.active_object
    plate.scale = (2.2, 2.2, 0.2)
    plate.data.materials.append(mat_plate)
    objs.append(plate)

    # Shovel blade
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.35, 0.35, 0.15))
    blade = bpy.context.active_object
    blade.scale = (0.7, 0.7, 0.1)
    blade.rotation_euler = (0, 0, math.radians(45))
    blade.data.materials.append(mat_metal)
    objs.append(blade)

    # Shovel shaft
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=1.4, location=(-0.25, -0.25, 0.15))
    shaft = bpy.context.active_object
    shaft.rotation_euler = (0, math.radians(90), math.radians(45))
    shaft.data.materials.append(mat_handle)
    objs.append(shaft)
    return objs

def build_spawn_star():
    objs = []
    mat_star = create_material("mat_spawn_star", (0.2, 0.95, 1.0, 1.0), emission_color=(0.2, 0.95, 1.0, 1.0), emission_strength=4.0)
    for i in range(8):
        angle = i * (2.0 * math.pi / 8.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(angle)*0.55, math.sin(angle)*0.55, 0))
        pt = bpy.context.active_object
        pt.scale = (0.15, 0.9, 0.1)
        pt.rotation_euler = (0, 0, angle + math.radians(90))
        pt.data.materials.append(mat_star)
        objs.append(pt)
    return objs

def main():
    clear_scene()
    setup_render_settings(res=128)
    create_camera_and_lights()

    items = {
        (SPRITES_POWERUPS, "star.png"): build_star,
        (SPRITES_POWERUPS, "bomb.png"): build_bomb,
        (SPRITES_POWERUPS, "clock.png"): build_clock,
        (SPRITES_POWERUPS, "helmet.png"): build_helmet,
        (SPRITES_POWERUPS, "shovel.png"): build_shovel,
        (SPRITES_EFFECTS, "spawn_star.png"): build_spawn_star
    }

    for (folder, fname), builder in items.items():
        objs = builder()
        out_file = os.path.join(folder, fname)
        render_and_clean(objs, out_file)

if __name__ == "__main__":
    main()
