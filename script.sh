#!/bin/bash
# Morning news - GitHub Actions
# Features: Chinese news + translated international news
# Push: WeChat (PushPlus) + HarmonyOS negative screen (today-task)

set -e

# Step 1: Fetch Sina News
curl -sL "https://news.sina.com.cn/" -o /tmp/sina.html 2>/dev/null
python3 << 'PYEOF'
import re
with open("/tmp/sina.html") as f: h = f.read()
ts = set()
bad = ["书签","快捷","标准","智能","登录","注册","首页","排行","开奖"]
for m in re.findall(r'<a[^>]*>([^<]{8,60})</a>', h):
    t = m.strip()
    if any("\u4e00" <= c <= "\u9fff" for c in t) and len(t) >= 6 and not any(x in t for x in bad):
        ts.add(t)
with open("/tmp/cn.txt", "w") as f:
    for t in list(ts)[:6]: f.write(f"- {t}\n")
print(f"国内: {len(ts)} topics found")
PYEOF

# Step 2: Fetch NPR international news
curl -sL "https://feeds.npr.org/1001/rss.xml" -o /tmp/npr.xml 2>/dev/null
python3 << 'PYEOF'
import re
with open("/tmp/npr.xml") as f: x = f.read()
ts = []
for m in re.findall(r"<title>(.*?)</title>", x):
    t = m.strip().replace("&apos;", "'").replace("&amp;", "&")
    if t and t != "NPR Topics: News" and len(t) > 5: ts.append(t)
with open("/tmp/intl_en.txt", "w") as f:
    for t in ts[:5]: f.write(t + "\n")
print(f"国际英文: {len(ts)} topics found")
for t in ts[:5]: print(f"  ▸ {t}")
PYEOF

# Step 3: Translate international news to Chinese using Qwen
python3 << 'PYEOF'
import json, urllib.request, os

DASHSCOPE_KEY = os.environ.get("DASHSCOPE_API_KEY", "sk-22ab95e18a574fcb9a5b126639103a64")

# Read English headlines
with open("/tmp/intl_en.txt") as f:
    lines = [l.strip() for l in f if l.strip()]
    lines = lines[:5]

if not lines:
    with open("/tmp/intl.txt", "w") as f:
        f.write("- 暂无\n")
    print("国际新闻为空，跳过翻译")
else:
    en_text = "\n".join(f"{i+1}. {t}" for i, t in enumerate(lines))
    prompt = f"""请将以下英文新闻标题翻译成简洁的中文，每条一行：
{en_text}

要求：
- 每条翻译成中文新闻标题风格
- 保留关键信息
- 专业、简洁
- 直接输出翻译结果，不要编号，不要多余说明"""

    data = json.dumps({
        "model": "qwen-turbo-latest",
        "input": {"messages": [{"role": "user", "content": prompt}]}
    }, ensure_ascii=False).encode()
    req = urllib.request.Request(
        "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation",
        data=data,
        headers={"Authorization": f"Bearer {DASHSCOPE_KEY}", "Content-Type": "application/json"}
    )
    resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    translated = resp["output"]["choices"][0]["message"]["content"].strip()
    print(f"翻译结果:\n{translated}")

    with open("/tmp/intl.txt", "w") as f:
        for line in translated.split("\n"):
            line = line.strip()
            if line and not line.startswith("#"):
                f.write(f"- {line.lstrip('-0123456789. ')}\n")

# Step 4: Fetch 36kr tech news
curl -sL "https://www.36kr.com/newsflashes" -H "User-Agent: Mozilla/5.0" -o /tmp/36kr.html 2>/dev/null
python3 << 'PYEOF'
import re
with open("/tmp/36kr.html") as f: h = f.read()
ts = set()
for m in re.findall(r'<a[^>]*href="/newsflashes/[^"]*"[^>]*>([^<]{6,80})</a>', h):
    t = m.strip()
    if any("\u4e00" <= c <= "\u9fff" for c in t): ts.add(t)
with open("/tmp/tech.txt", "w") as f:
    for t in list(ts)[:4]: f.write(f"- {t}\n")
PYEOF

# Step 5: Build markdown content and push to negative screen + PushPlus
python3 << 'PYEOF'
import json, urllib.request, time

TOKEN = "4b14ad2c8062439f804d3886e8a87d99"
AUTH_CODE = "mfO5YSCg6Ll2"

def read_lines(path):
    try:
        with open(path) as f: return [l.strip() for l in f if l.strip()]
    except: return []

cn = read_lines("/tmp/cn.txt")
intl = read_lines("/tmp/intl.txt")
tech = read_lines("/tmp/tech.txt")

# Build markdown for negative screen
md = "# 🕐 早间新闻速报\n\n"
md += "## 🇨🇳 国内\n\n"
for t in cn[:6]: md += f"{t}\n"
if not cn: md += "- 暂无\n"
md += "\n## 🌍 国际\n\n"
for t in intl[:5]: md += f"{t}\n"
if not intl: md += "- 暂无\n"
md += "\n## 📱 科技\n\n"
for t in tech[:4]: md += f"{t}\n"
if not tech: md += "- 暂无\n"
md += "\n---\n\n_每天早八点 Poirot 为您播报 🕵️_"

# Push to HarmonyOS negative screen
push_url = "https://hiboard-claw-drcn.ai.dbankcloud.cn/distribution/message/cloud/claw/msg/upload"
task_data = {
    "authCode": AUTH_CODE,
    "msgContent": [{
        "scheduleTaskId": "morning_news_daily",
        "scheduleTaskName": "早间新闻速报",
        "summary": "早间新闻速报任务已完成",
        "result": "任务已完成",
        "content": md,
        "source": "OpenClaw",
        "taskFinishTime": int(time.time())
    }]
}
req1 = urllib.request.Request(push_url, data=json.dumps(task_data, ensure_ascii=False).encode(),
    headers={"Content-Type": "application/json"})
try:
    resp1 = json.loads(urllib.request.urlopen(req1, timeout=10).read())
    print(f"负一屏推送: {resp1.get('desc', resp1.get('code','OK'))}")
except Exception as e:
    print(f"负一屏推送失败: {e}")

# Build HTML for PushPlus (WeChat)
cn_html = "".join(f"<p>{t}</p>" for t in cn[:6])
intl_html = "".join(f"<p>{t}</p>" for t in intl[:5])
tech_html = "".join(f"<p>{t}</p>" for t in tech[:4])

body = f"<h3>🕐 早间新闻速报</h3><hr><h4>🇨🇳 国内</h4>{cn_html}<hr><h4>🌍 国际（翻译）</h4>{intl_html}<hr><h4>📱 科技</h4>{tech_html}<hr><p>每天早八点 Poirot 为您播报 🕵️</p>"
payload = json.dumps({"token": TOKEN, "title": "🕐 早间新闻速报", "content": body, "template": "html"}, ensure_ascii=False)
req2 = urllib.request.Request("https://www.pushplus.plus/send", data=payload.encode(), headers={"Content-Type": "application/json"})
urllib.request.urlopen(req2)
print("PushPlus推送: 成功")
PYEOF

echo "Done"
