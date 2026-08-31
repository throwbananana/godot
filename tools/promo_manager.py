#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tank Battle — 终端营销与推广追踪管理系统 (promo_manager.py)
Unified CLI & Interactive TUI for marketing dispatch, UTM tracking generation,
campaign logging, post metrics collection, analytics dashboard, and itch.io monitoring.
"""

import os
import sys
import json
import time
import argparse
import subprocess
import webbrowser
import urllib.parse
import urllib.request
from datetime import datetime

# Enforce UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

BASE_URL = "https://throwbananana.itch.io/tank-battle"
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOG_FILE = os.path.join(PROJECT_ROOT, "logs", "marketing_tracker.jsonl")
METRICS_FILE = os.path.join(PROJECT_ROOT, "logs", "marketing_metrics.json")
DOCS_KIT = os.path.join(PROJECT_ROOT, "docs", "tank_battle_marketing_kit.md")

CHANNELS = {
    "reddit_godot": {
        "name": "Reddit (r/godot)",
        "category": "Tech / Dev",
        "best_time": "20:00 - 23:00 (UTC+8)",
        "utm_source": "reddit",
        "utm_medium": "community",
        "utm_campaign": "r_godot_launch",
        "submit_url": "https://www.reddit.com/r/godot/submit?title={title}&text={body}",
        "title": "I spent months rebuilding Battle City in Godot 4 — added a Slay the Spire branching campaign, in-battle building, and synthesized all audio in GDScript (Free Web/Win)",
        "body": """Hey everyone! 👋

I'm excited to share **Tank Battle**, a project modernizing the classic NES *Battle City / Tank 1990* with modern roguelite depth and local co-op mechanics.

### 🎮 Key Features:
- **Slay-the-Spire Style Campaign**: 8 Acts × 15 Floors with branching procedural room graphs, elite battles, and shops across 3 biomes (Plains, Desert, Glacial).
- **In-Battle Structure Building**: Place reinforced walls, defense turrets, sniper nests, and traps on the fly!
- **RPG Progression & Workshop**: Upgrade firepower, armor plating, ricochet shells, and special abilities.
- **Local 2-Player Co-op**: Dual controllers / split-keyboard support on couch play.
- **Daily Seeded Runs & Classic Endless Arcade Mode**.

### 🛠️ Technical Highlights:
- **100% Procedural Audio**: There are **zero audio files** in the project. Every explosion, shot, and laser is synthesized at runtime in pure GDScript via `AudioStreamGenerator`.
- **Headless Blender Cycles Pipeline**: All 240+ tank animation frames and tiles rendered headlessly.
- **67 Automated Tests**: Headless CI tests ensuring zero map dead-ends or state sync bugs.

🕹️ **Play free in browser (no install needed) or download for Windows**:  
👉 {link}

I’d love to hear your feedback on the controls, balance, and build variety!"""
    },
    "reddit_webgames": {
        "name": "Reddit (r/WebGames)",
        "category": "Web Gaming",
        "best_time": "20:00 - 23:00 (UTC+8)",
        "utm_source": "reddit",
        "utm_medium": "post",
        "utm_campaign": "r_webgames_launch",
        "submit_url": "https://www.reddit.com/r/WebGames/submit?url={link}&title={title}",
        "title": "[HTML5] Tank Battle - Battle City reimagined as a Slay-the-Spire Roguelite with building and co-op",
        "body": "Play free in browser: {link}\n\nA roguelite reimagining of classic Tank 1990! Features 15-floor Spire campaign, in-battle tactical building, deep upgrades, and local 2P co-op!"
    },
    "reddit_indiegames": {
        "name": "Reddit (r/indiegames)",
        "category": "Indie Gamers",
        "best_time": "20:00 - 23:00 (UTC+8)",
        "utm_source": "reddit",
        "utm_medium": "post",
        "utm_campaign": "r_indiegames_launch",
        "submit_url": "https://www.reddit.com/r/indiegames/submit?title={title}&text={body}",
        "title": "What if Battle City was a Roguelite? I made a game where you build defenses, level up your tank, and climb a 15-floor Spire with a friend. Free on browser!",
        "body": """Remember playing *Battle City / Tank 1990* on the NES? 

