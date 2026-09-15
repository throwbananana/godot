#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tank Battle — 全自动推广发帖机器人 (auto_publisher.py)
Directly opens each target platform, auto-injects Title, Markdown Body, UTM Links,
and triggers Post/Submit actions automatically.
"""

import os
import sys
import time
import json
import urllib.parse
from datetime import datetime
from playwright.sync_api import sync_playwright

# Enforce UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROFILE_DIR = os.path.join(PROJECT_ROOT, "logs", "chrome_automation_profile")
METRICS_FILE = os.path.join(PROJECT_ROOT, "logs", "marketing_metrics.json")
LOG_FILE = os.path.join(PROJECT_ROOT, "logs", "marketing_tracker.jsonl")

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


def auto_post_reddit(page, channel_key, subreddit, is_link=False):
    c = CHANNELS[channel_key]
    link = get_tracked_url(channel_key)
    title = c["title"].format(link=link)
    body = c["body"].format(link=link)
    submit_url = f"https://www.reddit.com/r/{subreddit}/submit"

    log(f"【r/{subreddit}】正在导航至发帖页面: {submit_url}...", "STEP")
    page.goto(submit_url, wait_until="domcontentloaded")
    time.sleep(3)

    if is_link:
        # Switch to Link tab
        try:
            for s in ['button:has-text("Link")', '[role="tab"]:has-text("Link")', 'button:has-text("URL")']:
                loc = page.locator(s).first
                if loc.is_visible(timeout=1500):
                    loc.click()
                    time.sleep(1)
                    break
        except Exception:
            pass

        # Fill Title
        for s in ['textarea[name="title"]', 'input[name="title"]', 'textarea[placeholder*="Title"]', 'input[placeholder*="Title"]']:
            try:
                loc = page.locator(s).first
                if loc.is_visible(timeout=1500):
                    loc.fill(title)
                    log(f"【r/{subreddit}】标题已自动填入", "SUCCESS")
                    break
            except Exception:
                continue

        # Fill URL
        for s in ['textarea[name="url"]', 'input[name="url"]', 'input[placeholder*="Url"]', 'input[placeholder*="URL"]', 'input[type="url"]']:
            try:
                loc = page.locator(s).first
                if loc.is_visible(timeout=1500):
                    loc.fill(link)
                    log(f"【r/{subreddit}】试玩落地页链接已自动填入", "SUCCESS")
                    break
            except Exception:
                continue
    else:
        # Fill Title
        for s in ['textarea[name="title"]', 'input[name="title"]', 'faceplate-textarea-input[name="title"] textarea', 'textarea[placeholder*="Title"]', 'input[placeholder*="Title"]', 'textarea']:
            try:
                loc = page.locator(s).first
                if loc.is_visible(timeout=1500):
                    loc.fill(title)
                    log(f"【r/{subreddit}】标题已自动填入", "SUCCESS")
                    break
            except Exception:
                continue

        # Switch to Markdown mode if available
        try:
            md_btn = page.locator('button:has-text("Markdown")').first
            if md_btn.is_visible(timeout=1500):
                md_btn.click()
                time.sleep(1)
        except Exception:
            pass

        # Fill Body
        for s in ['textarea[name="body"]', 'faceplate-textarea-input[name="body"] textarea', 'textarea[name="text"]', 'div[role="textbox"]', 'div[contenteditable="true"]', 'textarea[placeholder*="Text"]']:
            try:
                loc = page.locator(s).first
                if loc.is_visible(timeout=1500):
                    if "contenteditable" in s or "textbox" in s:
                        loc.click()
                        page.keyboard.insert_text(body)
                    else:
                        loc.fill(body)
                    log(f"【r/{subreddit}】正文内容已自动注入", "SUCCESS")
                    break
            except Exception:
                continue

    time.sleep(2)

    # Click Post button
    log(f"【r/{subreddit}】正在自动点击提交按钮...", "STEP")
    for s in ['button:has-text("Post")', 'button[type="submit"]:has-text("Post")', 'shreddit-post-submit-button button', 'button[type="submit"]', 'button:has-text("Submit")']:
        try:
            btn = page.locator(s).first
            if btn.is_visible(timeout=2000) and btn.is_enabled(timeout=2000):
                btn.click()
                log(f"【r/{subreddit}】已触发提交按钮点击！", "SUCCESS")
                break
        except Exception:
            continue

    time.sleep(4)
    update_channel_metric(channel_key, post_url=page.url, status="posted")


def auto_post_twitter(page):
    channel_key = "twitter_x"
    c = CHANNELS[channel_key]
    link = get_tracked_url(channel_key)
    body = c["body"].format(link=link)
    tweet_intent = f"https://twitter.com/intent/tweet?text={urllib.parse.quote(body)}"

    log("【Twitter/X】正在导航至发推创作台...", "STEP")
    page.goto(tweet_intent, wait_until="domcontentloaded")
    time.sleep(3)

    log("【Twitter/X】正在自动触发 Post 按钮...", "STEP")
    for s in ['button[data-testid="tweetButton"]', 'button[data-testid="tweetButtonInline"]', 'button:has-text("Post")', 'button:has-text("Tweet")', 'button:has-text("发帖")']:
        try:
            btn = page.locator(s).first
            if btn.is_visible(timeout=2500):
                btn.click()
                log("【Twitter/X】已自动触发发推！", "SUCCESS")
                break
        except Exception:
            continue

    time.sleep(3)
    update_channel_metric(channel_key, post_url=page.url, status="posted")


def main():
    print("\n" + "╔" + "═" * 70 + "╗")
    print("║" + " 🤖 TANK BATTLE — 全自动直接发布流水线".center(58) + "║")
    print("╠" + "═" * 70 + "╣")
    print("║  1. 自动导航各平台发帖入口                               ║")
    print("║  2. 自动填入 Title、Markdown 正文与专属带参 UTM 链接     ║")
    print("║  3. 自动触发各平台提交按钮 (Post / Submit)               ║")
    print("║  4. 自动持久化保存结果至本地数据大盘                     ║")
    print("╚" + "═" * 70 + "╝\n")

    os.makedirs(PROFILE_DIR, exist_ok=True)

    with sync_playwright() as p:
        log("启动自动化 Chrome 浏览器实例...", "STEP")
        context = p.chromium.launch_persistent_context(
            user_data_dir=PROFILE_DIR,
            channel="chrome",
            headless=False,
            viewport={"width": 1280, "height": 850},
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-default-browser-check"
            ]
        )

        try:
            # Tab 1: r/godot
            page1 = context.pages[0] if context.pages else context.new_page()
            auto_post_reddit(page1, "reddit_godot", "godot", is_link=False)
            time.sleep(2)

            # Tab 2: r/WebGames
            page2 = context.new_page()
            auto_post_reddit(page2, "reddit_webgames", "WebGames", is_link=True)
            time.sleep(2)

            # Tab 3: r/indiegames
            page3 = context.new_page()
            auto_post_reddit(page3, "reddit_indiegames", "indiegames", is_link=False)
            time.sleep(2)

            # Tab 4: r/playmygame
            page4 = context.new_page()
            auto_post_reddit(page4, "reddit_playmygame", "playmygame", is_link=False)
            time.sleep(2)

            # Tab 5: Twitter / X
            page5 = context.new_page()
            auto_post_twitter(page5)
            time.sleep(2)

            log("🏆 全自动发布流水线执行完毕！", "SUCCESS")
            log("所有发帖标签页已全部就绪并保持活动状态。", "INFO")

        except Exception as e:
            log(f"执行异常: {e}", "ERROR")

        # Keep browser open for viewing
        log("浏览器窗口保持打开，会话状态已持久化。", "INFO")
        time.sleep(10)


if __name__ == "__main__":
    main()
