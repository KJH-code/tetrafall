// 타이틀 화면 흐름 (스매시식 '아무 키나'): 처음 켤 때 테마 엔딩 장면 + 블록 로고 (3D, title-scene.js) → 빛 터진 뒤 'Enter / 클릭하여 시작'.
// 아무 키·클릭·터치 → (로고가 다 안 쌓였으면 빨리 감기) → 카메라가 앞으로 빠져나가며 하얗게 → 하얀 막 뒤에서 메뉴 섬으로 바꾸고 걷힘 → 방 목록.
// 테마는 켤 때마다 무작위 (shared/title.js pickTitleTheme). 소리는 title-sound.js (테마 앰비언트·착지·반짝).
// 누른 키는 메뉴 입력으로 새지 않음 (창 맨 앞에서 가로챔). 움직임 줄이기면 완성 로고 + 페이드. 링크(?room=)로 오면 건너뜀 — 부르는 쪽(main.js)이 shared/title.js showTitle 로 판단
import { CONFIG as C } from '/shared/config.js';
import { pickTitleTheme } from '/shared/title.js';
import { TitleSound } from '/title-sound.js';

// renderer: Renderer, reduced: 움직임 줄이기, unlock: 첫 입력 때 소리 풀기, onDone: 타이틀이 끝나 방 목록이 보일 때
// sound·music: 효과음·음악 (없으면 소리 없이). theme: 테마 고정 (확인용, 없으면 무작위)
export function startTitle({ renderer, reduced = false, unlock = () => {}, onDone = () => {}, sound = null, music = null, theme = null }) {
  const el = document.getElementById('title');
  if (!el) return null;
  const id = theme && C.TITLE_THEMES[theme] ? theme : pickTitleTheme();
  const scene = renderer.startTitle(id, reduced);
  const sfx = sound ? new TitleSound(sound, music, id) : null;
  scene.on.land = (n) => sfx?.land(n);
  scene.on.burst = () => sfx?.burst();
  scene.on.exit = () => sfx?.exit();
  document.body.classList.add('title-on'); // 방 목록·접속 글씨 숨김 (index.html)
  el.classList.remove('hidden', 'ready', 'pressed', 'out');
  el.classList.toggle('reduced', !!reduced);
  el.dataset.theme = id;
  el.style.setProperty('--title-glow', `#${C.TITLE_THEMES[id].edge.toString(16).padStart(6, '0')}`); // 안내 글씨 빛 = 테마 빛 색
  const white = el.querySelector('.white');
  const startAt = performance.now();
  let pressed = false;
  let finished = false;
  let swapped = false;

  function finish() {
    if (finished) return;
    finished = true;
    document.body.classList.remove('title-on');
    el.classList.add('hidden');
    if (white) white.style.opacity = '0';
    window.removeEventListener('keydown', onKey, true);
    window.removeEventListener('keyup', swallow, true);
    el.removeEventListener('pointerdown', onPointer);
    sfx?.stop();
    onDone(); // 방 목록이 보임 (처음이면 튜토리얼 묻기)
  }

  // 매 프레임: 소리 준비·'Enter' 안내 보이기·빠져나가기 하얀 막 → 다 덮이면 메뉴 섬으로 바꾸고 걷힘
  const tick = () => {
    if (finished) return;
    if (renderer.title !== scene && !swapped) return finish(); // 누가 타이틀을 치움 (방에 들어감)
    sfx?.update();
    if (scene.ready) el.classList.add('ready');
    const ex = scene.exit;
    if (ex) {
      if (white) white.style.opacity = String(ex.white);
      if (ex.swap && !swapped) {
        swapped = true;
        renderer.endTitle(); // 하얀 막 뒤에서 메뉴 섬 (render.js)
        document.body.classList.remove('title-on');
        el.classList.add('out'); // 막만 남기고 안내·클릭 받기 끔
      }
      if (ex.done) return finish();
    }
    requestAnimationFrame(tick);
  };
  // 장면이 치워진 뒤에도 하얀 막이 걷히게 시계를 여기서 감음
  let last = performance.now();
  const clock = () => {
    if (finished) return;
    const now = performance.now();
    if (swapped) scene.exitT += Math.min(50, now - last); // 느린 컴퓨터에서도 걷히는 게 보이게 (한 프레임 최대 50ms)
    last = now;
    requestAnimationFrame(clock);
  };
  requestAnimationFrame(tick);
  requestAnimationFrame(clock);

  function go() {
    unlock();
    sfx?.update();
    if (pressed) return;
    if (performance.now() - startAt < C.TITLE_INPUT_DELAY_MS) return; // 켜자마자 눌린 키(새로고침 F5 등)는 무시
    pressed = true;
    el.classList.add('pressed');
    scene.press();
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
  return { scene, theme: id, go, finish, get done() { return finished; } };
}
