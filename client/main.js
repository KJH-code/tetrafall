// 클라이언트 진입점: WebSocket 연결, 상태 수신, 입력 전송, 렌더 루프, HUD.
import { CONFIG as C } from '/shared/config.js';
import { Renderer, PLAYER_COLORS, damageColor } from '/render.js';
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
  if (action.name === 'push' && state && state.phase === 'playing' && p && p.alive && !p.controlling && !p.stunned) {
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

// 화면에 보이는 이름: 입력한 이름이 있으면 그것, 없으면 P1 같은 기본 이름 (서버 로그는 늘 P1)
function shownName(p) {
  return p.nick || p.name;
}

function nameOf(id) {
  const p = state && state.players.find((x) => x.id === id);
  return p ? shownName(p) : '?';
}

// 사람이 입력한 이름을 innerHTML 에 넣을 때 (맨 위 승수)
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

const KIND_KO = { push: '밀치기', projectile: '투사체', weapon: '망치', shock: '설치 블록 충격파', bomb: '폭탄' };
const ITEM_KO = { control: '조종권', knockback: '투사체', weapon: '망치', jump: '점프력 상승', ghost: '유령화', brick: '설치 블록', bomb: '폭탄' };
const ITEM_HELP = {
  control: '조종권 획득! 블록을 하늘에서 조종합니다',
  knockback: '투사체 획득! (2번 칸) 우클릭으로 발사',
  weapon: `망치 획득! ${C.WEAPON_USES}번 동안 좌클릭이 2배로 밀고 오래 기절시킴`,
  jump: `점프력 상승! ${C.JUMP_BOOST_MS / 1000}초 동안 2칸 벽도 넘음`,
  ghost: `유령화! ${C.GHOST_MS / 1000}초 동안 블록 통과 (떨어지는 블록엔 깔림)`,
  brick: `설치 블록 1×2 ${C.BRICK_USES}개! (2번 칸) 우클릭으로 조준한 곳(최대 ${C.BRICK_RANGE}칸)에 떨어뜨림 · 깔리면 압사, 옆은 충격파 · Q/E 로 앞↔옆`,
  bomb: `폭탄! (3번 칸) 우클릭으로 던지면 ${C.BOMB_FUSE_MS / 1000}초 뒤 터져 블록을 부수고 근처 사람을 날림`,
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
    case 'build': {
      const [x, y, z] = e.cells[0];
      fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.5 }, null, 0x9ab0e0, 5, 1.8, 0.07, 0.3);
      sound.play('land', { dist: e.who === myId ? 0 : distToMe(x + 0.5, y + 0.5, z) });
      return;
    }
    case 'bombPlace':
      sound.play('tick', { dist: e.who === myId ? 0 : distToMe(e.x + 0.5, e.y + 0.5, e.z) });
      return;
    case 'boom': {
      const d = distToMe(e.x, e.y, e.z);
      fx.burst({ x: e.x, y: e.y, z: e.z }, null, 0xff7020, 40, 9, 0.16, 0.7);
      fx.burst({ x: e.x, y: e.y, z: e.z }, null, 0x555555, 24, 5, 0.12, 0.9);
      fx.ring({ x: e.x, y: e.y, z: e.z }, 0xffa040, 4.5);
      sound.play('boom', { dist: d });
      if (d !== undefined && d < 6) fx.shake(0.35 * (1 - d / 6), 450);
      return;
    }
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
      if (nameInput.value) submitName();
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
// Enter 로도 시작·재시작 (호스트만, 판 사이에만. 판 중 Enter 는 블록 하드드롭)
document.addEventListener('keydown', (e) => {
  if (e.code !== 'Enter' || !state || state.hostId !== myId || !state.canStart) return;
  if (state.phase !== 'lobby' && state.phase !== 'over') return;
  e.preventDefault();
  send({ type: 'start' });
});
$('add-bot').addEventListener('click', () => send({ type: 'addBot' }));
$('remove-bot').addEventListener('click', () => send({ type: 'removeBot' }));
$('map-select').addEventListener('change', (e) => send({ type: 'setMap', map: e.target.value }));
const MAP_KO = { random: '무작위', flat: '평지', pyramid: '피라미드', stairs: '계단', bowl: '그릇', spiral: '나선 계단', pillars: '기둥 숲', fortress: '요새' };

