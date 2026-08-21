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

# 3. BOSS HP BAR FRAME (ui_boss_bar_frame.png), TRACK (ui_boss_bar_track.png) & FILL (ui_boss_bar_fill.png)
#
# TextureProgressBar draws texture_under, then the cropped texture_progress on
# top of it, then texture_over on top of THAT at full opacity, uncropped. The
# frame used to be a solid cube spanning the whole bar (with the dark track
# baked in as opaque pixels) -- as texture_over that opaque rectangle would
# have permanently hidden the health-color fill underneath, so the bar would
# never visually change with HP. The frame is now a hollow ring (four bars,
# no center geometry) so the middle renders transparent and the fill shows
# through; the dark track background moves to its own texture for
# texture_under so the empty portion still reads as a track, not raw HUD bg.
def build_boss_bar_frame():
    objs = []
    mat_frame = create_clay_mat("m_ui_boss_frm", (0.20, 0.18, 0.22, 1.0), roughness=0.50)
    mat_gold_trim = create_clay_mat("m_ui_boss_gld", (0.95, 0.75, 0.20, 1.0), roughness=0.35)
    mat_ruby_crest = create_clay_mat("m_ui_boss_rby", (0.95, 0.15, 0.20, 1.0), emission=(0.95, 0.15, 0.20, 1.0), emission_str=3.5)

    # Hollow rim ring: top/bottom/left/right bars only, true empty hole in
    # the middle (outer envelope 4.40 x 0.70 unchanged from the old solid
    # frame; ~0.12-thick walls leave a ~4.16 x 0.46 hole, matching the old
    # track's footprint so the fill/track line up visually underneath it).
    rim_thickness = 0.12
    outer_w, outer_h = 4.40, 0.70
    for scale, loc in [
        ((outer_w, rim_thickness, 0.20), (0, outer_h / 2 - rim_thickness / 2, -0.05)),
        ((outer_w, rim_thickness, 0.20), (0, -(outer_h / 2 - rim_thickness / 2), -0.05)),
        ((rim_thickness, outer_h, 0.20), (outer_w / 2 - rim_thickness / 2, 0, -0.05)),
        ((rim_thickness, outer_h, 0.20), (-(outer_w / 2 - rim_thickness / 2), 0, -0.05)),
    ]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        bar = bpy.context.active_object
        bar.scale = scale
        bar.data.materials.append(mat_frame)
        apply_uniform_clay_bevel(bar, width=0.04, segments=2)
        objs.append(bar)

    # Center Skull/Crown Crest (sits in the hole, always on top of the fill)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.25, vertices=6, location=(0, 0, 0.10))
    crest = bpy.context.active_object
    crest.data.materials.append(mat_gold_trim)
    objs.append(crest)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.22))
    gem = bpy.context.active_object
    gem.data.materials.append(mat_ruby_crest)
    objs.append(gem)

    return objs


def build_boss_bar_track():
    """Static dark track background -- used as texture_under, drawn beneath
    the fill so the un-filled portion of the bar reads as a recessed track
    instead of transparent HUD background."""
    objs = []
    mat_track = create_clay_mat("m_ui_boss_trk", (0.08, 0.06, 0.10, 1.0), roughness=0.85)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    track = bpy.context.active_object
    track.scale = (4.10, 0.45, 0.15)
    track.data.materials.append(mat_track)
    apply_uniform_clay_bevel(track, width=0.02, segments=1)
    objs.append(track)
    return objs


