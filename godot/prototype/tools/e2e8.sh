#!/usr/bin/env bash
# 8명 판 자동 확인: 헤드리스 서버 (서버 봇 7명) + 헤드리스 봇 클라 1개 → ROUNDS 판. 서버 틱 시간도 찍힘
# 실행: bash godot/prototype/tools/e2e8.sh [판 수]
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
ROUNDS=${1:-2}
PORT=${PORT:-3103}
LOG=${LOG:-/tmp/tf-godot-e2e8}
mkdir -p "$LOG"
"$GODOT" --headless --path . -- --server --port "$PORT" --rounds "$ROUNDS" --bots 7 > "$LOG/server.txt" 2>&1 &
S=$!
sleep 1.5
"$GODOT" --headless --path . -- --client --bot --url "ws://127.0.0.1:$PORT" --name 사람봇 --quit-after-rounds "$ROUNDS" > "$LOG/c1.txt" 2>&1 &
A=$!
( sleep 400; kill $S $A 2>/dev/null ) & W=$!
wait $A; RA=$?
wait $S; RS=$?
kill $W 2>/dev/null
echo "--- 서버"; grep -a -E '^\[서버\]|=====|사망:' "$LOG/server.txt" | tail -14
echo "--- 클라"; grep -a '^\[클라' "$LOG/c1.txt"
echo "종료 코드: 서버 $RS, 클라 $RA"
[ $RS -eq 0 ] && [ $RA -eq 0 ]
