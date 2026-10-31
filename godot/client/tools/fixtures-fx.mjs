// G5 효과 계산의 정답 자료 (JS client/effects.js·ko.js 를 시각을 고정해 돌림) → tests/fixtures/fx.json. 실행 (레포 뿌리): node godot/client/tools/fixtures-fx.mjs
// shake: 흔들림 이어 받기 (센 것이 이김)·세기 · squash·punch: 찌그러짐·팔 뻗음 곡선 · timeScale: 압사 히트스톱·마지막 킬 슬로모션
// plume: 스매시 줄기 크기·투명도 · smash: 줄기 자리 (필드 끝으로 자름)·방향 · cam: 마지막 킬 줌 (시야·보는 쪽) · edge: 화면 끝 번쩍 자리
// bblocks.json: 건축가 블록 부품·솟기·금·깜빡임·R 준비·무너짐·조각 수 (shared/bblock-look.js)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { register } from 'node:module';

register('../../../test/support/client-loader.mjs', import.meta.url);
let T = 1000;
performance.now = () => T;
const el = () => ({ style: {}, classList: { add() {}, remove() {} } });
globalThis.document = { createElement: el, body: { appendChild() {} } };
const THREE = await import('three');
const { CONFIG: C } = await import('../../../shared/config.js');
const { Effects } = await import('../../../client/effects.js');
const { KO } = await import('../../../client/ko.js');

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures');
const scene = new THREE.Scene();
const fx = new Effects(scene);
const res = {};

// 흔들림: [시각, 세기, ms] 차례로 → 그때 남은 세기 (amp·ms·until)
res.shake = [];
for (const [t, amp, ms] of [[0, 0.1, 200], [50, 0.05, 300], [60, 0.3, 450], [300, 0.1, 100], [520, 0.05, 280], [900, 0.2, 280], [1000, 0.19, 280]]) {
  T = 1000 + t;
  fx.shake(amp, ms);
  res.shake.push({ t, amp, ms, gotAmp: fx.shakeAmp, gotMs: fx.shakeMs, gotUntil: fx.shakeUntil - 1000 });
}
res.squash = [];
res.punch = [];
for (let t = 0; t <= 400; t += 17) {
  T = 5000;
  fx.hitSquash(1);
  fx.startPunch(1);
  T = 5000 + t;
  res.squash.push([t, fx.squashAmount(1)]);
  res.punch.push([t, fx.punchAmount(1)]);
}

// KO
const field = { w: 12, d: 12 };
const ko = new KO(scene, fx, { colorOf: () => 0xff4040, field: () => field });
T = 10000;
ko.death({ who: 1, cause: 'crush', x: 3, y: 3, z: 1 }, null, false, 2); // 가까운 압사 → 히트스톱
const ts = [];
for (const t of [0, 50, 119, 121, 200]) ts.push([t, ko.timeScale(10000 + t)]);
T = 20000;
ko.final({ who: 2, x: 5, y: 6, z: 1 });
for (let t = 0; t <= 1700; t += 50) ts.push([10000 + t, ko.timeScale(20000 + t)]);
res.timeScale = ts;

// 스매시 줄기: 필드 밖 자리 → 줄기 자리·방향, 프레임마다 크기·투명도
res.smash = [];
for (const [p, o] of [[{ x: -2, y: 5, z: -4 }, { x: -1, y: 0 }], [{ x: 14, y: 13, z: 3 }, { x: 0.7, y: 0.7 }], [{ x: 6, y: -1, z: 0.5 }, { x: 0, y: -1 }]]) {
  const before = ko.plumes.length;
  ko.smash(p, o, 0xffffff, false, false);
  const m = ko.plumes[before].mesh;
  const up = new THREE.Vector3(0, 1, 0).applyQuaternion(m.quaternion);
  res.smash.push({ p, out: o, at: [m.position.x, m.position.y, m.position.z], dir: [up.x, up.y, up.z] });
}
ko.plumes.splice(0, ko.plumes.length - 1);
const pl = ko.plumes[0];
res.plume = [];
for (let i = 0; i < 60; i++) {
  ko.update(1 / 60);
  if (!ko.plumes.includes(pl)) break;
  res.plume.push([pl.age, pl.mesh.scale.x, pl.mesh.scale.y, pl.mesh.material.opacity]);
}

// 마지막 킬 줌: 카메라 자리·보는 곳 → 시야·보는 쪽 (게임 좌표, z 위)
res.cam = [];
for (const [t, eye, look, target] of [
  [100, [0, 0, 5], [6, 6, 1], [5, 6, 1]],
  [800, [0, 0, 5], [6, 6, 1], [5, 6, 1]],
  [1500, [2, -3, 8], [6, 2, 0], [1, 9, 2]],
  [800, [10, 10, 2], [10, 0, 2], [0, 10, 0]],
]) {
  const cam = new THREE.PerspectiveCamera(70, 1, 0.1, 500);
  cam.up.set(0, 0, 1);
  cam.position.set(...eye);
  cam.lookAt(new THREE.Vector3(...look));
  T = 30000;
  ko.final({ who: 2, x: target[0], y: target[1], z: target[2] });
  T = 30000 + t;
  ko.camHook(cam);
  const f = new THREE.Vector3(0, 0, -1).applyQuaternion(cam.quaternion);
  res.cam.push({ t, eye, look, target, fov: cam.fov, fwd: [f.x, f.y, f.z] });
}

