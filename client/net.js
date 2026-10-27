// 접속 상태 표시 (2026-10-27 재혁: 렉·핑을 모름): 화면 구석에 핑·서버 부하, 렉 걸리면 알림.
// 계산은 shared/net.js. 요소 id 만 만들고 모양은 최소 (HUD 디자인은 B 가 입힘): #net > #netPing · #netWarn
import { CONFIG as C } from '/shared/config.js';
import { NetMeter } from '/shared/net.js';

export class NetStatus {
  // send(obj): 서버로 보내는 함수 (main.js)
  constructor(send, parent = document.body) {
    this.send = send;
    this.meter = new NetMeter();
    this.el = document.createElement('div');
    this.el.id = 'net';
    this.el.style.cssText = 'position:fixed;right:8px;bottom:6px;font:12px monospace;color:#cfd8dc;opacity:.8;pointer-events:none;z-index:50;text-align:right';
    this.pingEl = document.createElement('span');
    this.pingEl.id = 'netPing';
    this.warnEl = document.createElement('div');
    this.warnEl.id = 'netWarn';
    this.warnEl.style.cssText = 'color:#ffb74d;font-weight:bold';
    this.el.append(this.warnEl, this.pingEl);
    parent.appendChild(this.el);
    this.timer = setInterval(() => this.send(this.meter.ping(performance.now())), C.NET_PING_MS);
    this.drawTimer = setInterval(() => this.draw(), 250);
  }

  // main.js ws.onmessage 에서 모든 메시지를 넘김 (pong·state 만 씀)
  onMessage(msg) {
    const now = performance.now();
    if (msg.type === 'pong') this.meter.onPong(msg, now);
    else if (msg.type === 'state') this.meter.onState(now);
  }

  draw() {
    const v = this.meter.view(performance.now());
    this.pingEl.textContent = `핑 ${v.ping}${v.server >= C.NET_SERVER_SLOW_MS ? ` · 서버 ${v.server}ms` : ''}`;
    this.pingEl.dataset.level = v.level; // B 가 색 입힐 자리 ([data-level=bad])
    this.pingEl.style.color = v.level === 'bad' ? '#ef5350' : v.level === 'warn' ? '#ffb74d' : '';
    this.warnEl.textContent = v.warn ? `⚠ ${v.warn}` : '';
  }

  stop() {
    clearInterval(this.timer);
    clearInterval(this.drawTimer);
  }
}
