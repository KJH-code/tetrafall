# W44 — 모션 QA 자동화: 재연 전체에서 튐·떨림·발 미끄러짐·뚫림을 자동으로 찾아 고치기 (2026-11-11)

재혁의 눈 피드백 없이 **데이터로** 모션 결함을 찾는 도구를 만들고, 표의 위쪽 결함을 고쳤다. 모든 수치는 소프트웨어 렌더 (xvfb + llvmpipe) 에서 **렌더를 끈 채 뼈 포즈·월드 변환만** 읽어 쟀다 — 움직임의 맛·속도감은 수치로 못 잡으니 재혁 PC 확인이 필요하다 (맨 아래 '소프트웨어 렌더 한계').

## 1. 도구

| 파일 | 하는 일 |
| --- | --- |
| `core/motion_qa_math.gd` · `motion_qa_rot.gd` | 순수 계산 (노드·엔진 상태 없음): 팝·떨림·발 디딤·캡슐 깊이·신축 비·경첩 한계 검출기 (한 표본씩 먹이는 streaming), 임계 상수 |
| `core/motion_qa.gd` | 표본기 노드: 몸마다 뼈 포즈 (`Skeleton3D` 로컬·전역) 와 스킨 메시 일부 점·천 사슬 점·상태 (`Ext.last_st`, 클립 층 값) 를 **60Hz 시계 절대값 칸**에 맞춰 읽어 검출기에 먹임. 끝에 `motion_qa.json` (요약 + 상위 20) · `motion_qa.csv` (사건 한 줄씩) |
| `core/replay.gd` (훅 6줄) | `--motion-qa <폴더>` 를 받아 노드를 붙이고 재연 끝에 `finish()`. 가상 시계를 `Motion_.clock` 에 꽂음 |
| `main.gd` (훅 4줄) | 재혁 PC 용: `--motion-qa` (폴더 없이) = **가벼운 모드** (팝 카운터만) → 한 판 끝에 `user://motion_qa.txt` 에 '팝 상위 5개' (hitch 로거와 같은 `# ---- 판 요약` 형식). 꺼져 있으면 노드가 없어 비용 0 |
| `tools/motion_qa.mjs` | 여러 재연 결과를 캐릭터별·결함 종류별 표로 합침 (`node godot/client/tools/motion_qa.mjs <폴더> [<후 폴더>]`, 전→후 열), 상위 N 목록은 CSV 에서 |
| `tests/test_motion_qa.gd` | 합성 뼈 열로 검출기 시험 (알려진 팝·떨림·미끄러짐·뚫림·한계) + 새 모델 4명 합성 시나리오의 팝 수 상한 (회귀) |

**가상 시계 (결정적 재연)**: 몸 동작 층 (`external.gd` 클립 층·천·가산·일어나기, `body.gd` 의 맞음·동작 시각, `ragdoll.gd` 재우기) 이 `Time.get_ticks_msec()` 를 써서 느린 기계 (llvmpipe 4fps) 에서는 한 프레임 dt 가 0.1초로 잘려 클립 크로스페이드·천이 실제와 다르게 돌았다. `Motion_.now_s()` / `now_ms()` (`chars/ext_motion.gd`) 로 바꿔 평소엔 실제 시계, 재연에선 `Net.virt` (가상 시계) — 평소 동작은 그대로. `--fixed-fps 120` 과 같이 쓰면 거의 같은 결과 (닌자 새 모델 8명 판만 래그돌 물리가 비결정이라 몸 팝이 ±15 흔들림 — 연습 재연 4개는 같음).

**재연 돌리는 법** (헤드리스 `--headless` 는 world.gd 가 판 몸을 안 만들어서 쓸 수 없음 — xvfb 로 소프트웨어 렌더를 켜되 그리기는 끔):
```
xvfb-run -a godot --path godot/client --rendering-driver opengl3 --resolution 960x540 --fixed-fps 120 -- \
  --replay <녹화.rec> --replay-fps 120 --replay-secs 44 --replay-warm 0 --no-pose-lod --set third=true --motion-qa <출력 폴더>
node godot/client/tools/motion_qa.mjs <출력 폴더의 부모>
```
`--no-pose-lod` 로 먼 몸도 매 프레임 자세를 셈 (끄면 몸이 30·15Hz 로만 포즈를 받아 팝이 커 보임), `--set third=true` 는 연습 재연에서 내 몸이 3인칭으로 그려지게.
확인용: `--qa-trace <몸 id>` (발 줄·표본별 trace.csv), `--qa-bone-trace <뼈 이름>` (그 뼈의 회전·클립 층 값 btrace.csv), 끄기 스위치 (전후 비교) `--no-w43` (W43 가산) · `--no-cloth-sub` (천 서브스텝) · `--no-cloth-rate` (천 뼈 회전 속도 제한) · `--no-cloth-col` (천 몸 충돌) · `--no-run-hys` (걷기↔달리기 히스테리시스 + 클립 재시작) · `--no-clip-restart` (같은 클립 재시작만).

## 2. 무엇을 어떻게 잼

표본: 시계 절대값 60Hz 칸마다 (재연이 120fps 면 두 프레임에 하나). 임계는 **표본 한 칸 (1/60초) 당** 값.

