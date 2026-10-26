// 서버 로그 요약: 판 길이·사망 원인·인원 구성별·맵별·모드별·플레이어별·아이템 사용.
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
        mode: '생존', // 모드 줄이 없으면 생존 (예전 로그·생존 모드)
        sky: false, // 하늘 계단 (줄이 없으면 끔)
        melts: 0, // 용암에 녹은 하늘 블록
        master: null, // 블록 마스터 판의 마스터
        names: m[3] ? m[3].split(' ') : null, // 옛 로그엔 참가자 목록이 없음 → 끝날 때 사망자 + 승자로 채움
        deaths: [],
        winner: null,
        len: null,
        lava: false,
        use: new Map(), // P1 → 아이템 사용 횟수
        combos: [], // { by: [때린 이름…] (옛 로그는 null), target, n }
        basics: [], // 캐릭터 평타 명중 { by, n } (n 0 = 공중 평타), 2026-10-25~
        counters: [], // 카운터히트를 넣은 이름 (2026-10-25~)
        blasts: [], // 건축가 블록 폭발 { kind: '벽'|'3타 블록'|'발판', n: 칸 수 } (2026-10-25~)
        bigBombs: 0, // 건축가 대폭발
        armor: { held: 0, broken: 0 }, // 탱크 아머 버팀·깨짐 (2026-10-25~)
        hunter: { marks: 0, shots: 0, refunds: 0 }, // 사냥꾼 표식·처형 사격·게이지 회수 (2026-10-26~)
        cannon: { fired: 0, hits: 0, broke: 0, big: 0 }, // 대포수 포탄 발사·명중·블록 부숨(칸)·대형 포탄 (2026-10-26~)
        berserker: { leaps: 0, spins: 0, rage: 0, cut: 0, endHits: 0, broken: 0 }, // 광전사 도약·소용돌이·분노 배율 합·깎은 피해 %·끝 날림 맞힌 수·끊김 (2026-10-26~)
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
    } else if ((m = line.match(/^ {2}캐릭터: (.*)$/))) {
      // "P1 탱크 / P2(봇) 닌자" → 이름 → 캐릭터
      cur.chars = new Map(m[1].split(' / ').map((x) => x.split(' ')));
    } else if (line === '  하늘 계단: 켬') {
      cur.sky = true;
    } else if (line.startsWith('  [하늘] ') && line.includes('용암에 녹음')) {
      cur.melts++;
    } else if ((m = line.match(/^ {2}모드: (블록 마스터|킬 점수전)(?: \(마스터 (\S+?),)?/))) {
      cur.mode = m[1];
      cur.master = m[2] || null;
    } else if ((m = line.match(/^ {2}\[콤보\] (?:(\S+) → )?(\S+) (\d+)타( 마무리)?$/))) {
      // "P1 → P2 3타" (때린 사람 여럿이면 P1+P3), 마무리 타로 끝나면 "… 6타 마무리" (2026-10-25~). 2026-10-24 처음 형식은 "P2 3타" (때린 사람 없음)
      cur.combos.push({ by: m[1] ? m[1].split('+') : null, target: m[2], n: Number(m[3]), finish: !!m[4] });
    } else if ((m = line.match(/^ {2}\[평타\] (\S+) → \S+ 넉백[^(]*\(.*?%\) (?:공중|(\d+)타) /))) {
      // "  [평타] P1 → P2 넉백 (P2 7%) 1타 옆치기" / "… 공중 망치 내려찍기" / "… 공중 2타 내려 차기" (공중은 n 0 으로, 무적이라 무시는 안 셈)
      cur.basics.push({ by: m[1], n: m[2] ? Number(m[2]) : 0 });
      countUse(cur, line);
    } else if ((m = line.match(/^ {2}\[폭발\] \S+ (벽|3타 블록|발판) (\d+)칸/))) {
      cur.blasts.push({ kind: m[1], n: Number(m[2]) });
    } else if (/^ {2}\[포탄\] \S+ 발사/.test(line)) {
      cur.cannon.fired++;
    } else if (/^ {2}\[포탄\] \S+ → \S+ 넉백/.test(line)) {
      cur.cannon.hits++;
    } else if ((m = line.match(/^ {2}\[포탄\] \S+ (?:블록 부숨|대형 포탄 블록 (\d+)칸 부숨)/))) {
      cur.cannon.broke += m[1] ? Number(m[1]) : 1;
    } else if (/^ {2}\[필살\] \S+ 대형 포탄 발사/.test(line)) {
      cur.cannon.big++;
    } else if (/^ {2}\[스킬\] \S+ 광폭 도약/.test(line)) {
      cur.berserker.leaps++;
    } else if ((m = line.match(/^ {2}\[필살\] \S+ 분노 소용돌이 \(분노 ×([\d.]+), 피해 (\d+)% → (\d+)%\)/))) {
      cur.berserker.spins++;
      cur.berserker.rage += Number(m[1]);
      cur.berserker.cut += Number(m[2]) - Number(m[3]);
    } else if (/^ {2}\[필살\] \S+ 분노 소용돌이 끊김/.test(line)) {
      cur.berserker.broken++;
    } else if ((m = line.match(/^ {2}\[필살\] \S+ 소용돌이 끝(?: → (.+))?$/))) {
      if (m[1]) cur.berserker.endHits += m[1].split(', ').length;
    } else if (/^ {2}\[표식\] /.test(line)) {
      cur.hunter.marks++;
    } else if (/^ {2}\[필살\] \S+ 처형 사격 \(/.test(line)) {
      cur.hunter.shots++;
      if (line.endsWith('게이지 회수')) cur.hunter.refunds++;
    } else if ((m = line.match(/^ {2}\[아머\] \S+ ← \S+ (버팀|깨짐)/))) {
      cur.armor[m[1] === '버팀' ? 'held' : 'broken']++;
    } else if (/^ {2}\[필살\] \S+ 대폭발 \(/.test(line)) {
      cur.bigBombs++;
    } else if ((m = line.match(/^ {2}\[카운터\] (\S+) → \S+$/))) {
      cur.counters.push(m[1]);
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
    r.winnerKeys = team ? team.map(who) : r.winner ? r.winner.split(' ').map(who) : []; // 팀전이면 그 팀 전원, 블록 마스터 생존자·킬 점수전 동점은 공백으로 여럿
    r.masterKey = r.master ? who(r.master) : null;
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
      r.use.set(name, { build: 0, bombs: 0, bombHits: 0, bricks: 0, crushes: 0, shocks: 0, shots: 0, shotHits: 0, crits: 0 });
    }
    return r.use.get(name);
  };
  let m;
  if ((m = line.match(/^ {2}\[(?:밀치기|망치|평타)\] (\S+) → \S+ 넉백 치명타/))) u(m[1]).crits++; // [망치] 는 2026-10-25 에 없앤 아이템 (옛 로그)
  if ((m = line.match(/^ {2}\[쌓기\] (\S+) →/))) u(m[1]).build++;
  else if ((m = line.match(/^ {2}\[폭탄\] (\S+) → \(/))) u(m[1]).bombs++;
  else if ((m = line.match(/^ {2}\[폭탄\] (\S+) → \S+ 넉백/))) u(m[1]).bombHits++;
  else if ((m = line.match(/^ {2}\[투척\] (\S+) 의 \S+ 에 \S+ 깔림/))) u(m[1]).crushes++;
  else if ((m = line.match(/^ {2}\[투척\] (\S+) \S+ → \(/))) u(m[1]).bricks++;
  else if ((m = line.match(/^ {2}\[충격파\] (\S+) → \S+ 넉백/))) u(m[1]).shocks++;
  else if ((m = line.match(/^ {2}\[발사\] (\S+) /))) u(m[1]).shots++;
  else if ((m = line.match(/^ {2}\[투사체\] (\S+) → \S+ 넉백/))) u(m[1]).shotHits++;
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
      // 킬 점수전은 한 판에 여러 번 죽음 → 원인은 전부 세고, 버틴 시간은 안 셈 (부활하니까). 블록 마스터의 마스터도 버틴 시간 없음
      const ds = r.deaths.filter((x) => x.key === p.key);
      for (const d of ds) {
        s[d.cause]++;
        if (d.damage !== null && d.cause !== 'disconnect') s.deathDamage.push(d.damage);
      }
      if (r.mode !== '킬 점수전' && p.key !== r.masterKey) {
        const d = ds[0];
        if (!d) s.survive.push(r.len);
        else if (d.cause !== 'disconnect') s.survive.push(d.t);
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
  const items = { humanRounds: 0, build: 0, bombs: 0, bombHits: 0, bricks: 0, crushes: 0, shocks: 0, shots: 0, shotHits: 0, crits: 0 };
  for (const r of rounds) {
    for (const p of r.players) {
      if (p.bot) continue;
      items.humanRounds++;
      const u = r.useByKey.get(p.key);
      if (!u) continue;
      for (const k of ['build', 'bombs', 'bombHits', 'bricks', 'crushes', 'shocks', 'shots', 'shotHits', 'crits']) items[k] += u[k] || 0;
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
    bySky: rounds.some((r) => r.sky) ? group((r) => (r.sky ? '켬' : '끔')) : [],
    melts: rounds.reduce((n, r) => n + r.melts, 0),
    byChar: (() => {
      // 캐릭터별 판·승 (사람·봇 따로). 캐릭터 줄이 있는 판만
      const t = new Map();
      for (const r of rounds) {
        if (!r.chars) continue;
        for (const p of r.players) {
          const c = r.chars.get(p.name);
          if (!c) continue;
          const k = `${c}${p.bot ? ' (봇)' : ''}`;
          if (!t.has(k)) t.set(k, { key: k, rounds: 0, wins: 0 });
          t.get(k).rounds++;
          if (r.winnerKeys.includes(p.key)) t.get(k).wins++;
        }
      }
      return [...t.values()].sort((a, b) => a.key.localeCompare(b.key));
    })(),
    basics: (() => {
      // 캐릭터 평타: 타 번호별 명중 수 (몇 타까지 이어지는지)
      const t = new Map();
      for (const r of rounds) {
        for (const b of r.basics) {
          const c = r.chars && r.chars.get(b.by);
          if (!c) continue;
          const k = `${c}${isBot(b.by) ? ' (봇)' : ''}`;
          if (!t.has(k)) t.set(k, { key: k, byN: {} });
          t.get(k).byN[b.n] = (t.get(k).byN[b.n] || 0) + 1;
        }
        for (const by of r.counters) {
          const c = r.chars && r.chars.get(by);
          if (!c) continue;
          const k = `${c}${isBot(by) ? ' (봇)' : ''}`;
          if (!t.has(k)) t.set(k, { key: k, byN: {} });
          t.get(k).counters = (t.get(k).counters || 0) + 1;
        }
      }
      return [...t.values()].sort((a, b) => a.key.localeCompare(b.key));
    })(),
    builder: (() => {
      // 건축가 블록 폭발 (벽·3타 블록) 과 대폭발 횟수
      const all = rounds.flatMap((r) => r.blasts);
      const by = (k) => all.filter((b) => b.kind === k);
      const cells = all.reduce((a, b) => a + b.n, 0);
      const armor = { held: rounds.reduce((a, r) => a + r.armor.held, 0), broken: rounds.reduce((a, r) => a + r.armor.broken, 0) };
      const hunter = ['marks', 'shots', 'refunds'].reduce((o, k) => ({ ...o, [k]: rounds.reduce((a, r) => a + r.hunter[k], 0) }), {});
      const cannon = ['fired', 'hits', 'broke', 'big'].reduce((o, k) => ({ ...o, [k]: rounds.reduce((a, r) => a + r.cannon[k], 0) }), {});
      const berserker = ['leaps', 'spins', 'rage', 'cut', 'endHits', 'broken'].reduce((o, k) => ({ ...o, [k]: rounds.reduce((a, r) => a + r.berserker[k], 0) }), {});
      return { armor, hunter, cannon, berserker, blasts: all.length, wall: by('벽').length, third: by('3타 블록').length, pad: by('발판').length, cells, big: rounds.reduce((a, r) => a + r.bigBombs, 0) };
    })(),
    combos: (() => {
      // 콤보 (2타 이상): 길이별 횟수 + 넣은 캐릭터별 (사람·봇 따로, 여럿이 같이 넣은 건 따로)
      const len = {};
      const t = new Map();
      const charRounds = new Map(); // 캐릭터 키 → 판 수 (1명·1판당 계산)
      const row = (k) => {
        if (!t.has(k)) t.set(k, { key: k, combos: 0, hits: 0, max: 0, full: 0 });
        return t.get(k);
      };
      for (const r of rounds) {
        const charKey = (name) => {
          const c = r.chars && r.chars.get(name);
          return c ? `${c}${isBot(name) ? ' (봇)' : ''}` : null;
        };
        for (const p of r.players) {
          const k = charKey(p.name);
          if (k) charRounds.set(k, (charRounds.get(k) || 0) + 1);
        }
        for (const cb of r.combos) {
          len[cb.n] = (len[cb.n] || 0) + 1;
          if (!cb.by) continue;
          const k = cb.by.length > 1 ? '여럿이 같이' : charKey(cb.by[0]) || '캐릭터 없음';
          const x = row(k);
          x.combos++;
          x.hits += cb.n;
          x.max = Math.max(x.max, cb.n);
          if (cb.finish) x.full++;
        }
      }
      const total = Object.values(len).reduce((a, b) => a + b, 0);
      const byChar = [...t.values()].map((x) => ({ ...x, rounds: charRounds.get(x.key) || 0 })).sort((a, b) => b.combos - a.combos);
      return { total, len, byChar };
    })(),
    byMode: group((r) => r.mode).map((g) => {
      const rs = rounds.filter((r) => r.mode === g.key);
      const masterWins = rs.filter((r) => r.masterKey && r.winnerKeys.includes(r.masterKey)).length;
      const note = g.key === '블록 마스터' ? `마스터 승 ${masterWins}/${rs.length}` : g.key === '킬 점수전' ? `판당 사망 ${(g.deaths / rs.length).toFixed(1)}` : '';
      return { ...g, note };
    }),
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
  if (s.bySky.length) out.push('', `== 하늘 계단별 == (용암에 녹은 하늘 블록 ${s.melts})`, table(['하늘 계단', '판', '길이 중앙값', '압사 비율'], groupRows(s.bySky)));
  if (s.byChar.length) out.push('', '== 캐릭터별 ==', table(['캐릭터', '판', '승', '승률'], s.byChar.map((c) => [c.key, c.rounds, c.wins, pct(c.wins, c.rounds)])));
  if (s.combos.total) {
    const lens = Object.keys(s.combos.len).map(Number).sort((a, b) => a - b);
    out.push('', `== 콤보 (2타 이상, 평타 마무리 타 또는 ${C.COMBO_MS / 1000}초 넘은 다음 타가 마무리) ==`, `${s.combos.total}번 · 길이별 ${lens.map((n) => `${n}타 ${s.combos.len[n]}`).join(' · ')}`);
    if (s.combos.byChar.length) {
      out.push(
        table(
          ['넣은 캐릭터', '콤보', '1명·1판당', '평균 타수', '최대', '마무리'],
          s.combos.byChar.map((x) => [x.key, x.combos, x.rounds ? (x.combos / x.rounds).toFixed(1) : '-', (x.hits / x.combos).toFixed(1), x.max, x.full]),
        ),
      );
    }
  }
  if (s.basics.length) {
    const maxN = Math.max(...s.basics.flatMap((x) => Object.keys(x.byN).map(Number)));
    const ns = Array.from({ length: maxN }, (_, i) => i + 1);
    out.push(
      '',
      '== 평타 명중 (타 번호별) ==',
      table(['캐릭터', ...ns.map((n) => `${n}타`), '공중', '카운터'], s.basics.map((x) => [x.key, ...ns.map((n) => x.byN[n] || '-'), x.byN[0] || 0, x.counters || 0])),
    );
  }
  if (s.builder.blasts || s.builder.big) {
    const b = s.builder;
    out.push('', '== 건축가 블록 ==', `폭발 ${b.blasts}번 (벽 ${b.wall} · 3타 블록 ${b.third} · 발판 ${b.pad}, 평균 ${b.blasts ? (b.cells / b.blasts).toFixed(1) : 0}칸) · 대폭발 ${b.big}번`);
  }
  const bz = s.builder.berserker;
  if (bz.leaps || bz.spins)
    out.push('', '== 광전사 ==', `광폭 도약 ${bz.leaps}번 · 소용돌이 ${bz.spins}번 (평균 분노 ×${bz.spins ? (bz.rage / bz.spins).toFixed(2) : '-'} · 깎은 피해 평균 ${bz.spins ? Math.round(bz.cut / bz.spins) : '-'}% · 끝 날림 ${bz.endHits}명 · 끊김 ${bz.broken}번)`);
  if (s.builder.cannon.fired || s.builder.cannon.big) out.push('', '== 대포수 ==', `포탄 ${s.builder.cannon.fired}발 · 명중 ${s.builder.cannon.hits} · 블록 부숨 ${s.builder.cannon.broke}칸 · 대형 포탄 ${s.builder.cannon.big}번`);
  if (s.builder.hunter.marks || s.builder.hunter.shots) out.push('', '== 사냥꾼 ==', `표식 ${s.builder.hunter.marks}번 · 처형 사격 ${s.builder.hunter.shots}번 (게이지 회수 ${s.builder.hunter.refunds}번)`);
  if (s.builder.armor.held || s.builder.armor.broken) out.push('', '== 탱크 아머 ==', `버팀 ${s.builder.armor.held}번 · 깨짐 ${s.builder.armor.broken}번`);
  out.push('', '== 모드별 ==', table(['모드', '판', '길이 중앙값', '압사 비율', ''], groupRows(s.byMode).map((row, i) => [...row, s.byMode[i].note])));
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
        ...(it.build ? [['쌓기 블록 (2026-10-24 전 로그)', it.build, per(it.build), '-']] : []),
        ['폭탄', it.bombs, per(it.bombs), `${it.bombHits}명`],
        ['설치 블록 1×2', it.bricks, per(it.bricks), `깔림 ${it.crushes} · 충격파 ${it.shocks}`],
        ['투사체', it.shots, per(it.shots), `${it.shotHits}번`],
        ['치명타 (밀치기·공중 평타)', it.crits, per(it.crits), '-'],
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
