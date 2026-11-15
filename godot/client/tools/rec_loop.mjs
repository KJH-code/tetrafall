// 녹화를 N번 이어 붙여 긴 판(길게 재연) 만들기 (W37, 3분 누수 확인용): 시각(앞 칸)과 서버 시각(state.time)을 한 바퀴 길이만큼 밀어 붙임.
// 사용: node rec_loop.mjs <in.rec> <out.rec> <N>
import fs from 'node:fs';

const [inp, out, ns] = process.argv.slice(2);
const n = Number(ns || 3);
const lines = fs.readFileSync(inp, 'utf8').split('\n').filter((l) => l.includes('\t'));
const t0 = parseFloat(lines[0]);
const t1 = parseFloat(lines[lines.length - 1]);
const span = t1 - t0 + 200;
const stSpan = (() => { // 서버 시각 한 바퀴 길이
  let hi = 0;
  for (const l of lines) { const m = /"time":([0-9.eE+-]+)/.exec(l.slice(0, 200)); if (m && l.includes('"type":"state"')) hi = Math.max(hi, parseFloat(m[1])); }
  return hi + 100;
})();
const res = [];
for (let k = 0; k < n; k++) {
  for (const l of lines) {
    const tab = l.indexOf('\t');
    const at = parseFloat(l.slice(0, tab)) + span * k;
    let body = l.slice(tab + 1);
    if (k > 0 && body.startsWith('{"type":"state"')) body = body.replace(/^({"type":"state","time":)([0-9.eE+-]+)/, (_, a, b) => a + (parseFloat(b) + stSpan * k));
    res.push(at + '\t' + body);
  }
}
fs.writeFileSync(out, res.join('\n'));
console.log(`${out}: ${n} 바퀴, 한 바퀴 ${(span / 1000).toFixed(1)}초`);
