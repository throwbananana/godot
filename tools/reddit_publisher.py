#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tank Battle — Reddit 官方 API 直发引擎 (reddit_publisher.py)
Uses official PRAW OAuth SDK to post directly and securely to Reddit communities
without browser automation blocks.
"""

import os
import sys
import json
import time
from datetime import datetime
import praw
from prawcore.exceptions import ResponseException, OAuthException

# Enforce UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CREDS_FILE = os.path.join(PROJECT_ROOT, "logs", "reddit_credentials.json")
METRICS_FILE = os.path.join(PROJECT_ROOT, "logs", "marketing_metrics.json")

sys.path.insert(0, os.path.dirname(__file__))
try:
    from promo_manager import CHANNELS, get_tracked_url, update_channel_metric
except ImportError:
    CHANNELS = {}


def log(msg, level="INFO"):
    prefix = {
        "INFO": "ℹ️ ",
        "SUCCESS": "✅ ",
        "WARN": "⚠️ ",
        "ERROR": "❌ ",
        "STEP": "🚀 "
    }.get(level, "")
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {prefix}{msg}", flush=True)


def load_credentials():
    if os.path.exists(CREDS_FILE):
        try:
            with open(CREDS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_credentials(creds):
    os.makedirs(os.path.dirname(CREDS_FILE), exist_ok=True)
    with open(CREDS_FILE, "w", encoding="utf-8") as f:
        json.dump(creds, f, ensure_ascii=False, indent=2)
    log(f"凭据已安全保存到本地: {CREDS_FILE}", "SUCCESS")


def init_reddit_client(creds):
    return praw.Reddit(
        client_id=creds["client_id"],
        client_secret=creds["client_secret"],
        username=creds["username"],
        password=creds["password"],
        user_agent=creds.get("user_agent", f"python:tank.battle.promo:v1.0 (by /u/{creds['username']})")
    )


def test_auth(reddit):
    try:
        user = reddit.user.me()
        if user:
            log(f"Reddit 身份认证成功！已登录账号: u/{user.name} (Karma: {user.link_karma + user.comment_karma})", "SUCCESS")
            return True
    except Exception as e:
        log(f"认证失败: {e}", "ERROR")
    return False


def post_channel(reddit, channel_key, subreddit_name, is_link=False):
    c = CHANNELS[channel_key]
    link = get_tracked_url(channel_key)
    title = c["title"].format(link=link)
    body = c["body"].format(link=link)

    log(f"正在发布到 r/{subreddit_name}...", "STEP")
    sub = reddit.subreddit(subreddit_name)

    try:
        if is_link:
            submission = sub.submit(title=title, url=link)
        else:
            submission = sub.submit(title=title, selftext=body)

        post_url = f"https://www.reddit.com{submission.permalink}"
        log(f"🎉 成功发布至 r/{subreddit_name}！", "SUCCESS")
        log(f"   🔗 帖子公开链接: {post_url}", "SUCCESS")

        update_channel_metric(channel_key, post_url=post_url, status="posted")
        return post_url
    except Exception as e:
        log(f"发布至 r/{subreddit_name} 失败: {e}", "ERROR")
        return None


def run_all(creds=None):
    if not creds:
        creds = load_credentials()

    if not creds or not creds.get("client_id") or not creds.get("username"):
        print("\n" + "=" * 70)
        print(" 🔑 请输入 Reddit 开发者 API 凭据 (可在 https://www.reddit.com/prefs/apps 创建)")
        print("=" * 70)
        client_id = input("1. Client ID (应用名称下方的那串字符): ").strip()
        client_secret = input("2. Client Secret: ").strip()
        username = input("3. Reddit 用户名: ").strip()
        password = input("4. Reddit 密码: ").strip()

        if not (client_id and client_secret and username and password):
            log("凭据不完整，取消执行。", "ERROR")
            return

        creds = {
            "client_id": client_id,
            "client_secret": client_secret,
            "username": username,
            "password": password,
            "user_agent": f"python:tank.battle.promo:v1.0 (by /u/{username})"
        }
        save_credentials(creds)

    log("正在通过 Reddit 官方 API 建立安全加密连接...", "STEP")
    reddit = init_reddit_client(creds)
    if not test_auth(reddit):
        return

    print("\n" + "=" * 70)
    print(" 🚀 开始全自动直发 Reddit 4 大核心板块")
    print("=" * 70)

    # 1. r/godot
    post_channel(reddit, "reddit_godot", "godot", is_link=False)
    time.sleep(3)

    # 2. r/WebGames
    post_channel(reddit, "reddit_webgames", "WebGames", is_link=True)
    time.sleep(3)

    # 3. r/indiegames
    post_channel(reddit, "reddit_indiegames", "indiegames", is_link=False)
    time.sleep(3)

    # 4. r/playmygame
    post_channel(reddit, "reddit_playmygame", "playmygame", is_link=False)
    time.sleep(3)

    log("🏆 Reddit 全渠道 API 自动发帖流水线全部完成！", "SUCCESS")


if __name__ == "__main__":
    if len(sys.argv) > 4:
        # CLI argument mode: client_id client_secret username password
        creds = {
            "client_id": sys.argv[1],
            "client_secret": sys.argv[2],
            "username": sys.argv[3],
            "password": sys.argv[4],
            "user_agent": f"python:tank.battle.promo:v1.0 (by /u/{sys.argv[3]})"
        }
        save_credentials(creds)
        run_all(creds)
    else:
        run_all()
