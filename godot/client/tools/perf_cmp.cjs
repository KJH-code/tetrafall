// 8명 판 성능 비교 (G3): JS 판 (three) · 고도 웹을 같은 크로미움 (Mesa GL, web_shot.cjs 와 같은 설정) 에서 같은 방식으로 잼.
// 미리: 게임 서버 (난수 고정 — 예: Math.random = mulberry32(42) 로 server/index.js) 포트 3000, 고도 웹은 serve_web.mjs 8060
// 게임 서버 포트는 GAME_PORT (기본 3000), 고도 웹 서빙 포트는 WEB_PORT (기본 8060)
// 실행: xvfb-run -a node godot/client/tools/perf_cmp.cjs js|web <view third|first|spectate> <map> [잴 초=10] [시작 뒤 기다림 초=15]
// 출력 한 줄 JSON: 평균 프레임 ms · 1% low (가장 느린 1% 평균) · 그리기 수 · 삼각형 수 (JS) · JS 힙 MB. 고도 웹은 자동 조종 --perf-log 줄도 같이
const { chromium } = require('playwright');
const fs = require('fs');
const GAME = process.env.GAME_PORT || 3000;

// 이 node 아래 프로세스 (크로미움 브라우저·GPU·렌더러) 의 CPU 시간 합 (ms, /proc). 기계를 다른 일과 나눠 쓰면 벽시계 프레임 시간이 크게 흔들려서
// 같은 일의 비용은 'CPU ms / 프레임' 으로도 봄 (리눅스만, 없으면 null)
function cpuTimes() {
  try {
    const tick = 1000 / 100; // CLK_TCK 100
    const kids = {};
    const info = {};
    for (const d of fs.readdirSync('/proc')) {
      if (!/^\d+$/.test(d)) continue;
      try {
        const st = fs.readFileSync(`/proc/${d}/stat`, 'utf8');
        const f = st.slice(st.lastIndexOf(')') + 2).split(' ');
        const ppid = Number(f[1]);
        (kids[ppid] = kids[ppid] || []).push(Number(d));
        const cmd = fs.readFileSync(`/proc/${d}/cmdline`, 'utf8');
        const type = (cmd.match(/--type=([a-z-]+)/) || [])[1] || 'browser';
        info[d] = { ms: (Number(f[11]) + Number(f[12])) * tick, type };
      } catch (e) {}
    }
    const out = { all: 0 };
    const walk = (pid) => {
      for (const k of kids[pid] || []) {
        const i = info[k];
        if (i) { out.all += i.ms; out[i.type] = (out[i.type] || 0) + i.ms; }
        walk(k);
      }
    };
    walk(process.pid);
    return out;
  } catch (e) {
    return null;
  }
}

(async () => {
  const [target, view = 'third', map = 'pyramid', secs = '10', warm = '15'] = process.argv.slice(2);
  const browser = await chromium.launch({ headless: false, args: ['--use-angle=gl', '--ignore-gpu-blocklist', '--enable-precise-memory-info'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  if (target === 'js') {
    await page.addInitScript((third) => {
      localStorage.setItem('tf-settings', JSON.stringify({ third, music: 0, sfx: 0 }));
      localStorage.setItem('tf-tutorial', 'skipped');
      localStorage.setItem('tf-name', 'js');
    }, view === 'third');
    await page.goto(`http://127.0.0.1:${GAME}/`);
    await page.waitForFunction(() => window.__tf && window.__tf.getState, null, { timeout: 30000 });
    await page.evaluate(() => window.__tf.title?.finish?.());
    await page.waitForTimeout(1500);
    await page.evaluate(() => window.__tf.send({ type: 'create', name: '', nick: 'js' }));
    await page.waitForFunction(() => window.__tf.getMyId() != null, null, { timeout: 15000 });
    await page.evaluate(({ map, view }) => {
      const s = window.__tf.send;
      s({ type: 'setMap', map });
      if (view === 'spectate') s({ type: 'spectate' });
      for (let i = 0; i < (view === 'spectate' ? 8 : 7); i++) s({ type: 'addBot' });
    }, { map, view });
    await page.waitForTimeout(1500);
    await page.evaluate(() => window.__tf.send({ type: 'start' }));
    await page.mouse.click(640, 360); // 포인터 잡기 (1인칭 화면)
  } else {
    const q = `?server=ws://127.0.0.1:${GAME}&auto=host&bots=${view === 'spectate' ? 8 : 7}&wait-players=8&map=${map}&view=${view}&perf-log=1&perf-secs=${secs}&shot-after=${Number(warm) + Number(secs)}${process.env.EXTRA || ''}`;
    await page.goto(`http://127.0.0.1:${process.env.WEB_PORT || 8060}/${q}`);
  }
  await page.waitForTimeout(Number(warm) * 1000);
  const c0 = cpuTimes();
  const r = await page.evaluate((secs) => new Promise((res) => {
    const ms = [];
    const calls = [];
    const tris = [];
    const R = window.__tf && window.__tf.renderer && window.__tf.renderer.renderer;
    if (R) R.info.autoReset = false; // JS: 한 프레임 = 장면 + 외곽선 두 번 그림 → 프레임마다 직접 셈
    let last = performance.now();
    const t0 = last;
    const f = (now) => {
      ms.push(now - last);
      last = now;
      if (R) { calls.push(R.info.render.calls); tris.push(R.info.render.triangles); R.info.reset(); }
      if (now - t0 < secs * 1000) requestAnimationFrame(f);
      else {
        const s = [...ms].sort((a, b) => b - a);
        const k = Math.max(1, Math.ceil(s.length * 0.01));
        const tf = window.__tf;
        const info = tf && tf.renderer && tf.renderer.renderer ? tf.renderer.renderer.info.render : null;
        res({ frames: ms.length, avg: ms.reduce((a, b) => a + b, 0) / ms.length, low: s.slice(0, k).reduce((a, b) => a + b, 0) / k, draws: calls.length ? Math.round(calls.slice(1).reduce((a, b) => a + b, 0) / Math.max(1, calls.length - 1)) : null, tris: tris.length ? Math.round(tris.slice(1).reduce((a, b) => a + b, 0) / Math.max(1, tris.length - 1)) : null, heapMB: performance.memory ? performance.memory.usedJSHeapSize / 1048576 : null, phase: tf && tf.getState() ? tf.getState().phase : null });
      }
    };
    requestAnimationFrame(f);
  }), Number(secs));
  const c1 = cpuTimes();
  if (c0 && c1) { // CPU ms / 프레임: 전부 · GPU 프로세스 · 렌더러 (wasm·JS)
    const per = (k) => +(((c1[k] || 0) - (c0[k] || 0)) / r.frames).toFixed(1);
    r.cpu = { all: per('all'), gpu: per('gpu-process'), renderer: per('renderer') };
  }
  if (target === 'web') await page.waitForTimeout(8000); // 고도 자동 조종이 성능 줄을 찍을 때까지
  if (process.env.SHOT) await page.screenshot({ path: process.env.SHOT });
  if (process.env.LOGS) console.error(logs.filter((l) => /자동|ERROR|error|SCRIPT/.test(l)).slice(0, 30).join('\n'));
  console.log(JSON.stringify({ target, view, map, ...r, godot: logs.filter((l) => l.includes('성능 표') || l.includes('성능 구간')).slice(-2).join(' || ') || null }));
  await browser.close();
})();
