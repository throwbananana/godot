#!/usr/bin/env python3
"""
Godot Tank Battle -> 3D WebGL Clay Studio & Battle Arena Launcher
一键从 Godot 项目中启动 Three.js 3D 黏土模型精修工坊与 3D 战场模拟器
"""
import os
import sys
import subprocess

STUDIO_DIR = r"G:\tools\treee.js-project1"

def main():
    if not os.path.exists(STUDIO_DIR):
        print(f"[错误] 未找到 3D 黏土工坊目录: {STUDIO_DIR}")
        input("按回车退出...")
        return

    print("==================================================================")
    print("🎨 正在从 Godot 项目启动 Three.js 3D 黏土模型精修工坊与 3D 战场模拟器...")
    print(f"📁 工坊路径: {STUDIO_DIR}")
    print("🌐 即将自动唤起默认浏览器访问 http://localhost:8080")
    print("==================================================================")

    server_script = os.path.join(STUDIO_DIR, "server.py")
    if os.path.exists(server_script):
        subprocess.run([sys.executable, server_script], cwd=STUDIO_DIR)
    else:
        print(f"[错误] 未找到服务脚本: {server_script}")

if __name__ == '__main__':
    main()