def build_boss_bar_fill():
    # Scaled to nearly the track's own width (4.10) rather than leaving a wide
    # margin: TextureProgressBar's left-to-right fill crops this texture
    # proportionally to *its own* pixel width, so empty padding here becomes a
    # dead zone where the bar looks unfilled/full near 0%/100% HP regardless
    # of the true value. Keeping the margin to ~1px of AA avoids that.
    objs = []
    mat_fill = create_clay_mat("m_ui_boss_fil", (0.95, 0.20, 0.25, 1.0), emission=(0.95, 0.20, 0.25, 1.0), emission_str=3.2)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    fill = bpy.context.active_object
    fill.scale = (4.06, 0.40, 0.15)
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
    mat_rim = create_clay_mat("m_ui_bdg_dia_rim", (0.18, 0.55, 0.68, 1.0), roughness=0.40)
    mat_dia = create_clay_mat("m_ui_bdg_dia", (0.35, 0.92, 1.0, 1.0), emission=(0.35, 0.92, 1.0, 1.0), emission_str=4.0)
    mat_facet = create_clay_mat("m_ui_bdg_dia_fct", (0.80, 0.98, 1.0, 1.0), emission=(0.80, 0.98, 1.0, 1.0), emission_str=3.0, roughness=0.25)

    # Darker rim, matching the two-layer read of the gold/eagle badges
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.20, vertices=8, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.rotation_euler = (0, 0, math.radians(22.5))
    rim.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(rim, width=0.05, segments=2)
    objs.append(rim)

    # Gem body
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.30, vertices=8, location=(0, 0, 0.05))
    dia = bpy.context.active_object
    dia.data.materials.append(mat_dia)
    apply_uniform_clay_bevel(dia, width=0.10, segments=2)
    objs.append(dia)

    # Table facet cross on top so the gem reads as cut, not a flat disc
    for rot in (0.0, 90.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.20))
        facet = bpy.context.active_object
        facet.rotation_euler = (0, 0, math.radians(45 + rot))
        facet.scale = (0.62, 0.10, 0.02)
        facet.data.materials.append(mat_facet)
        objs.append(facet)

    return objs

def build_eagle_badge():
    # NOTE: camera is top-down orthographic (looks down -Z). A cone's default
    # axis runs along local Z, so a Z-only rotation just spins its base circle
    # in place -- it always reads as a plain dot from above, never as a wing.
    # To get a wing silhouette in the XY footprint the cone's axis has to be
    # tipped into the XY plane first (rotate on X), *then* swept on Z.
    objs = []
    mat_eagle = create_clay_mat("m_ui_bdg_egl", (0.95, 0.78, 0.22, 1.0), roughness=0.35)
    mat_shield = create_clay_mat("m_ui_bdg_shd", (0.22, 0.45, 0.85, 1.0), roughness=0.45)

    # Shield Crest Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.20, vertices=6, location=(0, 0, 0))
    shd = bpy.context.active_object
    shd.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(shd, width=0.06, segments=2)
    objs.append(shd)

    # Golden Eagle Wings -- flattened, tapered cones lying in the XY plane,
    # wide root at the head/shoulder tapering to a swept-back tip.
    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.30, radius2=0.0, depth=0.62, vertices=10,
                                         location=(side * 0.30, -0.05, 0.14))
        wing = bpy.context.active_object
        # Rx 90 deg lays the cone flat (root toward +Y, tip toward -Y in local
        # space); Rz sweeps the tip outward/back away from the shield center.
        wing.rotation_euler = (math.radians(90), 0, math.radians(-55 * side))
        wing.scale = (1.0, 1.0, 0.55)
        wing.data.materials.append(mat_eagle)
        apply_uniform_clay_bevel(wing, width=0.015, segments=1)
        objs.append(wing)

    # Eagle Head
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.20, location=(0, 0.20, 0.16))
    head = bpy.context.active_object
    head.data.materials.append(mat_eagle)
    objs.append(head)

    # Beak, so the head reads as a head and not a third wing-root dot
    mat_beak = create_clay_mat("m_ui_bdg_bk", (0.85, 0.55, 0.15, 1.0), roughness=0.40)
    bpy.ops.mesh.primitive_cone_add(radius1=0.06, radius2=0.0, depth=0.14, vertices=6,
                                     location=(0, 0.36, 0.16))
    beak = bpy.context.active_object
    beak.rotation_euler = (math.radians(90), 0, 0)
    beak.data.materials.append(mat_beak)
    objs.append(beak)

    return objs

def main():
    print("==================================================")
    print(" Executing Premium Clay UI Asset Pipeline...      ")
    print("==================================================")

    reset_jitter_seed(0)

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

    # 3. Boss HP Bar Frame, Track & Fill
    clear_scene()
    setup_render_settings(512, 96, samples=24)
    create_sokpop_lighting(ortho_scale=4.60)
    objs = build_boss_bar_frame()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_boss_bar_frame.png"))
    print("[OK] Boss HP Bar Frame Rendered.")

    clear_scene()
    setup_render_settings(512, 96, samples=24)
    create_sokpop_lighting(ortho_scale=4.60)
    objs = build_boss_bar_track()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_boss_bar_track.png"))
    print("[OK] Boss HP Bar Track Rendered.")

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
