# YTDMacApp

原生 macOS (SwiftUI) 应用骨架，支持:
- 下载 YouTube 视频 (`yt-dlp`)
- AI 转录字幕 (OpenAI 兼容 API)
- AI 翻译双语字幕
  - 在线: OpenAI 兼容格式 (`/v1/chat/completions`)
  - 本地: Ollama (`/api/chat`)

## 1. 环境准备

1. 安装 `yt-dlp` 和 `ffmpeg`:
   - `brew install yt-dlp ffmpeg`
2. 如果用本地翻译，安装并启动 Ollama:
   - `brew install ollama`
   - `ollama serve`
   - `ollama pull qwen2.5:7b`

## 2. 运行

```bash
swift run
```

## 3. 使用方式（每一步可独立执行）

1. 全局设置
   - 用 Finder 按钮选择输出目录
   - 配置 OpenAI 兼容 API 地址和 Key（用于转录）
   - 选择翻译引擎（OpenAI Compatible / Ollama）
   - 目标语言使用“语言名称”下拉框选择
2. 步骤 1：下载视频
   - 输入 YouTube URL
   - 点击“下载到输出目录”
3. 步骤 2：转录字幕
   - 可手动选择本地视频文件
   - 点击“仅执行转录”，生成 `*_original.srt`
4. 步骤 3：翻译字幕
   - 可手动选择本地 `.srt` 字幕
   - 点击“仅执行翻译并生成双语字幕”

输出文件:
- `*_original.srt`
- `*_bilingual.srt`

## 4. 接口兼容要求

### OpenAI 兼容
- 转录接口: `POST /v1/audio/transcriptions`
- 翻译接口: `POST /v1/chat/completions`
- 鉴权: `Authorization: Bearer <API_KEY>`

### Ollama
- 翻译接口: `POST /api/chat`
- 请求体使用 `messages`，`stream=false`

## 5. 已知限制

- 当前版本会把视频文件直接上传做转录，超大视频会比较慢。
- 翻译采用批量编号行解析，如果模型返回格式不稳定会报条数不一致。
- 某些异常 SRT（格式损坏）可能解析失败。
