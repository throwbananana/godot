"""按名字定向重渲坦克精灵, 不动其它资源。

为什么需要它: build_all_sokpop_assets_unified.py 的 main() 是全量的 —— 跑一次会
重渲 240 帧坦克 + 全部瓦片/建筑/道具。只要工作区里有任何尚未提交的资源改动
(例如手工调过的 enemy_laser / enemy_missile, 或还没入库的 enemy_warp), 全量跑
就会把它们连同目标一起覆盖掉。调一个 enemy_basic 的颜色不该有这种爆炸半径。

调色板从 build_all_sokpop_assets_unified 直接 import, 是唯一真源 —— 这里不复制
一份, 否则两边迟早发散 (这正是当年三份 render 管线副本的老问题)。

用法:
    blender --background --python tools/rerender_tanks.py -- enemy_basic
    blender --background --python tools/rerender_tanks.py -- enemy_basic enemy_fast
    blender --background --python tools/rerender_tanks.py -- --list

关于抖动种子: reset_jitter_seed() 用固定值 2000, 因此本脚本可复现 (同样输入 ->
同样输出)。它不会复刻全量批次里该坦克所处的种子位置 —— 顶点抖动本来就是随机
装饰, 要的是确定性而不是和某次历史批次逐字节一致。
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
    ORTHO_SCALE_TANK,
)
from build_all_sokpop_assets_unified import (
    build_sokpop_tank,
    PLAYER_PALETTES,
    ENEMY_PALETTES,
    SPRITES_TANKS,
)

ALL_PALETTES = {}
ALL_PALETTES.update(PLAYER_PALETTES)
ALL_PALETTES.update(ENEMY_PALETTES)

JITTER_SEED = 2000


def parse_targets(argv):
    """取 `--` 之后的参数; Blender 会把它前面的都吃掉。"""
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return []


def main():
    targets = parse_targets(sys.argv)

    if not targets or "--list" in targets:
        print("可重渲的坦克:")
        for k in sorted(ALL_PALETTES):
            print(f"  {k}")
        if not targets:
            print("\n未指定目标。用法: blender --background --python tools/rerender_tanks.py -- <name> [...]")
        return

    unknown = [t for t in targets if t not in ALL_PALETTES]
    if unknown:
        print(f"[ERROR] 未知的坦克名: {', '.join(unknown)}")
        print(f"[ERROR] 可选: {', '.join(sorted(ALL_PALETTES))}")
        raise SystemExit(1)

    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    reset_jitter_seed(JITTER_SEED)

    for name in targets:
        cfg = ALL_PALETTES[name]
        print(f">>> 重渲 {name} (6 帧)...")
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"],
                barrel_thick=cfg["bthick"], is_heavy=cfg["heavy"],
                is_plasma=cfg.get("plasma", False), frame=frame,
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    print(f"\n[OK] 已重渲 {len(targets)} 组坦克, 共 {len(targets) * 6} 帧。")


if __name__ == "__main__":
    main()
