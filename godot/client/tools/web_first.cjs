// 웹 첫 실행 재기 (친구가 링크를 처음 열 때): 웹 빌드 폴더를 C# 서버 /play/ 처럼 brotli 미리 압축 (.br) 으로 서빙,
// 크로미움 (Mesa GL) 캐시 끔 + 네트워크 흉내 (기본 10Mbps 내려받기·40ms 지연). 잼: 받은 바이트 (압축), 문서·wasm·pck 다 받은 때,
// 첫 화면 (고도 로딩 막 #status 가 사라진 때), 그 뒤 N 초 동안 프레임 틈 (셰이더 만들기 멈춤 = 긴 프레임)
// 실행: xvfb-run -a node godot/client/tools/web_first.cjs <웹 빌드 폴더> [Mbps=10] [뒤에 잴 초=12] ["?주소 뒤"]
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
(async () => {
  const [dir, mbps = '10', secs = '12', query = ''] = process.argv.slice(2);
  // .br 미리 만들기 (tools/package.mjs 와 같은 설정)
  for (const f of fs.readdirSync(dir)) {
    if (fs.statSync(path.join(dir, f)).isDirectory() || /\.(br|gz|import)$/.test(f) || fs.existsSync(path.join(dir, f + '.br')) && fs.statSync(path.join(dir, f + '.br')).mtimeMs >= fs.statSync(path.join(dir, f)).mtimeMs) continue;
    const d = fs.readFileSync(path.join(dir, f));
    fs.writeFileSync(path.join(dir, f + '.br'), zlib.brotliCompressSync(d, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: d.length } }));
  }
  let sent = 0; // 보낸 바이트 (압축) — 서버 쪽에서 셈 (CDP 는 fetch 로 받는 wasm·pck 를 놓침)
  const done = {}; // 파일 → 다 보낸 때 (ms, 열기부터)
  let t0 = Date.now();
  const srv = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split('?')[0]);
    const f = path.join(dir, u === '/' ? 'index.html' : u);
    if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    const br = /\bbr\b/.test(req.headers['accept-encoding'] || '') && fs.existsSync(f + '.br');
    res.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream', ...(br ? { 'content-encoding': 'br' } : {}), 'cache-control': 'no-store' });
    const src = br ? f + '.br' : f;
    sent += fs.statSync(src).size;
    res.on('finish', () => { done[path.basename(f)] = Date.now() - t0; });
    fs.createReadStream(src).pipe(res);
  }).listen(0);
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  const bps = Number(mbps) * 1e6 / 8;
  if (Number(mbps) > 0) await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 40, downloadThroughput: bps, uploadThroughput: bps });
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  t0 = Date.now();
  await page.goto(`http://127.0.0.1:${srv.address().port}/${query}`);
  if (process.env.LOADSHOT) { // 로딩 화면 스샷 (열고 이 ms 뒤)
    await page.waitForTimeout(Number(process.env.LOADSHOT_MS || 4000));
    await page.screenshot({ path: process.env.LOADSHOT });
  }
  // 첫 화면: 고도 로딩 막 (#status 또는 우리 로딩 #tf-load) 이 사라진 때
  await page.waitForFunction(() => !document.getElementById('status') && !document.getElementById('tf-load'), null, { timeout: 300000, polling: 100 });
  const first = Date.now() - t0;
  const gaps = await page.evaluate((secs) => new Promise((res) => {
    const g = [];
    let last = performance.now();
    const t0 = last;
    const f = (now) => { g.push(now - last); last = now; if (now - t0 < secs * 1000) requestAnimationFrame(f); else res(g); };
    requestAnimationFrame(f);
  }), Number(secs));
  const sorted = [...gaps].sort((a, b) => b - a);
  console.log(JSON.stringify({ mbps: Number(mbps), MB: +(sent / 1e6).toFixed(2), html: done['index.html'], js: done['index.js'], wasm: done['index.wasm'], pck: done['index.pck'], firstScreen: first, frames: gaps.length, avg: +(gaps.reduce((a, b) => a + b, 0) / gaps.length).toFixed(1), worst: sorted.slice(0, 3).map((x) => Math.round(x)), over250: gaps.filter((x) => x > 250).length, errors: logs.filter((l) => /SCRIPT ERROR|SHADER ERROR/.test(l)).length }));
  await browser.close();
  srv.close();
})();
