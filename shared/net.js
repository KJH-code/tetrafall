// 접속 상태 (핑·서버 부하·끊김) 계산: three.js·DOM 없는 순수 계산 — client/net.js 가 쓰고 test/ko.test.js 가 검증한다.
// 화면이 NET_PING_MS 마다 { type: 'ping', t } 를 보내고, 서버가 pong { t, workMs, behindMs, tickMs } 로 답함 (server/rooms.js).
import { CONFIG as C } from './config.js';

export class NetMeter {
  constructor() {
    this.rtt = null; // 마지막 왕복 시간 (ms)
    this.avg = null; // 최근 평균 (지수 평균)
    this.workMs = 0; // 서버 틱 한 번 일한 시간 (최근 최댓값)
    this.behindMs = 0; // 서버 틱이 밀린 시간
    this.lastStateAt = null; // 마지막 스냅샷 받은 시각
    this.warn = null; // { text, until }
    this.spikes = 0; // 연속으로 튄 핑 수
    this.highs = 0; // 연속으로 높은 핑 수
    this.recent = []; // 최근 핑 NET_PING_REPEAT 개
    this.gaps = []; // 스냅샷이 빈 시각 (NET_GAP_WINDOW_MS 안)
    this.frames = []; // 최근 화면 프레임 간격 (ms, NET_FRAME_WINDOW 개)
    this.frameMs = 0; // 그중 가장 긴 것: 이만큼은 화면 쪽이 늦은 것 (pong·스냅샷 처리가 프레임을 기다림)
    this.lastFrameAt = null;
  }

  ping(now) {
    return { type: 'ping', t: now };
  }

  // 화면 프레임마다 (client/net.js 의 requestAnimationFrame 시각 t, performance.now 와 같은 시계)
  onFrame(t) {
    if (this.lastFrameAt !== null && t > this.lastFrameAt) this.frames = [...this.frames, t - this.lastFrameAt].slice(-C.NET_FRAME_WINDOW);
    this.frameMs = this.frames.length ? Math.max(...this.frames) : 0;
    this.lastFrameAt = t;
  }

  // 화면 쪽이 늦은 시간: 최근 가장 긴 프레임, 또는 지금 프레임이 아직 안 끝났으면 (메인 스레드가 막혀 메시지를 늦게 처리) 그만큼. 프레임을 모르면 0
  slack(now) {
    return Math.max(this.frameMs, this.lastFrameAt === null ? 0 : now - this.lastFrameAt);
  }

  // 한 번 튄 핑은 알림 안 함 (화면이 잠깐 멈춰 pong 처리가 늦어도 튐): 연속 NET_PING_REPEAT 번 높거나 튀어야
  onPong(msg, now) {
    const rtt = now - msg.t;
    if (!(rtt >= 0)) return;
    const net = rtt - this.slack(now); // 화면이 늦은 만큼 빼면 네트워크 몫 (표시는 rtt 그대로)
    const spike = this.avg !== null && net > this.avg * C.NET_PING_SPIKE_MULT && net > C.NET_PING_WARN_MS / 2;
    this.spikes = spike ? this.spikes + 1 : 0;
    this.highs = net > C.NET_PING_WARN_MS ? this.highs + 1 : 0;
    this.rtt = rtt;
    if (!spike) this.avg = this.avg === null ? Math.max(0, net) : this.avg * 0.8 + Math.max(0, net) * 0.2; // 튄 값은 평균에 안 넣음 (다음 튐도 잡게)
    this.recent = [...this.recent, net].slice(-C.NET_PING_REPEAT);
    this.workMs = msg.workMs || 0;
    this.behindMs = msg.behindMs || 0;
    if (this.highs >= C.NET_PING_REPEAT) this.setWarn(`핑 높음 ${Math.round(rtt)}ms`, now);
    else if (this.spikes >= C.NET_PING_REPEAT) this.setWarn(`핑 튐 ${Math.round(rtt)}ms`, now);
    if (this.workMs > C.NET_SERVER_SLOW_MS || this.behindMs > C.NET_SERVER_BEHIND_MS) this.setWarn('서버 느림', now);
  }

  // 스냅샷을 받을 때마다. 사이가 NET_SNAPSHOT_GAP_MS 넘게 빈 게 NET_GAP_WINDOW_MS 안에 NET_GAP_REPEAT 번이거나, 한 번이라도 NET_SNAPSHOT_STALL_MS 넘으면 끊김 알림
  onState(now) {
    const gap = this.lastStateAt === null ? 0 : now - this.lastStateAt - this.slack(now); // 화면이 멈칫한 만큼은 빼고
    this.lastStateAt = now;
    if (gap <= C.NET_SNAPSHOT_GAP_MS) return;
    this.gaps = [...this.gaps.filter((t) => now - t < C.NET_GAP_WINDOW_MS), now];
    if (gap > C.NET_SNAPSHOT_STALL_MS || this.gaps.length >= C.NET_GAP_REPEAT) this.setWarn(`끊김 ${Math.round(gap)}ms`, now);
  }

  setWarn(text, now) {
    this.warn = { text, until: now + C.NET_WARN_HOLD_MS };
  }

  // 화면에 보일 것: { ping: 'NNms' | '…', server: 서버 일한 시간 ms, warn: 알림 글 | null, level: 'ok' | 'warn' | 'bad' }
  view(now) {
    if (this.lastStateAt !== null && now - this.lastStateAt - this.slack(now) > C.NET_SNAPSHOT_STALL_MS) this.setWarn(`끊김 ${Math.round(now - this.lastStateAt)}ms`, now); // 지금도 안 옴
    const warn = this.warn && now < this.warn.until ? this.warn.text : null;
    const bad = this.recent.length >= C.NET_PING_REPEAT && Math.min(...this.recent) > C.NET_PING_WARN_MS * 2; // 빨강도 연속일 때만
    return {
      ping: this.rtt === null ? '…' : `${Math.round(this.rtt)}ms`,
      server: Math.round(this.workMs),
      warn,
      level: bad ? 'bad' : warn ? 'warn' : 'ok',
    };
  }
}
