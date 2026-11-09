// 배포 묶음 (G7): C# 서버 + 고도 웹 빌드 + 고도 PC 클라를 한 폴더로 → zip. 받는 PC 에는 .NET·node·고도 필요 없음.
// 실행 (레포 뿌리에서): node godot/server/tools/package.mjs [--godot <고도 4.7.2 실행 파일>] [--targets win,linux] [--cloudflared] [--no-godot] [--web-template <zip>]
//   --godot       : 고도 실행 파일 (없으면 환경 변수 GODOT). 웹·PC 클라를 내보냄 (템플릿: godot/client/README.md G7)
//   --web-template: 웹 내보내기에 쓸 직접 빌드한 템플릿 zip (godot/client/tools/build-web-template.sh 결과, 없으면 환경 변수 GODOT_WEB_TEMPLATE).
//                   내보내는 동안만 export_presets.cfg 웹 custom_template/release 를 그 경로로 바꾸고 끝나면 (실패해도) 되돌림. 안 주면 공식 템플릿
//   --no-godot    : 내보내기 건너뛰고 이미 있는 godot/client/build/ 를 씀 (없는 건 빠짐 — 안내만)
//   --cloudflared : cloudflared 를 GitHub 에서 받아 서버 옆에 넣음 (그러면 --online 이 설치 없이 됨). 못 받아도 (GitHub 일시 장애) 묶음은 cloudflared 없이 만들고
//                   경고 + README.txt '직접 설치' 안내 + dist/release-notes.md (릴리스 노트에 덧붙임). 막으려면 --require-cloudflared
//   --cloudflared-cache <폴더> : 받은 cloudflared 를 <폴더>/<플랫폼>/<이름> 에 보관 — 있으면 네트워크를 안 씀 (환경 변수 CLOUDFLARED_CACHE). 최신이 아니라 정한 태그면 CLOUDFLARED_TAG
//   --cloudflared-budget <초>  : cloudflared 받기 전체(모든 플랫폼) 시간 상한, 기본 600 (한 번 시도 최대 60초, 3번까지, 간격 2·4초)
//   --require-cloudflared      : cloudflared 를 못 받으면 묶기를 실패로 (기본은 경고하고 계속)
//   --out <폴더>  : 기본 dist/
// 결과: dist/tetrafall-win-x64/ (+ .zip), dist/tetrafall-linux-x64/ (+ .zip)
//   Tetrafall.Server(.exe)   서버 (자기 완결형 한 파일)
//   web/                     고도 웹 빌드 (+ 파일마다 .br·.gz 미리 압축) → 서버가 /play/ 로, / 는 /play/ 로 넘겨줌
//   tetrafall(.exe / .x86_64) 고도 PC 클라 (기본 ws://127.0.0.1:3000 = 이 PC 서버)
//   start-lan / start-online (.bat / .sh — 윈도우 .bat 은 처음에 tetrafall.exe 를 고성능 GPU 로 등록), README.txt, cloudflared(.exe) (--cloudflared 일 때)
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const clientDir = path.join(root, 'godot', 'client');
const serverProject = path.join(root, 'godot', 'server', 'src', 'Tetrafall.Server');

