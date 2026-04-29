#!/bin/bash
# Daily news digest via WeChat - scrapes websites directly
# Runs from system cron at 8:00 AM

cd /root/.openclaw/workspace

DATE_STR=$(date '+%Y年%m月%d日 %A')

# Fetch domestic news from Sina
python3 << 'PYEOF'
import subprocess, json, re

# Sina news
result = subprocess.run(['node', '-e', '''
const https = require("https");
https.get("https://news.sina.com.cn/", res => {
    let data = "";
    res.on("data", d => data += d);
    res.on("end", () => console.log(data));
}).on("error", e => console.error(e));
'''], capture_output=True, text=True, timeout=15)
html = result.stdout

# Extract Chinese news headlines
titles = set()
# Find links with Chinese titles
pattern = re.findall(r'<a[^>]*href="(https?://[^"]+)"[^>]*>([^<]{6,60})</a>', html)
for url, title in pattern:
    title = title.strip()
    # Filter: must contain Chinese characters, not look like nav/logo text
    if any('\u4e00' <= c <= '\u9fff' for c in title):
        if len(title) >= 6 and len(title) <= 60:
            if not any(x in title for x in ['设为书签', '快捷方式', '手机', '标准版', '智能版', '登录', '注册', '首页', '福彩开奖', '开奖直播', '每日排行', '点击观看']):
                titles.add(title)

# Also try the highlighted items
highlight = re.findall(r'<h2[^>]*>([^<]{6,60})</h2>', html)
for t in highlight:
    if any('\u4e00' <= c <= '\u9fff' for c in t):
        titles.add(t.strip())

cn_titles = list(titles)[:8]
with open('/tmp/news_cn.txt', 'w') as f:
    for t in cn_titles:
        f.write(t + '\n')
print(f"Found {len(cn_titles)} CN headlines")
for t in cn_titles:
    print(f"  ▸ {t}")
PYEOF

# Fetch tech news from 36kr
python3 << 'PYEOF'
import subprocess, re

result = subprocess.run(['node', '-e', '''
const https = require("https");
https.get("https://www.36kr.com/newsflashes", {headers: {"User-Agent": "Mozilla/5.0"}}, res => {
    let data = "";
    res.on("data", d => data += d);
    res.on("end", () => console.log(data));
}).on("error", e => console.error(e));
'''], capture_output=True, text=True, timeout=15)
html = result.stdout

# Extract titles from 36kr
titles = set()
pattern = re.findall(r'<a[^>]*href="/newsflashes/[^"]*"[^>]*>([^<]{6,80})</a>', html)
for t in pattern:
    t = t.strip()
    if any('\u4e00' <= c <= '\u9fff' for c in t):
        titles.add(t)

tech_titles = list(titles)[:5]
with open('/tmp/news_tech.txt', 'w') as f:
    for t in tech_titles:
        f.write(t + '\n')
print(f"Found {len(tech_titles)} tech headlines")
for t in tech_titles:
    print(f"  ▸ {t}")
PYEOF

# Fetch international news from NPR RSS
python3 << 'PYEOF'
import subprocess, re

result = subprocess.run(['node', '-e', '''
const https = require("https");
https.get("https://feeds.npr.org/1001/rss.xml", res => {
    let data = "";
    res.on("data", d => data += d);
    res.on("end", () => console.log(data));
}).on("error", e => console.error(e));
'''], capture_output=True, text=True, timeout=15)
xml = result.stdout

titles = []
pattern = re.findall(r'<title><!\[CDATA\[(.*?)\]\]></title>', xml) or re.findall(r'<title>(.*?)</title>', xml)
for t in pattern:
    t = t.strip()
    if t and t != 'NPR Topics: News' and len(t) > 5:
        t = t.replace('&apos;', "'").replace('&amp;', '&').replace('&quot;', '"').replace('&lt;', '<').replace('&gt;', '>')
        titles.append(t)

intl_titles = titles[:5]
with open('/tmp/news_intl.txt', 'w') as f:
    for t in intl_titles:
        f.write(t + '\n')
print(f"Found {len(intl_titles)} intl headlines")
for t in intl_titles:
    print(f"  ▸ {t}")
PYEOF

# Build and send the message
python3 << 'PYEOF'
import os

def read_lines(filepath):
    try:
        with open(filepath) as f:
            return [l.strip() for l in f if l.strip()]
    except:
        return []

cn = read_lines('/tmp/news_cn.txt')
intl = read_lines('/tmp/news_intl.txt')
tech = read_lines('/tmp/news_tech.txt')

lines = ['🕐 早间新闻速报', '━━━━━━━━━━━━━━━━', '']

lines.append('🇨🇳 国内')
for t in cn[:6]:
    lines.append(f'▸ {t}')
if not cn:
    lines.append('▸ （暂未获取到国内新闻）')

lines.append('')
lines.append('🌍 国际')
for t in intl[:5]:
    lines.append(f'▸ {t}')
if not intl:
    lines.append('▸ （暂未获取到国际新闻）')

lines.append('')
lines.append('📱 科技')
for t in tech[:4]:
    lines.append(f'▸ {t}')
if not tech:
    lines.append('▸ （暂未获取到科技新闻）')

lines.append('')
lines.append('━━━━━━━━━━━━━━━━')
lines.append('每天早八点 Poirot 为您播报 🕵️')

msg = '\n'.join(lines)
with open('/tmp/weixin_news_msg.txt', 'w') as f:
    f.write(msg)
print(msg)
PYEOF

MSG=$(cat /tmp/weixin_news_msg.txt 2>/dev/null)
if [ -z "$MSG" ]; then
    MSG="🕐 早安！今天新闻抓取失败，稍后再试 🕵️"
fi

# Send via OpenClaw CLI
openclaw message send --channel openclaw-weixin --target "o9cq804V0DLhUk0YVzG5cPYl2huQ@im.wechat" --message "$MSG" 2>&1

echo ""
echo "Done at $(date)"
