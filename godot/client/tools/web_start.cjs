// 웹 시작 시간 재기 (W53): 웹 빌드를 brotli 미리 압축 서빙 (+ 선택 네트워크 흉내) 으로 열고, 시간표를 모음:
//   html·js·wasm·pck 다 받은 때 · 엔진 켜기 (콘솔 [켜기] 줄, ?boot-log) · 첫 화면 (로딩 막 사라짐) · 메뉴 (?auto 없이 = 타이틀/메뉴 그려진 뒤 프레임 안정)
//   · 방 입장 (?auto=host 면 '들어옴' 콘솔) · 프레임 틈 큰 것 (rAF 간격 > 임계)
// 실행: xvfb-run -a node godot/client/tools/web_start.cjs <웹 빌드 폴더> [Mbps=0] [뒤에 잴 초=10] [임계 ms=150] ["?주소 뒤"]
//   기본 주소 뒤 = ?boot-log  (방 입장까지 재려면 "?boot-log&server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=99", JS 서버 필요)
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ogg': 'audio/ogg' };
(async () => {
  const [dir, mbps = '0', secs = '10', thr = '150', query = '?boot-log'] = process.argv.slice(2);
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory() || /\.(br|gz|import)$/.test(f) || (fs.existsSync(full + '.br') && fs.statSync(full + '.br').mtimeMs >= fs.statSync(full).mtimeMs)) continue;
    const d = fs.readFileSync(full);
    fs.writeFileSync(full + '.br', zlib.brotliCompressSync(d, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: Number(process.env.WEB_BRQ || 11), [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: d.length } }));
  }
  let sent = 0;
  const done = {};
  const reqs = [];
  let t0 = Date.now();
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split('?')[0]);
    const f = path.join(dir, u === '/' ? 'index.html' : u);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    const br = /\bbr\b/.test(req.headers['accept-encoding'] || '') && fs.existsSync(f + '.br');
    res.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream', ...(br ? { 'content-encoding': 'br' } : {}), 'cache-control': 'no-store' });
    const src = br ? f + '.br' : f;
    sent += fs.statSync(src).size;
    const start = Date.now() - t0;
    res.on('finish', () => { done[path.basename(f)] ||= Date.now() - t0; reqs.push([path.basename(f), start, Date.now() - t0, fs.statSync(src).size]); });
    fs.createReadStream(src).pipe(res);
  }).listen(0);
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  if (Number(mbps) > 0) { const bps = Number(mbps) * 1e6 / 8; await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 40, downloadThroughput: bps, uploadThroughput: bps }); }
  await page.addInitScript((thr) => {
    window.__gaps = [];
    let last = performance.now();
    const f = (now) => { if (now - last > thr) window.__gaps.push([Math.round(last), Math.round(now - last)]); last = now; requestAnimationFrame(f); };
    requestAnimationFrame(f);
  }, Number(thr));
  const boot = [];
  const logs = [];
  const marks = {};
  page.on('console', (m) => {
    const t = m.text();
    logs.push(t);
    if (t.startsWith('[켜기]')) boot.push(t.replace('[켜기]', '').trim());
    const now = Date.now() - t0;
    if (t.includes('들어옴') && marks.joined == null) marks.joined = now;
  });
  t0 = Date.now();
  await page.goto(`http://127.0.0.1:${srv.address().port}/${query}`);
  await page.waitForFunction(() => !document.getElementById('status') && !document.getElementById('tf-load'), null, { timeout: 300000, polling: 50 });
  marks.firstScreen = Date.now() - t0;
  await page.waitForTimeout(Number(secs) * 1000);
  const gaps = await page.evaluate(() => window.__gaps);
  const totalGap = gaps.reduce((a, g) => a + g[1], 0);
  console.log(JSON.stringify({
    mbps: Number(mbps), MB: +(sent / 1e6).toFixed(2), recv: { html: done['index.html'], js: done['index.js'], wasm: done['index.wasm'], pck: done['index.pck'] }, ...marks,
    boot, gapsN: gaps.length, gapsMs: totalGap, worst: gaps.map((g) => g[1]).sort((a, b) => b - a).slice(0, 5),
    gaps: gaps.map((g) => g.join('@')).slice(0, 14), reqs: reqs.length, errors: logs.filter((l) => /SCRIPT ERROR|SHADER ERROR/.test(l)).length,
  }));
  if (process.env.WEB_LOGS) fs.writeFileSync(process.env.WEB_LOGS, logs.join('\n'));
  await browser.close();
  srv.close();
})();
