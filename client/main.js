// 클라이언트 진입점: WebSocket 연결, 상태 수신, 입력 전송, 렌더 루프, HUD.
import { CONFIG as C } from '/shared/config.js';
import { Renderer, TEAM_MAIN, playerColor, damageColor } from '/render.js';
import { Input } from '/input.js';
import { ACTIONS, DEFAULT_BINDS, keyLabel, groupLabel, normCode, saveBinds, conflicts } from '/keys.js';
import { Sound } from '/sound.js';
import { Music } from '/music.js';
import { loadModels } from '/models.js';
import { portrait, setPortraitModels } from '/portrait.js';
import { NetStatus } from '/net.js';
import { KO } from '/ko.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
const centerEl = $('center');
const centerText = $('center-text');
const startBtn = $('start-btn');
const keysEl = $('keys');
const crosshair = $('crosshair');
const flash = $('flash');
const banner = $('banner');
const dangerEl = $('danger');
let lastDanger = null; // 지난 프레임의 압사 경고 (처음 뜰 때만 경고음)
const toasts = $('toasts');

// 모델은 먼저 불러온다 (실패하면 예전 도형으로)
const models = await loadModels().catch((err) => {
  console.warn('모델을 못 불러와 기본 도형으로 그림:', err);
  return null;
});
setPortraitModels(models); // 초상(HUD 판·캐릭터 카드)도 같은 모델로
const renderer = new Renderer(document.body, models);
let ws = null;
let myId = null;
let state = null;
let lastState = null;
let wasAlive = true;
let closed = false; // 연결이 끊기면 HUD 갱신을 멈춰 끊김 메시지가 덮이지 않게

function send(obj) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}
const sound = new Sound();
const music = new Music(sound);
const fx = renderer.effects;
// KO 연출 (client/ko.js): 스매시 줄기·마지막 킬 슬로모션·압사. 소리는 ko.on('smash'|'final'|'crush', cb)
const ko = new KO(renderer.scene, fx, {
  colorOf: (id) => {
    const p = playerById(id);
    return p ? playerColor(p, state) : 0xffffff;
  },
  lowGfx: () => settings.lowGfx,
  field: () => ({ w: state?.field?.w ?? C.GRID_W, d: state?.field?.d ?? C.GRID_D }),
});
renderer.camHook = (cam) => ko.camHook(cam);
// KO 소리: 스매시 쾅·압사 쿵 (거리·좌우), 마지막 킬 = 낮게 늘어진 쾅 + 음악 잠깐 줄임
ko.on('smash', (i) => sound.play('smash', { dist: i.me ? 0 : undefined, pos: i, strong: i.me || i.near }));
ko.on('crush', (i) => sound.play('koCrush', { dist: i.me ? 0 : undefined, pos: i, strong: i.me || i.near }));
ko.on('final', (i) => {
  sound.play('final', { pos: i });
  music.duck(C.KO_FINAL_MS / 1000);
});
// 건축가 블록이 한 칸 터질 때 (연쇄는 칸마다 차례로): 소리 + 가까우면 흔들림
renderer.onBlast = (pos, big) => {
  const d = distToMe(pos.x, pos.y, pos.z);
  sound.play('boom', { dist: d, pos });
  if (d !== undefined && d < (big ? 7 : 4)) fx.shake(big ? 0.4 : 0.15, big ? 450 : 200);
};
renderer.onArrowStuck = (pos) => sound.play('land', { dist: distToMe(pos.x, pos.y, pos.z) }); // 화살이 블록에 박힘
if (typeof renderer.onHazardRise === 'function') renderer.onHazardRise((h) => sound.hazardRise(h)); // 위험 액체가 차오르는 순간 (렌더러 훅, 없으면 sound.update 가 state.lava 로 감지)
document.addEventListener('pointerdown', () => sound.unlock());
document.addEventListener('keydown', () => sound.unlock());

