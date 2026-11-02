// client/input.js — 포인터 락이 풀릴 때 (Esc) 이모트 바퀴·도움말이 닫히는지 (감사 C2). 가짜 document·window 로.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';

register('./support/client-loader.mjs', import.meta.url);

function setup() {
  const handlers = { doc: {}, win: {} };
  const canvas = { addEventListener() {}, requestPointerLock() {} };
  globalThis.document = { activeElement: null, pointerLockElement: canvas, addEventListener: (n, f) => (handlers.doc[n] = f) };
  globalThis.window = { addEventListener: (n, f) => (handlers.win[n] = f) };
  globalThis.localStorage = { getItem: () => null, setItem() {} };
  return { handlers, canvas };
}

test('G 누른 채 Esc (포인터 락 풀림): 바퀴 닫힘 + 다시 잡으면 시점이 돎', async () => {
  const { handlers, canvas } = setup();
  const { Input } = await import('../client/input.js');
  const sent = [], ui = [], wheel = [];
  const input = new Input(canvas, (a) => sent.push(a));
  input.onUi = (id, on) => ui.push([id, on]);
  input.onWheel = (n) => wheel.push(n);
  handlers.doc.pointerlockchange(); // 잠김
  assert.equal(input.locked, true);
  const emote = input.binds.emote, help = input.binds.help;
  handlers.doc.keydown({ code: emote.replace(/^Key/, 'Key'), repeat: false, preventDefault() {} });
  handlers.doc.keydown({ code: help, repeat: false, preventDefault() {} });
  assert.ok(input.wheel, '바퀴 열림');
  // Esc: 브라우저가 락을 풀고 pointerlockchange 를 쏨 (keyup 은 안 오거나 이미 키가 비워진 뒤)
  document.pointerLockElement = null;
  handlers.doc.pointerlockchange();
  assert.equal(input.wheel, null, '바퀴 닫힘');
  assert.equal(wheel.at(-1), null, '바퀴 표시도 닫으라고 알림');
  assert.deepEqual(ui.filter(([id]) => id === 'help').at(-1), ['help', false], '도움말 닫힘');
  assert.equal(input.keys.size, 0);
  // 다시 잡고 마우스 이동 → 시점이 돎 (wheel 이 안 가로챔)
  document.pointerLockElement = canvas;
  handlers.doc.pointerlockchange();
  const yaw0 = input.yaw;
  handlers.doc.mousemove({ movementX: 50, movementY: 0 });
  assert.notEqual(input.yaw, yaw0);
  // 늦게 온 keyup 은 아무 일도 안 함
  handlers.doc.keyup({ code: emote });
  assert.equal(sent.length, 0);
});
