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
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
os.makedirs(SPRITES_UI, exist_ok=True)

# 1. UI PANEL BACKGROUND (ui_panel_bg.png) - 9-Slice Clay Panel
def build_panel_bg():
    objs = []
    mat_panel = create_clay_mat("m_ui_pnl", (0.16, 0.14, 0.18, 1.0), roughness=0.60)
    mat_rim = create_clay_mat("m_ui_rim", (0.28, 0.25, 0.32, 1.0), roughness=0.45)

    # Outer Rim Frame
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    rim = bpy.context.active_object
    rim.scale = (2.20, 2.20, 0.20)
    rim.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(rim, width=0.08, segments=3)
    objs.append(rim)

    # Inner Recessed Bed
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.02))
    inner = bpy.context.active_object
    inner.scale = (1.95, 1.95, 0.15)
    inner.data.materials.append(mat_panel)
    apply_uniform_clay_bevel(inner, width=0.04, segments=2)
    objs.append(inner)

    # Corner Clay Rivets
    mat_rivet = create_clay_mat("m_ui_rvt", (0.85, 0.70, 0.30, 1.0), roughness=0.35)
    for cx in [-0.95, 0.95]:
        for cy in [-0.95, 0.95]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.12, vertices=12, location=(cx, cy, 0.08))
            rvt = bpy.context.active_object
            rvt.data.materials.append(mat_rivet)
            apply_uniform_clay_bevel(rvt, width=0.01, segments=1)
            objs.append(rvt)

    return objs

# 2. UI HOTBAR SLOT (ui_hotbar_slot.png & ui_hotbar_slot_active.png)
def build_hotbar_slot(active=False):
    objs = []
    mat_border = create_clay_mat("m_ui_slot_bdr", (0.95, 0.80, 0.25, 1.0) if active else (0.25, 0.22, 0.28, 1.0), 
                                 emission=(0.95, 0.80, 0.25, 1.0) if active else (0,0,0,1), 
                                 emission_str=3.0 if active else 0.0,
                                 roughness=0.40)
    mat_inner = create_clay_mat("m_ui_slot_in", (0.12, 0.10, 0.14, 1.0), roughness=0.75)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    bdr = bpy.context.active_object
    bdr.scale = (2.10, 2.10, 0.22)
    bdr.data.materials.append(mat_border)
    apply_uniform_clay_bevel(bdr, width=0.10, segments=3)
    objs.append(bdr)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.02))
    inner = bpy.context.active_object
    inner.scale = (1.70, 1.70, 0.18)
    inner.data.materials.append(mat_inner)
    apply_uniform_clay_bevel(inner, width=0.04, segments=2)
    objs.append(inner)

    return objs

# 3. BOSS HP BAR FRAME (ui_boss_bar_frame.png & ui_boss_bar_fill.png)
def build_boss_bar_frame():
    objs = []
    mat_frame = create_clay_mat("m_ui_boss_frm", (0.20, 0.18, 0.22, 1.0), roughness=0.50)
    mat_gold_trim = create_clay_mat("m_ui_boss_gld", (0.95, 0.75, 0.20, 1.0), roughness=0.35)
    mat_ruby_crest = create_clay_mat("m_ui_boss_rby", (0.95, 0.15, 0.20, 1.0), emission=(0.95, 0.15, 0.20, 1.0), emission_str=3.5)

    # Wide Frame
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    frm = bpy.context.active_object
    frm.scale = (4.40, 0.70, 0.20)
    frm.data.materials.append(mat_frame)
    apply_uniform_clay_bevel(frm, width=0.05, segments=2)
    objs.append(frm)

    # Inner Recessed Bar Track
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.02))
    track = bpy.context.active_object
    track.scale = (4.10, 0.45, 0.15)
    track.data.materials.append(create_clay_mat("m_ui_boss_trk", (0.08, 0.06, 0.10, 1.0), roughness=0.85))
    apply_uniform_clay_bevel(track, width=0.02, segments=1)
    objs.append(track)

    # Center Skull/Crown Crest
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.25, vertices=6, location=(0, 0, 0.10))
    crest = bpy.context.active_object
    crest.data.materials.append(mat_gold_trim)
    objs.append(crest)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.22))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_ruby_crest)
    objs.append(gem)

    return objs

