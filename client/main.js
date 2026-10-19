// 클라이언트 진입점: WebSocket 연결, 상태 수신, 입력 전송, 렌더 루프, HUD.
import { CONFIG as C } from '/shared/config.js';
import { Renderer } from '/render.js';
import { Input } from '/input.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
const centerEl = $('center');
const centerText = $('center-text');
const startBtn = $('start-btn');
const crosshair = $('crosshair');
const flash = $('flash');

const renderer = new Renderer(document.body);
let ws = null;
let myId = null;
let state = null;
let lastState = null;
let wasAlive = true;

function send(obj) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}
const input = new Input(renderer.canvas, (action) => send({ type: 'action', ...action }));

function connect() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}`);
  ws.onopen = () => {
    statusEl.textContent = '연결됨. 서버 응답 대기...';
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'welcome') {
      myId = msg.id;
      const sp = C.SPAWN_POINTS[msg.slot % C.SPAWN_POINTS.length];
      input.setYawPitch(sp.yaw, 0);
    } else if (msg.type === 'state') {
      lastState = state;
      if (!msg.grid && state && state.grid) msg.grid = state.grid; // 격자는 바뀔 때만 온다
      state = msg;
      onState();
    } else if (msg.type === 'reject') {
      centerText.textContent = msg.reason;
      statusEl.textContent = '';
    }
  };
  ws.onclose = () => {
    centerEl.classList.remove('hidden');
    centerText.textContent = '서버 연결 끊김. 새로고침하세요.';
    startBtn.classList.add('hidden');
  };
}

startBtn.addEventListener('click', () => send({ type: 'start' }));

function me() {
  return state ? state.players.find((p) => p.id === myId) : null;
}

function onState() {
  const p = me();
  if (!p) return;
  if (state.phase === 'playing' && !p.alive && wasAlive) {
    flash.style.opacity = 1;
    setTimeout(() => (flash.style.opacity = 0), 400);
  }
  wasAlive = p.alive;
  // 판이 새로 시작되면 시점을 스폰 방향으로
  if (lastState && lastState.round.n !== state.round.n) {
    const sp = C.SPAWN_POINTS[p.slot % C.SPAWN_POINTS.length];
    input.setYawPitch(sp.yaw, 0);
  }
}

function fmt(ms) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

function updateHud() {
  if (!state) return;
  const p = me();
  const isHost = state.hostId === myId;
  const alive = state.players.filter((x) => x.alive).length;
  const lines = [];
  lines.push(`${p ? p.name : '?'}${isHost ? ' (호스트)' : ''} · 라운드 ${state.round.n} · ${fmt(state.round.elapsed)}`);
  lines.push(`플레이어 ${state.players.length}/${C.PLAYER_COUNT} · 생존 ${alive}`);
  if (p && state.phase === 'playing') {
    const flags = [];
    if (p.controlling) flags.push(`블록 조종 중 ${(state.piece.timeLeft / 1000).toFixed(1)}s${state.piece.fits ? '' : ' (이 자리엔 못 놓음)'}`);
    else if (p.hasControl) flags.push('조종권 보유 → 다음 블록');
    if (p.ammo > 0) flags.push(`넉백 탄 ${p.ammo}`);
    if (p.stunned) flags.push('경직!');
    if (p.dashCd > 0) flags.push(`대시 ${(p.dashCd / 1000).toFixed(1)}s`);
    if (!p.alive) flags.push(`사망 (${p.cause === 'crush' ? '압사' : '낙사'})`);
    lines.push(flags.join(' · ') || '');
    const ctl = state.piece && state.piece.controller !== null ? state.players.find((x) => x.id === state.piece.controller) : null;
    if (ctl && state.piece.phase === 'control') lines.push(`${ctl.name} 이(가) 블록 조종 중`);
  }
  const t = state.round.totals;
  lines.push(`누적 ${t.rounds}판 · 압사 ${t.crush} · 낙사 ${t.fall}`);
  statusEl.textContent = lines.join('\n');

  // 가운데 안내
  let center = null;
  let showStart = false;
  if (state.phase === 'lobby') {
    center = state.canStart ? (isHost ? '모두 모였습니다' : '호스트가 시작하길 기다리는 중') : `플레이어 대기 중 (${state.players.length}/${C.PLAYER_COUNT})`;
    showStart = isHost && state.canStart;
  } else if (state.phase === 'over') {
    const w = state.players.find((x) => x.id === state.round.winnerId);
    center = `라운드 ${state.round.n} 종료\n승자: ${w ? w.name : '무승부'}`;
    showStart = isHost && state.canStart;
  } else if (p && !p.alive) {
    center = `사망: ${p.cause === 'crush' ? '압사' : '낙사'}\n관전 중`;
  } else if (!input.locked) {
    center = '화면을 클릭하면 조작 시작';
  }
  centerEl.classList.toggle('hidden', center === null);
  centerText.textContent = center || '';
  startBtn.classList.toggle('hidden', !showStart);
  startBtn.textContent = state.phase === 'over' ? '재시작' : '시작';

  input.enabled = state.phase === 'playing' && !!p && p.alive;
  crosshair.classList.toggle('hidden', !(input.enabled && !p.controlling));
}

// 입력 전송
setInterval(() => {
  if (!state || state.phase !== 'playing') return;
  send(debug.inputOverride || input.sample());
}, 1000 / C.INPUT_SEND_RATE);

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  const p = me();
  const view = p && p.controlling ? 'sky' : 'fps';
  renderer.render(state, myId, dt, view, { yaw: input.yaw, pitch: input.pitch });
  updateHud();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
connect();

// 디버그용 (자동 테스트·콘솔에서 입력 주입).
// window.__tf.send({type:'action', name:'push'}) / window.__tf.inputOverride = {type:'input', fwd:1, ...}
const debug = { send, getState: () => state, getMyId: () => myId, input, inputOverride: null };
window.__tf = debug;
