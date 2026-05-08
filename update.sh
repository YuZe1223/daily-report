#!/bin/bash
# Daily ranking update script
# Usage: bash update.sh
set -e

CHROME_CDP="--cdp 9222"
DATA_DIR="data"
TODAY=$(date +%Y-%m-%d)

echo "=== 抖音爆款榜日报更新 ==="
echo "日期: $TODAY"

# Step 1: Navigate to ranking page
echo "[1/6] 打开榜单页..."
agent-browser $CHROME_CDP open "https://buyin.jinritemai.com/dashboard/merch-picking-hall/rank"
sleep 3

# Step 2: Click 爆款榜 → 昨日 → 直播
echo "[2/6] 设置筛选条件..."
REFS=$(agent-browser $CHROME_CDP snapshot -i 2>&1)
BK_REF=$(echo "$REFS" | grep "爆款榜" | head -1 | grep -oP 'ref=e\d+' | head -1 | cut -d= -f2)
YS_REF=$(echo "$REFS" | grep "昨日" | head -1 | grep -oP 'ref=e\d+' | head -1 | cut -d= -f2)
ZB_REF=$(echo "$REFS" | grep "直播"  | head -1 | grep -oP 'ref=e\d+' | head -1 | cut -d= -f2)
agent-browser $CHROME_CDP click @$BK_REF && sleep 1
agent-browser $CHROME_CDP click @$YS_REF && sleep 1
agent-browser $CHROME_CDP click @$ZB_REF && sleep 1
# Scroll internal table container to load all 20 rows
agent-browser $CHROME_CDP eval "
(function() {
  var p = document.querySelector('.auxo-table');
  while (p && p.scrollHeight <= p.clientHeight) p = p.parentElement;
  if (p) p.scrollTop = p.scrollHeight;
})()
"
sleep 3

# Step 3: Extract data
echo "[3/6] 提取榜单数据..."
agent-browser $CHROME_CDP eval '
(async function() {
  const apiUrl = "https://buyin.jinritemai.com/pc/leaderboard/center/pmt?rank_type=pay_prod_qty_cnt&industry_id=all&prod_mesh=all&date_type=1d&genre_type=live&alli_cate_id=all&is_flagship=0";
  const resp = await fetch(apiUrl, {credentials: "include"});
  const json = await resp.json();
  const apiItems = json.data.promotions.slice(0, 20);

  const rows = document.querySelectorAll("table tbody tr");
  const result = [];
  rows.forEach(function(tr, i) {
    if (i >= 20) return;
    const tds = tr.querySelectorAll("td");
    if (tds.length < 5) return;
    const api = apiItems[i] || {};
    const sales = tds[3]?.textContent?.trim() || "";
    const comm = tds[4]?.textContent?.trim() || "";
    // Calculate unit price
    const rateMatch = comm.match(/(\d+)%/);
    const feeMatch = comm.match(/¥([\d.]+)/);
    const rate = rateMatch ? parseInt(rateMatch[1]) : 0;
    const fee = feeMatch ? parseFloat(feeMatch[1]) : 0;
    const unitPrice = rate > 0 ? fee / (rate / 100) : 0;
    result.push({
      rank: String(i+1),
      title: api.title || "",
      detail_url: api.detail_url || "",
      product_id: api.product_id || "",
      sales: sales,
      commission: comm,
      cos_ratio: rate,
      cos_fee: Math.round(fee * 100),
      unit_price: Math.round(unitPrice * 100) / 100,
      shop_name: api.shop_name || "",
      cover: api.cover?.url_list?.[0] || "",
    });
  });
  return JSON.stringify(result);
})()
' > /tmp/ranking_new.json 2>&1

# Step 4: Save data
echo "[4/6] 保存数据..."
python3 -c "
import json, os
raw = open('/tmp/ranking_new.json').read().strip()
data = json.loads(json.loads(raw))

record = {
    'date': '$TODAY',
    'title': f'抖音直播带货 · 爆款榜日报 $TODAY',
    'source': '巨量百应 爆款榜 (昨日/直播)',
    'products': data,
}

os.makedirs('$DATA_DIR', exist_ok=True)
with open(f'$DATA_DIR/$TODAY.json', 'w', encoding='utf-8') as f:
    json.dump(record, f, ensure_ascii=False, indent=2)
print(f'  Saved $TODAY.json ({len(data)} products)')

# Update all.json
try:
    with open(f'$DATA_DIR/all.json', 'r', encoding='utf-8') as f:
        all_data = json.load(f)
except:
    all_data = {}
all_data['$TODAY'] = record
with open(f'$DATA_DIR/all.json', 'w', encoding='utf-8') as f:
    json.dump(all_data, f, ensure_ascii=False, indent=2)
print(f'  Updated all.json ({len(all_data)} dates)')
"

# Step 5: Git commit
echo "[5/6] 提交到 Git..."
git add $DATA_DIR/
git commit -m "Add ranking data for $TODAY" || echo "  (no changes to commit)"

# Step 6: Push
echo "[6/6] 推送到 GitHub Pages..."
git push origin main

echo "=== 完成! ==="
echo "访问: https://yuze1223.github.io/daily-report/"
echo "数据: $DATA_DIR/$TODAY.json"