// 하이브리드 그래픽 노트북 (W6 2026-11-02, 재혁 PC: Core Ultra 내장 + RTX 5070 에서 tetrafall.exe 가 내장으로 돌아 랙): Windows 는 exe 마다 GPU 를 고름.
// HKCU\Software\Microsoft\DirectX\UserGpuPreferences 에 'exe 전체 경로' = 'GpuPreference=2;' (고성능) 를 쓰면 Windows 설정 > 그래픽 에서 고른 것과 같음 (관리자 권한 필요 없음).
// start 스크립트가 처음 켜질 때 쓰고, 이미 값이 있으면 (재혁이 직접 고른 것 포함) 건드리지 않음. 폴더를 옮기면 새 경로로 다시 씀.
// .bat 은 ASCII 만 (cmd 는 .bat 을 OEM 코드 페이지로 읽음 — 한글 글자를 넣으면 깨짐). 경로는 %~dp0 (실행 중 펼침 — 한글·공백 경로 그대로) 을 늘 따옴표 안에.
// 괄호 블록을 안 씀 (경로에 ')' 가 있으면 블록이 깨짐) → goto
export const GPU_PREF_KEY = 'HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences';
export const GPU_PREF_VALUE = 'GpuPreference=2;';
export function gpuPrefLines(exe = 'tetrafall.exe') {
  const at = `"%~dp0${exe}"`;
  return [
    `rem Hybrid laptop GPU: run ${exe} on the high-performance GPU (same as Windows Settings - Graphics). Skipped if already set.`,
    `if not exist ${at} goto run`,
    `reg query "${GPU_PREF_KEY}" /v ${at} >nul 2>&1`,
    `if errorlevel 1 reg add "${GPU_PREF_KEY}" /v ${at} /t REG_SZ /d "${GPU_PREF_VALUE}" /f >nul && echo [GPU] ${exe} set to high-performance GPU`,
    ':run',
  ];
}
export function winScript(serverArgs = '') {
  return ['@echo off', 'cd /d "%~dp0"', ...gpuPrefLines(), `Tetrafall.Server.exe${serverArgs ? ' ' + serverArgs : ''}`, 'pause', ''].join('\r\n');
}

// 렌더러 시험 (W12 2026-11-03, 고도판 성능): 기본은 GL Compatibility (웹과 같음). PC 만 Forward+·Mobile (Vulkan) 로 켜 보는 시험용 —
// 서버를 켜면서 tetrafall.exe 를 그 렌더러로 같이 켬 (고도 실행 인자 --rendering-method·--rendering-driver, 내보낸 exe 에도 먹음).
// 재혁 PC 에서 각각 F3 (Ctrl+C 복사) 숫자를 받아 기본값을 정함. compat 은 같은 흐름 (스크립트가 클라를 켬) 의 비교 기준.
export const RENDER_TRIALS = { compat: ['gl_compatibility', 'opengl3'], forward: ['forward_plus', 'vulkan'], mobile: ['mobile', 'vulkan'] };
export function winTryScript(method, driver) {
  return [
    '@echo off',
    'cd /d "%~dp0"',
    `rem Renderer trial: ${method} (${driver}). Normal play (start-lan.bat) uses GL Compatibility. Compare FPS with F3 (Ctrl+C copies the numbers).`,
    ...gpuPrefLines(),
    `start "" "%~dp0tetrafall.exe" --rendering-method ${method} --rendering-driver ${driver}`,
    'Tetrafall.Server.exe',
    'pause',
    '',
  ].join('\r\n');
}

// 새 Blender 탱크 시험 (W19): 기본은 꺼짐 (chars_config.gd EXT). 서버를 켜면서 PC 클라를 실행 인자 --ext 로 같이 켬 (사용자 인자라 `--` 뒤)
export function winExtScript() {
  return [
    '@echo off',
    'cd /d "%~dp0"',
    'rem New Blender tank trial: starts tetrafall.exe with --ext (external models). Pick the tank in the lobby. Normal play (start-lan.bat) is unchanged.',
    ...gpuPrefLines(),
    'start "" "%~dp0tetrafall.exe" -- --ext',
    'Tetrafall.Server.exe',
    'pause',
    '',
  ].join('\r\n');
}

