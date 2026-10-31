// shared/config.js · shared/maps.js → src/Tetrafall.Core/Config.g.cs · Maps.g.cs (C# 상수). JS 판이 얼어 있는 동안은 JS 값이 원본:
// JS config 를 바꾸면 다시 돌림. 실행: node godot/server/tools/gen-config.mjs
// 이름은 JS 그대로 (C.TICK_RATE) 라 규칙 코드를 줄 단위로 옮기기 쉬움. 숫자는 전부 double (JS 와 같은 계산)
// 표(객체·객체 배열)는 서버가 쓰는 것만 (SERVER_TABLES, 모양은 값에서 짐작해 클래스 T<이름> 을 만듦). 화면 전용 표는 파일 끝 주석 목록
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG } from '../../../shared/config.js';
import { MAPS, MAP_IDS } from '../../../shared/maps.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(here, '../src/Tetrafall.Core');
const num = (x) => (x === Infinity ? 'double.PositiveInfinity' : x === -Infinity ? 'double.NegativeInfinity' : Number.isNaN(x) ? 'double.NaN' : String(x));
const str = (s) => JSON.stringify(s);
const lines = [];
const skipped = [];
const tables = [];
// 서버 규칙이 쓰는 표 (server/·shared/tutorial.js 가 C.이름 으로 읽음). 나머지 표는 화면 전용이라 안 만듦.
// SPAWN_POINTS·spawnPointsFor 는 함수라 손으로 (ConfigFns.cs)
const SERVER_TABLES = ['BASIC_ATTACKS', 'KILLS_TARGET_BY_COUNT', 'KILLS_TARGET_TEAM_BY_COUNT', 'BOT_LEVELS', 'TUTORIAL_STEPS', 'TUTORIAL_DONE_TEXT'];
const HAND = ['SPAWN_POINTS', 'spawnPointsFor'];

