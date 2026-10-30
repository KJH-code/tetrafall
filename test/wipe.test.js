// 화면 전환 슬래시 (shared/wipe.js): 어느 화면 바뀜에 어느 전환인지, 띠 시간표, 판 시작을 늦추지 않음
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { screenOf, wipeKind, wipePlan } from '../shared/wipe.js';

test('화면 분류: 방 밖 · 대기실 · 판 · 결과 연출 (결과가 끝난 판 끝은 대기실)', () => {
  assert.equal(screenOf({ inRoom: false, phase: 'playing', hero: false }), 'menu');
  assert.equal(screenOf({ inRoom: true, phase: 'lobby', hero: false }), 'lobby');
  assert.equal(screenOf({ inRoom: true, phase: 'countdown', hero: false }), 'game');
  assert.equal(screenOf({ inRoom: true, phase: 'playing', hero: false }), 'game');
  assert.equal(screenOf({ inRoom: true, phase: 'over', hero: true }), 'results');
  assert.equal(screenOf({ inRoom: true, phase: 'over', hero: false }), 'lobby');
});

test('재혁이 고른 전환만: 메뉴→방 짧게, 판 시작·결과 등장 크게, 결과→대기실 짧게', () => {
  assert.equal(wipeKind('menu', 'lobby'), 'short'); // 만들기·들어가기
  assert.equal(wipeKind('menu', 'game'), 'short'); // 연습 (바로 판)
  assert.equal(wipeKind('lobby', 'game'), 'big'); // 판 시작
  assert.equal(wipeKind('results', 'game'), 'big'); // 결과 중에 Enter 재시작
  assert.equal(wipeKind('game', 'results'), 'big'); // 판 끝 → 결과
  assert.equal(wipeKind('results', 'lobby'), 'short'); // 결과 → 대기실 판
  // 안 하는 것: 같은 화면, 연습·결과 없는 판 끝, 처음 그리기
  for (const [a, b] of [['lobby', 'lobby'], ['game', 'game'], ['game', 'lobby'], [null, 'lobby'], [null, 'menu']]) assert.equal(wipeKind(a, b), null, `${a}→${b}`);
  assert.equal(wipeKind('lobby', 'menu'), 'short'); // 방 나가기
  assert.equal(wipeKind('game', 'menu'), 'short');
});

test('짧은 전환은 0.3~0.5초, 큰 전환은 0.6~1초 (재혁 기준), 큰 쪽이 더 김', () => {
  const s = wipePlan('short');
  const b = wipePlan('big');
  assert.ok(s.ms >= 300 && s.ms <= 500, `short ${s.ms}`);
  assert.ok(b.ms >= 600 && b.ms <= 1000, `big ${b.ms}`);
  assert.ok(b.bands.length > s.bands.length);
});

test('띠 시간표: 모두 전체 길이 안에 끝나고, 늦게 출발, 화면 밖 → 다 덮음 → 화면 밖', () => {
  for (const kind of Object.keys(C.UI_WIPE)) {
    const p = wipePlan(kind);
    assert.equal(p.bands.length, C.UI_WIPE[kind].bands);
    let prev = -1;
    for (const band of p.bands) {
      assert.ok(band.delay > prev, '뒤 띠가 늦게 출발');
      prev = band.delay;
      assert.ok(band.delay + band.ms <= p.ms + 1e-9, `${kind} 띠가 전체 길이 안에 끝남`);
      const offs = band.frames.map((f) => f.offset);
      assert.deepEqual(offs, [...offs].sort((x, y) => x - y), '키프레임 순서');
      assert.equal(offs[0], 0);
      assert.equal(offs.at(-1), 1);
      assert.equal(band.frames[0].x, C.UI_WIPE_X.from);
      assert.equal(band.frames.at(-1).x, C.UI_WIPE_X.to);
      assert.ok(band.frames.some((f) => f.x === C.UI_WIPE_X.cover), '다 덮는 자리를 지남');
    }
    // 화면 교체는 마지막(남색) 띠가 다 덮은 때 — 끝나기 전, 시작 뒤
    assert.ok(p.coverMs > 0 && p.coverMs < p.ms, `${kind} coverMs ${p.coverMs}`);
    const last = p.bands.at(-1);
    assert.ok(Math.abs(p.coverMs - (last.delay + C.UI_WIPE_IN * last.ms)) < 1e-9);
  }
});

