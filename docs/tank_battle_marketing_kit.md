# 🎮 Tank Battle (坦克大战: 尖塔战役) — 营销物料与全渠道推广套件

本文档汇集了 《Tank Battle》 全渠道宣发文案、Devlog 开发者日志、技术亮点、UTM 追踪策略及数据收集规范。您可以通过终端工具 `python tools/promo_manager.py` 一键管理和自动复制分发。

---

## 🔗 核心试玩与下载链接
- **Itch.io 官方主页**: https://throwbananana.itch.io/tank-battle
- **支持平台**: Web (HTML5 网页即点即玩无需安装) + Windows (原生桌面端免安装运行)

---

## 📋 渠道一览与 UTM 追踪配置

所有通过 `promo_manager.py` 分发的链接均已内置标准 UTM 参数，以便在 itch.io 分析后台精准识别流量来源：

| 渠道 Key | 平台名称 | 目标受众 | UTM 来源 (utm_source) | 推荐发帖时间 (北京时间) |
| :--- | :--- | :--- | :--- | :--- |
| `reddit_godot` | Reddit (r/godot) | Godot 开发者、技术极客 | `reddit` / `r_godot_launch` | 20:00 - 23:00 |
| `reddit_webgames` | Reddit (r/WebGames) | 网页游戏即点即玩玩家 | `reddit` / `r_webgames_launch` | 20:00 - 23:00 |
| `reddit_indiegames` | Reddit (r/indiegames) | 独立游戏爱好者、怀旧玩家 | `reddit` / `r_indiegames_launch` | 20:00 - 23:00 |
| `reddit_playmygame` | Reddit (r/playmygame) | 试玩反馈、游戏评测社区 | `reddit` / `r_playmygame_launch` | 20:00 - 23:00 |
| `twitter_x` | Twitter / X | 游戏开发圈、推特玩家 | `twitter` / `launch_tweet` | 19:00 - 23:00 |
| `discord` | Discord Showcase | 游戏开发与玩家社群 | `discord` / `launch_showcase` | 任何时段 |
| `itch_devlog` | Itch.io 站内 Devlog #1 | Itch 平台站内 SEO 与首页推荐 | `itch` / `devlog_01` | 随时更新 |
| `godot_showcase` | Godot 官方 Showcase | 全球 Godot 社区长期展示 | `godot_showcase` / `official_showcase` | 长期展位 |
| `bilibili_cn` | B站 / 抖音 / 小红书 | 国内独立游戏与二创玩家 | `bilibili` / `cn_launch` | 12:00 - 13:00 / 18:00 - 21:00 |
| `tieba_cn` | 百度贴吧 (godot/独立游戏吧) | 国内怀旧与独立开发者 | `tieba` / `cn_tieba_launch` | 18:00 - 22:00 |
| `hackernews` | Hacker News (Show HN) | 全球极客、程序员社区 | `hackernews` / `show_hn` | 20:00 - 23:00 |

---

## 📝 核心文案库 (Ready-to-Use Copy)

### 1. Reddit (r/godot)
- **Title**:
  ```text
  I spent months rebuilding Battle City in Godot 4 — added a Slay the Spire branching campaign, in-battle building, and synthesized all audio in GDScript (Free Web/Win)
  ```
- **Body**:
  ```markdown
  Hey everyone! 👋

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
  👉 https://throwbananana.itch.io/tank-battle?utm_source=reddit&utm_medium=community&utm_campaign=r_godot_launch

  I’d love to hear your feedback on the controls, balance, and build variety!
  ```

---

### 2. Reddit (r/WebGames)
- **Title**: `[HTML5] Tank Battle - Battle City reimagined as a Slay-the-Spire Roguelite with building and co-op`
- **Link**: `https://throwbananana.itch.io/tank-battle?utm_source=reddit&utm_medium=post&utm_campaign=r_webgames_launch`
- **Comment/Body**:
  ```text
  Play free in browser: https://throwbananana.itch.io/tank-battle?utm_source=reddit&utm_medium=post&utm_campaign=r_webgames_launch

  A roguelite reimaging of classic Tank 1990! Features 15-floor Spire campaign, in-battle tactical building, deep upgrades, and local 2P co-op!
  ```

