"""
tools/build_waving_grass.py
Generates a lush, organic 3D grass clump with Geometry Nodes wind-waving animation,
stylized PBR translucent foliage materials, studio lighting, and camera.
Compatible with Blender 5.2+ LTS.
"""

import bpy
import math
import random
import os
import sys

def clear_scene():
    """Clear all mesh objects, lights, cameras, and materials."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    # Purge orphan data blocks
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)
    for block in list(bpy.data.textures):
        if block.users == 0:
            bpy.data.textures.remove(block)
    for block in list(bpy.data.node_groups):
        if block.users == 0:
            bpy.data.node_groups.remove(block)

def srgb_to_linear_rgb(rgb):
    """Convert sRGB 0-1 values to linear RGB 3-tuple."""
    res = []
    for c in rgb[:3]:
        if c <= 0.04045:
            res.append(c / 12.92)
        else:
            res.append(((c + 0.055) / 1.055) ** 2.4)
    return tuple(res)

def srgb_to_linear_rgba(rgba):
    """Convert sRGB 0-1 values to linear RGBA 4-tuple."""
    res = list(srgb_to_linear_rgb(rgba[:3]))
    if len(rgba) > 3:
        res.append(rgba[3])
    else:
        res.append(1.0)
    return tuple(res)

def create_grass_material():
    """Create a stylized lush translucent foliage material."""
    mat = bpy.data.materials.new(name="M_Grass_Lush")
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    nodes.clear()

    # Output
    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (700, 200)

    # Principled BSDF
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 200)
    bsdf.inputs["Roughness"].default_value = 0.32
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.50
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.50
    
    # SSS for foliage translucency
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = 0.45
        bsdf.inputs["Subsurface Radius"].default_value = (0.15, 0.35, 0.08)
        bsdf.inputs["Subsurface Scale"].default_value = 0.08
    elif "Subsurface" in bsdf.inputs:
        bsdf.inputs["Subsurface"].default_value = 0.45

    # Texture Coordinate (Generated)
    tex_coord = nodes.new(type="ShaderNodeTexCoord")
    tex_coord.location = (-650, 200)

    # Separate XYZ to get Z (height along blade)
    sep_xyz = nodes.new(type="ShaderNodeSeparateXYZ")
    sep_xyz.location = (-450, 200)
    links.new(tex_coord.outputs["Generated"], sep_xyz.inputs["Vector"])

    # Color Ramp for Root -> Mid -> Tip gradient
    color_ramp = nodes.new(type="ShaderNodeValToRGB")
    color_ramp.location = (-200, 200)
    color_ramp.color_ramp.interpolation = 'EASE'

    # Color stops
    # 0.0: Earthy dark moss green
    color_ramp.color_ramp.elements[0].position = 0.0
    color_ramp.color_ramp.elements[0].color = srgb_to_linear_rgba((0.07, 0.18, 0.05, 1.0))

    # 0.32: Rich forest emerald
    elem1 = color_ramp.color_ramp.elements.new(0.32)
    elem1.color = srgb_to_linear_rgba((0.15, 0.52, 0.10, 1.0))

    # 0.70: Vibrant spring green
    elem2 = color_ramp.color_ramp.elements.new(0.70)
    elem2.color = srgb_to_linear_rgba((0.36, 0.76, 0.15, 1.0))

    # 1.0: Sunlit golden lime tip
    color_ramp.color_ramp.elements[-1].position = 1.0
    color_ramp.color_ramp.elements[-1].color = srgb_to_linear_rgba((0.80, 0.94, 0.22, 1.0))

    links.new(sep_xyz.outputs["Z"], color_ramp.inputs["Fac"])
    links.new(color_ramp.outputs["Color"], bsdf.inputs["Base Color"])
    if "Subsurface Color" in bsdf.inputs:
        links.new(color_ramp.outputs["Color"], bsdf.inputs["Subsurface Color"])

    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat

def create_soil_material():
    """Create rich dark soil material for base mound."""
    mat = bpy.data.materials.new(name="M_Soil_Earth")
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (400, 200)

    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 200)
    bsdf.inputs["Base Color"].default_value = srgb_to_linear_rgba((0.12, 0.08, 0.05, 1.0))
    bsdf.inputs["Roughness"].default_value = 0.90

    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat

def create_floor_material():
    """Create a soft studio floor material that catches shadows."""
    mat = bpy.data.materials.new(name="M_Studio_Floor")
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (400, 200)

    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 200)
    bsdf.inputs["Base Color"].default_value = srgb_to_linear_rgba((0.06, 0.07, 0.09, 1.0))
    bsdf.inputs["Roughness"].default_value = 0.92

    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat

def generate_blade_mesh_data(height, base_width, tip_width, curve_power=2.0, segments=9, crease_angle=0.35, twist_max=0.15):
    """
    Generate vertices, faces, and height-weights for a 3D curved V-crease grass blade.
    Returns: verts, faces, weights (0.0 at root, 1.0 at tip)
    """
    verts = []
    faces = []
    weights = []

    for i in range(segments + 1):
        t = i / float(segments) # 0.0 at base to 1.0 at tip
        
        # Arching curvature: smooth gravity drop along Y and height along Z
        z = height * (t - 0.28 * (t ** 2.4))
        y_offset = (t ** curve_power) * (height * 0.48)
        
        # Width profile: slight swell near 25% height, then gradual tapering to tip
        width_factor = (math.sin(t * math.pi * 0.85 + 0.15) if t < 0.25 else (1.0 - t * 0.95))
        w = base_width * max(0.05, width_factor)
        
        # V-crease fold depth
        crease_z = -math.sin(crease_angle) * w * 0.55 * (1.0 - t * 0.75)

        # Subtle blade twist along length
        twist = t * twist_max
        cos_tw = math.cos(twist)
        sin_tw = math.sin(twist)

        # 3 local vertices across blade width: Left, Spine, Right
        lx, ly, lz = -w * 0.5, y_offset, z
        sx, sy, sz = 0.0, y_offset + (w * 0.12), z + crease_z
        rx, ry, rz = w * 0.5, y_offset, z

        # Apply twist
        def apply_twist(x, y, z_val):
            tx = x * cos_tw - y * sin_tw
            ty = x * sin_tw + y * cos_tw
            return (tx, ty, z_val)

        v_idx_start = len(verts)
        verts.extend([apply_twist(lx, ly, lz), apply_twist(sx, sy, sz), apply_twist(rx, ry, rz)])
        
        # Weight based on normalized height (0.0 at root, 1.0 at tip)
        weight_val = (t ** 1.65)
        weights.extend([weight_val, weight_val, weight_val])

        # Create 2 quads per segment
        if i > 0:
            prev_idx = v_idx_start - 3
            faces.append((prev_idx, v_idx_start, v_idx_start + 1, prev_idx + 1))
            faces.append((prev_idx + 1, v_idx_start + 1, v_idx_start + 2, prev_idx + 2))

    # Add pointy tip triangle
    tip_z = height * 0.76
    tip_y = (1.0 ** curve_power) * (height * 0.52)
    tip_idx = len(verts)
    verts.append((0.0, tip_y, tip_z))
    weights.append(1.0)

    last_left = len(verts) - 4
    last_spine = len(verts) - 3
    last_right = len(verts) - 2
    faces.append((last_left, tip_idx, last_spine))
    faces.append((last_spine, tip_idx, last_right))

    return verts, faces, weights

def create_geometry_nodes_wind(obj):
    """
    Builds a Geometry Nodes procedural wind swaying modifier for the grass clump.
    Provides natural gust waves, tip turbulence, downward bending, and zero root slip.
    """
    gn_mod = obj.modifiers.new(name="Wind_Sway_GN", type='NODES')
    node_group = bpy.data.node_groups.new(name="GN_Grass_Wind_Sway", type='GeometryNodeTree')
    gn_mod.node_group = node_group

    # Sockets
    node_group.interface.new_socket(name="Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    s_speed = node_group.interface.new_socket(name="Wind Speed", in_out='INPUT', socket_type='NodeSocketFloat')
    s_speed.default_value = math.pi # Exactly 1 full cycle per 2.0 seconds (60 frames at 30 fps)
    s_speed.min_value = 0.0
    s_speed.max_value = 20.0

    s_strength = node_group.interface.new_socket(name="Wind Strength", in_out='INPUT', socket_type='NodeSocketFloat')
    s_strength.default_value = 0.32
    s_strength.min_value = 0.0
    s_strength.max_value = 2.0

    s_turb = node_group.interface.new_socket(name="Turbulence", in_out='INPUT', socket_type='NodeSocketFloat')
    s_turb.default_value = 0.08
    s_turb.min_value = 0.0
    s_turb.max_value = 1.0

    node_group.interface.new_socket(name="Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')

    nodes = node_group.nodes
    links = node_group.links
    nodes.clear()

    # Nodes
    in_node = nodes.new(type="NodeGroupInput")
    in_node.location = (-1000, 200)

    out_node = nodes.new(type="NodeGroupOutput")
    out_node.location = (850, 200)

    # Named Attribute for WindWeight
    attr_weight = nodes.new(type="GeometryNodeInputNamedAttribute")
    attr_weight.data_type = 'FLOAT'
    attr_weight.inputs["Name"].default_value = "WindWeight"
    attr_weight.location = (-1000, -100)

    # Scene Time (Seconds)
    time_node = nodes.new(type="GeometryNodeInputSceneTime")
    time_node.location = (-1000, 400)

    # Position
    pos_node = nodes.new(type="GeometryNodeInputPosition")
    pos_node.location = (-1000, 0)

    # Separate XYZ
    sep_pos = nodes.new(type="ShaderNodeSeparateXYZ")
    sep_pos.location = (-800, 0)
    links.new(pos_node.outputs["Position"], sep_pos.inputs["Vector"])

    # TimeScaled = Time * WindSpeed
    time_mult = nodes.new(type="ShaderNodeMath")
    time_mult.operation = 'MULTIPLY'
    time_mult.location = (-750, 400)
    links.new(time_node.outputs["Seconds"], time_mult.inputs[0])
    links.new(in_node.outputs["Wind Speed"], time_mult.inputs[1])

    # PosPhase = Pos.X * 1.5 + Pos.Y * 1.0
    pos_x_mult = nodes.new(type="ShaderNodeMath")
    pos_x_mult.operation = 'MULTIPLY'
    pos_x_mult.inputs[1].default_value = 1.5
    pos_x_mult.location = (-600, 50)
    links.new(sep_pos.outputs["X"], pos_x_mult.inputs[0])

    pos_y_mult = nodes.new(type="ShaderNodeMath")
    pos_y_mult.operation = 'MULTIPLY'
    pos_y_mult.inputs[1].default_value = 1.0
    pos_y_mult.location = (-600, -100)
    links.new(sep_pos.outputs["Y"], pos_y_mult.inputs[0])

    pos_phase_add = nodes.new(type="ShaderNodeMath")
    pos_phase_add.operation = 'ADD'
    pos_phase_add.location = (-420, 0)
    links.new(pos_x_mult.outputs["Value"], pos_phase_add.inputs[0])
    links.new(pos_y_mult.outputs["Value"], pos_phase_add.inputs[1])

    # TotalPhase1 = TimeScaled + PosPhase
    phase1_add = nodes.new(type="ShaderNodeMath")
    phase1_add.operation = 'ADD'
    phase1_add.location = (-240, 250)
    links.new(time_mult.outputs["Value"], phase1_add.inputs[0])
    links.new(pos_phase_add.outputs["Value"], phase1_add.inputs[1])

    # GustSine = Sine(TotalPhase1)
    sine1 = nodes.new(type="ShaderNodeMath")
    sine1.operation = 'SINE'
    sine1.location = (-60, 250)
    links.new(phase1_add.outputs["Value"], sine1.inputs[0])

    # Flutter Phase = TimeScaled * 2.0 - Pos.X * 2.0 + Pos.Y * 1.5
    flutter_time = nodes.new(type="ShaderNodeMath")
    flutter_time.operation = 'MULTIPLY'
    flutter_time.inputs[1].default_value = 2.0
    flutter_time.location = (-600, 300)
    links.new(time_mult.outputs["Value"], flutter_time.inputs[0])

    flutter_phase_add = nodes.new(type="ShaderNodeMath")
    flutter_phase_add.operation = 'ADD'
    flutter_phase_add.location = (-240, 100)
    links.new(flutter_time.outputs["Value"], flutter_phase_add.inputs[0])
    links.new(pos_phase_add.outputs["Value"], flutter_phase_add.inputs[1])

    sine2 = nodes.new(type="ShaderNodeMath")
    sine2.operation = 'SINE'
    sine2.location = (-60, 100)
    links.new(flutter_phase_add.outputs["Value"], sine2.inputs[0])

    # Primary Displacement = GustSine * WindStrength
    gust_disp = nodes.new(type="ShaderNodeMath")
    gust_disp.operation = 'MULTIPLY'
    gust_disp.location = (120, 300)
    links.new(sine1.outputs["Value"], gust_disp.inputs[0])
    links.new(in_node.outputs["Wind Strength"], gust_disp.inputs[1])

    # Flutter Displacement = FlutterSine * Turbulence
    flutter_disp = nodes.new(type="ShaderNodeMath")
    flutter_disp.operation = 'MULTIPLY'
    flutter_disp.location = (120, 150)
    links.new(sine2.outputs["Value"], flutter_disp.inputs[0])
    links.new(in_node.outputs["Turbulence"], flutter_disp.inputs[1])

    # Total Disp = GustDisp + FlutterDisp
    total_disp = nodes.new(type="ShaderNodeMath")
    total_disp.operation = 'ADD'
    total_disp.location = (280, 250)
    links.new(gust_disp.outputs["Value"], total_disp.inputs[0])
    links.new(flutter_disp.outputs["Value"], total_disp.inputs[1])

    # Mask by WindWeight: WeightedDisp = TotalDisp * WindWeight
    weighted_disp = nodes.new(type="ShaderNodeMath")
    weighted_disp.operation = 'MULTIPLY'
    weighted_disp.location = (440, 200)
    links.new(total_disp.outputs["Value"], weighted_disp.inputs[0])
    links.new(attr_weight.outputs["Attribute"], weighted_disp.inputs[1])

    # Vector Offset: Wind angle ~ 35 deg (X = 0.85, Y = 0.52)
    off_x = nodes.new(type="ShaderNodeMath")
    off_x.operation = 'MULTIPLY'
    off_x.inputs[1].default_value = 0.85
    off_x.location = (440, 50)
    links.new(weighted_disp.outputs["Value"], off_x.inputs[0])

    off_y = nodes.new(type="ShaderNodeMath")
    off_y.operation = 'MULTIPLY'
    off_y.inputs[1].default_value = 0.52
    off_y.location = (440, -100)
    links.new(weighted_disp.outputs["Value"], off_y.inputs[0])

    # Realistic Downward bend Z = - (WeightedDisp^2) * 0.70
    disp_sqr = nodes.new(type="ShaderNodeMath")
    disp_sqr.operation = 'MULTIPLY'
    disp_sqr.location = (440, -250)
    links.new(weighted_disp.outputs["Value"], disp_sqr.inputs[0])
    links.new(weighted_disp.outputs["Value"], disp_sqr.inputs[1])

    off_z = nodes.new(type="ShaderNodeMath")
    off_z.operation = 'MULTIPLY'
    off_z.inputs[1].default_value = -0.70
    off_z.location = (600, -250)
    links.new(disp_sqr.outputs["Value"], off_z.inputs[0])

    # Combine XYZ
    comb_offset = nodes.new(type="ShaderNodeCombineXYZ")
    comb_offset.location = (600, 0)
    links.new(off_x.outputs["Value"], comb_offset.inputs["X"])
    links.new(off_y.outputs["Value"], comb_offset.inputs["Y"])
    links.new(off_z.outputs["Value"], comb_offset.inputs["Z"])

    # Set Position
    set_pos = nodes.new(type="GeometryNodeSetPosition")
    set_pos.location = (620, 250)
    links.new(in_node.outputs["Geometry"], set_pos.inputs["Geometry"])
    links.new(comb_offset.outputs["Vector"], set_pos.inputs["Offset"])
    links.new(set_pos.outputs["Geometry"], out_node.inputs["Geometry"])

    print("Created Geometry Nodes Wind Sway setup successfully.")

def build_grass_clump():
    """
    Build a rich organic 3D grass clump with 4 natural layers (140 blades, wide fountain profile).
    """
    random.seed(101)

    all_verts = []
    all_faces = []
    all_weights = []

    # 4 layers with wide spread:
    # 1. Inner core: Tall, upright (28 blades)
    # 2. Mid inner tier: Medium-tall, outward fanning (45 blades)
    # 3. Mid outer tier: Medium, wide arching (42 blades)
    # 4. Outer perimeter: Shorter, graceful droop touching soil (25 blades)
    layers = [
        {"count": 28, "radius_min": 0.01, "radius_max": 0.10, "h_min": 0.80, "h_max": 1.05, "tilt_min": 0.08, "tilt_max": 0.28, "w_base": 0.048, "bend_pow": 1.8},
        {"count": 45, "radius_min": 0.08, "radius_max": 0.24, "h_min": 0.60, "h_max": 0.88, "tilt_min": 0.28, "tilt_max": 0.55, "w_base": 0.042, "bend_pow": 2.0},
        {"count": 42, "radius_min": 0.18, "radius_max": 0.38, "h_min": 0.42, "h_max": 0.68, "tilt_min": 0.52, "tilt_max": 0.85, "w_base": 0.038, "bend_pow": 2.2},
        {"count": 25, "radius_min": 0.25, "radius_max": 0.46, "h_min": 0.28, "h_max": 0.48, "tilt_min": 0.78, "tilt_max": 1.12, "w_base": 0.030, "bend_pow": 2.4},
    ]

    for layer in layers:
        for _ in range(layer["count"]):
            angle = random.uniform(0, 2 * math.pi)
            dist = random.uniform(layer["radius_min"], layer["radius_max"])
            pos_x = math.cos(angle) * dist
            pos_y = math.sin(angle) * dist
            
            height = random.uniform(layer["h_min"], layer["h_max"])
            base_w = layer["w_base"] * random.uniform(0.85, 1.25)
            tilt = random.uniform(layer["tilt_min"], layer["tilt_max"])
            yaw = angle + random.uniform(-0.45, 0.45) # Fanning outwards
            bend_power = layer["bend_pow"] * random.uniform(0.9, 1.15)
            twist = random.uniform(-0.28, 0.28)

            b_verts, b_faces, b_weights = generate_blade_mesh_data(
                height=height,
                base_width=base_w,
                tip_width=0.001,
                curve_power=bend_power,
                segments=8,
                crease_angle=random.uniform(0.28, 0.48),
                twist_max=twist
            )

            cos_tilt = math.cos(tilt)
            sin_tilt = math.sin(tilt)
            cos_yaw = math.cos(yaw)
            sin_yaw = math.sin(yaw)

            vert_offset = len(all_verts)
            for vx, vy, vz in b_verts:
                # Tilt forward around X axis
                t_y = vy * cos_tilt - vz * sin_tilt
                t_z = vy * sin_tilt + vz * cos_tilt
                t_x = vx

                # Rotate around Z axis (yaw)
                r_x = t_x * cos_yaw - t_y * sin_yaw
                r_y = t_x * sin_yaw + t_y * cos_yaw
                r_z = t_z

                # Translate to clump origin
                all_verts.append((r_x + pos_x, r_y + pos_y, max(0.0, r_z)))

            for face in b_faces:
                all_faces.append(tuple(idx + vert_offset for idx in face))

            all_weights.extend(b_weights)

    mesh = bpy.data.meshes.new(name="Grass_Clump_Mesh")
    mesh.from_pydata(all_verts, [], all_faces)
    mesh.update()

    obj = bpy.data.objects.new(name="Grass_Clump", object_data=mesh)
    bpy.context.collection.objects.link(obj)

    # Create Vertex Group for Wind Sway (WindWeight)
    vgroup = obj.vertex_groups.new(name="WindWeight")
    for i, w in enumerate(all_weights):
        vgroup.add([i], w, 'REPLACE')

    # Assign Lush Foliage Material
    grass_mat = create_grass_material()
    obj.data.materials.append(grass_mat)

    for poly in mesh.polygons:
        poly.use_smooth = True

    # Add Geometry Nodes procedural wind system
    create_geometry_nodes_wind(obj)

    with bpy.context.temp_override(active_object=obj, selected_objects=[obj]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    return obj

def build_soil_and_floor():
    """Build a subtle stylized soil mound at the root of the grass clump and studio floor."""
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=32,
        ring_count=16,
        radius=0.55,
        location=(0, 0, -0.47)
    )
    soil_obj = bpy.context.active_object
    soil_obj.name = "Soil_Base"
    soil_obj.scale = (1.0, 1.0, 0.90)

    for poly in soil_obj.data.polygons:
        poly.use_smooth = True

    soil_mat = create_soil_material()
    soil_obj.data.materials.append(soil_mat)

    with bpy.context.temp_override(active_object=soil_obj, selected_objects=[soil_obj]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Studio floor plane
    bpy.ops.mesh.primitive_circle_add(
        vertices=48,
        radius=3.5,
        fill_type='NGON',
        location=(0, 0, -0.01)
    )
    floor_obj = bpy.context.active_object
    floor_obj.name = "Studio_Floor"
    floor_mat = create_floor_material()
    floor_obj.data.materials.append(floor_mat)

    return soil_obj, floor_obj

def setup_studio_lighting_and_camera():
    """Configure three-point studio lighting and hero camera framing."""
    # Sun / Main Key Light
    sun_data = bpy.data.lights.new(name="Sun_KeyLight", type='SUN')
    sun_data.energy = 4.5
    sun_data.color = srgb_to_linear_rgb((1.0, 0.96, 0.88))
    sun_data.angle = math.radians(15)
    sun_obj = bpy.data.objects.new(name="Sun_KeyLight", object_data=sun_data)
    sun_obj.rotation_euler = (math.radians(48), math.radians(18), math.radians(45))
    bpy.context.collection.objects.link(sun_obj)

    # Rim / Back Light (Backlit translucency)
    rim_data = bpy.data.lights.new(name="Rim_BackLight", type='AREA')
    rim_data.energy = 180.0
    rim_data.size = 2.0
    rim_data.color = srgb_to_linear_rgb((0.80, 1.0, 0.75))
    rim_obj = bpy.data.objects.new(name="Rim_BackLight", object_data=rim_data)
    rim_obj.location = (-1.2, 1.8, 1.4)
    rim_obj.rotation_euler = (math.radians(-42), math.radians(-25), math.radians(-135))
    bpy.context.collection.objects.link(rim_obj)

    # Fill Light (Cool sky ambient)
    fill_data = bpy.data.lights.new(name="Fill_Light", type='AREA')
    fill_data.energy = 70.0
    fill_data.size = 2.5
    fill_data.color = srgb_to_linear_rgb((0.72, 0.85, 1.0))
    fill_obj = bpy.data.objects.new(name="Fill_Light", object_data=fill_data)
    fill_obj.location = (1.8, -1.5, 1.0)
    fill_obj.rotation_euler = (math.radians(55), 0, math.radians(40))
    bpy.context.collection.objects.link(fill_obj)

    # Camera with centered hero framing
    cam_data = bpy.data.cameras.new(name="Camera")
    cam_data.lens = 48
    cam_obj = bpy.data.objects.new(name="Camera", object_data=cam_data)
    cam_obj.location = (1.45, -1.85, 1.05)
    # Pitch ~ 60 deg, Yaw ~ 38 deg
    cam_obj.rotation_euler = (math.radians(63.0), 0, math.radians(38.0))
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj

    # World background
    world = bpy.context.scene.world
    if not world:
        world = bpy.data.worlds.new("World")
        bpy.context.scene.world = world
    world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node:
        bg_node.inputs["Color"].default_value = srgb_to_linear_rgba((0.07, 0.08, 0.10, 1.0))
        bg_node.inputs["Strength"].default_value = 0.80

def setup_render_settings(output_dir):
    """Setup render engine, resolution, and output parameters."""
    scene = bpy.context.scene
    
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items else 'BLENDER_EEVEE'
    scene.render.resolution_x = 1080
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 60 # 2-second seamless loop at 30 fps

    scene.display_settings.display_device = 'sRGB'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'Medium High Contrast'

    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

def export_glb(output_dir):
    glb_path = os.path.join(output_dir, "grass_clump_animated.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        export_apply=True,
        export_yup=True,
        export_materials='EXPORT',
        export_attributes=True,
        export_animations=True
    )
    print(f"Exported GLB to: {glb_path}")

def main():
    output_dir = os.path.abspath("assets/blender")
    frames_dir = os.path.join(output_dir, "frames")
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(frames_dir, exist_ok=True)
    blend_path = os.path.join(output_dir, "grass_clump_animated.blend")

    print("[1/6] Clearing scene and resetting data...")
    clear_scene()

    print("[2/6] Building lush 3D organic grass clump (140 blades) and Geometry Nodes wind system...")
    grass_obj = build_grass_clump()
    soil_obj, floor_obj = build_soil_and_floor()

    print("[3/6] Setting up studio lighting and hero camera framing...")
    setup_studio_lighting_and_camera()

    print(f"[4/6] Saving master Blender project to: {blend_path}")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    print("[5/6] Exporting GLB asset...")
    export_glb(output_dir)

    print("[6/6] Rendering beauty preview...")
    setup_render_settings(output_dir)
    scene = bpy.context.scene
    scene.frame_set(15) # Mid-sway peak
    preview_path = os.path.join(output_dir, "grass_clump_preview.png")
    scene.render.filepath = preview_path
    bpy.ops.render.render(write_still=True)
    print(f"Rendered still preview to: {preview_path}")

    print("Rendering 60 animation frames for GIF...")
    scene.render.filepath = os.path.join(frames_dir, "frame_")
    bpy.ops.render.render(animation=True)
    print("Blender generation and rendering complete!")

if __name__ == "__main__":
    main()