export const TARGETS = {
  win: {
    rid: 'win-x64',
    server: 'Tetrafall.Server.exe',
    preset: 'Windows',
    client: ['build/windows/tetrafall.exe'],
    cloudflared: { url: 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe', name: 'cloudflared.exe' },
    scripts: {
      'start-lan.bat': winScript(),
      'start-online.bat': winScript('--online'),
      ...Object.fromEntries(Object.entries(RENDER_TRIALS).map(([k, [m, d]]) => [`start-lan-${k}.bat`, winTryScript(m, d)])),
      'start-lan-ext.bat': winExtScript(),
    },
  },
  linux: {
    rid: 'linux-x64',
    server: 'Tetrafall.Server',
    preset: 'Linux',
    client: ['build/linux/tetrafall.x86_64'],
    cloudflared: { url: 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64', name: 'cloudflared' },
    scripts: {
      'start-lan.sh': '#!/bin/sh\ncd "$(dirname "$0")"\nexec ./Tetrafall.Server\n',
      'start-online.sh': '#!/bin/sh\ncd "$(dirname "$0")"\nexec ./Tetrafall.Server --online\n',
      'start-lan-ext.sh': '#!/bin/sh\ncd "$(dirname "$0")"\n./tetrafall.x86_64 -- --ext &\nexec ./Tetrafall.Server\n',
    },
  },
};

export function readme(t, { cloudflared = true } = {}) {
  const win = t.rid.startsWith('win');
  const ext = win ? 'bat' : 'sh';
  const pc = path.basename(t.client[0]);
  return [
    'Tetrafall (고도 클라 + C# 서버)',
    '',
    `같은 Wi-Fi 친구와:  start-lan.${ext} 를 켜고, 창에 뜬 "다른 PC에서: http://…" 주소를 친구에게`,
    `인터넷 친구와:      start-online.${ext} 를 켜고, 창에 뜬 https://….trycloudflare.com 주소를 친구에게 (클립보드에 복사돼 있음)`,
    ...(cloudflared
      ? ['                    cloudflared 가 이 폴더에 없으면: ' + (win ? 'winget install --id Cloudflare.cloudflared' : 'https://github.com/cloudflare/cloudflared/releases 에서 받아 이 폴더에 cloudflared 로')]
      : [
          '                    ※ 이 묶음에는 cloudflared 가 안 들어 있음 (만들 때 GitHub 에서 못 받음). 먼저 직접 설치:',
          '                      ' + (win ? 'winget install --id Cloudflare.cloudflared' : 'https://github.com/cloudflare/cloudflared/releases 에서 받아 이 폴더에 cloudflared 로 (chmod +x)'),
          '                      같은 Wi-Fi (start-lan) 는 상관없이 됨',
        ]),
    '',
    `나(서버 PC)는:      ${pc} 를 켜면 이 PC 서버에 바로 붙음 (아니면 브라우저로 http://localhost:3000)`,
    '친구는:             받은 주소를 크롬·엣지로 열기 (설치 없음). 방 코드는 대기실 "링크 복사"',
    `친구가 PC 클라로:   ${pc} -- --server wss://….trycloudflare.com   (같은 Wi-Fi 면 ws://서버IP:3000)`,
    '',
    '끄기: 서버 창을 닫거나 Ctrl+C. 판 기록은 logs/ 폴더',
    '포트 바꾸기: 환경 변수 PORT (기본 3000)',
    'cloudflared: Cloudflare (Apache-2.0) https://github.com/cloudflare/cloudflared',
    ...(win
      ? [
          '',
          `게임이 느리면:      노트북 (내장+외장 그래픽) 은 start-lan·start-online 이 처음 켜질 때 ${pc} 를 Windows 고성능 GPU 로 등록함 (관리자 권한 없이, 이미 정했으면 그대로).`,
          `                    ${pc} 만 따로 쓰면 Windows 설정 > 시스템 > 디스플레이 > 그래픽 에서 ${pc} 를 '고성능'. 게임 설정 '화질' 자동·높음·보통·낮음, F3 = 성능 표시 (Ctrl+C 복사)`,
          `                    내장 그래픽으로 도는 것 같으면 타이틀 왼쪽 아래·설정 창에 노란 경고와 해결법이 뜸. 판 중 GPU 가 병목이면 3D 해상도가 알아서 0.6~1.0 사이로 조절됨 (설정 '3D 해상도 자동', 끄기 가능).`,
          '                    랙 순간 기록: F3 를 켜면 %APPDATA%\\Godot\\app_userdata\\Tetrafall\\hitches.txt 에 쌓임 — 느렸다면 그 파일도 보내 주세요',
          '',
          '렌더러 시험 (성능 비교용):  start-lan-compat.bat (지금 기본) · start-lan-forward.bat (Forward+) · start-lan-mobile.bat (Mobile)',
          `                    서버와 ${pc} 를 그 렌더러로 같이 켬 (색이 조금 다를 수 있음 — 시험용). 세 개를 각각: 같은 맵의 8명 판 (방 설정에서 봇 7) 을 한 판 하고,`,
          '                    판 중에 F3 → Ctrl+C 로 복사한 한 줄 (첫 줄에 렌더러·GPU 이름이 들어 있음) 을 하나씩 보내 주세요. 타이틀 왼쪽 아래 글자에도 지금 렌더러가 나옴',
          '',
          '새 탱크 시험 (Blender 모델):  start-lan-ext.bat — 서버와 ' + pc + ' 를 --ext 로 같이 켬. 대기실에서 탱크를 고르면 새 모델 (기본 start-lan 은 그대로)',
        ]
      : []),
    '',
  ].join(win ? '\r\n' : '\n');
}

// 서버 한 파일: 자기 완결 + 안에서 압축 + 문화권 자료 빼기 (규칙은 문화권 안 씀 — 숫자·시각 글자는 직접 만듦). ASP.NET 이라 트리밍(PublishTrimmed)은 안 함
export const PUBLISH_FLAGS = ['--self-contained', '-p:PublishSingleFile=true', '-p:EnableCompressionInSingleFile=true', '-p:InvariantGlobalization=true', '-p:DebugType=none', '-p:IsTransformWebConfigDisabled=true'];
// Kestrel 혼자 도니 필요 없는 것: IIS 모듈·web.config·정적 웹 자산 목록
export const PUBLISH_DROP = ['aspnetcorev2_inprocess.dll', 'web.config', 'Tetrafall.Server.staticwebassets.endpoints.json'];

// export_presets.cfg 글에서 이름이 preset 인 묶음의 custom_template/release 만 zip 경로로 바꾼 글 (나머지 글자는 그대로).
// 경로는 / 로 (고도 cfg 문자열에서 \ 는 이스케이프라 윈도우 경로도 / 로 씀). 그 묶음·줄이 없으면 오류
export function withReleaseTemplate(cfg, preset, zip) {
  const nl = cfg.includes('\r\n') ? '\r\n' : '\n';
  const lines = cfg.split(nl);
  const nameAt = lines.findIndex((l, i) => l === `name="${preset}"` && lines.slice(0, i).reverse().find((h) => h.startsWith('['))?.match(/^\[preset\.\d+\]$/));
  if (nameAt < 0) throw new Error(`export_presets.cfg 에 '${preset}' 내보내기 설정이 없음`);
  const id = lines.slice(0, nameAt).reverse().find((h) => h.startsWith('[')).slice(1, -1);
  const optAt = lines.indexOf(`[${id}.options]`);
  if (optAt < 0) throw new Error(`export_presets.cfg 에 [${id}.options] 가 없음`);
  let end = lines.findIndex((l, i) => i > optAt && l.startsWith('['));
  if (end < 0) end = lines.length;
  const at = lines.findIndex((l, i) => i > optAt && i < end && l.startsWith('custom_template/release='));
  if (at < 0) throw new Error(`[${id}.options] 에 custom_template/release 가 없음`);
  lines[at] = `custom_template/release=${JSON.stringify(path.resolve(zip).split(path.sep).join('/'))}`;
  return lines.join(nl);
}

// 웹 템플릿 zip 확인: 있는 파일이고 고도 웹 템플릿 (안에 godot.wasm·godot.js) 인지 — 잘못 주면 내보내기 전에 멈춤
export function checkWebTemplate(zip) {
  if (!fs.existsSync(zip) || !fs.statSync(zip).isFile()) throw new Error(`웹 템플릿 zip 이 없음: ${zip}`);
  const names = zipNames(fs.readFileSync(zip));
  for (const need of ['godot.wasm', 'godot.js']) if (!names.includes(need)) throw new Error(`웹 템플릿 zip 안에 ${need} 가 없음: ${zip}`);
}

// zip 중앙 목록의 파일 이름들 (끝 레코드에서 찾음, zip64 안 봄)
export function zipNames(buf) {
  let e = buf.length - 22;
  while (e >= 0 && buf.readUInt32LE(e) !== 0x06054b50) e--;
  if (e < 0) throw new Error('zip 이 아님');
  const n = buf.readUInt16LE(e + 10);
  let p = buf.readUInt32LE(e + 16);
  const names = [];
  for (let i = 0; i < n; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('zip 중앙 목록이 깨짐');
    const len = buf.readUInt16LE(p + 28);
    names.push(buf.toString('utf8', p + 46, p + 46 + len));
    p += 46 + len + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32);
  }
  return names;
}

// fn 을 도는 동안만 export_presets.cfg 의 preset 템플릿을 zip 으로 (zip 이 없으면 그냥 fn). 끝나면 원래 글 그대로 되돌림.
// 원래 글은 <cfg>.orig 에도 둠 — 내보내기 중 Ctrl+C 로 node 가 바로 죽어 finally 를 못 돌면 다음 실행이 먼저 그것으로 되돌림 (restorePresets)
export const PRESETS_ORIG = '.orig';
export function restorePresets(cfgPath) {
  const orig = cfgPath + PRESETS_ORIG;
  if (!fs.existsSync(orig)) return false;
  fs.writeFileSync(cfgPath, fs.readFileSync(orig));
  fs.rmSync(orig);
  return true;
}
export function withPresetTemplate(cfgPath, preset, zip, fn) {
  if (restorePresets(cfgPath)) console.log(`지난번 끊긴 내보내기의 ${path.basename(cfgPath)} 를 되돌림`);
  if (!zip) return fn();
  const before = fs.readFileSync(cfgPath, 'utf8');
  const changed = withReleaseTemplate(before, preset, zip);
  fs.writeFileSync(cfgPath + PRESETS_ORIG, before);
  fs.writeFileSync(cfgPath, changed);
  try {
    return fn();
  } finally {
    restorePresets(cfgPath);
  }
}

function run(cmd, args, opts = {}) {
  console.log(`> ${cmd} ${args.join(' ')}`);
  const r = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  if (r.error) throw new Error(`${cmd} 실행 실패: ${r.error.message}`);
  if (r.status !== 0) throw new Error(`${cmd} 가 ${r.status} 로 끝남`);
}

// 아주 작은 zip 쓰기 (deflate, 유닉스 권한 비트 — 리눅스 실행 파일이 풀어도 실행되게). 폴더 이름을 zip 안 맨 위 폴더로
// zip 의 MS-DOS 날짜·시각 (2초 단위, 현지 시각) — 날짜 위 16비트, 시각 아래 16비트
export function dosTime(d) {
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2);
  return ((date << 16) | time) >>> 0;
}

