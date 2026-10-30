// 봇 판 시뮬레이션 (npm run sim): 봇끼리 판을 코어 수만큼 나눠 돌리고 캐릭터별 승률·사망 원인·판 길이를 낸다.
// 판마다 시드가 정해져 있어서 같은 옵션이면 결과가 같다 → 패치 전후를 같은 시드로 비교 (--base).
// 로그는 서버와 같은 형식으로 sim-logs/<시각>/ 에 남겨서 npm run stats -- sim-logs/<시각> 으로 자세히 볼 수 있다.
//
//   npm run sim                               # 2·3·4인 × 맵 7개, 504판 × 자리 바꿔 2번
//   npm run sim -- --rounds 200 --players 2   # 1:1 만 200판 (×2)
//   npm run sim -- --chars ninja,tank         # 캐릭터 풀을 좁힘 (인원보다 적으면 겹쳐서 뽑음)
//   npm run sim -- --base sim-logs/<시각>     # 지난 결과와 비교 (같은 시드·옵션일 때 의미 있음)
//
// 옵션: --rounds N (짝 하나당 판 수 합, 기본 504) · --players 2,3,4 · --maps all|flat,stairs · --chars all|... ·
//       --level easy|normal|hard · --sky on|off (기본 config SKY_STAIRS_DEFAULT) · --seed N · --workers N ·
//       --no-mirror (자리 바꾼 판 안 돌림) · --no-log · --out 폴더
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Game } from '../server/game.js';
import { MAP_IDS } from '../server/maps.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;
export const SIM_ROUND_CAP_MS = 10 * 60 * 1000; // 이보다 길면 무승부로 끊고 '시간 초과' 로 셈

// 시드 고정 난수 (mulberry32). 게임 서버의 난수는 전부 game.rng 하나를 지나서 이것만 바꾸면 판이 재현됨
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(...parts) {
  let h = 2166136261;
  for (const ch of parts.join('|')) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  return h >>> 0;
}

export function parseArgs(argv) {
  const o = { rounds: 504, players: [2, 3, 4], maps: MAP_IDS, chars: C.CHARACTERS, level: C.BOT_LEVEL_DEFAULT, sky: C.SKY_STAIRS_DEFAULT, seed: 1, workers: Math.max(1, os.availableParallelism ? os.availableParallelism() : os.cpus().length), mirror: true, log: true, out: null, base: null };
  const list = (v, all) => (v === 'all' ? all : v.split(',').map((s) => s.trim()).filter(Boolean));
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const v = () => {
      const x = argv[++i];
      if (x === undefined) throw new Error(`${a} 뒤에 값이 없음`);
      return x;
    };
    if (a === '--rounds') o.rounds = Number(v());
    else if (a === '--players') o.players = list(v()).map(Number);
    else if (a === '--maps') o.maps = list(v(), MAP_IDS);
    else if (a === '--chars') o.chars = list(v(), C.CHARACTERS);
    else if (a === '--level') o.level = v();
    else if (a === '--sky') o.sky = v() === 'on';
    else if (a === '--seed') o.seed = Number(v());
    else if (a === '--workers') o.workers = Number(v());
    else if (a === '--no-mirror') o.mirror = false;
    else if (a === '--no-log') o.log = false;
    else if (a === '--out') o.out = v();
    else if (a === '--base') o.base = v();
    else throw new Error(`모르는 옵션 ${a}`);
  }
  if (!(o.rounds > 0)) throw new Error('--rounds 는 1 이상');
  for (const n of o.players) if (!(n >= 2 && n <= C.MAX_PLAYERS)) throw new Error(`--players ${n}: 2~${C.MAX_PLAYERS}`);
  for (const m of o.maps) if (!MAP_IDS.includes(m)) throw new Error(`--maps ${m}: ${MAP_IDS.join(',')} 중`);
  for (const c of o.chars) if (!C.CHARACTERS.includes(c)) throw new Error(`--chars ${c}: ${C.CHARACTERS.join(',')} 중`);
  if (!C.BOT_LEVELS[o.level]) throw new Error(`--level ${o.level}: ${Object.keys(C.BOT_LEVELS).join(',')} 중`);
  return o;
}

