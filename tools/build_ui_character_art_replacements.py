import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    reset_jitter_seed,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
os.makedirs(SPRITES_UI, exist_ok=True)

# 1. SHOP REFRESH / REROLL ICON (ui_icon_shop_refresh.png)
def build_icon_shop_refresh():
    objs = []
    mat_plate = create_clay_mat("m_srf_plt", (0.16, 0.22, 0.26, 1.0), roughness=0.50)
    mat_arrow = create_clay_mat("m_srf_arr", (0.35, 0.88, 1.0, 1.0), emission=(0.35, 0.88, 1.0, 1.0), emission_str=3.2)
    mat_gold = create_clay_mat("m_srf_gld", (1.0, 0.82, 0.22, 1.0), roughness=0.35)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.22, vertices=24, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Two circular curving arrow arcs
    for ang in [0, 180]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.36 * math.cos(math.radians(ang)), 0.36 * math.sin(math.radians(ang)), 0.18))
        arc = bpy.context.active_object
        arc.rotation_euler = (0, 0, math.radians(ang + 45))
        arc.scale = (0.14, 0.45, 0.14)
        arc.data.materials.append(mat_arrow)
        apply_uniform_clay_bevel(arc, width=0.02, segments=1)
        objs.append(arc)

        # Arrow head
        hx = 0.42 * math.cos(math.radians(ang + 50))
        hy = 0.42 * math.sin(math.radians(ang + 50))
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.16, vertices=3, location=(hx, hy, 0.18))
        head = bpy.context.active_object
        head.rotation_euler = (0, 0, math.radians(ang + 110))
        head.data.materials.append(mat_arrow)
        apply_uniform_clay_bevel(head, width=0.02, segments=1)
        objs.append(head)

    return objs

# 2. SHOP CART / ARMS DEALER ICON (ui_icon_shop_cart.png)
def build_icon_shop_cart():
    objs = []
    mat_plate = create_clay_mat("m_sc_plt", (0.24, 0.18, 0.14, 1.0), roughness=0.55)
    mat_gold = create_clay_mat("m_sc_gld", (1.0, 0.85, 0.25, 1.0), roughness=0.35)
    mat_cart = create_clay_mat("m_sc_crt", (0.95, 0.65, 0.20, 1.0), emission=(0.95, 0.65, 0.20, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.22, vertices=24, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Cart basket
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.05, 0.05, 0.18))
    basket = bpy.context.active_object
    basket.scale = (0.55, 0.40, 0.18)
    basket.data.materials.append(mat_cart)
    apply_uniform_clay_bevel(basket, width=0.03, segments=2)
    objs.append(basket)

    # Cart wheels
    for wx in [-0.25, 0.15]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.16, vertices=12, location=(wx, -0.22, 0.18))
        wh = bpy.context.active_object
        wh.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(wh, width=0.015, segments=1)
        objs.append(wh)

    # Cart handle
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.30, 0.22, 0.20))
    handle = bpy.context.active_object
    handle.rotation_euler = (0, 0, math.radians(-35))
    handle.scale = (0.08, 0.35, 0.14)
    handle.data.materials.append(mat_cart)
    apply_uniform_clay_bevel(handle, width=0.01, segments=1)
    objs.append(handle)

    return objs

# 3. LOCK & KEY ICON (ui_icon_lock_key.png)
def build_icon_lock_key():
    objs = []
    mat_plate = create_clay_mat("m_lk_plt", (0.22, 0.18, 0.26, 1.0), roughness=0.55)
    mat_lock = create_clay_mat("m_lk_lck", (1.0, 0.82, 0.22, 1.0), roughness=0.35)
    mat_shackle = create_clay_mat("m_lk_shk", (0.65, 0.68, 0.75, 1.0), roughness=0.35)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    # Padlock Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0.18))
    body = bpy.context.active_object
    body.scale = (0.50, 0.42, 0.22)
    body.data.materials.append(mat_lock)
    apply_uniform_clay_bevel(body, width=0.04, segments=2)
    objs.append(body)

    # Shackle arch
    bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.18, vertices=16, location=(0, 0.18, 0.18))
    shk = bpy.context.active_object
    shk.scale = (1.0, 0.9, 1.0)
    shk.data.materials.append(mat_shackle)
    apply_uniform_clay_bevel(shk, width=0.03, segments=2)
    objs.append(shk)

    # Keyhole
    mat_hole = create_clay_mat("m_lk_hol", (0.10, 0.08, 0.12, 1.0), roughness=0.80)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.24, vertices=12, location=(0, -0.06, 0.20))
    hole = bpy.context.active_object
    hole.data.materials.append(mat_hole)
    objs.append(hole)

    return objs