export function writeZip(dir, out, when = new Date()) {
  const dos = dosTime(when);
  const files = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) walk(full);
      else files.push(full);
    }
  };
  walk(dir);
  const top = path.basename(dir);
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const f of files) {
    const name = Buffer.from(`${top}/${path.relative(dir, f).split(path.sep).join('/')}`, 'utf8');
    const data = fs.readFileSync(f);
    const comp = zlib.deflateRawSync(data, { level: 6 });
    const crc = zlib.crc32(data);
    const mode = fs.statSync(f).mode & 0o777;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6); // 이름 UTF-8
    local.writeUInt16LE(8, 8); // deflate
    local.writeUInt32LE(dos, 10); // 시각 (묶은 때)
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(comp.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE((3 << 8) | 20, 4); // 만든 곳 유닉스 (권한 비트 읽힘)
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(0x0800, 8);
    cen.writeUInt16LE(8, 10);
    cen.writeUInt32LE(dos, 12);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(comp.length, 20);
    cen.writeUInt32LE(data.length, 24);
    cen.writeUInt16LE(name.length, 28);
    cen.writeUInt32LE(((0o100000 | mode) << 16) >>> 0, 38);
    cen.writeUInt32LE(offset, 42);
    if (offset + 30 + name.length + comp.length > 0xffffffff) throw new Error('zip 이 4GB 넘음 (zip64 안 씀)');
    chunks.push(local, name, comp);
    central.push(cen, name);
    offset += 30 + name.length + comp.length;
  }
  const cenBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(cenBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  fs.writeFileSync(out, Buffer.concat([...chunks, cenBuf, end]));
  return files.length;
}

