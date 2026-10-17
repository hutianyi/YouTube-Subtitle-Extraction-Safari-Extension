# YouTube Subtitle Extraction Safari Extension

A macOS Safari Web Extension that extracts subtitles from the current YouTube video and copies a complete summary prompt to the clipboard. No OpenAI API key is required.

[中文说明](README.zh-CN.md) · [Privacy](PRIVACY.md) · [MIT License](LICENSE)

## How it works

1. Open a YouTube video in Safari and click the extension button.
2. On first use, Safari may ask for the optional cookie permission. If you grant it, the extension passes only YouTube-domain cookies from the video's cookie store to the local helper. This lets `yt-dlp` retrieve captions with your existing YouTube login without the helper opening Safari's protected browser-data directory. No video or audio is downloaded.
3. It selects English manual captions first, then English speech-recognition captions, then Chinese manual/speech-recognition captions. Otherwise it uses available original-language captions. Machine-translated captions are excluded.
4. The helper copies `这期节目讲了什么` followed by the full transcript to the clipboard.
5. If the original video tab has not changed, it navigates to `https://chatgpt.com/`. Paste with **Command-V** and send the message yourself.

The app and Xcode target retain the name **YouTube 字幕总结**. The extension version is **1.0.8**. See [changes](CHANGELOG.md) and the [privacy details](PRIVACY.md) before granting the new optional permission.

## Requirements

- macOS **26.5 or later**, matching the current containing-app deployment target. Older systems have not been validated.
- Xcode **26.6 or later** to open the existing project format.
- Safari, `yt-dlp`, and Python 3.

With Homebrew already installed, run this in Terminal from any directory. It installs the local subtitle extraction tools:

```sh
brew install yt-dlp python
```

See the [yt-dlp installation guide](https://github.com/yt-dlp/yt-dlp/wiki/Installation) for other installation methods. The helper searches the usual Apple Silicon and Intel Homebrew locations.

## Build and enable

1. Clone or download this repository and open `Source/YouTube 字幕总结.xcodeproj` in Xcode.
2. Select the **YouTube 字幕总结** scheme and **My Mac** as the destination.
3. For local testing, configure both targets in **Signing & Capabilities** using your own signing settings. The repository does not contain a developer team or signing certificate. Generic bundle identifiers are consistent across the helper and extension; changing them requires updating all matching identifiers and the temporary-directory entitlement.
4. Build and run the containing app once, then enable the extension in Safari Settings → Extensions.
5. For an unsigned/local build, enable unsigned extensions using [Apple’s Safari testing instructions](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension). This relaxes Safari’s signing check for development extensions, so only enable extensions you trust.
6. Grant YouTube website access. Allow the optional cookie permission if you want extraction to use your existing YouTube login. ChatGPT is only a navigation destination; the extension no longer requests website access to it.

After replacing an older build, fully quit and reopen Safari so it reloads the extension.

For a compilation check that does not install or launch the extension, run this in Terminal **from the repository root**. Build artifacts stay in `build/`:

```sh
xcodebuild \
  -project 'Source/YouTube 字幕总结.xcodeproj' \
  -scheme 'YouTube 字幕总结' \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

This is a source release. It does not include a signed or notarized app, and an unsigned compilation alone does not verify Safari activation.

## Optional manual fallback

Automatic extraction is self-contained. A Terminal fallback is optional. The included `Scripts/manual-fallback.command` shares the embedded extractor and its language-selection rules. Review it before use: it explicitly allows `yt-dlp` to read Safari's cookie database if anonymous extraction is blocked. macOS may require separate permission for that access.

To configure the included script, run this **from the repository root**:

```sh
defaults write com.example.YouTubeSubtitleExtraction \
  ManualFallbackCommandPath -string "$PWD/Scripts/manual-fallback.command"
```

This stores the path only in local app preferences. Keep the script in this repository's `Scripts/` directory. If extraction fails, the app starts the script with the video URL as its first argument, so you do not need to paste it again. You can configure a different trusted executable script, but it must accept that first argument to avoid an interactive URL prompt. With no valid fallback configured, the app reports the extraction error instead.

Declining the optional cookie permission does not make the background helper read Safari's cookie database. It attempts anonymous extraction; only an explicitly configured Terminal fallback may opt into the separate browser-database access.

## Verification

Run these offline checks **from the repository root**. Python 3 is already required by the extractor; Node.js is needed only for the simulated browser tests:

```sh
python3 Source/tests/test_subtitle_flow.py
node Source/tests/test_background.cjs
```

These checks cover login forwarding, retry behavior, permission denial, language selection, and tab-navigation protection. They do not activate Safari or replace live browser testing.

## Limitations

Subtitle availability depends on YouTube, the network, and the installed `yt-dlp` version. Videos without usable captions, restricted videos, rate limiting, and YouTube changes may prevent extraction. The current flow accepts YouTube watch pages and `youtu.be` links. It replaces the clipboard contents when used and may replace the original video tab with ChatGPT after success.

## Source layout

- `Source/YouTube 字幕总结/` — containing macOS app and embedded extraction script.
- `Source/YouTube 字幕总结 Extension/` — Safari Web Extension and native-message handler.
- `Source/YouTube 字幕总结.xcodeproj/` — Xcode project.
- `Source/tests/` — offline extraction and simulated browser regression checks.
- `Scripts/manual-fallback.command` — optional Terminal fallback accepting a video URL.

## License

MIT. External tools such as `yt-dlp` and Python remain under their respective licenses and are installed separately.