// 판 목록. (인원, 맵) 짝마다 rounds / 짝 수 만큼 (올림). 판마다 시드·자리별 캐릭터가 정해짐.
// mirror 면 같은 시드로 자리만 거꾸로 한 판을 하나 더 → 시작 자리 유불리가 캐릭터에 안 묻음
export function planJobs(o) {
  const combos = o.players.flatMap((n) => o.maps.map((map) => ({ n, map })));
  const per = Math.ceil(o.rounds / combos.length);
  const jobs = [];
  for (const { n, map } of combos) {
    for (let k = 0; k < per; k++) {
      const seed = hashSeed(o.seed, n, map, k);
      const r = mulberry32(seed ^ 0x9e3779b9);
      let chars;
      if (o.chars.length >= n) {
        const pool = [...o.chars];
        for (let i = pool.length - 1; i > 0; i--) {
          const j = Math.floor(r() * (i + 1));
          [pool[i], pool[j]] = [pool[j], pool[i]];
        }
        chars = pool.slice(0, n);
      } else chars = Array.from({ length: n }, () => o.chars[Math.floor(r() * o.chars.length)]);
      jobs.push({ id: jobs.length, n, map, seed, chars });
      if (o.mirror) jobs.push({ id: jobs.length, n, map, seed, chars: [...chars].reverse(), mirror: true });
    }
  }
  return jobs;
}

// 한 판. 결과는 숫자만 (워커에서 넘기기 쉽게)
export function runJob(job, o, log = () => {}) {
  const g = new Game(log, { characters: true, skyStairs: o.sky });
  g.rng = mulberry32(job.seed);
  g.setBotLevel(o.level);
  g.setMap(job.map);
  const bots = [];
  for (let i = 0; i < job.n; i++) bots.push(g.addBot());
  bots.forEach((p, i) => g.setChar(p.id, job.chars[i]));
  g.startRound();
  const t0 = g.time;
  while (g.phase === 'playing' && g.time - t0 < SIM_ROUND_CAP_MS) g.tick(TICK);
  const timeout = g.phase === 'playing';
  if (timeout) g.endRound(null);
  const winners = g.winnerIds && g.winnerIds.length ? g.winnerIds : g.winnerId != null ? [g.winnerId] : [];
  const seat = new Map(bots.map((p, i) => [p.id, i]));
  const causes = { crush: 0, fall: 0, lava: 0 };
  for (const d of g.deaths) if (d.cause in causes) causes[d.cause]++;
  return { id: job.id, n: job.n, map: job.map, chars: job.chars, winSeats: winners.map((w) => seat.get(w)).filter((s) => s !== undefined), lenMs: g.roundEndTime - t0, causes, timeout };
}