// 내 밀치기는 서버 응답을 기다리지 않고 바로 팔을 휘두르고 소리를 낸다 (조작감)
function onLocalAction(action) {
  const p = me();
  if (action.name === 'push' && state && state.phase === 'playing' && p && p.alive && !p.controlling && !p.stunned) {
    fx.startPunch(myId);
    sound.play('swing', { char: p.char });
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

const KIND_KO = { push: '밀치기', projectile: '투사체', shock: '설치 블록 충격파', bomb: '폭탄', charge: '돌진', slam: '내려찍기', slash: '순간 베기', wall: '솟는 벽', hook: '갈고리', blockslam: '블록내려찍기', blast: '블록 폭발', bigbomb: '대폭발', wallkick: '벽차기', quake: '솟는 땅', ghost: '유령블록' };
const ITEM_KO = { control: '조종권', knockback: '투사체', jump: '점프력 상승', ghost: '유령화', brick: '설치 블록', bomb: '폭탄', speed: '이속 증가' };
const CAUSE_KO = { crush: '압사', fall: '낙사', lava: '용암' };
const WEAPON_KO = { push: '밀치기', projectile: '투사체', shock: '충격파', bomb: '폭탄', control: '조종 블록', thrown: '설치 블록', charge: '돌진', slam: '내려찍기', slash: '순간 베기', wall: '솟는 벽', hook: '갈고리', blockslam: '블록내려찍기', blast: '블록 폭발', bigbomb: '대폭발', wallkick: '벽차기', quake: '솟는 땅', ghost: '유령블록', glide: '낙하 음파' };

// 오른쪽 위 킬 피드: "죽인 사람 → 죽은 사람 낙사 (망치)". 내가 낀 줄은 노란 테두리
const killfeedEl = $('killfeed');
function killFeed(e) {
  const victim = playerById(e.who);
  const killer = e.by !== null ? playerById(e.by) : null;
  const row = document.createElement('div');
  row.className = `kill${e.who === myId || e.by === myId ? ' mine' : ''}`;
  const name = (p, fallback) => {
    const span = document.createElement('span');
    span.textContent = p ? shownName(p) : fallback || '?';
    if (p) span.style.color = colorOf(p);
    return span;
  };
  const how = document.createElement('span');
  how.className = 'how';
  how.textContent = ` ${CAUSE_KO[e.cause] || e.cause}${e.weapon ? ` (${WEAPON_KO[e.weapon] || e.weapon})` : ''}`;
  if (e.by !== null) row.append(name(killer, e.byName), ' → ');
  row.append(name(victim), how);
  killfeedEl.appendChild(row);
  while (killfeedEl.children.length > C.KILLFEED_MAX) killfeedEl.firstChild.remove();
  setTimeout(() => (row.style.opacity = 0), C.KILLFEED_MS);
  setTimeout(() => row.remove(), C.KILLFEED_MS + 600);
}

// 대기 화면 '조작법' 버튼: 긴 설명은 눌렀을 때만
$('keys-btn').addEventListener('click', () => $('keys-text').classList.toggle('hidden'));
// 판 중 조작법: 도움말 키(기본 H)를 누르고 있는 동안만 (글이 화면을 덮지 않게)
// 시점 키(기본 V): 1인칭 ↔ 3인칭 (설정에도 같은 칸, 이 브라우저에 기억)
const helpEl = $('help');
input.onUi = (id, down) => {
  if (id === 'help') helpEl.classList.toggle('hidden', !down);
  if (id === 'practice' && down) setPracticeOpen(!practiceOpen); // 연습 방에서만 열림
  if (id === 'view' && down) {
    settings.third = !settings.third;
    $('set-third').checked = settings.third;
    applySettings();
    saveSettings();
  }
};

// 화면에 보이는 키 글자: [data-key="skill"] → 그 행동의 키, [data-keys="fwd,left,back,right"] → 묶어서 (WASD)
const keyText = (id) => keyLabel(input.binds[id]);
const pieceKeysText = () => `${groupLabel(input.binds, ['pieceUp', 'pieceDown', 'pieceLeft', 'pieceRight'])} 이동 · ${groupLabel(input.binds, ['rotL', 'rotR'])} 회전 · ${keyText('drop')} 낙하`;
function refreshKeyLabels() {
  for (const el of document.querySelectorAll('[data-key]')) el.textContent = keyText(el.dataset.key);
  for (const el of document.querySelectorAll('[data-keys]')) el.textContent = groupLabel(input.binds, el.dataset.keys.split(','));
}

// 콤보 'N HIT' (때린 쪽 노랑, 맞은 쪽 빨강)
const comboEl = $('combo');
let comboTimer = null;
function showCombo(n, taken, finish) {
  comboEl.textContent = `${n} HIT${finish ? '!!' : '!'}`;
  comboEl.classList.toggle('taken', taken);
  comboEl.classList.remove('hidden');
  clearTimeout(comboTimer);
  comboTimer = setTimeout(() => comboEl.classList.add('hidden'), C.COMBO_TEXT_MS);
}

// 카운터히트 'COUNTER!' (넣은 쪽 하늘색, 당한 쪽 빨강). 콤보 글자 바로 위에 짧게
const counterEl = $('counter');
let counterTimer = null;
function showCounter(taken) {
  counterEl.classList.toggle('taken', taken);
  counterEl.classList.remove('hidden');
  counterEl.style.animation = 'none'; // 연달아 와도 다시 튀어나오게
  void counterEl.offsetWidth;
  counterEl.style.animation = '';
  clearTimeout(counterTimer);
  counterTimer = setTimeout(() => counterEl.classList.add('hidden'), C.COUNTER_TEXT_MS);
}

let myStreak = 0; // 내가 이어 넣은 타 수 (streak 이벤트, 상대가 바뀌어도 이어짐)
function handleEvent(e) {
  // 닌자 표창에 맞음: 판정은 즉시지만 맞는 효과는 표창이 날아가 닿을 때 (STAR_FLY_MS 뒤)
  if (e.type === 'hit' && e.star && !e.late) {
    setTimeout(() => handleEvent({ ...e, late: true }), C.STAR_FLY_MS);
    return;
  }
  feelEvent(e);
  switch (e.type) {
    case 'ultFail': // 내 R 을 못 씀: R 칸이 빨갛게 흔들림 + 아주 짧은 글자
      if (e.who === myId) slotFail(e.reason);
      return;
    // ---- 사냥꾼 ----
    case 'mark': {
      // 표식 +1: 맞은 사람 머리 위에서 빨간 불꽃 (개수는 snapshot marks 로 머리 위에)
      const t = playerById(e.target);
      if (t) fx.burst({ x: t.x, y: t.y, z: t.z + C.PLAYER_HEIGHT + 0.3 }, null, 0xff3a2a, 10 + e.n * 4, 2.5, 0.08, 0.4);
      if (e.by === myId || e.target === myId) sound.play('pickup', { dist: 0 });
      return;
    }
    case 'markGone': {
      const t = playerById(e.target);
      if (t) fx.burst({ x: t.x, y: t.y, z: t.z + C.PLAYER_HEIGHT + 0.3 }, null, 0x886666, 5, 1.2, 0.06, 0.3);
      return;
    }
    case 'leapWarn': {
      // 추적 도약 예고: 네 발로 웅크림 + 덮칠 대상까지 바닥에 빨간 줄
      renderer.skillMove(e.who, 'hunterLeap', e.ms);
      const a = playerById(e.who);
      const t = e.target !== null && e.target !== undefined ? playerById(e.target) : null;
      if (a && t) renderer.trail({ x: a.x, y: a.y, z: a.z + 0.08 }, { x: t.x, y: t.y, z: t.z + 0.08 }, 0xff3020, e.ms + C.HUNTER_LEAP_MS);
      if (a) fx.burst({ x: a.x, y: a.y, z: a.z + 0.1 }, null, 0xc0a070, 6, 1.5, 0.08, 0.3);
      break;
    }
    case 'leap':
      renderer.skillStrike(e.who, 'hunterLeap');
      fx.burst({ x: e.from.x, y: e.from.y, z: e.from.z + 0.1 }, null, 0xc0a070, 14, 3.5, 0.11, 0.45);
      sound.play('swing', { dist: e.who === myId ? 0 : distToMe(e.from.x, e.from.y, e.from.z) });
      setTimeout(() => fx.burst({ x: e.to.x, y: e.to.y, z: e.to.z + 0.1 }, null, 0xc0a070, 12, 3, 0.1, 0.4), e.ms);
      break;
    case 'aim': {
      // 처형 사격 조준: 석궁을 꺼내 겨눔 + 대상마다 빨간 조준점. 내가 대상이면 화면 가장자리가 붉게 + 째깍
      renderer.skillMove(e.who, 'hunterAim', e.ms);
      renderer.aimAt(e);
      if ((e.targets || []).includes(myId)) {
        flashScreen('rgba(255,0,0,.22)');
        sound.play('tick', { dist: 0 });
      }
      break;
    }
    case 'shot': {
      renderer.skillStrike(e.who, 'hunterAim');
      renderer.shoot(e);
      sound.play('fire', { dist: e.who === myId ? 0 : distToMe(e.from.x, e.from.y, e.from.z), pos: e.from, char: playerById(e.who)?.char });
      break;
    }
    case 'ultRefund': // 표식 3개 대상을 맞혀 R 게이지 돌려받음: 노란 빛 + 내 R 칸 반짝
      renderer.aura(e.who, true);
      if (e.who === myId) {
        const r = $('skill-r');
        r.classList.remove('glint');
        void r.offsetWidth;
        r.classList.add('glint');
        sound.play('pickup', { dist: 0 });
      }
      break;
    case 'castDrop': // 기억해 둔 F·R 이 버려짐: 그 칸이 살짝 깜빡 (글자 없음)
      if (e.who === myId) slotBlink(e.kind === 'ult' ? 'skill-r' : 'skill-f');
      return;
    case 'skill':
    case 'ult': {
      // 쓰는 순간 그 캐릭터 둘레에 빛 (스킬 빨강, 필살기 노란 빛기둥). 글자 없이, 누가 무엇인지는 캐릭터 모양으로
      const a = playerById(e.who);
      if (!a) break;
      const ult = e.type === 'ult';
      renderer.aura(e.who, ult);
      fx.burst({ x: a.x, y: a.y, z: a.z + 0.9 }, null, ult ? C.ULT_AURA_COLOR : C.SKILL_AURA_COLOR, ult ? 22 : 10, 4, 0.1, 0.45);
      sound.play(ult ? 'boom' : 'swing', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      break;
    }
    case 'attack': // 평타 준비 시작 → 몸 동작 (준비 자세가 상대가 읽는 예고)
      renderer.attackStart(e);
      break;
    case 'swing': // 판정 순간 → 타격 자세 (나 포함)
      renderer.attackSwing(e);
      break;
    case 'interrupt': // 내 공격이 맞아서 끊김: 글자 없이 몸 동작만
      renderer.interrupt(e.who);
      if (e.kind === 'skill') renderer.hookCancel(e.who); // 날아가던 갈고리는 감김 (준비 번쩍도 멈춤)
      if (e.kind === 'skill') renderer.windupUntil.delete(e.who);
      if (e.kind === 'ult') renderer.aimEnd(e.who); // 조준 중에 끊긴 처형 사격
      if (e.kind === 'ult' && playerById(e.who)?.char === 'berserker') renderer.setDizzy(e.who, C.BERSERK_DIZZY_S * 0.5); // 끊긴 소용돌이: 휘청 + 잠깐 어지러움
      break;
    case 'blink': // 닌자 순간 베기: 손발 다 뻗고 돌진 + 몸이 빠르게 미끄러져 감 (잔상·바람 줄) (공중에서도)
      renderer.skillMove(e.who, 'ninjaDash');
      renderer.blinkSlide(e);
      fx.burst({ x: e.from.x, y: e.from.y, z: e.to.z + 0.8 }, null, 0x404060, 10, 2, 0.1, 0.4);
      fx.burst({ x: e.to.x, y: e.to.y, z: e.to.z + 0.8 }, null, 0x404060, 10, 2, 0.1, 0.4);
      renderer.trail({ x: e.from.x, y: e.from.y, z: e.to.z + 0.9 }, { x: e.to.x, y: e.to.y, z: e.to.z + 0.9 }, 0xffffff, 280);
      break;
    case 'wallKick': {
      // 닌자 벽 차기: 몸을 돌려 블록을 차고 '슈우욱' 위로 + 찬 자리에 '쾅' 충격파
      renderer.skillMove(e.who, 'ninjaWallKick');
      const wall = { x: e.x + e.dir.x * 0.5, y: e.y + e.dir.y * 0.5, z: e.z + 0.6 };
      fx.ring(wall, 0xffffff, 3, 0.3);
      fx.ring({ x: e.x, y: e.y, z: e.z + 0.1 }, 0xffffff, C.NINJA_WALLKICK_RANGE * 2, 0.35, true);
      fx.burst(wall, { x: -e.dir.x, y: -e.dir.y }, 0xb0a090, 14, 4, 0.1, 0.45);
      renderer.streakUp({ x: e.x, y: e.y, z: e.z + 0.2 }, 2.4, 0xffffff, 300);
      const d = e.who === myId ? 0 : distToMe(e.x, e.y, e.z);
      sound.play('airJump', { dist: d });
      sound.play('land', { dist: d });
      if (d !== undefined && d < 3) fx.shake(0.12, 180);
      break;
    }
    case 'empower': {
      // 닌자 R 강화 시작: 보라 불티가 확 (강화 중 깜빡임은 render.js 가 snapshot empower 로)
      const a = playerById(e.who);
      if (a) fx.burst({ x: a.x, y: a.y, z: a.z + 1 }, null, C.EMPOWER_GLOW, 24, 5, 0.1, 0.6);
      break;
    }
    case 'star': // 닌자 표창 한 발: 던지는 팔 + 빠르게 직진하는 표창
      renderer.starShot(e);
      sound.play('swing', { dist: e.who === myId ? 0 : distToMe(e.from.x, e.from.y, e.from.z) });
      break;
    case 'streak': // 때린 쪽이 이어 넣은 타 수 (닌자 갈아타기): 내 'N HIT' 는 이걸로 셈
      if (e.who === myId) {
        myStreak = e.n;
        showCombo(e.n, false, false);
      }
      break;
    case 'armor': {
      // 탱크 아머로 버팀: 몸이 하얗게 번쩍 + 쇠 불꽃 + 쨍 (안 휘청, 얼굴만 찡그림)
      renderer.armorHit(e.who);
      const a = playerById(e.who);
      if (a) {
        fx.burst({ x: a.x, y: a.y, z: a.z + 1 }, null, 0xfff0a0, 14, 6, 0.06, 0.3);
        sound.play('crit', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      }
      break;
    }
    case 'armorBreak': {
      // 아머 깨짐: 유리 깨지듯 하늘빛 파편이 사방으로 + 고리 (그 타에 크게 휘청)
      renderer.armorBreak(e.who);
      const a = playerById(e.who);
      if (a) {
        const pos = { x: a.x, y: a.y, z: a.z + 1 };
        fx.burst(pos, null, 0xd8f0ff, 30, 9, 0.11, 0.6);
        fx.burst(pos, null, 0x9ab8d0, 16, 6, 0.08, 0.5);
        fx.ring(pos, 0xd8f0ff, 3.4, 0.3);
        sound.play('crush', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      }
      break;
    }
    case 'quakeRise': {
      // 탱크 R 바깥 고리: 땅이 솟음 (흙먼지, 가까우면 흔들림)
      renderer.quakeRise(e.cells, e.ms, e.id);
      for (const [x, y, z] of e.cells) {
        fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.1 }, null, C.QUAKE_COLOR, 6, 4, 0.12, 0.5);
        fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.6 }, { x: 0, y: 0 }, 0x6a5e52, 2, 5, 0.16, 0.5); // 튀는 흙덩이
      }
      const [x, y, z] = e.cells.reduce((a, c) => a.map((v, i) => v + c[i] / e.cells.length), [0, 0, 0]);
      fx.ring({ x: x + 0.5, y: y + 0.5, z: z + 0.05 }, C.QUAKE_COLOR, 6, 0.35, true);
      const d = distToMe(x + 0.5, y + 0.5, z);
      sound.play('land', { dist: d });
      sound.play('boom', { dist: (d ?? 0) + 3 });
      if (d !== undefined && d < 8) fx.shake(0.28, 350);
      break;
    }
    case 'quakeFall': // 솟은 땅이 가라앉음
      renderer.quakeFall(e.gone || e.cells || [], e.id);
      for (const [x, y, z] of e.gone || e.cells || []) fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.1 }, null, C.QUAKE_COLOR, 4, 2, 0.1, 0.45);
      if ((e.gone || e.cells || []).length) sound.play('land', { dist: distToMe((e.gone || e.cells)[0][0] + 0.5, (e.gone || e.cells)[0][1] + 0.5, (e.gone || e.cells)[0][2]) });
      break;
    case 'ninjaTouch': {
      // 닌자가 떨어지는 블록을 밟아 공중 점프 회복: 발밑에 흰 김 + 작은 고리
      const a = playerById(e.who);
      if (a) {
        fx.burst({ x: a.x, y: a.y, z: a.z }, null, 0xffffff, 8, 2.5, 0.08, 0.35);
        fx.ring({ x: a.x, y: a.y, z: a.z + 0.05 }, 0xffffff, 1.4, 0.25, true);
        fx.burst({ x: a.x, y: a.y, z: a.z + 0.05 }, null, 0xfff4b0, 6, 3, 0.05, 0.25); // 반짝
        sound.play('tap', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      }
      // 밟힌 블록이 번쩍하며 꾹 눌림
      const pc = state?.pieces?.find((q) => q.id === e.piece);
      if (pc) renderer.blockPulse(pc.cells, 0xffffff, { ms: C.BLOCK_PULSE_MS * 0.8, jolt: -C.BLOCK_JOLT * 1.5, opacity: 0.6 });
      break;
    }
    case 'charge': // 탱크 방패 돌진: 가는 길에 흙먼지 줄 + 돌진 동안 아머 (몸이 금속처럼 번쩍)
      renderer.armorOn(e.who, C.TANK_CHARGE_MS + 120);
      renderer.skillMove(e.who, 'tankCharge');
      renderer.trail({ x: e.x, y: e.y, z: e.z + 0.15 }, { x: e.x + Math.cos(e.yaw) * 3, y: e.y + Math.sin(e.yaw) * 3, z: e.z + 0.15 }, 0xc0a070, 400);
      fx.burst({ x: e.x, y: e.y, z: e.z + 0.2 }, null, 0xc0a070, 14, 3, 0.12, 0.5);
      break;
    case 'slamWarn': // 탱크 내려찍기: 떨어질 범위를 바닥에 + 떠오르는 동안 아머
      renderer.armorOn(e.who, e.ms + 150);
      renderer.skillMove(e.who, 'tankSlam', e.ms);
      renderer.markCircle(e.x, e.y, e.z, e.r, 0xff3020, e.ms + C.WARN_TAIL_MS); // 쾅 이벤트가 닿을 때까지 끊기지 않게
      {
        // 솟을 고리 땅이 떨림: 예고 동안 고리 자리에서 흙먼지가 톡톡 + 가까우면 화면이 살짝 떨림
        const steps = Math.max(1, Math.floor(e.ms / 90));
        for (let k = 0; k < steps; k++) {
          setTimeout(() => {
            for (let n = 0; n < 4; n++) {
              const ang = Math.random() * Math.PI * 2;
              const rr = e.r + Math.random() * C.TANK_RING_WIDTH;
              fx.burst({ x: e.x + Math.cos(ang) * rr, y: e.y + Math.sin(ang) * rr, z: e.z + 0.05 }, { x: 0, y: 0 }, C.QUAKE_COLOR, 1, 1.2, 0.1, 0.4);
            }
          }, k * 90);
        }
        const dd = distToMe(e.x, e.y, e.z);
        if (dd !== undefined && dd < e.r + C.TANK_RING_WIDTH + 1.5) fx.shake(0.05, e.ms);
      }
      break;
    case 'slam': {
      renderer.armorOff(e.who);
      renderer.skillStrike(e.who, 'tankSlam');
      fx.ring({ x: e.x, y: e.y, z: e.z + 0.1 }, 0xc0b090, e.r * 2, 0.4, true);
      fx.burst({ x: e.x, y: e.y, z: e.z + 0.2 }, null, 0xc0b090, 28, 7, 0.14, 0.6);
      const me = playerById(myId);
      if (me && Math.hypot(me.x - e.x, me.y - e.y) < e.r * 2) fx.shake(0.25, 350);
      break;
    }
    case 'wallWarn': // 건축가 솟는 벽: 솟을 자리를 노랗게
      renderer.skillMove(e.who, 'builderWall', e.ms);
      renderer.markCells(e.cells, 0xffd23a, e.ms);
      break;
    case 'wallRise':
      renderer.skillStrike(e.who, 'builderWall', true); // 3타 블록도 wallRise 가 옴 → 벽 준비 중일 때만
      for (const [x, y, z] of e.cells) if (z === Math.min(...e.cells.map((c) => c[2]))) fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.1 }, null, 0xa87448, 6, 3, 0.1, 0.4);
      sound.play('land', { dist: e.who === myId ? 0 : distToMe(e.cells[0][0], e.cells[0][1], e.cells[0][2]) });
      break;
    // ---- 건축가 블록 (색·깜빡임은 render.js updateBBlocks 가 snapshot bblocks 로) ----
    case 'bblock': // 생김: 바닥에서 솟음
      renderer.bblockBorn(e.cells);
      break;
    case 'bblockGone': // 수명 끝·오래된 3타 블록: 회색 먼지
      for (const [x, y, z] of e.cells) fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.5 }, null, 0x999999, 8, 2, 0.1, 0.5);
      break;
    case 'blast': {
      // 망치로 쳐서 폭발: cells 순서대로 차례로 펑 (치는 방향으로 파편)
      const o = playerById(e.who);
      renderer.blastChain(e, o ? playerColor(o, state) : 0xc08040);
      break;
    }
    case 'bigBombWarn': {
      // 대폭발 예고: 3×3 이 솟고 빨갛게 부풀며 째깍 (점점 빠르게)
      renderer.bblockBorn(e.cells);
      renderer.skillMove(e.who, 'builderBig');
      const [cx, cy, cz] = e.cells[Math.floor(e.cells.length / 2)];
      for (const t of [0, 0.35, 0.6, 0.78, 0.9]) setTimeout(() => sound.play('tick', { dist: distToMe(cx + 0.5, cy + 0.5, cz) }), t * e.ms);
      break;
    }
    case 'bigBomb': {
      // 대폭발: 가운데 칸에서 크게 + 칸마다 파편 (치는 방향 dir)
      const o = playerById(e.who);
      const color = o ? playerColor(o, state) : 0xff4030;
      e.cells.forEach(([x, y, z], i) => renderer.bbPop({ x, y, z, dir: e.dir, hex: i % 2 ? color : 0xff5020 }, i === Math.floor(e.cells.length / 2)));
      break;
    }
    case 'padBoost': // 공중 F: 발판이 생기며 엉덩이를 차올림
      renderer.skillMove(e.who, 'builderPad');
      if (e.cell) fx.burst({ x: e.cell[0] + 0.5, y: e.cell[1] + 0.5, z: e.cell[2] + 1 }, { x: 0, y: 0 }, 0xffffff, 10, 3, 0.1, 0.4);
      break;
    case 'counter': // 카운터히트: 같은 틱의 hit 보다 먼저 옴 → 맞은 몸이 더 크게 휘청
      renderer.counterHit(e.target);
      if (e.by === myId || e.target === myId) showCounter(e.target === myId);
      break;
    case 'practiceReset': {
      // 연습: 떨어지거나 깔려서 제자리로 (안 죽음·허수아비) — 그 자리에서 하얀 김만 작게
      const t = playerById(e.who);
      if (t) fx.burst({ x: t.x, y: t.y, z: t.z + 0.6 }, null, 0xffffff, 12, 2.5, 0.12, 0.5);
      if (e.who === myId) flashScreen('rgba(255,255,255,.25)');
      break;
    }
    case 'charChange': {
      // 연습: 판 중 캐릭터 바꿈 — 플레이어 색 김이 펑 (몸은 다음 스냅샷에서 새 캐릭터로)
      const t = playerById(e.who);
      if (t) fx.burst({ x: t.x, y: t.y, z: t.z + 0.8 }, null, hex2num(colorOf(t)), 16, 3, 0.12, 0.5);
      break;
    }
    case 'mapChange': // 연습: 판 중 맵 바꿈 (격자는 gridVersion 으로 다시 그려짐)
      renderer.gridVersion = -1;
      renderer.clearQuakes();
      break;
    case 'dummyCombo': // 연습 방 허수아비 콤보 기록: 끝난 콤보는 잠깐 결과로 남김
      if (e.done) practiceDone.set(e.id, { ...e, until: performance.now() + C.PRACTICE_COMBO_SHOW_MS });
      break;
    case 'combo': // 내가 때리거나 맞은 콤보만
      if (e.finish) renderer.comboFinish(e.target); // 마무리 타는 몸이 더 크게 휘청 (모두)
      // 맞은 쪽은 맞은 타 수, 때린 쪽은 streak 로 이어 셈 (마무리 '!!' 만 여기서)
      if (e.target === myId) showCombo(e.n, true, e.finish);
      else if (e.by === myId && e.finish) showCombo(Math.max(myStreak, e.n), false, true);
      break;
    case 'skillWindup': {
      // 지상 F 준비 (닌자·탱크·갈고리): 몸이 하얗게 번쩍 + 째깍 (피하기 어려워도 보이게)
      renderer.skillWindup(e);
      const a = playerById(e.who);
      sound.play('tick', { dist: e.who === myId ? 0 : a ? distToMe(a.x, a.y, a.z) : undefined });
      break;
    }
    case 'hookThrow': {
      // 갈고리 던짐: 팔 쭉 + 갈고리 머리가 날아감 (닿는 건 hook 이벤트)
      renderer.skillStrike(e.who, 'hookThrow');
      renderer.hookThrowRope(e);
      const a = playerById(e.who);
      sound.play('swing', { dist: e.who === myId ? 0 : a ? distToMe(a.x, a.y, a.z) : undefined, pos: a, char: 'hook' });
      sound.play('latch', { dist: e.who === myId ? 0 : a ? distToMe(a.x, a.y, a.z) : undefined, pos: a });
      break;
    }
    case 'hook': {
      // 갈고리가 닿는 순간: 상대면 그 상대가 질질 끌려옴, 블록이면 내가 끌려감, 빗나가면 감김
      renderer.hookRope(e);
      const a = playerById(e.who);
      if (e.target !== null && e.target !== undefined) {
        const t = playerById(e.target);
        const dir = a && t ? { x: a.x - t.x, y: a.y - t.y } : null;
        if (dir) {
          const len = Math.hypot(dir.x, dir.y) || 1;
          dir.x /= len;
          dir.y /= len;
          renderer.hitReact(e.target, dir, {});
        }
        renderer.skillMove(e.target, 'hookDragged');
      } else if (e.block) {
        // 블록에 걸림: 그 블록이 번쩍 들썩 + 돌가루, 끌려가는 길에 바람 줄
        renderer.skillMove(e.who, 'hookZip');
        renderer.blockPulse([e.block], 0xffffff, { jolt: 0.08 });
        const c = { x: e.block[0] + 0.5, y: e.block[1] + 0.5, z: e.block[2] + 0.5 };
        fx.burst(c, null, 0x9a8a78, 8, 2.5, 0.08, 0.4);
        if (a) for (const dz of [0.4, 0.9, 1.4]) renderer.trail({ x: a.x, y: a.y, z: a.z + dz }, { x: c.x, y: c.y, z: a.z + dz }, 0xffffff, 300);
        sound.play('land', { dist: e.who === myId ? 0 : distToMe(c.x, c.y, c.z) });
      }
      break;
    }
    case 'bang': {
      // 탕: 총구에서 큰 불꽃 + 흰 섬광 + 오래 남는 연기, 소리 두 겹, 가까우면 흔들림 (팔 반동은 '탕' 동작)
      const fx0 = Math.cos(e.yaw);
      const fy0 = Math.sin(e.yaw);
      const muzzle = { x: e.x + fx0 * 0.75, y: e.y + fy0 * 0.75, z: e.z + 1.15 };
      fx.burst(muzzle, { x: fx0 * 1.5, y: fy0 * 1.5 }, 0xffb030, 22, 9, 0.12, 0.25);
      fx.burst(muzzle, { x: fx0, y: fy0 }, 0xffffe0, 10, 6, 0.16, 0.12);
      fx.burst(muzzle, { x: fx0 * 0.3, y: fy0 * 0.3 }, 0x8a8a8a, 16, 1.5, 0.16, 1.4);
      fx.ring(muzzle, 0xffd080, 2.4, 0.18);
      const d = e.who === myId ? 0 : distToMe(e.x, e.y, e.z);
      sound.play('fire', { dist: d });
      sound.play('boom', { dist: d });
      if (d !== undefined && d < 4) fx.shake(e.who === myId ? 0.18 : 0.1, 200);
      break;
    }
    // ---- 바드 ----
    case 'noteFire': {
      // 류트 음파 발사: 줄 긁는 반짝 (음표는 snapshot notes)
      fx.burst({ x: e.x, y: e.y, z: e.z }, e.dir ? { x: e.dir.x, y: e.dir.y } : null, C.BARD_NOTE_COLOR, 6, 3, 0.06, 0.3);
      sound.play('pickup', { dist: e.who === myId ? 0 : distToMe(e.x, e.y, e.z) });
      break;
    }
    case 'noteEnd':
      if (e.what !== 'expire') fx.burst({ x: e.x, y: e.y, z: e.z }, null, C.BARD_NOTE_COLOR, 10, 3, 0.07, 0.4);
      else fx.burst({ x: e.x, y: e.y, z: e.z }, null, C.BARD_NOTE_COLOR, 4, 1, 0.05, 0.3);
      break;
    case 'ghostDrop': // 유령 블록 생김 (떨어지는 동안은 pieces 의 shape 'ghost')
      renderer.ghostDropFx(e);
      sound.play('tap', { dist: distToMe(e.x + 0.5, e.y + 0.5, e.z) });
      break;
    case 'ghostDropFail': // 내 투하가 안 됨 (쿨·칸 꽉 참 등): 조준 원만 살짝 흔들림 (글자 없음)
      if (e.who === myId) ghostRefuse();
      break;
    case 'headBonk': { // 떨어지는 블록에 머리를 박았지만 살았음: 쿵 + 별 + 끄덕 (압사 납작과 다르게)
      renderer.headBonk(e);
      const d = e.who === myId ? 0 : distToMe(e.x, e.y, e.z);
      sound.play('tap', { dist: d });
      sound.play('land', { dist: d });
      if (e.who === myId) fx.shake(C.HEAD_BONK_SHAKE, 160);
      break;
    }
    case 'dive': // 메탈 공중 기타 꽂기: 거꾸로 뒤집혀 아래로 빠르게 (속도선은 render)
      renderer.diveStart(e);
      sound.play('swing', { dist: e.who === myId ? 0 : distToMe(e.x, e.y, e.z) });
      break;
    case 'diveEnd': {
      renderer.diveEnd(e);
      const d = e.who === myId ? 0 : distToMe(e.x, e.y, e.z);
      if (e.what === 'land') {
        sound.play('land', { dist: d });
        if (d < 3) fx.shake(e.who === myId ? 0.25 : 0.1, 250);
      } else if (e.what === 'hit' && d < 3) fx.shake(e.who === myId ? 0.3 : 0.12, 250);
      break;
    }
    case 'glide': {
      // 음유 공중: 빙글 도는 동안 (snapshot glideLeft) 발밑에서 초록 반짝
      const a = playerById(e.who);
      if (a) fx.ring({ x: a.x, y: a.y, z: a.z + 0.1 }, C.BARD_NOTE_COLOR, 0.6, 0.3, true);
      break;
    }
    case 'glideRing': // 음유 천천히 낙하 음파 고리 (피해): 소리는 B2
      renderer.bardGlideRing(e);
      break;
    case 'form':
      // 폼 전환: 메탈 = 기타 치켜들고 리프 충격파 (모히칸은 snapshot form 으로 솟음) / 음유 = 두 팔 벌려 치유파
      renderer.skillMove(e.who, e.form === 'metal' ? 'bardRiff' : 'bardHeal');
      renderer.bardForm(e);
      sound.play('strum', { dist: e.who === myId ? 0 : e.x !== undefined ? distToMe(e.x, e.y, e.z) : undefined, form: e.form });
      if (e.form === 'metal') sound.play('boom', { dist: e.who === myId ? 0 : e.x !== undefined ? distToMe(e.x, e.y, e.z) : undefined });
      if (e.form === 'bard' && (e.healed || []).some((h) => h.id === myId)) damageEl.animate([{ transform: 'scale(1.5)', color: '#80ffa0' }, { transform: 'scale(1)' }], { duration: 450 });
      break;
    case 'song':
      renderer.skillMove(e.who, 'bardSong');
      renderer.bardSong(e);
      sound.play('strum', { dist: e.who === myId ? 0 : distToMe(e.x, e.y, e.z), pos: e });
      if ((e.targets || []).includes(myId)) flashScreen('rgba(255,106,213,.25)');
      break;
    case 'amp': {
      // 앰프 음파 시작: 앰프·원뿔은 snapshot ampLeft 동안 (render). 연주는 figureAnim amp
      const a = playerById(e.who);
      if (a) fx.burst({ x: a.x, y: a.y, z: a.z + 1 }, null, C.BARD_AMP_COLOR, 16, 4, 0.08, 0.4);
      sound.play('boom', { dist: e.who === myId ? 0 : a ? distToMe(a.x, a.y, a.z) : undefined });
      break;
    }
    case 'ampEnd':
      renderer.ampEnd(e);
      break;
    // ---- 광전사 ----
    case 'rush': {
      // F 광폭 도약: 도끼 치켜들고 날아감 + 발밑 흙먼지
      renderer.skillMove(e.who, 'berserkerLeap');
      fx.burst({ x: e.from.x, y: e.from.y, z: e.from.z + 0.1 }, null, 0xc0a070, 14, 3.5, 0.11, 0.45);
      sound.play('swing', { dist: e.who === myId ? 0 : distToMe(e.from.x, e.from.y, e.from.z) });
      break;
    }
    case 'rushLand':
      renderer.skillMove(e.who, 'berserkerSlam');
      renderer.rushLand(e);
      break;
    case 'spin': {
      // R 분노 소용돌이 시작: 깎인 % 만큼 몸에서 김이 확 빠짐 (내 것이면 화면 % 가 쪼그라들며 바뀜). 도는 모습은 snapshot spinLeft 로
      const a = playerById(e.who);
      if (a) {
        fx.burst({ x: a.x, y: a.y, z: a.z + 1.1 }, { x: 0, y: 0 }, 0xf4f4f4, 10 + Math.round((e.cut || 0) / 2), 4, 0.14, 0.7);
        fx.ring({ x: a.x, y: a.y, z: a.z + 0.9 }, 0xff6040, 2.6, 0.3);
      }
      if (e.who === myId && e.cut > 0) damageEl.animate([{ transform: 'scale(1.6)', color: '#ffffff' }, { transform: 'scale(0.8)' }, { transform: 'scale(1)' }], { duration: 450 });
      break;
    }
    case 'spinEnd':
      renderer.spinEnd(e);
      break;
    // ---- 대포수 ----
    case 'shellFire': {
      // 포구 불꽃·연기 + 쾅 + 반동 (땅: 엉덩방아, 공중: 뒤로 래그돌 회전)
      renderer.muzzleBlast(e);
      renderer.cannonRecoil(e);
      const d = e.who === myId ? 0 : distToMe(e.x, e.y, e.z);
      sound.play('boom', { dist: d });
      if (e.who === myId) fx.shake(e.big ? 0.3 : 0.14, e.big ? 300 : 160);
      break;
    }
    case 'shellEnd':
      renderer.shellImpact(e);
      break;
    case 'blockBreak':
      renderer.blockBreak(e);
      if (e.cells?.length) {
        const dd = e.who === myId ? 0 : distToMe(e.cells[0][0] + 0.5, e.cells[0][1] + 0.5, e.cells[0][2]);
        sound.play('shatter', { dist: dd }); // 와장창
        if (dd !== undefined && dd < 3) fx.shake(e.big ? 0.18 : 0.08, 160);
      }
      break;
    case 'groundShot':
      renderer.groundShot(e);
      renderer.skillMove(e.who, 'cannonJump');
      break;
    case 'bigShellBlast':
      renderer.bigShellBlast(e);
      break;
    case 'reload': {
      if (e.ammo !== undefined) {
        // 대포수 장전: 허리 포탄이 하나 늘고 (snapshot) 내 것이면 찰칵 + HUD 칸 반짝
        if (e.who === myId) {
          sound.play('latch', { dist: 0 });
          cannonHudFlash(e.ammo);
        }
        break;
      }
      // 장전 (상대를 끌어옴): 허리 권총에서 불꽃이 확 + 찰칵
      const a = playerById(e.who);
      if (a) fx.burst({ x: a.x, y: a.y, z: a.z + 0.75 }, null, 0xffd040, 12, 3, 0.07, 0.35);
      sound.play('latch', { dist: e.who === myId ? 0 : a ? distToMe(a.x, a.y, a.z) : undefined, pos: a });
      break;
    }
    case 'blockGrab': // R 1단계: 블록이 뽑혀 끌려와 머리 위에서 돎
      renderer.blockGrab(e);
      sound.play('tear', { dist: e.who === myId ? 0 : distToMe(e.from[0] + 0.5, e.from[1] + 0.5, e.from[2]) }); // 찌익
      renderer.skillMove(e.who, 'hookSlam', e.ms);
      break;
    case 'blockSlam': // R 2단계: 앞으로 쾅 → 박힘 (필드 밖이면 떨어져 사라짐)
      renderer.blockSlam(e);
      renderer.skillStrike(e.who, 'hookSlam');
      break;
    case 'zombie': // 블록 마스터: 죽어서 마스터 편
      if (e.who === myId) toast('마스터 편이 됐다! 하늘에서 블록으로 남은 사람을 깔아라', 'good');
      else toast(`${nameOf(e.who)} 마스터 편으로`);
      break;
    case 'respawn': // 킬 점수전 부활 (연습 방은 제자리로 돌아가는 것도 respawn → practiceReset·charChange 가 따로 보여 줌)
      if (e.who === myId && !inPractice()) {
        toast(`부활! ${C.KILLS_SHIELD_MS / 1000}초 무적`, 'good');
        sound.play('go');
      }
      break;
    case 'hit': // 글자 알림 없이 화면 번쩍·소리·이펙트·콤보 숫자로 (2026-10-24 재혁: 글이 너무 많음)
      if (e.target === myId && e.ok) flashScreen('rgba(255,210,0,.45)');
      break;
    case 'pickup': // 내가 먹은 것만 짧게 (쓰는 법은 아래 아이템 칸)
      if (e.who === myId) toast(`${ITEM_KO[e.item] || e.item}!`, 'good');
      break;
    case 'controlStart':
      if (e.who !== myId) toast(`${nameOf(e.who)} 블록 조종 시작. 그림자를 조심!`);
      break;
    case 'death':
      if (e.cause !== 'disconnect') killFeed(e);
      if (e.who === myId) {
        // 나를 죽인 사람부터 따라감 (없거나 이미 죽었으면 다음 사람)
        spec.killed = { cause: e.cause, by: e.by, byName: e.byName, weapon: e.weapon };
        spec.target = e.by;
        spec.overview = false;
      }
      break;
    case 'lava':
      toast('용암! 위로', 'me');
      break;
    case 'clear':
      toast('층 클리어!');
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
      sound.play('swing', { dist: distToMe(a.x, a.y, a.z), pos: a, char: a.char });
      return;
    }
    case 'hit': {
      const t = playerById(e.target);
      const a = playerById(e.by);
      if (!t) return;
      const chest = { x: t.x, y: t.y, z: t.z + 1.0 };
      if (!e.ok) {
        fx.burst(chest, null, 0xaaaaaa, 4, 2, 0.06, 0.25); // 무적이라 무시: 작은 회색 먼지만
        return;
      }
      let dir = null;
      if (a) {
        const dx = t.x - a.x;
        const dy = t.y - a.y;
        const len = Math.hypot(dx, dy) || 1;
        dir = { x: dx / len, y: dy / len };
      }
      const heavy = e.crit || e.kind === 'blast' || e.kind === 'bigbomb';
      if (e.crit) {
        // 치명타: 금색 파편 한 겹 + 큰 고리 + 전용 소리
        fx.burst(chest, dir, 0xffd030, C.FX_PARTICLES * 2, 8, 0.12, 0.6);
        fx.ring(chest, 0xffd030, 4.2);
        sound.play('crit', { dist: e.by === myId || e.target === myId ? 0 : distToMe(t.x, t.y, t.z), pos: t });
      }
      fx.burst(chest, dir, e.kind === 'projectile' ? 0xffee40 : heavy ? 0xffa040 : 0xfff2c0, heavy ? C.FX_PARTICLES * 2 : C.FX_PARTICLES, heavy ? 7 : 5);
      fx.ring(chest, e.kind === 'projectile' ? 0xffee40 : heavy ? 0xff8a10 : 0xffffff, heavy ? 3.4 : 2.4);
      fx.hitSquash(e.target);
      renderer.hitReact(e.target, dir, { heavy, crit: e.crit, kind: e.kind }); // TABS 식 몸: 맞은 방향으로 휘청
      const weapon = { char: a?.char, form: a?.bard?.form }; // 때린 캐릭터 무기 소리 (바드는 폼)
      if (e.target === myId) {
        sound.play('hurt');
        sound.play('hit', { dist: 0, ...weapon });
        fx.shake(C.FX_SHAKE_HURT * (heavy ? 1.6 : 1));
      } else if (e.by === myId) {
        sound.play('hit', { strong: true, ...weapon });
        if (heavy) sound.play('hurt'); // 망치는 묵직한 저음을 한 겹 더
        fx.shake(C.FX_SHAKE_HIT * (heavy ? 2 : 1), 150);
        showHitmarker();
      } else {
        sound.play('hit', { dist: distToMe(t.x, t.y, t.z), pos: t, ...weapon });
      }
      return;
    }
    case 'fire': {
      const a = playerById(e.who);
      if (a) sound.play('fire', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      return;
    }
    case 'melt': {
      // 하늘 계단 블록이 용암에 녹음: 칸마다 주황 번쩍 + 지글 불티 + 연기
      renderer.melt(e);
      const c = e.cells?.[0];
      if (c) sound.play('sizzle', { dist: distToMe(c[0] + 0.5, c[1] + 0.5, c[2]), pos: { x: c[0] + 0.5, y: c[1] + 0.5, z: c[2] } });
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
        fx.burst({ x: x + 0.5, y: y + 0.5, z }, null, 0x9a9a9a, 5, 2.8, 0.09, 0.4);
        fx.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.05 }, { x: 0, y: 0 }, 0xb0aaa4, 2, 0.5, 0.2, 1.3); // 천천히 가라앉는 먼지 (여운)
      }
      // 내려앉은 블록이 꾹 눌렸다 돌아옴 + 받친 블록도 살짝 (옅게: 그림자·시야 안 가림)
      renderer.blockPulse(e.cells, 0xffffff, { jolt: -C.LAND_JOLT, opacity: 0.35 });
      renderer.blockPulse(renderer.blockNeighbors(e.cells).filter((c) => c[2] < cz), 0xffffff, { jolt: -C.LAND_JOLT, opacity: 0.2 });
      cx /= e.cells.length;
      cy /= e.cells.length;
      const d = distToMe(cx, cy, cz);
      sound.play('land', { dist: d, pos: { x: cx, y: cy, z: cz } });
      if (d !== undefined && d < 3.5) fx.shake(0.08, 180);
      return;
    }
    case 'finalKill':
      ko.final(e);
      return;
    case 'death': {
      const t = playerById(e.who);
      if (!t) return;
      const d = e.who === myId ? 0 : distToMe(t.x, t.y, t.z);
      const pos = { x: t.x, y: t.y, z: t.z + 0.8 };
      ko.death(e, null, e.who === myId, d);
      if (e.who === myId) sound.play('lose', { dist: 0 });
      if (e.cause === 'crush') {
        renderer.crushFlat(e.who); // 납작하게 찌그러진 몸이 잠깐 남음
        fx.burst(pos, null, 0xff3030, 22, 6, 0.12, 0.6);
        fx.burst({ x: t.x, y: t.y, z: t.z + 0.1 }, null, 0x9a9a9a, 14, 3.5, 0.12, 0.6); // 깔린 자리 먼지
        sound.play('crush', { dist: d, pos });
        sound.play('land', { dist: d, pos }); // 큰 쿵
        if (e.who === myId) fx.shake(0.35, 450);
        else if (d !== undefined && d < 4) fx.shake(0.1, 200);
      } else if (e.cause === 'lava') {
        fx.burst(pos, null, 0xffa020, 18, 4, 0.1, 0.6);
        sound.play('lavaDeath', { dist: d, pos });
      } else if (e.cause === 'fall') {
        sound.play('fall', { dist: d, pos });
      }
      return;
    }
    case 'airJump': {
      // 2단 점프: 발밑에 흰 김 + 휙
      const a = playerById(e.who);
      if (!a) return;
      fx.burst({ x: a.x, y: a.y, z: a.z + 0.05 }, null, 0xffffff, 8, 2.5, 0.08, 0.35);
      renderer.airJump(e.who); // 앞 공중제비
      sound.play('airJump', { dist: e.who === myId ? 0 : distToMe(a.x, a.y, a.z) });
      return;
    }
    case 'pickup':
      if (e.who === myId) sound.play('pickup');
      return;
    case 'bombPlace':
      sound.play('tick', { dist: e.who === myId ? 0 : distToMe(e.x + 0.5, e.y + 0.5, e.z) });
      return;
    case 'boom': {
      const d = distToMe(e.x, e.y, e.z);
      fx.burst({ x: e.x, y: e.y, z: e.z }, null, 0xff7020, 40, 9, 0.16, 0.7);
      fx.burst({ x: e.x, y: e.y, z: e.z }, null, 0x555555, 24, 5, 0.12, 0.9);
      fx.ring({ x: e.x, y: e.y, z: e.z }, 0xffa040, 4.5);
      sound.play('boom', { dist: d, pos: e });
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
// 연결 끊김: HUD 갱신을 멈추고 대기 화면 버튼들을 숨김 (안내 문구만 남김)
function stopHud() {
  closed = true;
  centerEl.classList.remove('hidden');
  for (const el of [startBtn, $('bot-btns'), $('map-info'), $('name-row'), $('room-row'), $('host-players'), $('keys'), $('spec')]) el.classList.add('hidden');
}

let net = null; // 접속 상태 표시 (client/net.js)
function connect() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}`);
  ws.onopen = () => {
    statusEl.textContent = '연결됨. 서버 응답 대기...';
    if (!net) net = new NetStatus(send); // 핑·렉 표시 (client/net.js)
    // 링크(?room=ABCD)로 왔으면 바로 그 방으로
    const code = new URLSearchParams(location.search).get('room');
    if (code) {
      pendingJoin = true; // 먼저 오는 목록으로 방 밖 화면을 띄우지 않게
      send({ type: 'join', code });
    }
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    msg.recvAt = performance.now(); // 받은 시각 (화면 위치 보간의 서버 시계 추정)
    if (net) net.onMessage(msg);
    if (msg.type === 'rooms') {
      roomList = msg;
      if (!myId && !pendingJoin) showRooms();
    } else if (msg.type === 'joinError') {
      pendingJoin = false;
      setUrlRoom(null);
      showRooms(msg.reason);
    } else if (msg.type === 'welcome') {
      myId = msg.id;
      room = msg.room;
      pendingJoin = false;
      setUrlRoom(room.code); // 새로고침해도 같은 방으로
      roomsEl.classList.add('hidden');
      statusEl.classList.remove('hidden');
      const sp = C.SPAWN_POINTS[msg.slot % C.SPAWN_POINTS.length];
      input.setYawPitch(sp.yaw, 0);
      if (nameInput.value) submitName();
      const savedChar = loadPref('tf-char');
      if (savedChar) send({ type: 'setChar', char: savedChar });
      const savedColor = Number(loadPref('tf-color')); // 이미 누가 쓰면 서버가 거절 → 들어올 때 받은 빈 색 그대로
      if (loadPref('tf-color') !== null && Number.isInteger(savedColor)) send({ type: 'setColor', color: savedColor });
    } else if (msg.type === 'left') {
      leftRoom(msg.reason);
    } else if (msg.type === 'state') {
      if (!myId) return; // 방을 나간 직후 남은 스냅샷
      lastState = state;
      if (!msg.grid && state && state.grid) msg.grid = state.grid; // 격자는 바뀔 때만 온다
      state = msg;
      if (msg.room) room = msg.room;
      onState();
      for (const e of msg.events || []) handleEvent(e);
    }
  };
  ws.onclose = () => {
    stopHud();
    centerText.textContent = '서버 연결 끊김. 새로고침하세요.';
    if (!roomsEl.classList.contains('hidden')) {
      roomsMsg.textContent = '서버 연결 끊김. 새로고침하세요.';
      for (const b of roomsEl.querySelectorAll('button:not(.settings-btn)')) b.disabled = true;
    }
    // 자동으로 다시 붙어 봄 (client/net.js): 되면 새로고침 → ?room=코드 로 같은 방
    if (net)
      net.reconnect((text) => {
        centerText.textContent = text;
        if (!roomsEl.classList.contains('hidden')) roomsMsg.textContent = text;
      });
  };
}

// ---------- 방 밖: 방 만들기 · 코드로 들어가기 · 공개 방 목록 ----------
const roomsEl = $('rooms');
const roomsMsg = $('rooms-msg');
const roomsNick = $('rooms-nick');
const roomCodeInput = $('room-code');
let room = null; // 들어가 있는 방 { code, name, public }
let roomList = null; // 서버가 보낸 공개 방 목록
let roomListKey = '';
let pendingJoin = false;
roomCodeInput.maxLength = C.ROOM_CODE_LEN;
$('room-name').maxLength = C.ROOM_NAME_MAX_LEN;

function setUrlRoom(code) {
  const url = code ? `${location.pathname}?room=${code}` : location.pathname;
  try {
    history.replaceState(null, '', url);
  } catch {
    // 주소창을 못 바꿔도 게임엔 지장 없음
  }
}
const roomLink = (code) => (room && room.code === code && room.link) || `${location.origin}${location.pathname}?room=${code}`; // 터널 주소가 있으면 그걸로 (서버 room.link)

function showRooms(message) {
  roomsEl.classList.remove('hidden');
  statusEl.classList.add('hidden');
  if (message !== undefined) roomsMsg.textContent = message;
  if (document.activeElement !== roomsNick) roomsNick.value = nameInput.value;
  renderRoomList();
}

function renderRoomList() {
  if (!roomList) return;
  const full = roomList.count >= roomList.max;
  $('room-create').disabled = full;
  $('rooms-count').textContent = `(지금 열린 방 ${roomList.count}/${roomList.max}개${full ? ', 가득 참' : ''})`;
  const key = JSON.stringify(roomList.rooms);
  if (key === roomListKey) return;
  roomListKey = key;
  const listEl = $('room-list');
  listEl.textContent = '';
  if (!roomList.rooms.length) {
    const none = document.createElement('div');
    none.className = 'none';
    none.textContent = '공개된 방 없음. 친구에게 코드나 링크를 받거나 방을 만드세요';
    listEl.append(none);
    return;
  }
  for (const r of roomList.rooms) {
    const row = document.createElement('div');
    row.className = 'room';
    const name = document.createElement('div');
    name.textContent = r.name;
    const info = document.createElement('div');
    info.className = 'info';
    const bots = r.bots ? ` + 봇 ${r.bots} (${BOT_LEVEL_KO[r.botLevel] || r.botLevel})` : '';
    info.textContent = `사람 ${r.humans}${bots} / ${r.max}명 · ${C.MODE_NAMES[r.mode] || '생존'} · 맵 ${MAP_KO[r.map] || r.map}${r.skyStairs ? ' · 하늘 계단' : ''} · ${r.teamMode ? '팀전' : '개인전'}`;
    const btn = document.createElement('button');
    btn.textContent = r.humans + r.bots >= r.max ? '꽉 참' : '들어가기';
    btn.disabled = r.humans + r.bots >= r.max;
    btn.addEventListener('click', () => joinRoom(r.code));
    row.append(name, btn, info);
    listEl.append(row);
  }
}

function syncNick() {
  nameInput.value = roomsNick.value;
  try {
    localStorage.setItem('tf-name', roomsNick.value);
  } catch {
    // 저장이 막혀 있어도 이번 접속에는 보낸다
  }
}
function joinRoom(code) {
  syncNick();
  roomsMsg.textContent = '';
  send({ type: 'join', code });
}
roomsNick.maxLength = C.NAME_MAX_LEN;
roomsNick.addEventListener('change', syncNick);
$('room-create').addEventListener('click', () => {
  syncNick();
  roomsMsg.textContent = '';
  send({ type: 'create', name: $('room-name').value, nick: roomsNick.value });
});
$('room-join').addEventListener('click', () => joinRoom(roomCodeInput.value));
roomCodeInput.addEventListener('keydown', (e) => {
  if (e.code === 'Enter') joinRoom(roomCodeInput.value);
});

// 방에서 나옴 (나가기 버튼·내보내짐): 방 화면 상태를 비우고 목록으로
function leftRoom(reason) {
  myId = null;
  room = null;
  state = null;
  lastState = null;
  wasAlive = true;
  input.enabled = false;
  renderer.gridVersion = -1; // 격자 버전은 방마다 0부터라, 다음 방 버전이 우연히 같으면 지형을 안 바꿈
  roomRowKey = '';
  if (document.pointerLockElement) document.exitPointerLock();
  setUrlRoom(null);
  showRooms(reason || '');
}

$('room-leave').addEventListener('click', () => send({ type: 'leave' }));
$('room-public').addEventListener('click', () => room && send({ type: 'setPublic', on: !room.public }));
$('room-copy').addEventListener('click', async () => {
  if (!room) return;
  const link = roomLink(room.code);
  let ok = false;
  try {
    await navigator.clipboard.writeText(link); // https(터널)에서만 됨
    ok = true;
  } catch {
    // http(LAN) 에선 클립보드가 막힘 → 옛 방식
    const ta = document.createElement('textarea');
    ta.value = link;
    document.body.append(ta);
    ta.select();
    try {
      ok = document.execCommand('copy');
    } catch {
      ok = false;
    }
    ta.remove();
  }
  toast(ok ? '링크 복사됨' : '복사가 막힘: 아래 주소를 직접 복사하세요');
});

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
// 하늘 계단 (호스트, 판 사이): 맵 고르기 옆 체크 상자
const skyLabel = document.createElement('label');
skyLabel.style.cssText = 'font-size:15px;margin-left:8px';
const skyBox = document.createElement('input');
skyBox.type = 'checkbox';
skyBox.id = 'sky-stairs';
skyLabel.append(skyBox, ' 하늘 계단');
skyLabel.title = '떨어지는 블록이 하늘까지 쌓여 위로 올라갈 수 있음 (높이 2배)';
$('bot-btns').append(skyLabel);
skyBox.addEventListener('change', () => send({ type: 'skyStairs', on: skyBox.checked }));
$('bot-level').addEventListener('change', (e) => send({ type: 'botLevel', level: e.target.value }));
$('mode-select').addEventListener('change', (e) => send({ type: 'setMode', mode: e.target.value }));
const BOT_LEVEL_KO = { easy: '쉬움', normal: '보통', hard: '어려움' };
// 캐릭터 설명 (대기 화면). 수치는 config
const charDesc = (c) => `${keyText('skill')} ${C.SKILL_NAMES[c]} · ${keyText('ult')} ${C.ULT_NAMES[c]}`; // 짧게 (2026-10-24 재혁: 글이 너무 많음), 키는 설정 따라

const MODE_DESC = {
  survival: '생존: 마지막까지 살아남은 사람이 승',
  master: `블록 마스터: 한 명이 하늘에서 블록만 떨어뜨리고, 나머지는 ${C.MASTER_TIME_MS / 1000}초 버티기 (각자 도생, 죽으면 마스터 편, 마스터는 판마다 돌아감)`,
  kills: `킬 점수전: 죽어도 ${C.KILLS_RESPAWN_MS / 1000}초 뒤 부활. 킬 +1 · 자멸 -1, ${C.KILLS_TIME_MS / 60000}분 또는 ${C.KILLS_TARGET}킬 (팀 ${C.KILLS_TARGET_TEAM}킬)`,
};
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

// ---------- 설정 (감도·효과음·음악·시야각·그림자). 이 브라우저에 기억 ----------
// 대기 화면과 "화면을 클릭하면 조작 시작" 판(ESC 로 마우스를 풀었을 때)의 '설정' 버튼으로 연다
const SETTINGS_DEFAULT = { sens: 1, sfx: 1, music: 1, fov: C.FOV_DEFAULT, shadows: true, outline: true, lowGfx: false, third: false };
function loadSettings() {
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem('tf-settings') || '{}') || {};
    // 예전 체크박스 값 이어받기
    if (localStorage.getItem('tf-shadows') === 'off' && saved.shadows === undefined) saved.shadows = false;
    if (localStorage.getItem('tf-music') === 'off' && saved.music === undefined) saved.music = 0;
  } catch {
    saved = {};
  }
  return { ...SETTINGS_DEFAULT, ...saved };
}
const settings = loadSettings();
function applySettings() {
  input.sensitivity = settings.sens;
  sound.setVolume(settings.sfx);
  music.setVolume(settings.music);
  renderer.fov = settings.fov;
  renderer.setShadows(settings.shadows);
  renderer.setOutline(settings.outline);
  renderer.setLowGfx(settings.lowGfx);
  renderer.third = !!settings.third;
  // 3인칭: 내 캐릭터가 화면 가운데 아래에 서므로 큰 피해 % 는 왼쪽 아래 구석으로 (가운데 상대를 안 가리게).
  // #bottom 은 transform 이 있어 그 안에선 구석에 못 붙임 → #hud 로 옮김
  const dmg = $('damage');
  if (settings.third && !dmg.classList.contains('corner')) $('hud').appendChild(dmg);
  else if (!settings.third && dmg.classList.contains('corner')) $('bottom').insertBefore(dmg, $('skills'));
  dmg.classList.toggle('corner', !!settings.third);
}
function saveSettings() {
  try {
    localStorage.setItem('tf-settings', JSON.stringify(settings));
  } catch {
    // 저장이 막혀 있어도 이번엔 적용
  }
}
applySettings();
const settingsEl = $('settings');
const fields = [
  ['set-sens', 'sens', (v) => `${v.toFixed(1)}배`],
  ['set-sfx', 'sfx', (v) => `${Math.round(v * 100)}%`],
  ['set-music', 'music', (v) => (v > 0 ? `${Math.round(v * 100)}%` : '끔')],
  ['set-fov', 'fov', (v) => `${Math.round(v)}°`],
];
for (const [id, key, fmt] of fields) {
  const el = $(id);
  const out = $(`${id}-v`);
  el.value = settings[key];
  out.textContent = fmt(settings[key]);
  el.addEventListener('input', () => {
    settings[key] = Number(el.value);
    out.textContent = fmt(settings[key]);
    applySettings();
    saveSettings();
  });
}
const checks = [
  ['set-shadows', 'shadows'],
  ['set-outline', 'outline'],
  ['set-lowgfx', 'lowGfx'],
  ['set-third', 'third'],
];
for (const [id, key] of checks) {
  const el = $(id);
  el.checked = settings[key];
  el.addEventListener('change', () => {
    settings[key] = el.checked;
    applySettings();
    saveSettings();
  });
}
// ---------- 조작 키 (설정 창): 칸을 누르고 키나 마우스 버튼을 누르면 바뀜, Esc 취소. 겹치면 빨갛게 ----------
const keybindsEl = $('keybinds');
const keyDupEl = $('key-dup');
const keyBtns = {};
let listening = null; // 키를 기다리는 행동 id
let swallowClickUntil = 0; // 마우스 버튼으로 정한 직후의 클릭은 무시 (그 클릭이 다시 칸을 누르지 않게)
let lastGroup = null;
for (const a of ACTIONS) {
  if (a.group !== lastGroup) {
    const h = document.createElement('div');
    h.className = 'kb-group';
    h.textContent = a.group;
    keybindsEl.append(h);
    lastGroup = a.group;
  }
  const name = document.createElement('span');
  name.textContent = a.label;
  const btn = document.createElement('button');
  btn.className = 'kb-btn';
  if (a.id === 'item') name.classList.add('items-dim'); // 아이템 안 나오는 판이면 회색
  btn.addEventListener('click', () => {
    if (performance.now() < swallowClickUntil) return;
    listening = listening === a.id ? null : a.id;
    showBinds();
  });
  keyBtns[a.id] = btn;
  keybindsEl.append(name, btn);
}
function showBinds() {
  const dup = conflicts(input.binds);
  for (const a of ACTIONS) {
    const btn = keyBtns[a.id];
    btn.textContent = listening === a.id ? '키를 누르세요 (Esc 취소)' : keyText(a.id);
    btn.classList.toggle('wait', listening === a.id);
    btn.classList.toggle('dup', !!dup[input.binds[a.id]]);
  }
  const lines = Object.entries(dup).map(([code, ids]) => `${keyLabel(code)}: ${ids.map((id) => ACTIONS.find((a) => a.id === id).label).join(' · ')}`);
  keyDupEl.textContent = lines.length ? `겹치는 키 (둘 다 실행됨) — ${lines.join(' / ')}` : '';
  refreshKeyLabels();
}
function setBind(id, code) {
  input.setBinds({ ...input.binds, [id]: code });
  saveBinds(input.binds);
  listening = null;
  showBinds();
}
// 기다리는 중이면 키·마우스를 게임보다 먼저 가로챔
window.addEventListener(
  'keydown',
  (e) => {
    if (!listening) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (e.code === 'Escape') {
      listening = null;
      showBinds();
    } else setBind(listening, normCode(e.code));
  },
  true,
);
window.addEventListener(
  'mousedown',
  (e) => {
    if (!listening) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    swallowClickUntil = performance.now() + 400;
    setBind(listening, `Mouse${e.button}`);
  },
  true,
);
$('keys-reset').addEventListener('click', () => {
  input.setBinds(DEFAULT_BINDS);
  saveBinds(input.binds);
  listening = null;
  showBinds();
});
showBinds();

function openSettings(on) {
  if (!on) listening = null;
  settingsEl.classList.toggle('hidden', !on);
}
document.querySelectorAll('.settings-btn').forEach((b) => b.addEventListener('click', () => openSettings(true)));
$('settings-close').addEventListener('click', () => openSettings(false));
$('settings-reset').addEventListener('click', () => {
  Object.assign(settings, SETTINGS_DEFAULT);
  for (const [id, key, fmt] of fields) {
    $(id).value = settings[key];
    $(`${id}-v`).textContent = fmt(settings[key]);
  }
  for (const [id, key] of checks) $(id).checked = settings[key];
  applySettings();
  saveSettings();
});

// ---------- 처음 하는 사람 안내: 이 브라우저가 처음이면 카드 3장 (설정에서 다시 보기) ----------
const tutorialEl = $('tutorial');
const cards = [...tutorialEl.querySelectorAll('.card')];
let cardIdx = 0;
function showCard(i) {
  cardIdx = i;
  cards.forEach((c, k) => c.classList.toggle('hidden', k !== i));
  $('tut-next').textContent = i === cards.length - 1 ? '시작하기' : '다음';
  $('tut-page').textContent = `${i + 1} / ${cards.length}`;
}
function openTutorial(on) {
  tutorialEl.classList.toggle('hidden', !on);
  if (on) showCard(0);
  else {
    try {
      localStorage.setItem('tf-tutorial', 'done');
    } catch {
      // 저장이 막혀 있으면 다음에 또 보임
    }
  }
}
$('tut-next').addEventListener('click', () => (cardIdx < cards.length - 1 ? showCard(cardIdx + 1) : openTutorial(false)));
$('tut-skip').addEventListener('click', () => openTutorial(false));
$('settings-tutorial').addEventListener('click', () => {
  openSettings(false);
  openTutorial(true);
});
try {
  if (localStorage.getItem('tf-tutorial') !== 'done') openTutorial(true);
} catch {
  openTutorial(true);
}
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
let victory = { id: null, until: 0 }; // 판 끝 승리 연출: 승자 id 와 끝나는 시각
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
const hex = (n) => `#${n.toString(16).padStart(6, '0')}`;
function colorOf(p) {
  return hex(playerColor(p, state));
}
const TEAM_KO = { red: '빨강', blue: '파랑' };

