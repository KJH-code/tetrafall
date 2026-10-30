// 타이틀 소리 (전부 합성, sound.js 의 tone·noise 를 빌림): 테마마다 어두운 앰비언트 (낮은 웅웅 + 걸러낸 잡음 + 띄엄띄엄 소리:
// 동굴 물방울·울림, 화산 불씨 탁탁, 사막 바람, 버섯 뽀글, 하늘 성 풍경, 성채 횃불, 초원 귀뚜라미) + 블록 착지 재질 소리 + 로고 완성 반짝 + 빠져나가기 쉭.
// 값은 config TITLE_THEMES.*.sound · TITLE_SOUND. 오디오는 첫 입력 뒤에야 깨어남 (브라우저 규칙) → 그 전엔 조용, 깨면 앰비언트 시작
import { CONFIG as C } from '/shared/config.js';

const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

export class TitleSound {
  // sound: Sound (sound.js), theme: TITLE_THEMES 키. 메뉴·대기실까지 이어질 땐 music.js 가 맡아 매 프레임 update (곡은 그동안 쉼)
  constructor(sound, theme) {
    this.s = sound;
    this.theme = theme;
    this.S = C.TITLE_THEMES[theme].sound;
    this.nodes = [];
    this.out = null;
    this.nextPing = 0;
    this.stopped = false;
    this.lastLand = 0;
  }

  // 매 프레임: 오디오가 깨어 있으면 한 번 준비 (앰비언트 켜기), 띄엄띄엄 소리
  update() {
    const s = this.s;
    if (this.stopped || !s.ready()) return;
    if (!this.out) this.build();
    const now = s.ctx.currentTime;
    if (now >= this.nextPing) {
      if (this.nextPing) this.ping();
      const [a, b] = C.TITLE_SOUND.pingEvery;
      this.nextPing = now + a + Math.random() * (b - a);
    }
  }

  build() {
    const s = this.s;
    const ctx = s.ctx;
    const t = ctx.currentTime;
    this.out = ctx.createGain();
    this.out.gain.setValueAtTime(0, t);
    this.out.gain.linearRampToValueAtTime(C.TITLE_SOUND.vol, t + C.TITLE_SOUND.fadeIn);
    this.out.connect(s.master);
    // 울림 (메아리): 띄엄띄엄 소리·착지·반짝이 다 거침
    this.wet = ctx.createGain();
    this.wet.gain.value = C.TITLE_SOUND.echo;
    const d = ctx.createDelay(1.5);
    d.delayTime.value = C.TITLE_SOUND.echoDelay;
    const fb = ctx.createGain();
    fb.gain.value = C.TITLE_SOUND.echoFeedback;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 2200;
    this.wet.connect(d).connect(lp).connect(fb).connect(d);
    lp.connect(this.out);
    this.fx = ctx.createGain(); // 효과 소리 입구 (마른 소리 + 울림)
    this.fx.connect(this.out);
    this.fx.connect(this.wet);
    // 낮은 웅웅: 두 음 (조금 어긋나 맥놀이) 을 걸러서
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 320;
    const g = ctx.createGain();
    g.gain.value = 0.32;
    f.connect(g).connect(this.out);
    for (const hz of this.S.drone) {
      for (const det of [1, 1.006]) {
        const o = ctx.createOscillator();
        o.type = 'sawtooth';
        o.frequency.value = hz * det;
        o.connect(f);
        o.start(t);
        this.nodes.push(o);
      }
    }
    const lfo = ctx.createOscillator();
    const lg = ctx.createGain();
    lfo.frequency.value = 0.09;
    lg.gain.value = 120;
    lfo.connect(lg).connect(f.frequency);
    lfo.start(t);
    this.nodes.push(lfo);
    // 바탕 잡음 (동굴 바람·불길·밤 공기): 갈색 잡음을 테마 대역으로
    const n = ctx.createBufferSource();
    n.buffer = s.brownBuf;
    n.loop = true;
    const nf = ctx.createBiquadFilter();
    nf.type = 'bandpass';
    nf.frequency.value = this.S.hum;
    nf.Q.value = 0.6;
    const ng = ctx.createGain();
    ng.gain.value = 0.55;
    n.connect(nf).connect(ng).connect(this.out);
    n.start(t);
    this.nodes.push(n);
  }

  // 띄엄띄엄 소리 (테마마다)
  ping() {
    const s = this.s;
    const o = this.fx;
    s.det = 1 + (Math.random() * 2 - 1) * 0.08;
    const kind = this.S.ping;
    if (kind === 'drip') {
      // 물방울: 짧게 위로 미끄러지는 맑은 음 (울림이 길게)
      const f = 900 + Math.random() * 900;
      s.tone({ freq: f, freqEnd: f * 1.9, dur: 0.09, type: 'sine', vol: 0.5, out: o });
      s.tone({ freq: f * 2.4, freqEnd: f * 3, dur: 0.05, type: 'sine', vol: 0.12, delay: 0.01, out: o });
    } else if (kind === 'ember') {
      for (let i = 0; i < 4; i++) s.noise({ dur: 0.03, vol: 0.4, filter: 'highpass', freq: 2500, delay: i * (0.04 + Math.random() * 0.08), out: o }); // 탁탁
      s.tone({ freq: 50, freqEnd: 38, dur: 1.2, type: 'sine', vol: 0.25, out: o }); // 우르릉
    } else if (kind === 'wind') {
      s.noise({ dur: 2.6, vol: 0.35, filter: 'bandpass', freq: 500, freqEnd: 1400, q: 3, out: o }); // 휘이잉
    } else if (kind === 'bubble') {
      for (let i = 0; i < 3; i++) s.tone({ freq: 220 + Math.random() * 200, freqEnd: 700, dur: 0.07, type: 'sine', vol: 0.3, delay: i * 0.11, out: o }); // 뽀글
    } else if (kind === 'chime') {
      const scale = [0, 3, 5, 7, 10, 12];
      for (let i = 0; i < 2; i++) s.tone({ freq: midiHz(this.S.pitch + scale[Math.floor(Math.random() * scale.length)]), dur: 2.2, type: 'sine', vol: 0.22, delay: i * 0.3, out: o }); // 풍경
    } else if (kind === 'torch') {
      s.noise({ dur: 1.4, vol: 0.35, filter: 'lowpass', freq: 500, freqEnd: 250, out: o }); // 화르르
      for (let i = 0; i < 3; i++) s.noise({ dur: 0.02, vol: 0.3, filter: 'highpass', freq: 3000, delay: Math.random() * 0.8, out: o });
    } else if (kind === 'cricket') {
      for (let i = 0; i < 6; i++) s.tone({ freq: 4200, freqEnd: 4400, dur: 0.035, type: 'square', vol: 0.05, delay: i * 0.06, out: o }); // 찌르르
    }
    s.det = 1;
  }

