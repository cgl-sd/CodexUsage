# CodexUsage

语言：[English](README.md) | **中文**

CodexUsage 是一个轻量级 macOS 菜单栏应用，用于查看本地 Codex token 使用情况。

<img src="docs/images/overview.png" alt="CodexUsage overview" width="420">

## 功能

- 菜单栏进度圆环，用于显示每日 token 目标完成度。
- 弹出面板显示：
  - 每日用量与可配置目标，
  - 当前可用的 Codex 配额窗口，
  - 本地账号计划信息。
- 每日用量会同时显示不含缓存的估算值，目标进度仍按含缓存总量计算。
- 当剩余配额低于或等于 20% 时使用警示颜色。
- 支持手动刷新，重新扫描本地 Codex 日志。
- 设置窗口可修改每日 token 目标。
- 支持在应用内检查 GitHub Releases 是否有新版本。
- 本地小型应用，无服务器组件。

## 数据来源

CodexUsage 只读取本地 Codex 文件，并且会根据当前 macOS 用户的 home 目录动态解析路径：

- 用量和限额事件：`$HOME/.codex/sessions/**/*.jsonl`
- 账号信息：`$HOME/.codex/auth.json`

每日 token 用量通过本地 `token_count` 事件中的 `last_token_usage.total_tokens` 汇总得到。配额百分比来自 Codex 写入本地事件里的当前可用 `rate_limits` 窗口。

应用不会写死账号 ID、用户名或绝对路径。换到另一台 Mac 或另一个系统用户时，它会读取那个用户自己的本地 Codex 数据目录。

本应用不会上传用量数据。

## 最近更新

- v0.1.5 优化了操作逻辑，并适用于 Codex 临时取消 5 小时额度限制、只显示当前可用配额窗口的情况。

## 安装

从 Release 页面下载 `CodexUsage.dmg`。

1. 打开 `CodexUsage.dmg`。
2. 将 `CodexUsage.app` 拖入 `Applications`。
3. 从 Applications 打开 `CodexUsage.app`。
4. 应用会出现在 macOS 菜单栏。

如果 macOS 提示无法验证开发者，请先尝试打开一次应用，然后进入 **System Settings（系统设置）** > **Privacy & Security（隐私与安全性）**，在安全性区域点击 `CodexUsage.app` 对应的 **Open Anyway（仍要打开）**，再在弹出的确认框里点击 **Open（打开）**。对于没有使用 Apple Developer ID 签名和公证的构建，这是正常情况。

在部分 macOS 版本中，右键点击 `CodexUsage.app` 并选择 **Open（打开）** 也可能直接出现同样的确认入口。

## 使用

- 点击菜单栏图标打开用量面板。
- 点击刷新图标重新扫描本地 Codex 日志。
- 点击设置图标修改每日目标。
- 默认每日目标是 `8000万 token`。

## 从源码构建

要求：

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift Package Manager

本地构建并运行：

```bash
./script/build_and_run.sh
```

创建本地可分发的 app、ZIP 和 DMG：

```bash
./script/package_app.sh
```

产物会输出到 `dist/`。

## 分发

默认打包脚本会创建 ad-hoc 签名的应用，适合本地测试或个人使用。

如果要公开发布并减少 Gatekeeper 警告，需要使用 Developer ID 证书和 Apple 公证：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="codexusage-notary" \
./script/package_app.sh
```

## 兼容性

当前包目标为 macOS 14 及更新版本。
