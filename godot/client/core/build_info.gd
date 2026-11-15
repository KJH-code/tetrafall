# 이 빌드가 어느 버전인가 (W48 성능 보고서 첫 줄). 소스에서 돌리면 아래 값 그대로 ('dev'), 배포 묶음 (godot/server/tools/package.mjs) 은
# 내보내는 동안만 이 파일의 TAG·COMMIT 을 git 태그·커밋으로 바꿨다가 끝나면 되돌림 (stampBuildInfo) → 내보낸 클라가 자기 버전을 앎.
extends RefCounted

const TAG := "dev"
const COMMIT := ""


static func text() -> String:
	return TAG + ((" (%s)" % COMMIT) if COMMIT != "" else "")
