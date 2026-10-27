# 모델·소리 출처 (전부 CC0 1.0, 퍼블릭 도메인)

| 파일 | 출처 | 라이선스 |
|---|---|---|
| `robot/RobotExpressive.glb` | Tomás Laulhé (Quaternius), 표정 추가 Don McCurdy — three.js 예제 `examples/models/gltf/RobotExpressive` (r170) | CC0 1.0 |
| `kenney-platformer/` (bomb, spring, crate-item, button-round) | Kenney, Platformer Kit 4.1 — https://kenney.nl/assets/platformer-kit | CC0 1.0 |
| `kenney-survival/tool-hammer.glb` | Kenney, Survival Kit 2.0 — https://kenney.nl/assets/survival-kit | CC0 1.0 |
| `kenney-graveyard/character-ghost.glb` | Kenney, Graveyard Kit 5.0 — https://kenney.nl/assets/graveyard-kit | CC0 1.0 |
| `kenney-blaster/blaster-b.glb` | Kenney, Blaster Kit 2.1 — https://kenney.nl/assets/blaster-kit | CC0 1.0 |

Kenney 모델은 같은 폴더의 `Textures/colormap.png` 를 참조한다 (키트마다 색표가 달라 폴더를 나눔).
CC0 라 표기 의무는 없지만 만든 사람을 남겨 둔다.

## 효과음 (`sfx/`, 2026-10-27)

| 파일 (`sfx/` 안, 원래 이름 그대로) | 출처 | 라이선스 |
|---|---|---|
| `impactPunch_*`, `impactPlate_heavy_*`, `impactWood_*`, `impactMining_*`, `impactBell_heavy_*`, `impactGeneric_light_*`, `impactSoft_heavy_*`, `impactMetal_*`, `impactGlass_heavy_*` | Kenney, Impact Sounds 1.0 — https://kenney.nl/assets/impact-sounds | CC0 1.0 |
| `chop`, `knifeSlice*`, `drawKnife3`, `cloth1~3`, `metalLatch`, `metalClick` | Kenney, RPG Audio 1.0 — https://kenney.nl/assets/rpg-audio | CC0 1.0 |
| `explosionCrunch_000~002`, `lowFrequency_explosion_001`, `slime_000` | Kenney, Sci-fi Sounds 1.0 — https://kenney.nl/assets/sci-fi-sounds | CC0 1.0 |
| `pluck_001~002`, `confirmation_001` | Kenney, Interface Sounds 1.0 — https://kenney.nl/assets/interface-sounds | CC0 1.0 |
| `jingles_STEEL02`, `jingles_STEEL05` | Kenney, Music Jingles 1.0 — https://kenney.nl/assets/music-jingles | CC0 1.0 |

각 팩의 License.txt: "Creative Commons Zero, CC0 — free to use in personal, educational and commercial projects" (표기 의무 없음, 그래도 남김).
어느 이벤트에 어느 묶음이 쓰이는지는 `shared/config.js` 의 `SFX_BANKS`·`SFX_WEAPONS`. 나머지 소리(UI·카운트다운·위험 액체 지속음·배경음악)는 `client/sound.js`·`music.js` 에서 합성 (파일 없음).
