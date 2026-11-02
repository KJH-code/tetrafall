// 테스트용 시드 난수 (선형 합동 생성기): 같은 시드면 같은 수열 → 봇·랜덤이 끼어도 판이 재현됨.
// 시드를 어떻게 섞을지는 테스트 파일이 정함 (예: game.test.js 의 SEED0). game.rng·Rooms({ rng })·그 밖의 난수 자리에 그대로 넣음
export function lcg(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}
