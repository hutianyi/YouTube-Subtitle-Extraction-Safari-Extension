#!/bin/zsh

# Optional Terminal fallback. Pass a URL as the first argument, or enter one.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
VIDEO_URL="${1:-}"
if [[ -z "$VIDEO_URL" ]]; then
  print -n "YouTube video URL: "
  IFS= read -r VIDEO_URL
fi

SCRIPT_ROOT="${0:A:h:h}"
EXTRACTOR="$SCRIPT_ROOT/Source/YouTube 字幕总结/Resources/SubtitleExtractor.sh"
if [[ ! -f "$EXTRACTOR" ]]; then
  print -u2 -- "Keep this script in the repository's Scripts folder."
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/youtube-manual.XXXXXX")" || exit 1
trap '/bin/rm -rf -- "$TEMP_DIR"' EXIT HUP INT TERM

# Explicit opt-in for this trusted, user-configured Terminal fallback only.
# yt-dlp reads Safari's cookie database; it does not export a cookie file.
if ! YTSUB_ALLOW_SAFARI_COOKIE_FALLBACK=1 /bin/zsh "$EXTRACTOR" "$VIDEO_URL" "$TEMP_DIR/transcript.txt"; then
  exit 1
fi

if ! {
  print -r -- "这期节目讲了什么"
  print ""
  /bin/cat "$TEMP_DIR/transcript.txt"
} | /usr/bin/pbcopy; then
  print -u2 -- "Could not copy the transcript to the clipboard."
  exit 1
fi

print -- "Prompt copied. Paste it in ChatGPT with Command-V."
/usr/bin/open -a Safari "https://chatgpt.com/"
