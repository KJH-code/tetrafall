// 모션 QA 결과 모으기 (W44): 재연마다 core/motion_qa.gd 가 남긴 motion_qa.json 들을 캐릭터별·결함 종류별 표 (마크다운) 로 합치고, 두 묶음의 전후 차이를 낸다.
//   node godot/client/tools/motion_qa.mjs <결과 폴더>                  결과 폴더 아래 */motion_qa.json 전부를 합침
//   node godot/client/tools/motion_qa.mjs <전 폴더> <후 폴더>          전 → 후 열
//   --top N   상위 목록 길이 (기본 20)   --only pop,slide  목록 종류만
//   재연 돌리기: godot --path godot/client --rendering-driver opengl3 --fixed-fps 120 -- --replay <녹화> --replay-fps 120 --replay-secs 44 --replay-warm 0 --no-pose-lod --set third=true --motion-qa <출력 폴더>
//   (헤드리스 --headless 는 판 몸을 안 만듦 — world.gd 가 건너뜀. xvfb-run 으로 소프트웨어 렌더 켜고, 그리기는 replay 가 끔)
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const dirs = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
const topN = Number(opt('--top', 20));
const only = opt('--only', '').split(',').filter(Boolean);
if (!dirs.length) { console.error('사용: node motion_qa.mjs <결과 폴더> [<후 폴더>]'); process.exit(2); }

function load(root) {
  const files = [];
  for (const d of fs.readdirSync(root)) {
    const f = path.join(root, d, 'motion_qa.json');
    if (fs.existsSync(f)) files.push([d, JSON.parse(fs.readFileSync(f, 'utf8'))]);
  }
  return files;
}

const add = (o, k, v) => { o[k] = (o[k] || 0) + v; };
const mx = (o, k, v) => { o[k] = Math.max(o[k] ?? -Infinity, v); };

// 캐릭터별 합침
function merge(files) {
  const out = {};
  for (const [, j] of files) {
    for (const [ch, c] of Object.entries(j.chars)) {
      if (c.samples < 30) continue; // 허수아비·잠깐 보인 몸 제외
      const o = (out[ch] ||= { samples: 0, excluded: 0, pops: 0, soft: 0, pop_cls: {}, pop_worst: 0, jit_bad: 0, jit_win: 0, slide: {}, idle_n: 0, idle_bad: 0, idle_sum: 0, sunk: 0, ground: 0, floaty: 0,
        cloth_pen: 0, cloth_of: 0, cloth_max: 0, st_hi: 0, st_n: 0, st_max: 0, w_pen: 0, w_n: 0, w_max: 0, lim: {}, lim_worst: {}, flicker: 0, seam: {} });
      add(o, 'samples', c.samples); add(o, 'excluded', c.excluded); add(o, 'pops', c.pops); add(o, 'soft', c.pops_soft);
      for (const [k, v] of Object.entries(c.pop_by)) add(o.pop_cls, k, v);
      mx(o, 'pop_worst', c.pop_worst);
      add(o, 'jit_bad', c.jitter.bad); add(o, 'jit_win', c.jitter.windows);
      for (const [k, v] of Object.entries(c.slide)) { const s = (o.slide[k] ||= { n: 0, bad: 0, sum: 0, p95: 0 }); s.n += v.n; s.bad += v.bad; s.sum += v.mean * v.n; s.p95 = Math.max(s.p95, v.p95); }
      add(o, 'idle_n', c.idle_drift.n); add(o, 'idle_bad', c.idle_drift.bad); add(o, 'idle_sum', c.idle_drift.mean * c.idle_drift.n);
      add(o, 'sunk', c.foot.sunk); add(o, 'ground', c.foot.ground_frames); add(o, 'floaty', c.foot.float);
      add(o, 'cloth_pen', c.cloth_pen.frames); add(o, 'cloth_of', c.cloth_pen.of); mx(o, 'cloth_max', c.cloth_pen.max);
      add(o, 'st_hi', c.stretch.hi); add(o, 'st_n', c.stretch.samples); mx(o, 'st_max', c.stretch.max);
      add(o, 'w_pen', c.weapon_pen.frames); add(o, 'w_n', c.weapon_pen.samples); mx(o, 'w_max', c.weapon_pen.max);
      for (const [k, v] of Object.entries(c.limits)) add(o.lim, k, v);
      for (const [k, v] of Object.entries(c.limit_worst)) mx(o.lim_worst, k, v);
      add(o, 'flicker', c.clip_flicker);
      for (const [pair, s] of Object.entries(c.seam)) {
        const q = (o.seam[pair] ||= { n: 0, jump_sum: 0, peak_max: 0, jump_max: 0, bone: '', clip: '' });
        q.n += s.n; q.jump_sum += s.jump_mean * s.n; q.jump_max = Math.max(q.jump_max, s.jump_max);
        if (s.peak_max > q.peak_max) { q.peak_max = s.peak_max; q.bone = s.bone; q.clip = s.clip; }
      }
    }
  }
  return out;
}

