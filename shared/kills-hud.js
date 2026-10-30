// 킬 점수전 화면 계산 (DOM·three.js 없는 순수 계산): 킬·죽음·자멸 세기와 연속 킬, 위 점수 띠 (1~N위 + 나 / 팀 합계), Tab 점수표 줄,
// 부활 카운트다운 초, 체력전 HP 비율. client/main.js 가 그리고 test/kills-hud.test.js 가 고정
import { CONFIG as C } from './config.js';

// 'death' 이벤트 {who, by} 로 판 동안 사람마다 킬·죽음·자멸·연속 킬을 셈 (서버 스냅샷에 그 필드가 없을 때 — 있으면 서버 값이 먼저)
// by 가 없거나 자기 자신이면 자멸 (킬 점수전 -1 과 같은 기준), 죽으면 그 사람 연속 킬은 0
export class KillTally {
  constructor() {
    this.reset();
  }

  reset() {
    this.rows = new Map(); // id → { kills, deaths, self, streak }
  }

  row(id) {
    let r = this.rows.get(id);
    if (!r) this.rows.set(id, (r = { kills: 0, deaths: 0, self: 0, streak: 0 }));
    return r;
  }

  // 반환: 이 죽음으로 죽인 사람의 연속 킬 (자멸·킬 없음이면 0). e.streak 가 오면 그 값
  add(e) {
    const v = this.row(e.who);
    v.deaths++;
    v.streak = 0;
    const by = e.by ?? null;
    if (by === null || by === e.who) {
      v.self++;
      return 0;
    }
    const k = this.row(by);
    k.kills++;
    k.streak = Number.isInteger(e.streak) ? e.streak : k.streak + 1;
    return k.streak;
  }

  // 서버 필드 (kills·deaths·selfKills) 가 있으면 그것, 없으면 센 값
  stats(p) {
    const r = this.rows.get(p.id) || { kills: 0, deaths: 0, self: 0, streak: 0 };
    return {
      kills: Number.isInteger(p.kills) ? p.kills : r.kills,
      deaths: Number.isInteger(p.deaths) ? p.deaths : r.deaths,
      self: Number.isInteger(p.selfKills) ? p.selfKills : r.self,
      streak: Number.isInteger(p.streak) ? p.streak : r.streak,
    };
  }
}

// 연속 킬 글자 (KILLS_STREAK_MIN 아래면 '')
export function streakText(n) {
  if (!(n >= C.KILLS_STREAK_MIN)) return '';
  return C.KILLS_STREAK_TEXT[n] || `${n}연속 킬`;
}

// 목표까지 진행 (0~1)
export const progress = (score, target) => Math.max(0, Math.min(1, (score || 0) / Math.max(1, target)));

// 점수 순서 (같으면 자리 순서). 관전자·허수아비 뺌
export function ranked(players) {
  return players.filter((p) => !p.spectator && !p.dummy).sort((a, b) => (b.score || 0) - (a.score || 0) || a.slot - b.slot);
}

// 개인전 위 점수 띠: 1~KILLS_TOP_N 위 + (그 안에 없으면) 나. 같은 점수는 같은 등수
export function topBar(players, myId) {
  const list = ranked(players);
  const rankOf = (i) => list.findIndex((p) => (p.score || 0) === (list[i].score || 0)) + 1;
  const out = list.slice(0, C.KILLS_TOP_N).map((p, i) => ({ id: p.id, score: p.score || 0, rank: rankOf(i), me: p.id === myId }));
  const mi = list.findIndex((p) => p.id === myId);
  if (mi >= C.KILLS_TOP_N) out.push({ id: myId, score: list[mi].score || 0, rank: rankOf(mi), me: true, extra: true });
  return out;
}

// Tab 점수표 줄: 등수·킬·죽음·자멸·점수 (개인전은 점수 순, 팀전은 팀끼리 묶어 빨강 먼저)
export function scoreRows(players, tally, teamMode) {
  let list = ranked(players);
  if (teamMode) list = [...list.filter((p) => p.team === 'red'), ...list.filter((p) => p.team !== 'red')];
  return list.map((p) => ({ id: p.id, team: p.team, score: p.score || 0, ...tally.stats(p) }));
}

// 부활까지 큰 숫자 (올림 초, 0 이하면 0)
export const respawnSecs = (ms) => (ms > 0 ? Math.ceil(ms / 1000) : 0);

// 체력전 HP 비율: players[].hp ÷ hpMax (스냅샷 맨 위 hpMax, 사람마다 hpMax 가 있으면 그것). 없으면 null → 막대 안 그림
export function hpFrac(p, hpMax) {
  const max = p && p.hpMax > 0 ? p.hpMax : hpMax;
  if (!p || !Number.isFinite(p.hp) || !(max > 0)) return null;
  return Math.max(0, Math.min(1, p.hp / max));
}
