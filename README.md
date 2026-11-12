# 阅读从简 · Reading Simple

免费的原生 Mac EPUB / PDF 阅读器。把引用原句和自己的想法放在一起，安静阅读，随手记录。

[下载安装包](https://github.com/xgchip/reading-simple/releases/tag/v1.0.0) · [官网](https://xgchip.github.io/reading-simple/) · [使用帮助](https://xgchip.github.io/reading-simple/support.html) · [隐私政策](https://xgchip.github.io/reading-simple/privacy.html)

## 下载与安装

从 Releases 下载 `ReadingSimple-1.0.0-arm64.dmg`，打开磁盘映像，将「阅读从简」拖到 Applications。当前提供 **Apple Silicon（M 系列）版本**；部署目标 macOS 14，实际验证环境 macOS 27.0.1，尚未在 macOS 14 实机验收。没有 Intel 安装包。

**首个版本为公开测试版：ad-hoc 签名，未经 Apple 公证。** macOS 可能阻止首次打开。请确认下载来自本仓库，并核对 SHA256SUMS.txt；不要关闭 Gatekeeper 或运行去除安全保护的命令。如果不希望运行未经公证的安装包，可按下方步骤从源码构建。系统对外部应用的处理说明见 [Apple 支持](https://support.apple.com/102445)。

## 功能

- EPUB2/3 可重排阅读；PDF 原版式阅读、页码跳转、缩放和旋转。
- 选择文字划线、记录想法；正式笔记与未提交草稿分别保存。
- 跨书搜索引用和想法，点击返回原文。
- 将全部正式想法或搜索结果导出为 Markdown，包含引用、想法、书名及章节/页码。
- 素白、暖纸和深色主题，原创纸张纹理。
- 本地书库与阅读进度，无账户、广告或云同步。导入的书籍不随软件发布。

只支持无 DRM 的可重排 EPUB。扫描 PDF 可阅读，当前不含 OCR；不会绕过文档密码或复制/批注权限。Markdown 导出不是完整书库备份。

## 从源码构建

需要 macOS、完整 Xcode（含 macOS SDK）、命令行工具、Python 3 和 zsh。首次构建需要联网获取精确固定为 0.9.20 的 ZIPFoundation。开发验证使用 Xcode 27.2；较旧 Xcode 尚未逐版本验证。

```sh
git clone https://github.com/xgchip/reading-simple.git
cd reading-simple
zsh scripts/build_direct.sh
```

输出到 `release/direct/`：应用、DMG、构建与验证报告。脚本不会覆盖已有输出目录或正在运行的应用；再次构建请指定新的输出目录，例如 `zsh scripts/build_direct.sh release/direct-next`。默认采用本地 ad-hoc 签名，不需要开发者账户。

该脚本复用名为 `AppStore` 的生产编译配置以剔除诊断 CLI、测试目录覆盖和阅读日志；这**不代表进行商店签名、上传或提交**。不要用普通 Debug/Release 构建替代公开发行包。

也可在 Xcode 打开 `Reader.xcodeproj` 进行开发。内部 bundle ID `com.haley.MarginReader` 保留以维持已有书库兼容。进行独立分支开发时可另选自己的 bundle ID，避免影响既有应用数据。

## 许可证与对应源码

Copyright (C) 2026 Yanli Tan。本项目原创代码、文档与图标使用 **GPL-3.0-only**，完整条款见 [LICENSE](LICENSE)。ZIPFoundation 保持 MIT 许可证，原创暖纸/深色纹理保持 CC0，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

每个安装包旁提供 `ReadingSimple-1.0.0-CorrespondingSource.zip`，包含对应应用源码、构建脚本以及 ZIPFoundation 0.9.20 完整源码和许可。GitHub 自动生成的 Source code 下载仅含本仓库；需要完整依赖源码时请下载上述对应源码包。

## 反馈

请在 [Issues](https://github.com/xgchip/reading-simple/issues) 反馈问题，附应用版本、系统版本、文档格式和复现步骤。不要公开私人书籍、摘录或笔记；支持邮箱为 haley.chai@gmail.com。
