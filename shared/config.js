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
  AUTO_FALL_STEP_MS: 500, // 자동 낙하: 1칸 내려오는 간격 (판 시작 때). 2026-10-24 350→500 (재혁: 억까 → 떨어지는 속도 감속)
  AUTO_FALL_STEP_MIN_MS: 300, // 판 후반 (RAMP_FULL_MS 이후). 2026-10-24 200→300
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
  CONTROL_ITEM: false, // 조종권 아이템을 필드에 내놓을지. 2026-10-24 재혁: 뺌 (블록 마스터의 마스터 조종은 그대로)
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
  // 손에 드는 아이템은 하나만 (2026-10-24 재혁: 핫바·쌓기 블록 없앰). 들고 있으면 다른 손 아이템은 못 주움 (필드에 남음).
  // 우클릭으로 씀 (투사체·설치 블록·폭탄), 망치는 좌클릭 밀치기 대신. 버프(점프·유령·이속)는 먹자마자 효과라 따로
  HELD_ITEMS: ['knockback', 'brick', 'bomb', 'weapon'],
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

  // ---- 캐릭터 평타 (2026-10-25 재혁 승인, 스매시 레전드식) ----
  // 캐릭터가 있는 게임에서만 (캐릭터 없는 예전 규칙은 위 밀치기 그대로). 망치를 들면 망치가 우선.
  // 지상: 앞 타가 맞고 BASIC_CHAIN_WINDOW_MS 안에 다시 누르면 다음 타 (후딜 중에 누르면 기다렸다 나감), 빗나가거나 놓치면 1타부터.
  // 스킬(F)을 쓰면 이어 치기 창이 다시 열림 (타 번호 그대로) → 평타 → 스킬 → 평타.
  // 한 타 = windup(준비, 이 뒤에 판정) → rec(후딜, 이 뒤에 다음 타). 중간 타 넉백 kb 는 고정 (피해 % 와 상관없음, 콤보 감쇠 없음) → 몇 % 든 이어짐.
  // 마무리 타(finish)와 공중 평타의 kb 는 밀치기처럼 피해 % 배율. 마무리 타가 맞으면 콤보 마무리 (×COMBO_FINISH_KB, 무적).
  // step: 판정 순간 때리는 쪽이 앞으로 나가는 거리 (칸). 경직 stun ≥ rec + 다음 타 windup + 약 0.1초 → 바로 누르면 확정.
  // 공중: 캐릭터마다 한 타 (치명타 규칙 그대로). 타 번호에 안 셈 — 맞으면 이어 치기 창 유지, 빗나가면 1타부터
  BASIC_CHAIN_WINDOW_MS: 500,
  BASIC_HITSTOP_MS: 60, // 중간 타 멈칫 (공중 평타는 HITSTOP_MS)
  BASIC_FINISH_HITSTOP_MS: 110, // 마무리 타 멈칫
  BASIC_STEP_GAP: 0.6, // step 으로 나갈 때 앞 상대와 이 거리 앞에서 멈춤 (지나쳐서 등 뒤로 가지 않게)
  BASIC_FINISH_MOVE_MULT: 0.5, // 마무리 타 준비 중 이동 속도 (예고 모션 동안 묶임)
  // F·R 캔슬 (2026-10-25 재혁 승인): 평타가 맞은 뒤 후딜이면 후딜을 끊고 바로, 빗나간 뒤 후딜이면 후딜이 끝나고, 준비 중이면 판정을 기다림 (수치 없음, game.js cast)
  // 카운터히트 (2026-10-25 재혁 승인): 맞는 쪽이 평타 준비·후딜, 스킬·필살기 준비(돌진 중 포함) 중이면 경직 ×, 멈칫 × (걷기·점프만은 아님, 이미 경직 중이면 아님).
  // 봇 480판: 한 판에 약 10번 (넣음·당함 캐릭터별 고름)
  COUNTER_STUN_MULT: 1.5,
  COUNTER_HITSTOP_MULT: 1.5,
  BASIC_ATTACKS: {
    // 탱크: 딜은 낮고 안정적. 2타는 띄우지 않고 경직을 길게 (3타 확정). 카운터히트 넣은 뒤 봇 480판 28% → 1·2타 딜 6/7 → 5/6, 방패 밀기 넉백 4.2 → 3.8
    tank: {
      chain: [
        { name: '주먹', windup: 120, rec: 300, stun: 550, dmg: 5, kb: 1.5, up: 2, step: 0.4 },
        { name: '어깨 박치기', windup: 150, rec: 350, stun: 750, dmg: 6, kb: 2, up: 1, step: 0.8 },
        { name: '방패 밀기', windup: 300, rec: 450, stun: 600, dmg: 10, kb: 3.8, up: 3, step: 0.3, finish: true },
      ],
      air: { name: '방패 내려치기', windup: 150, rec: 400, stun: 500, dmg: 8, kb: 3, up: 2, step: 0 },
    },
    // 닌자: 단검 짤딜 4타 + 마지막에 표창 (사거리 4칸, 좁은 각). 봇 판으로 초안에서 3·4·5타 딜 +1, 표창 넉백 3.6 → 5.6. 카운터히트 넣은 뒤 20% → 1·2타 딜 3 → 4. 맵 섞은 판 → 회전 베기 딜 5 → 6
    ninja: {
      chain: [
        { name: '찌르기', windup: 60, rec: 180, stun: 350, dmg: 4, kb: 0.8, up: 1, step: 0.3 },
        { name: '반대 찌르기', windup: 60, rec: 180, stun: 350, dmg: 4, kb: 0.8, up: 1, step: 0.3 },
        { name: '베어 올리기', windup: 60, rec: 200, stun: 380, dmg: 4, kb: 0.8, up: 2, step: 0.3 },
        { name: '회전 베기', windup: 80, rec: 220, stun: 520, dmg: 6, kb: 1, up: 1, step: 0.3 },
        { name: '표창', windup: 200, rec: 400, stun: 500, dmg: 8, kb: 5.6, up: 3, step: 0, range: 4, angle: 20, finish: true },
      ],
      air: { name: '공중 베기', windup: 60, rec: 300, stun: 400, dmg: 5, kb: 2.5, up: 2, step: 0 },
    },
    // 건축가: 옆치기 → 반대로 치기 → 내려찍기 + 바닥 블록 1칸 솟음 (맞으면 그 사람 발밑, 빗나가면 앞 칸). 카운터히트 뒤 28% → 내려찍기 딜 11 → 10. 맵 섞은 판 28% → 1·2타 딜 7 → 6
    builder: {
      chain: [
        { name: '옆치기', windup: 120, rec: 300, stun: 550, dmg: 6, kb: 1.2, up: 2, step: 0.4 },
        { name: '반대 치기', windup: 120, rec: 350, stun: 800, dmg: 6, kb: 1.2, up: 2, step: 0.4 },
        { name: '내려찍기', windup: 350, rec: 450, stun: 700, dmg: 10, kb: 2.5, up: 8, step: 0.3, finish: true, raise: true },
      ],
      air: { name: '망치 내려찍기', windup: 200, rec: 450, stun: 500, dmg: 9, kb: 3, up: 2, step: 0 },
    },
    // 갈고리: 평타에는 당김 없음. 주먹 넉백 초안 4.6 → 4.2 (봇 판). 맵 섞은 판 19% (벽·높은 지형에서 약함) → 휘두르기 딜 8 → 9, 주먹 넉백 4.2 → 4.4 휘두르기 → (F 갈고리 당김) → 주먹. 사거리는 패시브 HOOK_PUSH_RANGE_MULT
    hook: {
      chain: [
        { name: '갈고리 휘두르기', windup: 150, rec: 350, stun: 650, dmg: 9, kb: 2.5, up: 3, step: 0 },
        { name: '주먹', windup: 200, rec: 400, stun: 600, dmg: 9, kb: 4.4, up: 3, step: 0.4, finish: true },
      ],
      air: { name: '공중 휘두르기', windup: 150, rec: 400, stun: 500, dmg: 7, kb: 3, up: 2, step: 0 },
    },
  },

  // ---- 경직 ----
  STUN_MS: 500, // 밀치기 히트 경직: 이 동안 조작 불가. 경직 중에 또 맞으면 콤보 (밀치기 쿨 600 보다 짧아 평타만으로는 안 이어짐)
  // 콤보 (2026-10-24 재혁): 경직 중에 또 맞히면 콤보가 이어짐. 경직이 풀리면(끊김) 또는 첫 타에서 COMBO_MS 가 지난 뒤 들어간 타(마무리)에
  // 콤보가 끝나고 COMBO_IFRAME_MS 무적 (공격만 막음, 압사·낙사·용암은 못 막음). 여럿이 때려도 맞는 사람 기준으로 셈.
  // 2026-10-25 재혁: 타 수(5타) 대신 시간으로 끊음 (다타 캐릭터도 스킬까지 이어지게. 3초 제안 → 재혁 1초), 무적 1초는 "개사기 + 흐름이 끊김" → 0.3초
  // 콤보 중 가벼운 공격(밀치기·베기·돌진·갈고리)은 수평 넉백 ×COMBO_LIGHT_KB, 마지막 타는 ×COMBO_FINISH_KB 로 크게 날림
  // 2026-10-25 재혁 승인: 1.0 → 1.4초 (닌자 평타 5타 최단 1.18초 + 입력 여유). 캐릭터 평타의 마무리 타(finish)는 시간과 상관없이 마무리
  COMBO_MS: 1400,
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
  // 2026-10-24 재혁: 스킬이 직접 피해·넉백을 주고 콤보로 이어지게 (닌자 = 콤보 캐릭터). 남이 쓰는 것도 보이게 예고·효과
  SKILL_NAMES: { tank: '돌진', ninja: '순간 베기', builder: '솟는 벽', hook: '갈고리' },
  ULT_NAMES: { tank: '내려찍기', ninja: '그림자 일격', builder: '블록 비', hook: '회오리' },
  SKILL_CD_MS: { tank: 8000, ninja: 6000, builder: 11000, hook: 8000 }, // 봇 160판으로 맞춤 (2026-10-24)
  CHAR_DEFAULT: 'tank',
  // 스킬·필살기를 쓰면 그 캐릭터에 빛 (글자 대신, 남에게도 보임. 누가 무엇인지는 캐릭터 모양으로). 2026-10-25 재혁:
  // 전체 느낌을 방해하지 않지만 잘 보이게 → 노을(주황·빨강)과 대비되는 차가운 색, 압사 경고(빨강)·치명타(노랑)와 안 겹치게
  SKILL_AURA_COLOR: 0xffffff, // F: 발밑에 얇은 고리가 짧게 퍼지고 몸이 순간 하얗게 번쩍
  SKILL_AURA_MS: 300,
  SKILL_GLOW_MS: 140,
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
  TANK_CHARGE_SPEED: 12, // 스킬 돌진: 이 속도(칸/초)로 TANK_CHARGE_MS 동안 앞으로 (약 3칸). 처음 부딪힌 상대를 치고 멈춤
  TANK_CHARGE_MS: 250,
  TANK_CHARGE_HIT_RANGE: 0.9, // 몸 가운데끼리 이 거리 안이면 부딪힘
  TANK_CHARGE_KB_SPEED: 4.2,
  TANK_CHARGE_KB_UP: 3,
  TANK_CHARGE_STUN_MS: 600,
  TANK_CHARGE_DAMAGE: 15,
  TANK_SLAM_WINDUP_MS: 500, // 필살 내려찍기: 떠올랐다가 이 뒤에 쾅 (바닥에 범위 예고)
  TANK_SLAM_JUMP: 6, // 떠오르는 속도
  TANK_SLAM_RANGE: 2.5, // 쾅 범위 (수평, 높이 차 2칸 안)
  TANK_SLAM_KB_SPEED: 4.5, // 옆으로는 조금, 위로 크게 띄움 → 공중 치명타 연계
  TANK_SLAM_KB_UP: 9,
  TANK_SLAM_STUN_MS: 900,
  TANK_SLAM_DAMAGE: 20, // 2026-10-25 맵 7개 섞은 봇 504판 탱크 29% (킬 대부분 내려찍기) → 25 → 20, 넉백 5 → 4.5
  // 닌자 (콤보: 평타 → F 순간 베기 → 평타 → R 일격 → F 초기화 → F → 평타)
  NINJA_SPEED_MULT: 1.2, // 패시브: 이동 속도. 2026-10-25 평타 개편 뒤 1.1 → 1.2 (봇 480판 닌자 82승 / 기대 120, 가장 많이 죽음 → 117승)
  // 2026-10-25 재혁 결정: 3 → 4칸. 생존기·이동기 강화 (F → R 맞히면 F 쿨 초기화 → F → 2단 점프 → 대시로 멀리 빠짐). 경직 중 사용(탈출기)은 안 넣음
  NINJA_BLINK_DIST: 4, // 스킬 순간 베기: 보는 방향으로 (벽 앞까지) 이동하며 지나간 길의 상대를 벰 (한 번 쓸 때 한 사람 한 번). 상대를 만나면 그 바로 뒤(NINJA_STRIKE_BEHIND)에서 멈춤
  NINJA_SLASH_WIDTH: 0.8, // 지나간 선에서 이 거리 안이면 베임
  NINJA_SLASH_KB_SPEED: 2.5,
  NINJA_SLASH_KB_UP: 2,
  NINJA_SLASH_STUN_MS: 600,
  NINJA_SLASH_DAMAGE: 15,
  NINJA_STRIKE_RANGE: 6, // 필살 그림자 일격: 이 거리 안 가장 가까운 상대 등 뒤로 순간이동해 치명타 밀치기. 맞히면 F 쿨 초기화. 없으면 안 쓰임
  NINJA_STRIKE_BEHIND: 0.8, // 상대 뒤 이 거리에 섬
  // 건축가
  BUILDER_WALL_WIDTH: 3, // 스킬 솟는 벽: 바로 앞 가로 3칸 × 2층. 예고 뒤 솟으며 그 칸 위 사람을 띄움
  BUILDER_WALL_HEIGHT: 2,
  BUILDER_WALL_WARN_MS: 400,
  BUILDER_WALL_KB_UP: 9,
  BUILDER_WALL_STUN_MS: 700,
  BUILDER_WALL_DAMAGE: 10,
  BUILDER_RAIN_CELLS: [[0, 0], [1, 0]], // 필살 블록 비: 조준한 칸 기준 1×1 블록 자리 (깔리면 압사, 옆은 충격파). 5개는 봇 판 건축가 50/160 → 3개.
  // 2026-10-25 재혁 승인: 3 → 2개 (맵 7개 섞은 봇 504판 건축가 149승 / 기대 126, 킬 약 80% 가 블록 비)
  BUILDER_BRICK_BONUS: 1, // 패시브: 설치 블록 아이템을 주우면 이만큼 더 (2026-10-24, '벽 쿨 짧음' 대신)
  // 갈고리 (연계: 평타로 밀고 → 갈고리로 다시 당겨 → 평타)
  HOOK_PUSH_RANGE_MULT: 1.2, // 패시브: 평타(밀치기) 사거리
  HOOK_RANGE: 5, // 스킬 갈고리: 보는 방향 이 거리 안 첫 상대를 끌어옴
  HOOK_HALF_ANGLE_DEG: 15, // 갈고리가 닿는 시야 반각
  HOOK_PULL_TO: 1, // 끌어와서 내 앞 이 거리에 놓음
  HOOK_STUN_MS: 600,
  HOOK_DAMAGE: 10,
  HOOK_ULT_RANGE: 3.5, // 필살 회오리: 주변 이 거리 안 모두 끌어모은 뒤 HOOK_WHIRL_FLING_MS 뒤 바깥으로 한꺼번에 튕김
  HOOK_ULT_STUN_MS: 600,
  HOOK_ULT_DAMAGE: 15,
  HOOK_WHIRL_FLING_MS: 300,
  HOOK_WHIRL_KB_SPEED: 5, // 8.4 는 봇 120판 갈고리 56승 (회오리 킬 138)
  HOOK_WHIRL_KB_UP: 5,
  HOOK_WHIRL_STUN_MS: 900,

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
  BOT_AIR_JUMP_VZ: 2, // 봇은 위로 가는 속도가 이보다 느려지면 (꼭대기 근처) 2단 점프
  BOT_REACTION_MS: 450, // 그림자가 보이고 나서 피하기 시작할 때까지 (사람 반응 흉내)
  BOT_AIM_ERROR_RAD: 0.3, // 투사체 조준 오차 (라디안, ± 이 안에서 무작위)
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
    easy: { CHAIN_DELAY_MS: 2.5, REACTION_MS: 1.7, AIM_ERROR_RAD: 2, DROP_DELAY_MS: 3, PUSH_INTERVAL_MS: 1.8, BRICK_AIM_ERROR: 1.6, CONTROL_AIM_ERROR: 1.5 },
    normal: { CONTROL_AIM_ERROR: 0 },
    hard: { CHAIN_DELAY_MS: 0.5, REACTION_MS: 0.6, AIM_ERROR_RAD: 0.5, DROP_DELAY_MS: 0.6, PUSH_INTERVAL_MS: 0.65, BRICK_AIM_ERROR: 0.6, CONTROL_AIM_ERROR: 0 },
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
  FIGURE_CHARS: ['tank', 'ninja', 'builder', 'hook'], // TABS 식 몸(client/figure.js)으로 그리는 캐릭터 (2026-10-24). 캐릭터 없으면 로봇
  FIGURE_BODY: { tank: 'drum', ninja: 'slim', builder: 'sturdy', hook: 'reach' }, // 캐릭터별 체형 (client/figure.js BODIES). 2026-10-24 재혁: 탱크는 통통한 쪽
  FIGURE_SCALE: 1.15, // 몸 전체 크기 배율 (1 이면 로봇과 키가 같아도 가늘어서 작아 보임). 판정 상자는 그대로
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
