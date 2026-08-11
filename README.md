# CodexNotes

CodexNotes 是一个跟随 Codex 当前任务自动切换的原生 macOS Markdown 笔记侧栏。

> English: CodexNotes is a native macOS Markdown sidecar that follows the task currently selected in Codex. The app supports both Simplified Chinese and English.

[下载最新版本](https://github.com/jiangsir-tech/CodexNotes/releases/latest) · [提交问题](https://github.com/jiangsir-tech/CodexNotes/issues)

## 系统要求

- Apple Silicon（arm64）或 Intel（x86_64）Mac
- macOS 14.0 或更高版本
- 正式 Release 为 Universal 2，同一份应用同时包含 arm64 与 x86_64
- 当前已验证兼容 Codex `26.803.41515`

CodexNotes 是非官方第三方工具，与 OpenAI 没有隶属、授权或背书关系。

## 安装

1. 从 [Releases](https://github.com/jiangsir-tech/CodexNotes/releases/latest) 下载 `CodexNotes-v<版本号>-macOS-universal.zip`；同一份 Universal 2 文件适用于 Apple Silicon 与 Intel Mac。
2. 解压后，把 `CodexNotes.app` 移到 `/Applications` 或 `~/Applications`。
3. 首次打开后，CodexNotes 会常驻菜单栏，不会在 Dock 显示图标。

正式 Release 使用 Developer ID 签名并通过 Apple notarization。你可以在终端验证：

```sh
codesign --verify --deep --strict --all-architectures --verbose=2 /Applications/CodexNotes.app
spctl --assess --type exec --verbose=4 /Applications/CodexNotes.app
```

## 主要功能

- 在 Codex 中切换任务时，自动打开对应的独立任务笔记
- 任务笔记通过稳定任务 ID 绑定；任务改名不会丢失内容
- 项目笔记通过 Codex 的真实项目归属绑定，不会把工作目录误认成项目
- 所有正文保存为本地纯文本 Markdown，不需要登录或联网
- 停止输入约 450 毫秒后自动保存；切换任务前会立即保存
- 支持标准 Markdown 待办、图形复选框、进度显示和原生撤销
- 支持 `**粗体**` 与 Obsidian 兼容的 `==高亮==`
- 支持在任务笔记与项目笔记之间安全移动选中文字
- 支持粘贴或拖入 PNG、JPEG、HEIC、静态 WebP；导入时清除 EXIF/GPS 元数据
- 支持系统原色及六套自定义主题，并可调整字号与行间距
- 支持跟随系统、简体中文和 English 三种语言选项
- 支持自定义全局显示/隐藏快捷键；只在 Codex 正在运行且未隐藏时生效
- 可选择登录 Mac 时启动；该功能默认关闭并使用 macOS 原生登录项
- 记住窗口位置和大小；隐藏、重新显示或重启后不会漂移
- 关于页显示版本、作者与项目链接，并支持手动检查或主动开启每日 GitHub Release 更新检查

## 数据与隐私

所有笔记和受管图片默认保存在：

```text
~/Library/Application Support/Codex Task Notes/Notes/
├── Assets/
├── Tasks/
└── Projects/
```

Markdown 原文是唯一数据源。图形复选框、图片预览、粗体和高亮都只是编辑器显示效果，不会引入私有数据库格式。

CodexNotes 不上传笔记、不提供云同步，也不包含遥测或分析服务。应用只读取 Codex 写在本机的状态与导航日志，用来识别当前任务。

只有当你手动点击“检查更新”，或主动开启“自动检查更新”后，应用才会访问 GitHub Releases API。成功检查后间隔 24 小时；网络失败时会静默退避重试。应用只检查版本，不会自动下载或安装；请求不包含笔记内容、设备标识或遥测数据。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⇧Space`（默认，可更改） | 显示或隐藏 CodexNotes；只在 Codex 正在运行且未隐藏时生效 |
| `⌘1` | 切换到任务笔记 |
| `⌘2` | 切换到项目笔记 |
| `⌘↩` | 切换当前行的待办状态 |
| `⌘B` | 切换选中文字的粗体 |
| `⌘⇧H` | 切换选中文字的高亮 |

## 从源码构建

需要 Xcode 15.4 或更高版本。应用的运行下限是 macOS 14。

```sh
test_build_dir="$(mktemp -d /tmp/codexnotes-test.XXXXXX)"
COPYFILE_DISABLE=1 swift test --scratch-path "$test_build_dir"
zsh scripts/verify-localizations.sh
zsh scripts/package-app.sh
```

`package-app.sh` 默认只在 `dist/` 生成 Universal 2 的本地 ad-hoc 构建，不会覆盖已安装应用。开发者如需安装本地构建，必须显式执行：

```sh
CODEX_NOTES_INSTALL_LOCAL=1 \
CODEX_NOTES_INSTALL_DIRECTORY="$HOME/Applications" \
zsh scripts/package-app.sh
```

正式 Developer ID 签名与 Apple notarization 使用：

```sh
CODEX_NOTES_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CODEX_NOTES_NOTARY_PROFILE="your-notarytool-profile" \
zsh scripts/release-notarized.sh
```

## 兼容性说明

自动跟随目前依赖 Codex `26.803.41515` 写出的本机主窗口导航日志。该日志不是公开稳定接口，因此 Codex 大版本更新后需要重新进行兼容性测试。

Universal 2 产物会验证 arm64 与 x86_64 两个架构。当前 Codex 联动验证以 Apple Silicon 真机为主；Intel 版已包含原生 x86_64 架构代码，完整联动兼容性将在真实 Intel Mac 上持续验证，交叉编译或 Rosetta 启动仅作为补充。

## 许可证

本仓库目前尚未采用开源许可证。公开源码用于透明度、审查与问题反馈，不代表授予复制、修改或再分发源码及品牌素材的许可。