// 이름: 대기 화면 입력칸. 브라우저에 기억해 두고 접속할 때마다 보낸다 (판 사이에만 바뀜)
const nameInput = $('name-input');
nameInput.maxLength = C.NAME_MAX_LEN;
function savedName() {
  try {
    return localStorage.getItem('tf-name') || '';
  } catch {
    return '';
  }
}
function submitName() {
  const name = nameInput.value;
  try {
    localStorage.setItem('tf-name', name);
  } catch {
    // 저장이 막혀 있어도 이번 접속에는 보낸다
  }
  send({ type: 'setName', name });
}
nameInput.value = savedName();
nameInput.addEventListener('change', submitName);
nameInput.addEventListener('keydown', (e) => {
  e.stopPropagation(); // 이름 칠 때는 게임 키(Enter 시작, 숫자 칸)가 안 먹게
  if (e.code === 'Enter') {
    submitName();
    nameInput.blur();
  }
});

function me() {
  return state ? state.players.find((p) => p.id === myId) : null;
}

// ---------- 큰 글씨: 카운트다운 3·2·1·시작!, 판 끝 "P2 승리!" ----------
const bigmsg = $('bigmsg');
let bigUntil = 0; // 이 시각까지는 카운트다운이 덮어쓰지 않음 (시작!·승리 표시)
let lastCount = null;
function showBig(text, color = '#fff', ms = 800, small = false) {
  bigmsg.textContent = text;
  bigmsg.style.color = color;
  bigmsg.classList.toggle('small', small);
  bigmsg.classList.remove('hidden');
  bigUntil = performance.now() + ms;
}
function updateBig() {
  const now = performance.now();
  if (state && state.phase === 'countdown') {
    const n = Math.max(1, Math.ceil(state.round.countdownLeft / 1000));
    if (n !== lastCount) {
      sound.play('tick');
      lastCount = n;
    }
    showBig(String(n), '#fff', 0);
    return;
  }
  if (now > bigUntil) bigmsg.classList.add('hidden');
}
function colorOf(p) {
  return `#${PLAYER_COLORS[p.slot % PLAYER_COLORS.length].toString(16).padStart(6, '0')}`;
}

