# 튜닝 수치는 전부 여기. shared/config.js 값 그대로 시작 (시제품 범위만)
# 좌표계: x,y 는 바닥 격자, z 는 위쪽. 블록 한 칸 = 1 단위 (그리기에서 고도 y-up 으로 바꿈)
extends RefCounted

# ---- 네트워크 / 루프 ----
const PORT := 3100
const TICK_RATE := 30
const MIN_PLAYERS := 2
const MAX_PLAYERS := 8
const ROUND_RESTART_MS := 3000.0 # 판 끝나고 다음 판까지 (서버)

# ---- 격자 ----
const GRID_W := 10
const GRID_D := 10
const GRID_H := 16
const FIELD_SIZES := {2: 10, 3: 12, 4: 14, 5: 16, 6: 17, 7: 18, 8: 19}
const FALL_DEATH_Z := -4.0
const SPAWN_INSET := 2.5

# ---- 블록 ----
const AUTO_FALL_STEP_MS := 500.0
const AUTO_FALL_STEP_MIN_MS := 300.0
const AUTO_SPAWN_DELAY_MS := 1000.0
const AUTO_SPAWN_DELAY_MIN_MS := 400.0
const CONCURRENT_START := 2
const CONCURRENT_RAMP_MS := 20000.0
const CONCURRENT_MAX := 4
const RAMP_FULL_MS := 90000.0
const FIRST_SPAWN_DELAY_MS := 1000.0
const PIECE_SPAWN_Z := GRID_H
const CRUSH_WARN_MS := 2000.0
const CRUSH_ESCAPE_CELLS := 2
const HEAD_BONK_STUN_MS := 180.0

# ---- 플레이어 ----
const PLAYER_HALF := 0.3
const PLAYER_HEIGHT := 1.6
const MOVE_SPEED := 4.5
const AIR_JUMPS := 1
const AIR_JUMP_SPEED := 7.5
const JUMP_SPEED := 7.5
const JUMP_BUFFER_MS := 200.0
const GRAVITY := 20.0
const DASH_SPEED := 6.0
const DASH_COOLDOWN_MS := 1500.0
const AIR_DASHES := 1
const KB_DAMPING_GROUND := 6.0
const KB_DAMPING_AIR := 1.2
const WALL_BOUNCE_RATIO := 1.0
const WALL_BOUNCE_MIN_SPEED := 3.0
const WALL_BOUNCE_MAX_UP := 11.0
const MAX_STEP_DT := 0.05

# ---- 밀치기·넉백 ----
const PUSH_RANGE := 1.8
const PUSH_HALF_ANGLE_DEG := 60.0
const PUSH_COOLDOWN_MS := 600.0
const PUSH_KB_SPEED := 4.2
const PUSH_KB_UP := 3.0
const PUSH_DAMAGE := 10 # DAMAGE_GAIN.push
const DAMAGE_KB_BASE := 0.7
const DAMAGE_KB_PER_PERCENT := 0.01
const STUN_MS := 500.0
const COMBO_MS := 1400.0
const COMBO_IFRAME_MS := 300.0
const COMBO_LIGHT_KB := 0.6
const COMBO_FINISH_KB := 1.3
const CRIT_MIN_HEIGHT := 0.3
const CRIT_DAMAGE_MULT := 1.5
const CRIT_KB_MULT := 1.25
const CRIT_HITSTOP_MULT := 2.0
const HITSTOP_MS := 90.0

# ---- 용암 ----
const LAVA_TRIGGER_AVG_HEIGHT := 1.0
const LAVA_START_Z := -1.0
const LAVA_RISE_MS_PER_CELL := 16000.0

# ---- 봇 (헤드리스 자동 확인용 아주 단순한 입력) ----
const BOT_THINK_MS := 100.0
