// 조작 키 설정: 행동마다 키 하나 (키보드 e.code 또는 마우스 'Mouse0'~'Mouse4'). 설정 창에서 바꾸고 이 브라우저에 기억 (tf-keys)
// 판정은 input.js, 화면 글자(도움말·조작법·스킬 칸)는 main.js 의 [data-key] 가 keyLabel 로 바꿔 보여 줌

// 설정 창 순서대로. group 은 설정 창 소제목
export const ACTIONS = [
  { id: 'fwd', label: '앞으로', def: 'KeyW', group: '이동' },
  { id: 'back', label: '뒤로', def: 'KeyS', group: '이동' },
  { id: 'left', label: '왼쪽', def: 'KeyA', group: '이동' },
  { id: 'right', label: '오른쪽', def: 'KeyD', group: '이동' },
  { id: 'jump', label: '점프·2단 점프', def: 'Space', group: '이동' },
  { id: 'dash', label: '대시', def: 'ShiftLeft', group: '이동' },
  { id: 'attack', label: '평타 (밀치기)', def: 'Mouse0', group: '공격' },
  { id: 'item', label: '든 아이템 쓰기', def: 'Mouse2', group: '공격' },
  { id: 'skill', label: '스킬', def: 'KeyF', group: '공격' },
  { id: 'ult', label: '필살기', def: 'KeyR', group: '공격' },
  { id: 'rotL', label: '회전 · 설치 방향 ←', def: 'KeyQ', group: '블록' },
  { id: 'rotR', label: '회전 · 설치 방향 →', def: 'KeyE', group: '블록' },
  { id: 'pieceUp', label: '블록 앞으로', def: 'ArrowUp', group: '블록' },
  { id: 'pieceDown', label: '블록 뒤로', def: 'ArrowDown', group: '블록' },
  { id: 'pieceLeft', label: '블록 왼쪽', def: 'ArrowLeft', group: '블록' },
  { id: 'pieceRight', label: '블록 오른쪽', def: 'ArrowRight', group: '블록' },
  { id: 'drop', label: '블록 바로 낙하', def: 'Enter', group: '블록' },
  { id: 'view', label: '1인칭 ↔ 3인칭', def: 'KeyV', group: '기타' },
  { id: 'emote', label: '이모트 바퀴 (누르고 있기)', def: 'KeyG', group: '기타' },
  { id: 'help', label: '조작법 보기 (누르고 있기)', def: 'KeyH', group: '기타' },
  { id: 'practice', label: '연습 창 열기·닫기 (연습 방) · 점수표 (킬 점수전, 누르고 있기)', def: 'Tab', group: '기타' },
  { id: 'perf', label: '성능 표시 켜기·끄기 (FPS·구간 ms)', def: 'F3', group: '기타' },
  { id: 'tutSkip', label: '튜토리얼 이 단계 넘기기', def: 'KeyN', group: '기타' },
];

export const DEFAULT_BINDS = Object.fromEntries(ACTIONS.map((a) => [a.id, a.def]));

// 왼쪽·오른쪽 Shift 처럼 같은 키는 하나로 (설정에서 어느 쪽을 눌러도 같은 키)
const SAME = { ShiftRight: 'ShiftLeft', ControlRight: 'ControlLeft', AltRight: 'AltLeft', MetaRight: 'MetaLeft' };
export const normCode = (code) => SAME[code] || code;

const MOUSE = ['좌클릭', '휠 클릭', '우클릭', '마우스 뒤', '마우스 앞'];
const NAMED = {
  Space: 'Space', ShiftLeft: 'Shift', ControlLeft: 'Ctrl', AltLeft: 'Alt', MetaLeft: 'Win', Enter: 'Enter', Tab: 'Tab', Backspace: '←Back',
  CapsLock: 'Caps', Escape: 'Esc', ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→',
  Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/',
};

// 화면에 보일 이름: KeyF → F, Digit1 → 1, Mouse2 → 우클릭, Numpad5 → 숫자판 5
export function keyLabel(code) {
  if (!code) return '없음';
  if (code.startsWith('Mouse')) return MOUSE[Number(code.slice(5))] || `마우스 ${code.slice(5)}`;
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Numpad')) return `숫자판 ${code.slice(6)}`;
  return NAMED[code] || code;
}

// 저장된 키 (없거나 깨졌으면 기본값). 없는 행동은 기본값으로 채움 (나중에 행동이 늘어도)
export function loadBinds() {
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem('tf-keys') || '{}') || {};
  } catch {
    saved = {};
  }
  const out = { ...DEFAULT_BINDS };
  for (const a of ACTIONS) if (typeof saved[a.id] === 'string' && saved[a.id]) out[a.id] = saved[a.id];
  return out;
}

export function saveBinds(binds) {
  try {
    localStorage.setItem('tf-keys', JSON.stringify(binds));
  } catch {
    // 저장이 막혀 있어도 이번엔 적용
  }
}

// 겹치는 키: { code: [행동 id, ...] } (둘 이상인 것만)
export function conflicts(binds) {
  const by = {};
  for (const a of ACTIONS) (by[binds[a.id]] ||= []).push(a.id);
  return Object.fromEntries(Object.entries(by).filter(([, ids]) => ids.length > 1));
}

// 여러 키를 묶어 한 덩어리 글자로: 이동 4개가 다 글자 키면 붙여서 (WASD), 아니면 '/' 로 (Q/E, ↑/↓/←/→)
export function groupLabel(binds, ids) {
  const labels = ids.map((id) => keyLabel(binds[id]));
  return ids.length === 4 && labels.every((l) => /^[A-Z0-9]$/.test(l)) ? labels.join('') : labels.join('/');
}

// 이모트 바퀴 칸 고르기 (input.js): w = 바퀴를 연 뒤 마우스를 움직인 양 {x 오른쪽, y 아래}. 위가 0, 시계 방향으로 n 칸.
// minPx 보다 덜 움직였으면 -1 (안 고름)
export function wheelSlot(w, n, minPx) {
  if (!w || !(n > 0) || Math.hypot(w.x, w.y) < minPx) return -1;
  const ang = Math.atan2(w.x, -w.y); // 위 0, 오른쪽 +π/2
  return ((Math.round(ang / ((Math.PI * 2) / n)) % n) + n) % n;
}
