// 1인칭 팔 (client/viewmodel.js) 숫자 뽑기 (W11): 캐릭터 몸에 동작 단계를 주고 figureAnim → ViewModel.update 뒤
// anchor 기준 방패·어깨·팔꿈치·손 변환. node godot/client/tools/vm_dump.mjs [캐릭터] > out.json
import { register } from 'node:module';
register('../../../test/support/client-loader.mjs', import.meta.url);
globalThis.document ??= { createElement: () => ({ width: 0, height: 0, getContext: () => new Proxy({}, { get: () => () => {}, set: () => true }) }) };
const THREE = await import('three');
const { CONFIG: C } = await import('../../../shared/config.js');
const { buildFigure, figureAnim } = await import('../../../client/figure.js');
const { ViewModel } = await import('../../../client/viewmodel.js');
const ch = process.argv[2] || 'tank';
const DT = 1 / 60;
const base = () => ({ air: false, walking: false, hs: 0, walk: 0, vz: 0, t: 0, stunned: false, dancing: false, emote: -1, emoteT: 0, victory: -1, punch: 0, holding: false, hit: null, act: null, accF: 0, accS: 0, tumble: 0, recover: 0, land: 0, flip: -1, rag: false, sniffAt: null, idle: 0, airDash: 0, bump: null, whirl: -1, dizzy: 0, glide: false, amp: false });
const set = C.BASIC_ATTACKS[ch];
const moves = [...set.chain.map((a) => a.name), ...set.air.map((a) => a.name)];
const R = (x) => Math.round(x * 1e4) / 1e4;
const rel = (o, root) => {
  const m = new THREE.Matrix4();
  for (let n = o; n && n !== root; n = n.parent) {
    n.updateMatrix();
    m.premultiply(n.matrix);
  }
  return m;
};
const dec = (m) => {
  const p = new THREE.Vector3(), q = new THREE.Quaternion(), s = new THREE.Vector3();
  m.decompose(p, q, s);
  return { p: p.toArray().map(R), q: q.toArray().map(R), s: s.toArray().map(R) };
};
const out = [];
// seq: 한 몸으로 1타 → 끝 타를 이어서 (실제 준비·타격·회복 시간, 60fps) — 동작 사이 자세 이어짐까지 대조. 아니면 동작마다 새 몸
const seq = process.argv[3] === 'seq';
const all = [...set.chain, ...set.air];
const frames = (mi) => (seq ? [['wind', Math.ceil(all[mi].windup / 1000 / DT)], ['strike', Math.ceil(C.FIGURE_STRIKE_S / DT)], ['rec', Math.ceil(all[mi].rec / 1000 / DT)]] : [['wind', 8], ['strike', 6], ['rec', 10]]);
let built, g, vm, t;
moves.forEach((move, mi) => {
  if (!seq || mi === 0) built = buildFigure(0xffffff, ch, null);
  if (!seq || mi === 0) {
    g = built.group;
    g.userData.look = ch;
    g.userData.figure = built.figure;
    g.userData.anim = { hs: 0, walk: 0, t: 0 };
    vm = new ViewModel();
    vm.sync(g);
    vm.on = true;
    t = 1;
  }
  const fig = built.figure;
  for (const [ph, k] of frames(mi)) {
    for (let i = 0; i < k; i++) {
      t += DT;
      const act = { id: mi + 1, move, phase: ph, u: (i + 1) / k, air: mi >= set.chain.length };
      figureAnim(fig, { ...base(), t, act, air: seq && act.air }, DT);
      g.userData.anim.t = 0; // 숨쉬기 끔 (비교용)
      vm.update(DT, act);
      const row = { move, phase: ph, u: R(act.u) };
      const sh = vm.shield;
      if (sh) {
        row.shieldVis = sh.visible;
        row.shieldLocal = { p: sh.position.toArray().map(R), r: [sh.rotation.x, sh.rotation.y, sh.rotation.z].map(R), s: sh.scale.toArray().map(R) };
        row.shield = dec(rel(sh, vm.anchor));
      }
      row.waist = dec(rel(vm.twin.waist, vm.anchor));
      row.shoulders = vm.twin.shoulders.map((o) => dec(rel(o, vm.anchor)));
      row.elbows = vm.twin.elbows.map((o) => dec(rel(o, vm.anchor)));
      row.srcWaist = [fig.waist.rotation.x, fig.waist.rotation.y, fig.waist.rotation.z].map(R);
      row.srcSh = fig.shoulders.map((o) => [o.rotation.x, o.rotation.y, o.rotation.z].map(R));
      row.srcEl = fig.elbows.map((o) => [o.rotation.x, o.rotation.y, o.rotation.z].map(R));
      row.anchor = { p: vm.anchor.position.toArray().map(R), q: vm.anchor.quaternion.toArray().map(R), s: R(vm.anchor.scale.x) };
      out.push(row);
    }
  }
});
console.log(JSON.stringify(out));
