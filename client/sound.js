// 효과음: 몸에 닿는 소리는 Kenney CC0 파일 (client/assets/sfx, config SFX_BANKS), UI·특수음·이어지는 소리는 WebAudio 합성.
// 브라우저 정책상 첫 클릭(Pointer Lock) 뒤에야 소리가 난다.
// 남 소리는 내 귀(카메라) 기준 거리로 작아지고 방향으로 왼쪽·오른쪽에 놓인다 (play 의 pos).
// 위험 액체(용암·물·늪·에너지·폭풍)는 표면까지 거리에 따라 커지는 지속음 (update → hazard).
import { CONFIG as C } from '/shared/config.js';

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

export class Sound {
  constructor() {
    this.ctx = null;
    this.volume = 1; // 설정의 효과음 크기 (0~1, SFX_VOLUME 에 곱함)
    this.buffers = new Map(); // 파일 이름 → 디코드한 소리
    this.listener = null; // { x, y, z, yaw } 내 귀 (카메라)
    this.when = null; // 녹음용: 이 시각에 소리를 놓음 (없으면 지금)
    this.hz = null; // 위험 액체 지속음 { style, nodes, gain, out }
    this.hazardStyle = C.SFX_HAZARD.fallback;
    this.hazardHooked = false; // 렌더러의 차오름 훅을 받으면 내 감지는 안 씀
    this.lastRiseAt = -Infinity;
    this.lavaWas = false;
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = C.SFX_VOLUME * v;
    if (this.direct) this.direct.gain.value = C.SFX_VOLUME * v;
  }

