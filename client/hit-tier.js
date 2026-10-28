// 타격 소리 세기 단계 (three.js·WebAudio 없는 순수 계산, main.js 가 hit 이벤트마다 부름, 테스트 test/sound.test.js)
// 치명타 > 강타 (콤보 마무리·묵직한 스킬 kind) > 약타 (표창·투사체·연속으로 자주 맞는 kind) > 중타 (나머지 평타)
import { CONFIG as C } from '../shared/config.js';

export function hitTier(e) {
  if (e.crit) return 'crit';
  if (e.finish || C.SFX_HEAVY_KINDS.includes(e.kind)) return 'heavy';
  if (e.star || C.SFX_LIGHT_KINDS.includes(e.kind)) return 'light';
  return 'medium';
}
