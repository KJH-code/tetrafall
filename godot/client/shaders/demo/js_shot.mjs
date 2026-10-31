// G3 확인: JS 판 (three, client/toon.js + OutlineEffect) 으로 g3_demo 와 같은 장면을 그려 스샷. 레포 뿌리에서 node godot/client/shaders/demo/js_shot.mjs js_demo.html 출력.png
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../../..");
const here = path.dirname(new URL(import.meta.url).pathname); // JS 판 비교 장면 (js_demo.html) 을 three 로 그려 스샷: node godot/client/shaders/demo/js_shot.mjs js_demo.html 출력.png
const page = process.argv[2] || 'demo.html', out = process.argv[3], q = process.argv[4] || '';
const srv = http.createServer((req, res) => {
  let u = decodeURIComponent(req.url.split('?')[0]);
  let f = fs.existsSync(path.join(here, u)) && u.length > 1 ? path.join(here, u) : u.startsWith('/vendor/jsm/') ? path.join(root, 'node_modules/three/examples/jsm', u.slice(12)) : u === '/vendor/three.module.js' ? path.join(root, 'node_modules/three/build/three.module.js') : u.startsWith('/shared/') ? path.join(root, u) : path.join(root, 'client', u);
  if (u === '/world_demo.js') { res.writeHead(200, { 'content-type': 'text/javascript' }); return res.end(fs.readFileSync(path.join(root, 'client/world.js'), 'utf8') + '\nexport { floorTexture };'); }
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : 'text/html' }); fs.createReadStream(f).pipe(res);
}).listen(0);
const port = srv.address().port;
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
p.on('pageerror', (e) => console.log('ERR', e.message));
await p.goto(`http://localhost:${port}/${page}${q}`);
await p.waitForFunction(() => window.done, null, { timeout: 60000 });
await p.screenshot({ path: out });
await b.close(); srv.close();
