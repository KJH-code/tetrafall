// shared/config.js · shared/maps.js → src/Tetrafall.Core/Config.g.cs · Maps.g.cs (C# 상수). JS 판이 얼어 있는 동안은 JS 값이 원본:
// JS config 를 바꾸면 다시 돌림. 실행: node godot/server/tools/gen-config.mjs
// 이름은 JS 그대로 (C.TICK_RATE) 라 규칙 코드를 줄 단위로 옮기기 쉬움. 숫자는 전부 double (JS 와 같은 계산)
// 표(객체·객체 배열)는 아직 안 만듦 → 파일 끝 주석 목록. 그 묶음을 옮기는 세션이 손으로 (또는 이 도구를 늘려) 넣음
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
  else skipped.push(k);
}
const head = '// 만든 파일 — 고치지 말 것. node godot/server/tools/gen-config.mjs 가 shared/config.js 에서 만듦\n#pragma warning disable CS1591\nnamespace Tetrafall.Core;\n\n';
fs.writeFileSync(
  path.join(outDir, 'Config.g.cs'),
  `${head}public static partial class C\n{\n${lines.join('\n')}\n}\n\n// 아직 안 만든 값 (표·함수 등, ${skipped.length}개): ${skipped.join(' ')}\n`,
);
fs.writeFileSync(
  path.join(outDir, 'Maps.g.cs'),
  `${head}public static partial class Maps\n{\n    public static readonly string[] MAP_IDS = { ${MAP_IDS.map(str).join(', ')} };\n    public static readonly Dictionary<string, (string Name, string Log)> MAPS = new() { ${Object.entries(MAPS).map(([id, m]) => `[${str(id)}] = (${str(m.name)}, ${str(m.log)})`).join(', ')} };\n}\n`,
);
console.log(`Config.g.cs: 값 ${lines.length}개, 아직 안 만든 값 ${skipped.length}개 / Maps.g.cs: 맵 ${MAP_IDS.length}개`);
