#!/bin/bash
# AI HOT 轮询脚本 — 拉取精选条目，增量推送到飞书/Lark 群
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载配置（优先加载 config.sh，不存在则用 config.sh.example 的值）
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "⚠️  未找到 config.sh，请先复制 config.sh.example 并填入你的配置："
    echo "   cp $SCRIPT_DIR/config.sh.example $SCRIPT_DIR/config.sh"
    exit 1
fi

# 默认值：状态文件和日志放在脚本目录下
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/state.json}"
LOG_FILE="${POLL_LOG:-$SCRIPT_DIR/poll.log}"
API_BASE="${API_BASE:-https://aihot.virxact.com}"
MAX_PER_MESSAGE="${MAX_PER_MESSAGE:-3}"
PAGE_SIZE="${PAGE_SIZE:-50}"
LOOKBACK_HOURS="${LOOKBACK_HOURS:-12}"
MAX_SENT_IDS="${MAX_SENT_IDS:-1000}"
DRY_RUN="${AIHOT_DRY_RUN:-0}"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36 aihot-news/0.3.0"

# macOS mktemp 要求 X 必须在模板末尾才会替换；trap 确保异常退出也清理
cleanup() {
    rm -f "${all_items_json:-}" "${sorted_json:-}"
}
trap cleanup EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ---- 1. 读状态 ----
if [[ -f "$STATE_FILE" ]]; then
    last_published=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('last_published_at',''))")
else
    last_published=$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')
    echo "{\"last_published_at\":\"$last_published\",\"sent_item_ids\":[]}" > "$STATE_FILE"
    log "首次运行，起点: $last_published"
fi

# AI HOT 的 selected 会后补较早 publishedAt 的条目；公开 API 契约要求窗口查询 + 去重。
since_published=$(python3 -c "
ts = '$last_published'
from datetime import datetime, timedelta
dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
dt = dt - timedelta(hours=$LOOKBACK_HOURS)
print(dt.strftime('%Y-%m-%dT%H:%M:%S.') + f'{dt.microsecond // 1000:03d}Z')
")
since_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$since_published', safe=''))")
log "查询窗口: since=$since_published, last_published_at=$last_published"

# ---- 2. 拉取 API ----
all_items_json=$(mktemp /tmp/aihot_items.XXXXXXXXXX)
page=1
cursor=""

while true; do
    if [[ -n "$cursor" ]]; then
        url="${API_BASE}/api/public/items?mode=selected&since=${since_encoded}&take=${PAGE_SIZE}&cursor=${cursor}"
    else
        url="${API_BASE}/api/public/items?mode=selected&since=${since_encoded}&take=${PAGE_SIZE}"
    fi

    resp=$(curl -sH "User-Agent: $UA" "$url")

    if ! echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'items' in d" 2>/dev/null; then
        log "ERROR: API 响应异常，跳过。前200字符: ${resp:0:200}"
        rm -f "$all_items_json"
        exit 0
    fi

    count=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))")
    log "第${page}页: ${count}条"

    if [[ "$count" -eq 0 ]]; then
        break
    fi

    echo "$resp" | python3 -c "
import sys, json
for item in json.load(sys.stdin)['items']:
    print(json.dumps(item, ensure_ascii=False))
" >> "$all_items_json"

    cursor=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('nextCursor',''))")
    has_next=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('hasNext',False)).lower())")
    if [[ "$has_next" != "true" || -z "$cursor" ]]; then
        break
    fi
    page=$((page + 1))
    sleep 0.5
done

# ---- 3. 过滤已发送条目，并按 publishedAt 升序 ----
sorted_json=$(mktemp /tmp/aihot_sorted.XXXXXXXXXX)
python3 - "$STATE_FILE" "$all_items_json" "$sorted_json" <<'PY_STATE_FILTER'
import json
import sys

state_file, all_items_file, sorted_file = sys.argv[1:4]
try:
    with open(state_file) as f:
        state = json.load(f)
except FileNotFoundError:
    state = {}

sent_ids = set(state.get("sent_item_ids") or [])
items = []
with open(all_items_file) as f:
    for line in f:
        if not line.strip():
            continue
        item = json.loads(line)
        if item.get("id") in sent_ids:
            continue
        items.append(item)

items.sort(key=lambda d: (d.get("publishedAt") or "", d.get("id") or ""))
with open(sorted_file, "w") as f:
    for item in items:
        f.write(json.dumps(item, ensure_ascii=False) + "\n")
