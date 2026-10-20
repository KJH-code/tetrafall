// Tetrafall — 모든 튜닝 수치는 이 파일 하나에 모은다.
// 서버와 클라이언트가 같이 import 한다. (서버: ../shared/config.js, 클라: /shared/config.js)
// 좌표계: x,y 는 바닥 격자, z 는 위쪽. 블록 한 칸 = 1 단위.

export const CONFIG = {
  // ---- 네트워크 / 루프 ----
  PORT: 3000,
  TICK_RATE: 30, // 서버 고정 틱 (Hz)
  // 인원. 2026-10-20 2인 고정 → 2명 이상 가변. 최대는 SPAWN_POINTS 개수(8)까지
  MAX_PLAYERS: 4, // 방에 들어올 수 있는 최대 인원 (넘으면 접속 거부)
  MIN_PLAYERS: 2, // 호스트가 시작할 수 있는 최소 인원

  // ---- 필드 ----
  GRID_W: 6, // x 칸 수
  GRID_D: 6, // y 칸 수
  GRID_H: 12, // z 칸 수 (높이)
  FALL_DEATH_Z: -4, // 발 높이가 이 아래로 내려가면 낙사

  // ---- 블록 낙하 ----
  AUTO_FALL_STEP_MS: 350, // 자동 낙하: 1칸 내려오는 간격. 2026-10-20 500→350 (12칸 낙하 6초 → 4.2초)
  HARD_DROP_STEP_MS: 80, // 하드드롭 후 1칸 내려오는 간격
  AUTO_SPAWN_DELAY_MS: 1000, // 착지 후 다음 자동 블록이 나오기까지. 2026-10-20 2000→1000 (블록 주기 8초 → 약 5.2초)
  FIRST_SPAWN_DELAY_MS: 1000, // 판 시작 후 첫 블록까지 (첫 착지 = 이 값 + 12칸 × AUTO_FALL_STEP_MS). 2026-10-20 3000→1000
  SHADOW_LEAD_MS: 3000, // 착지 몇 ms 전부터 그림자 표시
  PIECE_SPAWN_Z: 12, // 블록이 나타나는 높이 (= GRID_H 권장: 필드 바로 위)
  SPAWN_TRIES: 50, // 아이템 자리를 찾는 시도 횟수
  // 자동 블록(조종 안 된 블록)이 가장 낮은 층을 클리어하는 쪽으로 떨어지게 하는 유도. 2026-10-20 도입
  // 점수가 1 높을 때마다 뽑힐 확률이 exp(CLEAR_BIAS) 배. 0 = 완전 무작위 (예전 방식)
  // 시뮬레이션 (블록만 떨어뜨림, 300회): 20블록 안에 층 클리어가 한 번이라도 난 비율
  //   0 → 0%, 0.6 → 28%, 1 → 71% (첫 클리어 중앙값 10블록 ≈ 52초), 2 → 76%
  CLEAR_BIAS: 1,
  CLEAR_PICK_SHAPE: true, // true: 모양도 유도로 고름. false: 모양은 무작위 (이러면 bias 2 여도 22%)
  CLEAR_SCORE: { FILL: 4, CLEAR: 6, BAD_GAP: 3, HOLE: 3 }, // 점수 항목 (server/game.js placementScore 설명 참고)

  // ---- 조종권 ----
  CONTROL_TIME_MS: 8000, // 이 안에 안 떨구면 자동 낙하
  // true: 조종권을 먹는 즉시 조종 시작 (떨어지던 자동 블록을 넘겨받거나 새 블록). false: 다음 블록부터 조종. 2026-10-20 도입
  CONTROL_TAKEOVER: true,
  CONTROL_ITEM_RESPAWN_MS: 6000, // 조종권 아이템 재스폰 대기
  CONTROL_HOVER_Z: 12, // 조종 중 블록이 떠 있는 높이

  // ---- 넉백 아이템 / 투사체 ----
  KNOCKBACK_ITEM_RESPAWN_MS: 8000,
  KNOCKBACK_AMMO: 1, // 아이템 하나당 발사 횟수
  PROJECTILE_SPEED: 18, // 단위/초
  PROJECTILE_RADIUS: 0.2,
  PROJECTILE_LIFE_MS: 1500,
  PROJECTILE_KB_SPEED: 9, // 투사체 맞았을 때 수평 넉백 속도
  PROJECTILE_KB_UP: 4, // 투사체 맞았을 때 위로 튀는 속도

  // ---- 밀치기 (근접) ----
  PUSH_RANGE: 1.8, // 사거리 (중심 거리)
  PUSH_HALF_ANGLE_DEG: 60, // 바라보는 방향 기준 반각
  PUSH_COOLDOWN_MS: 600,
  PUSH_KB_SPEED: 4.2, // 밀려나는 거리 약 1.5칸. 2026-10-20 7→3.5(1.2칸)→4.2. 시작 위치(가장자리에서 1.5칸)에서 한 번 밀려도 안 떨어지는 상한 근처
  PUSH_KB_UP: 3,

  // ---- 경직 ----
  STUN_MS: 500, // 넉백 맞으면 이 동안 조작 불가 + 추가 넉백 무시

  // ---- 플레이어 물리 ----
  PLAYER_HALF: 0.3, // AABB 반폭 (x,y)
  PLAYER_HEIGHT: 1.6,
  EYE_HEIGHT: 1.45,
  MOVE_SPEED: 4.5, // 단위/초
  JUMP_SPEED: 7.5, // 최고 높이 약 1.28칸 → 1칸 블록은 올라가고 2칸 벽은 못 넘음. 2026-10-20 6.5→7.5 (6.5는 0.95칸이라 1칸도 못 올라감)
  GRAVITY: 20,
  DASH_SPEED: 6, // 대시 순간 속도. 2026-10-20 10→6 (땅에서 약 1.7칸 → 약 1칸)
  DASH_COOLDOWN_MS: 1500,
  KB_DAMPING_GROUND: 6, // 외부 속도(넉백·대시) 감쇠율 /초, 땅
  KB_DAMPING_AIR: 1.2, // 외부 속도 감쇠율 /초, 공중
  MAX_STEP_DT: 0.05, // 물리 서브스텝 상한 (초)

  // ---- 아이템 ----
  ITEM_PICK_RADIUS: 0.6, // 플레이어 중심과 아이템 중심 수평 거리
  ITEM_HEIGHT_TOL: 1.2, // 발 높이와 아이템 바닥 높이 차 허용

  // ---- 판 ----
  PASS_CRUSH_SHARE: 0.5, // 1단계 합격선: 누적 사망 중 압사 비율. 판 종료 로그에 표시. 2026-10-20 재정의
  ROUND_TIME_LIMIT_MS: 0, // 0 = 제한 없음. 양수면 시간 초과 시 무승부
  // 2026-10-20 모서리 칸 → 한 칸 안쪽. 가장자리에서 1.5칸이라 밀치기 한 번으로는 안 떨어진다.
  // 순서대로 P1, P2, ... 에 배정. 모두 필드 중앙을 바라본다. 2인일 때는 대각선 마주보기
  SPAWN_POINTS: [
    { x: 1.5, y: 1.5, yaw: Math.PI / 4 }, // P1
    { x: 4.5, y: 4.5, yaw: (-3 * Math.PI) / 4 }, // P2
    { x: 4.5, y: 1.5, yaw: (3 * Math.PI) / 4 }, // P3
    { x: 1.5, y: 4.5, yaw: -Math.PI / 4 }, // P4
    { x: 3, y: 1.5, yaw: Math.PI / 2 }, // P5
    { x: 3, y: 4.5, yaw: -Math.PI / 2 }, // P6
    { x: 1.5, y: 3, yaw: 0 }, // P7
    { x: 4.5, y: 3, yaw: Math.PI }, // P8
  ],

  // ---- AI 봇 (서버에서 돎, 사람과 같은 입력만 씀) ----
  BOT_THINK_MS: 100, // 판단 주기
  BOT_REACTION_MS: 450, // 그림자가 보이고 나서 피하기 시작할 때까지 (사람 반응 흉내)
  BOT_AIM_ERROR_RAD: 0.3, // 투사체 조준 오차 (라디안, ± 이 안에서 무작위)
  BOT_DROP_DELAY_MS: 250, // 조종 중 상대 위에 맞춘 뒤 떨어뜨리기까지
  BOT_PUSH_INTERVAL_MS: 1500, // 봇이 밀치기 사이에 두는 간격 (×0.7~1.3 무작위). 낮을수록 공격적

  // ---- 클라이언트 ----
  MOUSE_SENSITIVITY: 0.0022,
  SKY_CAMERA_HEIGHT: 22, // 하늘 시점 카메라 높이 (필드 중심 위)
  SKY_TRANSITION_MS: 700, // 1인칭 ↔ 하늘 시점 전환 애니메이션 길이
  TOAST_MS: 2200, // 화면 알림이 떠 있는 시간
  INPUT_SEND_RATE: 30, // 입력 전송 Hz
};