| 결함 | 잼 | 임계 (`core/motion_qa_math.gd`) |
| --- | --- | --- |
| **팝 (튐)** | 뼈 (손가락·끝 뼈 뺌) 로컬 회전의 표본 간 각속도. **각속도가 임계를 넘고 직전 표본보다 임계의 절반 넘게 갑자기 늘 때** 한 번 (매끈히 빨라지는 달리기 다리·휘두름은 안 셈 — 그건 '빠름') | 몸통·팔다리 35°, 손·발·머리·목 60°, 천 80° (+ 약한 팝 = 절반) |
| **떨림** | 서기 (idle) 20표본 뒤부터 30표본 창마다 속도 벡터 변화 RMS (°/표본²) + 속도 방향 뒤집힘 비율 | RMS 0.25° 이상 & 뒤집힘 35% 이상 |
| **발 미끄러짐** | 발·발가락 중 낮은 쪽이 서 있는 높이 +2cm 안이고 두 발 중 낮은 (지지) 발인 표본이 6개 (0.1초) 이상 이어진 '디딤' 에서 발 월드 xz 이동 길이 ÷ 같은 동안 몸 이동 길이. 몸이 0.12m 이상 0.8m/s 이상 가는 디딤만 걸음 (앞·뒤·옆), 거의 안 가면 '정지 중 끌림' (>4cm) | 비 0.35 |
| 발 박힘·뜸 | 땅 위 상태 (서기·걷기·착지) 에서 낮은 발이 서 있는 높이 아래 3cm / 두 발이 5cm 위 | |
| **천 뚫림** | 천 사슬 점을 스킨 메시에서 잰 몸 캡슐 (몸통 2 + 허벅지 2 + 정강이 2, 반지름 = 지배 정점의 축 거리 중앙값 × 0.85) 속 깊이, 쉬는 자세에서 이미 안인 만큼 뺌 | 2cm |
| **무기 뚫림** | 손 뼈 지배 정점 중 손목에서 먼 점 (탱크 해머·방패, 사냥꾼 총…) 이 같은 캡슐 속 | 2cm |
| **삼각형 늘어남** | 뼈 경계 변 ~700개의 스킨된 길이 ÷ 쉬는 길이 (10Hz) | 표에는 ×5 이상 |
| **관절 한계** | 팔꿈치·무릎: 위·아래 뼈 방향 사이 각, 굽힘 방향은 클립에서 잰 자연 굽힘 축. 목+머리 비틀림 (스윙·트위스트 분해), 척추 누적 회전 | 반대 굽힘 −25° · 165° 넘게 접힘 · 목 70° · 척추 80° |
| **전환 이음새** | 상태 (서기·걷기·공격·공중·착지·경직·일어나기) 가 바뀐 표본의 최대 각속도 + 이후 15표본 (0.25초) 최고 | |
| 클립 깜빡임 | 땅 위 서기·걷기·달리기 사이에서 클립이 0.3초 안에 다시 바뀜 | |

**제외**: 래그돌 (모터 0.97 미만) · 경직·쓰러짐 상태와 풀린 뒤 4표본, 부활·순간이동 (0.8m↑), 이 캐릭터 클립에 없는 동작 (캐릭터만 바꿔 만든 녹화의 옛 캐릭터 기술 — 코드 자세라 검사 대상 아님), 재연이 건너뛰는 구간.

**녹화**: ① 연습 방 자동 조종 (`--auto practice --char <캐릭터> --skills 1.0 --view third --rec`, JS 서버) 45초 × 4명 — 그 캐릭터의 **진짜 평타·스킬·필살기**가 나옴 (`prac_ninja·tank·hunter·hook`) ② `new8.rec` (새 모델 8명 판, 래그돌·충돌·걷기 포함, 기술은 옛 캐릭터 것이라 걷기·서기·점프·착지·래그돌 전환용). 녹화 파일은 레포 밖 (큼).

## 3. 결과: 결함 종류별 표 (전 = 이 워커 고침 전 W43 상태 → 후)

연습 4개 (44초) + new8 (30초) 합산, 캐릭터별. 모든 칸은 `전 → 후` (같으면 한 값).

| 결함 | ninja | tank | hunter | hook |
| --- | --: | --: | --: | --: |
| 표본 (60Hz, 래그돌 제외 후) | 2947 → 2952 | 3281 → 3277 | 2965 → 2967 | 2852 → 2863 |
| **팝 (몸통·팔다리·손발머리)** 임계 35/60°·급가속 | 182 → 89 | 114 → 90 | 112 → 90 | 31 → 36 |
|   └ 약한 팝 (임계 절반) | 1205 → 831 | 542 → 405 | 1400 → 693 | 908 → 562 |
|   └ 최악 각속도 (°/프레임) | 179.1 → 167.3 | 176.8 → 70.5 | 179.3 → 67.9 | 179.8 → 152.5 |
| **천 팝** (임계 80°) | 61 → 0 | 26 → 0 | 143 → 0 | 166 → 0 |
| 떨림 창 (서 있을 때) | 0/66 | 0/132 | 0/132 | 0/132 |
| **발 미끄러짐** 나쁜 디딤/걸음 디딤 | 2/2 | 1/1 | 0/0 → 1/1 | 6/6 → 5/5 |
|   └ 앞 비 평균 · 뒤 · 옆 | 1.75 · 1.62 · - → 1.54 · - · - | 1.18 · - · - → 0.68 · - · - | - · - · - → 1.51 · - · - | 2.22 · 2.68 · - → 3.04 · 2.44 · - |
|   └ 정지 중 발 끌림 (>4cm) | 1/1 → 0/0 | 5/5 → 4/4 | 4/5 → 3/4 | 5/5 → 8/8 |
| 발 박힘 / 뜸 (땅 프레임 중) | 7 / 0 (307) | 2 / 0 (402) → 4 / 0 (402) | 5 / 0 (391) | 4 / 0 (568) → 7 / 0 (576) |
| **천 뚫림** 프레임 (>2cm) | 0/492 (최대 0m) → 0/493 (최대 0m) | 18/544 (최대 0.098m) → 0/543 (최대 0m) | 34/494 (최대 0.082m) → 0/494 (최대 0m) | 64/472 (최대 0.087m) → 1/474 (최대 0.023m) |
| **무기 뚫림** 프레임 (>2cm) | 0/0 (최대 0m) | 1/544 (최대 0.133m) → 3/543 (최대 0.115m) | 0/494 (최대 0m) | 0/0 (최대 0m) |
| **삼각형 늘어남** (몸, ×5↑) | 0/492 (최대 ×4.7) → 0/493 (최대 ×4.7) | 170/544 (최대 ×13.6) → 169/543 (최대 ×13.9) | 2/494 (최대 ×5.6) → 0/494 (최대 ×4.9) | 83/472 (최대 ×7.1) → 81/474 (최대 ×8) |
| 관절 한계: 반대 굽힘·과굽힘·목·척추 | 2 · 0 · 0 · 0 → 1 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 |
| 클립 깜빡임 (0.3초 안 재전환) | 12 | 8 | 6 | 19 → 15 |


