// 방 나가기: 한 번 더 물어야 하나 (순수 계산 — client/main.js 가 쓰고 test/leave.test.js 가 검증)
// 판 중(카운트다운·진행)이고 연습 방이 아니면 묻는다 — 나가면 그 판은 패배. 대기실·판 끝·연습·관전(이미 죽음)은 바로
export function leaveNeedsConfirm({ phase, practice, alive }) {
  if (practice) return false;
  if (phase !== 'playing' && phase !== 'countdown') return false;
  return alive !== false;
}