def build_boss_bar_fill():
    objs = []
    mat_fill = create_clay_mat("m_ui_boss_fil", (0.95, 0.20, 0.25, 1.0), emission=(0.95, 0.20, 0.25, 1.0), emission_str=3.2)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    fill = bpy.context.active_object
    fill.scale = (4.0, 0.40, 0.15)
    fill.data.materials.append(mat_fill)
    apply_uniform_clay_bevel(fill, width=0.02, segments=2)
    objs.append(fill)
    return objs

# 4. BADGES: Gold, Diamond, Eagle Crest
def build_gold_badge():
    objs = []
    mat_gold = create_clay_mat("m_ui_bdg_gld", (1.0, 0.82, 0.18, 1.0), roughness=0.35)
    mat_rim = create_clay_mat("m_ui_bdg_rim", (0.80, 0.58, 0.12, 1.0), roughness=0.40)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.22, vertices=24, location=(0, 0, 0))
    coin = bpy.context.active_object
    coin.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(coin, width=0.05, segments=2)
    objs.append(coin)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.25, vertices=24, location=(0, 0, 0.02))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim)
    objs.append(rim)

    # Dollar / G Stamp
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
    bar = bpy.context.active_object
    bar.scale = (0.16, 0.55, 0.10)
    bar.data.materials.append(mat_gold)
    objs.append(bar)

    return objs

def build_diamond_badge():
    objs = []
    mat_dia = create_clay_mat("m_ui_bdg_dia", (0.35, 0.92, 1.0, 1.0), emission=(0.35, 0.92, 1.0, 1.0), emission_str=4.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.80, depth=0.28, vertices=8, location=(0, 0, 0))
    dia = bpy.context.active_object
    dia.data.materials.append(mat_dia)
    apply_uniform_clay_bevel(dia, width=0.08, segments=2)
    objs.append(dia)
    return objs

def build_eagle_badge():
    objs = []
    mat_eagle = create_clay_mat("m_ui_bdg_egl", (0.95, 0.78, 0.22, 1.0), roughness=0.35)
    mat_shield = create_clay_mat("m_ui_bdg_shd", (0.22, 0.45, 0.85, 1.0), roughness=0.45)

    # Shield Crest Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.20, vertices=6, location=(0, 0, 0))
    shd = bpy.context.active_object
    shd.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(shd, width=0.06, segments=2)
    objs.append(shd)

    # Golden Eagle Wings
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.35, depth=0.75, vertices=12, location=(side * 0.42, 0.10, 0.12))
        wing = bpy.context.active_object
        wing.rotation_euler = (0, 0, math.radians(-35 * side))
        wing.data.materials.append(mat_eagle)
        objs.append(wing)

    # Eagle Head
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, 0.15, 0.16))
    head = bpy.context.active_object
    head.data.materials.append(mat_eagle)
    objs.append(head)

    return objs

def main():
    print("==================================================")
    print(" Executing Premium Clay UI Asset Pipeline...      ")
    print("==================================================")

    # 1. UI Panel Background (256x256)
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.40)
    objs = build_panel_bg()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_panel_bg.png"))
    print("[OK] UI Panel Background Rendered.")

    # 2. Hotbar Slots (Inactive & Active)
    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.30)
    objs = build_hotbar_slot(active=False)
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_hotbar_slot.png"))
    print("[OK] UI Hotbar Slot Normal Rendered.")

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.30)
    objs = build_hotbar_slot(active=True)
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_hotbar_slot_active.png"))
    print("[OK] UI Hotbar Slot Active Rendered.")

    # 3. Boss HP Bar Frame & Fill
    clear_scene()
    setup_render_settings(512, 96, samples=24)
    create_sokpop_lighting(ortho_scale=4.60)
    objs = build_boss_bar_frame()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_boss_bar_frame.png"))
    print("[OK] Boss HP Bar Frame Rendered.")

    clear_scene()
    setup_render_settings(512, 96, samples=24)
    create_sokpop_lighting(ortho_scale=4.60)
    objs = build_boss_bar_fill()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_boss_bar_fill.png"))
    print("[OK] Boss HP Bar Fill Rendered.")

    # 4. Badges (Gold, Diamond, Eagle)
    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_gold_badge()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_badge_gold.png"))
    print("[OK] Gold Badge Rendered.")

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_diamond_badge()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_badge_diamond.png"))
    print("[OK] Diamond Badge Rendered.")

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_eagle_badge()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_badge_eagle.png"))
    print("[OK] Eagle Badge Rendered.")

if __name__ == '__main__':
    main()