// 결과 모으기. 캐릭터 기대 승률 = 판마다 1/n 을 더한 것 (인원이 섞여도 ×기대 로 비교 가능)
export function summarizeSim(results) {
  const chars = new Map();
  const ch = (c) => {
    if (!chars.has(c)) chars.set(c, { char: c, rounds: 0, wins: 0, expect: 0, byN: {} });
    return chars.get(c);
  };
  const byN = {};
  const causes = { crush: 0, fall: 0, lava: 0 };
  let draws = 0;
  let timeouts = 0;
  for (const r of results) {
    const nb = (byN[r.n] ||= { rounds: 0, lens: [], causes: { crush: 0, fall: 0, lava: 0 } });
    nb.rounds++;
    nb.lens.push(r.lenMs);
    for (const k in causes) {
      causes[k] += r.causes[k];
      nb.causes[k] += r.causes[k];
    }
    if (!r.winSeats.length) draws++;
    if (r.timeout) timeouts++;
    const share = r.winSeats.length ? 1 / r.winSeats.length : 0; // 공동 승리는 나눠 가짐
    r.chars.forEach((c, s) => {
      const x = ch(c);
      const w = r.winSeats.includes(s) ? share : 0;
      x.rounds++;
      x.wins += w;
      x.expect += 1 / r.n;
      const xn = (x.byN[r.n] ||= { rounds: 0, wins: 0, expect: 0 });
      xn.rounds++;
      xn.wins += w;
      xn.expect += 1 / r.n;
    });
  }
  const median = (a) => {
    if (!a.length) return 0;
    const s = [...a].sort((p, q) => p - q);
    return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
  };
  const rows = [...chars.values()].map((x) => ({ ...x, ratio: x.expect ? x.wins / x.expect : 0 })).sort((a, b) => b.ratio - a.ratio);
  const ns = Object.keys(byN).map(Number).sort((a, b) => a - b);
  return {
    rounds: results.length,
    draws,
    timeouts,
    causes,
    ns,
    byN: Object.fromEntries(ns.map((n) => [n, { rounds: byN[n].rounds, medianMs: median(byN[n].lens), causes: byN[n].causes }])),
    medianMs: median(results.map((r) => r.lenMs)),
    chars: rows,
  };
}

const pct = (a, b) => (b ? `${((a / b) * 100).toFixed(1)}%` : '-');
const sec = (ms) => `${(ms / 1000).toFixed(1)}초`;

function table(head, rows) {
  const w = head.map((h, i) => Math.max(len(h), ...rows.map((r) => len(String(r[i])))));
  const line = (r) => r.map((c, i) => String(c) + ' '.repeat(w[i] - len(String(c)))).join('  ').trimEnd();
  return [line(head), ...rows.map(line)].join('\n');
}
// 한글은 두 칸
function len(s) {
  let n = 0;
  for (const c of s) n += /[ᄀ-ᇿ　-鿿가-힯]/.test(c) ? 2 : 1;
  return n;
}

export function formatSim(s, base = null) {
  const name = (c) => C.CHAR_NAMES[c] || c;
  const deaths = s.causes.crush + s.causes.fall + s.causes.lava;
  const bc = base ? new Map(base.chars.map((x) => [x.char, x])) : null;
  const out = [];
  out.push(`판 ${s.rounds} · 무승부 ${s.draws} · 시간 초과 ${s.timeouts} · 판 길이 중앙값 ${sec(s.medianMs)}${base ? ` (전 ${sec(base.medianMs)})` : ''}`);
  out.push(`사망 ${deaths}: 압사 ${pct(s.causes.crush, deaths)} · 낙사 ${pct(s.causes.fall, deaths)} · 용암 ${pct(s.causes.lava, deaths)}`);
  out.push('', '== 캐릭터별 (×기대 = 승 ÷ 판마다 1/인원 합, 1.00 이 평균) ==');
  const head = ['캐릭터', '판', '승률', '×기대', ...s.ns.map((n) => `${n}인`)];
  if (bc) head.push('전 ×기대', '차이');
  out.push(
    table(
      head,
      s.chars.map((x) => {
        const row = [name(x.char), x.rounds, pct(x.wins, x.rounds), x.ratio.toFixed(2), ...s.ns.map((n) => (x.byN[n] ? (x.byN[n].wins / x.byN[n].expect).toFixed(2) : '-'))];
        if (bc) {
          const b = bc.get(x.char);
          row.push(b ? b.ratio.toFixed(2) : '-', b ? `${x.ratio - b.ratio >= 0 ? '+' : ''}${(x.ratio - b.ratio).toFixed(2)}` : '-');
        }
        return row;
      }),
    ),
  );
  out.push('', '== 인원별 ==');
  out.push(
    table(
      ['인원', '판', '판 길이 중앙값', '압사', '낙사', '용암'],
      s.ns.map((n) => {
        const b = s.byN[n];
        const d = b.causes.crush + b.causes.fall + b.causes.lava;
        return [`${n}인`, b.rounds, sec(b.medianMs), pct(b.causes.crush, d), pct(b.causes.fall, d), pct(b.causes.lava, d)];
      }),
    ),
  );
  return out.join('\n');
}

