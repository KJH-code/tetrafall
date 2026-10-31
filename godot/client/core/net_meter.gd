# 접속 상태 (핑·서버 부하·끊김) 계산 (shared/net.js NetMeter 그대로). 화면이 NET_PING_MS 마다 ping, 서버가 pong {t, workMs, behindMs, tickMs}
extends RefCounted

const C := preload("res://core/config.gd")

var rtt = null
var avg = null
var work_ms := 0.0
var behind_ms := 0.0
var last_state_at = null
var warn = null # {text, until}
var spikes := 0
var highs := 0
var recent: Array = []
var gaps: Array = []
var frames: Array = []
var frame_ms := 0.0
var last_frame_at = null


func ping(now: float) -> Dictionary:
	return {"type": "ping", "t": now}


func on_frame(t: float) -> void:
	if last_frame_at != null and t > last_frame_at:
		frames.append(t - last_frame_at)
		frames = frames.slice(-int(C.NET_FRAME_WINDOW))
	frame_ms = frames.max() if not frames.is_empty() else 0.0
	last_frame_at = t


func slack(now: float) -> float:
	return maxf(frame_ms, 0.0 if last_frame_at == null else now - last_frame_at)


func on_pong(msg: Dictionary, now: float) -> void:
	var r: float = now - float(msg.get("t", 0))
	if not (r >= 0):
		return
	var net: float = r - slack(now)
	var spike: bool = avg != null and net > avg * C.NET_PING_SPIKE_MULT and net > C.NET_PING_WARN_MS / 2
	spikes = spikes + 1 if spike else 0
	highs = highs + 1 if net > C.NET_PING_WARN_MS else 0
	rtt = r
	if not spike:
		avg = maxf(0, net) if avg == null else avg * 0.8 + maxf(0, net) * 0.2
	recent.append(net)
	recent = recent.slice(-int(C.NET_PING_REPEAT))
	work_ms = float(msg.get("workMs", 0) if msg.get("workMs") != null else 0)
	behind_ms = float(msg.get("behindMs", 0) if msg.get("behindMs") != null else 0)
	if highs >= C.NET_PING_REPEAT:
		set_warn("핑 높음 %dms" % roundi(r), now)
	elif spikes >= C.NET_PING_REPEAT:
		set_warn("핑 튐 %dms" % roundi(r), now)
	if work_ms > C.NET_SERVER_SLOW_MS or behind_ms > C.NET_SERVER_BEHIND_MS:
		set_warn("서버 느림", now)


func on_state(now: float) -> void:
	var gap: float = 0.0 if last_state_at == null else now - last_state_at - slack(now)
	last_state_at = now
	if gap <= C.NET_SNAPSHOT_GAP_MS:
		return
	gaps = gaps.filter(func(t): return now - t < C.NET_GAP_WINDOW_MS)
	gaps.append(now)
	if gap > C.NET_SNAPSHOT_STALL_MS or gaps.size() >= C.NET_GAP_REPEAT:
		set_warn("끊김 %dms" % roundi(gap), now)


func set_warn(text: String, now: float) -> void:
	warn = {"text": text, "until": now + C.NET_WARN_HOLD_MS}


# 화면에 보일 것: {ping: "NNms" | "…", server: ms, warn: 글 | null, level: "ok" | "warn" | "bad"}
func view(now: float) -> Dictionary:
	if last_state_at != null and now - last_state_at - slack(now) > C.NET_SNAPSHOT_STALL_MS:
		set_warn("끊김 %dms" % roundi(now - last_state_at), now)
	var w = warn.text if warn != null and now < warn.until else null
	var bad: bool = recent.size() >= C.NET_PING_REPEAT and recent.min() > C.NET_PING_WARN_MS * 2
	return {
		"ping": "…" if rtt == null else "%dms" % roundi(rtt),
		"server": roundi(work_ms),
		"warn": w,
		"level": "bad" if bad else ("warn" if w != null else "ok"),
	}
