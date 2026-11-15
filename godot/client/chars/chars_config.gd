# G2 고도에만 필요한 수치 (PLAN 7절: 묶음 폴더의 <묶음>_config.gd). JS 수치는 core/config.gd
extends RefCounted

const Opts := preload("res://core/opts.gd")

# 몸 조각 합치기 (JS client/batch.js 와 같은 뜻): 움직이는 노드마다 그 아래 같이 움직이는 조각을 재질 종류마다 메시 하나로 (색은 정점 색).
# false 면 조각마다 MeshInstance3D (확인용 — 그리기 수가 몸 하나에 약 100+)
# (2026-10-31 Skeleton3D 한 메시 판은 1인칭에서 몸이 화면을 덮고 하얀 조각이 보이고, 숨긴 조각도 삼각형을 그려서 바꿈)
const MERGE := true
# 합칠 때 툰 조각 전부를 G3.batch_mesh (뼈 = 조각, 숨김 = 뼈 크기 거의 0) 로 몸 한 메시 — 몸 하나 = 툰 1 + 외곽선 1 + 눈 basic·체크 무늬 조각
# false 면 움직이는 노드마다 재질 종류별 메시 (그리기 3인칭 8명 ~510). (c965e42 의 내 뼈 판은 대기실·초상에서 몸이 찌그러져 버림)
const SKIN := true
# 래그돌 (chars/ragdoll.gd, JS client/ragdoll.js): false 면 끔 (figureAnim 자세 그대로)
const RAGDOLL := true
const RAGDOLL_TIME_MIN := 0.05 # 래그돌 물리 시간 배율 하한 (히트스톱 0 이어도 나눗셈이 안 터지게)
const RAGDOLL_SLEEP_MS := 350.0 # 모터가 다 센 채로 이만큼 지나면 래그돌 강체를 쉼 (물리 비용 없음, 자세는 figureAnim 그대로). 맞음·경직·낙사면 바로 깸
const RAGDOLL_FALL_RECOVER_S := 0.3 # W52 낙하 (RAGDOLL_FALL_Z 아래) 가 끝난 뒤 모터가 힘 빠진 값에서 1 로 돌아오는 시간 (초, 0 이면 예전처럼 한 프레임)
const RAGDOLL_SNAP_DEV_DEG := 30.0 # W52 물리 자세가 목표에서 이 각 (도) 넘게 멀 때만 snap 이 오르는 속도를 제한
const RAGDOLL_SNAP_RISE_PER_S := 3.0 # W52 위 제한: snap 이 오르는 속도 (/초). 0.6 까지 0.2초
const RAGDOLL_SLEEP_DEV_DEG := 15.0 # W52 쉬기 전 물리 자세가 목표에서 이 각 (도) 안이어야 (아니면 더 기다림·쉴 때 블렌드)
const RAGDOLL_SLEEP_WAIT_MS := 700.0 # W52 위 조건이 안 돼도 이만큼 (ms) 더 기다린 뒤엔 쉬면서 블렌드
const RAGDOLL_SLEEP_BLEND_DPS := 900.0 # W52 쉴 때 블렌드 길이 = 자세 차이 (도) ÷ 이 값 (초)
const RAGDOLL_SLEEP_BLEND_MAX_S := 0.25 # W52 위 상한
const RAGDOLL_WAKE_BELOW := 0.95 # 모터가 이보다 약할 때만 깨어 있음 (맞음·경직 회복 끝 무렵 0.95~1 은 물리가 목표와 거의 같아 쉼)
# 1인칭 팔 SubViewport 다중 샘플 = 판 화면과 같음 (JS viewmodel 은 판과 같은 캔버스 = antialias) → world/world_config.gd msaa_3d (웹·PC·그래픽 낮춤)
# W7 구운 몸 (assets/models/<캐릭터>.glb, 레포 뿌리 tools/bake-bodies.mjs): 있으면 그 파일로 몸을 만듦 (조립·묶기 없음). false 면 늘 예전 조립 (chars/data/bodies.bin)
const GLB := true

