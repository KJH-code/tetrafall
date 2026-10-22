// npm run online (tools/online.js): cloudflared 출력에서 친구에게 줄 주소를 찾는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tunnelUrl } from '../tools/online.js';

test('터널 주소: cloudflared 안내 상자에서 찾고, 실패 메시지의 api 주소는 무시', () => {
  const ok = [
    '2026-10-22T13:18:41Z INF Requesting new quick Tunnel on trycloudflare.com...',
    '2026-10-22T13:18:43Z INF +--------------------------------------------------------------------------------------------+',
    '2026-10-22T13:18:43Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |',
    '2026-10-22T13:18:43Z INF |  https://pottery-sense-quarterly-lightweight.trycloudflare.com                             |',
  ].join('\n');
  assert.equal(tunnelUrl(ok), 'https://pottery-sense-quarterly-lightweight.trycloudflare.com');
  const fail =
    'failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel": dial tcp: lookup api.trycloudflare.com: no such host';
  assert.equal(tunnelUrl(fail), null);
  assert.equal(tunnelUrl('see https://www.cloudflare.com/website-terms/'), null);
});