// 아이템이 나오는 판인지 (서버가 알려 주기 전엔 설정값)
document.body.classList.toggle('no-items', !C.ITEMS_ENABLED);
function onState() {
  if (state.itemsEnabled !== undefined) document.body.classList.toggle('no-items', !state.itemsEnabled);
  const p = me();
  if (!p) return;
  if (lastState && lastState.phase !== state.phase) renderer.clearQuakes(); // 판 시작·끝: 서버도 솟은 땅을 버림
  if (lastState && lastState.phase === 'countdown' && state.phase === 'playing') {
    lastCount = null;
    sound.play('go');
    showBig('시작!', '#ffe14a', 700);
  }
  if (lastState && lastState.phase === 'playing' && state.phase === 'over' && !inPractice()) {
    const w = state.players.find((x) => x.id === state.round.winnerId);
    sound.play('win');
    const wt = state.round.winnerTeam;
    // 승리 연출 (모두의 카메라가 승자에게). 팀전이면 이긴 팀에서 살아 있는 사람 (없으면 아무 팀원)
    const ws = (state.round.winnerIds || []).map(playerById).filter(Boolean); // 승자가 여럿일 수 있음 (블록 마스터 생존자, 킬 점수전 동점)
    const star = wt ? state.players.find((x) => x.team === wt && x.alive) || state.players.find((x) => x.team === wt) : ws.find((x) => x.alive) || ws[0];
    if (star) victory = { id: star.id, until: performance.now() + C.WIN_BANNER_MS };
    const wasMaster = lastState.players.find((x) => x.master && !x.zombie);
    if (wt) showBig(`${TEAM_KO[wt]}팀 승리!`, hex(TEAM_MAIN[wt]), C.WIN_BANNER_MS, true);
    else if (ws.length > 1) showBig(state.mode === 'master' ? '생존자 승리!' : '공동 승리!', '#ffe14a', C.WIN_BANNER_MS, true);
    else if (w && wasMaster && wasMaster.id === w.id) showBig(`마스터 ${shownName(w)} 승리!`, colorOf(w), C.WIN_BANNER_MS, true);
    else if (w && state.mode === 'master') showBig(`${shownName(w)} 혼자 버팀!`, colorOf(w), C.WIN_BANNER_MS, true);
    else if (w) showBig(`${shownName(w)} 승리!`, colorOf(w), C.WIN_BANNER_MS, true);
    else showBig('무승부', '#ddd', C.WIN_BANNER_MS, true);
  }
  if (state.phase === 'playing' && !p.alive && wasAlive) flashScreen('rgba(255,0,0,.45)');
  wasAlive = p.alive;
  // 판이 새로 시작되면 시점을 스폰 방향으로
  if (lastState && lastState.round.n !== state.round.n) {
    const pts = state.field ? C.spawnPointsFor(state.field.w, state.field.d) : C.SPAWN_POINTS;
    const sp = pts[p.slot % pts.length];
    input.setYawPitch(sp.yaw, 0);
  }
}

