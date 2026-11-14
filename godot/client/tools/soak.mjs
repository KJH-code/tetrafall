// 스트레스 시험 실행기 (W50): JS 서버 + xvfb 고도 클라 (tools/soak.gd) 를 띄워 한 시나리오를 돌리고 추세 표를 찍음. 큰 로그는 파일로 안 남김 (줄 수 세기·표본 줄만 모음).
// 사용: node soak.mjs <시나리오> [--n N] [--bots N] [--port P] [--godot 경로] [--extra "--adapt ..."] [--timeout 초]
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import readline from 'node:readline';

const argv = process.argv.slice(2);
const scen = argv[0] || 'rounds';
const opt = (k, d) => { const i = argv.indexOf('--' + k); return i >= 0 ? argv[i + 1] : d; };
const here = path.dirname(new URL(import.meta.url).pathname);
const root = path.resolve(here, '../../..');
const client = path.resolve(here, '..');
const godot = opt('godot', process.env.GODOT || '/home/user/tools-dl/Godot_v4.7.2-stable_linux.x86_64');
const port = Number(opt('port', 3400 + Math.floor(Math.random() * 400)));
const n = opt('n', '10');
const bots = opt('bots', '3');
const extra = (opt('extra', '') || '').split(' ').filter(Boolean);
const timeout = Number(opt('timeout', 1500)) * 1000;
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'soakhome-'));

const server = spawn('node', ['server/index.js'], { cwd: root, env: { ...process.env, PORT: String(port) }, stdio: 'ignore' });
await new Promise((r) => setTimeout(r, 1500));
const env = { ...process.env, HOME: home, XDG_DATA_HOME: path.join(home, 'data'), XDG_CONFIG_HOME: path.join(home, 'cfg') };
// 가져온 import 캐시는 프로젝트 안 .godot 라 HOME 과 무관
const g = spawn('xvfb-run', ['-a', godot, '--rendering-method', 'gl_compatibility', '--path', client, '--', '--server', `ws://127.0.0.1:${port}`, '--soak', scen, '--soak-n', n, '--bots', bots, '--soak-sample', opt('sample', '0'), ...extra], { env, stdio: ['ignore', 'pipe', 'pipe'] });
const rows = [];
let lines = 0, bad = 0, aborted = false;
const kinds = {};
const onLine = (l) => {
  lines++;
  if (/^\[soak\]/.test(l)) { rows.push(l); if (!/로그 \d+번/.test(l)) console.log(l); else console.log(l); }
  else if (/ERROR|WARNING|SCRIPT ERROR|Aborted|corrupted|malloc/.test(l)) {
    bad++;
    if (/Aborted|corrupted|malloc/.test(l)) aborted = true;
    const k = l.replace(/\d+/g, '#').slice(0, 90);
    kinds[k] = (kinds[k] || 0) + 1;
  }
};
readline.createInterface({ input: g.stdout }).on('line', onLine);
readline.createInterface({ input: g.stderr }).on('line', onLine);
const timer = setTimeout(() => { console.log('시간 초과 — 끊음'); g.kill('SIGKILL'); }, timeout);
const rc = await new Promise((r) => g.on('close', (c, s) => r(c ?? 128 + (s === 'SIGKILL' ? 9 : 0))));
clearTimeout(timer);
server.kill();
fs.rmSync(home, { recursive: true, force: true });

const num = (l, k) => { const m = new RegExp(k + '=([-0-9.]+)').exec(l); return m ? Number(m[1]) : NaN; };
console.log('\n=== 표: ' + scen + ' (n=' + n + ') ===');
console.log('꼬리표\tt\trss MB\tobj\tnode\torph\tres\tsmem\tvmem\tfmax\terr\twarn');
for (const l of rows.filter((x) => / t=/.test(x))) {
  const tag = (/\[soak\] \S+ (\S+) t=/.exec(l) || [])[1];
  console.log([tag, num(l, 't'), num(l, 'rss'), num(l, 'obj'), num(l, 'node'), num(l, 'orph'), num(l, 'res'), num(l, 'smem'), num(l, 'vmem'), num(l, 'fmax'), num(l, 'err'), num(l, 'warn')].join('\t'));
}
const top = Object.entries(kinds).sort((a, b) => b[1] - a[1]).slice(0, 8);
console.log(`종료 코드 rc=${rc}${aborted ? ' (abort 문구 있음)' : ''} · 출력 ${lines}줄 · 경고/에러 줄 ${bad}`);
for (const [k, v] of top) console.log(`  ${v}번 ${k}`);
process.exit(rc === 0 ? 0 : 1);
