// 방 각본 (S6): JS rooms.js 와 C# Rooms 가 같은 각본에서 같은 메시지·로그를 내는지. 각본은 자료 (단계 목록) 라 C# 테스트
// (tests/Tetrafall.Tests/RoomScenarioTests.cs) 가 같은 각본을 그대로 돌림. fixtures.mjs 가 JS 결과를 protocol-rooms.json 에 씀.
// 아직 C# 에 없는 게임 일 (판 시작 성공·입력·연습·체력전 스냅샷·바드/대포수/광전사/사냥꾼 스냅샷) 은 각본에 안 넣음
//
// 단계: { c: 'connect' } (접속 번호 1부터) · { c: 'msg', i, m } · { c: 'raw', i, text } (글자 그대로 — JSON 이 아니면 버림)
//       { c: 'step' } (틱 한 번 + 보내기) · { c: 'ticks', ms } (틱만) · { c: 'disconnect', i } · { c: 'list', force }
//       { c: 'clock', ms } (빈도 제한 시계) · { c: 'gameRng', i, seed } (접속 i 가 있는 방의 게임 난수 = mulberry32(seed))
//       { c: 'fault', i, where } (접속 i 의 방에서 '틱'·'메시지'·'스냅샷' 때 Error('펑')) · { c: 'publicUrl', url }
// 오류 로그 줄 ('[오류] 틱: Error: 펑\n    at …') 은 스택이 언어마다 달라 '[오류] 틱' 까지만 비교
import { Rooms } from '../../../server/rooms.js';
import { mulberry32 } from '../../../tools/sim.js';

const TICK = 1000 / 30;
const long = 'ㄱ'.repeat(300) + '끝';

