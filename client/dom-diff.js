// 매 프레임 같은 값을 DOM 에 다시 쓰지 않게 (2026-11 감사 C11): 글자·속성은 바뀔 때만 씀.
// textContent 를 같은 글로 다시 쓰면 글자 노드를 새로 만들고, classList.add/remove 는 이미 그 상태여도 class 속성을 다시 써서 브라우저가 매번 스타일을 새로 계산함.
// 요소는 textContent·getAttribute·setAttribute·classList 만 있으면 됨 (테스트는 가짜 요소)
export function setText(el, text) {
  const s = String(text);
  if (el.textContent !== s) el.textContent = s;
}
export function setAttr(el, name, value) {
  const s = String(value);
  if (el.getAttribute(name) !== s) el.setAttribute(name, s);
}
// 클래스 한 개 켜고 끄기 (이미 그 상태면 아무것도 안 씀). classList.toggle(c, on) 은 이미 그렇게 동작 — 이름만 맞춰 둠
export function setClass(el, name, on) {
  if (el.classList.contains(name) !== !!on) el.classList.toggle(name, !!on);
}