// 화면 끝 번쩍: 투영된 자리 (sx, sy, 카메라 뒤) → 백분율 자리
res.edge = [];
ko.edgeColor = '#ffffff';
for (const [sx, sy, sz] of [[0.2, 0.1, 0.5], [-0.9, 0.3, 0.5], [2.5, -0.4, 0.5], [0.3, 0.6, 1.5], [0, 0, 0.5], [-3, -3, 0.9]]) {
  const cam = new THREE.PerspectiveCamera(70, 1, 0.1, 500);
  cam.updateMatrixWorld();
  cam.updateProjectionMatrix();
  const v = new THREE.Vector3(sx, sy, sz).unproject(cam);
  ko.edgeAt = { x: v.x, y: v.y, z: v.z };
  ko.edgeUntil = T + C.KO_EDGE_MS * 0.5;
  ko.drawEdge(cam, T);
  const m = /at ([-\d.e]+)% ([-\d.e]+)%/.exec(ko.edgeEl.style.background);
  res.edge.push({ sx, sy, behind: sz > 1, px: +m[1], py: +m[2], alpha: +ko.edgeEl.style.opacity });
}

fs.writeFileSync(path.join(out, 'fx.json'), JSON.stringify(res));
console.log('fx.json', Object.fromEntries(Object.entries(res).map(([k, v]) => [k, v.length])));

// ---------- G6 건축가 블록 (shared/bblock-look.js) → bblocks.json ----------
const BL = await import('../../../shared/bblock-look.js');
const bb = { parts: {}, rise: [], crack: [], flash: [], big: [], collapse: [], shards: [] };
for (const k of BL.BB_KINDS) bb.parts[k] = BL.bblockParts(k);
for (let u = -0.1; u <= 1.1; u += 0.05) bb.rise.push([u, BL.riseScale(u)]);
for (const l of [5000, 3500, 3499, 2000, 1000, 400, 0, -50]) bb.crack.push([l, BL.crackOf(l)]);
for (const l of [2000, 1500, 1499, 1000, 499, 200, 0]) for (const now of [0, 69, 71, 139, 141, 210, 300]) bb.flash.push([l, now, BL.flashOf(l, now)]);
for (const l of [900, 800, 600, 400, 200, 0]) for (const now of [0, 123, 456, 789]) bb.big.push([l, now, BL.bigPrep(l, now)]);
for (let u = -0.2; u <= 1.2; u += 0.1) bb.collapse.push([u, BL.collapseAt(u)]);
for (const k of [...BL.BB_KINDS, 'collapse']) for (const low of [false, true]) bb.shards.push([k, low, BL.shardCount(k, low)]);
fs.writeFileSync(path.join(out, 'bblocks.json'), JSON.stringify(bb));
console.log('bblocks.json');

// ---------- G6 성능 표시 (shared/perf.js) → perf.json ----------
const PF = await import('../../../shared/perf.js');
{
  const { mulberry32 } = await import('../../../tools/sim.js');
  const r = mulberry32(5);
  const w = new PF.PerfWindow();
  const frames = [];
  const sums = [];
  let t = 0;
  for (let i = 0; i < 700; i++) {
    const ms = 14 + r() * 6 + (i % 97 === 0 ? 60 : 0);
    t += ms;
    const sec = { ragdoll: r() * 2, grid: r(), render: 3 + r() * 2 };
    if (i % 5 === 0) sec.hazard = 0.5;
    const work = ms * 0.6;
    frames.push([t, ms, sec, work]);
    w.push(t, ms, sec, work);
    if (i % 50 === 49) sums.push([i, w.summary(t)]);
  }
  const gpus = ['ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)', 'ANGLE (Intel, Intel(R) UHD Graphics 620 (0x00005917) Direct3D11 vs_5_0 ps_5_0, D3D11)', 'Mesa Intel(R) UHD Graphics (CML GT2)', 'NVIDIA GeForce GTX 1050/PCIe/SSE2', 'AMD Radeon Pro 5500M OpenGL Engine', 'Apple M1', '', 'ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)'];
  const lines = [[sums[sums.length - 1][1], {}], [sums[3][1], { draws: 120, tris: 45678, players: 8, rag: 8, low: false, size: '1280×720', gpu: 'Apple M1', ping: '30ms' }], [sums[5][1], { draws: 7, tris: 999, players: 2, low: true }]];
  fs.writeFileSync(path.join(out, 'perf.json'), JSON.stringify({ frames, sums, worst: [[[], 0.01, PF.worstAvg([], 0.01)], [[5, 1, 9, 3], 0.01, PF.worstAvg([5, 1, 9, 3], 0.01)], [[5, 1, 9, 3, 7, 2], 0.5, PF.worstAvg([5, 1, 9, 3, 7, 2], 0.5)]], gpus: gpus.map((g) => [g, PF.shortGpu(g)]), lines: lines.map(([s, e]) => [s, e, PF.perfLine(s, e)]) }));
  console.log('perf.json');
}

// ---------- G6 튜토리얼 화면 (shared/tutorial.js) → tutorial_ui.json ----------
{
  const T = await import('../../../shared/tutorial.js');
  const keyName = (id) => `<${id}>`;
  const texts = [];
  for (const st of C.TUTORIAL_STEPS) for (const ch of ['tank', 'bard', 'ninja']) texts.push([st.id, ch, T.stepText(st, { char: ch, keyName })]);
  const prog = [];
  for (let i = -1; i < 14; i++) prog.push([i, T.progressLabel(i)]);
  const done = [[], ['ok'], ['ok', 'skip'], ['skip', 'skip'], ['ok', 'ok', 'ok'], null].map((r) => [r, T.doneMessage(r)]);
  fs.writeFileSync(path.join(out, 'tutorial_ui.json'), JSON.stringify({ texts, prog, done }));
  console.log('tutorial_ui.json');
}
