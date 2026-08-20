import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
BLENDER_SAVE = os.path.join(PROJECT_DIR, "assets", "blender", "tank_battle_assets.blend")

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

def create_camera_and_lights(ortho_scale=3.4):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera = cam_obj

    # Key Directional Light
    light_data = bpy.data.lights.new(name='SunLight', type='SUN')
    light_data.energy = 4.5
    light_data.color = (1.0, 0.98, 0.92)
    light_obj = bpy.data.objects.new('SunLight', light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.location = (2, -3, 8)
    light_obj.rotation_euler = (math.radians(25), math.radians(15), math.radians(-35))

    # Fill Light
    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 150.0
    fill_data.color = (0.75, 0.88, 1.0)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-3, 3, 6)

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
        elif 'Emission' in bsdf.inputs:
            bsdf.inputs['Emission'].default_value = emission_color
    output = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    return mat

def build_tank(name_prefix, body_col, turret_col, track_col, trim_col, barrel_len=1.2, barrel_thick=0.16, frame=0, hull_w=1.35, hull_l=1.55):
    tank_group = []
    
    mat_body = create_material(f"{name_prefix}_body", body_col, roughness=0.25, metallic=0.08)
    mat_turret = create_material(f"{name_prefix}_turret", turret_col, roughness=0.2, metallic=0.12)
    mat_track = create_material(f"{name_prefix}_track", track_col, roughness=0.55, metallic=0.3)
    mat_trim = create_material(f"{name_prefix}_trim", trim_col, roughness=0.25, metallic=0.15)
    mat_dark = create_material(f"{name_prefix}_dark", (0.08, 0.08, 0.1, 1.0), roughness=0.7)

    # 1. Main Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0))
    hull = bpy.context.active_object
    hull.name = f"{name_prefix}_hull"
    hull.scale = (hull_w, hull_l, 0.5)
    hull.data.materials.append(mat_body)
    tank_group.append(hull)

    # Hull Front Sloped Armor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, hull_l*0.48, 0.06))
    front = bpy.context.active_object
    front.scale = (hull_w * 0.9, 0.32, 0.42)
    front.data.materials.append(mat_trim)
    tank_group.append(front)

    # 2. Tracks (Left & Right)
    track_w = 0.38
    track_x = hull_w * 0.5 + track_w * 0.5 - 0.02
    track_l = hull_l * 1.2
    for side, x_pos in [('L', -track_x), ('R', track_x)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        track = bpy.context.active_object
        track.name = f"{name_prefix}_track_{side}"
        track.scale = (track_w, track_l, 0.58)
        track.data.materials.append(mat_track)
        tank_group.append(track)

        # Track Treads (Animated)
        offset = 0.14 if frame == 1 else 0.0
        num_treads = 7
        for i in range(num_treads):
            y_pos = -track_l*0.42 + (i / float(num_treads - 1)) * (track_l * 0.84) + offset
            if y_pos > track_l * 0.46:
                y_pos -= track_l * 0.88
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, y_pos, 0.32))
            tread = bpy.context.active_object
            tread.scale = (track_w * 1.05, 0.08, 0.08)
            tread.data.materials.append(mat_dark)
            tank_group.append(tread)

    # 3. Turret
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.45))
    turret = bpy.context.active_object
    turret.name = f"{name_prefix}_turret"
    turret.scale = (0.85, 0.85, 0.45)
    turret.data.materials.append(mat_turret)
    tank_group.append(turret)

    # Turret Hatch
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.16, location=(0, -0.15, 0.72))
    hatch = bpy.context.active_object
    hatch.data.materials.append(mat_trim)
    tank_group.append(hatch)

    # 4. Gun Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick, depth=barrel_len, location=(0, 0.38 + barrel_len/2.0, 0.45))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_trim)
    tank_group.append(barrel)

    # Muzzle Brake
    bpy.ops.mesh.primitive_cylinder_add(radius=barrel_thick * 1.4, depth=0.18, location=(0, 0.38 + barrel_len, 0.45))
    muzzle = bpy.context.active_object
    muzzle.rotation_euler = (math.radians(90), 0, 0)
    muzzle.data.materials.append(mat_dark)
    tank_group.append(muzzle)

    return tank_group

