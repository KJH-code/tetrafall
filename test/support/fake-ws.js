// 테스트용 가짜 소켓: 서버가 보낸 메시지를 msgs 에 모음 (rooms.js 는 readyState·OPEN·send 만 씀)
export function fakeWs() {
  return {
    OPEN: 1,
    readyState: 1,
    msgs: [],
    send(text) {
      this.msgs.push(JSON.parse(text));
    },
    last(type) {
      return [...this.msgs].reverse().find((m) => m.type === type);
    },
  };
}
