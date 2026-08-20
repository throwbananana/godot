import bpy
import math
import os

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")

for folder in [SPRITES_EFFECTS, SPRITES_TILES]:
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
    
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        scene.view_settings.view_transform = 'Filmic'

def create_lighting(ortho_scale=3.3):
    cam_data = bpy.data.cameras.new(name='TopDownCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new('TopDownCam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, 0, 10)
    bpy.context.scene.camera = cam_obj

    sun_data = bpy.data.lights.new(name='SunKey', type='SUN')
    sun_data.energy = 2.6
    sun_data.color = (1.0, 0.94, 0.86)
    sun_obj = bpy.data.objects.new('SunKey', sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (3, -3, 8)
    sun_obj.rotation_euler = (math.radians(38), math.radians(18), math.radians(-32))

    fill_data = bpy.data.lights.new(name='FillLight', type='POINT')
    fill_data.energy = 16.0
    fill_data.color = (0.92, 0.88, 0.98)
    fill_obj = bpy.data.objects.new('FillLight', fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.location = (-4, 4, 6)

    rim_data = bpy.data.lights.new(name='RimLight', type='POINT')
    rim_data.energy = 10.0
    rim_data.color = (1.0, 0.96, 0.90)
    rim_obj = bpy.data.objects.new('RimLight', rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (0, 5, 4.5)

def create_clay_mat(name, col, roughness=0.76, sss_weight=0.08, emission=None, emission_str=0.0):
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

def apply_bevel(obj, width=0.12, segments=4):
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
    print(f"Rendered Animation Asset: {os.path.basename(out_path)}")

# ==================== 1. 开火枪口火花 (MUZZLE FLASH 3 FRAMES) ====================

def build_muzzle_flash(frame_idx):
    objs = []
    mat_core = create_clay_mat(f"m_mf_c_{frame_idx}", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=3.5)
    mat_ring = create_clay_mat(f"m_mf_r_{frame_idx}", (0.98, 0.55, 0.18, 1.0), emission=(0.98, 0.55, 0.18, 1.0), emission_str=2.0)

    scale_mult = [0.65, 1.15, 0.8][frame_idx]
    rot = frame_idx * 0.45

    # Center Clay Fireball
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45 * scale_mult, location=(0, 0, 0))
    sph = bpy.context.active_object
    sph.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(sph)

    # 4 Fluffy Clay Starburst Spikes
    for i in range(4):
        ang = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cone_add(radius1=0.22 * scale_mult, depth=0.75 * scale_mult, location=(math.cos(ang)*0.45*scale_mult, math.sin(ang)*0.45*scale_mult, 0))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, math.radians(90), ang)
        cone.data.materials.append(mat_ring)
        apply_bevel(cone, width=0.04, segments=2)
        objs.append(cone)

    return objs

# ==================== 2. 受击飞溅陶泥碎屑 (CLAY DEBRIS 4 FRAMES) ====================

def build_clay_debris(frame_idx):
    objs = []
    mat_clay = create_clay_mat(f"m_deb_{frame_idx}", (0.92, 0.48, 0.28, 1.0))
    mat_white = create_clay_mat(f"m_deb_w_{frame_idx}", (0.98, 0.85, 0.45, 1.0))

    dist = 0.25 + frame_idx * 0.35
    scale_factor = max(0.2, 0.9 - frame_idx * 0.2)

    for i in range(6):
        ang = i * (2.0 * math.pi / 6.0) + frame_idx * 0.3
        d = dist * (0.8 + (i % 3) * 0.2)
        r = (0.16 if i % 2 == 0 else 0.12) * scale_factor
        mat_curr = mat_clay if i % 2 == 0 else mat_white
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(ang)*d, math.sin(ang)*d, 0))
        sp = bpy.context.active_object
        sp.data.materials.append(mat_curr)
        bpy.ops.object.shade_smooth()
        objs.append(sp)

    return objs

# ==================== 3. 护盾力场泡泡 (SHIELD BUBBLE 4 FRAMES) ====================

def build_shield_bubble(frame_idx):
    objs = []
    mat_ring = create_clay_mat(f"m_sh_{frame_idx}", (0.28, 0.88, 0.78, 1.0), emission=(0.28, 0.88, 0.78, 1.0), emission_str=2.5)
    mat_spark = create_clay_mat(f"m_sh_sp_{frame_idx}", (0.95, 0.98, 1.0, 1.0), emission=(0.95, 0.98, 1.0, 1.0), emission_str=3.0)

    pulse_scale = 1.25 + math.sin(frame_idx * (math.pi / 2.0)) * 0.12
    rot = frame_idx * (math.pi / 4.0)

    # Outer Shield Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=pulse_scale, minor_radius=0.12, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_ring)
    bpy.ops.object.shade_smooth()
    objs.append(ring)

    # Orbiting Beads
    for i in range(4):
        ang = rot + i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(math.cos(ang)*pulse_scale, math.sin(ang)*pulse_scale, 0))
        bead = bpy.context.active_object
        bead.data.materials.append(mat_spark)
        bpy.ops.object.shade_smooth()
        objs.append(bead)

    return objs

