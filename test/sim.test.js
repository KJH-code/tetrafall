// 봇 판 시뮬레이션 (tools/sim.js): 판 목록·재현·워커 나눔·집계
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseArgs, planJobs, runJob, runParallel, summarizeSim, formatSim, mulberry32 } from '../tools/sim.js';
import { CONFIG as C } from '../shared/config.js';

const small = (extra = []) => parseArgs(['--rounds', '4', '--players', '2,3', '--maps', 'flat,stairs', '--no-log', ...extra]);

test('sim: 판 목록은 (인원, 맵) 짝마다 같은 수, 자리 바꾼 판은 같은 시드·거꾸로 캐릭터', () => {
  const o = small();
  const jobs = planJobs(o);
  assert.equal(jobs.length, 2 * 2 * 1 * 2); // 짝 4개 × 짝당 1판 × 자리 바꿔 2번
  for (let i = 0; i < jobs.length; i += 2) {
    assert.equal(jobs[i].seed, jobs[i + 1].seed);
    assert.deepEqual(jobs[i + 1].chars, [...jobs[i].chars].reverse());
    assert.equal(new Set(jobs[i].chars).size, jobs[i].n, '캐릭터가 인원보다 많으면 안 겹침');
    for (const c of jobs[i].chars) assert.ok(C.CHARACTERS.includes(c));
  }
  assert.deepEqual(planJobs(o), jobs, '같은 옵션이면 같은 목록');
  assert.notDeepEqual(planJobs(small(['--seed', '2'])).map((j) => j.seed), jobs.map((j) => j.seed));
  assert.equal(planJobs(small(['--no-mirror'])).length, 4);
});

test('sim: 캐릭터 풀이 인원보다 작으면 겹쳐서 뽑음', () => {
  const jobs = planJobs(small(['--players', '4', '--chars', 'tank,ninja']));
  for (const j of jobs) {
    assert.equal(j.chars.length, 4);
    for (const c of j.chars) assert.ok(['tank', 'ninja'].includes(c));
  }
});

test('sim: 같은 판은 다시 돌려도 결과가 같다 (game.rng 하나로 재현)', () => {
  const o = small();
  const job = planJobs(o)[0];
  const a = runJob(job, o);
  const b = runJob(job, o);
  assert.deepEqual(a, b);
  assert.ok(a.lenMs > 0);
  assert.ok(a.winSeats.length <= 1);
});

test('sim: 워커 수와 상관없이 결과가 같다', async () => {
  const o1 = small(['--workers', '1']);
  const o2 = small(['--workers', '3']);
  const jobs = planJobs(o1);
  const [r1, r2] = await Promise.all([runParallel(jobs, o1), runParallel(jobs, o2)]);
  assert.deepEqual(r1, r2);
  assert.deepEqual(r1.map((r) => r.id), jobs.map((j) => j.id), '판 순서대로 정렬');
});

test('sim: ×기대 는 판마다 1/인원 합 기준, 공동 승리는 나눔, 비교 열', () => {
  const R = (n, chars, winSeats, lenMs = 1000) => ({ n, chars, winSeats, lenMs, causes: { crush: 1, fall: n - 2, lava: 0 }, timeout: false });
  const s = summarizeSim([R(2, ['tank', 'ninja'], [0]), R(4, ['tank', 'ninja', 'bard', 'hook'], [0]), R(2, ['tank', 'ninja'], [0, 1]), R(2, ['tank', 'ninja'], [])]);
  const tank = s.chars.find((x) => x.char === 'tank');
  assert.equal(tank.rounds, 4);
  assert.equal(tank.wins, 2.5);
  assert.equal(tank.expect, 0.5 * 3 + 0.25);
  assert.equal(tank.byN[4].wins / tank.byN[4].expect, 4);
  assert.equal(s.draws, 1);
  assert.equal(s.chars[0].char, 'tank', '×기대 높은 순');
  const text = formatSim(s, s);
  assert.ok(text.includes('탱크'));
  assert.ok(text.includes('+0.00'), '같은 결과와 비교하면 차이 0');
});

test('sim: 시드 난수는 0~1, 시드마다 다름', () => {
  const r = mulberry32(7);
  const xs = Array.from({ length: 1000 }, r);
  assert.ok(xs.every((x) => x >= 0 && x < 1));
  assert.notEqual(mulberry32(1)(), mulberry32(2)());
});

test('sim: 잘못된 옵션은 거절', () => {
  assert.throws(() => parseArgs(['--players', '1']));
  assert.throws(() => parseArgs(['--maps', 'nope']));
  assert.throws(() => parseArgs(['--chars', 'wizard']));
  assert.throws(() => parseArgs(['--level', 'insane']));
  assert.throws(() => parseArgs(['--what']));
});
