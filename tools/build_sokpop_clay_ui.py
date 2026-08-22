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

def build_clay_heart(full=True):
    objs = []
    col = (0.92, 0.32, 0.42, 1.0) if full else (0.42, 0.44, 0.50, 1.0)
    mat_h = create_sokpop_clay_mat(f"m_heart_{full}", col)
    mat_hl = create_sokpop_clay_mat(f"m_heart_hl_{full}", (0.98, 0.98, 1.0, 1.0))

    # Sculpted Organic Clay Heart
    for sx in [-0.38, 0.38]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.55, location=(sx, 0.25, 0))
        sph = bpy.context.active_object
        sph.scale = (1.0, 1.0, 0.75)
        sph.data.materials.append(mat_h)
        bpy.ops.object.shade_smooth()
        objs.append(sph)

    bpy.ops.mesh.primitive_cone_add(radius1=0.78, depth=1.18, location=(0, -0.32, 0))
    cone = bpy.context.active_object
    cone.rotation_euler = (0, 0, math.radians(180))
    cone.scale = (1.0, 0.85, 0.75)
    cone.data.materials.append(mat_h)
    add_smooth_clay_bevel(cone, width=0.14, segments=3)
    objs.append(cone)

    if full:
        # Glossy White Clay Reflection Highlight
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(-0.35, 0.45, 0.30))
        hl = bpy.context.active_object
        hl.scale = (1.0, 1.0, 0.6)
        hl.data.materials.append(mat_hl)
        bpy.ops.object.shade_smooth()
        objs.append(hl)

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
