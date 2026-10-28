// 인원·화면 폭에 따른 HUD 배치 (shared/hud-layout.js): 8명이어도 아래 판이 한 줄·화면 안, 대기실 판이 관리 칸과 안 겹침, 머리 위 이름표 줄이기
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { cardLayout, lobbyPlace, labelSizes } from '../shared/hud-layout.js';

test('아래 플레이어 판: 2~8명 × 1280·960·800·640 폭에서 한 줄로 화면 안', () => {
  for (const W of [1280, 960, 800, 640]) {
    for (let n = 2; n <= C.MAX_PLAYERS; n++) {
      const L = cardLayout(n, W);
      assert.ok(L.total <= W - 2 * C.HUD_CARD_MARGIN, `${W}px ${n}명: 합 ${L.total}`);
      assert.ok(L.w >= C.HUD_CARD_MIN_W && L.w <= C.HUD_CARD_W, `${W}px ${n}명: 폭 ${L.w}`);
      assert.ok(L.gap >= 0);
    }
  }
});

test('4명까지 큰 판 그대로 (1280·960), 5명부터 작은 판', () => {
  for (const W of [1280, 960]) for (let n = 2; n <= 4; n++) assert.deepEqual([cardLayout(n, W).w, cardLayout(n, W).compact], [C.HUD_CARD_W, false], `${W} ${n}명`);
  for (let n = C.HUD_CARD_COMPACT_FROM; n <= C.MAX_PLAYERS; n++) assert.equal(cardLayout(n, 1280).compact, true);
  assert.equal(cardLayout(8, 1280).w, C.HUD_CARD_W, '1280 은 8명도 최대 폭');
  assert.ok(cardLayout(8, 960).w < C.HUD_CARD_W, '960 8명은 줄임');
});

test('대기실: 관리 칸과 안 겹치면 가운데 그대로, 겹치면 비킴, 모자라면 폭을 줄임 (화면 밖으로 안 나감)', () => {
  assert.deepEqual(lobbyPlace(1280, 640, 223), { cx: 640, maxW: null });
  assert.deepEqual(lobbyPlace(1280, 640, 0), { cx: 640, maxW: null }); // 관리 칸 없음 (호스트 아님)
  for (const [W, cw, hr] of [[960, 520, 223], [800, 480, 223], [800, 600, 223], [640, 500, 200]]) {
    const p = lobbyPlace(W, cw, hr);
    const w = p.maxW ?? cw;
    assert.ok(p.cx - w / 2 >= hr + C.HUD_LOBBY_GAP - 0.5, `${W}: 관리 칸 오른쪽으로`);
    assert.ok(p.cx + w / 2 <= W - C.HUD_CARD_MARGIN + 0.5, `${W}: 오른쪽 화면 안`);
  }
});

test('머리 위 이름표: 가까운 LABEL_FULL_N 명만 원래 크기, 나머지 작고 흐리게', () => {
  const d = [9, 3, 15, 1, 7, 12, 5, 20];
  const out = labelSizes(d);
  const full = out.filter((o) => o.scale === 1).length;
  assert.equal(full, C.LABEL_FULL_N);
  const sorted = d.map((x, i) => [x, i]).sort((a, b) => a[0] - b[0]);
  sorted.forEach(([, i], r) => assert.equal(out[i].scale, r < C.LABEL_FULL_N ? 1 : C.LABEL_FAR_SCALE));
  assert.ok(C.LABEL_FAR_SCALE < 1 && C.LABEL_FAR_OPACITY < 1);
  assert.deepEqual(labelSizes([4, 2]), [{ scale: 1, opacity: 1 }, { scale: 1, opacity: 1 }], '4명 이하면 그대로');
});