// 웹 빌드 미리 압축: 파일마다 <파일>.br (brotli 최고) + <파일>.gz (gzip 9) 를 옆에. 서버 StaticFiles.Precompressed 가 Accept-Encoding 따라 골라 줌.
// 작은 파일·이미 압축된 형식은 건너뜀. 돌려줌: 바이트 합 { raw, br, gz } (압축 안 한 파일은 날것 크기로 셈)
export const PRECOMPRESS_EXT = new Set(['.wasm', '.pck', '.js', '.html', '.json', '.css', '.svg', '.txt']);
export const PRECOMPRESS_MIN_BYTES = 1024;
export function precompress(dir) {
  const sum = { raw: 0, br: 0, gz: 0 };
  for (const e of fs.readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (!e.isFile()) continue;
    const f = path.join(e.parentPath ?? e.path, e.name);
    if (f.endsWith('.br') || f.endsWith('.gz')) continue;
    const data = fs.readFileSync(f);
    sum.raw += data.length;
    if (!PRECOMPRESS_EXT.has(path.extname(f).toLowerCase()) || data.length < PRECOMPRESS_MIN_BYTES) {
      sum.br += data.length;
      sum.gz += data.length;
      continue;
    }
    const br = zlib.brotliCompressSync(data, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: data.length } });
    const gz = zlib.gzipSync(data, { level: 9 });
    fs.writeFileSync(`${f}.br`, br);
    fs.writeFileSync(`${f}.gz`, gz);
    sum.br += br.length;
    sum.gz += gz.length;
  }
  return sum;
}

