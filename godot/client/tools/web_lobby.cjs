// 웹 첫 대기실·첫 판 멈춤 재기 (W36 2026-11-09): 웹 빌드를 web_first.cjs 와 같은 방식으로 (brotli 미리 압축 서빙 + 네트워크 흉내) 열고,
// 자동 조종 (?server=…&auto=host&bots=3) 으로 방 입장 → 시작까지 가면서 프레임 틈이 큰 순간 (rAF 간격 > 임계, 기본 100ms) 을 단계별로 모음:
// 단계 = 켜기~입장 (wasm 컴파일·엔진 켜기·첫 셰이더) · 대기실 (입장~시작) · 판 (시작 뒤). 대기실만 보려면 주소에 wait-players=99. 셰이더 컴파일은 소프트웨어 렌더 (llvmpipe) 라 PC 보다 훨씬 느림 — 대략만.
// 미리: 게임 서버 (JS: PORT=3000 npm start). 실행: xvfb-run -a node godot/client/tools/web_lobby.cjs <웹 빌드 폴더> [Mbps=0] [판 뒤 잴 초=8] [임계 ms=100] ["?주소 뒤"]
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ogg': 'audio/ogg' };
(async () => {
  const [dir, mbps = '0', secs = '8', thr = '100', query = '?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4'] = process.argv.slice(2);
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory() || /\.(br|gz|import)$/.test(f) || (fs.existsSync(full + '.br') && fs.statSync(full + '.br').mtimeMs >= fs.statSync(full).mtimeMs)) continue;
    const d = fs.readFileSync(full);
    fs.writeFileSync(full + '.br', zlib.brotliCompressSync(d, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: d.length } }));
  }
  let sent = 0;
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split('?')[0]);
    const f = path.join(dir, u === '/' ? 'index.html' : u);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    const br = /\bbr\b/.test(req.headers['accept-encoding'] || '') && fs.existsSync(f + '.br');
    res.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream', ...(br ? { 'content-encoding': 'br' } : {}), 'cache-control': 'no-store' });
    sent += fs.statSync(br ? f + '.br' : f).size;
    fs.createReadStream(br ? f + '.br' : f).pipe(res);
  }).listen(0);
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  if (Number(mbps) > 0) { const bps = Number(mbps) * 1e6 / 8; await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 40, downloadThroughput: bps, uploadThroughput: bps }); }
  await page.addInitScript((thr) => { // 프레임 틈 기록 (페이지 시계 = 열기부터)
    window.__gaps = [];
    let last = performance.now();
    const f = (now) => { if (now - last > thr) window.__gaps.push([Math.round(last), Math.round(now - last)]); last = now; requestAnimationFrame(f); };
    requestAnimationFrame(f);
  }, Number(thr));
  const marks = {};
  const logs = [];
  page.on('console', (m) => {
    const t = m.text();
    const now = Date.now() - t0;
    logs.push(t);
    if (t.includes('들어옴') && marks.joined == null) marks.joined = now;
    if (/시작 \(\d+명\)/.test(t) && marks.started == null) marks.started = now;
  });
  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${srv.address().port}/${query}`);
  await page.waitForFunction(() => !document.getElementById('status') && !document.getElementById('tf-load'), null, { timeout: 300000, polling: 100 });
  marks.firstScreen = Date.now() - t0;
  const dl = Date.now() + 120000;
  const lobbyOnly = query.includes('wait-players=99'); // 시작 안 하고 대기실에만 머묾 (대기실 멈춤만 재기)
  while (marks.started == null && !(lobbyOnly && marks.joined != null) && Date.now() < dl) await page.waitForTimeout(200);
  await page.waitForTimeout(Number(secs) * 1000);
  const gaps = await page.evaluate(() => window.__gaps);
  // 페이지 시계와 node 시계의 차 (열기 직후 페이지 시계 0 근처) — 단계 경계는 대략이라 100ms 안팎 오차
  // 자동 조종은 로딩 막이 걷히기 전에 이미 방에 들어갈 수 있어서 (firstScreen 은 따로 보고) 단계는 입장·시작 시각으로만 나눔
  const phase = (t) => (marks.joined == null || t < marks.joined ? '켜기~입장' : marks.started == null || t < marks.started ? '대기실' : '판');
  const out = {};
  for (const [t, g] of gaps) { const p = phase(t); (out[p] ||= []).push(g); }
  const sum = Object.fromEntries(Object.entries(out).map(([p, a]) => [p, { n: a.length, sumMs: a.reduce((x, y) => x + y, 0), worst: a.sort((x, y) => y - x).slice(0, 4) }]));
  console.log(JSON.stringify({ mbps: Number(mbps), thrMs: Number(thr), MB: +(sent / 1e6).toFixed(2), ...marks, gaps: sum, errors: logs.filter((l) => /SCRIPT ERROR|SHADER ERROR/.test(l)).length }));
  await browser.close();
  srv.close();
})();
