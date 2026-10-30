// Game 도움 함수·표 (클래스 밖). 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮기고 export 만 붙임
import { CONFIG as C } from '../shared/config.js';
import { CELL, cellOfShape } from '../shared/pieces.js';

export const EPS = 1e-6;
export const DIR6 = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];


export function cellKey(cx, cy, cz) {
  return `${cx},${cy},${cz}`;
}

// 플레이어 AABB 가 칸 (cx, cy, cz) 와 겹치는가 (경계에 닿기만 하면 아님)
export function overlapsCell(p, cx, cy, cz) {
  return (
    cx < p.x + C.PLAYER_HALF - EPS &&
    cx + 1 > p.x - C.PLAYER_HALF + EPS &&
    cy < p.y + C.PLAYER_HALF - EPS &&
    cy + 1 > p.y - C.PLAYER_HALF + EPS &&
    cz < p.z + C.PLAYER_HEIGHT - EPS &&
    cz + 1 > p.z + EPS
  );
}

export function fmtTime(ms) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}


// 하늘 계단: 올라갈 높이 h(칸)일 때 점프(+꼭대기에서 공중 점프)로 닿는 수평 거리 (칸)
export function skyReach(h) {
  const g = C.GRAVITY;
  const v = C.JUMP_SPEED;
  if (C.AIR_JUMPS > 0) {
    const va = C.AIR_JUMP_SPEED;
    const d = va * va + 2 * g * ((v * v) / (2 * g) - h);
    return d < 0 ? 0 : C.MOVE_SPEED * (v / g + (va + Math.sqrt(d)) / g);
  }
  const d = v * v - 2 * g * h;
  return d < 0 ? 0 : (C.MOVE_SPEED * (v + Math.sqrt(d))) / g;
}


// 연습: 피해 % 설정값 (0~PRACTICE_DAMAGE_MAX 정수, 아니면 null)
export function practiceDamage(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(C.PRACTICE_DAMAGE_MAX, Math.round(n)));
}

// 허수아비 콤보 기록 → 보낼 값 (dist·height 는 소수 둘째 자리)
export function comboOut(c) {
  return { hits: c.hits, damage: c.damage, dist: Math.round(c.dist * 100) / 100, height: Math.round(Math.max(0, c.height) * 100) / 100 };
}

// 착지한 블록의 격자 값 (색): 유령 투하 = GHOST_BASE + 떨어뜨린 사람 색 번호 (나가도 그 색), 설치 블록, 그 밖은 모양
export function pieceCellValue(pc) {
  if (pc.ghostBy) return CELL.GHOST_BASE + pc.ghostColor;
  return pc.thrownBy ? CELL.THROWN : cellOfShape(pc.shape);
}

// 블록 칸들의 테두리 상자 (x0·y0 = 가장 작은 칸, x1·y1 = 가장 큰 칸 + 1)
export function cellBox(pc) {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const [dx, dy] of pc.cells) {
    x0 = Math.min(x0, pc.px + dx);
    y0 = Math.min(y0, pc.py + dy);
    x1 = Math.max(x1, pc.px + dx + 1);
    y1 = Math.max(y1, pc.py + dy + 1);
  }
  return { x0, y0, x1, y1 };
}

// 두 블록 칸 사이 가장 가까운 수평 거리 (칸 모서리끼리, 붙어 있으면 0)
export function cellGap(a, b) {
  let best = Infinity;
  for (const [ax, ay] of a.cells) {
    for (const [bx, by] of b.cells) {
      const dx = Math.max(0, Math.abs(a.px + ax - (b.px + bx)) - 1);
      const dy = Math.max(0, Math.abs(a.py + ay - (b.py + by)) - 1);
      const d2 = dx * dx + dy * dy;
      if (d2 < best) best = d2;
    }
  }
  return Math.sqrt(best); // 제곱으로 비교하고 마지막에 한 번만 (하늘 자리 고르기에서 많이 부름)
}

// 인원별 표 ({ 인원: 값 }) 에서 n 이하 가장 큰 칸 (없으면 가장 작은 칸): FIELD_SIZES · SKY_CHAINS
export function byCount(table, n) {
  const keys = Object.keys(table).map(Number).sort((a, b) => a - b);
  const k = keys.filter((x) => x <= n).pop() ?? keys[0];
  return table[k];
}

export function maxPlayers() {
  return Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
}

export function shareText(t) {
  const deaths = t.crush + t.fall + (t.lava || 0);
  if (!deaths) return '사망 없음';
  const share = t.crush / deaths;
  const pass = share >= C.PASS_CRUSH_SHARE ? '합격선 이상' : '합격선 미만';
  return `${(share * 100).toFixed(0)}% (합격선 ${(C.PASS_CRUSH_SHARE * 100).toFixed(0)}% → ${pass})`;
}

export const BOT_LEVEL_KO = { easy: '쉬움', normal: '보통', hard: '어려움' };
export const TEAM_KO = { red: '빨강', blue: '파랑' };

// 킬 로그의 공격 이름 (npm run stats 가 한 단어로 읽음)
// 평타 로그 이름: "2타 반대 찌르기", 공중이면 "공중 망치 내려찍기" (공중 연타가 있는 캐릭터는 "공중 2타 내려 차기")
export function basicLabel(set, n, air, def) {
  return air ? `공중 ${set.air.length > 1 ? `${n}타 ` : ''}${def.name}` : `${n}타 ${def.name}`;
}

// 필살기 공격 종류 (탱크 아머를 깸)
export const ULT_KINDS = new Set(['slam', 'bigbomb', 'blockslam', 'execute', 'bigshell', 'spin', 'spinend', 'amp', 'ampend']);

export const BBLOCK_LOG = { wall: '벽', third: '3타 블록', pad: '발판' };
// 판 끝 "  블록:" 줄 (npm run stats). 떨어진 블록은 착지할 때, 건축가 블록은 칸마다, 갈고리 R 은 박힐 때 셈
export const LANDED_LOG = { auto: '자동', sky: '하늘', control: '조종', item: '설치', builder: '건축가', hook: '갈고리', ghost: '유령' };
export function emptyLanded() {
  return Object.fromEntries(Object.keys(LANDED_LOG).map((k) => [k, 0]));
}
// 사망 로그 "밟은 칸" (한 단어, npm run stats)
export const GROUND_LOG = { floor: '바닥', terrain: '지형', stack: '블록', sky: '하늘', piece: '낙하블록', none: '없음' };

export const WEAPON_LOG = { ghost: '유령블록', push: '밀치기', shell: '포탄', bigshell: '대형포탄', groundshot: '발밑포격', leapwave: '광폭도약', spin: '소용돌이회전', spinend: '소용돌이', note: '음파', riff: '기타리프', glide: '낙하음파', amp: '앰프', ampend: '앰프마무리', pounce: '덮치기', execute: '처형사격', wallkick: '벽차기', blast: '블록폭발', bigbomb: '대폭발', projectile: '투사체', shock: '충격파', bomb: '폭탄', control: '조종블록', thrown: '설치블록', slam: '내려찍기', hook: '갈고리', charge: '돌진', slash: '순간베기', wall: '솟는벽', blockslam: '블록내려찍기' };

export function causeKo(cause) {
  if (cause === 'crush') return '압사';
  if (cause === 'fall') return '낙사';
  if (cause === 'lava') return '용암';
  if (cause === 'disconnect') return '접속 끊김';
  if (cause === 'hp') return '체력';
  return cause;
}
