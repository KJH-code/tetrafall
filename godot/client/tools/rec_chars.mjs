// 녹화 (--rec) 의 스냅샷에서 플레이어 캐릭터를 바꿔 새 녹화를 만든다 (W37 프레임 구성표용: 새 모델 4명 ×2 판·섞인 판 등을 서버 없이).
// 사용: node rec_chars.mjs <in.rec> <out.rec> <char,char,…>   (자리 순서대로, 모자라면 되풀이)
//   예: node rec_chars.mjs game8.rec all_new.rec ninja,tank,hunter,hook,ninja,tank,hunter,hook
// 규칙·판정은 안 건드림 — 보이는 몸만 바뀜 (위치·이벤트는 그대로, 캐릭터 고유 이벤트 모습은 안 맞을 수 있음).
import fs from 'node:fs';

const [inp, out, list] = process.argv.slice(2);
if (!inp || !out || !list) {
  console.error('사용: node rec_chars.mjs <in.rec> <out.rec> <char,char,…>');
  process.exit(2);
}
const chars = list.split(',');
const lines = fs.readFileSync(inp, 'utf8').split('\n');
const res = lines.map((l) => {
  const tab = l.indexOf('\t');
  if (tab < 0) return l;
  const body = l.slice(tab + 1);
  if (!body.startsWith('{"type":"state"') && !body.startsWith('{"type":"welcome"')) return l;
  const j = JSON.parse(body);
  if (Array.isArray(j.players)) j.players.forEach((p, i) => { p.char = chars[i % chars.length]; });
  return l.slice(0, tab + 1) + JSON.stringify(j);
});
fs.writeFileSync(out, res.join('\n'));
console.log(`${out}: ${chars.join(',')}`);