I decided to take that core arcade action and turn it into a full-fledged roguelite campaign:
- Branching route selection on a 15-floor map per act
- Mid-battle structure building (walls, turrets, EMP towers)
- Deep tank upgrades in the workshop
- Full 2-player local co-op support

It's completely free to play right in your browser (no install needed) or as a standalone Windows build!

🔗 **Play here**: {link}

Looking forward to your high scores and feedback!"""
    },
    "reddit_playmygame": {
        "name": "Reddit (r/playmygame)",
        "category": "Playtesting / Feedback",
        "best_time": "20:00 - 23:00 (UTC+8)",
        "utm_source": "reddit",
        "utm_medium": "post",
        "utm_campaign": "r_playmygame_launch",
        "submit_url": "https://www.reddit.com/r/playmygame/submit?title={title}&text={body}",
        "title": "[Free Web/Win] Tank Battle - Modern Battle City with Slay-the-Spire Roguelite campaign, base building, and co-op. Looking for feedback!",
        "body": """Hi r/playmygame! 

I've been working on **Tank Battle**, an arcade roguelite where classic tank action meets tactical deckbuilding-style route progression.

- **Platforms**: Free HTML5 (runs smoothly in browser) & Windows standalone.
- **Controls**: Mouse + Keyboard or Full Gamepad support (Xbox / PS / Generic).
- **Core Loop**: Clear arena rooms, scavenge scrap, build mid-combat defenses, upgrade your chassis at shops, and defeat biome bosses.

👉 **Play URL**: {link}

Looking for feedback on:
1. Difficulty pacing across Floors 1-15.
2. Building vs Shooting balance in tight rooms.
3. Co-op couch feel.

Thank you!"""
    },
    "twitter_x": {
        "name": "Twitter / X",
        "category": "Social Media",
        "best_time": "19:00 - 23:00 (UTC+8)",
        "utm_source": "twitter",
        "utm_medium": "social",
        "utm_campaign": "launch_tweet",
        "submit_url": "https://twitter.com/intent/tweet?text={body}",
        "title": "Tank Battle Launch Tweet",
        "body": """I reimagined classic Battle City with a Slay-the-Spire branching campaign, RPG upgrades, and in-battle structure building! 💥

🛡️ 8 Acts × 15 Floors
👥 Local 2-Player Co-op
🔊 All audio synthesized in code! (Zero sound files)

Play FREE in your browser on @itchio 👇
🔗 {link}

