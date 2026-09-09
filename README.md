# FrameCut

FrameCut 是一个原生 macOS 视频切割工具。它可以打开或拖入本地视频，按真实视频帧和关键帧定位，设置包含式入点/出点，并把所选片段保存为 MP4 或 MOV。

## 主要功能

- 使用 AVFoundation 本地读取和导出，不上传视频。
- 扫描视频样本时间戳，显示真实帧数，并支持上一帧/下一帧。
- 识别同步样本，支持上一关键帧/下一关键帧。
- 缩略图时间线、播放头、可拖动的 I/O 手柄和高亮选区。
- 出点包含当前帧；导出范围自动延伸到下一帧边界。
- 导出前检查入点、出点、时长、帧数和格式，再通过 macOS 保存面板确认位置。
- 导出进度、取消、错误恢复，以及在 Finder 中显示结果。
- 智能压缩会结合源编码、分辨率、帧率和单位像素码率评估压缩空间，在保持原始画面尺寸的前提下用 HEVC 给出目标码率、预计体积和缩小比例。
- 多级兼容解码：MP4/MOV 等系统容器先走 AVFoundation；AVI/MKV/WebM 等先由 FFmpeg 探测并尝试无损重封装，视频或音频仍不可读时自动生成 H.264/AAC 兼容预览。
- 兼容智能导出直接读取源文件，使用经过多场景试压校准的 x265 CRF 24 内容自适应压缩，不把预览代理的损失带入成品。
- 首次启动自动进行运行环境自检；仅在缺少媒体组件时弹出向导，先引导安装 Homebrew，再通过 Homebrew 安装所需组件。只有复检全部通过才会在本机偏好设置中保存完成标记；失败或稍后处理时，下次启动会继续自检。
- 拖放视频和完整键盘快捷键。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- 官方预览构建计划同时支持 Apple Silicon 与 Intel Mac（Universal 2）。
- 从源码构建需要 Xcode 15 或更高版本及 Swift 5.10+。
- 原生格式无需额外依赖；其他容器、编解码兼容预览与内容自适应压缩需要 FFmpeg，本机可通过 `brew install ffmpeg` 安装。

FrameCut 不捆绑 Homebrew 或 FFmpeg 二进制文件。组件用途、安装边界及各自许可信息见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 下载与安装

FrameCut 当前没有 Apple Developer ID 签名和 Apple 公证。GitHub Releases 中提供的二进制版本应视为无签名预览版；macOS 首次打开时会阻止直接运行，需要用户在“系统设置 → 隐私与安全性”中确认“仍要打开”。

只从 [`OpenLingyan/framecut` Releases](https://github.com/OpenLingyan/framecut/releases) 下载，并在运行前核对随包提供的 SHA-256 文件。不要关闭 Gatekeeper，也不要执行来源不明的终端绕过命令。完整步骤、兼容范围和风险说明见 [`docs/INSTALLATION.md`](docs/INSTALLATION.md)。

## 媒体兼容清单

| 类型 | 常见格式 |
|---|---|
| 视频编解码 | H.264/AVC、H.265/HEVC、AV1、VP9、VP8、MPEG-4 Part 2（Xvid/DivX）、MPEG-2、MPEG-1、ProRes、DNxHD/DNxHR、Motion JPEG、VC-1/WMV、Theora、CineForm |
| 音频编解码 | AAC、MP3、AC-3、E-AC-3、Opus、Vorbis、FLAC、ALAC、PCM、WMA、DTS |
| 容器与流文件 | MP4/M4V、MOV、AVI/DivX、MKV、WebM、WMV/ASF、MPG/MPEG/VOB、TS/M2TS/MTS/M4TS、MXF、FLV/F4V、3GP/3G2、OGV、RM/RMVB、DV/MOD/TOD，以及 H.264/H.265/AV1 裸流 |

具体可解码范围取决于当前 FFmpeg 构建启用的解码器。导出统一使用兼容性更好的 H.264/AAC，智能压缩使用 H.265/HEVC + AAC。

## 构建 macOS 应用

```bash
./scripts/build-app.sh
open dist/FrameCut.app
```

脚本会先由 `Resources/FrameCut.png` 生成完整尺寸的 `FrameCut.icns`，再构建包含 `arm64` 和 `x86_64` 的 Universal 2 App，并进行 ad-hoc 临时签名。仅需本机架构时可以指定，例如：

```bash
FRAMECUT_BUILD_ARCHS=arm64 ./scripts/build-app.sh
```

生成可上传到 GitHub Releases 的 ZIP 和 SHA-256 文件：

```bash
./scripts/package-release.sh
```

这些产物适合无签名预览发布；若要消除 Gatekeeper 的未知开发者警告，仍需使用 Apple Developer ID 签名和公证。维护者发布流程见 [`docs/RELEASING.md`](docs/RELEASING.md)。

开发时也可以直接运行：

```bash
./scripts/run.sh
./scripts/run.sh /绝对路径/示例视频.mp4
```

## 快捷键

| 操作 | 快捷键 |
|---|---|
| 打开视频 | `⌘O` |
| 导出片段 | `⌘E` |
| 播放 / 暂停选区 | `Space` |
| 上一帧 / 下一帧 | `←` / `→` |
| 上一关键帧 / 下一关键帧 | `⇧←` / `⇧→` |
| 将当前帧设为入点 / 出点 | `I` / `O` |

## 测试

```bash
swift test
```

项目包含时间码、帧二分定位、关键帧跳转和包含式出点计算的单元测试。

## 参与贡献与安全

开发环境、测试素材规范和 Pull Request 要求见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。发现安全漏洞时请勿公开披露，按照 [`SECURITY.md`](SECURITY.md) 使用 GitHub 私密漏洞报告渠道。

## 隐私与文件安全

FrameCut 对视频的读取、画面分析、预览和导出均在本机执行，不会上传视频，也不会修改源视频。导出会创建用户在系统保存面板中明确选择的新文件；若目标已经存在，覆盖确认由 macOS 处理。

运行环境自检同样在本机完成。系统缺少 Homebrew 或 FFmpeg 时，安装向导需要联网访问 Homebrew 官方安装源及其软件包服务；该过程只用于安装或更新运行组件，不会向 Homebrew、FFmpeg 或 FrameCut 服务上传视频及其内容。

## 开源许可

FrameCut 自身源代码采用 [MIT License](LICENSE)。Homebrew、FFmpeg 及其组件不属于 FrameCut 源代码，适用各自的许可证，详见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
