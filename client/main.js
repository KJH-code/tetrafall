// 클라이언트 진입점: WebSocket 연결, 상태 수신, 입력 전송, 렌더 루프, HUD.
import { CONFIG as C } from '/shared/config.js';
import { Renderer } from '/render.js';
import { Input } from '/input.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
const centerEl = $('center');
const centerText = $('center-text');
const startBtn = $('start-btn');
const keysEl = $('keys');
const crosshair = $('crosshair');
const flash = $('flash');
const banner = $('banner');
const toasts = $('toasts');

const renderer = new Renderer(document.body);
let ws = null;
let myId = null;
let state = null;
let lastState = null;
let wasAlive = true;
let rejected = false; // 방이 꽉 차서 거부됨. 이어지는 연결 끊김 메시지로 덮어쓰지 않는다

function send(obj) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}
const input = new Input(renderer.canvas, (action) => send({ type: 'action', ...action }));

// ---------- 알림 ----------
function toast(text, kind = '') {
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.textContent = text;
  toasts.appendChild(el);
  while (toasts.children.length > 4) toasts.firstChild.remove();
  setTimeout(() => (el.style.opacity = 0), C.TOAST_MS);
  setTimeout(() => el.remove(), C.TOAST_MS + 450);
}

function flashScreen(color) {
  flash.style.transition = 'none';
  flash.style.background = color;
  flash.style.opacity = 1;
  requestAnimationFrame(() => {
    flash.style.transition = 'opacity .4s';
    flash.style.opacity = 0;
  });
}

function nameOf(id) {
  const p = state && state.players.find((x) => x.id === id);
  return p ? p.name : '?';
}

const KIND_KO = { push: '밀치기', projectile: '투사체' };

function handleEvent(e) {
  switch (e.type) {
    case 'hit':
      if (e.target === myId) {
        if (e.ok) {
          flashScreen('rgba(255,210,0,.45)');
          toast(`${nameOf(e.by)}의 ${KIND_KO[e.kind]}에 맞음!`, 'me');
        }
      } else if (e.by === myId) {
        toast(e.ok ? `${KIND_KO[e.kind]} 명중!` : `${KIND_KO[e.kind]} 명중했지만 상대가 경직 중이라 무효`, e.ok ? 'good' : '');
      }
      break;
    case 'pickup':
      if (e.who === myId) {
        toast(e.item === 'control' ? '조종권 획득! 다음 블록을 하늘에서 조종합니다' : '투사체 획득! 우클릭으로 발사', 'good');
      } else {
        toast(`${nameOf(e.who)} ${e.item === 'control' ? '조종권' : '투사체'} 획득`);
      }
      break;
    case 'controlStart':
      if (e.who !== myId) toast(`${nameOf(e.who)} 블록 조종 시작. 그림자를 조심!`);
      break;
    case 'clear':
      toast(`층 클리어! 위에 있던 것들이 ${e.n}칸 내려앉음`);
      break;
    default:
  }
}

