// 배포 묶음 (G7): C# 서버 + 고도 웹 빌드 + 고도 PC 클라를 한 폴더로 → zip. 받는 PC 에는 .NET·node·고도 필요 없음.
// 실행 (레포 뿌리에서): node godot/server/tools/package.mjs [--godot <고도 4.7.2 실행 파일>] [--targets win,linux] [--cloudflared] [--no-godot]
//   --godot       : 고도 실행 파일 (없으면 환경 변수 GODOT). 웹·PC 클라를 내보냄 (템플릿: godot/client/README.md G7)
//   --no-godot    : 내보내기 건너뛰고 이미 있는 godot/client/build/ 를 씀 (없는 건 빠짐 — 안내만)
//   --cloudflared : cloudflared 를 GitHub 에서 받아 서버 옆에 넣음 (그러면 --online 이 설치 없이 됨)
//   --out <폴더>  : 기본 dist/
// 결과: dist/tetrafall-win-x64/ (+ .zip), dist/tetrafall-linux-x64/ (+ .zip)
//   Tetrafall.Server(.exe)   서버 (자기 완결형 한 파일)
//   web/                     고도 웹 빌드 (+ 파일마다 .br·.gz 미리 압축) → 서버가 /play/ 로, / 는 /play/ 로 넘겨줌
//   tetrafall(.exe / .x86_64) 고도 PC 클라 (기본 ws://127.0.0.1:3000 = 이 PC 서버)
//   start-lan / start-online (.bat / .sh), README.txt, cloudflared(.exe) (--cloudflared 일 때)
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const clientDir = path.join(root, 'godot', 'client');
const serverProject = path.join(root, 'godot', 'server', 'src', 'Tetrafall.Server');

export const TARGETS = {
  win: {
    rid: 'win-x64',
    server: 'Tetrafall.Server.exe',
    preset: 'Windows',
    client: ['build/windows/tetrafall.exe'],
    cloudflared: { url: 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe', name: 'cloudflared.exe' },
    scripts: {
      'start-lan.bat': '@echo off\r\ncd /d "%~dp0"\r\nTetrafall.Server.exe\r\npause\r\n',
      'start-online.bat': '@echo off\r\ncd /d "%~dp0"\r\nTetrafall.Server.exe --online\r\npause\r\n',
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
    },
  },
};

export function readme(t) {
  const win = t.rid.startsWith('win');
  const ext = win ? 'bat' : 'sh';
  const pc = path.basename(t.client[0]);
  return [
    'Tetrafall (고도 클라 + C# 서버)',
    '',
    `같은 Wi-Fi 친구와:  start-lan.${ext} 를 켜고, 창에 뜬 "다른 PC에서: http://…" 주소를 친구에게`,
    `인터넷 친구와:      start-online.${ext} 를 켜고, 창에 뜬 https://….trycloudflare.com 주소를 친구에게 (클립보드에 복사돼 있음)`,
    '                    cloudflared 가 이 폴더에 없으면: winget install --id Cloudflare.cloudflared',
    '',
    `나(서버 PC)는:      ${pc} 를 켜면 이 PC 서버에 바로 붙음 (아니면 브라우저로 http://localhost:3000)`,
    '친구는:             받은 주소를 크롬·엣지로 열기 (설치 없음). 방 코드는 대기실 "링크 복사"',
    `친구가 PC 클라로:   ${pc} -- --server wss://….trycloudflare.com   (같은 Wi-Fi 면 ws://서버IP:3000)`,
    '',
    '끄기: 서버 창을 닫거나 Ctrl+C. 판 기록은 logs/ 폴더',
    '포트 바꾸기: 환경 변수 PORT (기본 3000)',
    'cloudflared: Cloudflare (Apache-2.0) https://github.com/cloudflare/cloudflared',
    '',
  ].join(win ? '\r\n' : '\n');
}

function run(cmd, args, opts = {}) {
  console.log(`> ${cmd} ${args.join(' ')}`);
  const r = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  if (r.error) throw new Error(`${cmd} 실행 실패: ${r.error.message}`);
  if (r.status !== 0) throw new Error(`${cmd} 가 ${r.status} 로 끝남`);
}

// 아주 작은 zip 쓰기 (deflate, 유닉스 권한 비트 — 리눅스 실행 파일이 풀어도 실행되게). 폴더 이름을 zip 안 맨 위 폴더로
export function writeZip(dir, out) {
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
    local.writeUInt32LE(0, 10); // 시각 (0 = 1980)
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

async function download(url, to) {
  console.log(`받는 중: ${url}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url} → ${res.status}`);
  fs.writeFileSync(to, Buffer.from(await res.arrayBuffer()));
  fs.chmodSync(to, 0o755);
}

function parseArgs(argv) {
  const o = { targets: ['win', 'linux'], out: path.join(root, 'dist'), godot: process.env.GODOT || null, exportGodot: true, cloudflared: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--godot') o.godot = argv[++i];
    else if (a === '--targets') o.targets = argv[++i].split(',');
    else if (a === '--out') o.out = path.resolve(argv[++i]);
    else if (a === '--no-godot') o.exportGodot = false;
    else if (a === '--cloudflared') o.cloudflared = true;
    else throw new Error(`모르는 옵션: ${a}`);
  }
  for (const t of o.targets) if (!TARGETS[t]) throw new Error(`모르는 대상: ${t} (win, linux)`);
  if (o.exportGodot && !o.godot) throw new Error('고도 실행 파일을 --godot 또는 GODOT 로 알려 주세요 (이미 내보냈으면 --no-godot)');
  return o;
}

async function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.exportGodot) {
    run(o.godot, ['--headless', '--path', clientDir, '--import']);
    const presets = ['Web', ...o.targets.map((t) => TARGETS[t].preset)];
    for (const p of presets) {
      const target = { Web: 'build/web', Windows: 'build/windows', Linux: 'build/linux' }[p];
      fs.mkdirSync(path.join(clientDir, target), { recursive: true });
      run(o.godot, ['--headless', '--path', clientDir, '--export-release', p]);
    }
  }
  fs.mkdirSync(o.out, { recursive: true });
  const missing = [];
  for (const name of o.targets) {
    const t = TARGETS[name];
    const dir = path.join(o.out, `tetrafall-${t.rid}`);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    run('dotnet', ['publish', serverProject, '-c', 'Release', '-r', t.rid, '--self-contained', '-p:PublishSingleFile=true', '-p:DebugType=none', '-o', dir]);
    const web = path.join(clientDir, 'build', 'web');
    if (fs.existsSync(path.join(web, 'index.html'))) {
      fs.cpSync(web, path.join(dir, 'web'), { recursive: true });
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
    fs.writeFileSync(path.join(dir, 'README.txt'), readme(t));
    if (o.cloudflared) await download(t.cloudflared.url, path.join(dir, t.cloudflared.name));
    const zip = `${dir}.zip`;
    const n = writeZip(dir, zip);
    console.log(`묶음: ${path.relative(root, zip)} (파일 ${n}개, ${(fs.statSync(zip).size / 1e6).toFixed(1)}MB)`);
  }
  if (missing.length) console.log(`\n빠진 것 (고도로 내보낸 뒤 다시):\n  ${missing.join('\n  ')}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
