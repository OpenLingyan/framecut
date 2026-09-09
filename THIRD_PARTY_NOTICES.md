# 第三方软件声明

FrameCut 自身源代码采用 MIT License，详见 [`LICENSE`](LICENSE)。以下软件不属于 FrameCut 源代码，其各自的许可证和使用条款仍然独立有效。

当前源码、构建脚本和 `FrameCut.app` 不捆绑 Homebrew、FFmpeg、`ffmpeg` 或 `ffprobe` 二进制文件。FrameCut 只会在用户的 Mac 上检测并调用由用户单独安装的外部程序。

## FFmpeg

- 项目主页：<https://ffmpeg.org/>
- 许可说明：<https://ffmpeg.org/legal.html>
- 用途：媒体信息探测、非原生格式兼容预览、H.264/AAC 转换和 H.265/HEVC 内容自适应压缩。
- 安装方式：由用户通过 Homebrew 安装的 `ffmpeg` formula 提供 `ffmpeg` 和 `ffprobe`。

FFmpeg 官方说明其默认采用 GNU Lesser General Public License 2.1 或更高版本；如果构建启用了特定可选 GPL 组件，则该 FFmpeg 构建整体适用 GNU General Public License 2 或更高版本。用户本机安装版本的准确许可范围由该版本的构建选项及其包含的组件决定。

## Homebrew

- 项目主页：<https://brew.sh/>
- 安装说明：<https://docs.brew.sh/Installation>
- 源代码许可：<https://github.com/Homebrew/brew/blob/master/LICENSE.txt>（BSD 2-Clause License）
- 用途：首次运行环境缺少媒体组件时，安装向导会引导用户安装 Homebrew；检测到 Homebrew 后，FrameCut 可调用 `brew install ffmpeg` 或 `brew reinstall ffmpeg`。

Homebrew 本身不随 FrameCut 分发。通过 Homebrew 安装的软件包各自采用其上游项目的许可证，Homebrew 的许可证不替代这些软件包的许可证。

## 后续分发注意事项

如果未来版本把 FFmpeg、Homebrew 或其他第三方二进制直接放入 App、DMG 或安装包，发布者应在发布前重新核对实际构建选项、完整许可证文本、源代码提供方式及其他分发义务，并同步更新本文件。
