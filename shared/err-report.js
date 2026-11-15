// 에러 한 번만 찍기: 같은 글이 매 프레임·틱 쏟아지면 콘솔이 묻히니 처음 한 번만, 하지만 글이 바뀌면 다시 찍음
// (예전엔 '첫 에러 한 번' 뒤로는 다른 에러도 영영 안 보였음). log 는 갈아끼울 수 있음 (테스트)
export function createErrorReporter(log = console.error) {
  let last = null;
  return {
    report(label, err) {
      const msg = String((err && err.stack && String(err.stack).split('\n')[0]) || (err && err.message) || err);
      if (msg === last) return false;
      last = msg;
      log(label, err);
      return true;
    },
    reset() {
      last = null;
    },
  };
}

// 이벤트 묶음을 하나씩 처리: 하나가 터져도 나머지는 계속 (예전엔 첫 예외에 같은 틱 나머지를 버림)
export function runEach(list, fn, onError) {
  let failed = 0;
  for (const e of list || []) {
    try {
      fn(e);
    } catch (err) {
      failed++;
      onError(e, err);
    }
  }
  return failed;
}
