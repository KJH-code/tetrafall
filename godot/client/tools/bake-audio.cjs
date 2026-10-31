// 소리 굽기 (G5): JS 화면의 합성 소리를 크로미움 OfflineAudioContext 로 그대로 녹음 → audio/baked/*.ogg + manifest.json.
// 고도는 녹음본만 틀어서 (실행 중 합성 없음) JS 와 같은 소리가 웹에서도 가볍게. 매번 다른 높낮이는 녹음본 여러 개 + 재생할 때 높낮이 흔들기.
// - 효과음 (client/sound.js play): 이름·무기·세기·폼별, 녹음본 VARIANTS 개
// - 위험 액체 지속음 (buildHazard) 5종 이어지는 고리 + 튀는 소리 (hazardPop)
// - 곡 (client/music.js): 대기실 + 맵 테마 7 × (보통·긴장), 16마디 한 바퀴 이어지는 고리
// - 앰비언트 (client/title-sound.js): 테마 7 웅웅 고리 + 띄엄띄엄 소리 (메뉴·대기실)
// 실행 (레포 뿌리, JS 서버가 client/ 를 서빙해야 함): PORT=3399 node server/index.js & node godot/client/tools/bake-audio.cjs [포트]
// ffmpeg (libvorbis) 필요. 다시 구우면 녹음본 무작위가 바뀜 (소리 모양은 같음)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const PORT = Number(process.argv[2] || 3399);
const OUT = path.join(__dirname, '../audio/baked');
const SR = 44100;
const VARIANTS = 3;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  for (const f of fs.readdirSync(OUT)) if (f.endsWith('.ogg')) fs.unlinkSync(path.join(OUT, f));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/bake-audio-origin`); // 404 쪽이어도 같은 출처면 모듈을 부를 수 있음
  // 페이지 안: 녹음 도우미
  await page.evaluate(async (SR) => {
    const { Sound } = await import('/sound.js');
    const { Music } = await import('/music.js');
    const { TitleSound } = await import('/title-sound.js');
    const { CONFIG: C } = await import('/shared/config.js');
    window.C = C;
    // 효과음 파일은 한 번만 받아 디코드 (AudioBuffer 는 문맥과 상관없이 씀)
    const cache = new Map();
    const tmp = new OfflineAudioContext(1, SR, SR);
    const names = new Set(Object.values(C.SFX_BANKS).flatMap((b) => b.files));
    await Promise.all([...names].map((n) => fetch(`${C.SFX_DIR}${n}.ogg`).then((r) => r.arrayBuffer()).then((a) => tmp.decodeAudioData(a)).then((b) => cache.set(n, b)).catch(() => {})));
    const fresh = (seconds) => {
      const ctx = new OfflineAudioContext(1, Math.ceil(SR * seconds), SR);
      const s = new Sound();
      s.load = () => { for (const [k, v] of cache) s.buffers.set(k, v); return Promise.resolve(); };
      s.attach(ctx);
      s.when = 0.01;
      return { ctx, s };
    };
    const pack = (buf, from = 0, to = buf.length) => {
      const d = buf.getChannelData(0).subarray(from, to);
      let peak = 0;
      for (const v of d) peak = Math.max(peak, Math.abs(v));
      return { data: Array.from(d), peak };
    };
    // 끝의 조용한 꼬리 자르기 (-70dB)
    const trim = (buf) => {
      const d = buf.getChannelData(0);
      let end = d.length;
      while (end > 0 && Math.abs(d[end - 1]) < 0.0003) end--;
      return pack(buf, 0, Math.min(d.length, end + Math.round(SR * 0.02)));
    };
    // 고리: 길이 L 초를 맨 끝 구간에서 따고, 앞 X 초를 그 직전과 겹쳐 이음 (이어 돌려도 딸깍 없이)
    const loopOf = (buf, L, X = 0.25) => {
      const d = buf.getChannelData(0);
      const n = Math.round(L * SR);
      const x = Math.round(X * SR);
      const start = d.length - n;
      const out = new Float32Array(n);
      for (let i = 0; i < n; i++) out[i] = d[start + i];
      for (let i = 0; i < x; i++) {
        const a = i / x;
        out[i] = out[i] * a + d[start - x + i] * (1 - a);
      }
      let peak = 0;
      for (const v of out) peak = Math.max(peak, Math.abs(v));
      return { data: Array.from(out), peak };
    };
    window.bake = {
      async sfx(name, opts, seconds = 2.5, setup = null) {
        const { ctx, s } = fresh(seconds);
        if (setup === 'hazard') s.hazardStyle = opts.style;
        if (name === 'rise') s.rise(s.master);
        else s.play(name, opts);
        return trim(await ctx.startRendering());
      },
      async hazardLoop(style, L) {
        const { ctx, s } = fresh(L + 3);
        const hz = s.buildHazard(style);
        hz.out.gain.value = 1;
        return loopOf(await ctx.startRendering(), L);
      },
      async hazardPop(style) {
        const { ctx, s } = fresh(2.6);
        s.hazardPop(style, s.master);
        return trim(await ctx.startRendering());
      },
      async song(key, tense) {
        const song = (await import('/music.js')).songFor(key, tense);
        const L = (16 * 16 * 60) / song.bpm / 4; // 16마디
        const { ctx, s } = fresh(L * 2 + 0.1);
        const m = new Music(s);
        m.mood = key === 'lobby' ? 'calm' : tense ? 'lava' : 'battle';
        m.theme = key === 'lobby' ? null : key;
        m.renderTo(ctx, ctx.destination, L * 2 + 0.05);
        const buf = await ctx.startRendering();
        const d = buf.getChannelData(0);
        const n = Math.round(L * SR);
        const out = d.slice(n, 2 * n); // 두 번째 바퀴 (첫 바퀴 꼬리가 앞에 겹쳐 있어 이어 돌리면 그대로)
        let peak = 0;
        for (const v of out) peak = Math.max(peak, Math.abs(v));
        return { data: Array.from(out), peak, length: L, bpm: song.bpm };
      },
      async drone(theme, L) {
        const { ctx, s } = fresh(L + 4);
        s.ready = () => true;
        const ts = new TitleSound(s, theme);
        ts.build();
        ts.out.gain.cancelScheduledValues(0);
        ts.out.gain.value = C.TITLE_SOUND.vol;
        return loopOf(await ctx.startRendering(), L);
      },
      async ping(theme) {
        const { ctx, s } = fresh(6);
        s.ready = () => true;
        const ts = new TitleSound(s, theme);
        ts.build();
        for (const n of ts.nodes) n.stop(0); // 웅웅은 끄고 띄엄 소리 + 울림만
        ts.out.gain.cancelScheduledValues(0);
        ts.out.gain.value = C.TITLE_SOUND.vol;
        ts.ping();
        return trim(await ctx.startRendering());
      },
    };
  }, SR);
  const C = await page.evaluate(() => window.C);
  const manifest = { sampleRate: SR, sfx: {}, hazard: {}, music: {}, ambient: {} };
  const save = (file, r) => {
    const wav = path.join(OUT, `${file}.wav`);
    const buf = Buffer.alloc(44 + r.data.length * 2);
    buf.write('RIFF', 0); buf.writeUInt32LE(36 + r.data.length * 2, 4); buf.write('WAVEfmt ', 8);
    buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
    buf.write('data', 36); buf.writeUInt32LE(r.data.length * 2, 40);
    const norm = r.peak > 0 ? 0.95 / r.peak : 1; // 크게 맞춰 굽고 (양자화 잡음 적게), 고도는 gain 으로 원래 크기
    r.data.forEach((v, i) => buf.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(v * norm * 32767))), 44 + i * 2));
    fs.writeFileSync(wav, buf);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '3', path.join(OUT, `${file}.ogg`)]);
    fs.unlinkSync(wav);
    return { file: `${file}.ogg`, gain: r.peak > 0 ? r.peak / 0.95 : 1, sec: +(r.data.length / SR).toFixed(3) };
  };
  // ---- 효과음 ----
  const weapons = [null, ...Object.keys(C.SFX_WEAPONS)];
  const jobs = [];
  const add = (key, name, opts = {}, n = VARIANTS, seconds = 2.5, setup = null) => jobs.push({ key, name, opts, n, seconds, setup });
  for (const w of weapons) {
    add(`swing.${w || 'none'}`, 'swing', w ? { char: w } : {});
    for (const [t, o] of [['1', { step: 1 }], ['2', { step: 2 }], ['3', { step: 3 }], ['heavy', { tier: 'heavy' }], ['crit', { tier: 'crit' }]]) {
      add(`hit.${w || 'none'}.${t}`, 'hit', { ...o, ...(w ? { char: w } : {}) }, 2);
      if (w === 'bard') add(`hit.bardMetal.${t}`, 'hit', { ...o, char: 'bard', form: 'metal' }, 2);
    }
  }
  add('fire.none', 'fire', {});
  add('fire.hunter', 'fire', { char: 'hunter' });
  for (const n of ['tear', 'shatter', 'tap', 'crit', 'hurt', 'danger', 'airJump', 'land', 'crush', 'fall', 'pickup', 'latch', 'boom', 'tick', 'go', 'win', 'lose', 'bbBreak', 'clear', 'sizzle']) add(n, n, {}, ['danger', 'tick', 'go', 'win', 'lose', 'clear'].includes(n) ? 1 : VARIANTS);
  for (const n of ['smash', 'koCrush', 'glideRing', 'bbTick', 'bbBlast']) {
    add(n, n, {});
    add(`${n}.strong`, n, { strong: true });
  }
  add('bbRise', 'bbRise', {});
  add('bbRise.big', 'bbRise', { big: true });
  add('final', 'final', {}, 1, 3);
  add('strum', 'strum', {});
  add('strum.metal', 'strum', { form: 'metal' });
  const styles = Object.keys(C.SFX_HAZARD.vol);
  for (const st of styles) {
    add(`lavaDeath.${st}`, 'lavaDeath', { style: st }, 2, 2.5, 'hazard');
    add(`rise.${st}`, 'rise', { style: st }, 1, 3, 'hazard');
  }
  for (const j of jobs) {
    const files = [];
    for (let i = 0; i < j.n; i++) {
      const r = await page.evaluate(({ name, opts, seconds, setup }) => window.bake.sfx(name, opts, seconds, setup), j);
      files.push(save(`${j.key}.${i}`, r));
    }
    manifest.sfx[j.key] = files;
    process.stdout.write('.');
  }
  // ---- 위험 액체 ----
  const loopLen = { water: 9.0909, storm: 14.2857, energy: 5, lava: 4, swamp: 4 }; // 흔들림 주기의 배수 (water 0.22Hz ×2, storm 0.07Hz, energy 0.4Hz ×2)
  for (const st of styles) {
    const loop = save(`hazard.${st}`, await page.evaluate(({ st, L }) => window.bake.hazardLoop(st, L), { st, L: loopLen[st] || 4 }));
    const pops = [];
    for (let i = 0; i < 4; i++) pops.push(save(`hazardPop.${st}.${i}`, await page.evaluate((st) => window.bake.hazardPop(st), st)));
    manifest.hazard[st] = { loop, pops };
    process.stdout.write('h');
  }
  // ---- 곡 ----
  for (const key of Object.keys(C.MUSIC_THEMES)) {
    for (const tense of key === 'lobby' ? [false] : [false, true]) {
      const r = await page.evaluate(({ key, tense }) => window.bake.song(key, tense), { key, tense });
      manifest.music[`${key}${tense ? '.tense' : ''}`] = { ...save(`music.${key}${tense ? '.tense' : ''}`, r), length: r.length, bpm: r.bpm };
      process.stdout.write('m');
    }
  }
  // ---- 앰비언트 (메뉴·대기실) ----
  for (const theme of Object.keys(C.TITLE_THEMES)) {
    const drone = save(`ambient.${theme}`, await page.evaluate(({ theme }) => window.bake.drone(theme, 11.1111), { theme }));
    const pings = [];
    for (let i = 0; i < 4; i++) pings.push(save(`ambientPing.${theme}.${i}`, await page.evaluate((theme) => window.bake.ping(theme), theme)));
    manifest.ambient[theme] = { drone, pings };
    process.stdout.write('a');
  }
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 1));
  const size = fs.readdirSync(OUT).filter((f) => f.endsWith('.ogg')).reduce((a, f) => a + fs.statSync(path.join(OUT, f)).size, 0);
  console.log(`\n녹음 ${fs.readdirSync(OUT).filter((f) => f.endsWith('.ogg')).length}개, ${(size / 1e6).toFixed(2)}MB`);
  await browser.close();
})();
