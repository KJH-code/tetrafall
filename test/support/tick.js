// 테스트용 틱 도움: 서버 틱 한 번의 길이(ms), 게임을 ms 만큼 돌림
import { CONFIG as C } from '../../shared/config.js';

export const TICK = 1000 / C.TICK_RATE;

export function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}
