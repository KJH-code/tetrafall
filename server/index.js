// Tetrafall 호스트 서버: 정적 파일 서빙 + WebSocket + 고정 틱 게임 루프.
// 실행: npm start  → 다른 PC는 브라우저에서 http://<호스트IP>:3000
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { CONFIG as C } from '../shared/config.js';
import { Game } from './game.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT) || C.PORT;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

// URL → 디스크 경로. 클라이언트 폴더, 공용 폴더, three.js 모듈만 노출한다.
function resolveFile(urlPath) {
  if (urlPath === '/' || urlPath === '') return path.join(ROOT, 'client', 'index.html');
  if (urlPath === '/vendor/three.module.js') {
    return path.join(ROOT, 'node_modules', 'three', 'build', 'three.module.js');
  }
  let base;
  let rel;
  if (urlPath.startsWith('/shared/')) {
    base = path.join(ROOT, 'shared');
    rel = urlPath.slice('/shared/'.length);
  } else {
    base = path.join(ROOT, 'client');
    rel = urlPath.slice(1);
  }
  const full = path.normalize(path.join(base, rel));
  if (!full.startsWith(base + path.sep)) return null; // 경로 탈출 방지
  return full;
}

const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = resolveFile(urlPath);
  if (!file) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(data);
  });
});

function stamp() {
  return new Date().toLocaleTimeString('ko-KR', { hour12: false });
}
const log = (msg) => console.log(`[${stamp()}] ${msg}`);

const game = new Game(log, { countdownMs: C.ROUND_COUNTDOWN_MS });
game.setMap(C.MAP_DEFAULT);
const wss = new WebSocketServer({ server });
const sockets = new Map(); // id -> ws
let nextId = 1;

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

wss.on('connection', (ws) => {
  const id = nextId++;
  const player = game.addPlayer(id);
  if (!player) {
    send(ws, { type: 'reject', reason: `방이 꽉 찼습니다 (최대 ${Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length)}명)` });
    ws.close();
    return;
  }
  sockets.set(id, ws);
  send(ws, { type: 'welcome', id, slot: player.slot, name: player.name });
  send(ws, game.snapshot(true));

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    if (!msg || typeof msg !== 'object') return;
    switch (msg.type) {
      case 'input':
        game.handleInput(id, msg);
        break;
      case 'action':
        game.handleAction(id, msg);
        break;
      case 'addBot':
        if (game.isHost(id) && !game.addBot()) log('봇 추가 거부: 방이 꽉 찼거나 판 진행 중');
        break;
      case 'removeBot':
        if (game.isHost(id)) game.removeBot();
        break;
      case 'setMap':
        if (game.isHost(id)) game.setMap(String(msg.map));
        break;
      case 'start':
        if (game.isHost(id)) {
          if (!game.startRound()) log(`시작 거부: 플레이어 ${game.players.size}명 (최소 ${C.MIN_PLAYERS}명)`);
        }
        break;
      default:
    }
  });

  ws.on('close', () => {
    sockets.delete(id);
    game.removePlayer(id);
    if (game.humanCount() === 0) game.removeAllBots(); // 사람이 다 나가면 봇도 정리
  });
});

// 고정 틱 루프. setInterval 의 드리프트를 누적 시간으로 보정한다.
const TICK_MS = 1000 / C.TICK_RATE;
let last = performance.now();
let acc = 0;
setInterval(() => {
  const now = performance.now();
  acc += now - last;
  last = now;
  let steps = 0;
  while (acc >= TICK_MS && steps < 5) {
    game.tick(TICK_MS);
    acc -= TICK_MS;
    steps++;
  }
  if (acc > TICK_MS * 5) acc = 0; // 너무 밀리면 버린다
  if (steps > 0 && sockets.size) {
    const snap = game.snapshot(false);
    snap.events = game.drainEvents();
    const payload = JSON.stringify(snap);
    for (const ws of sockets.values()) if (ws.readyState === ws.OPEN) ws.send(payload);
  }
}, TICK_MS);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Tetrafall 호스트 서버 실행 중 (포트 ${PORT}, 틱 ${C.TICK_RATE}Hz, 인원 ${C.MIN_PLAYERS}~${Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length)}명)`);
  console.log('이 PC에서:        http://localhost:' + PORT);
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) console.log(`다른 PC에서 (${name}): http://${a.address}:${PORT}`);
    }
  }
  console.log('튜닝 상수: shared/config.js');
});
