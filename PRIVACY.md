# Privacy

## Published source

This repository contains source code, documentation, and app icons. It does not include browser profiles, ChatGPT or YouTube login sessions, cookies, passwords, API keys, signing certificates, developer-team settings, personal computer paths, compiled applications, build logs, or local extraction results. Icon EXIF and text metadata have been removed. Git history starts with the sanitized source.

The bundle identifiers use the generic prefix `com.example.YouTubeSubtitleExtraction`. The GitHub repository owner is visible as part of normal public GitHub hosting; private email addresses and local computer usernames are not included in commit authorship.

## When you run the extension

- Version 1.0.8 adds an **optional `cookies` permission**. After the user grants it, the extension reads cookies associated with `https://www.youtube.com/` from the video's cookie store. It filters the result to YouTube domains and passes those cookies, with the selected video URL, to its local macOS helper. It does not read ChatGPT cookies or request ChatGPT website access.
- The helper runs `yt-dlp` with `--ignore-config` and uses a temporary file containing only the forwarded YouTube cookies. These session credentials are sensitive. They are used for requests to YouTube, not sent to ChatGPT or to a project-operated service, and never intentionally printed to logs.
- The normal background flow does not open Safari's browser login database. If permission is declined or the browser interface is unavailable, it attempts anonymous extraction. It does not use browser-database access as a way around permission denial.
- Task URLs, forwarded YouTube login data, and downloaded captions are temporarily stored locally. Task directories are private to the current user, login/task files use owner-only permissions, and files are normally removed after processing. An interrupted process may leave temporary files.
- YouTube receives the normal metadata and caption requests made by `yt-dlp`, including the forwarded YouTube cookies when available.
- The helper replaces the clipboard with the prompt and transcript, or with the video URL when extraction fails. Other apps with clipboard access may read it.
- After successful extraction, the active workflow opens `https://chatgpt.com/` and relies on you to paste and send. It does not export your ChatGPT session, retrieve login credentials, or require an OpenAI API key. ChatGPT may use the existing browser session when you visit its website.
- A manual fallback script is optional, configured locally, and receives the video URL as its first argument. Review any script before using it. The included `Scripts/manual-fallback.command` explicitly opts into `YTSUB_ALLOW_SAFARI_COOKIE_FALLBACK=1`: if anonymous retrieval is blocked, `yt-dlp --cookies-from-browser safari` reads Safari's cookie database in that Terminal process. This legacy access is broader than the extension's filtered YouTube handoff; it is not enabled for the default background flow. The script does not export the browser's cookie jar to a separate file.

There is no project analytics service or project-operated backend. Normal YouTube and ChatGPT website behavior is governed by those services.

## Sharing changes

Before sharing code or reports, exclude app preferences, browser data, logs, downloaded subtitles, signing material, user-specific Xcode settings, and screenshots containing accounts or conversations. `.gitignore` covers common generated and private files; it is not a substitute for reviewing what you commit.