# W11 탱크 1인칭 방패를 왼손에 쥠 (재혁 2026-11-03: 3·4타 때 1인칭에서 방패가 손에 없이 몸에 고정됨 — JS viewmodel 은 허리에 붙은 채, 고도만 고침).
# 방패 자리·방향을 정하고 왼손을 방패 안쪽 손잡이로 IK (viewmodel.gd _hold_shield). false 면 예전 (허리에 붙음, JS 와 같음)
const VM_SHIELD_HAND := true
const VM_SHIELD_GRIP := [0.16, 0.0, 0.0] # 손잡이 점 (방패 좌표, 크기 VM_SHIELD[0] 곱하기 전): 바깥면 (돌기) 이 -x 라 안쪽 +x — 판 반 두께 + 주먹 반지름
# 방패 가운데 (허리 좌표: 앞 +x, 왼쪽 +y, 위 +z, 어깨 높이 z 0.604) · 바깥면 방향 [돌림 (앞에서 왼쪽 +), 들림 (위로 +)]
const VM_SHIELD_GUARD := [0.4, 0.28, 0.57, 0.6, -0.25] # 쥐고 든 자세 (화면 왼쪽 아래 비스듬히 — 예전 자리, 안쪽 면이 카메라 쪽)
const VM_SHIELD_LOW := [0.14, 0.36, 0.17, 0.6, -0.6] # 꺼내기 전·넣은 뒤 (팔을 내린 화면 밖 아래)
const VM_SHIELD_IN_S := 0.18 # 방패 동작이 시작되면 이만큼 동안 손을 내려 방패를 쥐고 들어 올림 (앞 VM_SHIELD_REACH 몫은 빈손으로 내려감)
const VM_SHIELD_OUT_S := 0.2 # 방패 동작이 끝나면 이만큼 동안 방패를 내려 넣고 손이 원래 자리로
const VM_SHIELD_REACH := 0.4
const VM_SHIELD_ARM_SLACK := 0.005 # 팔 길이 (윗팔 + 아래팔) 보다 이만큼 안쪽까지만 (IK 가 늘 닿게)
# 동작별 밀치기 (준비 = W 로 당김, 타격 = W → S 로 밀침, 회복 = S → 0 으로 복귀): [앞, 왼쪽, 위, 돌림, 들림] 을 쥔 자세에 더함
const VM_SHIELD_PUSH := {
	"방패 올려치기": {"W": [-0.08, 0.02, -0.06, 0.0, -0.2], "S": [0.07, 0.0, 0.08, -0.1, 0.5]},
	"방패 내려치기": {"W": [-0.05, 0.0, 0.08, 0.0, 0.35], "S": [0.07, 0.0, -0.08, -0.1, -0.45]},
	"tankCharge": {"W": [0.0, 0.0, 0.0, 0.0, 0.0], "S": [0.06, 0.0, 0.0, -0.15, 0.0]},
}

