// 테트리미노 칸 모습 값 (three.js 없음, client/piece-look.js 가 씀 + 테스트). 맵 테마마다 WORLD_THEMES.*.piece 가
// 기본 (PIECE_LOOK 둥근 장난감 블록 + SHAPE_COLORS) 을 덮어씀. 테마가 없으면 기본 그대로
import { CONFIG as C } from './config.js';

export function pieceSpec(themeId) {
  const t = themeId && C.WORLD_THEMES[themeId] ? C.WORLD_THEMES[themeId].piece : null;
  const base = { style: 'toy', segs: 2, fresnel: 0, crack: 0, band: null, opacity: 1, ...C.PIECE_LOOK, colors: { ...C.SHAPE_COLORS } };
  if (!t) return base;
  return { ...base, ...t, colors: { ...base.colors, ...(t.colors || {}) } };
}
