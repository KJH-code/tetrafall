// 고도판 배포 묶음 (godot/server/tools/package.mjs) 의 웹 템플릿 옵션 (W5 2026-11-02 재혁: 직접 빌드한 웹 템플릿을 배포에도)
// --web-template <zip> / GODOT_WEB_TEMPLATE: 웹 내보내기 동안만 export_presets.cfg 웹 custom_template/release 를 바꾸고 끝나면 되돌림
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { withReleaseTemplate, withPresetTemplate, restorePresets, PRESETS_ORIG, checkWebTemplate, zipNames, parseArgs, writeZip } from '../godot/server/tools/package.mjs';

const CFG = path.resolve('godot/client/export_presets.cfg');

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'tf-pkg-'));
}

// 이름만 다른 파일을 맨 위에 담은 작은 zip (저장 방식) — 고도 웹 템플릿 흉내
function flatZip(out, names) {
  const parts = [];
  const cen = [];
  let off = 0;
  for (const n of names) {
    const name = Buffer.from(n);
    const data = Buffer.from('x');
    const crc = zlib.crc32(data);
    const loc = Buffer.alloc(30);
    loc.writeUInt32LE(0x04034b50, 0);
    loc.writeUInt16LE(20, 4);
    loc.writeUInt32LE(crc, 14);
    loc.writeUInt32LE(1, 18);
    loc.writeUInt32LE(1, 22);
    loc.writeUInt16LE(name.length, 26);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(20, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt32LE(crc, 16);
    c.writeUInt32LE(1, 20);
    c.writeUInt32LE(1, 24);
    c.writeUInt16LE(name.length, 28);
    c.writeUInt32LE(off, 42);
    parts.push(loc, name, data);
    cen.push(c, name);
    off += 30 + name.length + 1;
  }
  const cb = Buffer.concat(cen);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(names.length, 8);
  end.writeUInt16LE(names.length, 10);
  end.writeUInt32LE(cb.length, 12);
  end.writeUInt32LE(off, 16);
  fs.writeFileSync(out, Buffer.concat([...parts, cb, end]));
}

test('웹 템플릿: 실제 export_presets.cfg 에서 웹 custom_template/release 한 줄만 바뀜 (PC 설정·debug 그대로)', () => {
  const before = fs.readFileSync(CFG, 'utf8');
  const after = withReleaseTemplate(before, 'Web', '/w/tpl.zip');
  const a = before.split('\n');
  const b = after.split('\n');
  assert.equal(a.length, b.length);
  const diff = a.map((l, i) => [i, l, b[i]]).filter(([, x, y]) => x !== y);
  assert.equal(diff.length, 1);
  assert.equal(diff[0][2], 'custom_template/release="/w/tpl.zip"');
  const webOpts = a.indexOf('[preset.0.options]');
  const nextPreset = a.findIndex((l, i) => i > webOpts && l.startsWith('[preset.'));
  assert.ok(diff[0][0] > webOpts && diff[0][0] < nextPreset, '웹 [preset.N.options] 안');
  // 커밋된 cfg 는 빈 값 (기계마다 경로가 달라 커밋 안 함)
  assert.equal(a[diff[0][0]], 'custom_template/release=""');
});

test('웹 템플릿: 상대 경로는 절대로, CRLF 글은 CRLF 그대로, 없는 설정은 오류', () => {
  const cfg = ['[preset.0]', '', 'name="Linux"', '', '[preset.0.options]', '', 'custom_template/release=""', '', '[preset.1]', '', 'name="Web"', '', '[preset.1.options]', '', 'custom_template/debug=""', 'custom_template/release=""', ''].join('\r\n');
  const out = withReleaseTemplate(cfg, 'Web', 'tpl.zip');
  assert.ok(out.includes(`custom_template/release=${JSON.stringify(path.resolve('tpl.zip'))}\r\n`));
  assert.ok(out.startsWith('[preset.0]\r\n\r\nname="Linux"\r\n\r\n[preset.0.options]\r\n\r\ncustom_template/release=""\r\n'), 'Linux 는 그대로');
  assert.equal(out.split('\r\n').length, cfg.split('\r\n').length);
  assert.throws(() => withReleaseTemplate(cfg, 'Windows', 'a.zip'), /Windows/);
  assert.throws(() => withReleaseTemplate('[preset.0]\nname="Web"\n', 'Web', 'a.zip'), /options/);
});

test('웹 템플릿: 내보내는 동안만 바뀌고 끝나면 (오류여도) 같은 글로 되돌림, 안 주면 손 안 댐', () => {
  const dir = tmpDir();
  const cfg = path.join(dir, 'export_presets.cfg');
  const orig = fs.readFileSync(CFG, 'utf8');
  fs.writeFileSync(cfg, orig);
  let seen = null;
  const r = withPresetTemplate(cfg, 'Web', '/w/tpl.zip', () => {
    seen = fs.readFileSync(cfg, 'utf8');
    assert.ok(fs.existsSync(cfg + PRESETS_ORIG), '원래 글을 옆에 둠');
    return 7;
  });
  assert.equal(r, 7);
  assert.ok(seen.includes('custom_template/release="/w/tpl.zip"'));
  assert.equal(fs.readFileSync(cfg, 'utf8'), orig);
  assert.ok(!fs.existsSync(cfg + PRESETS_ORIG));
  assert.throws(() => withPresetTemplate(cfg, 'Web', '/w/tpl.zip', () => { throw new Error('내보내기 실패'); }), /내보내기 실패/);
  assert.equal(fs.readFileSync(cfg, 'utf8'), orig);
  assert.ok(!fs.existsSync(cfg + PRESETS_ORIG));
  // 템플릿 없음 = 공식 템플릿: 파일을 건드리지 않음
  withPresetTemplate(cfg, 'Web', null, () => assert.equal(fs.readFileSync(cfg, 'utf8'), orig));
  assert.ok(!fs.existsSync(cfg + PRESETS_ORIG));
  fs.rmSync(dir, { recursive: true });
});

test('웹 템플릿: 지난 실행이 Ctrl+C 로 끊겨 남은 .orig 는 다음 실행이 먼저 되돌림', () => {
  const dir = tmpDir();
  const cfg = path.join(dir, 'export_presets.cfg');
  const orig = fs.readFileSync(CFG, 'utf8');
  fs.writeFileSync(cfg + PRESETS_ORIG, orig);
  fs.writeFileSync(cfg, withReleaseTemplate(orig, 'Web', '/old/tpl.zip'));
  withPresetTemplate(cfg, 'Web', null, () => assert.equal(fs.readFileSync(cfg, 'utf8'), orig));
  assert.ok(!fs.existsSync(cfg + PRESETS_ORIG));
  assert.equal(restorePresets(cfg), false, '되돌릴 것 없으면 false');
  fs.rmSync(dir, { recursive: true });
});

test('웹 템플릿 zip 확인: 맨 위에 godot.wasm·godot.js 가 있어야 함', () => {
  const dir = tmpDir();
  const good = path.join(dir, 'good.zip');
  flatZip(good, ['godot.js', 'godot.wasm', 'godot.html']);
  assert.deepEqual(zipNames(fs.readFileSync(good)), ['godot.js', 'godot.wasm', 'godot.html']);
  checkWebTemplate(good);
  const noWasm = path.join(dir, 'nowasm.zip');
  flatZip(noWasm, ['godot.js']);
  assert.throws(() => checkWebTemplate(noWasm), /godot\.wasm/);
  // 폴더째 묶은 zip (이름 앞에 폴더) 은 고도 템플릿이 아님
  fs.mkdirSync(path.join(dir, 'tpl'));
  fs.writeFileSync(path.join(dir, 'tpl', 'godot.wasm'), 'x');
  fs.writeFileSync(path.join(dir, 'tpl', 'godot.js'), 'x');
  writeZip(path.join(dir, 'tpl'), path.join(dir, 'nested.zip'));
  assert.throws(() => checkWebTemplate(path.join(dir, 'nested.zip')), /godot\.wasm/);
  assert.throws(() => checkWebTemplate(path.join(dir, 'none.zip')), /없음/);
  assert.throws(() => zipNames(Buffer.from('not a zip at all, definitely not')), /zip 이 아님/);
  fs.rmSync(dir, { recursive: true });
});

test('옵션: --web-template 이 GODOT_WEB_TEMPLATE 보다 먼저, 상대 경로는 절대로, 둘 다 없으면 공식 (null)', () => {
  const env = process.env.GODOT_WEB_TEMPLATE;
  try {
    delete process.env.GODOT_WEB_TEMPLATE;
    assert.equal(parseArgs(['--no-godot']).webTemplate, null);
    process.env.GODOT_WEB_TEMPLATE = '/env/tpl.zip';
    assert.equal(parseArgs(['--no-godot']).webTemplate, '/env/tpl.zip');
    assert.equal(parseArgs(['--no-godot', '--web-template', 'rel/tpl.zip']).webTemplate, path.resolve('rel/tpl.zip'));
  } finally {
    if (env === undefined) delete process.env.GODOT_WEB_TEMPLATE;
    else process.env.GODOT_WEB_TEMPLATE = env;
  }
});
