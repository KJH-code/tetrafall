# W18 이펙트 수치 (2026-11-04, 재혁 '고도로 더 올리기' — 타격·스킬·폭발). 손맛 값은 전부 여기 한 곳 (코드에 숫자 박지 않음).
# JS 판에 없는 고도 쪽 덧칠: 빛 번쩍·불꽃 줄·연기·돌 조각·화면 히트스톱·카메라 반동·팔 반동·몸 번쩍.
# JS 와 같은 파편·고리·흔들림 (config.gd FX_*·KO_*) 은 그대로 두고 그 위에 얹음 → 화질 '낮음' 이면 위 덧칠을 다 끄고 JS 모습만 (fx/README.md)
# 재혁이 눈으로 맞출 값: HIT_TIERS (타격 단계별) · BOOM (폭발) · KICK·HITSTOP (화면) · LEVELS (화질별 수·상한)
extends RefCounted

# 타격 단계 (audio/sound_math.gd hit_tier 와 같은 이름: 소리 단계와 화면 단계가 늘 같게): light 약 · medium 중 · heavy 강 · crit 치명
# flash  = [크기 칸, ms, 세기 0~1, 모양 0 둥근 빛 · 1 십자 별] — 맞은 가슴에 번쩍
# shock  = [커지는 크기 칸, ms] — 번쩍 뒤 퍼지는 빛 고리 (카메라를 봄, 0 = 없음)
# sparks = [수, 빠르기 칸/초, 길이 칸, 수명 ms] — 밀린 쪽으로 튀는 불꽃 줄
# dust   = [수, 크기 칸] — 발밑 흙먼지 연기 (0 = 없음)
# stop   = 화면 히트스톱 ms (내가 때리거나 맞았을 때만, 그동안 화면 시계 × HITSTOP_SCALE)
# kick   = 카메라 반동 세기 (도, 1인칭 기준 — 3인칭은 KICK.third 배)
# fov    = 시야 조임 (0~1, 강·치명만 — 'zoom punch')
# vm     = 1인칭 팔 반동 세기 (칸)
# body   = 맞은 몸 하얗게 번쩍 ms (0 = 없음)
# shake_hit·shake_hurt = JS 흔들림 (FX_SHAKE_HIT·FX_SHAKE_HURT) 에 곱함. medium 1·heavy (때림 2·맞음 1.6) 은 JS 그대로
const HIT_TIERS := {
	"light": {"flash": [0.8, 90.0, 0.6, 0], "shock": [0.0, 0.0], "sparks": [3, 6.0, 0.22, 140.0], "dust": [0, 0.0], "stop": 0.0, "kick": 0.35, "fov": 0.0, "vm": 0.012, "body": 0.0, "shake_hit": 0.6, "shake_hurt": 0.7},
	"medium": {"flash": [1.5, 120.0, 0.85, 1], "shock": [1.6, 170.0], "sparks": [6, 8.0, 0.32, 180.0], "dust": [0, 0.0], "stop": 0.0, "kick": 0.8, "fov": 0.0, "vm": 0.022, "body": 60.0, "shake_hit": 1.0, "shake_hurt": 1.0},
	"heavy": {"flash": [2.3, 160.0, 1.0, 1], "shock": [2.6, 220.0], "sparks": [11, 11.0, 0.6, 240.0], "dust": [4, 0.55], "stop": 45.0, "kick": 1.6, "fov": 0.025, "vm": 0.035, "body": 90.0, "shake_hit": 2.0, "shake_hurt": 1.6},
	"crit": {"flash": [3.2, 200.0, 1.0, 1], "shock": [3.6, 260.0], "sparks": [16, 13.0, 0.8, 280.0], "dust": [6, 0.7], "stop": 70.0, "kick": 2.4, "fov": 0.045, "vm": 0.05, "body": 120.0, "shake_hit": 2.6, "shake_hurt": 2.0},
}
const HIT_SPARK_COLOR := {"light": 0xfff2c0, "medium": 0xffe08a, "heavy": 0xffa040, "crit": 0xffd030}
const HIT_FLASH_COLOR := {"light": 0xfff2c8, "medium": 0xffe6a0, "heavy": 0xffa848, "crit": 0xffc020}
# 빛 모양별 가림 (0 = 순수 가산 — 어두운 데선 같지만 밝은 잔디·하늘 위에선 거의 안 보임, 1 = 뒤를 덮음): 둥근·별·고리·줄
const GLOW_OCCLUDE := [0.45, 0.55, 0.3, 0.35]
const HIT_FLASH_FRONT := 0.7 # 맞은 가슴 번쩍을 카메라 쪽으로 이만큼 (칸) — 몸 가운데라 몸에 가려 가장자리만 보이던 것
const HIT_DUST_COLOR := 0xb8ad9c
const HIT_BODY_COLOR := 0xffffff # 맞은 몸 번쩍 (치명은 HIT_FLASH_COLOR.crit 쪽으로 섞음)
const HIT_IGNORED_FLASH := [0.6, 80.0, 0.4] # 무적이라 무시된 타: 작은 회색 빛 (크기·ms·세기)

