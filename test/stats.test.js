// 로그 요약 (tools/stats.js) 테스트: 실제 게임이 찍는 로그를 그대로 읽는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Rooms } from '../server/rooms.js';
import { parseLog, summarize, formatReport, latestRun } from '../tools/stats.js';

const TICK = 1000 / C.TICK_RATE;

// 봇끼리 몇 판 돌려 서버와 같은 형식의 로그를 만든다 (앞에 [시각] 도 붙여서)
function botGames(rounds) {
  const lines = [];
  const g = new Game((s) => lines.push(`[12시 0분 0초] ${s}`));
  g.rng = Math.random;
  const human = g.addPlayer(1);
  g.setNick(human.id, '재혁');
  g.addBot();
  g.addBot();
  g.setSpectator(human.id, true); // 사람은 관전 (봇끼리만 싸움). 참가자 목록에서 빠지는지도 봄
  let kills = 0;
  let deaths = 0;
  for (let r = 0; r < rounds; r++) {
    g.startRound();
    const t0 = g.time;
    while (g.phase === 'playing' && g.time - t0 < 180000) g.tick(TICK);
    if (g.phase === 'playing') g.endRound(null);
    kills += g.deaths.filter((d) => d.killer).length; // g.deaths 는 판마다 비워짐
    deaths += g.deaths.length;
  }
  return { g, text: lines.join('\n'), kills, deaths };
}

test('통계: 실제 게임 로그에서 판 수·승수·사망 원인이 서버 집계와 같다', () => {
  const { g, text, kills: serverKills, deaths: serverDeaths } = botGames(6);
  const rounds = parseLog(text);
  assert.equal(rounds.length, 6);
  const s = summarize(rounds);
  assert.equal(s.byCause.crush, g.totals.crush);
  assert.equal(s.byCause.fall, g.totals.fall);
  assert.equal(s.byCause.lava, g.totals.lava);
  for (const p of g.participants()) {
    const row = s.players.find((x) => x.key === p.name);
    assert.ok(row, `${p.name} 이 플레이어별 표에 있음`);
    assert.equal(row.wins, p.wins, `${p.name} 승수`);
    assert.equal(row.rounds, 6);
  }
  assert.ok(!s.players.some((x) => x.key === '재혁'), '관전자는 참가자가 아님');
  // 킬: 서버가 기록한 킬과 같다
  const kills = s.players.reduce((n, p) => n + p.kills, 0);
  assert.equal(kills, serverKills);
  assert.equal(s.weapons.total, serverDeaths);
  assert.ok(serverKills > 0, '봇끼리 6판이면 킬이 나옴');
  const known = ['밀치기', '망치', '투사체', '충격파', '폭탄', '조종블록', '설치블록', '(킬 없음)'];
  for (const [k] of s.weapons.rows) assert.ok(known.includes(k), `공격 이름 ${k}`);
  assert.deepEqual(s.byComp.map((x) => x.key), ['봇 2 (보통)'], '봇 난이도가 구성에 붙음');
  assert.ok(formatReport(s).includes('== 플레이어별 =='));
});