#GodotEngine #gamedev #indiegame #itchio #pixelart @godotengine"""
    },
    "discord": {
        "name": "Discord Showcase",
        "category": "Communities",
        "best_time": "Anytime",
        "utm_source": "discord",
        "utm_medium": "showcase",
        "utm_campaign": "launch_showcase",
        "submit_url": "https://discord.com/channels/@me",
        "title": "Discord Showcase Post",
        "body": """**Tank Battle (Battle City × Slay-the-Spire Roguelite)**
A modern reimagining of classic Tank 1990 made with Godot 4.5!

✨ **Features**:
• Slay-the-Spire style branching campaign across 3 biomes (8 acts × 15 floors)
• Tactical structure building mid-battle (turrets, conduits, walls)
• Local 2-player co-op with gamepad & split-keyboard
• 100% procedural runtime audio synthesis (zero sound files!)
• Headless Blender automated asset pipeline

🌐 **Play free in browser**: <{link}>"""
    },
    "itch_devlog": {
        "name": "itch.io Devlog #1",
        "category": "Platform SEO",
        "best_time": "Anytime",
        "utm_source": "itch",
        "utm_medium": "devlog",
        "utm_campaign": "devlog_01",
        "submit_url": "https://itch.io/dashboard",
        "title": "Devlog #1: How We Built Tank Battle with Zero Audio Files & Automated 3D Renders",
        "body": """Welcome to the first devlog for **Tank Battle**!

### 🔊 Why There Are Zero Audio Files in the Game
To keep the web export light, instant-loading, and free from asset licensing friction, every single sound effect—from tank engines, bullet ricochets, and heavy cannon explosions to laser hums—is synthesized in real-time in pure GDScript using Godot's `AudioStreamGenerator`.

This allowed us to dynamically alter sound pitch, frequency modulation, and decay based on bullet velocity and armor thickness during intense combat.

### 🎨 Sokpop-Inspired Claymation Pipeline
All tanks, biomes (Plains, Desert, Glacial), and destructible terrain were procedurally modeled in Blender and rendered into isometric sprite sheets through a fully headless Python/Cycles pipeline, achieving a tactile claymation visual style.

### 🚀 Try It Now
We are actively tuning weapon balance, boss attack patterns, and co-op revive mechanics. Jump in, climb the Spire, and let us know what tank builds you discover!

Play free: {link}"""
    },
    "godot_showcase": {
        "name": "Godot Official Showcase",
        "category": "Engine Showcase",
        "best_time": "Permanent",
        "utm_source": "godot_showcase",
        "utm_medium": "showcase",
        "utm_campaign": "official_showcase",
        "submit_url": "https://godotengine.org/showcase/",
        "title": "Tank Battle - Godot Showcase Submission",
        "body": "{link}"
    },
    "bilibili_cn": {
        "name": "Bilibili / 国内社区",
        "category": "Domestic CN",
        "best_time": "12:00-13:00 / 18:00-21:00",
        "utm_source": "bilibili",
        "utm_medium": "video_desc",
        "utm_campaign": "cn_launch",
        "submit_url": "https://member.bilibili.com/platform/upload/video/frame",
        "title": "【Godot4独立游戏】我把童年《坦克大战》做成了爬塔肉鸽+双人建造！",
        "body": """耗时数月，用 Godot 4 重制的《坦克大战: 尖塔战役》终于发布啦！
结合了《杀戮尖塔》式的分支爬塔地图、战中建造防御工事、坦克 RPG 养成和双人同屏合作！

🛠️ 技术亮点：
- 零音频文件：全部音效代码实时程序化合成！
- 资产全自动化 Blender 渲染管线
- 网页版点开直接玩（支持免安装）

🎮 网页试玩与 Windows 下载：
{link}

欢迎大家在评论区提出手感和数值平衡建议！"""
    },
    "tieba_cn": {
        "name": "百度贴吧 (godot/独立游戏吧)",
        "category": "Domestic CN",
        "best_time": "18:00 - 22:00",
        "utm_source": "tieba",
        "utm_medium": "post",
        "utm_campaign": "cn_tieba_launch",
        "submit_url": "https://tieba.baidu.com/f?kw=godot",
        "title": "【自制独立游戏】童年红白机《坦克大战》重制版：爬塔肉鸽 + 战中造塔防工事！",
        "body": """吧友们好！用 Godot 4 独立开发了一款重制版坦克大战。

主要特色：
1. 爬塔地图机制：15 层关卡，精英怪、商店、随机事件、Boss战
2. 即时建造：战斗中可以随时放水泥墙、机枪炮塔、减速电网
3. 纯代码程序化音频：游戏内 0 个音频文件，全靠 GDScript 合成
4. 双人同屏合作：支持双摇杆手柄与键盘分屏操作

在线网页即点即玩（免安装）：
{link}

欢迎大家试玩给点建议！"""
    },
    "hackernews": {
        "name": "Hacker News (Show HN)",
        "category": "Geek / Global",
        "best_time": "20:00 - 23:00 (UTC+8)",
        "utm_source": "hackernews",
        "utm_medium": "post",
        "utm_campaign": "show_hn",
        "submit_url": "https://news.ycombinator.com/submit",
        "title": "Show HN: Tank Battle – NES Battle City rebuilt with Slay the Spire roguelite & procedural audio",
        "body": """Hey HN,

I built Tank Battle ({link}), a modernization of the 1985 NES Battle City with roguelite room progression, real-time in-battle building, and local co-op.

Technical details:
- Engine: Godot 4
- Audio: 0 audio files. Every bullet sound, motor hum, and explosion is synthesized at runtime in GDScript via AudioStreamGenerator.
- Visuals: Procedural Blender Cycles pipeline rendering 240+ isometric animation frames headlessly.
- Tests: 67 headless integration tests covering map node connectivity, building collisions, and economy balance.

Plays directly in the browser via WebAssembly/WebGL. Feedback on engine audio synthesis and balance welcome!"""
    }
}


