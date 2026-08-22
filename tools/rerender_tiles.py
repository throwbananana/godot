"""按名字定向重渲地形瓦片, 不动其它资源。

和 rerender_tanks.py / rerender_vfx.py 同一套路: builder 一律从*属主脚本*
import, 这里只负责挑目标和摆画幅, 不复制几何代码。

只登记了属主脚本确认能复现已提交美术的那几张。**故意不含** tile_ice /
tile_hard_clay / tile_conveyor / tile_jump_pad / tile_platform —— 它们属于
CLAUDE.md 里记的那 16 张"孤儿资源": 渲它们的脚本已经被删了, 现存的实现只能
复现轮廓、复现不了着色。给它们重渲等于拿已知可用的美术去换一版没人审过的,
需要先做美术决策, 不是顺手就能做的事。

用法:
    blender --background --python tools/rerender_tiles.py -- tile_brick
    blender --background --python tools/rerender_tiles.py -- --all
    blender --background --python tools/rerender_tiles.py -- --list
"""

import os
import sys

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    render_and_clean,
    reset_jitter_seed,
    ORTHO_SCALE_DEFAULT,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_brick,
    build_sokpop_steel,
    build_sokpop_trees,
    build_sokpop_water,
    SPRITES_TILES,
)
from build_desert_mechanics import build_desert_sand_tile

JITTER_SEED = 4200

# name -> (builder, 帧数(1=单张), 输出名模板)
# builder 收一个 frame 参数; 单张的用 lambda 吞掉。
GROUPS = {
    "tile_brick": (lambda f: build_sokpop_brick(), 1, "tile_brick.png"),
    "tile_steel": (lambda f: build_sokpop_steel(), 1, "tile_steel.png"),
    "tile_trees": (lambda f: build_sokpop_trees(), 1, "tile_trees.png"),
    "tile_sand":  (lambda f: build_desert_sand_tile(), 1, "tile_sand.png"),
    "tile_water": (build_sokpop_water, 6, "tile_water_f{i}.png"),
}


def parse_targets(argv):
    """取 `--` 之后的参数; Blender 会把它前面的都吃掉。"""
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return []


def main():
    targets = parse_targets(sys.argv)

    if not targets or "--list" in targets:
        print("可重渲的瓦片:")
        for k in sorted(GROUPS):
            print(f"  {k}")
        if not targets:
            print("\n未指定目标。用法: blender --background --python tools/rerender_tiles.py -- <name> [...] | --all")
        return

    # --legacy-light 用旧的点光源布光渲。存在的意义是"复现性对照":
    # 想知道某处差异是自己改出来的还是脚本本来就渲不出已提交的图, 就用它渲一遍
    # 和 HEAD 比 —— 这是 CLAUDE.md 反复强调的那道手续 (陈旧脚本会悄悄改掉美术)。
    legacy = "--legacy-light" in targets
    targets = [t for t in targets if not t.startswith("--legacy")]

    if "--all" in targets:
        targets = sorted(GROUPS)

    unknown = [t for t in targets if t not in GROUPS]
    if unknown:
        print(f"[ERROR] 未知的瓦片: {', '.join(unknown)}")
        print(f"[ERROR] 可选: {', '.join(sorted(GROUPS))}")
        raise SystemExit(1)

    total = 0
    for name in targets:
        builder, n_frames, tmpl = GROUPS[name]
        print(f">>> 重渲 {name} ({n_frames} 帧)...")
        for i in range(n_frames):
            clear_scene()
            setup_render_settings(rx=256, ry=256)
            # 满幅地形瓦片走无缝光照 —— 点光源会在瓦片内部造出位置梯度,
            # 铺开后就是一条条网格线。详见 sokpop_common.create_sokpop_lighting。
            create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT, seamless=not legacy)
            reset_jitter_seed(JITTER_SEED + i)
            objs = builder(i)
            out = tmpl.format(i=i) if "{i}" in tmpl else tmpl
            render_and_clean(objs, os.path.join(SPRITES_TILES, out))
            total += 1

    print(f"\n[OK] 已重渲 {len(targets)} 组瓦片, 共 {total} 张。")


if __name__ == "__main__":
    main()
