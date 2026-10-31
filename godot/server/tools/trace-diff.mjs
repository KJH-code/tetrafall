// 두 판 기록(JSONL, trace.mjs 형식)에서 처음 갈라지는 틱과 JSON 경로·값을 보여 줌. 실행: node godot/server/tools/trace-diff.mjs js.jsonl cs.jsonl
// 숫자만 다르면 비트(ulp) 차이도 보여 줌 → JsMath 를 안 쓴 곳 (System.Math.Sin 등) 찾기
import fs from 'node:fs';

const [a, b] = process.argv.slice(2).map((f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean));
function firstDiff(x, y, path = '') {
  if (typeof x !== typeof y || Array.isArray(x) !== Array.isArray(y) || (x === null) !== (y === null)) return { path, x, y };
  if (x && typeof x === 'object') {
    const keys = Array.isArray(x) ? [...Array(Math.max(x.length, y.length)).keys()] : [...new Set([...Object.keys(x), ...Object.keys(y)])];
    if (!Array.isArray(x) && Object.keys(x).join() !== Object.keys(y).join()) return { path: `${path} (키 순서)`, x: Object.keys(x), y: Object.keys(y) };
    for (const k of keys) {
      const d = firstDiff(x[k], y[k], `${path}${Array.isArray(x) ? `[${k}]` : `.${k}`}`);
      if (d) return d;
    }
    return null;
  }
  return x === y ? null : { path, x, y };
}
const ulp = (x, y) => {
  const f = new Float64Array([x, y]);
  const i = new BigInt64Array(f.buffer);
  return (i[0] > i[1] ? i[0] - i[1] : i[1] - i[0]).toString();
};
for (let i = 0; i < Math.max(a.length, b.length); i++) {
  if (a[i] === b[i]) continue;
  if (!a[i] || !b[i]) {
    console.log(`${i}번째 줄: 한쪽 기록이 끝남 (${a.length} vs ${b.length}줄)`);
    process.exit(1);
  }
  const A = JSON.parse(a[i]);
  const B = JSON.parse(b[i]);
  const logs = firstDiff(A.logs, B.logs, 'logs');
  const snap = firstDiff(JSON.parse(A.snap), JSON.parse(B.snap), 'snap');
  const d = snap || logs || { path: '(글자 모양: 숫자 쓰기·이스케이프)', x: A.snap.slice(0, 200), y: B.snap.slice(0, 200) };
  console.log(`틱 ${A.t} 에서 처음 갈라짐: ${d.path}`);
  console.log(`  A: ${JSON.stringify(d.x)}`);
  console.log(`  B: ${JSON.stringify(d.y)}`);
  if (typeof d.x === 'number' && typeof d.y === 'number') console.log(`  차이 ${d.x - d.y} (${ulp(d.x, d.y)} ulp) — 1~2 ulp 면 수학 함수 (JsMath) 의심`);
  if (logs && snap) console.log(`  로그도 다름: ${logs.path}`);
  process.exit(1);
}
console.log(`같음 (${a.length}줄)`);