읽는 법: 몸 팝은 **공격 phase 의 빠른 타격 (strike·wind) 이 거의 전부** — 서버 `moves` 시간이 정한 짧은 시간에 클립 한 구간을 밀어 넣어 생긴 설계값이라 안 건드림 (아래 '보류'). 천 팝 61~166 → 0, 천 뚫림 (탱크 18·사냥꾼 34·갈고리 64 프레임) → 0~1. 발 미끄러짐·삼각형 늘어남은 고치지 않음 (판정 한계·보류 참고).

### 3-1. W43 가산 (`--no-w43`) 의 영향 — 새로 만든 결함 / 없앤 결함

`--no-w43` (전) → W43 켬 (후), 고침 전 코드끼리:

| 결함 | ninja | tank | hunter | hook |
| --- | --: | --: | --: | --: |
| 표본 (60Hz, 래그돌 제외 후) | 2954 → 2947 | 3284 → 3281 | 2972 → 2965 | 2872 → 2852 |
| **팝 (몸통·팔다리·손발머리)** 임계 35/60°·급가속 | 199 → 182 | 112 → 114 | 119 → 112 | 37 → 31 |
|   └ 약한 팝 (임계 절반) | 1238 → 1205 | 520 → 542 | 1405 → 1400 | 1311 → 908 |
|   └ 최악 각속도 (°/프레임) | 179.6 → 179.1 | 172.3 → 176.8 | 179.5 → 179.3 | 179.9 → 179.8 |
| **천 팝** (임계 80°) | 57 → 61 | 31 → 26 | 136 → 143 | 306 → 166 |
| 떨림 창 (서 있을 때) | 0/66 | 0/132 | 0/132 | 0/132 |
| **발 미끄러짐** 나쁜 디딤/걸음 디딤 | 3/3 → 2/2 | 1/1 | 0/0 | 5/5 → 6/6 |
|   └ 앞 비 평균 · 뒤 · 옆 | 1.58 · - · 1.56 → 1.75 · 1.62 · - | 0.99 · - · - → 1.18 · - · - | - · - · - | 2.5 · 2.09 · 4.58 → 2.22 · 2.68 · - |
|   └ 정지 중 발 끌림 (>4cm) | 1/1 | 4/4 → 5/5 | 4/5 | 5/5 |
| 발 박힘 / 뜸 (땅 프레임 중) | 7 / 0 (308) → 7 / 0 (307) | 2 / 1 (402) → 2 / 0 (402) | 5 / 0 (391) | 4 / 0 (570) → 4 / 0 (568) |
| **천 뚫림** 프레임 (>2cm) | 0/491 (최대 0m) → 0/492 (최대 0m) | 7/545 (최대 0.112m) → 18/544 (최대 0.098m) | 35/495 (최대 0.083m) → 34/494 (최대 0.082m) | 86/476 (최대 0.086m) → 64/472 (최대 0.087m) |
| **무기 뚫림** 프레임 (>2cm) | 0/0 (최대 0m) | 3/545 (최대 0.125m) → 1/544 (최대 0.133m) | 0/495 (최대 0m) → 0/494 (최대 0m) | 0/0 (최대 0m) |
| **삼각형 늘어남** (몸, ×5↑) | 0/491 (최대 ×4.7) → 0/492 (최대 ×4.7) | 176/545 (최대 ×14.7) → 170/544 (최대 ×13.6) | 2/495 (최대 ×5.6) → 2/494 (최대 ×5.6) | 81/476 (최대 ×6.8) → 83/472 (최대 ×7.1) |
| 관절 한계: 반대 굽힘·과굽힘·목·척추 | 1 · 0 · 0 · 0 → 2 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 |
| 클립 깜빡임 (0.3초 안 재전환) | 9 → 12 | 5 → 8 | 3 → 6 | 18 → 19 |


W43 이 **없앤** 것: 갈고리 천 팝 306 → 166, 갈고리 천 뚫림 86 → 64 프레임, 갈고리 약한 팝 1311 → 908 (방향 기울임·무기 흔들림이 치마를 덜 흔듦), 닌자 팝 199 → 182. **새로 만든** 것: 땅 위 클립 깜빡임 (닌자 9→12, 탱크 5→8, 사냥꾼 3→6 — 뒤로 걸음 `~r` 클립이 문턱에서 앞뒤로 바뀜), 탱크 천 뚫림 7 → 18 프레임. 뒤쪽은 이번에 고침 (4절 ②·③).

## 4. 고친 것 (전후 수치 — 항목별 기여)

항목별로 하나씩만 끈 시험 (`abl.sh` 식, new8 30초 + 닌자 연습 44초, 같은 코드에서 스위치만):

| # | 고친 것 | 파일 | 끄면 → 켜면 |
| --- | --- | --- | --- |
| ① | **천 서브스텝**: 앵커 (몸) 가 한 걸음에 첫 마디 길이의 절반 넘게 움직이면 (돌진·회전) 앵커를 쪼개 따라가며 verlet 여러 번. 한 번에 건너뛰면 사슬이 앵커 반대쪽으로 뒤집힘 | `chars/ext_cloth.gd` | 천 팝 (new8, 갈고리·사냥꾼·닌자·탱크): 전 **156·15·36·14** → 서브스텝만 **63·6·20·5** (회전 제한 끈 채) |
| ② | **천 뼈 회전 속도 제한**: 뼈가 한 표본에 50° (3000°/초) 넘게 안 돎. 그래도 뒤집히는 순간 (한 표본 170~180°) 이 남아서 | `chars/ext_cloth.gd` | 위 → **0·0·0·0** (회전 제한 켬). 전체 연습+new8: 천 팝 61·26·143·166 → 0 |
| ③ | **천 몸 충돌**: `cloth_colliders` (몸통·허벅지·정강이 캡슐, 반지름은 QA 가 스킨 메시에서 잰 값) 으로 사슬 점이 몸 안에 들어가면 밖으로 (쉬는 자세에서 이미 안인 만큼은 봐줌) 후 마디 길이 한 번 더 | `chars/ext_cloth.gd` + `assets/models/ext/{tank,hunter,hook}.json` | 갈고리 천 뚫림 프레임 (new8) **전 29** → 충돌 끄면 31 / 켜면 **0**. 전체: 탱크 18 → 0, 사냥꾼 34 → 0, 갈고리 64 → 1 (최대 깊이 0.098m → 0.023m) |
| ④ | **같은 공격 클립 재시작 크로스페이드**: 닌자 표창 → 표창2 (같은 `star` 클립) 처럼 연달아 같은 클립이면 끝 자세에서 시작 자세로 한 표본에 137° 튀던 것을 0.1초 크로스페이드 | `chars/external.gd` `_clip_layer` | 닌자 연습 몸 팝 **148 → 38**, 최악 각속도 137.5° → 129° (클립 재시작 끔 → 켬) |
| ⑤ | **걷기↔달리기 히스테리시스**: 속도 비율이 문턱 (`run_from` 0.55) 근처에서 출렁이면 `EXT_RUN_HYS` 0.08 만큼 지금 클립 유지 | `chars/ext_clips.gd` (`select` 의 `prev_clip`) | 갈고리 깜빡임 (new8) 15 → 14 — **효과 작음** (이 녹화에선 거의 안 걸림), 다른 결함을 늘리지 않아 유지 |