def get_tracked_url(channel_key):
    cfg = CHANNELS.get(channel_key)
    if not cfg:
        return BASE_URL
    params = {
        "utm_source": cfg["utm_source"],
        "utm_medium": cfg["utm_medium"],
        "utm_campaign": cfg["utm_campaign"]
    }
    return f"{BASE_URL}?{urllib.parse.urlencode(params)}"


def get_platform_submit_url(channel_key):
    cfg = CHANNELS.get(channel_key)
    if not cfg or not cfg.get("submit_url"):
        return ""
    link = get_tracked_url(channel_key)
    body = cfg["body"].format(link=link)
    title = cfg.get("title", "").format(link=link)
    
    encoded_title = urllib.parse.quote(title)
    encoded_body = urllib.parse.quote(body)
    encoded_link = urllib.parse.quote(link)
    return cfg["submit_url"].format(title=encoded_title, body=encoded_body, link=encoded_link)


def copy_to_clipboard(text):
    try:
        if sys.platform == "win32":
            p = subprocess.Popen(["clip"], stdin=subprocess.PIPE, shell=True)
            p.communicate(text.encode("utf-8"))
            return True
        elif sys.platform == "darwin":
            p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
            p.communicate(text.encode("utf-8"))
            return True
        else:
            p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE)
            p.communicate(text.encode("utf-8"))
            return True
    except Exception as e:
        print(f"  [WARN] Clipboard copy failed: {e}")
    return False


