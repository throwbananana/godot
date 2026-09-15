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
    ORTHO_SCALE_PROP,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# 1. TACTICAL MISSILE PROJECTILE (projectile_missile.png)
def build_tactical_missile():
    objs = []
    mat_body = create_clay_mat("m_msl_body", (0.88, 0.90, 0.94, 1.0), roughness=0.40)
    mat_nose = create_clay_mat("m_msl_nose", (0.95, 0.22, 0.25, 1.0), roughness=0.35)
    mat_fin = create_clay_mat("m_msl_fin", (0.20, 0.22, 0.28, 1.0), roughness=0.50)
    mat_thruster = create_clay_mat("m_msl_flame", (1.0, 0.60, 0.10, 1.0), emission=(1.0, 0.60, 0.10, 1.0), emission_str=4.5)

    # Aerodynamic Missile Fuselage
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.60, vertices=24, location=(0, 0, 0))
    body = bpy.context.active_object
    body.data.materials.append(mat_body)
    apply_uniform_clay_bevel(body, width=0.03, segments=2)
    objs.append(body)

    # Red Radome Nose Cone
    bpy.ops.mesh.primitive_cone_add(radius1=0.22, depth=0.65, vertices=24, location=(0, 1.12, 0))
    nose = bpy.context.active_object
    nose.rotation_euler = (math.radians(-90), 0, 0)
    nose.data.materials.append(mat_nose)
    apply_uniform_clay_bevel(nose, width=0.03, segments=2)
    objs.append(nose)

    # 4 Stabilizing Tail Fins
    for i in range(4):
        ang = i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.35, -0.62, math.sin(ang) * 0.35))
        fin = bpy.context.active_object
        fin.scale = (0.28, 0.42, 0.05)
        fin.rotation_euler = (0, ang, 0)
        fin.data.materials.append(mat_fin)
        apply_uniform_clay_bevel(fin, width=0.01, segments=1)
        objs.append(fin)

    # Glowing Rocket Thruster Plume
    bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.02, depth=0.55, vertices=16, location=(0, -1.05, 0))
    flame = bpy.context.active_object
    flame.rotation_euler = (math.radians(90), 0, 0)
    flame.data.materials.append(mat_thruster)
    objs.append(flame)

    return objs

# 2. TARGETING RETICLE (reticle_target.png)
def build_targeting_reticle():
    objs = []
    mat_reticle = create_clay_mat("m_ret_ring", (1.0, 0.25, 0.20, 1.0), emission=(1.0, 0.25, 0.20, 1.0), emission_str=4.0)
    mat_dot = create_clay_mat("m_ret_dot", (1.0, 0.90, 0.30, 1.0), emission=(1.0, 0.90, 0.30, 1.0), emission_str=5.0)

    # Outer Targeting Ring
    bpy.ops.mesh.primitive_torus_add(major_radius=0.92, minor_radius=0.06, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_reticle)
    objs.append(ring)

    # 4 Cardinal Crosshair Chevrons
    for i in range(4):
        ang = i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang) * 0.95, math.sin(ang) * 0.95, 0))
        tick = bpy.context.active_object
        tick.scale = (0.10, 0.36, 0.08) if i % 2 == 0 else (0.36, 0.10, 0.08)
        tick.data.materials.append(mat_reticle)
        apply_uniform_clay_bevel(tick, width=0.01, segments=1)
        objs.append(tick)

    # Inner Center Dot
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, location=(0, 0, 0))
    dot = bpy.context.active_object
    dot.data.materials.append(mat_dot)
    objs.append(dot)

    return objs

# 3. MISSILE STRIKE POWERUP PROP (powerup_missile.png)
def build_missile_powerup():
    objs = []
    mat_case = create_clay_mat("m_pwr_case", (0.28, 0.38, 0.28, 1.0), roughness=0.60)
    mat_gold = create_clay_mat("m_pwr_gold", (0.96, 0.80, 0.20, 1.0), roughness=0.35)
    mat_red = create_clay_mat("m_pwr_red", (0.95, 0.20, 0.25, 1.0), emission=(0.95, 0.20, 0.25, 1.0), emission_str=3.0)

    # Radio Transceiver Pod Body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.10, 0))
    pod = bpy.context.active_object
    pod.scale = (1.20, 0.95, 0.45)
    pod.data.materials.append(mat_case)
    apply_uniform_clay_bevel(pod, width=0.06, segments=2)
    objs.append(pod)

    # Dual Miniature Missiles in Casing
    for mx in [-0.28, 0.28]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.85, vertices=16, location=(mx, 0.15, 0.18))
        m_body = bpy.context.active_object
        m_body.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(m_body, width=0.02, segments=1)
        objs.append(m_body)

        bpy.ops.mesh.primitive_cone_add(radius1=0.12, depth=0.30, vertices=16, location=(mx, 0.70, 0.18))
        m_cone = bpy.context.active_object
        m_cone.rotation_euler = (math.radians(-90), 0, 0)
        m_cone.data.materials.append(mat_red)
        apply_uniform_clay_bevel(m_cone, width=0.02, segments=1)
        objs.append(m_cone)

    # Antenna
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.65, vertices=12, location=(-0.45, 0.65, 0))
    ant = bpy.context.active_object
    ant.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(ant, width=0.01, segments=1)
    objs.append(ant)

    return objs