function onState() {
  const p = me();
  if (!p) return;
  if (lastState && lastState.phase === 'countdown' && state.phase === 'playing') {
    lastCount = null;
    sound.play('go');
    showBig('시작!', '#ffe14a', 700);
  }
  if (lastState && lastState.phase === 'playing' && state.phase === 'over') {
    const w = state.players.find((x) => x.id === state.round.winnerId);
    sound.play('win');
    if (w) showBig(`${shownName(w)} 승리!`, colorOf(w), C.WIN_BANNER_MS, true);
    else showBig('무승부', '#ddd', C.WIN_BANNER_MS, true);
  }
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

// ---------- 승수 (맨 위) ----------
// 2명이면 "P1 3 : 1 P2", 3명 이상이면 "P1 3 · P2 1 · P3 0". 바뀔 때만 다시 그림
const scoreEl = $('score');
let scoreKey = '';
function updateScore() {
  const ps = [...state.players].sort((a, b) => a.slot - b.slot);
  const key = ps.map((p) => `${p.id}:${p.wins}:${p.nick}`).join(',') + `|${myId}`;
  if (key === scoreKey) return;
  scoreKey = key;
  scoreEl.classList.toggle('hidden', ps.length < 2);
  const name = (p) => `<span style="color:${colorOf(p)}" class="${p.id === myId ? 'me' : ''}">${escapeHtml(shownName(p))}</span>`;
  if (ps.length === 2) {
    const [a, b] = ps;
    scoreEl.innerHTML = `${name(a)} ${a.wins}<span class="sep">:</span>${b.wins} ${name(b)}`;
  } else {
    scoreEl.innerHTML = ps.map((p) => `${name(p)} ${p.wins}`).join('<span class="sep">·</span>');
  }
}

// ---------- HUD ----------
function updateHud() {
  if (!state) return;
  const p = me();
  const isHost = state.hostId === myId;
  const alive = state.players.filter((x) => x.alive).length;
  const lines = [];
  lines.push(`${p ? (p.nick ? `${p.nick} (${p.name})` : p.name) : '?'}${isHost ? ' (호스트)' : ''} · 라운드 ${state.round.n} · ${fmt(state.round.elapsed)}${state.map && state.round.n ? ` · ${state.map.name}` : ''}`);
  const maxP = Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
  lines.push(`플레이어 ${state.players.length}/${maxP} · 생존 ${alive}`);
  if (p && state.phase === 'playing') {
    // 피해 %·경직·버프·핫바는 화면 아래 가운데 (updateBottom). 여기엔 사망과 용암만
    if (!p.alive) lines.push(`사망 (${CAUSE_KO[p.cause] || p.cause})`);
    if (state.lava && state.lava.active) {
      const above = p.alive ? (p.z - state.lava.z).toFixed(1) : '-';
      lines.push(`용암 높이 ${Math.max(0, state.lava.z).toFixed(1)} · 내 발 위로 ${above}칸`);
    }
  }
  const t = state.round.totals;
  lines.push(`누적 ${t.rounds}판 · 압사 ${t.crush} · 낙사 ${t.fall} · 용암 ${t.lava || 0}`);
  statusEl.textContent = lines.join('\n');

  updateScore();
  updateBig();
  updateBottom(p);

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
    center = `라운드 ${state.round.n} 종료\n승자: ${w ? shownName(w) : '무승부'}`;
    showStart = isHost && state.canStart;
    showKeys = true;
  } else if (p && !p.alive) {
    center = `사망: ${CAUSE_KO[p.cause] || p.cause}\n관전 중`;
  } else if (state.phase === 'countdown') {
    center = null; // 3·2·1 큰 글씨만 (화면 클릭으로 조작 잡기는 그대로 됨)
  } else if (!input.locked) {
    center = '화면을 클릭하면 조작 시작';
    showKeys = true;
  }
  if (state.phase === 'over' && performance.now() < bigUntil) center = null; // "P2 승리!" 가 떠 있는 동안은 안내판을 감춤
  centerEl.classList.toggle('hidden', center === null);
  centerText.textContent = center || '';
  startBtn.classList.toggle('hidden', !showStart);
  startBtn.textContent = state.phase === 'over' ? '재시작 (Enter)' : '시작 (Enter)';
  keysEl.classList.toggle('hidden', !showKeys);
  // 봇 버튼: 호스트만, 판 사이에만
  const between = state.phase === 'lobby' || state.phase === 'over';
  $('name-row').classList.toggle('hidden', !between);
  const showBots = isHost && between;
  $('bot-btns').classList.toggle('hidden', !showBots);
  // 맵: 호스트는 고르고, 다른 사람은 보기만
  const mapSel = $('map-select');
  if (state.map && document.activeElement !== mapSel) mapSel.value = state.map.choice;
  const mapInfo = $('map-info');
  mapInfo.classList.toggle('hidden', !(state.map && !isHost && between));
  if (state.map) mapInfo.textContent = `맵: ${MAP_KO[state.map.choice] || state.map.choice}`;
  if (showBots) {
    $('add-bot').disabled = state.players.length >= Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
    $('remove-bot').disabled = !state.players.some((x) => x.isBot);
  }

  input.enabled = (state.phase === 'playing' || state.phase === 'countdown') && !!p && p.alive; // 카운트다운 중엔 시선만 (서버가 이동·행동을 막음)
  // 조준점: 고른 핫바 칸에 따라 색. 2번 투사체 = 빨강, 2번 설치 블록 = 노랑, 3번 폭탄 = 주황 (자세한 건 아래 핫바)
  const armed = !!p && p.hand === 2 && p.ammo > 0;
  const brick = !!p && p.hand === 2 && p.bricks > 0;
  const bomb = !!p && p.hand === 3 && p.bombs > 0;
  crosshair.classList.toggle('hidden', !(input.enabled && !p.controlling));
  crosshair.classList.toggle('armed', armed || brick || bomb);
  crosshair.classList.toggle('brick', brick);
  crosshair.classList.toggle('bomb', bomb);
  crosshair.dataset.ammo = '';
}