전체 합산 (표 3): 몸 팝 닌자 182 → 89 · 탱크 114 → 90 · 사냥꾼 112 → 90 · 갈고리 31 → 36 (갈고리는 잡음 범위), 최악 각속도 탱크 176.8° → 70.5°, 사냥꾼 179° → 68°.

전후 그림: `cloth_hook_run_before_after.png` (갈고리 달리기 8프레임, 위 전 / 아래 후 — 소프트웨어 렌더 정지 프레임이라 치마 조각이 다리를 지나는 정도만 보임, 차이는 작음. 숫자가 근거).

## 5. 상위 20 목록 (전 = W43 상태, 고침 전)

### 몸 팝 (손가락·천 제외) 상위 20

| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | ninja | RightUpLeg | 163.89 | idle | idle | 30.9 | new8 | fade 1.00 cw 0.23 since_lab 5.98 since_clip 5.97 |
| 2 | ninja | RightLeg | 162.84 | idle | idle | 30.9 | new8 | fade 1.00 cw 0.23 since_lab 5.98 since_clip 5.97 |
| 3 | ninja | LeftUpLeg | 161.73 | idle | idle | 30.9 | new8 | fade 1.00 cw 0.23 since_lab 5.98 since_clip 5.97 |
| 4 | ninja | RightArm | 137.53 | act 표창/wind | star | 8.2 | prac_ninja | fade 1.00 cw 1.00 since_lab 1.43 since_clip 0.40 |
| 5 | ninja | RightArm | 137.53 | act 표창/wind | star | 9.2 | prac_ninja | fade 1.00 cw 1.00 since_lab 2.43 since_clip 0.23 |
| 6 | ninja | RightArm | 137.53 | act 표창/wind | star | 9.5 | prac_ninja | fade 1.00 cw 1.00 since_lab 2.73 since_clip 0.53 |
| 7 | ninja | RightArm | 137.53 | act 표창/wind | star | 10.6 | prac_ninja | fade 1.00 cw 1.00 since_lab 3.77 since_clip 0.23 |
| 8 | ninja | RightArm | 137.53 | act 표창/wind | star | 10.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 4.07 since_clip 0.53 |
| 9 | ninja | RightArm | 137.53 | act 표창/wind | star | 11.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 5.07 since_clip 0.23 |
| 10 | ninja | RightArm | 137.53 | act 표창/wind | star | 12.2 | prac_ninja | fade 1.00 cw 1.00 since_lab 5.37 since_clip 0.53 |
| 11 | ninja | RightArm | 137.53 | act 표창/wind | star | 14.6 | prac_ninja | fade 1.00 cw 1.00 since_lab 0.70 since_clip 0.23 |
| 12 | ninja | RightArm | 137.53 | act 표창/wind | star | 14.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 1.03 since_clip 0.57 |
| 13 | ninja | RightArm | 137.53 | act 표창/wind | star | 15.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 2.00 since_clip 0.20 |
| 14 | ninja | RightArm | 137.53 | act 표창/wind | star | 17.2 | prac_ninja | fade 1.00 cw 1.00 since_lab 3.33 since_clip 0.23 |
| 15 | ninja | RightArm | 137.53 | act 표창/wind | star | 17.5 | prac_ninja | fade 1.00 cw 1.00 since_lab 3.63 since_clip 0.53 |
| 16 | ninja | RightArm | 137.53 | act 표창/wind | star | 18.5 | prac_ninja | fade 1.00 cw 1.00 since_lab 4.67 since_clip 0.37 |
| 17 | ninja | RightArm | 137.53 | act 표창/wind | star | 18.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 5.00 since_clip 0.70 |
| 18 | ninja | RightArm | 137.53 | act 표창/wind | star | 22.5 | prac_ninja | fade 1.00 cw 1.00 since_lab 0.70 since_clip 0.37 |
| 19 | ninja | RightArm | 137.53 | act 표창/wind | star | 22.8 | prac_ninja | fade 1.00 cw 1.00 since_lab 1.00 since_clip 0.67 |
| 20 | ninja | RightArm | 137.53 | act 표창/wind | star | 23.9 | prac_ninja | fade 1.00 cw 1.00 since_lab 2.03 since_clip 0.23 |

### 천 팝 상위 20

| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | hook | Skirt1_1 | 179.84 | act 탕/strike | k_shot | 17.1 | new8 | fade 1.00 cw 1.00 since_lab 0.85 since_clip 0.28 |
| 2 | hook | Skirt1_1 | 179.7 | act 갈고리 스핀/rec | k_spin | 5.2 | new8 | fade 1.00 cw 1.00 since_lab 0.68 since_clip 0.28 |
| 3 | hunter | Cape3_1 | 179.34 | act 내려 베기/rec | h_dive | 1.2 | prac_hunter | fade 1.00 cw 1.00 since_lab 0.72 since_clip 0.28 |
| 4 | ninja | Scarf2 | 179.06 | act ninjaDash/rec | dash | 3.8 | prac_ninja | fade 1.00 cw 1.00 since_lab 0.58 since_clip 0.15 |
| 5 | hunter | Cape2_1 | 178.91 | act 찔러 넣기/rec | h_thrust | 10.3 | prac_hunter | fade 1.00 cw 1.00 since_lab 9.88 since_clip 0.45 |
| 6 | hunter | Cape3_2 | 178.03 | act 베기/wind | h_slash | 22.2 | prac_hunter | fade 0.08 cw 1.00 since_lab 8.20 since_clip 0.30 |
| 7 | hook | Skirt3_3 | 177.92 | act 탕/rec | k_shot | 17.2 | new8 | fade 1.00 cw 1.00 since_lab 0.98 since_clip 0.42 |
| 8 | tank | Tabard1_2 | 176.83 | land | land | 25.3 | prac_tank | fade 1.00 cw 0.12 since_lab 0.37 since_clip 0.35 |
| 9 | hook | Skirt3_3 | 176.49 | act 갈고리 내려치기/rec | k_chop | 11.2 | new8 | fade 1.00 cw 1.00 since_lab 0.30 since_clip 0.30 |
| 10 | ninja | Scarf2 | 176.47 | loco | walk | 2.3 | new8 | fade 0.14 cw 1.00 since_lab 0.05 since_clip 0.05 |
| 11 | ninja | Scarf3 | 176.45 | land | land | 22.7 | new8 | fade 1.00 cw 1.00 since_lab 0.25 since_clip 0.25 |
| 12 | ninja | Scarf2 | 176.04 | act 찌르기/rec | atk1 | 1 | prac_ninja | fade 1.00 cw 1.00 since_lab 0.02 since_clip 0.17 |
| 13 | ninja | Scarf1 | 175.39 | loco | walk | 2.3 | new8 | fade 0.28 cw 1.00 since_lab 0.07 since_clip 0.02 |
| 14 | hunter | Cape1_1 | 175.05 | act 반대 베기/rec | h_back | 39.4 | prac_hunter | fade 1.00 cw 1.00 since_lab 8.95 since_clip 0.22 |
| 15 | hook | Skirt1_3 | 174.33 | land | land | 19.1 | new8 | fade 0.95 cw 1.00 since_lab 0.12 since_clip 0.12 |
| 16 | hook | Skirt3_3 | 174.03 | act 갈고리 내려치기/rec | k_chop | 11.4 | new8 | fade 1.00 cw 1.00 since_lab 0.50 since_clip 0.50 |
| 17 | ninja | Scarf2 | 173.46 | act 반대 찌르기/wind | atk2 | 21.3 | prac_ninja | fade 0.67 cw 1.00 since_lab 0.75 since_clip 0.05 |
| 18 | hook | Skirt3_3 | 173.42 | act 갈고리 스핀/rec | k_spin | 5.2 | new8 | fade 1.00 cw 1.00 since_lab 0.68 since_clip 0.28 |
| 19 | hook | Skirt1_3 | 172.82 | act 탕/rec | k_shot | 17.2 | new8 | fade 1.00 cw 1.00 since_lab 0.98 since_clip 0.42 |
| 20 | hunter | Cape2_3 | 172.57 | act 찔러 넣기/rec | h_thrust | 10.3 | prac_hunter | fade 1.00 cw 1.00 since_lab 9.88 since_clip 0.45 |

### 발 미끄러짐 상위 20 (비 = 발 끌림 ÷ 몸 이동)

| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | hook | 발 L | 4.44 | 걸음 fwd | fall | 15.6 | new8 | slide 2.83 body 0.64 len 25 |
| 2 | hook | 발 R | 3.66 | 걸음 back | walk~r | 15.5 | new8 | slide 1.65 body 0.45 len 19 |
| 3 | hook | 발 L | 2.43 | 걸음 back | run~r | 5.8 | new8 | slide 1.35 body 0.55 len 15 |
| 4 | hook | 발 R | 1.96 | 걸음 back | run~r | 5.9 | new8 | slide 1.57 body 0.80 len 18 |
| 5 | ninja | 발 R | 1.75 | 걸음 fwd | atk2 | 1.2 | prac_ninja | slide 0.71 body 0.41 len 9 |
| 6 | ninja | 발 R | 1.62 | 걸음 back | run~r | 22.8 | new8 | slide 1.70 body 1.05 len 23 |
| 7 | hook | 발 R | 1.36 | 걸음 fwd | k_hook | 33.9 | prac_hook | slide 0.64 body 0.47 len 8 |
| 8 | tank | 발 L | 1.18 | 걸음 fwd | run | 38.9 | prac_tank | slide 0.71 body 0.60 len 9 |
| 9 | hook | 발 L | 0.85 | 걸음 fwd | run | 33.9 | prac_hook | slide 0.26 body 0.31 len 6 |
| 10 | hunter | 발 R | 0.58 | 정지 끌림 | jump | 4.4 | new8 | len 139 |
| 11 | tank | 발 R | 0.57 | 정지 끌림 | walk | 9.2 | new8 | len 8 |
| 12 | tank | 발 L | 0.56 | 정지 끌림 | jump | 4.4 | new8 | len 139 |
| 13 | tank | 발 R | 0.55 | 정지 끌림 | jump | 4.4 | new8 | len 139 |
| 14 | hunter | 발 L | 0.39 | 정지 끌림 | jump | 4.4 | new8 | len 139 |
| 15 | hook | 발 R | 0.31 | 정지 끌림 | k_hook | 11 | prac_hook | len 12 |
| 16 | hunter | 발 R | 0.18 | 정지 끌림 | h_leap | 0.4 | prac_hunter | len 16 |
| 17 | ninja | 발 R | 0.18 | 정지 끌림 | dash | 0.5 | prac_ninja | len 23 |
| 18 | hook | 발 R | 0.16 | 정지 끌림 | k_throw | 0.5 | prac_hook | len 21 |
| 19 | tank | 발 L | 0.16 | 정지 끌림 | t_charge | 0.5 | prac_tank | len 23 |
| 20 | tank | 발 R | 0.14 | 정지 끌림 | t_charge | 0.5 | prac_tank | len 23 |

