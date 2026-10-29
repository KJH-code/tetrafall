// 성능 표시 계산 (F3 패널): DOM·three.js 없는 순수 계산 — client/perf.js 가 쓰고 test/perf.test.js 가 검증한다.
// 프레임마다 { t: 시각(ms), ms: 프레임 간격, sec: { 구간: ms }, work: 그 프레임 JS 일한 시간 } 을 넣으면
// FPS·평균 프레임 시간·1% low·구간 평균·기타 JS (= 일한 시간 - 잰 구간 합) 를 낸다
import { CONFIG as C } from './config.js';

export class PerfWindow {
  constructor() {
    this.frames = [];
  }

  push(t, ms, sec = {}, work = ms) {
    this.frames.push({ t, ms, sec, work });
    const old = t - C.PERF_LOW_MS;
    let cut = 0;
    while (cut < this.frames.length && this.frames[cut].t < old) cut++;
    if (cut) this.frames.splice(0, cut);
  }

  // now: 지금 시각. 최근 PERF_FPS_MS 로 FPS·평균·구간, 최근 PERF_LOW_MS 로 1% low
  summary(now) {
    const recent = this.frames.filter((f) => f.t >= now - C.PERF_FPS_MS);
    const n = recent.length;
    const avg = n ? recent.reduce((s, f) => s + f.ms, 0) / n : 0;
    const sections = {};
    for (const k of Object.keys(C.PERF_SECTIONS)) sections[k] = n ? recent.reduce((s, f) => s + (f.sec[k] || 0), 0) / n : 0;
    const measured = Object.values(sections).reduce((s, v) => s + v, 0);
    const work = n ? recent.reduce((s, f) => s + f.work, 0) / n : 0;
    return { fps: (n * 1000) / C.PERF_FPS_MS, avg, low: worstAvg(this.frames.map((f) => f.ms), C.PERF_LOW_FRAC), sections, work, other: Math.max(0, work - measured), frames: n };
  }
}

// 가장 느린 frac 만큼(적어도 1개)의 평균 = "1% low" 프레임 시간
export function worstAvg(list, frac) {
  if (!list.length) return 0;
  const k = Math.max(1, Math.ceil(list.length * frac));
  const worst = [...list].sort((a, b) => b - a).slice(0, k);
  return worst.reduce((s, v) => s + v, 0) / k;
}

// 복사용 한 줄 (재혁이 붙여넣기 쉽게). extra: { draws, tris, players, rag, low, gpu, ping, size }
export function perfLine(s, extra = {}) {
  const f1 = (v) => (Math.round(v * 10) / 10).toFixed(1);
  const parts = [`FPS ${Math.round(s.fps)}`, `프레임 평균 ${f1(s.avg)}ms`, `1% low ${f1(s.low)}ms`, `JS ${f1(s.work)}ms`];
  for (const [k, name] of Object.entries(C.PERF_SECTIONS)) parts.push(`${name} ${f1(s.sections[k] || 0)}`);
  parts.push(`기타 JS ${f1(s.other)}`);
  if (extra.draws !== undefined) parts.push(`그리기 ${extra.draws}`);
  if (extra.tris !== undefined) parts.push(`삼각형 ${extra.tris >= 1000 ? `${Math.round(extra.tris / 1000)}k` : extra.tris}`);
  if (extra.players !== undefined) parts.push(`${extra.players}명 (래그돌 ${extra.rag ?? 0})`);
  if (extra.low !== undefined) parts.push(`그래픽 낮춤 ${extra.low ? '켬' : '끔'}`);
  if (extra.size) parts.push(`화면 ${extra.size}`);
  if (extra.gpu) parts.push(`GPU ${extra.gpu}`);
  if (extra.ping) parts.push(`핑 ${extra.ping}`);
  return parts.join(' · ');
}

// 패널에 보일 짧은 GPU 이름 (복사 줄은 전체): "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)" → "NVIDIA GeForce RTX 3060"
export function shortGpu(name) {
  let s = String(name || '');
  const m = s.match(/^ANGLE \((.*)\)$/);
  if (m) {
    const parts = m[1].split(', ');
    s = parts.length >= 2 ? parts[1] : parts[0];
  }
  return s
    .replace(/\(0x[0-9a-f]+\)/gi, '')
    .replace(/\s+(Direct3D|vs_|ps_|OpenGL|Vulkan|Metal)\S*.*$/i, '')
    .replace(/\s+/g, ' ')
    .replace(/\s+\)/g, ')')
    .trim();
}
