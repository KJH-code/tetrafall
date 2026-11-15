// 방 안 효과용 예약 (setTimeout 묶음): 방을 나갈 때 한꺼번에 취소 → 나간 뒤 이전 방의 소리·파편·글자가 메뉴 위에 튀지 않음.
// 타이머 함수는 갈아끼울 수 있음 (테스트가 가짜 시계를 넣음)
export function createLater(setT = setTimeout, clearT = clearTimeout) {
  const ids = new Set();
  return {
    later(fn, ms) {
      const id = setT(() => {
        ids.delete(id);
        fn();
      }, ms);
      ids.add(id);
      return id;
    },
    cancelAll() {
      for (const id of ids) clearT(id);
      ids.clear();
    },
    get size() {
      return ids.size;
    },
  };
}
