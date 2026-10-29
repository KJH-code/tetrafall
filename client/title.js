// 타이틀 화면 흐름 (스매시식 '아무 키나'): 처음 켤 때 큰 블록 로고 (3D, title-scene.js) + 'Enter / 클릭하여 시작'.
// 아무 키·클릭·터치 → (로고가 다 안 쌓였으면 빨리 감기) → 카메라가 메뉴 섬 쪽으로 내려오며 짧은 슬래시 → 방 목록.
// 누른 키는 메뉴 입력으로 새지 않음 (창 맨 앞에서 가로챔). 그래픽 낮춤·움직임 줄이기면 완성 로고 + 페이드.
// 링크(?room=)로 오면 건너뜀 — 부르는 쪽(main.js)이 shared/title.js showTitle 로 판단
import { CONFIG as C } from '/shared/config.js';

// renderer: Renderer, playWipe: main.js 의 화면 전환 (kind → plan), reduced: 움직임 줄이기, unlock: 첫 입력 때 소리 풀기
export function startTitle({ renderer, playWipe, reduced = false, unlock = () => {} }) {
  const el = document.getElementById('title');
  if (!el) return null;
  const scene = renderer.startTitle(reduced);
  document.body.classList.add('title-on'); // 방 목록·접속 글씨 숨김 (index.html)
  el.classList.remove('hidden');
  el.classList.toggle('reduced', !!reduced);
  const startAt = performance.now();
  let pressed = false;
  let finished = false;

  function finish() {
    if (finished) return;
    finished = true;
    document.body.classList.remove('title-on');
    el.classList.add('hidden');
    window.removeEventListener('keydown', onKey, true);
    window.removeEventListener('keyup', swallow, true);
    el.removeEventListener('pointerdown', onPointer);
  }

  // 띠가 화면을 다 덮을 때 타이틀을 치우고 (그 뒤는 방 목록), 카메라가 다 내려오면 로고 블록 정리
  function wipeOut() {
    const plan = playWipe('short');
    setTimeout(finish, plan ? plan.coverMs : 0);
  }

  function go() {
    unlock();
    if (pressed) return;
    if (performance.now() - startAt < C.TITLE_INPUT_DELAY_MS) return; // 켜자마자 눌린 키(새로고침 F5 등)는 무시
    pressed = true;
    el.classList.add('pressed');
    if (reduced) {
      wipeOut();
      setTimeout(() => renderer.endTitle(), C.UI_WIPE_FADE_MS);
      return;
    }
    scene.press();
    // 빨리 감기 + 내려오기 시간을 보며 슬래시를 띄움
    const tick = () => {
      if (renderer.title !== scene) return finish();
      if (scene.zoomT !== null && scene.zoomT >= C.TITLE_ZOOM_MS * C.TITLE_WIPE_AT) {
        wipeOut();
        const left = Math.max(0, C.TITLE_ZOOM_MS - scene.zoomT);
        setTimeout(() => renderer.title === scene && renderer.endTitle(), left + 50);
        return;
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  function onKey(e) {
    if (e.ctrlKey || e.metaKey || e.altKey) return; // 브라우저 단축키(새로고침·탭)는 그대로
    if (/^F\d+$/.test(e.key)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    go();
  }
  function swallow(e) {
    if (/^F\d+$/.test(e.key)) return; // 누름을 통과시킨 F 키는 뗌도 (안 그러면 F3 성능 표시가 눌린 채로 남음)
    if (!finished || pressed) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }
  function onPointer(e) {
    e.preventDefault();
    go();
  }
  window.addEventListener('keydown', onKey, true);
  window.addEventListener('keyup', swallow, true);
  el.addEventListener('pointerdown', onPointer);
  return { scene, go, finish, get done() { return finished; } };
}
