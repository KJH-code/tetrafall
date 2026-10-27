// 인터넷 대전: 이 PC 에서 서버를 켜고 Cloudflare 터널로 https 주소를 받아 친구에게 준다.
// 실행: npm run online   (cloudflared 가 깔려 있어야 함. 없으면 설치 방법을 띄우고 서버만 켬)
// 터널 주소(https://….trycloudflare.com)는 켤 때마다 바뀐다. 계정·도메인 필요 없음.
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../shared/config.js';

// cloudflared 출력에서 터널 주소 찾기. 주소는 단어-단어-….trycloudflare.com
// (실패 메시지의 https://api.trycloudflare.com 을 집지 않게 하이픈이 있는 것만)
export function tunnelUrl(text) {
  const m = String(text).match(/https:\/\/[a-z0-9]+(?:-[a-z0-9]+)+\.trycloudflare\.com/);
  return m ? m[0] : null;
}

const INSTALL = [
  'cloudflared 가 없어 터널을 못 켰습니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다.',
  '설치 (한 번만):',
  '  Windows : winget install --id Cloudflare.cloudflared   (설치 뒤 터미널을 새로 열기)',
  '  macOS   : brew install cloudflared',
  '  그 밖   : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/',
  '설치하고 다시 npm run online',
].join('\n');

// 클립보드에 넣는 명령 (운영체제마다). 없으면 null
export function clipboardCommand(platform = process.platform) {
  if (platform === 'win32') return ['clip', []];
  if (platform === 'darwin') return ['pbcopy', []];
  if (platform === 'linux') return process.env.WAYLAND_DISPLAY ? ['wl-copy', []] : ['xclip', ['-selection', 'clipboard']];
  return null;
}

// 주소를 클립보드에 (실패해도 조용히 false)
function copyToClipboard(text) {
  const cmd = clipboardCommand();
  if (!cmd) return Promise.resolve(false);
  return new Promise((resolve) => {
    try {
      const c = spawn(cmd[0], cmd[1], { stdio: ['pipe', 'ignore', 'ignore'] });
      c.on('error', () => resolve(false));
      c.on('exit', (code) => resolve(code === 0));
      c.stdin.end(text);
    } catch {
      resolve(false);
    }
  });
}

export function banner(url, copied = false) {
  const lines = [
    '친구에게 이 주소를 보내세요 (켤 때마다 바뀜):',
    '',
    `  ${url}`,
    '',
    copied ? '(클립보드에 복사해 둠 — 메신저에 붙여 넣기만)' : '(복사: 위 주소를 드래그)',
    '방을 만든 뒤 대기 화면의 "링크 복사" 는 이 주소 + 방 코드로 복사됨',
  ];
  const w = Math.max(...lines.map((l) => l.length)) + 4;
  const bar = '='.repeat(w);
  return ['', bar, ...lines.map((l) => `  ${l}`), bar, ''].join('\n');
}

// 터널 지키기 (2026-10-27 재혁: "링크가 안 될 때도 많음" = 켜자마자 Cloudflare 530·1033 에러 페이지).
// cloudflared 를 켜고 → 주소를 받고 → 그 주소로 실제 요청(HTTP + 웹소켓)이 될 때까지 기다렸다가 알림 (onReady).
// 정한 시간 안에 안 열리거나, 열린 뒤에 죽으면 cloudflared 를 다시 켜서 새 주소 (연속 실패 TUNNEL_MAX_RESTARTS 번까지).
// spawnTunnel() → { stdout, stderr (data 이벤트), on('exit'), kill() }, probe(url) → Promise<bool>, sleep(ms), now() 는 테스트에서 가짜로
export class TunnelKeeper {
  constructor({ spawnTunnel, probe, onReady = () => {}, onStatus = () => {}, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), now = () => Date.now() }) {
    Object.assign(this, { spawnTunnel, probe, onReady, onStatus, sleep, now });
    this.stopped = false;
    this.fails = 0; // 연속 실패 (열리면 0)
    this.child = null;
    this.url = null; // 지금 열린 주소
  }

  stop() {
    this.stopped = true;
    if (this.child) this.child.kill();
  }

  async run() {
    while (!this.stopped) {
      if (this.fails > C.TUNNEL_MAX_RESTARTS) {
        this.onStatus('give-up', `터널을 ${C.TUNNEL_MAX_RESTARTS + 1}번 켰는데 안 열립니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다. 잠시 뒤 npm run online 을 다시 해 보세요`);
        return false;
      }
      const child = this.spawnTunnel();
      this.child = child;
      let out = '';
      let exited = false;
      const onData = (b) => {
        out = (out + b.toString()).slice(-4000);
      };
      child.stdout?.on('data', onData);
      child.stderr?.on('data', onData);
      child.on('exit', () => {
        exited = true;
      });
      child.on('error', () => {
        exited = true;
      });
      // 1) 주소 받기
      let url = null;
      for (const t0 = this.now(); !url && !exited && !this.stopped && this.now() - t0 < C.TUNNEL_URL_TIMEOUT_MS; ) {
        url = tunnelUrl(out);
        if (!url) await this.sleep(C.TUNNEL_POLL_MS);
      }
      if (this.stopped) return true;
      if (!url) {
        this.fail(child, exited ? 'cloudflared 가 바로 꺼짐' : '주소를 못 받음', out);
        if (exited && /ENOENT|not found|not recognized/i.test(out)) return false;
        continue;
      }
      // 2) 그 주소가 실제로 열릴 때까지 (Cloudflare 가 주소를 퍼뜨리는 데 몇 초 걸림)
      this.onStatus('checking', `터널 주소 받음: ${url} — 친구가 열 수 있는지 확인 중…`);
      let open = false;
      for (const t0 = this.now(); !open && !exited && !this.stopped && this.now() - t0 < C.TUNNEL_READY_TIMEOUT_MS; ) {
        open = await this.probe(url);
        if (!open) await this.sleep(C.TUNNEL_PROBE_INTERVAL_MS);
      }
      if (this.stopped) return true;
      if (!open) {
        this.fail(child, exited ? '터널이 꺼짐' : `${Math.round(C.TUNNEL_READY_TIMEOUT_MS / 1000)}초 안에 안 열림`, out);
        continue;
      }
      this.fails = 0;
      this.url = url;
      this.onReady(url);
      // 3) 열린 뒤에도 주기적으로 확인. 꺼지거나 연속 TUNNEL_HEALTH_FAILS 번 안 열리면 다시 켬
      let bad = 0;
      while (!this.stopped && !exited && bad < C.TUNNEL_HEALTH_FAILS) {
        await this.sleep(C.TUNNEL_HEALTH_MS);
        if (this.stopped || exited) break;
        bad = (await this.probe(url)) ? 0 : bad + 1;
      }
      if (this.stopped) return true;
      this.url = null;
      this.fail(child, exited ? '터널이 꺼짐' : '주소가 안 열림', out, true);
    }
    return true;
  }

  fail(child, why, out, wasOpen = false) {
    this.fails++;
    try {
      child.kill();
    } catch {
      // 이미 꺼짐
    }
    this.onStatus('restart', `${wasOpen ? '열려 있던 ' : ''}터널 문제 (${why}) → 다시 켭니다 (${this.fails}/${C.TUNNEL_MAX_RESTARTS})`, out);
  }
}

