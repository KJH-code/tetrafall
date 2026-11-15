// W49 모션 설정 조합 순회: 같은 재연 (녹화) 을 프리셋·플래그 조합마다 돌려 (xvfb 소프트웨어 렌더, 그리기는 끔) 모션 QA 의 튐 (팝) 수·SCRIPT ERROR·엔진 경고·종료 코드를 표로 모은다.
//   조합 = 전부 켬 (새) · 옛 · 최소 · 플래그 하나씩 끔 (--no-<플래그>) + 판 중 토글 (--motion-script) 한 번.
// 쓰는 법: node godot/client/tools/motion_combos.mjs --godot <godot 실행파일> --rec <녹화.rec> [--secs 20] [--out <폴더>] [--only new,old,toggle,no-gaze …]
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, existsSync, writeFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i >= 0 ? process.argv[i + 1] : d; };
const godot = arg('godot');
const rec = arg('rec');
const secs = arg('secs', '20');
const out = resolve(arg('out', 'motion-combos'));
const only = arg('only', '') ? arg('only').split(',') : null;
if (!godot || !rec) { console.error('--godot 와 --rec 필요'); process.exit(2); }
const proj = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const FLAGS = ['gait_new', 'dir', 'lean', 'getup', 'weapon', 'cloth', 'gaze', 'land_breath', 'hit_dir', 'vm_arm', 'pop_fix'];
const combos = [
  { name: 'new', args: [] },
  { name: 'old', args: ['--motion', 'old'] },
  { name: 'min', args: ['--motion', 'min'] },
  ...FLAGS.map((f) => ({ name: 'no-' + f.replace(/_/g, '-'), args: ['--no-' + f.replace(/_/g, '-')] })),
  { name: 'toggle', args: ['--motion-script', '4:old,8:new,12:min,16:new'] },
];
mkdirSync(out, { recursive: true });
const rows = [];
for (const c of combos) {
  if (only && !only.includes(c.name)) continue;
  const dir = join(out, c.name);
  mkdirSync(dir, { recursive: true });
  const a = ['-a', '-s', '-screen 0 1280x720x24', godot, '--path', proj, '--rendering-driver', 'opengl3', '--resolution', '960x540', '--fixed-fps', '120', '--',
    '--replay', rec, '--replay-fps', '120', '--replay-secs', secs, '--replay-warm', '0', '--no-pose-lod', '--set', 'third=true', '--motion-qa', dir, ...c.args];
  const t0 = Date.now();
  const r = spawnSync('xvfb-run', a, { encoding: 'utf8', timeout: 1200000, maxBuffer: 1 << 28 });
  const log = (r.stdout || '') + (r.stderr || '');
  writeFileSync(join(dir, 'log.txt'), log);
  const j = existsSync(join(dir, 'motion_qa.json')) ? JSON.parse(readFileSync(join(dir, 'motion_qa.json'), 'utf8')) : null;
  let pops = 0, cloth = 0, samples = 0;
  for (const ch of Object.values(j?.chars ?? {})) { pops += ch.pops; cloth += (ch.pop_by?.cloth ?? 0); samples += ch.samples; }
  rows.push({
    name: c.name, rc: r.status, secs: ((Date.now() - t0) / 1000).toFixed(0), samples, pops, cloth_pops: cloth,
    script_errors: (log.match(/SCRIPT ERROR/g) || []).length,
    engine_warn: (log.match(/cannot be normalized|must be normalized|must not be zero|det == 0/g) || []).length,
    toggles: j?.toggles ? j.toggles.list.map((l) => `${l.t}s→${l.preset}: ${l.pops_1s_after}`).join(' · ') + ` (재연 평균 ${j.toggles.pops_per_s_avg}/초)` : '',
  });
  console.log(JSON.stringify(rows.at(-1)));
}
const head = '| 조합 | rc | 표본 | 튐 | 천 튐 | SCRIPT ERROR | 엔진 경고 | 토글 직후 1초 튐 |\n| --- | --: | --: | --: | --: | --: | --: | --- |';
console.log('\n' + head + '\n' + rows.map((r) => `| ${r.name} | ${r.rc} | ${r.samples} | ${r.pops} | ${r.cloth_pops} | ${r.script_errors} | ${r.engine_warn} | ${r.toggles} |`).join('\n'));
writeFileSync(join(out, 'table.md'), head + '\n' + rows.map((r) => `| ${r.name} | ${r.rc} | ${r.samples} | ${r.pops} | ${r.cloth_pops} | ${r.script_errors} | ${r.engine_warn} | ${r.toggles} |`).join('\n') + '\n');