def build_brick_tile():
    objs = []
    mat_brick = create_material("tile_brick_mat", (0.82, 0.32, 0.15, 1.0), roughness=0.7)
    mat_mortar = create_material("tile_mortar_mat", (0.2, 0.15, 0.12, 1.0), roughness=0.9)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.1))
    base = bpy.context.active_object
    base.scale = (2.8, 2.8, 0.2)
    base.data.materials.append(mat_mortar)
    objs.append(base)

    for row in range(4):
        for col in range(4):
            x = -1.05 + col * 0.7
            y = -1.05 + row * 0.7
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.1))
            brick = bpy.context.active_object
            brick.scale = (0.6, 0.6, 0.25)
            brick.data.materials.append(mat_brick)
            objs.append(brick)
    return objs

def build_steel_tile():
    objs = []
    mat_steel = create_material("tile_steel_mat", (0.75, 0.78, 0.82, 1.0), roughness=0.2, metallic=0.85)
    mat_dark_steel = create_material("tile_dark_steel", (0.35, 0.38, 0.42, 1.0), roughness=0.3, metallic=0.9)
    mat_bolt = create_material("tile_bolt_mat", (0.95, 0.95, 1.0, 1.0), roughness=0.15, metallic=0.95)

    for rx in [-0.7, 0.7]:
        for ry in [-0.7, 0.7]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0))
            plate = bpy.context.active_object
            plate.scale = (1.28, 1.28, 0.3)
            plate.data.materials.append(mat_steel)
            objs.append(plate)

            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, 0.18))
            inner = bpy.context.active_object
            inner.scale = (0.9, 0.9, 0.1)
            inner.data.materials.append(mat_dark_steel)
            objs.append(inner)

            for bx in [-0.45, 0.45]:
                for by in [-0.45, 0.45]:
                    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.1, location=(rx + bx, ry + by, 0.24))
                    bolt = bpy.context.active_object
                    bolt.data.materials.append(mat_bolt)
                    objs.append(bolt)
    return objs

def build_water_tile():
    objs = []
    mat_water = create_material("tile_water_mat", (0.1, 0.45, 0.92, 1.0), roughness=0.1, metallic=0.1)
    mat_crest = create_material("tile_crest_mat", (0.45, 0.85, 1.0, 1.0), roughness=0.1, emission_color=(0.3, 0.7, 1.0, 1.0), emission_strength=1.5)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    water = bpy.context.active_object
    water.scale = (2.8, 2.8, 0.3)
    water.data.materials.append(mat_water)
    objs.append(water)

    for y_pos in [-0.9, -0.1, 0.7]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=2.4, location=(0, y_pos, 0.18))
        wave = bpy.context.active_object
        wave.rotation_euler = (0, math.radians(90), 0)
        wave.data.materials.append(mat_crest)
        objs.append(wave)
    return objs

def build_trees_tile():
    objs = []
    mat_dark_green = create_material("tile_trees_dark", (0.08, 0.45, 0.12, 1.0), roughness=0.6)
    mat_light_green = create_material("tile_trees_light", (0.22, 0.75, 0.2, 1.0), roughness=0.5)

    positions = [
        (-0.7, -0.7, 0.4, 0.65), (0.7, -0.7, 0.4, 0.6),
        (-0.7, 0.7, 0.4, 0.62), (0.7, 0.7, 0.4, 0.68),
        (0, 0, 0.65, 0.75)
    ]
    for x, y, z, r in positions:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z))
        bush = bpy.context.active_object
        bush.data.materials.append(mat_dark_green)
        objs.append(bush)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=r*0.65, location=(x, y, z + 0.2))
        top_leaf = bpy.context.active_object
        top_leaf.data.materials.append(mat_light_green)
        objs.append(top_leaf)
    return objs

