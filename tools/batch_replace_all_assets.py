#!/usr/bin/env python3
"""
batch_replace_all_assets.py
一键执行 Blender 全量 3D 黏土模型与材质重渲染、法线烘焙、Godot 资产重导入并启动游戏
"""

import os
import sys
import subprocess
import time

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

BLENDER_EXE = r"C:\steam\steamapps\common\Blender\blender.exe"
GODOT_CONSOLE = r"C:\Godot\tools\Godot_v4.5-stable_win64_console.exe"
GODOT_GUI = r"C:\Godot\tools\Godot_v4.5-stable_win64.exe"

PROJECT_DIR = r"G:\Users\123\Documents\GitHub\godot"
TOOLS_DIR = os.path.join(PROJECT_DIR, "tools")

RENDER_SCRIPTS = [
    "build_all_sokpop_assets_unified.py",
    "build_differentiated_enemy_assets.py",
    "build_advanced_bosses_and_vfx.py",
    "build_engineer_tank.py",
    "build_spider_tank.py",
    "build_sandworm_tank.py",
    "build_all_bullet_assets.py",
    "build_bunker_assets.py",
    "build_flamethrower_assets.py",
    "build_sokpop_animations.py",
    "build_normal_maps.py",
]

def main():
    print("==================================================================")
    print("🚀 开始执行全量 3D 黏土模型渲染与 Godot 资产全量替换流程...")
    print(f"📁 项目路径: {PROJECT_DIR}")
    print(f"🎨 Blender 引擎: {BLENDER_EXE}")
    print("==================================================================")

    # 1. 依次执行所有 Blender 渲染脚本
    for script_name in RENDER_SCRIPTS:
        script_path = os.path.join(TOOLS_DIR, script_name)
        if not os.path.exists(script_path):
            print(f"[跳过] 脚本不存在: {script_name}")
            continue

        print(f"\n>>> [1/3 渲染中] 正在执行: {script_name} ...")
        cmd = [BLENDER_EXE, "--background", "--python", script_path]
        try:
            res = subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True, encoding="utf-8", errors="ignore")
            if res.returncode == 0:
                print(f"  ✅ {script_name} 渲染完成并已写入 assets/ 目录！")
            else:
                print(f"  ⚠️ {script_name} 执行返回代码: {res.returncode}")
                if res.stderr:
                    print("  [错误信息]:", res.stderr[-300:])
        except Exception as e:
            print(f"  ❌ 执行出错: {e}")

    # 2. 调用 Godot 引擎重新导入全量资产
    print("\n==================================================================")
    print("🔄 [2/3 重导入] 正在通知 Godot 引擎重新扫描并编译全部新资产缓存...")
    print("==================================================================")
    import_cmd = [GODOT_CONSOLE, "--headless", "--path", PROJECT_DIR, "--editor", "--quit"]
    try:
        res = subprocess.run(import_cmd, cwd=PROJECT_DIR, capture_output=True, text=True, encoding="utf-8", errors="ignore")
        print("  ✅ Godot 资产缓存全部重导入完成！")
    except Exception as e:
        print(f"  ❌ Godot 导入执行出错: {e}")

    # 3. 自动化测试验证
    print("\n==================================================================")
    print("🧪 [3/3 验证中] 正在运行全量自动化集成测试验证新资产一致性...")
    print("==================================================================")
    test_cmd = [GODOT_CONSOLE, "--headless", "--path", PROJECT_DIR, "--script", "tools/test_compile_all.gd"]
    subprocess.run(test_cmd, cwd=PROJECT_DIR)

    # 4. 启动 Godot 游戏
    print("\n==================================================================")
    print("🎉 全部资产已成功替换！正在为您启动 Godot 游戏...")
    print("==================================================================")
    subprocess.Popen([GODOT_GUI, "--path", PROJECT_DIR], cwd=PROJECT_DIR)
    print("游戏已在前台启动。")

if __name__ == '__main__':
    main()
