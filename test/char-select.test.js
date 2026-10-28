// 대기실 캐릭터 고르기 (shared/char-select.js): 큰 3D 캐릭터 방향·도발 시간, 랜덤 뽑기, 설명 데이터 빠짐 없음
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { stageYaw, tauntAt, randomReel } from '../shared/char-select.js';

function seeded(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

test('고르면 도발하는 동안 정면, 그 뒤 CHAR_STAGE_SPIN 으로 천천히 돎', () => {
  const hold = C.EMOTE_MS / 1000;
  assert.equal(stageYaw(0), 0);
  assert.equal(stageYaw(hold), 0);
  assert.ok(Math.abs(stageYaw(hold + 2) - 2 * C.CHAR_STAGE_SPIN) < 1e-9);
  assert.ok(C.CHAR_STAGE_SPIN > 0 && C.CHAR_STAGE_SPIN < 2, '천천히');
});

test('도발 포즈는 고른 뒤 EMOTE_MS 동안 한 번만', () => {
  assert.deepEqual(tauntAt(0), { on: true, t: 0 });
  assert.equal(tauntAt(C.EMOTE_MS / 2).on, true);
  assert.equal(tauntAt(C.EMOTE_MS + 1).on, false);
  assert.equal(tauntAt(-1).on, false);
  assert.equal(tauntAt(Infinity).on, false);
});

test('랜덤: 지금 캐릭터는 안 뽑음, 마지막 불 = 뽑힌 캐릭터, CHAR_RANDOM_MS 에 끝, 점점 느려짐, 미리 멈춰 보이지 않음', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const cur = C.CHARACTERS[seed % C.CHARACTERS.length];
    const { pick, steps } = randomReel(C.CHARACTERS, cur, seeded(seed));
    assert.notEqual(pick, cur);
    assert.ok(C.CHARACTERS.includes(pick));
    assert.equal(steps.at(-1).char, pick);
    assert.equal(steps.at(-1).at, C.CHAR_RANDOM_MS);
    assert.ok(steps.length >= 4, '몇 번은 돎');
    for (let i = 1; i < steps.length - 1; i++) assert.ok(steps[i].at - steps[i - 1].at >= steps[i - 1].at - (steps[i - 2]?.at ?? 0), '느려짐');
    assert.ok(steps.slice(0, -1).every((s) => s.char !== pick), '끝 전엔 뽑힌 칸에 불이 안 멈춤');
  }
  // 여러 번 뽑으면 다 나옴 (지금 것 빼고)
  const seen = new Set();
  const rnd = seeded(7);
  for (let i = 0; i < 400; i++) seen.add(randomReel(C.CHARACTERS, 'tank', rnd).pick);
  assert.equal(seen.size, C.CHARACTERS.length - 1);
});

test('설명 카드 데이터: 캐릭터마다 이름·한 줄 소개·F·R 설명', () => {
  for (const c of C.CHARACTERS) {
    for (const k of ['CHAR_NAMES', 'CHAR_INTRO', 'SKILL_NAMES', 'SKILL_DESC', 'ULT_NAMES', 'ULT_DESC']) assert.ok(typeof C[k][c] === 'string' && C[k][c].length > 0, `${k}.${c}`);
  }
});
