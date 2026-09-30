# SmoothSnake

Godot **4.7.2 + GDScript** 连续平面贪吃蛇。浅黄色画板、圆球组成的小蛇、程序绘制的像素苹果和炸弹，无外部美术或字体依赖。发布目标为电脑浏览器，游戏内使用英文短标签。

## 本地试玩

已生成的网页包可直接启动：

```bash
python3 tools/web.py serve
```

访问 **http://127.0.0.1:8060**。不要双击 `index.html`，浏览器需要通过 HTTP 加载 WebAssembly。

修改代码后，重新导出并启动：

```bash
python3 tools/web.py dev
```

脚本自动寻找 Godot 4.7.2，并从官方发行包下载两个 Web 导出模板到 `.tools/templates/`。只下载约 20 MB 的 Web 模板，不下载完整的跨平台模板包。需要 Python 3 和首次下载时的网络访问；安装好模板后可离线构建。

如未找到 Godot，可指定路径：

```bash
GODOT_BIN=/path/to/godot python3 tools/web.py dev
```

`python3 tools/web.py build` 仅构建，输出到 `build/web/`；`serve --port 8080` 可更改端口。也可以在 Godot 编辑器中打开 `project.godot`，按 F6/F5 调试，使用 **Web** 预设导出。编辑器导出前先运行 `python3 tools/fetch_web_templates.py`。

## 操作与规则

| 操作 | 按键 |
| --- | --- |
| 开始 | Enter 或点击 Let's play |
| 向左 / 向右转 | ← / →，也支持 A / D |
| 暂停 / 继续 | Esc，或 Pause / Resume 按钮 |
| 重新开始 | 菜单内 Restart run；结束后 Play again；暂停或结束时按 R |
| 音效开关 | 左下角 Sound on / off |

蛇持续前进。红苹果 +1；金苹果 +5，并使当前速度翻倍 10 秒；彩色苹果 +10，20 秒内每 2 秒在空地额外生成一个苹果，共 10 个。

- 同类增益再次拾取时刷新持续时间，不叠加倍率。彩色苹果同时重置两秒生成节奏；金色与彩色效果可以共存。
- 普通补给维持至少 5 个苹果，额外苹果不会立即消失。随机种类概率为红 72%、金 18%、彩色 10%。
- 每 10 秒尝试生成一个炸弹，完整倒计时 5 秒后爆炸。虚线圈表示 108 像素爆炸半径；爆炸瞬间蛇头中心在圈内（含边界）即死亡，只有身体进入不会死亡。
- 撞击墙或自身时，以蛇头的**入射方向**与接触面**向内法向**的夹角判定：≤45° 死亡；>45° 沿切线滑行，并纠正重叠。实现中使用障碍物向外法向 `n`，判定式为 `-direction.dot(n) ≥ cos(45°)`。
- 头附近的两节身体作为连接的颈部，不参与自身碰撞；后续身体圆球逐个检测。
- 暂停或切换到其他窗口时，移动、炸弹、增益和补给全部暂停。重玩清空本局状态。
- 最高分与音效偏好保存在浏览器本地存储；清理站点数据会重置。
- 空地不足时跳过本次生成，普通补给每 0.5 秒重试，不会卡死或强行生成在蛇身上。

## 增长设计

记分数为 `s`，身体圆半径、圆球边缘的参考间距为：

```text
r(s) = 11 + 6 × (√(1 + s / 10) − 1)
g(s) = 8 / (1 + s / 35)
头半径 = 1.24 × r(s)
```

开局身体两节，前 5 分严格为 `2+s` 节。蛇头中心到蛇尾中心的路径长度：

```text
0 ≤ s ≤ 5:
L(s) = 2.24 × r(s) + g(s) + (s + 1) × (2 × r(s) + g(s))

s > 5:
L(s) = L(5) + 620 × (√(1 + (s − 5) / 10) − 1)

基础速度 = 156 + 65 × (√(1 + s / 15) − 1) 像素/秒
转向速度 = 2.65 弧度/秒
```

5 分以后按目标长度选择身体节数，再沿历史轨迹均匀采样圆心。长度、宽度严格递增，后续增长逐渐放缓；参考间距逐渐缩小，让身体更紧密。5→15 分时，长度约翻倍、半径增大约 20%，不会出现吃十个苹果仍看不出变化的情况。

模拟使用 120 Hz 固定步长，每次移动进一步拆为不超过 3 像素的小步，避免加速时穿墙或穿过身体。

## GitHub Pages

仓库内已提供 `.github/workflows/pages.yml`：

1. 将本项目推送到 GitHub 仓库的 `main` 或 `master` 分支。
2. 在仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。
3. 推送代码，或在 Actions 中手动运行 **Build and deploy Web game**。
4. 工作流安装 Godot 4.7.2、运行玩法测试、导出并部署。访问部署任务显示的 Pages 地址。

PR 只测试与构建，并提供可下载的 `smoothsnake-web` 构建产物；不会部署。

网页导出使用 Compatibility / WebGL 2、**单线程 WebAssembly**，无需 COOP/COEP 响应头，兼容 GitHub Pages 的项目子路径。当前没有绑定远端仓库，也没有发布线上站点。

## 验证

无需插件的玩法与菜单回归：

```bash
godot --headless --path . --import
godot --headless --path . --script tests/run.gd
```

覆盖增长单调性与减速、连续转向、实际拾取、45° 碰撞边界、墙与自身擦碰、加速防穿透、增益刷新和到期、炸弹生成与爆炸边界、安全生成、暂停/继续/重玩、失焦自动暂停。

可选浏览器验收（先构建并启动本地服务器）：

```bash
npm install --prefix .tools/browser playwright
PLAYWRIGHT_BROWSERS_PATH="$PWD/.tools/ms-playwright" \
  .tools/browser/node_modules/.bin/playwright install chromium-headless-shell
PLAYWRIGHT_BROWSERS_PATH="$PWD/.tools/ms-playwright" \
  node tools/browser_smoke.cjs
```

也可通过 `CHROME_BIN` 指向已有 Chrome。测试真实加载、开始、吃苹果、暂停画面冻结、撞墙结束、重玩、转向与窗口缩放，截图和结果保存在 `artifacts/`。

## 文件结构

```text
scenes/main.tscn          主场景
scripts/snake_model.gd    可独立测试的移动、碰撞、增长与计时逻辑
scripts/game.gd           输入、绘图、菜单、音效与本地记录
web/shell.html           网页外壳、加载进度与错误反馈
tools/                  模板下载、构建、本地服务与浏览器检查
tests/run.gd            自动回归测试
export_presets.cfg      单线程 Web 导出配置
.github/workflows/      测试、构建、Pages 部署
plan.md                 原始需求
```
