#!/bin/bash
# Daily news digest via WeChat
export TAVILY_API_KEY="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"

cd /root/.openclaw/workspace

# Search domestic news (Chinese keywords)
python3 /root/.openclaw/workspace/skills/tavily/scripts/tavily_search.py "今日中国重要新闻 2026年4月" --topic news --max-results 5 --depth basic --json > /tmp/news_cn.json 2>/dev/null

# Search international news (English keywords)
python3 /root/.openclaw/workspace/skills/tavily/scripts/tavily_search.py "breaking news today world 2026" --topic news --max-results 5 --depth basic --json > /tmp/news_intl.json 2>/dev/null

# Compile and send
python3 -c "
import json, os

with open('/tmp/news_cn.json') as f: cn = json.load(f)
with open('/tmp/news_intl.json') as f: intl = json.load(f)

msg = '🕐 早间新闻速报 | ' + os.popen('date \"+%Y年%m月%d日 %A\"').read().strip() + '\n'
msg += '━━━━━━━━━━━━━━━━\n\n'

msg += '🇨🇳 国内\n'
for r in cn.get('results', [])[:5]:
    title = r.get('title', '')
    if len(title) > 40: title = title[:40] + '...'
    msg += f'▸ {title}\n'

msg += '\n🌍 国际\n'
for r in intl.get('results', [])[:5]:
    title = r.get('title', '')
    if len(title) > 40: title = title[:40] + '...'
    msg += f'▸ {title}\n'

if cn.get('answer'):
    msg += f'\n📝 摘要：{cn[\"answer\"][:200]}\n'

msg += '\n━━━━━━━━━━━━━━━━\n每天早八点 Poirot 为您播报 🕵️'

# Write message to a file for sending
with open('/tmp/weixin_news_message.txt', 'w') as f:
    f.write(msg)

print(msg)
"
