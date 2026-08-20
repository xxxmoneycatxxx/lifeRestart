# 构建指南

## 环境要求

| 依赖 | 版本 | 用途 |
|------|------|------|
| Node.js | 22+ | 前端构建 |
| pnpm | 最新 | 包管理 |
| Rust | stable | Tauri 后端编译 |
| JDK | 17+ | Android 构建（仅 APK） |
| Android SDK | API 36 | Android 构建（仅 APK） |
| Android NDK | 27.2 | Android 构建（仅 APK） |

构建脚本会自动检测并提示安装缺失的依赖（JDK / Android SDK / NDK）。

---

## 桌面端 — `build.ps1`

构建 Windows 桌面应用（Tauri），产物为免安装 exe。

```powershell
.\build.ps1
```

**产物**：`dist\liferestart-desktop.exe`

**流程**：
1. 构建游戏数据（xlsx → TS）
2. `tauri build --no-bundle`（前端 vite 构建 + Rust 编译）
3. 收集 exe 到 `dist\`

---

## Android — `build-apk.ps1`

构建 Android APK（Tauri），通过 `tauri android build` 统一处理前端构建、Rust 交叉编译和 Gradle 打包。

```powershell
.\build-apk.ps1 [-BuildMode debug|release] [-Arch arm64|arm|x86|x86_64|all] [-AutoConfirm]
```

### 参数

| 参数 | 别名 | 默认值 | 说明 |
|------|------|--------|------|
| `-BuildMode` | — | `release` | 构建模式：`debug` 或 `release` |
| `-Arch` | — | `arm64` | 目标架构：`arm64`、`arm`、`x86`、`x86_64`、`all` |
| `-AutoConfirm` | `-y` | — | 自动确认依赖安装，无需交互 |

参数顺序任意。

### 示例

```powershell
# 默认：release + arm64
.\build-apk.ps1

# 构建 debug 版 arm64 APK
.\build-apk.ps1 -BuildMode debug

# 构建所有架构的 release APK
.\build-apk.ps1 -Arch all

# 自动确认 + 快速构建
.\build-apk.ps1 -y -Arch arm64
```

### 产物

| 架构 | 文件名 |
|------|--------|
| arm64 | `dist\app-arm64-release.apk` |
| arm | `dist\app-arm-release.apk` |
| x86 | `dist\app-x86-release.apk` |
| x86_64 | `dist\app-x86_64-release.apk` |
| all | 以上全部（不含 universal） |

### 签名

首次构建时自动生成签名密钥（`signing\liferestart.keystore`）。**请妥善备份 `signing\` 目录**，丢失密钥将无法更新已发布的 APK。

---

## 开发模式

```powershell
# Web 热更新开发
pnpm dev

# Tauri 桌面端热更新开发
pnpm dev:desktop

# Android 热更新开发（需连接设备/模拟器）
pnpm --filter @remake/web exec tauri android dev
```