# 화면 히트스톱: 그동안 화면 시계 (View.time_scale — 보간·몸·효과) 배율. KO 압사 KO_CRUSH_STOP_SCALE 와 같은 방식 (더 느린 쪽이 이김)
const HITSTOP_SCALE := 0.12
# 카메라 반동: ms 동안 (1-t)² 로 줄어듦. 맞음 = 위로 들리고 밀린 쪽으로 기울어짐, 때림 = 앞으로 살짝 숙임
const KICK := {"ms": 170.0, "hurt_pitch": 1.0, "hurt_roll": 0.8, "hit_pitch": -0.45, "hit_yaw": 0.25, "third": 0.45}
# 1인칭 팔 반동 ms (때림 = 팔이 몸 쪽으로 툭, 맞음 = 옆·아래로 흔들림)
const VM_KICK_MS := 160.0

# 움직임 줄이기 (설정 reducedMotion): 흔들림·반동·히트스톱·번쩍 배율 (JS 흔들림·압사 히트스톱 포함)
const REDUCED := {"shake": 0.3, "kick": 0.0, "stop": 0.0, "flash": 0.5, "fov": 0.0}

# 화질 (world/gfx_calc.gd: high·medium·low) 별 덧칠 수준. mult = 덧칠 입자 수 배율, max_* = 한 번에 떠 있는 수 상한 (풀 크기 — 넘으면 오래된 것부터 덮어씀)
# low = 덧칠 없음 (JS 모습 그대로: 파편·고리·흔들림만). 히트스톱·반동·팔 반동·몸 번쩍은 그리기 비용이 없어 낮음에서도 켬
const LEVELS := {
	"high": {"mult": 1.0, "glow": true, "smoke": true, "chunks": true},
	"medium": {"mult": 0.7, "glow": true, "smoke": true, "chunks": true},
	"low": {"mult": 0.0, "glow": false, "smoke": false, "chunks": false},
}
const MAX_GLOW := 160 # 빛 (번쩍·불꽃 줄·빛 고리·불덩이) MultiMesh 하나
const MAX_SMOKE := 64 # 연기 MultiMesh 하나
const MAX_CHUNKS := 64 # 돌·흙 조각 MultiMesh 하나 (한 번 튀고 멈춤)
const MAX_RINGS := 12 # JS 충격파 고리 (effects.js MAX_RINGS) — 예전 MeshInstance 12개 → MultiMesh 하나

# 폭발 (폭탄 boom·대포 포탄·대형 포탄·건축가 블록·바드 앰프 끝): 크기 k (1 = 폭탄) 에 곱함
# fire = [불덩이 수, 크기 칸, ms] · flash = [크기, ms] · shock = [바닥 빛 고리 크기, ms] · smoke = [수, 크기, ms, 오르는 빠르기]
# chunks = [수, 빠르기, 크기] · sparks = [수, 빠르기, 길이, ms]
const BOOM := {
	"fire": [6, 1.3, 420.0], "flash": [4.2, 160.0], "shock": [5.0, 380.0], "smoke": [7, 1.1, 1300.0, 1.1],
	"chunks": [10, 7.0, 0.16], "sparks": [12, 12.0, 0.55, 300.0],
	"fire_colors": [0xffd060, 0xff8a20, 0xff5a10], "smoke_color": 0x4a4440, "chunk_color": 0x6a5e52, "spark_color": 0xffc050,
}
# 폭발 종류별 크기 k
const BOOM_K := {"boom": 1.0, "shell": 0.55, "bigShell": 1.25, "groundShot": 0.6, "bblock": 0.5, "bigBomb": 1.3, "amp": 0.8, "muzzle": 0.35}

