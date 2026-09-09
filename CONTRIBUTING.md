# 贡献指南

感谢你愿意改进 FrameCut。项目欢迎缺陷修复、兼容性改进、测试、文档和经过讨论的新功能。

## 提交问题前

- 先搜索现有 Issue，确认问题尚未被报告。
- 普通缺陷请说明 macOS 版本、Mac 架构、FrameCut 版本或提交哈希、媒体容器与编解码格式、复现步骤和实际结果。
- 不要上传私人、受版权保护或包含敏感信息的视频。优先使用 `scripts/generate-qa-video.sh` 创建的合成样片，或提供经过最小化和脱敏的复现材料。
- 安全漏洞不要提交公开 Issue，请按照 [`SECURITY.md`](SECURITY.md) 私下报告。

## 开发环境

- macOS 14 Sonoma 或更高版本
- Xcode 15 或更高版本
- Swift 5.10 或更高版本
- Homebrew 与 FFmpeg，用于完整格式兼容和媒体集成测试

```bash
git clone https://github.com/OpenLingyan/framecut.git
cd framecut
brew install ffmpeg
swift test
./scripts/run.sh
```

## 修改原则

- 保持改动聚焦，一次 Pull Request 解决一个清晰的问题。
- 延续现有 Swift 和 SwiftUI 风格，避免与功能无关的大规模格式化。
- 修复缺陷或改变行为时应同步添加或更新测试。
- 新增第三方依赖前，请说明必要性、许可证、二进制体积和隐私影响。
- 不要提交 `.design/`、本地构建产物、真实测试视频、凭证、密钥或开发机路径。
- 新增图片、字体、音视频等资产时，必须确认允许在 MIT 开源仓库中再分发，并在需要时注明来源和许可证。
- FrameCut 当前不捆绑 FFmpeg 或 Homebrew；如果改变这一边界，必须同步更新 `README.md` 和 `THIRD_PARTY_NOTICES.md` 并重新审查分发义务。

## 本地验证

先执行基础检查：

```bash
for shell_script in scripts/*.sh; do zsh -n "$shell_script"; done
swift build -c release --arch arm64 --arch x86_64
swift test
```

运行完整媒体集成测试：

```bash
./scripts/generate-qa-video.sh .design/fixtures/qa-sample.mp4

FRAMECUT_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
FRAMECUT_CONTENT_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
FRAMECUT_COMPATIBILITY_QA_VIDEO="$PWD/.design/fixtures/qa-sample.mp4" \
swift test

./scripts/build-app.sh
lipo dist/FrameCut.app/Contents/MacOS/FrameCut -verify_arch arm64 x86_64
```

完整测试应无失败、无跳过。测试生成的 `.design/` 内容和全部 `dist/` 发布产物已被 Git 忽略。

## Pull Request

提交前请确认：

- [ ] 变更能够在支持的 macOS 和 Swift 版本上构建。
- [ ] 相关测试已通过，新增行为有对应测试。
- [ ] 未包含密钥、个人路径、私人媒体或无权分发的资产。
- [ ] 用户可见行为、依赖或隐私边界发生变化时，README 和第三方声明已同步更新。
- [ ] Pull Request 描述包含改动目的、验证方式和必要的界面截图。

提交贡献即表示你同意按照项目根目录中的 MIT License 授权该贡献。