// cloudflared 받기 (W36 2026-11-09): v0.1.13 배포가 GitHub 504 가 이어져 실패 → ① 캐시 ② 몇 번 시도해도 안 되면 그 플랫폼 zip 은 cloudflared 없이 ③ 전체 시간 상한.
export const DL_TRIES = 3;
export const DL_ATTEMPT_MS = 60_000;
export const DL_BUDGET_SEC = 600;
export function cloudflaredUrl(t, tag = process.env.CLOUDFLARED_TAG || '') {
  const u = t.cloudflared.url;
  return tag ? u.replace('/releases/latest/download/', `/releases/download/${tag}/`) : u;
}
// 한 파일 받기. 시도마다 timeout (남은 예산 안에서), 실패하면 2·4초 쉬고 다시. 못 받으면 throw. 받는 도중 끊긴 반쪽 파일은 남기지 않음
export async function download(url, to, { fetchFn = fetch, tries = DL_TRIES, attemptMs = DL_ATTEMPT_MS, deadline = Infinity, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = console.log } = {}) {
  log(`받는 중: ${url}`);
  let last;
  for (let i = 0; i < tries; i++) {
    const left = deadline - Date.now();
    if (left <= 0) throw last ?? new Error('시간 상한(예산)을 넘음');
    try {
      const res = await fetchFn(url, { signal: AbortSignal.timeout(Math.min(attemptMs, left)) });
      if (!res.ok) throw new Error(`${url} → ${res.status}`);
      const buf = Buffer.from(await res.arrayBuffer());
      if (!buf.length) throw new Error(`${url} → 빈 응답`);
      fs.writeFileSync(to, buf);
      fs.chmodSync(to, 0o755);
      return;
    } catch (e) {
      last = e;
      log(`  받기 실패 (${i + 1}/${tries}): ${e.message}${e.cause ? ' · ' + e.cause.message : ''}`);
      if (i < tries - 1) await sleep(Math.min(2000 * 2 ** i, Math.max(0, deadline - Date.now())));
    }
  }
  throw last;
}

