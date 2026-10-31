// client/figure.js 의 공격 동작 MOVES·끊김 BROKEN·도발/승리 포즈 POSES 자세 표 → chars/moves.gd (만든 파일, 손으로 고치지 않음)
// POSES 의 loop(t) 는 함수라 여기선 빠짐 → chars/figure_motion.gd 가 손으로 옮김 (fixtures.mjs 의 figure_motion.json 이 확인)
// 실행 (레포 뿌리): node godot/client/tools/gen-moves.mjs
import { register } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

register('../../../test/support/client-loader.mjs', import.meta.url);
const { MOVES, POSES } = await import('../../../client/figure.js');
const src = fs.readFileSync(new URL('../../../client/figure.js', import.meta.url), 'utf8');
const broken = src.match(/^const BROKEN = (\{.*\});$/m);
if (!broken) throw new Error('figure.js 에서 BROKEN 을 못 찾음');
const BROKEN = Function(`return (${broken[1]})`)();

const num = (v) => (Number.isInteger(v) ? `${v}.0` : String(v));
function gd(v) {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return num(v);
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) return `[${v.map(gd).join(', ')}]`;
  if (typeof v === 'function') throw new Error('함수는 못 옮김');
  return `{${Object.entries(v).map(([k, x]) => `${JSON.stringify(k)}: ${gd(x)}`).join(', ')}}`;
}
const poses = {};
for (const [who, sets] of Object.entries(POSES)) {
  poses[who] = {};
  for (const [kind, set] of Object.entries(sets)) {
    const { loop, ...rest } = set;
    poses[who][kind] = { ...rest, loop: !!loop };
  }
}
for (const [name, m] of Object.entries(MOVES)) for (const v of Object.values(m)) if (typeof v === 'function') throw new Error(`MOVES ${name} 에 함수`);
const out = [
  '# 만든 파일 — 고치지 말 것. node godot/client/tools/gen-moves.mjs 가 client/figure.js 에서 만듦',
  '# MOVES: 공격 동작 (W 준비 · S 타격 자세, 칸 이름은 figure.js 와 같음, [오른쪽, 왼쪽] 에서 null = 그대로) · BROKEN: 끊긴 공격 · POSES: 도발/승리 (loop 은 figure_motion.gd)',
  'extends RefCounted',
  '',
  `const MOVES := ${gd(MOVES)}`,
  `const BROKEN := ${gd(BROKEN)}`,
  `const POSES := ${gd(poses)}`,
  '',
];
const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '../chars/moves.gd');
fs.writeFileSync(file, out.join('\n'));
console.log(`moves.gd: MOVES ${Object.keys(MOVES).length}, POSES ${Object.keys(POSES).length}`);
