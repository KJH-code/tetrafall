// 서버 로그 요약: 판 길이·사망 원인·인원 구성별·맵별·플레이어별·아이템 사용.
// 실행: npm run stats              → logs/ 에서 가장 최근 서버 실행 (폴더면 그 안의 방 파일 전부)
//       npm run stats -- a.txt b.txt → 여러 파일 (붙여 넣은 콘솔 로그도 됨), 폴더를 주면 그 안의 .txt 전부
// 로그는 방마다 파일: logs/<서버를 켠 시각>/<방을 연 시각>_<코드>.txt (예전 서버는 logs/<시각>.txt 하나)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../shared/config.js';

const CAUSES = { 압사: 'crush', 낙사: 'fall', 용암: 'lava', '접속 끊김': 'disconnect' };
const isBot = (name) => name.includes('(봇)');

// "1:17" → 77
function toSec(s) {
  const [m, sec] = s.split(':').map(Number);
  return m * 60 + sec;
}

function fmtSec(s) {
  if (s === null || Number.isNaN(s)) return '-';
  const r = Math.round(s);
  return `${Math.floor(r / 60)}:${String(r % 60).padStart(2, '0')}`;
}

function median(xs) {
  if (!xs.length) return null;
  const a = [...xs].sort((x, y) => x - y);
  const m = a.length >> 1;
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
}

const pct = (a, b) => (b ? `${Math.round((a / b) * 100)}%` : '-');