# 4. TERRAIN MAP ICON (ui_icon_terrain.png)
def build_icon_terrain():
    objs = []
    mat_plate = create_clay_mat("m_ter_plt", (0.16, 0.24, 0.20, 1.0), roughness=0.55)
    mat_trim = create_clay_mat("m_ter_trm", (0.45, 0.85, 0.65, 1.0), roughness=0.35)
    mat_mountain = create_clay_mat("m_ter_mtn", (0.35, 0.80, 0.50, 1.0), emission=(0.35, 0.80, 0.50, 1.0), emission_str=2.5)
    mat_peak = create_clay_mat("m_ter_pk", (0.95, 0.95, 1.0, 1.0), roughness=0.30)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.22, vertices=24, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Twin Mountain peaks
    peaks = [(-0.22, -0.05, 0.42), (0.22, 0.05, 0.36)]
    for px, py, p_rad in peaks:
        bpy.ops.mesh.primitive_cone_add(radius1=p_rad, depth=0.50, vertices=6, location=(px, py, 0.16))
        mtn = bpy.context.active_object
        mtn.data.materials.append(mat_mountain)
        apply_uniform_clay_bevel(mtn, width=0.03, segments=2)
        objs.append(mtn)

        bpy.ops.mesh.primitive_cone_add(radius1=p_rad * 0.4, depth=0.18, vertices=6, location=(px, py, 0.32))
        snw = bpy.context.active_object
        snw.data.materials.append(mat_peak)
        apply_uniform_clay_bevel(snw, width=0.01, segments=1)
        objs.append(snw)

    return objs

# 5. RECON / RADAR CROSSHAIR ICON (ui_icon_recon.png)
def build_icon_recon():
    objs = []
    mat_plate = create_clay_mat("m_rcn_plt", (0.26, 0.14, 0.16, 1.0), roughness=0.55)
    mat_scope = create_clay_mat("m_rcn_scp", (0.95, 0.30, 0.35, 1.0), emission=(0.95, 0.30, 0.35, 1.0), emission_str=3.5)
    mat_dot = create_clay_mat("m_rcn_dot", (1.0, 0.90, 0.40, 1.0), emission=(1.0, 0.90, 0.40, 1.0), emission_str=4.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    # Reticle Ring
    bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=0.22, vertices=24, location=(0, 0, 0.06))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_scope)
    apply_uniform_clay_bevel(ring, width=0.03, segments=1)
    objs.append(ring)

    # Crosshair bars
    for scale, loc in [((0.10, 0.70, 0.16), (0, 0, 0.16)), ((0.70, 0.10, 0.16), (0, 0, 0.16))]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        bar = bpy.context.active_object
        bar.scale = scale
        bar.data.materials.append(mat_scope)
        apply_uniform_clay_bevel(bar, width=0.015, segments=1)
        objs.append(bar)

    # Center dot
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.22))
    dot = bpy.context.active_object
    dot.data.materials.append(mat_dot)
    objs.append(dot)

    return objs

# 6. REWARD / GIFT DROP ICON (ui_icon_gift.png)
def build_icon_gift():
    objs = []
    mat_plate = create_clay_mat("m_gft_plt", (0.24, 0.18, 0.24, 1.0), roughness=0.55)
    mat_box = create_clay_mat("m_gft_box", (0.95, 0.35, 0.45, 1.0), roughness=0.45)
    mat_gold = create_clay_mat("m_gft_gld", (1.0, 0.85, 0.25, 1.0), emission=(1.0, 0.85, 0.25, 1.0), emission_str=2.8)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    # Gift Box Cube
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.16))
    box = bpy.context.active_object
    box.scale = (0.58, 0.58, 0.24)
    box.data.materials.append(mat_box)
    apply_uniform_clay_bevel(box, width=0.04, segments=2)
    objs.append(box)

    # Golden Ribbon Cross
    for scale in [(0.62, 0.14, 0.26), (0.14, 0.62, 0.26)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.17))
        rbn = bpy.context.active_object
        rbn.scale = scale
        rbn.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(rbn, width=0.02, segments=1)
        objs.append(rbn)

    # Ribbon Bow
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, -0.04, 0.32))
    bow = bpy.context.active_object
    bow.data.materials.append(mat_gold)
    objs.append(bow)

    return objs

