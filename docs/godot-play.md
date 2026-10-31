# 고도 판 켜기: 재혁 PC (윈도우) 한 장

C# 서버 + 고도 클라를 묶은 zip 하나면 끝이다. 받는 PC 에는 .NET·node·고도 모두 필요 없다.

## 1. 받기

**A. zip 을 받았으면** `tetrafall-win-x64.zip` 을 아무 폴더에 풀면 된다 (예: `D:\tetrafall-win-x64\`).

| 파일 | 하는 일 |
| --- | --- |
| `start-online.bat` | 서버 + 인터넷 터널 → 친구용 https 주소 |
| `start-lan.bat` | 서버만 (같은 Wi-Fi) |
| `tetrafall.exe` | 고도 PC 클라 (이 PC 서버에 바로 붙음) |
| `Tetrafall.Server.exe` | 서버 (bat 이 켬) |
| `web/` | 친구 브라우저용 고도 웹 빌드 (서버가 `/play/` 로 줌) |
| `cloudflared.exe` | 터널 (없으면 아래 설치) |

**B. 직접 만들기** (레포에서, 한 번만 설치: .NET 10 SDK · Node 22 · 고도 4.7.2 + 내보내기 템플릿 — 고도 편집기 `편집기 → 내보내기 템플릿 관리 → 다운로드`)

```
git pull
node godot/server/tools/package.mjs --godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --targets win --cloudflared
```

→ `dist\tetrafall-win-x64.zip` (+ 같은 이름 폴더). 고도 내보내기를 이미 해 뒀으면 `--godot …` 대신 `--no-godot`. 리눅스 묶음은 `--targets linux` (둘 다면 `win,linux`).

## 2. 켜기

1. `start-online.bat` 을 두 번 클릭한다.
2. 처음이면 윈도우 방화벽 창이 뜬다. **개인 네트워크 허용**을 누른다 (같은 Wi-Fi 친구가 붙으려면 필요).
3. 창에 `[터널] … 확인 중…` 이 보이다가 `=====` 상자에 `https://단어-단어-….trycloudflare.com` 이 나오면 준비가 끝난 것이다. 이 주소는 클립보드에도 복사돼 있다.
   - `cloudflared 가 없어…` 가 뜨면 `winget install --id Cloudflare.cloudflared` 를 실행하고 창을 다시 연다. 아니면 `cloudflared.exe` 를 이 폴더에 넣어도 된다.
4. 나는 `tetrafall.exe` 를 켠다. 브라우저로 `http://localhost:3000` 을 열어도 된다.

끄기: 서버 창을 닫거나 `Ctrl+C`. 판 기록은 `logs\` 폴더에 남는다.

## 3. 친구에게 링크

- **인터넷 친구**: 상자의 https 주소를 메신저로 보낸다. 친구는 크롬이나 엣지로 열기만 하면 되고 설치는 없다.
  - 방을 만든 뒤 대기실 **링크 복사** 를 누르면 그 주소 + 방 코드 (`…/?room=ABCD`) 가 복사된다. 친구는 그 방으로 바로 들어온다.
  - 주소는 켤 때마다 바뀐다. 터널이 죽으면 서버가 cloudflared 를 다시 켜서 **새 주소**를 창에 띄운다 (방·판은 그대로). 그때는 새 링크를 다시 보낸다.
- **같은 Wi-Fi 친구**: `start-lan.bat` 창의 `다른 PC에서 (…): http://192.168.x.x:3000` 주소를 보낸다.
- **친구가 PC 클라로**: `tetrafall.exe -- --server wss://단어-단어-….trycloudflare.com` 으로 연다. 같은 Wi-Fi 면 `ws://192.168.x.x:3000`.

## 안 될 때

| 증상 | 할 일 |
| --- | --- |
| 친구 화면에 Cloudflare 530·1033 | 상자가 뜨기 전에 연 것. 상자가 뜬 뒤 다시 연다 |
| 터널을 6번 켰는데 안 열림 | 잠시 뒤 `start-online.bat` 다시. 서버는 켜져 있어 같은 Wi-Fi 는 된다 |
| 3000 포트를 이미 씀 | 다른 서버(`npm start` 등)를 끄거나, 창에서 `set PORT=3100` 한 뒤 `Tetrafall.Server.exe --online` |
| 같은 Wi-Fi 친구가 못 붙음 | 방화벽에서 `Tetrafall.Server` 를 개인 네트워크 허용 |

자세한 터널 방식 (주소 확인·다시 켜기·고정 주소) 은 [online.md](online.md). 서버 옵션: `--online` (= 환경 변수 `TF_ONLINE=1`), `PORT`, `CLOUDFLARED` (cloudflared 경로).
