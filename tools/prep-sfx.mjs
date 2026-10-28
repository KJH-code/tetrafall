// 타격·휘두름 효과음 재료 다듬기 (2026-10-28): OpenGameArt CC0 원본 → client/assets/sfx/*.ogg
//   node tools/prep-sfx.mjs <원본 폴더> [출력 폴더]
// <원본 폴더> 에 아래 SOURCES 의 팩을 받아 풀어 둠 (7z 는 7z 나 py7zr 로). 파일마다 앞 무음 자르기 → 대역 거르기 → 길이 자르기·끝 페이드 → 최고점 -1dB 로 맞춤 → 모노 ogg.
// 왜: 예전 타격(Kenney impactPunch)은 무게중심 ~100Hz·3kHz 위가 거의 없고 어택 30~40ms 라 '둔탁'. 스매시식 '팍!' = 1~3ms 고역 크랙 + 짧은 중역 펀치 + 짧은 꼬리 → 재료를 역할별로 나눠 다듬고 sound.js 가 겹쳐 틈
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// 팩 (전부 OpenGameArt, 페이지 라이선스 CC0)
export const SOURCES = {
  thwack: 'https://opengameart.org/content/thwack-sounds (Jordan Irwin / AntumDeluge, thwack-1.0.zip)',
  qubodupPunch: 'https://opengameart.org/content/punch (qubodup, qubodupPunch.7z)',
  qubodupImpact: 'https://opengameart.org/content/impact (qubodup, qubodupImpact.7z)',
  ljudbank: 'https://opengameart.org/content/37-hitspunches (independent.nu ljudbank, independent_nu_ljudbank-hits_and_punches.7z)',
  starninjasSword: 'https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes (StarNinjas, sword_-_starninjas_1.zip)',
  swishes: 'https://opengameart.org/content/swishes-sound-pack (swishes.zip)',
};

// 역할: hp = 이 높이 아래를 깎음 (Hz), lp = 위를 깎음, len = 길이 (초), fade = 끝 페이드 길이
const ROLES = {
  crack: { hp: 1200, lp: 16000, len: 0.16, fade: 0.1 }, // 맞는 순간 '팍' (고역 찰싹)
  punch: { hp: 110, lp: 7000, len: 0.22, fade: 0.12 }, // 짧은 몸통 '퍽' (중역, 웅웅 저음은 깎음)
  heavy: { hp: 45, lp: 9000, len: 0.5, fade: 0.25 }, // 강타 '콰앙' 몸통
  ring: { hp: 900, lp: 16000, len: 0.4, fade: 0.25 }, // 치명타 쨍
  swishBlade: { hp: 1500, lp: 16000, len: 0.3, fade: 0.15 }, // 칼 '슉' (높고 짧게)
  swishMid: { hp: 400, lp: 12000, len: 0.18, fade: 0.08 }, // 맨손·보통 '휙'
  swishHeavy: { hp: 150, lp: 8000, len: 0.24, fade: 0.1 }, // 도끼·망치 '훙'
};

// [출력 이름, 역할, 원본 (원본 폴더 기준)]
export const FILES = [
  ['hitCrack_1', 'crack', 'thwack-1.0/PCM/thwack-01.wav'],
  ['hitCrack_2', 'crack', 'thwack-1.0/PCM/thwack-04.wav'],
  ['hitCrack_3', 'crack', 'thwack-1.0/PCM/thwack-10.wav'],
  ['hitPunch_1', 'punch', 'qubodupPunch/qubodupPunch/qubodupPunch01.flac'],
  ['hitPunch_2', 'punch', 'qubodupPunch/qubodupPunch/qubodupPunch05.flac'],
  ['hitPunch_3', 'punch', 'thwack-1.0/PCM/thwack-06.wav'],
  ['hitPunch_4', 'punch', 'independent_nu_ljudbank-hits_and_punches/hits/hit15.mp3.flac'],
  ['hitPunch_5', 'punch', 'independent_nu_ljudbank-hits_and_punches/hits/hit10.mp3.flac'],
  ['hitHeavy_1', 'heavy', 'qubodupPunch/qubodupPunch/qubodupPunch04.flac'],
  ['hitHeavy_2', 'heavy', 'independent_nu_ljudbank-hits_and_punches/hits/hit24.mp3.flac'],
  ['hitHeavy_3', 'heavy', 'independent_nu_ljudbank-hits_and_punches/hits/hit25.mp3.flac'],
  ['hitHeavy_4', 'heavy', 'qubodupImpact/qubodupImpact/qubodupImpactStone.flac'],
  ['hitRing_1', 'ring', 'qubodupImpact/qubodupImpact/qubodupImpactMetal.flac'],
  ['swishBlade_1', 'swishBlade', 'sword_-_starninjas_1/sword - StarNinjas/sword.6.ogg'],
  ['swishBlade_2', 'swishBlade', 'sword_-_starninjas_1/sword - StarNinjas/sword.8.ogg'],
  ['swishBlade_3', 'swishBlade', 'sword_-_starninjas_1/sword - StarNinjas/sword.5.ogg'],
  ['swishMid_1', 'swishMid', 'swishes/swishes/swish-10.wav'],
  ['swishMid_2', 'swishMid', 'swishes/swishes/swish-13.wav'],
  ['swishMid_3', 'swishMid', 'swishes/swishes/swish-12.wav'],
  ['swishMid_4', 'swishMid', 'swishes/swishes/swish-11.wav'],
  ['swishHeavy_1', 'swishHeavy', 'swishes/swishes/swish-1.wav'],
  ['swishHeavy_2', 'swishHeavy', 'swishes/swishes/swish-5.wav'],
  ['swishHeavy_3', 'swishHeavy', 'swishes/swishes/swish-7.wav'],
];

function peakDb(file, filters) {
  const out = spawnSync('ffmpeg', ['-hide_banner', '-i', file, '-af', `${filters},volumedetect`, '-f', 'null', '-']).stderr.toString();
  return Number((out.match(/max_volume: (-?[\d.]+) dB/) || [])[1] ?? 0);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [src, out = 'client/assets/sfx'] = process.argv.slice(2);
  if (!src) {
    console.error('사용법: node tools/prep-sfx.mjs <원본 폴더> [출력 폴더]');
    process.exit(1);
  }
  fs.mkdirSync(out, { recursive: true });
  for (const [name, role, rel] of FILES) {
    const r = ROLES[role];
    const file = path.join(src, rel);
    const base = [
      'aformat=channel_layouts=mono',
      'silenceremove=start_periods=1:start_threshold=-40dB:start_silence=0.002',
      `highpass=f=${r.hp}`,
      `lowpass=f=${r.lp}`,
      `atrim=0:${r.len}`,
      `afade=t=in:d=0.002`,
      `afade=t=out:st=${(r.len - r.fade).toFixed(3)}:d=${r.fade}`,
    ].join(',');
    const gain = -1 - peakDb(file, base); // 최고점 -1dB
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', file, '-af', `${base},volume=${gain.toFixed(2)}dB`, '-ar', '44100', '-c:a', 'libvorbis', '-q:a', '4', path.join(out, `${name}.ogg`)]);
    console.log(`${name}.ogg  ← ${rel}  (${role}, ${gain >= 0 ? '+' : ''}${gain.toFixed(1)}dB)`);
  }
}
