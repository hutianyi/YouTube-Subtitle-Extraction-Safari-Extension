# Changelog

## 1.0.8 — 2026-10-17

- Add an optional Safari cookie permission to forward only YouTube login data to the local helper, allowing authenticated subtitle extraction without opening the protected Safari browser-data directory.
- Remove ChatGPT website access; ChatGPT remains a normal navigation destination with manual paste and submission.
- Keep anonymous extraction available when login access is declined. Browser-database access is restricted to an explicitly opted-in Terminal fallback.
- Pass the video URL directly to the configured fallback script. Include an optional fallback that shares the embedded extractor and its English/Chinese language priorities.
- Avoid pipe-buffer stalls while collecting extraction errors.
- Add offline extraction and simulated browser regression tests; update setup and privacy documentation.

This is a source-only release. Compilation and automated checks do not establish Safari activation or live browser acceptance on another Mac.
