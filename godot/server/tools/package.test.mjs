// 배포 묶음 start 스크립트 (W6 2026-11-02): 윈도우 .bat 이 tetrafall.exe 를 고성능 GPU 로 등록 (HKCU UserGpuPreferences, 이미 있으면 건너뜀) + README 안내.
// 실행 (레포 뿌리): node --test godot/server/tools/package.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { TARGETS, readme, gpuPrefLines, GPU_PREF_KEY, GPU_PREF_VALUE } from './package.mjs';

const bat = (name) => TARGETS.win.scripts[name];

test('start-lan·start-online .bat: GPU 등록 다음 서버', () => {
  for (const [name, args] of [['start-lan.bat', ''], ['start-online.bat', ' --online']]) {
    const lines = bat(name).split('\r\n');
    assert.equal(lines[0], '@echo off');
    assert.equal(lines[1], 'cd /d "%~dp0"');
    const q = lines.findIndex((l) => l.startsWith('reg query'));
    const a = lines.findIndex((l) => l.includes('reg add'));
    const run = lines.indexOf(`Tetrafall.Server.exe${args}`);
    assert.ok(q > 1 && a === q + 1 && run > a, `${name}: 조회 → 없으면 쓰기 → 서버`);
    assert.equal(lines[a].startsWith('if errorlevel 1 reg add'), true, '조회 실패 (값 없음) 일 때만 씀 — 재혁이 직접 고른 값은 그대로');
    assert.ok(lines[a].includes(`/t REG_SZ /d "${GPU_PREF_VALUE}" /f`), '고성능 = GpuPreference=2;');
    assert.ok(lines.some((l) => l === 'if not exist "%~dp0tetrafall.exe" goto run') && lines.includes(':run'), 'exe 가 없으면 건너뜀');
    assert.equal(lines.at(-2), 'pause');
    assert.ok(bat(name).endsWith('\r\n') && !/[^\r]\n/.test(bat(name)), 'CRLF');
  }
  assert.equal(GPU_PREF_KEY, 'HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences', '사용자 키 (관리자 권한 필요 없음)');
});

test('.bat 은 ASCII 만, 괄호 블록 없음, rem 에 리다이렉트 글자 없음', () => {
  for (const name of ['start-lan.bat', 'start-online.bat']) {
    const s = bat(name);
    assert.ok(/^[\x00-\x7f]*$/.test(s), `${name}: cmd 는 .bat 을 OEM 코드 페이지로 읽음 → 한글 글자 금지`);
    for (const l of s.split('\r\n')) {
      if (l.startsWith('rem ')) assert.ok(!/[<>|&%]/.test(l), `rem 줄에 특수 글자: ${l}`);
      else assert.ok(!/^\s*\(|\)\s*$/.test(l), `괄호 블록 (경로의 ')' 로 깨짐): ${l}`);
    }
  }
});

test('경로에 한글·공백·괄호가 있어도: %~dp0 은 늘 따옴표 안', () => {
  // cmd 는 %~dp0 을 실행 중에 펼침 (파일 글자가 아님 → 한글 그대로). 펼친 뒤 따옴표 짝이 맞고 경로가 늘 따옴표 안인지
  const dir = 'C:\\Users\\김재혁\\Downloads\\테트라폴 (새 판) & 친구\\tetrafall-win-x64\\';
  for (const l of gpuPrefLines()) {
    if (!l.includes('%~dp0')) continue;
    const out = l.replaceAll('%~dp0', dir);
    assert.equal((out.match(/"/g) || []).length % 2, 0, `따옴표 짝: ${out}`);
    let inQ = false;
    for (let i = 0; i < out.length; i++) {
      if (out[i] === '"') inQ = !inQ;
      if (out.startsWith(dir, i)) assert.ok(inQ, `경로가 따옴표 밖: ${out}`);
    }
    assert.ok(out.includes(`"${dir}tetrafall.exe"`), '값 이름 = exe 전체 경로 (Windows 설정 > 그래픽 과 같은 모양)');
  }
});

test('README: 윈도우만 GPU 안내 한 줄 (+ 설정 화질·F3)', () => {
  const w = readme(TARGETS.win);
  assert.ok(w.includes('고성능 GPU 로 등록') && w.includes('Windows 설정 > 시스템 > 디스플레이 > 그래픽') && w.includes('F3'));
  assert.ok(w.split('\r\n').length > 5 && !/[^\r]\n/.test(w), '윈도우 README 는 CRLF');
  const l = readme(TARGETS.linux);
  assert.ok(!l.includes('고성능 GPU') && !l.includes('\r'), '리눅스는 안내 없음·LF');
  assert.ok(TARGETS.linux.scripts['start-lan.sh'].startsWith('#!/bin/sh'), '리눅스 .sh 그대로');
});

// W12 렌더러 시험 .bat: 서버 + 클라를 그 렌더러로 같이, 기본 start-lan.bat 은 그대로 (클라를 안 켬)
test('start-lan-compat·forward·mobile .bat: 렌더러만 다름', () => {
  const want = { compat: 'gl_compatibility --rendering-driver opengl3', forward: 'forward_plus --rendering-driver vulkan', mobile: 'mobile --rendering-driver vulkan' };
  for (const [k, args] of Object.entries(want)) {
    const s = bat(`start-lan-${k}.bat`);
    const lines = s.split('\r\n');
    assert.ok(/^[\x00-\x7f]*$/.test(s) && s.endsWith('\r\n'), `${k}: ASCII·CRLF`);
    assert.ok(!/\(\r\n/.test(s), `${k}: 괄호 블록 없음`);
    const at = lines.findIndex((l) => l.startsWith('start ""'));
    assert.equal(lines[at], `start "" "%~dp0tetrafall.exe" --rendering-method ${args}`);
    assert.ok(at > lines.indexOf(':run') && lines[at + 1] === 'Tetrafall.Server.exe' && lines[at + 2] === 'pause', `${k}: GPU 등록 → 클라 → 서버`);
  }
  assert.ok(!bat('start-lan.bat').includes('tetrafall.exe" --'), '기본 start-lan 은 그대로');
  assert.ok(readme(TARGETS.win).includes('start-lan-forward.bat'), 'README 안내');
});

// W19 새 Blender 탱크 시험: 클라를 --ext 로 켬, 기본 start-lan 은 그대로
test('start-lan-ext .bat/.sh: 클라 --ext', () => {
  const s = bat('start-lan-ext.bat');
  const lines = s.split('\r\n');
  assert.ok(/^[\x00-\x7f]*$/.test(s) && s.endsWith('\r\n'), 'ASCII·CRLF');
  assert.ok(!/\(\r\n/.test(s), '괄호 블록 없음');
  const at = lines.findIndex((l) => l.startsWith('start ""'));
  assert.equal(lines[at], 'start "" "%~dp0tetrafall.exe" -- --ext');
  assert.ok(at > lines.indexOf(':run') && lines[at + 1] === 'Tetrafall.Server.exe' && lines[at + 2] === 'pause', 'GPU 등록 → 클라 → 서버');
  const sh = TARGETS.linux.scripts['start-lan-ext.sh'];
  assert.ok(sh.startsWith('#!/bin/sh') && sh.includes('tetrafall.x86_64 -- --ext') && sh.includes('exec ./Tetrafall.Server'));
  assert.ok(!bat('start-lan.bat').includes('--ext'), '기본 start-lan 은 그대로');
  assert.ok(readme(TARGETS.win).includes('start-lan-ext.bat'), 'README 안내');
});
