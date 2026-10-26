// 효과음: 파일 없이 WebAudio 로 합성한다. 브라우저 정책상 첫 클릭(Pointer Lock) 뒤에야 소리가 난다.
import { CONFIG as C } from '/shared/config.js';

export class Sound {
  constructor() {
    this.ctx = null;
    this.volume = 1; // 설정의 효과음 크기 (0~1, SFX_VOLUME 에 곱함)
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = C.SFX_VOLUME * v;
  }

  // 사용자 입력 이벤트 안에서 한 번 불러 오디오를 깨운다
  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = C.SFX_VOLUME * this.volume;
      this.master.connect(this.ctx.destination);
      const len = this.ctx.sampleRate;
      this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this.noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
  }

  ready() {
    return this.ctx && this.ctx.state === 'running';
  }

  // 주파수가 미끄러지는 단순 음
  tone({ freq, freqEnd = freq, dur, type = 'sine', vol = 0.5, delay = 0 }) {
    const t = this.ctx.currentTime + delay;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    const det = this.det || 1; // 같은 소리도 높낮이 조금씩 다르게 (play 마다)
    o.frequency.setValueAtTime(freq * det, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(20, freqEnd * det), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  // 걸러낸 잡음 (타격·바람·부서짐)
  noise({ dur, vol = 0.5, filter = 'lowpass', freq = 1000, freqEnd = freq, q = 1, delay = 0 }) {
    const t = this.ctx.currentTime + delay;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter();
    f.type = filter;
    f.Q.value = q;
    const det = this.det || 1;
    f.frequency.setValueAtTime(freq * det, t);
    f.frequency.exponentialRampToValueAtTime(Math.max(20, freqEnd * det), t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.02);
  }

  // 거리(칸)에 따라 작아지는 크기
  static falloff(dist) {
    if (dist === undefined) return 1;
    return Math.max(0.2, 1 - dist / C.SFX_HEAR_RANGE);
  }

  play(name, { dist, strong = false } = {}) {
    if (!this.ready()) return;
    const v = Sound.falloff(dist);
    this.det = 1 + (Math.random() * 2 - 1) * C.SFX_DETUNE;
    switch (name) {
      case 'tear': // 갈고리 R 블록 뜯김: 찌익 (높아지는 거친 소리) + 낮은 뚝
        this.noise({ dur: 0.32, vol: 0.55 * v, filter: 'bandpass', freq: 350, freqEnd: 2600, q: 2.5 });
        this.tone({ freq: 140, freqEnd: 60, dur: 0.2, type: 'sawtooth', vol: 0.25 * v, delay: 0.22 });
        break;
      case 'shatter': // 대포수 블록 부숨: 와장창 (깨지는 높은 소리 + 낮은 쾅 + 부스러기 딱딱)
        this.noise({ dur: 0.35, vol: 0.7 * v, filter: 'highpass', freq: 2500, freqEnd: 900 });
        this.tone({ freq: 110, freqEnd: 40, dur: 0.25, type: 'square', vol: 0.4 * v });
        for (const d of [0.08, 0.15, 0.23]) this.tone({ freq: 1800 + Math.random() * 1200, freqEnd: 900, dur: 0.04, type: 'triangle', vol: 0.18 * v, delay: d });
        break;
      case 'tap': // 닌자가 떨어지는 블록에 닿음: 작은 탁
        this.tone({ freq: 1400, freqEnd: 800, dur: 0.05, type: 'triangle', vol: 0.3 * v });
        this.noise({ dur: 0.04, vol: 0.2 * v, filter: 'highpass', freq: 3000 });
        break;
      case 'swing': // 휘두르는 바람 소리
        this.noise({ dur: 0.13, vol: 0.3 * v, filter: 'bandpass', freq: 1600, freqEnd: 500, q: 1.5 });
        break;
      case 'hit': // 내가 때림 / 누가 맞음: 퍽 + 짧은 딱
        this.tone({ freq: 190, freqEnd: 55, dur: 0.14, type: 'square', vol: (strong ? 0.5 : 0.3) * v });
        this.noise({ dur: 0.16, vol: (strong ? 0.6 : 0.35) * v, freq: 2600, freqEnd: 300 });
        this.tone({ freq: 1100, freqEnd: 300, dur: 0.05, type: 'triangle', vol: 0.25 * v });
        break;
      case 'crit': // 치명타: 높은 금속성 딩 두 번 + 쩍
        this.tone({ freq: 1500, freqEnd: 900, dur: 0.12, type: 'square', vol: 0.3 * v });
        this.tone({ freq: 2200, freqEnd: 1600, dur: 0.18, type: 'triangle', vol: 0.3 * v, delay: 0.06 });
        this.noise({ dur: 0.12, vol: 0.5 * v, filter: 'highpass', freq: 3000 });
        break;
      case 'hurt': // 내가 맞음: 낮고 묵직하게
        this.tone({ freq: 140, freqEnd: 40, dur: 0.28, type: 'sine', vol: 0.8 });
        this.noise({ dur: 0.22, vol: 0.5, freq: 900, freqEnd: 150 });
        break;
      case 'fire':
        this.tone({ freq: 600, freqEnd: 1500, dur: 0.12, type: 'square', vol: 0.18 * v });
        this.noise({ dur: 0.1, vol: 0.2 * v, filter: 'highpass', freq: 2000 });
        break;
      case 'danger': // 압사 경고: 높은 삑삑
        this.tone({ freq: 1250, dur: 0.07, type: 'square', vol: 0.22 });
        this.tone({ freq: 1250, dur: 0.07, type: 'square', vol: 0.22, delay: 0.11 });
        break;
      case 'airJump': // 2단 점프: 짧은 휙
        this.noise({ dur: 0.12, vol: 0.25 * v, filter: 'bandpass', freq: 900, freqEnd: 2400, q: 1.2 });
        break;
      case 'land': // 블록 착지: 쿵
        this.tone({ freq: 95, freqEnd: 38, dur: 0.18, type: 'sine', vol: 0.55 * v });
        this.noise({ dur: 0.14, vol: 0.3 * v, freq: 600, freqEnd: 120 });
        break;
      case 'crush': // 압사: 으깨짐
        this.noise({ dur: 0.45, vol: 0.8 * v, freq: 1800, freqEnd: 90 });
        this.tone({ freq: 80, freqEnd: 28, dur: 0.4, type: 'square', vol: 0.5 * v });
        break;
      case 'fall': // 낙사: 휘익 떨어짐
        this.tone({ freq: 900, freqEnd: 140, dur: 0.75, type: 'sine', vol: 0.35 * v });
        break;
      case 'lavaDeath':
        this.noise({ dur: 0.6, vol: 0.6 * v, filter: 'bandpass', freq: 1200, freqEnd: 300, q: 0.7 });
        this.tone({ freq: 220, freqEnd: 60, dur: 0.5, type: 'sawtooth', vol: 0.2 * v });
        break;
      case 'pickup':
        this.tone({ freq: 660, dur: 0.09, type: 'triangle', vol: 0.35 });
        this.tone({ freq: 990, dur: 0.14, type: 'triangle', vol: 0.35, delay: 0.08 });
        break;
      case 'lava': // 용암 시작: 우르릉
        this.noise({ dur: 1.6, vol: 0.6, freq: 260, freqEnd: 120 });
        this.tone({ freq: 55, freqEnd: 42, dur: 1.5, type: 'sawtooth', vol: 0.25 });
        break;
      case 'boom': // 폭탄
        this.noise({ dur: 0.9, vol: 0.9 * v, freq: 1400, freqEnd: 60 });
        this.tone({ freq: 70, freqEnd: 25, dur: 0.7, type: 'sine', vol: 0.9 * v });
        break;
      case 'tick': // 카운트다운 3·2·1
        this.tone({ freq: 660, dur: 0.12, type: 'square', vol: 0.22 * v });
        break;
      case 'go': // 시작!
        this.tone({ freq: 990, dur: 0.35, type: 'square', vol: 0.25 });
        this.tone({ freq: 1320, dur: 0.3, type: 'triangle', vol: 0.2, delay: 0.02 });
        break;
      case 'win': // 판 끝, 승자 발표
        [392, 523, 659, 784, 1047].forEach((f, i) => this.tone({ freq: f, dur: 0.22, type: 'triangle', vol: 0.32, delay: i * 0.09 }));
        break;
      case 'clear':
        [523, 659, 784, 1047].forEach((f, i) => this.tone({ freq: f, dur: 0.15, type: 'triangle', vol: 0.3, delay: i * 0.07 }));
        break;
      default:
    }
  }
}
