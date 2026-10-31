// 기존 JS 화면을 C# 서버에 붙여 방 만들기 → 대기실이 뜨는지 스샷 (뼈대 확인).
// 미리: C# 서버 (PORT=3200 dotnet run --project godot/server/src/Tetrafall.Server). 실행: xvfb-run -a node godot/server/tools/lobby_shot.cjs <저장 폴더> [주소]
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const out = process.argv[2] || '.';
  const url = process.argv[3] || 'http://127.0.0.1:3200/';
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  const ws = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  page.on('websocket', (s) => s.on('framereceived', (f) => ws.length < 6 && ws.push(String(f.payload).slice(0, 80))));
  await page.addInitScript(() => localStorage.setItem('tf-tutorial', 'done'));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(4000);
  await page.screenshot({ path: path.join(out, 'cs-menu.png') });
  await page.evaluate(() => document.getElementById('room-create').click());
  await page.waitForTimeout(5000);
  await page.screenshot({ path: path.join(out, 'cs-lobby.png') });
  const info = await page.evaluate(() => ({ lobby: !!document.querySelector('#lobby:not(.hidden), #char-pick'), code: (document.body.innerText.match(/[A-Z]{4}/g) || []).slice(0, 5) }));
  console.log(JSON.stringify({ info, errors: errors.slice(0, 8), ws }, null, 1));
  await browser.close();
})();
