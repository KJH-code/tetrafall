// 웹 안정성 시험 (W50): 웹 내보내기를 크로미움에서 열어 (1) Opts 쿼리 (?old-gait=1 ?no-ext=1 ?ext=1 …) 마다 콘솔 에러 없이 판이 도는지 (2) 자동 조종 연속 판을 N분 돌리며 CDP Performance.getMetrics (JS 힙·DOM 노드) 추세와 콘솔 에러 수.
// 미리: JS 서버 (PORT=3000 node server/index.js) + 웹 내보내기 서빙 (WEB_PORT=8060 node godot/client/tools/serve_web.mjs 8060)
// 실행: xvfb-run -a node godot/client/tools/web_soak.cjs <분(기본 5)> [쿼리 하나만]
const { chromium } = require('playwright');

const MIN = Number(process.argv[2] || 5);
const only = process.argv[3];
const base = `http://127.0.0.1:${process.env.WEB_PORT || 8060}/`;
const server = `ws://127.0.0.1:${process.env.SERVER_PORT || 3000}`;

async function run(query, ms, sample) {
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable');
  const errs = {};
  let lines = 0, joined = false, rounds = 0;
  page.on('console', (m) => {
    lines++;
    const t = m.text();
    if (t.includes('들어옴')) joined = true;
    if (/판 \d+ 끝/.test(t)) rounds++;
    if (m.type() === 'error' || /SCRIPT ERROR|ERROR:|Uncaught/.test(t)) { const k = t.replace(/\d+/g, '#').slice(0, 100); errs[k] = (errs[k] || 0) + 1; }
  });
  page.on('pageerror', (e) => { const k = 'pageerror ' + String(e).slice(0, 100); errs[k] = (errs[k] || 0) + 1; });
  page.on('crash', () => { errs.CRASH = 1; });
  await page.goto(`${base}?server=${server}&${query}`, { waitUntil: 'load' });
  const rows = [];
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    await page.waitForTimeout(sample ? 15000 : Math.min(ms, 30000));
    const m = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
    rows.push([Math.round((Date.now() - t0) / 1000), Math.round(m.JSHeapUsedSize / 1048576), m.Nodes, lines, rounds]);
  }
  await browser.close();
  return { rows, errs, joined, lines, rounds };
}

(async () => {
  const queries = ['auto=host&bots=3&wait-players=4&quit-after-rounds=999', 'auto=host&bots=3&wait-players=4&old-gait=1&quit-after-rounds=999', 'auto=host&bots=3&wait-players=4&no-ext=1&quit-after-rounds=999', 'auto=host&bots=3&wait-players=4&ext=1&quit-after-rounds=999', 'auto=host&bots=3&wait-players=4&no-tex-prefetch=1&no-entry-split=1&no-prewarm-sched=1&quit-after-rounds=999'];
  if (!only) {
    for (const q of queries) {
      const r = await run(q, 45000, false);
      console.log(`쿼리 ${q.replace('&quit-after-rounds=999', '')}: 방 들어옴 ${r.joined} · 콘솔 ${r.lines}줄 · 에러 ${JSON.stringify(r.errs)}`);
    }
  }
  const q = only || queries[0];
  const r = await run(q, MIN * 60000, true);
  console.log(`연속 ${MIN}분 (${q}): 초 | JS 힙 MB | DOM 노드 | 콘솔 줄 | 끝난 판`);
  for (const x of r.rows) console.log(x.join(' | '));
  console.log('에러', JSON.stringify(r.errs), '· 방 들어옴', r.joined);
})();