export const SCENARIOS = [
  {
    name: '재접속 대기실: 자리 유지·토큰으로 복귀·틀린 토큰·두 창·만료·방 닫힘',
    seed: 11,
    steps: [
      { c: 'connect' },
      { c: 'msg', i: 1, m: { type: 'create', nick: '재혁' } },
      { c: 'connect' },
      { c: 'step' },
      { c: 'joinFirst', i: 2 },
      { c: 'gameRng', i: 1, seed: 5 },
      { c: 'msg', i: 1, m: { type: 'teamMode', on: true } },
      { c: 'msg', i: 1, m: { type: 'setChar', char: 'ninja' } },
      { c: 'msg', i: 1, m: { type: 'setColor', color: 9 } },
      { c: 'msg', i: 2, m: { type: 'setColor', color: 9 } },
      { c: 'msg', i: 2, m: { type: 'setColor', color: '3' } },
      { c: 'msg', i: 2, m: { type: 'setColor', color: 2.5 } },
      { c: 'msg', i: 2, m: { type: 'setColor', color: 13 } },
      { c: 'step' },
      { c: 'disconnect', i: 1 },
      { c: 'step' },
      { c: 'ticks', ms: 59000 },
      { c: 'connect' }, // 3 = a 다시
      { c: 'rejoinAs', i: 3, of: 1, lower: true },
      { c: 'step' },
      { c: 'msg', i: 3, m: { type: 'setChar', char: 'tank' } },
      { c: 'connect' }, // 4: 틀린 토큰들
      { c: 'msg', i: 4, m: { type: 'rejoin', code: '?', token: 'f'.repeat(32) } },
      { c: 'rejoinAs', i: 4, of: 1, badToken: 'ffff' },
      { c: 'rejoinAs', i: 4, of: 1, badToken: 123 },
      { c: 'msg', i: 4, m: { type: 'rejoin', code: 'ZZZZ', token: 'token1' } },
      { c: 'msg', i: 4, m: { type: 'rejoin' } },
      { c: 'connect' }, // 5: b 의 토큰으로 두 번째 창 (b 는 아직 붙어 있음)
      { c: 'rejoinAs', i: 5, of: 2 },
      { c: 'step' },
      { c: 'msg', i: 2, m: { type: 'create' } }, // 옛 창은 새 id 로 새 방
      { c: 'step' },
      { c: 'msg', i: 3, m: { type: 'rejoin', code: 'X', token: 'token1' } }, // 방 안 접속의 rejoin 은 무시
      { c: 'disconnect', i: 5 },
      { c: 'ticks', ms: 60100 },
      { c: 'step' },
      { c: 'connect' }, // 6
      { c: 'rejoinAs', i: 6, of: 2 },
      { c: 'disconnect', i: 3 },
      { c: 'ticks', ms: 30000 },
      { c: 'step' },
      { c: 'ticks', ms: 30100 },
      { c: 'list', force: true },
    ],
  },
  {
    name: '방 안 설정: 공개·봇·관전·내보내기·이름·팀·봇 난이도·맵·모드·하늘 계단·체력전·시작 거부·이상한 메시지',
    seed: 22,
    steps: [
      { c: 'connect' },
      { c: 'msg', i: 1, m: { type: 'create', name: '  재미 \t 방 ', nick: long } },
      { c: 'gameRng', i: 1, seed: 12 }, // 봇 둘이 탱크·닌자·건축가·갈고리 중 (나머지 캐릭터 스냅샷은 아직 C# 에 없음)
      { c: 'connect' },
      { c: 'joinFirst', i: 2 },
      { c: 'connect' }, // 3: 방 밖에서 목록 봄
      { c: 'msg', i: 2, m: { type: 'setPublic', on: true } }, // 방장 아님
      { c: 'msg', i: 1, m: { type: 'setPublic', on: 1 } },
      { c: 'list' },
      { c: 'list' }, // 안 바뀌면 안 보냄
      { c: 'msg', i: 1, m: { type: 'spectate', target: '2', on: true } }, // Number('2')
      { c: 'msg', i: 1, m: { type: 'spectate', target: 'x', on: true } },
      { c: 'list' },
      { c: 'step' },
      { c: 'msg', i: 1, m: { type: 'addBot' } },
      { c: 'msg', i: 1, m: { type: 'addBot' } },
      { c: 'msg', i: 2, m: { type: 'addBot' } }, // 방장 아님
      { c: 'list' },
      { c: 'msg', i: 1, m: { type: 'removeBot' } },
      { c: 'msg', i: 1, m: { type: 'spectate', target: 2, on: false } },
      { c: 'msg', i: 1, m: { type: 'setName', name: ' 이름\u0007 바꿈 ' } },
      { c: 'msg', i: 1, m: { type: 'setName', name: null } },
      { c: 'msg', i: 2, m: { type: 'setName', name: ['a', 'b'] } },
      { c: 'msg', i: 1, m: { type: 'teamMode', on: 'yes' } },
      { c: 'msg', i: 1, m: { type: 'setTeam', target: 2, team: 'blue' } },
      { c: 'msg', i: 1, m: { type: 'setTeam', target: 2, team: 'green' } },
      { c: 'msg', i: 1, m: { type: 'shuffleTeams' } },
      { c: 'msg', i: 1, m: { type: 'botLevel', level: 'hard' } },
      { c: 'msg', i: 1, m: { type: 'botLevel', level: 'toString' } },
      { c: 'msg', i: 1, m: { type: 'setMap', map: 'pyramid' } },
      { c: 'msg', i: 1, m: { type: 'setMap', map: 'nope' } },
      { c: 'msg', i: 1, m: { type: 'setMode', mode: 'master' } }, // 팀전도 꺼짐
      { c: 'msg', i: 1, m: { type: 'teamMode', on: true } }, // 블록 마스터라 안 됨
      { c: 'msg', i: 1, m: { type: 'setMode', mode: 'kills' } },
      { c: 'msg', i: 1, m: { type: 'setMode', mode: 'survival' } }, // (킬 점수전 스냅샷 killsTarget 은 아직 C# 에 없어 보내기 전에 되돌림)
      { c: 'msg', i: 1, m: { type: 'skyStairs', on: false } },
      { c: 'msg', i: 1, m: { type: 'hpMode', on: true } },
      { c: 'msg', i: 1, m: { type: 'hpMode', on: false } }, // (체력전 스냅샷은 아직 C# 에 없어 보내기 전에 끔)
      { c: 'list' },
      { c: 'step' },
      { c: 'msg', i: 1, m: { type: 'kick', target: -1 } }, // 봇 내보내기
      { c: 'msg', i: 1, m: { type: 'kick', target: 1 } }, // 자기 자신은 안 됨
      { c: 'msg', i: 2, m: { type: 'kick', target: 1 } }, // 방장 아님
      { c: 'msg', i: 1, m: { type: 'kick', target: 2 } },
      { c: 'msg', i: 1, m: { type: 'start' } }, // 1명 → 시작 거부 로그
      { c: 'msg', i: 1, m: { type: 'nope' } },
      { c: 'msg', i: 1, m: { type: ['setMap'], map: 'flat' } }, // type 이 글자가 아님 → 무시
      { c: 'raw', i: 1, text: '[1,2]' }, // 배열도 메시지로 셈 (빈도), 아무 일 없음
      { c: 'raw', i: 1, text: '5' },
      { c: 'raw', i: 1, text: 'not json' },
      { c: 'msg', i: 1, m: { type: 'ping', t: 1e21 } },
      { c: 'msg', i: 1, m: { type: 'ping', t: -0 } },
      { c: 'publicUrl', url: 'https://abc-def.trycloudflare.com//' },
      { c: 'step' },
      { c: 'publicUrl', url: 'http://abc.example.com' },
      { c: 'step' },
      { c: 'list' },
      { c: 'msg', i: 1, m: { type: 'leave' } },
      { c: 'list' },
    ],
  },
  {
    name: '방 수·인원 상한: 최대 방 수, 꽉 찬 방, 하나가 닫히면 다시 됨',
    seed: 33,
    steps: [
      ...Array.from({ length: 8 }, (_, k) => [{ c: 'connect' }, { c: 'msg', i: k + 1, m: { type: 'create', name: `방${k}` } }]).flat(),
      { c: 'connect' }, // 9
      { c: 'msg', i: 9, m: { type: 'create' } },
      { c: 'msg', i: 1, m: { type: 'leave' } },
      { c: 'msg', i: 9, m: { type: 'create', nick: '  ' } },
      { c: 'gameRng', i: 9, seed: 8 },
      ...Array.from({ length: 7 }, () => ({ c: 'msg', i: 9, m: { type: 'addBot' } })),
      { c: 'msg', i: 9, m: { type: 'addBot' } }, // 꽉 참
      { c: 'joinFirstOf', i: 1, of: 9 }, // 꽉 참 (스냅샷은 안 보냄: 봇 캐릭터 중 아직 C# 스냅샷이 없는 것이 있음)
      { c: 'msg', i: 9, m: { type: 'leave' } }, // 봇만 남음 → 방 닫힘
      { c: 'list', force: true },
    ],
  },
  {
    name: '방 하나의 예외: 틱·메시지·스냅샷 예외는 그 방만 닫음, 다른 방은 계속, 닫힌 방 사람은 새 방',
    seed: 44,
    steps: [
      { c: 'connect' },
      { c: 'msg', i: 1, m: { type: 'create' } },
      { c: 'connect' },
      { c: 'msg', i: 2, m: { type: 'create' } },
      { c: 'connect' },
      { c: 'msg', i: 3, m: { type: 'create' } },
      { c: 'connect' },
      { c: 'joinFirstOf', i: 4, of: 1 },
      { c: 'step' },
      { c: 'fault', i: 1, where: '틱' },
      { c: 'step' },
      { c: 'msg', i: 1, m: { type: 'create' } },
      { c: 'fault', i: 2, where: '메시지' },
      { c: 'msg', i: 2, m: { type: 'input', fwd: 1 } },
      { c: 'fault', i: 3, where: '스냅샷' },
      { c: 'step' },
      { c: 'step' },
      { c: 'list', force: true },
    ],
  },
  {
    name: '메시지 빈도: 몰리면 NET_MSG_BURST 개, 넘는 건 버리고 한 번만 로그, 시간이 지나면 다시',
    seed: 55,
    steps: [
      { c: 'connect' },
      ...Array.from({ length: 70 }, (_, k) => ({ c: 'msg', i: 1, m: { type: 'ping', t: k } })),
      { c: 'clock', ms: 100 },
      ...Array.from({ length: 20 }, (_, k) => ({ c: 'msg', i: 1, m: { type: 'ping', t: 100 + k } })),
      { c: 'connect' },
      { c: 'msg', i: 2, m: { type: 'ping', t: 1 } },
    ],
  },
];

