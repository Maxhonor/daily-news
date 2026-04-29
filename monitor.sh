#!/bin/bash
# Monitor https://yzb.ppsuc.edu.cn/sszs.htm for new updates
# Designed to run on GitHub Actions

STATE_FILE="/tmp/sszs_last_ids.txt"
PREV_FILE="/tmp/sszs_last_ids.txt.prev"
URL="https://yzb.ppsuc.edu.cn/sszs.htm"

# Fetch current articles
ARTICLES=$(python3 << 'PYEOF' 2>/dev/null
import sys, re, json, urllib.request
url = "https://yzb.ppsuc.edu.cn/sszs.htm"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", errors="ignore")
articles = []
matches = re.findall(r'info/1008/(\d+)\.htm[^>]*title="([^"]*)"', html)
dates = re.findall(r'(\d{4}-\d{2}-\d{2})', html)
for i, (aid, title) in enumerate(matches):
    date = dates[i] if i < len(dates) else ""
    articles.append({"id": aid, "title": title.strip(), "date": date})
print(json.dumps(articles, ensure_ascii=False))
PYEOF
)

echo "$ARTICLES" > "$STATE_FILE"

# Compare with previous state
if [ -f "$PREV_FILE" ]; then
    NEW_ITEMS=$(python3 << 'PYEOF'
import json, sys
with open("/tmp/sszs_last_ids.txt") as f:
    current = json.load(f)
with open("/tmp/sszs_last_ids.txt.prev") as f:
    prev = json.load(f)

current_ids = {a["id"] for a in current}
prev_ids = {a["id"] for a in prev}
new_ids = current_ids - prev_ids

if not new_ids:
    print("NO_UPDATE")
else:
    new = [a for a in current if a["id"] in new_ids]
    # Pick only items from today or after the latest prev date
    latest_prev_date = max(a["date"] for a in prev) if prev else ""
    result = []
    for a in new:
        if a["date"] >= latest_prev_date[:7]:  # same month at least
            result.append(a)
    if result:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print("NO_UPDATE")
PYEOF
)

    if [ "$NEW_ITEMS" != "NO_UPDATE" ] && [ -n "$NEW_ITEMS" ]; then
        # Send notification via PushPlus
        CONTENT=$(echo "$NEW_ITEMS" | python3 -c "
import json, sys
items = json.load(sys.stdin)
html = '<ul>'
for item in items:
    html += f'<li><strong>{item[\"date\"]}</strong>：{item[\"title\"]}</li>'
html += '</ul>'
print(html)
")
        curl -s -X POST "https://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"4b14ad2c8062439f804d3886e8a87d99\",\"title\":\"📢 公大研招网有更新\",\"content\":\"<h3>📢 硕士招生页面有新通知</h3><hr>${CONTENT}<br><hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>👉 点击查看原文</a>\",\"template\":\"html\"}"
        echo "SENT_UPDATE"
    else:
        echo "NO_UPDATE"
else:
    echo "FIRST_RUN - saved initial state"
fi

# Save current as previous for next run
cp "$STATE_FILE" "$PREV_FILE"