// 플랫폼 하나의 cloudflared 를 dest 에 놓음. 돌려줌 { ok, from: 'cache'|'net'|null, error }. 캐시 폴더에 있으면 네트워크 안 씀, 받으면 캐시에 보관.
// 못 받아도 throw 안 함 (required 일 때만) — 호출쪽이 경고하고 계속
export async function fetchCloudflared(t, dest, o = {}) {
  const { cache = null, required = false, ...dl } = o;
  const log = dl.log ?? console.log;
  const cached = cache ? path.join(cache, t.rid, t.cloudflared.name) : null;
  if (cached && fs.existsSync(cached) && fs.statSync(cached).size > 0) {
    fs.copyFileSync(cached, dest);
    fs.chmodSync(dest, 0o755);
    log(`cloudflared 캐시 사용 (${t.rid}): ${cached}`);
    return { ok: true, from: 'cache', error: null };
  }
  try {
    await download(cloudflaredUrl(t), dest, dl);
  } catch (e) {
    fs.rmSync(dest, { force: true });
    if (required) throw e;
    return { ok: false, from: null, error: e.message };
  }
  if (cached) {
    fs.mkdirSync(path.dirname(cached), { recursive: true });
    fs.copyFileSync(dest, cached);
  }
  return { ok: true, from: 'net', error: null };
}

// 릴리스 노트에 덧붙일 글 (cloudflared 를 못 넣은 플랫폼이 있을 때만, 아니면 빈 글)
export function releaseNotes(missingCloudflared) {
  if (!missingCloudflared.length) return '';
  return [
    '### cloudflared 안내',
    `이번 묶음의 ${missingCloudflared.join(', ')} 에는 cloudflared 가 들어 있지 않습니다 (빌드 때 GitHub 에서 받지 못함).`,
    '인터넷 친구와 하려면 직접 설치: Windows `winget install --id Cloudflare.cloudflared`, Linux 는 https://github.com/cloudflare/cloudflared/releases 에서 받아 서버 옆에 `cloudflared` 로 두기. 같은 Wi-Fi (start-lan) 는 영향 없음.',
    '',
  ].join('\n');
}

export function parseArgs(argv) {
  const o = { targets: ['win', 'linux'], out: path.join(root, 'dist'), godot: process.env.GODOT || null, exportGodot: true, cloudflared: false, webTemplate: process.env.GODOT_WEB_TEMPLATE || null, cloudflaredCache: process.env.CLOUDFLARED_CACHE ? path.resolve(process.env.CLOUDFLARED_CACHE) : null, cloudflaredBudgetSec: DL_BUDGET_SEC, requireCloudflared: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--godot') o.godot = argv[++i];
    else if (a === '--targets') o.targets = argv[++i].split(',');
    else if (a === '--out') o.out = path.resolve(argv[++i]);
    else if (a === '--no-godot') o.exportGodot = false;
    else if (a === '--cloudflared') o.cloudflared = true;
    else if (a === '--web-template') o.webTemplate = argv[++i];
    else if (a === '--cloudflared-cache') o.cloudflaredCache = path.resolve(argv[++i]);
    else if (a === '--cloudflared-budget') o.cloudflaredBudgetSec = Number(argv[++i]);
    else if (a === '--require-cloudflared') o.requireCloudflared = true;
    else throw new Error(`모르는 옵션: ${a}`);
  }
  for (const t of o.targets) if (!TARGETS[t]) throw new Error(`모르는 대상: ${t} (win, linux)`);
  if (o.exportGodot && !o.godot) throw new Error('고도 실행 파일을 --godot 또는 GODOT 로 알려 주세요 (이미 내보냈으면 --no-godot)');
  if (o.webTemplate) o.webTemplate = path.resolve(o.webTemplate);
  if (!(o.cloudflaredBudgetSec > 0)) throw new Error('--cloudflared-budget 은 0 보다 큰 초');
  return o;
}

