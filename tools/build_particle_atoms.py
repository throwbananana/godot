"""粒子原子 (particle atoms) —— 运行时粒子层用的单颗贴图。

这批和本目录其它 build_*.py 的区别在于**用途**: 其它脚本渲的是"一整个效果"
(六帧翻书, 整团碎块一次性画完), 这里渲的是**一颗**碎片 / 一粒火星 / 一团烟,
由 scripts/vfx_particles.gd 在运行时给每一颗算速度、重力、自旋和淡出。

为什么仍然走 Blender 而不是在 GDScript 里 draw_circle:
整套美术是 Sokpop 黏土渲染 (见 sokpop_common.py 顶部), 平涂的矢量圆点混在
里面一眼就是外来物。渲出来的原子自带黏土的凹凸、次表面和同一套光照预算,
和现有特效是同一种材质感。

尺寸取 128 而不是项目标准的 256: 这些东西在屏幕上只有 5~12px
(见 vfx_particles.gd 里的 size 取值), 256 的源图纯属浪费内存 ——
按 compress/mode=0 无损导入, 256 一张约 350KB, 128 一张约 87KB。

用法:
    blender --background --python tools/build_particle_atoms.py
    blender --background --python tools/build_particle_atoms.py -- spark smoke
"""

import bpy
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sokpop_common import (  # noqa: E402
    clear_scene, setup_render_settings, create_sokpop_lighting, create_clay_mat,
    apply_uniform_clay_bevel, reset_jitter_seed, render_and_clean,
    clear_material_cache, purge_orphans,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), "assets", "sprites", "effects")

RES = 128
# 画幅取得很紧, 让单颗原子尽量占满 128px —— 它在游戏里会被缩到几个像素,
# 源图里留白越多, 有效分辨率越低。
ORTHO_ATOM = 1.30


def _shard(name, seed_rot, stretch=1.0, col=(0.66, 0.45, 0.30)):
    """一块带棱角的黏土碎片。三个变体只换朝向和长宽比, 不换材质 ——
    颗粒在屏幕上只有几个像素, 能读出来的差别只有剪影比例。"""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.46, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1.0 * stretch, 0.78 / stretch, 0.62)
    obj.rotation_euler = (0.0, 0.0, seed_rot)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    apply_uniform_clay_bevel(obj, width=0.05, segments=2, jitter=0.02)
    obj.data.materials.append(create_clay_mat(f"mat_{name}", col, roughness=0.80))
    return obj


def build_clay_chunk_a():
    return [_shard("chunk_a", 0.0, 1.0)]


def build_clay_chunk_b():
    return [_shard("chunk_b", math.radians(37.0), 1.35, (0.61, 0.41, 0.27))]


def build_clay_chunk_c():
    return [_shard("chunk_c", math.radians(71.0), 0.80, (0.70, 0.50, 0.34))]


def build_spark():
    """撞击火星: 细长的热核。拉长是为了在旋转时能读出"飞行方向",
    圆点转起来是没有方向的。"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.30, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = "spark"
    obj.scale = (1.9, 0.42, 0.42)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    # 自发光压在 emission_peak 以内, 不然会被 create_clay_mat 的过曝钳位削平
    # (见 CLAUDE.md "每个发光脉冲通道都被钳成了常数" 那段)。
    obj.data.materials.append(create_clay_mat(
        "mat_spark", (1.0, 0.86, 0.52), roughness=0.55,
        emission=(1.0, 0.80, 0.42), emission_str=2.6, bump_strength=0.10, mottle=0.03))
    return [obj]


def build_ember():
    """余烬: 比火星小、更圆、更暗, 用于爆炸尾焰。"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=0.34, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = "ember"
    obj.scale = (1.0, 0.92, 0.70)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(create_clay_mat(
        "mat_ember", (0.98, 0.48, 0.16), roughness=0.62,
        emission=(1.0, 0.42, 0.10), emission_str=1.8, bump_strength=0.14, mottle=0.05))
    return [obj]


def build_smoke():
    """烟团: 三个错开的球叠成不规则轮廓。单球会读成"一个灰点",
    错开之后即使缩到 8px 边缘也还是毛的, 这正是烟和实心碎块的区别。"""
    objs = []
    for i, (dx, dy, r) in enumerate([(0.0, 0.0, 0.40), (0.17, 0.11, 0.29), (-0.15, 0.14, 0.25)]):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=r, location=(dx, dy, 0.0))
        o = bpy.context.object
        o.name = f"smoke_{i}"
        o.scale = (1.0, 1.0, 0.72)
        bpy.ops.object.transform_apply(scale=True)
        bpy.ops.object.shade_smooth()
        o.data.materials.append(create_clay_mat(
            "mat_smoke", (0.60, 0.58, 0.56), roughness=0.92,
            bump_strength=0.22, mottle=0.12))
        objs.append(o)
    return objs


BUILDERS = {
    "particle_clay_chunk_a": build_clay_chunk_a,
    "particle_clay_chunk_b": build_clay_chunk_b,
    "particle_clay_chunk_c": build_clay_chunk_c,
    "particle_spark": build_spark,
    "particle_ember": build_ember,
    "particle_smoke": build_smoke,
}


def main():
    argv = sys.argv
    wanted = []
    if "--" in argv:
        wanted = [a for a in argv[argv.index("--") + 1:]]

    names = list(BUILDERS.keys())
    if wanted:
        picked = []
        for w in wanted:
            for n in names:
                if w == n or w == n.replace("particle_", ""):
                    picked.append(n)
        names = picked or names

    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"[particle atoms] 输出目录: {OUT_DIR}")
    print(f"[particle atoms] 将渲染: {', '.join(names)}")

    for name in names:
        clear_scene()
        clear_material_cache()
        # 每颗原子固定同一个抖动种子 —— 三个碎片变体的差异要来自建模参数,
        # 不能来自随机抖动, 否则重渲一次三块碎片就全换了长相。
        reset_jitter_seed(1207)
        setup_render_settings(rx=RES, ry=RES, samples=40)
        create_sokpop_lighting(ortho_scale=ORTHO_ATOM)
        objs = BUILDERS[name]()
        render_and_clean(objs, os.path.join(OUT_DIR, f"{name}.png"), label="[particle atom]")
        purge_orphans()

    print("[particle atoms] 完成。别忘了:")
    print("  1) godot --headless --path . --editor --quit   (生成 .import)")
    print("  2) python tools/fix_sprite_mipmaps.py          (打开 mipmap)")
    print("  3) godot --headless --path . --editor --quit   (重新导入)")


if __name__ == "__main__":
    main()
