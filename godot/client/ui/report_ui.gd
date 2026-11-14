# 성능 보고 복사 화면 쪽 (W48): 복사하면 아래 가운데 토스트 '복사됨 — 채팅에 붙여 넣어 주세요'. 클립보드에 들어갔다고 확인되지 않으면 (웹 브라우저는 복사가 됐는지 읽을 수 없음·
# 일부 리눅스 창 환경) 글 전체를 선택된 글 칸에 보여 줌 — 직접 Ctrl+C. 버튼은 results.gd·lobby.gd 의 '성능 보고 복사' (R.request_copy), 키는 F4 (Keys 'report').
# 토스트·칸은 UI 배율을 따름 (UI 뿌리 창 content_scale 안에서 그림).
extends CanvasLayer

const S := preload("res://ui/ui_style.gd")
const R := preload("res://core/report.gd")

const TOAST_MS := 3500
const OK_TEXT := "복사됨 — 채팅에 붙여 넣어 주세요"
const MANUAL_TEXT := "자동 복사가 안 됐을 수 있어요 — 아래 글을 선택해서 (Ctrl+A) 복사 (Ctrl+C) 해 주세요"

var toast: PanelContainer
var toast_label: Label
var box: PanelContainer
var box_head: Label
var edit: TextEdit
var toast_until := 0


func _ready() -> void:
	name = "ReportUi"
	layer = 60
	toast = PanelContainer.new()
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.05, 0.04, 0.12, 0.92)
	tb.border_color = S.alpha(S.g(), 0.7)
	tb.set_border_width_all(1)
	tb.set_content_margin_all(10)
	tb.content_margin_left = 18
	tb.content_margin_right = 18
	toast.add_theme_stylebox_override("panel", tb)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = S.body_label(OK_TEXT, 15, Color.WHITE)
	toast.add_child(toast_label)
	toast.visible = false
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.position.y -= 56
	add_child(toast)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", S.pane())
	box.visible = false
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	box_head = S.body_label(MANUAL_TEXT, 13, Color("e6e0f4"))
	box_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(box_head)
	edit = TextEdit.new()
	edit.editable = false
	edit.custom_minimum_size = Vector2(620, 230)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_theme_font_size_override("font_size", 12)
	v.add_child(edit)
	var close := S.button("닫기", func(): box.visible = false, "ghost", 13)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(close)
	add_child(box)
	if R.inst != null and is_instance_valid(R.inst):
		R.inst.copied.connect(_on_copied)


func _on_copied(ok: bool, text: String) -> void:
	show_toast(OK_TEXT if ok else "보고서를 만들었어요 — 복사가 안 되면 아래 글을 복사해 주세요")
	if not ok:
		show_text(text)


func show_toast(t: String) -> void:
	toast_label.text = t
	toast.visible = true
	toast_until = Time.get_ticks_msec() + TOAST_MS
	set_process(true)


func show_text(text: String) -> void:
	edit.text = text
	box.visible = true
	if edit.is_inside_tree():
		edit.grab_focus()
	edit.select_all()


func _process(_d: float) -> void:
	if toast.visible and Time.get_ticks_msec() >= toast_until:
		toast.visible = false
	if not toast.visible:
		set_process(false)
