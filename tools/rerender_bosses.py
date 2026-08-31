"""定向重渲 Boss 精灵 (Targeted boss re-render).

与 rerender_tanks.py / rerender_tiles.py / rerender_vfx.py 同一个家族, 存在理由
也一样: **绝不为了改一个资源去跑 build_* 脚本的 main()**。

这里尤其要命 —— 四个 Boss 分属两个所有者脚本, 而其中
build_expansion_sokpop_assets.py::main() 除了 enemy_boss 之外还会渲
diorama_shop / diorama_event / icon_atk / icon_speed / icon_armor / icon_regen,
这 6 张都在 CLAUDE.md 记录的"16 张孤儿资产"名单里 —— 没有任何现存脚本能复现
它们已提交的样子。跑一次 main() 就会把它们静默换成没人审过的版本。

所以本脚本从所有者脚本里 import 建模函数, 只渲指定的那一组, 不复制几何
(复制 = 第二个能渲同一张图的地方 = 下一次画风发散的起点)。

每个 Boss 的机位/种子必须与所有者 main() 里的完全一致, 否则重渲出来的图会和
已提交版本对不上, 而这种差异会被误读成"美术被改了":
  - enemy_boss        seed 2000, ortho 3.60 (ORTHO_SCALE_TANK), 在 main() 里排第 1
  - titan/scorpion/mammoth  seed 3500, ortho 3.85, 在 main() 里分别排第 1/2/3

注意 scorpion/mammoth 的 jitter 种子: 所有者脚本只在 main() 开头 reset 一次,
之后三个 Boss 连续渲, 所以第 2、3 个 Boss 拿到的是被前面消耗过的随机流。想
逐像素复现它们, 就必须按 main() 的顺序把前面的也走一遍 —— 这就是
--faithful 干的事 (默认开启)。

用法:
    blender --background --python tools/rerender_bosses.py -- enemy_boss
    blender --background --python tools/rerender_bosses.py -- enemy_titan_boss
    blender --background --python tools/rerender_bosses.py -- --list
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
    reset_jitter_seed,
    render_and_clean,
    ORTHO_SCALE_TANK,
)
from build_expansion_sokpop_assets import build_sokpop_boss_tank
from build_advanced_bosses_and_vfx import (
    build_titan_boss,
    build_scorpion_boss,
    build_mammoth_boss,
    SPRITES_TANKS,
)

BOSS_ORTHO = 3.85       # titan/scorpion/mammoth 共用的宽机位

# name -> (builder, seed, ortho, 该 Boss 在所有者 main() 中的序号)
GROUPS = {
    "enemy_boss":          (build_sokpop_boss_tank, 2000, ORTHO_SCALE_TANK, 0),
    "enemy_titan_boss":    (build_titan_boss,       3500, BOSS_ORTHO,       0),
    "enemy_scorpion_boss": (build_scorpion_boss,    3500, BOSS_ORTHO,       1),
    "enemy_mammoth_boss":  (build_mammoth_boss,     3500, BOSS_ORTHO,       2),
}

# 与 GROUPS 中序号对应的同批次顺序 (用于 --faithful 消耗随机流)
ADVANCED_ORDER = [build_titan_boss, build_scorpion_boss, build_mammoth_boss]


def parse_targets(argv):
    """取 `--` 之后的参数; Blender 会把它前面的都吃掉。"""
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return []


def render_group(name, faithful=True):
    builder, seed, ortho, order = GROUPS[name]

    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ortho)
    reset_jitter_seed(seed)

    # 复现所有者 main() 的随机流: 把排在本 Boss 前面的那些先建再丢。
    # 只对 build_advanced_bosses_and_vfx 那三个有意义 (enemy_boss 排第 1)。
    if faithful and order > 0:
        for earlier in ADVANCED_ORDER[:order]:
            for frame in range(6):
                for ob in earlier(frame):
                    try:
                        import bpy
                        bpy.data.objects.remove(ob, do_unlink=True)
                    except Exception:
                        pass

    print(f">>> 重渲 {name} (6 帧, seed={seed}, ortho={ortho})...")
    for frame in range(6):
        objs = builder(frame)
        render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

        # 无后缀的图标图必须在 frame==0 之后*立刻*渲, 不能挪到循环外面。
        # 它是所有者 main() 里 `if frame == 0:` 分支的第二次 build_*(0) —— 那次
        # 建模会消耗顶点抖动的随机流, 后面 f1..f5 拿到的是被消耗过的流。挪到
        # 循环末尾看起来等价, 实测会让 f1..f5 全部对不上已提交美术
        # (rms_low 0.40~0.49), 而 f0 完好 —— 这种"第一帧对、后面全错"的形状就是
        # 随机流错位的指纹, 很容易被误读成"美术被改了"。
        if frame == 0 and name != "enemy_boss":
            render_and_clean(builder(0), os.path.join(SPRITES_TANKS, f"{name}.png"))


def main():
    targets = parse_targets(sys.argv)

    if not targets or "--list" in targets:
        print("可重渲的 Boss:")
        for k in sorted(GROUPS):
            _b, seed, ortho, order = GROUPS[k]
            print(f"  {k:<22} seed={seed} ortho={ortho} 批内序号={order}")
        if not targets:
            print("\n未指定目标。用法: blender --background --python tools/rerender_bosses.py -- <name> [...]")
        return

    faithful = "--no-faithful" not in targets
    targets = [t for t in targets if not t.startswith("--")]

    if not targets:
        targets = sorted(GROUPS)

    unknown = [t for t in targets if t not in GROUPS]
    if unknown:
        print(f"[ERROR] 未知的 Boss: {', '.join(unknown)}")
        print(f"[ERROR] 可选: {', '.join(sorted(GROUPS))}")
        raise SystemExit(1)

    for name in targets:
        render_group(name, faithful=faithful)

    print(f"\n[OK] 已重渲 {len(targets)} 个 Boss。")


if __name__ == "__main__":
    main()
