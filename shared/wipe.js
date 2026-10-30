// 화면 전환 슬래시 계산: three.js·DOM 없는 순수 계산 — client/main.js 가 띄우고 test/wipe.test.js 가 검증한다.
// 화면(screen) 은 'menu'(방 밖) · 'lobby'(대기실, 결과 연출이 끝난 판 끝 포함) · 'game'(카운트다운·판 중) · 'results'(판 끝 결과 연출).
// 바뀔 때 어느 전환인지(short·big·없음)와, 띠마다 언제 어디로 가는지(WAAPI 키프레임)·언제 화면을 다 덮는지(coverMs)를 낸다.
import { CONFIG as C } from './config.js';

// closeup = 판 끝 승자 클로즈업 중 (shared/victory.js): 아직 판 화면 그대로 (결과 표 슬래시는 클로즈업 뒤)
export function screenOf({ inRoom, phase, hero, closeup = false }) {
  if (!inRoom) return 'menu';
  if (phase === 'countdown' || phase === 'playing') return 'game';
  if (phase === 'over' && closeup) return 'game';
  if (phase === 'over' && hero) return 'results';
  return 'lobby';
}

// 재혁이 고른 전환만: 메뉴 → 방(대기실·연습) / 대기실·결과 → 판 시작 / 판 끝 → 결과 / 결과 → 대기실 판 / 방 나가기 → 메뉴 (짧게)
export function wipeKind(prev, next) {
  if (!prev || !next || prev === next) return null;
  if (prev === 'menu') return 'short';
  if (next === 'menu') return 'short'; // 방 나가기 (대기실·판·결과 → 메뉴)
  if (next === 'game' && (prev === 'lobby' || prev === 'results')) return 'big';
  if (prev === 'game' && next === 'results') return 'big';
  if (prev === 'results' && next === 'lobby') return 'short';
  return null;
}

// reduced: '그래픽 낮춤' 또는 prefers-reduced-motion → 슬래시 대신 짧은 페이드
export function wipePlan(kind, reduced = false) {
  if (!kind || !C.UI_WIPE[kind]) return null;
  if (reduced) return { kind, fade: true, ms: C.UI_WIPE_FADE_MS, coverMs: C.UI_WIPE_FADE_MS * C.UI_WIPE_IN, bands: [] };
  const k = C.UI_WIPE[kind];
  const lag = k.ms * C.UI_WIPE_STAGGER;
  const dur = k.ms - lag * (k.bands - 1); // 마지막 띠도 전체 길이 안에 끝나게
  const X = C.UI_WIPE_X;
  const reach = C.UI_WIPE_IN;
  const leave = Math.min(1, reach + k.hold);
  const bands = [];
  for (let i = 0; i < k.bands; i++) {
    bands.push({
      delay: i * lag,
      ms: dur,
      frames: [
        { offset: 0, x: X.from },
        { offset: reach, x: X.cover },
        { offset: leave, x: X.cover },
        { offset: 1, x: X.to },
      ],
    });
  }
  // 띠는 늦게 출발한 것이 위에 그려짐: 앞의 띠들은 노랑 앞줄로 먼저 보이고, 마지막 남색 띠가 화면을 다 덮음
  const main = bands[bands.length - 1];
  return { kind, fade: false, ms: k.ms, coverMs: main.delay + reach * dur, bands };
}
