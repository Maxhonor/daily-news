#!/bin/bash
# Monitor https://yzb.ppsuc.edu.cn/sszs.htm for new updates
# Always sends notification via PushPlus

STATE_FILE="/tmp/sszs_ids.txt"
PREV_FILE="/tmp/sszs_ids_prev.txt"

# Step 1: Fetch current articles
python3 << 'PYEOF'
import json, re, urllib.request
url = "https://yzb.ppsuc.edu.cn/sszs.htm"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", errors="ignore")
articles = []
matches = re.findall(r'info/1008/(\d+)\.htm[^>]*title="([^"]*)"', html)
dates = re.findall(r'(\d{4}-\d{2}-\d{2})', html)
for i, (aid, title) in enumerate(matches):
    date = dates[i] if i < len(dates) else ""
    articles.append({"id": aid, "title": title.strip(), "date": date})
with open("/tmp/sszs_ids.txt", "w") as f:
    json.dump(articles, f, ensure_ascii=False)
PYEOF

# Step 2: Compare and send notification via Python
python3 << 'PYEOF'
import json, os, urllib.request

TOKEN = "4b14ad2c8062439f804d3886e8a87d99"

with open("/tmp/sszs_ids.txt") as f:
    current = json.load(f)

if not os.path.exists("/tmp/sszs_ids_prev.txt"):
    body = "<h3>硕士招生页面监控已启动</h3>"
    body += "<p>从今天起每天18:00将推送更新状态。</p>"
    body += f"<p>当前共 {len(current)} 条通知</p>"
    if current:
        body += f"<p>最近: {current[0]['date']} {current[0]['title'][:40]}</p>"
    body += "<hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>点击查看原文</a>"
    payload = json.dumps({"token": TOKEN, "title": "[监控] 公大研招网监控已启动", "content": body, "template": "html"}, ensure_ascii=False)
    req = urllib.request.Request("https://www.pushplus.plus/send", data=payload.encode(), headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req)
    print("FIRST_RUN - sent startup notification")
else:
    with open("/tmp/sszs_ids_prev.txt") as f:
        prev = json.load(f)
    cur_ids = {a["id"] for a in current}
    prev_ids = {a["id"] for a in prev}
    new_ids = cur_ids - prev_ids
    if new_ids:
        new_items = [a for a in current if a["id"] in new_ids]
        items_html = "<ul>"
        for item in new_items:
            items_html += f"<li><strong>{item['date']}</strong>：{item['title']}</li>"
        items_html += "</ul>"
        body = f"<h3>硕士招生页面有新通知</h3><hr>{items_html}<hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>点击查看原文</a>"
        payload = json.dumps({"token": TOKEN, "title": "[更新] 公大研招网有更新", "content": body, "template": "html"}, ensure_ascii=False)
        req = urllib.request.Request("https://www.pushplus.plus/send", data=payload.encode(), headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req)
        print("HAS_UPDATE - sent update notification")
    else:
        body = "<h3>硕士招生页面今日暂无新通知</h3>"
        if current:
            body += f"<p>最近一条：{current[0]['date']} {current[0]['title'][:40]}</p>"
        body += "<hr><a href='https://yzb.ppsuc.edu.cn/sszs.htm'>点击查看原文</a>"
        payload = json.dumps({"token": TOKEN, "title": "[每日] 公大研招网暂无更新", "content": body, "template": "html"}, ensure_ascii=False)
        req = urllib.request.Request("https://www.pushplus.plus/send", data=payload.encode(), headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req)
        print("NO_UPDATE - sent daily status")
PYEOF

# Step 3: Save state for next run
cp "$STATE_FILE" "$PREV_FILE"