# W14 외부 뼈대 모델 (assets/models/ext/<캐릭터>.glb, chars/external.gd, 안내 chars/EXTERNAL.md): 있으면 그 모델 (→ 없으면 구운 몸 → 코드 조립).
# 지금 들어 있는 건 시험용 로봇 하나 (탱크 자리) 였는데, 2026-11-05 Tripo 모델 (탱크·닌자·사냥꾼) 이 들어와 기본 켬 — 끄려면 실행 인자 --no-ext (모델이 없는 캐릭터는 구운 몸 → 코드 몸, 테스트는 Body.use_ext)
const EXT := true
# 조정 값 기본 (모델마다 assets/models/ext/<캐릭터>.json 이 덮음): bones 뼈 이름 덮어쓰기 {우리 관절: 모델 뼈} · yaw 앞 방향 (도, glTF 앞 +Z → 게임 앞 = 90) ·
# height 키 배율 (PLAYER_HEIGHT × FIGURE_SCALE 기준) · offset 몸 기준 옮김 [x, y, z] (고도 좌표, m) · tint 몸 색 "keep" 텍스처 그대로 / "band" + 허리 플레이어 색 띠 / "tint" 곱함 (tint_k) ·
# band 띠 [반지름, 두께, 뼈 따라 올림] (모델 키 비율) · band_joint 띠를 붙일 관절 · keep 안쪽 몸에서 남길 소품 (refs 키, 예 "shields") · attach 따로 받은 물건 [{glb, joint, pos, rot, scale}] ·
# vm_from 1인칭 팔에 남길 부분 ("elbow" 팔꿈치 아래 = 예전 1인칭과 같음, "shoulder") · vm_node 1인칭 팔 메시 노드 이름 (glb 안에 따로 만든 닫힌 팔, 있으면 삼각형 가르기 안 함) · vm_snap 1인칭에서 우리 관절 자리에 붙일 관절 (팔꿈치 → 손이 예전 1인칭 자리) · clips 동작 이름 → 모델 클립 이름 (play_clip 예)
# W34 skin_mask {메시 노드 이름: 몸 색 칸 마스크 텍스처 경로} — tint "mask" 몸이 꼭짓점 UV2 대신 이 그림 (한 채널, 칸 = 흰, tools/blender/tripo/relod.py·maskbake.py 가 굽음) 을 읽음 (판 LOD 의 칸 경계가 알베도와 텍셀 단위로 맞음). 없는 메시는 예전 꼭짓점 판정
# W19 (tools/blender 고퀄 모델): lods {stage, high, medium, low} = 화면·화질별로 그릴 메시 노드 이름 (stage = 대기실 큰 캐릭터·초상·1인칭 팔, 나머지 = 판 화질) ·
# faces {idle, hit, attack} 표정 텍스처 (이름이 <id>_face 인 재질에 끼움 — 맞음·경직 = hit, 공격 동작 = attack) · toon_steps 툰 3단 (칠한 그늘이 있으면 부드럽게) ·
# label_lift 머리 위 이름표 올림 (m, 모델이 코드 몸보다 클 때) · face_glow 얼굴 재질이 제 색으로 빛남 (가림형: 투구 안 어둠의 눈) · outline 외곽선 굵기 배율 (C.OUTLINE_THICKNESS ×, 얼굴엔 안 그림) · rim [세기, 거듭제곱] 가장자리 빛 · tint "mask" 면 몸 색 칸 (UV2.x = 1) 만 플레이어 색을 곱함
const EXT_DEFAULTS := {"bones": {}, "yaw": 90.0, "height": 1.0, "offset": [0, 0, 0], "tint": "band", "tint_k": 0.6, "band": [0.17, 0.035, 0.0], "band_joint": "waist",
	"keep": [], "attach": [], "vm_from": "elbow", "vm_snap": ["elbow"], "vm_node": "", "clips": {}, "cloth": [], "lods": {}, "dash_wrist": {}, "vm_bone_scale": {}, "skin_mask": {}, "faces": {}, "outline": 1.0, "rim": [0.0, 3.0], "rope_bone": ""}
# rope_bone 갈고리 밧줄이 나가는 모델 뼈 이름 끝 (예 "LeftHandMiddle4", world/hook_fx.gd hand — 코드 손 관절은 모델 손과 20 cm 어긋남)
# W23 동작 클립 (chars/ext_clips.gd): 클립 층 섞기 — 들어갈 때·나갈 때 속도 (/초, cw 가 0↔1), 래그돌 모터가 이보다 약하면 코드 (물리) 로, 클립 바뀔 때 크로스페이드 초
const EXT_CLIP_IN := 14.0
const EXT_CLIP_OUT := 30.0
const EXT_CLIP_MOTOR_MIN := 0.9
const EXT_CLIP_FADE_S := 0.10
# W38 맞음 움찔 (external.gd _hit_flinch): 맞은 뒤 FLINCH_S 초 동안 척추 둘·머리 뼈 [이름, 비율] 을 RAD × 세기 (hit.pow 0.4~2) 만큼 젖힘, 감쇠 시간 DECAY_S
const EXT_HIT_FLINCH_S := 0.30
const EXT_HIT_FLINCH_DECAY_S := 0.09
const EXT_HIT_FLINCH_RAD := 0.18
const EXT_HIT_FLINCH_BONES := [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 0.6], ["mixamorig_Head", 0.8]]
const EXT_HIT_FACE_S := 0.45 # 맞은 뒤 이만큼 (초) '맞음' 표정
# W40 가산 동작 (chars/ext_motion.gd + external.gd _extra_layer): 시선·머리 추적, 숨쉬기, 착지 숙임, 맞음 방향별 반응 — 코드·클립 위에 뼈 회전만 더함
const EXT_GAZE_MAX_DEG := 35.0 # 머리·윗몸이 몸 앞에서 돌아갈 수 있는 한계
const EXT_GAZE_DIST := 7.0 # 이 거리 (m) 안의 가장 가까운 몸을 쳐다봄
const EXT_GAZE_FOV := 1.9 # 몸 앞 ±이 각 (라디안) 안의 몸만 (뒤에 있는 몸은 안 돌아봄)
const EXT_GAZE_RATE := 5.0 # 따라가는 빠르기 (/초)
const EXT_GAZE_W_RATE := 4.0 # 켜고 끄는 가중치 빠르기 (/초)
const EXT_GAZE_BONES := [["mixamorig_Spine2", 0.2], ["mixamorig_Neck", 0.35], ["mixamorig_Head", 0.45]] # 합 1.0 = 한계 각 전부
const EXT_GAZE_HIT_OFF_S := 0.45 # 맞은 직후 이만큼은 시선 끔
const EXT_BREATH_PERIOD := Vector2(2.6, 3.8) # 숨쉬기 한 번 (초) 범위, 캐릭터마다 이 안에서
const EXT_BREATH_RAD := 0.016 # 숨쉬기 가슴 젖힘 (라디안)
const EXT_LAND_BEND_RAD := 0.36 # 착지 무릎 굽힘 최대 (허벅지 앞 α, 정강이 −2α)
const EXT_LAND_LEAN_RAD := 0.2 # 착지 윗몸 숙임
const EXT_HIT_CRIT_POW := 1.5 # 이 세기 이상 맞음 = 치명·강타 (머리 채찍·손 흔들림)
const EXT_HIT_TWIST := 0.5 # 옆에서 맞으면 몸통이 비틀리는 비율
const EXT_HIT_WHIP_RAD := 0.3
const EXT_HIT_HAND_RAD := 0.35
const EXT_HIT_CRIT_S := 0.5
const EXT_ARMOR_BREAK_S := 0.45 # 탱크 방어구 깨짐: 방패 쥔 팔 반동 시간
const EXT_ARMOR_BREAK_RAD := 0.5