  // 사용자 입력 이벤트 안에서 한 번 불러 오디오를 깨운다
  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.attach(new AC());
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
  }

  // 오디오 문맥에 붙임 (녹음 확인은 OfflineAudioContext 를 넣음). 파일은 뒤에서 받아 디코드
  attach(ctx, dest = ctx.destination) {
    this.ctx = ctx;
    this.master = ctx.createGain();
    this.master.gain.value = C.SFX_VOLUME * this.volume;
    // 슬로모션 필터·크기 (slowmo): 평소엔 다 통과
    this.slowFilter = ctx.createBiquadFilter();
    this.slowFilter.type = 'lowpass';
    this.slowFilter.frequency.value = 20000;
    this.slowGain = ctx.createGain();
    this.master.connect(this.slowFilter).connect(this.slowGain).connect(dest);
    this.slowRate = 1;
    this.direct = ctx.createGain(); // 슬로모션 필터를 안 거치는 출구 (마지막 킬 소리 자체)
    this.direct.gain.value = C.SFX_VOLUME * this.volume;
    this.direct.connect(dest);
    const len = ctx.sampleRate;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    // 갈색 잡음 (낮게 웅웅, 위험 액체 바탕). 2초, 끝과 처음이 이어지게 반복
    this.brownBuf = ctx.createBuffer(1, len * 2, ctx.sampleRate);
    const b = this.brownBuf.getChannelData(0);
    let last = 0;
    for (let i = 0; i < b.length; i++) {
      last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
      b[i] = last * 3.5;
    }
    this.loaded = this.load();
    return this.loaded;
  }

  // 효과음 파일 다 받기 (실패한 파일은 건너뜀 → 그 소리만 합성으로)
  load() {
    const names = new Set(Object.values(C.SFX_BANKS).flatMap((b) => b.files));
    return Promise.all(
      [...names].map((n) =>
        fetch(`${C.SFX_DIR}${n}.ogg`)
          .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(r.status))))
          .then((a) => this.ctx.decodeAudioData(a))
          .then((buf) => this.buffers.set(n, buf))
          .catch(() => {}),
      ),
    );
  }

  ready() {
    return !!this.ctx && (this.ctx.state === 'running' || this.when !== null);
  }

  now() {
    return this.when ?? this.ctx.currentTime;
  }

  // 내 귀: 카메라 행렬 (matrixWorld.elements, 열 우선) → 위치와 바라보는 방향
  setListener(m) {
    if (!m) return;
    this.listener = { x: m[12], y: m[13], z: m[14], yaw: Math.atan2(-m[9], -m[8]) };
  }

  // 소리 하나의 출구: 거리로 작아지고 (falloff) 방향으로 왼쪽·오른쪽 (pos 가 있고 내 소리가 아니면)
  bus(dist, pos, out = this.master) {
    let d = dist;
    let pan = 0;
    const L = this.listener;
    if (pos && L && dist !== 0) {
      const dx = pos.x - L.x;
      const dy = pos.y - L.y;
      d = Math.hypot(dx, dy, (pos.z ?? L.z) - L.z);
      const len = Math.hypot(dx, dy);
      // 오른쪽 = 바라보는 방향을 시계 방향으로 90도 (z 위 오른손 좌표)
      if (len > 0.3) pan = ((dx * Math.sin(L.yaw) - dy * Math.cos(L.yaw)) / len) * C.SFX_PAN;
    }
    const g = this.ctx.createGain();
    g.gain.value = Sound.falloff(d);
    if (pan && this.ctx.createStereoPanner) {
      const p = this.ctx.createStereoPanner();
      p.pan.value = Math.max(-1, Math.min(1, pan));
      g.connect(p).connect(out);
    } else g.connect(out);
    return g;
  }

  // 주파수가 미끄러지는 단순 음
  tone({ freq, freqEnd = freq, dur, type = 'sine', vol = 0.5, delay = 0, out = this.master }) {
    const t = this.now() + delay;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    const det = this.det || 1; // 같은 소리도 높낮이 조금씩 다르게 (play 마다)
    o.frequency.setValueAtTime(freq * det, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(20, freqEnd * det), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  // 걸러낸 잡음 (타격·바람·부서짐)
  noise({ dur, vol = 0.5, filter = 'lowpass', freq = 1000, freqEnd = freq, q = 1, delay = 0, out = this.master }) {
    const t = this.now() + delay;
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
    src.connect(f).connect(g).connect(out);
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.02);
  }

  // 효과음 묶음에서 하나를 골라 틈 (파일이 없으면 false → 부른 쪽이 합성으로 대신)
  // cut = 이 길이(초)에서 끊음 (뒤 40% 동안 빠르게 줄여 딸깍 없이). 꼬리를 짧게 해 통통 가볍게
  sample(bank, { vol = 1, rate = 1, delay = 0, out = this.master, cut = 0 } = {}) {
    const b = C.SFX_BANKS[bank];
    if (!b) return false;
    const have = b.files.filter((f) => this.buffers.has(f));
    if (!have.length) return false;
    const src = this.ctx.createBufferSource();
    src.buffer = this.buffers.get(have[Math.floor(Math.random() * have.length)]);
    src.playbackRate.value = rate * (this.det || 1);
    const g = this.ctx.createGain();
    const t = this.now() + delay;
    g.gain.value = vol * b.gain;
    if (cut > 0) {
      g.gain.setValueAtTime(vol * b.gain, t + cut * 0.6);
      g.gain.linearRampToValueAtTime(0, t + cut);
    }
    src.connect(g).connect(out);
    src.start(t);
    if (cut > 0) src.stop(t + cut + 0.01);
    return true;
  }

  // 약·중타·휘두름 소리 후보 (config SFX_HIT_STYLE, hitStyle 로 덮어씀: 비교 녹음용). 'A' 면 null (예전 그대로)
  style() {
    return C.SFX_HIT_STYLES[this.hitStyle || C.SFX_HIT_STYLE] || null;
  }

  // 후보 겹 하나: 효과음 묶음 또는 합성 잡음·음
  layer(L, out) {
    if (L.bank) this.sample(L.bank, { vol: L.vol, rate: L.rate, cut: L.cut, delay: L.delay, out });
    else if (L.noise) this.noise({ ...L.noise, out });
    else if (L.tone) this.tone({ ...L.tone, out });
  }

  // 합성 기타 (바드 타격): 화음을 빠르게 긁음. metal 이면 낮고 찌그러진 파워 코드
  strum(out, vol, metal = false) {
    const t0 = this.now();
    const shaper = metal ? this.ctx.createWaveShaper() : null;
    if (shaper) {
      const n = 256;
      const curve = new Float32Array(n);
      for (let i = 0; i < n; i++) curve[i] = Math.tanh(((i / (n - 1)) * 2 - 1) * 6);
      shaper.curve = curve;
      shaper.connect(out);
    }
    C.SFX_STRUM.forEach((m, i) => {
      const t = t0 + i * 0.018;
      const o = this.ctx.createOscillator();
      const f = this.ctx.createBiquadFilter();
      const g = this.ctx.createGain();
      o.type = 'sawtooth';
      o.frequency.value = midiHz(m - (metal ? 12 : 0)) * (this.det || 1);
      f.type = 'lowpass';
      f.frequency.setValueAtTime(3200, t);
      f.frequency.exponentialRampToValueAtTime(500, t + 0.5);
      g.gain.setValueAtTime(vol * (metal ? 0.18 : 0.22), t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.6);
      o.connect(f).connect(g).connect(shaper || out);
      o.start(t);
      o.stop(t + 0.62);
    });
  }

  // 거리(칸)에 따라 작아지는 크기
  static falloff(dist) {
    if (dist === undefined) return 1;
    return Math.max(0.2, 1 - dist / C.SFX_HEAR_RANGE);
  }

  // name: 이벤트 소리. dist = 내 몸에서 거리 (0 = 내 소리), pos = 소리 난 곳 (있으면 내 귀 기준 거리·방향),
  // char = 그 소리를 낸 캐릭터 (무기 소리), strong = 내가 때림, form = 바드 폼, tier = 타격 세기 단계 (light·medium·heavy·crit, hitTier)
  play(name, { dist, pos, strong = false, char, form, tier } = {}) {
    if (!this.ready()) return;
    this.det = (1 + (Math.random() * 2 - 1) * C.SFX_DETUNE) * this.slowRate;
    const o = this.bus(dist, pos, name === 'final' ? this.direct : this.master); // 마지막 킬 소리는 자기 슬로모션에 안 먹먹해지게
    const w = (char && C.SFX_WEAPONS[char]) || null;
    switch (name) {
      case 'tear': // 갈고리 R 블록 뜯김: 찌익 (높아지는 거친 소리) + 나무 뚝
        this.noise({ dur: 0.32, vol: 0.55, filter: 'bandpass', freq: 350, freqEnd: 2600, q: 2.5, out: o });
        if (!this.sample('woodL', { rate: 0.7, delay: 0.22, out: o })) this.tone({ freq: 140, freqEnd: 60, dur: 0.2, type: 'sawtooth', vol: 0.25, delay: 0.22, out: o });
        break;
      case 'shatter': // 블록 부숨: 돌 깨짐 + 높은 와장창 + 낮은 쾅
        if (!this.sample('mining', { out: o })) this.noise({ dur: 0.35, vol: 0.7, filter: 'highpass', freq: 2500, freqEnd: 900, out: o });
        this.sample('glassH', { rate: 0.8, out: o });
        this.tone({ freq: 110, freqEnd: 40, dur: 0.25, type: 'sine', vol: 0.4, out: o });
        break;
      case 'tap': // 닌자가 떨어지는 블록에 닿음: 작은 탁
        if (!this.sample('tapL', { rate: 1.3, out: o })) this.tone({ freq: 1400, freqEnd: 800, dur: 0.05, type: 'triangle', vol: 0.3, out: o });
        break;
      case 'swing': { // 휘두름: 짧고 날카로운 '휙' (무기 크기별 묶음·높낮이) + 보통·무거운 무기는 바람 가르는 고역 한 겹
        const sw = w || { swing: 'swishMid', rate: 1 };
        const st = this.style();
        if (st) { // 후보 B·C·D: 휘두름 높낮이·길이 + 합성 바람
          const S = st.swing;
          this.sample(sw.swing, { rate: sw.rate * S.rate, cut: S.cut, vol: S.vol, out: o });
          if (S.air) this.noise({ ...S.air, out: o });
          break;
        }
        const S = C.SFX_SWING;
        const rate = sw.rate * S.rate;
        this.sample(sw.swing, { rate, cut: S.cut, out: o });
        if (sw.swing !== 'swishBlade') this.sample('swishBlade', { rate: rate * 0.7, vol: C.SFX_SWING_AIR, cut: S.cut, out: o });
        break;
      }
      case 'hit': { // 맞음 (스매시식): 고역 크랙 '팍' + 짧은 펀치 '퍽' (+ 강타 몸통) → 무기 겹은 얇게 → 강타·치명타는 히트스톱이 풀릴 때 '콰앙'
        const T = C.SFX_HIT_TIERS[tier] || C.SFX_HIT_TIERS[strong ? 'medium' : 'light'];
        const r = T.rate;
        const cut = T.cut || 0; // 약·중타: 꼬리를 짧게 (통통 가볍게)
        const st = this.style();
        const lm = st && !T.release && (st[tier] || st[strong ? 'medium' : 'light']);
        if (lm) { // 후보 B·C·D 의 약·중타: 그 후보의 겹 + 얇은 무기 겹 (강타·치명은 아래 공통)
          for (const L of lm) this.layer(L, o);
          if (w && w.hit === 'strum') this.strum(o, 0.6, form === 'metal');
          else if (w) this.sample(w.hit, { vol: C.SFX_WEAPON_LAYER, rate: st.weaponRate, cut: cut && cut * 1.5, out: o });
          break;
        }
        if (T.crack) this.sample('hitCrack', { vol: T.crack, rate: r, cut, out: o });
        if (T.punch) this.sample('hitPunch', { vol: T.punch, rate: r * (T.punchRate || 1), cut, out: o });
        if (T.heavy) this.sample('hitHeavy', { vol: T.heavy, rate: r, out: o });
        if (T.ring) this.sample('hitRing', { vol: T.ring, out: o });
        if (w && w.hit === 'strum') this.strum(o, 0.6, form === 'metal');
        else if (w) this.sample(w.hit, { vol: C.SFX_WEAPON_LAYER, rate: T.weaponRate || 1, cut: cut && cut * 1.5, out: o });
        if (T.release) {
          // 날아감: 낮은 쾅 + 멀어지는 바람 (히트스톱 길이만큼 늦게)
          const d = T.release / 1000;
          this.sample('hitHeavy', { rate: 0.7, vol: C.SFX_HIT_RELEASE, delay: d, out: o });
          this.noise({ dur: 0.35, vol: C.SFX_HIT_RELEASE * 0.5, filter: 'bandpass', freq: 1800, freqEnd: 350, q: 1, delay: d, out: o });
          if (tier === 'crit') this.sample('boomLow', { rate: 1.3, vol: C.SFX_HIT_RELEASE, delay: d, out: o });
        }
        break;
      }
      case 'crit': // 치명타 표시음: 종 딩 (타격 자체는 hit 의 crit 단계)
        if (!this.sample('bell', { rate: 1.4, out: o })) this.tone({ freq: 2200, freqEnd: 1600, dur: 0.18, type: 'triangle', vol: 0.3, out: o });
        break;
      case 'hurt': // 내가 맞음: 크랙 뒤에 몸에 울리는 짧은 저음 (크랙을 덮지 않게 조금 늦게·짧게)
        this.tone({ freq: 120, freqEnd: 50, dur: 0.15, type: 'sine', vol: 0.35, delay: 0.012, out: o });
        break;
      case 'fire': // 쏨: 사냥꾼은 석궁 줄 팅, 나머지는 합성 탕
        if (w && w.shot && this.sample(w.shot, { rate: 0.9, out: o })) {
          this.noise({ dur: 0.18, vol: 0.18, filter: 'bandpass', freq: 2200, freqEnd: 700, q: 1.2, out: o });
          break;
        }
        this.tone({ freq: 600, freqEnd: 1500, dur: 0.12, type: 'square', vol: 0.18, out: o });
        this.noise({ dur: 0.1, vol: 0.2, filter: 'highpass', freq: 2000, out: o });
        break;
      case 'danger': // 압사 경고: 높은 삑삑
        this.tone({ freq: 1250, dur: 0.07, type: 'square', vol: 0.22, out: o });
        this.tone({ freq: 1250, dur: 0.07, type: 'square', vol: 0.22, delay: 0.11, out: o });
        break;
      case 'airJump': // 2단 점프: 옷 펄럭 + 휙
        this.sample('cloth', { rate: 1.35, vol: 0.6, out: o });
        this.noise({ dur: 0.12, vol: 0.18, filter: 'bandpass', freq: 900, freqEnd: 2400, q: 1.2, out: o });
        break;
      case 'land': // 블록 착지: 쿵 (나무 묵직 + 낮은 울림)
        this.sample('woodH', { rate: 0.7, out: o });
        this.tone({ freq: 95, freqEnd: 38, dur: 0.18, type: 'sine', vol: 0.45, out: o });
        break;
      case 'crush': // 압사: 몸이 깔림 + 큰 쿵
        this.sample('softH', { out: o });
        this.sample('woodH', { rate: 0.55, out: o });
        this.noise({ dur: 0.4, vol: 0.5, freq: 1800, freqEnd: 90, out: o });
        this.tone({ freq: 80, freqEnd: 28, dur: 0.4, type: 'sine', vol: 0.5, out: o });
        break;
      case 'fall': // 낙사: 휘익 떨어짐 (이어지는 소리라 합성)
        this.tone({ freq: 900, freqEnd: 140, dur: 0.75, type: 'sine', vol: 0.35, out: o });
        this.noise({ dur: 0.7, vol: 0.12, filter: 'bandpass', freq: 1800, freqEnd: 400, q: 0.8, out: o });
        break;
      case 'lavaDeath': // 위험 액체에 빠짐: 철퍽 + 지글 (액체 종류에 맞게)
        this.sample('slime', { rate: this.hazardStyle === 'lava' ? 0.8 : 1, out: o });
        if (this.hazardStyle === 'lava') this.noise({ dur: 0.6, vol: 0.5, filter: 'bandpass', freq: 1200, freqEnd: 300, q: 0.7, out: o });
        else if (this.hazardStyle === 'energy' || this.hazardStyle === 'storm') this.tone({ freq: 1600, freqEnd: 120, dur: 0.4, type: 'square', vol: 0.15, out: o });
        else this.noise({ dur: 0.45, vol: 0.35, freq: 900, freqEnd: 150, out: o });
        break;
      case 'sizzle': // 하늘 계단 블록이 위험 액체에 녹음: 치익
        this.noise({ dur: 0.5, vol: 0.4, filter: 'bandpass', freq: 3000, freqEnd: 900, q: 0.9, out: o });
        this.sample('slime', { rate: 1.3, vol: 0.5, out: o });
        break;
      case 'pickup':
        if (!this.sample('confirm', { out: o })) {
          this.tone({ freq: 660, dur: 0.09, type: 'triangle', vol: 0.35, out: o });
          this.tone({ freq: 990, dur: 0.14, type: 'triangle', vol: 0.35, delay: 0.08, out: o });
        }
        break;
      case 'latch': // 장전·갈고리 걸림: 철컥
        if (!this.sample('latch', { out: o })) this.tone({ freq: 1800, freqEnd: 900, dur: 0.05, type: 'square', vol: 0.15, out: o });
        break;
      case 'lava': // 위험 액체가 차오르기 시작: 액체 종류별 큰 소리
        this.rise(o);
        break;
      case 'boom': // 폭발: 와작 + 낮은 쿵
        if (!this.sample('boom', { out: o })) this.noise({ dur: 0.9, vol: 0.9, freq: 1400, freqEnd: 60, out: o });
        this.sample('boomLow', { vol: 0.7, out: o });
        this.tone({ freq: 70, freqEnd: 25, dur: 0.6, type: 'sine', vol: 0.6, out: o });
        break;
      case 'strum': // 바드 노래·폼: 기타 긁기
        this.strum(o, 1, form === 'metal');
        break;
      case 'smash': // KO 스매시 (낙사): 쾅 + 바깥으로 뻗는 폭발 꼬리 (+ 내 것·가까우면 높은 핑)
        this.sample('boom', { rate: 0.85, out: o });
        this.sample('boomLow', { out: o });
        this.noise({ dur: 0.9, vol: 0.45, filter: 'bandpass', freq: 2400, freqEnd: 260, q: 0.9, delay: 0.05, out: o });
        if (strong) this.tone({ freq: 1900, freqEnd: 1500, dur: 0.6, type: 'sine', vol: 0.18, delay: 0.04, out: o });
        break;
      case 'koCrush': // KO 압사: 묵직한 쾅 (히트스톱 순간) → 멈춤이 풀릴 때 부스러기
        this.sample('punchH', { rate: 0.55, out: o });
        this.sample('hitCrack', { rate: 0.8, out: o });
        this.sample('boomLow', { rate: 1.2, vol: 0.8, out: o });
        this.tone({ freq: 60, freqEnd: 24, dur: 0.5, type: 'sine', vol: strong ? 0.8 : 0.5, out: o });
        this.sample('mining', { rate: 0.8, delay: C.SFX_KO.crushTail, out: o });
        this.sample('softH', { rate: 0.8, delay: C.SFX_KO.crushTail, out: o });
        break;
      case 'final': { // 마지막 킬 슬로모션: 낮게 늘어진 쾅 + 깊은 종 + 차오르는 바람
        this.det = 1;
        this.sample('boom', { rate: 0.45, out: o });
        this.sample('bell', { rate: 0.5, vol: 1.2, delay: 0.05, out: o });
        this.tone({ freq: 55, freqEnd: 30, dur: 1.6, type: 'sine', vol: 0.6, out: o });
        // 바람이 차올랐다 확 사라짐 (슬로모션 끝에 맞춰)
        const t = this.now();
        const src = this.ctx.createBufferSource();
        src.buffer = this.noiseBuf;
        src.loop = true;
        const f = this.ctx.createBiquadFilter();
        f.type = 'bandpass';
        f.frequency.setValueAtTime(250, t);
        f.frequency.exponentialRampToValueAtTime(2500, t + 1.3);
        const g = this.ctx.createGain();
        g.gain.setValueAtTime(0.0001, t);
        g.gain.exponentialRampToValueAtTime(0.35, t + 1.3);
        g.gain.exponentialRampToValueAtTime(0.0001, t + 1.6);
        src.connect(f).connect(g).connect(o);
        src.start(t);
        src.stop(t + 1.65);
        break;
      }
      case 'glideRing': { // 음유 낙하 음파 고리: 류트 팅 (화음 두 음) + 퍼져 나가는 음파 (떨리며 내려가는 울림 + 바람)
        this.sample('pluck', { rate: 1.25, out: o });
        const [a, b] = C.SFX_STRUM.slice(-2);
        this.tone({ freq: midiHz(a + 12), dur: 0.35, type: 'triangle', vol: 0.18, out: o });
        this.tone({ freq: midiHz(b + 12), dur: 0.4, type: 'triangle', vol: 0.15, delay: 0.06, out: o });
        this.tone({ freq: 520, freqEnd: 180, dur: 0.6, type: 'sine', vol: 0.22, delay: 0.04, out: o });
        this.noise({ dur: 0.55, vol: 0.18, filter: 'bandpass', freq: 600, freqEnd: 2600, q: 1.4, delay: 0.04, out: o });
        if (strong) this.tone({ freq: 1600, freqEnd: 1200, dur: 0.15, type: 'sine', vol: 0.1, delay: 0.1, out: o }); // 누군가 맞음: 반짝
        break;
      }
      case 'tick': // 카운트다운 3·2·1
        this.tone({ freq: 660, dur: 0.12, type: 'square', vol: 0.22, out: o });
        break;
      case 'go': // 시작!
        this.tone({ freq: 990, dur: 0.35, type: 'square', vol: 0.25, out: o });
        this.tone({ freq: 1320, dur: 0.3, type: 'triangle', vol: 0.2, delay: 0.02, out: o });
        break;
      case 'win': // 판 끝, 승자 발표: 스틸드럼 징글
        this.det = 1;
        if (!this.sample('jingleWin', { out: o })) [392, 523, 659, 784, 1047].forEach((f, i) => this.tone({ freq: f, dur: 0.22, type: 'triangle', vol: 0.32, delay: i * 0.09, out: o }));
        break;
      case 'lose': // 내가 죽음: 내려가는 징글
        this.det = 1;
        this.sample('jingleLose', { out: o });
        break;
      case 'clear':
        [523, 659, 784, 1047].forEach((f, i) => this.tone({ freq: f, dur: 0.15, type: 'triangle', vol: 0.3, delay: i * 0.07, out: o }));
        break;
      default:
    }
  }

  // 화면 시간 배율 (KO 슬로모션, main.js 프레임마다): 슬로모션이면 효과음을 먹먹하고 낮게, 아니면 원래대로
  slowmo(scale) {
    if (!this.ready() || !this.slowFilter) return;
    const K = C.SFX_KO;
    const slow = scale < 1 && scale > K.slowAbove;
    if (slow === this.slowOn) return;
    this.slowOn = slow;
    this.slowRate = slow ? K.slowRate : 1;
    const t = this.now();
    this.slowFilter.frequency.setTargetAtTime(slow ? K.slowLowpass : 20000, t, K.ease);
    this.slowGain.gain.setTargetAtTime(slow ? K.slowGain : 1, t, K.ease);
  }

  // ---------- 위험 액체 ----------

  // 차오르기 시작한 순간 (서버 'lava' 이벤트 또는 렌더러 훅): 액체 종류별로 크게 한 번
  rise(o = this.master) {
    const at = this.now();
    if (at - this.lastRiseAt < 1) return; // 훅과 이벤트가 같이 와도 한 번만
    this.lastRiseAt = at;
    const s = this.hazardStyle;
    if (s === 'lava' || s === 'swamp') {
      this.noise({ dur: 1.6, vol: 0.55, freq: s === 'lava' ? 260 : 500, freqEnd: 120, out: o });
      this.sample('boomLow', { rate: 0.6, vol: 0.8, out: o });
      if (s === 'swamp') this.sample('slime', { rate: 0.6, out: o });
    } else if (s === 'water') {
      this.noise({ dur: 1.4, vol: 0.5, filter: 'bandpass', freq: 400, freqEnd: 1600, q: 0.6, out: o }); // 쏴아
      this.noise({ dur: 1.8, vol: 0.4, freq: 300, freqEnd: 120, delay: 0.3, out: o });
    } else if (s === 'energy') {
      this.tone({ freq: 55, freqEnd: 220, dur: 1.4, type: 'sawtooth', vol: 0.22, out: o }); // 웅 올라감
      this.tone({ freq: 880, freqEnd: 1760, dur: 1.2, type: 'sine', vol: 0.1, out: o });
    } else if (s === 'storm') this.thunder(o, 1);
    else this.noise({ dur: 1.6, vol: 0.6, freq: 260, freqEnd: 120, out: o });
  }

  // 렌더러의 차오름 훅 (B3 renderer.onHazardRise) 에서 부름. 오면 내 감지는 끔
  hazardRise(h = {}) {
    this.hazardHooked = true;
    if (h.style) this.hazardStyle = h.style;
    if (this.ready()) this.rise(this.bus(undefined, h.pos));
  }

  thunder(o, vol) {
    this.noise({ dur: 0.12, vol: 0.6 * vol, filter: 'highpass', freq: 2500, out: o }); // 콰직
    this.noise({ dur: 2.2, vol: 0.9 * vol, freq: 1600, freqEnd: 50, delay: 0.05, out: o }); // 우르르릉
    this.tone({ freq: 60, freqEnd: 30, dur: 1.6, type: 'sine', vol: 0.4 * vol, delay: 0.05, out: o });
  }

  // 액체 종류별 지속음 만들기 (갈색 잡음 바탕 + 종류별 색)
  buildHazard(style) {
    const ctx = this.ctx;
    const out = ctx.createGain();
    out.gain.value = 0;
    out.connect(this.master);
    const nodes = [];
    const t = this.now();
    const loop = (buf) => {
      const s = ctx.createBufferSource();
      s.buffer = buf;
      s.loop = true;
      s.start(t, Math.random());
      nodes.push(s);
      return s;
    };
    const lfo = (hz, depth, param) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.frequency.value = hz;
      g.gain.value = depth;
      o.connect(g).connect(param);
      o.start(t);
      nodes.push(o);
    };
    const filt = (type, freq, q = 0.7) => {
      const f = ctx.createBiquadFilter();
      f.type = type;
      f.frequency.value = freq;
      f.Q.value = q;
      return f;
    };
    if (style === 'energy') {
      // 웅웅: 낮은 톱니 둘 (살짝 어긋나 맥놀이) + 높은 떨림
      const f = filt('lowpass', 420, 4);
      for (const hz of [55, 55.6]) {
        const o = ctx.createOscillator();
        o.type = 'sawtooth';
        o.frequency.value = hz;
        o.connect(f);
        o.start(t);
        nodes.push(o);
      }
      lfo(0.4, 160, f.frequency);
      const g = ctx.createGain();
      g.gain.value = 0.5;
      f.connect(g).connect(out);
      const hi = ctx.createOscillator();
      const hg = ctx.createGain();
      hi.frequency.value = 880;
      hg.gain.value = 0.04;
      lfo(6, 0.03, hg.gain);
      hi.connect(hg).connect(out);
      hi.start(t);
      nodes.push(hi);
    } else {
      // 물 출렁 · 용암 끓음 · 늪 · 폭풍 바람: 갈색 잡음을 거르는 높이와 흔들림만 다름
      const base = { water: 650, lava: 240, swamp: 380, storm: 180 }[style] ?? 300;
      const f = filt('lowpass', base, style === 'water' ? 1.2 : 0.7);
      loop(this.brownBuf).connect(f);
      if (style === 'water') lfo(0.22, 380, f.frequency); // 철썩철썩
      if (style === 'storm') lfo(0.07, 90, f.frequency); // 바람이 밀려왔다 감
      f.connect(out);
    }
    return { style, nodes, out };
  }

  // 튀는 소리 하나 (뽀글·출렁·지직·천둥)
  hazardPop(style, o) {
    this.det = 1 + (Math.random() * 2 - 1) * 0.15;
    if (style === 'lava') this.tone({ freq: 70 + Math.random() * 60, freqEnd: 160, dur: 0.12, type: 'sine', vol: 0.5, out: o }); // 꿀렁
    else if (style === 'swamp') this.tone({ freq: 180 + Math.random() * 120, freqEnd: 650, dur: 0.07, type: 'sine', vol: 0.35, out: o }); // 뽀글
    else if (style === 'water') this.noise({ dur: 0.3, vol: 0.35, filter: 'bandpass', freq: 900, freqEnd: 500, q: 0.8, out: o }); // 찰싹
    else if (style === 'energy') this.tone({ freq: 1400, freqEnd: 180, dur: 0.1, type: 'square', vol: 0.12, out: o }); // 지직
    else if (style === 'storm') this.thunder(o, 0.6);
  }

  // 매 프레임 (그림 그린 뒤): 귀 위치·위험 액체 지속음·차오름 감지. cam = 카메라 matrixWorld.elements
  update(cam, state, dt) {
    this.setListener(cam);
    if (!this.ready() || !state) return;
    const theme = state.map && C.WORLD_MAP_THEME?.[state.map.id];
    this.hazardStyle = (theme && C.WORLD_THEMES?.[theme]?.hazard?.style) || C.SFX_HAZARD.fallback;
    const lava = state.lava;
    const live = state.phase === 'playing' && lava && lava.active;
    // 차오름 감지 (렌더러 훅이 없을 때만): 꺼져 있다 켜짐
    if (live && !this.lavaWas && !this.hazardHooked) this.rise();
    this.lavaWas = !!live;
    const ear = this.listener ? this.listener.z : 0;
    this.hazard({ style: this.hazardStyle, level: live ? 1 : 0, dist: live ? Math.max(0, ear - lava.z) : Infinity, dt });
  }

  // 위험 액체 지속음: style (WORLD_THEMES hazard.style), level 0~1, dist = 표면까지 높이 (칸). 매 프레임 불러도 됨
  hazard({ style, level = 1, dist = 0, dt = 0 }) {
    if (!this.ready()) return;
    const H = C.SFX_HAZARD;
    const near = Math.max(H.min, 1 - dist / H.range);
    const target = style ? (H.vol[style] ?? 0.3) * clamp01(level) * (Number.isFinite(dist) ? near : 0) : 0;
    if (this.hz && this.hz.style !== style) this.stopHazard();
    if (!this.hz && target > 0) this.hz = this.buildHazard(style);
    if (!this.hz) return;
    const now = this.now();
    this.hz.out.gain.setTargetAtTime(target, now, H.fade);
    this.hz.level = target;
    if (target > 0.001 && Math.random() < (H.pops[style] ?? 0) * dt) this.hazardPop(style, this.hz.out);
    if (target === 0) {
      this.hz.quietFor = (this.hz.quietFor || 0) + dt;
      if (this.hz.quietFor > H.fade * 6) this.stopHazard(); // 다 작아지면 노드 정리
    } else this.hz.quietFor = 0;
  }

  stopHazard() {
    const hz = this.hz;
    if (!hz) return;
    this.hz = null;
    const t = this.now();
    hz.out.gain.setTargetAtTime(0, t, 0.1);
    for (const n of hz.nodes) n.stop(t + 0.6);
    setTimeout(() => hz.out.disconnect(), 800);
  }
}
