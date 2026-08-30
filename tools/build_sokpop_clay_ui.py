import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

os.makedirs(SPRITES_UI, exist_ok=True)

# 渲染管线统一在 sokpop_common —— 见该文件顶部说明。
from sokpop_common import (  # noqa: E402
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    ORTHO_SCALE_DEFAULT,
    create_clay_mat as create_sokpop_clay_mat,
    apply_uniform_clay_bevel as add_smooth_clay_bevel,
    reset_jitter_seed,
    render_and_clean as _render_and_clean,
)


def create_sokpop_warm_lighting(ortho_scale=ORTHO_SCALE_DEFAULT):
    create_sokpop_lighting(ortho_scale=ortho_scale)


def render_and_clean(objects, out_path):
    _render_and_clean(objects, out_path, label="Rendered Clay UI")

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
    elif state == "disabled":
        col = (0.75, 0.74, 0.72, 1.0)
        col_rim = (0.58, 0.56, 0.55, 1.0)
        z_scale = 0.25

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

def build_procedural_organic_heart(name="ClayHeart", col=(0.96, 0.16, 0.26, 1.0), roughness=0.28, scale_xyz=(1.0, 1.0, 0.46)):
    import bmesh
    me = bpy.data.meshes.new(name + "_Mesh")
    bm = bmesh.new()
    
    half_profile_2d = [
        (0.00, -0.84),   # 0: bottom tip
        (0.26, -0.52),   # 1: lower right curve
        (0.68, -0.08),   # 2: middle right bulge
        (0.78,  0.28),   # 3: upper right widest
        (0.64,  0.64),   # 4: upper right lobe outer
        (0.40,  0.75),   # 5: top right lobe peak
        (0.18,  0.66),   # 6: inner top slope
        (0.00,  0.38),   # 7: top center cleft
    ]
    
    outline_2d = []
    for pt in half_profile_2d:
        outline_2d.append(pt)
    for i in range(len(half_profile_2d) - 2, 0, -1):
        pt = half_profile_2d[i]
        outline_2d.append((-pt[0], pt[1]))
        
    num_pts = len(outline_2d)
    
    # Layer 0: Front center vertex (Z = +0.36)
    v_front_center = bm.verts.new((0.0, 0.06, 0.36 * scale_xyz[2]))
    # Layer 1: Mid front ring
    front_ring = []
    for (x, y) in outline_2d:
        front_ring.append(bm.verts.new((x * 0.68 * scale_xyz[0], y * 0.68 * scale_xyz[1], 0.26 * scale_xyz[2])))
        
    # Layer 2: Equator rim ring
    rim_ring = []
    for (x, y) in outline_2d:
        rim_ring.append(bm.verts.new((x * 1.00 * scale_xyz[0], y * 1.00 * scale_xyz[1], 0.00)))
        
    # Layer 3: Mid back ring
    back_ring = []
    for (x, y) in outline_2d:
        back_ring.append(bm.verts.new((x * 0.68 * scale_xyz[0], y * 0.68 * scale_xyz[1], -0.26 * scale_xyz[2])))
        
    # Layer 4: Back center vertex (Z = -0.36)
    v_back_center = bm.verts.new((0.0, 0.06, -0.36 * scale_xyz[2]))
    
    bm.verts.ensure_lookup_table()
    
    for i in range(num_pts):
        next_i = (i + 1) % num_pts
        bm.faces.new([v_front_center, front_ring[i], front_ring[next_i]])
        bm.faces.new([front_ring[i], rim_ring[i], rim_ring[next_i], front_ring[next_i]])
        bm.faces.new([rim_ring[i], back_ring[i], back_ring[next_i], rim_ring[next_i]])
        bm.faces.new([v_back_center, back_ring[next_i], back_ring[i]])
        
    bm.to_mesh(me)
    bm.free()
    
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    
    mat = create_sokpop_clay_mat("m_" + name, col, roughness=roughness)
    obj.data.materials.append(mat)
    
    for poly in me.polygons:
        poly.use_smooth = True
        
    sub = obj.modifiers.new("Subsurf", 'SUBSURF')
    sub.levels = 3
    sub.render_levels = 3
    
    return obj


def build_clay_heart(full=True):
    objs = []
    if full:
        col = (0.96, 0.16, 0.26, 1.0)
        heart = build_procedural_organic_heart("HeartFull", col=col, roughness=0.28)
        objs.append(heart)
        
        # Primary glossy highlight pebble on upper-left lobe
        mat_hl = create_sokpop_clay_mat("m_heart_hl", (1.0, 1.0, 1.0, 1.0), roughness=0.10)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(-0.30, 0.44, 0.28))
        hl1 = bpy.context.active_object
        hl1.scale = (1.1, 0.75, 0.4)
        hl1.rotation_euler = (0, 0, math.radians(28))
        hl1.data.materials.append(mat_hl)
        bpy.ops.object.shade_smooth()
        objs.append(hl1)
        
        # Secondary cute smaller highlight dot
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(-0.44, 0.26, 0.26))
        hl2 = bpy.context.active_object
        hl2.scale = (1.0, 1.0, 0.4)
        hl2.data.materials.append(mat_hl)
        bpy.ops.object.shade_smooth()
        objs.append(hl2)
    else:
        # Empty heart: Dark slate stone clay with deep inner shadow
        col_rim = (0.28, 0.25, 0.32, 1.0)
        heart = build_procedural_organic_heart("HeartEmpty", col=col_rim, roughness=0.65)
        objs.append(heart)
        
        # Inner recessed dark core
        col_inner = (0.13, 0.11, 0.16, 1.0)
        inner = build_procedural_organic_heart("HeartEmptyInner", col=col_inner, roughness=0.85, scale_xyz=(0.76, 0.76, 0.40))
        inner.location = (0, 0, 0.04)
        objs.append(inner)
        
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
    render_and_clean(build_clay_button("disabled"), os.path.join(SPRITES_UI, "btn_clay_disabled.png"))

    setup_render_settings(rx=128, ry=128)
    create_sokpop_warm_lighting(ortho_scale=2.2)
    render_and_clean(build_clay_heart(True), os.path.join(SPRITES_UI, "hp_heart_full.png"))
    render_and_clean(build_clay_heart(False), os.path.join(SPRITES_UI, "hp_heart_empty.png"))

    print("All UI Textures Calibrated and Rendered Successfully!")

if __name__ == "__main__":
    main()