### 천 뚫림 상위 20

| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | tank | Tabard1_1 | 0.1 | loco | run | 39.3 | prac_tank |  |
| 2 | hook | Skirt1_1 | 0.09 | act | k_fist | 11.8 | new8 |  |
| 3 | hook | Skirt1_1 | 0.09 | act | k_shot | 17.3 | new8 |  |
| 4 | hook | Skirt3_1 | 0.09 | loco | run~r | 5.8 | new8 |  |
| 5 | hunter | Cape2_1 | 0.08 | act | h_dive | 9.1 | prac_hunter |  |
| 6 | hook | Skirt1_1 | 0.08 | act | k_throw | 4.8 | new8 |  |
| 7 | hunter | Cape2_1 | 0.08 | act | h_dive | 23.3 | prac_hunter |  |
| 8 | tank | Tabard2_1 | 0.08 | loco | run | 39.1 | prac_tank |  |
| 9 | hunter | Cape2_1 | 0.08 | act | h_dive | 38.7 | prac_hunter |  |
| 10 | hook | Skirt2_1 | 0.07 | act | k_fist | 16.5 | new8 |  |
| 11 | hook | Skirt2_1 | 0.07 | act | k_fist | 5.4 | new8 |  |
| 12 | hunter | Cape2_1 | 0.07 | act | h_dive | 25.4 | prac_hunter |  |
| 13 | hook | Skirt3_1 | 0.07 | act | k_spin | 5 | new8 |  |
| 14 | hook | Skirt3_1 | 0.06 | act | k_hook | 6.2 | new8 |  |
| 15 | hunter | Cape2_1 | 0.06 | act | h_dive | 1 | prac_hunter |  |
| 16 | hook | Skirt1_1 | 0.06 | act | k_shot | 17.1 | new8 |  |
| 17 | hunter | Cape2_1 | 0.06 | act | h_dive | 8.5 | prac_hunter |  |
| 18 | hook | Skirt2_1 | 0.06 | act | k_hook | 42.3 | prac_hook |  |
| 19 | hook | Skirt3_1 | 0.06 | act | k_hook | 17.6 | prac_hook |  |
| 20 | hook | Skirt2_1 | 0.05 | act | k_fist | 12 | new8 |  |

### 전환 이음새 (전, 래그돌 관련 전환 뺌)

| 전환 | ninja | tank | hunter | hook |
| --- | --: | --: | --: | --: |
| air→recover | 1회 · 전환 순간 평균 26.5° · 이후 0.25초 최고 176.1° | - | - | - |
| idle→loco | 2회 · 전환 순간 평균 17.4° · 이후 0.25초 최고 167° | 1회 · 전환 순간 평균 3.1° · 이후 0.25초 최고 39.1° | 1회 · 전환 순간 평균 15.4° · 이후 0.25초 최고 95.1° | 5회 · 전환 순간 평균 12.6° · 이후 0.25초 최고 42.3° |
| act→idle | 13회 · 전환 순간 평균 4.7° · 이후 0.25초 최고 55.3° | 2회 · 전환 순간 평균 1.4° · 이후 0.25초 최고 10.4° | - | 2회 · 전환 순간 평균 2.3° · 이후 0.25초 최고 96.3° |
| act→air | - | 4회 · 전환 순간 평균 1.8° · 이후 0.25초 최고 83.5° | 1회 · 전환 순간 평균 1.1° · 이후 0.25초 최고 28.9° | 1회 · 전환 순간 평균 0.7° · 이후 0.25초 최고 27° |
| loco→act | 2회 · 전환 순간 평균 22.9° · 이후 0.25초 최고 40.4° | 1회 · 전환 순간 평균 19.4° · 이후 0.25초 최고 57.3° | 1회 · 전환 순간 평균 55.2° · 이후 0.25초 최고 63.8° | 7회 · 전환 순간 평균 21.9° · 이후 0.25초 최고 46.1° |
| land→act | - | 6회 · 전환 순간 평균 13.9° · 이후 0.25초 최고 63° | 1회 · 전환 순간 평균 3.6° · 이후 0.25초 최고 60.2° | 1회 · 전환 순간 평균 5.7° · 이후 0.25초 최고 33.4° |
| air→act | - | 3회 · 전환 순간 평균 2.4° · 이후 0.25초 최고 57.3° | 2회 · 전환 순간 평균 9.9° · 이후 0.25초 최고 61.5° | 4회 · 전환 순간 평균 3.8° · 이후 0.25초 최고 42.7° |
| air→land | 1회 · 전환 순간 평균 30.8° · 이후 0.25초 최고 30.8° | - | 1회 · 전환 순간 평균 28.9° · 이후 0.25초 최고 28.9° | 3회 · 전환 순간 평균 24.3° · 이후 0.25초 최고 60.6° |
| idle→act | 14회 · 전환 순간 평균 0.6° · 이후 0.25초 최고 55.3° | 2회 · 전환 순간 평균 3.9° · 이후 0.25초 최고 20.9° | 2회 · 전환 순간 평균 0.7° · 이후 0.25초 최고 60.2° | 5회 · 전환 순간 평균 8° · 이후 0.25초 최고 33.4° |
| act→loco | 2회 · 전환 순간 평균 13.8° · 이후 0.25초 최고 36.2° | 1회 · 전환 순간 평균 4.7° · 이후 0.25초 최고 41.7° | 1회 · 전환 순간 평균 15.5° · 이후 0.25초 최고 53° | 2회 · 전환 순간 평균 12.7° · 이후 0.25초 최고 46.1° |
| act→recover | - | 1회 · 전환 순간 평균 44.6° · 이후 0.25초 최고 48.1° | - | - |
| loco→idle | - | 2회 · 전환 순간 평균 15° · 이후 0.25초 최고 39.3° | 2회 · 전환 순간 평균 29.9° · 이후 0.25초 최고 46.4° | 2회 · 전환 순간 평균 18.5° · 이후 0.25초 최고 23.3° |

### 무기 뚫림·삼각형 늘어남·관절 한계·클립 깜빡임 상위 8 (전)