// ---- 표 → C# (모양을 값에서 짐작) ----
// 객체의 값이 다 객체면 Dictionary<string, T> (키 = 캐릭터·모드·인원 등), 숫자뿐이면 Dictionary<string, double>, 그 밖의 객체는 클래스 (필드 = JS 키 그대로).
// 배열은 T[]. 여러 값의 모양을 합칠 때 어떤 값에 없는 필드는: 숫자 double? · 글자 string? · 참거짓 false · 나머지 null (JS undefined 처럼)
const classes = [];
const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
function shapeOf(v) {
  if (typeof v === 'number') return { k: 'num' };
  if (typeof v === 'string') return { k: 'str' };
  if (typeof v === 'boolean') return { k: 'bool' };
  if (Array.isArray(v)) {
    if (!v.length) return { k: 'arr', el: null }; // 빈 배열: 다른 값과 합칠 때 그쪽 모양
    const prims = v.every((x) => typeof x === 'number' || typeof x === 'string');
    if (prims && new Set(v.map((x) => typeof x)).size > 1) return { k: 'arr', el: { k: 'any' } }; // [x, y, '이름'] 같은 섞인 칸
    return { k: 'arr', el: v.map(shapeOf).reduce(merge) };
  }
  if (isObj(v)) {
    const vals = Object.values(v);
    if (vals.length && vals.every(isObj)) {
      const all = vals.map(shapeOf);
      if (all.every((s) => s.k === 'dict' || s.k === 'cls')) return { k: 'dict', el: all.reduce(merge) };
    }
    if (vals.length && vals.every((x) => typeof x === 'number')) return { k: 'dict', el: { k: 'num' } };
    const f = {};
    for (const [a, b] of Object.entries(v)) f[a] = { s: shapeOf(b), opt: false };
    return { k: 'cls', f };
  }
  throw new Error(`표 값 모양을 모름: ${JSON.stringify(v)}`);
}
function merge(a, b) {
  if (!a || !b) return a || b;
  if (a.k === 'any' || b.k === 'any') return { k: 'any' };
  if (a.k !== b.k) {
    if (new Set([a.k, b.k]).size === 2 && [a.k, b.k].every((k) => k === 'num' || k === 'str')) return { k: 'any' };
    if ([a.k, b.k].every((k) => k === 'dict' || k === 'cls')) return merge(asCls(a), asCls(b));
    throw new Error(`표 모양이 섞임: ${a.k} / ${b.k}`);
  }
  if (a.k === 'arr' || a.k === 'dict') return { k: a.k, el: merge(a.el, b.el) };
  if (a.k !== 'cls') return a;
  const f = {};
  for (const key of new Set([...Object.keys(a.f), ...Object.keys(b.f)])) {
    const x = a.f[key];
    const y = b.f[key];
    f[key] = x && y ? { s: merge(x.s, y.s), opt: x.opt || y.opt } : { s: (x || y).s, opt: true };
  }
  return { k: 'cls', f };
}
// 숫자 dict 를 클래스와 합칠 일은 없음 (안전하게 에러)
function asCls(s) {
  if (s.k === 'cls') return s;
  throw new Error('dict 와 클래스가 섞임');
}
const pascal = (s) => s.toLowerCase().split('_').map((w) => w[0].toUpperCase() + w.slice(1)).join('');
function typeName(s, name) {
  if (s.k === 'num') return 'double';
  if (s.k === 'str') return 'string';
  if (s.k === 'bool') return 'bool';
  if (s.k === 'any') return 'object';
  if (s.k === 'arr') return `${s.el ? typeName(s.el, name) : 'double'}[]`;
  if (s.k === 'dict') return `Dictionary<string, ${typeName(s.el, name)}>`;
  if (!s.name) {
    s.name = s.want || name;
    name = s.name;
    const fields = Object.entries(s.f).map(([key, { s: fs, opt }]) => {
      const sub = name + key[0].toUpperCase() + key.slice(1);
      const t = typeName(fs, sub);
      const nul = opt && t !== 'bool' ? '?' : '';
      return `    public ${t}${nul} ${key};`;
    });
    classes.push(`public sealed partial class ${name}\n{\n${fields.join('\n')}\n}`);
  }
  return s.name;
}
function value(v, s) {
  if (s.k === 'num') return num(v);
  if (s.k === 'str') return str(v);
  if (s.k === 'bool') return String(v);
  if (s.k === 'any') return typeof v === 'number' ? `(object)${num(v)}` : str(v);
  if (s.k === 'arr') return `new ${s.el ? typeName(s.el) : 'double'}[] { ${v.map((x) => value(x, s.el)).join(', ')} }`;
  if (s.k === 'dict') return `new() { ${Object.entries(v).map(([a, b]) => `[${str(a)}] = ${value(b, s.el)}`).join(', ')} }`;
  return `new ${s.name}() { ${Object.entries(v).map(([a, b]) => `${a} = ${value(b, s.f[a].s)}`).join(', ')} }`;
}
// 평타 표: 체인·공중·메탈·loaded·ammo 칸이 다 같은 '평타 하나' (JS 코드가 def 하나로 다룸) → 클래스 하나 TAttack 로 합침
const UNIFY = { BASIC_ATTACKS: { name: 'TAttack', is: (s) => s.k === 'cls' && s.f.name && s.f.windup } };
function unify(root, { name, is }) {
  const found = [];
  const walk = (s) => {
    if (!s || found.includes(s)) return;
    if (s.k === 'cls') {
      if (is(s)) found.push(s);
      for (const { s: fs } of Object.values(s.f)) walk(fs);
    } else if (s.k === 'arr' || s.k === 'dict') walk(s.el);
  };
  walk(root);
  const U = found.reduce(merge);
  U.want = name;
  const seen = new Set();
  const swap = (s) => {
    if (!s || seen.has(s)) return s;
    seen.add(s);
    if (s.k === 'cls') for (const f of Object.values(s.f)) f.s = is(f.s) ? U : swap(f.s);
    else if (s.k === 'arr' || s.k === 'dict') s.el = is(s.el) ? U : swap(s.el);
    return s;
  };
  for (const f of Object.values(U.f)) if (f.s && is(f.s)) f.s = U;
  swap(U);
  return is(root) ? U : swap(root);
}
function genTable(k, v) {
  let s = shapeOf(v);
  if (UNIFY[k]) s = unify(s, UNIFY[k]);
  const t = typeName(s, `T${pascal(k)}`);
  return `    public static readonly ${t} ${k} = ${value(v, s)};`;
}
for (const [k, v] of Object.entries(CONFIG)) {
  const t = typeof v;
  if (t === 'number') lines.push(`    public const double ${k} = ${num(v)};`);
  else if (t === 'string') lines.push(`    public const string ${k} = ${str(v)};`);
  else if (t === 'boolean') lines.push(`    public const bool ${k} = ${v};`);
  else if (Array.isArray(v) && v.length && v.every((x) => typeof x === 'number')) lines.push(`    public static readonly double[] ${k} = { ${v.map(num).join(', ')} };`);
  else if (Array.isArray(v) && v.length && v.every((x) => typeof x === 'string')) lines.push(`    public static readonly string[] ${k} = { ${v.map(str).join(', ')} };`);
  else if (v && t === 'object' && !Array.isArray(v) && Object.values(v).length && Object.values(v).every((x) => typeof x === 'number'))
    lines.push(`    public static readonly Dictionary<string, double> ${k} = new() { ${Object.entries(v).map(([a, b]) => `[${str(a)}] = ${num(b)}`).join(', ')} };`);
  else if (v && t === 'object' && !Array.isArray(v) && Object.values(v).length && Object.values(v).every((x) => typeof x === 'string'))
    lines.push(`    public static readonly Dictionary<string, string> ${k} = new() { ${Object.entries(v).map(([a, b]) => `[${str(a)}] = ${str(b)}`).join(', ')} };`);
  else if (SERVER_TABLES.includes(k)) tables.push(k);
  else skipped.push(k);
}
const tableOut = tables.map((k) => genTable(k, CONFIG[k]));
const head = '// 만든 파일 — 고치지 말 것. node godot/server/tools/gen-config.mjs 가 shared/config.js 에서 만듦\n#nullable enable\n#pragma warning disable CS1591, CS8618\nnamespace Tetrafall.Core;\n\n';
fs.writeFileSync(
  path.join(outDir, 'Config.g.cs'),
  `${head}public static partial class C\n{\n${lines.join('\n')}\n\n    // ---- 표 (서버 규칙이 쓰는 것) ----\n${tableOut.join('\n')}\n}\n\n${classes.join('\n\n')}\n\n// 손으로 옮긴 값 (함수): ${skipped.filter((k) => HAND.includes(k)).join(' ')} → ConfigFns.cs\n// 화면 전용이라 안 만든 값 (${skipped.filter((k) => !HAND.includes(k)).length}개): ${skipped.filter((k) => !HAND.includes(k)).join(' ')}\n`,
);
fs.writeFileSync(
  path.join(outDir, 'Maps.g.cs'),
  `${head}public static partial class Maps\n{\n    public static readonly string[] MAP_IDS = { ${MAP_IDS.map(str).join(', ')} };\n    public static readonly Dictionary<string, (string Name, string Log)> MAPS = new() { ${Object.entries(MAPS).map(([id, m]) => `[${str(id)}] = (${str(m.name)}, ${str(m.log)})`).join(', ')} };\n}\n`,
);
console.log(`Config.g.cs: 값 ${lines.length}개 + 표 ${tables.length}개, 화면 전용·손으로 ${skipped.length}개 / Maps.g.cs: 맵 ${MAP_IDS.length}개`);