const CHARS = ['ninja', 'tank', 'hunter', 'hook'];
const sum = (o) => Object.values(o).reduce((a, b) => a + b, 0);
const f1 = (x) => (Math.round(x * 10) / 10).toString();
const f2 = (x) => (Math.round(x * 100) / 100).toString();
const f3 = (x) => (Math.round(x * 1000) / 1000).toString();

// 표 한 줄 = [이름, (캐릭터마다 값)] — 전후면 '전 → 후'
function rows(m) {
  const g = (ch, fn) => (m[ch] ? fn(m[ch]) : '-');
  const slideBad = (o) => sum(Object.fromEntries(Object.entries(o.slide).map(([k, v]) => [k, v.bad])));
  const slideN = (o) => sum(Object.fromEntries(Object.entries(o.slide).map(([k, v]) => [k, v.n])));
  const slideMean = (o, kind) => (o.slide[kind] ? f2(o.slide[kind].sum / o.slide[kind].n) : '-');
  const R = [
    ['표본 (60Hz, 래그돌 제외 후)', (o) => `${o.samples - o.excluded}`],
    ['**팝 (몸통·팔다리·손발머리)** 임계 35/60°·급가속', (o) => `${o.pops - (o.pop_cls.cloth || 0)}`],
    ['  └ 약한 팝 (임계 절반)', (o) => `${o.soft}`],
    ['  └ 최악 각속도 (°/프레임)', (o) => f1(o.pop_worst)],
    ['**천 팝** (임계 80°)', (o) => `${o.pop_cls.cloth || 0}`],
    ['떨림 창 (서 있을 때)', (o) => `${o.jit_bad}/${o.jit_win}`],
    ['**발 미끄러짐** 나쁜 디딤/걸음 디딤', (o) => `${slideBad(o)}/${slideN(o)}`],
    ['  └ 앞 비 평균 · 뒤 · 옆', (o) => `${slideMean(o, 'fwd')} · ${slideMean(o, 'back')} · ${slideMean(o, 'side')}`],
    ['  └ 정지 중 발 끌림 (>4cm)', (o) => `${o.idle_bad}/${o.idle_n}`],
    ['발 박힘 / 뜸 (땅 프레임 중)', (o) => `${o.sunk} / ${o.floaty} (${o.ground})`],
    ['**천 뚫림** 프레임 (>2cm)', (o) => `${o.cloth_pen}/${o.cloth_of} (최대 ${f3(o.cloth_max)}m)`],
    ['**무기 뚫림** 프레임 (>2cm)', (o) => `${o.w_pen}/${o.w_n} (최대 ${f3(o.w_max)}m)`],
    ['**삼각형 늘어남** (몸, ×2.2↑)', (o) => `${o.st_hi}/${o.st_n} (최대 ×${f1(o.st_max)})`],
    ['관절 한계: 반대 굽힘·과굽힘·목·척추', (o) => `${o.lim.rev || 0} · ${o.lim.over || 0} · ${o.lim.neck || 0} · ${o.lim.spine || 0}`],
    ['클립 깜빡임 (0.3초 안 재전환)', (o) => `${o.flicker}`],
  ];
  return R.map(([name, fn]) => [name, ...CHARS.map((ch) => g(ch, fn))]);
}