---

### 3. Reddit (r/indiegames & r/playmygame)
- **Title**:
  ```text
  What if Battle City was a Roguelite? I made a game where you build defenses, level up your tank, and climb a 15-floor Spire with a friend. Free on browser!
  ```
- **Body**:
  ```markdown
  Remember playing *Battle City / Tank 1990* on the NES? 

  I decided to take that core arcade action and turn it into a full-fledged roguelite campaign:
  - Branching route selection on a 15-floor map per act
  - Mid-battle structure building (walls, turrets, EMP towers)
  - Deep tank upgrades in the workshop
  - Full 2-player local co-op support

  It's completely free to play right in your browser (no install needed) or as a standalone Windows build!

  🔗 **Play here**: https://throwbananana.itch.io/tank-battle?utm_source=reddit&utm_medium=post&utm_campaign=r_indiegames_launch

  Looking forward to your high scores and feedback!
  ```

---

### 4. Twitter / X
- **Text**:
  ```text
  I reimagined classic Battle City with a Slay-the-Spire branching campaign, RPG upgrades, and in-battle structure building! 💥

  🛡️ 8 Acts × 15 Floors
  👥 Local 2-Player Co-op
  🔊 All audio synthesized in code! (Zero sound files)

  Play FREE in your browser on @itchio 👇
  🔗 https://throwbananana.itch.io/tank-battle?utm_source=twitter&utm_medium=social&utm_campaign=launch_tweet

  #GodotEngine #gamedev #indiegame #itchio #pixelart @godotengine
  ```

---

### 5. itch.io Devlog #1
- **Title**: `Devlog #1: How We Built Tank Battle with Zero Audio Files & Automated 3D Renders`
- **Body**:
  ```markdown
  Welcome to the first devlog for **Tank Battle**!

  ### 🔊 Why There Are Zero Audio Files in the Game
  To keep the web export light, instant-loading, and free from asset licensing friction, every single sound effect—from tank engines, bullet ricochets, and heavy cannon explosions to laser hums—is synthesized in real-time in pure GDScript using Godot's `AudioStreamGenerator`.
  
  This allowed us to dynamically alter sound pitch, frequency modulation, and decay based on bullet velocity and armor thickness during intense combat.

  ### 🎨 Sokpop-Inspired Claymation Pipeline
  All tanks, biomes (Plains, Desert, Glacial), and destructible terrain were procedurally modeled in Blender and rendered into isometric sprite sheets through a fully headless Python/Cycles pipeline, achieving a tactile claymation visual style.

  ### 🚀 Try It Now
  We are actively tuning weapon balance, boss attack patterns, and co-op revive mechanics. Jump in, climb the Spire, and let us know what tank builds you discover!
  ```

---

### 6. 国内社区 (Bilibili / 贴吧 / 小红书)
- **标题**: `【Godot4开源独立游戏】我把童年《坦克大战》做成了爬塔肉鸽+双人建造！`
- **正文**:
  ```text
  耗时数月，用 Godot 4 重制的《坦克大战: 尖塔战役》终于发布啦！
  结合了《杀戮尖塔》式的分支爬塔地图、战中建造防御工事、坦克 RPG 养成和双人同屏合作！

  🛠️ 技术亮点：
  - 零音频文件：全部音效代码实时程序化合成！
  - 资产全自动化 Blender 渲染管线
  - 网页版点开直接玩（支持免安装）

  🎮 网页试玩与 Windows 下载：
  https://throwbananana.itch.io/tank-battle?utm_source=bilibili&utm_medium=video_desc&utm_campaign=cn_launch

  欢迎大家在评论区提出手感和数值平衡建议！
  ```

---

## 📊 终端推广与数据闭环管理

您只需在终端运行：
```powershell
python tools/promo_manager.py -i
```
即可进入交互式终端管理中心：
1. **一键分发**：选择平台自动复制文案并在默认浏览器中调出发帖页面；
2. **数据回传**：记录帖子链接、点赞量 (Upvotes)、评论数 (Comments)、浏览量与玩家反馈；
3. **数据大盘**：终端内以可视化表格实时展示各渠道推广进度与转化指标。
