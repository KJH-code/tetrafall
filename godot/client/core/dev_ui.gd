# 개발용 화면 (G0): ui/ui.tscn (G4) 이 생기기 전까지만. 접속 상태·핑, 방 만들기·코드로 들어가기·봇·시작·나가기, 판 상태 한 줄씩
extends CanvasLayer

var status: Label
var info: Label
var code_edit: LineEdit
var nick_edit: LineEdit


func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	add_child(box)
	status = Label.new()
	box.add_child(status)
	var row := HBoxContainer.new()
	box.add_child(row)
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = "이름"
	nick_edit.custom_minimum_size.x = 110
	row.add_child(nick_edit)
	_button(row, "방 만들기", func(): Store.create_room("", nick_edit.text))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "방 코드"
	code_edit.custom_minimum_size.x = 90
	row.add_child(code_edit)
	_button(row, "들어가기", func(): Store.join(code_edit.text))
	_button(row, "봇 추가", func(): Store.send_room({"type": "addBot"}))
	_button(row, "시작", func(): Store.send_room({"type": "start"}))
	_button(row, "나가기", func(): Store.leave())
	info = Label.new()
	box.add_child(info)
	for e in [nick_edit, code_edit]:
		e.focus_entered.connect(func(): PlayerInput.ui_blocking = true)
		e.focus_exited.connect(func(): PlayerInput.ui_blocking = false)
	Store.join_error.connect(func(r): info.text = r)
	Store.left_room.connect(func(r): info.text = "방 밖: %s" % r)


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func _process(_d: float) -> void:
	var room_text := ("방 %s (%s)" % [Store.room.code, Store.room.name]) if Store.in_room() else "방 밖 (공개 방 %d개)" % Store.rooms_list.get("rooms", []).size()
	status.text = "%s | %s | %s %s" % [Net.status, Net.ping_text(), room_text, Net.warn_text()]
	if not Store.in_room() or Store.state.is_empty():
		return
	var st := Store.state
	var lines := ["%s | 판 %d | %dx%d | 마우스 %s (클릭하면 잡힘, Esc 풂)" % [st.phase, int(st.round.n), int(st.field.w), int(st.field.d), "잡힘" if PlayerInput.locked else "풀림"]]
	for p in st.players:
		lines.append("%s%s %s %d%% %s" % ["> " if int(p.id) == Store.my_id else "  ", p.name, p.get("char", ""), int(p.damage), "" if p.alive else "(탈락)"])
	info.text = "\n".join(lines)
