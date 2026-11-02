// 고도 웹 짝 비교 (W5): 8명 판 (봇 7) 을 크로미움 (Mesa GL, perf_cmp.cjs 와 같은 설정) 에서 열고 world/perf_ab.gd 의 'AB …' 줄이 나올 때까지 기다림.
// 한 판 안에서 설정 A/B 를 번갈아 재서 기계를 나눠 쓰거나 장면이 달라도 비율이 흔들리지 않음 (종류는 world/perf_ab.gd 머리)
// 미리: 게임 서버 (GAME_PORT, 기본 3000) + 고도 웹 서빙 (WEB_PORT, 기본 8060 — serve_web.mjs)
// 실행: xvfb-run -a node godot/client/tools/perf_ab.cjs <종류> ["&ab-secs=40&msaa=0" 같은 주소 뒤]
const { chromium } = require('playwright');

(async () => {
  const [kind, extra = ''] = process.argv.slice(2);
  const game = process.env.GAME_PORT || 3000;
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  let line = null;
  const errs = [];
  page.on('console', (m) => {
    const t = m.text();
    if (t.startsWith('AB ')) line = t;
    if (/SCRIPT ERROR|SHADER ERROR/.test(t)) errs.push(t.slice(0, 200));
  });
  await page.goto(`http://127.0.0.1:${process.env.WEB_PORT || 8060}/?server=ws://127.0.0.1:${game}&auto=host&bots=7&wait-players=8&map=${process.env.MAP || 'pyramid'}&view=third&ab=${kind}${extra}`);
  const t0 = Date.now();
  while (!line && Date.now() - t0 < 300000) await page.waitForTimeout(1000);
  console.log(`${kind}${extra}: ${line || '시간 넘김'}${errs.length ? ' · 오류 ' + errs.slice(0, 3).join(' | ') : ''}`);
  await browser.close();
})();
