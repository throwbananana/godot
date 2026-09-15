"""rerender_buildings.py — 定向重渲 build_all_sokpop_assets_unified.py 名下的建筑图

    blender --background --python tools/rerender_buildings.py -- turret_gun
    blender --background --python tools/rerender_buildings.py -- --list
    blender --background --python tools/rerender_buildings.py -- --all

=== 为什么需要这个 ===

CLAUDE.md 有一条很硬的规矩: **绝不要为了改一个资产去跑 unified 的 main()**
—— 它会把 240 帧坦克加上每一块瓦片/建筑/道具全部重渲一遍, 顺手覆盖掉工作区
里任何还没提交的美术改动。

坦克有 rerender_tanks.py, 地形有 rerender_tiles.py, 特效有 rerender_vfx.py,
唯独 unified 名下的这 5 张建筑图一直没有定向入口 —— 于是"只想改一下炮塔"就
只剩下跑 main() 这一条路, 正好撞在那条规矩上。这个文件补上这个口子。

和那三个同门工具一样, 它**从属主导入建模函数**, 一行几何都不抄 —— 抄一份就
等于又造了一个会各自漂移的属主, 而这个仓库因为这件事吃过好几次亏
(见 CLAUDE.md "Stale build scripts")。

=== 渲染设置照抄属主 main() 跑到这一批时的现场 ===

setup_render_settings(256, 256) + create_sokpop_lighting(ORTHO_SCALE_DEFAULT)
(**带点光源**, 不是 seamless —— 这几个都是独立物件而不是满幅瓦片) +
reset_jitter_seed(1000)。

这套口径是量出来的而不是猜的: qa_orphan_audit.py 里 buildings/turret_gun.png
与 buildings/turret_base.png 两条, 用 point/3.3 复现已提交的美术分别是
d_rgb 0.34 / 0.99 (判定线 3.0, Cycles 采样噪声本底就有 1~2)。

=== 注意 turret_gun / repair_station 有第二个"生产者" ===

tools/refine_buildings_and_tanks.py 里的 build_refined_turret_gun() 是**另一版
完全不同的美术** (深色底盘 + 双管加特林 + 警示黄炮盾 + 侧挂导弹巢), 而且它也
往同一个 turret_gun.png 里写。谁最后跑谁赢, 而已提交的那版是 unified 的蓝色
圆顶。**跑 refine_buildings_and_tanks.py 会静默把炮塔换成另一版。**
这和 CLAUDE.md 已经记过的 refine_all_assets.py 对六个道具的陷阱是同一个坑的
另一个洞。
"""

import os
import sys

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
    SPRITES_BUILDINGS,
    build_sokpop_turret_base,
    build_sokpop_turret_gun,
    build_sokpop_fortified_wall,
    build_sokpop_landmine,
    build_sokpop_repair_station,
)

## 与属主 main() 里 "3. Rendering Unified Sokpop Buildings" 那一批一一对应。
GROUPS = {
    "turret_base":    build_sokpop_turret_base,
    "turret_gun":     build_sokpop_turret_gun,
    "fortified_wall": build_sokpop_fortified_wall,
    "landmine":       build_sokpop_landmine,
    "repair_station": build_sokpop_repair_station,
}

JITTER_SEED = 1000


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--list" in argv:
        print("可渲染的建筑 (属主 build_all_sokpop_assets_unified.py):")
        for n in sorted(GROUPS):
            print("   ", n)
        return

    names = sorted(GROUPS) if "--all" in argv else [a for a in argv if not a.startswith("-")]
    if not names:
        print("[ERROR] 没指定要渲哪个。用 -- <名字> / -- --all / -- --list")
        raise SystemExit(1)
    unknown = [n for n in names if n not in GROUPS]
    if unknown:
        print("[ERROR] 不认识: %s" % ", ".join(unknown))
        print("        可选: %s" % ", ".join(sorted(GROUPS)))
        raise SystemExit(1)

    print("=" * 60)
    print("  定向重渲建筑 (%d 张)" % len(names))
    print("=" * 60)

    for name in names:
        clear_scene()
        setup_render_settings(rx=256, ry=256)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
        reset_jitter_seed(JITTER_SEED)
        out = os.path.join(SPRITES_BUILDINGS, "%s.png" % name)
        render_and_clean(GROUPS[name](), out)
        print("  [OK] %s.png" % name)

    print("\n" + "=" * 60)
    print("  完成 -> %s" % SPRITES_BUILDINGS)
    print("  别忘了: python tools/fix_sprite_mipmaps.py, 然后 --editor --quit 重导")


if __name__ == "__main__":
    main()