# 7. CONTROLLER / CONTROLS ICON (ui_icon_controls.png)
def build_icon_controls():
    objs = []
    mat_plate = create_clay_mat("m_ctrl_plt", (0.18, 0.16, 0.22, 1.0), roughness=0.55)
    mat_pad = create_clay_mat("m_ctrl_pad", (0.35, 0.32, 0.42, 1.0), roughness=0.45)
    mat_btn = create_clay_mat("m_ctrl_btn", (0.95, 0.82, 0.25, 1.0), emission=(0.95, 0.82, 0.25, 1.0), emission_str=2.5)
    mat_dpad = create_clay_mat("m_ctrl_dpd", (0.85, 0.30, 0.35, 1.0), emission=(0.85, 0.30, 0.35, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    # Gamepad Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.16))
    body = bpy.context.active_object
    body.scale = (0.75, 0.44, 0.20)
    body.data.materials.append(mat_pad)
    apply_uniform_clay_bevel(body, width=0.06, segments=2)
    objs.append(body)

    # D-Pad on Left
    for scale in [(0.24, 0.08, 0.22), (0.08, 0.24, 0.22)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.22, 0, 0.18))
        dp = bpy.context.active_object
        dp.scale = scale
        dp.data.materials.append(mat_dpad)
        apply_uniform_clay_bevel(dp, width=0.015, segments=1)
        objs.append(dp)

    # Buttons on Right
    for bx, by in [(0.18, 0.06), (0.28, -0.04)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.22, vertices=12, location=(bx, by, 0.18))
        btn = bpy.context.active_object
        btn.data.materials.append(mat_btn)
        apply_uniform_clay_bevel(btn, width=0.01, segments=1)
        objs.append(btn)

    return objs

# 8. PAUSE EMBLEM ICON (ui_icon_pause.png)
def build_icon_pause():
    objs = []
    mat_plate = create_clay_mat("m_ps_plt", (0.22, 0.18, 0.26, 1.0), roughness=0.55)
    mat_gold = create_clay_mat("m_ps_gld", (1.0, 0.82, 0.22, 1.0), roughness=0.35)
    mat_bar = create_clay_mat("m_ps_bar", (0.35, 0.88, 1.0, 1.0), emission=(0.35, 0.88, 1.0, 1.0), emission_str=3.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.22, vertices=24, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Twin Pause Bars
    for px in [-0.18, 0.18]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, 0, 0.18))
        bar = bpy.context.active_object
        bar.scale = (0.16, 0.52, 0.18)
        bar.data.materials.append(mat_bar)
        apply_uniform_clay_bevel(bar, width=0.03, segments=1)
        objs.append(bar)

    return objs

# 9. WRENCH / REPAIR TOOL ICON (ui_icon_wrench.png)
def build_icon_wrench():
    objs = []
    mat_plate = create_clay_mat("m_wr_plt", (0.18, 0.20, 0.24, 1.0), roughness=0.55)
    mat_wrench = create_clay_mat("m_wr_tool", (0.95, 0.75, 0.25, 1.0), emission=(0.95, 0.75, 0.25, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    # Crossed Wrenches
    for ang in [-45, 45]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.16))
        handle = bpy.context.active_object
        handle.rotation_euler = (0, 0, math.radians(ang))
        handle.scale = (0.14, 0.85, 0.16)
        handle.data.materials.append(mat_wrench)
        apply_uniform_clay_bevel(handle, width=0.02, segments=1)
        objs.append(handle)

        for end_y in [-0.42, 0.42]:
            ey_x = end_y * math.sin(math.radians(-ang))
            ey_y = end_y * math.cos(math.radians(-ang))
            bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.18, vertices=12, location=(ey_x, ey_y, 0.16))
            jaw = bpy.context.active_object
            jaw.data.materials.append(mat_wrench)
            apply_uniform_clay_bevel(jaw, width=0.02, segments=1)
            objs.append(jaw)

    return objs

def main():
    print("================================================================")
    print(" Rendering UI Character Art Replacements...                    ")
    print("================================================================")

    # clear_scene() 不是可选的: create_sokpop_lighting() 只清相机和灯, 不清 mesh。
    # 少了这一句, Blender 出厂场景的默认立方体 (2x2x2, 原点) 会一直留在场景里 ——
    # ortho_scale=2.10 下它占满 95% 画幅, 顶面 z=+1 又高于所有图标几何 (z<=0.2),
    # 于是九张图标全部渲染成同一块 (193,194,199) 的灰方块 (alpha 覆盖率 91.8%,
    # 灰度 std 1.7)。render_and_clean() 只删自己那批对象, 立方体能撑过全部九次渲染。
    clear_scene()

    reset_jitter_seed(99)

    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.10)

    render_and_clean(build_icon_shop_refresh(), os.path.join(SPRITES_UI, "ui_icon_shop_refresh.png"))
    render_and_clean(build_icon_shop_cart(), os.path.join(SPRITES_UI, "ui_icon_shop_cart.png"))
    render_and_clean(build_icon_lock_key(), os.path.join(SPRITES_UI, "ui_icon_lock_key.png"))
    render_and_clean(build_icon_terrain(), os.path.join(SPRITES_UI, "ui_icon_terrain.png"))
    render_and_clean(build_icon_recon(), os.path.join(SPRITES_UI, "ui_icon_recon.png"))
    render_and_clean(build_icon_gift(), os.path.join(SPRITES_UI, "ui_icon_gift.png"))
    render_and_clean(build_icon_controls(), os.path.join(SPRITES_UI, "ui_icon_controls.png"))
    render_and_clean(build_icon_pause(), os.path.join(SPRITES_UI, "ui_icon_pause.png"))
    render_and_clean(build_icon_wrench(), os.path.join(SPRITES_UI, "ui_icon_wrench.png"))

    print("\n[OK] All Character Art Replacements Rendered Successfully!")

if __name__ == '__main__':
    main()