# W43 클립 크로스페이드 (초): 클립 바뀔 때 종류 (ext_clips.select 의 kind) 에 따라. 공격 들어갈 때는 칼같이 (EXT_CLIP_FADE_S), 나올 때·서기↔걷기·달리기·착지는 길게 — tools/clip_pops.gd 가 잰 자세 차이 (최대 70~120°) 가 0.1 초에 몰려 튀던 것
const EXT_RESTART_BACK_S := 0.12 # W44 같은 공격 클립의 시각이 이만큼 (초) 넘게 거꾸로 가면 '다시 시작' → 크로스페이드
const EXT_RUN_HYS := 0.08 # W44 걷기↔달리기 문턱 (run_from, 속도 비율) 히스테리시스 폭
const EXT_FADE_ADAPT_DPS := 900.0 # W52 페이드 길이 = 이음 자세 차이 (도) ÷ 이 값 (초) 로 늘림 — 차이 90° 면 0.1초, 172° 면 0.19초. 기본 길이보다 짧아지진 않음
const EXT_FADE_ADAPT_MAX_S := 0.24 # W52 위 늘림 상한 (공격 타이밍이 너무 밀리지 않게)
const EXT_FADE_LOCO_S := 0.18 # 서기·걷기·달리기·착지 사이
const EXT_FADE_ACT_OUT_S := 0.20 # 공격·스킬·도발·승리 끝 → 다른 클립
const EXT_FADE_LAND_S := 0.14 # 점프·낙하 → 착지
# W43 방향 이동 (스트레이프·후진): 몸은 조준 방향을 보고 이동은 따로라, 몸 기준 이동 방향에 맞춰 걷기·달리기 클립을 거꾸로 틀고 (뒤로 걸음) 골반을 이동 쪽으로 돌린 만큼 척추를 되돌림 (옆걸음).
# 서버 이동·판정은 그대로 — 뼈 회전만.
const EXT_DIR_MIN_SPEED := 0.9 # 이 속도 (m/s) 아래면 방향 안 따짐
const EXT_DIR_REV_ENTER_DEG := 105.0 # 이동 방향이 몸 앞에서 이만큼 넘게 벗어나면 '뒤로 걸음' (거꾸로 재생)
const EXT_DIR_REV_LEAVE_DEG := 75.0 # 이만큼 안으로 돌아오면 다시 앞으로 (히스테리시스)
const EXT_DIR_GAIN := 1.0 # 골반 yaw = 이동 방향 (앞 기준으로 접은 각) × 이 값 (W46: 0.6 → 1.0 — 다리 걸음 축이 이동 방향과 맞아야 디딘 발이 안 끌림)
const EXT_DIR_COUNTER := [["mixamorig_Spine", 0.5], ["mixamorig_Spine1", 0.3], ["mixamorig_Spine2", 0.2]] # W46: 골반을 돌린 만큼 윗몸이 되돌리는 몫 (척추 셋에 나눔 — 한 뼈에 몰면 벨트가 비틀려 늘어남). 합 1
const EXT_DIR_MAX_DEG := 70.0 # 골반 yaw 한계 (W46: 45° → 70°, 옆걸음 발 미끄러짐 비 0.75~0.9 → 0.3 — tools/gait_qa.gd)
# W47 걸음 되돌리기 (`-- --old-gait`, 웹 `?old-gait=1`): W46 이 달리기 박자를 1.6 → 0.5~0.75 로 늦춰 (걸음 수 닌자 8.4 → 2.6/초 …) 재혁이 눈으로 비교하려고 W34/W43 값으로 되돌리는 스위치.
# stride = 캐릭터 → {클립: [보폭 k, c, 박자]} (W46 전 ext/*.json clips.stride), 방향 이득·한계·윗몸 되돌림은 W46 전 값 (되돌림 비면 예전처럼 waist 한 뼈에 몰음)
const EXT_GAIT_OLD := {
	"stride": {
		"ninja": {"walk": [1.4, -0.1, 1.6], "run": [1.45, -0.14, 1.6]},
		"tank": {"walk": [1.4, -0.03, 1.6], "run": [1.45, -0.07, 1.6]},
		"hunter": {"walk": [1.4, -0.03, 1.6], "run": [1.45, -0.08, 1.6]},
		"hook": {"walk": [1.4, -0.04, 1.6], "run": [1.45, -0.08, 1.6]},
	},
	"dir_gain": 0.6,
	"dir_max_deg": 45.0,
	"dir_counter": [],
}


