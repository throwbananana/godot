"""按名字定向重渲特效动画, 不动其它资源。

为什么需要它: 和 rerender_tanks.py 同样的理由 —— 爆炸的 6 帧归
build_all_sokpop_assets_unified.py 管, 而那个脚本的 main() 是全量的, 跑一次
会连带重渲 240 帧坦克和所有瓦片/建筑/道具, 把工作区里任何还没入库的资源一起
覆盖掉。调一组爆炸不该有这种爆炸半径。

各组的 builder 一律从*属主脚本* import, 不在这里复制一份几何代码。这是本仓库
反复吃过亏的地方: 一旦两处都能渲同一张图, 谁最后跑谁赢, 美术就会莫名其妙地
回退 (见 CLAUDE.md "Stale build scripts")。这里只负责挑帧和摆画幅。

用法:
    blender --background --python tools/rerender_vfx.py -- explosion
    blender --background --python tools/rerender_vfx.py -- explosion suicide_blast
    blender --background --python tools/rerender_vfx.py -- --all
    blender --background --python tools/rerender_vfx.py -- --list
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
from build_all_sokpop_assets_unified import build_sokpop_explosion, SPRITES_EFFECTS, SPRITES_TILES
from build_suicide_and_mirage_assets import build_suicide_blast_vfx, ORTHO_SCALE_BLAST
from build_sokpop_animations import build_dust_puff, build_muzzle_flash, build_base_eagle_idle
from build_semantic_vfx import (
    build_heal_pulse,
    build_emp_pulse,
    build_reward_burst,
    build_frost_shatter,
    build_sand_burst,
    build_build_assemble,
    build_ricochet_spark,
    build_hit_spall,
)

JITTER_SEED = 3100

# name -> (builder, 帧数, 输出名模板, ortho_scale[, 输出目录])
#
# 第 5 项是可选的输出目录, 缺省 SPRITES_EFFECTS。加它是因为鹰巢待机动画属于
# 地形目录 (base_eagle.gd 从 tiles/ 取图), 而这个脚本原来写死了 effects/ ——
# 写死的话要么把鹰渲错地方, 要么就得为它单开一个脚本, 两条都不如加一项。
GROUPS = {
    "explosion":     (build_sokpop_explosion,   6, "explosion_{i}.png",         ORTHO_SCALE_DEFAULT),
    # 爆炸差分。同一套火球语言的另外两次实例 (换角相位 + 换 wobble 种子),
    # 不是另外两种爆炸 —— 见 build_sokpop_explosion 上方 EXPLOSION_VARIANTS。
    "explosion_v1":  (lambda i: build_sokpop_explosion(i, 1), 6, "explosion_v1_{i}.png", ORTHO_SCALE_DEFAULT),
    "explosion_v2":  (lambda i: build_sokpop_explosion(i, 2), 6, "explosion_v2_{i}.png", ORTHO_SCALE_DEFAULT),
    "suicide_blast": (build_suicide_blast_vfx,  6, "vfx_suicide_blast_f{i}.png", ORTHO_SCALE_BLAST),
    "dust_puff":     (build_dust_puff,          6, "dust_puff_{i}.png",         ORTHO_SCALE_DEFAULT),
    "muzzle_flash":  (build_muzzle_flash,       6, "muzzle_flash_{i}.png",      ORTHO_SCALE_DEFAULT),

    # 语义化特效组 (build_semantic_vfx.py)。存在的理由见那个脚本的顶部注释:
    # 通用冲击波一个人演了 79 处语义不同的事件, 这六组是把它拆开。
    "heal_pulse":     (build_heal_pulse,     6, "vfx_heal_pulse_f{i}.png",     ORTHO_SCALE_DEFAULT),
    "emp_pulse":      (build_emp_pulse,      6, "vfx_emp_pulse_f{i}.png",      ORTHO_SCALE_DEFAULT),
    "reward_burst":   (build_reward_burst,   6, "vfx_reward_burst_f{i}.png",   ORTHO_SCALE_DEFAULT),
    "frost_shatter":  (build_frost_shatter,  6, "vfx_frost_shatter_f{i}.png",  ORTHO_SCALE_DEFAULT),
    "sand_burst":     (build_sand_burst,     6, "vfx_sand_burst_f{i}.png",     ORTHO_SCALE_DEFAULT),
    "build_assemble": (build_build_assemble, 6, "vfx_build_assemble_f{i}.png", ORTHO_SCALE_DEFAULT),

    # 鹰巢待机动画。**注意它写进 tiles/ 而不是 effects/**。
    # 不要拿 build_sokpop_animations.py 的 main() 去渲它 —— 那个 main() 会连带
    # 重渲 muzzle_flash / clay_debris / shield_bubble / shockwave / dust_puff /
    # base_damaged 六组已提交的美术。定向重渲走这里。
    "base_eagle_idle": (build_base_eagle_idle, 6, "base_eagle_f{i}.png", ORTHO_SCALE_DEFAULT, SPRITES_TILES),
    # 第二批拆分: 通用特效仍然承担着 217 处调用 (shockwave 82 / clay_debris 74 /
    # dust_puff 61)。这两组拆的是其中最要命的两对语义 —— "打不动" vs "打没了",
    # "受伤" vs "被摧毁"。
    "ricochet_spark": (build_ricochet_spark, 6, "vfx_ricochet_spark_f{i}.png", ORTHO_SCALE_DEFAULT),
    "hit_spall":      (build_hit_spall,      6, "vfx_hit_spall_f{i}.png",      ORTHO_SCALE_DEFAULT),
}


def parse_targets(argv):
    """取 `--` 之后的参数; Blender 会把它前面的都吃掉。"""
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return []


def main():
    targets = parse_targets(sys.argv)

    if not targets or "--list" in targets:
        print("可重渲的特效组:")
        for k in sorted(GROUPS):
            print(f"  {k}")
        if not targets:
            print("\n未指定目标。用法: blender --background --python tools/rerender_vfx.py -- <name> [...] | --all")
        return

    if "--all" in targets:
        targets = sorted(GROUPS)

    unknown = [t for t in targets if t not in GROUPS]
    if unknown:
        print(f"[ERROR] 未知的特效组: {', '.join(unknown)}")
        print(f"[ERROR] 可选: {', '.join(sorted(GROUPS))}")
        raise SystemExit(1)

    total = 0
    for name in targets:
        entry = GROUPS[name]
        builder, n_frames, tmpl, ortho = entry[:4]
        out_dir = entry[4] if len(entry) > 4 else SPRITES_EFFECTS
        print(f">>> 重渲 {name} ({n_frames} 帧, ortho={ortho}) -> {os.path.basename(out_dir)}/")
        for i in range(n_frames):
            # 每帧都重建场景: create_sokpop_lighting() 是幂等的 (会先清光源),
            # 但 clear_scene() 才能保证上一帧的网格不会留在画面里 —— 那正是
            # 当年九张 UI 图渲成灰方块的原因。
            clear_scene()
            setup_render_settings(rx=256, ry=256, samples=28)
            create_sokpop_lighting(ortho_scale=ortho)
            reset_jitter_seed(JITTER_SEED + i)
            objs = builder(i)
            render_and_clean(objs, os.path.join(out_dir, tmpl.format(i=i)))
            total += 1

    print(f"\n[OK] 已重渲 {len(targets)} 组特效, 共 {total} 帧。")


if __name__ == "__main__":
    main()