**무기 뚫림**
| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | tank | 무기 점 | 0.13 | recover | (코드) | 26 | new8 |  |

**삼각형 늘어남** (몸, ×2.2 이상 사건 중 상위)
| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | tank | LeftUpLeg|Spine | 13.58 | land | land | 25.3 | prac_tank |  |
| 2 | tank | LeftUpLeg|Spine | 13.48 | act | t_slam | 25.5 | new8 |  |
| 3 | tank | LeftUpLeg|Spine | 12.88 | air | jump | 13.5 | prac_tank |  |
| 4 | tank | LeftUpLeg|Spine | 12.61 | air | fall | 26 | prac_tank |  |
| 5 | tank | LeftUpLeg|Spine | 12.61 | act | t_charge | 26.4 | new8 |  |
| 6 | tank | LeftUpLeg|Spine | 12.58 | recover | (코드) | 25.9 | new8 |  |
| 7 | tank | LeftUpLeg|Spine | 11.71 | act | t_punch | 13.8 | prac_tank |  |
| 8 | tank | LeftUpLeg|Spine | 11.69 | act | t_slam | 25.4 | new8 |  |

**관절 한계**
| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | ninja | RightForeArm | 49.61 | idle rev | idle | 30.9 | new8 |  |
| 2 | ninja | RightLeg | 31.63 | idle rev | idle | 30.9 | new8 |  |

**클립 깜빡임**
| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | hunter | walk~r→walk | 0.29 | loco | walk | 2.1 | new8 |  |
| 2 | hook | walk~r→walk | 0.29 | loco | walk | 2.1 | new8 |  |
| 3 | hook | walk→run~r | 0.28 | loco | run~r | 5.8 | new8 |  |
| 4 | hook | run→run~r | 0.28 | loco | run~r | 15.5 | new8 |  |
| 5 | hook | (코드)→idle | 0.28 | idle | idle | 0.2 | prac_hook |  |
| 6 | ninja | (코드)→idle | 0.28 | idle | idle | 0.2 | prac_ninja |  |
| 7 | ninja | run~r→walk~r | 0.28 | loco | walk~r | 1.1 | prac_ninja |  |
| 8 | ninja | walk→run | 0.28 | loco | run | 1.2 | prac_ninja |  |

### 고친 뒤 (후) 몸 팝 상위 20

| # | 캐릭터 | 뼈 | 값 | 상태 | 클립 | 시각 | 재연 | 비고 |
| --: | --- | --- | --: | --- | --- | --: | --- | --- |
| 1 | ninja | LeftForeArm | 167.31 | idle | idle | 30.9 | new8 | fade 1.00 cw 0.23 since_lab 5.98 since_clip 5.97 |
| 2 | ninja | LeftForeArm | 161.84 | air | fall | 15.1 | new8 | fade 1.00 cw 0.12 since_lab 5.25 since_clip 5.23 |
| 3 | hook | Hips | 152.5 | act 갈고리 스핀/rec | k_spin | 32.4 | prac_hook | fade 1.00 cw 0.47 since_lab 0.02 since_clip 0.02 |
| 4 | hook | LeftArm | 132.99 | act hookSlam/strike | k_slam | 14.3 | new8 | fade 1.00 cw 0.23 since_lab 0.30 since_clip 0.28 |
| 5 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 7.7 | prac_ninja | fade 0.50 cw 1.00 since_lab 0.90 since_clip 0.03 |
| 6 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 9.8 | prac_ninja | fade 0.50 cw 1.00 since_lab 2.97 since_clip 0.03 |
| 7 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 24.2 | prac_ninja | fade 0.50 cw 1.00 since_lab 2.40 since_clip 0.03 |
| 8 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 26.3 | prac_ninja | fade 0.50 cw 1.00 since_lab 4.47 since_clip 0.03 |
| 9 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 31.5 | prac_ninja | fade 0.50 cw 1.00 since_lab 9.63 since_clip 0.03 |
| 10 | ninja | RightArm | 128.97 | act ninjaDash/strike | dash | 33.5 | prac_ninja | fade 0.50 cw 1.00 since_lab 11.67 since_clip 0.03 |
| 11 | ninja | RightArm | 128.48 | act ninjaDash/strike | dash | 16 | prac_ninja | fade 0.50 cw 1.00 since_lab 2.10 since_clip 0.03 |
| 12 | ninja | LeftArm | 127.88 | air | jump | 2.1 | new8 | fade 1.00 cw 1.00 since_lab 0.02 since_clip 0.02 |
| 13 | ninja | LeftArm | 125.15 | air | jump | 2.1 | new8 | fade 1.00 cw 1.00 since_lab 0.06 since_clip 0.06 |
| 14 | ninja | LeftArm | 117.11 | air | jump | 2.2 | new8 | fade 1.00 cw 1.00 since_lab 0.11 since_clip 0.11 |
| 15 | ninja | RightForeArm | 115.03 | air | fall | 15.1 | new8 | fade 1.00 cw 0.12 since_lab 5.25 since_clip 5.23 |
| 16 | ninja | RightArm | 110.72 | air | jump | 2.1 | new8 | fade 1.00 cw 1.00 since_lab 0.01 since_clip 0.01 |
| 17 | ninja | Hips | 110.63 | idle | idle | 30.9 | new8 | fade 1.00 cw 0.23 since_lab 5.98 since_clip 5.97 |
| 18 | ninja | LeftArm | 109.94 | air | jump | 2.2 | new8 | fade 1.00 cw 1.00 since_lab 0.16 since_clip 0.16 |
| 19 | ninja | LeftArm | 108.04 | air | jump | 2.1 | new8 | fade 1.00 cw 1.00 since_lab 0.01 since_clip 0.01 |
| 20 | ninja | RightArm | 107.33 | air | jump | 2.1 | new8 | fade 1.00 cw 1.00 since_lab 0.06 since_clip 0.06 |

## 6. 보류한 것과 이유

