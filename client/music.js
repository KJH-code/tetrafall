// 배경음악: 파일 없이 WebAudio 로 합성한 반복곡. 효과음과 같은 AudioContext 를 쓴다 (첫 클릭 뒤부터 남).
// 곡 = 맵 테마별 (config MUSIC_THEMES: 음계·화음 진행·빠르기·악기·장단) + 대기실. 위험이 차오르면 같은 곡의 긴장 버전 (MUSIC_TENSION).
// 분위기 'calm'(대기·판 종료) → 대기실 곡, 'battle'(판 중) → 맵 테마 곡, 'lava'(위험이 차오르는 중) → 맵 테마 긴장 버전.
// 16분음표 한 칸씩 조금 앞서 예약해서(lookahead) 프레임이 끊겨도 박자가 안 밀린다.
import { CONFIG as C } from '../shared/config.js'; // (상대 경로: 테스트가 node 에서도 불러옴)
import { lobbyTheme } from '../shared/title.js';

const STEPS = 16; // 한 마디 16칸
const AHEAD_S = 0.2; // 이만큼 앞까지 예약
const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

// 쓸 수 있는 악기·장단·화음 쪼개기 이름 (config MUSIC_THEMES 가 이 안에서만 고르는지 테스트)
export const INSTRUMENTS = ['bell', 'pluck', 'reed', 'saw', 'marimba', 'lute', 'pad', 'triangle', 'sine', 'square', 'sawtooth'];
export const DRUMS = ['none', 'pop', 'tamb', 'sparse', 'heavy', 'wood', 'march'];
export const ARPS = ['pad', 'up', 'down', 'updown', 'bounce'];

// 테마 + 긴장 여부 → 실제로 쓸 곡 설정
export function songFor(themeId, tense) {
  const base = C.MUSIC_THEMES[themeId] || C.MUSIC_THEMES[C.MUSIC_THEME_DEFAULT];
  if (!tense) return base;
  const T = C.MUSIC_TENSION;
  // 단조로: 장3도(4)·장6도(9)·장7도(11) 를 반음 내림
  const scale = T.minor ? base.scale.map((v) => (v === 4 || v === 9 || v === 11 ? v - 1 : v)) : base.scale;
  return { ...base, bpm: base.bpm * T.bpm, scale, drums: T.drums, leadUp: T.leadUp, tense: true };
}

// 음계 몇 번째 음 → MIDI (음계 길이를 넘으면 옥타브 위)
export function degreeNote(song, deg) {
  const n = song.scale.length;
  const oct = Math.floor(deg / n);
  return song.root + song.scale[((deg % n) + n) % n] + 12 * oct;
}

// 화음: 진행의 deg 위에 음계를 하나 건너 세 음 (3화음)
export function chordAt(song, bar) {
  const deg = song.prog[bar % song.prog.length];
  return [0, 2, 4].map((k) => degreeNote(song, deg + k));
}

