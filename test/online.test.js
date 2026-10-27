// npm run online (tools/online.js): cloudflared 출력에서 친구에게 줄 주소를 찾는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { tunnelUrl, TunnelKeeper, probeUrl } from '../tools/online.js';
import { CONFIG as C } from '../shared/config.js';

test('터널 주소: cloudflared 안내 상자에서 찾고, 실패 메시지의 api 주소는 무시', () => {
  const ok = [
    '2026-10-22T13:18:41Z INF Requesting new quick Tunnel on trycloudflare.com...',
    '2026-10-22T13:18:43Z INF +--------------------------------------------------------------------------------------------+',
    '2026-10-22T13:18:43Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |',
    '2026-10-22T13:18:43Z INF |  https://pottery-sense-quarterly-lightweight.trycloudflare.com                             |',
  ].join('\n');
  assert.equal(tunnelUrl(ok), 'https://pottery-sense-quarterly-lightweight.trycloudflare.com');
  const fail =
    'failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel": dial tcp: lookup api.trycloudflare.com: no such host';
  assert.equal(tunnelUrl(fail), null);
  assert.equal(tunnelUrl('see https://www.cloudflare.com/website-terms/'), null);
});

// ---------- 터널 지키기 (TunnelKeeper): 가짜 cloudflared · 가짜 요청 · 가짜 시계 ----------

// lines: 켜자마자 낼 출력 (주소 등). exitNow 면 바로 꺼짐
function fakeTunnel(lines, { exitNow = false } = {}) {
  const c = new EventEmitter();
  c.stdout = new EventEmitter();
  c.stderr = new EventEmitter();
  c.killed = false;
  c.kill = () => {
    if (c.killed) return;
    c.killed = true;
    c.emit('exit', null);
  };
  queueMicrotask(() => {
    for (const l of lines) c.stderr.emit('data', Buffer.from(`${l}\n`));
    if (exitNow) c.emit('exit', 1);
  });
  return c;
}

// urls: 켤 때마다 줄 주소들, openAfter(url, tries) → 열렸나. 가짜 시계로 sleep 은 바로 지나감
function harness(urls, openAt, { maxTime = 10 * 60 * 1000, exitNow = false } = {}) {
  let t = 0;
  const spawned = [];
  const ready = [];
  const status = [];
  const tries = new Map();
  let k;
  k = new TunnelKeeper({
    spawnTunnel: () => {
      const u = urls[Math.min(spawned.length, urls.length - 1)];
      const c = fakeTunnel(u ? [`INF |  ${u}   |`] : ['ERR failed'], { exitNow });
      spawned.push(c);
      return c;
    },
    probe: async (url) => {
      const n = (tries.get(url) || 0) + 1;
      tries.set(url, n);
      return openAt(url, n, t);
    },
    onReady: (url) => ready.push({ url, t }),
    onStatus: (kind, text) => status.push({ kind, text, t }),
    sleep: async (ms) => {
      t += ms;
      if (t > maxTime) k.stop();
    },
    now: () => t,
  });
  return { k, spawned, ready, status, tries, time: () => t };
}

const U1 = 'https://first-try-one.trycloudflare.com';
const U2 = 'https://second-try-two.trycloudflare.com';

test('터널 지키기: 주소를 받아도 바로 안 알리고, 실제로 열릴 때까지 기다렸다가 알림 (그 사이 다시 켜지 않음)', async () => {
  const h = harness([U1], (url, n) => n >= 4, { maxTime: 20000 });
  await h.k.run();
  assert.equal(h.spawned.length, 1);
  assert.equal(h.ready.length, 1);
  assert.equal(h.ready[0].url, U1);
  assert.ok(h.ready[0].t >= 3 * C.TUNNEL_PROBE_INTERVAL_MS, '세 번 실패한 뒤에야 알림');
  assert.ok(h.status.some((s) => s.kind === 'checking'));
  assert.ok(!h.status.some((s) => s.kind === 'restart'));
});

test('터널 지키기: 정한 시간 안에 안 열리면 cloudflared 를 다시 켜 새 주소, 새 주소가 열리면 그걸 알림', async () => {
  const h = harness([U1, U2], (url) => url === U2, { maxTime: 3 * C.TUNNEL_READY_TIMEOUT_MS });
  await h.k.run();
  assert.equal(h.spawned.length, 2);
  assert.ok(h.spawned[0].killed, '첫 터널은 끔');
  assert.deepEqual(h.ready.map((r) => r.url), [U2]);
  assert.ok(h.status.some((s) => s.kind === 'restart' && /안 열림/.test(s.text)));
});

test('터널 지키기: 열린 뒤에 연속으로 안 열리면 다시 켜 새 주소로 알림 (TUNNEL_HEALTH_FAILS)', async () => {
  const deadAt = 5 * C.TUNNEL_HEALTH_MS;
  const h = harness([U1, U2], (url, n, t) => (url === U1 ? t < deadAt : true), { maxTime: deadAt + (C.TUNNEL_HEALTH_FAILS + 3) * C.TUNNEL_HEALTH_MS });
  await h.k.run();
  assert.deepEqual(h.ready.map((r) => r.url), [U1, U2]);
  assert.ok(h.ready[1].t >= deadAt + C.TUNNEL_HEALTH_FAILS * C.TUNNEL_HEALTH_MS - C.TUNNEL_HEALTH_MS, '연속 실패 뒤에');
  assert.ok(h.spawned[0].killed);
  assert.ok(h.status.some((s) => s.kind === 'restart' && /열려 있던/.test(s.text)));
});

test('터널 지키기: 계속 실패하면 TUNNEL_MAX_RESTARTS 번 다시 켜 보고 포기 (안내)', async () => {
  const h = harness([null], () => false, { exitNow: true });
  const ok = await h.k.run();
  assert.equal(ok, false);
  assert.equal(h.spawned.length, C.TUNNEL_MAX_RESTARTS + 1);
  assert.equal(h.ready.length, 0);
  assert.ok(h.status.at(-1).kind === 'give-up');
});

test('터널 열림 확인 (probeUrl): 첫 화면 200 + 게임 페이지 + 웹소켓이 열려야 성공. Cloudflare 530·안내 페이지·웹소켓 실패는 실패', async () => {
  const page = (status, body) => async () => ({ ok: status >= 200 && status < 300, status, text: async () => body });
  class WsOk {
    constructor() {
      setTimeout(() => this.onopen && this.onopen(), 1);
    }
    close() {}
  }
  class WsBad {
    constructor() {
      setTimeout(() => this.onerror && this.onerror(new Error('x')), 1);
    }
    close() {}
  }
  assert.equal(await probeUrl(U1, { fetchFn: page(200, '<title>Tetrafall</title>'), WS: WsOk }), true);
  assert.equal(await probeUrl(U1, { fetchFn: page(530, 'error 1033'), WS: WsOk }), false, 'Cloudflare 530');
  assert.equal(await probeUrl(U1, { fetchFn: page(200, 'Cloudflare tunnel starting'), WS: WsOk }), false, '게임 페이지가 아님');
  assert.equal(await probeUrl(U1, { fetchFn: page(200, 'Tetrafall'), WS: WsBad }), false, '웹소켓 실패');
  assert.equal(await probeUrl(U1, { fetchFn: async () => { throw new Error('ENOTFOUND'); }, WS: WsOk }), false);
  assert.equal(await probeUrl(U1, { fetchFn: page(200, 'Tetrafall'), WS: null }), true, '웹소켓이 없는 Node 면 HTTP 만');
});
