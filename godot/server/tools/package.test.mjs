// 배포 묶음 start 스크립트 (W6 2026-11-02): 윈도우 .bat 이 tetrafall.exe 를 고성능 GPU 로 등록 (HKCU UserGpuPreferences, 이미 있으면 건너뜀) + README 안내.
// 실행 (레포 뿌리): node --test godot/server/tools/package.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { TARGETS, readme, gpuPrefLines, GPU_PREF_KEY, GPU_PREF_VALUE, download, fetchCloudflared, cloudflaredUrl, releaseNotes, parseArgs } from './package.mjs';

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

// W32 하이브리드 GPU: .bat 이 고성능으로 등록하는 exe 이름 = 묶음에 실제로 들어가는 윈도우 클라 exe = 내보내기 프리셋 이름 (이름이 어긋나면 등록이 헛돎).
// 값 이름은 '%~dp0' + exe (= 사용자가 켜는 전체 경로) 라서 폴더를 옮겨도 다음 start 에서 새 경로로 다시 씀. 클라를 켜는 모든 .bat 이 등록 다음에 켬.
test('GPU 등록 exe 이름 = 묶음 윈도우 클라 = 내보내기 프리셋', () => {
  const exe = path.basename(TARGETS.win.client[0]);
  assert.equal(exe, 'tetrafall.exe');
  const presets = fs.readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../client/export_presets.cfg'), 'utf8');
  const win = presets.split(/\[preset\.\d+\]\r?\n/).find((b) => /name="Windows"/.test(b));
  assert.ok(win, '윈도우 프리셋');
  assert.equal(path.basename(/export_path="([^"]+)"/.exec(win)[1]), exe, '프리셋 내보내기 이름');
  for (const l of gpuPrefLines().filter((x) => x.includes('%~dp0'))) assert.ok(l.includes(`"%~dp0${exe}"`), `등록 줄 exe: ${l}`);
  assert.ok(gpuPrefLines()[0].includes(exe), '안내 줄도 같은 이름');
  for (const [name, s] of Object.entries(TARGETS.win.scripts)) {
    const lines = s.split('\r\n');
    const run = lines.indexOf(':run');
    assert.ok(run > 0, `${name}: GPU 등록 줄이 있음`);
    for (const [i, l] of lines.entries()) if (l.startsWith('start ""')) {
      assert.ok(i > run && l.includes(`"%~dp0${exe}"`), `${name}: 클라는 등록 다음, 같은 exe`);
    }
  }
});

// ---- 배포 안정성 (W36 2026-11-09): cloudflared 캐시·실패해도 계속·시간 상한 ----
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'tf-pkg-'));
const quiet = { log() {}, sleep: async () => {} };
const okRes = (body = 'BIN') => ({ ok: true, status: 200, arrayBuffer: async () => Buffer.from(body) });

test('download: 일시 장애는 다시 시도해서 받음, 시도마다 timeout 신호', async () => {
  const d = tmp();
  let n = 0;
  const signals = [];
  const fetchFn = async (url, init) => {
    signals.push(init.signal);
    return ++n < 3 ? { ok: false, status: 504 } : okRes('hello');
  };
  await download('http://x/a', path.join(d, 'a'), { ...quiet, fetchFn });
  assert.equal(n, 3);
  assert.equal(fs.readFileSync(path.join(d, 'a'), 'utf8'), 'hello');
  assert.ok(signals.every((s) => s instanceof AbortSignal), '각 시도에 AbortSignal.timeout');
});

test('download: 계속 실패하면 throw, 반쪽 파일을 안 남김. 시도 횟수 상한', async () => {
  const d = tmp();
  let n = 0;
  await assert.rejects(download('http://x/a', path.join(d, 'a'), { ...quiet, fetchFn: async () => (n++, { ok: false, status: 504 }) }), /504/);
  assert.equal(n, 3);
  assert.equal(fs.existsSync(path.join(d, 'a')), false);
});

test('download: 시간 예산이 지나면 더 시도 안 함', async () => {
  const d = tmp();
  let n = 0;
  await assert.rejects(download('http://x/a', path.join(d, 'a'), { ...quiet, deadline: Date.now() - 1, fetchFn: async () => (n++, okRes()) }));
  assert.equal(n, 0);
});

test('cloudflared 못 받아도 throw 안 함 (경고용 결과), required 면 throw', async () => {
  const d = tmp();
  const fetchFn = async () => ({ ok: false, status: 504 });
  const r = await fetchCloudflared(TARGETS.linux, path.join(d, 'cloudflared'), { ...quiet, fetchFn });
  assert.equal(r.ok, false);
  assert.match(r.error, /504/);
  assert.equal(fs.existsSync(path.join(d, 'cloudflared')), false);
  await assert.rejects(fetchCloudflared(TARGETS.linux, path.join(d, 'cloudflared'), { ...quiet, fetchFn, required: true }), /504/);
});

