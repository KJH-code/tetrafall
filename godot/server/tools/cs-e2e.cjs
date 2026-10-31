// 실전 확인: 기존 JS 화면(브라우저)을 서버에 붙여 8명 판 (사람 1 + 봇 7) 을 모드 3개 × 캐릭터 켬으로 끝까지 → 결과 → 다음 판 시작,
// 그다음 연습 방·튜토리얼 방 (넘기기로 끝까지). 페이지 에러·콘솔 에러를 모으고 단계마다 스샷.
// 미리: 서버 (C#: PORT=3300 dotnet godot/server/src/Tetrafall.Server/bin/Release/net10.0/Tetrafall.Server.dll, JS: PORT=3300 npm start)
// 실행: xvfb-run -a node godot/server/tools/cs-e2e.cjs <스샷 폴더> [주소] → 마지막 줄 JSON 요약 (ok·판마다 모드·틱·승자·에러)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const out = process.argv[2] || '.';
const url = process.argv[3] || 'http://127.0.0.1:3300/';
const MODES = ['survival', 'master', 'kills'];
const ROUND_MAX_MS = 240000;

async function waitFor(page, fn, arg, ms, what) {
  const t0 = Date.now();
  for (;;) {
    if (await page.evaluate(fn, arg)) return Date.now() - t0;
    if (Date.now() - t0 > ms) throw new Error(`시간 넘음: ${what}`);
    await page.waitForTimeout(250);
  }
}

async function openPage(browser, errors, tag) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('pageerror', (e) => errors.push(`[${tag}] pageerror ${String(e).slice(0, 300)}`));
  page.on('console', (m) => m.type() === 'error' && !m.text().startsWith('Failed to load resource') && errors.push(`[${tag}] console ${m.text().slice(0, 300)}`));
  page.on('response', (r) => r.status() >= 400 && errors.push(`[${tag}] ${r.status()} ${r.url()}`));
  await page.addInitScript(() => localStorage.setItem('tf-tutorial', 'done'));
  await page.goto(url + '?title=meadow', { waitUntil: 'load' });
  await waitFor(page, () => !!window.__tf, null, 20000, '__tf');
  // 타이틀은 Enter 로 넘김
  await page.waitForTimeout(1500);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(2500);
  return page;
}