// 로그 텍스트 → 끝난 판 목록. 서버가 판 중간에 꺼져 종료 줄이 없는 판은 버린다.
// 사람은 P1·P2 대신 입력한 이름으로 묶는다. P 번호는 자리 번호라 나갔다 들어온 다른 사람도 같은 번호를 받으므로,
// "접속" 줄마다 새 접속으로 보고 그 접속에서 처음 넣은 이름으로 묶는다 (판 중간에 이름을 바꿔도 한 사람).
// 이름을 안 넣은 접속은 P 번호 (파일이 여럿이면 P 번호는 서버 실행마다 다른 사람일 수 있음)
export function parseLog(text) {
  const rounds = [];
  const conns = new Map(); // P1 → { key: 처음 넣은 이름, aliases: 그 뒤에 바꾼 이름 }
  const conn = (name) => {
    if (!conns.has(name)) conns.set(name, { key: null, aliases: new Set() });
    return conns.get(name);
  };
  let cur = null;
  let last = null; // 방금 끝난 판: 종료 줄 다음의 "  사망:" 요약 줄을 받음
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/^\[[^\]]*\]\s?/, ''); // 앞의 [시각] 떼기
    let m;
    if ((m = line.match(/^(P\d+(?:\(봇\))?) 접속 \(slot/))) {
      conns.set(m[1], { key: null, aliases: new Set() });
    } else if ((m = line.match(/^(P\d+) 이름: (.*)$/))) {
      const c = conn(m[1]);
      if (m[2] !== '(없음)' && !c.key) c.key = m[2];
      else if (m[2] !== '(없음)' && m[2] !== c.key) c.aliases.add(m[2]);
    } else if ((m = line.match(/^===== ROUND (\d+) 시작 \((\d+)명(?:: (.*?))?, 맵 ([^,]+?)(?:, 봇 (\S+))?\) =====$/))) {
      last = null;
      cur = {
        n: Number(m[1]),
        size: Number(m[2]),
        map: m[4],
        botLevel: m[5] || null, // 봇 난이도 (넣기 전 로그엔 없음)
        names: m[3] ? m[3].split(' ') : null, // 옛 로그엔 참가자 목록이 없음 → 끝날 때 사망자 + 승자로 채움
        deaths: [],
        winner: null,
        len: null,
        lava: false,
        use: new Map(), // P1 → 아이템 사용 횟수
      };
    } else if ((m = line.match(/^ {2}사망: (.*)$/)) && last) {
      // 접속 끊김은 [사망] 줄 없이 여기에만 나옴
      for (const part of m[1].split(', ')) {
        const d = part.match(/^(\S+) (압사|낙사|용암|접속 끊김)@(\d+:\d+)$/);
        if (!d || last.deaths.some((x) => x.name === d[1])) continue;
        last.deaths.push({ name: d[1], cause: CAUSES[d[2]], t: toSec(d[3]), damage: null });
        if (!last.conns.has(d[1])) {
          last.names.push(d[1]);
          last.conns.set(d[1], conn(d[1]));
        }
      }
      last = null;
    } else if (!cur) {
      continue;
    } else if ((m = line.match(/^ {2}\[사망\] (\S+) (압사|낙사|용암|접속 끊김) @ (\d+:\d+)(?:.*피해 (\d+)%)?(?:, 킬 (?:없음|(\S+) ([^\s)]+)))?/))) {
      // 킬: 이름 = 그 사람, null = 킬 없음, undefined = 킬 기록이 없던 옛 로그
      const killed = /, 킬 /.test(line);
      cur.deaths.push({
        name: m[1],
        cause: CAUSES[m[2]],
        t: toSec(m[3]),
        damage: m[4] === undefined ? null : Number(m[4]),
        killer: killed ? m[5] || null : undefined,
        weapon: killed ? m[6] || null : undefined,
      });
    } else if ((m = line.match(/^===== ROUND (\d+) 종료 \| 길이 (\d+:\d+) \| 승자: (.+) =====$/))) {
      if (Number(m[1]) === cur.n) {
        cur.len = toSec(m[2]);
        cur.winner = m[3] === '무승부' ? null : m[3];
        if (!cur.names) cur.names = [...new Set([...cur.deaths.map((d) => d.name), ...(cur.winner ? [cur.winner] : [])])];
        cur.conns = new Map(cur.names.map((n) => [n, conn(n)])); // 이 판에 있던 접속 (이름은 나중에 넣어도 반영)
        rounds.push(cur);
        last = cur;
      }
      cur = null;
    } else if ((m = line.match(/^ {2}팀: 빨강 ?(.*?) \/ 파랑 ?(.*)$/))) {
      // 팀전: 팀 승리를 사람별 승으로 나눔
      cur.teams = { 빨강: m[1] ? m[1].split(' ') : [], 파랑: m[2] ? m[2].split(' ') : [] };
    } else if (/^ {2}\[용암\] .*용암 상승 시작/.test(line)) {
      cur.lava = true;
    } else {
      countUse(cur, line);
    }
  }
  // P 번호 → 이름 (사람만)
  for (const r of rounds) {
    const who = (name) => (isBot(name) ? name : r.conns.get(name)?.key || name);
    r.players = r.names.map((name) => ({ name, key: who(name), bot: isBot(name), aliases: [...(r.conns.get(name)?.aliases || [])] }));
    const team = r.winner && r.teams ? r.teams[r.winner.replace(/팀$/, '')] : null;
    r.winnerKeys = team ? team.map(who) : r.winner ? [who(r.winner)] : []; // 팀전이면 그 팀 전원
    for (const d of r.deaths) {
      d.key = who(d.name);
      d.killerKey = d.killer ? who(d.killer) : d.killer;
    }
    r.useByKey = new Map([...r.use].map(([name, u]) => [who(name), u]));
  }
  return rounds;
}