// ---------- 연결 ----------
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
      for (const e of msg.events || []) handleEvent(e);
    } else if (msg.type === 'reject') {
      rejected = true;
      centerText.textContent = msg.reason;
      statusEl.textContent = '';
    }
  };
  ws.onclose = () => {
    centerEl.classList.remove('hidden');
    if (!rejected) centerText.textContent = '서버 연결 끊김. 새로고침하세요.';
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
  if (state.phase === 'playing' && !p.alive && wasAlive) flashScreen('rgba(255,0,0,.45)');
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

// ---------- HUD ----------
function updateHud() {
  if (!state) return;
  const p = me();
  const isHost = state.hostId === myId;
  const alive = state.players.filter((x) => x.alive).length;
  const lines = [];
  lines.push(`${p ? p.name : '?'}${isHost ? ' (호스트)' : ''} · 라운드 ${state.round.n} · ${fmt(state.round.elapsed)}`);
  const maxP = Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
  lines.push(`플레이어 ${state.players.length}/${maxP} · 생존 ${alive}`);
  if (p && state.phase === 'playing') {
    const flags = [];
    if (p.stunned) flags.push('경직!');
    if (p.dashCd > 0) flags.push(`대시 ${(p.dashCd / 1000).toFixed(1)}s`);
    if (!p.alive) flags.push(`사망 (${p.cause === 'crush' ? '압사' : '낙사'})`);
    if (flags.length) lines.push(flags.join(' · '));
  }
  const t = state.round.totals;
  const share = t.crush + t.fall > 0 ? ` · 압사 비율 ${Math.round((t.crush / (t.crush + t.fall)) * 100)}% (합격 ${Math.round(C.PASS_CRUSH_SHARE * 100)}%)` : '';
  lines.push(`누적 ${t.rounds}판 · 압사 ${t.crush} · 낙사 ${t.fall}${share}`);
  statusEl.textContent = lines.join('\n');

  // 상단 배너: 조종권 상태 (예고 → 조종 중)
  let bannerText = null;
  let bannerColor = 'rgba(0,140,160,.85)';
  if (p && p.alive && state.phase === 'playing') {
    if (p.controlling && state.piece) {
      const left = state.piece.timeLeft / 1000;
      bannerText = `블록 조종 중 ${left.toFixed(1)}초\n방향키 이동 · Q/E 회전 · Enter 낙하${state.piece.fits ? '' : '\n여기엔 못 놓음 (빨간 미리보기)'}`;
      if (left < 3) bannerColor = 'rgba(200,60,20,.9)';
    } else if (p.hasControl) {
      const n = state.nextSpawnIn;
      bannerText = n === null || n === undefined ? '조종권 보유: 곧 하늘 시점으로 전환' : `조종권 보유: ${(n / 1000).toFixed(1)}초 후 하늘 시점으로 전환`;
    }
  }
  banner.classList.toggle('hidden', bannerText === null);
  if (bannerText !== null) {
    banner.textContent = bannerText;
    banner.style.background = bannerColor;
  }

  // 가운데 안내
  let center = null;
  let showStart = false;
  let showKeys = false;
  if (state.phase === 'lobby') {
    const n = state.players.length;
    if (!state.canStart) center = `플레이어 대기 중 (${n}명, 최소 ${C.MIN_PLAYERS}명)`;
    else if (isHost) center = `${n}명 접속 (최대 ${maxP}명)\n더 기다리거나 시작하세요`;
    else center = `${n}명 접속. 호스트가 시작하길 기다리는 중`;
    showStart = isHost && state.canStart;
    showKeys = true;
  } else if (state.phase === 'over') {
    const w = state.players.find((x) => x.id === state.round.winnerId);
    center = `라운드 ${state.round.n} 종료\n승자: ${w ? w.name : '무승부'}`;
    showStart = isHost && state.canStart;
    showKeys = true;
  } else if (p && !p.alive) {
    center = `사망: ${p.cause === 'crush' ? '압사' : '낙사'}\n관전 중`;
  } else if (!input.locked) {
    center = '화면을 클릭하면 조작 시작';
    showKeys = true;
  }
  centerEl.classList.toggle('hidden', center === null);
  centerText.textContent = center || '';
  startBtn.classList.toggle('hidden', !showStart);
  startBtn.textContent = state.phase === 'over' ? '재시작' : '시작';
  keysEl.classList.toggle('hidden', !showKeys);

  input.enabled = state.phase === 'playing' && !!p && p.alive;
  // 조준점: 투사체가 있으면 빨갛고 크게 + 탄 수
  const armed = !!p && p.ammo > 0;
  crosshair.classList.toggle('hidden', !(input.enabled && !p.controlling));
  crosshair.classList.toggle('armed', armed);
  crosshair.dataset.ammo = armed ? `투사체 ×${p.ammo} (우클릭)` : '';
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
  const view = p && p.alive && p.controlling ? 'sky' : 'fps';
  input.sky = view === 'sky';
  renderer.render(state, myId, dt, view, { yaw: input.yaw, pitch: input.pitch });
  updateHud();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
connect();

// 디버그용 (자동 테스트·콘솔에서 입력 주입).
// window.__tf.send({type:'action', name:'push'}) / window.__tf.inputOverride = {type:'input', fwd:1, ...}
const debug = { send, getState: () => state, getMyId: () => myId, input, inputOverride: null, renderer };
window.__tf = debug;
