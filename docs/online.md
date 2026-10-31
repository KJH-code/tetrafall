# 인터넷 대전 (npm run online)

> 고도 판 (C# 서버) 은 `Tetrafall.Server --online` 이 같은 일을 node 없이 한다 — 재혁 PC 순서는 [godot-play.md](godot-play.md).

## 지금 방식: Cloudflare 빠른 터널 (계정·도메인 필요 없음)

```
npm run online
```

1. 서버를 켜고 `cloudflared` 로 `https://단어-단어-….trycloudflare.com` 주소를 받는다.
2. **그 주소가 친구 쪽에서 실제로 열릴 때까지 확인한 뒤에** 알린다 (첫 화면 + 웹소켓). 켜자마자 친구가 열면 Cloudflare 530·1033 에러가 뜨던 것.
   - 콘솔에 `[터널] … 확인 중…` 이 보이다가 큰 상자로 주소가 나오면 그때 보내면 된다. 주소는 클립보드에도 복사돼 있다.
   - 정해진 시간(`TUNNEL_READY_TIMEOUT_MS`) 안에 안 열리면 cloudflared 를 다시 켜서 새 주소를 받는다 (연속 `TUNNEL_MAX_RESTARTS` 번까지).
3. 켜 둔 동안에도 `TUNNEL_HEALTH_MS` 마다 주소가 열리는지 본다. 죽으면 cloudflared 만 다시 켜 **새 주소**를 콘솔에 띄운다. 서버·방·판은 그대로다.
   - 대기실의 "링크 복사" 는 늘 지금 터널 주소 + 방 코드로 복사된다.
   - 친구 화면은 끊기면 자동으로 다시 붙어 본다. 하지만 터널 주소가 바뀌었으면 옛 주소로는 못 돌아오니 **새 링크를 다시 보내야** 한다.

빠른 터널은 켤 때마다 주소가 바뀐다 (Cloudflare 정책).

## 같은 주소를 계속 쓰려면: 이름 있는 터널 (named tunnel)

**Cloudflare 계정 + Cloudflare 에 올린 내 도메인**이 있어야 한다 (2026-10-27: 재혁 도메인 없음 → 지금은 안 씀).
도메인이 생기면 한 번만 설정:

```
cloudflared tunnel login                                   # 브라우저로 Cloudflare 로그인, 도메인 고르기
cloudflared tunnel create tetrafall                        # 터널 만들기 (자격 파일이 ~/.cloudflared 에 생김)
cloudflared tunnel route dns tetrafall game.내도메인.com     # 고정 주소 연결
```

그 뒤로는 서버를 켜고 `cloudflared tunnel run --url http://localhost:3000 tetrafall` 하면 늘 `https://game.내도메인.com` 이다.
(`npm run online` 에 옵션으로 넣는 건 도메인이 생기면.)