function countUse(r, line) {
  const u = (name) => {
    if (!r.use.has(name)) {
      r.use.set(name, { build: 0, bombs: 0, bombHits: 0, bricks: 0, crushes: 0, shocks: 0, shots: 0, shotHits: 0, hammerHits: 0, crits: 0 });
    }
    return r.use.get(name);
  };
  let m;
  if ((m = line.match(/^ {2}\[(?:밀치기|망치)\] (\S+) → \S+ 넉백 치명타/))) u(m[1]).crits++; // 아래 망치 명중으로도 셈
  if ((m = line.match(/^ {2}\[쌓기\] (\S+) →/))) u(m[1]).build++;
  else if ((m = line.match(/^ {2}\[폭탄\] (\S+) → \(/))) u(m[1]).bombs++;
  else if ((m = line.match(/^ {2}\[폭탄\] (\S+) → \S+ 넉백/))) u(m[1]).bombHits++;
  else if ((m = line.match(/^ {2}\[투척\] (\S+) 의 \S+ 에 \S+ 깔림/))) u(m[1]).crushes++;
  else if ((m = line.match(/^ {2}\[투척\] (\S+) \S+ → \(/))) u(m[1]).bricks++;
  else if ((m = line.match(/^ {2}\[충격파\] (\S+) → \S+ 넉백/))) u(m[1]).shocks++;
  else if ((m = line.match(/^ {2}\[발사\] (\S+) /))) u(m[1]).shots++;
  else if ((m = line.match(/^ {2}\[투사체\] (\S+) → \S+ 넉백/))) u(m[1]).shotHits++;
  else if ((m = line.match(/^ {2}\[망치\] (\S+) → \S+ 넉백/))) u(m[1]).hammerHits++;
}

const shareOf = (deaths) => {
  const counted = deaths.filter((d) => d.cause !== 'disconnect');
  return { crush: counted.filter((d) => d.cause === 'crush').length, n: counted.length };
};

// 판 목록 → 표로 낼 숫자
export function summarize(rounds) {
  const deaths = rounds.flatMap((r) => r.deaths);
  const byCause = { crush: 0, fall: 0, lava: 0, disconnect: 0 };
  for (const d of deaths) byCause[d.cause]++;

  const group = (keyOf) => {
    const g = new Map();
    for (const r of rounds) {
      const k = keyOf(r);
      if (!g.has(k)) g.set(k, []);
      g.get(k).push(r);
    }
    return [...g].map(([k, rs]) => {
      const s = shareOf(rs.flatMap((r) => r.deaths));
      return { key: k, rounds: rs.length, lenMedian: median(rs.map((r) => r.len)), crush: s.crush, deaths: s.n };
    });
  };
  const comp = (r) => {
    const bots = r.players.filter((p) => p.bot).length;
    const humans = r.players.length - bots;
    if (r.teams) return `${bots ? `사람 ${humans} + 봇 ${bots}` : `사람 ${humans}`} 팀전`;
    if (!bots) return `사람 ${humans}`;
    const lv = r.botLevel ? ` (${r.botLevel})` : '';
    return humans ? `사람 ${humans} + 봇 ${bots}${lv}` : `봇 ${bots}${lv}`;
  };

  const players = new Map();
  for (const r of rounds) {
    for (const p of r.players) {
      if (!players.has(p.key)) {
        players.set(p.key, { key: p.key, bot: p.bot, aliases: new Set(), rounds: 0, wins: 0, kills: 0, crush: 0, fall: 0, lava: 0, disconnect: 0, survive: [], deathDamage: [] });
      }
      const s = players.get(p.key);
      for (const a of p.aliases) if (a !== p.key) s.aliases.add(a);
      s.rounds++;
      if (r.winnerKeys.includes(p.key)) s.wins++;
      const d = r.deaths.find((x) => x.key === p.key);
      if (d) {
        s[d.cause]++;
        if (d.cause !== 'disconnect') s.survive.push(d.t);
        if (d.damage !== null && d.cause !== 'disconnect') s.deathDamage.push(d.damage);
      } else {
        s.survive.push(r.len);
      }
    }
    for (const d of r.deaths) if (d.killerKey && players.has(d.killerKey)) players.get(d.killerKey).kills++;
  }

  // 무엇이 판을 끝내나: 킬을 낸 공격 종류 (킬 기록이 있는 사망만)
  const withKill = deaths.filter((d) => d.killer !== undefined && d.cause !== 'disconnect');
  const byWeapon = new Map();
  for (const d of withKill) {
    const k = d.weapon || '(킬 없음)';
    byWeapon.set(k, (byWeapon.get(k) || 0) + 1);
  }
  const weapons = { total: withKill.length, rows: [...byWeapon].sort((a, b) => b[1] - a[1]) };

  // 낙사 때 피해 % 분포: 몇 % 에서 날아가 죽나 (넉백 세기 조정 근거)
  const buckets = [0, 50, 100, 150, 200];
  const fallDamage = buckets.map((lo, i) => ({
    label: i < buckets.length - 1 ? `${lo}~${buckets[i + 1] - 1}%` : `${lo}%+`,
    n: deaths.filter((d) => d.cause === 'fall' && d.damage !== null && d.damage >= lo && (i === buckets.length - 1 || d.damage < buckets[i + 1])).length,
  }));

  // 아이템: 사람만 (봇은 쓰는 규칙이 코드에 정해져 있어 의미가 다름)
  const items = { humanRounds: 0, build: 0, buildAll: 0, bombs: 0, bombHits: 0, bricks: 0, crushes: 0, shocks: 0, shots: 0, shotHits: 0, hammerHits: 0, crits: 0 };
  for (const r of rounds) {
    for (const p of r.players) {
      if (p.bot) continue;
      items.humanRounds++;
      const u = r.useByKey.get(p.key);
      if (!u) continue;
      for (const k of ['build', 'bombs', 'bombHits', 'bricks', 'crushes', 'shocks', 'shots', 'shotHits', 'hammerHits', 'crits']) items[k] += u[k] || 0;
      if (u.build >= C.BUILD_BLOCKS_PER_ROUND) items.buildAll++;
    }
  }

  const lens = rounds.map((r) => r.len);
  return {
    rounds: rounds.length,
    lenMedian: median(lens),
    lenMean: lens.length ? lens.reduce((a, b) => a + b, 0) / lens.length : null,
    lenMax: lens.length ? Math.max(...lens) : null,
    lavaRounds: rounds.filter((r) => r.lava).length,
    byCause,
    byComp: group(comp),
    byMap: group((r) => r.map),
    players: [...players.values()].sort((a, b) => a.bot - b.bot || b.wins - a.wins),
    fallDamage,
    weapons,
    items,
  };
}

// 한글은 터미널에서 두 칸
const width = (s) => [...String(s)].reduce((w, ch) => w + (/[ᄀ-ￜ]/.test(ch) ? 2 : 1), 0);
function table(head, rows) {
  const cols = head.map((h, i) => Math.max(width(h), ...rows.map((r) => width(r[i]))));
  const line = (r) => r.map((c, i) => String(c) + ' '.repeat(cols[i] - width(c))).join('  ').trimEnd();
  return [line(head), cols.map((w) => '-'.repeat(w)).join('  '), ...rows.map(line)].join('\n');
}

export function formatReport(s) {
  if (!s.rounds) return '끝난 판이 없음';
  const out = [];
  const c = s.byCause;
  const counted = c.crush + c.fall + c.lava;
  out.push(`== 전체 ==`);
  out.push(`판 ${s.rounds} · 길이 중앙값 ${fmtSec(s.lenMedian)} · 평균 ${fmtSec(s.lenMean)} · 최대 ${fmtSec(s.lenMax)} · 용암이 올라온 판 ${s.lavaRounds}`);
  out.push(`사망: 압사 ${c.crush} (${pct(c.crush, counted)}) · 낙사 ${c.fall} (${pct(c.fall, counted)}) · 용암 ${c.lava} (${pct(c.lava, counted)})${c.disconnect ? ` · 접속 끊김 ${c.disconnect} (비율에서 뺌)` : ''}`);
  out.push(`압사 합격선 ${Math.round(C.PASS_CRUSH_SHARE * 100)}%`);
  const groupRows = (g) => g.map((x) => [x.key, x.rounds, fmtSec(x.lenMedian), `${pct(x.crush, x.deaths)} (${x.crush}/${x.deaths})`]);
  out.push('', '== 인원 구성별 ==', table(['구성', '판', '길이 중앙값', '압사 비율'], groupRows(s.byComp)));
  out.push('', '== 맵별 ==', table(['맵', '판', '길이 중앙값', '압사 비율'], groupRows(s.byMap)));
  out.push(
    '',
    '== 플레이어별 ==',
    table(
      ['이름', '판', '승', '승률', '킬', '압사', '낙사', '용암', '버틴 시간 중앙값', '죽을 때 피해 % 중앙값'],
      s.players.map((p) => [
        p.aliases.size ? `${p.key} (=${[...p.aliases].join(', ')})` : p.key,
        p.rounds,
        p.wins,
        pct(p.wins, p.rounds),
        p.kills,
        p.crush,
        p.fall,
        p.lava,
        fmtSec(median(p.survive)),
        p.deathDamage.length ? `${Math.round(median(p.deathDamage))}%` : '-',
      ]),
    ),
  );
  out.push('', '== 킬을 낸 공격 ==');
  if (s.weapons.total) out.push(table(['공격', '사망', '비율'], s.weapons.rows.map(([k, n]) => [k, n, pct(n, s.weapons.total)])));
  else out.push('기록 없음 (킬 기록이 없던 옛 로그)');
  out.push('', '== 낙사할 때 피해 % ==');
  if (s.fallDamage.some((b) => b.n)) out.push(table(s.fallDamage.map((b) => b.label), [s.fallDamage.map((b) => b.n)]));
  else out.push('기록 없음 (피해 % 가 없던 옛 로그거나 낙사가 없음)');
  const it = s.items;
  const per = (n) => (it.humanRounds ? (n / it.humanRounds).toFixed(1) : '-');
  out.push(
    '',
    `== 아이템 (사람만, 사람 1명이 한 판 ${it.humanRounds}번 기준) ==`,
    table(
      ['종류', '쓴 횟수', '1명·1판당', '맞힘'],
      [
        ['쌓기 블록', it.build, per(it.build), `${C.BUILD_BLOCKS_PER_ROUND}개 다 씀 ${it.buildAll}번 (${pct(it.buildAll, it.humanRounds)})`],
        ['폭탄', it.bombs, per(it.bombs), `${it.bombHits}명`],
        ['설치 블록 1×2', it.bricks, per(it.bricks), `깔림 ${it.crushes} · 충격파 ${it.shocks}`],
        ['투사체', it.shots, per(it.shots), `${it.shotHits}번`],
        ['망치', '-', '-', `${it.hammerHits}번`],
        ['치명타 (밀치기·망치)', it.crits, per(it.crits), '-'],
      ],
    ),
  );
  return out.join('\n');
}

// Windows PowerShell 5 의 `>` 저장은 UTF-16. BOM 을 보고 맞춰 읽는다
function readText(file) {
  const buf = fs.readFileSync(file);
  if (buf[0] === 0xff && buf[1] === 0xfe) return buf.subarray(2).toString('utf16le');
  return buf.toString('utf8').replace(/^\uFEFF/, '');
}

// 폴더 → 그 안의 .txt (이름순), 파일 → 그대로
function expand(p) {
  if (!fs.statSync(p).isDirectory()) return [p];
  return fs
    .readdirSync(p)
    .filter((f) => f.endsWith('.txt'))
    .sort()
    .map((f) => path.join(p, f));
}

// logs/ 에서 가장 최근 것 (시각 이름이라 이름순 마지막). 새 서버는 폴더, 예전 서버는 파일 하나
export function latestRun(dir) {
  if (!fs.existsSync(dir)) return null;
  const entries = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.txt') || fs.statSync(path.join(dir, f)).isDirectory())
    .sort();
  for (let i = entries.length - 1; i >= 0; i--) {
    const full = path.join(dir, entries[i]);
    if (expand(full).length) return full; // 방을 하나도 안 연 빈 폴더는 건너뜀
  }
  return null;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  let args = process.argv.slice(2);
  if (!args.length) {
    const run = latestRun(path.join(root, 'logs'));
    if (!run) {
      console.log('logs/ 에 로그가 없음. 서버(npm start)를 한 번 돌리거나 파일을 지정: npm run stats -- 파일.txt');
      process.exit(1);
    }
    args = [path.relative(process.cwd(), run)];
  }
  const files = args.flatMap(expand);
  // 파일마다 따로 읽음 (P 번호는 방·서버 실행마다 다른 사람)
  const rounds = files.flatMap((f) => parseLog(readText(f)));
  console.log(`로그: ${args.join(', ')}${files.length > args.length ? ` (파일 ${files.length}개)` : ''}\n`);
  console.log(formatReport(summarize(rounds)));
}
