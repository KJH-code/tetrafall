# Tetrafall 고도 클라

고도 4.7.2 GDScript (렌더러 Compatibility — 웹·PC 같은 빌드). 서버는 JS 서버 (`npm start`) 또는 C# 서버 (`godot/server`) — 같은 프로토콜.
지금은 **G0 뼈대**: 접속·재접속(자리 토큰)·핑·스냅샷·보간·입력·키 설정 + 개발용 상자 화면. 묶음 나누기 규칙은 `../PLAN.md` 7절.

## 실행 (레포 뿌리에서, 고도 받기는 `../prototype/README.md`)

```
PORT=3000 npm start                                     # JS 게임 서버 (C# 서버도 됨)
godot --headless --path godot/client --import           # 처음 한 번 (글꼴 등)
godot --path godot/client                               # 창 클라 → ws://127.0.0.1:3000. 방 만들기·봇 추가·시작, 화면 클릭하면 마우스 잡힘 (Esc 풂)
godot --path godot/client -- --server ws://주소:3000 --room ABCD   # 다른 서버·바로 그 방
```

옵션 (`--` 뒤, 웹이면 주소 뒤 `?키=값`): `--server` · `--room` · `--name` · `--profile` (자리 토큰 저장을 나눔 — 같은 PC 에서 사람 둘) ·
자동 확인 `--auto host|guest` `--bots N` `--wait-players N` `--drop-at 초` (연결 끊었다 같은 자리로) `--quit-after-rounds N` `--quit-after 초` `--min-moved 칸` `--shot 파일.png --shot-after 초`

## 테스트·확인

```
godot --headless --path godot/client -s res://tests/run_tests.gd   # 보간·핑·키 설정이 JS 와 같은 값 (tests/fixtures, JS 에서 뽑음)
node godot/client/tools/fixtures.mjs                              # 정답 자료 다시 뽑기 (client/interp.js·shared/net.js·client/keys.js)
node godot/client/tools/gen-config.mjs                            # shared/config.js → core/config.gd (JS config 를 바꾸면)
bash godot/client/tools/e2e.sh                                    # JS 서버 + 헤드리스 클라 둘: 방 만들기·코드로 들어가기·판·중간에 끊고 같은 자리로
xvfb-run -a godot --path godot/client --rendering-driver opengl3 -- --auto host --bots 7 --wait-players 8 --shot /tmp/s.png --shot-after 12 --quit-after 13
```

## 내보내기 (G7)

```
mkdir -p godot/client/build/{web,windows,linux}
godot --headless --path godot/client --export-release Web build/web/index.html
godot --headless --path godot/client --export-release Windows build/windows/tetrafall.exe
godot --headless --path godot/client --export-release Linux build/linux/tetrafall.x86_64
node godot/client/tools/serve_web.mjs 8060      # 브라우저 http://127.0.0.1:8060/?server=ws://127.0.0.1:3000
WEB_PORT=8060 xvfb-run -a node godot/client/tools/web_shot.cjs /tmp "?server=ws://127.0.0.1:3000&auto=host&bots=3&wait-players=4"
```

- 템플릿: `~/.local/share/godot/export_templates/4.7.2.stable/` 에 `web_nothreads_release.zip`·`windows_release_x86_64.exe`·`linux_release.x86_64` (받기는 prototype README)
- 크기 (2026-10-31): 웹 wasm 39.5MB (gzip 약 10MB) + pck 0.3MB, 윈도우 exe 110MB, 리눅스 74MB (pck 포함 한 파일). `build/` 는 커밋 안 함
- 웹은 지금 게임 서버와 다른 포트에서 서빙 (`?server=`). 게임 서버가 웹 빌드도 같이 서빙하게 하는 건 C# 서버 S6 와 약속 (같은 호스트면 `?server=` 없이 붙음)
- 재혁 PC (윈도우): `tetrafall.exe -- --server ws://<서버 IP>:3000` (또는 같은 PC 면 그냥 `tetrafall.exe`)

## 구조 (G0 = core/)

| 파일 | 내용 (JS 원본) |
| --- | --- |
| `core/net.gd` (자동 로드 `Net`) | 접속·보내기·받기·끊기면 다시 붙기·핑 (main.js connect, net.js) |
| `core/store.gd` (`Store`) | 프로토콜 처리·최신 스냅샷·격자·보간 위치 `view_pos` (main.js onmessage) |
| `core/player_input.gd` (`PlayerInput`) | 키보드·마우스 → input·action (input.js) |
| `core/view.gd` (`View`) | 화면 공용 상태: 시점·관전·설정 |
| `core/keys.gd` · `interp.gd` · `net_meter.gd` · `seat.gd` · `coords.gd` | keys.js · interp.js · shared/net.js · seat.js · 좌표/색 |
| `core/config.gd` | 만든 파일 (shared/config.js) |
| `core/dev_view.gd` · `dev_ui.gd` · `autopilot.gd` | 개발용 상자 화면·버튼·자동 조종 (G1·G4 씬이 생기면 안 쓰임) |
