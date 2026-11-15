// 프레임 구성 한 번에 (W37): 장면 여럿을 재연 (core/replay.gd --budget) 으로 돌려 분류별 표 (그리기·삼각형·그림자 삼각형·그림·CPU ms) 를 모아 찍는다.
// 재혁 PC·다음 워커가 같은 표를 다시 뽑는 용 — 소프트웨어 렌더(xvfb+llvmpipe)·실제 GPU 둘 다 동작. GPU ms 는 이 표에 없음 (F3 패널·히치 로거로).
//   node godot/client/tools/frame_budget.cjs --godot <godot 실행파일> [--res 1280x720] [--secs 2] [--warm 8] [--only 이름,이름] [--rec-dir <폴더>] [--no-xvfb] [-- <고도 인자 더>]
//   장면: 녹화 (tests/fixtures 가 아니라 --rec-dir, 필수 (또는 환경 변수 BUDGET_RECS) — 녹화는 크다 (15MB) 라 레포 밖) 마다 하나. 없으면 tools/rec_chars.mjs 로 만든 파일을 둠 (README 참고).
//   --compare <앞에 저장한 .json> : 같은 장면의 합계를 전/후 열로.   --save <.json> : 결과 저장.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const dd = argv.indexOf('--');
const extra = dd >= 0 ? argv.slice(dd + 1) : [];
const godot = opt('--godot', process.env.GODOT || 'godot');
const res = opt('--res', '1280x720');
const secs = opt('--secs', '2');
const warm = opt('--warm', '8');
const only = opt('--only', '').split(',').filter(Boolean);
const recDir = opt('--rec-dir', process.env.BUDGET_RECS || '');
const proj = path.join(__dirname, '..');
const noX = argv.includes('--no-xvfb');

const recs = fs.existsSync(recDir) ? fs.readdirSync(recDir).filter((f) => f.endsWith('.rec')).sort() : [];
if (!recs.length) { console.error(`녹화 없음: '${recDir}' — --rec-dir (--rec 로 녹화 또는 tools/rec_chars.mjs 로 만든 .rec 폴더)`); process.exit(2); }
const fmt = (n) => (n / 1000).toFixed(1) + 'k';
const prev = opt('--compare', '') ? JSON.parse(fs.readFileSync(opt('--compare'), 'utf8')) : null;
function show(j) {
  console.log(`\n### ${j.label}  (${res}, 영상 메모리 ${j.vram_mb.toFixed(1)}MB)`);
  console.log('| 분류 | 노드 | 그리기 | 삼각형 | 그림자 삼각형 | 그림 MB |\n| --- | --: | --: | --: | --: | --: |');
  for (const r of j.rows) console.log(`| ${r.cat} | ${r.nodes} | ${r.draws} | ${fmt(r.tris)} | ${fmt(r.stris)} | ${(r.tex / 1048576).toFixed(1)} |`);
  const t = j.total;
  console.log(`| **합계 3D** | | ${t[0]} | ${fmt(t[4])} | ${fmt(t[5])} | |`);
  console.log(`| 2D (창) | | ${j.canvas} | | | |`);
  const ck = Object.keys(j.cpu).sort((a, b) => j.cpu[b] - j.cpu[a]);
  console.log(`\nCPU ms/프레임: ${ck.map((k) => `${k} ${j.cpu[k].toFixed(2)}`).join(' · ')}`);
  console.log(j.summary); console.log(j.growth);
  const p = prev && prev.find((x) => x.label === j.label);
  if (p) console.log(`전 → 후: 삼각형 ${fmt(p.total[4])} → ${fmt(t[4])} · 그림자 ${fmt(p.total[5])} → ${fmt(t[5])} · 그리기 ${p.total[0]} → ${t[0]} · 영상 메모리 ${p.vram_mb.toFixed(1)} → ${j.vram_mb.toFixed(1)}MB`);
}
const results = [];
for (const f of recs) {
  const name = f.replace(/\.rec$/, '');
  if (only.length && !only.includes(name)) continue;
  const args = ['--path', proj, '--rendering-driver', 'opengl3', '--resolution', res, '--', '--replay', path.join(recDir, f), '--replay-render', '--replay-fps', '60',
    '--replay-warm', warm, '--replay-secs', secs, '--prof', '--budget', '--budget-label', name, ...extra];
  const cmd = noX ? godot : 'xvfb-run';
  const full = noX ? args : ['-a', godot, ...args];
  process.stderr.write(`[${name}] 재는 중…\n`);
  const r = spawnSync(cmd, full, { encoding: 'utf8', maxBuffer: 1 << 28, timeout: Number(opt('--timeout', '900')) * 1000 });
  const out = (r.stdout || '') + (r.stderr || '');
  if (process.env.BUDGET_LOGS) fs.writeFileSync(path.join(process.env.BUDGET_LOGS, `${name}.log`), out);
  const m = out.split('\n').find((l) => l.startsWith('[구성json] '));
  if (!m) { console.error(`[${name}] 표 없음\n` + out.split('\n').slice(-15).join('\n')); continue; }
  const j = JSON.parse(m.slice(m.indexOf(' ') + 1));
  const sm = out.split('\n').find((l) => l.includes('[재연] 결과:')) || '';
  const mm = out.split('\n').find((l) => l.includes('[재연] 늘어남')) || '';
  j.summary = sm.replace('[재연] ', ''); j.growth = mm.replace('[재연] ', '');
  results.push(j);
  show(j);
}
if (opt('--save', '')) fs.writeFileSync(opt('--save', ''), JSON.stringify(results));