static func old_gait() -> bool:
	return Opts.args().has("--old-gait") or not flag("gait_new")


# ---------- W49 모션 가산 층 플래그 (설정 창 '모션' · 실행 인자 · 테스트가 같은 길) ----------
# 이름 → 기본값 (켜짐 = 지금 모습 그대로). 순서·글은 설정 창 개별 토글 표시용 (EXT_MOTION_LABELS).
# gait_new = 걸음 박자·보폭·옆걸음 이득 새값 (W46, 끄면 `--old-gait` 와 같은 옛값) · dir = 방향 이동 블렌드 (뒤로 걸음 클립 거꾸로·옆걸음 골반 yaw·팔 흔들림 폭, W43)
# lean = 이동 기울임·방향 전환 비틀림 (W43) · getup = 일어나기 (W43) · weapon = 무기 처짐·흔들림 (W43) · cloth = 천 시뮬 (끄면 천 뼈가 쉬는 자세로 돌아가 멈춤)
# pop_fix = W52 튐 줄이기 (크로스페이드 슬러프 호 고정·래그돌 복귀 블렌드·공격 구간 다리 이음, 끄면 W49 와 같음) · gaze = 시선·머리 추적 (W40) · land_breath = 착지 숙임·숨쉬기 (W40) · hit_dir = 맞음 방향별 움찔 (W40, 끄면 W38 처럼 뒤로 젖힘만) · vm_arm = 1인칭 팔 클립 구동 (W43)
const EXT_MOTION_FLAGS := {
	"gait_new": true, "dir": true, "lean": true, "getup": true, "weapon": true,
	"cloth": true, "gaze": true, "land_breath": true, "hit_dir": true, "vm_arm": true, "pop_fix": true,
}
const EXT_MOTION_LABELS := {
	"gait_new": "걸음 박자 새값 (끄면 옛값)", "dir": "방향 이동 블렌드 (옆·뒤 걸음)", "lean": "이동 기울임·방향 전환", "getup": "일어나기", "weapon": "무기 처짐",
	"cloth": "천 시뮬", "gaze": "시선 추적", "land_breath": "착지·숨쉬기", "hit_dir": "맞음 방향별 움찔", "vm_arm": "1인칭 팔 클립 구동", "pop_fix": "튐 줄이기 (이음·복귀)",
}
# 프리셋 = 이 표 값의 묶음. new = 지금 그대로, old = v0.1.17 이전 (W46 이전 걸음 + W43 가산 넷 끔, W40 가산·W44 천 수정은 유지), min = 클립 + 코드 자세만 (가산 층 전부 끔)
const EXT_MOTION_PRESETS := {
	"new": {"gait_new": true, "dir": true, "lean": true, "getup": true, "weapon": true, "cloth": true, "gaze": true, "land_breath": true, "hit_dir": true, "vm_arm": true, "pop_fix": true},
	"old": {"gait_new": false, "dir": false, "lean": false, "getup": false, "weapon": false, "cloth": true, "gaze": true, "land_breath": true, "hit_dir": true, "vm_arm": false, "pop_fix": false},
	"min": {"gait_new": false, "dir": false, "lean": false, "getup": false, "weapon": false, "cloth": false, "gaze": false, "land_breath": false, "hit_dir": false, "vm_arm": false, "pop_fix": false},
}
const EXT_MOTION_PRESET_NAMES := {"new": "새 모션 (기본)", "old": "옛 모션 (v0.1.17 이전)", "min": "최소 (코드 자세만)", "custom": "직접 고름"}
# `--no-w43` = 이 넷 (W43 가산 층 전부). 인자 이름 = `--no-` + 플래그 (밑줄은 -), 예: `--no-gaze` `--no-land-breath` `--no-gait-new` (= `--old-gait`)
const EXT_NO_W43 := ["dir", "lean", "getup", "weapon"]