PY_STATE_FILTER

total=$(wc -l < "$sorted_json" | tr -d ' ')
if [[ "$total" -eq 0 ]]; then
    log "无新增。"
    rm -f "$all_items_json" "$sorted_json"
    exit 0
fi

log "共 ${total} 条新增。"

# ---- 4. 格式化并发送 ----
batch=""
batch_count=0
newest_ts=""
sent_ids_batch=""

while IFS= read -r line; do
    item=$(echo "$line" | python3 -c "
import sys, json
d = json.loads(sys.stdin.readline())
cat_map = {'ai-models':'模型','ai-products':'产品','industry':'行业','paper':'论文','tip':'技巧'}

from datetime import datetime, timezone, timedelta
bj = timezone(timedelta(hours=8))
ts_str = d.get('publishedAt','')
dt = datetime.fromisoformat(ts_str.replace('Z','+00:00'))
bj_dt = dt.astimezone(bj)
time_prefix = f'{bj_dt.month}月{bj_dt.day}日 {bj_dt.hour:02d}:{bj_dt.minute:02d}'

s = d.get('summary','') or ''
short_s = s[:120] + ('…' if len(s) > 120 else '')
print(json.dumps({
    'title': d.get('title',''),
    'source': d.get('source','未知'),
    'cat': cat_map.get(d.get('category',''), d.get('category','未知')),
    'summary': short_s,
    'url': d.get('url',''),
    'ts': d.get('publishedAt',''),
    'time_prefix': time_prefix
}, ensure_ascii=False))
")

    title=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
    source=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['source'])")
    cat=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['cat'])")
    summary=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['summary'])")
    url=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
    ts=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['ts'])")
    time_prefix=$(echo "$item" | python3 -c "import sys,json; print(json.load(sys.stdin)['time_prefix'])")
    item_id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

    newest_ts="$ts"
    sent_ids_batch="${sent_ids_batch}${item_id}
"

    entry="🔹（${time_prefix}）${title}
📂 ${cat} · ${source}
${summary}
🔗 ${url}"

    if [[ $batch_count -eq 0 ]]; then
        batch="$entry"
    else
        batch="${batch}

${entry}"
    fi
    batch_count=$((batch_count + 1))

    if [[ $batch_count -ge $MAX_PER_MESSAGE ]]; then
        log "发送 ${batch_count} 条…"
        if [[ "$DRY_RUN" == "1" ]]; then
            log "DRY_RUN: 跳过发送 ${batch_count} 条。"
        else
            lark-cli im +messages-send --chat-id "$CHAT_ID" --text "$batch" --as bot >> "$LOG_FILE" 2>&1
        fi
        sleep 0.5
        batch=""
        batch_count=0
    fi
done < "$sorted_json"

if [[ $batch_count -gt 0 ]]; then
    log "发送最后 ${batch_count} 条…"
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: 跳过发送最后 ${batch_count} 条。"
    else
        lark-cli im +messages-send --chat-id "$CHAT_ID" --text "$batch" --as bot >> "$LOG_FILE" 2>&1
    fi
fi

# ---- 5. 更新状态 ----
if [[ -n "$newest_ts" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: 跳过状态更新: $newest_ts"
        rm -f "$all_items_json" "$sorted_json"
        log "完成。"
        exit 0
    fi
    python3 - "$STATE_FILE" "$newest_ts" "$MAX_SENT_IDS" <<PY_STATE_UPDATE
import json
import sys
from datetime import datetime, timezone

state_file, newest_ts, max_sent_ids = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    with open(state_file) as f:
        state = json.load(f)
except FileNotFoundError:
    state = {}

def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))

old_ts = state.get("last_published_at")
if old_ts:
    state["last_published_at"] = max(old_ts, newest_ts, key=parse)
else:
    state["last_published_at"] = newest_ts

sent_ids = list(state.get("sent_item_ids") or [])
seen = set(sent_ids)
for item_id in """$sent_ids_batch""".splitlines():
    if item_id and item_id not in seen:
        sent_ids.append(item_id)
        seen.add(item_id)
state["sent_item_ids"] = sent_ids[-max_sent_ids:]
state["sent_item_ids_updated_at"] = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

with open(state_file, "w") as f:
    json.dump(state, f, ensure_ascii=False, separators=(",", ":"))
    f.write("\n")
PY_STATE_UPDATE
    log "状态更新: $newest_ts"
fi

rm -f "$all_items_json" "$sorted_json"
log "完成。"
