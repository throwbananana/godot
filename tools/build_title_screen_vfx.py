import os
import sys
import math
import bpy
import bmesh

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_UI, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_PROP,
)

# 1. Build 3D Rotating Logo Radial Halo Disk
def build_logo_halo():
    objs = []
    mat_gold_beam = create_clay_mat("m_halo_gold", (0.98, 0.82, 0.25, 0.85), emission=(0.98, 0.82, 0.25, 1.0), emission_str=2.5)
    mat_cyan_beam = create_clay_mat("m_halo_cyan", (0.25, 0.85, 1.0, 0.75), emission=(0.25, 0.85, 1.0, 1.0), emission_str=2.8)
    mat_center_core = create_clay_mat("m_halo_core", (1.0, 1.0, 0.95, 1.0), emission=(1.0, 1.0, 0.95, 1.0), emission_str=3.5)

    # 12-pointed Sunburst Rays
    num_rays = 12
    for i in range(num_rays):
        angle = i * (2.0 * math.pi / num_rays)
        is_even = (i % 2 == 0)
        length = 1.35 if is_even else 0.95
        width = 0.16 if is_even else 0.11
        mat = mat_gold_beam if is_even else mat_cyan_beam
        
        # Ray mesh
        bpy.ops.mesh.primitive_cylinder_add(radius=width, depth=length, vertices=12, location=(0, 0, 0))
        ray = bpy.context.active_object
        ray.scale = (1.0, 0.35, 1.0)
        # Position along angle
        dist = length * 0.52
        rx = math.cos(angle) * dist
        ry = math.sin(angle) * dist
        ray.location = (rx, ry, 0.0)
        ray.rotation_euler = (0, 0, angle + math.pi / 2.0)
        ray.data.materials.append(mat)
        apply_uniform_clay_bevel(ray, width=0.03, segments=2)
        objs.append(ray)

    # Center Radiant Core Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.10, vertices=32, location=(0, 0, 0.05))
    core = bpy.context.active_object
    core.data.materials.append(mat_center_core)
    apply_uniform_clay_bevel(core, width=0.04, segments=2)
    objs.append(core)

    return objs

# 2. Build 3D Sparkle / Glint VFX (6 frames)
def build_sparkle_glint_frame(frame_idx, total_frames=6):
    objs = []
    t = frame_idx / float(total_frames - 1)
    
    mat_core = create_clay_mat(f"m_spk_core_{frame_idx}", (1.0, 1.0, 0.95, 1.0), emission=(1.0, 1.0, 0.95, 1.0), emission_str=4.0)
    mat_gold = create_clay_mat(f"m_spk_gold_{frame_idx}", (0.98, 0.85, 0.22, 1.0), emission=(0.98, 0.85, 0.22, 1.0), emission_str=3.0)
    mat_cyan = create_clay_mat(f"m_spk_cyan_{frame_idx}", (0.25, 0.90, 1.0, 1.0), emission=(0.25, 0.90, 1.0, 1.0), emission_str=3.2)

    # Growth -> Peak -> Dissipation curve
    if t < 0.4:
        scale_factor = 0.3 + (t / 0.4) * 0.85  # 0.3 -> 1.15
        rot_speed = t * 1.2
    else:
        scale_factor = 1.15 - ((t - 0.4) / 0.6) * 0.90  # 1.15 -> 0.25 (Strict dissipation < 50% peak!)
        rot_speed = 0.48 + (t - 0.4) * 2.0

    # Central diamond star
    for axis_rot in [0.0, math.pi * 0.5]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
        bar = bpy.context.active_object
        bar.scale = (0.18 * scale_factor, 1.20 * scale_factor, 0.12 * scale_factor)
        bar.rotation_euler = (0, 0, axis_rot + rot_speed)
        bar.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(bar, width=0.03 * scale_factor, segments=2)
        objs.append(bar)

    # Diagonal cyan petals (smaller)
    for axis_rot in [math.pi * 0.25, math.pi * 0.75]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.02))
        bar = bpy.context.active_object
        bar.scale = (0.12 * scale_factor, 0.75 * scale_factor, 0.10 * scale_factor)
        bar.rotation_euler = (0, 0, axis_rot + rot_speed)
        bar.data.materials.append(mat_cyan)
        apply_uniform_clay_bevel(bar, width=0.02 * scale_factor, segments=2)
        objs.append(bar)

    # Brilliant center sphere
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22 * scale_factor, location=(0, 0, 0.05))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # Outer satellite motes on late frames
    if frame_idx >= 2:
        mote_dist = 0.45 + (frame_idx - 2) * 0.32
        mote_r = max(0.02, 0.09 - (frame_idx - 2) * 0.022)
        for mi in range(4):
            m_ang = mi * (math.pi * 0.5) + rot_speed * 1.5
            mx = math.cos(m_ang) * mote_dist
            my = math.sin(m_ang) * mote_dist
            bpy.ops.mesh.primitive_uv_sphere_add(radius=mote_r, location=(mx, my, 0.02))
            mote = bpy.context.active_object
            mote.data.materials.append(mat_gold if mi % 2 == 0 else mat_cyan)
            bpy.ops.object.shade_smooth()
            objs.append(mote)

    return objs

