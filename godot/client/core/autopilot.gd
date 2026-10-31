# 자동 조종 (헤드리스 확인용, main.gd --auto): host 는 방 만들고 봇 넣고 시작, guest 는 --room 으로 들어감.
# 판 중에는 가장 가까운 상대 쪽으로 걸으며 평타 (PlayerInput.override). --drop-at 초에 연결을 일부러 끊어 재접속(같은 자리) 확인.
# 끝에 한 줄 요약을 찍고 종료 코드 0 (확인 실패면 2)
extends Node

const C := preload("res://core/config.gd")

var args := {}
var role := "host"
var start_ms := 0.0
var created := false
var started := false
var snapshots := 0
var rounds := 0
var last_phase := ""
var moved := 0.0
var last_pos = null
var rejoined := false
var dropped := false
var interp_ok := 0
var push_at := 0.0
var shot_done := false


func _ready() -> void:
	role = str(args.get("auto", "host"))
	start_ms = Net.now_ms()
	Store.rooms_changed.connect(_on_rooms)
	Store.joined.connect(_on_joined)
	Store.state_changed.connect(_on_state)
	Store.join_error.connect(func(r): _log("들어가기 실패: %s" % r))


func _log(t: String) -> void:
	print("[자동 %s] %s" % [role, t])


func _on_rooms(_list: Dictionary) -> void:
	if role == "host" and not created and not Store.in_room() and Store.pending_code == "":
		created = true
		Store.create_room("", str(args.get("name", "고도")))


func _on_joined(room: Dictionary, again: bool) -> void:
	_log("방 %s 들어옴 (내 id %d%s)" % [room.code, Store.my_id, ", 같은 자리로 다시" if again else ""])
	if again:
		rejoined = true
		return
	PlayerInput.lock_mouse(true) # 헤드리스: 마우스 잡힌 셈 (입력이 나가게)
	if role == "host":
		for i in int(args.get("bots", 1)):
			Store.send_room({"type": "addBot"})


func _on_state(st: Dictionary, _prev: Dictionary) -> void:
	snapshots += 1
	var ph := str(st.phase)
	if role == "host" and not started and ph == "lobby" and st.get("canStart", false) and Store.player(Store.my_id).size() > 0 and int(st.players.size()) >= int(args.get("wait-players", 2)):
		started = true
		Store.send_room({"type": "start"})
		_log("시작 (%d명)" % st.players.size())
	if ph == "over" and last_phase == "playing":
		rounds += 1
		_log("판 %d 끝: 승자 %s, 스냅샷 %d개, 내가 움직인 거리 %.1f칸, 보간 위치 %d번" % [rounds, str(st.round.winnerId), snapshots, moved, interp_ok])
		if role == "host" and rounds < int(args.get("quit-after-rounds", 1)):
			Store.send_room({"type": "start"})
	last_phase = ph
	var me := Store.me()
	if not me.is_empty():
		var p := Vector3(me.x, me.y, me.z)
		if last_pos != null:
			moved += (p - last_pos).length()
		last_pos = p


func _process(_d: float) -> void:
	var now := Net.now_ms()
	var el := (now - start_ms) / 1000.0
	# 판 중: 가장 가까운 상대 쪽으로 걷고 가끔 평타
	var me := Store.me()
	if Store.phase() == "playing" and not me.is_empty() and me.alive:
		var best = null
		var bd := INF
		for p in Store.state.players:
			if int(p.id) == Store.my_id or not p.alive:
				continue
			var d := Vector2(p.x - me.x, p.y - me.y).length()
			if d < bd:
				bd = d
				best = p
		var yaw: float = atan2(best.y - me.y, best.x - me.x) if best != null else me.yaw
		PlayerInput.set_yaw_pitch(yaw, 0)
		PlayerInput.override = {"type": "input", "fwd": 1 if bd > 1.2 else 0, "strafe": 0, "jump": false, "yaw": yaw, "pitch": 0}
		if bd < 1.7 and now >= push_at:
			push_at = now + 300
			PlayerInput.press("attack")
		if Store.view_pos(Store.my_id) != Vector3.ZERO:
			interp_ok += 1
	else:
		PlayerInput.override = null
	if args.has("drop-at") and not dropped and el >= float(args["drop-at"]):
		dropped = true
		_log("연결을 일부러 끊음 (재접속 확인)")
		Net.drop_for_test()
	if args.has("shot") and not shot_done and el >= float(args.get("shot-after", 8)) and DisplayServer.get_name() != "headless":
		shot_done = true
		get_viewport().get_texture().get_image().save_png(str(args.shot))
		_log("화면 저장 %s" % args.shot)
	var done_rounds := rounds >= int(args.get("quit-after-rounds", 999999))
	var done_time := args.has("quit-after") and el >= float(args["quit-after"])
	if done_rounds or done_time:
		var ok := snapshots > 0 and (not args.has("drop-at") or rejoined) and (not args.has("quit-after-rounds") or done_rounds) and (not args.has("min-moved") or moved >= float(args["min-moved"]))
		_log("끝: 판 %d번, 스냅샷 %d개, 움직인 거리 %.1f칸, 재접속 %s, %s" % [rounds, snapshots, moved, "같은 자리" if rejoined else "안 함", Net.ping_text()])
		get_tree().quit(0 if ok else 2)
