#!/usr/bin/env bash
# 죽은 방 탈출 + 서버 침묵 감지 자동 확인: C# 서버 + 헤드리스 고도 클라.
#  A (서버 다시 켬): host 가 방을 만든 뒤 서버를 죽이고 같은 포트로 다시 켬 → host 는 다시 붙지만 그 방은 없음
#    → 대기실에 갇히지 않고 '방으로 돌아가지 못했습니다 — …그런 방이 없습니다' 이유와 함께 방 밖으로 (--expect-left)
#  B (서버 12초 멈춤): host + guest 판 중에 서버를 kill -STOP → 12초 뒤 -CONT. 소켓은 안 끊기지만 아무것도 안 옴
#    → 클라가 '서버 응답 없음' 으로 소켓을 버리고 다시 붙어 같은 자리로 (자리 토큰), 서버 로그엔 복귀
# 실행 (레포 뿌리): bash godot/client/tools/e2e_net.sh   ·  PORT (기본 3431) · LOG (기본 /tmp/tf-e2e-net) ·
#   SERVER_DLL (Tetrafall.Server.dll 경로 — 없으면 $LOG/bin 에 Release 로 지음) · STALL (B 가 멈추는 초, 기본 12) · QUIT_A·QUIT_B (클라가 끝나는 초)
# 끄는 것은 이 스크립트가 띄운 PID 만 (같은 기계에 다른 서버가 있어도 안 건드림)
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CLIENT="$ROOT/godot/client"
GODOT=${GODOT:-godot}
PORT=${PORT:-3431}
LOG=${LOG:-/tmp/tf-e2e-net}
STALL=${STALL:-12}
QUIT_A=${QUIT_A:-60}
QUIT_B=${QUIT_B:-45}
mkdir -p "$LOG"
cd "$ROOT"
if [ -z "${SERVER_DLL:-}" ]; then
  dotnet build -c Release -o "$LOG/bin" godot/server/src/Tetrafall.Server > "$LOG/build.txt" 2>&1 || { tail -5 "$LOG/build.txt"; echo "e2e_net: 서버 빌드 실패"; exit 1; }
  SERVER_DLL="$LOG/bin/Tetrafall.Server.dll"
fi

S=""
# 끝날 때 (중간에 멈춰도): 아직 살아 있는 내 자식만 끔 — jobs -p 는 이 셸이 띄워 아직 도는 것만 (끝난 PID 는 다른 프로세스가 다시 쓸 수 있음)
cleanup() {
  for p in $(jobs -p); do
    kill -CONT "$p" 2>/dev/null # 멈춘 채면 TERM 을 못 받음
    kill "$p" 2>/dev/null
  done
  sleep 0.5
  for p in $(jobs -p); do
    kill -9 "$p" 2>/dev/null # 서버는 TERM 뒤에도 한참 살 수 있음 (server_down 설명)
  done
}
trap cleanup EXIT

# 서버 띄우기 (출력 파일 $1): 시작 줄이 나올 때까지 기다림. PID 는 S
server_up() {
  PORT=$PORT TF_ROOT="$ROOT" TF_LOG_DIR="$LOG/logs" dotnet "$SERVER_DLL" > "$1" 2>&1 &
  S=$!
  for i in $(seq 1 50); do
    grep -q "서버 실행 중" "$1" 2>/dev/null && return 0
    kill -0 $S 2>/dev/null || return 1
    sleep 0.2
  done
  return 1
}

# 서버 내리기: TERM 을 보내고 2초 안에 안 죽으면 KILL. C# 서버는 TERM 을 받아도 열린 WebSocket 이 있으면 종료 대기 (30초) 동안
# 틱·스냅샷을 계속 보내며 살아 있음 → 그대로 두면 '서버가 죽음' 이 아니라 30초 뒤에야 끊김
server_down() {
  kill $S 2>/dev/null
  for i in $(seq 1 10); do
    kill -0 $S 2>/dev/null || break
    sleep 0.2
  done
  kill -9 $S 2>/dev/null
  wait $S 2>/dev/null
}

# 클라 띄우기 (출력 파일 $1, 나머지는 -- 뒤 옵션). PID 는 $!
client() {
  local out="$1"
  shift
  "$GODOT" --headless --path "$CLIENT" -- --server "ws://127.0.0.1:$PORT" "$@" > "$out" 2>&1 &
}

# 로그 $1 에 글 $2 가 나올 때까지 (최대 $3 초, 0.2초마다)
wait_for() {
  for i in $(seq 1 $(($3 * 5))); do
    grep -q "$2" "$1" 2>/dev/null && return 0
    sleep 0.2
  done
  return 1
}

