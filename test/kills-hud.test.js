// 킬 점수전 화면 계산 (shared/kills-hud.js): 킬·죽음·자멸·연속 킬 세기, 위 점수 띠 (1~N위 + 나), Tab 점수표, 부활 초, 체력전 HP
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { KillTally, streakText, progress, topBar, scoreRows, respawnSecs, hpFrac, hpView, hpColor } from '../shared/kills-hud.js';

test('킬·죽음·자멸·연속 킬: 죽으면 연속 0, 킬 없음·자기 자신은 자멸, 서버 필드가 있으면 그것', () => {
  const t = new KillTally();
  assert.equal(t.add({ who: 2, by: 1 }), 1);
  assert.equal(t.add({ who: 3, by: 1 }), 2);
  assert.equal(t.add({ who: 4, by: 1 }), 3);
  assert.equal(t.add({ who: 1, by: null }), 0, '자멸');
  assert.equal(t.add({ who: 2, by: 2 }), 0, '자기 자신 = 자멸');
  assert.deepEqual(t.stats({ id: 1 }), { kills: 3, deaths: 1, self: 1, streak: 0 });
  assert.deepEqual(t.stats({ id: 2 }), { kills: 0, deaths: 2, self: 1, streak: 0 });
  assert.equal(t.add({ who: 3, by: 4, streak: 5 }), 5, '서버 streak 가 오면 그 값');
  assert.deepEqual(t.stats({ id: 9, kills: 7, deaths: 2, selfKills: 1, streak: 4 }), { kills: 7, deaths: 2, self: 1, streak: 4 }, '서버 필드 먼저');
  t.reset();
  assert.deepEqual(t.stats({ id: 1 }), { kills: 0, deaths: 0, self: 0, streak: 0 });
});

test('연속 킬 글자: KILLS_STREAK_MIN 부터, 표 밖은 N연속 킬', () => {
  assert.equal(streakText(C.KILLS_STREAK_MIN - 1), '');
  assert.equal(streakText(0), '');
  assert.equal(streakText(2), C.KILLS_STREAK_TEXT[2]);
  assert.equal(streakText(9), '9연속 킬');
});

test('위 점수 띠: 1~N위 + 나 (밖이면 덧붙임), 같은 점수는 같은 등수, 관전자·허수아비 뺌, 진행 0~1', () => {
  const ps = [
    { id: 1, slot: 0, score: 2 },
    { id: 2, slot: 1, score: 5 },
    { id: 3, slot: 2, score: 5 },
    { id: 4, slot: 3, score: 1 },
    { id: 5, slot: 4, score: -1 },
    { id: 6, slot: 5, score: 9, spectator: true },
  ];
  const top = topBar(ps, 5);
  assert.deepEqual(top.map((r) => r.id), [2, 3, 1, 5]);
  assert.deepEqual(top.map((r) => r.rank), [1, 1, 3, 5]);
  assert.ok(top.at(-1).me && top.at(-1).extra, '나는 끝에 덧붙임');
  assert.equal(topBar(ps, 2).length, C.KILLS_TOP_N, '내가 안에 있으면 덧붙이지 않음');
  assert.equal(progress(3, 7), 3 / 7);
  assert.equal(progress(-2, 7), 0);
  assert.equal(progress(9, 7), 1);
});

test('Tab 점수표: 개인전 점수 순, 팀전은 빨강 팀 먼저 묶음, 킬·죽음·자멸 같이', () => {
  const t = new KillTally();
  t.add({ who: 2, by: 1 });
  const ps = [
    { id: 1, slot: 0, score: 1, team: 'blue' },
    { id: 2, slot: 1, score: 0, team: 'red' },
    { id: 3, slot: 2, score: 3, team: 'blue' },
  ];
  assert.deepEqual(scoreRows(ps, t, false).map((r) => r.id), [3, 1, 2]);
  assert.deepEqual(scoreRows(ps, t, true).map((r) => r.id), [2, 3, 1]);
  const r1 = scoreRows(ps, t, false).find((r) => r.id === 1);
  assert.equal(r1.kills, 1);
  assert.equal(scoreRows(ps, t, false).find((r) => r.id === 2).deaths, 1);
});

test('부활 초는 올림, 체력전 HP 는 hp·hpMax 가 있을 때만 0~1', () => {
  assert.equal(respawnSecs(C.KILLS_RESPAWN_MS), C.KILLS_RESPAWN_MS / 1000);
  assert.equal(respawnSecs(4001), 5);
  assert.equal(respawnSecs(1), 1);
  assert.equal(respawnSecs(0), 0);
  assert.equal(respawnSecs(null), 0);
  assert.equal(hpFrac({ hp: 50, hpMax: 200 }), 0.25);
  assert.equal(hpFrac({ hp: -5, hpMax: 100 }), 0);
  assert.equal(hpFrac({ damage: 30 }), null, '체력전 아님');
  assert.equal(hpFrac(null), null);
  assert.equal(hpFrac({ hp: 60 }, 120), 0.5, '스냅샷 맨 위 hpMax (A1 서버)');
  assert.equal(hpFrac({ hp: 60 }), null, 'hpMax 없음');
});

test('체력전 화면: 켜면 남은 HP (올림, 0 아래 없음)·사람마다 최대·낮음, 끄면 null (예전 %)', () => {
  const st = { hpMode: true, hpMax: 120 };
  assert.deepEqual(hpView({ hp: 86.2, damage: 33.8 }, st), { hp: 87, max: 120, frac: 86.2 / 120, low: false });
  assert.equal(hpView({ hp: 300, hpMax: 400 }, st).max, 400, '사람마다 hpMax 먼저');
  assert.equal(hpView({ hp: 300, hpMax: 400 }, st).frac, 0.75);
  assert.equal(hpView({ hp: -4 }, st).hp, 0);
  assert.equal(hpView({ hp: 20 }, st).low, 20 / 120 < C.HUD_HP_LOW);
  assert.equal(hpView({ hp: 60 }, { hpMax: 120 }), null, '체력전 끔');
  assert.equal(hpView({ damage: 30 }, st), null, 'HP 모름');
  assert.equal(hpView(null, st), null);
  assert.equal(hpView({ hp: 60 }, null), null);
});

test('HP 글자색: 가득 흰색 → 반 노랑 → 0 빨강, 범위 밖은 잘림', () => {
  assert.deepEqual(hpColor(1), [255, 255, 255]);
  assert.deepEqual(hpColor(0.5), [255, 255, 0]);
  assert.deepEqual(hpColor(0), [255, 40, 0]);
  assert.deepEqual(hpColor(1.5), [255, 255, 255]);
  assert.deepEqual(hpColor(-1), [255, 40, 0]);
  const [, g1] = hpColor(0.4);
  const [, g2] = hpColor(0.2);
  assert.ok(g1 > g2, '낮을수록 빨강 쪽');
});