// 테마마다 같은 멜로디가 나오게 (테마 이름으로 씨앗)
function seeded(str) {
  let s = 0;
  for (const ch of str) s = (s * 31 + ch.charCodeAt(0)) >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

export class Music {
  constructor(sound) {
    this.sound = sound;
    this.on = true;
    this.volume = 1;
    this.mood = 'calm';
    this.theme = null; // 지금 맵 테마 id (없으면 MUSIC_THEME_DEFAULT)
    this.step = 0;
    this.nextAt = 0;
    this.gain = null;
    this.timer = null;
    this.notes = 0; // 예약한 음 수 (헤드리스 확인용)
    this.motifs = new Map(); // 곡 이름 → 마디별 멜로디 (음계 칸 또는 null)
    this.ambient = null; // 앰비언트 (title-sound.js TitleSound): 타이틀·메뉴·대기실은 곡 대신 테마 앰비언트
    this.makeAmbient = null; // (테마 id) => TitleSound — main.js 가 넣음 (없으면 앰비언트 없이 예전 곡)
  }

  // 그 테마 앰비언트 (이미 같은 테마면 그대로, 다르면 바꿈). 타이틀이 착지·반짝 소리도 여기에 냄
  ambientFor(theme) {
    if (this.ambient && this.ambient.theme === theme) return this.ambient;
    this.ambient?.stop();
    this.ambient = theme && this.makeAmbient ? this.makeAmbient(theme) : null;
    return this.ambient;
  }

  // 지금 앰비언트를 틀 테마: 메뉴 (state 없음) = 메뉴 테마, 대기실 (판 전, 연습 아님) = 방 맵 테마, 그 밖 (판·결과) = 없음 (곡)
  static ambientTheme(state, menuTheme) {
    if (!state) return menuTheme || null;
    return lobbyTheme(state);
  }

  // 설정의 음악 크기 (0~1, MUSIC_VOLUME 에 곱함). 0 이면 꺼서 예약도 안 함
  setVolume(v) {
    this.volume = v;
    this.on = v > 0;
    if (this.gain) this.gain.gain.setTargetAtTime(C.MUSIC_VOLUME * v, this.sound.ctx.currentTime, 0.15);
  }

  // 잠깐 줄임 (KO 마지막 킬 슬로모션): seconds 동안 MUSIC_VOLUME × musicDuck, 그 뒤 천천히 원래대로
  duck(seconds, level = C.SFX_KO.musicDuck, at = null) {
    if (!this.gain || !this.ctx) return;
    const t = at ?? this.ctx.currentTime; // at: 녹음 확인용 시각
    const full = C.MUSIC_VOLUME * this.volume;
    const g = this.gain.gain;
    g.cancelScheduledValues(t);
    g.setTargetAtTime(full * level, t, 0.05);
    g.setTargetAtTime(full, t + seconds, 0.35);
  }

  setMood(mood) {
    this.mood = mood;
  }

  // 지금 곡 이름: 대기실 / 맵 테마 (+ 긴장)
  songKey() {
    if (this.mood === 'calm') return 'lobby';
    return this.theme && C.MUSIC_THEMES[this.theme] ? this.theme : C.MUSIC_THEME_DEFAULT;
  }

  song() {
    return songFor(this.songKey(), this.mood === 'lava');
  }

  // 매 프레임 불러도 됨: 오디오가 깨어나면 한 번만 준비하고 예약 타이머를 돌린다. state 로 맵 테마를 고름.
  // menuTheme: 메뉴 배경 테마 (renderer.backdropTheme) — 메뉴·대기실은 곡 대신 테마 앰비언트 (판 시작하면 곡)
  update(state, menuTheme = null) {
    if (state && state.map) this.theme = C.WORLD_MAP_THEME?.[state.map.id] || null;
    if (this.makeAmbient) {
      const want = Music.ambientTheme(state, menuTheme);
      if (want) this.ambientFor(want);
      else if (this.ambient) {
        this.ambient.stop();
        this.ambient = null;
      }
      this.ambient?.update();
    }
    if (this.timer || !this.sound.ready()) return;
    this.build(this.sound.ctx, this.sound.ctx.destination);
    this.nextAt = this.sound.ctx.currentTime + 0.1;
    this.timer = setInterval(() => this.schedule(), 50);
  }

  // 음악 출구 (크기 + 테마별 메아리)
  build(ctx, dest) {
    this.ctx = ctx;
    this.gain = ctx.createGain();
    this.gain.gain.value = C.MUSIC_VOLUME * this.volume;
    this.gain.connect(dest);
    // 메아리: 곡마다 echo 만큼 보냄 (수정 동굴·하늘 성)
    this.echoSend = ctx.createGain();
    this.echoSend.gain.value = 0;
    const delay = ctx.createDelay(1);
    delay.delayTime.value = 0.33;
    const fb = ctx.createGain();
    fb.gain.value = 0.38;
    this.echoSend.connect(delay).connect(fb).connect(delay);
    delay.connect(this.gain);
    this.dry = ctx.createGain();
    this.dry.connect(this.gain);
    this.dry.connect(this.echoSend);
    this.drumBus = ctx.createGain(); // 북은 따로 작게 (MUSIC_MIX)
    this.drumBus.gain.value = C.MUSIC_MIX.drums;
    this.drumBus.connect(this.gain);
  }

  schedule() {
    const ctx = this.ctx;
    if (!this.on || this.ambient) {
      this.nextAt = ctx.currentTime + 0.1; // 꺼져 있거나 앰비언트 동안은 예약 안 함 (켜면 바로 이어서)
      return;
    }
    if (this.nextAt < ctx.currentTime) this.nextAt = ctx.currentTime + 0.05; // 탭이 멈췄다 돌아온 경우
    while (this.nextAt < ctx.currentTime + AHEAD_S) this.advance();
  }

  // 한 칸 예약하고 다음 칸으로
  advance() {
    const song = this.song();
    this.playStep(this.step, this.nextAt, song, this.songKey());
    this.nextAt += 60 / song.bpm / 4;
    this.step = (this.step + 1) % (STEPS * 16);
  }

  // 녹음 확인용: 다른 문맥(OfflineAudioContext)에 seconds 만큼 미리 다 예약
  renderTo(ctx, dest, seconds) {
    this.build(ctx, dest);
    this.nextAt = 0.05;
    this.step = 0;
    while (this.nextAt < seconds) this.advance();
  }

  // 곡의 마디별 멜로디 (테마 이름 씨앗으로 한 번 만들고 반복): 16마디, 마디마다 16칸 중 음계 칸 또는 null
  motif(key, song) {
    const id = `${key}${song.tense ? '!' : ''}`;
    if (this.motifs.has(id)) return this.motifs.get(id);
    const r = seeded(key);
    const bars = [];
    let deg = 7;
    // 앞 8마디를 만들고 뒤 8마디는 앞을 되풀이하되 끝만 바꿈 (외우기 쉽게)
    for (let b = 0; b < 8; b++) {
      const cells = new Array(STEPS).fill(null);
      if (r() < song.motif) {
        for (let s = 0; s < STEPS; s += r() < 0.35 ? 4 : 2) {
          if (r() < 0.25) continue; // 쉼
          deg = Math.max(4, Math.min(12, deg + Math.round((r() - 0.5) * 4)));
          cells[s] = deg;
        }
      }
      bars.push(cells);
    }
    for (let b = 0; b < 8; b++) bars.push(b === 7 ? bars[3].map((d) => (d === null ? null : d - 2)) : bars[b]);
    this.motifs.set(id, bars);
    return bars;
  }

  playStep(i, t, song, key) {
    const s = i % STEPS;
    const bar = Math.floor(i / STEPS);
    const chord = chordAt(song, bar);
    const stepS = 60 / song.bpm / 4;
    this.echoSend.gain.value = song.echo || 0;
    // 화음 쪼개기 (arp)
    const up = song.leadUp || 0;
    const A = song.arp;
    if (A === 'pad') {
      if (s === 0) for (const m of chord) this.inst('pad', midiHz(m + up), t, stepS * 15, 0.11);
    } else if (A === 'up' || A === 'down' || A === 'updown' || A === 'bounce') {
      const seq = A === 'up' ? [0, 1, 2, 1] : A === 'down' ? [2, 1, 0, 1] : A === 'updown' ? [0, 1, 2, 1, 2, 1] : [0, 2, 1, 2];
      const every = A === 'bounce' || song.tense ? 1 : 2;
      if (s % every === 0) this.inst(song.lead, midiHz(chord[seq[(s / every) % seq.length]] + 12 + up), t, stepS * 1.6, 0.07 * C.MUSIC_MIX.lead);
    }
    // 멜로디 (motif)
    const m = this.motif(key, song)[bar % 16][s];
    if (m !== null) this.inst(song.lead, midiHz(degreeNote(song, m) + up), t, stepS * 2.4, 0.13 * C.MUSIC_MIX.lead);
    // 베이스: 마디 첫 박 + 반 마디 (긴장하면 8분음표)
    const bassEvery = song.tense ? 2 : song.drums === 'none' ? 8 : 4;
    if (s % bassEvery === 0) this.inst(song.bass, midiHz(chord[0] - 12), t, stepS * (bassEvery - 0.3), (song.drums === 'none' ? 0.35 : 0.45) * C.MUSIC_MIX.bass);
    this.drums(song.drums, s, t);
  }

  // 장단
  drums(kit, s, t) {
    switch (kit) {
      case 'pop': // 초원·하늘: 킥 1·3, 스네어 2·4, 8분 하이햇
        if (s % 8 === 0) this.kick(t, 0.7);
        if (s % 8 === 4) this.hiss(t, 0.1, 1800, 0.3);
        if (s % 2 === 0) this.hiss(t, 0.03, 7000, 0.1);
        break;
      case 'tamb': // 사막: 쿵(1) 따(3.5) + 16분 탬버린 (센박 크게)
        if (s === 0 || s === 10) this.tom(t, 110, 0.5);
        if (s === 6 || s === 14) this.tom(t, 220, 0.35);
        this.hiss(t, 0.05, 6000, s % 4 === 0 ? 0.16 : 0.07);
        break;
      case 'sparse': // 수정 동굴: 마디에 킥 하나 + 가끔 높은 똑
        if (s === 0) this.kick(t, 0.45);
        if (s === 11) this.wood(t, 1800, 0.12);
        break;
      case 'heavy': // 화산·긴장: 8분 킥, 2·4 큰 스네어, 16분 하이햇
        if (s % 2 === 0) this.kick(t, s % 4 === 0 ? 0.9 : 0.55);
        if (s % 8 === 4) this.hiss(t, 0.16, 1400, 0.45);
        this.hiss(t, 0.025, 8000, 0.09);
        break;
      case 'wood': // 버섯 숲: 나무 블록 통통 + 가벼운 킥
        if (s % 8 === 0) this.kick(t, 0.5);
        if (s % 4 === 2) this.wood(t, 1200, 0.18);
        if (s % 8 === 7) this.wood(t, 1600, 0.12);
        break;
      case 'march': // 중세 성: 행진 북 (따다닥 따) + 큰북
        if (s % 8 === 0) this.tom(t, 80, 0.6);
        if (s % 4 === 2 || s === 13 || s === 15) this.hiss(t, 0.07, 2200, s % 4 === 2 ? 0.28 : 0.14);
        break;
      default: // none: 대기실
    }
  }

  // 악기 (lead·bass): 오실레이터 + 엔벌로프 (+ 배음·필터)
  inst(name, freq, t, dur, vol) {
    const ctx = this.ctx;
    const env = (g, a, d, v) => {
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(v, t + a);
      g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    };
    const osc = (type, f, v, d, a = 0.01, filterHz = 0) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f, t);
      env(g, a, d, v);
      if (filterHz) {
        const fl = ctx.createBiquadFilter();
        fl.type = 'lowpass';
        fl.frequency.setValueAtTime(filterHz, t);
        fl.frequency.exponentialRampToValueAtTime(Math.max(200, filterHz / 4), t + d);
        o.connect(fl).connect(g);
      } else o.connect(g);
      g.connect(this.dry);
      o.start(t);
      o.stop(t + d + 0.03);
      this.notes++;
    };
    switch (name) {
      case 'bell': // 사인 + 어긋난 배음 (종)
        osc('sine', freq, vol, dur * 1.6);
        osc('sine', freq * 2.76, vol * 0.35, dur * 0.7);
        break;
      case 'pluck': // 짧게 튕김 (세모파 + 밝은 필터)
        osc('triangle', freq, vol * 1.2, Math.min(dur, 0.35));
        osc('square', freq, vol * 0.25, Math.min(dur, 0.12), 0.005, 3000);
        break;
      case 'reed': // 피리 같은 (사각파를 거르고 느리게 열림)
        osc('square', freq, vol * 0.6, dur, 0.04, 1800);
        break;
      case 'saw': // 거친 톱니 (화산)
        osc('sawtooth', freq, vol * 0.7, dur, 0.01, 2400);
        break;
      case 'marimba': // 나무 건반: 사인 + 4배 배음 짧게
        osc('sine', freq, vol * 1.3, Math.min(dur, 0.3), 0.003);
        osc('sine', freq * 4, vol * 0.25, 0.05, 0.002);
        break;
      case 'lute': // 류트: 세모파 + 톱니 조금, 빨리 사그라짐
        osc('triangle', freq, vol, Math.min(dur, 0.45), 0.004);
        osc('sawtooth', freq, vol * 0.2, Math.min(dur, 0.25), 0.004, 2600);
        break;
      case 'pad': // 느리게 차오르는 화음
        osc('triangle', freq, vol, dur, dur * 0.25);
        osc('sine', freq * 1.005, vol * 0.6, dur, dur * 0.3);
        break;
      case 'triangle':
      case 'sine':
      case 'square':
      case 'sawtooth':
        osc(name, freq, vol, dur);
        break;
      default:
        osc('triangle', freq, vol, dur);
    }
  }

  kick(t, vol = 0.8) {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.frequency.setValueAtTime(130, t);
    o.frequency.exponentialRampToValueAtTime(40, t + 0.12);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    o.connect(g).connect(this.drumBus);
    o.start(t);
    o.stop(t + 0.17);
    this.notes++;
  }

  // 손북·큰북 (높이 있는 쿵)
  tom(t, freq, vol) {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(freq * 0.55, t + 0.2);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.25);
    o.connect(g).connect(this.drumBus);
    o.start(t);
    o.stop(t + 0.27);
    this.notes++;
  }

  // 나무 블록 똑
  wood(t, freq, vol) {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = 'triangle';
    o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);
    o.connect(g).connect(this.drumBus);
    o.start(t);
    o.stop(t + 0.08);
    this.notes++;
  }

  hiss(t, dur, freq, vol) {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.sound.noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = 'highpass';
    f.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.drumBus);
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.02);
    this.notes++;
  }
}
