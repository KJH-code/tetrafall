// 웹 내보내기를 크로미움(Mesa)에서 열어 게임 서버에 붙고 스샷 + 첫 로딩 시간. 고도 웹은 SwiftShader 에서 깨져 보여 Mesa 로.
// 미리: 게임 서버 (JS: PORT=3000 npm start) + node godot/client/tools/serve_web.mjs 8060
// 실행 (레포 뿌리): xvfb-run -a node godot/client/tools/web_shot.cjs <저장 폴더> "<주소 뒤 ?…>"   예: "?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4"
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const out = process.argv[2] || '.';
  const query = process.argv[3] || '?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4';
  const wait = Number(process.env.SHOT_WAIT || 12000);
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  const t0 = Date.now();
  const marks = {};
  page.on('console', (m) => {
    const t = Date.now() - t0;
    logs.push(`${t}ms ${m.text()}`);
    if (m.text().includes('들어옴') && !marks.joined) marks.joined = t;
  });
  await page.goto(`http://127.0.0.1:${process.env.WEB_PORT || 8060}/${query}`, { waitUntil: 'load' });
  marks.load = Date.now() - t0;
  await page.waitForTimeout(wait);
  await page.screenshot({ path: path.join(out, 'client-web.png') });
  const fps = await page.evaluate(() => new Promise((r) => { let n = 0; const s = performance.now(); const f = () => { n++; if (performance.now() - s < 2000) requestAnimationFrame(f); else r(n / 2); }; requestAnimationFrame(f); }));
  console.log(JSON.stringify({ ...marks, fps }));
  console.log(logs.filter((l) => /자동|ERROR|error|SCRIPT/.test(l)).slice(0, 12).join('\n'));
  await browser.close();
})();
