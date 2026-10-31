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

# ---- 자동 블록 자리 고르기 (game-placement.js) ----
const CLEAR_BIAS := 0.3 # 가중치 exp(CLEAR_BIAS × 점수). 0 이면 완전 무작위
const CLEAR_PICK_SHAPE := true # 모양도 점수로 고름
const CLEAR_SCORE := {"FILL": 4, "CLEAR": 6, "BAD_GAP": 3, "HOLE": 3}

# ---- 캐릭터 (시제품은 닌자만) ----
const CHAR_NINJA := "ninja"
const ULT_MAX := 100.0
const ULT_PER_DAMAGE := 1.0
const SKILL_CD_MS := {"ninja": 6000.0}
const SKILL_WINDUP_MS := 150.0
const SKILL_WINDUP_CHARS := ["ninja"]
const COUNTER_STUN_MULT := 1.5
const COUNTER_HITSTOP_MULT := 1.5
const STREAK_MS := 1000.0
const BASIC_CHAIN_WINDOW_MS := 500.0
const BASIC_HITSTOP_MS := 60.0
const BASIC_FINISH_HITSTOP_MS := 110.0
const BASIC_STEP_GAP := 0.6
const BASIC_FINISH_MOVE_MULT := 0.5
# 평타: windup(준비) → 판정 → rec(후딜). 중간 타 kb 는 고정, finish 타·공중 한 타짜리는 % 배율
const BASIC_ATTACKS := {
	"ninja": {
		"chain": [
			{"name": "찌르기", "windup": 60, "rec": 150, "stun": 330, "dmg": 3, "kb": 0.8, "up": 1, "step": 0.3},
			{"name": "반대 찌르기", "windup": 60, "rec": 150, "stun": 340, "dmg": 3, "kb": 0.8, "up": 1, "step": 0.3},
			{"name": "앞차기", "windup": 70, "rec": 170, "stun": 400, "dmg": 3, "kb": 0.8, "up": 1, "step": 0.3},
			{"name": "올려 차기", "windup": 120, "rec": 350, "stun": 900, "dmg": 5, "kb": 0.5, "up": 8, "step": 0.2},
		],
		"air": [
			{"name": "공중 베기", "windup": 60, "rec": 150, "stun": 400, "dmg": 3, "kb": 0.8, "up": 3, "step": 0},
			{"name": "내려 차기", "windup": 100, "rec": 450, "stun": 500, "dmg": 5, "kb": 4.6, "up": 1, "step": 0, "finish": true},
		],
	},
}
const NINJA_KB_TAKEN := 1.1
const NINJA_HIT_CD_CUT_MS := 500.0
const NINJA_BLINK_DIST := 4.0
const NINJA_BLINK_BEHIND := 0.8
const NINJA_SLASH_WIDTH := 0.8
const NINJA_SLASH_KB_SPEED := 2.5
const NINJA_SLASH_KB_UP := 2.0
const NINJA_SLASH_STUN_MS := 600.0
const NINJA_SLASH_DAMAGE := 8
const NINJA_WALLKICK_UP := 8.0
const NINJA_WALLKICK_RANGE := 1.5
const NINJA_WALLKICK_KB_SPEED := 4.0
const NINJA_WALLKICK_KB_UP := 2.0
const NINJA_WALLKICK_STUN_MS := 250.0
const NINJA_WALLKICK_DAMAGE := 2
const NINJA_EMPOWER_MS := 6000.0
const NINJA_STAR := {"windup": 60, "gap": 80, "range": 3.0, "angle": 15.0, "dmg": 2, "stun": 250, "kb": 0.6, "up": 1}
