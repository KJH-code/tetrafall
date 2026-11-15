// 화면 시계 (감사 C7): KO 슬로모션·히트스톱 (client/ko.js timeScale) 은 프레임 dt 에 배율을 곱해 '화면만' 느리게 함.
// 그런데 대포 반동·바드 폼 팝·표창 다시 쥐기·떠다니는 빛 같은 연출이 performance.now() (실제 시간) 로 돌면 슬로모션을 무시하고 혼자 정상 속도로 감 →
// 이런 연출은 이 시계를 씀. 렌더러가 매 프레임 배율 곱한 dt 로 advance 해서, 슬로모션이면 시계도 느리게 감 (멈춘 동안은 같이 멈춤).
// 시작은 실제 시간에 맞춤 (연출이 찍어 둔 옛 시각과 비교해도 어긋나지 않게)
export class ScreenClock {
  constructor(start = typeof performance !== 'undefined' ? performance.now() : 0) {
    this.t = start; // ms
  }
  now() {
    return this.t;
  }
  advance(dtSec) {
    if (dtSec > 0) this.t += dtSec * 1000;
  }
}
export const screenClock = new ScreenClock();