// 승자 이름들 (블록 마스터 생존자·킬 점수전 동점이면 여럿)
function winnersText() {
  const ws = (state.round.winnerIds || []).map(playerById).filter(Boolean);
  return ws.length ? ws.map(shownName).join(', ') : '무승부';
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
  const ps = state.players.filter((p) => !p.spectator && !p.dummy).sort((a, b) => a.slot - b.slot); // 관전자·허수아비는 승수에서 뺌
  if (inPractice()) {
    // 연습 방: 승수 없음
    scoreKey = '';
    scoreEl.classList.add('hidden');
    return;
  }
  const tw = state.teamWins || { red: 0, blue: 0 };
  const kills = state.mode === 'kills' && state.phase !== 'lobby'; // 킬 점수전: 판 중·판 끝엔 승수 대신 이번 판 점수 + 남은 시간
  const ts = state.teamScores || { red: 0, blue: 0 };
  const left = kills && state.round.left !== null ? fmt(state.round.left) : '';
  // 판 중엔 아래 플레이어 판이 사람마다 승수·점수를 보여 준다 → 맨 위 줄은 팀 합계가 필요한 팀전에만 (화면 덜 가리게)
  const dup = cardsOn() && !state.teamMode;
  const key = `${kills}|${left}|${dup}|` + ps.map((p) => `${p.id}:${p.wins}:${p.score}:${p.nick}:${p.team}:${p.color}`).join(',') + `|${myId}|${state.teamMode}|${tw.red}:${tw.blue}|${ts.red}:${ts.blue}`;
  if (key === scoreKey) return;
  scoreKey = key;
  scoreEl.classList.toggle('hidden', ps.length < 2 || dup);
  if (dup) return;
  const name = (p) => `<span style="color:${colorOf(p)}" class="${p.id === myId ? 'me' : ''}">${escapeHtml(shownName(p))}</span>`;
  const team = (t) => `<span style="color:${hex(TEAM_MAIN[t])}" class="${me() && me().team === t ? 'me' : ''}">${TEAM_KO[t]}</span>`;
  if (kills) {
    const tail = left ? `<span class="sep">·</span>${left}` : '';
    if (state.teamMode) scoreEl.innerHTML = `킬 ${team('red')} ${ts.red}<span class="sep">:</span>${ts.blue} ${team('blue')}${tail}`;
    else scoreEl.innerHTML = `킬 ${[...ps].sort((a, b) => b.score - a.score).map((p) => `${name(p)} ${p.score}`).join('<span class="sep">·</span>')}${tail}`;
    return;
  }
  if (state.teamMode) {
    // 팀전: 팀 승수 (내 팀에 밑줄)
    scoreEl.innerHTML = `${team('red')} ${tw.red}<span class="sep">:</span>${tw.blue} ${team('blue')}`;
  } else if (ps.length === 2) {
    const [a, b] = ps;
    scoreEl.innerHTML = `${name(a)} ${a.wins}<span class="sep">:</span>${b.wins} ${name(b)}`;
  } else {
    scoreEl.innerHTML = ps.map((p) => `${name(p)} ${p.wins}`).join('<span class="sep">·</span>');
  }
}

