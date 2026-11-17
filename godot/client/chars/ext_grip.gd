# c9 두 손 묶음 (순수 계산): 외부 모델 json 의 "grip": true — 두 손으로 든 물건이 몸 메시와 한 덩어리인 모델 (대포수: 손대포가 두 주먹에 녹아 붙음).
# 코드 자세는 한 팔씩 움직이므로 (후려치기·반동) 그대로 맞추면 물건이 두 손 사이로 늘어나 가시가 됨 → 판 몸 (3인칭) 에서는 팔 전체 (빗장 ~ 손가락 끝) 뼈를
# 맞춘 회전 대신 '부모 아래 쉬는 자세' 로 묶음: 팔·물건이 가슴 뼈에 단단히 붙어 몸통과 같이 움직이고, 다리·척추·목은 예전처럼 코드 관절을 따라감.
# 우리 관절 노드 (래그돌·판정·효과 자리) 는 그대로 — 모델 뼈만 묶음. 1인칭 쌍둥이는 안 묶음 (전용 팔 메시 + 소품).
# 여기는 뼈 이름 → 묶을지 만 (chars/external.gd Ext._bind 가 처음 한 번 번호 집합으로 만들고 그 뼈의 자세를 뼈대에서 끔, _code_bones 가 씀). 테스트 tests/test_external.gd test_grip_bones
extends RefCounted

# Tripo 자동 리깅 규격 (접두어 없는 이름 78개, tools/blender/README.md 13절): 좌우는 앞에 L_ / R_
const SIDES := ["L_", "R_"]
# 팔 뼈 (끝 숫자를 뺀 이름이 정확히 이 중 하나): 빗장·위팔·아래팔·손 + 그 사이 보조 뼈 (트위스트·팔꿈치 나눔 뼈 — 안 맞춘 뼈라 원래도 부모를 따라감)
const ARM := ["Clavicle", "Upperarm", "UpperarmTwist", "ElbowShareBone", "Forearm", "ForearmTwist", "Hand"]
# 손가락 뼈 (Thumb1~3 …)
const FINGERS := ["Thumb", "Index", "Mid", "Ring", "Pinky"]


# 이름 끝의 숫자를 뺌 (Mid3 → Mid, UpperarmTwist02 → UpperarmTwist)
static func _core(s: String) -> String:
	var i := s.length()
	while i > 0 and s.unicode_at(i - 1) >= 48 and s.unicode_at(i - 1) <= 57:
		i -= 1
	return s.substr(0, i)


# 이 뼈를 쉬는 자세로 묶는지: 좌우 접두가 붙고, 나머지 이름 (끝 숫자 뺌) 이 팔·손가락 목록과 정확히 같을 때만.
# (넓은 맞춤 — '이름에 Mid 가 들어감' — 은 안 씀: 척추·목·머리·다리·눈은 접두가 없거나 목록에 없어 안 걸림)
static func is_grip(bone_name: String) -> bool:
	for sd in SIDES:
		if bone_name.begins_with(sd):
			var core := _core(bone_name.substr(sd.length()))
			return ARM.has(core) or FINGERS.has(core)
	return false


# 뼈 이름 목록 → 묶을 뼈 번호 집합 {번호: true}
static func bones(names: PackedStringArray) -> Dictionary:
	var out := {}
	for i in names.size():
		if is_grip(names[i]):
			out[i] = true
	return out