test('통계: 자리 번호를 물려받은 다른 사람은 따로, 접속 중에 이름을 바꾼 사람은 하나로 센다', () => {
  const text = [
    'P1 접속 (slot 0) — 호스트',
    'P1 이름: 재혁',
    'P2 접속 (slot 1)',
    '===== ROUND 1 시작 (2명: P1 P2, 맵 평지) =====',
    '  [사망] P2 낙사 @ 0:20 (위치 1.0, 2.0, -4.0, 피해 30%)',
    '===== ROUND 1 종료 | 길이 0:20 | 승자: P1 =====',
    '[호스트] P2 내보냄',
    'P2 접속 종료',
    'P2 접속 (slot 1)', // 다른 사람이 같은 자리로
    'P2 이름: 민수',
    'P1 이름: 장난',
    '===== ROUND 2 시작 (2명: P1 P2, 맵 평지) =====',
    '  [사망] P1 압사 @ 0:10 (위치 1.0, 2.0, 0.0, 피해 0%)',
    '===== ROUND 2 종료 | 길이 0:10 | 승자: P2 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  const row = (k) => s.players.find((p) => p.key === k);
  assert.equal(row('재혁').rounds, 2, '이름을 바꿔도 같은 접속이면 한 사람');
  assert.deepEqual([...row('재혁').aliases], ['장난']);
  assert.equal(row('민수').rounds, 1);
  assert.equal(row('민수').wins, 1);
  assert.equal(row('P2').rounds, 1, '나가기 전 P2 는 이름 없는 다른 사람');
});

test('통계: 팀전이면 이긴 팀 전원에게 승, 구성에 팀전 표시', () => {
  const text = [
    '===== ROUND 1 시작 (4명: P1 P2 P3 P4(봇), 맵 평지, 봇 보통) =====',
    '  팀: 빨강 P1 P3 / 파랑 P2 P4(봇)',
    '  [사망] P2 낙사 @ 0:20 (위치 1.0, 2.0, -4.0, 피해 30%, 킬 P1 밀치기)',
    '  [사망] P4(봇) 낙사 @ 0:25 (위치 1.0, 2.0, -4.0, 피해 30%, 킬 P3 망치)',
    '===== ROUND 1 종료 | 길이 0:25 | 승자: 빨강팀 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  const wins = Object.fromEntries(s.players.map((p) => [p.key, p.wins]));
  assert.deepEqual(wins, { P1: 1, P3: 1, P2: 0, 'P4(봇)': 0 });
  assert.equal(s.byComp[0].key, '사람 3 + 봇 1 팀전');
});

test('통계: 이름으로 묶고, 접속 끊김은 요약 줄에서 받고, 옛 형식·끝나지 않은 판·CRLF 도 읽는다', () => {
  const text = [
    '[1시] P1 접속 (slot 0) — 호스트',
    '[1시] P1 이름: 재혁',
    '[1시] ===== ROUND 1 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '[1시]   [쌓기] P1 → (1,2,1) (남은 4개)',
    '[1시]   [폭탄] P1 → (3,3) z=1 설치, 1.5초 뒤 폭발',
    '[1시]   [폭탄] P1 → P2 넉백 (P2 40%)',
    '[1시]   [밀치기] P1 → P2 넉백 치명타 (P2 55%)',
    '[1시]   [사망] P3(봇) 낙사 @ 0:10 (위치 1.0, 2.0, -4.0, 피해 120%, 킬 P1 조종블록)',
    '[1시] P2 접속 종료',
    '[1시] ===== ROUND 1 종료 | 길이 0:12 | 승자: P1 =====',
    '[1시]   사망: P3(봇) 낙사@0:10, P2 접속 끊김@0:12',
    // 옛 형식: 참가자 목록·피해 % 없음
    '[1시] ===== ROUND 2 시작 (2명, 맵 계단) =====',
    '[1시]   [사망] P1 압사 @ 0:30 (위치 1.0, 2.0, 3.0)',
    '[1시] ===== ROUND 2 종료 | 길이 0:30 | 승자: P3(봇) =====',
    '[1시]   사망: P1 압사@0:30',
    // 서버가 판 중간에 꺼짐 → 버림
    '[1시] ===== ROUND 3 시작 (2명: P1 P3(봇), 맵 평지) =====',
    '[1시]   [사망] P1 낙사 @ 0:05 (위치 1.0, 2.0, -4.0, 피해 10%)',
  ].join('\r\n');
  const rounds = parseLog(text);
  assert.equal(rounds.length, 2);
  assert.deepEqual(rounds[0].players.map((p) => p.key), ['재혁', 'P2', 'P3(봇)']);
  assert.deepEqual(rounds[1].players.map((p) => p.key).sort(), ['P3(봇)', '재혁']);
  const s = summarize(rounds);
  assert.deepEqual(s.byCause, { crush: 1, fall: 1, lava: 0, disconnect: 1 });
  const me = s.players.find((p) => p.key === '재혁');
  assert.equal(me.rounds, 2);
  assert.equal(me.wins, 1);
  assert.equal(s.fallDamage.find((b) => b.label === '100~149%').n, 1);
  assert.equal(s.items.humanRounds, 3, '사람 1명이 한 판: 재혁 2 + P2 1');
  assert.equal(s.items.build, 1);
  assert.equal(s.items.bombs, 1);
  assert.equal(s.items.bombHits, 1);
  assert.equal(s.items.crits, 1);
  assert.equal(s.byComp.find((c) => c.key === '사람 2 + 봇 1').rounds, 1);
  assert.deepEqual(s.weapons.rows, [['조종블록', 1]], '공격 이름에 괄호가 안 붙음 (옛 형식·접속 끊김 사망은 표에서 빠짐)');
  assert.equal(s.players.find((p) => p.key === '재혁').kills, 1);
  assert.equal(s.byComp.find((c) => c.key === '사람 1 + 봇 1').rounds, 1);
});

test('통계: 방마다 따로 남긴 로그를 방별로 읽어 합친다', () => {
  const logs = {};
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(`[12시 0분 0초] ${m}`), close() {} };
    },
  });
  const ws = () => ({ OPEN: 1, readyState: 1, send() {} });
  const a = rooms.connect(ws());
  const b = rooms.connect(ws());
  rooms.message(a, { type: 'create', nick: '재혁' });
  rooms.message(b, { type: 'create', nick: '민수' });
  for (const c of [a, b]) {
    rooms.message(c, { type: 'setName', name: c === a ? '재혁' : '민수' });
    rooms.message(c, { type: 'addBot' });
    rooms.message(c, { type: 'start' });
  }
  for (let t = 0; t < 30 * 300 && [...rooms.rooms.values()].some((r) => r.game.phase === 'playing'); t++) rooms.tick(TICK);
  const codes = Object.keys(logs);
  assert.equal(codes.length, 2);
  const perRoom = codes.map((c) => parseLog(logs[c].join('\n')));
  assert.deepEqual(perRoom.map((r) => r.length), [1, 1], '방마다 한 판');
  const s = summarize(perRoom.flat());
  assert.equal(s.players.find((p) => p.key === '재혁').rounds, 1);
  assert.equal(s.players.find((p) => p.key === '민수').rounds, 1, '두 방 모두 P1 이지만 이름으로 따로 셈');
});

