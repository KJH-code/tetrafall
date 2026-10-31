// 서버 부하 (JS 쪽): 진짜 Rooms 를 가짜 소켓으로 — 방 4개 × 8명 (사람 1 = 가짜 소켓, 보낸 글자는 버림 + 봇 7), 캐릭터 켬, 모드 생존·킬·마스터·생존.
// 서버 틱 루프 한 번 (rooms.tick + rooms.broadcast: 스냅샷 JSON·보내기) 의 시간을 틱마다 재서 평균·중앙값·99%·최대 (앞 WARM 틱은 데우기라 뺌, 최대는 따로).
// 판이 끝나면 (재는 밖에서) 다시 시작. 시드 고정 (방 코드·판 난수). C# 쪽: dotnet godot/server/src/Tetrafall.Server/bin/Release/net10.0/Tetrafall.Server.dll load
// 실행: node godot/server/tools/load.mjs [틱 수=3600] → JSON 한 줄
import { Rooms } from '../../../server/rooms.js';
import { CONFIG as C } from '../../../shared/config.js';
import { mulberry32 } from '../../../tools/sim.js';

const TICKS = Number(process.argv[2] ?? 3600);
const WARM = 300;
const MODES = ['survival', 'kills', 'master', 'survival'];
const TICK = 1000 / C.TICK_RATE;
const rooms = new Rooms({ rng: mulberry32(1), countdownMs: 0 });
let bytes = 0;
const list = MODES.map((mode, r) => {
  const ws = { OPEN: 1, readyState: 1, send: (t) => (bytes += t.length) };
  const conn = rooms.connect(ws);
  rooms.message(conn, { type: 'create', nick: `P${r}` });
  const room = conn.room;
  room.game.rng = mulberry32(100 + r);
  for (let i = 0; i < 7; i++) rooms.message(conn, { type: 'addBot' });
  rooms.message(conn, { type: 'setMode', mode });
  rooms.message(conn, { type: 'start' });
  return { conn, room };
});
const times = [];
let rounds = 0;
for (let t = 0; t < TICKS; t++) {
  const t0 = performance.now();
  rooms.tick(TICK);
  rooms.broadcast();
  times.push(performance.now() - t0);
  for (const { conn, room } of list) {
    if (room.game.phase === 'over') {
      rounds++;
      rooms.message(conn, { type: 'start' });
    }
  }
}
const steady = times.slice(WARM).sort((a, b) => a - b);
const r3 = (x) => Math.round(x * 1000) / 1000;
const avg = steady.reduce((a, b) => a + b, 0) / steady.length;
console.log(JSON.stringify({ server: 'js', rooms: list.length, players: list.map((x) => x.room.game.players.size), ticks: TICKS, warm: WARM, rounds, avgMs: r3(avg), p50Ms: r3(steady[Math.floor(steady.length * 0.5)]), p99Ms: r3(steady[Math.floor(steady.length * 0.99)]), maxMs: r3(steady.at(-1)), maxWarmMs: r3(Math.max(...times.slice(0, WARM))), budgetMs: r3(TICK), sentMB: r3(bytes / 1e6) }));