# 4. ENEMY MISSILE TANK CHASSIS & LAUNCH POD (enemy_missile_f0..f5.png)
def build_missile_tank(frame=0):
    objs = []
    mat_body = create_clay_mat("m_etk_camo", (0.35, 0.40, 0.30, 1.0), roughness=0.65)
    mat_tread = create_clay_mat("m_etk_tread", (0.16, 0.18, 0.20, 1.0), roughness=0.75)
    mat_pod = create_clay_mat("m_etk_pod", (0.25, 0.28, 0.32, 1.0), roughness=0.50)
    mat_warhead = create_clay_mat("m_etk_wh", (0.95, 0.22, 0.25, 1.0), emission=(0.95, 0.22, 0.25, 1.0), emission_str=2.5)

    # 1. Track Chassis (Left & Right)
    tread_phase = (frame / 6.0) * math.pi
    for tx in [-0.85, 0.85]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.15))
        tread = bpy.context.active_object
        tread.scale = (0.42, 1.75, 0.48)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.05, segments=2)
        objs.append(tread)

        # Wheels with frame phase
        for wy in [-0.55, 0.0, 0.55]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.45, vertices=16, location=(tx, wy, -0.15))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), tread_phase)
            wheel.data.materials.append(mat_tread)
            objs.append(wheel)

    # 2. Main Tank Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.05))
    hull = bpy.context.active_object
    hull.scale = (1.25, 1.45, 0.45)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.08, segments=2)
    objs.append(hull)

    # 3. Inclined Quad-Tube Missile Launcher Pod
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.15, 0.45))
    pod = bpy.context.active_object
    pod.scale = (0.95, 1.15, 0.42)
    pod.rotation_euler = (math.radians(-18), 0, 0)
    pod.data.materials.append(mat_pod)
    apply_uniform_clay_bevel(pod, width=0.06, segments=2)
    objs.append(pod)

    # 4 Missile Launcher Tubes with Visible Red Warheads
    tube_offsets = [(-0.30, 0.35), (0.30, 0.35), (-0.30, -0.10), (0.30, -0.10)]
    for (ox, oz) in tube_offsets:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.95, vertices=16, location=(ox, 0.25, 0.45 + oz * 0.4))
        tube = bpy.context.active_object
        tube.rotation_euler = (math.radians(72), 0, 0)
        tube.data.materials.append(mat_pod)
        apply_uniform_clay_bevel(tube, width=0.02, segments=1)
        objs.append(tube)

        # Red Warhead Cap
        bpy.ops.mesh.primitive_cone_add(radius1=0.10, depth=0.22, vertices=16, location=(ox, 0.72, 0.60 + oz * 0.4))
        cap = bpy.context.active_object
        cap.rotation_euler = (math.radians(-18), 0, 0)
        cap.data.materials.append(mat_warhead)
        apply_uniform_clay_bevel(cap, width=0.02, segments=1)
        objs.append(cap)

    return objs

def main():
    print("==================================================")
    print(" Executing Missile System 3D Asset Pipeline... ")
    print("==================================================")

    # 1. Render Tactical Missile Projectile
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_tactical_missile()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "projectile_missile.png"))
    print("[OK] Projectile Missile Rendered.")

    # 2. Render Targeting Reticle
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_targeting_reticle()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "reticle_target.png"))
    print("[OK] Targeting Reticle Rendered.")

    # 3. Render Missile Powerup
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_missile_powerup()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "missile_strike.png"))
    print("[OK] Missile Powerup Rendered.")

    # 4. Render 6-Frame Enemy Missile Tank Sequence
    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_missile_tank(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_missile_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Enemy Missile Tank Frame {f} Rendered.")

if __name__ == '__main__':
    main()
