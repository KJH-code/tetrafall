// shared/config.js · shared/maps.js → core/config.gd (GDScript 상수). JS config 를 바꾸면 다시 돌림 (JS 가 원본, 이 파일은 만든 파일).
// 실행 (레포 뿌리): node godot/client/tools/gen-config.mjs
// - 이름은 JS 그대로: C.TICK_RATE, C.WORLD_THEMES["meadow"]["sky"] ...
// - 숫자는 전부 float (JS 와 같은 계산: 1000 / C.TICK_RATE 가 정수 나눗셈이 되지 않게). 배열 첨자로 쓸 땐 int()
// - 표(객체·배열)도 그대로 const Dictionary·Array. 함수 (spawnPointsFor 등) 만 빠짐 → 파일 끝 주석
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG } from '../../../shared/config.js';
import { MAPS, MAP_IDS } from '../../../shared/maps.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const num = (x) => {
  if (x === Infinity) return 'INF';
  if (x === -Infinity) return '-INF';
  if (Number.isNaN(x)) return 'NAN';
  const s = String(x);
  return /[.eE]/.test(s) ? s : `${s}.0`;
};
const skipped = [];
function lit(v, k) {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return num(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'function') return undefined;
  if (Array.isArray(v)) {
    const items = v.map((x) => lit(x, k));
    return items.includes(undefined) ? undefined : `[${items.join(', ')}]`;
  }
  if (typeof v === 'object') {
    const parts = [];
    for (const [a, b] of Object.entries(v)) {
      const l = lit(b, k);
      if (l === undefined) return undefined;
      parts.push(`${JSON.stringify(a)}: ${l}`);
    }
    return `{${parts.join(', ')}}`;
  }
  return undefined;
}
const lines = [];
for (const [k, v] of Object.entries(CONFIG)) {
  const l = lit(v, k);
  if (l === undefined) skipped.push(k);
  else lines.push(`const ${k} = ${l}`);
}
lines.push(`const MAP_IDS = ${lit(MAP_IDS)}`, `const MAPS = ${lit(MAPS)}`);
const out = `# 만든 파일 — 고치지 말 것. node godot/client/tools/gen-config.mjs 가 shared/config.js·shared/maps.js 에서 만듦
# 쓰기: const C := preload("res://core/config.gd") → C.TICK_RATE. 숫자는 전부 float (첨자는 int())
extends RefCounted

${lines.join('\n')}

# 빠진 값 (함수): ${skipped.join(' ')}
`;
fs.writeFileSync(path.join(here, '../core/config.gd'), out);
console.log(`config.gd: 값 ${lines.length}개, 빠진 함수 ${skipped.length}개 (${skipped.join(' ')})`);