// JS 쪽 실행: { sent: [[접속 번호, 글자]], logs: [글자] }
export function runJs(sc) {
  const sent = [];
  const logs = [];
  let tk = 0;
  let clock = 0;
  class FixedRooms extends Rooms {
    newSeat(room, conn) {
      const token = `token${++tk}`;
      room.seats.set(conn.id, { token, conn, awayAt: null });
      return token;
    }
  }
  const rooms = new FixedRooms({
    rng: mulberry32(sc.seed),
    openLog: (code) => ({ log: (m) => logs.push(`[${code}] ${m}`), close: () => logs.push(`[${code}] (닫음)`) }),
    serverLog: (m) => logs.push(`[서버] ${m}`),
    now: () => clock,
  });
  const conns = [null];
  const tokens = [null];
  for (const s of sc.steps) {
    if (s.c === 'connect') {
      const i = conns.length;
      const ws = { readyState: 1, OPEN: 1, send: (t) => sent.push([i, t]) };
      conns.push(rooms.connect(ws));
      tokens.push(null);
      // 접속 i 가 받은 마지막 welcome 토큰 (rejoinAs 용)
      const orig = ws.send;
      ws.send = (t) => {
        orig(t);
        const m = JSON.parse(t);
        if (m.type === 'welcome') tokens[i] = m.token;
      };
    } else if (s.c === 'msg') rooms.message(conns[s.i], s.m);
    else if (s.c === 'raw') {
      let msg;
      try {
        msg = JSON.parse(s.text);
      } catch {
        continue;
      }
      rooms.message(conns[s.i], msg);
    } else if (s.c === 'joinFirst') rooms.message(conns[s.i], { type: 'join', code: conns[1].room.code });
    else if (s.c === 'joinFirstOf') rooms.message(conns[s.i], { type: 'join', code: conns[s.of].room.code });
    else if (s.c === 'rejoinAs') {
      const code = [...rooms.rooms.values()].find((r) => [...r.seats.values()].some((x) => x.token === tokens[s.of]))?.code ?? 'NONE';
      rooms.message(conns[s.i], { type: 'rejoin', code: s.lower ? ` ${code.toLowerCase()} ` : code, token: s.badToken ?? tokens[s.of] });
    } else if (s.c === 'step') {
      rooms.tick(TICK);
      rooms.broadcast();
    } else if (s.c === 'ticks') {
      for (let t = 0; t < s.ms; t += TICK) rooms.tick(TICK);
    } else if (s.c === 'disconnect') rooms.disconnect(conns[s.i]);
    else if (s.c === 'list') rooms.broadcastList(!!s.force);
    else if (s.c === 'clock') clock += s.ms;
    else if (s.c === 'gameRng') conns[s.i].room.game.rng = mulberry32(s.seed);
    else if (s.c === 'fault') {
      const g = conns[s.i].room.game;
      const boom = () => {
        throw new Error('펑');
      };
      if (s.where === '틱') g.tick = boom;
      else if (s.where === '메시지') g.handleInput = boom;
      else g.snapshot = boom;
    } else if (s.c === 'publicUrl') rooms.setPublicUrl(s.url);
    else throw new Error(`모르는 단계 ${s.c}`);
  }
  return { sent, logs: logs.map(cutError) };
}

// '[코드] [오류] 틱: Error: 펑\n    at …' → '[코드] [오류] 틱'
export function cutError(line) {
  const m = line.match(/^(\[[A-Z]+\] \[오류\] [^:]+):/);
  return m ? m[1] : line;
}