# ==================== 4. 等离子冲击波 (SHOCKWAVE 4 FRAMES) ====================

def build_shockwave(frame_idx):
    objs = []
    mat_wave = create_clay_mat(f"m_sw_{frame_idx}", (0.35, 0.85, 1.0, 1.0), emission=(0.35, 0.85, 1.0, 1.0), emission_str=3.0)
    rad = 0.45 + frame_idx * 0.35
    thick = max(0.04, 0.16 - frame_idx * 0.035)

    bpy.ops.mesh.primitive_torus_add(major_radius=rad, minor_radius=thick, location=(0, 0, 0))
    tor = bpy.context.active_object
    tor.data.materials.append(mat_wave)
    bpy.ops.object.shade_smooth()
    objs.append(tor)
    return objs

# ==================== 5. 砖块击碎尘埃烟团 (DUST PUFF 4 FRAMES) ====================

def build_dust_puff(frame_idx):
    objs = []
    mat_dust = create_clay_mat(f"m_dp_{frame_idx}", (0.85, 0.78, 0.72, 1.0))
    scale_factor = 0.4 + frame_idx * 0.2
    dist = 0.15 + frame_idx * 0.22

    for i in range(5):
        ang = i * (2.0 * math.pi / 5.0) + frame_idx * 0.2
        r = 0.32 * scale_factor
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(math.cos(ang)*dist, math.sin(ang)*dist, 0))
        puff = bpy.context.active_object
        puff.data.materials.append(mat_dust)
        bpy.ops.object.shade_smooth()
        objs.append(puff)
    return objs

# ==================== 6. 基地受损晕厥表情 (BASE DAMAGED) ====================

def build_base_damaged():
    objs = []
    mat_ped = create_clay_mat("m_bd_p", (0.85, 0.80, 0.74, 1.0))
    mat_chick = create_clay_mat("m_bd_c", (0.98, 0.78, 0.25, 1.0))
    mat_beak = create_clay_mat("m_bd_b", (0.98, 0.52, 0.15, 1.0))
    mat_blush = create_clay_mat("m_bd_bl", (0.98, 0.42, 0.52, 1.0))
    mat_spiral = create_clay_mat("m_bd_sp", (0.2, 0.2, 0.25, 1.0))

    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.35, vertices=16, location=(0, 0, 0))
    ped = bpy.context.active_object
    ped.data.materials.append(mat_ped)
    apply_bevel(ped, width=0.12, segments=3)
    objs.append(ped)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(0, 0.05, 0.65))
    body = bpy.context.active_object
    body.data.materials.append(mat_chick)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    for sign in [-1, 1]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(sign * 0.75, 0.05, 0.75))
        w = bpy.context.active_object
        w.scale = (0.5, 1.0, 0.7)
        w.rotation_euler = (0, 0, math.radians(sign * -55))
        w.data.materials.append(mat_chick)
        bpy.ops.object.shade_smooth()
        objs.append(w)

    # Beak Open (Shocked)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.35, vertices=16, location=(0, 0.85, 0.65))
    beak = bpy.context.active_object
    beak.rotation_euler = (math.radians(90), 0, 0)
    beak.data.materials.append(mat_beak)
    apply_bevel(beak, width=0.06, segments=2)
    objs.append(beak)

    # Cartoon Dizzy Spiral Eyes
    for sx in [-0.28, 0.28]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.05, location=(sx, 0.72, 0.82))
        eye = bpy.context.active_object
        eye.rotation_euler = (math.radians(90), 0, 0)
        eye.data.materials.append(mat_spiral)
        bpy.ops.object.shade_smooth()
        objs.append(eye)

        # Blush
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(sx * 1.35, 0.68, 0.62))
        bl = bpy.context.active_object
        bl.data.materials.append(mat_blush)
        bpy.ops.object.shade_smooth()
        objs.append(bl)

    return objs

def main():
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_lighting(ortho_scale=3.3)

    print(">>> Rendering Sokpop Animations & VFX...")
    # 1. Muzzle Flash
    for i in range(3):
        render_and_clean(build_muzzle_flash(i), os.path.join(SPRITES_EFFECTS, f"muzzle_flash_{i}.png"))

    # 2. Clay Debris
    for i in range(4):
        render_and_clean(build_clay_debris(i), os.path.join(SPRITES_EFFECTS, f"clay_debris_{i}.png"))

    # 3. Shield Bubble
    for i in range(4):
        render_and_clean(build_shield_bubble(i), os.path.join(SPRITES_EFFECTS, f"shield_bubble_{i}.png"))

    # 4. Shockwave
    for i in range(4):
        render_and_clean(build_shockwave(i), os.path.join(SPRITES_EFFECTS, f"shockwave_{i}.png"))

    # 5. Dust Puff
    for i in range(4):
        render_and_clean(build_dust_puff(i), os.path.join(SPRITES_EFFECTS, f"dust_puff_{i}.png"))

    # 6. Base Damaged
    render_and_clean(build_base_damaged(), os.path.join(SPRITES_TILES, "base_damaged.png"))

    print("All Sokpop Clay Animations Successfully Rendered!")

if __name__ == "__main__":
    main()
