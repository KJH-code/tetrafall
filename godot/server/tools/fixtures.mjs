// JS 판에서 C# 테스트의 정답 자료를 뽑음 → tests/Tetrafall.Tests/fixtures/*.json. 실행: node godot/server/tools/fixtures.mjs
// - jsmath.json: Math.sin·cos·exp·atan2·hypot·round 의 입력·출력 비트 (C# JsMath 가 V8 과 비트까지 같은지)
// - jsnumber.json: 숫자 → JSON.stringify 글자 (C# JsNumber·JsonOut)
// - mulberry32.json: 시드별 처음 값들 (tools/sim.js mulberry32)
// - protocol-lobby.json: 방 만들기·들어가기·핑·나가기 각본에서 JS 서버(rooms.js)가 보낸 메시지·로그 글자 그대로 (C# Rooms 가 같은지)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rooms } from '../../../server/rooms.js';
import { mulberry32 } from '../../../tools/sim.js';

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '../tests/Tetrafall.Tests/fixtures');
const bits = (x) => Buffer.from(new Float64Array([x]).buffer).toString('hex');
const r = mulberry32(4242);
const write = (name, data) => fs.writeFileSync(path.join(out, name), JSON.stringify(data));

// 수학: 게임에 나오는 범위 + 경계
const ins = [];
for (let i = 0; i < 1500; i++) ins.push([(r() - 0.5) * (i % 4 === 0 ? 60 : 8), (r() - 0.5) * 20, (r() - 0.5) * 6]);
ins.push([0, 0, 0], [-0, 1, 0], [Math.PI / 2, -Math.PI, 0], [1e-300, -1e-300, 0], [700, -745, 3], [0.5, -0.5, 2.5], [-2.5, 1.5, -0.4999999999999999]);
const math = ins.map(([a, b, c]) => [bits(a), bits(b), bits(c), bits(Math.sin(a)), bits(Math.cos(a)), bits(Math.exp(a > 50 ? 50 : a)), bits(Math.atan2(a, b)), bits(Math.hypot(a, b)), bits(Math.hypot(a, b, c)), bits(Math.round(c)), bits(Math.round(a))]);
write('jsmath.json', math);

// 숫자 글자
const nums = [0, -0, 0.125, -0.125, 0.5, -0.5, 1.005, 2.5, -2.5, 0.045, -0.04, 1e21 + 1, 1, -1, 1e-7, 1.5e-7, 1e-6, 123456789012345680000, 1e21, 1e20, 0.1 + 0.2, 1 / 3, -2.5, 1000 / 30, 5e-324, 1.7976931348623157e308, 2 ** 53, 2 ** 53 + 2, 1e15, 1e16, 123.456, -0.000001];
for (let i = 0; i < 1500; i++) nums.push((r() - 0.5) * 10 ** Math.floor(r() * 50 - 25));
write('jsnumber.json', nums.map((x) => [bits(x), JSON.stringify(x), x.toFixed(0), x.toFixed(1), x.toFixed(2), x.toFixed(3)]));

// mulberry32
write('mulberry32.json', [1, 1000, 4242, 0xffffffff].map((seed) => { const f = mulberry32(seed); return [seed, Array.from({ length: 20 }, () => bits(f()))]; }));

// 대기실 프로토콜 각본 (C# ProtocolTests 와 같은 순서)
const sent = [];
const logs = [];
const sock = (i) => ({ readyState: 1, OPEN: 1, send: (t) => sent.push([i, t]) });
let tk = 0;
class FixedRooms extends Rooms {
  newSeat(room, conn) {
    const token = `token${++tk}`;
    room.seats.set(conn.id, { token, conn, awayAt: null });
    return token;
  }
}
const rooms = new FixedRooms({ rng: mulberry32(77), openLog: (code) => ({ log: (m) => logs.push(`[${code}] ${m}`), close: () => logs.push(`[${code}] (닫음)`) }), serverLog: (m) => logs.push(`[서버] ${m}`), now: () => 0 });
const TICK = 1000 / 30;
const step = () => { rooms.tick(TICK); rooms.broadcast(); };
const c1 = rooms.connect(sock(1));
rooms.message(c1, { type: 'create', name: '', nick: '  재혁\u0001  최고 ' });
step();
const code = c1.room.code;
const c2 = rooms.connect(sock(2));
rooms.message(c2, { type: 'join', code: ` ${code.toLowerCase()} ` });
step();
rooms.message(c2, { type: 'ping', t: 123.5 });
rooms.message(c2, { type: 'ping', t: 'x' });
rooms.message(c1, { type: 'join', code: 'ZZZZ' }); // 방 안이라 무시
rooms.message(c2, { type: 'leave' });
step();
const c3 = rooms.connect(sock(3));
rooms.message(c3, { type: 'join', code: 'nope' });
rooms.message(c3, { type: 'join' });
rooms.message(c3, { type: 'create', name: '이름이 아주 아주 아주 아주 긴 방 이름입니다', nick: 5 });
step();
rooms.broadcastList(true);
rooms.message(c1, { type: 'leave' });
rooms.broadcastList();
write('protocol-lobby.json', { sent, logs });
console.log(`jsmath ${math.length}, jsnumber ${nums.length}, 프로토콜 메시지 ${sent.length}개·로그 ${logs.length}줄`);
