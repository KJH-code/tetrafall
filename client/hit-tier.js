// 타격 소리 세기 단계·콤보 순번 (three.js·WebAudio 없는 순수 계산, main.js 가 hit 이벤트마다 부름, 테스트 test/sound.test.js)
// 치명타 > 강타 (콤보 마무리·묵직한 스킬 kind) > 약타 (표창·투사체·연속으로 자주 맞는 kind) > 중타 (나머지 평타)
import { CONFIG as C } from '../shared/config.js';

export function hitTier(e) {
  if (e.crit) return 'crit';
  if (e.finish || C.SFX_HEAVY_KINDS.includes(e.kind)) return 'heavy';
  if (e.star || C.SFX_LIGHT_KINDS.includes(e.kind)) return 'light';
  return 'medium';
}

// 콤보 순번 (1타·2타·3타 → 소리가 점점 묵직하게): 평타 n (마무리 전 몇 번째), 없으면 이어 넣은 타 수 streak. SFX_HIT_COMBO 길이에서 멈춤
export function hitStep(e) {
  return Math.min(C.SFX_HIT_COMBO.length, Math.max(1, e.n || e.streak || 1));
}
