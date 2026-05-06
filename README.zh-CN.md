# Computer Use CLI

[English](README.md) | 简体中文

[![Version](https://img.shields.io/github/v/release/jianliang00/computer-use-cli?sort=semver&label=version)](https://github.com/jianliang00/computer-use-cli/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/jianliang00/computer-use-cli/release.yml?label=build)](https://github.com/jianliang00/computer-use-cli/actions/workflows/release.yml)
![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple)
![Architecture](https://img.shields.io/badge/architecture-Apple%20silicon-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

从 Mac 终端自动化操作隔离的 macOS 虚拟机。

`computer-use` 可以创建临时 macOS 虚拟机，查看虚拟机中正在运行的 App，获取屏幕截图和辅助功能树，并发送点击、输入、快捷键、拖拽、滚动以及辅助功能动作等 UI 操作。

## 适用场景

当你需要以下能力时，可以使用这个项目：

- 在隔离的 macOS 虚拟机中操作 App，避免影响主桌面。
- 通过截图和辅助功能树查看 App 当前的 UI 状态。
- 从终端或上层自动化代理运行可重复的 UI 自动化命令。

## 环境要求

- Apple 芯片 Mac。
- macOS 15 或更新版本。
- 已准备好的 macOS 虚拟机镜像，默认使用 `ghcr.io/jianliang00/computer-use:v0.1.6`。
- 只有从源码构建时才需要 Swift 6。

虚拟机镜像需要预先为 computer-use 配置好，并授予辅助功能和屏幕录制权限。如果需要构建该镜像，请参考 [Guest Image](docs/guest-image.md)。

## 安装

从 GitHub Releases 页面下载 `computer-use-<version>-macos-arm64.pkg`。

手动安装：

1. 在 Finder 中打开 `.pkg` 文件。
2. 按照 macOS 安装程序提示完成安装。
3. 验证安装：

```bash
computer-use --help
```

命令行安装：

```bash
sudo installer -pkg computer-use-<version>-macos-arm64.pkg -target /
computer-use --help
```

安装后会得到：

```text
/usr/local/bin/computer-use
```

使用 `computer-use` 前，不需要额外安装其他命令行工具。

## 快速开始

创建并启动一台虚拟机：

```bash
computer-use machine create --name demo --image ghcr.io/jianliang00/computer-use:v0.1.6
computer-use machine start --machine demo
```

确认虚拟机已经准备好：

```bash
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
```

列出虚拟机中正在运行的 App，并获取 UI 状态：

```bash
computer-use apps list --machine demo
computer-use state get --machine demo --app TextEdit
computer-use state get --machine demo --app TextEdit --screenshot-output ./textedit.png
```

发送常见操作：

```bash
computer-use action click --machine demo --app TextEdit --x 120 --y 240
computer-use action type --machine demo --app TextEdit --text "hello"
computer-use action key --machine demo --app TextEdit --key cmd+a
```

`state get` 会返回 `snapshot_id`、元素 ID 和元素索引。可以用
`--screenshot-output` 将截图 base64 解码成 PNG 文件；需要定位到具体元素时，
可以使用元素索引：

```bash
computer-use action click --machine demo \
  --app TextEdit \
  --element-index <element-index>
```

## 常用命令

管理虚拟机：

```bash
computer-use machine list
computer-use machine inspect --machine demo
computer-use machine logs --machine demo
computer-use machine stop --machine demo
computer-use machine rm --machine demo
```

检查虚拟机状态：

```bash
computer-use agent ping --machine demo
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
```

运行 UI 操作：

```bash
computer-use action drag --machine demo --app TextEdit --from-x 100 --from-y 100 --to-x 400 --to-y 300
computer-use action scroll --machine demo --app TextEdit --element-index <element-index> --direction down --pages 0.5
computer-use action set-value --machine demo --app TextEdit --element-index <element-index> --value "new value"
computer-use action action --machine demo --app TextEdit --element-index <element-index> --name AXPress
```

## 应该下载哪个发布文件？

- `computer-use-<version>-macos-arm64.pkg`：安装到你的 Mac。
- `computer-use-guest-kit-<version>-macos-arm64.pkg`：仅在构建或修复 macOS 虚拟机镜像时使用。
- `*.tar.gz`：原始安装内容归档，适合高级打包流程。

普通用户不需要在每台虚拟机中安装 `guest kit`。直接使用已经准备好并授权的镜像即可。

## 从源码构建

```bash
swift build
swift test
swift run computer-use --help
```

## 文档

- [Usage](docs/usage.md)：命令参考和常规工作流。
- [Guest Image](docs/guest-image.md)：构建可用于 computer-use 的 macOS 虚拟机镜像。
- [Releasing](docs/releasing.md)：签名和公证后的 release 包。
- [Development](docs/development.md)：本地开发与验证。
- [Architecture](docs/architecture.md)：技术设计。
