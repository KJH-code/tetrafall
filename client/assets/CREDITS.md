# 모델·소리 출처 (전부 CC0 1.0, 퍼블릭 도메인)

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `robot/RobotExpressive.glb` | Tomás Laulhé (Quaternius), 표정 추가 Don McCurdy — three.js 예제 `examples/models/gltf/RobotExpressive` (r170) | CC0 1.0 |
| `kenney-platformer/` (bomb, spring, crate-item, button-round) | Kenney, Platformer Kit 4.1 — https://kenney.nl/assets/platformer-kit | CC0 1.0 |
| `kenney-survival/tool-hammer.glb` | Kenney, Survival Kit 2.0 — https://kenney.nl/assets/survival-kit | CC0 1.0 |
| `kenney-graveyard/character-ghost.glb` | Kenney, Graveyard Kit 5.0 — https://kenney.nl/assets/graveyard-kit | CC0 1.0 |
| `kenney-blaster/blaster-b.glb` | Kenney, Blaster Kit 2.1 — https://kenney.nl/assets/blaster-kit | CC0 1.0 |

# 글꼴 출처

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `fonts/black-han-sans-korean.woff2`, `fonts/black-han-sans-latin.woff2` | Black Han Sans — zesstype, Copyright 2015 The Black Han Sans Project Authors (https://github.com/zesstype/Black-Han-Sans). 한글·라틴 부분집합은 Fontsource 패키지 `@fontsource/black-han-sans` 의 woff2 | SIL OFL 1.1 (`fonts/OFL.txt`) |

OFL 은 상업 이용·재배포가 되지만 글꼴 파일 자체를 팔 수 없고 라이선스 전문을 같이 둬야 한다 → `fonts/OFL.txt`.

Kenney 모델은 같은 폴더의 `Textures/colormap.png` 를 참조한다 (키트마다 색표가 달라 폴더를 나눔).
CC0 라 표기 의무는 없지만 만든 사람을 남겨 둔다.

## 효과음 (`sfx/`, 2026-10-27)

| 파일 (`sfx/` 안, 원래 이름 그대로) | 출처 | 라이선스 |
|---|---|---|
| `impactPunch_heavy_*`, `impactPlate_heavy_*`, `impactWood_*`, `impactMining_*`, `impactBell_heavy_*`, `impactGeneric_light_*`, `impactSoft_heavy_*`, `impactMetal_*`, `impactGlass_heavy_*` | Kenney, Impact Sounds 1.0 — https://kenney.nl/assets/impact-sounds | CC0 1.0 |
| `chop`, `knifeSlice*`, `cloth1~3`, `metalLatch`, `metalClick` | Kenney, RPG Audio 1.0 — https://kenney.nl/assets/rpg-audio | CC0 1.0 |
| `explosionCrunch_000~002`, `lowFrequency_explosion_001`, `slime_000` | Kenney, Sci-fi Sounds 1.0 — https://kenney.nl/assets/sci-fi-sounds | CC0 1.0 |
| `pluck_001~002`, `confirmation_001` | Kenney, Interface Sounds 1.0 — https://kenney.nl/assets/interface-sounds | CC0 1.0 |
| `jingles_STEEL02`, `jingles_STEEL05` | Kenney, Music Jingles 1.0 — https://kenney.nl/assets/music-jingles | CC0 1.0 |

각 팩의 License.txt: "Creative Commons Zero, CC0 — free to use in personal, educational and commercial projects" (표기 의무 없음, 그래도 남김).
어느 이벤트에 어느 묶음이 쓰이는지는 `shared/config.js` 의 `SFX_BANKS`·`SFX_WEAPONS`. 나머지 소리(UI·카운트다운·위험 액체 지속음·배경음악)는 `client/sound.js`·`music.js` 에서 합성 (파일 없음).

## 타격·휘두름 (`sfx/hit*`, `sfx/swish*`, 2026-10-28)

OpenGameArt CC0 원본을 `tools/prep-sfx.mjs` 로 역할별로 다듬음 (앞 무음 자르기·대역 거르기·길이 자르기·페이드·최고점 맞춤). 어느 파일이 어느 원본인지는 그 스크립트의 `FILES` 표.

| 파일 | 원본 팩 | 라이선스 |
|---|---|---|
| `hitCrack_1~3`, `hitPunch_3` | Thwack Sounds — Jordan Irwin (AntumDeluge) — https://opengameart.org/content/thwack-sounds | CC0 1.0 |
| `hitPunch_1·2`, `hitHeavy_1` | Punch — qubodup — https://opengameart.org/content/punch | CC0 1.0 |
| `hitHeavy_4`, `hitRing_1` | Impact — qubodup — https://opengameart.org/content/impact | CC0 1.0 |
| `hitPunch_4·5`, `hitHeavy_2·3` | 37 hits/punches — independent.nu ljudbank — https://opengameart.org/content/37-hitspunches | CC0 1.0 |
| `swishBlade_1~3` | 20 Sword Sound Effects — StarNinjas — https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | CC0 1.0 |
| `swishMid_1~4`, `swishHeavy_1~3` | Swishes Sound Pack — https://opengameart.org/content/swishes-sound-pack | CC0 1.0 |
