// 이번 창의 메뉴 테마 (타이틀·메뉴 배경·앰비언트가 같이 씀): sessionStorage (config MENU_THEME_KEY) 에 한 번 고른 테마.
// 타이틀이 고르면 그걸 저장, 타이틀을 안 거친 메뉴 (링크로 와서 방에서 나옴) 는 처음 물을 때 무작위로 골라 저장 → 창을 닫기 전까지 같은 장면
import { CONFIG as C } from '/shared/config.js';
import { pickTitleTheme } from '/shared/title.js';

let cached = null;

export function sessionTheme() {
  if (cached) return cached;
  let id = null;
  try {
    id = sessionStorage.getItem(C.MENU_THEME_KEY);
  } catch {}
  cached = C.TITLE_THEMES[id] ? id : pickTitleTheme();
  setSessionTheme(cached);
  return cached;
}

export function setSessionTheme(id) {
  if (!C.TITLE_THEMES[id]) return;
  cached = id;
  try {
    sessionStorage.setItem(C.MENU_THEME_KEY, id);
  } catch {}
}

// 지금 배경 테마를 화면 (HTML) 에 알림: body data-theme + CSS 변수 --theme-glow·--theme-edge (메뉴·대기실 판 색을 장면에 맞추기, B 쪽 CSS 가 씀). id 없으면 지움
let marked;
export function markTheme(id) {
  if (id === marked || typeof document === 'undefined') return;
  marked = id;
  const b = document.body;
  const T = id && C.TITLE_THEMES[id];
  const hex = (c) => `#${c.toString(16).padStart(6, '0')}`;
  if (!T) {
    delete b.dataset.theme;
    b.style.removeProperty('--theme-glow');
    b.style.removeProperty('--theme-edge');
    return;
  }
  b.dataset.theme = id;
  b.style.setProperty('--theme-glow', hex(T.glow));
  b.style.setProperty('--theme-edge', hex(T.edge));
}