async function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.exportGodot) {
    if (o.webTemplate) {
      checkWebTemplate(o.webTemplate);
      console.log(`웹 템플릿: ${o.webTemplate} (${(fs.statSync(o.webTemplate).size / 1e6).toFixed(1)}MB)`);
    } else console.log('웹 템플릿: 공식 (export_templates)');
    run(o.godot, ['--headless', '--path', clientDir, '--import']);
    const presets = ['Web', ...o.targets.map((t) => TARGETS[t].preset)];
    for (const p of presets) {
      const target = { Web: 'build/web', Windows: 'build/windows', Linux: 'build/linux' }[p];
      fs.mkdirSync(path.join(clientDir, target), { recursive: true });
      const exp = () => run(o.godot, ['--headless', '--path', clientDir, '--export-release', p]);
      if (p === 'Web') withPresetTemplate(path.join(clientDir, 'export_presets.cfg'), 'Web', o.webTemplate, exp);
      else exp();
    }
  }
  fs.mkdirSync(o.out, { recursive: true });
  const missing = [];
  const missingCf = [];
  const cfDeadline = Date.now() + o.cloudflaredBudgetSec * 1000;
  for (const name of o.targets) {
    const t = TARGETS[name];
    const dir = path.join(o.out, `tetrafall-${t.rid}`);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    run('dotnet', ['publish', serverProject, '-c', 'Release', '-r', t.rid, ...PUBLISH_FLAGS, '-o', dir]);
    for (const f of PUBLISH_DROP) fs.rmSync(path.join(dir, f), { force: true });
    const web = path.join(clientDir, 'build', 'web');
    if (fs.existsSync(path.join(web, 'index.html'))) {
      fs.cpSync(web, path.join(dir, 'web'), { recursive: true, filter: (src) => !src.endsWith('.import') }); // 고도 *.import 는 편집기 것
      const z = precompress(path.join(dir, 'web'));
      console.log(`web/ 미리 압축: 날것 ${(z.raw / 1e6).toFixed(1)}MB → br ${(z.br / 1e6).toFixed(1)}MB · gz ${(z.gz / 1e6).toFixed(1)}MB`);
    }
    else missing.push(`${name}: 웹 빌드 (godot/client/build/web)`);
    for (const c of t.client) {
      const src = path.join(clientDir, c);
      if (fs.existsSync(src)) fs.copyFileSync(src, path.join(dir, path.basename(c)));
      else missing.push(`${name}: PC 클라 (${c})`);
    }
    for (const [file, text] of Object.entries(t.scripts)) fs.writeFileSync(path.join(dir, file), text, { mode: 0o755 });
    let hasCf = false;
    if (o.cloudflared) {
      const r = await fetchCloudflared(t, path.join(dir, t.cloudflared.name), { cache: o.cloudflaredCache, required: o.requireCloudflared, deadline: cfDeadline });
      hasCf = r.ok;
      if (!r.ok) {
        missingCf.push(name);
        const msg = `cloudflared 를 못 넣음 (${name}): ${r.error} — 이 묶음은 cloudflared 없이 만듦 (README.txt 에 직접 설치 안내)`;
        console.log(process.env.GITHUB_ACTIONS ? `::warning title=cloudflared 받기 실패 (${name})::${msg}` : `경고: ${msg}`);
      }
    }
    fs.writeFileSync(path.join(dir, 'README.txt'), readme(t, { cloudflared: hasCf || !o.cloudflared }));
    const zip = `${dir}.zip`;
    const n = writeZip(dir, zip);
    console.log(`묶음: ${path.relative(root, zip)} (파일 ${n}개, ${(fs.statSync(zip).size / 1e6).toFixed(1)}MB)`);
  }
  // 릴리스 노트에 덧붙일 글 (워크플로가 있으면 body_path 로 씀) + Actions 요약
  const notes = releaseNotes(missingCf);
  fs.writeFileSync(path.join(o.out, 'release-notes.md'), notes);
  if (notes && process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n${notes}\n`);
  if (missing.length) console.log(`\n빠진 것 (고도로 내보낸 뒤 다시):\n  ${missing.join('\n  ')}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