test('cloudflared 캐시: 받으면 보관, 다음엔 네트워크를 안 씀 (플랫폼별 폴더)', async () => {
  const d = tmp();
  const cache = path.join(d, 'cache');
  let n = 0;
  const fetchFn = async () => (n++, okRes('EXE'));
  const a = await fetchCloudflared(TARGETS.win, path.join(d, 'cloudflared.exe'), { ...quiet, fetchFn, cache });
  assert.deepEqual([a.ok, a.from, n], [true, 'net', 1]);
  assert.equal(fs.readFileSync(path.join(cache, 'win-x64', 'cloudflared.exe'), 'utf8'), 'EXE');
  fs.rmSync(path.join(d, 'cloudflared.exe'));
  const b = await fetchCloudflared(TARGETS.win, path.join(d, 'cloudflared.exe'), { ...quiet, fetchFn: async () => { throw new Error('네트워크를 쓰면 안 됨'); }, cache });
  assert.deepEqual([b.ok, b.from], [true, 'cache']);
  assert.equal(fs.readFileSync(path.join(d, 'cloudflared.exe'), 'utf8'), 'EXE');
  assert.equal(fs.existsSync(path.join(cache, 'linux-x64')), false, '다른 플랫폼 칸은 안 건드림');
});

test('cloudflared 캐시에 빈 파일이면 무시하고 다시 받음', async () => {
  const d = tmp();
  const cache = path.join(d, 'cache');
  fs.mkdirSync(path.join(cache, 'linux-x64'), { recursive: true });
  fs.writeFileSync(path.join(cache, 'linux-x64', 'cloudflared'), '');
  const r = await fetchCloudflared(TARGETS.linux, path.join(d, 'cf'), { ...quiet, fetchFn: async () => okRes('NEW'), cache });
  assert.equal(r.from, 'net');
  assert.equal(fs.readFileSync(path.join(cache, 'linux-x64', 'cloudflared'), 'utf8'), 'NEW');
});

test('cloudflared 태그를 정하면 latest 대신 그 태그 주소', () => {
  assert.match(cloudflaredUrl(TARGETS.linux, ''), /releases\/latest\/download\/cloudflared-linux-amd64$/);
  assert.equal(cloudflaredUrl(TARGETS.win, '2025.1.0'), 'https://github.com/cloudflare/cloudflared/releases/download/2025.1.0/cloudflared-windows-amd64.exe');
});

test('README: cloudflared 가 빠지면 직접 설치 안내가 맨 앞에 (플랫폼별), 있으면 예전 한 줄', () => {
  const winMiss = readme(TARGETS.win, { cloudflared: false });
  assert.match(winMiss, /cloudflared 가 안 들어 있음/);
  assert.match(winMiss, /winget install --id Cloudflare\.cloudflared/);
  assert.match(readme(TARGETS.linux, { cloudflared: false }), /releases 에서 받아 이 폴더에 cloudflared 로 \(chmod \+x\)/);
  assert.doesNotMatch(readme(TARGETS.win), /안 들어 있음/);
  assert.match(readme(TARGETS.win), /cloudflared 가 이 폴더에 없으면: winget/);
});

test('릴리스 노트: 빠진 플랫폼이 있을 때만 글, 없으면 빈 글', () => {
  assert.equal(releaseNotes([]), '');
  const n = releaseNotes(['linux']);
  assert.match(n, /linux/);
  assert.match(n, /winget install/);
});

test('옵션: 캐시·예산·필수 (기본은 캐시 없음·600초·필수 아님)', () => {
  const base = ['--no-godot'];
  const d = parseArgs(base);
  assert.deepEqual([d.cloudflaredCache, d.cloudflaredBudgetSec, d.requireCloudflared], [null, 600, false]);
  const o = parseArgs([...base, '--cloudflared-cache', 'c', '--cloudflared-budget', '90', '--require-cloudflared']);
  assert.deepEqual([o.cloudflaredCache, o.cloudflaredBudgetSec, o.requireCloudflared], [path.resolve('c'), 90, true]);
  assert.throws(() => parseArgs([...base, '--cloudflared-budget', '0']));
});

// ---- release.yml (W36): 작은 웹 템플릿 켜기/끄기 스위치 ----
test('release.yml: 웹 템플릿 job 은 변수·수동 입력으로만 켜짐 (기본 끔), package 는 건너뛰어도 돎', () => {
  const y = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '../../../.github/workflows/release.yml'), 'utf8');
  const job = y.slice(y.indexOf('  web-template:'), y.indexOf('  package:'));
  assert.match(job, /vars\.WEB_TEMPLATE_BUILD == 'true'/);
  assert.match(job, /inputs\.web_template == true/);
  assert.match(y, /web_template:\n\s+description:[^\n]*\n\s+type: boolean\n\s+default: false/);
  assert.match(y, /needs: web-template\n\s+#[^\n]*\n\s+if: \$\{\{ !cancelled\(\)/);
  assert.match(y, /--cloudflared-cache/);
});
