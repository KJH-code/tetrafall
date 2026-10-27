// 플레이어 위치 보간 (three.js 없는 순수 계산, render.js 가 씀)
// 서버는 30Hz 로 스냅샷을 보내고 도착 간격은 들쭉날쭉하다. 최신 값을 쫓아가면 스냅샷이 올 때마다 확 움직였다 느려져서 뚝뚝 끊김.
// 그래서 스냅샷을 서버 시각(state.time)으로 쌓아 두고, 화면은 '추정 서버 시각 - 지연'에 해당하는 위치를 두 스냅샷 사이에서 선형으로 고른다.
import { CONFIG as C } from '../shared/config.js';

// 화면 시계: 서버 시각을 로컬 시각으로 옮겨 재고, 프레임마다 dt 만큼 고르게 흐른다 (도착이 들쭉날쭉해도 안 튐)
export class SnapClock {
  constructor() {
    this.reset();
  }

  reset() {
    this.samples = []; // 최근 (서버 시각 - 도착 시각). 가장 큰 값 = 가장 덜 늦게 온 스냅샷
    this.offset = null;
    this.t = null; // 화면 서버 시각 (지연 0 기준, ms)
    this.lastServer = -Infinity;
  }

  // 스냅샷 도착: serverMs = state.time, nowMs = 받은 로컬 시각. 서버 시각이 뒤로 가면 (새 방) 처음부터
  onSnapshot(serverMs, nowMs) {
    if (serverMs < this.lastServer - C.INTERP_RESET_MS) this.reset();
    this.lastServer = serverMs;
    this.samples.push(serverMs - nowMs);
    if (this.samples.length > C.INTERP_CLOCK_SAMPLES) this.samples.shift();
    this.offset = Math.max(...this.samples);
  }

  // 프레임마다: 화면 서버 시각을 dt 만큼 흘리고, 목표(지금 로컬 시각 + offset)와의 차이는 천천히 메움
  advance(nowMs, dtMs) {
    if (this.offset === null) return null;
    const target = nowMs + this.offset;
    if (this.t === null || Math.abs(target - this.t) > C.INTERP_RESET_MS) this.t = target;
    else {
      const err = target - (this.t + dtMs);
      this.t += dtMs + Math.max(-dtMs * C.INTERP_CLOCK_SLEW, Math.min(dtMs * C.INTERP_CLOCK_SLEW, err));
    }
    return this.t;
  }
}

// 플레이어 한 명의 스냅샷 기록 [{t, x, y, z}] (서버 시각 오름차순)
export function pushTrack(track, t, x, y, z) {
  const last = track[track.length - 1];
  if (last && t <= last.t) {
    if (t === last.t) Object.assign(last, { x, y, z });
    else track.length = 0; // 시각이 뒤로 감: 새로
  } else if (last && Math.hypot(x - last.x, y - last.y, z - last.z) > C.INTERP_TELEPORT) track.length = 0; // 순간이동·부활: 이어 그리지 않음
  track.push({ t, x, y, z });
  while (track.length > C.INTERP_TRACK_LEN) track.shift();
}

// 시각 t 의 위치. 기록 사이면 선형 보간, 앞이면 첫 값, 뒤면 마지막 두 점으로 extrapMs 까지만 내다봄
export function sampleTrack(track, t, extrapMs, out = {}) {
  const n = track.length;
  if (!n) return null;
  if (n === 1 || t <= track[0].t) return Object.assign(out, { x: track[0].x, y: track[0].y, z: track[0].z });
  let i = n - 1;
  while (i > 0 && track[i - 1].t > t) i--;
  const a = track[Math.max(0, i - 1)];
  const b = track[i];
  if (t >= b.t) {
    // 다음 스냅샷이 아직 안 옴: 마지막 속도로 조금만 더 감
    const span = b.t - a.t;
    const u = span > 0 ? Math.min(t - b.t, extrapMs) / span : 0;
    return Object.assign(out, { x: b.x + (b.x - a.x) * u, y: b.y + (b.y - a.y) * u, z: b.z + (b.z - a.z) * u });
  }
  const u = (t - a.t) / (b.t - a.t);
  return Object.assign(out, { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, z: a.z + (b.z - a.z) * u });
}