  // 블록 착지 (n = 이번 프레임에 닿은 조각 수): 재질 소리. 겹쳐 떨어지면 너무 많지 않게 묶음
  land(n) {
    const s = this.s;
    if (this.stopped || !s.ready() || !this.out) return;
    const now = s.ctx.currentTime;
    if (now - this.lastLand < C.TITLE_SOUND.landGap) return;
    this.lastLand = now;
    const o = this.fx;
    const v = C.TITLE_SOUND.land * Math.min(1.6, 0.8 + n * 0.2);
    s.det = 1 + (Math.random() * 2 - 1) * 0.12;
    const kind = this.S.land;
    if (kind === 'crystal') {
      const f = midiHz(this.S.pitch + [0, 4, 7, 12][Math.floor(Math.random() * 4)]);
      s.tone({ freq: f, dur: 0.5, type: 'sine', vol: v * 0.5, out: o }); // 칭
      s.tone({ freq: f * 2.76, dur: 0.18, type: 'sine', vol: v * 0.18, out: o });
      s.noise({ dur: 0.04, vol: v * 0.3, filter: 'highpass', freq: 4000, out: o });
    } else if (kind === 'stone') {
      s.noise({ dur: 0.16, vol: v * 0.8, filter: 'lowpass', freq: 700, freqEnd: 200, out: o }); // 쿵
      s.tone({ freq: 110, freqEnd: 60, dur: 0.14, type: 'sine', vol: v * 0.5, out: o });
    } else if (kind === 'sand') {
      s.noise({ dur: 0.22, vol: v * 0.6, filter: 'bandpass', freq: 1800, freqEnd: 900, q: 0.8, out: o }); // 사각
      s.tone({ freq: 90, freqEnd: 60, dur: 0.1, type: 'sine', vol: v * 0.35, out: o });
    } else {
      s.tone({ freq: 160, freqEnd: 90, dur: 0.12, type: 'sine', vol: v * 0.6, out: o }); // 퐁 (버섯·풀)
      s.noise({ dur: 0.08, vol: v * 0.3, filter: 'lowpass', freq: 900, out: o });
    }
    s.det = 1;
  }

  // 로고 완성: 낮은 쿵 + 올라가는 반짝 아르페지오 + 높은 반짝임 잡음
  burst() {
    const s = this.s;
    if (this.stopped || !s.ready() || !this.out) return;
    const o = this.fx;
    const v = C.TITLE_SOUND.burst;
    s.tone({ freq: 70, freqEnd: 35, dur: 1.4, type: 'sine', vol: v * 0.8, out: o });
    s.noise({ dur: 1.6, vol: v * 0.35, filter: 'lowpass', freq: 1200, freqEnd: 120, out: o });
    [0, 7, 12, 16, 19, 24].forEach((m, i) => s.tone({ freq: midiHz(this.S.pitch + m), dur: 1.4 - i * 0.1, type: 'triangle', vol: v * 0.3, delay: 0.05 + i * 0.07, out: o }));
    s.noise({ dur: 1.8, vol: v * 0.25, filter: 'highpass', freq: 6000, freqEnd: 9000, delay: 0.1, out: o });
  }

  // Enter: 앞으로 빠져나가는 쉭 (점점 높게)
  exit() {
    const s = this.s;
    if (this.stopped || !s.ready() || !this.out) return;
    s.noise({ dur: C.TITLE_EXIT_MS / 1000 + 0.2, vol: C.TITLE_SOUND.exit, filter: 'bandpass', freq: 300, freqEnd: 4000, q: 1.2, out: this.fx });
    s.tone({ freq: midiHz(this.S.pitch + 12), freqEnd: midiHz(this.S.pitch + 24), dur: C.TITLE_EXIT_MS / 1000, type: 'sine', vol: C.TITLE_SOUND.exit * 0.3, out: this.fx });
  }

  // 끝: 앰비언트 천천히 줄이고 노드 정리
  stop() {
    if (this.stopped) return;
    this.stopped = true;
    if (!this.out) return;
    const ctx = this.s.ctx;
    const t = ctx.currentTime;
    this.out.gain.cancelScheduledValues(t);
    this.out.gain.setTargetAtTime(0, t, 0.4);
    const nodes = this.nodes;
    setTimeout(() => {
      for (const n of nodes) n.stop?.();
      this.out.disconnect();
    }, 3000);
  }
}
