# SmoothSnake

SmoothSnake 是一个使用 **Godot 4.7.2 + GDScript** 开发的连续平面贪吃蛇游戏，支持 Web、Windows 和 macOS。游戏资源由程序绘制或随仓库提供，不依赖外部美术与字体。

## 在线游玩

**[https://ppmark0712.github.io/SmoothSnake/](https://ppmark0712.github.io/SmoothSnake/)**

无需下载或安装，使用桌面浏览器打开即可游玩。

## 本地运行

### 环境要求

- Python 3
- Godot **4.7.2 stable**（必须与项目版本一致）
- 首次构建时可访问网络，用于下载约 20 MB 的 Web 导出模板

在仓库根目录执行：

```bash
python3 tools/web.py dev
```

脚本会完成以下工作：

1. 查找本机的 Godot 4.7.2。
2. 将 Web 导出模板下载到 `.tools/templates/`（仅首次执行）。
3. 导出游戏到 `build/web/`。
4. 在 <http://127.0.0.1:8060> 启动本地服务器。

使用 `Ctrl+C` 停止服务器。Web 版本必须通过 HTTP 访问，不能直接双击 `build/web/index.html`。

如果脚本没有找到 Godot，可显式指定可执行文件：

```bash
GODOT_BIN=/path/to/godot python3 tools/web.py dev
```

脚本会依次检查 `GODOT_BIN`、`.tools/godot`、`PATH` 中的 `godot` / `godot4`，以及 macOS 默认安装位置。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `python3 tools/web.py dev` | 重新构建并启动本地服务器 |
| `python3 tools/web.py build` | 仅构建 Web 版本，输出到 `build/web/` |
| `python3 tools/web.py serve` | 启动已有的 Web 构建，不重新导出 |
| `python3 tools/web.py serve --port 8080` | 使用指定端口启动已有构建 |
| `python3 tools/fetch_web_templates.py` | 仅下载或检查 Web 导出模板 |
| `python3 tools/desktop.py` | 构建 Windows 和 macOS Release 压缩包 |
| `python3 tools/desktop.py templates` | 仅下载或检查桌面导出模板 |
| `python3 tools/generate_audio.py` | 重新生成四类苹果的拾取音效 |

完成首次模板下载后，后续构建可以离线进行。

### 在 Godot 编辑器中运行

1. 使用 Godot 4.7.2 打开 `project.godot`。
2. 按 `F6` 运行当前场景，或按 `F5` 运行项目。
3. 如需从编辑器导出 Web 版本，先执行 `python3 tools/fetch_web_templates.py`，再选择 **Web** 导出预设。
4. 如需导出桌面版本，先执行 `python3 tools/desktop.py templates`，再选择 **Windows** 或 **macOS** 预设。

### 桌面 Release

执行以下命令会下载缺失的官方桌面模板，并同时生成两个发布压缩包：

```bash
python3 tools/desktop.py
```

输出文件：

- `build/releases/SmoothSnake-Windows-x86_64.zip`
- `build/releases/SmoothSnake-macOS-universal.zip`

macOS 包未使用项目开发者证书签名或公证，首次打开时可能需要在系统设置中手动允许。GitHub Pages 工作流仍只调用 `tools/web.py`，不会下载或构建桌面版本。

推送以 `v` 开头的版本标签会触发 `.github/workflows/release.yml`，自动构建桌面包、创建同名 GitHub Release，并上传两个 ZIP 和 `SHA256SUMS`：

```bash
git push origin main
git tag v1.0.0
git push origin v1.0.0
```

## 操作

| 操作 | 按键或入口 |
| --- | --- |
| 开始 | `Enter` 或 **Let's play** |
| 左右转向 | `←` / `→` |
| 暂停或继续 | `Esc`，或 **Pause / Resume** |
| 重新开始 | `R`，或结束后的 **Play again** |
| 切换难度 | 菜单中的 **Easy / Medium / Hard** |
| 开关音效 | 左下角 **Sound on / off** |
| 碰撞调试层 | `D` |

蛇会持续向前移动。不同苹果提供分数、加速或苹果雨效果；炸弹按所选难度生成并在倒计时结束后爆炸。撞墙或撞到自身时，正面碰撞会结束游戏，较小角度的擦碰会自动修正为沿边界滑行。

## 仓库构成

```text
SmoothSnake/
├── scenes/
│   └── main.tscn               # 游戏主场景
├── scripts/
│   ├── snake_model.gd          # 移动、增长、碰撞、苹果与炸弹等核心模型
│   └── game.gd                 # 输入、绘制、菜单、音效与本地记录
├── assets/audio/               # 四类苹果的拾取音效
├── web/
│   └── shell.html              # Web 页面外壳、加载进度与错误反馈
├── tools/
│   ├── web.py                  # Web 构建与本地服务器入口
│   ├── desktop.py              # Windows/macOS 模板、构建与打包入口
│   ├── fetch_web_templates.py  # 按需下载 Godot Web 导出模板
│   ├── generate_audio.py       # 程序化生成拾取音效
│   └── browser_smoke.cjs       # 浏览器端冒烟测试
├── tests/
│   └── run.gd                  # 无插件的玩法与菜单回归测试
├── .github/workflows/
│   ├── pages.yml               # 测试、构建及 GitHub Pages 部署
│   └── release.yml             # 标签触发的桌面构建与 Release 发布
├── project.godot               # Godot 项目配置与主场景入口
├── export_presets.cfg          # Web、Windows 与 macOS 导出配置
├── plan.md                     # 原始玩法与设计需求
└── LICENSE                     # MIT License
```

核心职责分为两层：

- `scripts/snake_model.gd` 保存与界面无关的确定性游戏状态和规则，可由测试直接驱动。
- `scripts/game.gd` 负责把模型连接到 Godot 场景，包括输入、渲染、菜单、音频和浏览器本地存储。

以下目录由工具生成且不会提交到 Git：

| 目录 | 内容 |
| --- | --- |
| `.godot/` | Godot 导入缓存与编辑器状态 |
| `.tools/` | 本地 Godot、导出模板及浏览器测试依赖 |
| `build/web/` | 可部署的 Web 构建产物 |
| `build/releases/` | Windows 与 macOS Release 压缩包 |
| `artifacts/` | 浏览器测试截图与结果 |

## 测试

运行 GDScript 回归测试：

```bash
godot --headless --path . --import
godot --headless --path . --script tests/run.gd
```

测试覆盖移动与转向、成长曲线、苹果效果、炸弹生成与爆炸、碰撞边界、暂停、重玩及菜单状态。

可选的浏览器冒烟测试需要 Node.js 和 Playwright。先构建并启动本地服务器，再执行：

```bash
npm install --prefix .tools/browser playwright
PLAYWRIGHT_BROWSERS_PATH="$PWD/.tools/ms-playwright" \
  .tools/browser/node_modules/.bin/playwright install chromium-headless-shell
PLAYWRIGHT_BROWSERS_PATH="$PWD/.tools/ms-playwright" \
  node tools/browser_smoke.cjs
```

也可以通过 `CHROME_BIN` 使用本机已有的 Chrome。测试结果写入 `artifacts/`。

## GitHub Pages

仓库通过 `.github/workflows/pages.yml` 自动测试、构建和部署：

1. 在仓库 **Settings → Pages → Build and deployment** 中将 **Source** 设为 **GitHub Actions**。
2. 推送到 `main` 或 `master`，或手动运行 **Build and deploy Web game**。
3. 从部署任务中打开生成的 Pages 地址。

Pull Request 只运行测试和构建，并上传 `smoothsnake-web` 构建产物，不执行部署。Web 导出使用 Compatibility / WebGL 2 和单线程 WebAssembly，无需配置 COOP/COEP 响应头。

## License

本项目使用 [MIT License](LICENSE)。