// ---------- 화면 아래 플레이어 판 (스매시식: 초상 · 이름 · 큰 % · 내 색 띠) ----------
// 카운트다운·판 중·판 끝에 사람마다 한 칸. 맞으면 % 가 흔들리고, 죽으면 회색 KO
const playersEl = $('players');
const playerCards = new Map(); // id → { el, sub, pct } (초상·이름은 다시 만들 때만 바뀜)
const shownPct = new Map(); // id → 지난 프레임 피해 % (올라갈 때만 흔듦)
let playersKey = '';
const livePlayers = () => state.players.filter((p) => !p.spectator && !p.dummy).sort((a, b) => a.slot - b.slot);
function cardsOn() {
  return !!state && !inPractice() && ['countdown', 'playing', 'over'].includes(state.phase) && livePlayers().length >= 2;
}
function updatePlayers() {
  const on = cardsOn();
  playersEl.classList.toggle('hidden', !on);
  document.body.classList.toggle('cards', on); // 판이 있으면 아래 줄(스킬·관전 안내)을 그 위로 올린다
  if (!on) {
    playersKey = '';
    return;
  }
  const ps = livePlayers();
  const key = ps.map((p) => `${p.id}:${p.char}:${p.color}:${p.team}:${shownName(p)}`).join(',') + `|${state.teamMode}|${state.mode}`;
  if (key !== playersKey) {
    playersKey = key;
    playersEl.textContent = '';
    playerCards.clear();
    for (const p of ps) {
      const el = document.createElement('div');
      el.className = 'pc';
      el.innerHTML =
        '<div class="top"><div class="face"></div><div><div class="nm"></div><div class="sub"></div></div></div><div class="pct"></div><div class="bar"></div>';
      const col = colorOf(p);
      el.style.setProperty('--pcol', col);
      el.classList.toggle('me', p.id === myId);
      const img = p.char ? portrait(p.char, playerColor(p, state), 96) : '';
      if (img) el.querySelector('.face').style.backgroundImage = `url(${img})`;
      el.querySelector('.nm').textContent = shownName(p);
      playersEl.append(el);
      playerCards.set(p.id, { el, sub: el.querySelector('.sub'), pct: el.querySelector('.pct') });
    }
  }
  const kills = state.mode === 'kills';
  for (const p of ps) {
    const c = playerCards.get(p.id);
    if (!c) continue;
    const was = shownPct.get(p.id);
    if (was !== undefined && p.damage > was && p.alive) {
      c.el.classList.remove('hurt');
      void c.el.offsetWidth; // 다시 흔들리게 애니메이션 되감기
      c.el.classList.add('hurt');
    }
    shownPct.set(p.id, p.damage);
    const dead = !p.alive && !p.master;
    c.el.classList.toggle('dead', dead);
    c.el.classList.toggle('watch', spectating() && !spec.overview && spec.target === p.id); // 관전 중 보고 있는 사람
    const pct = dead ? '<i>KO</i>' : `${p.damage}<u>%</u>`;
    if (c.pct.innerHTML !== pct) c.pct.innerHTML = pct;
    c.pct.style.color = dead ? '' : damageColor(p.damage);
    const tag = state.teamMode ? `${TEAM_KO[p.team] || ''}팀 · ` : '';
    const sub = `${tag}${C.CHAR_NAMES[p.char] || ''} ${kills ? `킬 ${p.score}` : `승 ${p.wins}`}`;
    if (c.sub.textContent !== sub) c.sub.textContent = sub;
  }
}

