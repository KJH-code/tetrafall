// Tetrafall — 모든 튜닝 수치는 이 파일 하나에 모은다.
// 서버와 클라이언트가 같이 import 한다. (서버: ../shared/config.js, 클라: /shared/config.js)
// 좌표계: x,y 는 바닥 격자, z 는 위쪽. 블록 한 칸 = 1 단위.

// 시작 위치: 가장자리에서 inset 칸 안쪽 8곳. 순서대로 P1, P2, ... (2인은 대각선 마주보기). 모두 필드 중앙을 바라본다
function spawnPoints(W, D, inset) {
  const pts = [
    [inset, inset],
    [W - inset, D - inset],
    [W - inset, inset],
    [inset, D - inset],
    [W / 2, inset],
    [W / 2, D - inset],
    [inset, D / 2],
    [W - inset, D / 2],
  ];
  return pts.map(([x, y]) => ({ x, y, yaw: Math.atan2(D / 2 - y, W / 2 - x) }));
}

const GRID_W = 10;
const GRID_D = 10;
const GRID_H = 16;

export const CONFIG = {
  // ---- 네트워크 / 루프 ----
  PORT: 3000,
  TICK_RATE: 30, // 서버 고정 틱 (Hz)
  // 인원. 2026-10-20 2인 고정 → 2명 이상 가변. 최대는 SPAWN_POINTS 개수(8)까지
  MAX_PLAYERS: 8, // 방에 들어올 수 있는 최대 인원, 사람 + 봇 (넘으면 접속 거부). 2026-10-28 재혁 4 → 8 (필드는 FIELD_SIZES 로 인원 따라 커짐, 팀전은 4:4 까지)
  // 플레이어 색 (2026-10-27 재혁: 사람이 고름). 대기실에서 이 팔레트 중 하나 (방에서 쓰는 색은 못 고름, 먼저 고른 사람 우선).
  // 앞 8색은 예전 자리 순 색 그대로 (고르지 않으면 이 순서로 자동). 블록 모양 색·압사 경고 빨강·치명타 노랑·궁 하늘색과 덜 겹치게 고른 것
  PLAYER_PALETTE: [
    0xe05050, // 빨강
    0x50c050, // 초록
    0xb060e0, // 보라
    0xe0c050, // 금색
    0xf0f0f0, // 하양
    0x40d0c0, // 청록
    0xff80b0, // 분홍
    0x8a5a30, // 갈색
    0xa8e060, // 연두
    0x7a2a58, // 자두
    0x2c2c38, // 숯
    0xa0b4d0, // 회청
    0xd07040, // 녹슨 주황
    0x206050, // 짙은 청록
  ],
  MIN_PLAYERS: 2, // 호스트가 시작할 수 있는 최소 인원
  // 방: 2026-10-22 6단계 (인터넷 대전). 서버 하나에 방 여러 개, 방마다 게임 하나
  // 방 하나(봇 4) ≈ CPU 한 코어의 4%. 사람 하나에 보내는 양 (2026-10-28 잰 값, 압축 후): 4명 판 ≈ 0.4Mbps, 8명 판 ≈ 0.65Mbps (압축 전 1.5·3.4, 하늘 사슬 3개) → 8명 방 하나 ≈ 업로드 5Mbps
  ROOM_MAX: 8, // 서버 하나에 동시에 열 수 있는 방
  ROOM_CODE_LEN: 4, // 방 코드 글자 수
  ROOM_CODE_CHARS: 'ABCDEFGHJKLMNPQRSTUVWXYZ', // 헷갈리는 I·O 뺌
  ROOM_NAME_MAX_LEN: 16, // 방 이름 글자 수
  ROOM_LIST_MS: 1000, // 방 밖(목록 화면)에 있는 사람에게 공개 방 목록을 다시 보내는 간격

  // ---- 필드 ----
  // 2026-10-20 2단계: 6×6×12 → 10×10×16 (4인에 좁음, 위로 올라가는 게임이라 높이도 늘림)
  GRID_W, // x 칸 수 (기본·대기실. 판 크기는 FIELD_SIZES 로 판마다 정함 → game.W·D, snapshot field)
  GRID_D, // y 칸 수
  // 인원별 필드 크기 (2026-10-26 재혁: 4인전이 좁음). 판 시작 때 필드에 나가는 사람·봇 수로 (블록 마스터는 마스터 빼고). 높이는 GRID_H 그대로.
  // 2인은 예전 그대로 10×10 (1:1 느낌 유지). 떨어지는 블록 동시 개수·필드 아이템 수는 넓이(10×10 기준 배율)에 비례
  // 2026-10-28 8인: 5~8명은 한 사람 넓이 약 45~51칸 (4인 49칸과 비슷하게, 많을수록 조금 붐비게 — 판 길이가 너무 늘지 않게)
  FIELD_SIZES: { 2: 10, 3: 12, 4: 14, 5: 16, 6: 17, 7: 18, 8: 19 },
  MAP_MAX_H: 7, // 시작 지형 높이 상한 (shared/maps.js, 하늘 성 뾰족탑 7층)
  GRID_H, // z 칸 수 (높이)
  FALL_DEATH_Z: -4, // 발 높이가 이 아래로 내려가면 낙사

  // ---- 블록 낙하 ----
  // 2단계: 판이 길어질수록 블록이 빨라지고 많아진다 ("처음에 1개, 갈수록 더 짧게, 많이")
  //   동시에 떨어지는 자동 블록 수 = min(MAX, CONCURRENT_START + 경과 / RAMP_MS)
  //   다음 블록까지 간격·1칸 낙하 간격 = 시작값에서 끝값으로 RAMP_FULL_MS 동안 선형으로 줄어듦
  AUTO_FALL_STEP_MS: 500, // 자동 낙하: 1칸 내려오는 간격 (판 시작 때). 2026-10-24 350→500 (재혁: 억까 → 떨어지는 속도 감속)
  AUTO_FALL_STEP_MIN_MS: 300, // 판 후반 (RAMP_FULL_MS 이후). 2026-10-24 200→300
  AUTO_SPAWN_DELAY_MS: 1000, // 자동 블록끼리 나오는 간격 (판 시작 때)
  AUTO_SPAWN_DELAY_MIN_MS: 400, // 판 후반
  CONCURRENT_START: 2, // 판 시작 동시 블록. 2026-10-26 재혁 1 → 2 (판이 짧아 블록이 쌓이기 전에 끝남. 봇 504판: 블록 위 사망 21 → 29%, 압사 32 → 37%, 판 30 → 28초). 하늘 계단 켬 판은 안 씀 (하늘 사슬)
  CONCURRENT_RAMP_MS: 20000, // 이 시간마다 동시 블록 +1
  CONCURRENT_MAX: 4,
  RAMP_FULL_MS: 90000, // 낙하·간격이 끝값에 닿는 시간
  HARD_DROP_STEP_MS: 80, // 하드드롭 후 1칸 내려오는 간격
  FIRST_SPAWN_DELAY_MS: 1000, // 판 시작 후 첫 블록까지
  SHADOW_LEAD_MS: 3000, // 착지 몇 ms 전부터 그림자 표시
  PIECE_SPAWN_Z: GRID_H, // 블록이 나타나는 높이 (필드 바로 위)
  SPAWN_TRIES: 50, // 아이템 자리를 찾는 시도 횟수
  // 자동 블록(조종 안 된 블록)이 가장 낮은 층을 클리어하는 쪽으로 떨어지게 하는 유도. 2026-10-20 도입
  // 점수가 1 높을 때마다 뽑힐 확률이 exp(CLEAR_BIAS) 배. 0 = 완전 무작위 (예전 방식)
  // 시뮬레이션 (블록만 떨어뜨림, 300회): 20블록 안에 층 클리어가 한 번이라도 난 비율
  //   0 → 0%, 0.6 → 28%, 1 → 71% (첫 클리어 중앙값 10블록 ≈ 52초), 2 → 76%
  CLEAR_BIAS: 0.3, // 2026-10-20 2단계: 1 → 약하게 (지형이 쌓여 위로 올라가는 게임. 10×10 시뮬레이션으로 정함)
  CLEAR_PICK_SHAPE: true, // true: 모양도 유도로 고름. false: 모양은 무작위 (이러면 bias 2 여도 22%)
  CLEAR_SCORE: { FILL: 4, CLEAR: 6, BAD_GAP: 3, HOLE: 3 }, // 점수 항목 (server/game.js placementScore 설명 참고)

  // ---- 하늘 계단 (2026-10-26 재혁: 대기실 옵션, 기본 켬) ----
  // 다음 블록들이 미리 높은 하늘에 떠서 천천히 내려온다. 이웃 블록끼리 점프(+공중 점프)로 건너갈 수 있는 높이차·틈으로 놓아 계단이 됨.
  // 모든 하늘 블록이 같은 속도로 내려가서 이웃 사이 높이차·틈은 착지 전까지 그대로. 용암이 켜지면 용암 표면에 닿은 블록은 녹아 사라짐.
  // 끄면 예전 규칙 그대로 (격자 높이 GRID_H, AUTO_FALL 낙하·동시 수). 블록 마스터는 자동 블록이 없어서 무시
  // 닿는 거리 R(h) = MOVE_SPEED × 공중 시간 (꼭대기에서 공중 점프, h = 올라갈 높이): h=0 → 5.8칸, 1 → 5.3, 2 → 4.7
  SKY_STAIRS_DEFAULT: true, // 방(대기실) 기본값. new Game() 기본은 끔 (예전 테스트 그대로)
  SKY_GRID_H: 32, // 켬일 때 격자 높이 (판마다 game.H, snapshot field.h)
  SKY_COUNT: 7, // 사슬 하나에 떠 있는 블록 수 (착지·녹으면 그 사슬 맨 위에 새로)
  // 인원별 사슬 수 (2026-10-28 재혁 "블록 더 많이": 사슬 하나는 착지 빠르기가 정해져 있어 큰 판일수록 블록이 드물었음 → 5명 이상 판은 압사 9~14%).
  // 판 시작 때 필드에 나가는 인원으로 (FIELD_SIZES 와 같은 방식). 사슬마다 SKY_COUNT 개, 따로 계단. 떨어지는 빠르기·그림자(경고) 시간은 그대로
  // 봇 판 (2026-10-28, 인원마다 245판): 사슬 1개면 압사 6명 11% · 8명 8% → 이 표로 6명 22% · 8명 23% (4명 17% 와 비슷), 판 길이 6명 94 → 92초 · 8명 100 → 96초. 2~4명은 그대로
  SKY_CHAINS: { 2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 3, 8: 3 },
  SKY_SPAWN_PER_TICK: 1, // 한 틱에 놓는 하늘 블록 수 (자리 고르기가 무거워서 나눔: 판 시작 사슬 7개 = 7틱 약 0.23초)
  SKY_TOP_Z: 32, // 블록 윗면 최고 높이 (상한)
  SKY_RISE_MIN: 1, // 새 블록 = 맨 위 블록 지금 높이 + 이 범위의 칸 (정수 무작위)
  SKY_RISE_MAX: 2, // 2단 점프 최고 약 2.8칸이라 여유 있게
  SKY_GAP_MIN: 1, // 이웃 블록 칸 사이 최소 거리 (붙으면 머리 부딪힘·한 덩어리로 보임)
  SKY_REACH_SAFETY: 0.5, // 틈은 R(높이차) × 이 값까지 → 높이차 1 이면 약 2.6칸, 2 면 약 2.3칸
  SKY_FALL_STEP_MS: 2500, // 하늘 블록 1칸 내려오는 간격, 판 내내 고정 (예전 AUTO_FALL 500→300)
  // 그림자(경고)는 착지까지 남은 칸 수로: 예전 SHADOW_LEAD_MS(착지 3초 전)는 한 칸 2.5초면 깔리기 0.5초 전이라 못 피함 (봇 판 압사 28% → 55%)
  SKY_LAVA_TRIGGER_MS: 60000, // 켬 판은 판 시작 후 이 시간이 지나면 평균 높이와 상관없이 용암 시작 (2026-10-26 재혁: 착지가 느려 용암이 거의 안 옴, 봇 504판 중 2판)
  // 인원별 (2026-10-28): 사슬이 늘면 계단이 많아져 판이 길어짐 (8명 3사슬 106초) → 5명 이상은 용암을 조금 일찍. 2~4명은 SKY_LAVA_TRIGGER_MS 그대로
  SKY_LAVA_TRIGGER_BY_COUNT: { 2: 60000, 5: 55000, 7: 50000 },
  SKY_SHADOW_CELLS: 3, // 착지 높이 + 이 칸 안으로 내려오면 그림자 (머리 위 약 1.4칸, 깔리기 약 5초 전)
  SKY_BASE_UP: 6, // 사슬 첫 블록 높이: 그 아래 기둥(착지 높이)보다 이만큼 위
  BOT_SKY_HOP_LAVA: 4, // 봇은 용암 표면이 발에서 이 높이(칸) 안이면 하늘 계단으로 올라탐
  BOT_SKY_HOP_DIST: 3, // 봇이 노리는 하늘 블록까지 수평 거리 (칸 모서리까지)

  // ---- 조종권 ----
  CONTROL_TIME_MS: 8000, // 이 안에 안 떨구면 자동 낙하
  // true: 조종권을 먹는 즉시 조종 시작 (떨어지던 자동 블록을 넘겨받거나 새 블록). false: 다음 블록부터 조종. 2026-10-20 도입
  CONTROL_TAKEOVER: true,
  CONTROL_ITEM: false, // 조종권 아이템을 필드에 내놓을지. 2026-10-24 재혁: 뺌 (블록 마스터의 마스터 조종은 그대로)
  CONTROL_ITEM_RESPAWN_MS: 6000, // 조종권 아이템 재스폰 대기
  CONTROL_HOVER_Z: GRID_H, // 조종 중 블록이 떠 있는 높이

  // ---- 아이템 (조종권 제외) — 2단계 ----
  // 필드에 동시에 ITEM_MAX_ON_FIELD 개까지. 종류는 ITEM_POOL 에서 무작위
  ITEMS_ENABLED: false, // 우클릭 파워 아이템을 필드에 내놓을지. 2026-10-26 재혁: 전부 꺼 둠 (코드는 그대로, true 면 예전처럼). 조종권은 CONTROL_ITEM
  ITEM_POOL: ['knockback', 'jump', 'ghost', 'brick', 'bomb', 'speed'], // 2026-10-25 재혁: 망치 아이템 뺌 ("개사기", 망치 모양은 건축가 무기로)
  ITEM_MAX_ON_FIELD: 2,
  ITEM_FIRST_SPAWN_MS: 4000, // 판 시작 후 첫 아이템
  ITEM_RESPAWN_MS: 6000, // 다음 아이템까지
  // 점프력 상승: 최고 높이 약 2.33칸 (2칸 벽은 넘고 3칸은 못 넘음, 30Hz 실측)
  JUMP_BOOST_MS: 8000,
  JUMP_BOOST_SPEED: 10,
  // 유령화: 블록을 옆으로 통과, 점프하면 머리 위 블록을 뚫고 올라가 그 위에 섬, 아래로는 안 빠짐 (한쪽 통과 발판).
  // 압사도 면역 (2026-10-21 재혁: 떨어지는 블록이 그냥 통과). 끝날 때 블록 안이면 그 기둥 꼭대기로 밀려 올라감.
  // 낙사·용암은 그대로 죽음
  GHOST_MS: 6000,
  // 이속 증가 (노란 번개): SPEED_MS 동안 걷는 속도 × SPEED_MULT (대시는 그대로)
  SPEED_MS: 6000,
  SPEED_MULT: 1.4,
  SPEED_TRAIL_RATE: 14, // 이속 증가 중 달릴 때 발밑 잔상이 생기는 빈도 (초당)
  // 이모트 (2026-10-22): G 를 누른 채 마우스 방향으로 고름 (위·오른쪽·아래·왼쪽). 하는 동안 못 움직임, 맞거나 공격하면 끊김
  EMOTE_NAMES: ['손 흔들기', '춤', '웃기', '도발', '전용 도발'], // 바퀴 칸 (위부터 시계 방향, 72°씩). 서버는 이 길이까지만 받음. 마지막 칸 = 캐릭터 전용 (이름은 EMOTE_CHAR_NAMES)
  EMOTE_CHAR: 4, // 캐릭터 전용 도발 번호 (client/figure.js POSES taunt)
  EMOTE_CHAR_NAMES: { tank: '덤벼', ninja: '인 맺기', builder: '어깨 망치', hook: '이리 와', hunter: '찍었다', cannon: '하늘 포', berserker: '포효', bard: '인사', metal: '메탈 뿔' }, // 전용 도발 칸 이름 (바드는 폼별: metal). 2026-10-28 재혁: AI 가 정하고 gif 로 확인
  POSE_IN_S: 0.22, // 도발·승리 포즈: 준비 자세로 모이는 시간 (초)
  POSE_SNAP_S: 0.1, // 준비 → 결정 포즈로 딱 튀는 시간
  POSE_OUT_S: 0.3, // 도발이 끝나기 전 이 동안 풀려 돌아옴 (승리는 안 풀림)
  EMOTE_MS: 1600,
  EMOTE_COOLDOWN_MS: 2500,
  EMOTE_ARM_SCALE: 1.9, // 이모트 땐 팔을 키워서 멀리서도 동작이 보이게
  EMOTE_PICK_PX: 30,
  EMOTE_CLIPS: ['Wave', 'Dance', 'Yes', 'No', 'Wave'], // 로봇 모델에서 이모트마다 쓰는 동작 (손 흔들기·춤·웃기(끄덕끄덕)·도발(고개 젓기)) // 바퀴 메뉴: 마우스를 이만큼(px) 움직여야 고른 것으로 침
  // 손에 드는 아이템은 하나만 (2026-10-24 재혁: 핫바·쌓기 블록 없앰). 들고 있으면 다른 손 아이템은 못 주움 (필드에 남음).
  // 우클릭으로 씀 (투사체·설치 블록·폭탄). 버프(점프·유령·이속)는 먹자마자 효과라 따로
  HELD_ITEMS: ['knockback', 'brick', 'bomb'],
  // 폭탄: 설치 블록과 같은 조준으로 던지면 그 칸 위에 놓여 BOMB_FUSE_MS 깜빡이다 터짐.
  // 폭탄 칸 중심 가로세로 ±BOMB_RADIUS, 위아래 ±BOMB_RADIUS 블록을 부숨 (시작 지형 포함). 던진 사람은 폭발 면제
  BOMB_USES: 1,
  BOMB_FUSE_MS: 1500,
  BOMB_RADIUS: 1, // 3×3×3
  BOMB_BLAST_RANGE: 2, // 폭탄 중심에서 이 수평 거리·높이 차 안의 사람을 날림
  BOMB_KB_SPEED: 8.4,
  BOMB_KB_UP: 5,
  BOMB_STUN_MS: 1200,
  // 설치 블록 (2026-10-20 개편): 우클릭으로 조준점이 가리키는 칸(최대 BRICK_RANGE 칸 앞) 위 공중에 블록을 만들어 떨어뜨린다.
  // 그림자가 보이고, 밑에 있으면 압사, 착지한 칸 바로 옆에 있으면 충격파로 망치급 넉백 + 피해 %.
  // 투사체와 우클릭을 같이 써서, 둘 중 나중에 먹은 쪽만 남는다. 1×2 는 Q/E 로 앞으로 ↔ 옆으로
  BRICK_USES: 2, // 아이템 하나당 던지는 횟수
  BRICK_RANGE: 4, // 조준점 방향 수평 최대 거리 (칸). 그 안에서 시선이 지형에 닿는 칸, 안 닿으면 끝 칸
  BRICK_MIN_DIST: 1.3, // 이보다 가까운 칸은 안 고름 (반폭 0.3 + 1: 내 몸 위로는 안 떨어짐)
  BRICK_DROP_HEIGHT: 3, // 착지 높이보다 이만큼 위에서 생겨 떨어짐
  BRICK_FALL_STEP_MS: 300, // 한 칸 내려오는 간격 → 3칸 약 0.9초
  BRICK_SHOCK_RANGE: 1, // 착지한 블록 가장자리에서 이 거리(칸) 안 = 충격파
  BRICK_SHOCK_KB_SPEED: 8.4, // 예전 아이템 망치와 같은 세기
  BRICK_SHOCK_KB_UP: 4,
  BRICK_SHOCK_STUN_MS: 1200,
  BRICK_SHOCK_HEIGHT: 1.5, // 충격파가 닿는 높이 차 (착지 높이와 발 높이 차, 칸)

  // ---- 피해 % (대난투식, 2026-10-20) ----
  // 맞을 때마다 공격 종류별로 쌓이고 판 내내 안 줄어든다. 수평 넉백 = 기본 × (DAMAGE_KB_BASE + 피해% × DAMAGE_KB_PER_PERCENT).
  // 경직 중이라 무시된 공격은 안 쌓인다. 압사·용암은 % 와 상관없이 즉사
  DAMAGE_GAIN: { push: 10, projectile: 20, shock: 40, bomb: 40 },
  // 0% 에선 예전의 0.7배로 약하게 시작, 30% 에서 예전과 같고 그 뒤로 더 세짐 (2026-10-20 재혁 결정 c:
  // 예전 세기에서 시작하니 봇 판 중앙값이 43 → 20초로 줄어서)
  DAMAGE_KB_BASE: 0.7,
  DAMAGE_KB_PER_PERCENT: 0.01,

  // ---- 투사체 (넉백 아이템) ----
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

  // ---- 캐릭터 평타 (2026-10-25 재혁 승인, 스매시 레전드식) ----
  // 캐릭터가 있는 게임에서만 (캐릭터 없는 예전 규칙은 위 밀치기 그대로). 망치를 들면 망치가 우선.
  // 2026-10-25 재혁: 공중 평타도 캐릭터마다 타 수가 다름 (air 를 배열로. 건축가·탱크·갈고리 1타, 닌자 2타). 공중 연타 중간 타는 지상처럼 고정 넉백
  // 지상: 앞 타가 끝나고 BASIC_CHAIN_WINDOW_MS 안에 다시 누르면 다음 타 (후딜 중에 누르면 기다렸다 나감), 놓치면 1타부터.
  // 2026-10-25 재혁: 허공 이어 치기 — 빗나가도 다음 타로 이어짐 (빗나간 타도 후딜은 다 받음. 예전엔 빗나가면 1타부터)
  // 스킬(F)을 쓰면 이어 치기 창이 다시 열림 (타 번호 그대로) → 평타 → 스킬 → 평타.
  // 한 타 = windup(준비, 이 뒤에 판정) → rec(후딜, 이 뒤에 다음 타). 중간 타 넉백 kb 는 고정 (피해 % 와 상관없음, 콤보 감쇠 없음) → 몇 % 든 이어짐.
  // 마무리 타(finish)와 공중 평타의 kb 는 밀치기처럼 피해 % 배율. 마무리 타가 맞으면 콤보 마무리 (×COMBO_FINISH_KB, 무적).
  // step: 판정 순간 때리는 쪽이 앞으로 나가는 거리 (칸). 경직 stun ≥ rec + 다음 타 windup + 약 0.1초 → 바로 누르면 확정.
  // 공중: air 배열 순서대로 (지상 타 번호와 따로 셈, 같은 이어 치기 창). 떨어지며 위에서 치면 치명타. 이어 치기 창 유지
  BASIC_CHAIN_WINDOW_MS: 500,
  BASIC_HITSTOP_MS: 60, // 중간 타 멈칫 (공중 한 타짜리는 HITSTOP_MS)
  JUMP_BUFFER_MS: 200, // 땅에서 누른 점프를 이만큼 기억 (멈칫·후딜 중 짧게 눌러도 씹히지 않게)
  STREAK_MS: 1000, // 때린 쪽 이어 넣은 타 수: 이 시간 안에 또 맞히면 상대가 바뀌어도 이어짐 (닌자 갈아타기 'N HIT', streak 이벤트)
  BASIC_FINISH_HITSTOP_MS: 110, // 마무리 타 멈칫
  BASIC_STEP_GAP: 0.6, // step 으로 나갈 때 앞 상대와 이 거리 앞에서 멈춤 (지나쳐서 등 뒤로 가지 않게)
  BASIC_FINISH_MOVE_MULT: 0.5, // 마무리 타 준비 중 이동 속도 (예고 모션 동안 묶임)
  // F·R 캔슬 (2026-10-25 재혁 승인): 평타가 맞은 뒤 후딜이면 후딜을 끊고 바로, 빗나간 뒤 후딜이면 후딜이 끝나고, 준비 중이면 판정을 기다림 (수치 없음, game.js cast)
  // 카운터히트 (2026-10-25 재혁 승인): 맞는 쪽이 공격 동작 중이면 경직 ×, 멈칫 × (이미 경직 중이면 아님).
  // 2026-10-25 재혁 결정 (첫 사람 플레이테스트 14판에 86번, 동시에 누른 평타끼리도 카운터): 빗나간 평타의 후딜·스킬·필살기 준비(돌진 중 포함)만. 평타 준비 중·맞힌 평타의 후딜은 아님
  // 봇 480판: 한 판에 약 10번 (넣음·당함 캐릭터별 고름)
  COUNTER_STUN_MULT: 1.5,
  COUNTER_HITSTOP_MULT: 1.5,
  BASIC_ATTACKS: {
    // 탱크 (2026-10-25 재혁 확정, docs/characters.md 3.3 버티기(반격)형·초보 추천): 평평평(방패 올려치기로 띄움) → 점프 → 공중 방패 내려치기(마무리).
    // 3타는 마무리 아님 (예전 방패 밀기는 마무리라 멀리 날아가 공중 평타가 못 따라감). 2타는 띄우지 않고 경직을 길게 (3타 확정)
    tank: {
      chain: [
        { name: '주먹', windup: 120, rec: 300, stun: 550, dmg: 5, kb: 1.5, up: 2, step: 0.4 },
        { name: '어깨 박치기', windup: 150, rec: 350, stun: 750, dmg: 6, kb: 2, up: 1, step: 0.8 },
        { name: '방패 올려치기', windup: 300, rec: 500, stun: 900, dmg: 8, kb: 0.5, up: 8, step: 0.3 },
      ],
      air: [{ name: '방패 내려치기', windup: 150, rec: 400, stun: 600, dmg: 10, kb: 3.8, up: 1, step: 0, finish: true }],
    },
    // 닌자 (2026-10-25 재혁 확정, docs/characters.md 3.2 연계형): 지상 4타 + 공중 2타. 콤보 사이 후딜은 짧고 연타 마지막 타 뒤 후딜은 김 (허공 이어 치기 스팸 방지).
    // 4타 올려 차기는 마무리 아님 — 띄워서 공중 평타로 이어 감. 공중 2타 내려 차기가 마무리. 수치는 초안 (stun·kb 는 문서에 없어 A 가 정함).
    // 2026-10-25 재혁: 올려 차기 후딜 500 → 350 (사람 손으로 풀 콤보가 들어가게)
    ninja: {
      chain: [
        { name: '찌르기', windup: 60, rec: 150, stun: 330, dmg: 3, kb: 0.8, up: 1, step: 0.3 },
        { name: '반대 찌르기', windup: 60, rec: 150, stun: 340, dmg: 3, kb: 0.8, up: 1, step: 0.3 },
        { name: '앞차기', windup: 70, rec: 170, stun: 400, dmg: 3, kb: 0.8, up: 1, step: 0.3 },
        { name: '올려 차기', windup: 120, rec: 350, stun: 900, dmg: 5, kb: 0.5, up: 8, step: 0.2 },
      ],
      air: [
        { name: '공중 베기', windup: 60, rec: 150, stun: 400, dmg: 3, kb: 0.8, up: 3, step: 0 },
        { name: '내려 차기', windup: 100, rec: 450, stun: 500, dmg: 5, kb: 4.6, up: 1, step: 0, finish: true },
      ],
    },
    // 건축가: 옆치기 → 반대로 치기 → 내려찍기 + 바닥 블록 1칸 솟음 (맞으면 그 사람 발밑, 빗나가면 앞 칸). 카운터히트 뒤 28% → 내려찍기 딜 11 → 10. 맵 섞은 판 28% → 1·2타 딜 7 → 6
    builder: {
      chain: [
        { name: '옆치기', windup: 120, rec: 300, stun: 550, dmg: 6, kb: 1.2, up: 2, step: 0.4 },
        { name: '반대 치기', windup: 120, rec: 350, stun: 800, dmg: 6, kb: 1.2, up: 2, step: 0.4 },
        { name: '내려찍기', windup: 350, rec: 450, stun: 700, dmg: 10, kb: 2.5, up: 8, step: 0.3, finish: true, raise: true },
      ],
      air: [{ name: '망치 내려찍기', windup: 200, rec: 450, stun: 500, dmg: 9, kb: 3, up: 2, step: 0 }],
    },
    // 갈고리 (2026-10-25 재혁 확정, docs/characters.md 3.4 그래플러): 휘두르기 → 주먹 → 장전이면 탕(빈 총이 됨) / 빈 총이면 갈고리 내려치기.
    // 공중은 갈고리 수평 한 바퀴 (주변 전부). 패시브 사거리 ×1.2 삭제. 수치는 초안 (stun·kb 는 문서에 없어 A 가 정함)
    hook: {
      chain: [
        { name: '갈고리 휘두르기', windup: 150, rec: 300, stun: 550, dmg: 6, kb: 2, up: 3, step: 0 },
        { name: '주먹', windup: 150, rec: 300, stun: 600, dmg: 6, kb: 1.5, up: 2, step: 0.4 },
        {
          name: '갈고리 내려치기', windup: 200, rec: 450, stun: 500, dmg: 6, kb: 3, up: 2, step: 0.3, finish: true,
          loaded: { name: '탕', windup: 200, rec: 500, stun: 600, dmg: 12, kb: 7, up: 3, step: 0, range: 2, angle: 75, finish: true, shot: true }, // 장전돼 있으면. kb 6 → 7 (2026-10-25 재혁, 봇 504판 갈고리 12% → 18%)
        },
      ],
      air: [{ name: '갈고리 스핀', windup: 150, rec: 400, stun: 500, dmg: 6, kb: 3, up: 2, step: 0, angle: 180 }],
    },
    // 사냥꾼 (2026-10-26 재혁 확정, docs/characters.md 3.5 사냥꾼형): 베기 → 반대 베기 → 찔러 넣기 (맞으면 표식 +1). 속도는 탱크와 닌자 사이.
    // 공중 내려 베기 1타는 표식 없음. 수치는 초안 (stun·kb 는 문서에 없어 A 가 정함)
    // 2026-10-26 재혁 ㄱ: 공중 내려 베기 = 마무리 (가+다 뒤 킬 낼 타가 없었음). 평평평(표식) → F 덮침 → 평평평 → 점프 → 공중 마무리. kb 는 탱크 공중 마무리 수준
    // 2026-10-26 재혁 결정 "가": 찔러 넣기는 마무리 아님 (봇 판: 마무리 → 무적이라 F 덮침·R 이 거의 다 빗나감). 이어지는 타 수준 kb + 긴 경직 → F 덮침·평타로 이어 감
    hunter: {
      chain: [
        { name: '베기', windup: 100, rec: 250, stun: 450, dmg: 5, kb: 1.2, up: 2, step: 0.3 },
        { name: '반대 베기', windup: 100, rec: 250, stun: 550, dmg: 5, kb: 1.2, up: 2, step: 0.3 },
        { name: '찔러 넣기', windup: 200, rec: 450, stun: 850, dmg: 8, kb: 1.5, up: 2, step: 0.4, mark: true }, // stun ≥ F 준비 200 + 도약 300 + 여유
      ],
      air: [{ name: '내려 베기', windup: 150, rec: 400, stun: 600, dmg: 7, kb: 3.8, up: 1, step: 0, finish: true }],
    },
    // 대포수 (2026-10-26 재혁 확정, docs/characters.md 3.6 견제): 탄이 있으면 평타 = 포탄 (서버가 날리는 보이는 투사체, 지상·공중), 없으면 대포 후려치기.
    // 한 타짜리 (이어 치기 없음). 수치는 초안 (준비·후딜·경직·넉백은 A 가 정함)
    cannon: {
      chain: [
        { name: '후려치기', windup: 150, rec: 400, stun: 500, dmg: 5, kb: 3.5, up: 2, step: 0.2, finish: true, ammo: { name: '포탄', windup: 150, rec: 350, shell: true } },
      ],
      air: [{ name: '후려치기', windup: 150, rec: 400, stun: 500, dmg: 5, kb: 3.5, up: 2, step: 0, ammo: { name: '포탄', windup: 150, rec: 350, shell: true } }],
    },
    // 광전사 (2026-10-26 재혁 확정, docs/characters.md 3.7 돌파·쉬움): 판정 넓은 2타 (가로 베기 → 내려찍기 마무리) + 공중 회전 베기 (사방).
    // windup·rec·dmg 는 문서 초안, stun·kb·사거리는 A 가 정함
    berserker: {
      chain: [
        { name: '가로 베기', windup: 150, rec: 300, stun: 650, dmg: 7, kb: 1.5, up: 1, step: 0.3, range: 2.1 },
        { name: '내려찍기', windup: 250, rec: 450, stun: 700, dmg: 10, kb: 4.4, up: 3, step: 0.3, finish: true },
      ],
      air: [{ name: '회전 베기', windup: 150, rec: 400, stun: 550, dmg: 8, kb: 3.5, up: 2, step: 0, angle: 180, radial: true }], // angle 180 = 사방, radial = 바깥으로 밀침
    },
    // 바드 (2026-10-26 재혁 확정, docs/characters.md 3.8 폼 체인지): 음유시인 폼 = 류트 음파(약한 원거리, 둔화) + 공중 천천히 낙하, 메탈 폼(metal) = 기타 근접 2타 + 공중 기타 꽂기.
    // 압사 원칙: 점프 봉인·입력 무시 없음, 둔화 약하게. 수치는 초안 (A 가 정함)
    bard: {
      chain: [{ name: '류트 음파', windup: 150, rec: 350, stun: 300, dmg: 3, kb: 1, up: 0.5, step: 0, note: true }],
      air: [{ name: '천천히 낙하', windup: 100, rec: 300, stun: 300, dmg: 3, kb: 1.5, up: 1, step: 0, range: 1.2, glide: true }], // 2026-10-27 재혁: 누를 때마다 (착지 전 BARD_GLIDE_MAX_PER_AIR 번) 몸 둘레 range 칸 음파 고리, 바깥으로 고정 넉백. 둔화 없음
      metal: {
        chain: [
          { name: '기타 후려치기', windup: 150, rec: 300, stun: 650, dmg: 6, kb: 1.5, up: 1, step: 0.3 },
          { name: '기타 내려치기', windup: 250, rec: 450, stun: 700, dmg: 10, kb: 4.6, up: 3, step: 0.3, finish: true },
        ],
        air: [{ name: '기타 꽂기', windup: 150, rec: 400, stun: 600, dmg: 9, kb: 3.8, up: -4, step: 0, angle: 180, finish: true, dive: true }], // 누르면 아래로 빠르게 낙하 (BARD_DIVE_*), 내려가며 닿은 상대는 아래로 꽂고 (up 음수), 못 닿으면 착지 충격
      },
    },
  },

  // ---- 경직 ----
  STUN_MS: 500, // 밀치기 히트 경직: 이 동안 조작 불가. 경직 중에 또 맞으면 콤보 (밀치기 쿨 600 보다 짧아 평타만으로는 안 이어짐)
  // 콤보 (2026-10-24 재혁): 경직 중에 또 맞히면 콤보가 이어짐. 경직이 풀리면(끊김) 또는 첫 타에서 COMBO_MS 가 지난 뒤 들어간 타(마무리)에
  // 콤보가 끝나고 COMBO_IFRAME_MS 무적 (공격만 막음, 압사·낙사·용암은 못 막음). 여럿이 때려도 맞는 사람 기준으로 셈.
  // 2026-10-25 재혁: 타 수(5타) 대신 시간으로 끊음 (다타 캐릭터도 스킬까지 이어지게. 3초 제안 → 재혁 1초), 무적 1초는 "개사기 + 흐름이 끊김" → 0.3초
  // 콤보 중 가벼운 공격(밀치기·베기·돌진·갈고리)은 수평 넉백 ×COMBO_LIGHT_KB, 마지막 타는 ×COMBO_FINISH_KB 로 크게 날림
  // 2026-10-25 재혁 승인: 1.0 → 1.4초 (닌자 평타 5타 최단 1.18초 + 입력 여유). 캐릭터 평타의 마무리 타(finish)는 시간과 상관없이 마무리
  COMBO_MS: 1400, // 2026-10-25 재혁: 때린 쪽이 연타를 이어 가는 중인 타는 이 시간이 지나도 시간 마무리가 아님 (연타 마무리·끊김·경직 풀림으로 끝)
  COMBO_IFRAME_MS: 300,
  COMBO_LIGHT_KB: 0.6,
  COMBO_FINISH_KB: 1.3,
  // 치명타 (2026-10-21 재혁): 밀치기·망치를 공중에서 떨어지는 중에, 발이 상대보다 CRIT_MIN_HEIGHT 이상 높을 때 맞히면
  // 피해 % × CRIT_DAMAGE_MULT, 수평 넉백 × CRIT_KB_MULT, 멈칫 × CRIT_HITSTOP_MULT (마리오 밟기 느낌, 타이밍 실력)
  CRIT_MIN_HEIGHT: 0.3,
  CRIT_DAMAGE_MULT: 1.5,
  CRIT_KB_MULT: 1.25,
  CRIT_HITSTOP_MULT: 2,
  HITSTOP_MS: 90, // 2단계 타격감: 명중 순간 때린 쪽·맞은 쪽이 멈칫하는 시간 (그 뒤 날아감)

  // ---- 플레이어 물리 ----
  PLAYER_HALF: 0.3, // AABB 반폭 (x,y)
  PLAYER_HEIGHT: 1.6,
  EYE_HEIGHT: 1.45,
  MOVE_SPEED: 4.5, // 단위/초
  AIR_JUMPS: 1, // 공중에서 더 뛸 수 있는 횟수 (2단 점프). 2026-10-24 재혁: 이동성 (쌓인 지형에 갇힘)
  AIR_JUMP_SPEED: 7.5, // 2단 점프 위 속도 → 두 번 합쳐 약 2.5칸 (2칸 벽을 넘음)
  CRUSH_WARN_MS: 2000, // 내 머리 위로 떨어지는 블록이 이 시간 안에 깔면 경고 (발밑 빨간 표시·경고음·화면 글자)
  // 머리 박음 (2026-10-26 재혁: 압사 완화): 떨어지는 블록이 몸에 닿아도 블록 아래로 빠져나갈 빈 공간이 이 칸 이상이면 압사 대신 아래로 밀려남 + 짧은 경직
  CRUSH_ESCAPE_CELLS: 2, // 블록 아래면 ~ 몸 아래 기둥 꼭대기(필드 밖은 끝없이). 땅에 서 있으면 키(1.6)보다 작을 때 닿으므로 그대로 압사
  HEAD_BONK_STUN_MS: 180,
  HEAD_BONK_FX_MS: 700, // 머리 박음 화면: 머리 위 노란 별이 도는 시간 (경직보다 조금 길게, 살았다는 게 보이게)
  HEAD_BONK_NOD: 0.7, // 머리 박음: 머리가 숙여지는 각 (라디안)
  HEAD_BONK_SQUASH: 0.08, // 머리 박음: 몸이 잠깐 눌려 내려가는 높이 (칸)
  HEAD_BONK_SHAKE: 0.12, // 머리 박음 (내 것): 화면 흔들림
  JUMP_SPEED: 7.5, // 최고 높이 약 1.28칸 → 1칸 블록은 올라가고 2칸 벽은 못 넘음. 2026-10-20 6.5→7.5 (6.5는 0.95칸이라 1칸도 못 올라감)
  GRAVITY: 20,
  DASH_SPEED: 6, // 대시 순간 속도. 2026-10-20 10→6 (땅에서 약 1.7칸 → 약 1칸)
  DASH_COOLDOWN_MS: 1500,
  AIR_DASHES: 1, // 공중 대시는 착지 전 이 횟수까지 (땅·블록·하늘 블록에 서면 다시 채움). 2026-10-26 재혁: 하늘 계단에서 공중 대시 연타로 버티기 막음. 지상 대시는 쿨타임만
  KB_DAMPING_GROUND: 6, // 외부 속도(넉백·대시) 감쇠율 /초, 땅
  KB_DAMPING_AIR: 1.2, // 외부 속도 감쇠율 /초, 공중
  // 벽 튕김 (2026-10-23 재혁: 피해 240% 인데 벽에 막혀 20번 넘게 맞기만 함). 위로 뜨는 힘은 % 와 상관없이 일정해서 1칸 턱도 못 넘었음.
  // 넉백으로 날아가다 벽에 박히면 그 수평 속도 × 비율을 위로 (맞을 때마다 한 번). 1칸을 넘으려면 약 6.3, 2칸 8.9, 3칸 11
  WALL_BOUNCE_RATIO: 1.0,
  WALL_BOUNCE_MIN_SPEED: 3, // 이보다 느리게 박히면 그냥 멈춤 (톡 치였을 때 깡충 안 뜨게)
  WALL_BOUNCE_MAX_UP: 11, // 위로 뜨는 속도 상한 (약 3칸)
  MAX_STEP_DT: 0.05, // 물리 서브스텝 상한 (초)

  // ---- 아이템 ----
  ITEM_PICK_RADIUS: 0.6, // 플레이어 중심과 아이템 중심 수평 거리
  ITEM_HEIGHT_TOL: 1.2, // 발 높이와 아이템 바닥 높이 차 허용

  // ---- 용암 (2단계) ----
  // 쌓인 블록의 평균 높이가 기준에 닿으면 경고 → 필드 아래에서 올라온다. 닿으면 즉사 (사망 원인 '용암')
  // 블록 사이에 끼어 진행이 안 되는 판을 끝내고, 위로 올라가게 만든다
  LAVA_TRIGGER_AVG_HEIGHT: 1.0, // 판 시작 뒤 쌓인 평균 기둥 높이 (칸). 시작 지형(맵)은 빼고 잼
  LAVA_START_Z: -1, // 처음 표면 높이 (바닥 아래). 바닥에 선 사람이 올라갈 시간
  // 1칸 올라오는 데 걸리는 시간. 봇 4명 시뮬레이션 40판: 4초면 용암이 판을 끝내기만 하고(최고 높이 3), 16초면 판 중앙 58초·최대 102초·최고 높이 4로 올라가는 플레이가 생김
  LAVA_RISE_MS_PER_CELL: 16000,
  // 용암 연출 (화면만)
  LAVA_LIGHT_INTENSITY: 3, // 용암 빛 세기
  LAVA_LIGHT_RANGE: 9, // 용암 빛이 닿는 거리 (칸)
  LAVA_EMBER_RATE: 12, // 초당 불똥 수

  // ---- 맵 (2단계 D) ----
  MAP_DEFAULT: 'random', // 서버 켤 때 맵 선택: 'random' 또는 server/maps.js 의 MAP_IDS (flat·pyramid·stairs·bowl·spiral·pillars·fortress). 호스트가 대기 화면에서 바꿀 수 있음

  // ---- 캐릭터 (2026-10-24 7단계 재혁: 친구들이 '스킬/고유기 넣어서'. 캐릭터마다 패시브 + 스킬 F(쿨) + 필살기 R(게이지)) ----
  CHARACTERS: ['tank', 'ninja', 'builder', 'hook', 'hunter', 'cannon', 'berserker', 'bard'], // 사냥꾼·대포수·광전사·바드 2026-10-26 (docs/characters.md 3.5~3.8)
  CHAR_NAMES: { tank: '탱크', ninja: '닌자', builder: '건축가', hook: '갈고리', hunter: '사냥꾼', cannon: '대포수', berserker: '광전사', bard: '바드' },
  // 2026-10-24 재혁: 스킬이 직접 피해·넉백을 주고 콤보로 이어지게 (닌자 = 콤보 캐릭터). 남이 쓰는 것도 보이게 예고·효과
  SKILL_NAMES: { tank: '돌진', ninja: '순간 베기', builder: '솟는 벽', hook: '갈고리', hunter: '추적 도약', cannon: '발밑 포격', berserker: '광폭 도약', bard: '폼 전환' },
  ULT_NAMES: { tank: '내려찍기', ninja: '강화', builder: '대폭발', hook: '블록 내려찍기', hunter: '처형 사격', cannon: '대형 포탄', berserker: '분노 소용돌이', bard: '취약의 노래' },
  // 대기실 캐릭터 고르기 설명 카드 (2026-10-28 재혁: '스킬 보기' 를 눌러야 보임). 한 줄 소개 · F · R 짧게
  CHAR_INTRO: { tank: '덜 밀리는 방패 돌격대 — 처음이면 추천', ninja: '끊기지 않는 연타 — 떨어지는 블록을 밟으면 공중 점프가 돌아옴', builder: '블록을 깔고, 망치로 쳐서 터뜨린다', hook: '갈고리로 끌어와서 다시 친다', hunter: '표식을 남기면 끝까지 사냥한다', cannon: '피하면서 멀리서 포탄으로 저격', berserker: '밀릴수록 세진다 — 내 피해 % 만큼 더 멀리 날림', bard: '폼을 바꿔 싸운다 — 음유(원거리·둔화) ↔ 메탈(근접)' },
  SKILL_DESC: { tank: '방패를 앞세워 약 3칸 돌진. 맞아도 안 멈춤', ninja: '보는 쪽으로 순간 이동하며 지나간 상대를 벰', builder: '바로 앞에 가로 3칸 벽을 솟게 해 위 사람을 띄움 (공중이면 발밑에 2칸 기둥을 세우고 그 위에 섬)', hook: '갈고리를 던져 상대를 내 앞으로 끌어옴', hunter: '표식 있는 가까운 상대에게 도약해 덮침', cannon: '발밑에 포격 — 위로 크게 뛰며 주변을 밀침', berserker: '앞으로 크게 뛰어 착지 충격파 (떨어질 때 복귀기)', bard: '폼 전환 — 음유→메탈은 주변 밀침, 메탈→음유는 피해 % 회복' },
  ULT_DESC: { tank: '떠올랐다가 쾅 — 넓은 충격파, 바깥 고리 땅이 솟음', ninja: '잠깐 동안 평타가 표창 2연발', builder: '앞에 큰 블록 묶음이 솟았다가 터짐 (망치로 치면 바로)', hook: '블록 덩어리를 뽑아 들어 내려찍음', hunter: '앞의 표식 대상 전부 처형 사격 (게이지 2배 필요)', cannon: '블록을 뚫고 가는 대형 포탄, 끝에서 폭발', berserker: '빙글빙글 돌며 밀치고 끝에 크게 날림', bard: '앞 상대가 잠깐 더 멀리 날아감 (메탈 폼이면 앰프 음파)' },
  CHAR_STAGE_SPIN: 0.5, // 대기실 큰 3D 캐릭터가 도는 빠르기 (라디안/초). 고르면 정면에서 도발 한 번(EMOTE_MS) 뒤 다시 돎
  CHAR_RANDOM_MS: 650, // '랜덤' 뽑기 연출 길이 (카드 불이 이만큼 돌다가 멈춤)
  CHAR_RANDOM_STEP_MS: 60, // 뽑기 연출에서 불이 옮겨 가는 간격 (끝으로 갈수록 느려짐)
  // 이동 스킬 예고 (2026-10-26 재혁, docs/characters.md 2절): 닌자 F·탱크 F·갈고리 F 는 지상에서 쓰면 SKILL_WINDUP_MS 준비 (방향은 누른 순간 고정, 이벤트 skillWindup → 화면 번쩍·소리)
  // 뒤에 나감, 공중에서 쓰면 바로 (복귀가 안 늦게). 준비 중에 맞으면 끊기고 쿨타임 돌려줌 (카운터 대상)
  SKILL_WINDUP_MS: 150,
  SKILL_WINDUP_CHARS: ['ninja', 'tank', 'hook'],
  SKILL_CD_MS: { tank: 8000, ninja: 6000, builder: 8000, hook: 8000, hunter: 7000, cannon: 8000, berserker: 7000, bard: 6000 }, // 봇 160판으로 맞춤 (2026-10-24). 건축가 11 → 8초 (2026-10-25: F 가 콤보 부품·복귀기, 지상·공중 같이 씀)
  CHAR_DEFAULT: 'tank',
  // 스킬·필살기를 쓰면 그 캐릭터에 빛 (글자 대신, 남에게도 보임. 누가 무엇인지는 캐릭터 모양으로). 2026-10-25 재혁:
  // 전체 느낌을 방해하지 않지만 잘 보이게 → 노을(주황·빨강)과 대비되는 차가운 색, 압사 경고(빨강)·치명타(노랑)와 안 겹치게
  SKILL_AURA_COLOR: 0xffffff, // F: 발밑에 얇은 고리가 짧게 퍼지고 몸이 순간 하얗게 번쩍
  SKILL_AURA_MS: 300,
  SKILL_GLOW_MS: 140,
  SKY_PIECE_WHITEN: 0.35, // 하늘 계단 블록: 모양 색을 흰색으로 섞는 정도 (밝게)
  SKY_PIECE_OPACITY: 0.88, // 하늘 계단 블록 비침 (떠 있는 느낌)
  LABEL_ABOVE_HEAD: 0.3, // 이름표를 머리(모자·모히칸 포함) 꼭대기에서 이만큼 위에 (예전 높이 아래로는 안 내림)
  SHADOW_DARKEN_MS: 1500, // 착지 예고: 이 시간 안으로 들어오면 그림자가 점점 진해짐
  SHADOW_OPACITY_FAR: 0.32, // 멀 때 그림자 진하기
  SHADOW_OPACITY_NEAR: 0.7, // 내려앉기 직전 그림자 진하기
  CRUSH_FLAT_MS: 1100, // 압사: 납작하게 찌그러진 몸이 남는 시간
  CRUSH_FLAT_Z: 0.12, // 납작한 정도 (키 배율)
  SFX_DETUNE: 0.06, // 효과음마다 높낮이를 ±이만큼 랜덤 (같은 소리가 덜 기계적으로)
  OCCLUDE_ENTER: 0.85, // 3인칭·관전: 카메라→캐릭터 선에서 이 거리(칸) 안의 떨어지는 블록 칸은 반투명
  OCCLUDE_EXIT: 1.05, // 반투명이 풀리는 거리 (들어갈 때보다 멀게: 경계에서 깜빡이지 않게)
  OCCLUDE_OPACITY: 0.22,
  ULT_READY_SPARKLE_RATE: 2, // 그 빛에서 위로 오르는 반짝이 (초당, 아주 적게)
  ULT_READY_AURA_OPACITY: 0.24, // R 게이지가 찬 상대 몸 둘레 옅은 빛 (ULT_AURA_COLOR, 숨 쉬듯 75~100%)
  ULT_AURA_COLOR: 0x8fe6ff, // R: 몸이 하늘색으로 빛나는 동안 반짝이가 위로 올라감 + 고리 두 겹
  ULT_AURA_MS: 900,
  COMBO_TEXT_MS: 900, // 내가 때리거나 맞은 콤보 'N HIT' 글자
  ULT_MAX: 100, // 필살기 게이지 (다 차면 R)
  ULT_PER_DAMAGE: 1, // 피해 % 를 주거나 받을 때 1% 당 게이지
  // 탱크
  // 패시브 덜 밀림: 받는 넉백(% 배율이 붙는 것: 마무리 타·공중 평타·스킬·아이템) × 이 값. 평타 중간 타의 고정 넉백은 그대로.
  // 2026-10-25 재혁 승인: '피해 % ×0.85' 대신 (딜이 낮은 대신 안정성). 0.85~0.92 사이에서 봇 판으로 맞춤.
  // (2026-10-24 예전 '넉백 ×0.85' 는 탱크 딜이 평타급일 때 봇 120판 51승 / 기대 30)
  TANK_KB_TAKEN: 0.92, // 0.88 → 0.92 (봇 320판 탱크 91승 / 기대 80)
  // (받은 피해 게이지 배율 TANK_ULT_TAKEN_MULT 는 없앰: ×2 → ×1.5 → 삭제. 2026-10-25 재혁 "R 이 5초마다 참". 탱크 패시브는 덜 밀림 하나)
  // 아머 (2026-10-25): F 돌진 중·R 떠오르는 동안. 넉백·경직만 막고 피해 % 는 받음. 마무리 타·필살기에 맞으면 깨지고 보통처럼 맞음.
  // 아머 중엔 카운터 안 당함 (카운터 규칙 예외). 경직 중엔 F·R 못 씀 (그대로) → 상대 공격 전에 켜야 함
  TANK_CHARGE_SPEED: 12, // F 방패 돌진: 이 속도(칸/초)로 TANK_CHARGE_MS 동안 앞으로 (약 3칸). 아머라 맞아도 안 멈춤, 처음 부딪힌 상대를 치고 멈춤
  TANK_CHARGE_MS: 250,
  TANK_CHARGE_HIT_RANGE: 0.9, // 몸 가운데끼리 이 거리 안이면 부딪힘
  TANK_CHARGE_KB_SPEED: 4.2,
  TANK_CHARGE_KB_UP: 3,
  TANK_CHARGE_STUN_MS: 600,
  TANK_CHARGE_DAMAGE: 15,
  TANK_SLAM_WINDUP_MS: 700, // 필살 내려찍기: 떠올랐다가 이 뒤에 쾅 (바닥에 범위 예고). 500 → 700 (2026-10-26 재혁: 광역 킬 1순위, 피하기 어려움)
  TANK_SLAM_JUMP: 6, // 떠오르는 속도
  TANK_SLAM_RANGE: 2.5, // 쾅 범위 (수평, 높이 차 2칸 안)
  TANK_SLAM_KB_SPEED: 4.5, // 옆으로는 조금, 위로 크게 띄움 → 공중 치명타 연계
  TANK_SLAM_KB_UP: 9,
  TANK_SLAM_STUN_MS: 900,
  // R 바깥 고리: 충격파(TANK_SLAM_RANGE) 바깥 TANK_RING_WIDTH 칸 고리의 바닥이 1층 솟아 위 사람을 띄움 → TANK_RING_MS 뒤 가라앉음 (남지 않음, 안 터짐, 압사 없음)
  TANK_RING_WIDTH: 1,
  TANK_RING_MS: 1000,
  TANK_RING_UP: 5, // 7 → 5 (2026-10-26 재혁, 예고 0.7초와 같이)
  TANK_RING_STUN_MS: 600,
  TANK_SLAM_DAMAGE: 15, // 2026-10-25 맵 7개 섞은 봇 504판 탱크 29% (킬 대부분 내려찍기) → 25 → 20, 넉백 5 → 4.5.
  // 탱크 개편 뒤 20 → 15 (재혁 결정 '나': 피해 15 / 고리 up 5 / 둘 다 실험 → 피해 15 가 가장 내려감, 고리 up 은 공중 마무리 연계를 위해 7 유지)
  // 닌자 (2026-10-25 재혁 확정, docs/characters.md 3.2 — 연계형 "이어지는 공격의 연속". 수치는 초안)
  // 갈아타기: 이어 치기 타 번호·창은 맞은 상대와 상관없이 닌자에게 남음 (모든 캐릭터 공통 구조). 맞는 쪽 COMBO_MS 는 그대로
  // 패시브: 이속 ×1.2 삭제 → 떨어지는 블록에 닿으면(밟거나 옆면) 공중 점프 회복 + 받는 넉백 × NINJA_KB_TAKEN
  NINJA_KB_TAKEN: 1.1, // 가벼워서 잘 밀림 (탱크 TANK_KB_TAKEN 반대). 피해 % 배율이 붙는 넉백에만
  NINJA_HIT_CD_CUT_MS: 500, // 적중 보상: 평타가 맞을 때마다 F 쿨 이만큼 줄어듦
  // 2026-10-25 재혁 결정: 3 → 4칸. 생존기·이동기 강화. 경직 중 사용(탈출기)은 안 넣음. 공중에서도 됨 (복귀)
  NINJA_BLINK_DIST: 4, // F 순간 베기: 보는 방향으로 (블록 앞까지) 이동하며 지나간 길의 상대를 벰 (한 번 쓸 때 한 사람 한 번). 상대를 만나면 그 바로 뒤(NINJA_BLINK_BEHIND)에서 멈춤
  NINJA_BLINK_BEHIND: 0.8,
  NINJA_SLASH_WIDTH: 0.8, // 지나간 선에서 이 거리 안이면 베임
  NINJA_SLASH_KB_SPEED: 2.5,
  NINJA_SLASH_KB_UP: 2,
  NINJA_SLASH_STUN_MS: 600,
  NINJA_SLASH_DAMAGE: 8, // 15 → 8 (2026-10-25: 한 방 약한 캐릭)
  // 블록에 막히면 벽 차기: 블록을 차고 위로 튀어 오름 + 작은 충격파 (피해 작게, 넉백만). 벽 통과는 없음
  NINJA_WALLKICK_UP: 8,
  NINJA_WALLKICK_RANGE: 1.5, // 닌자 둘레 이 거리 안 상대
  NINJA_WALLKICK_KB_SPEED: 4,
  NINJA_WALLKICK_KB_UP: 2,
  NINJA_WALLKICK_STUN_MS: 250,
  NINJA_WALLKICK_DAMAGE: 2,
  // R 강화 (그림자 일격 삭제): NINJA_EMPOWER_MS 동안 지상 1~3타와 공중 평타가 표창 2연발 (즉시 판정, 4타 올려 차기는 그대로)
  NINJA_EMPOWER_MS: 6000,
  NINJA_STAR: { windup: 60, gap: 80, range: 3, angle: 15, dmg: 2, stun: 250, kb: 0.6, up: 1 }, // 한 발. 2발 합쳐 딜 4 (근접 3 보다 조금 더), 경직은 근접보다 짧게. 마무리 타 자리면 둘째 발이 그 타의 마무리 넉백
  // 사냥꾼 (2026-10-26 재혁 확정, docs/characters.md 3.5 — "표식을 남기면 끝까지 사냥한다". 수치는 초안)
  // 표식: 상대에게 붙음 (사냥꾼마다 따로). 지상 평타 마무리 타(찔러 넣기)가 맞으면 +1, 최대 HUNTER_MARK_MAX, 마지막으로 쌓인 뒤 HUNTER_MARK_MS 면 사라짐
  HUNTER_MARK_MAX: 3,
  HUNTER_MARK_MS: 10000, // 2026-10-26 재혁 5 → 10초 (콤보를 다 못 맞히면 표식이 금방 사라져 R 을 못 씀)
  // F 추적 도약: HUNTER_LEAP_RANGE 안 표식 있는 가장 가까운 상대에게 (예고 HUNTER_LEAP_WINDUP_MS) 도약해 덮침, 없으면 보는 방향 HUNTER_LEAP_DIST 칸. 덮치면 이어 치기 창 → 평평평
  HUNTER_LEAP_RANGE: 6,
  HUNTER_LEAP_DIST: 3,
  HUNTER_LEAP_WINDUP_MS: 200,
  HUNTER_LEAP_MS: 300, // 도약에 걸리는 시간
  HUNTER_LEAP_UP: 6,
  HUNTER_LEAP_BEHIND: 0.8, // 덮칠 때 상대 앞 이 거리에 내림
  // 2026-10-26 재혁 결정 "다": 도약 중 착지 직전까지 표식 대상을 따라감 (유도). 틱마다 내릴 자리를 대상 쪽으로 HUNTER_LEAP_HOMING 비율만큼,
  // 처음 정한 자리에서 최대 HUNTER_LEAP_HOMING_MAX 칸까지. 남은 시간에 맞춰 속도를 다시 정함
  HUNTER_LEAP_HOMING: 0.8,
  HUNTER_LEAP_HOMING_MAX: 2,
  HUNTER_POUNCE_RANGE: 1.4, // 내렸을 때 이 거리 안이면 덮침 (피해 작게, 경직으로 평타 연결)
  HUNTER_POUNCE_DAMAGE: 4,
  HUNTER_POUNCE_STUN_MS: 500,
  // R 처형 사격: 보는 방향 HUNTER_SHOT_ANGLE_DEG(전체 각)·HUNTER_SHOT_RANGE 안 내 표식 대상 전부. HUNTER_SHOT_WINDUP_MS 조준 예고 뒤 즉시 판정.
  // 블록이 시선을 가리면 막힘 (격자 시선 검사). 표식 1개당 피해·넉백, 맞은 대상 표식 소모. 표식이 최대인 상대를 맞히면 게이지를 돌려받음
  HUNTER_SHOT_ANGLE_DEG: 90,
  HUNTER_SHOT_RANGE: 8,
  HUNTER_SHOT_WINDUP_MS: 500,
  HUNTER_SHOT_DAMAGE_PER_MARK: 8,
  HUNTER_SHOT_KB_BASE: 2,
  HUNTER_SHOT_KB_PER_MARK: 2.5, // 2026-10-26 재혁 ㄴ 1.5 → 2.5 (킬 낼 기술)
  HUNTER_SHOT_UP: 3,
  HUNTER_SHOT_STUN_MS: 700,
  HUNTER_ULT_MULT: 2, // R 게이지 필요량 × 이 값 (대가)
  // 대포수 (2026-10-26 재혁 확정, docs/characters.md 3.6 — "피하면서 공중 저격". 수치는 초안)
  // 장전: 최대 CANNON_AMMO_MAX 발, CANNON_RELOAD_MS 마다 한 발씩 (판 시작·부활 때 가득). F·R 은 탄 안 씀
  CANNON_AMMO_MAX: 3,
  CANNON_RELOAD_MS: 2500,
  // 포탄: 느리고 보이는 서버 투사체 (조준 방향 3D, 즉시 판정 아님). 맞으면 넉백 큼. 쌓인 블록에 맞으면 1칸 부숨 (바닥·시작 지형은 안 부숨). 쏘면 반동으로 뒤로
  CANNON_SHELL_SPEED: 12,
  CANNON_SHELL_RANGE: 12, // 이만큼 날아가면 사라짐
  CANNON_SHELL_RADIUS: 0.3,
  CANNON_SHELL_DAMAGE: 10,
  CANNON_SHELL_KB_SPEED: 6,
  CANNON_SHELL_KB_UP: 4,
  CANNON_SHELL_STUN_MS: 600,
  CANNON_RECOIL: 3, // 반동 (땅, 뒤로 수평 속도)
  CANNON_RECOIL_AIR: 5, // 반동 (공중, 매 발)
  // F 발밑 포격: 위로 크게 + 발밑 범위 넉백 (공중에서도)
  CANNON_JUMP_UP: 11,
  CANNON_FBLAST_RANGE: 1.8,
  CANNON_FBLAST_DAMAGE: 6,
  CANNON_FBLAST_KB_SPEED: 5,
  CANNON_FBLAST_KB_UP: 5,
  CANNON_FBLAST_STUN_MS: 600,
  // R 대형 포탄: 조준 방향 직선으로 관통하며 지나간 쌓인 블록 전부 부숨 (바닥·시작 지형은 안 부숨, 통과). 사람은 밀치고 계속 날아감, 끝(사거리·필드 밖·바닥)에서 폭발
  CANNON_R_SPEED: 20,
  CANNON_R_RANGE: 14,
  CANNON_R_RADIUS: 0.6,
  CANNON_R_DAMAGE: 10,
  CANNON_R_KB_SPEED: 5,
  CANNON_R_KB_UP: 3,
  CANNON_R_STUN_MS: 600,
  CANNON_R_BLAST_RANGE: 2.2,
  CANNON_R_BLAST_DAMAGE: 15,
  CANNON_R_BLAST_KB_SPEED: 7,
  CANNON_R_BLAST_KB_UP: 6,
  CANNON_R_BLAST_STUN_MS: 800,
  CANNON_R_RECOIL: 8,
  // 광전사 (2026-10-26 재혁 확정, docs/characters.md 3.7 — "밀릴수록 세진다". 수치는 초안)
  // 패시브 분노: 광전사가 주는 넉백(수평) × (1 + 자기 피해 % × BERSERKER_RAGE_PER_PERCENT), 상한 없음 (재혁).
  // 고정 넉백인 평타 중간 타(가로 베기)는 빼고 (세지면 2타가 안 닿음) — 마무리·공중 평타·F·R 에
  BERSERKER_RAGE_PER_PERCENT: 0.0025, // 2026-10-26 재혁 다 0.003 → 0.0025 (가·나 뒤에도 45%·소용돌이 필살기 킬 1위)
  // F 광폭 도약: 보는 방향으로 BERSERKER_LEAP_DIST 칸을 BERSERKER_LEAP_MS 동안 뛰고, 땅에 닿으면 착지 충격파 (낭떠러지 밖으로 뛰면 복귀기)
  BERSERKER_LEAP_DIST: 4,
  BERSERKER_LEAP_MS: 500,
  BERSERKER_LEAP_UP: 7,
  BERSERKER_LEAP_LAND_MS: 1500, // 도약 끝나고 이 안에 땅에 안 닿으면 충격파 없음
  BERSERKER_WAVE_RANGE: 1.5,
  BERSERKER_WAVE_DAMAGE: 6,
  BERSERKER_WAVE_KB_SPEED: 4,
  BERSERKER_WAVE_KB_UP: 4,
  BERSERKER_WAVE_STUN_MS: 600,
  // R 분노 소용돌이: BERSERKER_SPIN_MS 동안 회전 (이동 ×BERSERKER_SPIN_MOVE_MULT), BERSERKER_SPIN_TICK_MS 마다 닿는 상대를 작게 밀침 (빨아들이지 않음),
  // 끝날 때 한 번 크게 날림 (분노는 R 시작 때 깎은 뒤 피해 % 로 — 2026-10-26 재혁 가, 봇 504판 광전사 50%·소용돌이 필살기 킬 1위). 시작할 때 자기 피해 % 를 BERSERKER_RAGE_CUT 만큼 깎음 (0 아래로는 안 감)
  BERSERKER_SPIN_MS: 1500,
  BERSERKER_SPIN_MOVE_MULT: 0.3, // 2026-10-26 재혁 0.6 → 0.3 (사람 판에서 "개셈")
  BERSERKER_SPIN_RANGE: 1.6,
  BERSERKER_SPIN_TICK_MS: 250,
  BERSERKER_SPIN_TICK_DAMAGE: 2,
  BERSERKER_SPIN_TICK_KB: 1.2,
  BERSERKER_SPIN_TICK_UP: 1,
  BERSERKER_SPIN_TICK_STUN_MS: 400,
  BERSERKER_SPIN_END_RANGE: 2.0,
  BERSERKER_SPIN_END_DAMAGE: 10,
  BERSERKER_SPIN_END_KB_SPEED: 4, // 2026-10-26 재혁 나 5 → 4 (가 뒤에도 47%·소용돌이 필살기 킬 1위)
  BERSERKER_SPIN_END_KB_UP: 5,
  BERSERKER_SPIN_END_STUN_MS: 800,
  BERSERKER_RAGE_CUT: 20, // 2026-10-26 재혁 40 → 20
  // 바드 (2026-10-26 재혁 확정, docs/characters.md 3.8). 폼 form: 'bard'(음유시인, 판 시작·부활) / 'metal'. F = 폼 전환 (쿨 SKILL_CD_MS.bard), R = 지금 폼의 R
  BARD_FORM_NAMES: { bard: '음유시인', metal: '메탈' },
  BARD_METAL_ULT_NAME: '앰프 음파',
  // 류트 음파 (음유 평타): 보이는 느린 투사체, 사람에 닿으면 약한 넉백 + 둔화, 블록에 닿으면 사라짐
  BARD_NOTE_SPEED: 10,
  BARD_NOTE_RANGE: 6,
  BARD_NOTE_RADIUS: 0.35,
  // 둔화: 이동 속도 × (1 - BARD_SLOW), BARD_SLOW_MS (안 쌓이고 갱신만). 압사 원칙: 약하게
  BARD_SLOW: 0.2,
  BARD_SLOW_MS: 2000,
  // 음유 공중 평타 천천히 낙하: 중력 × BARD_GLIDE_GRAVITY, 떨어지는 속도 최대 BARD_GLIDE_FALL. 공중 평타 동작(준비+후딜) 동안만, 이어 치면 연장.
  // 땅에 닿거나 맞으면 바로 풀림 (2026-10-26 재혁: 3초 계속 이어지던 것 → 공격하는 동안만)
  BARD_GLIDE_GRAVITY: 0.25,
  BARD_GLIDE_FALL: 2,
  // 메탈 공중 평타 기타 꽂기 (2026-10-26 재혁 버그: 아래로 꽂으며 빠르게 낙하): 누르는 순간 낙하 속도 BARD_DIVE_SPEED 이상, 수평 이동 ×BARD_DIVE_MOVE_MULT.
  // 판정은 한 번: 내려가며 아래 상대에 닿으면 (수평 BARD_DIVE_HIT_R 안) 아래로 꽂음, 못 닿고 착지하면 발밑 BARD_DIVE_LAND_RANGE 충격 (위로 BARD_DIVE_LAND_UP).
  // 착지 전 1번. BARD_DIVE_MAX_MS 안에 안 닿으면 (낭떠러지) 판정 없이 끝
  BARD_DIVE_SPEED: 13,
  BARD_DIVE_MOVE_MULT: 0.3,
  BARD_DIVE_HIT_R: 0.9,
  BARD_DIVE_LAND_RANGE: 1.5,
  BARD_DIVE_LAND_UP: 3,
  BARD_DIVE_MAX_MS: 1500,
  BARD_GLIDE_MAX_PER_AIR: 3, // 2026-10-26 재혁: 착지 전 천천히 낙하는 이 횟수까지 (땅·블록·하늘 블록에 서면 다시). 0.4초마다 눌러 계속 떠 있는 "니가와" 막기
  // F 음유 → 메탈: 충격파 + 기타 리프 (주변 밀침)
  BARD_RIFF_RANGE: 1.8,
  BARD_RIFF_DAMAGE: 5,
  BARD_RIFF_KB_SPEED: 4,
  BARD_RIFF_KB_UP: 3,
  BARD_RIFF_STUN_MS: 500,
  // F 메탈 → 음유: 치유파, 나 (+ 팀전이면 BARD_HEAL_RANGE 안 팀원) 피해 % BARD_HEAL 깎음 (0 아래로 안 감)
  BARD_HEAL: 10,
  BARD_HEAL_RANGE: 4,
  // 음유 R 취약의 노래: 앞 BARD_SONG_ANGLE_DEG(전체 각)·BARD_SONG_RANGE 안 상대가 BARD_VULN_MS 동안 받는 넉백 ×BARD_VULN_MULT
  // (피해 % 배율 넉백에만 — 평타 중간 타 같은 고정 넉백은 그대로)
  BARD_SONG_ANGLE_DEG: 120,
  BARD_SONG_RANGE: 5,
  BARD_VULN_MS: 4000,
  BARD_VULN_MULT: 1.3,
  // 메탈 R 앰프 음파: BARD_AMP_MS 동안 앞 원뿔(BARD_AMP_ANGLE_DEG 전체 각, BARD_AMP_RANGE)에 BARD_AMP_TICK_MS 마다 작게 밀침, 끝에 크게.
  // 연주 중 이동 ×BARD_AMP_MOVE_MULT, 평타 안 나감. 맞아도 안 끊김 (넉백은 받고 경직 중에도 연주 계속 — 2026-10-26 재혁 가, 끊김 56~65% 라 약했음)
  BARD_AMP_MS: 3000,
  BARD_AMP_MOVE_MULT: 0, // 2026-10-26 재혁 0.5 → 0 (연주 중 제자리: 쫓아가며 싹쓸이 막기)
  BARD_AMP_LOCK_YAW: true, // 연주 방향도 시작 때 고정 (돌리면 제자리에서 원뿔로 주변을 쓸 수 있어서). false 면 보는 방향 따라감
  BARD_AMP_ANGLE_DEG: 70,
  BARD_AMP_RANGE: 4,
  BARD_AMP_TICK_MS: 300,
  BARD_AMP_TICK_DAMAGE: 2,
  BARD_AMP_TICK_KB: 1.5,
  BARD_AMP_TICK_UP: 1,
  BARD_AMP_TICK_STUN_MS: 450,
  BARD_AMP_END_DAMAGE: 10,
  BARD_AMP_END_KB_SPEED: 4, // 2026-10-26 재혁 5 → 4
  BARD_AMP_END_KB_UP: 4,
  BARD_AMP_END_STUN_MS: 800,
  // 건축가 (2026-10-25 재혁 확정, docs/characters.md 3.1 — 지형·설치형 "깔고, 쳐서 터뜨린다". 수치는 초안, 밸런스는 나머지 캐릭터 뒤)
  // 건축가 블록: 벽(지상 F)·3타 블록(평타 3타)·발판(공중 F)·대폭발(R). BUILDER_BLOCK_MS 뒤 사라짐.
  // 건축가 망치(평타)로 치면 폭발: 치는 방향 앞쪽 사람만 그쪽으로 날림, 건축가 자신은 안 맞음. 같은 F 벽 칸끼리만 연쇄. 상대는 못 터뜨림
  BUILDER_WALL_WIDTH: 3, // 지상 F 솟는 벽: 바로 앞 가로 3칸 × 1층. 예고 뒤 솟으며 그 칸 위 사람을 띄움
  BUILDER_WALL_HEIGHT: 1, // 2 → 1 (2026-10-25: 1층이라 점프로 넘음)
  BUILDER_WALL_WARN_MS: 400,
  BUILDER_WALL_KB_UP: 9,
  BUILDER_WALL_STUN_MS: 700,
  BUILDER_WALL_DAMAGE: 10,
  BUILDER_BLOCK_MS: 8000, // 건축가 블록 수명
  BUILDER_THIRD_MAX: 3, // 3타 블록 동시 최대 (넘으면 제일 오래된 것부터 사라짐)
  BUILDER_PAD_HEIGHT: 2, // 공중 F: 발밑에 세우는 기둥 칸 수 (2026-10-30 재혁: 1칸 발판 + 부스트 → 2칸 기둥 위에 섬. 봇 밸런스는 나중)
  BUILDER_PAD_BOOST: 8, // 공중 F 에 기둥을 한 칸도 못 세울 때(필드 밖·바로 밑이 막힘) 위로 부스트 속도 (복귀기, 3타 띄움과 같은 세기, 약 1.6칸)
  BUILDER_BLAST_RANGE: 1, // 블록 폭발: 터지는 칸 가장자리에서 이 거리(칸) 안
  BUILDER_BLAST_HEIGHT: 1.5, // 블록 폭발이 닿는 높이 차
  BUILDER_BLAST_DAMAGE: 8, // 가까이 터진 칸 1칸당 피해 %
  BUILDER_BLAST_KB_SPEED: 6, // 넉백 중간 (밀치기 4.2 ~ 충격파 8.4 사이)
  BUILDER_BLAST_KB_UP: 4,
  BUILDER_BLAST_STUN_MS: 800,
  BUILDER_BLAST_ULT: 5, // 패시브: 내 블록이 1칸 터질 때마다 필살기 게이지 (대폭발 블록은 안 셈). 설치 블록 +1 패시브 대신
  // R 대폭발: 앞 BUILDER_BIG_GAP 칸 띄우고 SIZE×SIZE 가 바닥에서 솟음 (위 사람 띄움) → FUSE 뒤 자동 폭발, 망치로 치면 바로.
  // 범위 안 내 블록도 같이 터짐. 블록 비(위에서 떨어뜨림)는 버림 — 킬 80% 가 조준 압사
  BUILDER_BIG_SIZE: 3,
  BUILDER_BIG_GAP: 1,
  BUILDER_BIG_FUSE_MS: 800,
  BUILDER_BIG_RISE_UP: 6, // 솟을 때 위 사람 띄우는 속도
  BUILDER_BIG_RISE_STUN_MS: 0, // 띄우기만 (경직 없음) → 0.8초 안에 벗어날 수 있음 (문서 대응법). 경직을 주면 콤보 끝 무적이 폭발과 겹쳐 안 맞기도 함
  BUILDER_BIG_RANGE: 1, // 대폭발이 닿는 거리 (칸 가장자리에서)
  BUILDER_BIG_DAMAGE: 25,
  BUILDER_BIG_KB_SPEED: 7,
  BUILDER_BIG_KB_UP: 6,
  BUILDER_BIG_STUN_MS: 900,
  BUILDER_BLAST_HOLE: false, // 테스트 옵션: 터진 칸 아래 바닥 1칸을 BUILDER_HOLE_MS 동안 구멍으로 (사람 테스트로 비교)
  BUILDER_HOLE_MS: 8000,
  // 갈고리 (연계: 평타로 밀고 → 갈고리로 다시 당겨 → 평타)
  // 장전 (플린트록): F 갈고리로 상대를 끌어오면 장전 (시간으로는 안 참), 판 시작·부활 때 장전. 평타 3타가 탕이면 빈 총
  HOOK_RANGE: 5, // F 갈고리: 보는 방향 이 거리 안에서 상대·블록 중 먼저 닿는 것. 판정은 HOOK_FLY_MS 뒤 (갈고리가 닿는 순간)
  HOOK_HALF_ANGLE_DEG: 15, // 상대에 닿는 시야 반각
  HOOK_PULL_TO: 1, // 상대를 끌어와서 내 앞 이 거리에 놓음
  HOOK_STUN_MS: 600,
  HOOK_DAMAGE: 10,
  HOOK_ZIP_SPEED: 16, // 블록에 걸리면 내가 그쪽으로 이 속도(칸/초)로 끌려감 (이동·복귀, 공중 가능)
  HOOK_ZIP_UP: 5, // 끌려갈 때 살짝 위로 (블록 위로 올라서기 쉽게)
  HOOK_RAY_HEIGHT: 1, // 블록을 찾는 갈고리 높이 (발에서)
  // R 블록 내려찍기 (회오리 삭제): 보는 방향 HOOK_RANGE 안 첫 블록의 덩어리를 뽑아 (2026-10-26 재혁: 테트로미노 통째로 — 떨어지는·하늘 블록은 그 블록, 쌓인 블록은 같은 블록 id 로 이어진 칸, 지형·건축가·박힌 칸은 1칸. 조종 중인 블록은 안 잡음) (HOOK_GRAB_MS) → 앞 직선 HOOK_SLAM_LEN 칸에 수직으로 내려찍음 (넉백 + 띄움)
  // → 끝 칸 기둥 꼭대기에 박혀 지형으로 남음 (그 칸 사람은 압사 대신 밀쳐냄, 필드 밖이면 사라짐). 바닥은 못 뽑음, 블록이 없으면 안 쓰임. 건축가 블록은 속성 그대로
  HOOK_GRAB_MS: 400, // 2026-10-26 재혁 300 → 400 (덩어리 통째로 드는 예고, 피할 틈)
  HOOK_GRAB_CONE_DEG: 25, // R 보조 판정: 조준 직선이 블록을 놓치면 이 반각 원뿔 안 가장 가까운 블록 (한 번 누르면 나가게)
  HOOK_SLAM_LEN: 5,
  HOOK_SLAM_WIDTH: 1.2, // 직선에서 이 거리 안이면 맞음. 2026-10-26 재혁 0.8 → 1.2 (덩어리 폭)
  HOOK_SLAM_DAMAGE: 14, // 2026-10-26 재혁 12 → 14
  HOOK_SLAM_KB_SPEED: 5,
  HOOK_SLAM_KB_UP: 7,
  HOOK_SLAM_STUN_MS: 800,

  // ---- 판 ----
  PASS_CRUSH_SHARE: 0.5, // 1단계 합격선: 누적 사망 중 압사 비율. 판 종료 로그에 표시. 2026-10-20 재정의
  ROUND_TIME_LIMIT_MS: 0, // 0 = 제한 없음. 양수면 시간 초과 시 무승부

  // ---- 유령 투하 (2026-10-26 재혁: 먼저 죽은 사람이 판 끝까지 구경만 함 → 하늘에서 1칸 블록을 떨어뜨림) ----
  // 생존 모드(팀전 포함)만. 죽자마자 1개, 그 뒤 GHOST_DROP_CD_MS 마다. 보내는 칸의 기둥 꼭대기 + GHOST_DROP_UP 에서 생겨 그 판 보통 블록 속도로 떨어짐
  GHOST_DROP_ENABLED: true,
  GHOST_DROP_CD_MS: 6000,
  GHOST_DROP_UP: 5, // 기둥 꼭대기 위 이 칸에서 생김 (보통 블록처럼 그림자 예고 시간이 생기게)
  GHOST_DROP_UP_SKY: 2, // 하늘 계단 켬 판은 블록이 2.5초에 한 칸이라 (5칸이면 12.5초) 이만큼만 → 5초
  GHOST_DROP_BOTS: false, // 죽은 봇도 떨어뜨릴지 (봇 판 비교용, 기본 끔)

  // ---- 연습 모드 (2026-10-26 재혁: 혼자 쓰는 방, 판이 안 끝남, 허수아비) ----
  PRACTICE_DUMMY_MAX: 3, // 허수아비 최대 (사람 + 허수아비 ≤ MAX_PLAYERS 자리)
  PRACTICE_DUMMY_DIST: 2, // 허수아비를 내 앞 이 거리(칸)에 놓음
  PRACTICE_DAMAGE_MAX: 999, // 피해 % 설정 상한 (허수아비·내 피해 %)
  PRACTICE_RESPAWN_MS: 1500, // "안 죽음" 을 끄고 죽으면 이만큼 뒤 처음 자리에서

  // ---- 게임 모드 (2026-10-23 재혁: 호스트가 대기 화면에서 고름) ----
  // survival = 마지막 생존자 (예전 그대로), master = 블록 마스터 (1 대 다), kills = 부활 킬 점수전
  MODE_DEFAULT: 'survival',
  MODE_NAMES: { survival: '생존', master: '블록 마스터', kills: '킬 점수전' }, // 로그·화면 이름 (npm run stats 가 읽음)
  // 블록 마스터: 한 명이 하늘에서 블록만 조종 (자동 블록·조종권 없음), 나머지는 각자 도생으로 버팀.
  // 생존자가 다 깔리면 마스터 승, 시간이 지나면 살아남은 생존자 모두 승. 마스터는 판마다 자리 순서로 돌아감
  MASTER_TIME_MS: 60000,
  MASTER_NEXT_PIECE_MS: 400, // 마스터가 블록을 떨어뜨린 뒤 다음 블록이 하늘에 생기기까지
  // 2026-10-23 첫 인터넷 플레이 뒤 재혁: "블록이 한 곳에 겹쳐서 사람들이 타고 못 올라감", "죽고 기다림" →
  // 죽은 생존자는 마스터 편 (하늘에서 자기 블록), 마스터 편 블록은 무작위 자리에서 시작하고 주변보다 너무 높게는 못 놓음
  MASTER_MAX_RISE: 3, // 마스터 편 블록이 놓인 뒤 높이가 바로 둘레(8방향) 가장 높은 기둥보다 이만큼 넘게 높으면 못 놓음 (탑 방지)
  // 킬 점수전: 죽어도 부활, 킬 +1 · 자멸(킬 없이 죽음) -1. 시간이 끝나거나 누가 목표 킬에 닿으면 끝
  KILLS_TIME_MS: 180000,
  KILLS_TARGET: 7, // 개인전 목표 킬
  KILLS_TARGET_TEAM: 6, // 팀전 목표 (팀 합계). 2026-10-23 재혁 10 → 6 (첫 플레이 3분 동안 1 : 3)
  KILLS_RESPAWN_MS: 5000, // 죽고 나서 부활까지 (그동안 관전)
  KILLS_SHIELD_MS: 2000, // 부활 직후 무적: 안 밀리고 안 깔림 (떨어지면 죽음)
  KILLS_SINK_HEIGHT: 9, // 킬 점수전은 용암이 없음. 가장 높은 기둥이 이 높이에 닿으면 맨 아래 층을 지워 전체를 한 칸 내림
  // 가장자리에서 2.5칸 안쪽 = 칸 중심 (밀치기 한 방 약 1.5칸이라 시작하자마자 한 방에 안 떨어진다)
  SPAWN_POINTS: spawnPoints(GRID_W, GRID_D, 2.5),
  SPAWN_INSET: 2.5,
  spawnPointsFor: (W, D) => spawnPoints(W, D, 2.5), // 판 크기별 시작 위치

  // ---- AI 봇 (서버에서 돎, 사람과 같은 입력만 씀) ----
  BOT_THINK_MS: 100, // 판단 주기
  BOT_AIR_JUMP_VZ: 2, // 봇은 위로 가는 속도가 이보다 느려지면 (꼭대기 근처) 2단 점프
  BOT_EDGE_MARGIN: 1.2, // 봇이 상대 뒤를 잡으러 갈 때 서는 자리는 필드 끝에서 이만큼 안 (예전 0.45)
  BOT_KITE_ARC_DEG: 90, // kite: 상대 둘레 원에서 지금 방향 ±이 각도 안의 자리를 봄
  BOT_RECOVER_INSET: 1.2, // 복귀할 때 필드 끝에서 이만큼 안쪽 점을 노림
  BOT_RECOVER_DASH_OUT: 1, // 밖으로 향하는 넉백 속도(칸/초)가 이보다 빠르면 공중 대시로 끊음
  BOT_RECOVER_LOW_Z: 1, // 복귀 중 발이 이보다 낮으면 2단 점프를 미루지 않고 바로 (필드 바닥보다 낮게 돌아오면 옆면에 막힘)
  BOT_REACTION_MS: 450, // 그림자가 보이고 나서 피하기 시작할 때까지 (사람 반응 흉내). 상대 예고 피하기·봇 탱크 아머 반응도 같은 지연
  // 상대 예고 피하기 (2026-10-26 재혁: 봇은 예고를 안 보고 다 맞았음 → 봇 판이 사람 판과 달랐음). 지상 F 준비·탱크 R·평타 마무리 준비·사냥꾼 도약/조준·
  // 광전사 회전·바드 앰프가 나를 노리면 BOT_REACTION_MS 뒤에 옆(범위 공격이면 바깥)으로 피함. 예고마다 한 번 BOT_DODGE_CHANCE 확률로 피할지 정함 (난이도 배수, 최대 BOT_DODGE_CHANCE_MAX)
  BOT_DODGE_CHANCE: 0.6,
  BOT_DODGE_CHANCE_MAX: 0.9,
  BOT_DODGE_STEP: 2, // 피할 때 옆으로 가는 거리 (칸)
  BOT_DODGE_DASH_MS: 300, // 남은 시간이 이보다 짧으면 대시로 피함 (대시가 있으면)
  BOT_AIM_ERROR_RAD: 0.3, // 투사체 조준 오차 (라디안, ± 이 안에서 무작위)
  BOT_SHELL_AIM_ERROR_RAD: 0.3, // 대포수 포탄·대형 포탄 조준 오차 (좌우·위아래 각각 ±, 쏠 때마다 새로). 2026-10-26 총괄 승인: 오차 0 명중 77%·승률 58% → 0.15 명중 73%·44% → 0.3 명중 61%·40% (투사체 BOT_AIM_ERROR_RAD 와 같게)
  BOT_DROP_DELAY_MS: 250, // 조종 중 상대 위에 맞춘 뒤 떨어뜨리기까지
  BOT_TARGET_JITTER: 1, // 상대 고를 때 판마다 상대별로 0~이 값(칸)을 거리에 더함. 동점일 때 늘 같은 상대(사람)만 노리지 않게
  BOT_SKILL_INTERVAL_MS: 300, // 봇이 캐릭터 스킬·필살기를 쓴 뒤 다음 것을 써 보기까지 (×0.7~1.3 무작위). 2026-10-26 재혁 봇 지능: 2000 → 300 (2초에 한 번만 따져서 띄운 뒤 F·덮침 같은 이어 가기를 놓쳤음)
  BOT_CHAIN_DELAY_MS: 80, // 캐릭터 평타 이어 치기: 다음 타를 누를 수 있게 된 뒤 봇이 누르기까지 (×0.7~1.3 무작위)
  BOT_PUSH_INTERVAL_MS: 1500, // 봇이 밀치기 사이에 두는 간격 (×0.7~1.3 무작위). 낮을수록 공격적
  BOT_BRICK_AIM_ERROR: 1.2, // 설치 블록 던질 때 조준점을 상대 발밑에서 이 반경(칸) 안 무작위로 빗나감 (없으면 거의 다 맞힘)
  BOT_BOMB_DANGER_PAD: 0.5, // 봇이 피하는 폭탄 범위 = BOMB_BLAST_RANGE + 이만큼 (칸 중심 거리 기준이라 여유)
  BOT_BRICK_STEP_PITCH: -1.3, // 발판 던질 때 시선 각도: 거의 발밑을 보면 BRICK_MIN_DIST 앞 칸에 바로 닿음
  BOT_LAVA_MARGIN: 1.5, // 용암이 켜지면 표면에서 이 높이(칸) 안의 낮은 칸으로는 내려가지 않음 (1.5칸 = 24초)
  BOT_CONTROL_AIM_ERROR: 1, // 조종 블록 겨냥이 빗나가는 반경(칸) 기준. 아래 난이도 배수를 곱함 (보통·어려움 0 = 정확히 겨냥)
  // 봇 난이도 (호스트가 대기 화면에서 고름, 모든 봇에 같이). 위 BOT_* 값에 곱하는 배수. 보통 = 위 값 그대로 (조종 겨냥 오차만 0)
  BOT_LEVELS: {
    easy: { DODGE_CHANCE: 0.25, CHAIN_DELAY_MS: 2.5, REACTION_MS: 1.7, AIM_ERROR_RAD: 2, SHELL_AIM_ERROR_RAD: 2, DROP_DELAY_MS: 3, PUSH_INTERVAL_MS: 1.8, BRICK_AIM_ERROR: 1.6, CONTROL_AIM_ERROR: 1.5 },
    normal: { CONTROL_AIM_ERROR: 0 },
    hard: { DODGE_CHANCE: 1.4, CHAIN_DELAY_MS: 0.5, REACTION_MS: 0.6, AIM_ERROR_RAD: 0.5, SHELL_AIM_ERROR_RAD: 0.5, DROP_DELAY_MS: 0.6, PUSH_INTERVAL_MS: 0.65, BRICK_AIM_ERROR: 0.6, CONTROL_AIM_ERROR: 0 },
  },
  BOT_LEVEL_DEFAULT: 'normal',

  // ---- 타격감 (클라이언트, 2단계) ----
  SFX_VOLUME: 0.5, // 전체 효과음 크기 0~1
  MUSIC_VOLUME: 0.07, // 배경음악 크기 (효과음보다 작게)
  SFX_HEAR_RANGE: 14, // 이 거리(칸) 밖 소리는 작게 (최소 20%)
  // ---- 소리 개편 (2026-10-27, client/sound.js · music.js). 효과음 = 몸에 닿는 소리는 Kenney CC0 파일 + UI·이어지는 소리는 합성 ----
  SFX_DIR: '/assets/sfx/', // 효과음 파일 폴더 (client/assets/sfx, 출처 CREDITS.md)
  // 소리 묶음: 이름 → 파일(확장자 .ogg 빼고) 여러 개 중 하나를 골라 틀고 높낮이를 SFX_DETUNE 만큼 흔듦 (반복 피로), gain = 묶음 크기
  SFX_BANKS: {
    // 타격 (2026-10-28 다시, OpenGameArt CC0 를 tools/prep-sfx.mjs 로 역할별 다듬음): 크랙 '팍' + 펀치 '퍽' + 강타 몸통 '콰앙' + 치명타 쨍
    hitHeavy: { files: ['hitHeavy_1', 'hitHeavy_2', 'hitHeavy_3', 'hitHeavy_4'], gain: 0.8 },
    hitRing: { files: ['hitRing_1'], gain: 0.45 },
    // 휘두름: 칼 '슉' (높고 짧게) · 보통 '휙' · 무거운 '훙'
    swishBlade: { files: ['swishBlade_1', 'swishBlade_2', 'swishBlade_3'], gain: 0.55 },
    swishMid: { files: ['swishMid_1', 'swishMid_2', 'swishMid_3', 'swishMid_4'], gain: 0.7 },
    swishHeavy: { files: ['swishHeavy_1', 'swishHeavy_2', 'swishHeavy_3'], gain: 0.8 },
    punchM: { files: ['impactPunch_medium_000', 'impactPunch_medium_001', 'impactPunch_medium_002', 'impactPunch_medium_003', 'impactPunch_medium_004'], gain: 0.8 }, // 맞음 '퍽' (1·2타)
    punchH: { files: ['impactPunch_heavy_000', 'impactPunch_heavy_001', 'impactPunch_heavy_002', 'impactPunch_heavy_003', 'impactPunch_heavy_004'], gain: 0.9 }, // 3타·강타·치명·내가 맞음 '퍽!'
    plateH: { files: ['impactPlate_heavy_000', 'impactPlate_heavy_001', 'impactPlate_heavy_002', 'impactPlate_heavy_003', 'impactPlate_heavy_004'], gain: 0.55 }, // 방패·금속판 (탱크)
    woodH: { files: ['impactWood_heavy_000', 'impactWood_heavy_001', 'impactWood_heavy_002', 'impactWood_heavy_003', 'impactWood_heavy_004'], gain: 0.8 }, // 블록 착지·망치
    woodL: { files: ['impactWood_light_000', 'impactWood_light_001', 'impactWood_light_002'], gain: 0.6 }, // 화살 박힘·작은 나무
    mining: { files: ['impactMining_000', 'impactMining_001', 'impactMining_002'], gain: 0.7 }, // 돌 깨짐 (블록 부숨·솟는 땅)
    bell: { files: ['impactBell_heavy_002', 'impactBell_heavy_003'], gain: 0.45 }, // 치명타 딩
    tapL: { files: ['impactGeneric_light_000', 'impactGeneric_light_001', 'impactGeneric_light_002'], gain: 0.6 }, // 작은 탁
    softH: { files: ['impactSoft_heavy_000', 'impactSoft_heavy_001', 'impactSoft_heavy_002'], gain: 1 }, // 몸이 깔림·쓰러짐
    metalM: { files: ['impactMetal_medium_000', 'impactMetal_medium_001', 'impactMetal_medium_003'], gain: 0.55 }, // 갈고리·아머 쨍
    metalL: { files: ['impactMetal_light_001', 'impactMetal_light_004'], gain: 0.5 }, // 가벼운 금속
    glassH: { files: ['impactGlass_heavy_000', 'impactGlass_heavy_002'], gain: 0.35 }, // 수정·와장창 높은 겹
    chop: { files: ['chop'], gain: 0.75 }, // 도끼 (광전사)
    slice: { files: ['knifeSlice', 'knifeSlice2'], gain: 0.55 }, // 단검 베기 (닌자)
    cloth: { files: ['cloth1', 'cloth2', 'cloth3'], gain: 1.1 }, // 휘두름·뛰기 옷 펄럭
    latch: { files: ['metalLatch', 'metalClick'], gain: 0.5 }, // 장전·갈고리 걸림
    boom: { files: ['explosionCrunch_000', 'explosionCrunch_001', 'explosionCrunch_002'], gain: 0.7 }, // 폭발
    boomLow: { files: ['lowFrequency_explosion_001'], gain: 0.9 }, // 폭발 낮은 겹·우르릉
    slime: { files: ['slime_000'], gain: 0.6 }, // 녹음·늪 빠짐
    pluck: { files: ['pluck_001', 'pluck_002'], gain: 0.5 }, // 석궁 줄 (사냥꾼)
    confirm: { files: ['confirmation_001'], gain: 0.4 }, // 아이템 먹음
    jingleWin: { files: ['jingles_STEEL02'], gain: 0.55 }, // 판 끝 승리 (올라가는 스틸드럼)
    jingleLose: { files: ['jingles_STEEL05'], gain: 0.45 }, // 내가 죽음 (내려가는 스틸드럼)
  },
  // 캐릭터별 무기 소리: swing = 휘두를 때 묶음 (rate = 높낮이 배율, 낮을수록 무거움), hit = 때려서 맞을 때 덧씌우는 묶음 ('strum' 은 합성 기타)
  // swing = 휘두름 묶음 (swishBlade·swishMid·swishHeavy), rate = 높낮이 (무기가 클수록 낮게), hit = 공통 타격 위에 얇게 얹는 무기 겹
  SFX_WEAPONS: {
    tank: { swing: 'swishHeavy', rate: 0.85, hit: 'plateH' }, // 방패·주먹
    ninja: { swing: 'swishBlade', rate: 1.15, hit: 'slice' }, // 단검
    builder: { swing: 'swishHeavy', rate: 0.75, hit: 'woodH' }, // 망치
    hook: { swing: 'swishMid', rate: 1, hit: 'metalM' }, // 갈고리·권총
    hunter: { swing: 'swishMid', rate: 1.12, hit: 'woodL', shot: 'pluck' }, // 석궁
    cannon: { swing: 'swishHeavy', rate: 0.9, hit: 'hitHeavy' }, // 대포
    berserker: { swing: 'swishHeavy', rate: 0.68, hit: 'chop' }, // 도끼
    bard: { swing: 'swishMid', rate: 0.95, hit: 'strum' }, // 기타·류트
  },
  SFX_SWING: { rate: 1.22, cut: 0.15 }, // 휘두름 전체: 무기 rate 에 곱하는 높낮이 (높게) · 이 길이(초)에서 끊음 (짧게)
  SFX_SWING_AIR: 0.35, // 보통·무거운 휘두름 위에 얹는 칼 '슉' 크기 (바람 가르는 고역, 높낮이는 rate × 0.7)
  // 맞음 '퍽' (2026-10-28 재혁 '퍽퍽퍽 그 타격감': 17bb4e8 의 Kenney impactPunch 그대로 + 콤보가 이어질수록 점점 묵직하게)
  // bank·vol·rate = '퍽' 묶음·크기·높낮이 (낮을수록 묵직), body = 몸통 저음 (SFX_HIT_BODY) 크기, weapon = 때린 무기 겹 크기
  SFX_HIT_COMBO: [ // 약·중타: 콤보 순번 (hitStep: 평타 n, 없으면 streak) 1타 < 2타 < 3타 (그 뒤는 3타)
    { bank: 'punchM', vol: 0.75, rate: 1.05, body: 0, weapon: 0.6 },
    { bank: 'punchM', vol: 0.95, rate: 0.95, body: 0.25, weapon: 0.7 },
    { bank: 'punchH', vol: 1, rate: 0.88, body: 0.45, weapon: 0.8 },
  ],
  SFX_HIT_LIGHT: 0.75, // 약타 (표창·투사체 등 SFX_LIGHT_KINDS) 크기 배율
  SFX_HIT_BODY: { freq: 140, freqEnd: 45, dur: 0.16, type: 'sine' }, // 몸통 저음 (합성)
  SFX_HIT_TICK: { freq: 1100, freqEnd: 300, dur: 0.04, vol: 0.15 }, // 맞는 순간 짧은 '딱' (합성, 17bb4e8 그대로)
  // 강타 (콤보 마무리·묵직한 스킬) · 치명: 더 낮은 '퍽!' + 강타 몸통 (hitHeavy) '콰앙', release = 히트스톱이 풀리는 순간(ms) 날아가는 쾅, ring = 치명 쨍
  SFX_HIT_TIERS: {
    heavy: { bank: 'punchH', vol: 1, rate: 0.8, body: 0.6, heavy: 0.8, weapon: 0.85, release: 110 },
    crit: { bank: 'punchH', vol: 1, rate: 0.75, body: 0.7, heavy: 1, ring: 1, weapon: 0.85, release: 180 },
  },
  SFX_HIT_RELEASE: 0.3, // 강타·치명 '날아감' 겹 크기 (맞는 순간 '팍'보다 작게: 최고점이 맞는 순간에 오게)
  SFX_HEAVY_KINDS: ['blast', 'bigbomb', 'bigshell', 'blockslam', 'slam', 'charge', 'execute', 'spinend', 'leapwave', 'pounce', 'riff', 'ampend', 'wall', 'bomb'], // 이 kind 로 맞으면 강타
  SFX_LIGHT_KINDS: ['projectile', 'note', 'glide', 'spin', 'amp', 'shock'], // 약타 (연속으로 자주 맞는 것·투사체)
  // KO 연출 소리 (ko.on 'smash'·'final'·'crush'). 화면 시간이 느려지면 (슬로모션) 효과음은 먹먹하고 낮게, 음악은 잠깐 줄임
  SFX_KO: {
    slowAbove: 0.15, // 화면 시간 배율이 이보다 크고 1 보다 작으면 슬로모션으로 봄 (이하 = 압사 히트스톱처럼 아주 짧은 멈춤 → 소리는 그대로)
    slowRate: 0.7, // 슬로모션 동안 새로 나는 효과음 높낮이 (빠르기) 배율
    slowLowpass: 1300, // 슬로모션 동안 효과음 전체를 이 높이(Hz) 위로 깎음 (먹먹하게)
    slowGain: 0.75, // 슬로모션 동안 효과음 크기
    ease: 0.08, // 먹먹해지고 풀리는 시간 (초)
    musicDuck: 0.3, // 마지막 킬 슬로모션 동안 음악 크기 배율
    crushTail: 0.12, // 압사 KO: 큰 쿵 뒤 부스러기가 이만큼 뒤에 (화면 히트스톱 KO_CRUSH_STOP_MS 와 맞춤)
  },
  SFX_PAN: 0.75, // 남 소리를 왼쪽·오른쪽으로 벌리는 정도 (0 가운데 ~ 1 한쪽 끝)
  SFX_STRUM: [52, 59, 64, 67], // 바드 타격 기타 화음 (MIDI, 메탈 폼은 낮게 + 찌그러뜨림)
  // 위험 액체 지속 소리 (용암·물·늪·에너지·폭풍 = WORLD_THEMES hazard.style). 거리 = 내 귀(카메라)에서 표면까지 높이
  SFX_HAZARD: {
    range: 9, // 이 높이(칸) 위면 아주 작게
    min: 0.12, // 멀어도 남는 크기 비율
    fade: 0.4, // 크기가 바뀌는 시간 (초)
    vol: { water: 0.5, lava: 0.45, swamp: 0.38, energy: 0.34, storm: 0.4 },
    pops: { water: 1.2, lava: 3.5, swamp: 5, energy: 0.4, storm: 0.13 }, // 초당 튀는 소리 (출렁·뽀글·지직·천둥)
    fallback: 'lava', // 테마가 없는 맵 (예전 노을)
  },
  // ---- 배경음악 (합성, 테마별). 음 = MIDI, scale = 으뜸음에서 반음 간격, prog = 마디마다 화음 (음계 몇 번째 음 위의 3화음) ----
  // lead·bass = 악기 (music.js INSTRUMENTS), drums = 장단 (DRUMS), arp = 화음 쪼개는 모양, motif = 마디마다 멜로디 쓸 확률
  MUSIC_THEMES: {
    lobby: { bpm: 92, root: 57, scale: [0, 2, 4, 5, 7, 9, 11], prog: [5, 3, 0, 4], lead: 'bell', bass: 'sine', drums: 'none', arp: 'pad', motif: 0.3 }, // 대기실: 느긋한 벨 + 화음
    meadow: { bpm: 128, root: 60, scale: [0, 2, 4, 5, 7, 9, 11], prog: [0, 4, 5, 3], lead: 'pluck', bass: 'triangle', drums: 'pop', arp: 'up', motif: 0.6 }, // 초원: 밝은 장조
    desert: { bpm: 112, root: 62, scale: [0, 1, 4, 5, 7, 8, 10], prog: [0, 1, 0, 6], lead: 'reed', bass: 'triangle', drums: 'tamb', arp: 'updown', motif: 0.7 }, // 사막: 프리지안 도미넌트 + 탬버린
    crystal: { bpm: 96, root: 64, scale: [0, 2, 4, 6, 7, 9, 11], prog: [0, 1, 5, 4], lead: 'bell', bass: 'sine', drums: 'sparse', arp: 'pad', motif: 0.5, echo: 0.42 }, // 수정 동굴: 리디안 벨 + 메아리
    volcano: { bpm: 150, root: 52, scale: [0, 2, 3, 5, 7, 8, 11], prog: [0, 5, 6, 4], lead: 'saw', bass: 'saw', drums: 'heavy', arp: 'down', motif: 0.5 }, // 화산: 화성 단조 + 무거운 북
    skycastle: { bpm: 120, root: 65, scale: [0, 2, 4, 6, 7, 9, 11], prog: [0, 3, 4, 0], lead: 'triangle', bass: 'sine', drums: 'pop', arp: 'pad', motif: 0.6, echo: 0.3 }, // 하늘 성: 리디안 패드
    mushroom: { bpm: 132, root: 67, scale: [0, 2, 4, 7, 9], prog: [0, 3, 4, 2], lead: 'marimba', bass: 'triangle', drums: 'wood', arp: 'bounce', motif: 0.7 }, // 버섯 숲: 오음 마림바, 통통
    castle: { bpm: 110, root: 62, scale: [0, 2, 3, 5, 7, 9, 10], prog: [0, 6, 3, 4], lead: 'lute', bass: 'triangle', drums: 'march', arp: 'up', motif: 0.6 }, // 중세 성: 도리안 류트 + 행진 북
  },
  MUSIC_MIX: { drums: 0.5, lead: 1.5, bass: 1 }, // 음악 안의 크기 비율 (북이 멜로디를 덮지 않게)
  MUSIC_THEME_DEFAULT: 'volcano', // 테마가 없는 맵 (예전 노을: 용암)
  // 위험이 차오를 때 긴장 버전: 빠르기 배율, 음계를 단조로 (3·6·7 음 반음 내림), 드럼 두 배, 리드 한 옥타브 위
  MUSIC_TENSION: { bpm: 1.22, minor: true, drums: 'heavy', leadUp: 12 },
  FX_SHAKE_HURT: 0.18, // 맞았을 때 화면 흔들림 세기 (칸)
  FX_SHAKE_HIT: 0.05, // 때렸을 때
  FX_SHAKE_MS: 280,
  FX_SQUASH_MS: 320, // 맞은 캐릭터 찌그러졌다 펴지는 시간
  FX_PARTICLES: 14, // 명중 파편 개수

  // ---- 클라이언트 ----
  MOUSE_SENSITIVITY: 0.0022,
  FOV_DEFAULT: 75, // 1인칭 시야각 기본 (설정에서 60~100)
  SKY_CAMERA_HEIGHT: GRID_H + 14, // 하늘 시점 카메라 높이 (필드 중심 위)
  SKY_TRANSITION_MS: 700, // 1인칭 ↔ 하늘 시점 전환 애니메이션 길이
  // 3인칭 (V 로 1인칭과 바꿈, 폴가이즈처럼 내 캐릭터 뒤·위에서 봄). 이동·조준은 1인칭과 같은 yaw·pitch
  TP_DIST: 3.8, // 캐릭터에서 카메라까지 거리 (칸)
  TP_PIVOT_UP: 1.7, // 발 위로 이 높이의 점을 중심으로 돎 (머리 조금 위 → 내 캐릭터가 화면 가운데 아래)
  TP_TILT: 0.3, // 시선보다 이만큼(라디안) 더 위에서 내려다봄 (앞을 볼 때도 카메라가 머리 위)
  TP_SIDE: 0.4, // 카메라·시선을 오른쪽으로 이만큼 비킴 (칸). 바로 앞 상대가 내 몸에 가리지 않게 (어깨 너머)
  TP_LOOK_AHEAD: 2, // 중심에서 시선 방향으로 이만큼 앞을 바라봄 (화면 가운데 ≈ 조준 방향)
  TP_CAM_MARGIN: 0.3, // 블록이 가리면 막힌 칸에서 이만큼 앞에 카메라
  TP_EASE_OUT: 4, // 당겨졌던 카메라가 다시 멀어지는 빠르기 (/초). 가까워질 때는 바로
  TP_MIN_Z: 0.3, // 카메라가 발보다 이만큼 아래로는 안 감 (올려다볼 때 바닥 속으로 안 들어가게)
  TP_HIDE_DIST: 0.9, // 카메라가 이보다 가까이 당겨지면 내 몸을 숨김 (머리 속이 보이지 않게)
  NAME_MAX_LEN: 8, // 대기 화면에서 넣는 이름 (머리 위 표시)
  ROUND_COUNTDOWN_MS: 3000, // 판 시작 전 3·2·1 (그동안 시작 위치에 서서 시선만 돌릴 수 있음). 서버만 켬, 테스트는 0
  COOLDOWN_FLASH_MS: 250, // 조준점 둘레 쿨 원이 다 차면 번쩍이는 시간
  WIN_BANNER_MS: 2500, // 판이 끝나면 "P2 승리!" 큰 글씨 표시 시간
  // 인원 따라 HUD 배치 (2026-10-28 방 최대 8명). shared/hud-layout.js 가 계산, 모양은 index.html
  HUD_CARD_W: 140, // 아래 플레이어 판 한 장 최대 폭 (px, 여백 포함 — 4명까지 이 크기)
  HUD_CARD_MIN_W: 76, // 아무리 좁아도 이보다 작게는 안 함 (그래도 넘치면 판끼리 간격을 줄임)
  HUD_CARD_GAP: 10, // 판 사이 간격 (px)
  HUD_CARD_MARGIN: 12, // 화면 양 끝 여백 (px)
  HUD_CARD_COMPACT_FROM: 5, // 이 인원부터 작은 판 (캐릭터·승 줄 빼고 초상·이름·% 만)
  HUD_LOBBY_W: { min: 380, frac: 0.36, max: 470 }, // 대기실 판 폭 (오른쪽에 붙음, 화면 폭 × frac 을 min~max px 로) — 가운데 맵 섬·사람이 보이게
  LABEL_SIZE: [0.3, 0.13], // 머리 위 이름·% 판 크기 (화면 비율, 거리와 상관없이 같음)
  LABEL_FULL_N: 4, // 머리 위 이름·% 를 원래 크기로 그리는 사람 수 (카메라에서 가까운 순). 나머지는 작고 흐리게
  LABEL_FAR_SCALE: 0.68, // 그 나머지 크기 배율
  LABEL_FAR_OPACITY: 0.72, // 그 나머지 불투명도
  // 성능 표시 (F3, 2026-10-29 재혁: 8명 판에서 어디가 무거운지 숫자로). shared/perf.js 가 계산, client/perf.js 가 재고 보여 줌
  PERF_FPS_MS: 1000, // FPS·평균 프레임 시간: 최근 이만큼
  PERF_LOW_MS: 5000, // 최악(1% low): 최근 이만큼 프레임 중 가장 느린 PERF_LOW_FRAC 의 평균 (1초는 표본이 적어서 길게)
  PERF_LOW_FRAC: 0.01,
  PERF_DRAW_MS: 250, // 패널 글자 다시 쓰는 간격
  PERF_SECTIONS: { ragdoll: '래그돌', bodies: '몸 애니', grid: '블록', hazard: '위험', render: '렌더' }, // 재는 구간 (나머지는 '기타 JS')
  // 직접 해 보는 튜토리얼 (2026-10-29 재혁): 혼자 방(연습 모드 위)에서 목표 하나씩. 해내면 체크·소리 → 다음, '이 단계 넘기기' 늘 있음. 3~5분.
  // 단계 표: 문구의 {키 id} 는 화면이 지금 키 설정 이름으로 (keys.js), {skillDesc}·{ultDesc} 는 고른 캐릭터의 SKILL_DESC·ULT_DESC.
  // 자리는 필드 가운데 기준 (+x 앞): start [x, y, 보는 방향]·target·dummies [x, y, 피해 %] 는 가운데 칸의 가운데에서 몇 칸, items [x, y, 종류]·blocks [x0, y0, x1, y1, 높이] (양 끝 포함)·stairs [[x, y0, y1, 높이], ...] 는 가운데 칸에서 몇 번째 칸
  // skipChars: 이 캐릭터는 이 단계 없음 (바드는 공중 평타가 천천히 낙하·기타 꽂기라 치명타가 없음). kind = 완료 조건 (shared/tutorial.js judge): reach 목표 칸 (minZ 높이 위에 서서) · dash · damage 허수아비 pct% · ringout 허수아비 낙사 · crit 치명타 · skill F · ult R ·
  // item 주워서 쓰기 · dodge 떨어지는 블록 n개 피함 · climb 용암 위 z 까지 오름. 서버 판정은 server/tutorial.js, 진행·문구 순수 계산은 shared/tutorial.js
  TUTORIAL_STEPS: [
    { id: 'move', part: 1, kind: 'reach', keys: ['fwd', 'left', 'back', 'right'], text: '빛나는 칸까지 걸어가기 · {fwd}{left}{back}{right}', start: [-3, -2, 0.6], target: [2, 2] },
    { id: 'jump', part: 1, kind: 'reach', minZ: 2, keys: ['jump'], text: '2칸 벽 위로 · {jump} 점프 → 공중에서 {jump} 한 번 더 = 2단 점프', start: [-3, 0, 0], target: [3, 0], blocks: [[1, -5, 4, 4, 2]] },
    { id: 'dash', part: 1, kind: 'dash', keys: ['dash'], text: '대시 · {dash} — 순간 빠르게 (공중에서도 한 번)', start: [-3, 0, 0] },
    { id: 'push', part: 2, kind: 'damage', pct: 30, keys: ['attack'], text: '허수아비 밀기 · {attack} — 맞을수록 피해 % 가 쌓여 더 멀리 날아감 (30% 까지)', start: [-1.5, 0, 0], dummies: [[0.5, 0, 0]] },
    { id: 'ringout', part: 2, kind: 'ringout', keys: ['attack'], text: '허수아비를 섬 밖으로 떨어뜨리기 (낙사) · {attack} — 피해 % 가 높으면 멀리 날아감', start: [1.4, 0, 0], dummies: [[3, 0, 90]] },
    { id: 'crit', part: 2, kind: 'crit', keys: ['jump', 'attack'], text: '치명타 · {jump} 점프, 떨어지는 중에 {attack} — 위에서 치면 더 세게', start: [-1.5, 0, 0], dummies: [[0.5, 0, 0]], skipChars: ['bard'] },
    { id: 'skill', part: 3, kind: 'skill', keys: ['skill'], text: '스킬 {skill} · {skillDesc}', start: [-2, 0, 0], dummies: [[0.5, 0, 0]], noCooldown: true, marks: 1 },
    { id: 'ult', part: 3, kind: 'ult', keys: ['ult'], text: '필살기 {ult} (게이지가 차면) · {ultDesc}', start: [-2, 0, 0], dummies: [[0.5, 0, 0]], blocks: [[-1, 1, -1, 1, 2]], noCooldown: true, fullUlt: true, marks: 3 },
    { id: 'item', part: 3, kind: 'item', keys: ['item'], text: '아이템 주워서 쓰기 · {item} (손 아이템은 하나만)', start: [-3, 0, 0], items: [[-1, 0, 'knockback']], dummies: [[2, 0, 0]] },
    { id: 'dodge', part: 4, kind: 'dodge', n: 3, keys: [], text: '블록 피하기 · 바닥 그림자 = 블록이 떨어질 자리 (3개)', start: [0, 0, 0] },
    { id: 'climb', part: 4, kind: 'climb', z: 5, keys: ['jump'], text: '용암 위로 · 쌓인 블록을 {jump} 점프로 타고 맨 위까지', start: [-4, 0, 0], stairs: [[-3, -1, 1, 1], [-2, -1, 1, 2], [-1, -1, 1, 3], [0, -1, 1, 4], [1, -1, 1, 5], [2, -1, 1, 5]] },
  ],
  TUTORIAL_NEXT_MS: 1400, // 해낸 뒤 체크·소리를 보여 주고 다음 단계까지
  TUTORIAL_REACH_R: 0.9, // reach: 목표 칸 가운데에서 이 거리 안
  TUTORIAL_DODGE_EVERY_MS: 1600, // dodge: 앞 블록이 내려앉고 이만큼 뒤 다음 블록 (내 자리를 덮게)
  TUTORIAL_DODGE_DROP_Z: 6, // dodge: 블록이 이 높이(바닥 위 칸)에서 떨어지기 시작
  TUTORIAL_DODGE_STEP_MS: 330, // dodge: 1칸 내려오는 간격 (그림자를 보고 피할 시간 ≈ 높이 × 이것)
  TUTORIAL_LAVA_START_Z: -0.6, // climb: 용암 처음 높이 (바닥 아래)
  TUTORIAL_LAVA_MS_PER_CELL: 2400, // climb: 용암이 1칸 오르는 시간 (보통 판보다 느리게)
  TUTORIAL_LAVA_TOP_GAP: 1.5, // climb: 용암은 꼭대기(z)보다 이만큼 아래에서 멈춤 (올라가면 안전)
  TUTORIAL_BOTS: 3, // 끝난 뒤 '봇 3명과 한 판'
  // 목표 칸 빛 (2026-10-29 재혁: 연해서 멀리서 안 보임 → 진하게): 바닥 고리 + 바깥 빛 기둥 + 가운데 밝은 심지, 맥동 (pulseMs 주기)
  TUTORIAL_MARK: { color: 0x5ef09a, core: 0xd8ffe6, h: 4.5, beamR: 0.46, beamOpacity: [0.34, 0.6], coreR: 0.11, coreOpacity: [0.7, 1], ring: [0.3, 0.52], ringOpacity: 1, ringPulse: 0.25, pulseMs: 900 },
  // 끝 화면 문구 (2026-10-29 재혁: '11단계 중 0단계 해냄' 이 차가움 → 숫자 0 을 앞세우지 않고, 넘긴 게 있으면 다시 할 길을 부드럽게). shared/tutorial.js doneMessage
  TUTORIAL_DONE_TEXT: {
    all: { title: '튜토리얼 완료!', text: '모든 단계를 해냈어요. 이제 진짜 판에서 밀고, 피하고, 살아남기!' },
    some: { title: '튜토리얼 끝!', text: '{ok}단계를 해냈어요. 넘긴 단계는 메뉴의 \'튜토리얼\' 에서 언제든 다시 해 볼 수 있어요.' },
    none: { title: '튜토리얼 끝!', text: '넘긴 단계는 메뉴의 \'튜토리얼\' 에서 언제든 다시 해 볼 수 있어요. 바로 한 판 해 봐도 좋아요!' },
  },
  // 그리기 수 줄이기 (2026-10-29, 8명 판 그리기 ~1800 → 캐릭터 몸 조각·파편·떨어지는 블록 칸이 대부분)
  BATCH_MIN_PIECES: 2, // 캐릭터 몸 조각: 같은 재질 묶음(색·발광만 다른 재질은 한 묶음)이 이만큼 이상이면 SkinnedMesh 하나로 합침 (client/batch.js)
  BATCH_HIDE_LAYER: 30, // 합친 조각 Mesh 가 옮겨 가는 층 (아무 카메라도 안 켜서 안 그려짐, 뼈로만 씀)
  INSTANCE_POOL_MIN: 16, // 떨어지는 블록 칸·그림자 칸 InstancedMesh 처음 칸 수 (모자라면 두 배로 다시 만듦, client/instpool.js)
  LEAVE_CONFIRM_MS: 3000, // 판 중 '방 나가기' 를 한 번 누르면 이 동안 '정말 나가기' 로 바뀜 (한 번 더 누르면 나감, 연습·대기실은 바로)
  RESULTS_HERO_MS: 5000, // 승자 클로즈업 (VICTORY_CLOSEUP_MS) 이 끝나면 이 동안은 결과 연출만 (가운데 승자 초상 크게 + 결과 표, 대기실 판은 숨김). 그 뒤 결과는 사라지고 대기실 판이 들어옴 (승수는 위 줄). 호스트 Enter 재시작은 그동안에도 됨
  // 화면 전환 (2026-10-28 재혁: 스매시식 사선 슬래시). shared/wipe.js 가 계산, client/main.js 가 띄움, 모양(색·기울기·띠 폭)은 index.html #wipe.
  // 짧은 것 = 메뉴 → 대기실·연습, 결과 → 대기실 판 (자주 봄) / 큰 것 = 대기실 → 판 시작, 판 끝 → 결과. 판 시작은 슬래시만 (뒤의 카운트다운은 서버 시간 그대로, 안 늦춤)
  UI_WIPE: {
    short: { ms: 420, bands: 2, hold: 0.04 }, // bands: 띠 수 (앞 띠들은 노랑·주황 앞줄, 마지막 남색 띠가 화면을 다 덮음), hold: 다 덮은 채 머무는 비율
    big: { ms: 850, bands: 3, hold: 0.16 },
  },
  UI_WIPE_IN: 0.3, // 띠 하나가 화면 밖에서 다 덮는 자리까지 오는 비율 (빠르게 들어와 화면 교체를 가림)
  UI_WIPE_STAGGER: 0.08, // 띠끼리 출발 간격 (전체 길이에 대한 비율)
  UI_WIPE_X: { from: -240, cover: -60, to: 140 }, // 띠 왼쪽 끝 위치 (vw): 시작(화면 왼쪽 밖) → 다 덮음 → 끝(오른쪽 밖). 띠 폭은 index.html (210vw)
  UI_WIPE_FADE_MS: 240, // '그래픽 낮춤'·움직임 줄이기(prefers-reduced-motion)면 슬래시 대신 짧은 어두운 페이드
  TOAST_MS: 2200, // 화면 알림이 떠 있는 시간
  // 화면 색·조명 (2026-10-22 4단계, 화면만). 테트리미노는 모양마다 색, 쌓이면 BLOCK_LANDED_SHADE 만큼 어둡게
  SHAPE_COLORS: { I: 0x38c8e8, O: 0xf8e030, T: 0xa050e0, S: 0x50c850, Z: 0xe85050, J: 0x4070e8, L: 0xf08a30 },
  BLOCK_LANDED_SHADE: 0.88,
  // 맵 테마마다 WORLD_THEMES.*.piece 가 덮어씀 (shared/piece-look.js): style 면 텍스처 (toy|wood|sandstone|gem|obsidian|marble|jelly|stone) · shape 칸 모양 (round|gem|bricks|cap|crate|framed, client/piece-shapes.js, 그래픽 낮춤이면 round)
  // rows·gap 벽돌 줄 수·줄눈 · segs 둥근 모서리 단 · colors 조각 색 · accent [색1, 색2] 부품 색 (흰 점·금 테·잎·버섯 대) · crack 밝은 금 빛 · fresnel 비스듬한 면 빛 테 · opacity 떨어지는 블록 비침
  PIECE_LOOK: { size: 0.94, bevel: 0.1, glow: 0.16 }, // 테트리미노 칸 모양 (떨어지는·쌓인·하늘 계단·유령): 크기 (칸 사이 틈), 둥근 모서리 반지름, 제 색으로 빛남 — 이어진 무광 지형과 구분
  TERRAIN_COLOR: 0x8c8a96, // 시작 지형 (돌)
  BUILD_COLOR: 0xa87448, // 쌓기 블록 (나무)
  THROWN_COLOR: 0xd8c890, // 착지한 설치 블록 (모래)
  // 노을 하늘: 위 → 가운데 → 지평선 그라데이션, 해는 지평선 가까이 (그림자가 길게)
  SKY_TOP: 0x2c2f6e,
  SKY_MID: 0xc8607a,
  SKY_HORIZON: 0xffae5c,
  SUN_DIR: [-0.55, 0.62, 0.32], // 해가 있는 방향 (필드 가운데 기준, 정규화 전)
  SUN_COLOR: 0xffc890,
  FOG_NEAR: 28,
  FOG_FAR: 75,
  // 판 빛 (client/game-light.js, 2026-10-30 재혁: 타이틀 '빛 언어' 를 판에 섞되 밝기는 유지 — 블록·그림자·가장자리·상대가 잘 보이게). 그래픽 낮춤이면 'off'
  // grade [채도, 대비, 밝기] (캔버스 CSS 색 보정) · vignette [가장자리 어둠 세기, 어둠 시작 (화면 반지름 비율), 색 'r,g,b'] · rim 블록 빛 테두리 (프레넬)
  // halo [빛 무리 세기, 크기 (칸)] 떨어지는 블록·아이템 둘레 · flash 빛 터짐 크기 배수 (0 = 끔) · sky [하늘·안개 밝기 배수, 채도 더함] 판 중에만 (필드 조명은 그대로)
  GAME_LIGHT: 'vivid', // 2026-10-30 재혁 고름 (C)
  GAME_LIGHT_PRESETS: {
    off: { grade: [1, 1, 1], vignette: [0, 0.6, '0,0,0'], rim: 0, halo: [0, 1], flash: 0, sky: null },
    rim: { grade: [1.15, 1.05, 1], vignette: [0.35, 0.58, '12,6,24'], rim: 0.5, halo: [0, 1], flash: 0, sky: [0.75, 0.08] }, // A: 색 진하게 + 하늘 어둡게 + 비네트 + 블록 빛 테두리
    glow: { grade: [1.15, 1.06, 1], vignette: [0.38, 0.56, '12,6,24'], rim: 0.5, halo: [0.35, 2.4], flash: 1, sky: [0.7, 0.1] }, // B: A + 빛 무리 + 착지·KO·필살기 빛 터짐
    vivid: { grade: [1.28, 1.1, 1.02], vignette: [0.5, 0.5, '14,6,28'], rim: 0.75, halo: [0.5, 2.8], flash: 1.5, sky: [0.5, 0.15] }, // C: B 를 세게 (하늘 많이 어둡게 — 타이틀에 가장 가까움)
  },
  GAME_LIGHT_MAX: 600, // 빛 무리·빛 터짐 사각형 최대 수 (InstancedMesh 하나)
  GAME_LIGHT_FLASH_MAX: 48, // 동시에 남는 빛 터짐 수
  GAME_LIGHT_FLASH: { land: [1.8, 280], ko: [5, 560], ult: [4, 460], color: 0xfff0c8 }, // 빛 터짐 [크기 (칸), ms], color 테마 빛이 없을 때
  GAME_LIGHT_ITEM: 0xffe48a, // 아이템 빛 무리 색
  GAME_LIGHT_SKY_SPEED: 0.8, // 하늘이 어두워지는·돌아오는 빠르기 (/초, 0→1)
  // 맵 테마 (client/world.js, 모습만). 표에 없는 맵은 위의 노을 그대로 → 새 맵 테마는 WORLD_THEMES 에 값을 넣고 WORLD_MAP_THEME 에 잇기만
  WORLD_MAP_THEME: { flat: 'meadow', pyramid: 'desert', stairs: 'crystal', bowl: 'volcano', spiral: 'skycastle', pillars: 'mushroom', fortress: 'castle' },
  WORLD_DRIFT_SPEED: 0.006, // 먼 섬·구름이 필드 둘레를 도는 빠르기 (라디안/초)
  WORLD_LOW_DETAIL: 0.4, // 그래픽 낮춤: 먼 섬·구름·떠다니는 빛·위험 입자 수 비율
  WORLD_FAR: { dist: [112, 138], height: [8, 18], radius: [5, 11] }, // 먼 배경 크기 (칸). 하늘 구 반지름 150 안쪽
  WORLD_SEA_FADE: [70, 145],
  // 테마 지형 블록 모습 (client/blocks.js 셰이더, 값 합치기 shared/block-style.js). 2026-10-29 재혁: 칸마다 줄·복붙 무늬 없이 TABS 저폴리 → 주상절리(columns) 고름,
  // 칸 경계는 밟는 윗면에만 알아볼 정도. 없는 이름이면 예전 텍스처 블록. 테마마다 WORLD_THEMES.*.terrain.block 이 아래 값을 덮어씀
  // segs 면 나눔 · disp 꼭짓점 흔들기 (월드 잡음, 칸) · chamfer 드러난 모서리 깎기 [최소, 최대] · step 드러난 윗면 칸마다 높낮이 (발 높이 어긋남 최대 step/2) · blotch 큰 얼룩 [크기(1/칸), 세기]
  // edge 드러난 옆 모서리 어둡게 · wear 드러난 윗면 가장자리 밝게 (닳음) · mottle 자리마다 밝기 흔들림 · topLift 윗면 밝게 · height 아래 어둡게 [바닥 밝기, 이 높이에서 원래 밝기]
  // veins 테마 빛 금 세기 (빛 색 glow 있는 테마만) · veinScale 금 촘촘함 · grid 윗면 칸 경계 [어둡게, 두께(칸)]
  // sideShade 옆면 밝기 (윗면과 대비) · ao 벽 밑·바닥에 닿은 옆면 아래 그늘 · hi 드러난 윗 모서리 하이라이트 · selfLight 제 색으로 빛남 (어두운 하늘 맵, block 에서)
  // 테마 결 (block 에서만): lip 윗면 색이 옆으로 흘러내리는 깊이 (잔디·이끼) · strata 사암 층 [층/칸, 밝기 차] · brick 돌벽돌 [폭, 높이, 줄눈, 벽돌마다 밝기] · sheen 비스듬한 면 빛 (수정)
  // sprout 튀어나온 조각 (화면만, 그래픽 낮춤이면 끔): kind crystal|basalt|mushroom|brick|ledge|tuft · side 드러난 옆면마다 확률 · top 드러난 윗면 확률 (가장자리, BLOCK_SPROUT_TOP_SCALE 배 작게) · size [최소, 최대]
  WORLD_BLOCK_STYLE: 'columns',
  WORLD_BLOCK_STYLES: {
    rock: { segs: 2, disp: 0.13, chamfer: [0.08, 0.2], step: 0, blotch: [0.16, 0.5], edge: 0.6, wear: 0.7, mottle: 0.45, topLift: 1.35, height: [0.55, 6], veins: 0.95, veinScale: 1, grid: [0, 0.03] }, // 시안 A 깎은 바위
    columns: { segs: 1, disp: 0, chamfer: [0.08, 0.14], step: 0.14, blotch: [0.12, 0.35], edge: 0.6, wear: 0.7, mottle: 0.28, topLift: 1.5, height: [0.72, 6], veins: 0.6, veinScale: 0.8, grid: [0.2, 0.025], sideShade: 0.66, ao: 0.5, hi: 0.55 }, // 시안 B 주상절리 (고름)
    smooth: { segs: 1, disp: 0, chamfer: [0.1, 0.12], step: 0, blotch: [0.08, 0.6], edge: 0.35, wear: 0.4, mottle: 0.1, topLift: 1.4, height: [0.65, 6], veins: 0, veinScale: 0.6, grid: [0, 0.03] }, // 시안 C 매끈 저폴리
  },
  BLOCK_SPROUT_MAX: 800, // 튀어나온 조각 최대 수 (조각 종류마다 인스턴스 하나)
  BLOCK_SPROUT_TOP_SCALE: 0.55, // 밟는 윗면 조각은 이만큼 작게 (발에 안 걸리게, 판정 무관)
  WORLD_BLOCK_VARIANTS: 4, // 테마 지형 블록 면 무늬 변형 수 (칸 위치로 고르고, 90도 돌림·뒤집기)
  WORLD_BLOCK_JITTER: 0.08, // 칸마다 밝기 흔들림 (±)
  WORLD_BLOCK_BEVEL: 0.07, // 블록 모서리 깎은 반지름 (칸). 윗면 가운데는 평평 → 서는 자리 그대로
  WORLD_DECOR_MAX: 240, // 블록 소품 (결정 덩어리·깨진 돌) 최대 수. 그래픽 낮춤이면 없음 // 구름 바다 판: 이 거리부터 끝까지 투명해짐 (판 끝이 지평선에 곡선으로 안 보이게)
  // 타이틀 화면 (shared/title.js 계산 · client/title-scene.js 3D · client/title-world.js 테마 장면 · client/title-sound.js 소리 · client/title.js 흐름). 처음 켤 때만, 링크로 오면 건너뜀.
  // 2026-10-30 재혁: 지오메트리 대시 엔딩 아트처럼 — 켤 때마다 맵 테마 7개 중 무작위 하나의 어두운 '엔딩' 장면 (타이틀 전용, 판 맵은 그대로) + 빛나는 글자 + 빛 터짐
  TITLE_TEXT: 'TETRAFALL', // 로고 글자 (5×7 복셀 글꼴: 대문자·숫자·! -)
  TITLE_BOLD: 2, // 글꼴 한 칸 = 2×2 칸 (획 2칸 두께, 10×14 글자)
  TITLE_GAP: 1, // 글자 사이 (글꼴 칸, ×TITLE_BOLD)
  TITLE_BUILD_MS: 3200, // 다 쌓이는 데 걸리는 시간 — 조각 수에서 출발 간격을 거꾸로 계산 (titleInterval)
  TITLE_DROP_MIN_MS: 8, // 출발 간격 최소
  TITLE_DROP_INTERVAL_MS: 55, // 간격 기본값 (dropSchedule 를 그냥 부를 때)
  TITLE_FALL_MS: 520, // 조각 하나가 떨어지는 시간
  TITLE_SETTLE_MS: 260, // 닿은 뒤 작게 튕기는 시간
  TITLE_DROP_H: 9, // 떨어지기 시작하는 높이 (글자 칸)
  TITLE_BOUNCE: 0.25, // 튕김 높이 (글자 칸)
  TITLE_FAST: 6, // 누르면 남은 쌓기를 이만큼 빨리 감음
  TITLE_SCALE: 0.5, // 글자 칸 하나의 크기 (게임 칸)
  TITLE_FILL: 0.74, // 로고 폭이 화면 폭의 이만큼 (카메라 거리를 화면 비율·시야각으로 계산)
  TITLE_FOV: 50, // 타이틀 카메라 세로 시야각 (영화처럼 좁게)
  TITLE_CAM_UP: -1.6, // 카메라를 로고 가운데보다 조금 아래에 (올려다봄, 아래 반사가 보이게)
  TITLE_CAM_SIDE: -3, // 옆으로 비켜 보기 (블록 옆면이 보이게)
  TITLE_CAM_SWAY: 1.2, // 천천히 옆으로 흔들림
  TITLE_CAM_PUSH: 0.1, // 쌓이는 동안 천천히 다가감 (거리 비율)
  TITLE_OUTLINE: 0.1, // 빛 테두리 두께 (블록 크기 비율)
  TITLE_PIECE_GLOW: 0.2, // 글자 블록 (테마 테트리미노 칸 PieceLook) 에 더하는 제 색 빛 (extraGlow) — 타이틀 빛은 따로 (TITLE_GLOW)
  TITLE_LETTER_MIX: 0.5, // 테마 칸 색에 글자 색 (TITLE_THEMES.*.letter) 을 섞는 비율
  TITLE_DARK_MS: 1600, // 처음 캄캄 → 장면 빛이 천천히 밝아지는 시간
  TITLE_LIT_START: 0.12, // 처음 장면 밝기 (0~1)
  TITLE_GLOW: [0.15, 0.62], // 글자 스스로 빛남 [쌓이는 동안, 빛 터진 뒤]
  TITLE_LAND_FLASH_MS: 380, // 블록이 닿을 때 번쩍 (그 블록만)
  TITLE_BURST_MS: 1400, // 다 쌓인 순간 빛 터짐이 가라앉는 시간
  TITLE_BURST_PEAK: 2.0, // 빛 터짐 때 글자 빛 배수 (가장 셀 때)
  TITLE_SWEEP_MS: 2600, // 글자 위를 지나가는 빛 띠 주기 (빛 터진 뒤)
  TITLE_SWEEP_W: 3, // 빛 띠 폭 (게임 칸)
  TITLE_TWINKLE: 0.9, // 반짝임: 1초에 블록 몇 개가 반짝 (× 블록 수 / 100)
  TITLE_BLOOM: [0.75, 0.28, 0.82], // 블룸 [세기, 퍼짐, 문턱 밝기] (그래픽 낮춤이면 끔)
  TITLE_BLOOM_BURST: 1.25, // 빛 터짐 때 블룸 세기
  TITLE_SPARKS: [140, 50], // 빛 터짐 불티 수 [보통, 그래픽 낮춤]
  TITLE_REFLECT: 0.45,
  TITLE_LIGHT: [9, 18, 22], // 빛 세기 배수 [앞 빛, 로고 뒤 빛, 테마 소품 빛] (× TITLE_THEMES key·back 세기) // 아래 바닥 반사 세기 (그래픽 낮춤이면 반사 대신 어두운 바닥)
  TITLE_FLOOR_GAP: 1.1, // 로고 밑에서 바닥까지 (게임 칸)
  TITLE_EXIT_MS: 1150, // Enter 뒤: 카메라가 로고 위로 솟아 장면 안쪽으로 날아가 메뉴 카메라로 자리 잡기까지 (하얀 막 없이 그 장면이 메뉴 배경)
  TITLE_MENU_SHOW_AT: 0.75, // 그중 이 비율에서 메뉴 판을 띄움 (카메라가 자리 잡는 동안 판이 들어옴)
  TITLE_EXIT_FLY: [-0.08, 11, 1.1, 2], // 날아가기 끝 = 메뉴 카메라 [앞으로 (로고 거리 비율, 0 = 로고 바로 위, 음수 = 지나감), 위로 (칸), 바라보는 곳 앞쪽 (로고 거리 비율), 바라보는 곳 높이 (칸)]
  TITLE_EXIT_FADE_MS: 350, // 움직임 줄이기: 하얗게 됐다 (이만큼) 걷히는 (이만큼) 시간 — 가장 하얄 때 메뉴 카메라로
  TITLE_HINT_DELAY_MS: 500, // 빛 터진 뒤 'Enter' 안내가 나오기까지
  TITLE_INPUT_DELAY_MS: 250, // 켜자마자 눌린 키는 무시
  // 테마별 타이틀 장면 (맵 테마 id = WORLD_THEMES 키). 메뉴 섬은 그 테마의 맵 (WORLD_MAP_THEME 거꾸로)
  // bg 배경 · fog [색, 로고 뒤 이만큼부터, 이만큼에서 다 가림] · amb [색, 세기] · key [색, 세기] 로고 앞 빛 · back [색, 세기] 로고 뒤 빛
  // letter 글자 블록 색들 (조각마다 차례로) · glow 글자 빛 색 · edge 빛 테두리 색 · floor 바닥 색 · motes [색, 수, 크기, 위로 오름 빠르기] 떠다니는 빛 가루
  // flare 렌즈 플레어 색 · pieceGlow 글자 블록 빛 더하기 (어두운 칸 재질 테마만) · sound { drone [Hz, Hz], hum 잡음 대역 Hz, ping 띄엄띄엄 소리 종류, land 블록 착지 재질, pitch 반짝 음 높이 }
  TITLE_THEMES: {
    crystal: {
      name: '자수정 동굴', bg: 0x07040d, fog: [0x10071c, 18, 75], amb: [0x6a3a9a, 0.55], key: [0xff8ae8, 1.4], back: [0xb04bff, 2.2],
      letter: [0xf6dcff, 0xe9c4ff, 0xffd6f1], glow: 0xff4fd8, edge: 0xff7be6, floor: 0x140a1f,
      motes: [0xff7ae0, 260, 0.16, 0.05], flare: 0xff8af0,
      crystals: [0xb24bff, 0xff5fd2, 0x8a5bff], rock: 0x241536,
      sound: { drone: [55, 82.4], hum: 380, ping: 'drip', land: 'crystal', pitch: 76 },
    },
    volcano: {
      pieceGlow: 0.45, // 흑요석 칸이 어두워 글자 빛을 더 (1차 '빛나는 글자' 만큼)
      name: '화산', bg: 0x070202, fog: [0x1a0603, 20, 80], amb: [0x5a1a0a, 0.5], key: [0xffa060, 1.3], back: [0xff4a10, 2.4],
      letter: [0xffd2a0, 0xffbd80, 0xffe2b8], glow: 0xff5a14, edge: 0xff7a2a, floor: 0x120807,
      motes: [0xff7020, 220, 0.14, 1.1], flare: 0xffa050,
      lava: 0xff4a0a, rock: 0x1c1210,
      sound: { drone: [41.2, 61.7], hum: 160, ping: 'ember', land: 'stone', pitch: 69 },
    },
    desert: {
      mirror: false, // 거울 바닥 없음 (테마가 땅을 만듦)
      name: '별빛 사막', bg: 0x04071a, fog: [0x0a1030, 30, 110], amb: [0x2a3a7a, 0.6], key: [0xffe6b0, 1.3], back: [0xffb640, 1.8],
      letter: [0xffe9b8, 0xfff2d0, 0xffdc9a], glow: 0xffb030, edge: 0xffd070, floor: 0x161a34,
      motes: [0xfff0c0, 120, 0.1, 0.02], flare: 0xffe0a0,
      sand: 0x2a2c50, stone: 0x3a3456, cap: 0xffc040, moon: 0xdfe8ff,
      sound: { drone: [49, 73.4], hum: 900, ping: 'wind', land: 'sand', pitch: 74 },
    },
    mushroom: {
      name: '빛 버섯 숲', bg: 0x030a0c, fog: [0x061a1c, 16, 70], amb: [0x1a5a5a, 0.4], key: [0xa0fff0, 1.0], back: [0x30ffc8, 1.5],
      letter: [0xd6fff4, 0xc4f6ff, 0xf0d6ff], glow: 0x30ffc8, edge: 0x60ffe0, floor: 0x081412,
      motes: [0x80ffd8, 240, 0.12, 0.25], flare: 0x90ffe8,
      caps: [0x30e8ff, 0xff4fd0, 0x7cff6a], stem: 0x5a7a74,
      sound: { drone: [52, 78], hum: 600, ping: 'bubble', land: 'soft', pitch: 79 },
    },
    skycastle: {
      mirror: false, // 거울 바닥 없음 (테마가 땅을 만듦)
      name: '밤 구름 위 성', bg: 0x050820, fog: [0x0c1238, 30, 120], amb: [0x3a4a9a, 0.6], key: [0xd8e6ff, 1.3], back: [0x7fb0ff, 2.0],
      letter: [0xeef4ff, 0xdce8ff, 0xfff4dc], glow: 0x6fa8ff, edge: 0x9cc6ff, floor: 0x1a2048,
      motes: [0xcfe0ff, 140, 0.1, 0.03], flare: 0xc0d8ff,
      cloud: 0x2c3570, wall: 0x2a2f58, roof: 0x3a2f6a, window: 0xffd27a, moon: 0xeef4ff,
      sound: { drone: [58.3, 87.3], hum: 1200, ping: 'chime', land: 'stone', pitch: 81 },
    },
    castle: {
      name: '횃불 성벽', bg: 0x080504, fog: [0x140c08, 18, 75], amb: [0x4a2a18, 0.5], key: [0xffc890, 1.3], back: [0xff9a30, 2.0],
      letter: [0xffe6c0, 0xfff0d8, 0xffd6a0], glow: 0xff9a30, edge: 0xffb050, floor: 0x16100c,
      motes: [0xffa040, 120, 0.1, 0.9], flare: 0xffc070,
      wall: 0x2e2620, torch: 0xff8a20,
      sound: { drone: [46.2, 69.3], hum: 220, ping: 'torch', land: 'stone', pitch: 72 },
    },
    meadow: {
      mirror: false, // 거울 바닥 없음 (테마가 땅을 만듦)
      name: '반딧불 밤 초원', bg: 0x030810, fog: [0x061420, 22, 90], amb: [0x2a4a5a, 0.3], key: [0xe8ffd0, 0.8], back: [0xb8ff50, 1.0],
      letter: [0xc8e0b0, 0xbcd8a0, 0xd6e4b8], glow: 0x7ee030, edge: 0xa8f050, floor: 0x0a1810,
      motes: [0xd8ff60, 90, 0.2, 0.05], flare: 0xe0ffb0,
      grass: 0x0a2014, tree: 0x06120c, moon: 0xf0f6ff,
      sound: { drone: [61.7, 92.5], hum: 2400, ping: 'cricket', land: 'soft', pitch: 77 },
    },
  },  // 타이틀 소리 (client/title-sound.js, 합성): vol 앰비언트 크기 · fadeIn 켜질 때 천천히 (초) · echo·echoDelay·echoFeedback 울림 · pingEvery 띄엄띄엄 소리 간격 [최소, 최대] 초
  // land 착지 크기 · landGap 착지 소리 최소 간격 (초, 겹쳐 떨어지면 묶음) · burst 로고 완성 반짝 크기 · exit 빠져나가기 쉭 크기
  TITLE_SOUND: { vol: 0.55, fadeIn: 2.5, echo: 0.45, echoDelay: 0.37, echoFeedback: 0.45, pingEvery: [1.4, 4.2], land: 0.55, landGap: 0.045, burst: 0.9, exit: 0.45 },

  // 메뉴 배경 = 타이틀 엔딩 장면 그대로 (client/title-scene.js menu): 메뉴 카메라가 천천히 떠돎. side 옆 (칸) · bob 위아래 (칸) · yaw 바라보는 방향 돌림 (라디안) · speed [옆, 위아래, 돌림] 빠르기 · easeMs 날아간 뒤 떠돌기가 들어오는 시간
  MENU_DRIFT: { side: 5, bob: 0.8, yaw: 0.3, speed: [0.11, 0.17, 0.07], easeMs: 3000 },
  MENU_THEME_KEY: 'tf-menu-theme', // 이번 창 (sessionStorage) 메뉴·타이틀 테마 — 타이틀을 안 거친 메뉴도 같은 테마
  // 대기실 (방 안·판 전) 배경 = 그 방 맵 테마의 어두운 엔딩 장면 (client/lobby-dark.js): 섬·사람은 그대로, 둘레만. 판 시작하면 밝은 판
  LOBBY_DARK: { drop: 6, clear: 0.85, fog: [8, 30], sun: 0.55, hemi: 0.8, flash: 0.85, flashMs: 600, lights: { point: 5, dir: 1 }, prewarmMs: 1500 }, // lights 대기실 무대 빛 수 (모든 테마 같게 채움 — 셰이더 다시 안 만듦) · prewarmMs 메뉴 카메라가 자리 잡고 이만큼 뒤 대기실 장면을 한 번 몰래 그려 셰이더를 미리 데움 · drop 섬 아래 거울 바닥 깊이 (칸) · clear 소품 안 두는 반지름 (판 크기 비율) · fog 안개 시작·끝 더하기 · sun·hemi 섬 빛 (테마 key·amb 세기 비율) · flash·flashMs 맵 바꿈 번쩍 세기·가라앉는 시간 (재혁: 맵 바꾸면 곧바로 장면도)
  // 상승하는 위험 모습 (client/hazard.js, 화면만 — 판정은 서버 lava.z). 테마마다 값은 WORLD_THEMES.*.hazard
  HAZARD_NOISE_WAVE: 1.6, // 잡음 파도 높이 배수 (× 테마 wave[0]). 2026-10-30 재혁: 사인파 줄무늬 → 겹친 잡음 + 흐르는 빛 띠 (시안 A)
  HAZARD_FALLBACK: 'volcano', // 테마 없는 화면(대기실)의 위험 모습
  HAZARD_DEEP: 8, // 몸통 바닥 깊이 (표면 아래 칸) · 필드 밖 깊이
  HAZARD_SEG: [120, 40], // 표면 격자 수 (정점 파도) [보통, 그래픽 낮춤]
  HAZARD_FIELD_RES: 4, // 닿는 곳 거리 표: 칸마다 몇 칸으로 나눔
  HAZARD_FOAM_DIST: 3, // 거리 표 최대 (칸)
  HAZARD_RISE_STEP: 0.5, // 표면이 이만큼(칸) 오를 때마다 번쩍·흔들림·소리 훅 (16초/칸이라 8초마다)
  HAZARD_PULSE_DECAY: 1.2, // 번쩍이 사라지는 빠르기 (/초)
  HAZARD_RISE_SHAKE: [0.06, 260, 4], // 차오를 때 흔들림 [세기, ms, 내 발과 표면 거리가 이 칸 안일 때만]
  HAZARD_VIGNETTE_DIST: 2.5, // 내 발이 표면 위 이 칸 안이면 화면 가장자리 경고
  HAZARD_VIGNETTE_MAX: 0.55, // 경고 최대 진하기
  HAZARD_BULGE_DIST: 1.2, // 표면이 발 밑 이 칸 안이면 들썩
  HAZARD_BULGE_AMP: 0.18, // 들썩 높이 (칸)
  HAZARD_CONTACT_RATE: 14, // 닿는 곳 입자 (초당, 그래픽 낮춤이면 없음)
  HAZARD_FAR_SIZE: 145, // 지평선까지 바다: 필드 밖 큰 판 반 크기 (칸, 하늘 구 150 안쪽). 끝 쪽은 지평선 색으로 녹이며 투명
  HAZARD_CURVE: 0.0009, // 먼 바다가 지평선 쪽으로 둥글게 내려가는 정도 (거리² 배율) → 먼 산이 차례로 잠김 (125칸에서 약 10칸 아래)
  HAZARD_CURVE_FROM: 20, // 이 거리(필드 가운데에서) 안쪽은 평평 (필드 위 판과 이음매 없이)
  HAZARD_FAR_SEG: 64, // 먼 판 격자 수 (둥글게 내려가는 모양만)
  HAZARD_FOG_MIX: 0.75, // 먼 액체가 안개색에 섞이는 정도 (안개 끝에서)
  HAZARD_SHIMMER_NORMAL: 0.9, // 먼 표면 잔물결 법선 세기 (햇빛 반짝임 길, 그래픽 낮춤이면 끔)
  HAZARD_FAR_RINGS: 16, // 먼 섬·산이 잠기는 곳 테 최대 수 (셰이더 uniform)
  HAZARD_RING_ABOVE: 0.4, // 꼭대기가 표면 아래로 이만큼 잠길 때까지 테 (잠긴 직후 거품)
  HAZARD_SINK_MS: 2400, // 빠진 몸이 잠기는 시간
  HAZARD_SINK_FLOAT: 0.3, // 그중 앞부분 비율은 표면에 걸려 허우적
  HAZARD_SINK_DEPTH: 1.5, // 잠기는 깊이 (칸)
  // 테마 값: sky 하늘 그라데이션(below = 지평선 아래, 구름 바다 쪽 · 밤이면 stars 별 밝기, disc 달 색, glow 달빛 번짐, discSize 원반 크기)
  // sunDir 해(달) 방향 · hemi [하늘, 땅, 세기] · fog [색, 시작, 끝]
  // floor 바닥 (paint grass|sand|stone|cracks|marble|moss, a·b 체크 두 색, line 칸 선, rim 판 옆면, glow 빛나는 금 색)
  // terrain 지형 블록 (paint grass|sandstone|bricks|crystal|basalt|stump, top·side 면 색, rim 테두리, glow 빛나는 결 색, crust 식은 껍질 색,
  //   tints 칸마다 섞는 빛깔 (tintMix 비율), jitter 밝기 흔들림, decor 블록 소품 { kind crystal|rubble, chance 칸 비율, size [최소, 최대] })
  // cliff 섬 절벽·뿌리 띠 색 (위→아래) · props 먼 섬 소품 · glow 빛나는 소품 색 · wall·roof·flag 탑·집 색
  // far 먼 배경 (shapes peak|mesa|pyramid|volcano|crystal|cumulus|bigshroom|castle, haze 지평선 색 섞는 비율 [최소, 최대])
  // sea 아래 구름 바다 [색, 높이] · cloudGlow 구름 스스로 밝기 · motes 떠다니는 빛 { color, count, size, rise 위로 올라감, speed } · edgeOpacity 필드 높이 세로선
  // hazard 위험(용암 자리, hazard.js): style water|lava|swamp|energy|storm, deep·mid 깊은 곳 색, shallow 얕은 곳, foam 닿는 곳 테·물마루,
  //   alpha [깊은 곳, 얕은 곳] 불투명도, reflect 하늘 반사, wave [파도 높이, 빠르기], depthFade 얕음→깊음 거리(칸),
  //   tint 잠긴 블록 색 (tintDepth 깊이당), band [닿는 선 위 띠 색, 세기, 빛남(true)/어두워짐], contact 닿는 곳 입자 색, ambient·particleSpeed 표면 입자,
  //   light [빛 색, 세기 배율], particles 표면 입자 두 색, splash 빠질 때 튀김 두 색, vignette 화면 경고 색 (낮 맵은 짙게, 밤 맵은 밝게 — 배경과 대비). 밤 맵은 반구광(hemi)을 세게 해 캐릭터·블록이 안 묻히게
  WORLD_THEMES: {
    meadow: { // 평지: 초원 섬 · 맑은 낮 · 파란 물
      seed: 11,
      sky: { top: 0x2f7fd8, mid: 0x7fc0f0, horizon: 0xdff0f6, below: 0xc4e2f2 },
      sunDir: [-0.45, 0.5, 0.78],
      sunColor: 0xfff4e0,
      sunIntensity: 1.7,
      hemi: [0xeef6ff, 0x7a9660, 1.05],
      fog: [0xd6ebf4, 45, 120],
      floor: { paint: 'grass', a: 0x88cc58, b: 0x7bbf4c, line: 'rgba(40,70,25,0.35)', rim: 0x6aa844 },
      terrain: { paint: 'grass', top: 0x86c857, side: 0x9a6b44, rim: 0x4c3420, block: { lip: 0.2, strata: [2.2, 0.035], tints: [0xa0d468, 0x78b44e, 0x9cb858], sprout: { kind: 'tuft', side: 0, top: 0.35, size: [0.9, 1.4] } } }, // 잔디 윗면이 흙 옆면으로 흘러내림
      piece: { style: 'wood', shape: 'crate', bevel: 0.05, glow: 0.12, accent: [0x58b040, 0xffffff], colors: { I: 0x4fb8e0, O: 0xf6c945, T: 0xb07ad8, S: 0x3fae8a, Z: 0xe8604c, J: 0x4a6ee0, L: 0xf09038 } }, // 나무 상자 + 윗면 잎 덤불 (건축가 판자 상자와 달리 띠·쇠 모서리 없음, 잔디 초록과 안 겹치게 S 는 청록)
      cliff: [0x9a6b44, 0x8f8576, 0x81786a, 0x72695c, 0x645b50],
      rock: 0x8f8778,
      trunk: 0x7a5434,
      leaf: [0x5fae48, 0x76c056, 0x4f9a3e, 0x9ccc5a],
      props: ['pine', 'round', 'round', 'rock'],
      cloud: 0xffffff,
      far: { shapes: ['peak'], color: 0x7090b8, base: -20, count: 14, haze: [0.4, 0.7] },
      sea: [0xeef6fb, -16], // 구름 바다 [색, 높이]
      clouds: 30,
      islets: 7,
      edgeOpacity: 0.05,
      hazard: { style: 'water', deep: 0x0b3a8c, mid: 0x2a7ee6, shallow: 0x7ad4ff, foam: 0xf4fbff, alpha: [0.9, 0.5], reflect: 0.55, wave: [0.07, 1.0], depthFade: 1.4, tint: 0x2a6ad0, tintDepth: 0.4, band: [0x6a7a90, 0.5, false], contact: 0xffffff, ambient: 0.5, particleSpeed: 3, light: [0x5aa8ff, 0.6], particles: [0xffffff, 0xa8d8ff], splash: [0xffffff, 0x8fd0ff], vignette: 0x082a7a },
    },
    desert: { // 피라미드: 사막 · 늦은 오후 · 청록 오아시스 물 · 사암 블록
      seed: 23,
      sky: { top: 0x3c7ccc, mid: 0x9cc0e0, horizon: 0xf8d8a0, below: 0xeccb94 },
      sunDir: [-0.62, 0.5, 0.42],
      sunColor: 0xffd29a,
      sunIntensity: 1.55,
      hemi: [0xfff0d8, 0xb08a5a, 1.0],
      fog: [0xf2dcb0, 45, 120],
      floor: { paint: 'sand', a: 0xebcf8e, b: 0xe0c27e, line: 'rgba(120,80,30,0.35)', rim: 0xd2a964 },
      terrain: { paint: 'sandstone', top: 0xf0d49a, side: 0xd9a868, rim: 0x8a5a2c, block: { strata: [2.6, 0.12], height: [0.85, 6], mottle: 0.18, tints: [0xf2d49a, 0xe6bc7c, 0xf6dfb4], sprout: { kind: 'rubble', side: 0.14, top: 0, size: [0.9, 1.4], ground: true } } }, // 사암 층 + 벽 밑 무너진 사암 덩어리
      piece: { style: 'sandstone', shape: 'bricks', rows: 3, gap: 0.045, bevel: 0.025, glow: 0.1, colors: { I: 0x3aa6a0, O: 0xf2d060, T: 0x9c4f8c, S: 0x6f9a4c, Z: 0xc8502c, J: 0x2f5f9e, L: 0xe8902e } }, // 사암 벽돌 층 (칸 안 3줄 어긋나 쌓기 + 상형문자 새김, 사막 장신구 색: 터키석·사프란·자두·선인장·테라코타·청금석·황토)
      cliff: [0xc98a50, 0xa85e34, 0xd49a5c, 0x9a5230, 0x7c4426], // 붉은 사암 지층
      rock: 0xc08a56,
      trunk: 0x8a6440,
      leaf: [0x5c9a48, 0x6fae50, 0x4e8a3c],
      props: ['cactus', 'palm', 'rock', 'pyramid'],
      cloud: 0xfff2e0,
      far: { shapes: ['mesa', 'mesa', 'pyramid'], color: 0xc08a5a, base: -18, count: 12, haze: [0.4, 0.7] },
      sea: [0xf0dcb8, -16], // 아래 모래 안개 바다 (밝게, 붉은 절벽 띠가 도드라지게)
      clouds: 18,
      islets: 6,
      edgeOpacity: 0.05,
      hazard: { style: 'water', deep: 0x05606c, mid: 0x14b8b0, shallow: 0x80f2e2, foam: 0xe8fff8, alpha: [0.9, 0.5], reflect: 0.5, wave: [0.06, 0.9], depthFade: 1.4, tint: 0x1a9a98, tintDepth: 0.4, band: [0x8a7a68, 0.55, false], contact: 0xffffff, ambient: 0.5, particleSpeed: 3, light: [0x40e0d0, 0.6], particles: [0xffffff, 0x9ff0e4], splash: [0xffffff, 0x9ff0e4], vignette: 0x044a50 },
    },
    crystal: { // 계단: 수정 동굴 · 밤 · 분홍 에너지 액체 · 수정 블록
      seed: 37,
      sky: { top: 0x0a0822, mid: 0x261c58, horizon: 0x5a3c8c, below: 0x1a1240, stars: 0.9, disc: 0xeae6ff, glow: 0x7060e0, discSize: 0.0012 },
      sunDir: [0.45, -0.5, 0.62],
      sunColor: 0xc8c0ff,
      sunIntensity: 1.05,
      hemi: [0xb8a8ff, 0x48386e, 1.55],
      fog: [0x2a2052, 40, 120],
      floor: { paint: 'stone', a: 0x5a5474, b: 0x524c6a, line: 'rgba(20,14,40,0.55)', rim: 0x4a4466 },
      terrain: { paint: 'crystal', top: 0x6c6290, side: 0x544a74, rim: 0x231c3a, glow: 0x6ef2ff, tints: [0x8a7cc0, 0x5a6ab0, 0x7a5aa8], decor: { kind: 'crystal', chance: 0.22, size: [0.32, 0.5] }, block: { segs: 2, disp: 0.07, step: 0.12, mottle: 0.42, veins: 0.4, veinScale: 0.9, sheen: 0.16, sprout: { kind: 'crystal', side: 0.32, top: 0.16, size: [1, 1.6] } } }, // 결정 면 (꼭짓점 흔들어 깎은 면 + 비스듬한 면 빛) + 수정 맥
      piece: { style: 'gem', shape: 'gem', bevel: 0.16, glow: 0.3, fresnel: 0.6, opacity: 0.86, colors: { I: 0x5ef0ff, O: 0xffe066, T: 0xc070ff, S: 0x50f0a0, Z: 0xff5080, J: 0x5a7cff, L: 0xffa040 } }, // 깎인 보석 (모서리 잘린 여러 면 + 면마다 낮은 피라미드, 빛 테, 떨어질 땐 살짝 비침)
      cliff: [0x4a4268, 0x3c3458, 0x322b4c, 0x29233e, 0x201b32],
      rock: 0x4c4466,
      trunk: 0x3a3250,
      leaf: [0x6a5c90],
      glow: [0x6ef2ff, 0xb48cff, 0x8ad8ff],
      props: ['crystal', 'crystal', 'rock'],
      cloud: 0x5a4c90,
      cloudGlow: 0.35,
      far: { shapes: ['peak', 'crystal', 'crystal'], color: 0x2a2450, base: -16, count: 14, haze: [0.2, 0.45] },
      sea: [0x1c1446, -16],
      clouds: 14,
      islets: 7,
      motes: { color: 0x9ae8ff, count: 50, size: 0.16 },
      edgeOpacity: 0.06,
      hazard: { style: 'energy', deep: 0x30186a, mid: 0x8a58d8, shallow: 0xc8acf4, foam: 0xf2ebff, alpha: [0.88, 0.6], reflect: 0.35, wave: [0.05, 1.3], depthFade: 1.0, tint: 0x7c52c8, tintDepth: 0.5, band: [0x9a70e8, 0.6, true], contact: 0xe4d8ff, ambient: 0.8, particleSpeed: 4, light: [0x9a6ef0, 1.0], particles: [0xe0d0ff, 0x9a6ae0], splash: [0xffffff, 0xa078f0], vignette: 0x7c52c8 } // 보라 빛 (2026-10-30 재혁: 형광 분홍 눈 아픔),
    },
    volcano: { // 그릇: 화산 분화구 · 밤 · 용암 · 현무암 블록 (빛나는 금)
      seed: 41,
      sky: { top: 0x140608, mid: 0x3c1010, horizon: 0x8c2c16, below: 0x2c0c08, stars: 0.35, disc: 0xffc8a0, glow: 0xff6a30, discSize: 0.0008 },
      sunDir: [0.35, 0.6, 0.5],
      sunColor: 0xffb090,
      sunIntensity: 1.0,
      hemi: [0xffbca0, 0x5c3030, 1.45],
      fog: [0x3c1410, 40, 115],
      floor: { paint: 'cracks', a: 0x4a4446, b: 0x423c3e, line: 'rgba(0,0,0,0.5)', rim: 0x302a2c, glow: 0xff6a1a },
      terrain: { paint: 'basalt', top: 0x585254, side: 0x464042, rim: 0x161214, glow: 0xff7a24, crust: 0x4a2e28, tints: [0x5a5050, 0x484244, 0x5a4840], decor: { kind: 'rubble', chance: 0.2, size: [0.45, 0.7] }, block: { top: 0x8e8080, side: 0x5a5052, topLift: 1.55, sideShade: 0.72, height: [0.8, 6], veins: 0.75, selfLight: 0.2, sprout: { kind: 'basalt', side: 0.24, top: 0.05, size: [1.1, 1.6] } } }, // 현무암 (어두운 하늘에 묻히지 않게 밝은 재빛 윗면) + 용암 금
      piece: { style: 'obsidian', bevel: 0.07, glow: 0.08, crack: 2.4, colors: { I: 0x40d8ff, O: 0xffd040, T: 0xd060ff, S: 0x60ff80, Z: 0xff3a20, J: 0x4a70ff, L: 0xff8a20 } }, // 흑요석 + 조각 색으로 밝게 빛나는 금
      cliff: [0x3e3838, 0x322c2c, 0x2a2424, 0x221c1c, 0x1a1414],
      rock: 0x3a3434,
      trunk: 0x2a2220,
      leaf: [0x3a3030],
      glow: [0xff7a24, 0xffb040],
      props: ['deadtree', 'lavarock', 'rock'],
      cloud: 0x5c4846,
      cloudGlow: 0.3,
      far: { shapes: ['volcano', 'volcano', 'peak'], color: 0x2a1c1c, base: -16, count: 12, haze: [0.15, 0.35] },
      sea: [0x5a160a, -16], // 아래 멀리 녹은 바위 바다 (어둡게 빛남)
      clouds: 16,
      islets: 6,
      motes: { color: 0xff9a40, count: 60, size: 0.12, rise: true, speed: 1.2 },
      edgeOpacity: 0.06,
      hazard: { style: 'lava', deep: 0x4a0a04, mid: 0xff4a08, shallow: 0xffa830, foam: 0xffe070, alpha: [1, 1], reflect: 0.08, wave: [0.04, 0.5], depthFade: 0.8, tint: 0xff5010, tintDepth: 0.8, band: [0xff5a10, 0.9, true], contact: 0xd8d0c8, ambient: 1, particleSpeed: 4, light: [0xff6a20, 1.0], particles: [0xffb030, 0xff5010], splash: [0xffb030, 0x5a5050], vignette: 0xff4010 }, // 닿는 곳 입자 = 증기 (희끄무레)
    },
    skycastle: { // 나선: 하늘 성 · 금빛 해질녘 · 번개 구름 · 흰 돌벽돌
      seed: 53,
      sky: { top: 0x3c3c8c, mid: 0xd88c8c, horizon: 0xffd27c, below: 0xffe2b4 },
      sunDir: [-0.6, 0.55, 0.25],
      sunColor: 0xffcc80,
      sunIntensity: 1.55,
      hemi: [0xfff0d4, 0x8c7ca4, 1.1],
      fog: [0xffdca4, 45, 120],
      floor: { paint: 'marble', a: 0xf2ece0, b: 0xe6decc, line: 'rgba(150,120,60,0.4)', rim: 0xd8b860 },
      terrain: { paint: 'bricks', top: 0xf4efe4, side: 0xe2d9c6, rim: 0xc09a40, block: { step: 0.05, mottle: 0.12, brick: [0.62, 0.333, 0.035, 0.12], tints: [0xf4efe4, 0xeadfcb, 0xf8f3ea], sprout: { kind: 'brick', side: 0.25, top: 0, size: [1, 1] } } }, // 흰 돌벽돌
      piece: { style: 'marble', shape: 'framed', bevel: 0.08, glow: 0.12, accent: [0xf0c040, 0xffffff], colors: { I: 0x3a9ad0, O: 0xe8c838, T: 0x9a5ad8, S: 0x3aa860, Z: 0xd84060, J: 0x4a56c8, L: 0xe87a30 } }, // 진한 대리석 + 굵은 금 테·금 마름모 (크림 성벽과 안 섞이게)
      cliff: [0xe6dccb, 0xb8a8a4, 0xa09094, 0x8a7a84, 0x706070],
      rock: 0xc8bcb4,
      trunk: 0x8a6a4a,
      leaf: [0x7ab060, 0x8cc070],
      wall: 0xf2ece0,
      roof: 0x5a6ad8,
      flag: 0xff5050,
      props: ['spire', 'spire', 'round', 'rock'],
      cloud: 0xfff0dc,
      far: { shapes: ['cumulus', 'cumulus', 'castle'], color: 0xffe0c4, base: -16, count: 12, haze: [0.2, 0.45] },
      sea: [0xffe6c4, -16],
      clouds: 34,
      islets: 8,
      motes: { color: 0xffe080, count: 40, size: 0.1 },
      edgeOpacity: 0.05,
      hazard: { style: 'storm', deep: 0x24124a, mid: 0x6c3cbc, shallow: 0xa484ec, foam: 0xf0e4ff, alpha: [0.95, 0.7], reflect: 0.3, wave: [0.1, 0.8], depthFade: 1.2, tint: 0x6a40c0, tintDepth: 0.5, band: [0xc0a0ff, 0.4, true], contact: 0xf0e8ff, ambient: 0.7, particleSpeed: 4, light: [0xa070ff, 0.9], particles: [0xe8d8ff, 0xa070ff], splash: [0xffffff, 0xa070ff], vignette: 0x8a50ff },
    },
    mushroom: { // 기둥 숲: 버섯 숲 · 밤 반딧불 · 형광 연두 독늪 · 그루터기 블록
      seed: 67,
      sky: { top: 0x061a1e, mid: 0x0e3a3c, horizon: 0x2c6c5c, below: 0x0a2626, stars: 0.75, disc: 0xf0ffe8, glow: 0x60c0a0, discSize: 0.0035 },
      sunDir: [0.5, 0.4, 0.55],
      sunColor: 0xc0f0e0,
      sunIntensity: 1.05,
      hemi: [0xa8f0d8, 0x34503e, 1.55],
      fog: [0x0e3030, 40, 115],
      floor: { paint: 'moss', a: 0x4a7840, b: 0x426e3a, line: 'rgba(10,30,10,0.5)', rim: 0x5a4430 },
      terrain: { paint: 'stump', top: 0xc8985e, side: 0x7a5434, rim: 0x2e1e12, block: { top: 0x6e9a4a, lip: 0.24, tints: [0x84aa54, 0x5e8a46, 0x9a9a52], sprout: { kind: 'mushroom', side: 0.14, top: 0.16, size: [1, 1.7] } } }, // 이끼 낀 흙 (셰이더 블록은 윗면 이끼, 예전 텍스처는 나무 그루터기)
      piece: { style: 'jelly', shape: 'cap', bevel: 0.24, glow: 0.18, fresnel: 0.35, accent: [0xfffaf0, 0xf0e2c8], colors: { I: 0x5ae0d8, O: 0xffd25a, T: 0xb46cf0, S: 0xb0f060, Z: 0xff5a8a, J: 0x5a8aff, L: 0xff8f4a } }, // 버섯: 크림색 밑동 + 볼록한 갓 (조각 색) + 큰 흰 점
      cliff: [0x5a4030, 0x4a3a30, 0x3a3028, 0x2e2620, 0x241e1a],
      rock: 0x4a5048,
      trunk: 0xd8d0b8, // 버섯 대
      leaf: [0x2c5a3a, 0x3a6a40],
      glow: [0xff6ab4, 0x7ae0ff, 0xffd060],
      props: ['mushroom', 'mushroom', 'pine', 'rock'],
      cloud: 0x5a9a8c,
      cloudGlow: 0.4,
      far: { shapes: ['bigshroom', 'bigshroom', 'peak'], color: 0x14302c, base: -16, count: 12, haze: [0.15, 0.35] },
      sea: [0x0a2a28, -16],
      clouds: 14,
      islets: 7,
      motes: { color: 0xfff27a, count: 70, size: 0.13 }, // 반딧불 (노랑 — 독늪 연두와 다르게)
      edgeOpacity: 0.06,
      hazard: { style: 'swamp', deep: 0x0a4a1c, mid: 0x2ee06a, shallow: 0x9cffb4, foam: 0xe4ffe8, alpha: [0.95, 0.75], reflect: 0.25, wave: [0.035, 0.6], depthFade: 1.0, tint: 0x60d020, tintDepth: 0.6, band: [0x80ff40, 0.35, true], contact: 0xdcff96, ambient: 0.6, particleSpeed: 2, light: [0x8aff40, 1.0], particles: [0xc8ff60, 0x60ff20], splash: [0xc8ff60, 0x60ff20], vignette: 0x70ff30 },
    },
    castle: { // 요새: 중세 성 · 맑은 오후 · 탁한 겨자빛 해자 독늪 · 성벽 돌
      seed: 79,
      sky: { top: 0x3c86d8, mid: 0x88c4ee, horizon: 0xeaf2ea, below: 0xc8dccc },
      sunDir: [-0.5, 0.45, 0.62],
      sunColor: 0xffeed0,
      sunIntensity: 1.6,
      hemi: [0xf0f4ff, 0x7a8a60, 1.05],
      fog: [0xdceaea, 45, 120],
      floor: { paint: 'grass', a: 0x80c050, b: 0x74b446, line: 'rgba(40,70,25,0.35)', rim: 0x8a8a88 }, // 판 옆면 = 돌 테
      terrain: { paint: 'bricks', top: 0xb0b0ac, side: 0x9c9c9a, rim: 0x46464a, block: { step: 0.06, mottle: 0.2, brick: [0.8, 0.5, 0.04, 0.16], tints: [0xb0b0ac, 0xa2a89e, 0xbab4aa], sprout: { kind: 'brick', side: 0.28, top: 0, size: [1, 1] } } }, // 회색 돌벽돌
      piece: { style: 'stone', shape: 'bricks', rows: 2, gap: 0.06, bevel: 0.04, glow: 0.1, colors: { I: 0x4a90b8, O: 0xd8b040, T: 0x8a4a9a, S: 0x4a8a50, Z: 0xb83a3a, J: 0x34508c, L: 0xc8702c } }, // 줄눈 있는 돌 벽돌 2줄 (문장 색으로 칠함)
      cliff: [0x8a8a88, 0x7a7268, 0x6e665c, 0x625a50, 0x544c44],
      rock: 0x8a8a86,
      trunk: 0x6a4a30,
      leaf: [0x4f9a3e, 0x5fae48, 0x76c056],
      wall: 0xb8b4ac,
      roof: 0xc04a3a,
      flag: 0x3a5ad8,
      props: ['tower', 'house', 'pine', 'round'],
      cloud: 0xffffff,
      far: { shapes: ['peak', 'peak', 'castle'], color: 0x7090b8, base: -18, count: 13, haze: [0.4, 0.7] },
      sea: [0xeef6f4, -16],
      clouds: 28,
      islets: 7,
      edgeOpacity: 0.05,
      hazard: { style: 'swamp', deep: 0x06302c, mid: 0x109a78, shallow: 0x6ee8c0, foam: 0xd8fff0, alpha: [0.96, 0.8], reflect: 0.3, wave: [0.035, 0.6], depthFade: 1.0, tint: 0x0e8068, tintDepth: 0.6, band: [0x2a5a50, 0.5, false], contact: 0xd8fff0, ambient: 0.5, particleSpeed: 2, light: [0x40d0a8, 0.5], particles: [0xc0ffe8, 0x40c8a0], splash: [0xd8fff0, 0x40c8a0], vignette: 0x063a30 }, // 겨자빛 탁한 늪 (잔디 초록·버섯 숲 형광 연두와 다르게)
    },
  },
  HELD_MODEL_SIZE: 0.28,
  ROBOT_EYE_WHITE: 0.62, // 로봇 흰자 반지름 (원래 검은 눈 무리 크기에 대한 비율)
  ROBOT_EYE_PUPIL: 0.3, // 로봇 눈동자 반지름 (같은 비율)
  ROBOT_RUN_SPEED: 3.2, // 이 속도(칸/초)보다 빠르면 로봇이 달리기 동작
  ROBOT_FADE_S: 0.15, // 로봇 동작이 바뀔 때 섞는 시간
  FIGURE_CHARS: ['tank', 'ninja', 'builder', 'hook', 'hunter', 'cannon', 'berserker', 'bard'], // TABS 식 몸(client/figure.js)으로 그리는 캐릭터 (2026-10-24). 캐릭터 없으면 로봇
  // 체형 (칸, client/figure.js). foot 발 두께, shin·thigh 다리 마디, torso 몸통 높이, chestR·waistR 가슴·허리 반지름, depth 앞뒤 납작함,
  // barrel 이면 몸통이 둥근 통, head·headW 머리 높이·폭, sink 머리가 어깨에 묻히는 깊이, upper·lower 팔 마디, armR·foreR 팔 굵기,
  // legR 다리 굵기, hand 손 크기, shoulderY 어깨 관절 옆 거리, hipY 다리 사이, hunch 구부정한 각, bend 가만히 설 때 무릎 굽힘(없으면 0), spread 팔 벌린 각
  FIGURE_BODIES: {
    // 보통 마네킹
    lean: { foot: 0.06, shin: 0.36, thigh: 0.36, torso: 0.48, chestR: 0.15, waistR: 0.12, depth: 0.72, head: 0.28, headW: 0.17, sink: -0.05, upper: 0.3, lower: 0.27, armR: 0.045, foreR: 0.04, legR: 0.065, hand: 0.048, shoulderY: 0.18, hipY: 0.075, hunch: 0, spread: 0.22 },
    // 닌자 (재빠른 그림자): 가늘고 날렵한 몸, 살짝 숙이고 무릎 굽힘 (2026-10-28 재혁: 치비 말고 보통 머리·원래 키)
    slim: { foot: 0.06, shin: 0.37, thigh: 0.37, torso: 0.46, chestR: 0.14, waistR: 0.11, depth: 0.76, head: 0.27, headW: 0.17, sink: -0.05, upper: 0.29, lower: 0.27, armR: 0.04, foreR: 0.037, legR: 0.054, hand: 0.046, shoulderY: 0.165, hipY: 0.066, hunch: 0.12, bend: 0.2, spread: 0.26 },
    // 땅딸막 노동자 (건축가): 키 작고 다리 짧음, 넓은 어깨·두꺼운 팔뚝, 배 살짝 (2026-10-28 재혁: 마리오·밥 더 빌더 느낌)
    sturdy: { foot: 0.07, shin: 0.25, thigh: 0.25, torso: 0.55, chestR: 0.235, waistR: 0.22, depth: 0.84, head: 0.28, headW: 0.21, sink: 0.04, upper: 0.25, lower: 0.25, armR: 0.068, foreR: 0.076, legR: 0.09, hand: 0.068, shoulderY: 0.29, hipY: 0.1, hunch: 0.05, bend: 0.12, spread: 0.36 },
    // 호리호리 음유시인 (바드): 가늘고 다리 김, 좁은 어깨, 곧은 자세 (2026-10-28 재혁: 로빈후드)
    lithe: { foot: 0.06, shin: 0.41, thigh: 0.4, torso: 0.45, chestR: 0.14, waistR: 0.11, depth: 0.72, head: 0.27, headW: 0.17, sink: -0.06, upper: 0.29, lower: 0.27, armR: 0.04, foreR: 0.036, legR: 0.056, hand: 0.045, shoulderY: 0.165, hipY: 0.068, hunch: -0.04, spread: 0.18 },
    // 덩치 큰 해적 선장 (갈고리): 술통 가슴·넓은 어깨의 큰 상체 + 가는 다리 (뒤뚱 걸음), 긴 팔 (2026-10-28 위가 크고 아래가 가는 실루엣)
    reach: { foot: 0.06, shin: 0.33, thigh: 0.3, torso: 0.58, chestR: 0.25, waistR: 0.19, depth: 0.82, head: 0.28, headW: 0.19, sink: 0.02, upper: 0.34, lower: 0.33, armR: 0.06, foreR: 0.055, legR: 0.055, hand: 0.058, shoulderY: 0.28, hipY: 0.07, hunch: 0.08, spread: 0.32 },
    // 웅크린 추적자 (사냥꾼): 사냥개처럼 등 굽고 목을 앞으로 뺀 마른 몸, 무릎 늘 굽힘, 긴 팔 (2026-10-28 낮은 실루엣)
    stalk: { foot: 0.06, shin: 0.36, thigh: 0.33, torso: 0.47, chestR: 0.16, waistR: 0.115, depth: 0.76, head: 0.28, headW: 0.17, sink: -0.07, upper: 0.33, lower: 0.31, armR: 0.042, foreR: 0.038, legR: 0.058, hand: 0.05, shoulderY: 0.175, hipY: 0.07, hunch: 0.52, bend: 0.6, spread: 0.2 },
    // 통통 포수 꼬마 (대포수): 공처럼 둥근 배, 짧고 굵은 팔다리 (탱크보다 작음, 2026-10-28)
    stout: { foot: 0.065, shin: 0.17, thigh: 0.16, torso: 0.56, chestR: 0.31, waistR: 0.31, depth: 0.95, barrel: true, head: 0.27, headW: 0.21, sink: 0.07, upper: 0.21, lower: 0.2, armR: 0.06, foreR: 0.058, legR: 0.096, hand: 0.066, shoulderY: 0.28, hipY: 0.13, hunch: -0.06, bend: 0.25, spread: 0.45 },
    // 우락부락한 몸 (광전사): 키 작고 다부짐 — 아주 넓은 어깨·두꺼운 가슴 역삼각, 목 거의 없음, 굵은 팔뚝, 짧고 단단한 다리, 앞으로 숙인 공격적 자세 (2026-10-27 재혁: 코믹스 울버린 참고)
    brute: { foot: 0.07, shin: 0.22, thigh: 0.22, torso: 0.56, chestR: 0.29, waistR: 0.2, depth: 0.74, head: 0.27, headW: 0.21, sink: 0.1, upper: 0.27, lower: 0.26, armR: 0.08, foreR: 0.085, legR: 0.1, hand: 0.078, shoulderY: 0.34, hipY: 0.105, hunch: 0.3, bend: 0.3, spread: 0.42 },
    // 드럼통 (탱크): 둥근 통 몸통, 팔다리 짧고 뭉툭
    drum: { foot: 0.08, shin: 0.22, thigh: 0.22, torso: 0.74, chestR: 0.32, waistR: 0.31, depth: 0.86, barrel: true, head: 0.27, headW: 0.2, sink: 0.05, upper: 0.27, lower: 0.25, armR: 0.085, foreR: 0.085, legR: 0.1, hand: 0.075, shoulderY: 0.35, hipY: 0.13, hunch: 0.04, bend: 0.15, spread: 0.45 },
  
  },
  FIGURE_BODY: { tank: 'drum', ninja: 'slim', builder: 'sturdy', hook: 'reach', hunter: 'stalk', cannon: 'stout', berserker: 'brute', bard: 'lithe' }, // 캐릭터별 체형 (client/figure.js BODIES). 2026-10-24 재혁: 탱크는 통통한 쪽
  FIGURE_SCALE: 1.15, // 몸 전체 크기 배율 (1 이면 로봇과 키가 같아도 가늘어서 작아 보임). 판정 상자는 그대로
  // 1인칭 팔·무기 (client/viewmodel.js): 내 몸을 복제해 팔·무기만 따로 그림
  VM_FOV: 62, // 뷰모델 카메라 화각 (필드 화각과 따로: 넓은 화각에서도 팔이 늘어나 보이지 않게)
  VM_SCALE: 0.62, // 몸 크기 배율 (FIGURE_SCALE 에 곱함). 작을수록 팔이 화면을 덜 가림
  VM_POS: { default: [0, -0.16, -0.26], tank: [0, -0.2, -0.26], bard: [0.32, -0.14, -0.34], cannon: [0.24, -0.24, -0.45] }, // 어깨 높이 기준점 (카메라 기준: 오른쪽 +x, 위 +y, 뒤 +z). 캐릭터별로 덮어씀
  VM_SIZE: { tank: 0.7, builder: 0.58, bard: 0.7, cannon: 0.7, berserker: 0.75, hunter: 0.8, hook: 0.72 }, // 캐릭터별 크기 배율 (VM_SCALE 에 곱함). 굵은 팔은 화면을 많이 덮어서 작게 (광전사: 2026-10-27 어깨 넓고 팔뚝 굵어짐)
  VM_ROLL: { bard: 0.25 }, // 캐릭터별 화면 기울기 (라디안, + 면 반시계 방향). 바드 악기를 화면 아래에 가로로 눕혀 듦 (목이 조준점 쪽으로 안 감)
  VM_ARM_LOW: 1.0, // 내린 팔이 화면에선 이 각만큼 앞으로 든 팔 (라디안, π/2 = 정면)
  VM_ARM_OUT: 0.5, // 옆으로 벌린 각 배율
  VM_NARROW: 1.5, // 어깨 사이 거리 배율 (넓을수록 팔이 화면 양쪽 구석에서 나옴)
  VM_ELBOW_ADD: 1.35, // 내린 팔일 때 팔꿈치를 더 굽히는 각
  VM_BODY_FOLLOW: 0.45, // 몸통 숙임·비틂을 이만큼만 따라감
  VM_BOB: 0.018, // 걷기 흔들림 (칸)
  VM_BREATH: 0.004, // 숨쉬기 오르내림 (칸)
  VM_GUN_AIM: [1.45, 0.25], // 갈고리 장전 권총을 겨눌 때 [어깨 앞으로 든 각, 팔꿈치]
  VM_HOLD: ['bard', 'cannon'], // 두 손으로 무기를 잡는 캐릭터: 팔 각을 손이 잡을 점(VM_GRIP)에서 거꾸로 셈 (무기가 팔에 붙은 것처럼 안 보이게)
  // 손이 잡는 점 (무기 자기 좌표). 악기는 목이 +z, 앞면 +x. 대포는 포구가 +x, 위 +z
  VM_GRIP: {
    lute: { neck: [0.03, 0, 0.3], body: [0.05, 0, 0.03] },
    guitar: { neck: [0.02, 0, 0.3], body: [0.04, 0, 0.03] },
    cannon: { rear: [-0.2, 0.1, -0.12], front: [0.22, 0, -0.13] },
  },
  FIGURE_DIVE_FLIP: 1.6, // 바드 기타 꽂기: 떨어지는 동안 몸 전체를 앞으로 뒤집는 각 (타격 자세 허리 숙임과 합쳐 거꾸로)
  DIVE_LINE_R_MINE: 1.3, // 내 1인칭 꽂기면 속도선을 이 거리(칸) 밖에 (가까우면 화면을 덮는 흰 막대가 됨)
  DIVE_LINE_RATE: 60, // 바드 기타 꽂기: 1초에 생기는 속도선 수
  VM_DIVE_ROLL: 1.1, // 바드 기타 꽂기: 기타를 세워 머리(목 끝)가 화면 아래로 가게 돌리는 각 (라디안, 반시계)
  VM_DIVE_LIFT: 0.1, // 바드 기타 꽂기: 숙여도 화면 안에 보이게 기타·두 손을 들어 올리는 높이 (카메라 기준 칸)
  VM_SWEEP: 0.45, // 바드 메탈 기타 후려치기: 1인칭 기타가 화면을 가로질러 옮겨 가는 거리 (카메라 기준 칸)
  VM_CANNON_KICK_PITCH: 0.22, // 대포수 쏜 순간 1인칭 대포·두 손이 들리는 각
  VM_CANNON_KICK_BACK: 0.06, // 대포수 쏜 순간 1인칭 대포·두 손이 화면 쪽으로 밀리는 거리 (칸)
  VM_SPIN: ['berserker', 'hook'], // 몸 전체 돌기를 1인칭에도 그대로 (소용돌이·회전 베기·갈고리 스핀)
  VM_SHIELD: [0.55, 0.3, 0.12, 0.7], // 탱크 앞 방패 (방패 동작 동안) [크기 배율, 왼쪽으로(+y), 위로(+z), 비스듬히 돌림] (몸 좌표 칸·라디안)
  VM_CANNON: [0.7, 0.18, 0.22, -0.04], // 대포수 1인칭 대포 [크기 배율, 앞으로(+x), 왼쪽으로(+y), 위로(+z)] (몸 좌표 칸): 어깨 앞으로 내밀어 두 손이 잡게
  VM_PIP_SCALE: 0.65, // 대포 위 남은 포탄 크기 배율
  // 유령 투하 화면 (죽은 사람이 관전 중 1칸 블록을 떨어뜨림)
  GHOST_PIECE_OPACITY: 0.78, // 떨어지는 유령 블록 비침
  GHOST_PIECE_WHITEN: 0.3, // 떨어지는 유령 블록 색을 하얗게 섞는 정도 (유령 느낌)
  GHOST_AIM_RANGE: 60, // 조준 시선 최대 거리 (칸)
  GHOST_AIM_OPACITY: 0.6, // 조준 미리보기 큐브 비침
  GHOST_AIM_COOLDOWN_COLOR: 0x8a8a8a, // 쿨 중 미리보기 색
  GHOST_HINT_MS: 3500, // 처음 죽었을 때 '클릭: 블록 떨어뜨리기' 안내 시간
  PRACTICE_COMBO_SHOW_MS: 2500, // 연습 방: 끝난 허수아비 콤보 결과를 오른쪽에 남겨 두는 시간
  PRACTICE_SHOW_HEIGHT: 0.5, // 연습 방 콤보 기록: 이 높이(칸) 넘게 띄웠을 때만 '높이' 를 보임
  VM_STAR_HIDE_MS: 350, // 닌자 표창을 던진 뒤 왼손이 비어 있는 시간
  FIGURE_HORN_SEGS: 6, // 광전사 뿔 마디 수 (마디마다 같은 각으로 꺾여 매끈한 곡선)
  FIGURE_HORN_LEN: 0.42, // 뿔 한 개 길이 (칸, 몸 크기 배율 전)
  FIGURE_HORN_CURL: 2.1, // 뿔이 뿌리에서 끝까지 위로 휘는 각 합 (라디안, C 자)
  BERSERK_RAGE_PCT: 120, // 광전사 분노 화면: 피해 % 가 이만큼이면 가장 화남 (눈 충혈·눈썹·핏줄·빡침 표시·김. 몸 색은 안 바꿈: 플레이어 구분 우선)
  BERSERK_STEAM_RATE: 14,
  BARD_LUTE_SCALE: 1.35, // 류트 크기 배율 (가슴 앞에서 작아 보여서)
  TANK_TABARD_LEN: 0.36, // 탱크 허리 천 (플레이어 색) 길이
  TANK_PAD: 2.6, // 탱크 어깨 판 반지름 (팔 굵기 배)
  CANNON_SHORTS_GROW: 0.62, // 대포수 반바지 굵기 배율 (배 반지름 기준: 작을수록 배가 반바지 위로 둥글게 튀어나옴)
  NINJA_SCARF_LEN: 0.62, // 닌자 목도리 자락 길이 (플레이어 색, 등 뒤로 날림)
  HOOK_COAT_LEN: 0.42, // 갈고리 코트 자락 길이 (허리에서 무릎 위까지, 안감 플레이어 색)
  HUNTER_CAPE_LEN: 0.56, // 사냥꾼 털 망토 등 자락 길이 (겉 초록·안감 플레이어 색)
  METAL_PAD_R: 0.105, // 메탈 폼 징 재킷 어깨 패드 반지름 (몸 비율 전 칸)
  METAL_SOLE: 0.07, // 메탈 부츠 두꺼운 밑창 두께
  METAL_COLLAR: 0.11, // 메탈 재킷 세운 깃 높이
  BARD_HOOD_H: 0.2, // 음유시인 어깨 두건 깃 높이 (플레이어 색)
  BARD_CAPE_LEN: 0.62, // 음유시인 망토 길이 (몸 비율 전 칸, 어깨에서 무릎 위까지). 플레이어 색 (멀리서 누군지 보이게)
  BARD_HEADBANG_HZ: 2.2,
  BARD_GLIDE_TURNS_PER_S: 1.2,
  BARD_NOTE_COLOR: 0x6af08a, // 류트 음파 음표 색 (초록)
  BARD_AMP_COLOR: 0x7ab8ff, // 앰프 전격 음파 색 (푸른 번개)
  BARD_AMP_WAVE_MS: 160, // 앰프 음파 호가 나가는 간격
  BARD_AMP_WAVE_LIFE_MS: 450, // 호가 몸에서 사거리까지 퍼지는 시간 // 음유 천천히 낙하 때 빙글 도는 빠르기 (바퀴/초) // 바드 메탈 폼 대기 헤드뱅잉 (초당)
  BARD_FORM_POP_MS: 320, // 폼 전환 때 모히칸이 솟거나 모자가 얹히는 시간
  BERSERK_SPIN_TURNS_PER_S: 2.2, // R 소용돌이 화면 회전 빠르기 (바퀴/초)
  BERSERK_SPIN_FLAP: 2.2, // 소용돌이 중 수염·갈래·털 망토가 바깥으로 날리는 정도 (천 자락 들림 배율)
  BERSERK_DIZZY_S: 1.4, // 소용돌이 끝나고 어지러워 비틀 + 눈 빙글 + 머리 위 별 (초)
  BERSERK_SPIN_RING_COLOR: 0xff5030, // 소용돌이 범위 표시 (바닥 고리 + 도끼 궤적 원) // 가장 화났을 때 초당 김 수
  SHELL_SIZE: 0.2, // 화면 포탄 반지름 (판정 CANNON_SHELL_RADIUS 보다 작게: 잘 보이게만)
  SHELL_BIG_SIZE: 0.45, // 화면 대형 포탄 반지름
  CANNON_FLIP_PER_TURN: 4, // 대포수 공중 반동: recoil 이만큼마다 뒤로 한 바퀴 (공중 5 → 1바퀴, R 8 → 2바퀴)
  CANNON_FLIP_TURN_S: 0.45, // 한 바퀴 도는 시간 (초)
  CANNON_KICK: 0.18, // 쏠 때 대포가 어깨에서 뒤로 밀리는 거리 (칸, 몸 크기 배율 전)
  CANNON_KICK_MS: 220,
  FIGURE_SNIFF_EVERY: 3.2, // 사냥꾼이 가만히 있을 때 킁킁하는 간격 (초)
  FIGURE_SNIFF_LEN: 0.7, // 킁킁 한 번 길이 (초)
  FIGURE_BUILDER_SHIRT: [0x2c4a7a, 0xe8dcc0, 0xd8a838], // 건축가 작업 셔츠 체크 [바탕 남색, 굵은 줄 크림 (걷은 소매 테·깃도), 가는 줄 겨자]. 무늬라 어떤 플레이어 색(피부)과도 갈림 (2026-10-28 재혁)
  FIGURE_PLAID_REPEAT: 3, // 체크 무늬 반복 수 (원통 한 바퀴·한 마디에)
  FIGURE_HAT_TRIM: 0.55, // 건축가 안전모(플레이어 색) 능선·챙 테·띠 = 모자 색 × 이 값
  FIGURE_TRIM_DARK: 0.22, // 모자 색 밝기가 이보다 어두우면 (숯·자두 등) 테를 어둡게 말고 흰색 쪽으로
  FIGURE_TRIM_LIGHTEN: 0.5, // 그때 흰색으로 섞는 비율
  FIGURE_MUSCLE_SHADE: 0.6, // 광전사 근육 사이 홈 색 = 피부색 × 이 값
  FIGURE_EYE: 0.062, // 왕눈알 흰자 반지름 (칸, 몸 크기 배율 전)
  // 관절 스프링 (2026-10-27, FIGURE_FOLLOW 14/초 지수 추종 대신). w = 빠르기 (/초, 클수록 빨리 따라옴), damp = 감쇠비 (1 이면 안 넘침, 작을수록 출렁)
  // 다리는 발이 땅을 디뎌야 해서 단단하게, 팔·고개는 느슨하게 → 몸보다 늦게 따라와 흐느적 (TABS)
  FIGURE_SPRING: { body: { w: 22, damp: 0.7 }, neck: { w: 15, damp: 0.4 }, arm: { w: 19, damp: 0.45 }, leg: { w: 28, damp: 0.85 } },
  FIGURE_SPRING_FLIP: 1.6, // 2단 점프 공중제비 동안 스프링 빠르기 배율 (빨리 웅크려야 보임)
  FIGURE_SPRING_STEP: 0.008, // 스프링 계산 한 걸음 최대 (초). 프레임이 길어도 안 튀게
  FIGURE_LAG_ARM: 0.8, // 몸 가속도(칸/초²) 1 당 팔이 뒤로 처지는 힘 (빨라지면 팔이 뒤로, 멈추면 앞으로 쏠림)
  FIGURE_LAG_NECK: 0.35, // 같은 것, 고개
  FIGURE_LAG_ACC_MAX: 80, // 가속도 상한 (칸/초², 순간이동·대시 첫 프레임에 팔이 날아가지 않게)
  FIGURE_FLAP_SPRING: { w: 9, damp: 0.35 }, // 천 자락(망토·수염·갈래)이 속도를 따라가는 스프링: 멈추면 앞으로 넘어갔다 내려옴
  FIGURE_DROP_FOLLOW: 25, // 엉덩이 높이가 땅↔공중 사이에서 바뀔 때 따라가는 빠르기 (/초, 뚝 끊김 방지)
  FIGURE_SETTLE: 10, // 도는 동작이 끝나고 가장 가까운 한 바퀴 각으로 돌아가는 빠르기 (/초)
  // 액티브 래그돌 (2026-10-27 시범, client/ragdoll.js · ragdoll-math.js · cannon-es). 판정은 서버 AABB 그대로, 몸 모습만 클라 물리.
  // 평소·공격: 관절 모터가 지금 자세(figureAnim)를 세게 따라감 / 맞음·기절·낙사: 모터 힘이 빠져 흐물흐물 (TABS)
  RAGDOLL_CHARS: ['tank', 'ninja', 'builder', 'hook', 'hunter', 'cannon', 'berserker', 'bard'], // 래그돌로 그리는 캐릭터 (빈 배열이면 끔). 1인칭 내 몸은 늘 끔 (viewmodel 이 관절을 베낌). 2026-10-27 재혁: 8명 전부
  RAGDOLL_STEP: 1 / 120, // 물리 고정 걸음 (초)
  RAGDOLL_MAX_STEPS: 6, // 한 프레임에 최대 걸음 수 (느린 프레임에서 따라잡기 상한)
  RAGDOLL_GRAVITY: 20, // 몸 물리 중력 (칸/초², 서버 GRAVITY 와 같게)
  RAGDOLL_KP: 2500, // 관절 모터: 목표 자세와의 각 차이 1 라디안당 각가속도 (/초²). 클수록 자세를 세게 지킴
  RAGDOLL_KD: 80, // 관절 모터 감쇠 (/초)
  RAGDOLL_ROOT_KP: 1800, // 골반이 서버(보간) 위치를 따라가는 세기 (/초²)
  RAGDOLL_ROOT_KD: 85, // 같은 것 감쇠 (/초)
  RAGDOLL_ROOT_SHARE: 0.12, // 힘이 다 빠졌을 때 팔다리도 골반 끌어당김을 이만큼 나눠 받음 (골반 혼자 몸 전체를 끌면 출렁여 깨짐)
  RAGDOLL_LIN_KP: 2500, // 몸통·팔다리 조각이 자기 목표 위치로 가는 세기 (/초², 모터 세기를 곱함). 세면 자세가 그대로 읽힘
  RAGDOLL_LIN_KD: 80, // 같은 것 감쇠 (/초)
  RAGDOLL_COLLIDE_BELOW: 0.6, // 모터 세기가 이보다 약할 때만 바닥·블록과 부딪힘 (맞음·경직·낙사)
  RAGDOLL_ITERATIONS: 15, // 물리 풀이 반복 (클수록 관절이 덜 벌어짐)
  RAGDOLL_MAX_DRIFT: 0.35, // 골반이 판정 위치에서 이보다 (칸) 멀어지면 몸 전체를 순간 맞춤
  RAGDOLL_MOTOR_ATTACK: 1.6, // 공격 중 모터 세기 배율 (예고·타격이 읽히게)
  RAGDOLL_POSE_SNAP: 0.5, // 이모트·승리 포즈 동안 화면 자세를 목표 쪽으로 섞는 비율 (모터도 공격만큼 세게: 포즈가 흐물거리지 않고 또렷하게)
  RAGDOLL_ATTACK_SNAP: 0.6, // 공격 준비·타격 동안 화면 자세를 목표 자세 쪽으로 이만큼 섞음 (0 물리 그대로 ~ 1 목표 그대로, 타격이 확 튀게)
  RAGDOLL_HIT_MOTOR: 0.004, // 맞은 순간 모터 세기 (몸이 포개짐) → RAGDOLL_HIT_RECOVER_S 동안 1 로
  RAGDOLL_HIT_RECOVER_S: 0.9,
  RAGDOLL_STUN_MOTOR: 0.002, // 경직(날아감) 중 모터 세기 (팔다리 휘날림)
  RAGDOLL_STUN_RECOVER_S: 0.85, // 경직이 풀리고 모터가 다시 세지는 시간 (일어나기)
  RAGDOLL_FALL_MOTOR: 0.002, // 바닥 아래로 떨어지는 중 (낙사) 모터 세기
  RAGDOLL_FALL_Z: -0.4, // 발이 이보다 낮으면 낙사 중으로 봄 (칸)
  RAGDOLL_HIT_IMPULSE: 7, // 맞을 때 가슴·머리에 주는 충격 (세기 1, 질량 1 당 칸/초)
  RAGDOLL_HIT_UP: 0.45, // 충격의 위쪽 비율
  RAGDOLL_SLUMP: 0.55, // 힘이 다 빠지면 골반이 판정 위치보다 이만큼 (칸) 아래로 처질 수 있음 → 바닥에 쓰러져 누움, 힘이 돌아오면 일어남
  RAGDOLL_LIMP_LIFT: 0.25, // 다 처졌을 때 골반이 받는 중력 보정 비율 (0 이면 그대로 떨어짐)
  RAGDOLL_WEIGHT: { drum: 1.6, brute: 1.3, stout: 1.3, sturdy: 1.25, lean: 1, lithe: 0.85, reach: 1.15, stalk: 0.95, slim: 0.75 }, // 체형별 무게 (FIGURE_BODY). 무거울수록 맞을 때 덜 튐 (탱크 무겁게, 닌자 가볍게)
  // 관절 각도 제한 (원뿔): rotY = 가운데 방향을 figure 관절 rotation.y 부호로 기울인 각, cone = 가운데에서 벗어날 수 있는 각, twist = 비틀림 한계 (없으면 제한 없음).
  // 무릎은 뒤로만, 팔꿈치·엉덩이는 앞으로 많이 (평소 자세 범위는 다 들어가게 넉넉히). 어깨는 제한 없음 (팔 휘두름)
  RAGDOLL_LIMITS: {
    waist: { up: true, rotY: 0.2, cone: 0.9, twist: 1.1 },
    neck: { up: true, rotY: 0, cone: 0.9, twist: 0.9 },
    elbow: { rotY: -1.3, cone: 1.45 },
    knee: { rotY: 1.25, cone: 1.35 },
    hip: { rotY: -0.7, cone: 1.45 },
  },
  RAGDOLL_MASS: { pelvis: 3, chest: 4, head: 1.2, upper: 0.7, fore: 0.5, thigh: 1.4, shin: 1 }, // 몸 조각 질량 비율
  RAGDOLL_DAMPING: 0.05, // 조각마다 공기 저항 (선·각 모두)
  RAGDOLL_FRICTION: 0.6, // 바닥·블록 마찰
  RAGDOLL_GROUND_REACH: 2, // 래그돌 둘레 이 칸 안의 단단한 칸만 물리 상자로 (가까운 것만)
  FIGURE_ARM_SPREAD: 0.22, // 가만히 있을 때 팔을 옆으로 벌린 각 (라디안)
  FIGURE_WALK_LEG: 0.7, // 걸을 때 허벅지를 앞뒤로 드는 최대 각
  FIGURE_WALK_KNEE: 0.9, // 걸을 때 무릎을 굽히는 최대 각
  FIGURE_WALK_ARM: 0.6, // 걸을 때 팔을 앞뒤로 흔드는 최대 각
  FIGURE_RUN_LEAN: 0.18, // 최고 속도로 걸을 때 허리를 앞으로 숙이는 각
  FIGURE_HELD_SCALE: 0.7, // 손에 든 것 크기 배율 (팔이 가늘어서)
  FIGURE_RUN_TWIST: 0.2, // 달릴 때 어깨를 다리 반대로 비트는 각
  FIGURE_HIP_TWIST: 0.4, // 공격 동작의 허리 비틂(waistRoll) 중 골반(다리째)이 나눠 받는 비율. 허리만 돌면 윗몸만 따로 노는 것처럼 보임 (2026-10-27 재혁: 광전사 상체가 따로 놂)
  FIGURE_HIP_TWIST_FOLLOW: 8, // 공격이 시작·끝날 때 그 나눔이 켜지고 꺼지는 빠르기 (/초)
  FIGURE_RUN_ELBOW: 0.9, // 최고 속도로 달릴 때 팔꿈치를 더 굽히는 각 (팔 펌프)
  // 캐릭터별 걸음걸이 (2026-10-28, figure.js gaitPose). 빠진 칸은 FIGURE_GAIT_DEFAULT
  // stride 보폭(허벅지 각 배율) · freq 발 빠르기 배율 (render.js 걸음 위상) · lean 더 숙임 · neck 고개 (+ 숙임) · arm 팔 흔들기 배율 · armBack 팔을 뒤로 젖힘 (닌자) · elbow 팔꿈치 더 굽힘
  // knee 무릎 배율 · crouch 늘 굽힌 무릎 (웅크림) · wide 다리 벌림 · bounce 엉덩이 오르내림 (칸, 디딜 때 가장 낮음) · sway 옆으로 흔들 (뒤뚱) · twist 어깨 비틂 배율 · shrug 걸음마다 어깨·윗몸 들썩 (성난 황소)
  FIGURE_GAIT_DEFAULT: { stride: 1, freq: 1, lean: 0, neck: 0, arm: 1, armBack: 0, elbow: 0, knee: 1, crouch: 0, wide: 0, bounce: 0.02, sway: 0, twist: 1, shrug: 0 },
  FIGURE_GAIT: {
    tank: { stride: 0.75, freq: 0.8, lean: -0.05, arm: 0.55, knee: 0.7, wide: 0.12, bounce: 0.07, sway: 0.1, twist: 0.6 }, // 쿵쿵: 짧고 느린 보폭, 다리 벌리고 디딜 때 푹 꺼짐
    ninja: { stride: 1.15, freq: 1.15, lean: 0.38, neck: -0.15, arm: 0.15, armBack: 1.25, elbow: -0.9, knee: 1.15, bounce: 0.015, twist: 0.4 }, // 숙이고 팔을 뒤로 쭉
    cannon: { stride: 0.55, freq: 1.5, lean: 0, arm: 0.9, knee: 0.75, bounce: 0.04, sway: 0.06, twist: 0.6 }, // 종종: 짧은 다리로 빠르게
    berserker: { stride: 1, freq: 0.95, lean: 0.3, neck: -0.2, arm: 1.1, elbow: 0.4, knee: 1, wide: 0.06, bounce: 0.05, sway: 0.05, twist: 1.3, shrug: 0.32 }, // 성난 황소: 숙이고 걸음마다 어깨 들썩
    hunter: { stride: 0.75, freq: 0.95, lean: 0.32, neck: -0.25, arm: 0.45, elbow: 0.5, knee: 0.9, crouch: 0.45, bounce: 0.01, twist: 0.5 }, // 웅크려 살금
    builder: { stride: 0.85, freq: 0.88, lean: 0.12, neck: 0.1, arm: 0.8, knee: 0.85, bounce: 0.05, sway: 0.04 }, // 터벅터벅: 고개 살짝 숙이고 무겁게
    hook: { stride: 0.8, freq: 0.9, lean: -0.02, arm: 0.7, knee: 0.6, wide: 0.16, bounce: 0.03, sway: 0.22, twist: 0.5 }, // 뒤뚱 해적: 다리 벌리고 옆으로 흔들
    bard: { stride: 1.05, freq: 1.12, lean: 0, neck: -0.08, arm: 1, knee: 1.2, bounce: 0.09, sway: 0.04 }, // 경쾌: 통통 튀며
  },
  FIGURE_ACC_LEAN: { fwd: 0.012, side: 0.01, max: 0.35 }, // 가속·멈춤 (|앞뒤 가속도|) 만큼 앞으로, 옆 가속도 (방향 전환) 만큼 그쪽으로 몸 기울임 (칸/초² 당 라디안, 최대)
  // 공중 자세 (figure.js airPose): 위아래 속도 vz 가 이 값을 넘으면 오름·내려옴 자세가 다 섞임 (그 사이는 정점 자세)
  FIGURE_AIR_VZ: 3,
  FIGURE_AIR_DASH: { s: 0.2, tilt: 0.9 }, // 공중 대시 슈퍼맨 자세 시간 (초) · 몸 전체 앞으로 눕는 각
  FIGURE_BUMP: { decel: 25, minSpeed: 2, kick: 0.35, cooldown: 0.4, reach: 0.25 }, // 부딪힘: 땅에서 이 감속(칸/초²)보다 급히 멈추고 가던 쪽 reach 칸 안에 블록·사람이 있으면 휘청 (kick = 휘청 빠르기, 속도 1칸/초당)
  // 평소 버릇 (figure.js idlePose): 가만히 after 초 지나면 every 초마다 len 초 동안 캐릭터별 짧은 동작. 사냥꾼은 킁킁 (FIGURE_SNIFF_*)
  FIGURE_IDLE_AFTER: 2.5,
  FIGURE_IDLE: {
    tank: { kind: 'tap', every: 4.5, len: 1.1 }, // 등 방패 툭툭
    ninja: { kind: 'twirl', every: 3.8, len: 1.2 }, // 단검 손에서 돌리기
    builder: { kind: 'shoulder', every: 5, len: 1.4 }, // 망치 어깨에 척
    hook: { kind: 'polish', every: 4.2, len: 1.3 }, // 갈고리 닦기
    cannon: { kind: 'fiddle', every: 4, len: 1.2 }, // 어깨 포탄 만지작
    berserker: { kind: 'flex', every: 4.4, len: 1.5 }, // 씩씩 힘주고 목 꺾기
    bard: { kind: 'pluck', every: 3.6, len: 1 }, // 줄 튕기며 고개 까딱
  },
  FIGURE_HIT_LEAN: 0.35, // 맞은 순간 허리가 밀린 쪽으로 꺾이는 각 (세기 1 기준)
  FIGURE_HIT_KICK: 6, // 히트스톱이 끝나고 밀린 쪽으로 더 튕기는 빠르기 (라디안/초, 세기 1 기준)
  FIGURE_HIT_SPRING_K: 70, // 휘청 스프링 세기 (클수록 빨리 흔들림)
  FIGURE_HIT_SPRING_DAMP: 7, // 휘청 스프링 감쇠 (클수록 빨리 멈춤)
  FIGURE_HIT_HEAVY: 1.5, // 무거운 공격 (망치·치명타·폭탄 등) 휘청 세기
  FIGURE_HIT_FINISH: 2.2, // 콤보 마무리 타 휘청 세기
  // 건축가 블록 화면 (2026-10-30 재혁 시안 A '공사장 나무 상자'): client/bblocks.js 가 그리고, 칸 모양·연출 곡선 순수 계산은 shared/bblock-look.js
  // 바탕(판자·쇠 모서리)은 고정 색, 공사 줄무늬 띠만 주인 색. 종류마다: 벽 = 가로 판자·대각 버팀목·가운데 띠, 발판 기둥 = 세로 판자·윗가장자리 띠,
  // 3타 = 작은 상자·세로 띠, R = 어두운 나무·넓은 띠·위 주황 빛 판 (터질 때가 가까울수록 세짐). 크기는 칸 비율
  BB_LOOK: {
    box: { wall: 0.96, pad: 0.96, third: 0.84, big: 0.98 }, // 상자 한 변
    corner: 0.11, // 쇠 모서리 굵기
    band: { wall: { z: 0.62, h: 0.18 }, pad: { z: 0.9, h: 0.1 }, third: { w: 0.16 }, big: { z: 0.5, h: 0.32 } }, // 띠: z = 가운데 높이(상자 높이 비율), h = 두께, third 는 세로 띠 폭
    plate: { size: 0.5, h: 0.06 }, // R 위 빛 판
    wood: 0xc99a5c, woodPad: 0xb98a50, woodBig: 0x6e432a, steel: 0x4a4f5a,
    plateCold: 0x8a2a0c, plateHot: 0xff7a20, plateWhite: 0xfff2c0, // R 빛 판: 평소 → 터지기 직전
    stripeRepeat: [1.6, 0.3], // 띠 줄무늬 반복 (띠가 넓고 낮아 세로로 덜 눌리게)
  },
  BB_BLINK_MS: 1500, // 사라지기 이만큼 전부터 하얗게 깜빡임 (빨라짐)
  BB_CRACK_MS: 3500, // 사라지기 이만큼 전부터 금이 가운데서 점점 퍼짐
  BB_COLLAPSE_MS: 420, // 수명이 끝나면 이 동안 부서지며 내려앉음 (납작·기울며 가라앉음 + 판자 조각)
  BB_SHARDS: { wall: 9, pad: 9, third: 7, big: 16, collapse: 6, max: 320, life: 1.2, speed: 5.5, size: [0.3, 0.08, 0.035] }, // 터질 때 판자 조각 (칸마다), 최대 동시, 수명 초, 빠르기, 크기
  BB_LOW_FX: 0.4, // 그래픽 낮춤: 조각·먼지 수 비율
  BB_BIG_TICKS: [0, 0.32, 0.55, 0.7, 0.81, 0.89, 0.95], // R 준비 동안 째깍 시각 (BUILDER_BIG_FUSE_MS 비율, 점점 빠르게)
  BB_POP_MS: 260, // 생길 때 바닥에서 솟아오르는 시간 (살짝 넘쳤다 돌아옴)
  BB_CHAIN_STEP_MS: 50, // 연쇄 폭발: 칸마다 이 간격으로 차례로 터짐
  BB_BIG_SWELL: 0.18, // 대폭발 블록이 터지기 직전까지 부푸는 비율
  BB_TINT: 0.08, // 띠 주인 색에 흰색을 섞는 비율 (어두운 색도 줄무늬가 보이게, 너무 섞으면 바래 보임)
  STAR_FLY_MS: 100, // 닌자 표창이 날아가 보이는 시간 (판정은 즉시, 맞는 효과는 표창이 닿을 때)
  EMPOWER_GLOW: 0x6a2ad0, // 닌자 R 강화 중 몸이 깜빡이는 빛 (보라)
  // 탱크 화면
  ARMOR_SHINE: 0x8a96a8, // 아머 중 몸이 금속처럼 번쩍이는 빛
  FIGURE_HIT_ARMOR: 0.15, // 아머로 버틴 타: 휘청 세기 (얼굴만 찡그리는 정도)
  FIGURE_HIT_ARMOR_BREAK: 2.4, // 아머가 깨진 타: 휘청 세기 (크게)
  QUAKE_RISE_MS: 160, // 탱크 R 고리 땅이 솟는 시간 (넘쳤다 돌아옴)
  QUAKE_SINK_MS: 280, // 가라앉는 시간
  QUAKE_FALL_GRACE_MS: 1000, // 솟는 땅 화면 안전장치: 솟은 뒤 TANK_RING_MS + 이만큼 지나도 가라앉힘 이벤트가 없으면 화면에서 가라앉힘 (유령 블록 방지)
  QUAKE_SINK_SHAKE: 0.07, // 가라앉는 동안 떨림 (칸)
  QUAKE_COLOR: 0x9c8468, // 솟는 땅 색 (흙)
  // 갈고리 화면
  HOOK_FLY_MS: 110, // 갈고리 머리가 날아가 닿는 시간. 판정도 이때 (2026-10-26: 던진 방향·닿는 순간 위치로, 그 사이 옆으로 피하면 빗나감)
  HOOK_HOLD_MS: 380, // 닿은 뒤 사슬이 걸려 있는 시간 (끌려오는 동안)
  HOOK_GRAB_SWING_R: 0.9, // R: 뽑은 블록을 머리 위에서 돌리는 반지름 (칸)
  HOOK_GRAB_SHAKE: 0.18, // R: 뽑히기 전(HOOK_GRAB_MS) 덩어리가 제자리에서 덜덜 떠는 폭 (칸, 끝으로 갈수록 세게)
  HOOK_GRAB_SHAKE_PART: 0.5, // R: HOOK_GRAB_MS 중 앞쪽 이만큼은 제자리에서 덜덜, 나머지는 머리 위로 끌려옴 (그 뒤 서버가 내려찍음)
  HOOK_GRAB_FP_OPACITY: 0.4, // R: 내 1인칭이면 머리 위 덩어리를 이만큼만 (화면을 덮지 않게)
  HOOK_GRAB_FP_RAISE: 1.2, // R: 내 1인칭이면 덩어리를 이만큼 더 높이 (칸)
  HOOK_SLAM_FLY_MS: 150,
  HOOK_PULL_SLIDE_MS: 200, // 끌려오는 쪽: 갈고리가 닿을 때까지 제자리, 그 뒤 이 시간 동안 질질 끌려옴 (판정·위치는 서버가 즉시)
  BLOCK_PULSE_MS: 260, // 블록이 움직이거나 바뀌는 순간 그 칸이 번쩍 부풀었다 사라지는 시간 (render.js blockPulse)
  SPIN_ARC_MS: 380, // 갈고리 공중 스핀: 갈고리 끝이 그리는 원이 남는 시간
  WARN_TAIL_MS: 80, // 바닥 예고를 서버 예고 시간보다 조금 더 (쾅 이벤트가 오는 지연만큼, 예고가 먼저 꺼지지 않게)
  MARK_BLINK_MS: 1200, // 사냥꾼 표식이 사라지기 전 깜빡이기 시작하는 남은 시간
  MARK_BLINK_PERIOD_MS: 140, // 표식 깜빡이는 간격
  HUNT_EYE_COLOR: 0xff4030, // 사냥꾼의 눈: 블록 뒤 표식 대상 몸 색
  ARROW_FLY_MS: 90, // 석궁 화살이 날아가는 시간 (판정은 즉시, 애니만)
  ARROW_STUCK_MS: 1500, // 블록에 막힌 화살이 박혀 남는 시간
  ARROW_TRAIL_MS: 220, // 화살 지나간 빨간 줄
  ULT_FAIL_MS: 900, // R 을 못 썼을 때 R 칸에 짧은 이유가 보이는 시간
  ULT_FAIL_SHAKE_MS: 350, // R 칸이 빨갛게 흔들리는 시간
  CAST_DROP_BLINK_MS: 400, // 기억해 둔 F·R 이 버려졌을 때 칸이 깜빡이는 시간
  BLOCK_JOLT: 0.1, // 옆 블록이 터지거나 뽑히거나 박힐 때 들썩이는 높이 (칸)
  LAND_JOLT: 0.06, // 테트리미노가 내려앉을 때 눌리는 깊이
  ROPE_RADIUS: 0.045, // 갈고리 밧줄 굵기 (칸)
  ROPE_COLOR: 0xc8a36a, // 밧줄 색 (삼베)
  ROPE_TWISTS: 6, // 1칸당 꼰 무늬 반복
  ROPE_SAG: 0.18, // 날아가는 동안 늘어지는 정도 (길이 비율)
  ROPE_WOBBLE: 0.16, // 감길 때 출렁이는 폭 (칸) // R: 머리 위에서 박힐 자리까지 내려찍는 시간
  BLINK_SLIDE_MS: 120, // 닌자 순간 베기: 판정은 즉시지만 화면에선 몸이 from → to 로 이 시간 동안 미끄러져 감 (카메라도 따라감)
  BLINK_GHOST_MS: 30, // 미끄러지는 동안 이 간격으로 잔상
  BLINK_GHOST_FADE_MS: 240, // 잔상이 사라지는 시간
  FIGURE_ACT_MAX_S: 4, // 공격 동작이 이보다 오래 남으면 버림 (안전장치: 끝나지 않는 동작)
  FIGURE_STRIKE_S: 0.07, // 공격 타격 자세로 튀는 시간 (아주 짧게). 그 뒤 회복은 평타 표의 rec
  FIGURE_SWING_WAIT_S: 0.4, // 준비가 끝나고 이만큼 더 기다려도 판정(swing)이 안 오면 동작을 접음 (캔슬·끊김)
  FIGURE_BROKEN_S: 0.55, // 끊긴 공격(interrupt): 팔이 튕기고 자세가 무너졌다 돌아오는 시간
  FIGURE_HIT_COUNTER: 1.6, // 카운터히트(counter 이벤트)로 맞으면 휘청 세기에 곱함
  COUNTER_TEXT_MS: 700, // 내가 넣거나 당한 카운터 'COUNTER' 글자 (콤보 글자 위)
  FIGURE_TUMBLE_MIN_SPEED: 5.5, // 경직 중 이 속도(칸/초)보다 빠르게 날아가면 몸을 말고 구름 (밀치기 한 방은 안 구름)
  FIGURE_TUMBLE_SPEED: 13, // 구르는 빠르기 (라디안/초)
  FIGURE_RECOVER_S: 0.45, // 경직이 풀리고 쪼그렸다 일어나는 시간 (초)
  FIGURE_LAND_S: 0.3, // 착지 무릎 굽힘이 풀리는 시간 (초)
  FIGURE_LAND_KNEE: 1, // 착지 무릎 굽힘 세기 (가장 세게 떨어졌을 때)
  FIGURE_LAND_FALL_VZ: 9, // 이 속도(칸/초)로 떨어지면 착지 무릎을 가장 크게 굽힘
  FIGURE_FLIP_S: 0.5, // 2단 점프 앞 공중제비 한 바퀴 시간 (초)
  ROBOT_PUNCH_MS: 450, // 밀치기 때 펀치 동작을 보여주는 시간 // 캐릭터 손에 든 아이템 모델 크기
  ITEM_MODEL_SIZE: 0.55, // 필드 아이템 모델 크기 (가장 긴 변, 칸)
  BOMB_MODEL_SIZE: 0.55, // 놓인 폭탄 모델 크기
  THROWN_BLINK_MS: 120, // 떨어지는 설치 블록 깜빡임 간격
  // 승리 연출: 판이 끝나고 WIN_BANNER_MS 동안 모두의 카메라가 승자 정면으로
  VICTORY_FLY_S: 0.7, // 카메라가 날아가는 시간 (초)
  VICTORY_CLOSEUP_MS: 2800, // 판 끝 승자 클로즈업 (마지막 킬 슬로모션 뒤, 결과 표 전). 카메라가 승자 앞으로 날아가 승리 포즈를 보여 줌 (shared/victory.js)
  VICTORY_CLOSEUP_REDUCED_MS: 1500, // 움직임 줄이기·그래픽 낮춤: 카메라가 날아가지 않고 바로 승자 앞, 짧게
  VICTORY_DIST: 2.8, // 승자 앞 거리 (칸)
  VICTORY_UP: 1.4, // 발 위 높이 (칸)
  VICTORY_LOOK_UP: 0.45, // 승리 카메라가 승자 가슴보다 이만큼 위를 봄 (칸): 승자가 화면 아래쪽 2/3 에 오고 머리 위가 '승리!' 큰 글씨 자리
  VICTORY_SPIN: 5, // 춤: 빙글 도는 빠르기 (라디안/초)
  VICTORY_HOP: 0.35, // 춤: 깡충 높이 (칸)
  VICTORY_HOP_FREQ: 7, // 춤: 깡충 빠르기
  CONFETTI_RATE: 8, // 색종이 터지는 횟수 (초당)
  OUTLINE_THICKNESS: 0.0065, // 툰 외곽선 굵기 (화면 비율). 설정에서 끌 수 있음
  SHADOW_MAP_SIZE: 1024, // 그림자 해상도 (설정에서 끌 수 있음)
  // 콩 애니메이션 (화면만)
  ANIM_WALK_FREQ: 3.2, // 걸음 위상이 도는 빠르기 (속도 1칸/초당 라디안)
  ANIM_BOB: 0.07, // 걸을 때 통통 튀는 높이 (칸)
  ANIM_LEAN: 0.14, // 최고 속도로 걸을 때 앞으로 기울기 (라디안)
  ANIM_AIR_VZ: 0.8, // 위아래 속도가 이보다 크면 공중으로 봄 (칸/초)
  ANIM_TUMBLE_MIN_SPEED: 3, // 경직 중 이 속도(칸/초)보다 빠르게 날아가면 구름
  ANIM_TUMBLE_SPEED: 11, // 구르는 빠르기 (라디안/초)
  ANIM_SMOOTH: 12, // 속도·구르기 복귀를 따라가는 빠르기 (클수록 즉각)
  // 위치 보간 (client/interp.js). 2026-10-27: 최신 스냅샷을 지수로 쫓던 것 → 두 스냅샷 사이 보간 (60fps 에서 프레임마다 속도가 ±46% 들쭉날쭉하던 것)
  INTERP_DELAY_MS: 50, // 남의 캐릭터: 서버 시각보다 이만큼 늦게 그림 (1틱 33ms + 도착 흔들림 여유)
  INTERP_DELAY_SELF_MS: 35, // 내 캐릭터: 덜 늦게 (조작감). 다음 스냅샷이 늦으면 INTERP_EXTRAP_MS 까지 내다봄
  INTERP_EXTRAP_MS: 40, // 다음 스냅샷이 아직 안 왔을 때 마지막 속도로 더 가는 최대 시간
  INTERP_CLOCK_SAMPLES: 30, // 서버 시각 추정에 쓰는 최근 스냅샷 수 (가장 덜 늦게 온 것을 기준으로)
  INTERP_CLOCK_SLEW: 0.1, // 화면 시계가 목표와 어긋났을 때 프레임 시간의 이 비율까지만 빠르게·느리게 흐름
  INTERP_RESET_MS: 1000, // 화면 시계가 이보다 어긋나면 (탭 멈춤·새 방) 바로 맞춤
  INTERP_TELEPORT: 3, // 스냅샷 사이 이보다 멀리 (칸) 움직이면 보간 안 하고 바로 (부활·순간이동)
  INTERP_TRACK_LEN: 12, // 플레이어마다 기억하는 스냅샷 수
  ANIM_WALK_MIN_SPEED: 0.6, // 이 속도(칸/초)보다 빨라야 걷는 동작
  ANIM_STEP: 0.09, // 걸을 때 발을 앞뒤로 내미는 거리 (칸)
  ANIM_SWAY: 0.06, // 걸을 때 좌우로 흔들리는 각도 (라디안)
  ANIM_STRETCH: 0.12, // 위로 뛰어오를 때 늘어나는 비율
  ANIM_LAND_SQUASH: 0.2, // 착지 순간 납작해지는 비율
  ANIM_LAND_S: 0.2, // 착지 찌그러짐이 풀리는 시간 (초)
  // 관전 카메라 (2026-10-23 재혁: 마우스로 둘레를 돌리고 휠로 거리, 블록이 가리면 앞으로 당김)
  SPECTATE_DIST: 4.5, // 따라가기: 처음 거리 (칸)
  SPECTATE_DIST_MIN: 2, // 휠로 당길 수 있는 가장 가까운 거리
  SPECTATE_DIST_MAX: 12, // 휠로 멀어질 수 있는 가장 먼 거리
  SPECTATE_LOOK_UP: 1, // 따라가기: 발 위로 이만큼 높은 점을 바라봄 (칸)
  SPECTATE_CAM_MARGIN: 0.3, // 블록이 가리면 막힌 칸에서 이만큼 앞에 카메라
  SPECTATE_OVERVIEW_DIST: 14, // 전체 보기: 처음 거리 (필드 가운데에서)
  SPECTATE_OVERVIEW_MIN: 6,
  SPECTATE_OVERVIEW_MAX: 24,
  SPECTATE_OVERVIEW_FOLLOW: 2, // 전체 보기가 살아 있는 사람들 높이로 따라 올라가는 빠르기 (1/초)
  SPECTATE_ZOOM_STEP: 1.15, // 휠 한 칸에 거리를 이만큼 곱하거나 나눔
  BEAM_RADIUS: 0.05, // 조종 빛줄기 굵기 (칸)
  BEAM_OPACITY: 0.35, // 조종 빛줄기 기본 불투명도
  BEAM_PULSE: 0.2, // 조종 빛줄기 깜빡임 폭
  KILLFEED_MS: 6000, // 오른쪽 위 킬 알림이 떠 있는 시간
  KILLFEED_MAX: 5, // 킬 알림 최대 줄 수
  INPUT_SEND_RATE: 30, // 입력 전송 Hz
  // ---- 접속 상태 (2026-10-27 재혁: 렉·핑을 모름) ----
  // 서버 지키기 (2026-10-30 코드 감사): 메시지 크기·빈도 제한, 긴 글자는 먼저 자름
  NET_MAX_PAYLOAD_BYTES: 64 * 1024, // WebSocket 메시지 하나 최대 (넘으면 그 연결 끊음, ws 기본은 100MB). 가장 큰 화면→서버 메시지도 1KB 안쪽
  NET_MSG_RATE: 120, // 연결 하나가 1초에 보낼 수 있는 메시지 (입력 30Hz + 핑·행동). 넘는 건 버림
  NET_MSG_BURST: 60, // 잠깐 몰려도 이만큼은 받음 (토큰 통 크기)
  TEXT_RAW_MAX: 256, // 이름·방 이름 같은 글자는 정리하기 전에 이 길이로 먼저 자름 (1천만 자 이름 하나에 틱 1.1~1.6초 멈췄음)
  NET_DEFLATE_MIN_BYTES: 1024, // 이보다 큰 메시지만 압축 (스냅샷). 핑·입력 같은 작은 건 그대로
  NET_DEFLATE_LEVEL: 1, // zlib 압축 수준 (1 = 가장 빠름: 8명 스냅샷 하나 약 0.12ms, 원래 크기의 약 22%)
  NET_PING_MS: 1000, // 화면이 서버에 ping 보내는 간격
  NET_LOAD_DECAY: 0.95, // 서버 틱 일한 시간 최댓값이 틱마다 줄어드는 비율 (pong 의 workMs)
  NET_PING_WARN_MS: 150, // 핑이 이보다 높으면 렉 알림 (2026-10-27: 한 번 튄 건 무시 — 연속 NET_PING_REPEAT 번일 때만. 화면 멈칫으로 pong 처리가 늦은 것과 구분)
  NET_PING_SPIKE_MULT: 2.5, // 핑이 최근 평균의 이 배 넘게 튀면 렉 알림 (이것도 연속 NET_PING_REPEAT 번)
  NET_PING_REPEAT: 2,
  NET_SNAPSHOT_GAP_MS: 250, // 스냅샷 사이가 이만큼 비면 "끊김" 후보: NET_GAP_WINDOW_MS 안에 NET_GAP_REPEAT 번이면 알림 (로컬 한 번 흔들림은 무시, 2026-10-27 B 헤드리스 핑 5ms 에 노랑)
  NET_GAP_REPEAT: 2,
  NET_GAP_WINDOW_MS: 3000,
  NET_FRAME_WINDOW: 30, // 화면 프레임 간격을 이만큼 (최근 프레임 수) 보고 가장 긴 것 (또는 지금 프레임이 안 끝난 시간) 을 '화면 멈칫' 으로 핑·스냅샷 빈 시간에서 빼고 판정 (느린 화면은 네트워크 렉이 아님, 표시 핑은 그대로)
  NET_SNAPSHOT_STALL_MS: 600, // 한 번이라도 이만큼 비면 (또는 지금 이만큼 안 오면) 바로 "끊김"
  NET_SERVER_SLOW_MS: 20, // 서버 틱 한 번 일한 시간이 이보다 길면 "서버 느림" (틱 33ms)
  NET_SERVER_BEHIND_MS: 100, // 서버 틱이 정해진 시각보다 이만큼 밀리면 "서버 느림" (타이머가 조금씩 늦는 건 무시)
  NET_WARN_HOLD_MS: 1500, // 알림을 이만큼 보여 줌
  // ---- KO 연출 (2026-10-27 재혁) ----
  FINAL_KILL_WINDOW_MS: 500, // 판이 끝나기 이만큼 안의 죽음이 "마지막 킬" (서버 finalKill 이벤트)
  // 화면 (client/ko.js). 그래픽 낮춤이면 입자 × KO_LOW_GFX_PARTICLES
  KO_SMASH_MS: 900, // 스매시 폭발 줄기가 뻗었다 사라지는 시간
  KO_SMASH_LEN: 9, // 줄기 길이 (칸)
  KO_SMASH_WIDTH: 1.6, // 줄기 끝 반지름 (칸)
  KO_SMASH_UP: 0.6, // 줄기가 바깥에서 위로 드는 정도 (바깥 방향 1 에 대한 위 성분)
  KO_SMASH_PARTICLES: 40,
  KO_EDGE_MS: 700, // 화면 끝 번쩍 (떨어진 쪽, 그 사람 색)
  KO_NEAR_DIST: 6, // 이 거리 안이면 내 화면도 흔들림·히트스톱
  KO_SHAKE_ME: 0.45, // 내가 KO 됐을 때 흔들림
  KO_SHAKE_NEAR: 0.18, // 가까운 사람이 KO 됐을 때
  KO_SHAKE_MS: 500,
  KO_CRUSH_DUST: 46, // 압사 먼지 입자
  KO_CRUSH_CHIPS: 24, // 압사 블록 조각
  KO_CRUSH_STOP_MS: 120, // 압사 히트스톱 (화면만 멈칫)
  KO_CRUSH_STOP_SCALE: 0.05, // 히트스톱 동안 화면 시간 배율
  KO_FINAL_MS: 1600, // 마지막 킬 슬로모션 길이 (판 끝난 뒤 화면만)
  KO_FINAL_SCALE: 0.25, // 슬로모션 화면 시간 배율
  KO_FINAL_ZOOM: 0.6, // 슬로모션 때 시야각 배율 (작을수록 확대)
  KO_FINAL_LOOK: 0.7, // 슬로모션 때 카메라가 킬 자리 쪽으로 돌아보는 정도 (0~1)
  KO_LOW_GFX_PARTICLES: 0.4,
  // ---- npm run online 터널 지키기 (tools/online.js TunnelKeeper, 2026-10-27 재혁: 링크가 켜자마자 530·1033 에러일 때가 많음) ----
  TUNNEL_URL_TIMEOUT_MS: 20000, // cloudflared 를 켜고 이 안에 주소가 안 나오면 다시 켬
  TUNNEL_POLL_MS: 250, // 주소 나왔나 보는 간격
  TUNNEL_READY_TIMEOUT_MS: 45000, // 주소를 받고 이 안에 실제로 안 열리면 다시 켬 (보통 몇 초 ~ 20초)
  TUNNEL_PROBE_INTERVAL_MS: 2000, // 열리나 다시 보는 간격
  TUNNEL_PROBE_TIMEOUT_MS: 8000, // 요청 하나 기다리는 시간
  TUNNEL_HEALTH_MS: 30000, // 열린 뒤 확인 간격
  TUNNEL_HEALTH_FAILS: 2, // 연속 이만큼 안 열리면 다시 켬
  TUNNEL_MAX_RESTARTS: 5, // 연속 실패 상한 (넘으면 포기하고 안내)
  // 재접속 (2026-10-28 재혁): 끊긴 사람 자리를 이만큼 유지 (같은 자리·이름·색·캐릭터·팀·승수·피해 %). 판 중이면 그동안 봇이 대신 조종, 돌아오면 바로 돌려받음.
  // 지나면 예전처럼 나간 걸로 (판 중이면 '접속 끊김' 사망). 대기실도 같음 (방장이면 방장 유지, 사람이 다 끊겨도 방은 이 시간 뒤에 없어짐)
  RECONNECT_GRACE_MS: 60000,
  RECONNECT_TOKEN_BYTES: 16, // 자리 토큰 (방 코드와 같이 보냄) 길이: 16바이트 = 추측 불가
  NET_RECONNECT_MS: 2000, // 화면: 서버 연결이 끊기면 이 간격으로 다시 붙어 봄 (붙으면 새로고침 → 저장한 토큰으로 같은 자리)
  NET_RECONNECT_TRIES: 30, // 이만큼 해도 안 되면 그만 (30 × 2초 = 자리 유지 RECONNECT_GRACE_MS 와 같게. 터널 주소가 바뀌었으면 새 링크가 필요)
};

// 캐릭터의 평타 세트 (바드는 메탈 폼이면 metal 세트)
export function basicSet(char, form) {
  const set = CONFIG.BASIC_ATTACKS[char];
  return set && set.metal && form === 'metal' ? set.metal : set;
}
