# Video Easy Tool

[English](./README.md) | [简体中文](./README.zh-CN.md)

`Video Easy Tool` 是一个原生 macOS 应用，用于下载 YouTube 和哔哩哔哩视频、使用本地 Whisper 模型转录字幕、通过 OpenAI 兼容接口或 Ollama 翻译字幕，并导出双语字幕文件。

## 功能特性

- 使用 `yt-dlp` 下载 YouTube 和哔哩哔哩视频
- 使用本地 Whisper 模型转录本地视频
- 使用以下方式翻译字幕：
  - OpenAI 兼容聊天补全接口
  - Ollama 本地模型
- 导出双语 `.srt` 字幕
- 使用 `ffmpeg` 编辑本地视频，包括剪辑和转码
- 下载、转录、翻译、视频编辑都可以独立执行

## 环境要求

- macOS 14 及以上

## 运行方式

对于大多数用户，推荐直接从 [Releases](https://github.com/shshbb/Video-EasyTool/releases) 下载已经打包好的安装包。源码编译和运行更适合开发、调试或参与项目贡献，并不建议作为日常安装和使用方式。

安装包用户：

- 推荐直接从 [Releases](https://github.com/shshbb/Video-EasyTool/releases) 下载最新的 `.dmg`
- 应用本身面向 `macOS 14+`
- 当前提供的安装包仅支持 Apple Silicon（M 系列）Mac，不支持 Intel Mac
- 视频下载、视频编辑和本地转录仍然依赖目标机器上已安装的外部工具：
  - `yt-dlp`
  - `ffmpeg`
  - `whisper-cpp` 提供的 `whisper-cli`

如果你要使用 Ollama 作为本地翻译后端：

- 先安装 Ollama
- 确保 Ollama 后台服务正在运行
- 例如可以通过终端手动执行 `ollama serve`

如果你是从源码构建：

- 需要 Xcode Command Line Tools
- 需要 Homebrew

安装基础依赖：

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

如需使用 Ollama 翻译，可额外安装：

```bash
brew install ollama
```

开发环境运行：

```bash
swift run
```

构建 release：

```bash
swift build -c release
```

## 打包产物

推荐优先使用 `VideoEasyTool.dmg` 作为安装包。

当前打包产物输出到：

- `dist/VideoEasyTool.dmg`
- `dist/VideoEasyTool.app`
- `dist/VideoEasyTool.zip`

## 使用流程

### 1. 下载视频

- 粘贴 YouTube 或哔哩哔哩链接
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

### 4. 视频编辑

- 选择本地视频文件
- 如有需要，填写开始时间和结束时间进行剪辑
- 选择输出格式和 CRF
- 导出编辑后的视频文件

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
- 应用会根据主流模型家族自动选择工作模式：
  - 名称中包含 `qwen`、`llama`、`gemma`、`mistral`、`deepseek`、`gpt-oss` 等通用聊天家族关键字的模型，默认走批量 JSON 模式
  - 名称中包含 `translate`、`translator` 等翻译导向关键字的模型，默认走单条文本翻译模式
  - 名称中包含 `embed`、`embedding`、`bge`、`minilm`、`e5`、`mxbai-embed`、`nomic-embed` 等 embedding 关键字的模型，会被直接拦截，不允许用于字幕翻译
  - 名称中包含 `vision`、`vl`、`multimodal` 等视觉关键字的模型，在纯文本字幕翻译场景下仍默认走批量 JSON 模式
- 你仍然可以在应用里手动覆盖自动识别出来的工作模式

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
- 当前提供的安装包仅支持 Apple Silicon（M 系列）Mac
- 使用前需要先在本地安装所需外部工具

## 开源协议

本项目使用 GPL-3.0 协议，详见 [LICENSE](LICENSE)。