# 3. Build 3D UI Button Hover / Click Ripple Beads (5 frames)
def build_ui_ripple_frame(frame_idx, total_frames=5):
    objs = []
    t = frame_idx / float(total_frames - 1)
    
    mat_clay = create_clay_mat(f"m_rip_{frame_idx}", (0.95, 0.88, 0.40, 1.0), roughness=0.35, emission=(0.95, 0.88, 0.40, 1.0), emission_str=2.0)
    
    # Ring expansion radius: 0.35 -> 1.40
    ring_radius = 0.30 + t * 1.15
    # Bead radius shrinks on late frames for clean dissipation: 0.12 -> 0.03
    bead_r = max(0.025, 0.12 * (1.0 - t * 0.75))
    
    num_beads = 8
    for i in range(num_beads):
        angle = i * (2.0 * math.pi / num_beads) + t * 0.4
        bx = math.cos(angle) * ring_radius
        by = math.sin(angle) * ring_radius * 0.45  # Elliptical for button aspect ratio
        
        bpy.ops.mesh.primitive_uv_sphere_add(radius=bead_r, location=(bx, by, 0.0))
        bead = bpy.context.active_object
        bead.scale = (1.1, 0.9, 0.8)
        bead.data.materials.append(mat_clay)
        bpy.ops.object.shade_smooth()
        objs.append(bead)
        
    return objs

def main():
    print("=== Rendering Blender 3D Title Screen VFX & Animation Assets ===")
    
    # 1. Render Logo Halo
    print("Rendering UI Logo Halo...")
    clear_scene()
    setup_render_settings(rx=256, ry=256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_logo_halo()
    render_and_clean(objs, os.path.join(SPRITES_UI, "ui_logo_halo.png"))
    print("[OK] ui_logo_halo.png Rendered.")
    
    # 2. Render Sparkle Glint Sequence (6 frames)
    print("Rendering Sparkle Glint Sequence (6 frames)...")
    for i in range(6):
        clear_scene()
        setup_render_settings(rx=128, ry=128, samples=20)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = build_sparkle_glint_frame(i, 6)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"vfx_sparkle_glint_f{i}.png"))
    print("[OK] vfx_sparkle_glint_f0..5.png Rendered.")
    
    # 3. Render UI Ripple Beads Sequence (5 frames)
    print("Rendering UI Ripple Beads Sequence (5 frames)...")
    for i in range(5):
        clear_scene()
        setup_render_settings(rx=128, ry=128, samples=20)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = build_ui_ripple_frame(i, 5)
        render_and_clean(objs, os.path.join(SPRITES_EFFECTS, f"vfx_ui_ripple_f{i}.png"))
    print("[OK] vfx_ui_ripple_f0..4.png Rendered.")
    
    print("🎉 All Blender Title Screen VFX Rendered Cleanly! 🎉")

if __name__ == "__main__":
    main()
