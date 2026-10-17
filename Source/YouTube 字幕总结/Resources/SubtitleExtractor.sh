#!/bin/zsh

# Safari 扩展后台助手：优先提取英语、其次中文的 YouTube 字幕。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-en_US.UTF-8}"

fail() {
  print -u2 -r -- "$1"
  exit "${2:-1}"
}

if ! command -v yt-dlp >/dev/null 2>&1; then
  fail "没有检测到 yt-dlp。请先在 Terminal 中执行：brew install yt-dlp"
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "没有检测到 Python 3。请先在 Terminal 中执行：brew install python"
fi

YTDLP="$(command -v yt-dlp)"
PYTHON="$(command -v python3)"

VIDEO_URL="${1:-}"
RESULT_FILE="${2:-}"

if [[ -z "$VIDEO_URL" || -z "$RESULT_FILE" ]]; then
  fail "后台字幕提取参数不完整。"
fi

# 去掉粘贴时可能带入的首尾空白。
VIDEO_URL="${VIDEO_URL#"${VIDEO_URL%%[![:space:]]*}"}"
VIDEO_URL="${VIDEO_URL%"${VIDEO_URL##*[![:space:]]}"}"

if ! "$PYTHON" - "$VIDEO_URL" <<'PY' >/dev/null 2>&1
import sys
from urllib.parse import urlparse

url = sys.argv[1]
try:
    parsed = urlparse(url)
except Exception:
    raise SystemExit(1)

host = (parsed.hostname or "").lower().rstrip(".")
allowed = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
    "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com",
}
if parsed.scheme not in {"http", "https"} or host not in allowed or not parsed.path:
    raise SystemExit(1)
PY
then
  fail "无法识别这个 YouTube 链接，请检查链接。"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/youtube-subtitles.XXXXXX")" \
  || fail "无法创建临时目录，请稍后重试。"
trap 'rm -rf -- "$TEMP_DIR"' EXIT HUP INT TERM

METADATA_FILE="$TEMP_DIR/metadata.json"
ERROR_FILE="$TEMP_DIR/yt-dlp-error.txt"

# 普通后台任务仅使用 Safari 插件授权传入的登录数据。
# 手动后备可显式选择从 Safari 读取登录状态并重试一次。
# 登录数据仅供本次提取使用，不持久保存浏览器 Cookie。
COOKIE_ARGS=()
# Safari 插件仅传入 YouTube 域的本次登录数据，避免助手读取浏览器的受保护目录。
if [[ -n "${3:-}" && -f "$3" ]]; then
  COOKIE_ARGS=(--cookies "$3")