# 땅 충격 (탱크 내려찍기·솟는 땅·광전사 착지·소용돌이 끝·바드 꽂기·갈고리 내려찍기): 바닥 빛 고리 + 흙먼지 + 돌 조각
# shock = [크기 배율 (r 에 곱함), ms] · dust = [수, 크기, ms] · chunks = [수, 빠르기, 크기]
const QUAKE := {"shock": [2.2, 360.0], "dust": [8, 0.9, 1100.0], "chunks": [8, 6.0, 0.14], "dust_color": 0xb8a888, "glow_color": 0xffe0a0}
# 탱크 R 솟는 땅: 칸마다 흙 기둥 (아래에서 솟는 먼지) + 돌 조각
const QUAKE_RISE := {"dust": [2, 0.75, 900.0, 2.4], "chunks": [2, 5.0, 0.16]}

# KO: 낙사 스매시 (줄기 밑동 빛 + 바깥으로 불꽃 줄) · 압사 (먼지 구름 + 블록 조각) · 낙사 잔상 (사라지는 몸) · 마지막 킬 번쩍 [크기, ms] (슬로모션 화면 시계)
const KO_FX := {"smash_flash": [5.0, 260.0], "smash_sparks": [18, 16.0, 0.8, 380.0], "crush_smoke": [9, 1.2, 1400.0], "crush_chunks": [12, 7.0, 0.2], "fall_ghost_ms": 520.0, "fall_ghost_alpha": 0.55, "final": [3.5, 500.0]}

# 캐릭터 상시 효과 (JS render.js 에 있던 것, W3 남은 목록): 광전사 분노 김 · 닌자 강화 손 불티 · 바드 꽂기 속도선
# JS 값 (config.gd BERSERK_STEAM_RATE·DIVE_LINE_*) 을 그대로 쓰고, 여기엔 고도 쪽 덧칠만
const RAGE_GLOW := {"min": 0.6, "size": 1.4, "alpha": 0.35} # 분노 k 가 min 넘으면 몸 둘레 붉은 빛 (빛 MultiMesh, 낮음이면 끔)

# 효과 수준 (화질·설정) — 효과 노드가 프레임마다 한 번 정함
static func level_of(gfx_level: String, low_gfx: bool) -> Dictionary:
	if low_gfx:
		return LEVELS.low
	return LEVELS.get(gfx_level, LEVELS.medium)


# 덧칠 입자 수: 수준 배율, 0 이면 0 (낮음), 아니면 적어도 1
static func count(n: float, lv: Dictionary) -> int:
	var m := float(lv.get("mult", 1.0))
	if m <= 0.0 or n <= 0.0:
		return 0
	return maxi(1, roundi(n * m))


# 카메라 반동·팔 반동 곡선: t_ms 뒤 남은 세기 0~1 ((1-t)², 끝나면 0)
static func kick_k(t_ms: float, ms: float) -> float:
	if t_ms < 0.0 or t_ms >= ms:
		return 0.0
	var u := 1.0 - t_ms / ms
	return u * u


# 화면 히트스톱 배율: stop_until 전이면 HITSTOP_SCALE, 아니면 1
static func hit_scale(now: float, stop_until: float) -> float:
	return HITSTOP_SCALE if now < stop_until else 1.0


# 타격 단계 값 (모르는 단계는 medium)
static func tier(name: String) -> Dictionary:
	return HIT_TIERS.get(name, HIT_TIERS.medium)


# 움직임 줄이기 배율
static func reduced_k(key: String, reduced: bool) -> float:
	return float(REDUCED.get(key, 1.0)) if reduced else 1.0
