// 판 끝 연출 순서 (2026-10-30 재혁: 승리 포즈가 안 보임 → 스매시식 승자 클로즈업 뒤 결과). three.js 없는 순수 계산, main.js 가 씀, 테스트 test/wipe.test.js
// 판 끝 → (마지막 킬 슬로모션이 남았으면 그게 끝날 때까지 'slow') → 승자 클로즈업 'closeup' (카메라가 승자 앞, 승리 포즈) → 결과 표 'results' (RESULTS_HERO_MS) → 대기실 판 'lobby'
// 승자가 없거나 무승부면 클로즈업 없이 바로 결과. reduced (움직임 줄이기·그래픽 낮춤) 면 클로즈업을 짧게 (카메라는 날아가지 않고 바로 그 자리)
import { CONFIG as C } from './config.js';

// star = 클로즈업할 승자가 있음, slowLeftMs = 판이 끝난 순간 마지막 킬 슬로모션이 남은 시간. 반환 값은 판 끝부터 ms
export function victoryPlan({ star, slowLeftMs = 0, reduced = false }) {
  if (!star) return { closeupAt: 0, resultsAt: 0, endAt: C.RESULTS_HERO_MS };
  const closeupAt = Math.max(0, Number.isFinite(slowLeftMs) ? slowLeftMs : 0);
  const resultsAt = closeupAt + (reduced ? C.VICTORY_CLOSEUP_REDUCED_MS : C.VICTORY_CLOSEUP_MS);
  return { closeupAt, resultsAt, endAt: resultsAt + C.RESULTS_HERO_MS };
}

// t = 판 끝부터 ms
export function victoryStage(plan, t) {
  if (!plan || !(t >= 0)) return 'lobby';
  if (t < plan.closeupAt) return 'slow';
  if (t < plan.resultsAt) return 'closeup';
  if (t < plan.endAt) return 'results';
  return 'lobby';
}