// ---------- 판 끝: 승자 초상 + 결과 표 (이미 있는 숫자만) ----------
const resultsEl = $('results');
let resultsKey = '';
function updateResults() {
  const on = !!state && state.phase === 'over' && !inPractice() && livePlayers().length >= 2;
  resultsEl.classList.toggle('hidden', !on);
  if (!on) {
    resultsKey = '';
    return;
  }
  const ps = livePlayers();
  const winners = new Set(state.round.winnerIds && state.round.winnerIds.length ? state.round.winnerIds : [state.round.winnerId].filter(Boolean));
  const kills = state.mode === 'kills';
  const key = `${state.round.n}|${state.mode}|${state.teamMode}|${[...winners].join(',')}|` + ps.map((p) => `${p.id}:${p.wins}:${p.score}:${p.damage}:${p.alive}:${p.cause}`).join(',');
  if (key === resultsKey) return;
  resultsKey = key;
  const star = ps.find((p) => winners.has(p.id));
  const big = star && star.char ? portrait(star.char, playerColor(star, state), 192) : '';
  const head = state.round.winnerTeam
    ? `${TEAM_KO[state.round.winnerTeam]}팀 승리`
    : winners.size > 1
      ? '공동 승리'
      : star
        ? `${shownName(star)} 승리`
        : '무승부';
  const rows = [...ps]
    .sort((a, b) => Number(winners.has(b.id)) - Number(winners.has(a.id)) || (kills ? b.score - a.score : b.wins - a.wins) || a.slot - b.slot)
    .map((p) => {
      const img = p.char ? portrait(p.char, playerColor(p, state), 64) : '';
      const face = `<span class="face" style="--pcol:${colorOf(p)}${img ? `;background-image:url(${img})` : ''}"></span>`;
      const how = p.alive ? '생존' : CAUSE_KO[p.cause] || '탈락';
      return `<tr class="${winners.has(p.id) ? 'win' : ''}"><td class="n" style="color:${colorOf(p)}">${face}${escapeHtml(shownName(p))}</td><td>${C.CHAR_NAMES[p.char] || '—'}</td><td class="big">${kills ? p.score : p.wins}</td><td class="big">${p.damage}%</td><td>${how}</td></tr>`;
    })
    .join('');
  resultsEl.innerHTML =
    `<h4>라운드 ${state.round.n} 결과</h4>` +
    `<div style="display:flex;gap:12px;align-items:center;margin-bottom:8px">` +
    (big ? `<div style="width:86px;height:86px;background:rgba(0,0,0,.3) url(${big}) center/cover no-repeat;clip-path:polygon(12px 0,100% 0,calc(100% - 12px) 100%,0 100%);border-bottom:4px solid ${star ? colorOf(star) : '#888'};box-sizing:border-box"></div>` : '') +
    `<div class="big" style="font-size:22px;color:${star ? colorOf(star) : 'var(--accent)'}">${escapeHtml(head)}</div></div>` +
    `<table><tr><th>이름</th><th>캐릭터</th><th>${kills ? '킬' : '승'}</th><th>피해</th><th>결과</th></tr>${rows}</table>`;
}

