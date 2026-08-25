"""build_pipe_conduit_assets.py — 导流管道 (Conduit Pipe) 3D 黏土建模与渲染

为游戏生成管道建筑的美术资产:
  1. pipe_conduit.png       — 基础图标 / 商店 / 热键栏预览
  2. pipe_conduit_f0~f3.png — 带有流动导流指示光效的 4 帧贴图 (或转角形态)
"""

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
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)

def build_pipe_conduit(frame: int = 0):
    """
    90° 导流弯管 (Conduit Pipe Elbow):
    - 从左侧 (-X) 为入口，弯折后向正上方 (+Y) 为出口
    - 粗壮圆管，入口和出口有宽凸起法兰环 (Flange) 与发光导向箭头
    - 坚固的六边形/加固金属底座与铆钉
    - 内部具有深色空腔感
    """
    objs = []
    
    # 黏土材质
    mat_base   = create_clay_mat("m_pipe_base", srgb_to_linear((0.35, 0.38, 0.42, 1.0)), roughness=0.65)
    mat_pipe   = create_clay_mat("m_pipe_body", srgb_to_linear((0.28, 0.58, 0.72, 1.0)), roughness=0.50)
    mat_flange = create_clay_mat("m_pipe_flange", srgb_to_linear((0.85, 0.72, 0.22, 1.0)), roughness=0.45)
    mat_cavity = create_clay_mat("m_pipe_cavity", srgb_to_linear((0.08, 0.09, 0.12, 1.0)), roughness=0.90)
    mat_bolt   = create_clay_mat("m_pipe_bolt", srgb_to_linear((0.75, 0.78, 0.82, 1.0)), roughness=0.30)
    
    # 动态导向发光条纹
    pulse = 2.5 + 1.5 * math.sin(frame * (2.0 * math.pi / 4.0))
    mat_glow   = create_clay_mat(f"m_pipe_glow_{frame}", srgb_to_linear((0.20, 0.95, 1.0, 1.0)),
                                 emission=srgb_to_linear((0.20, 0.95, 1.0, 1.0)), emission_str=pulse)

    # 1. 重型地基底板 (防滑动加固板)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.05, 0.05, -0.22))
    base = bpy.context.active_object
    base.scale = (1.45, 1.45, 0.18)
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.06, segments=2)
    objs.append(base)

    # 地基四角固定铆钉
    for cx, cy in [(-0.62, -0.52), (0.52, -0.52), (-0.62, 0.62), (0.52, 0.62)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.12, vertices=12, location=(cx, cy, -0.10))
        bolt = bpy.context.active_object
        bolt.data.materials.append(mat_bolt)
        apply_uniform_clay_bevel(bolt, width=0.02, segments=2)
        objs.append(bolt)

    # 2. 管道转角弯头 - 用圆环分段近似平滑 90° 弯管
    # 中心在 (-0.25, 0.25)，从 (-0.85, -0.25) 弯向 (0.25, 0.85)
    center_x = 0.22
    center_y = -0.22
    bend_radius = 0.62
    pipe_radius = 0.28
    
    # 建立 90 度弯管段
    segments = 12
    for i in range(segments):
        t1 = (i / float(segments)) * (math.pi / 2.0)
        t2 = ((i + 1) / float(segments)) * (math.pi / 2.0)
        t_mid = (t1 + t2) / 2.0
        
        # 弧线位置
        px = center_x - math.cos(t_mid) * bend_radius
        py = center_y + math.sin(t_mid) * bend_radius
        pz = 0.12
        
        tangent_angle = t_mid # 切线角
        
        bpy.ops.mesh.primitive_cylinder_add(radius=pipe_radius, depth=bend_radius * (math.pi / (2.0 * segments)) * 1.15,
                                             vertices=16, location=(px, py, pz))
        seg = bpy.context.active_object
        seg.rotation_euler = (math.radians(90), 0, tangent_angle)
        seg.data.materials.append(mat_pipe)
        apply_uniform_clay_bevel(seg, width=0.04, segments=2)
        objs.append(seg)

    # 3. 入口直管段 (向 -X 延伸)
    bpy.ops.mesh.primitive_cylinder_add(radius=pipe_radius, depth=0.45, vertices=16,
                                         location=(-0.60, -0.22, 0.12))
    in_pipe = bpy.context.active_object
    in_pipe.rotation_euler = (0, math.radians(90), 0)
    in_pipe.data.materials.append(mat_pipe)
    apply_uniform_clay_bevel(in_pipe, width=0.04, segments=2)
    objs.append(in_pipe)

    # 4. 出口直管段 (向 +Y 延伸)
    bpy.ops.mesh.primitive_cylinder_add(radius=pipe_radius, depth=0.45, vertices=16,
                                         location=(0.22, 0.60, 0.12))
    out_pipe = bpy.context.active_object
    out_pipe.rotation_euler = (math.radians(90), 0, 0)
    out_pipe.data.materials.append(mat_pipe)
    apply_uniform_clay_bevel(out_pipe, width=0.04, segments=2)
    objs.append(out_pipe)

    # 5. 入口法兰环 (Flange Collar) & 黑色开口深腔
    bpy.ops.mesh.primitive_torus_add(major_radius=pipe_radius * 1.28, minor_radius=0.08,
                                     location=(-0.82, -0.22, 0.12))
    in_flange = bpy.context.active_object
    in_flange.rotation_euler = (0, math.radians(90), 0)
    in_flange.data.materials.append(mat_flange)
    bpy.ops.object.shade_smooth()
    objs.append(in_flange)

    bpy.ops.mesh.primitive_cylinder_add(radius=pipe_radius * 0.72, depth=0.08, vertices=16,
                                         location=(-0.85, -0.22, 0.12))
    in_hole = bpy.context.active_object
    in_hole.rotation_euler = (0, math.radians(90), 0)
    in_hole.data.materials.append(mat_cavity)
    objs.append(in_hole)

    # 6. 出口法兰环 (Flange Collar) & 黑色开口深腔
    bpy.ops.mesh.primitive_torus_add(major_radius=pipe_radius * 1.28, minor_radius=0.08,
                                     location=(0.22, 0.82, 0.12))
    out_flange = bpy.context.active_object
    out_flange.rotation_euler = (math.radians(90), 0, 0)
    out_flange.data.materials.append(mat_flange)
    bpy.ops.object.shade_smooth()
    objs.append(out_flange)

    bpy.ops.mesh.primitive_cylinder_add(radius=pipe_radius * 0.72, depth=0.08, vertices=16,
                                         location=(0.22, 0.85, 0.12))
    out_hole = bpy.context.active_object
    out_hole.rotation_euler = (math.radians(90), 0, 0)
    out_hole.data.materials.append(mat_cavity)
    objs.append(out_hole)

    # 7. 管道外壁上的导向发光箭头条带 (示明流动方向: 左进上出)
    for step_i in range(3):
        frac = (step_i + 1) / 4.0
        ang = frac * (math.pi / 2.0)
        gx = center_x - math.cos(ang) * (bend_radius)
        gy = center_y + math.sin(ang) * (bend_radius)
        gz = 0.12 + pipe_radius * 0.95
        
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(gx, gy, gz))
        glow_strip = bpy.context.active_object
        glow_strip.scale = (0.10, 0.14, 0.05)
        glow_strip.rotation_euler = (0, 0, ang)
        glow_strip.data.materials.append(mat_glow)
        apply_uniform_clay_bevel(glow_strip, width=0.01, segments=2)
        objs.append(glow_strip)

    # 8. 管道中央加强支架 (带转轴螺栓)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.35, vertices=16, location=(-0.10, 0.10, 0.12))
    hub = bpy.context.active_object
    hub.data.materials.append(mat_base)
    apply_uniform_clay_bevel(hub, width=0.03, segments=2)
    objs.append(hub)

    return objs