def build_ice_tile():
    objs = []
    mat_ice = create_material("tile_ice_mat", (0.82, 0.94, 1.0, 1.0), roughness=0.05, metallic=0.1)
    mat_frost = create_material("tile_frost_mat", (1.0, 1.0, 1.0, 1.0), roughness=0.1, emission_color=(0.9, 0.95, 1.0, 1.0), emission_strength=1.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ice = bpy.context.active_object
    ice.scale = (2.8, 2.8, 0.3)
    ice.data.materials.append(mat_ice)
    objs.append(ice)

    for pos in [(-0.6, -0.4), (0.4, 0.5), (-0.2, 0.2)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(pos[0], pos[1], 0.16))
        streak = bpy.context.active_object
        streak.scale = (1.0, 0.15, 0.05)
        streak.rotation_euler = (0, 0, math.radians(45))
        streak.data.materials.append(mat_frost)
        objs.append(streak)
    return objs

def build_eagle_base(destroyed=False):
    objs = []
    mat_base = create_material("base_stone", (0.25, 0.25, 0.28, 1.0) if not destroyed else (0.15, 0.12, 0.12, 1.0), roughness=0.6)
    mat_gold = create_material("base_gold", (0.95, 0.78, 0.15, 1.0), roughness=0.18, metallic=0.7)
    mat_rubble = create_material("base_rubble", (0.4, 0.2, 0.15, 1.0), roughness=0.9)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.scale = (2.6, 2.6, 0.35)
    ped.data.materials.append(mat_base)
    objs.append(ped)

    if not destroyed:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.1, 0.4))
        body = bpy.context.active_object
        body.scale = (0.7, 1.0, 0.4)
        body.data.materials.append(mat_gold)
        objs.append(body)

        for sign in [-1, 1]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * 0.75, 0.1, 0.4))
            wing = bpy.context.active_object
            wing.scale = (0.7, 0.55, 0.35)
            wing.rotation_euler = (0, 0, math.radians(sign * -25))
            wing.data.materials.append(mat_gold)
            objs.append(wing)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=0.3, location=(0, 0.55, 0.45))
        head = bpy.context.active_object
        head.data.materials.append(mat_gold)
        objs.append(head)
    else:
        for i, (rx, ry, rz, s) in enumerate([(-0.6, -0.4, 0.3, 0.4), (0.5, 0.3, 0.3, 0.5), (0, -0.2, 0.35, 0.6), (-0.3, 0.5, 0.25, 0.35)]):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rx, ry, rz))
            rubble = bpy.context.active_object
            rubble.scale = (s, s, s * 0.8)
            rubble.rotation_euler = (math.radians(i*30), math.radians(i*45), math.radians(i*20))
            rubble.data.materials.append(mat_rubble)
            objs.append(rubble)

    return objs

def build_bullet():
    objs = []
    mat_bullet = create_material("bullet_mat", (1.0, 0.85, 0.2, 1.0), roughness=0.1, emission_color=(1.0, 0.7, 0.1, 1.0), emission_strength=2.5)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0, 0))
    bullet = bpy.context.active_object
    bullet.scale = (0.7, 1.3, 0.7)
    bullet.data.materials.append(mat_bullet)
    objs.append(bullet)
    return objs

def build_explosion_frame(stage=0):
    objs = []
    mat_fire = create_material(f"exp_fire_{stage}", (1.0, 0.35, 0.05, 1.0), roughness=0.3, emission_color=(1.0, 0.5, 0.0, 1.0), emission_strength=3.5)
    mat_core = create_material(f"exp_core_{stage}", (1.0, 0.95, 0.4, 1.0), roughness=0.1, emission_color=(1.0, 0.95, 0.5, 1.0), emission_strength=4.5)
    mat_smoke = create_material(f"exp_smoke_{stage}", (0.2, 0.2, 0.25, 1.0), roughness=0.9)

    radius = 0.5 + stage * 0.45
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_core if stage < 2 else mat_smoke)
    objs.append(core)

    num_sparks = 6 + stage * 2
    for i in range(num_sparks):
        angle = i * (2.0 * math.pi / num_sparks)
        dist = radius * 0.9
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius * 0.4, location=(math.cos(angle)*dist, math.sin(angle)*dist, 0.1))
        spark = bpy.context.active_object
        spark.data.materials.append(mat_fire if stage < 3 else mat_smoke)
        objs.append(spark)

    return objs