room_code() {
  wait_for "$1" "방 [A-Z]\{4\} 들어옴" 20
  grep -o "방 [A-Z]\{4\} 들어옴" "$1" | head -1 | cut -d' ' -f2
}

# 확인 한 줄: 조건 ($2…) 이 참이면 ok, 아니면 그 시나리오 실패
FAIL=0
expect() {
  local what="$1"
  shift
  if "$@"; then echo "  ok   $what"; else echo "  FAIL $what"; FAIL=1; fi
}
# 로그 $1 에서 글 $2 가 글 $3 보다 먼저 (둘 다 있어야 함)
before() {
  local a b
  a=$(grep -n "$2" "$1" | head -1 | cut -d: -f1)
  b=$(grep -n "$3" "$1" | tail -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

# ---------- A: 서버 다시 켬 ----------
echo "A: 서버를 죽였다 다시 켬 (방이 없어짐)"
server_up "$LOG/a-server1.txt" || { echo "e2e_net: 서버가 안 뜸 (포트 $PORT)"; tail -5 "$LOG/a-server1.txt"; exit 1; }
client "$LOG/a-host.txt" --auto host --profile e2enet-a --bots 1 --expect-left --quit-after "$QUIT_A"
H=$!
CODE=$(room_code "$LOG/a-host.txt")
echo "  방 코드: ${CODE:-없음}"
sleep 3
server_down
server_up "$LOG/a-server2.txt" || { echo "e2e_net: 서버가 다시 안 뜸"; tail -5 "$LOG/a-server2.txt"; exit 1; }
wait $H; RH=$?
server_down
grep -h "^\[자동" "$LOG/a-host.txt" | grep -v "접속: .*([0-9]*/[0-9]*)" | sed 's/^/  /'
expect "방 코드를 받음" [ -n "$CODE" ]
expect "host 종료 코드 0 (지금 $RH)" [ $RH -eq 0 ]
expect "host 로그에 '방 밖:'" grep -q "방 밖:" "$LOG/a-host.txt"
expect "host 로그에 '방으로 돌아가지 못했습니다 — …그런 방이 없습니다'" grep -q "방으로 돌아가지 못했습니다 — .*그런 방이 없습니다" "$LOG/a-host.txt"
A=$FAIL

# ---------- B: 서버 12초 멈춤 ----------
FAIL=0
echo "B: 판 중에 서버를 ${STALL}초 멈춤 (소켓은 살아 있고 아무것도 안 옴)"
server_up "$LOG/b-server.txt" || { echo "e2e_net: 서버가 안 뜸 (포트 $PORT)"; tail -5 "$LOG/b-server.txt"; exit 1; }
client "$LOG/b-host.txt" --auto host --profile e2enet-bh --name 호스트 --bots 1 --wait-players 3 --quit-after "$QUIT_B"
H=$!
CODE=$(room_code "$LOG/b-host.txt")
echo "  방 코드: ${CODE:-없음}"
client "$LOG/b-guest.txt" --auto guest --profile e2enet-bg --room "$CODE" --quit-after "$QUIT_B"
G=$!
wait_for "$LOG/b-host.txt" "시작 (3명)" 20
sleep 4
kill -STOP $S
sleep "$STALL"
kill -CONT $S
wait $H; RH=$?
wait $G; RG=$?
server_down
grep -h "^\[자동" "$LOG/b-host.txt" "$LOG/b-guest.txt" | grep -v "접속: .*([0-9]*/[0-9]*)" | sed 's/^/  /'
grep -E "복귀|끊김\]" "$LOG/b-server.txt" | head -6 | sed 's/^/  /'
expect "판이 시작됨 (3명)" grep -q "시작 (3명)" "$LOG/b-host.txt"
expect "guest: '서버 응답 없음' 다음에 '같은 자리로 다시'" before "$LOG/b-guest.txt" "서버 응답 없음" "같은 자리로 다시"
expect "host: '서버 응답 없음' 다음에 '같은 자리로 다시'" before "$LOG/b-host.txt" "서버 응답 없음" "같은 자리로 다시"
expect "서버 로그에 복귀" grep -q "복귀" "$LOG/b-server.txt"
expect "종료 코드 host $RH, guest $RG" [ $RH -eq 0 -a $RG -eq 0 ]
B=$FAIL

name() { [ "$1" -eq 0 ] && echo 통과 || echo 실패; }
echo "e2e_net: A $(name $A) · B $(name $B)"
[ $A -eq 0 ] && [ $B -eq 0 ]
