// 테스트용: 진짜 서버 프로세스 (server/index.js) 를 빈 포트(PORT=0)로 띄우고 시작 줄에서 실제 포트를 읽음.
// 무작위 포트 충돌·느린 기계 대기 시간에 흔들리지 않게 (2026-10-30). *.test.js 가 아니라 npm test 가 따로 돌리지 않음
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ipc: npm run online 처럼 IPC 채널을 엶. 돌려주는 것: { srv, port, out() (지금까지 출력), until(re) (출력에 re 가 나올 때까지), stop() }
export async function startServer({ ipc = false, timeoutMs = 30000 } = {}) {
  const srv = spawn(process.execPath, [path.join(ROOT, 'server', 'index.js')], {
    stdio: ['ignore', 'pipe', 'pipe', ...(ipc ? ['ipc'] : [])],
    env: { ...process.env, PORT: '0' },
  });
  let out = '';
  srv.stdout.on('data', (b) => (out += b));
  srv.stderr.on('data', (b) => (out += b));
  const until = (re, ms = timeoutMs) =>
    new Promise((resolve, reject) => {
      const t0 = Date.now();
      const check = () => {
        if (re.test(out)) return resolve(out.match(re));
        if (srv.exitCode !== null) return reject(new Error(`서버가 꺼짐 (${srv.exitCode}):\n${out}`));
        if (Date.now() - t0 > ms) return reject(new Error(`${ms}ms 안에 ${re} 안 나옴:\n${out}`));
        setTimeout(check, 20);
      };
      check();
    });
  const stop = () => {
    if (srv.exitCode === null) srv.kill();
  };
  try {
    const m = await until(/실행 중 \(포트 (\d+),/);
    return { srv, port: Number(m[1]), out: () => out, until, stop };
  } catch (err) {
    stop();
    throw err;
  }
}