test('통계: 기본은 가장 최근 서버 실행 (폴더면 안의 방 파일 전부, 빈 폴더는 건너뜀, 예전 파일 하나도 됨)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tf-logs-'));
  try {
    assert.equal(latestRun(dir), null);
    fs.writeFileSync(path.join(dir, '2026-10-21_10-00-00.txt'), 'x');
    assert.equal(latestRun(dir), path.join(dir, '2026-10-21_10-00-00.txt'), '예전 형식 파일');
    fs.mkdirSync(path.join(dir, '2026-10-22_09-00-00'));
    fs.writeFileSync(path.join(dir, '2026-10-22_09-00-00', '2026-10-22_09-01-00_ABCD.txt'), 'x');
    fs.mkdirSync(path.join(dir, '2026-10-22_11-00-00')); // 방을 안 연 서버 실행
    assert.equal(latestRun(dir), path.join(dir, '2026-10-22_09-00-00'));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('통계: 모드별 — 블록 마스터 생존자 여럿 승·마스터 승, 킬 점수전은 한 판에 여러 번 죽음', () => {
  const text = [
    'P1 이름: 재혁',
    '===== ROUND 1 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '  모드: 블록 마스터 (마스터 P1, 1:00 버티기)',
    '  [사망] P3(봇) 압사 @ 0:20 (위치 1.0, 2.0, 0.0, 피해 0%, 킬 P1 조종블록)',
    '  시간 끝 (1:00) → 생존자 승',
    '===== ROUND 1 종료 | 길이 1:00 | 승자: P2 =====',
    '===== ROUND 2 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '  모드: 블록 마스터 (마스터 P2, 1:00 버티기)',
    '  [사망] P1 압사 @ 0:10 (위치 1.0, 2.0, 0.0, 피해 0%, 킬 P2 조종블록)',
    '  [사망] P3(봇) 압사 @ 0:30 (위치 1.0, 2.0, 0.0, 피해 0%, 킬 P2 조종블록)',
    '===== ROUND 2 종료 | 길이 0:30 | 승자: P2 =====',
    '===== ROUND 3 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '  모드: 블록 마스터 (마스터 P3(봇), 1:00 버티기)',
    '===== ROUND 3 종료 | 길이 1:00 | 승자: P1 P2 =====',
    '===== ROUND 4 시작 (2명: P1 P2, 맵 평지) =====',
    '  모드: 킬 점수전 (3:00 또는 7킬)',
    '  [사망] P2 낙사 @ 0:10 (위치 1.0, 2.0, -4.0, 피해 50%, 킬 P1 밀치기)',
    '  [점수] P1 +1 → 1',
    '  [사망] P2 낙사 @ 0:40 (위치 1.0, 2.0, -4.0, 피해 70%, 킬 P1 밀치기)',
    '  [사망] P1 낙사 @ 0:50 (위치 1.0, 2.0, -4.0, 피해 20%, 킬 없음)',
    '===== ROUND 4 종료 | 길이 3:00 | 승자: P1 =====',
    '  사망: P2 낙사@0:10, P2 낙사@0:40, P1 낙사@0:50',
  ].join('\n');
  const rounds = parseLog(text);
  assert.deepEqual(rounds.map((r) => r.mode), ['블록 마스터', '블록 마스터', '블록 마스터', '킬 점수전']);
  assert.deepEqual(rounds[2].winnerKeys, ['재혁', 'P2'], '생존자 여럿 승');
  const s = summarize(rounds);
  const row = (k) => s.players.find((p) => p.key === k);
  assert.equal(row('재혁').wins, 2);
  assert.equal(row('P2').wins, 3);
  assert.equal(row('P2').fall, 2, '킬 점수전에서 두 번 죽음');
  assert.equal(row('P2').deathDamage.length, 2);
  assert.equal(row('재혁').kills, 3, '마스터 킬 1 + 킬 점수전 2');
  const mode = Object.fromEntries(s.byMode.map((g) => [g.key, g]));
  assert.equal(mode['블록 마스터'].rounds, 3);
  assert.equal(mode['블록 마스터'].note, '마스터 승 1/3');
  assert.equal(mode['킬 점수전'].note, '판당 사망 3.0');
  assert.ok(formatReport(s).includes('== 모드별 =='));
});

test('통계: 캐릭터별 판·승 (사람·봇 따로)', () => {
  const text = [
    'P1 이름: 재혁',
    '===== ROUND 1 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '  캐릭터: P1 탱크 / P2 닌자 / P3(봇) 탱크',
    '===== ROUND 1 종료 | 길이 0:20 | 승자: P1 =====',
    '===== ROUND 2 시작 (2명: P1 P2, 맵 평지) =====',
    '  캐릭터: P1 갈고리 / P2 닌자',
    '===== ROUND 2 종료 | 길이 0:20 | 승자: P2 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  const row = (k) => s.byChar.find((c) => c.key === k);
  assert.deepEqual([row('탱크').rounds, row('탱크').wins], [1, 1]);
  assert.deepEqual([row('닌자').rounds, row('닌자').wins], [2, 1]);
  assert.deepEqual([row('탱크 (봇)').rounds, row('탱크 (봇)').wins], [1, 0]);
  assert.ok(formatReport(s).includes('== 캐릭터별 =='));
});

test('통계: 콤보 — 길이별 횟수, 넣은 캐릭터별 (여럿이 같이는 따로, 옛 형식은 길이만), 마무리로 끝난 콤보 수', () => {
  const text = [
    '===== ROUND 1 시작 (3명: P1 P2 P3(봇), 맵 평지) =====',
    '  캐릭터: P1 닌자 / P2 탱크 / P3(봇) 갈고리',
    '  [콤보] P1 → P2 3타',
    '  [콤보] P1 → P2 7타 마무리',
    '  [콤보] P3(봇) → P1 2타',
    '  [콤보] P1+P3(봇) → P2 4타',
    '  [콤보] P2 2타',
    '===== ROUND 1 종료 | 길이 0:30 | 승자: P1 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  assert.equal(s.combos.total, 5);
  assert.deepEqual(s.combos.len, { 2: 2, 3: 1, 4: 1, 7: 1 });
  const row = (k) => s.combos.byChar.find((x) => x.key === k);
  assert.deepEqual([row('닌자').combos, row('닌자').hits, row('닌자').max, row('닌자').full, row('닌자').rounds], [2, 3 + 7, 7, 1, 1]);
  assert.equal(row('갈고리 (봇)').combos, 1);
  assert.equal(row('여럿이 같이').combos, 1);
  const report = formatReport(s);
  assert.ok(report.includes('== 콤보'), report);
  assert.ok(report.includes('2타 2'), report);
});


test('통계: 캐릭터 평타 — 타 번호별 명중 수 (공중 평타 따로, 무적이라 무시는 안 셈), 카운터히트 수, 건축가 블록 폭발·대폭발', () => {
  const text = [
    '[1시] ===== ROUND 1 시작 (2명: P1 P2(봇), 맵 평지) =====',
    '[1시]   캐릭터: P1 건축가 / P2(봇) 닌자',
    '[1시]   [평타] P1 → P2(봇) 넉백 (P2(봇) 7%) 1타 옆치기',
    '[1시]   [평타] P1 → P2(봇) 넉백 (P2(봇) 14%) 2타 반대 치기',
    '[1시]   [콤보] P1 → P2(봇) 3타 마무리',
    '[1시]   [평타] P1 → P2(봇) 넉백 (P2(봇) 25%) 3타 내려찍기',
    '[1시]   [평타] P1 블록 솟음 (4,4,0)',
    '[1시]   [평타] P2(봇) → P1 무적이라 무시 1타 찌르기',
    '[1시]   [카운터] P1 → P2(봇)',
    '[1시]   [폭발] P1 벽 3칸 → P2(봇) 24%',
    '[1시]   [폭발] P1 3타 블록 1칸',
    '[1시]   [필살] P1 대폭발 (1명, 같이 터진 블록 1칸)',
    '[1시]   [아머] P1 ← P2(봇) 버팀 (P1 12%)',
    '[1시]   [아머] P1 ← P2(봇) 깨짐',
    '[1시]   [표식] P1 → P2(봇) 1개',
    '[1시]   [포탄] P1 발사 (남은 2발)',
    '[1시]   [포탄] P1 → P2(봇) 넉백 (P2(봇) 30%)',
    '[1시]   [포탄] P1 블록 부숨 (3,4,1)',
    '[1시]   [필살] P1 대형 포탄 발사',
    '[1시]   [포탄] P1 대형 포탄 블록 3칸 부숨',
    '[1시]   [필살] P1 처형 사격 (P2(봇) 3개) 게이지 회수',
    '[1시]   [스킬] P1 광폭 도약',
    '[1시]   [스킬] P1 착지 충격파 → P2(봇) 36%',
    '[1시]   [필살] P1 분노 소용돌이 (분노 ×1.60, 피해 200% → 160%)',
    '[1시]   [필살] P1 소용돌이 끝 → P2(봇) 50%',
    '[1시]   [필살] P1 분노 소용돌이 (분노 ×1.00, 피해 0% → 0%)',
    '[1시]   [필살] P1 분노 소용돌이 끊김',
    '[1시]   [음파] P1 → P2(봇) 둔화 (P2(봇) 3%)',
    '[1시]   [스킬] P1 메탈 폼 (기타 리프 → P2(봇) 8%)',
    '[1시]   [스킬] P1 음유시인 폼 (치유 P1 25% → 15%)',
    '[1시]   [필살] P1 취약의 노래 → P2(봇)',
    '[1시]   [필살] P1 앰프 음파',
    '[1시]   [필살] P1 앰프 음파 끊김',
    '[1시]   [평타] P2(봇) → P1 넉백 치명타 (P1 8%) 공중 공중 베기',
    '[1시]   [평타] P2(봇) → P1 넉백 (P1 13%) 공중 2타 내려 차기',
    '[1시]   [사망] P2(봇) 낙사 @ 0:10 (위치 1.0, 2.0, -4.0, 피해 120%, 킬 P1 밀치기)',
    '[1시] ===== ROUND 1 종료 | 길이 0:12 | 승자: P1 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  assert.deepEqual(
    s.basics.map((x) => [x.key, x.byN, x.counters || 0]),
    [
      ['건축가', { 1: 1, 2: 1, 3: 1 }, 1],
      ['닌자 (봇)', { 0: 2 }, 0],
    ],
  );
  assert.ok(formatReport(s).includes('== 평타 명중 (타 번호별) =='));
  assert.ok(formatReport(s).includes('표식 1번 · 처형 사격 1번 (게이지 회수 1번)'));
  assert.ok(formatReport(s).includes('포탄 1발 · 명중 1 · 블록 부숨 4칸 · 대형 포탄 1번'));
  assert.deepEqual(s.builder, { armor: { held: 1, broken: 1 }, hunter: { marks: 1, shots: 1, refunds: 1 }, cannon: { fired: 1, hits: 1, broke: 4, big: 1 }, berserker: { leaps: 1, spins: 2, rage: 2.6, cut: 40, endHits: 1, broken: 1 }, bard: { notes: 1, toMetal: 1, toBard: 1, healed: 10, songs: 1, vuln: 1, amps: 1, ampBroken: 1 }, blasts: 2, wall: 1, third: 1, pad: 0, cells: 4, big: 1 });
  assert.ok(formatReport(s).includes('버팀 1번 · 깨짐 1번'));
  assert.ok(formatReport(s).includes('폭발 2번 (벽 1 · 3타 블록 1 · 발판 0, 평균 2.0칸) · 대폭발 1번'));
  assert.ok(formatReport(s).includes('음파 명중 1 · 메탈 전환 1 · 음유 전환 1 (치유 10%) · 취약의 노래 1번 (1명) · 앰프 음파 1번 (끊김 1)'));
  assert.ok(formatReport(s).includes('광폭 도약 1번 · 소용돌이 2번 (평균 분노 ×1.30 · 깎은 피해 평균 20% · 끝 날림 1명 · 끊김 1번)'));
});

test('통계: 하늘 계단 켬/끔을 나눠 보고 녹은 하늘 블록을 셈', () => {
  const text = [
    '===== ROUND 1 시작 (2명: P1 P2, 맵 평지) =====',
    '  하늘 계단: 켬',
    '  [하늘] T 용암에 녹음 (z=3)',
    '  [사망] P2 압사 @ 0:30',
    '===== ROUND 1 종료 | 길이 0:30 | 승자: P1 =====',
    '===== ROUND 2 시작 (2명: P1 P2, 맵 평지) =====',
    '  [사망] P1 낙사 @ 0:20',
    '===== ROUND 2 종료 | 길이 0:20 | 승자: P2 =====',
  ].join('\n');
  const s = summarize(parseLog(text));
  assert.deepEqual(s.bySky.map((g) => [g.key, g.rounds]).sort(), [['끔', 1], ['켬', 1]]);
  assert.equal(s.melts, 1);
  assert.match(formatReport(s), /하늘 계단별/);
});
