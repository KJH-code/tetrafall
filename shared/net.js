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
  }

  ping(now) {
    return { type: 'ping', t: now };
  }

  onPong(msg, now) {
    const rtt = now - msg.t;
    if (!(rtt >= 0)) return;
    const spike = this.avg !== null && rtt > this.avg * C.NET_PING_SPIKE_MULT && rtt > C.NET_PING_WARN_MS / 2;
    this.rtt = rtt;
    this.avg = this.avg === null ? rtt : this.avg * 0.8 + rtt * 0.2;
    this.workMs = msg.workMs || 0;
    this.behindMs = msg.behindMs || 0;
    if (spike) this.setWarn(`핑 튐 ${Math.round(rtt)}ms`, now);
    else if (rtt > C.NET_PING_WARN_MS) this.setWarn(`핑 높음 ${Math.round(rtt)}ms`, now);
    if (this.workMs > C.NET_SERVER_SLOW_MS || this.behindMs > C.NET_SERVER_BEHIND_MS) this.setWarn('서버 느림', now);
  }

  // 스냅샷을 받을 때마다. 사이가 NET_SNAPSHOT_GAP_MS 넘게 비었으면 끊김 알림
  onState(now) {
    if (this.lastStateAt !== null && now - this.lastStateAt > C.NET_SNAPSHOT_GAP_MS) this.setWarn(`끊김 ${Math.round(now - this.lastStateAt)}ms`, now);
    this.lastStateAt = now;
  }

  setWarn(text, now) {
    this.warn = { text, until: now + C.NET_WARN_HOLD_MS };
  }

  // 화면에 보일 것: { ping: 'NNms' | '…', server: 서버 일한 시간 ms, warn: 알림 글 | null, level: 'ok' | 'warn' | 'bad' }
  view(now) {
    if (this.lastStateAt !== null && now - this.lastStateAt > C.NET_SNAPSHOT_GAP_MS) this.setWarn(`끊김 ${Math.round(now - this.lastStateAt)}ms`, now); // 지금도 안 옴
    const warn = this.warn && now < this.warn.until ? this.warn.text : null;
    const bad = this.rtt !== null && this.rtt > C.NET_PING_WARN_MS * 2;
    return {
      ping: this.rtt === null ? '…' : `${Math.round(this.rtt)}ms`,
      server: Math.round(this.workMs),
      warn,
      level: bad ? 'bad' : warn ? 'warn' : 'ok',
    };
  }
}