def load_metrics():
    if os.path.exists(METRICS_FILE):
        try:
            with open(METRICS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_metrics(metrics):
    os.makedirs(os.path.dirname(METRICS_FILE), exist_ok=True)
    with open(METRICS_FILE, "w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)


def log_activity(channel, url="", notes=""):
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    entry = {
        "timestamp": datetime.now().isoformat(),
        "channel": channel,
        "channel_name": CHANNELS.get(channel, {}).get("name", channel),
        "tracked_link": get_tracked_url(channel) if channel in CHANNELS else "",
        "post_url": url,
        "notes": notes
    }
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def update_channel_metric(channel_key, post_url=None, upvotes=None, comments=None, views=None, notes=None, status=None):
    metrics = load_metrics()
    if channel_key not in metrics:
        metrics[channel_key] = {
            "name": CHANNELS.get(channel_key, {}).get("name", channel_key),
            "status": "pending",
            "post_url": "",
            "upvotes": 0,
            "comments": 0,
            "views": 0,
            "notes": "",
            "created_at": datetime.now().isoformat(),
            "last_updated": datetime.now().isoformat()
        }
    m = metrics[channel_key]
    if status is not None:
        m["status"] = status
    elif m["status"] == "pending":
        m["status"] = "posted"
    if post_url:
        m["post_url"] = post_url
    if upvotes is not None:
        m["upvotes"] = int(upvotes)
    if comments is not None:
        m["comments"] = int(comments)
    if views is not None:
        m["views"] = int(views)
    if notes is not None:
        m["notes"] = notes
    m["last_updated"] = datetime.now().isoformat()

    save_metrics(metrics)
    log_activity(channel_key, url=m.get("post_url", ""), notes=f"Metrics updated: Upvotes={m.get('upvotes',0)}, Comments={m.get('comments',0)}, Views={m.get('views',0)} | {m.get('notes','')}")
    print(f"✅ 成功更新渠道 [{channel_key}] 数据指标！已同步保存至 logs/marketing_metrics.json 与日志流。")


def list_channels():
    metrics = load_metrics()
    print("\n" + "=" * 92)
    print(" 🎯 TANK BATTLE — 推广渠道矩阵与直达发帖地址")
    print("=" * 92)
    for key, c in CHANNELS.items():
        submit_url = get_platform_submit_url(key)
        tracked_url = get_tracked_url(key)
        print(f"\n📌 [{key}]  {c['name']}  ({c['category']})")
        print(f"   🌐 平台发帖页面直达: {submit_url if submit_url else 'N/A'}")
        print(f"   🔗 嵌入正文追踪链接: {tracked_url}")
    print("\n" + "=" * 92 + "\n")


def show_post(channel_key, do_copy=False, do_open=False, do_log=False):
    if channel_key not in CHANNELS:
        print(f"❌ 未知渠道: {channel_key}。可用渠道: {', '.join(CHANNELS.keys())}")
        return

    c = CHANNELS[channel_key]
    link = get_tracked_url(channel_key)
    body = c["body"].format(link=link)
    title = c.get("title", "").format(link=link)
    submit_url = get_platform_submit_url(channel_key)

    print("\n" + "=" * 80)
    print(f" 📢 平台: {c['name']}  [Key: {channel_key}]")
    print(f" 🌐 平台发帖直达: {submit_url}")
    print(f" 🔗 帖内带参链接: {link}")
    print("=" * 80)
    if title:
        print(f"📝 [Title / 帖子标题]:\n{title}\n")
    print(f"📄 [Post Body / 正文内容]:\n{body}")
    print("=" * 80)

    if do_copy:
        full_clip = f"{title}\n\n{body}" if title else body
        if copy_to_clipboard(full_clip):
            print("✅ 已将完整文案复制到系统剪贴板 (Ctrl+V 可直接粘贴)！")

    if do_open and submit_url:
        print(f"🌐 正在使用系统默认浏览器打开平台发帖页...")
        webbrowser.open(submit_url)

    if do_log:
        update_channel_metric(channel_key, status="posted")


def render_dashboard():
    metrics = load_metrics()
    print("\n" + "╔" + "═" * 96 + "╗")
    print("║" + " 📊 TANK BATTLE — 全渠道推广效果与流量大盘仪表盘".center(84) + "║")
    print("╠" + "═" * 96 + "╣")
    
    total_posts = 0
    total_upvotes = 0
    total_comments = 0
    total_views = 0

    print(f"║ {'渠道 Key':<18} │ {'平台名称':<24} │ {'状态':<8} │ {'点赞':>6} │ {'评论':>6} │ {'曝光':>8} │ {'最后更新':<10} ║")
    print("╟" + "─" * 96 + "╢")

    for key, c in CHANNELS.items():
        m = metrics.get(key, {})
        status = m.get("status", "待发布")
        if status == "posted":
            status_display = "🟢已发帖"
            total_posts += 1
        elif status == "active":
            status_display = "🔥活跃中"
            total_posts += 1
        else:
            status_display = "⚪待发帖"

        upvotes = m.get("upvotes", 0)
        comments = m.get("comments", 0)
        views = m.get("views", 0)
        dt = m.get("last_updated", "")[:10] if m.get("last_updated") else "-"

        total_upvotes += upvotes
        total_comments += comments
        total_views += views

        print(f"║ {key:<18} │ {c['name']:<22} │ {status_display:<6} │ {upvotes:>6} │ {comments:>6} │ {views:>8} │ {dt:<10} ║")

    print("╠" + "═" * 96 + "╣")
    print(f"║ 汇总数据: 已发帖渠道: {total_posts}/{len(CHANNELS)}  |  累计点赞: {total_upvotes}  |  累计评论互动: {total_comments}  |  预估曝光量: {total_views}".ljust(96) + "║")
    print("╚" + "═" * 96 + "╝\n")

    feedback_entries = []
    for key, m in metrics.items():
        if m.get("notes"):
            feedback_entries.append((m.get("name", key), m.get("notes"), m.get("post_url", "")))

    if feedback_entries:
        print("💬 玩家反馈与社区洞察记录:")
        for name, notes, purl in feedback_entries:
            print(f"  • [{name}]: {notes}")
            if purl:
                print(f"    🔗 帖子: {purl}")
        print()


def show_history():
    if not os.path.exists(LOG_FILE):
        print(f"ℹ️ 尚未记录任何推广活动日志 (文件尚未创建: {LOG_FILE})")
        return

    print("\n" + "=" * 80)
    print(" 📜 推广活动流水日志 (Activity Stream)")
    print("=" * 80)
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                dt = entry.get("timestamp", "")[:19].replace("T", " ")
                ch = entry.get("channel_name", entry.get("channel", "Unknown"))
                purl = entry.get("post_url", "")
                notes = entry.get("notes", "")
                print(f"#{i:02d} [{dt}]  {ch}")
                if purl:
                    print(f"     🔗 Post URL: {purl}")
                if notes:
                    print(f"     💬 Notes: {notes}")
                print("-" * 80)
            except Exception:
                continue


def generate_custom_utm(source, medium, campaign, content="", term=""):
    params = {
        "utm_source": source,
        "utm_medium": medium,
        "utm_campaign": campaign
    }
    if content:
        params["utm_content"] = content
    if term:
        params["utm_term"] = term
    url = f"{BASE_URL}?{urllib.parse.urlencode(params)}"
    print("\n" + "=" * 75)
    print(" 🎯 自定义 UTM 追踪链接已生成:")
    print(f" 👉 {url}")
    print("=" * 75)
    copy_to_clipboard(url)
    print("✅ 已自动复制到系统剪贴板！\n")
    return url


def check_itch_status():
    print("\n" + "=" * 70)
    print(" 🔍 itch.io 线上构建与渠道状态巡检")
    print("=" * 70)
    
    # 1. Check HTTP live page
    print("1. 正在检查 itch.io 页面在线状态...")
    try:
        req = urllib.request.Request(
            BASE_URL,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"   ✅ HTTP {resp.status} OK — 游戏主页在线正常 (URL: {BASE_URL})")
    except Exception as e:
        print(f"   ⚠️ 无法连接到 itch 页面: {e}")

    # 2. Check Butler CLI
    print("\n2. 正在检查 Butler 上传通道状态...")
    try:
        butler = os.path.expanduser("~/bin/butler/butler.exe")
        if not os.path.exists(butler):
            butler = "butler"
        res = subprocess.run(
            [butler, "status", "throwbananana/tank-battle"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        if res.returncode == 0:
            print(res.stdout if res.stdout else "   ✅ Butler 通道正常")
        else:
            output = res.stderr or res.stdout
            print(f"   ℹ️ Butler 状态响应:\n{output.strip()}")
    except Exception as e:
        print(f"   ℹ️ Butler CLI 未安装或未登录: {e}")

    print("=" * 70 + "\n")


def trigger_export():
    ps_script = os.path.join(PROJECT_ROOT, "tools", "export_itch.ps1")
    print(f"\n🚀 正在启动全自动导出与上传脚本: {ps_script}...")
    try:
        subprocess.run(["pwsh", ps_script], check=True)
    except Exception as e:
        print(f"❌ 运行 export_itch.ps1 出错: {e}")


def interactive_menu():
    while True:
        print("\n" + "╔" + "═" * 60 + "╗")
        print("║" + " 🎮 TANK BATTLE — 终端营销与推广全能管理中心".center(48) + "║")
        print("╠" + "═" * 60 + "╣")
        print("║  1. 🚀 一键推广发布 (选择渠道 -> 自动复制 -> 打开页面) ║")
        print("║  2. 📋 查看渠道列表与直达发帖地址总表                 ║")
        print("║  3. 📊 录入 / 更新推广数据 (点赞、评论、曝光、反馈)   ║")
        print("║  4. 📈 全渠道数据分析大盘 (Analytics Dashboard)        ║")
        print("║  5. ✍️ 自定义 UTM 追踪链接生成器                       ║")
        print("║  6. 📝 查看营销物料包与 Devlog #1                      ║")
        print("║  7. 🔍 itch.io 远程状态与 Butler 巡检                  ║")
        print("║  8. 📦 一键重新打包并部署到 itch.io (export_itch.ps1)  ║")
        print("║  9. 📜 查看历史活动流水日志 (Activity Stream)          ║")
        print("║  0. 退出 (Exit)                                        ║")
        print("╚" + "═" * 60 + "╝")
        
        choice = input("👉 请选择操作编号 [0-9]: ").strip()
        if choice == "0":
            print("👋 再见！祝推广顺利，大获好评！")
            break
        elif choice == "1":
            print("\n📌 可用渠道列表:")
            channel_keys = list(CHANNELS.keys())
            for idx, k in enumerate(channel_keys, 1):
                print(f"  [{idx:2d}] {k:<18} - {CHANNELS[k]['name']}")
            c_input = input("\n请输入渠道编号或 Key (直接回车取消): ").strip()
            if not c_input:
                continue
            selected_key = None
            if c_input.isdigit() and 1 <= int(c_input) <= len(channel_keys):
                selected_key = channel_keys[int(c_input) - 1]
            elif c_input in CHANNELS:
                selected_key = c_input
            
            if selected_key:
                show_post(selected_key, do_copy=True, do_open=True, do_log=True)
                p_url = input("\n🔗 是否现在录入已发帖的公开链接？(直接回车跳过): ").strip()
                if p_url:
                    update_channel_metric(selected_key, post_url=p_url, status="posted")
            else:
                print("❌ 输入无效。")
        elif choice == "2":
            list_channels()
        elif choice == "3":
            print("\n📊 录入/更新推广数据:")
            channel_keys = list(CHANNELS.keys())
            for idx, k in enumerate(channel_keys, 1):
                print(f"  [{idx:2d}] {k:<18} - {CHANNELS[k]['name']}")
            c_input = input("\n请选择渠道编号或 Key: ").strip()
            selected_key = None
            if c_input.isdigit() and 1 <= int(c_input) <= len(channel_keys):
                selected_key = channel_keys[int(c_input) - 1]
            elif c_input in CHANNELS:
                selected_key = c_input
            
            if selected_key:
                p_url = input("🔗 帖子公开链接 (留空保持原值): ").strip()
                up_str = input("👍 当前点赞数 Upvotes (留空跳过): ").strip()
                com_str = input("💬 当前评论数 Comments (留空跳过): ").strip()
                view_str = input("👀 预估曝光量 Views (留空跳过): ").strip()
                notes = input("📝 玩家反馈 / 关键建议 (留空跳过): ").strip()
                
                upvotes = int(up_str) if up_str.isdigit() else None
                comments = int(com_str) if com_str.isdigit() else None
                views = int(view_str) if view_str.isdigit() else None
                
                update_channel_metric(
                    selected_key,
                    post_url=p_url if p_url else None,
                    upvotes=upvotes,
                    comments=comments,
                    views=views,
                    notes=notes if notes else None,
                    status="active" if (upvotes or comments) else None
                )
            else:
                print("❌ 输入无效。")
        elif choice == "4":
            render_dashboard()
        elif choice == "5":
            print("\n✍️ 自定义 UTM 生成器:")
            src = input("1. 来源 utm_source (例如: bilibili, discord, tieba): ").strip()
            med = input("2. 媒介 utm_medium (例如: video, post, comment): ").strip()
            cmp = input("3. 活动 utm_campaign (例如: v1_launch, speedrun_event): ").strip()
            if src and med and cmp:
                generate_custom_utm(src, med, cmp)
            else:
                print("❌ source, medium, campaign 均为必填项。")
        elif choice == "6":
            if os.path.exists(DOCS_KIT):
                print(f"\n📖 完整营销物料套件已生成在: {DOCS_KIT}\n")
                show_post("itch_devlog")
            else:
                print("物料文档不存在。")
        elif choice == "7":
            check_itch_status()
        elif choice == "8":
            trigger_export()
        elif choice == "9":
            show_history()
        else:
            print("❌ 无效选项，请输入 0-9。")


def main():
    parser = argparse.ArgumentParser(description="Tank Battle — 终端营销与推广追踪管理系统")
    parser.add_argument("--interactive", "-i", action="store_true", help="启动交互式终端管理菜单 (推荐)")
    parser.add_argument("--list", "-l", action="store_true", help="列出所有推广渠道与其专属带参 UTM 链接")
    parser.add_argument("--channel", "-c", type=str, help="查看指定渠道的预设发帖文案 (如: reddit_godot, twitter_x, etc.)")
    parser.add_argument("--copy", action="store_true", help="配合 --channel: 将指定渠道的发帖文案直接复制到剪贴板")
    parser.add_argument("--open", "-o", action="store_true", help="配合 --channel: 在浏览器中直接打开该渠道的发帖页面")
    parser.add_argument("--dispatch", "-d", type=str, help="一键发布指定渠道: 打印文案 + 复制剪贴板 + 打开浏览器")
    parser.add_argument("--dashboard", action="store_true", help="展示全渠道推广效果与流量大盘仪表盘")
    parser.add_argument("--status", action="store_true", help="巡检 itch.io 远程构建与上传渠道状态")
    parser.add_argument("--update", "-u", type=str, help="更新指定渠道数据 (输入 channel key)")
    parser.add_argument("--upvotes", type=int, help="配合 --update: 更新点赞数")
    parser.add_argument("--comments", type=int, help="配合 --update: 更新评论数")
    parser.add_argument("--views", type=int, help="配合 --update: 更新曝光量")
    parser.add_argument("--url", type=str, help="配合 --update / --log: 帖子公开链接")
    parser.add_argument("--notes", type=str, help="配合 --update / --log: 备注信息与玩家反馈")
    parser.add_argument("--history", action="store_true", help="查看所有已记录的推广活动日志流水")
    parser.add_argument("--utm-gen", action="store_true", help="生成自定义 UTM 链接")
    parser.add_argument("--source", type=str, default="", help="UTM source")
    parser.add_argument("--medium", type=str, default="", help="UTM medium")
    parser.add_argument("--campaign", type=str, default="", help="UTM campaign")

    if len(sys.argv) == 1:
        interactive_menu()
        return

    args = parser.parse_args()

    if args.interactive:
        interactive_menu()
    elif args.list:
        list_channels()
    elif args.dashboard:
        render_dashboard()
    elif args.dispatch:
        show_post(args.dispatch, do_copy=True, do_open=True, do_log=True)
    elif args.channel:
        show_post(args.channel, do_copy=args.copy, do_open=args.open)
    elif args.update:
        update_channel_metric(
            args.update,
            post_url=args.url,
            upvotes=args.upvotes,
            comments=args.comments,
            views=args.views,
            notes=args.notes
        )
    elif args.status:
        check_itch_status()
    elif args.history:
        show_history()
    elif args.utm_gen:
        if args.source and args.medium and args.campaign:
            generate_custom_utm(args.source, args.medium, args.campaign)
        else:
            print("❌ 使用 --utm-gen 时需同时指定 --source, --medium, --campaign。")


if __name__ == "__main__":
    main()
