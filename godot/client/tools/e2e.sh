#!/usr/bin/env bash
# G0 자동 확인: JS 서버 (또는 SERVER_CMD) + 헤드리스 고도 클라 둘. host 가 방을 만들고 봇 1, guest 가 코드로 들어와 판을 돎.
# guest 는 DROP 초에 연결을 일부러 끊고 같은 자리로 다시 들어와야 함 (재접속 토큰). 셋 다 정상 종료면 성공.
# 실행 (레포 뿌리): bash godot/client/tools/e2e.sh   ·  C# 서버로: SERVER_CMD="dotnet godot/server/src/Tetrafall.Server/bin/Debug/net10.0/Tetrafall.Server.dll" bash …
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CLIENT="$ROOT/godot/client"
GODOT=${GODOT:-godot}
PORT=${PORT:-3302}
DROP=${DROP:-8}
LOG=${LOG:-/tmp/tf-g0-e2e}
mkdir -p "$LOG"
cd "$ROOT"
PORT=$PORT ${SERVER_CMD:-node server/index.js} > "$LOG/server.txt" 2>&1 &
S=$!
sleep 2
"$GODOT" --headless --path "$CLIENT" -- --server "ws://127.0.0.1:$PORT" --auto host --profile host --bots 1 --wait-players 3 --name 호스트 --quit-after-rounds 1 --quit-after 150 --min-moved 1 > "$LOG/host.txt" 2>&1 &
H=$!
CODE=""
for i in $(seq 1 50); do
  CODE=$(grep -o "방 [A-Z]\{4\} 들어옴" "$LOG/host.txt" | head -1 | cut -d' ' -f2)
  [ -n "$CODE" ] && break
  sleep 0.2
done
echo "방 코드: ${CODE:-없음}"
"$GODOT" --headless --path "$CLIENT" -- --server "ws://127.0.0.1:$PORT" --auto guest --profile guest --room "$CODE" --drop-at "$DROP" --quit-after-rounds 1 --min-moved 1 --quit-after 150 > "$LOG/guest.txt" 2>&1 &
G=$!
wait $H; RH=$?
wait $G; RG=$?
kill $S 2>/dev/null
grep -h "^\[자동" "$LOG/host.txt" "$LOG/guest.txt"
grep -E "복귀|끊김\]" "$LOG/server.txt" | head -4
echo "종료 코드: host $RH, guest $RG"
[ $RH -eq 0 ] && [ $RG -eq 0 ]
