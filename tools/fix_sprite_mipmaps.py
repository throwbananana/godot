#!/usr/bin/env python3
"""把 assets/sprites 下所有 .import 的 mipmaps/generate 拨成 true。

为什么需要这个脚本 (以及为什么它是通用的、不按批次写死)
--------------------------------------------------------
世界贴图是 256x256 的 Blender 渲染, 游戏里按 TILE_SCALE = 0.1875 画成 48px,
5.33 倍缩小 —— 没有 mipmap 就是爬行走样, 而不是"像素风的颗粒感"。
project.godot 里 default_texture_filter=3 (Linear Mipmap) 只是采样端, 贴图本身
有没有 mip 链由导入器决定。

问题在于 Godot 给新 PNG 生成的 .import 默认写 mipmaps/generate=false, 而且
**不报任何错** —— 没有 mipmap 的贴图照样渲染, 只是糊。历史上这条保证因此空转了
很久 (v0.06316 时 ~430 张全是 false), 后来被 tools/test_texture_mipmaps.gd 拦住,
但每加一批新图就会复发一次: enemy_plate_t* 复发过一次, 标题界面那 14 张
(vfx_sparkle_glint / vfx_ui_ripple / title_background_clay / title_logo_banner /
ui_logo_halo) 又复发了一次。

tools/ 里原本躺着三个按目录写死的修补脚本 (generate_new_imports.py /
generate_splitter_imports.py / generate_enemy_shield_tower_imports.py), 各自只
认自己那一批文件名 —— 于是每来一批新图就得再抄一个。这个脚本改成扫全树 + 原地
改写单个键, 不再关心批次: 加完图跑它一次就行。

用法:
    python tools/fix_sprite_mipmaps.py            # 实际改写
    python tools/fix_sprite_mipmaps.py --dry-run  # 只报告, 不落盘

改完必须重新导入, 否则 .godot 里缓存的还是旧的无 mip 版本:
    godot --headless --path . --import
    godot --headless --path . --script tools/test_texture_mipmaps.gd
"""

import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES_DIR = os.path.join(REPO_ROOT, "assets", "sprites")

NEEDLE = "mipmaps/generate=false"
FIXED = "mipmaps/generate=true"


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    if not os.path.isdir(SPRITES_DIR):
        print("[FAIL] 找不到 %s" % SPRITES_DIR)
        return 1

    scanned = 0
    changed = []
    # .import 里没有 mipmaps/generate 这一行的情况: Godot 只会在写过该键时才落
    # 这一行, 缺行等同于 false, 所以这里也要补 —— 只找 =false 会漏掉它们。
    missing_key = []

    for root, _dirs, files in os.walk(SPRITES_DIR):
        for name in files:
            if not name.endswith(".import"):
                continue
            path = os.path.join(root, name)
            scanned += 1
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()

            rel = os.path.relpath(path, REPO_ROOT).replace("\\", "/")

            if NEEDLE in text:
                new_text = text.replace(NEEDLE, FIXED)
                changed.append(rel)
            elif "mipmaps/generate=" not in text:
                # 挂在 [params] 段首, 与 Godot 自己的写法保持一致。
                if "[params]" not in text:
                    print("  [WARN] %s 没有 [params] 段, 跳过" % rel)
                    continue
                new_text = text.replace("[params]\n", "[params]\n\n%s\n" % FIXED, 1)
                missing_key.append(rel)
            else:
                continue

            if not dry_run:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new_text)

    total = len(changed) + len(missing_key)
    print("扫描 %d 个 .import" % scanned)
    if not total:
        print("✓ 全部已经是 mipmaps/generate=true, 无需改动")
        return 0

    verb = "需要改写" if dry_run else "已改写"
    print("%s %d 个:" % (verb, total))
    for rel in changed[:20]:
        print("  - %s  (false -> true)" % rel)
    for rel in missing_key[:20]:
        print("  - %s  (缺键 -> true)" % rel)
    if total > 20:
        print("  ... 另有 %d 个" % (total - 20))

    if not dry_run:
        print("\n下一步 (不重新导入的话 .godot 里缓存的还是旧的无 mip 版本):")
        print("  godot --headless --path . --import")
        print("  godot --headless --path . --script tools/test_texture_mipmaps.gd")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
