// 소리 개편 (client/sound.js · music.js): 효과음 파일·무기 표·위험 액체 표·테마 음악 표가 서로 맞는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { CONFIG as C } from '../shared/config.js';
import { songFor, chordAt, degreeNote, INSTRUMENTS, DRUMS, ARPS } from '../client/music.js';

const SFX = new URL('../client/assets/sfx/', import.meta.url);

test('효과음 묶음의 파일이 다 있고, 폴더에 안 쓰는 파일이 없고, 합계 3MB 이하', () => {
  const used = new Set(Object.values(C.SFX_BANKS).flatMap((b) => b.files.map((f) => `${f}.ogg`)));
  const onDisk = fs.readdirSync(SFX).filter((f) => f.endsWith('.ogg'));
  for (const f of used) assert.ok(onDisk.includes(f), `없음: ${f}`);
  for (const f of onDisk) assert.ok(used.has(f), `안 쓰는 파일: ${f}`);
  const bytes = onDisk.reduce((s, f) => s + fs.statSync(new URL(f, SFX)).size, 0);
  assert.ok(bytes < 3 * 1024 * 1024, `${bytes} 바이트`);
  for (const [k, b] of Object.entries(C.SFX_BANKS)) assert.ok(b.files.length && b.gain > 0, k);
});

test('효과음 출처: CREDITS.md 에 팩마다 CC0 로 적혀 있음', () => {
  const credits = fs.readFileSync(new URL('../client/assets/CREDITS.md', import.meta.url), 'utf8');
  for (const pack of ['impact-sounds', 'rpg-audio', 'sci-fi-sounds', 'interface-sounds', 'music-jingles']) assert.ok(credits.includes(`kenney.nl/assets/${pack}`), pack);
  for (const prefix of ['impactPunch', 'chop', 'explosionCrunch', 'pluck', 'jingles_STEEL']) assert.ok(credits.includes(prefix), prefix);
});

test('캐릭터 8명 모두 무기 소리가 있고, 그 묶음이 있음 (strum 은 합성 기타)', () => {
  for (const ch of C.CHARACTERS) {
    const w = C.SFX_WEAPONS[ch];
    assert.ok(w, ch);
    assert.ok(C.SFX_BANKS[w.swing], `${ch} swing`);
    assert.ok(w.hit === 'strum' || C.SFX_BANKS[w.hit], `${ch} hit`);
    if (w.shot) assert.ok(C.SFX_BANKS[w.shot], `${ch} shot`);
    assert.ok(w.rate > 0.3 && w.rate < 2, `${ch} rate`);
  }
  // 무기 소리가 다 같지 않음 (휘두름 높낮이 + 타격 겹)
  assert.ok(new Set(C.CHARACTERS.map((ch) => `${C.SFX_WEAPONS[ch].swing}${C.SFX_WEAPONS[ch].rate}${C.SFX_WEAPONS[ch].hit}`)).size === C.CHARACTERS.length);
});

test('위험 액체: 맵 테마의 hazard.style 마다 지속음 크기·튀는 소리가 있음', () => {
  const styles = new Set(Object.values(C.WORLD_THEMES).map((t) => t.hazard && t.hazard.style).filter(Boolean));
  styles.add(C.SFX_HAZARD.fallback);
  for (const s of styles) {
    assert.ok(C.SFX_HAZARD.vol[s] > 0, `vol ${s}`);
    assert.ok(C.SFX_HAZARD.pops[s] >= 0, `pops ${s}`);
  }
});

test('배경음악: 대기실 + 맵 테마마다 곡이 있고, 악기·장단 이름이 맞음', () => {
  const themes = new Set(Object.values(C.WORLD_MAP_THEME));
  for (const t of [...themes, 'lobby', C.MUSIC_THEME_DEFAULT]) {
    const s = C.MUSIC_THEMES[t];
    assert.ok(s, t);
    assert.ok(INSTRUMENTS.includes(s.lead) && INSTRUMENTS.includes(s.bass), `${t} 악기`);
    assert.ok(DRUMS.includes(s.drums) && ARPS.includes(s.arp), `${t} 장단`);
    assert.ok(s.bpm >= 60 && s.bpm <= 200, `${t} bpm`);
    assert.ok(s.prog.every((d) => d >= 0 && d < s.scale.length), `${t} 화음`);
  }
  // 테마마다 다른 곡 (빠르기·음계·악기 중 하나는 다름)
  const sig = [...themes].map((t) => JSON.stringify([C.MUSIC_THEMES[t].bpm, C.MUSIC_THEMES[t].scale, C.MUSIC_THEMES[t].lead]));
  assert.equal(new Set(sig).size, themes.size);
  assert.ok(DRUMS.includes(C.MUSIC_TENSION.drums));
});

test('긴장 버전: 더 빠르고 단조 (장3·6·7도가 반음 내려감), 화음은 음계 안의 음', () => {
  const calm = songFor('meadow', false);
  const tense = songFor('meadow', true);
  assert.ok(tense.bpm > calm.bpm);
  assert.deepEqual(tense.scale, [0, 2, 3, 5, 7, 8, 10]);
  for (const song of [calm, tense, songFor('desert', false)]) {
    for (let bar = 0; bar < 4; bar++) {
      for (const m of chordAt(song, bar)) assert.ok(song.scale.includes((((m - song.root) % 12) + 12) % 12), `${m}`);
    }
  }
  assert.equal(degreeNote(calm, 7), calm.root + 12); // 한 옥타브 위 으뜸음
  assert.equal(songFor('없는테마', false), C.MUSIC_THEMES[C.MUSIC_THEME_DEFAULT]);
});
