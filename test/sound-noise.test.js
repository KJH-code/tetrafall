// client/sound.js noise(): 1초 잡음 버퍼 + 시작 위치 0~0.5초 → 0.5초보다 긴 합성 소리가 잘리지 않게 loop (감사 C5). 가짜 오디오 문맥으로.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';

register('./support/client-loader.mjs', import.meta.url);
const { Sound } = await import('../client/sound.js');

function fakeCtx(made) {
  const param = () => ({ value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} });
  const node = () => ({ connect: (n) => n, Q: param(), frequency: param(), gain: param() });
  return {
    createBufferSource: () => { const s = { ...node(), loop: false, start() {}, stop() {} }; made.push(s); return s; },
    createBiquadFilter: node,
    createGain: node,
  };
}

test('noise(): 버퍼보다 길 수 있는 소리는 loop 로 돎', () => {
  const made = [];
  const snd = Object.create(Sound.prototype);
  snd.ctx = fakeCtx(made);
  snd.noiseBuf = { duration: 1 };
  snd.now = () => 0;
  snd.master = {};
  snd.noise({ dur: 1.8, freq: 300 }); // 파도·쏴아 (config 길이 1.4~1.8초)
  assert.equal(made.length, 1);
  assert.equal(made[0].loop, true);
  assert.ok(made[0].buffer === snd.noiseBuf);
});
