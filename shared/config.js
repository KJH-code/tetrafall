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
  GRID_W, // x 칸 수
  GRID_D, // y 칸 수
  GRID_H, // z 칸 수 (높이)
  FALL_DEATH_Z: -4, // 발 높이가 이 아래로 내려가면 낙사

  // ---- 블록 낙하 ----
  // 2단계: 판이 길어질수록 블록이 빨라지고 많아진다 ("처음에 1개, 갈수록 더 짧게, 많이")
  //   동시에 떨어지는 자동 블록 수 = min(MAX, 1 + 경과 / RAMP_MS)
  //   다음 블록까지 간격·1칸 낙하 간격 = 시작값에서 끝값으로 RAMP_FULL_MS 동안 선형으로 줄어듦
  AUTO_FALL_STEP_MS: 350, // 자동 낙하: 1칸 내려오는 간격 (판 시작 때)
  AUTO_FALL_STEP_MIN_MS: 200, // 판 후반 (RAMP_FULL_MS 이후)
  AUTO_SPAWN_DELAY_MS: 1000, // 자동 블록끼리 나오는 간격 (판 시작 때)
  AUTO_SPAWN_DELAY_MIN_MS: 400, // 판 후반
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

  // ---- 조종권 ----
  CONTROL_TIME_MS: 8000, // 이 안에 안 떨구면 자동 낙하
  // true: 조종권을 먹는 즉시 조종 시작 (떨어지던 자동 블록을 넘겨받거나 새 블록). false: 다음 블록부터 조종. 2026-10-20 도입
  CONTROL_TAKEOVER: true,
  CONTROL_ITEM_RESPAWN_MS: 6000, // 조종권 아이템 재스폰 대기
  CONTROL_HOVER_Z: GRID_H, // 조종 중 블록이 떠 있는 높이

  // ---- 아이템 (조종권 제외) — 2단계 ----
  // 필드에 동시에 ITEM_MAX_ON_FIELD 개까지. 종류는 ITEM_POOL 에서 무작위
  ITEM_POOL: ['knockback', 'weapon', 'jump', 'ghost', 'brick', 'bomb', 'speed'],
  ITEM_MAX_ON_FIELD: 2,
  ITEM_FIRST_SPAWN_MS: 4000, // 판 시작 후 첫 아이템
  ITEM_RESPAWN_MS: 6000, // 다음 아이템까지
  // 망치(근접 무기): WEAPON_USES 번 맞힐 동안 밀치기 대신. 넉백 2배 + 경직 길게. 빗나가면 소모 안 함 (2026-10-20 재혁)
  WEAPON_USES: 3,
  WEAPON_KB_SPEED: 8.4, // 밀치기(4.2)의 2배 → 약 3칸
  WEAPON_KB_UP: 4,
  WEAPON_STUN_MS: 1200,
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
  // 핫바 (2026-10-20): 1 쌓기 블록 · 2 던지는 아이템(투사체 또는 설치 블록) · 3 폭탄. 숫자키·마우스 휠로 고르고 우클릭으로 씀.
  // 아이템을 먹으면 그 칸으로 자동 전환. 좌클릭은 칸과 상관없이 밀치기(망치)
  // 쌓기 블록 (마크식): 조준한 블록 면(옆면 포함)에 1×1 을 바로 붙임. 사람이 있는 칸엔 못 놓음
  BUILD_BLOCKS_PER_ROUND: 5,
  BUILD_RANGE: 3, // 눈에서 시선 거리 (칸)
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
  BRICK_SHOCK_KB_SPEED: 8.4, // 망치와 같은 세기
  BRICK_SHOCK_KB_UP: 4,
  BRICK_SHOCK_STUN_MS: 1200,
  BRICK_SHOCK_HEIGHT: 1.5, // 충격파가 닿는 높이 차 (착지 높이와 발 높이 차, 칸)

  // ---- 피해 % (대난투식, 2026-10-20) ----
  // 맞을 때마다 공격 종류별로 쌓이고 판 내내 안 줄어든다. 수평 넉백 = 기본 × (DAMAGE_KB_BASE + 피해% × DAMAGE_KB_PER_PERCENT).
  // 경직 중이라 무시된 공격은 안 쌓인다. 압사·용암은 % 와 상관없이 즉사
  DAMAGE_GAIN: { push: 10, weapon: 25, projectile: 20, shock: 40, bomb: 40 },
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

  // ---- 경직 ----
  STUN_MS: 500, // 넉백 맞으면 이 동안 조작 불가 + 추가 넉백 무시
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
  JUMP_SPEED: 7.5, // 최고 높이 약 1.28칸 → 1칸 블록은 올라가고 2칸 벽은 못 넘음. 2026-10-20 6.5→7.5 (6.5는 0.95칸이라 1칸도 못 올라감)
  GRAVITY: 20,
  DASH_SPEED: 6, // 대시 순간 속도. 2026-10-20 10→6 (땅에서 약 1.7칸 → 약 1칸)
  DASH_COOLDOWN_MS: 1500,
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
  CHARACTERS: ['tank', 'ninja', 'builder', 'hook'],
  CHAR_NAMES: { tank: '탱크', ninja: '닌자', builder: '건축가', hook: '갈고리' },
  SKILL_NAMES: { tank: '버티기', ninja: '순간이동', builder: '벽 세우기', hook: '갈고리' },
  ULT_NAMES: { tank: '지면 강타', ninja: '그림자', builder: '블록 비', hook: '회오리' },
  CHAR_DEFAULT: 'tank',
  ULT_MAX: 100, // 필살기 게이지 (다 차면 R)
  ULT_PER_DAMAGE: 1, // 피해 % 를 주거나 받을 때 1% 당 게이지
  // 탱크
  TANK_DAMAGE_TAKEN: 0.85, // 패시브: 맞을 때 쌓이는 피해 % 배율. 2026-10-24 '넉백 ×0.85' 에서 바꿈 (봇 120판 탱크 51승 / 기대 30, 재혁: 패시브 바꿈)
  TANK_HOLD_MS: 2000, // 스킬 버티기: 이동안 안 밀림
  TANK_HOLD_CD_MS: 10000,
  TANK_SLAM_RANGE: 2.5, // 필살 지면 강타: 이 거리 안 (수평, 높이 차 2칸 안)
  TANK_SLAM_KB_SPEED: 8,
  TANK_SLAM_KB_UP: 6,
  TANK_SLAM_STUN_MS: 1000,
  TANK_SLAM_DAMAGE: 20,
  // 닌자
  NINJA_SPEED_MULT: 1.1, // 패시브: 이동 속도
  NINJA_BLINK_DIST: 3, // 스킬 순간이동: 보는 방향으로 (벽 앞까지)
  NINJA_BLINK_CD_MS: 6000,
  NINJA_SHADOW_MS: 3000, // 필살 그림자: 유령화(반투명·블록 통과·압사 면역) + 다음 밀치기 치명타
  // 건축가
  BUILDER_EXTRA_BLOCKS: 3, // 패시브: 쌓기 블록 추가
  BUILDER_WALL_CD_MS: 12000, // 스킬 벽 세우기: 바로 앞 가로 3칸 × 2층
  BUILDER_WALL_WIDTH: 3,
  BUILDER_WALL_HEIGHT: 2,
  BUILDER_RAIN_CELLS: [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]], // 필살 블록 비: 조준한 칸 기준 1×1 블록 자리
  // 갈고리
  HOOK_PUSH_RANGE_MULT: 1.2, // 패시브: 밀치기 사거리
  HOOK_RANGE: 5, // 스킬 갈고리: 보는 방향 이 거리 안 첫 상대를 끌어옴
  HOOK_HALF_ANGLE_DEG: 15, // 갈고리가 닿는 시야 반각
  HOOK_CD_MS: 8000,
  HOOK_PULL_TO: 1, // 끌어와서 내 앞 이 거리에 놓음
  HOOK_STUN_MS: 300,
  HOOK_ULT_RANGE: 4, // 필살 회오리: 주변 이 거리 안 모두 끌어옴
  HOOK_ULT_STUN_MS: 500,

  // ---- 지형 장치 (2026-10-24 재혁: 지형 묶음, 새 맵 2개) ----
  CRUMBLE_MS: 1000, // 무너지는 바닥: 밟고 나서 흔들리다 사라지기까지 (안 돌아옴)
  PLATFORM_SPEED: 1, // 움직이는 발판 속도 (칸/초). 걸어서 올라탈 수 있게 천천히

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

  // ---- AI 봇 (서버에서 돎, 사람과 같은 입력만 씀) ----
  BOT_THINK_MS: 100, // 판단 주기
  BOT_REACTION_MS: 450, // 그림자가 보이고 나서 피하기 시작할 때까지 (사람 반응 흉내)
  BOT_AIM_ERROR_RAD: 0.3, // 투사체 조준 오차 (라디안, ± 이 안에서 무작위)
  BOT_DROP_DELAY_MS: 250, // 조종 중 상대 위에 맞춘 뒤 떨어뜨리기까지
  BOT_TARGET_JITTER: 1, // 상대 고를 때 판마다 상대별로 0~이 값(칸)을 거리에 더함. 동점일 때 늘 같은 상대(사람)만 노리지 않게
  BOT_SKILL_INTERVAL_MS: 2000, // 봇이 캐릭터 스킬·필살기를 써 보는 간격 (×0.7~1.3 무작위)
  BOT_PUSH_INTERVAL_MS: 1500, // 봇이 밀치기 사이에 두는 간격 (×0.7~1.3 무작위). 낮을수록 공격적
  BOT_BRICK_AIM_ERROR: 1.2, // 설치 블록 던질 때 조준점을 상대 발밑에서 이 반경(칸) 안 무작위로 빗나감 (없으면 거의 다 맞힘)
  BOT_BOMB_DANGER_PAD: 0.5, // 봇이 피하는 폭탄 범위 = BOMB_BLAST_RANGE + 이만큼 (칸 중심 거리 기준이라 여유)
  BOT_BRICK_STEP_PITCH: -1.3, // 발판 던질 때 시선 각도: 거의 발밑을 보면 BRICK_MIN_DIST 앞 칸에 바로 닿음
  BOT_BUILD_STEP_PITCH: -1.0, // 쌓기 발판 놓을 때 시선 각도: 눈높이에서 바로 앞 칸 바닥(발 높이)에 닿음
  BOT_LAVA_MARGIN: 1.5, // 용암이 켜지면 표면에서 이 높이(칸) 안의 낮은 칸으로는 내려가지 않음 (1.5칸 = 24초)
  BOT_CONTROL_AIM_ERROR: 1, // 조종 블록 겨냥이 빗나가는 반경(칸) 기준. 아래 난이도 배수를 곱함 (보통·어려움 0 = 정확히 겨냥)
  // 봇 난이도 (호스트가 대기 화면에서 고름, 모든 봇에 같이). 위 BOT_* 값에 곱하는 배수. 보통 = 위 값 그대로 (조종 겨냥 오차만 0)
  BOT_LEVELS: {
    easy: { REACTION_MS: 1.7, AIM_ERROR_RAD: 2, DROP_DELAY_MS: 3, PUSH_INTERVAL_MS: 1.8, BRICK_AIM_ERROR: 1.6, CONTROL_AIM_ERROR: 1.5 },
    normal: { CONTROL_AIM_ERROR: 0 },
    hard: { REACTION_MS: 0.6, AIM_ERROR_RAD: 0.5, DROP_DELAY_MS: 0.6, PUSH_INTERVAL_MS: 0.65, BRICK_AIM_ERROR: 0.6, CONTROL_AIM_ERROR: 0 },
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
  WHEEL_STEP_MS: 120, // 마우스 휠로 핫바 한 칸 넘기는 최소 간격 (터치패드가 한 번에 여러 번 보내서)
  SKY_CAMERA_HEIGHT: GRID_H + 14, // 하늘 시점 카메라 높이 (필드 중심 위)
  SKY_TRANSITION_MS: 700, // 1인칭 ↔ 하늘 시점 전환 애니메이션 길이
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
  CRUMBLE_COLOR: 0x7fc8d8, // 무너지는 바닥 칸 (하늘빛 돌)
  CRUMBLE_SHAKE: 0.06, // 무너지기 직전 칸이 흔들리는 폭 (칸)
  PLATFORM_COLOR: 0xd8c070, // 움직이는 발판
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
  FIGURE_CHARS: ['tank'], // TABS 식 몸(client/figure.js)으로 그리는 캐릭터. 2026-10-24 시안: 탱크만, 나머지는 로봇 + 머리 장식
  FIGURE_BODY: { tank: 'drum' }, // 캐릭터별 체형 (client/figure.js BODIES: lean 보통 · drum 드럼통). 2026-10-24 재혁: 탱크는 통통한 쪽
  FIGURE_SCALE: 1.15, // 몸 전체 크기 배율 (1 이면 로봇과 키가 같아도 가늘어서 작아 보임). 판정 상자는 그대로
  FIGURE_EYE: 0.062, // 왕눈알 흰자 반지름 (칸, 몸 크기 배율 전)
  FIGURE_FOLLOW: 14, // 관절이 목표 자세를 따라가는 빠르기 (/초). 낮을수록 늦게 따라와 흐느적
  FIGURE_ARM_SPREAD: 0.22, // 가만히 있을 때 팔을 옆으로 벌린 각 (라디안)
  FIGURE_WALK_LEG: 0.7, // 걸을 때 허벅지를 앞뒤로 드는 최대 각
  FIGURE_WALK_KNEE: 0.9, // 걸을 때 무릎을 굽히는 최대 각
  FIGURE_WALK_ARM: 0.6, // 걸을 때 팔을 앞뒤로 흔드는 최대 각
  FIGURE_RUN_LEAN: 0.18, // 최고 속도로 걸을 때 허리를 앞으로 숙이는 각
  FIGURE_HELD_SCALE: 0.7, // 손에 든 것 크기 배율 (팔이 가늘어서)
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
