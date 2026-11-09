# 텍스처 스레드 미리 읽기 (W41): 몸을 만들 때 알베도·마스크를 메인 스레드에서 동기로 읽으면 (W39 지연 로드 뒤 몸당 10~50ms) 판 시작 직후 한 프레임에 몰림.
# 그 몸이 쓸 텍스처 경로를 대기실·메뉴에서 미리 스레드로 요청해 두고, 몸을 만들 때 get_tex 가 받아 씀 (요청 안 한 건 예전처럼 load).
# 요청한 걸 아무도 안 받으면 결과를 붙잡고 있으므로 판이 자리 잡은 뒤 drain 으로 놓음 (영상 메모리 W39 절감 유지).
extends RefCounted

static var _req := {} # 경로 → true (요청했고 아직 안 받음)
static var requested := 0
static var hits := 0 # 받아 쓴 수
static var enabled: bool = not preload("res://core/opts.gd").args().has("--no-tex-prefetch")


static func request(p: String) -> bool:
	if not enabled or p == "" or _req.has(p) or not ResourceLoader.exists(p):
		return false
	if ResourceLoader.load_threaded_request(p, "", false) != OK:
		return false
	_req[p] = true
	requested += 1
	return true


static func pending() -> int:
	return _req.size()


static func is_requested(p: String) -> bool:
	return _req.has(p)


# 요청한 것이면 받음 (아직 읽는 중이면 기다림), 아니면 load
static func get_tex(p: String):
	if _req.has(p):
		_req.erase(p)
		var r = ResourceLoader.load_threaded_get(p)
		if r != null:
			hits += 1
			return r
	return load(p)


# 요청 다 끝났나 (안 요청했으면 true)
static func ready(p: String) -> bool:
	return not _req.has(p) or ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


# 안 받은 요청을 놓음 (끝난 것만 — 읽는 중이면 다음에)
static func drain() -> int:
	var n := 0
	for p in _req.keys():
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(p)
			_req.erase(p)
			n += 1
	return n
