# 安装 FrameCut

## 支持范围

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac（Universal 2）
- 非原生媒体格式和智能压缩需要 Homebrew 与 FFmpeg

FrameCut 当前没有 Apple Developer ID 签名和 Apple 公证。GitHub Releases 中的二进制文件属于无签名预览版本，macOS 无法验证其开发者身份，也无法确认它是否经过 Apple 的恶意软件扫描。

## 下载并校验

只从项目的官方 [`OpenLingyan/framecut` Releases](https://github.com/OpenLingyan/framecut/releases) 页面下载以下两个同版本文件：

- `FrameCut-<版本>-macOS-universal2-unsigned.zip`
- `FrameCut-<版本>-macOS-universal2-unsigned.zip.sha256`

在终端进入下载目录并校验：

```bash
shasum -a 256 -c FrameCut-<版本>-macOS-universal2-unsigned.zip.sha256
```

只有看到 `OK` 后再继续安装。校验可以发现下载损坏或文件与发布清单不一致，但不能替代 Apple Developer ID 签名和公证。

## 安装与首次打开

1. 解压 ZIP，把 `FrameCut.app` 拖入“应用程序”。
2. 尝试打开一次 FrameCut；macOS 会提示无法验证开发者或无法检查恶意软件。
3. 打开“系统设置 → 隐私与安全性”，滚动到“安全性”。
4. 找到刚刚被阻止的 FrameCut，点击“仍要打开”，输入 Mac 登录密码并再次确认。
5. 以后可以像普通应用一样从“应用程序”打开当前版本。

不要关闭 Gatekeeper，也不要运行删除隔离属性的终端命令。如果设备由公司或学校管理，“仍要打开”可能不可用，此时无法安装当前无签名版本。

## 运行组件自检

FrameCut 第一次启动时会检查 Homebrew、FFmpeg 和 ffprobe：

- 组件齐全时直接进入主界面。
- 缺少 Homebrew 时，安装向导会说明并引导安装。
- Homebrew 可用后，向导可以通过它安装 FFmpeg。
- 只有复检通过才会记录自检完成；失败时下次启动仍会再次检查。

安装组件需要联网，但视频读取、分析、预览和导出都在本机完成，视频不会上传。

## 从源码构建

不希望放行无签名二进制时，可以审查源码后自行构建：

```bash
git clone https://github.com/OpenLingyan/framecut.git
cd framecut
swift test
./scripts/build-app.sh
open dist/FrameCut.app
```

从源码构建需要 Xcode 15 或更高版本及 Swift 5.10+。
