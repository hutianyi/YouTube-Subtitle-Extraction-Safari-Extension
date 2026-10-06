# Privacy

## Published source

This repository contains source code, documentation, and app icons. It does not include browser profiles, ChatGPT or YouTube login sessions, cookies, passwords, API keys, signing certificates, developer-team settings, personal computer paths, compiled applications, build logs, or local extraction results. Icon EXIF and text metadata have been removed. Git history starts with the sanitized source.

The bundle identifiers use the generic prefix `com.example.YouTubeSubtitleExtraction`. The GitHub repository owner is visible as part of normal public GitHub hosting; private email addresses and local computer usernames are not included in commit authorship.

## When you run the extension

- The extension sends the selected YouTube URL to its local macOS helper.
- The helper runs `yt-dlp` with `--ignore-config`; its built-in extraction does not request browser cookies or read browser login databases.
- YouTube receives the normal requests made by `yt-dlp` to retrieve video metadata and captions.
- Task URLs and downloaded caption files are temporarily stored locally and normally removed after processing. An interrupted process may leave temporary files.
- The helper replaces the clipboard with the prompt and transcript, or with the video URL when extraction fails. Other apps with clipboard access may read it.
- After successful extraction, the active workflow opens `https://chatgpt.com/` and relies on you to paste and send. It does not export your ChatGPT session, retrieve login credentials, or require an OpenAI API key. ChatGPT may use the existing browser session when you visit its website.
- A manual fallback script is optional, configured locally, and runs under its own behavior. Review that script before using it.

There is no project analytics service or project-operated backend. Normal YouTube and ChatGPT website behavior is governed by those services.

## Sharing changes

Before sharing code or reports, exclude app preferences, browser data, logs, downloaded subtitles, signing material, user-specific Xcode settings, and screenshots containing accounts or conversations. `.gitignore` covers common generated and private files; it is not a substitute for reviewing what you commit.
