// 로그 요약 (tools/stats.js) 테스트: 실제 게임이 찍는 로그를 그대로 읽는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { parseLog, summarize, formatReport } from '../tools/stats.js';

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
