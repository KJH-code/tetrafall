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
  MAX_PLAYERS: 4, // 방에 들어올 수 있는 최대 인원 (넘으면 접속 거부)
  MIN_PLAYERS: 2, // 호스트가 시작할 수 있는 최소 인원
  // 방: 2026-10-22 6단계 (인터넷 대전). 서버 하나에 방 여러 개, 방마다 게임 하나
  // 방 하나(봇 4) ≈ CPU 한 코어의 4%, 사람 하나에 보내는 양 ≈ 0.75Mbps → 8개면 32명 ≈ 업로드 24Mbps
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
  FIELD_SIZES: { 2: 10, 3: 12, 4: 14 },
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
  SKY_COUNT: 7, // 하늘에 떠 있는 블록 수 (착지·녹으면 맨 위에 새로)
  SKY_SPAWN_PER_TICK: 1, // 한 틱에 놓는 하늘 블록 수 (자리 고르기가 무거워서 나눔: 판 시작 사슬 7개 = 7틱 약 0.23초)
  SKY_TOP_Z: 32, // 블록 윗면 최고 높이 (상한)
  SKY_RISE_MIN: 1, // 새 블록 = 맨 위 블록 지금 높이 + 이 범위의 칸 (정수 무작위)
  SKY_RISE_MAX: 2, // 2단 점프 최고 약 2.8칸이라 여유 있게
  SKY_GAP_MIN: 1, // 이웃 블록 칸 사이 최소 거리 (붙으면 머리 부딪힘·한 덩어리로 보임)
  SKY_REACH_SAFETY: 0.5, // 틈은 R(높이차) × 이 값까지 → 높이차 1 이면 약 2.6칸, 2 면 약 2.3칸
  SKY_FALL_STEP_MS: 2500, // 하늘 블록 1칸 내려오는 간격, 판 내내 고정 (예전 AUTO_FALL 500→300)
  // 그림자(경고)는 착지까지 남은 칸 수로: 예전 SHADOW_LEAD_MS(착지 3초 전)는 한 칸 2.5초면 깔리기 0.5초 전이라 못 피함 (봇 판 압사 28% → 55%)
  SKY_LAVA_TRIGGER_MS: 60000, // 켬 판은 판 시작 후 이 시간이 지나면 평균 높이와 상관없이 용암 시작 (2026-10-26 재혁: 착지가 느려 용암이 거의 안 옴, 봇 504판 중 2판)
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
  EMOTE_NAMES: ['손 흔들기', '춤', '웃기', '도발'],
  EMOTE_MS: 1600,
  EMOTE_COOLDOWN_MS: 2500,
  EMOTE_ARM_SCALE: 1.9, // 이모트 땐 팔을 키워서 멀리서도 동작이 보이게
  EMOTE_PICK_PX: 30,
  EMOTE_CLIPS: ['Wave', 'Dance', 'Yes', 'No'], // 로봇 모델에서 이모트마다 쓰는 동작 (손 흔들기·춤·웃기(끄덕끄덕)·도발(고개 젓기)) // 바퀴 메뉴: 마우스를 이만큼(px) 움직여야 고른 것으로 침
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
      air: [{ name: '천천히 낙하', windup: 100, rec: 300, stun: 0, dmg: 0, kb: 0, up: 0, step: 0, glide: true }],
      metal: {
        chain: [
          { name: '기타 후려치기', windup: 150, rec: 300, stun: 650, dmg: 6, kb: 1.5, up: 1, step: 0.3 },
          { name: '기타 내려치기', windup: 250, rec: 450, stun: 700, dmg: 10, kb: 4.6, up: 3, step: 0.3, finish: true },
        ],
        air: [{ name: '기타 꽂기', windup: 150, rec: 400, stun: 600, dmg: 9, kb: 2, up: -4, step: 0, angle: 180, finish: true }], // 아래로 꽂음 (up 음수)
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
  BUILDER_PAD_BOOST: 8, // 공중 F 발판: 위로 부스트 속도 (3타 띄움과 같은 세기, 약 1.6칸)
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
  BOT_REACTION_MS: 450, // 그림자가 보이고 나서 피하기 시작할 때까지 (사람 반응 흉내)
  BOT_AIM_ERROR_RAD: 0.3, // 투사체 조준 오차 (라디안, ± 이 안에서 무작위)
  BOT_SHELL_AIM_ERROR_RAD: 0.3, // 대포수 포탄·대형 포탄 조준 오차 (좌우·위아래 각각 ±, 쏠 때마다 새로). 2026-10-26 총괄 승인: 오차 0 명중 77%·승률 58% → 0.15 명중 73%·44% → 0.3 명중 61%·40% (투사체 BOT_AIM_ERROR_RAD 와 같게)
  BOT_DROP_DELAY_MS: 250, // 조종 중 상대 위에 맞춘 뒤 떨어뜨리기까지
  BOT_TARGET_JITTER: 1, // 상대 고를 때 판마다 상대별로 0~이 값(칸)을 거리에 더함. 동점일 때 늘 같은 상대(사람)만 노리지 않게
  BOT_SKILL_INTERVAL_MS: 2000, // 봇이 캐릭터 스킬·필살기를 써 보는 간격 (×0.7~1.3 무작위)
  BOT_CHAIN_DELAY_MS: 80, // 캐릭터 평타 이어 치기: 다음 타를 누를 수 있게 된 뒤 봇이 누르기까지 (×0.7~1.3 무작위)
  BOT_PUSH_INTERVAL_MS: 1500, // 봇이 밀치기 사이에 두는 간격 (×0.7~1.3 무작위). 낮을수록 공격적
  BOT_BRICK_AIM_ERROR: 1.2, // 설치 블록 던질 때 조준점을 상대 발밑에서 이 반경(칸) 안 무작위로 빗나감 (없으면 거의 다 맞힘)
  BOT_BOMB_DANGER_PAD: 0.5, // 봇이 피하는 폭탄 범위 = BOMB_BLAST_RANGE + 이만큼 (칸 중심 거리 기준이라 여유)
  BOT_BRICK_STEP_PITCH: -1.3, // 발판 던질 때 시선 각도: 거의 발밑을 보면 BRICK_MIN_DIST 앞 칸에 바로 닿음
  BOT_LAVA_MARGIN: 1.5, // 용암이 켜지면 표면에서 이 높이(칸) 안의 낮은 칸으로는 내려가지 않음 (1.5칸 = 24초)
  BOT_CONTROL_AIM_ERROR: 1, // 조종 블록 겨냥이 빗나가는 반경(칸) 기준. 아래 난이도 배수를 곱함 (보통·어려움 0 = 정확히 겨냥)
  // 봇 난이도 (호스트가 대기 화면에서 고름, 모든 봇에 같이). 위 BOT_* 값에 곱하는 배수. 보통 = 위 값 그대로 (조종 겨냥 오차만 0)
  BOT_LEVELS: {
    easy: { CHAIN_DELAY_MS: 2.5, REACTION_MS: 1.7, AIM_ERROR_RAD: 2, SHELL_AIM_ERROR_RAD: 2, DROP_DELAY_MS: 3, PUSH_INTERVAL_MS: 1.8, BRICK_AIM_ERROR: 1.6, CONTROL_AIM_ERROR: 1.5 },
    normal: { CONTROL_AIM_ERROR: 0 },
    hard: { CHAIN_DELAY_MS: 0.5, REACTION_MS: 0.6, AIM_ERROR_RAD: 0.5, SHELL_AIM_ERROR_RAD: 0.5, DROP_DELAY_MS: 0.6, PUSH_INTERVAL_MS: 0.65, BRICK_AIM_ERROR: 0.6, CONTROL_AIM_ERROR: 0 },
  },
  BOT_LEVEL_DEFAULT: 'normal',

  // ---- 타격감 (클라이언트, 2단계) ----
  SFX_VOLUME: 0.5, // 전체 효과음 크기 0~1
  MUSIC_VOLUME: 0.07, // 배경음악 크기 (효과음보다 작게)
  MUSIC_BPM: { calm: 92, battle: 138, lava: 166 }, // 대기·판 중·용암 때 빠르기
  SFX_HEAR_RANGE: 14, // 이 거리(칸) 밖 소리는 작게 (최소 20%)
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
  TOAST_MS: 2200, // 화면 알림이 떠 있는 시간
  // 화면 색·조명 (2026-10-22 4단계, 화면만). 테트리미노는 모양마다 색, 쌓이면 BLOCK_LANDED_SHADE 만큼 어둡게
  SHAPE_COLORS: { I: 0x38c8e8, O: 0xf8e030, T: 0xa050e0, S: 0x50c850, Z: 0xe85050, J: 0x4070e8, L: 0xf08a30 },
  BLOCK_LANDED_SHADE: 0.88,
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
  HELD_MODEL_SIZE: 0.28,
  ROBOT_EYE_WHITE: 0.62, // 로봇 흰자 반지름 (원래 검은 눈 무리 크기에 대한 비율)
  ROBOT_EYE_PUPIL: 0.3, // 로봇 눈동자 반지름 (같은 비율)
  ROBOT_RUN_SPEED: 3.2, // 이 속도(칸/초)보다 빠르면 로봇이 달리기 동작
  ROBOT_FADE_S: 0.15, // 로봇 동작이 바뀔 때 섞는 시간
  FIGURE_CHARS: ['tank', 'ninja', 'builder', 'hook', 'hunter', 'cannon', 'berserker', 'bard'], // TABS 식 몸(client/figure.js)으로 그리는 캐릭터 (2026-10-24). 캐릭터 없으면 로봇
  FIGURE_BODY: { tank: 'drum', ninja: 'slim', builder: 'sturdy', hook: 'reach', hunter: 'stalk', cannon: 'stout', berserker: 'brute', bard: 'lean' }, // 캐릭터별 체형 (client/figure.js BODIES). 2026-10-24 재혁: 탱크는 통통한 쪽
  FIGURE_SCALE: 1.15, // 몸 전체 크기 배율 (1 이면 로봇과 키가 같아도 가늘어서 작아 보임). 판정 상자는 그대로
  // 1인칭 팔·무기 (client/viewmodel.js): 내 몸을 복제해 팔·무기만 따로 그림
  VM_FOV: 62, // 뷰모델 카메라 화각 (필드 화각과 따로: 넓은 화각에서도 팔이 늘어나 보이지 않게)
  VM_SCALE: 0.62, // 몸 크기 배율 (FIGURE_SCALE 에 곱함). 작을수록 팔이 화면을 덜 가림
  VM_POS: { default: [0, -0.16, -0.26], bard: [0, -0.08, -0.34], cannon: [0, -0.2, -0.26] }, // 어깨 높이 기준점 (카메라 기준: 오른쪽 +x, 위 +y, 뒤 +z). 캐릭터별로 덮어씀
  VM_ARM_LOW: 1.0, // 내린 팔이 화면에선 이 각만큼 앞으로 든 팔 (라디안, π/2 = 정면)
  VM_ARM_OUT: 0.5, // 옆으로 벌린 각 배율
  VM_NARROW: 1.5, // 어깨 사이 거리 배율 (넓을수록 팔이 화면 양쪽 구석에서 나옴)
  VM_ELBOW_ADD: 1.35, // 내린 팔일 때 팔꿈치를 더 굽히는 각
  VM_BODY_FOLLOW: 0.45, // 몸통 숙임·비틂을 이만큼만 따라감
  VM_BOB: 0.018, // 걷기 흔들림 (칸)
  VM_BREATH: 0.004, // 숨쉬기 오르내림 (칸)
  VM_GUN_AIM: [1.45, 0.25], // 갈고리 장전 권총을 겨눌 때 [어깨 앞으로 든 각, 팔꿈치]
  VM_RAW_POSE: ['bard'], // 팔 각을 안 바꾸는 캐릭터 (바드는 악기를 이미 가슴 앞에 들고 있음: 기준점만 올려 보이게)
  VM_SPIN: ['berserker', 'hook'], // 몸 전체 돌기를 1인칭에도 그대로 (소용돌이·회전 베기·갈고리 스핀)
  VM_CANNON: [0.55, -0.06, -0.1], // 대포수 어깨 대포 [크기 배율, 오른쪽으로(-y) 옮김, 아래로 옮김] (몸 좌표 칸)
  VM_PIP_SCALE: 0.65, // 대포 위 남은 포탄 크기 배율
  PRACTICE_COMBO_SHOW_MS: 2500, // 연습 방: 끝난 허수아비 콤보 결과를 오른쪽에 남겨 두는 시간
  PRACTICE_SHOW_HEIGHT: 0.5, // 연습 방 콤보 기록: 이 높이(칸) 넘게 띄웠을 때만 '높이' 를 보임
  VM_STAR_HIDE_MS: 350, // 닌자 표창을 던진 뒤 왼손이 비어 있는 시간
  FIGURE_HORN_SEGS: 6, // 광전사 뿔 마디 수 (마디마다 같은 각으로 꺾여 매끈한 곡선)
  FIGURE_HORN_LEN: 0.42, // 뿔 한 개 길이 (칸, 몸 크기 배율 전)
  FIGURE_HORN_CURL: 2.1, // 뿔이 뿌리에서 끝까지 위로 휘는 각 합 (라디안, C 자)
  BERSERK_RAGE_PCT: 120, // 광전사 분노 화면: 피해 % 가 이만큼이면 가장 화남 (눈 충혈·눈썹·핏줄·빡침 표시·김. 몸 색은 안 바꿈: 플레이어 구분 우선)
  BERSERK_STEAM_RATE: 14,
  BARD_LUTE_SCALE: 1.35, // 류트 크기 배율 (가슴 앞에서 작아 보여서)
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
  FIGURE_EYE: 0.062, // 왕눈알 흰자 반지름 (칸, 몸 크기 배율 전)
  FIGURE_FOLLOW: 14, // 관절이 목표 자세를 따라가는 빠르기 (/초). 낮을수록 늦게 따라와 흐느적
  FIGURE_ARM_SPREAD: 0.22, // 가만히 있을 때 팔을 옆으로 벌린 각 (라디안)
  FIGURE_WALK_LEG: 0.7, // 걸을 때 허벅지를 앞뒤로 드는 최대 각
  FIGURE_WALK_KNEE: 0.9, // 걸을 때 무릎을 굽히는 최대 각
  FIGURE_WALK_ARM: 0.6, // 걸을 때 팔을 앞뒤로 흔드는 최대 각
  FIGURE_RUN_LEAN: 0.18, // 최고 속도로 걸을 때 허리를 앞으로 숙이는 각
  FIGURE_HELD_SCALE: 0.7, // 손에 든 것 크기 배율 (팔이 가늘어서)
  FIGURE_RUN_TWIST: 0.2, // 달릴 때 어깨를 다리 반대로 비트는 각
  FIGURE_RUN_ELBOW: 0.9, // 최고 속도로 달릴 때 팔꿈치를 더 굽히는 각 (팔 펌프)
  FIGURE_HIT_LEAN: 0.35, // 맞은 순간 허리가 밀린 쪽으로 꺾이는 각 (세기 1 기준)
  FIGURE_HIT_KICK: 6, // 히트스톱이 끝나고 밀린 쪽으로 더 튕기는 빠르기 (라디안/초, 세기 1 기준)
  FIGURE_HIT_SPRING_K: 70, // 휘청 스프링 세기 (클수록 빨리 흔들림)
  FIGURE_HIT_SPRING_DAMP: 7, // 휘청 스프링 감쇠 (클수록 빨리 멈춤)
  FIGURE_HIT_HEAVY: 1.5, // 무거운 공격 (망치·치명타·폭탄 등) 휘청 세기
  FIGURE_HIT_FINISH: 2.2, // 콤보 마무리 타 휘청 세기
  // 건축가 블록 화면 (render.js updateBBlocks)
  BB_BLINK_MS: 1500, // 사라지기 이만큼 전부터 깜빡임
  BB_POP_MS: 260, // 생길 때 바닥에서 솟아오르는 시간 (살짝 넘쳤다 돌아옴)
  BB_CHAIN_STEP_MS: 50, // 연쇄 폭발: 칸마다 이 간격으로 차례로 터짐
  BB_BIG_SWELL: 0.18, // 대폭발 블록이 터지기 직전까지 부푸는 비율
  BB_TINT: 0.3, // 주인 색에 흰색을 섞는 비율 (금 간 무늬가 보이게)
  STAR_FLY_MS: 100, // 닌자 표창이 날아가 보이는 시간 (판정은 즉시, 맞는 효과는 표창이 닿을 때)
  EMPOWER_GLOW: 0x6a2ad0, // 닌자 R 강화 중 몸이 깜빡이는 빛 (보라)
  // 탱크 화면
  ARMOR_SHINE: 0x8a96a8, // 아머 중 몸이 금속처럼 번쩍이는 빛
  FIGURE_HIT_ARMOR: 0.15, // 아머로 버틴 타: 휘청 세기 (얼굴만 찡그리는 정도)
  FIGURE_HIT_ARMOR_BREAK: 2.4, // 아머가 깨진 타: 휘청 세기 (크게)
  QUAKE_RISE_MS: 160, // 탱크 R 고리 땅이 솟는 시간 (넘쳤다 돌아옴)
  QUAKE_SINK_MS: 280, // 가라앉는 시간
  QUAKE_SINK_SHAKE: 0.07, // 가라앉는 동안 떨림 (칸)
  QUAKE_COLOR: 0x9c8468, // 솟는 땅 색 (흙)
  // 갈고리 화면
  HOOK_FLY_MS: 110, // 갈고리 머리가 날아가 닿는 시간. 판정도 이때 (2026-10-26: 던진 방향·닿는 순간 위치로, 그 사이 옆으로 피하면 빗나감)
  HOOK_HOLD_MS: 380, // 닿은 뒤 사슬이 걸려 있는 시간 (끌려오는 동안)
  HOOK_GRAB_SWING_R: 0.9, // R: 뽑은 블록을 머리 위에서 돌리는 반지름 (칸)
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
  VICTORY_DIST: 2.8, // 승자 앞 거리 (칸)
  VICTORY_UP: 1.4, // 발 위 높이 (칸)
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
};

// 캐릭터의 평타 세트 (바드는 메탈 폼이면 metal 세트)
export function basicSet(char, form) {
  const set = CONFIG.BASIC_ATTACKS[char];
  return set && set.metal && form === 'metal' ? set.metal : set;
}
