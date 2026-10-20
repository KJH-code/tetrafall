// 클라이언트 진입점: WebSocket 연결, 상태 수신, 입력 전송, 렌더 루프, HUD.
import { CONFIG as C } from '/shared/config.js';
import { Renderer } from '/render.js';
import { Input } from '/input.js';
import { Sound } from '/sound.js';

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
const sound = new Sound();
const fx = renderer.effects;
document.addEventListener('pointerdown', () => sound.unlock());
document.addEventListener('keydown', () => sound.unlock());

// 내 밀치기는 서버 응답을 기다리지 않고 바로 팔을 휘두르고 소리를 낸다 (조작감)
function onLocalAction(action) {
  const p = me();
  if (action.name === 'push' && p && p.alive && !p.controlling && !p.stunned) {
    fx.startPunch(myId);
    sound.play('swing');
  }
}
const input = new Input(renderer.canvas, (action) => {
  onLocalAction(action);
  send({ type: 'action', ...action });
});

const hitmarker = $('hitmarker');
let hitmarkerTimer = 0;
function showHitmarker() {
  hitmarker.style.transition = 'none';
  hitmarker.style.opacity = 1;
  clearTimeout(hitmarkerTimer);
  hitmarkerTimer = setTimeout(() => {
    hitmarker.style.transition = 'opacity .15s';
    hitmarker.style.opacity = 0;
  }, 120);
}

function playerById(id) {
  return state && state.players.find((x) => x.id === id);
}

function distToMe(x, y, z) {
  const p = me();
  if (!p) return undefined;
  return Math.hypot(x - p.x, y - p.y, (z || 0) - p.z);
}

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

const KIND_KO = { push: '밀치기', projectile: '투사체', weapon: '망치', shock: '설치 블록 충격파' };
const ITEM_KO = { control: '조종권', knockback: '투사체', weapon: '망치', jump: '점프력 상승', ghost: '유령화', brick: '설치 블록' };
const ITEM_HELP = {
  control: '조종권 획득! 블록을 하늘에서 조종합니다',
  knockback: '투사체 획득! 우클릭으로 발사',
  weapon: `망치 획득! ${C.WEAPON_USES}번 동안 좌클릭이 2배로 밀고 오래 기절시킴`,
  jump: `점프력 상승! ${C.JUMP_BOOST_MS / 1000}초 동안 2칸 벽도 넘음`,
  ghost: `유령화! ${C.GHOST_MS / 1000}초 동안 블록 통과 (떨어지는 블록엔 깔림)`,
  brick: () => {
    const p = me();
    const big = p && p.brickBig;
    return `설치 블록 ${big ? '2×2' : '1×2'} ${C.BRICK_USES}개! 우클릭으로 조준한 곳(최대 ${C.BRICK_RANGE}칸)에 떨어뜨림 · 깔리면 압사, 옆은 충격파${big ? '' : ' · Q/E 로 앞↔옆'}`;
  },
};
const CAUSE_KO = { crush: '압사', fall: '낙사', lava: '용암' };

function handleEvent(e) {
  feelEvent(e);
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
        const help = ITEM_HELP[e.item];
        toast((typeof help === 'function' ? help() : help) || `${ITEM_KO[e.item] || e.item} 획득`, 'good');
      } else {
        toast(`${nameOf(e.who)} ${ITEM_KO[e.item] || e.item} 획득`);
      }
      break;
    case 'controlStart':
      if (e.who !== myId) toast(`${nameOf(e.who)} 블록 조종 시작. 그림자를 조심!`);
      break;
    case 'lava':
      toast('용암이 올라온다! 높은 곳으로 올라가세요', 'me');
      break;
    case 'clear':
      toast(`층 클리어! 위에 있던 것들이 ${e.n}칸 내려앉음`);
      break;
    default:
  }
}