test('띠 자리: 시작·끝은 화면 밖, 다 덮는 자리는 화면(0~100vw)을 가림 (띠 폭 210vw, index.html)', () => {
  const W = 210; // index.html #wipe .band width
  const X = C.UI_WIPE_X;
  assert.ok(X.from + W <= 0, '시작은 왼쪽 밖');
  assert.ok(X.to >= 100, '끝은 오른쪽 밖');
  assert.ok(X.cover <= 0 && X.cover + W >= 100, '다 덮음');
});

test('그래픽 낮춤·움직임 줄이기: 띠 없이 짧은 페이드', () => {
  for (const kind of ['short', 'big']) {
    const p = wipePlan(kind, true);
    assert.equal(p.fade, true);
    assert.equal(p.bands.length, 0);
    assert.equal(p.ms, C.UI_WIPE_FADE_MS);
    assert.ok(p.ms < wipePlan('short').ms, '슬래시보다 짧음');
    assert.ok(p.coverMs > 0 && p.coverMs < p.ms);
  }
  assert.equal(wipePlan(null), null);
  assert.equal(wipePlan('nope'), null);
});

test('판 시작 슬래시는 카운트다운보다 짧음 (카운트다운이 끝나기 전에 사라져 첫 입력을 안 가림)', () => {
  assert.ok(wipePlan('big').ms < C.ROUND_COUNTDOWN_MS);
});

// 판 끝 순서 (shared/victory.js): 슬로모션 → 승자 클로즈업 → 결과 표 → 대기실 판
import { victoryPlan, victoryStage } from '../shared/victory.js';
test('판 끝: 승자 클로즈업 뒤 결과, 슬로모션이 남았으면 그 뒤, 승자 없으면 바로 결과', () => {
  const p = victoryPlan({ star: true, slowLeftMs: 1600 });
  assert.equal(p.closeupAt, 1600);
  assert.equal(p.resultsAt, 1600 + C.VICTORY_CLOSEUP_MS);
  assert.equal(p.endAt, p.resultsAt + C.RESULTS_HERO_MS);
  assert.equal(victoryStage(p, 0), 'slow');
  assert.equal(victoryStage(p, 1600), 'closeup');
  assert.equal(victoryStage(p, p.resultsAt - 1), 'closeup');
  assert.equal(victoryStage(p, p.resultsAt), 'results');
  assert.equal(victoryStage(p, p.endAt), 'lobby');
  assert.ok(C.VICTORY_CLOSEUP_MS >= 2000 && C.VICTORY_CLOSEUP_MS <= 3000, '2~3초');
  // 승자 없음·무승부: 바로 결과
  const none = victoryPlan({ star: false, slowLeftMs: 1600 });
  assert.equal(victoryStage(none, 0), 'results');
  // 움직임 줄이기: 짧게
  const red = victoryPlan({ star: true, reduced: true });
  assert.equal(red.resultsAt, C.VICTORY_CLOSEUP_REDUCED_MS);
  assert.ok(C.VICTORY_CLOSEUP_REDUCED_MS < C.VICTORY_CLOSEUP_MS);
  assert.equal(victoryPlan({ star: true, slowLeftMs: NaN }).closeupAt, 0);
  // 클로즈업 동안은 판 화면 그대로 (결과 슬래시는 그 뒤: game → results)
  assert.equal(screenOf({ inRoom: true, phase: 'over', hero: false, closeup: true }), 'game');
  assert.equal(wipeKind('game', 'results'), 'big');
});
