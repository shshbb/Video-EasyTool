# Video Easy Tool

`Video Easy Tool` 是一个原生桌面应用，使用 SwiftUI 构建，面向 YouTube 视频下载、字幕转录、字幕翻译和基础转码场景。

## 功能

- 下载 YouTube 视频
- 使用本地 Whisper 模型转录字幕
- 生成双语字幕
- 支持 OpenAI 兼容接口翻译
- 支持 Ollama 本地模型翻译
- 支持独立执行下载、转录、翻译、转码

## 技术栈

- Swift 5.10
- SwiftUI
- Swift Package Manager
- `yt-dlp`
- `ffmpeg` / `ffprobe`
- `whisper-cli`
- Ollama 或 OpenAI 兼容翻译接口

## 系统要求

- macOS 14 或更高版本
- Xcode Command Line Tools

## 本地依赖

先安装下载和媒体处理依赖：

```bash
brew install yt-dlp ffmpeg
```

如果你要使用本地翻译，再安装并启动 Ollama：

```bash
brew install ollama
ollama serve
```

如果你要使用本地转录，需要安装 `whisper-cli`：

```bash
brew install whisper-cpp
```

## 运行

开发环境直接运行：

```bash
swift run
```

构建 release：

```bash
swift build -c release
```

## 使用说明

应用里的几个任务是分开的，可以单独执行。

### 下载视频

- 输入 YouTube 链接
- 选择输出目录
- 下载视频到本地

### 转录字幕

- 选择本地视频文件
- 选择 Whisper 模型
- 下载或检测模型
- 执行本地转录，生成 `*_original.srt`

### 翻译字幕

- 选择本地字幕文件
- 选择目标语言
- 选择翻译提供方
- OpenAI Compatible：填写 `base_url` 和 `api_key`
- Ollama：填写本地服务地址和模型名
- 执行翻译，生成 `*_bilingual.srt`

### 视频转码

- 选择本地视频
- 选择输出格式和 CRF
- 执行转码

## 接口兼容

### OpenAI Compatible

- 翻译接口：`POST /v1/chat/completions`
- 鉴权方式：`Authorization: Bearer <API_KEY>`
- `base_url` 支持填写带 `/v1` 或不带 `/v1` 的地址

### Ollama

- 翻译接口：`POST /api/chat`
- 使用 `messages` 格式请求

## 数据与输出

- 默认输出目录位于应用内部目录
- 用户手动选择的目录会被记住
- Whisper 模型下载到应用内部模型目录
- 任务日志显示在应用内，不写入仓库

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

- 某些异常字幕文件可能解析失败
- 长字幕翻译仍然依赖模型输出稳定性
- 本地工具缺失时需要先安装对应依赖

## License

GPL-3.0