static var _set := {} # 설정 창이 정한 값 (이름 → bool). 비면 기본값
static var _arg := {} # 인자가 끈 것 (이름 → true), refresh() 가 Opts.args() 에서 읽음 — 인자가 설정보다 우선 (끄는 쪽 합집합)
static var _arg_ready := false


# 설정 값 (View.settings.motionFlags) 을 받음. 모르는 이름은 버리고 빠진 것은 기본값
static func set_flags(d) -> void:
	_set = {}
	if d is Dictionary:
		for k in EXT_MOTION_FLAGS:
			if d.has(k):
				_set[k] = bool(d[k])


# 실행 인자 (`--motion old|min`, `--no-w43`, `--no-<플래그>`, `--old-gait`) 를 읽어 끄는 목록을 만듦. 인자가 바뀌는 테스트는 부름
static func refresh() -> void:
	_arg = {}
	var a := Opts.args()
	if a.has("--no-w43") or OS.get_cmdline_args().has("--no-w43"):
		for n in EXT_NO_W43:
			_arg[n] = true
	var mi := a.find("--motion")
	if mi >= 0 and mi + 1 < a.size() and EXT_MOTION_PRESETS.has(str(a[mi + 1])):
		var pr: Dictionary = EXT_MOTION_PRESETS[str(a[mi + 1])]
		for n in pr:
			if not bool(pr[n]):
				_arg[n] = true
	for n in EXT_MOTION_FLAGS:
		if a.has("--no-" + str(n).replace("_", "-")):
			_arg[n] = true
	if a.has("--old-gait"):
		_arg["gait_new"] = true
	_arg_ready = true


static func flag(name: String) -> bool:
	if not _arg_ready:
		refresh()
	if _arg.has(name):
		return false
	return bool(_set.get(name, EXT_MOTION_FLAGS.get(name, true)))


# 실행 인자가 꺼 둔 플래그 이름들 (표 순서) — 설정 창이 '설정보다 우선' 안내를 띄움
static func arg_off_names() -> Array:
	if not _arg_ready:
		refresh()
	var out := []
	for n in EXT_MOTION_FLAGS:
		if _arg.has(n):
			out.append(n)
	return out


# 설정 값 → 지금 프리셋 이름 ("new"·"old"·"min", 아니면 "custom")
static func preset_of(d) -> String:
	for pn in EXT_MOTION_PRESETS:
		var ok := true
		for k in EXT_MOTION_FLAGS:
			var v: bool = bool((d as Dictionary).get(k, EXT_MOTION_FLAGS[k])) if d is Dictionary else bool(EXT_MOTION_FLAGS[k])
			if v != bool(EXT_MOTION_PRESETS[pn][k]):
				ok = false
				break
		if ok:
			return str(pn)
	return "custom"


# 프리셋 값 묶음 (복사본)
static func preset_flags(pn: String) -> Dictionary:
	return (EXT_MOTION_PRESETS.get(pn, EXT_MOTION_PRESETS["new"]) as Dictionary).duplicate()


# 판 중 단축키: 새 모션이면 옛 모션으로, 그 밖 (옛·최소·직접) 이면 새 모션으로
static func toggled_preset(d) -> String:
	return "old" if preset_of(d) == "new" else "new"