| 항목 | 이유 |
| --- | --- |
| **공격 strike·wind 의 빠른 타격 팝** (사냥꾼 베기·반대 베기·찔러 넣기, 탱크 주먹·방패 올려치기·내려치기, 닌자 대시·표창 wind 등 몸 팝의 대부분) | 서버 `moves` 시간 (예: 표창 wind ≈ 67ms) 이 정한 짧은 시간에 클립 구간 (0.1~0.3초) 을 밀어 넣는 설계값. 시간·`figure_motion` 규칙은 건드리지 말라는 제약 (game-hash 기준선 유지). 클립을 더 짧게 다시 만들거나 (Blender) moves 시간을 늘려야 함 → 재혁 판단 |
| **달리기 다리 팝** (달리기 클립에서 무릎·허벅지가 표본당 35~63°) | W34 박자 배율 1.6 (발 미끄러짐을 줄이려 한 바퀴를 더 빨리 돌림) 의 결과 — 발 미끄러짐과 맞바꾼 값이라 되돌리면 W34 가 후퇴. 60Hz 표본 기준이라 144Hz 화면에선 덜 거침 |
| **발 미끄러짐 (뒤로 달리기 `run~r` 비 1.4~3)** | 걸음 디딤이 캐릭터마다 1~8개뿐이라 (연습 봇이 잘 안 걸음) 통계가 약하고, '지지 발' 판정이 달릴 때 낮게 스치는 발을 디딤으로 잘못 셀 수 있음 (비 > 1 은 물리적으로 발이 몸보다 빨리 간다는 뜻이라 판정 쪽 한계로 봄). 걷는 시간이 긴 녹화와 진짜 접지 정보 (서버 스냅샷 grounded + 발 속도) 가 있어야 의미 있음 |
| **탱크 허리 장갑·갈고리 허벅지 안쪽 삼각형 늘어남** (탱크 `LeftUpLeg|Spine` ×13.9, 544 표본 중 170 에서 ×5↑) | 스킨 웨이트 문제 (허벅지·척추 지배 정점이 한 변으로 붙음). Blender 웨이트 다듬기 (`tools/blender/tripo/`) 가 필요 — 모델 파일 재작성이라 눈 확인 없이 하면 위험해서 보류 |
| **래그돌 → 서기 복귀 한 표본 팝** (닌자 새 모델 8명 판 LeftForeArm 167°, cw 0.12~0.23) | 클립 가중치가 막 올라오는 표본에서 기본 자세와 클립 자세가 180° 근처로 멀 때 `slerp` 가 한 표본에 갈리는 문제. 래그돌 모터 경계 (0.9) 근처라 물리 쪽 손이 필요 — 이번엔 래그돌 제외 구간 경계라 보류 |
| **닌자 대시 strike 팔 팝 129°** | 크로스페이드 한가운데 (fade 0.5) 에서 한 표본에 갈림 — 클립 자체 (대시 팔 휘두름) 와 표창 끝 자세 사이가 180° 근처. 크로스페이드 방식 (축·각 분리) 을 바꿔야 해서 보류 |
| 떨림 | 서 있는 동안 떨림 창 0 (최대 RMS 0.03~0.17° < 0.25°) — 고칠 것 없음. 시선·숨쉬기·무기 용수철이 서 있을 때 떠는 일 없음 |
| 관절 한계 | 합성 말고 래그돌·옛 기술을 뺀 뒤 반대 굽힘 닌자 1 · 나머지 0 — 고칠 것 없음 |
| 시도하고 되돌림 | 클립이 빠지는 속도를 상태 전환 땐 느리게 (`EXT_CLIP_OUT` 30/초 → 9/초): 닌자 대시 팝이 안 줄어서 (원인이 크로스페이드 분해 쪽) 되돌림 |

## 7. 검증

- `tests/run_tests.gd`: **380 통과** (새 `test_motion_qa.gd` 8개 포함, 기준 372 → 380), 실패 0
- `tools/shader_check.gd` (xvfb gl_compatibility): 오류 0 (파일 23 + G3 재질 3 + 외부 몸 16)
- `node --test godot/server/tools/package.test.mjs test/godot-package.test.js`: 24 통과
- `node tools/game-hash.js`: `bf2e295158bcb4165fd79b097a1784c61b33716de4e28fa3023b46284dc4cc34` — 기준선 그대로 (서버 판정 불변)
- 재연 SCRIPT ERROR 0, 종료 rc=0 (`new8` + 연습 4개 × 3설정)
- 가벼운 모드 확인: 실제 연습 자동 조종 22초 + `--motion-qa` → `user://motion_qa.txt` 에 '판 요약: 튐 191회' + 상위 5 (캐릭터·뼈·종류·°/프레임·상태·시각)

## 8. 남은 문제 · 소프트웨어 렌더 한계

- 몸 팝의 대부분 (공격 구간) 은 설계값이라 줄지 않음 — 재혁이 '타격이 번쩍 튄다' 고 느끼는 순간과 맞을 가능성이 높음. `--motion-qa` 로 한 판 돌린 `user://motion_qa.txt` 의 상위 5 가 재혁이 '어색했다' 고 느낀 순간과 맞는지 (맞으면 임계가 눈과 맞는 것) 확인 필요
- 발 미끄러짐은 판정 한계 (6절). 걷기 많은 판 녹화 + 서버 접지 정보로 다시 재야 함
- 탱크·갈고리 허리·허벅지 웨이트 (삼각형 늘어남), 래그돌 복귀 팝, 닌자 대시 크로스페이드 (6절)
- 검출기 임계는 '눈으로 어색한 정도' 와 아직 맞춰 보지 못함 (눈 피드백 없음) — 천 팝은 contact sheet 로 보면 치마·망토가 몸 반대편으로 뒤집혀 보이는 정도였고, 임계 35/60° 는 60Hz 에서 4200~3600°/초
- 소프트웨어 렌더 (llvmpipe): 이 도구는 뼈·메시 수치만 읽어 렌더와 무관하지만, **움직임 속도·무게감·천의 맛·프레임 사이 시각적 거칠기는 못 잼**. contact sheet 도 정지 프레임. 재생 속도가 느린 기계에서도 가상 시계라 시뮬은 같게 돈다
- 닌자 새 모델 8명 판의 몸 팝은 래그돌 물리 비결정으로 ±15 (판 합산 비교는 그 안에서는 신뢰하지 말 것)