// 주소가 실제로 열리나: 첫 화면 HTTP 200 + 웹소켓 열림 (Node 22 전역 WebSocket, 없으면 HTTP 만)
export async function probeUrl(url, { fetchFn = globalThis.fetch, WS = globalThis.WebSocket, timeoutMs = C.TUNNEL_PROBE_TIMEOUT_MS } = {}) {
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeoutMs);
    const res = await fetchFn(`${url}/`, { signal: ctl.signal, redirect: 'manual' }).finally(() => clearTimeout(timer));
    if (!res.ok) return false;
    const body = await res.text();
    if (!/Tetrafall/.test(body)) return false; // Cloudflare 안내·에러 페이지가 200 으로 올 때
  } catch {
    return false;
  }
  if (!WS) return true;
  return new Promise((resolve) => {
    let done = false;
    const end = (ok) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        ws.close();
      } catch {
        // 무시
      }
      resolve(ok);
    };
    const timer = setTimeout(() => end(false), timeoutMs);
    let ws;
    try {
      ws = new WS(url.replace(/^https:/, 'wss:'));
    } catch {
      return end(false);
    }
    ws.onopen = () => end(true);
    ws.onerror = () => end(false);
    ws.onclose = () => end(false);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const port = Number(process.env.PORT) || C.PORT;
  let keeper = null;
  const children = [];
  const stopAll = () => {
    if (keeper) keeper.stop();
    for (const c of children) if (c.exitCode === null) c.kill();
  };
  process.on('SIGINT', () => {
    stopAll();
    process.exit(0);
  });

  // ipc: 터널 주소를 서버에 알려 대기실 "링크 복사" 가 이 주소로 (server/index.js process.on('message')). 터널을 다시 켜도 서버·방·판은 그대로
  const server = spawn(process.execPath, [path.join(root, 'server', 'index.js')], { stdio: ['inherit', 'inherit', 'inherit', 'ipc'], env: { ...process.env, PORT: String(port) } });
  children.push(server);
  server.on('exit', (code) => {
    console.log(`서버가 꺼짐 (코드 ${code}). 터널도 끕니다`);
    stopAll();
    process.exit(code ?? 0);
  });

  keeper = new TunnelKeeper({
    spawnTunnel: () => {
      const cf = spawn(process.env.CLOUDFLARED || 'cloudflared', ['tunnel', '--no-autoupdate', '--url', `http://localhost:${port}`], { stdio: ['ignore', 'pipe', 'pipe'] });
      cf.on('error', (err) => {
        if (err.code === 'ENOENT') {
          console.log(`\n${INSTALL}\n`);
          keeper.stop();
        } else console.log(`터널 실행 실패: ${err.message}`);
      });
      return cf;
    },
    probe: (url) => probeUrl(url),
    onStatus: (kind, text, out) => {
      console.log(`[터널] ${text}`);
      if (kind === 'give-up' && out) console.log(String(out).slice(-800));
    },
    onReady: (url) => {
      if (server.connected) server.send({ type: 'publicUrl', url });
      copyToClipboard(url).then((copied) => console.log(banner(url, copied)));
    },
  });
  keeper.run();
}
