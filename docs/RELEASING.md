# FrameCut 发布流程

## 当前发布策略

在项目取得 Apple Developer ID 并接入公证之前，二进制版本只作为 GitHub `Pre-release` 发布，并在文件名和发布说明中明确标记 `unsigned`。不要把当前版本描述为已签名、已公证或可无提示安装。

发布包不捆绑 Homebrew、FFmpeg 或 ffprobe。用户首次启动时由组件向导检查并引导安装。

## 发布前检查

1. 确认目标提交已经通过 Pull Request 合并到受保护的 `main`。
2. 更新 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
3. 确认 `main` 与远端同步且工作区没有未提交修改。
4. 执行完整验证：

```bash
for shell_script in scripts/*.sh; do zsh -n "$shell_script"; done
swift test
./scripts/package-release.sh
```

`package-release.sh` 默认构建 Universal 2 App，并在 `dist/` 生成：

- `FrameCut-<版本>-macOS-universal2-unsigned.zip`
- `FrameCut-<版本>-macOS-universal2-unsigned.zip.sha256`

验证 App、CPU 架构和校验文件：

```bash
codesign --verify --deep --strict --verbose=2 dist/FrameCut.app
lipo dist/FrameCut.app/Contents/MacOS/FrameCut -verify_arch arm64 x86_64

cd dist
shasum -a 256 -c FrameCut-<版本>-macOS-universal2-unsigned.zip.sha256
```

`dist/` 已被 Git 忽略，发布包和解压后的 App 不应提交到仓库。

## 创建 GitHub Pre-release

1. 在 GitHub Releases 中选择 `Draft a new release`。
2. 从已经合并并通过 CI 的 `main` 提交创建版本标签，例如 `v1.2.0`。
3. 标题使用 `FrameCut 1.2.0 (Unsigned Preview)`。
4. 上传 ZIP 和对应 SHA-256 文件。
5. 勾选 `Set as a pre-release`。
6. 发布说明必须包含：

```text
这是未经过 Apple Developer ID 签名与公证的预览版本。
支持 macOS 14+、Apple Silicon 与 Intel Mac。
首次打开需要在“系统设置 → 隐私与安全性”中选择“仍要打开”。
完整安装步骤：https://github.com/OpenLingyan/framecut/blob/main/docs/INSTALLATION.md
部分媒体格式与智能压缩需要通过首次启动向导安装 Homebrew 和 FFmpeg。
```

发布后，从 GitHub Release 页面重新下载文件，复核 SHA-256，并在没有本项目构建缓存的 Mac、虚拟机或独立测试账户上走一遍真实安装流程。

## 将来接入 Developer ID

取得 Apple Developer Program 账号后：

1. 创建并安装 `Developer ID Application` 证书。
2. 通过 `FRAMECUT_SIGNING_IDENTITY` 调用现有构建脚本：

```bash
FRAMECUT_SIGNING_IDENTITY="Developer ID Application: 团队名称 (TEAM_ID)" \
  ./scripts/build-app.sh
```

3. 使用 `notarytool` 提交 App 的 ZIP 或 DMG，等待 `Accepted`。
4. 使用 `stapler` 装订并验证公证票据。
5. 在干净系统上通过 Gatekeeper 验证后，才能去掉文件名中的 `unsigned` 和 GitHub 的 `Pre-release` 标记。

证书私钥、`.p12`、App Store Connect `AuthKey_*.p8` 密钥、Apple ID 专用密码和公证凭证绝不能提交到 Git。项目已忽略 `.release-secrets/`、`*.p12` 和 `AuthKey_*.p8`；本地公证凭证应保存在 macOS 钥匙串，CI 凭证应使用 GitHub Environments 与加密 Secrets。