fi
run_ytdlp() {
  local output_file="$TEMP_DIR/yt-dlp-output.txt"
  "$YTDLP" "${COOKIE_ARGS[@]}" "$@" >"$output_file" 2>"$ERROR_FILE"
  local exit_code=$?
  if [[ "${YTSUB_ALLOW_SAFARI_COOKIE_FALLBACK:-0}" == "1" ]] && \
    (( exit_code != 0 )) && (( ${#COOKIE_ARGS[@]} == 0 )) && \
    /usr/bin/grep -Eiq 'not a bot|sign in|login required|authentication|HTTP Error (401|403|429)|Use --cookies' "$ERROR_FILE"; then
    COOKIE_ARGS=(--cookies-from-browser safari)
    print -u2 -- "正在使用 Safari 登录状态重试字幕提取……"
    "$YTDLP" "${COOKIE_ARGS[@]}" "$@" >"$output_file" 2>"$ERROR_FILE"
    exit_code=$?
  fi
  if (( exit_code == 0 )); then
    /bin/cat "$output_file"
  fi
  return "$exit_code"
}

print ""
print "正在读取视频字幕信息……"

if ! run_ytdlp \
  --ignore-config \
  --no-playlist \
  --skip-download \
  --dump-single-json \
  --no-warnings \
  --socket-timeout 20 \
  --retries 3 \
  --extractor-args "youtube:skip=translated_subs" \
  "$VIDEO_URL" >"$METADATA_FILE"; then
  SHORT_ERROR="$(sed -n 's/^ERROR: */ /p' "$ERROR_FILE" | tail -n 1)"
  if [[ -n "$SHORT_ERROR" ]]; then
    fail "YouTube、网络或 yt-dlp 出错：${SHORT_ERROR# }"
  fi
  fail "YouTube、网络或 yt-dlp 出错。请检查网络，并尝试运行：brew upgrade yt-dlp"
fi

# 读取 yt-dlp 元数据：英语优先，其次中文；自动字幕只选音频识别轨道。
"$PYTHON" - "$METADATA_FILE" "$TEMP_DIR" <<'PY'
# SELECTOR_PY_START
import json
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

metadata_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])

try:
    info = json.loads(metadata_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(21)

def valid_tracks(value):
    if not isinstance(value, dict):
        return {}
    return {
        str(code): tracks for code, tracks in value.items()
        if code != "live_chat" and isinstance(tracks, list) and tracks
    }

manual = valid_tracks(info.get("subtitles"))
automatic = valid_tracks(info.get("automatic_captions"))

def clean_code(code):
    code = str(code).strip()
    return code[:-5] if code.lower().endswith("-orig") else code

def norm_code(code):
    return clean_code(code).replace("_", "-").lower()

def code_score(track_code, wanted_code):
    track = norm_code(track_code)
    wanted = norm_code(wanted_code)
    if not track or not wanted:
        return 0
    if track == wanted:
        return 100
    if track.startswith(wanted + "-") or wanted.startswith(track + "-"):
        return 80
    if track.split("-", 1)[0] == wanted.split("-", 1)[0]:
        return 40
    return 0

def track_name(tracks):
    for item in tracks:
        if isinstance(item, dict) and item.get("name"):
            name = str(item["name"])
            name = re.sub(r"\s*\((?:Original|auto-generated)\)\s*$", "", name, flags=re.I)
            if name:
                return name
    return ""

def is_original_auto(code, tracks):
    if code.lower().endswith("-orig"):
        return True
    for item in tracks:
        if not isinstance(item, dict):
            continue
        if str(item.get("name", "")).lower().endswith("(original)"):
            return True
        url = item.get("url")
        if not isinstance(url, str):
            continue
        query = parse_qs(urlparse(url).query)
        source_lang = (query.get("lang") or [""])[-1]
        translated_to = (query.get("tlang") or [""])[-1]
        if source_lang and not translated_to and norm_code(source_lang) == norm_code(code):
            return True
    return False

# yt-dlp 新版本的 “-orig” 标记最可靠；URL 中无 tlang 的源轨道用于兼容旧版本。
original_auto = []
for code, tracks in automatic.items():
    if is_original_auto(code, tracks):
        base = norm_code(code)
        if not any(norm_code(existing) == base for existing in original_auto):
            original_auto.append(code)
        elif code.lower().endswith("-orig"):
            original_auto = [
                code if norm_code(existing) == base else existing
                for existing in original_auto
            ]

# 多音轨视频中，yt-dlp 会把原始/默认音轨语言放在格式元数据里。
audio_original = []
audio_default = []
for fmt in info.get("formats") or []:
    if not isinstance(fmt, dict) or fmt.get("acodec") in (None, "none"):
        continue
    language = fmt.get("language")
    if not language:
        continue
    preference = fmt.get("language_preference")
    note = str(fmt.get("format_note") or "").lower()
    target = None
    if isinstance(preference, (int, float)) and preference >= 10 or "(original)" in note:
        target = audio_original
    elif isinstance(preference, (int, float)) and preference >= 5 or "(default)" in note:
        target = audio_default
    if target is not None and not any(norm_code(x) == norm_code(language) for x in target):
        target.append(str(language))

metadata_language = info.get("language")
language_hints = original_auto + audio_original + audio_default
if metadata_language:
    language_hints.append(str(metadata_language))

def best_match(tracks_by_code, hints):
    best = None
    best_score = 0
    for hint_index, hint in enumerate(hints):
        for order, code in enumerate(tracks_by_code):
            score = code_score(code, hint)
            candidate = (score, -hint_index, -order, code)
            if score and (best is None or candidate > best):
                best = candidate
                best_score = score
    return best[3] if best and best_score else None

chosen_code = None
chosen_kind = None

# 依次选择：英语人工、英语音频识别、中文人工、中文音频识别。
# 自动翻译字幕不属于 original_auto，不参与语言优先选择。
original_automatic = {code: automatic[code] for code in original_auto}
for language in ("en", "zh"):
    chosen_code = best_match(manual, [language])
    if chosen_code:
        chosen_kind = "manual"
        break
    chosen_code = best_match(original_automatic, [language])
    if chosen_code:
        chosen_kind = "automatic"
        break

# 没有英语或中文字幕时，沿用原来的原语言选择规则。
if chosen_code is None and manual:
    chosen_code = best_match(manual, language_hints)
    if chosen_code:
        chosen_kind = "manual"
    elif not original_auto:
        chosen_code = next(iter(manual))
        chosen_kind = "manual"

if chosen_code is None and original_auto:
    chosen_code = original_auto[0]
    chosen_kind = "automatic"

if chosen_code is None:
    raise SystemExit(20)

tracks = manual[chosen_code] if chosen_kind == "manual" else automatic[chosen_code]
language_name = track_name(tracks) or clean_code(chosen_code)
title = re.sub(r"\s+", " ", str(info.get("title") or "（未知标题）")).strip()

(out_dir / "selected-code.txt").write_text(chosen_code, encoding="utf-8")
(out_dir / "selected-pattern.txt").write_text("^" + re.escape(chosen_code) + "$", encoding="utf-8")
(out_dir / "selected-kind.txt").write_text(chosen_kind, encoding="utf-8")
(out_dir / "selected-language.txt").write_text(language_name, encoding="utf-8")
(out_dir / "video-title.txt").write_text(title, encoding="utf-8")
# SELECTOR_PY_END
PY
SELECT_STATUS=$?

if [[ $SELECT_STATUS -eq 20 ]]; then
  fail "这个视频没有可用的字幕。"
elif [[ $SELECT_STATUS -ne 0 ]]; then
  fail "无法读取字幕信息。请尝试运行：brew upgrade yt-dlp"
fi

SUB_PATTERN="$(<"$TEMP_DIR/selected-pattern.txt")"
SUB_KIND="$(<"$TEMP_DIR/selected-kind.txt")"

print "正在下载选中的字幕（不会下载视频或音频）……"

SUB_OPTIONS=(--write-subs)
if [[ "$SUB_KIND" == "automatic" ]]; then
  SUB_OPTIONS=(--write-auto-subs)
fi

if ! run_ytdlp \
  --ignore-config \
  --no-playlist \
  --skip-download \
  --quiet \
  --no-warnings \
  --socket-timeout 20 \
  --retries 3 \
  --extractor-args "youtube:skip=translated_subs" \
  "${SUB_OPTIONS[@]}" \
  --sub-langs "$SUB_PATTERN" \
  --sub-format "json3/vtt/best" \
  -o "$TEMP_DIR/subtitle.%(ext)s" \
  "$VIDEO_URL"; then
  SHORT_ERROR="$(sed -n 's/^ERROR: */ /p' "$ERROR_FILE" | tail -n 1)"
  if [[ -n "$SHORT_ERROR" ]]; then
    fail "字幕下载失败：${SHORT_ERROR# }"
  fi
  fail "字幕下载失败。请检查网络，并尝试运行：brew upgrade yt-dlp"
fi

SUBTITLE_FILE=""
for CANDIDATE in "$TEMP_DIR"/subtitle.*; do
  if [[ -f "$CANDIDATE" ]]; then
    SUBTITLE_FILE="$CANDIDATE"
    break
  fi
done

if [[ -z "$SUBTITLE_FILE" ]]; then
  fail "字幕下载失败：没有收到字幕文件。"
fi

TRANSCRIPT_FILE="$TEMP_DIR/transcript.txt"

# 将 JSON3/VTT/SRT 清理为 UTF-8 纯文本，并合并 YouTube 滚动字幕的重叠内容。
"$PYTHON" - "$SUBTITLE_FILE" "$TRANSCRIPT_FILE" <<'PY'
# CLEANER_PY_START
import html
import json
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

try:
    raw = source_path.read_text(encoding="utf-8-sig", errors="replace")
except Exception:
    raise SystemExit(1)

TAG_RE = re.compile(r"<[^>]*>")
INLINE_TIME_RE = re.compile(r"<\d{1,2}:\d{2}(?::\d{2})?[.,]\d{3}>")
SPACE_RE = re.compile(r"[ \t\r\f\v]+")

def clean_text(value):
    value = html.unescape(str(value))
    value = value.replace("\u200b", "").replace("\ufeff", "").replace("\xa0", " ")
    value = INLINE_TIME_RE.sub("", value)
    value = TAG_RE.sub("", value)
    value = SPACE_RE.sub(" ", value)
    return value.strip()

def smart_join(left, right):
    if not left:
        return right
    if not right:
        return left
    no_space_before = set(",.!?;:%)]}，。！？；：、）》】」』…")
    no_space_after = set("([{（《【「『")
    if right[0] in no_space_before or left[-1] in no_space_after:
        return left + right
    # CJK 字符之间通常不应擅自插入空格。
    if re.match(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", left[-1]) and \
       re.match(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", right[0]):
        return left + right
    return left + " " + right

def merge_overlap(previous, current):
    """返回合并文本；没有明显滚动重叠时返回 None。"""
    p_cmp = previous.casefold()
    c_cmp = current.casefold()
    if p_cmp == c_cmp:
        return previous
    if c_cmp.startswith(p_cmp):
        return previous + current[len(previous):]
    if p_cmp.startswith(c_cmp):
        return previous
    if c_cmp in p_cmp and len(c_cmp) >= max(4, int(len(p_cmp) * 0.45)):
        return previous

    p_words = previous.split()
    c_words = current.split()
    if len(p_words) > 1 or len(c_words) > 1:
        p_fold = [word.casefold() for word in p_words]
        c_fold = [word.casefold() for word in c_words]
        for size in range(min(len(p_words), len(c_words)), 0, -1):
            if p_fold[-size:] != c_fold[:size]:
                continue
            overlap_chars = sum(len(word) for word in c_words[:size])
            if size >= 2 or (min(len(p_words), len(c_words)) == 1 and overlap_chars >= 4):
                tail = " ".join(c_words[size:])
                return smart_join(previous, tail)

    # 无空格语言（中/日/韩等）按字符检查后缀与前缀，至少重叠 2 个字符。
    compact_p = re.sub(r"\s+", "", previous)
    compact_c = re.sub(r"\s+", "", current)
    cjk = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")
    if cjk.search(compact_p) and cjk.search(compact_c):
        p_fold = compact_p.casefold()
        c_fold = compact_c.casefold()
        for size in range(min(len(compact_p), len(compact_c)), 1, -1):
            if p_fold[-size:] == c_fold[:size]:
                return compact_p + compact_c[size:]
    return None

def add_piece(blocks, piece, force_append=False):
    piece = clean_text(piece)
    if not piece:
        return
    if not blocks:
        blocks.append(piece)
        return
    merged = merge_overlap(blocks[-1], piece)
    if merged is not None:
        blocks[-1] = merged
    elif force_append:
        blocks[-1] = smart_join(blocks[-1], piece)
    else:
        blocks.append(piece)

def json3_pieces(data):
    pieces = []
    for event in data.get("events") or []:
        if not isinstance(event, dict):
            continue
        segments = event.get("segs")
        if not isinstance(segments, list):
            continue
        text = "".join(str(seg.get("utf8") or "") for seg in segments if isinstance(seg, dict))
        lines = text.replace("\r", "\n").split("\n")
        first = True
        for line in lines:
            if clean_text(line):
                pieces.append((line, bool(event.get("aAppend")) and first))
                first = False
    return pieces

def timed_text_pieces(text):
    pieces = []
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    for block in re.split(r"\n\s*\n", normalized):
        lines = [line.strip() for line in block.split("\n")]
        if not lines:
            continue
        first = lines[0].lstrip("\ufeff")
        if first.startswith(("WEBVTT", "NOTE", "STYLE", "REGION")):
            continue
        timing_index = next((i for i, line in enumerate(lines) if "-->" in line), None)
        if timing_index is None:
            continue
        for line in lines[timing_index + 1:]:
            if clean_text(line):
                pieces.append((line, False))
    return pieces

pieces = []
try:
    parsed = json.loads(raw)
    if isinstance(parsed, dict) and isinstance(parsed.get("events"), list):
        pieces = json3_pieces(parsed)
except json.JSONDecodeError:
    pass

if not pieces:
    pieces = timed_text_pieces(raw)

blocks = []
for piece, force_append in pieces:
    add_piece(blocks, piece, force_append)

# 再去掉相邻的完全重复行，不改写、不翻译字幕内容。
deduped = []
for line in blocks:
    if not deduped or line.casefold() != deduped[-1].casefold():
        deduped.append(line)

transcript = "\n".join(deduped).strip()
if not transcript:
    raise SystemExit(2)

output_path.write_text(transcript + "\n", encoding="utf-8")
# CLEANER_PY_END
PY
CLEAN_STATUS=$?

if [[ $CLEAN_STATUS -ne 0 || ! -s "$TRANSCRIPT_FILE" ]]; then
  fail "字幕已下载，但无法整理成可用的纯文本。"
fi

umask 077
if ! /bin/cp -- "$TRANSCRIPT_FILE" "$RESULT_FILE"; then
  fail "字幕已经整理完成，但无法写入结果文件。"
fi

exit 0
