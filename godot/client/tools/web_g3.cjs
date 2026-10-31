// G3 웹 판 셰이더 점검: g3_demo 를 주 장면으로 내보낸 웹 판을 크로미움 (Mesa, web_shot.cjs 와 같은 설정) 에서 열어 경우마다 스샷 + 콘솔 오류 모음.
// 내보내기: 프로젝트를 복사해 run/main_scene 만 res://shaders/demo/g3_demo.tscn 으로 바꾸고 --export-release Web <폴더>/index.html
// 실행 (레포 뿌리): xvfb-run -a node godot/client/tools/web_g3.cjs <웹 판 폴더> <스샷 폴더> "이름|--theme crystal --terrain" …
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
(async () => {
  const [dir, out, ...cases] = process.argv.slice(2);
  const srv = http.createServer((req, res) => {
    const f = path.join(dir, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
    if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  }).listen(0);
  const port = srv.address().port;
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const report = [];
  for (const c of cases) {
    const [name, args] = c.split('|');
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    const errs = [];
    let ready = false;
    page.on('console', (m) => {
      const t = m.text();
      if (t.includes('G3_READY')) ready = true;
      if (/error|SHADER|failed/i.test(t)) errs.push(t.slice(0, 300));
    });
    page.on('pageerror', (e) => errs.push('pageerror ' + e.message));
    const t0 = Date.now();
    await page.goto(`http://127.0.0.1:${port}/?args=${encodeURIComponent(args)}`);
    while (!ready && Date.now() - t0 < 60000) await page.waitForTimeout(200);
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(out, `web_${name}.png`) });
    report.push({ name, ready, ms: Date.now() - t0, errors: errs });
    await page.close();
  }
  console.log(JSON.stringify(report, null, 1));
  await browser.close();
  srv.close();
})();
