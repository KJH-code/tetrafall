// npm run online 의 C# 서버 판 (S6): C# 서버(godot/server)를 켜고 Cloudflare 터널로 https 주소를 받아 친구에게 준다.
// 실행 (레포 뿌리에서): node godot/server/tools/online-cs.mjs   (dotnet·cloudflared 가 깔려 있어야 함, PORT 환경 변수로 포트)
// 터널 지키기·주소 찾기·안내 글은 tools/online.js 것을 그대로 씀. 다른 점: 터널 주소를 서버에 알리는 길이 node IPC 대신 표준 입력 한 줄
// ({"type":"publicUrl","url":…}, C# Program.cs 가 TF_STDIN_CONTROL=1 일 때 읽음). JS tools/online.js 는 얼어 있어 손대지 않음
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../../../shared/config.js';
import { TunnelKeeper, probeUrl, banner, clipboardCommand } from '../../../tools/online.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const project = path.join(here, '../src/Tetrafall.Server');

const INSTALL = [
  'cloudflared 가 없어 터널을 못 켰습니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다.',
  '설치 (한 번만):',
  '  Windows : winget install --id Cloudflare.cloudflared   (설치 뒤 터미널을 새로 열기)',
  '  macOS   : brew install cloudflared',
  '  그 밖   : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/',
  '설치하고 다시 node godot/server/tools/online-cs.mjs',
].join('\n');

function copyToClipboard(text) {
  const cmd = clipboardCommand();
  if (!cmd) return Promise.resolve(false);
  return new Promise((resolve) => {
    try {
      const c = spawn(cmd[0], cmd[1], { stdio: ['pipe', 'ignore', 'ignore'] });
      c.on('error', () => resolve(false));
      c.on('exit', (code) => resolve(code === 0));
      c.stdin.end(text);
    } catch {
      resolve(false);
    }
  });
}

// C# 서버 켜기: 빌드해 둔 dll 이 있으면 그것 (빠름), 없으면 dotnet run (처음엔 빌드하느라 몇 초)
export function serverCommand(env = process.env) {
  const dll = env.TF_SERVER_DLL || path.join(project, 'bin', 'Release', 'net10.0', 'Tetrafall.Server.dll');
  if (fs.existsSync(dll)) return ['dotnet', [dll]];
  return ['dotnet', ['run', '--project', project, '-c', 'Release']];
}

// 서버에 터널 주소 알리기 (표준 입력 한 줄)
export function publicUrlLine(url) {
  return `${JSON.stringify({ type: 'publicUrl', url })}\n`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT) || C.PORT;
  let keeper = null;
  const children = [];
  const stopAll = () => {
    if (keeper) keeper.stop();
    for (const c of children) if (c.exitCode === null) c.kill();
  };
  for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, () => {
      stopAll();
      process.exit(0);
    });
  }

  const [cmd, args] = serverCommand();
  const server = spawn(cmd, args, { cwd: root, stdio: ['pipe', 'inherit', 'inherit'], env: { ...process.env, PORT: String(port), TF_ROOT: root, TF_STDIN_CONTROL: '1' } });
  children.push(server);
  server.on('error', (err) => {
    console.log(err.code === 'ENOENT' ? 'dotnet 이 없습니다 (.NET 10 SDK: godot/server/README.md)' : `C# 서버 실행 실패: ${err.message}`);
    stopAll();
    process.exit(1);
  });
  server.on('exit', (code) => {
    console.log(`서버가 꺼짐 (코드 ${code}). 터널도 끕니다`);
    stopAll();
    process.exit(code ?? 0);
  });

  keeper = new TunnelKeeper({
    spawnTunnel: () => {
      const cf = spawn(process.env.CLOUDFLARED || 'cloudflared', ['tunnel', '--no-autoupdate', '--url', `http://localhost:${port}`], { stdio: ['ignore', 'pipe', 'pipe'] });
      cf.on('error', (err) => {
        if (err.code === 'ENOENT') {
          console.log(`\n${INSTALL}\n`);
          keeper.stop();
        } else console.log(`터널 실행 실패: ${err.message}`);
      });
      return cf;
    },
    probe: (url) => probeUrl(url),
    onStatus: (kind, text, out) => {
      console.log(`[터널] ${text}`);
      if (kind === 'give-up' && out) console.log(String(out).slice(-800));
    },
    onReady: (url) => {
      if (server.stdin.writable) server.stdin.write(publicUrlLine(url));
      copyToClipboard(url).then((copied) => console.log(banner(url, copied)));
    },
  });
  keeper.run();
}
