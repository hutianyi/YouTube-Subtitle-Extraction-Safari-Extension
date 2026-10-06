# YouTube Subtitle Extraction Safari Extension

macOS Safari 插件：提取当前 YouTube 视频字幕，复制“这期节目讲了什么”加字幕全文，再打开 ChatGPT，由你手动粘贴并发送。不需要 OpenAI API Key。

[English](README.md) · [隐私说明](PRIVACY.md) · [MIT 许可证](LICENSE)

## 安装和启用

当前源码版本为 **1.0.7**，应用和 Xcode 工程仍叫 **YouTube 字幕总结**。当前应用的部署目标是 **macOS 26.5**；需要 **Xcode 26.6 或更新版本**。更早系统尚未验证。

1. 本机需要 `yt-dlp` 和 Python 3。如果已安装 Homebrew，可在任意目录的 Terminal 运行以下命令，安装字幕提取依赖：

   ```sh
   brew install yt-dlp python
   ```

2. 下载或克隆仓库，用 Xcode 打开 `Source/YouTube 字幕总结.xcodeproj`。
3. 选择 **YouTube 字幕总结** 和 **My Mac**，在两个 target 的 **Signing & Capabilities** 中使用自己的本机签名设置。仓库不提供个人开发团队、证书或预签名应用。
4. 编译并运行一次应用，在 Safari 设置 → 扩展中启用插件。未签名的开发版本需要按照 [Apple 官方说明](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)允许未签名扩展；这会放宽开发扩展的签名检查，请只启用你信任的扩展。
5. 按提示授予 YouTube 和 ChatGPT 网站权限。通用应用标识在各处保持一致；如自行修改，需要同时修改源码、工程和临时目录权限中的相应标识。

仅检查源码是否可以编译的命令见 [英文说明](README.md#build-and-enable)。该命令不安装或启动插件。

## 日常使用

1. 在 Safari 打开 YouTube 的具体视频播放页，或 `youtu.be` 视频链接。
2. 点击扩展按钮，等待字幕提取。
3. 字幕选择顺序：英语人工字幕、英语音频识别字幕、中文人工字幕、中文音频识别字幕；再选择可用的原语言字幕，不选择机器翻译字幕。
4. 完整提示词会替换当前剪贴板内容。如果原视频标签页仍停留在同一网址，它会跳转到 `https://chatgpt.com/`。
5. 在 ChatGPT 输入框按 **Command-V**，检查内容后手动发送。插件不需要你的登录 Cookie、密码或令牌。

如果原标签页已改变，会保留当前网页；此时自行打开 ChatGPT 并粘贴。

## 可选的手动后备脚本

正常提取使用应用内的脚本。公开版本不绑定任何个人电脑目录，也不附带外部 `.command` 文件。

如果你已有可信的字幕提取脚本，可以在任意目录的 Terminal 运行下列命令，将路径保存到自己的本机偏好设置。请将示例改为实际脚本位置：

```sh
defaults write com.example.YouTubeSubtitleExtraction \
  ManualFallbackCommandPath -string "$HOME/Scripts/YouTube字幕提取.command"
```

自动提取失败时，应用会复制视频网址，并打开已配置的可执行脚本；在该脚本的 Terminal 窗口粘贴网址继续。未配置有效脚本时显示提取错误。

## 使用范围

字幕提取依赖 YouTube、网络和 `yt-dlp`。无字幕、受限视频、限流或网站变化均可能导致失败。公开仓库仅提供源码，不包含经过签名或公证的应用。源码编译成功不能代替 Safari 实际启用和字幕提取验收。

## 开源许可

本项目采用 MIT 许可证。外部安装的 `yt-dlp` 和 Python 分别遵循各自的许可证。