# 클립 걸음 설정 [k, c, 박자] (없으면 null). cc = cfg.clips (read_cfg 가 "char" 를 심어 둠)
static func stride_of(cc: Dictionary, clip: String):
	return stride_of_mode(cc, clip, old_gait())


# 같은 값을 걸음 모드를 정해서 (old = 옛값) — 설정이 바뀔 때 앞·뒤 모드의 보폭을 섞어 부드럽게 옮기려고
static func stride_of_mode(cc: Dictionary, clip: String, old: bool):
	if old:
		var t: Dictionary = (EXT_GAIT_OLD.stride as Dictionary).get(str(cc.get("char", "")), {})
		if t.has(clip):
			return t[clip]
	return (cc.get("stride", {}) as Dictionary).get(clip)


static func dir_gain() -> float:
	return float(EXT_GAIT_OLD.dir_gain) if old_gait() else EXT_DIR_GAIN


static func dir_max_deg() -> float:
	return float(EXT_GAIT_OLD.dir_max_deg) if old_gait() else EXT_DIR_MAX_DEG


static func dir_counter() -> Array:
	return EXT_GAIT_OLD.dir_counter if old_gait() else EXT_DIR_COUNTER


const EXT_DIR_RATE := 9.0 # 골반 yaw 따라가는 빠르기 (/초)
const EXT_DIR_FADE_S := 0.16 # 앞↔뒤 재생이 바뀔 때 크로스페이드 (초)
# W43 이동 기울임: 속도에 비례해 앞으로 (0~) + 가속·급정지 (가속도 m/s², 멈추면 뒤로 젖힘) + 뒤로 걸을 땐 살짝 뒤로. 라디안
const EXT_LEAN_SPEED_RAD := 0.07 # 달리기 속도 (MOVE_SPEED) 에서의 앞 숙임 (≈4°)
const EXT_LEAN_ACC_K := 0.004 # 가속도 1 m/s² 당
const EXT_LEAN_ACC_MAX := 0.12 # 가속·급정지 기울임 한계 (≈7°)
const EXT_LEAN_BACK_RAD := 0.05 # 뒤로 걸을 때 윗몸 뒤로
const EXT_LEAN_RATE := 10.0
const EXT_LEAN_BONES := [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 0.5], ["mixamorig_Head", -0.4]]
# W43 방향 전환: 이동 방향 (월드) 이 돌아가는 빠르기 (rad/s) × K 만큼 윗몸이 새 방향으로 비틀리고 (한계 MAX) 두 팔이 서로 반대로 반동
const EXT_TURN_MIN_SPEED := 1.5
const EXT_TURN_K := 0.045
const EXT_TURN_MAX_RAD := 0.30
const EXT_TURN_ARM_RAD := 0.35 # 비틀림 최대일 때 팔 앞뒤 반동
const EXT_TURN_RATE := 12.0
const EXT_TURN_BONES := [["mixamorig_Spine1", 0.5], ["mixamorig_Spine2", 0.5]]
# W43 일어나기 (경직이 풀려 땅에 닿은 뒤 · 부활 직후): 웅크린 자세에서 손을 짚고 한 발 내딛으며 일어남 (가산, 래그돌 모터가 돌아오는 만큼 섞임). 라디안
const EXT_GETUP_S := 0.7 # 전체 길이 (초)
const EXT_GETUP_TORSO := 0.45 # 윗몸 앞 숙임 (시작 값, 일어나며 0 으로)
const EXT_GETUP_ARM := 0.9 # 손 짚으러 팔이 앞으로 뻗는 양
const EXT_GETUP_LEG := 0.45 # 앞발 허벅지 앞 (뒷발은 0.5 배 뒤로 + 무릎 꿇음)
const EXT_GETUP_MOTOR := Vector2(0.12, 0.5) # 래그돌 모터가 이 구간에서 0 → 1 로 섞임 (몸이 완전히 축 늘어졌을 땐 안 함)
const EXT_GETUP_SPAWN_GAP_S := 0.5 # 몸이 이만큼 (초) 숨었다 다시 보이면 (부활·판 시작) 낮은 세기로 일어나기부터
const EXT_GETUP_SPAWN_AMP := 0.5
# W43 무기 무게·흔들림: 무기를 든 손뼈 (또는 등 칼처럼 몸에 붙은 뼈) 가 월드에서 움직이는 가속도 (걸음 통통·달리기·급정지) 를 용수철-댐퍼에 넣어 무기가 한 박자 늦게 처지고 흔들림. 공격·도발·승리·경직 중엔 꺼짐 (클립·코드·물리가 맡음).
# joint = 돌릴 관절, src = 가속도를 잴 관절 (기본 joint), gp = 앞뒤 가속도 (몸 기준 +앞) → 윗쪽이 뒤로 처지는 +, gy = 위 가속도 → 같은 축, gr = 옆 가속도 → 좌우 기울기, k·c = 용수철·댐퍼, max = 한계 (라디안), droop = 걷기·달리기 속도 비례 정적 처짐 (+ = 뒤, − = 앞으로 숙임), share = 윗팔 쪽에도 나눠 주는 비율
const EXT_WEAPON_ACC_MAX := 60.0 # 가속도 한계 (m/s²) — 공격 휘두름 스파이크 자름
const EXT_WEAPON_W_RATE := 8.0
const EXT_WEAPON := {
	"tank": [{"joint": "hand_R", "gp": 0.010, "gy": 0.0, "gr": 0.006, "k": 90.0, "c": 9.0, "max": 0.35, "droop": -0.14}], # 해머: 머리가 무거워 걸을 때 앞으로 처지고 급정지에 앞으로 쏠림
	"hunter": [{"joint": "hand_R", "gp": 0.004, "gy": -0.010, "gr": 0.003, "k": 70.0, "c": 7.0, "max": 0.28, "droop": 0.0}], # 소총: 어깨끈에 걸린 듯 달리면 총구가 위아래로 까딱
	"hook": [{"joint": "hand_L", "gp": 0.008, "gy": -0.010, "gr": 0.006, "k": 80.0, "c": 8.0, "max": 0.30, "droop": 0.0}], # 갈고리 팔: 걸음 반동
	"ninja": [{"joint": "torso", "src": "hips", "gp": 0.004, "gy": 0.0, "gr": 0.005, "k": 60.0, "c": 6.0, "max": 0.07, "droop": 0.0}], # 등 칼: 칼이 몸 메시에 붙어 있어 단독 흔들림은 못 하고 윗몸 약한 늦음만
}
# W43 달릴 때 팔 흔들림 폭: 클립 속도 기준 (걷기 = MOVE_SPEED × 0.5, 달리기 = MOVE_SPEED) 에서 속도가 벗어난 비율만큼 (범위 안으로)
const EXT_ARM_SWING_RANGE := Vector2(0.8, 1.25)
# W40 1인칭 팔을 3인칭 클립 (평타·스킬) 곡선으로: 클립이 코드 자세에서 얼마나 벗어났나 (뼈 지역 회전 차이) 를 1인칭 쌍둥이 팔에 이 비율로 더함 (0 = 끔)
const VM_CLIP_ARM := 1.0 # W43: 전체 배율 (0 = 끔). W40 은 손까지 섞어 0.3·0.55 에서 소총·갈고리 쥔 팔이 솟아 끔 → W43 은 손 방향 고정 + 어깨·팔꿈치만 (아래 VM_CLIP_ARM_K), 전후 docs/w43/
const VM_CLIP_ARM_BONES := ["shoulder_R", "elbow_R", "hand_R", "shoulder_L", "elbow_L", "hand_L"]
# W43 1인칭 팔 클립 곡선 다시 시험 (안전한 방식): 손 뼈의 클립 차이는 안 받고 (쥔 손·무기 방향 고정 — 손의 전역 회전을 되돌림) 어깨·팔꿈치 회전만 캐릭터별 비율 [어깨, 팔꿈치] (0~0.3) 로 섞음.
# VM_CLIP_ARM 은 전체 배율 (0 = 끔). 어깨 회전은 쌍둥이 팔꿈치가 우리 팔꿈치 관절 자리에 붙어 (vm_snap) 있어 윗팔 소매만 돌리고 손 자리는 팔꿈치 회전이 정함
const VM_CLIP_ARM_K := {"ninja": [0.2, 0.2], "tank": [0.2, 0.25], "hunter": [0.15, 0.2], "hook": [0.15, 0.2]}
const EXT_FLASH := 0.55 # 경직 하얀 깜빡임 (외부 모델은 피부 부위를 몰라서 몸 전체 하얀 발광으로)
