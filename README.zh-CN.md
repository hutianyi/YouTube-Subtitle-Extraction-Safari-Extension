# YouTube Subtitle Extraction Safari Extension

macOS Safari 插件：提取当前 YouTube 视频字幕，复制“这期节目讲了什么”加字幕全文，再打开 ChatGPT，由你手动粘贴并发送。不需要 OpenAI API Key。

[English](README.md) · [隐私说明](PRIVACY.md) · [MIT 许可证](LICENSE)

## 安装和启用

当前源码版本为 **1.0.8**，应用和 Xcode 工程仍叫 **YouTube 字幕总结**。当前应用的部署目标是 **macOS 26.5**；需要 **Xcode 26.6 或更新版本**。更早系统尚未验证。更新内容见 [CHANGELOG](CHANGELOG.md)。

1. 本机需要 `yt-dlp` 和 Python 3。如果已安装 Homebrew，可在任意目录的 Terminal 运行以下命令，安装字幕提取依赖：

   ```sh
   brew install yt-dlp python
   ```

2. 下载或克隆仓库，用 Xcode 打开 `Source/YouTube 字幕总结.xcodeproj`。
3. 选择 **YouTube 字幕总结** 和 **My Mac**，在两个 target 的 **Signing & Capabilities** 中使用自己的本机签名设置。仓库不提供个人开发团队、证书或预签名应用。
4. 编译并运行一次应用，在 Safari 设置 → 扩展中启用插件。未签名的开发版本需要按照 [Apple 官方说明](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)允许未签名扩展；这会放宽开发扩展的签名检查，请只启用你信任的扩展。
5. 按提示授予 YouTube 网站访问权限。首次点击时，可选择允许 Cookie 权限，让插件仅把当前视频所在 Safari 环境的 YouTube 登录数据交给本机助手；授权范围与临时处理方式见 [隐私说明](PRIVACY.md)。ChatGPT 仅是跳转目标，插件不再请求其网站访问权限。通用应用标识在各处保持一致；如自行修改，需要同时修改源码、工程和临时目录权限中的相应标识。

替换旧版本后，请完全退出并重新打开 Safari，让它重新加载扩展。

仅检查源码是否可以编译的命令见 [英文说明](README.md#build-and-enable)。该命令不安装或启动插件。

## 日常使用

1. 在 Safari 打开 YouTube 的具体视频播放页，或 `youtu.be` 视频链接。
2. 点击扩展按钮，按需允许使用 YouTube 登录状态，等待后台提取。助手通过插件接收登录数据，无需直接读取 Safari 的受保护浏览器目录。
3. 字幕选择顺序：英语人工字幕、英语音频识别字幕、中文人工字幕、中文音频识别字幕；再选择可用的原语言字幕，不选择机器翻译字幕。
4. 完整提示词会替换当前剪贴板内容。如果原视频标签页仍停留在同一网址，它会跳转到 `https://chatgpt.com/`。
5. 在 ChatGPT 输入框按 **Command-V**，检查内容后手动发送。插件不读取 ChatGPT 的登录 Cookie、密码或令牌，也不自动提交内容。

如果原标签页已改变，会保留当前网页；此时自行打开 ChatGPT 并粘贴。

## 可选的手动后备脚本

正常提取使用应用内的脚本。公开版本不绑定任何个人电脑目录；随附的 `Scripts/manual-fallback.command` 是可选的 Terminal 后备，与内置流程共用字幕选择规则。

请先检查后备脚本：它会在匿名提取被拦截时，明确允许 `yt-dlp` 读取 Safari Cookie 数据库；macOS 可能要求额外的系统访问许可。若决定使用，在**仓库根目录**运行以下命令，将脚本路径保存到本机偏好设置：

```sh
defaults write com.example.YouTubeSubtitleExtraction \
  ManualFallbackCommandPath -string "$PWD/Scripts/manual-fallback.command"
```

请把随附脚本保留在仓库的 `Scripts/` 目录。自动提取失败时，应用会把网址作为第一个参数交给后备脚本，无需再次粘贴。也可以配置自己的可信可执行脚本；要免于手动输入，它必须支持第一个参数接收视频网址。未配置有效脚本时显示提取错误。

拒绝可选 Cookie 权限时，后台助手只尝试匿名提取，不会因此读取 Safari Cookie 数据库。只有用户明确配置的 Terminal 后备可选择这种独立访问方式。

## 开发验证

在**仓库根目录**运行以下离线检查。提取程序本身需要 Python 3；只有浏览器模拟测试需要另行已有 Node.js：

```sh
python3 Source/tests/test_subtitle_flow.py
node Source/tests/test_background.cjs
```

测试覆盖登录数据传入、重试、权限拒绝、字幕语言选择和原标签页跳转保护，不会启动 Safari 或访问真实登录数据。

## 使用范围

字幕提取依赖 YouTube、网络和 `yt-dlp`。无字幕、受限视频、限流或网站变化均可能导致失败。公开仓库仅提供源码，不包含经过签名或公证的应用。源码编译成功不能代替 Safari 实际启用和字幕提取验收。

## 开源许可

本项目采用 MIT 许可证。外部安装的 `yt-dlp` 和 Python 分别遵循各自的许可证。
