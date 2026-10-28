// 재접속 자리 토큰 (2026-10-28): 방 코드마다 localStorage 에 둠 → 창을 닫았다 다시 열어도·새로고침해도 ?room=코드 로 같은 자리 (서버 rooms.js rejoin)
// 저장이 막힌 브라우저면 그냥 없음 (그땐 예전처럼 새로 들어감)
const key = (code) => `tf-seat:${String(code).toUpperCase()}`;

export function seatToken(code) {
  try {
    return localStorage.getItem(key(code));
  } catch {
    return null;
  }
}

export function saveSeat(code, token) {
  try {
    if (code && token) localStorage.setItem(key(code), token);
  } catch {
    // 저장 못 해도 게임은 됨
  }
}

export function dropSeat(code) {
  try {
    if (code) localStorage.removeItem(key(code));
  } catch {
    // 위와 같음
  }
}