function table(m) {
  const lines = ['| 결함 | ' + CHARS.join(' | ') + ' |', '| --- | ' + CHARS.map(() => '--:').join(' | ') + ' |'];
  for (const r of rows(m)) lines.push('| ' + r.join(' | ') + ' |');
  return lines.join('\n');
}

function table2(a, b) {
  const ra = rows(a), rb = rows(b);
  const lines = ['| 결함 | ' + CHARS.join(' | ') + ' |', '| --- | ' + CHARS.map(() => '--:').join(' | ') + ' |'];
  for (let i = 0; i < ra.length; i++) lines.push('| ' + [ra[i][0], ...CHARS.map((_, k) => (ra[i][k + 1] === rb[i][k + 1] ? ra[i][k + 1] : `${ra[i][k + 1]} → ${rb[i][k + 1]}`))].join(' | ') + ' |');
  return lines.join('\n');
}

function seams(m) {
  const lines = ['| 전환 | ' + CHARS.join(' | ') + ' |', '| --- | ' + CHARS.map(() => '--:').join(' | ') + ' |'];
  const pairs = new Set();
  for (const ch of CHARS) for (const p of Object.keys(m[ch]?.seam || {})) pairs.add(p);
  const list = [...pairs].filter((p) => !p.includes('rag'));
  list.sort((x, y) => Math.max(...CHARS.map((c) => m[c]?.seam[y]?.peak_max || 0)) - Math.max(...CHARS.map((c) => m[c]?.seam[x]?.peak_max || 0)));
  for (const p of list.slice(0, 12)) lines.push(`| ${p} | ` + CHARS.map((ch) => { const s = m[ch]?.seam[p]; return s ? `${s.n}회 · 전환 순간 평균 ${f1(s.jump_sum / s.n)}° · 이후 0.25초 최고 ${f1(s.peak_max)}°` : '-'; }).join(' | ') + ' |');
  return lines.join('\n');
}

function tops(files, kind) {
  const all = [];
  for (const [name, j] of files) for (const r of j.top[kind] || []) all.push({ ...r, rec: name });
  all.sort((a, b) => b.sev - a.sev);
  const lines = ['| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |', '| --: | --- | --- | --: | --- | --- | --: | --- | --- |'];
  all.slice(0, topN).forEach((r, i) => lines.push(`| ${i + 1} | ${r.char} | ${r.bone} | ${f2(r.sev)} | ${r.state} | ${r.clip} | ${f1(r.t)} | ${r.rec} | ${r.extra || ''} |`));
  return lines.join('\n');
}

const A = load(dirs[0]);
const mA = merge(A);
if (dirs.length > 1) {
  const B = load(dirs[1]);
  console.log(`## 전 (${dirs[0]}) → 후 (${dirs[1]})\n`);
  console.log(table2(mA, merge(B)));
} else {
  console.log(`## ${dirs[0]} (재연 ${A.map(([n]) => n).join(', ')})\n`);
  console.log(table(mA));
  console.log('\n### 상태 전환 이음새 (래그돌 관련 전환 뺌)\n');
  console.log(seams(mA));
  for (const kind of ['pop', 'slide', 'pen', 'weapon', 'stretch', 'limit', 'seam', 'flicker', 'jitter']) {
    if (only.length && !only.includes(kind)) continue;
    console.log(`\n### 상위 ${topN}: ${kind}\n`);
    console.log(tops(A, kind));
  }
}
