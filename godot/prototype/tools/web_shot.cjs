// 브라우저(Playwright 크로미움)로 웹 내보내기를 열어 서버에 붙고: 첫 로딩 시간을 재고 화면을 찍음.
// 미리: 고도 서버 (--server --port 3101) + node godot/prototype/tools/serve_web.mjs 8060 (+ 원하면 헤드리스 봇 클라)
// 실행: WEB_GL=mesa xvfb-run -a node godot/prototype/tools/web_shot.cjs [저장 폴더]  (기본 SwiftShader 는 고도 화면이 깨져 보임)
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const out = process.argv[2] || '.';
  // GL 경로: 기본 SwiftShader (크로미움 소프트웨어 WebGL). WEB_GL=mesa 면 xvfb 위 창 모드 + ANGLE→데스크톱 GL(Mesa llvmpipe)
  const mesa = process.env.WEB_GL === 'mesa';
  const browser = await chromium.launch({
    headless: !mesa,
    args: mesa ? ['--use-angle=gl', '--ignore-gpu-blocklist', '--enable-gpu'] : ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  let t0 = 0;
  const marks = {};
  page.on('console', (m) => {
    const t = Date.now() - t0;
    logs.push(`${t}ms ${m.text()}`);
    if (m.text().includes('내 id') && !marks.welcome) marks.welcome = t;
    if (m.text().includes('첫 스냅샷') && !marks.first) marks.first = t;
  });
  t0 = Date.now();
  await page.goto('http://127.0.0.1:8060/?server=ws://127.0.0.1:3101&bot', { waitUntil: 'load' });
  marks.load = Date.now() - t0;
  for (let i = 0; i < 600 && !marks.first; i++) await page.waitForTimeout(50);
  await page.waitForTimeout(Number(process.env.SHOT_WAIT || 6000)); // 판이 좀 진행되게
  await page.screenshot({ path: path.join(out, 'godot-web-1.png') });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: path.join(out, 'godot-web-2.png') });
  const fps = await page.evaluate(() => new Promise((r) => { let n = 0; const s = performance.now(); const f = () => { n++; if (performance.now() - s < 2000) requestAnimationFrame(f); else r(n / 2); }; requestAnimationFrame(f); }));
  const gl = await page.evaluate(() => { const c = document.createElement('canvas').getContext('webgl2'); const d = c && c.getExtension('WEBGL_debug_renderer_info'); return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'webgl2 ' + !!c; });
  console.log(JSON.stringify({ ...marks, fps, gl }, null, 1));
  console.log(logs.filter((l) => !l.includes('밀치기')).slice(0, 25).join('\n'));
  await browser.close();
})();