// ---------- HUD ----------
function updateHud() {
  if (!state || closed) return;
  const p = me();
  const isHost = state.hostId === myId;
  const maxP = Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
  // 왼쪽 위: 판 중에만 시간 하나 (남은 시간이 있는 모드는 남은 시간)
  const timeShown = state.phase === 'playing' ? fmt(state.round.left ?? state.round.elapsed) : null;
  statusEl.classList.toggle('hidden', timeShown === null);
  statusEl.textContent = timeShown || '';

  updateScore();
  updatePlayers();
  updateResults();
  updateBig();
  updateBottom(p);

  // 압사 경고: 내 머리 위로 떨어지는 블록이 곧 깔 때 (서버가 계산한 남은 시간)
  const danger = p && p.alive && state.phase === 'playing' ? p.danger : null;
  dangerEl.classList.toggle('hidden', danger === null || danger === undefined);
  if (danger !== null && danger !== undefined) {
    dangerEl.textContent = `⚠ 머리 위 블록! ${(danger / 1000).toFixed(1)}초`;
    if (lastDanger === null) sound.play('danger');
  }
  lastDanger = danger ?? null;

  // 상단 배너: 조종권 상태 (예고 → 조종 중)
  let bannerText = null;
  let bannerColor = 'rgba(0,140,160,.85)';
  if (p && p.alive && state.phase === 'playing') {
    const myPiece = (state.pieces || []).find((pc) => pc.phase === 'control' && pc.controller === myId);
    if (p.controlling && myPiece) {
      const left = myPiece.timeLeft / 1000;
      bannerText = `블록 조종 중 ${left.toFixed(1)}초\n${pieceKeysText()}${myPiece.fits ? '' : '\n여기엔 못 놓음 (빨간 미리보기)'}`;
      if (left < 3) bannerColor = 'rgba(200,60,20,.9)';
    } else if (p.hasControl) {
      const n = state.nextSpawnIn;
      bannerText = n === null || n === undefined ? '조종권 보유: 곧 하늘 시점으로 전환' : `조종권 보유: ${(n / 1000).toFixed(1)}초 후 하늘 시점으로 전환`;
    }
  }
  // 블록 마스터: 마스터는 할 일·남은 시간, 생존자는 누구 블록인지·남은 시간
  if (p && state.mode === 'master' && state.phase === 'playing' && state.round.left !== null) {
    const m = state.players.find((x) => x.master && !x.zombie); // 처음 마스터
    const survivors = state.players.filter((x) => x.alive && !x.master && !x.spectator).length;
    const left = fmt(state.round.left);
    if (p.master) {
      const myPiece = (state.pieces || []).find((pc) => pc.phase === 'control' && pc.controller === myId);
      bannerText = `${p.zombie ? '마스터 편' : '블록 마스터'}: 생존자를 다 깔아라! 남은 ${left} · 생존 ${survivors}명${myPiece ? `\n${pieceKeysText()} (${(myPiece.timeLeft / 1000).toFixed(1)}초)${myPiece.fits ? '' : ` · 여기엔 못 놓음 (꽉 찼거나 주변보다 ${C.MASTER_MAX_RISE}칸 넘게 높아짐)`}` : '\n다음 블록 준비 중'}`;
      bannerColor = 'rgba(120,40,160,.9)';
    } else if (p.alive) {
      bannerText = `${m ? shownName(m) : '마스터'}의 블록을 피해 버티기 · 남은 ${left} · 생존 ${survivors}명`;
      bannerColor = state.round.left < 10000 ? 'rgba(20,140,60,.9)' : 'rgba(120,40,160,.85)';
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
  } else if (state.phase === 'over' && !inPractice()) {
    const w = state.players.find((x) => x.id === state.round.winnerId);
    const wt = state.round.winnerTeam;
    center = `라운드 ${state.round.n} 종료\n승자: ${wt ? `${TEAM_KO[wt]}팀` : winnersText()}`;
    showStart = isHost && state.canStart;
    showKeys = true;
  } else if (spectating()) {
    center = null; // 관전 안내는 화면 아래 (#spec) — 가운데 판이 따라가는 사람을 가리지 않게
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
  if (between) updateCharRow(p);
  updateRoomRow(between, isHost);
  updateHostPlayers(isHost && between);
  const showBots = isHost && between;
  $('bot-btns').classList.toggle('hidden', !showBots);
  // 맵: 호스트는 고르고, 다른 사람은 보기만
  const mapSel = $('map-select');
  if (state.map && document.activeElement !== mapSel) mapSel.value = state.map.choice;
  if (state.skyStairs !== undefined) skyBox.checked = !!state.skyStairs;
  const lvSel = $('bot-level');
  if (state.botLevel && document.activeElement !== lvSel) lvSel.value = state.botLevel;
  const modeSel = $('mode-select');
  if (state.mode && document.activeElement !== modeSel) modeSel.value = state.mode;
  const modeInfo = $('mode-info');
  modeInfo.classList.toggle('hidden', !between);
  modeInfo.textContent = MODE_DESC[state.mode] || '';
  const mapInfo = $('map-info');
  mapInfo.classList.toggle('hidden', !(state.map && !isHost && between));
  if (state.map) mapInfo.textContent = `맵: ${MAP_KO[state.map.choice] || state.map.choice} · 모드: ${C.MODE_NAMES[state.mode] || state.mode}${state.skyStairs ? ' · 하늘 계단' : ''}`;
  if (showBots) {
    $('add-bot').disabled = state.players.length >= Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
    $('remove-bot').disabled = !state.players.some((x) => x.isBot);
  }

  input.enabled = (state.phase === 'playing' || state.phase === 'countdown') && !!p && p.alive; // 카운트다운 중엔 시선만 (서버가 이동·행동을 막음)
  // 조준점: 든 아이템에 따라 색. 투사체 = 빨강, 설치 블록 = 노랑, 폭탄 = 주황
  const armed = !!p && p.held === 'knockback';
  const brick = !!p && p.held === 'brick';
  const bomb = !!p && p.held === 'bomb';
  crosshair.classList.toggle('hidden', !(input.enabled && !p.controlling && !p.master));
  updateCooldowns(p, state.phase === 'playing' && input.enabled && !p.controlling && !p.master);
  updatePractice(p);
  updateItemTimers();
  crosshair.classList.toggle('armed', armed || brick || bomb);
  crosshair.classList.toggle('brick', brick);
  crosshair.classList.toggle('bomb', bomb);
  crosshair.dataset.ammo = '';
}

// ---------- 관전: 죽었거나 관전자면 살아 있는 사람을 3인칭으로 따라감 ----------
// 클릭·스페이스 = 다음 사람, 우클릭 = 전체 보기 ↔ 따라가기
const spec = { target: null, overview: false, killed: null, round: null, dist: C.SPECTATE_DIST, overviewDist: C.SPECTATE_OVERVIEW_DIST };
const specEl = $('spec');
function spectating() {
  const p = me();
  return !!state && (state.phase === 'playing' || state.phase === 'countdown') && !!p && !p.alive;
}
function aliveOthers() {
  return state.players.filter((x) => x.alive && !x.master && x.id !== myId).sort((a, b) => a.slot - b.slot); // 마스터는 필드에 없음
}
function nextTarget(dir = 1) {
  const list = aliveOthers();
  if (!list.length) {
    spec.target = null;
    return;
  }
  const i = list.findIndex((x) => x.id === spec.target);
  spec.target = list[(i + dir + list.length) % list.length].id;
  spec.overview = false;
}
function updateSpectate() {
  if (state && spec.round !== state.round.n) Object.assign(spec, { target: null, overview: false, killed: null, round: state.round.n }); // 새 판
  const on = spectating();
  specEl.classList.toggle('hidden', !on);
  if (!on) return;
  const t = playerById(spec.target);
  if (!spec.overview && (!t || !t.alive)) nextTarget();
  const p = me();
  const k = spec.killed;
  let head;
  if (p.spectator) head = '관전 중 (호스트가 관전으로 바꿈)';
  else if (!p.cause) head = '이번 판은 관전 (다음 판부터 참가)';
  else head = `사망: ${CAUSE_KO[p.cause] || p.cause}${k && k.by !== null ? ` — ${nameOf(k.by) !== '?' ? nameOf(k.by) : k.byName}의 ${WEAPON_KO[k.weapon] || k.weapon}` : ''}`;
  if (p.respawnIn !== null && p.respawnIn !== undefined) head += ` · 부활까지 ${Math.ceil(p.respawnIn / 1000)}초`;
  const now = playerById(spec.target);
  const watching = spec.overview || !now ? '전체 보기' : `${shownName(now)} 따라가는 중`;
  // 살아 있는 사람 목록 (지금 보는 사람은 ▶)
  const alive = aliveOthers();
  // 살아 있는 사람·피해 % 는 아래 플레이어 판이 보여 준다 (보는 사람 판에 ▶) → 판이 없을 때만 글로
  const list = cardsOn() ? '' : alive.map((x) => `${!spec.overview && x.id === spec.target ? '▶ ' : ''}${shownName(x)} ${x.damage}%`).join('   ');
  const next = ghostOn() ? `${keyText('jump')} 다음 사람 · 클릭 블록 떨어뜨리기` : `클릭/${keyText('jump')} 다음 사람`;
  const text = `${head}\n${watching} · 마우스 돌리기 · 휠 거리 · ${next} · 우클릭 ${spec.overview ? '따라가기' : '전체 보기'}${list ? `\n살아 있음: ${list}` : ''}`;
  if (specEl.textContent !== text) specEl.textContent = text;
}
document.addEventListener('mousedown', (e) => {
  if (!spectating()) return;
  if (e.button === 0) {
    // 유령 투하가 되는 판이면 클릭 = 조준한 칸에 블록 떨어뜨리기 (다음 사람은 점프 키)
    if (ghostOn()) {
      if (ghost.aim && me().ghostCd === 0) send({ type: 'ghostDrop', x: ghost.aim.x, y: ghost.aim.y });
      else ghostRefuse();
    } else nextTarget(1);
  }
  if (e.button === 2) spec.overview = !spec.overview;
});

// ---------- 유령 투하: 죽은 사람이 관전 중에 1칸 블록을 조준해 떨어뜨림 (snapshot ghostCd: null 못 함 · 0 가능 · ms 쿨) ----------
// 조준 = 화면 가운데 (마우스가 잡혀 있으면) 또는 마우스 위치에서 나간 시선이 처음 닿는 칸 기둥
const ghost = { aim: null, mouse: null, hinted: false, hintUntil: 0, refuseAt: 0 };
const ghostCdEl = $('ghost-cd');
const ghostHintEl = $('ghost-hint');
const ghostOn = () => spectating() && me().ghostCd !== null && me().ghostCd !== undefined;
document.addEventListener('mousemove', (e) => (ghost.mouse = { x: e.clientX, y: e.clientY }));
function ghostRefuse() {
  ghost.refuseAt = performance.now();
}
function updateGhostAim() {
  const on = ghostOn() && renderer.skyBlend === 0;
  ghostCdEl.classList.toggle('hidden', !on);
  if (!on) {
    ghost.aim = null;
    renderer.setGhostAim(null);
    ghostHintEl.classList.add('hidden');
    return;
  }
  const p = me();
  const w = window.innerWidth;
  const h = window.innerHeight;
  const at = input.locked || !ghost.mouse ? { x: w / 2, y: h / 2 } : ghost.mouse;
  ghost.aim = renderer.pickColumn(state, (at.x / w) * 2 - 1, -(at.y / h) * 2 + 1);
  const ready = p.ghostCd === 0;
  renderer.setGhostAim(ghost.aim && { ...ghost.aim, ready, color: playerColor(p, state) });
  // 조준 원: 쿨이면 회색이 시계 방향으로 차오름, 안 되는 걸 누르면 살짝 흔들림
  ghostCdEl.style.left = `${at.x}px`;
  ghostCdEl.style.top = `${at.y}px`;
  ghostCdEl.classList.toggle('wait', !ready);
  const fill = ready ? 1 : 1 - Math.min(1, p.ghostCd / C.GHOST_DROP_CD_MS);
  ghostCdEl.style.background = ready ? 'rgba(255,255,255,.12)' : `conic-gradient(rgba(200,200,200,.55) ${fill * 360}deg, rgba(0,0,0,.25) 0)`;
  const shake = performance.now() - ghost.refuseAt < 250 ? Math.sin(performance.now() / 20) * 4 : 0;
  ghostCdEl.style.transform = `translateX(${shake}px)`;
  // 처음 죽었을 때 한 번만 짧게 안내
  if (!ghost.hinted) {
    ghost.hinted = true;
    ghost.hintUntil = performance.now() + C.GHOST_HINT_MS;
  }
  ghostHintEl.classList.toggle('hidden', performance.now() >= ghost.hintUntil);
}
// 휠: 관전 카메라 거리 (따라가기·전체 보기 따로)
document.addEventListener('wheel', (e) => {
  if (!spectating() || !e.deltaY) return;
  const k = e.deltaY > 0 ? C.SPECTATE_ZOOM_STEP : 1 / C.SPECTATE_ZOOM_STEP;
  if (spec.overview || !playerById(spec.target)) spec.overviewDist = Math.min(C.SPECTATE_OVERVIEW_MAX, Math.max(C.SPECTATE_OVERVIEW_MIN, spec.overviewDist * k));
  else spec.dist = Math.min(C.SPECTATE_DIST_MAX, Math.max(C.SPECTATE_DIST_MIN, spec.dist * k));
});
document.addEventListener('keydown', (e) => {
  if (normCode(e.code) !== input.binds.jump || e.repeat || !spectating() || document.activeElement === nameInput) return; // 점프 키 = 다음 사람
  nextTarget(1);
  e.preventDefault();
});

// ---------- 이모트 바퀴 (G) ----------
const wheelEl = $('emote-wheel');
const wheelItems = [...wheelEl.querySelectorAll('.em')];
wheelItems.forEach((el, i) => (el.textContent = C.EMOTE_NAMES[i]));
input.onWheel = (pick) => {
  wheelEl.classList.toggle('hidden', pick === null);
  wheelItems.forEach((el, i) => el.classList.toggle('on', i === pick));
};

// ---------- 조준점 둘레 쿨 원 (대시·밀치기) ----------
const cdRing = $('cd-ring');
const cdArcs = {
  dash: { el: cdRing.querySelector('.dash'), track: cdRing.querySelector('.dash-track'), total: C.DASH_COOLDOWN_MS, flashUntil: 0, was: 0 },
  push: { el: cdRing.querySelector('.push'), track: cdRing.querySelector('.push-track'), total: C.PUSH_COOLDOWN_MS, flashUntil: 0, was: 0 },
};
for (const a of Object.values(cdArcs)) a.len = 2 * Math.PI * a.el.r.baseVal.value;
function updateCooldowns(p, show) {
  cdRing.classList.toggle('hidden', !show);
  if (!show) return;
  const now = performance.now();
  for (const [k, a] of Object.entries(cdArcs)) {
    const cd = k === 'dash' ? p.dashCd : p.pushCd;
    // 공중 대시를 다 씀 (airDashes 0 = 공중, 땅에 닿으면 다시 참): 대시 원이 회색으로 꽉 참 → 착지하면 번쩍
    const spent = k === 'dash' && p.airDashes === 0;
    if ((a.was > 0 && cd === 0) || (a.spent && !spent && cd === 0)) a.flashUntil = now + C.COOLDOWN_FLASH_MS; // 다 찼을 때 번쩍
    a.was = cd;
    a.spent = spent;
    const flashing = now < a.flashUntil && !spent;
    const fill = cd > 0 && !spent ? 1 - cd / a.total : 1;
    const on = cd > 0 || flashing || spent;
    a.el.classList.toggle('spent', spent);
    a.el.style.display = on ? '' : 'none';
    a.track.style.display = cd > 0 && !spent ? '' : 'none';
    a.el.setAttribute('stroke-dasharray', `${a.len * fill} ${a.len}`);
    a.el.classList.toggle('flash', flashing);
  }
}

// ---------- 맨 위 승수 밑: 다음 조종권·아이템까지 (시계가 도는 동안만) ----------
const timerEls = { control: $('t-control'), power: $('t-power') };
const TIMER_LOOK = { control: { color: '#20e0e0', label: '조종권' }, power: { color: '#ffb040', label: '아이템' } };
const timerFull = { control: null, power: null }; // 시계가 새로 시작될 때의 남은 시간 = 원이 다 찬 기준 (첫 아이템·재시도는 길이가 다름)
const timerPrev = { control: null, power: null };
function updateItemTimers() {
  const t = state.itemTimers || { control: null, power: null };
  for (const [k, el] of Object.entries(timerEls)) {
    const left = t[k] ?? null;
    if (left !== null && (timerPrev[k] === null || left > timerPrev[k])) timerFull[k] = Math.max(left, 1);
    timerPrev[k] = left;
    el.classList.toggle('hidden', left === null);
    if (left === null) continue;
    const look = TIMER_LOOK[k];
    const deg = 360 * (1 - Math.min(1, left / timerFull[k]));
    el.querySelector('.pie').style.background = `conic-gradient(${look.color} ${deg}deg, rgba(255,255,255,.2) 0)`;
    const txt = el.querySelector('.txt');
    txt.textContent = `${look.label} ${Math.ceil(left / 1000)}s`;
    txt.style.color = look.color;
  }
}

// ---------- 호스트: 플레이어마다 관전 ↔ 참가, 내보내기 (판 사이에만 보임) ----------
const hostPlayersEl = $('host-players');
let hostPlayersKey = '';
// 대기 화면의 방 줄: 코드·이름·공개 여부 + (호스트) 공개 토글 · 링크 복사 · 방 나가기
let roomRowKey = '';
function updateRoomRow(show, isHost) {
  $('room-row').classList.toggle('hidden', !(show && room));
  if (!show || !room) return;
  const key = `${room.code}|${room.name}|${room.public}|${isHost}|${state.phase}`;
  if (key === roomRowKey) return;
  roomRowKey = key;
  $('room-code-text').textContent = room.code;
  $('room-name-text').textContent = room.name;
  $('room-public-text').textContent = room.public ? '공개 (목록에 보임)' : '비공개 (코드·링크로만)';
  $('room-public').classList.toggle('hidden', !isHost);
  $('room-public').textContent = room.public ? '비공개로' : '공개로';
  $('room-link').textContent = roomLink(room.code);
}

function updateHostPlayers(show) {
  hostPlayersEl.classList.toggle('hidden', !show);
  if (!show) return;
  const ps = [...state.players].sort((a, b) => a.slot - b.slot);
  const key = ps.map((p) => `${p.id}:${p.spectator}:${p.nick}:${p.team}:${p.color}`).join(',') + `|${state.teamMode}|${state.mode}`;
  if (key === hostPlayersKey) return;
  hostPlayersKey = key;
  const title = document.createElement('div');
  title.className = 'title';
  title.textContent = '플레이어 관리 (호스트)';
  // 팀전 켜기 + 팀 섞기
  const teamRow = document.createElement('div');
  teamRow.className = 'title';
  const teamLabel = document.createElement('label');
  const teamCheck = document.createElement('input');
  teamCheck.type = 'checkbox';
  teamCheck.checked = !!state.teamMode;
  teamCheck.disabled = state.mode === 'master'; // 블록 마스터는 1 대 다
  teamCheck.addEventListener('change', () => send({ type: 'teamMode', on: teamCheck.checked }));
  teamLabel.append(teamCheck, ' 팀전 (빨강 vs 파랑)');
  teamRow.append(teamLabel);
  if (state.teamMode) {
    const shuffle = document.createElement('button');
    shuffle.textContent = '팀 섞기';
    shuffle.style.marginLeft = '8px';
    shuffle.addEventListener('click', () => send({ type: 'shuffleTeams' }));
    teamRow.append(shuffle);
  }
  const cells = [title, teamRow];
  for (const p of ps) {
    const who = document.createElement('span');
    who.textContent = `${shownName(p)}${p.id === myId ? ' (나)' : ''}${p.spectator ? ' · 관전' : ''}`; // 이름은 textContent 로
    who.style.color = colorOf(p);
    const spec = document.createElement('button');
    spec.textContent = p.spectator ? '참가로' : '관전으로';
    spec.addEventListener('click', () => send({ type: 'spectate', target: p.id, on: !p.spectator }));
    let team = document.createElement('span'); // 팀전이 아니면 빈 칸
    if (state.teamMode) {
      team = document.createElement('button');
      team.textContent = TEAM_KO[p.team];
      team.style.color = hex(TEAM_MAIN[p.team]);
      team.title = '눌러서 팀 바꾸기';
      team.addEventListener('click', () => send({ type: 'setTeam', target: p.id, team: p.team === 'red' ? 'blue' : 'red' }));
    }
    let kick = document.createElement('span'); // 자기 자신은 못 내보냄: 빈 칸으로 열 맞춤
    if (p.id !== myId) {
      kick = document.createElement('button');
      kick.textContent = '내보내기';
      kick.addEventListener('click', () => send({ type: 'kick', target: p.id }));
    }
    cells.push(who, team, spec, kick);
  }
  hostPlayersEl.replaceChildren(...cells);
}

// ---------- 화면 아래: 피해 % · 경직 · 버프 · 든 아이템 ----------
$('crit-dmg').textContent = C.CRIT_DAMAGE_MULT;
const bottomEl = $('bottom');
const damageEl = $('damage');
const buffsEl = $('buffs');
const stunEl = $('stun');
const vignetteEl = $('vignette');
const itemSlotEl = $('item-slot');
let shownDamage = null;
let bottomKey = '';
function updateBottom(p) {
  const show = !!p && p.alive && !p.master && (state.phase === 'playing' || state.phase === 'countdown'); // 마스터는 몸이 없어 아이템·피해 % 없음
  bottomEl.classList.toggle('hidden', !show);
  // 내 피해 % 는 아래 내 판(#players)이 크게 보여 준다 → 판이 없는 때(연습·혼자)만 따로 띄운다
  damageEl.classList.toggle('hidden', !show || cardsOn()); // 3인칭에선 #bottom 밖 (구석)
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
  if (p.jumpLeft > 0) buffs.push(`점프↑ ${(p.jumpLeft / 1000).toFixed(1)}s`);
  if (p.speedLeft > 0) buffs.push(`이속↑ ${(p.speedLeft / 1000).toFixed(1)}s`);
  if (p.ghostLeft > 0) buffs.push(`유령 ${(p.ghostLeft / 1000).toFixed(1)}s`);
  if (p.shieldLeft > 0) buffs.push(`부활 무적 ${(p.shieldLeft / 1000).toFixed(1)}s`);
  // 든 아이템 (하나만). 망치는 위 버프 줄에도 횟수가 나옴
  const item =
    p.ammo > 0 ? `투사체 ×${p.ammo}` : p.bricks > 0 ? `설치 1×2 ×${p.bricks} ${p.brickSide ? '옆' : '앞'}` : p.bombs > 0 ? `폭탄 ×${p.bombs}` : '아이템 —';
  if (p.iframeLeft > 0) buffs.push(`무적 ${(p.iframeLeft / 1000).toFixed(1)}s`);
  updateSkills(p);
  updateMyMarks(p);
  updateCannonHud(p);
  const key = `${buffs.join('|')}#${item}`;
  if (key === bottomKey) return;
  bottomKey = key;
  buffsEl.innerHTML = buffs.map((b) => `<span class="buff">${b}</span>`).join('');
  itemSlotEl.querySelector('.name').textContent = item;
  itemSlotEl.classList.toggle('empty', item.endsWith('—'));
}

// 캐릭터 스킬 F (쿨타임) · 필살기 R (게이지) 칸
const skillsEl = $('skills');
function updateSkills(p) {
  skillsEl.classList.toggle('hidden', !p.char);
  if (!p.char) return;
  const f = $('skill-f');
  const r = $('skill-r');
  const cdTotal = C.SKILL_CD_MS[p.char];
  f.querySelector('.name').textContent = `${C.SKILL_NAMES[p.char]} ${p.skillCd > 0 ? `${(p.skillCd / 1000).toFixed(1)}s` : ''}`;
  f.querySelector('.fill').style.width = `${p.skillCd > 0 ? (1 - p.skillCd / cdTotal) * 100 : 100}%`;
  f.classList.toggle('ready', p.skillCd <= 0);
  const ultMax = p.ultMax || C.ULT_MAX; // 사냥꾼은 2배
  const full = p.ult >= ultMax;
  const pct = Math.floor((p.ult / ultMax) * 100);
  // 사냥꾼: 게이지가 찼어도 지금 쏠 표식 대상이 없으면 회색 (서버 판정 ultTarget, 다른 캐릭터는 undefined)
  const dim = full && p.ultTarget === false;
  const ultName = p.char === 'bard' && p.bard?.form === 'metal' ? C.BARD_METAL_ULT_NAME : C.ULT_NAMES[p.char]; // 바드는 폼 따라
  r.querySelector('.name').textContent = performance.now() < ultFailUntil ? ultFailText : `${ultName} ${full ? '준비!' : `${pct}%`}`;
  r.querySelector('.fill').style.width = `${Math.min(100, (p.ult / ultMax) * 100)}%`;
  r.classList.toggle('ready', full && !dim);
  r.style.filter = dim ? 'grayscale(1) brightness(.7)' : '';
  // 갈고리 장전: R 칸 옆 작은 탄 (금색 = 장전, 빈 고리 = 빈 총)
  const ammo = $('ammo');
  ammo.classList.toggle('hidden', p.char !== 'hook');
  ammo.classList.toggle('loaded', !!p.loaded);
  // 탱크 패시브: 맞아서 필살기 게이지가 크게 찼을 때 칸이 반짝
  if (p.char === 'tank' && lastSelf && p.ult > lastSelf.ult && p.damage > lastSelf.damage) {
    r.classList.remove('glint');
    void r.offsetWidth; // 연달아 맞아도 다시 반짝
    r.classList.add('glint');
  }
  lastSelf = { ult: p.ult, damage: p.damage };
}
let lastSelf = null;
// 대포수 탄: F·R 칸 옆에 포탄 3칸 (찬 칸 = 검은 공, 빈 칸 = 테두리) + 다음 한 발 장전 진행 (빈 칸 첫째가 아래부터 차오름)
const cannonEl = document.createElement('div');
cannonEl.className = 'slot';
Object.assign(cannonEl.style, { display: 'none', minWidth: '0', gap: '6px', alignItems: 'center' });
const cannonBalls = [];
for (let i = 0; i < C.CANNON_AMMO_MAX; i++) {
  const b = document.createElement('div');
  Object.assign(b.style, { width: '18px', height: '18px', borderRadius: '50%', border: '2px solid #ddd', position: 'relative', overflow: 'hidden', background: 'transparent' });
  const fill = document.createElement('div');
  Object.assign(fill.style, { position: 'absolute', left: 0, right: 0, bottom: 0, height: '0%', background: '#2a2c30' });
  b.append(fill);
  cannonEl.append(b);
  cannonBalls.push({ b, fill });
}
$('skills').append(cannonEl);
function updateCannonHud(p) {
  const c = p && p.char === 'cannon' && p.cannon;
  cannonEl.style.display = c ? 'flex' : 'none';
  if (!c) return;
  const prog = c.reloadMs ? 1 - c.reloadLeft / c.reloadMs : 0;
  cannonBalls.forEach(({ b, fill }, i) => {
    const full = i < c.ammo;
    fill.style.height = full ? '100%' : i === c.ammo && c.reloadLeft > 0 ? `${Math.round(prog * 100)}%` : '0%';
    fill.style.background = full ? 'radial-gradient(circle at 35% 35%, #9a9ca4, #2a2c30 60%)' : '#6a6c70'; // 찬 칸 = 반짝이는 쇠공
    b.style.borderColor = full ? '#ffd23a' : '#888';
  });
}
function cannonHudFlash(ammo) {
  const ball = cannonBalls[ammo - 1];
  if (ball) ball.b.animate([{ transform: 'scale(1.5)', boxShadow: '0 0 10px #ffd23a' }, { transform: 'scale(1)' }], { duration: 300 });
}
// 내게 붙은 표식 (1인칭이라 머리 위가 안 보임): 화면 위 가운데 빨간 마름모, 사라지기 직전 깜빡
const myMarksEl = document.createElement('div');
myMarksEl.id = 'my-marks';
Object.assign(myMarksEl.style, { position: 'fixed', top: '13%', left: '50%', transform: 'translateX(-50%)', color: '#ff3a2a', fontSize: '26px', letterSpacing: '6px', textShadow: '0 0 4px #000, 0 0 2px #000', pointerEvents: 'none', zIndex: 5 });
document.body.append(myMarksEl);
function updateMyMarks(p) {
  const list = (p && p.alive && p.marks) || [];
  const m = list.reduce((a, b) => (!a || b.n > a.n ? b : a), null);
  const blink = m && m.left < C.MARK_BLINK_MS && Math.floor(performance.now() / C.MARK_BLINK_PERIOD_MS) % 2 === 1;
  const txt = m && !blink ? '◆'.repeat(Math.min(C.HUNTER_MARK_MAX, m.n)) : '';
  if (myMarksEl.textContent !== txt) myMarksEl.textContent = txt;
}
// R 을 못 씀 (ultFail): 칸이 빨갛게 좌우로 흔들리고 이름 자리에 짧은 이유
const ULT_FAIL_TEXT = { noBlock: '블록 없음', noSpace: '자리 없음', busy: '사용 중', noTarget: '대상 없음' };
let ultFailUntil = 0;
let ultFailText = '';
function slotFail(reason) {
  ultFailText = ULT_FAIL_TEXT[reason] || '못 씀';
  ultFailUntil = performance.now() + C.ULT_FAIL_MS;
  const r = $('skill-r');
  r.animate(
    [0, -7, 6, -4, 2, 0].map((x) => ({ transform: `translateX(${x}px)`, borderColor: '#ff3030', boxShadow: '0 0 10px #ff3030' })),
    { duration: C.ULT_FAIL_SHAKE_MS, easing: 'ease-out' },
  );
  r.querySelector('.name').animate([{ color: '#ff5050' }, { color: '#ff5050' }], { duration: C.ULT_FAIL_MS });
}
// 기억해 둔 F·R 이 버려짐 (castDrop): 칸이 살짝 어두워졌다 돌아옴
function slotBlink(id) {
  $(id).animate([{ opacity: 1 }, { opacity: 0.35 }, { opacity: 1 }, { opacity: 0.35 }, { opacity: 1 }], { duration: C.CAST_DROP_BLINK_MS });
}

// 대기 화면 캐릭터 고르기 (이 브라우저에 기억, 접속할 때 보냄)
const charSel = $('char-select');
for (const c of C.CHARACTERS) {
  const o = document.createElement('option');
  o.value = c;
  o.textContent = C.CHAR_NAMES[c];
  charSel.append(o);
}
function loadPref(k) {
  try {
    return localStorage.getItem(k);
  } catch {
    return null;
  }
}
charSel.addEventListener('change', () => {
  try {
    localStorage.setItem('tf-char', charSel.value);
  } catch {
    // 저장이 막혀도 이번 접속에는 보냄
  }
  send({ type: 'setChar', char: charSel.value });
  charSel.blur();
});
// 대기실 색 고르기: 팔레트 색 칸 (남이 쓰는 색은 ×, 판 중엔 대기 줄 자체가 숨음). 고른 색은 이 브라우저에 기억 (tf-color)
const swatchEls = C.PLAYER_PALETTE.map((col, i) => {
  const el = document.createElement('span');
  el.className = 'sw';
  el.style.background = hex(col);
  el.addEventListener('click', () => {
    if (el.classList.contains('used')) return;
    try {
      localStorage.setItem('tf-color', String(i));
    } catch {
      // 저장이 막혀도 이번 접속에는 보냄
    }
    send({ type: 'setColor', color: i });
  });
  $('color-swatches').append(el);
  return el;
});
function updateColorRow(p) {
  const used = new Set(state.players.filter((o) => o.id !== p.id).map((o) => o.color));
  swatchEls.forEach((el, i) => {
    el.classList.toggle('mine', p.color === i);
    el.classList.toggle('used', used.has(i));
    el.title = used.has(i) ? '다른 사람이 쓰는 색' : '';
  });
  $('color-team-note').classList.toggle('hidden', !state.teamMode);
}
// 캐릭터 초상 카드 (대기실): 누르면 위 select 값을 바꿔 보낸다 — 고르는 길은 하나로 둔다.
// 초상은 내 색으로 그리므로 색을 바꾸면 다시 그린다 (portrait.js 가 캐시)
const charCardsEl = $('char-cards');
let charCardsKey = '';
function updateCharCards(p) {
  const col = playerColor(p, state);
  if (charCardsKey !== String(col)) {
    charCardsKey = String(col);
    charCardsEl.textContent = '';
    for (const c of C.CHARACTERS) {
      const el = document.createElement('div');
      el.className = 'cc';
      el.dataset.char = c;
      el.title = C.CHAR_NAMES[c];
      el.innerHTML = '<div class="face"></div><div class="nm"></div>';
      const img = portrait(c, col, 128, true);
      if (img) el.querySelector('.face').style.backgroundImage = `url(${img})`;
      el.querySelector('.nm').textContent = C.CHAR_NAMES[c];
      el.addEventListener('click', () => {
        if (charSel.value === c) return;
        charSel.value = c;
        charSel.dispatchEvent(new Event('change'));
      });
      charCardsEl.append(el);
    }
  }
  for (const el of charCardsEl.children) el.classList.toggle('sel', el.dataset.char === p.char);
}
function updateCharRow(p) {
  if (p && p.color !== undefined) updateColorRow(p);
  const on = !!p && !!p.char;
  $('char-label').classList.toggle('hidden', !on);
  charCardsEl.classList.toggle('hidden', !on);
  $('char-info').classList.toggle('hidden', !on);
  if (!on) return;
  if (document.activeElement !== charSel) charSel.value = p.char;
  updateCharCards(p);
  $('char-info').textContent = charDesc(p.char);
}

// ---------- 연습 방 (샌드박스): 토글·내 피해·허수아비·캐릭터 + 허수아비 콤보 기록 ----------
// 연습 키(기본 Tab)로 왼쪽 작은 창을 열고 닫음 (열면 마우스가 풀려 고를 수 있음). 콤보 기록은 오른쪽에 작게, 연습 방에서만
const practiceEl = $('practice');
const practiceHint = $('practice-hint');
const pcomboEl = $('pcombo');
const prDummiesEl = $('pr-dummies');
const prMyDmg = $('pr-mydmg');
const prChar = $('pr-char');
let practiceOpen = false;
let prDummyKey = '';
const practiceDone = new Map(); // 허수아비 id → 끝난 콤보 { hits, damage, dist, height, until }
const inPractice = () => !!((room && room.practice) || (state && state.practice));
const prPlaying = () => inPractice() && !!state && (state.phase === 'playing' || state.phase === 'countdown');
$('practice-btn').addEventListener('click', () => {
  syncNick();
  roomsMsg.textContent = '';
  send({ type: 'practice', nick: roomsNick.value, char: loadPref('tf-char') || undefined });
});
function setPracticeOpen(on) {
  practiceOpen = !!on && prPlaying();
  practiceEl.classList.toggle('hidden', !practiceOpen);
  if (practiceOpen && document.pointerLockElement) document.exitPointerLock(); // 마우스로 고르게 (닫고 화면을 누르면 다시 조작)
}
$('pr-close').addEventListener('click', () => setPracticeOpen(false));
for (const box of practiceEl.querySelectorAll('[data-pr]')) {
  box.addEventListener('change', () => {
    send({ type: 'practiceSet', key: box.dataset.pr, value: box.checked });
    box.blur();
  });
}
const pctOf = (el) => Math.round(Number(el.value) || 0); // 범위(0~최대)는 서버가 자름
const hex2num = (h) => parseInt(h.slice(1), 16);
prMyDmg.max = C.PRACTICE_DAMAGE_MAX;
const prMap = $('pr-map');
for (const o of $('map-select').options) prMap.append(new Option(o.textContent, o.value));
prMap.addEventListener('change', () => {
  send({ type: 'setMap', map: prMap.value });
  prMap.blur();
});
prMyDmg.addEventListener('change', () => send({ type: 'practiceSet', key: 'myDamage', value: pctOf(prMyDmg) }));
for (const c of C.CHARACTERS) {
  const o = document.createElement('option');
  o.value = c;
  o.textContent = C.CHAR_NAMES[c];
  prChar.append(o);
}
prChar.addEventListener('change', () => {
  try {
    localStorage.setItem('tf-char', prChar.value);
  } catch {
    // 저장이 막혀도 이번 접속에는 보냄
  }
  send({ type: 'setChar', char: prChar.value });
  prChar.blur();
});
$('pr-add').addEventListener('click', () => send({ type: 'dummyAdd' }));
const fix1 = (v) => (Number.isFinite(v) ? v.toFixed(1) : '0');

function updatePractice(p) {
  const on = prPlaying();
  if (!on && practiceOpen) setPracticeOpen(false);
  practiceHint.classList.toggle('hidden', !on || practiceOpen);
  if (!on) {
    pcomboEl.textContent = '';
    return;
  }
  const pr = state.practice || {};
  const dummies = pr.dummies || [];
  if (practiceOpen) {
    for (const box of practiceEl.querySelectorAll('[data-pr]')) box.checked = !!pr[box.dataset.pr];
    if (document.activeElement !== prMyDmg) prMyDmg.value = Math.round(p.damage || 0);
    if (document.activeElement !== prChar && p.char) prChar.value = p.char;
    if (document.activeElement !== prMap && state.map) prMap.value = state.map.choice;
    $('pr-add').disabled = dummies.length >= C.PRACTICE_DUMMY_MAX;
    // 허수아비 줄: 이름 · 피해 % 칸 · 삭제 (허수아비가 바뀔 때만 다시 만듦)
    const key = dummies.map((d) => d.id).join(',');
    if (key !== prDummyKey) {
      prDummyKey = key;
      prDummiesEl.textContent = '';
      for (const d of dummies) {
        const row = document.createElement('div');
        row.className = 'dummy';
        row.dataset.id = d.id;
        const name = document.createElement('span');
        name.textContent = shownName(playerById(d.id) || { name: '허수아비' });
        const pct = document.createElement('input');
        pct.type = 'number';
        pct.min = '0';
        pct.max = prMyDmg.max;
        pct.step = prMyDmg.step;
        pct.addEventListener('change', () => send({ type: 'dummySet', id: d.id, damage: pctOf(pct) }));
        const del = document.createElement('button');
        del.textContent = '삭제';
        del.addEventListener('click', () => send({ type: 'dummyRemove', id: d.id }));
        row.append(name, pct, document.createTextNode('%'), del);
        prDummiesEl.append(row);
      }
    }
    for (const row of prDummiesEl.children) {
      const d = dummies.find((x) => String(x.id) === row.dataset.id);
      const pct = row.querySelector('input');
      if (d && document.activeElement !== pct) pct.value = Math.round(d.damageSet ?? playerById(d.id)?.damage ?? 0);
    }
  }
  // 콤보 기록: 진행 중이면 노란 타 수 · 피해 · 거리 (높이는 뜬 만큼만), 끝나면 흰 글씨로 잠깐
  const now = performance.now();
  const lines = [];
  for (const d of dummies) {
    const c = d.combo;
    const done = practiceDone.get(d.id);
    const tag = dummies.length > 1 ? `${escapeHtml(shownName(playerById(d.id) || { name: '허수아비' }))} · ` : '';
    const text = (x) => `${tag}<b>${x.hits}타</b> ${Math.round(x.damage)}% · ${fix1(x.dist)}칸${x.height >= C.PRACTICE_SHOW_HEIGHT ? ` · 높이 ${fix1(x.height)}` : ''}`;
    if (c && c.active && c.hits > 0) lines.push(`<div class="c">${text(c)}</div>`);
    else if (done && now < done.until) lines.push(`<div class="c done" style="opacity:${Math.min(1, (done.until - now) / 400)}">${text(done)}</div>`);
  }
  const html = lines.join('');
  if (pcomboEl.innerHTML !== html) pcomboEl.innerHTML = html;
}

// 입력 전송
setInterval(() => {
  if (!state || (state.phase !== 'playing' && state.phase !== 'countdown')) return;
  send(debug.inputOverride || input.sample());
}, 1000 / C.INPUT_SEND_RATE);

let last = performance.now();
let frameErrorShown = false;
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000) * ko.timeScale(now); // KO 슬로모션·히트스톱 (화면만)
  sound.slowmo(ko.timeScale(now)); // 슬로모션이면 효과음 먹먹하고 낮게
  last = now;
  ko.update(dt);
  const p = me();
  const view = p && p.alive && (p.controlling || p.master) ? 'sky' : 'fps'; // 블록 마스터는 다음 블록을 기다리는 동안에도 하늘
  if (view === 'sky' && !input.sky) {
    // 조종 시작: 보던 방향을 90도 단위로 맞추고 그 방향을 하늘 화면 위쪽으로 (W 가 계속 앞, 끝나고 돌아와도 같은 방향)
    const snapped = Math.round(input.yaw / (Math.PI / 2)) * (Math.PI / 2);
    input.setYawPitch(snapped, input.pitch);
    renderer.skyYaw = snapped;
  }
  input.sky = view === 'sky';
  // 한 프레임에서 에러가 나도 다음 프레임은 계속 그린다 (안 그러면 서버는 도는데 화면만 멈춤)
  try {
    updateSpectate();
    updateGhostAim();
    if (state) music.setMood(state.phase === 'playing' || state.phase === 'countdown' ? (state.lava && state.lava.active ? 'lava' : 'battle') : 'calm');
    music.update(state); // 맵 테마별 곡
    const vic = state && state.phase === 'over' && performance.now() < victory.until ? victory.id : null;
    const selfie = p && p.alive && p.emote >= 0 && !vic ? myId : null; // 내 이모트는 앞에서 보이게
    renderer.render(state, myId, dt, view, { yaw: input.yaw, pitch: input.pitch, follow: spectating() && !spec.overview ? spec.target : null, dist: spec.dist, overviewDist: spec.overviewDist, victory: vic, selfie });
    sound.update(renderer.camera.matrixWorld.elements, state, dt); // 귀(카메라) 위치·방향 + 위험 액체 지속음
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
  event: handleEvent, // 서버 이벤트를 손으로 넣어 화면 확인 (예: {type:'counter', by, target})
  getState: () => state,
  getMyId: () => myId,
  input,
  inputOverride: null,
  renderer,
  sound,
  music,
  ko,
  // 클릭과 같은 경로로 행동 보내기 (로컬 팔 휘두르기·소리 포함)
  act: (action) => {
    onLocalAction(action);
    send({ type: 'action', ...action });
  },
};
window.__tf = debug;
