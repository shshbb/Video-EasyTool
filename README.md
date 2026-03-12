# Video Easy Tool

[English](./README.md) | [简体中文](./README.zh-CN.md)

A native macOS app for downloading YouTube videos, transcribing subtitles with local Whisper models, translating subtitles with OpenAI-compatible APIs or Ollama, and exporting bilingual subtitle files.

## Features

- Download YouTube videos with `yt-dlp`
- Transcribe local video files with local Whisper models
- Translate subtitles with:
  - OpenAI-compatible chat completion APIs
  - Ollama local models
- Export bilingual `.srt` subtitles
- Transcode local video files with `ffmpeg`
- Run download, transcription, translation, and transcoding independently

## Requirements

- macOS 14+
- Xcode Command Line Tools
- Homebrew

Install required tools:

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

If you want local subtitle translation, install and start Ollama:

```bash
brew install ollama
ollama serve
```

## Run

For most users, the recommended way to install Video Easy Tool is to download the packaged installer from [Releases](https://github.com/shshbb/Video-EasyTool/releases). Building and running from source is mainly intended for development, debugging, or contributing, and is not the recommended installation path for everyday use.

Development:

```bash
swift run
```

Release build:

```bash
swift build -c release
```

## Packaging

The app bundle name is `VideoEasyTool.app`.

Current packaged artifacts are written to:

- `dist/VideoEasyTool.app`
- `dist/VideoEasyTool.zip`

## Workflow

### 1. Download video

- Paste a YouTube URL
- Choose an output directory
- Download the source video locally

### 2. Transcribe subtitle

- Select a local video file
- Choose a Whisper model
- Download or verify the selected model
- Generate `*_original.srt`

### 3. Translate subtitle

- Select a local `.srt` file
- Choose a target language
- Choose a translation backend
- Generate `*_bilingual.srt`

### 4. Transcode video

- Select a local video file
- Choose output format and CRF
- Export a transcoded file

## Translation Backends

### OpenAI-compatible API

- Endpoint: `POST /v1/chat/completions`
- Auth: `Authorization: Bearer <API_KEY>`
- `base_url` supports both forms:
  - with `/v1`
  - without `/v1`

### Ollama

- Endpoint: `POST /api/chat`
- Uses chat `messages` payloads

## Data Storage

- Default output directories are stored inside the app data directory
- User-selected external directories are remembered
- Whisper models are stored in the app's internal model directory
- Runtime logs are shown in the app UI and are not committed to this repository

App data location:

```text
~/Library/Application Support/VideoEasyTool
```

## Project Structure

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

## Known Limitations

- Some malformed subtitle files may fail to parse
- Long subtitle translation quality still depends on model stability
- Required external tools must be installed locally before use

## License

This project is licensed under the GPL-3.0 license. See [LICENSE](LICENSE).
