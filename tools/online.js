// 인터넷 대전: 이 PC 에서 서버를 켜고 Cloudflare 터널로 https 주소를 받아 친구에게 준다.
// 실행: npm run online   (cloudflared 가 깔려 있어야 함. 없으면 설치 방법을 띄우고 서버만 켬)
// 터널 주소(https://….trycloudflare.com)는 켤 때마다 바뀐다. 계정·도메인 필요 없음.
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../shared/config.js';

// cloudflared 출력에서 터널 주소 찾기. 주소는 단어-단어-….trycloudflare.com
// (실패 메시지의 https://api.trycloudflare.com 을 집지 않게 하이픈이 있는 것만)
export function tunnelUrl(text) {
  const m = String(text).match(/https:\/\/[a-z0-9]+(?:-[a-z0-9]+)+\.trycloudflare\.com/);
  return m ? m[0] : null;
}

const INSTALL = [
  'cloudflared 가 없어 터널을 못 켰습니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다.',
  '설치 (한 번만):',
  '  Windows : winget install --id Cloudflare.cloudflared   (설치 뒤 터미널을 새로 열기)',
  '  macOS   : brew install cloudflared',
  '  그 밖   : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/',
  '설치하고 다시 npm run online',
].join('\n');

function banner(url) {
  const lines = ['친구에게 이 주소를 보내세요 (켤 때마다 바뀜):', '', `  ${url}`, '', '방을 만든 뒤 대기 화면의 "링크 복사" 로 그 방 주소를 보내도 됨'];
  const w = Math.max(...lines.map((l) => l.length)) + 4;
  const bar = '='.repeat(w);
  return ['', bar, ...lines.map((l) => `  ${l}`), bar, ''].join('\n');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const port = Number(process.env.PORT) || C.PORT;
  const children = [];
  const stopAll = () => {
    for (const c of children) if (c.exitCode === null) c.kill();
  };
  process.on('SIGINT', () => {
    stopAll();
    process.exit(0);
  });

  const server = spawn(process.execPath, [path.join(root, 'server', 'index.js')], { stdio: 'inherit', env: { ...process.env, PORT: String(port) } });
  children.push(server);
  server.on('exit', (code) => {
    console.log(`서버가 꺼짐 (코드 ${code}). 터널도 끕니다`);
    stopAll();
    process.exit(code ?? 0);
  });

  const cf = spawn(process.env.CLOUDFLARED || 'cloudflared', ['tunnel', '--no-autoupdate', '--url', `http://localhost:${port}`], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  children.push(cf);
  let shown = false;
  let tail = '';
  const onData = (buf) => {
    if (shown) return;
    tail = (tail + buf.toString()).slice(-4000);
    const url = tunnelUrl(tail);
    if (url) {
      shown = true;
      console.log(banner(url));
    }
  };
  cf.stdout.on('data', onData);
  cf.stderr.on('data', onData);
  cf.on('error', (err) => {
    if (err.code === 'ENOENT') console.log(`\n${INSTALL}\n`);
    else console.log(`터널 실행 실패: ${err.message}`);
  });
  cf.on('exit', (code) => {
    if (code !== null && code !== 0) console.log(`터널이 꺼짐 (코드 ${code}). 마지막 출력:\n${tail.slice(-800)}`);
  });
}
