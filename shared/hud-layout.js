// 인원·화면 폭에 따른 HUD 배치 계산: DOM·three.js 없는 순수 계산 — client/main.js·render.js 가 쓰고 test/hud-layout.test.js 가 검증한다.
import { CONFIG as C } from './config.js';

// 아래 플레이어 판 n 장을 폭 viewW 화면에 한 줄로: 판 폭·간격·작은 판 여부·글자 배율
export function cardLayout(n, viewW) {
  const count = Math.max(1, n);
  let gap = C.HUD_CARD_GAP;
  const room = viewW - 2 * C.HUD_CARD_MARGIN;
  let w = Math.floor((room - gap * (count - 1)) / count);
  w = Math.min(C.HUD_CARD_W, w);
  if (w < C.HUD_CARD_MIN_W) {
    // 최소 폭으로 두고 간격을 줄여 한 줄에 넣음 (그래도 모자라면 간격 0)
    w = C.HUD_CARD_MIN_W;
    gap = count > 1 ? Math.max(0, Math.floor((room - w * count) / (count - 1))) : 0;
  }
  const compact = count >= C.HUD_CARD_COMPACT_FROM || w < C.HUD_CARD_W;
  return { w, gap, compact, scale: w / C.HUD_CARD_W, total: w * count + gap * (count - 1) };
}

// 대기실 판은 오른쪽에 붙임 (2026-10-30 재혁: 가운데 맵 미리보기 섬·사람들이 보이게). 폭 = 화면 폭 × frac 을 [min, max] 로.
// 반환: 판 폭·왼쪽 끝 (px). 화면 가운데는 늘 판 밖
export function lobbyDock(viewW) {
  const L = C.HUD_LOBBY_W;
  const w = Math.round(Math.min(L.max, Math.max(L.min, viewW * L.frac)));
  return { w, left: viewW - C.HUD_CARD_MARGIN - w };
}

// 머리 위 이름·% : 카메라에서 가까운 LABEL_FULL_N 명만 원래 크기, 나머지는 작고 흐리게. dists[i] → { scale, opacity }
export function labelSizes(dists) {
  const order = dists.map((d, i) => [d, i]).sort((a, b) => a[0] - b[0]);
  const out = dists.map(() => ({ scale: 1, opacity: 1 }));
  order.forEach(([, i], rank) => {
    if (rank >= C.LABEL_FULL_N) out[i] = { scale: C.LABEL_FAR_SCALE, opacity: C.LABEL_FAR_OPACITY };
  });
  return out;
}
