// 성능 표시 (F3, 2026-10-29 재혁: 자기 PC 에서 8명 판 어디가 무거운지 숫자로 — 엔진을 바꿀지 판단 근거).
// prof: 구간 재기 (render.js 가 래그돌·몸 애니·블록·위험·렌더를 begin/end). 패널이 꺼져 있으면 begin 이 0 을 돌려주고 end 가 바로 돌아가 비용 거의 0.
// PerfPanel: 오른쪽 위 핑 아래 작은 글자 판 + '복사'. 계산은 shared/perf.js. 켠 상태는 이 브라우저에 기억 (tf-perf)
import { CONFIG as C } from '/shared/config.js';
import { PerfWindow, perfLine, shortGpu } from '/shared/perf.js';

export const prof = {
  on: false,
  sec: {},
  begin() {
    return this.on ? performance.now() : 0;
  },
  end(key, t0) {
    if (!this.on) return;
    this.sec[key] = (this.sec[key] || 0) + performance.now() - t0;
  },
};

function loadOn() {
  try {
    return localStorage.getItem('tf-perf') === '1';
  } catch {
    return false;
  }
}

export class PerfPanel {
  // gl: THREE.WebGLRenderer, info(): { players, rag, low, ping } (main.js 가 지금 값)
  constructor(el, gl, info) {
    this.el = el;
    this.gl = gl;
    this.info = info;
    this.win = new PerfWindow();
    this.last = 0;
    this.drawAt = 0;
    this.t0 = 0;
    this.gpu = gpuName(gl);
    this.textEl = el.querySelector('.txt');
    el.querySelector('.copy').addEventListener('click', () => this.copy());
    this.toggle(loadOn(), false);
  }

  toggle(on = !prof.on, save = true) {
    prof.on = !!on;
    this.el.classList.toggle('hidden', !prof.on);
    document.body.classList.toggle('perf', prof.on);
    this.gl.info.autoReset = !prof.on; // 켜면 프레임마다 직접 0 으로 (외곽선은 장면을 두 번 그려서)
    this.win = new PerfWindow();
    this.last = 0;
    if (save) {
      try {
        localStorage.setItem('tf-perf', prof.on ? '1' : '0');
      } catch {
        // 저장 못 해도 이번엔 켜짐
      }
    }
  }

  frameStart(now) {
    if (!prof.on) return;
    prof.sec = {};
    this.t0 = now;
    this.gl.info.reset();
  }

  frameEnd(now) {
    if (!prof.on) return;
    const end = performance.now();
    if (this.last) this.win.push(now, now - this.last, prof.sec, end - this.t0);
    this.last = now;
    this.draws = this.gl.info.render.calls;
    this.tris = this.gl.info.render.triangles;
    if (end - this.drawAt >= C.PERF_DRAW_MS) {
      this.drawAt = end;
      this.draw(now);
    }
  }

  extra() {
    const i = this.info();
    return { draws: this.draws, tris: this.tris, players: i.players, rag: i.rag, low: i.low, size: `${innerWidth}×${innerHeight}`, gpu: this.gpu, ping: i.ping };
  }

  draw(now) {
    const s = this.win.summary(now);
    const e = this.extra();
    const f1 = (v) => (Math.round(v * 10) / 10).toFixed(1);
    const secs = Object.entries(C.PERF_SECTIONS).map(([k, name]) => `${name} ${f1(s.sections[k] || 0)}`);
    this.textEl.textContent = [
      `FPS ${Math.round(s.fps)}  프레임 ${f1(s.avg)}ms · 1% low ${f1(s.low)}ms`,
      `JS ${f1(s.work)}ms (기타 ${f1(s.other)})${e.ping ? ` · 핑 ${e.ping}` : ''}`,
      secs.slice(0, 3).join(' · '),
      secs.slice(3).join(' · '),
      `그리기 ${e.draws ?? 0} · 삼각형 ${Math.round((e.tris ?? 0) / 1000)}k`,
      `${e.players}명 (래그돌 ${e.rag}) · 그래픽 낮춤 ${e.low ? '켬' : '끔'} · ${e.size}`,
      `GPU ${shortGpu(e.gpu) || '모름'}`,
    ].join('\n');
  }

  line() {
    return perfLine(this.win.summary(performance.now()), this.extra());
  }

  async copy() {
    const text = this.line();
    const btn = this.el.querySelector('.copy');
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = '복사됨';
    } catch {
      // 클립보드가 막히면 (http 등) 글을 골라 두어 Ctrl+C 로
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.append(ta);
      ta.select();
      try {
        document.execCommand('copy');
        btn.textContent = '복사됨';
      } catch {
        btn.textContent = '복사 실패';
      }
      ta.remove();
    }
    setTimeout(() => (btn.textContent = '복사'), 1200);
  }
}

// GPU 이름: WEBGL_debug_renderer_info 가 있으면 진짜 이름, 없으면 브라우저가 주는 이름
function gpuName(gl) {
  try {
    const ctx = gl.getContext();
    const ext = ctx.getExtension('WEBGL_debug_renderer_info');
    return String(ctx.getParameter(ext ? ext.UNMASKED_RENDERER_WEBGL : ctx.RENDERER) || '');
  } catch {
    return '';
  }
}
