# 人生重开模拟器

一款基于 Web 的文字人生模拟游戏。随机分配属性、挑选天赋、经历不同的人生事件，最终达成各种成就。

## 特性

- 🎲 **随机人生**：属性、天赋、事件随机组合，每次重开都是新体验
- 🏆 **成就系统**：收集各种成就，解锁隐藏内容
- 💾 **存档管理**：支持加密导出/导入存档，跨设备同步进度
- 🌗 **明暗主题**：支持亮色/暗色主题切换
- 🖥️ **桌面版**：基于 Tauri v2 构建的 Windows 桌面应用
- 📱 **响应式**：适配不同屏幕尺寸

## 技术栈

- **前端**：React 19 + TypeScript + Vite
- **状态管理**：Jotai
- **样式**：原生 CSS
- **桌面端**：Tauri v2
- **包管理**：pnpm workspaces (monorepo)
- **测试**：Vitest + Bun

## 项目结构

```
lifeRestart/
├── apps/
│   ├── web/              # Web 前端 (React + Vite)
│   │   └── src-tauri/    # Tauri 桌面端配置
│   └── console/          # 命令行版本
├── packages/
│   ├── core/             # 游戏核心逻辑
│   ├── data/             # 游戏数据（事件、天赋、成就等）
│   ├── hooks/            # React Hooks
│   ├── condition/        # 条件解析
│   └── vitex/            # Vite 扩展
└── thirdparty/           # 第三方依赖
```

## 快速开始

### 环境要求

- Node.js 18+
- pnpm
- Bun（可选，用于加速）

### 安装依赖

```bash
pnpm install
```

### 构建游戏数据

```bash
pnpm build:data
```

### 开发模式

```bash
# Web 版本
pnpm dev

# 桌面版本（需要 Rust 环境）
pnpm dev:desktop
```

### 构建生产版本

```bash
# Web 版本
pnpm build:web

# 桌面版本（Windows 免安装 exe）
pnpm build:desktop
# 或直接运行
build.bat
```

构建产物位于 `dist/` 目录。

## 兼容性

### Web 版本

- 现代浏览器（Chrome 100+、Firefox 100+、Safari 16+）

### 桌面版本

- Windows 10/11
- 支持旧版 WebView2 运行时（Chromium 100+）
- 内置 polyfill 兼容 `Map.groupBy`、`Object.groupBy`
- CSS 降级处理（`dvh/dvw` → `vh/vw`、`oklch(from ...)` → `filter: brightness()`、`color-mix()` fallback）

## 存档导入导出

支持通过密码加密的存档字符串进行跨设备同步：

1. 点击主页面的「导出」按钮
2. 输入密码，获取加密后的存档字符串
3. 在另一台设备上点击「导入」，粘贴字符串并输入相同密码

也可将存档保存为 `.txt` 文件进行备份。

## 开发命令

| 命令 | 说明 |
|------|------|
| `pnpm dev` | 启动 Web 开发服务器 |
| `pnpm dev:desktop` | 启动 Tauri 桌面开发 |
| `pnpm build:web` | 构建 Web 生产版本 |
| `pnpm build:desktop` | 构建桌面版 exe |
| `pnpm lint` | 代码检查 |
| `pnpm test` | 运行测试 |
| `pnpm test:core` | 仅测试核心逻辑 |

## 许可证

MIT
