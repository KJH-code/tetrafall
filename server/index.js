// Tetrafall 호스트 서버: 정적 파일 서빙 + WebSocket + 고정 틱 게임 루프.
// 실행: npm start  → 다른 PC는 브라우저에서 http://<호스트IP>:3000 (인터넷: npm run online)
// 서버 하나에 방 여러 개 (server/rooms.js)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { CONFIG as C } from '../shared/config.js';
import { Rooms } from './rooms.js';
import { warmUpPlacement } from './game.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPort = Number(process.env.PORT);
const PORT = (process.env.PORT ?? '').trim() !== '' && Number.isInteger(envPort) && envPort >= 0 ? envPort : C.PORT; // 0 이면 운영체제가 빈 포트를 고름 (테스트), 실제 포트는 시작 줄에

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.glb': 'model/gltf-binary',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

// URL → 디스크 경로. 클라이언트 폴더, 공용 폴더, three.js 모듈만 노출한다.
function resolveFile(urlPath) {
  if (urlPath === '/' || urlPath === '') return path.join(ROOT, 'client', 'index.html');
  if (urlPath === '/vendor/three.module.js') {
    return path.join(ROOT, 'node_modules', 'three', 'build', 'three.module.js');
  }
  if (urlPath === '/vendor/cannon-es.js') {
    // 몸 래그돌 물리 (client/ragdoll.js). import 'cannon-es' 가 여기로
    return path.join(ROOT, 'node_modules', 'cannon-es', 'dist', 'cannon-es.js');
  }
  let base;
  let rel;
  if (urlPath.startsWith('/vendor/jsm/')) {
    // three.js 확장 (GLTFLoader·SkeletonUtils·OutlineEffect 등). import 'three/addons/…' 가 여기로
    base = path.join(ROOT, 'node_modules', 'three', 'examples', 'jsm');
    rel = urlPath.slice('/vendor/jsm/'.length);
  } else if (urlPath.startsWith('/shared/')) {
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
  let urlPath;
  try {
    urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch {
    // 잘못된 % 인코딩 주소 (2026-10-30 감사: 예전엔 이 한 줄로 서버가 죽음)
    res.writeHead(400);
    res.end('bad request');
    return;
  }
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
// 방마다 로그 파일: logs/<서버를 켠 시각>/<방을 연 시각>_<코드>.txt (플레이테스트 분석: npm run stats)
// 콘솔에는 같은 줄을 [코드] 를 붙여 찍는다
const LOG_DIR = path.join(ROOT, 'logs');
const pad = (n) => String(n).padStart(2, '0');
const fileStamp = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
const RUN_DIR = path.join(LOG_DIR, fileStamp(new Date()));

function openLog(code) {
  let fd = null;
  try {
    fs.mkdirSync(RUN_DIR, { recursive: true });
    fd = fs.openSync(path.join(RUN_DIR, `${fileStamp(new Date())}_${code}.txt`), 'a');
  } catch (err) {
    console.error(`[${code}] 로그 파일을 못 엶 (콘솔에만 남김): ${err.message}`);
  }
  return {
    log(msg) {
      const st = stamp();
      console.log(`[${st}] [${code}] ${msg}`);
      if (fd === null) return;
      try {
        fs.writeSync(fd, `[${st}] ${msg}\n`); // 바로 씀: 서버를 Ctrl+C 로 꺼도 마지막 줄까지 남게
      } catch {
        fd = null;
      }
    },
    close() {
      if (fd !== null) fs.closeSync(fd);
      fd = null;
    },
  };
}

// npm run online (tools/online.js) 이 터널 주소를 찾으면 IPC 로 알려 줌 → 대기실 "링크 복사" 가 터널 주소로
process.on('message', (m) => {
  if (m && m.type === 'publicUrl' && rooms.setPublicUrl(m.url)) console.log(`친구용 주소: ${m.url}`);
});
const rooms = new Rooms({
  openLog,
  serverLog: (msg) => console.log(`[${stamp()}] ${msg}`),
  countdownMs: C.ROUND_COUNTDOWN_MS,
});
// 스냅샷 압축 (permessage-deflate, 2026-10-28 8인): 8명 판 스냅샷 평균 9.6KB × 30Hz ≈ 2.35Mbps/명 → 약 0.5Mbps/명. 메시지마다 따로 압축 (연결마다 문맥 안 들고 있음: 메모리 적게)
const wss = new WebSocketServer({
  server,
  maxPayload: C.NET_MAX_PAYLOAD_BYTES, // 넘으면 그 연결만 끊김 (ws 기본 100MB)
  perMessageDeflate: {
    threshold: C.NET_DEFLATE_MIN_BYTES,
    zlibDeflateOptions: { level: C.NET_DEFLATE_LEVEL },
    serverNoContextTakeover: true,
    clientNoContextTakeover: true,
  },
});

wss.on('connection', (ws) => {
  const conn = rooms.connect(ws);
  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    rooms.message(conn, msg); // 방 안 예외는 rooms 가 그 방만 닫음
  });
  ws.on('close', () => rooms.disconnect(conn));
  ws.on('error', (err) => console.log(`[${stamp()}] 접속 ${conn.id} 소켓 오류: ${err.message}`)); // 너무 큰 메시지 등 → 그 연결만 닫힘
});

// 마지막 방어: 여기까지 올라온 예외는 콘솔에 남기고 서버는 계속 (방마다 예외는 rooms.js crash 가 먼저 잡음)
const guard = (where, fn) => () => {
  try {
    fn();
  } catch (err) {
    console.error(`[${stamp()}] ${where} 오류 (서버는 계속):`, err);
  }
};

// 고정 틱 루프. setInterval 의 드리프트를 누적 시간으로 보정한다. 모든 방이 같은 틱
const TICK_MS = 1000 / C.TICK_RATE;
let last = performance.now();
let acc = 0;
setInterval(guard('틱 루프', () => {
  const now = performance.now();
  acc += now - last;
  last = now;
  let steps = 0;
  const behind = Math.max(0, acc - TICK_MS); // 정해진 틱 시각보다 밀린 시간
  while (acc >= TICK_MS && steps < 5) {
    rooms.tick(TICK_MS);
    acc -= TICK_MS;
    steps++;
  }
  if (acc > TICK_MS * 5) acc = 0; // 너무 밀리면 버린다
  rooms.noteTick(performance.now() - now, behind); // 핑 화면에 서버 부하 (pong)
  if (steps > 0) rooms.broadcast();
}), TICK_MS);
setInterval(guard('방 목록', () => rooms.broadcastList()), C.ROOM_LIST_MS);

warmUpPlacement(); // 첫 판 첫 블록이 서버 틱을 막지 않게 (JIT 데우기)
server.listen(PORT, '0.0.0.0', () => {
  const port = server.address().port;
  if (!fs.existsSync(path.join(ROOT, 'node_modules', 'cannon-es'))) console.log('⚠ cannon-es 가 없음 → 몸 래그돌이 꺼짐. 레포 폴더에서 npm install 을 한 번 해 주세요 (Windows PowerShell 은 npm.cmd install)');
  console.log(`Tetrafall 호스트 서버 실행 중 (포트 ${port}, 틱 ${C.TICK_RATE}Hz, 방 최대 ${C.ROOM_MAX}개, 방마다 ${C.MIN_PLAYERS}~${Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length)}명)`);
  console.log('이 PC에서:        http://localhost:' + port);
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) console.log(`다른 PC에서 (${name}): http://${a.address}:${port}`);
    }
  }
  console.log('튜닝 상수: shared/config.js');
  console.log(`로그: ${path.relative(ROOT, RUN_DIR)}/ 에 방마다 파일 (요약: npm run stats)`);
});