def main():
    print("=" * 60)
    print("  Conduit Pipe (导流管道) 3D Clay Render Pipeline")
    print("=" * 60)

    # 1. 渲染 4 帧流动动画 (pipe_conduit_f0~f3.png)
    for f in range(4):
        print(f"[PIPE] Rendering animated frame {f}/3 ...")
        clear_scene()
        setup_render_settings(256, 256, samples=32)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
        objs = build_pipe_conduit(frame=f)
        out_path = os.path.join(SPRITES_BUILDINGS, f"pipe_conduit_f{f}.png")
        render_and_clean(objs, out_path)
        print(f"  [OK] pipe_conduit_f{f}.png")

    # 2. 渲染静态主图标 (pipe_conduit.png & pipe.png)
    print("[PIPE] Rendering static main icons ...")
    clear_scene()
    setup_render_settings(256, 256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_pipe_conduit(frame=0)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "pipe_conduit.png"))
    print("  [OK] pipe_conduit.png")

    clear_scene()
    setup_render_settings(256, 256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_PROP)
    objs = build_pipe_conduit(frame=0)
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "pipe.png"))
    print("  [OK] pipe.png")

    print("\n" + "=" * 60)
    print("  ✓ All Pipe Conduit renders complete!")
    print("=" * 60)

if __name__ == '__main__':
    main()