const st = () => {
  const s = window.__tf.getState();
  return s && { phase: s.phase, mode: s.mode, n: (s.players || []).length, round: s.round, practice: !!s.practice, tutorial: s.tutorial ?? null };
};

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist'] });
  const errors = [];
  const rounds = [];
  let ok = true;
  try {
    // ---- 8명 판: 모드 3개 ----
    const page = await openPage(browser, errors, 'room');
    await page.evaluate(() => document.getElementById('room-create').click());
    await waitFor(page, () => !!window.__tf.getMyId() && window.__tf.getState()?.phase === 'lobby', null, 15000, '대기실');
    for (let i = 0; i < 7; i++) await page.evaluate(() => window.__tf.send({ type: 'addBot' }));
    await waitFor(page, () => window.__tf.getState().players.length === 8, null, 10000, '봇 7명');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: path.join(out, 'lobby-8.png') });
    for (const mode of MODES) {
      await page.evaluate((m) => window.__tf.send({ type: 'setMode', mode: m }), mode);
      await waitFor(page, (m) => window.__tf.getState().mode === m, mode, 5000, `모드 ${mode}`);
      await page.evaluate(() => window.__tf.send({ type: 'start' }));
      await waitFor(page, () => ['countdown', 'playing'].includes(window.__tf.getState().phase), null, 10000, `${mode} 시작`);
      await waitFor(page, () => window.__tf.getState().phase === 'playing', null, 15000, `${mode} playing`);
      const t0 = Date.now();
      await page.waitForTimeout(5000);
      await page.screenshot({ path: path.join(out, `${mode}-play.png`) });
      await waitFor(page, () => window.__tf.getState().phase === 'over', null, ROUND_MAX_MS, `${mode} 판 끝`);
      const ms = Date.now() - t0;
      // 결과 판: 승리 연출 뒤 이번 판 번호로 뜸
      const n = await page.evaluate(() => window.__tf.getState().round.n);
      const shown = (k) => {
        const el = document.getElementById('results');
        return !!el && !el.classList.contains('hidden') && el.innerText.includes(`라운드 ${k} 결과`);
      };
      let results = true;
      try {
        await waitFor(page, shown, n, 15000, `${mode} 결과 판`);
      } catch {
        results = false;
      }
      await page.screenshot({ path: path.join(out, `${mode}-results.png`) });
      const res = await page.evaluate(() => {
        const s = window.__tf.getState();
        const el = document.getElementById('results');
        return { round: s.round.n, winners: s.round.winnerIds, text: el ? el.innerText.replace(/\s+/g, ' ').slice(0, 120) : '' };
      });
      rounds.push({ mode, ms, results, ...res });
      if (!results) ok = false;
      await page.waitForTimeout(6000); // 결과 연출 → 대기실 판
      await page.screenshot({ path: path.join(out, `${mode}-after.png`) });
    }
    // 다음 판: over 에서 다시 시작되는지
    await page.evaluate(() => window.__tf.send({ type: 'start' }));
    await waitFor(page, () => window.__tf.getState().phase === 'playing', null, 15000, '다음 판');
    rounds.push({ mode: 'next', started: true, state: await page.evaluate(st) });
    await page.close();

    // ---- 연습 방 ----
    const pr = await openPage(browser, errors, 'practice');
    await pr.evaluate(() => window.__tf.send({ type: 'practice', nick: 'e2e', char: 'ninja' }));
    await waitFor(pr, () => window.__tf.getState()?.mode === 'practice' && window.__tf.getState().phase === 'playing', null, 15000, '연습 방');
    await pr.evaluate(() => window.__tf.send({ type: 'dummyAdd' }));
    for (let i = 0; i < 10; i++) {
      await pr.evaluate(() => window.__tf.act({ name: 'push' }));
      await pr.waitForTimeout(300);
    }
    await pr.evaluate(() => window.__tf.act({ name: 'skill' }));
    await pr.waitForTimeout(2000);
    rounds.push({ mode: 'practice', state: await pr.evaluate(st) });
    await pr.screenshot({ path: path.join(out, 'practice.png') });
    await pr.close();

    // ---- 튜토리얼: 넘기기로 끝까지 ----
    const tu = await openPage(browser, errors, 'tutorial');
    const done = [];
    await tu.exposeFunction('__e2eDone', (e) => done.push(e));
    await tu.evaluate(() => {
      const ev = window.__tf.event;
      window.__tf.event = (e) => {
        if (e.type === 'tutorialDone') window.__e2eDone(e);
        return ev(e);
      };
    });
    await tu.evaluate(() => window.__tf.send({ type: 'tutorial', nick: 'e2e', char: 'tank' }));
    await waitFor(tu, () => window.__tf.getState()?.phase === 'playing' && !!window.__tf.getState().tutorial, null, 15000, '튜토리얼 방');
    await tu.waitForTimeout(1500);
    await tu.screenshot({ path: path.join(out, 'tutorial-start.png') });
    let steps = 0;
    for (; steps < 40; steps++) {
      const t = await tu.evaluate(() => window.__tf.getState().tutorial);
      if (!t || t.done) break;
      await tu.evaluate(() => window.__tf.send({ type: 'tutorialSkip' }));
      await tu.waitForTimeout(900);
    }
    await tu.waitForTimeout(1500);
    const tutState = await tu.evaluate(() => window.__tf.getState().tutorial);
    rounds.push({ mode: 'tutorial', skips: steps, done: !!tutState?.done, tutorial: tutState });
    if (!tutState?.done) ok = false;
    await tu.screenshot({ path: path.join(out, 'tutorial-end.png') });
    await tu.close();
  } catch (e) {
    ok = false;
    errors.push(`스크립트: ${e.message}`);
  }
  await browser.close();
  if (errors.length) ok = false;
  console.log(JSON.stringify({ ok, rounds, errors: errors.slice(0, 20) }));
})();