// 타격감: 소리·이펙트·흔들림
function feelEvent(e) {
  switch (e.type) {
    case 'swing': {
      if (e.who === myId) return; // 내 건 클릭할 때 이미 냄
      const a = playerById(e.who);
      if (!a) return;
      fx.startPunch(e.who);
      sound.play('swing', { dist: distToMe(a.x, a.y, a.z) });
      return;
    }
    case 'hit': {
      const t = playerById(e.target);
      const a = playerById(e.by);
      if (!t) return;
      const chest = { x: t.x, y: t.y, z: t.z + 1.0 };
      if (!e.ok) {
        fx.burst(chest, null, 0xaaaaaa, 4, 2, 0.06, 0.25); // 경직 중이라 무시: 작은 회색 먼지만
        return;
      }
      let dir = null;
      if (a) {
        const dx = t.x - a.x;
        const dy = t.y - a.y;
        const len = Math.hypot(dx, dy) || 1;
        dir = { x: dx / len, y: dy / len };
      }
      const heavy = e.kind === 'weapon';
      fx.burst(chest, dir, e.kind === 'projectile' ? 0xffee40 : heavy ? 0xffa040 : 0xfff2c0, heavy ? C.FX_PARTICLES * 2 : C.FX_PARTICLES, heavy ? 7 : 5);
      fx.ring(chest, e.kind === 'projectile' ? 0xffee40 : heavy ? 0xff8a10 : 0xffffff, heavy ? 3.4 : 2.4);
      fx.hitSquash(e.target);
      if (e.target === myId) {
        sound.play('hurt');
        fx.shake(C.FX_SHAKE_HURT * (heavy ? 1.6 : 1));
      } else if (e.by === myId) {
        sound.play('hit', { strong: true });
        if (heavy) sound.play('hurt'); // 망치는 묵직한 저음을 한 겹 더
        fx.shake(C.FX_SHAKE_HIT * (heavy ? 2 : 1), 150);
        showHitmarker();
      } else {
        sound.play('hit', { dist: distToMe(t.x, t.y, t.z) });
      }
      return;
    }
    case 'fire': {
      const a = playerById(e.who);
      if (a) sound.play('fire', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      return;
    }
    case 'land': {
      let cx = 0;
      let cy = 0;
      let cz = Infinity;
      for (const [x, y, z] of e.cells) {
        cx += x + 0.5;
        cy += y + 0.5;
        cz = Math.min(cz, z);
        fx.burst({ x: x + 0.5, y: y + 0.5, z }, null, 0x9a9a9a, 3, 2.2, 0.08, 0.35);
      }
      cx /= e.cells.length;
      cy /= e.cells.length;
      const d = distToMe(cx, cy, cz);
      sound.play('land', { dist: d });
      if (d !== undefined && d < 2.5) fx.shake(0.06, 160);
      return;
    }
    case 'death': {
      const t = playerById(e.who);
      if (!t) return;
      const d = e.who === myId ? 0 : distToMe(t.x, t.y, t.z);
      const pos = { x: t.x, y: t.y, z: t.z + 0.8 };
      if (e.cause === 'crush') {
        fx.burst(pos, null, 0xff3030, 22, 6, 0.12, 0.6);
        sound.play('crush', { dist: d });
        if (e.who === myId) fx.shake(0.3, 400);
      } else if (e.cause === 'lava') {
        fx.burst(pos, null, 0xffa020, 18, 4, 0.1, 0.6);
        sound.play('lavaDeath', { dist: d });
      } else if (e.cause === 'fall') {
        sound.play('fall', { dist: d });
      }
      return;
    }
    case 'pickup':
      if (e.who === myId) sound.play('pickup');
      return;
    case 'throw': {
      const a = playerById(e.who);
      if (e.who === myId) fx.startPunch(myId);
      if (a) sound.play('swing', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      return;
    }
    case 'lava':
      sound.play('lava');
      fx.shake(0.12, 900);
      return;
    case 'clear':
      sound.play('clear');
      return;
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
$('add-bot').addEventListener('click', () => send({ type: 'addBot' }));
$('remove-bot').addEventListener('click', () => send({ type: 'removeBot' }));
$('map-select').addEventListener('change', (e) => send({ type: 'setMap', map: e.target.value }));
const MAP_KO = { random: '무작위', flat: '평지', pyramid: '피라미드', stairs: '계단' };

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
  lines.push(`${p ? p.name : '?'}${isHost ? ' (호스트)' : ''} · 라운드 ${state.round.n} · ${fmt(state.round.elapsed)}${state.map && state.round.n ? ` · ${state.map.name}` : ''}`);
  const maxP = Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
  lines.push(`플레이어 ${state.players.length}/${maxP} · 생존 ${alive}`);
  if (p && state.phase === 'playing') {
    const flags = [];
    if (p.stunned) flags.push('경직!');
    if (p.dashCd > 0) flags.push(`대시 ${(p.dashCd / 1000).toFixed(1)}s`);
    if (p.weaponUses > 0) flags.push(`망치 ${p.weaponUses}회`);
    if (p.jumpLeft > 0) flags.push(`점프↑ ${(p.jumpLeft / 1000).toFixed(1)}s`);
    if (p.ghostLeft > 0) flags.push(`유령 ${(p.ghostLeft / 1000).toFixed(1)}s`);
    if (p.bricks > 0) flags.push(`블록 ${p.brickBig ? '2×2' : '1×2'} ×${p.bricks}${p.brickBig ? '' : p.brickSide ? ' 옆' : ' 앞'}`);
    if (p.alive) flags.unshift(`피해 ${p.damage}%`);
    if (!p.alive) flags.push(`사망 (${CAUSE_KO[p.cause] || p.cause})`);
    if (flags.length) lines.push(flags.join(' · '));
    if (state.lava && state.lava.active) {
      const above = p.alive ? (p.z - state.lava.z).toFixed(1) : '-';
      lines.push(`용암 높이 ${Math.max(0, state.lava.z).toFixed(1)} · 내 발 위로 ${above}칸`);
    }
  }
  const t = state.round.totals;
  lines.push(`누적 ${t.rounds}판 · 압사 ${t.crush} · 낙사 ${t.fall} · 용암 ${t.lava || 0}`);
  statusEl.textContent = lines.join('\n');

  // 상단 배너: 조종권 상태 (예고 → 조종 중)
  let bannerText = null;
  let bannerColor = 'rgba(0,140,160,.85)';
  if (p && p.alive && state.phase === 'playing') {
    const myPiece = (state.pieces || []).find((pc) => pc.phase === 'control' && pc.controller === myId);
    if (p.controlling && myPiece) {
      const left = myPiece.timeLeft / 1000;
      bannerText = `블록 조종 중 ${left.toFixed(1)}초\n방향키 이동 · Q/E 회전 · Enter 낙하${myPiece.fits ? '' : '\n여기엔 못 놓음 (빨간 미리보기)'}`;
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
    if (!state.canStart) center = `플레이어 대기 중 (${n}명, 최소 ${C.MIN_PLAYERS}명)${isHost ? "\n혼자면 '봇 추가'를 누르세요" : ''}`;
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
    center = `사망: ${CAUSE_KO[p.cause] || p.cause}\n관전 중`;
  } else if (!input.locked) {
    center = '화면을 클릭하면 조작 시작';
    showKeys = true;
  }
  centerEl.classList.toggle('hidden', center === null);
  centerText.textContent = center || '';
  startBtn.classList.toggle('hidden', !showStart);
  startBtn.textContent = state.phase === 'over' ? '재시작' : '시작';
  keysEl.classList.toggle('hidden', !showKeys);
  // 봇 버튼: 호스트만, 판 사이에만
  const showBots = isHost && state.phase !== 'playing';
  $('bot-btns').classList.toggle('hidden', !showBots);
  // 맵: 호스트는 고르고, 다른 사람은 보기만
  const mapSel = $('map-select');
  if (state.map && document.activeElement !== mapSel) mapSel.value = state.map.choice;
  const mapInfo = $('map-info');
  mapInfo.classList.toggle('hidden', !(state.map && !isHost && state.phase !== 'playing'));
  if (state.map) mapInfo.textContent = `맵: ${MAP_KO[state.map.choice] || state.map.choice}`;
  if (showBots) {
    $('add-bot').disabled = state.players.length >= Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
    $('remove-bot').disabled = !state.players.some((x) => x.isBot);
  }

  input.enabled = state.phase === 'playing' && !!p && p.alive;
  // 조준점: 투사체가 있으면 빨갛고 크게 + 탄 수, 설치 블록이 있으면 노랗게 + 개수
  const armed = !!p && p.ammo > 0;
  const brick = !!p && p.bricks > 0;
  crosshair.classList.toggle('hidden', !(input.enabled && !p.controlling));
  crosshair.classList.toggle('armed', armed || brick);
  crosshair.classList.toggle('brick', brick);
  if (armed) crosshair.dataset.ammo = `투사체 ×${p.ammo} (우클릭)`;
  else if (brick) {
    const dir = p.brickBig ? '' : ` · ${p.brickSide ? '옆' : '앞'} (Q/E)`;
    crosshair.dataset.ammo = `블록 ${p.brickBig ? '2×2' : '1×2'} ×${p.bricks} (우클릭)${dir}`;
  } else crosshair.dataset.ammo = '';
}

// 입력 전송
setInterval(() => {
  if (!state || state.phase !== 'playing') return;
  send(debug.inputOverride || input.sample());
}, 1000 / C.INPUT_SEND_RATE);

let last = performance.now();
let frameErrorShown = false;
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  const p = me();
  const view = p && p.alive && p.controlling ? 'sky' : 'fps';
  input.sky = view === 'sky';
  // 한 프레임에서 에러가 나도 다음 프레임은 계속 그린다 (안 그러면 서버는 도는데 화면만 멈춤)
  try {
    renderer.render(state, myId, dt, view, { yaw: input.yaw, pitch: input.pitch });
    updateHud();
  } catch (err) {
    if (!frameErrorShown) console.error('프레임 에러 (계속 그림):', err);
    frameErrorShown = true;
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
connect();

// 디버그용 (자동 테스트·콘솔에서 입력 주입).
// window.__tf.send({type:'action', name:'push'}) / window.__tf.inputOverride = {type:'input', fwd:1, ...}
const debug = {
  send,
  getState: () => state,
  getMyId: () => myId,
  input,
  inputOverride: null,
  renderer,
  sound,
  // 클릭과 같은 경로로 행동 보내기 (로컬 팔 휘두르기·소리 포함)
  act: (action) => {
    onLocalAction(action);
    send({ type: 'action', ...action });
  },
};
window.__tf = debug;
