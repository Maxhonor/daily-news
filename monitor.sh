#!/bin/bash
# Monitor https://yzb.ppsuc.edu.cn/sszs.htm for new updates
# Designed to run on GitHub Actions - always sends notification

STATE_FILE="/tmp/sszs_last_ids.txt"
PREV_FILE="/tmp/sszs_last_ids.txt.prev"

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
    print(json.dumps(new, ensure_ascii=False))
PYEOF
)

    if [ "$NEW_ITEMS" != "NO_UPDATE" ] && [ -n "$NEW_ITEMS" ]; then
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
            -d "{\"token\":\"4b14ad2c8062439f804d3886e8a87d99\",\"title\":\"\U0001f4e2 公大研招网有更新\",\"content\":\"<h3>\U0001f4e2 硕士招生页面有新通知</h3><hr>${CONTENT}<br><hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>\U0001f449 点击查看原文</a>\",\"template\":\"html\"}"
        echo "SENT_UPDATE"
    else
        curl -s -X POST "https://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"4b14ad2c8062439f804d3886e8a87d99\",\"title\":\"\u2705 公大研招网暂无更新\",\"content\":\"<h3>\u2705 硕士招生页面今日暂无新通知</h3><p>最近一条通知日期：$(python3 -c \"import json; d=json.load(open('/tmp/sszs_last_ids.txt')); print(d[0]['date']+'：'+d[0]['title'][:30] if d else '暂无')\")</p><hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>\U0001f449 点击查看原文</a>\",\"template\":\"html\"}"
        echo "SENT_NO_UPDATE"
    fi
else
    # First run - just save state and send initial notification
    curl -s -X POST "https://www.pushplus.plus/send" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"4b14ad2c8062439f804d3886e8a87d99\",\"title\":\"\U0001f4cb 公大研招网监控已启动\",\"content\":\"<h3>\U0001f4cb 公大研招网硕士招生页面监控已启动</h3><p>从今天起每天18:00将推送更新状态。</p><p>当前共 $(python3 -c \"import json; print(len(json.load(open('/tmp/sszs_last_ids.txt'))))\" ) 条通知</p><hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>\U0001f449 点击查看原文</a>\",\"template\":\"html\"}"
    echo "FIRST_RUN"
fi

# Save current as previous for next run
cp "$STATE_FILE" "$PREV_FILE"