def render_and_clean(objects, output_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"Rendered: {os.path.basename(output_path)}")

def main():
    clear_scene()
    setup_render_settings(res=128)
    create_camera_and_lights(ortho_scale=3.4)

    tanks_config = {
        "player_tank_yellow": {
            "body": (0.92, 0.68, 0.12, 1.0),
            "turret": (0.95, 0.75, 0.18, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (0.18, 0.62, 0.28, 1.0),
            "blen": 1.25, "bthick": 0.16
        },
        "player_tank_green": {
            "body": (0.22, 0.68, 0.25, 1.0),
            "turret": (0.28, 0.78, 0.32, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (0.92, 0.75, 0.18, 1.0),
            "blen": 1.25, "bthick": 0.16
        },
        "enemy_basic": {
            "body": (0.65, 0.70, 0.75, 1.0),
            "turret": (0.75, 0.80, 0.85, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (0.85, 0.25, 0.22, 1.0),
            "blen": 1.1, "bthick": 0.14
        },
        "enemy_fast": {
            "body": (0.25, 0.55, 0.95, 1.0),
            "turret": (0.35, 0.65, 1.0, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (1.0, 0.95, 0.95, 1.0),
            "blen": 1.35, "bthick": 0.13, "hull_w": 1.2, "hull_l": 1.4
        },
        "enemy_power": {
            "body": (0.88, 0.22, 0.22, 1.0),
            "turret": (0.95, 0.32, 0.28, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (0.95, 0.82, 0.2, 1.0),
            "blen": 1.6, "bthick": 0.15
        },
        "enemy_armor": {
            "body": (0.12, 0.42, 0.25, 1.0),
            "turret": (0.18, 0.52, 0.32, 1.0),
            "track": (0.25, 0.25, 0.28, 1.0),
            "trim": (0.75, 0.85, 0.25, 1.0),
            "blen": 1.45, "bthick": 0.22, "hull_w": 1.5, "hull_l": 1.7
        }
    }

    for name, cfg in tanks_config.items():
        for frame in [0, 1]:
            objs = build_tank(
                name_prefix=f"{name}_f{frame}",
                body_col=cfg["body"],
                turret_col=cfg["turret"],
                track_col=cfg["track"],
                trim_col=cfg["trim"],
                barrel_len=cfg["blen"],
                barrel_thick=cfg["bthick"],
                frame=frame,
                hull_w=cfg.get("hull_w", 1.35),
                hull_l=cfg.get("hull_l", 1.55)
            )
            out_file = os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png")
            render_and_clean(objs, out_file)

    tiles_renderers = {
        "tile_brick.png": build_brick_tile,
        "tile_steel.png": build_steel_tile,
        "tile_water.png": build_water_tile,
        "tile_trees.png": build_trees_tile,
        "tile_ice.png": build_ice_tile,
        "base_eagle.png": lambda: build_eagle_base(destroyed=False),
        "base_destroyed.png": lambda: build_eagle_base(destroyed=True)
    }

    for fname, builder in tiles_renderers.items():
        objs = builder()
        out_file = os.path.join(SPRITES_TILES, fname)
        render_and_clean(objs, out_file)

    objs = build_bullet()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "bullet.png"))

    for stage in range(4):
        objs = build_explosion_frame(stage)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"explosion_{stage}.png"))

    print("Rebuilding complete scene for .blend storage...")
    coll_tanks = bpy.data.collections.new("Tanks")
    coll_tiles = bpy.data.collections.new("Tiles")
    bpy.context.scene.collection.children.link(coll_tanks)
    bpy.context.scene.collection.children.link(coll_tiles)

    p_tank = build_tank("PlayerTankShowcase", (0.92, 0.68, 0.12, 1.0), (0.95, 0.75, 0.18, 1.0), (0.25, 0.25, 0.28, 1.0), (0.18, 0.62, 0.28, 1.0))
    for obj in p_tank:
        coll_tanks.objects.link(obj)

    os.makedirs(os.path.dirname(BLENDER_SAVE), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLENDER_SAVE)
    print(f"Successfully saved .blend file to: {BLENDER_SAVE}")

if __name__ == "__main__":
    main()
