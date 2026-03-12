# Video Easy Tool

[English](./README.md) | [简体中文](./README.zh-CN.md)

`Video Easy Tool` 是一个原生 macOS 应用，用于下载 YouTube 视频、使用本地 Whisper 模型转录字幕、通过 OpenAI 兼容接口或 Ollama 翻译字幕，并导出双语字幕文件。

## 功能特性

- 使用 `yt-dlp` 下载 YouTube 视频
- 使用本地 Whisper 模型转录本地视频
- 使用以下方式翻译字幕：
  - OpenAI 兼容聊天补全接口
  - Ollama 本地模型
- 导出双语 `.srt` 字幕
- 使用 `ffmpeg` 转码本地视频
- 下载、转录、翻译、转码都可以独立执行

## 环境要求

- macOS 14 及以上
- Xcode Command Line Tools
- Homebrew

安装基础依赖：

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

如果你要使用本地字幕翻译，再安装并启动 Ollama：

```bash
brew install ollama
ollama serve
```

## 运行方式

开发环境运行：

```bash
swift run
```

构建 release：

```bash
swift build -c release
```

## 打包产物

应用 bundle 名称为 `VideoEasyTool.app`。

当前打包产物输出到：

- `dist/VideoEasyTool.app`
- `dist/VideoEasyTool.zip`

## 使用流程

### 1. 下载视频

- 粘贴 YouTube 链接
- 选择输出目录
- 下载源视频到本地

### 2. 转录字幕

- 选择本地视频文件
- 选择 Whisper 模型
- 下载或检测所选模型
- 生成 `*_original.srt`

### 3. 翻译字幕

- 选择本地 `.srt` 文件
- 选择目标语言
- 选择翻译后端
- 生成 `*_bilingual.srt`

### 4. 视频转码

- 选择本地视频文件
- 选择输出格式和 CRF
- 导出转码文件

## 翻译后端

### OpenAI 兼容接口

- 接口：`POST /v1/chat/completions`
- 鉴权：`Authorization: Bearer <API_KEY>`
- `base_url` 支持两种写法：
  - 带 `/v1`
  - 不带 `/v1`

### Ollama

- 接口：`POST /api/chat`
- 使用聊天 `messages` 请求格式

## 数据存储

- 默认输出目录位于应用内部数据目录
- 用户手动选择的外部目录会被记住
- Whisper 模型存放在应用内部模型目录
- 运行日志显示在应用界面内，不会提交到仓库

应用数据目录：

```text
~/Library/Application Support/VideoEasyTool
```

## 项目结构

```text
Sources/VideoEasyTool/
  Models/
  Services/
  Utils/
  ViewModels/
  Views/
assets/
scripts/
```

## 已知限制

- 某些损坏或格式异常的字幕文件可能无法解析
- 长字幕翻译质量仍然依赖模型输出稳定性
- 使用前需要先在本地安装所需外部工具

## 开源协议

本项目使用 GPL-3.0 协议，详见 [LICENSE](LICENSE)。