// 판들을 워커 여럿에 나눠 돌림. 워커마다 로그 파일 하나 (logDir 이 있으면)
export function runParallel(jobs, o, { logDir = null, onProgress = () => {} } = {}) {
  const k = Math.max(1, Math.min(o.workers, jobs.length));
  const chunks = Array.from({ length: k }, (_, i) => jobs.filter((_, j) => j % k === i));
  const results = [];
  let done = 0;
  return Promise.all(
    chunks.map(
      (chunk, i) =>
        new Promise((resolve, reject) => {
          const w = new Worker(new URL(import.meta.url), { workerData: { sim: true, jobs: chunk, o, logFile: logDir ? path.join(logDir, `w${String(i).padStart(2, '0')}.txt`) : null } });
          w.on('message', (r) => {
            results.push(r);
            onProgress(++done, jobs.length);
          });
          w.on('error', reject);
          w.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`워커 ${i} 종료 코드 ${code}`))));
        }),
    ),
  ).then(() => results.sort((a, b) => a.id - b.id));
}

function workerMain() {
  const { jobs, o, logFile } = workerData;
  const fd = logFile ? fs.openSync(logFile, 'w') : null;
  const log = fd === null ? () => {} : (m) => fs.writeSync(fd, `${m}\n`);
  for (const job of jobs) parentPort.postMessage(runJob(job, o, log));
  if (fd !== null) fs.closeSync(fd);
}

function loadBase(p) {
  const f = fs.statSync(p).isDirectory() ? path.join(p, 'summary.json') : p;
  return JSON.parse(fs.readFileSync(f, 'utf8')).summary;
}

async function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const o = parseArgs(process.argv.slice(2));
  const base = o.base ? loadBase(o.base) : null;
  const jobs = planJobs(o);
  const stamp = new Date().toISOString().replace(/[:T]/g, '-').slice(0, 19);
  const outDir = o.out || path.join(root, 'sim-logs', stamp);
  fs.mkdirSync(outDir, { recursive: true });
  console.log(`봇 판 ${jobs.length}판 (인원 ${o.players.join('·')}, 맵 ${o.maps.length}개, 캐릭터 ${o.chars.length}명${o.mirror ? ', 자리 바꿔 2번' : ''}, 난이도 ${o.level}, 하늘 계단 ${o.sky ? '켬' : '끔'}, 시드 ${o.seed}) · 워커 ${Math.min(o.workers, jobs.length)}개`);
  const t0 = Date.now();
  let last = 0;
  const results = await runParallel(jobs, o, {
    logDir: o.log ? outDir : null,
    onProgress: (d, n) => {
      if (process.stdout.isTTY && Date.now() - last > 500) {
        last = Date.now();
        process.stdout.write(`\r  ${d}/${n}`);
      }
    },
  });
  if (process.stdout.isTTY) process.stdout.write('\r');
  const s = summarizeSim(results);
  console.log(`  ${((Date.now() - t0) / 1000).toFixed(1)}초 걸림\n`);
  console.log(formatSim(s, base));
  let commit = null;
  try {
    commit = fs.readFileSync(path.join(root, '.git', 'HEAD'), 'utf8').trim();
    if (commit.startsWith('ref: ')) commit = fs.readFileSync(path.join(root, '.git', commit.slice(5)), 'utf8').trim();
  } catch {}
  fs.writeFileSync(path.join(outDir, 'summary.json'), JSON.stringify({ commit, options: { ...o, base: undefined }, summary: s }, null, 1));
  console.log(`\n저장: ${path.relative(process.cwd(), outDir)}/summary.json${o.log ? ` · 자세히: npm run stats -- ${path.relative(process.cwd(), outDir)}` : ''}`);
}

if (!isMainThread && workerData && workerData.sim) workerMain();
else if (isMainThread && process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
