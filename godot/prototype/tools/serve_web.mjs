// 웹 내보내기(build/web) 정적 서빙 (gzip). 고도 웹 단일 스레드 판이라 COOP/COEP 헤더는 필요 없음.
// 실행: node godot/prototype/tools/serve_web.mjs [포트 8060]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../build/web');
const port = Number(process.argv[2] || 8060);
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const cache = new Map(); // 파일 → gzip (한 번만 압축)

http
  .createServer((req, res) => {
    const name = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const file = path.join(root, name === '/' ? 'index.html' : name);
    if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404).end();
      return;
    }
    const headers = { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' };
    if (/\bgzip\b/.test(req.headers['accept-encoding'] || '')) {
      if (!cache.has(file)) cache.set(file, zlib.gzipSync(fs.readFileSync(file), { level: 9 }));
      res.writeHead(200, { ...headers, 'Content-Encoding': 'gzip' }).end(cache.get(file));
    } else {
      res.writeHead(200, headers).end(fs.readFileSync(file));
    }
  })
  .listen(port, () => console.log(`웹: http://127.0.0.1:${port}/  (${root})`));
