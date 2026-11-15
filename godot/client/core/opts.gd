# 실행 인자 한 곳 (W29 웹 성능): 데스크톱은 `-- --키 값` (OS.get_cmdline_user_args), 웹은 주소 뒤 `?키=값` 을 같은 모양의
# ["--키", "값", ...] 으로 (값이 없으면 "--키" 만). 웹은 명령줄이 없어서 --no-ext·--gfx·--perf 같은 인자가 먹지 않던 것을 한 길로.
# 쓰는 쪽은 OS.get_cmdline_user_args() 대신 Opts.args(). 테스트는 Opts.override 로 웹 주소를 흉내
extends RefCounted

static var _web_cache = null # PackedStringArray (웹이면 처음 한 번만 읽음)
static var override = null # 테스트: PackedStringArray 로 두면 그것만 돌려줌 (null 이면 평소대로)
static var web_override = null # 테스트: bool 로 두면 web() 이 그 값 (null 이면 OS.has_feature("web"))


# 웹 빌드로 돌고 있는가 (테스트가 강제할 수 있게 함수로 감쌈)
static func web() -> bool:
	return bool(web_override) if web_override != null else OS.has_feature("web")


static func args() -> PackedStringArray:
	if override != null:
		return override
	var out := OS.get_cmdline_user_args()
	if not OS.has_feature("web"):
		return out
	if _web_cache == null:
		var list := PackedStringArray(out)
		var q = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))", true)))
		if typeof(q) == TYPE_DICTIONARY:
			for k in q:
				list.append("--" + str(k))
				if str(q[k]) != "":
					list.append(str(q[k]))
		_web_cache = list
	return _web_cache


static func has(key: String) -> bool:
	return args().has("--" + key)
