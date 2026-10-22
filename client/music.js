// 배경음악: 파일 없이 WebAudio 로 합성한 칩튠 반복곡. 효과음과 같은 AudioContext 를 쓴다 (첫 클릭 뒤부터 남).
// 분위기 'calm'(대기·판 종료) · 'battle'(판 중) · 'lava'(용암이 올라오는 중) 에 따라 빠르기와 악기가 바뀐다.
// 16분음표 한 칸씩 조금 앞서 예약해서(lookahead) 프레임이 끊겨도 박자가 안 밀린다.
import { CONFIG as C } from '/shared/config.js';

// 4마디 진행 Am - F - C - G (MIDI 음 번호, 화음 세 음)
const PROG = [
  [57, 60, 64],
  [53, 57, 60],
  [48, 52, 55],
  [55, 59, 62],
];
const STEPS = 16; // 한 마디 16칸
const AHEAD_S = 0.2; // 이만큼 앞까지 예약
const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

export class Music {
  constructor(sound) {
    this.sound = sound;
    this.on = true;
    this.volume = 1;
    this.mood = 'calm';
    this.step = 0;
    this.nextAt = 0;
    this.gain = null;
    this.timer = null;
    this.notes = 0; // 예약한 음 수 (헤드리스 확인용)
  }

  // 설정의 음악 크기 (0~1, MUSIC_VOLUME 에 곱함). 0 이면 꺼서 예약도 안 함
  setVolume(v) {
    this.volume = v;
    this.on = v > 0;
    if (this.gain) this.gain.gain.setTargetAtTime(C.MUSIC_VOLUME * v, this.sound.ctx.currentTime, 0.15);
  }

  setMood(mood) {
    this.mood = mood;
  }

  // 매 프레임 불러도 됨: 오디오가 깨어나면 한 번만 준비하고 예약 타이머를 돌린다
  update() {
    if (this.timer || !this.sound.ready()) return;
    const ctx = this.sound.ctx;
    this.gain = ctx.createGain();
    this.gain.gain.value = C.MUSIC_VOLUME * this.volume;
    this.gain.connect(ctx.destination);
    this.nextAt = ctx.currentTime + 0.1;
    this.timer = setInterval(() => this.schedule(), 50);
  }

  schedule() {
    const ctx = this.sound.ctx;
    if (!this.on) {
      this.nextAt = ctx.currentTime + 0.1; // 꺼져 있는 동안은 예약 안 함 (켜면 바로 이어서)
      return;
    }
    if (this.nextAt < ctx.currentTime) this.nextAt = ctx.currentTime + 0.05; // 탭이 멈췄다 돌아온 경우
    while (this.nextAt < ctx.currentTime + AHEAD_S) {
      this.playStep(this.step, this.nextAt);
      this.nextAt += 60 / C.MUSIC_BPM[this.mood] / 4;
      this.step = (this.step + 1) % (STEPS * PROG.length);
    }
  }

  playStep(i, t) {
    const s = i % STEPS;
    const chord = PROG[Math.floor(i / STEPS) % PROG.length];
    const stepS = 60 / C.MUSIC_BPM[this.mood] / 4;
    if (this.mood === 'calm') {
      // 대기: 마디 첫 박에 부드러운 화음, 반 마디마다 베이스
      if (s === 0) for (const m of chord) this.note(midiHz(m), t, stepS * 14, 'sine', 0.18);
      if (s % 8 === 0) this.note(midiHz(chord[0] - 12), t, stepS * 6, 'triangle', 0.5);
      return;
    }
    const lava = this.mood === 'lava';
    // 베이스: 8분음표로 뿌리음 (용암이면 옥타브 오르내림)
    if (s % 2 === 0) this.note(midiHz(chord[0] - 12 + (lava && s % 4 === 2 ? 12 : 0)), t, stepS * 1.6, 'triangle', 0.55);
    // 리드: 화음을 16분음표로 쪼갬 (용암이면 한 옥타브 위)
    this.note(midiHz(chord[s % 3] + (lava ? 24 : 12)), t, stepS * 0.8, 'square', 0.12);
    // 드럼: 킥 1·3박, 스네어 2·4박, 하이햇 (용암이면 16분음표마다)
    if (s % 8 === 0) this.kick(t);
    if (s % 8 === 4) this.hiss(t, 0.12, 1800, 0.35);
    if (lava || s % 2 === 0) this.hiss(t, 0.03, 7000, 0.12);
  }

  note(freq, t, dur, type, vol) {
    const ctx = this.sound.ctx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.gain);
    o.start(t);
    o.stop(t + dur + 0.02);
    this.notes++;
  }

  kick(t) {
    const ctx = this.sound.ctx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.frequency.setValueAtTime(130, t);
    o.frequency.exponentialRampToValueAtTime(40, t + 0.12);
    g.gain.setValueAtTime(0.8, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    o.connect(g).connect(this.gain);
    o.start(t);
    o.stop(t + 0.17);
    this.notes++;
  }

  hiss(t, dur, freq, vol) {
    const ctx = this.sound.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.sound.noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = 'highpass';
    f.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.gain);
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.02);
    this.notes++;
  }
}