// ---------- 화면 아래: 피해 % · 경직 · 버프 · 핫바 ----------
$('build-n').textContent = C.BUILD_BLOCKS_PER_ROUND; // 조작법 패널 숫자는 config 에서
const bottomEl = $('bottom');
const damageEl = $('damage');
const buffsEl = $('buffs');
const stunEl = $('stun');
const vignetteEl = $('vignette');
const slotEls = [1, 2, 3].map((n) => document.querySelector(`#hotbar .slot[data-n="${n}"]`));
let shownDamage = null;
let bottomKey = '';
function updateBottom(p) {
  const show = !!p && p.alive && (state.phase === 'playing' || state.phase === 'countdown');
  bottomEl.classList.toggle('hidden', !show);
  const stunned = show && p.stunned;
  stunEl.classList.toggle('hidden', !stunned);
  vignetteEl.classList.toggle('on', stunned);
  if (!show) return;
  if (shownDamage !== p.damage) {
    if (shownDamage !== null && p.damage > shownDamage) {
      damageEl.classList.add('pop'); // 맞으면 잠깐 커졌다 줄어듦
      setTimeout(() => damageEl.classList.remove('pop'), 140);
    }
    shownDamage = p.damage;
    damageEl.textContent = `${p.damage}%`;
    damageEl.style.color = damageColor(p.damage);
  }
  const buffs = [];
  if (p.weaponUses > 0) buffs.push(`망치 ${p.weaponUses}회`);
  if (p.jumpLeft > 0) buffs.push(`점프↑ ${(p.jumpLeft / 1000).toFixed(1)}s`);
  if (p.ghostLeft > 0) buffs.push(`유령 ${(p.ghostLeft / 1000).toFixed(1)}s`);
  if (p.dashCd > 0) buffs.push(`대시 ${(p.dashCd / 1000).toFixed(1)}s`);
  const slots = [
    p.blocks > 0 ? `쌓기 ×${p.blocks}` : '쌓기 —',
    p.ammo > 0 ? `투사체 ×${p.ammo}` : p.bricks > 0 ? `설치 1×2 ×${p.bricks} ${p.brickSide ? '옆' : '앞'}` : '아이템 —',
    p.bombs > 0 ? `폭탄 ×${p.bombs}` : '폭탄 —',
  ];
  const key = `${buffs.join('|')}#${slots.join('|')}#${p.hand}`;
  if (key === bottomKey) return;
  bottomKey = key;
  buffsEl.innerHTML = buffs.map((b) => `<span class="buff">${b}</span>`).join('');
  slotEls.forEach((el, i) => {
    el.querySelector('.name').textContent = slots[i];
    el.classList.toggle('sel', p.hand === i + 1);
    el.classList.toggle('empty', slots[i].endsWith('—'));
  });
}

// 입력 전송
setInterval(() => {
  if (!state || (state.phase !== 'playing' && state.phase !== 'countdown')) return;
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
