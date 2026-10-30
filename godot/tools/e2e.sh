#!/usr/bin/env bash
# 자동 확인: 헤드리스 서버 + 헤드리스 봇 클라 2개가 접속해 ROUNDS 판을 돌고 모두 정상 종료하는지.
# 실행: bash godot/tools/e2e.sh [판 수]   (GODOT 환경 변수로 실행 파일 지정, 기본 godot)
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
ROUNDS=${1:-2}
PORT=${PORT:-3101}
LOG=${LOG:-/tmp/tf-godot-e2e}
mkdir -p "$LOG"
"$GODOT" --headless --path . -- --server --port "$PORT" --rounds "$ROUNDS" > "$LOG/server.txt" 2>&1 &
S=$!
sleep 1.5
"$GODOT" --headless --path . -- --client --bot --url "ws://127.0.0.1:$PORT" --name 봇1 --quit-after-rounds "$ROUNDS" > "$LOG/c1.txt" 2>&1 &
A=$!
"$GODOT" --headless --path . -- --client --bot --url "ws://127.0.0.1:$PORT" --name 봇2 --quit-after-rounds "$ROUNDS" > "$LOG/c2.txt" 2>&1 &
B=$!
( sleep 240; kill $S $A $B 2>/dev/null ) & W=$!
wait $A; RA=$?
wait $B; RB=$?
wait $S; RS=$?
kill $W 2>/dev/null
echo "--- 서버"; grep -E '^\[|=====|사망' "$LOG/server.txt" | grep -v '밀치기' | tail -20
echo "--- 클라"; grep '^\[클라' "$LOG/c1.txt" "$LOG/c2.txt"
echo "종료 코드: 서버 $RS, 클라 $RA $RB"
[ $RS -eq 0 ] && [ $RA -eq 0 ] && [ $RB -eq 0 ]
