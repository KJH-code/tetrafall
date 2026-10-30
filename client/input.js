// 키보드·마우스 입력. 연속 입력은 주기적으로, 단발 행동은 즉시 서버에 보낸다.
import { CONFIG as C } from '/shared/config.js';
import { loadBinds, normCode, wheelSlot } from '/keys.js';

// 글자 칸에 쓰는 중 (체크박스·슬라이더에 포커스가 남은 건 아님)
const typing = () => {
  const el = document.activeElement;
  return !!el && (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && /^(text|search|number|)$/.test(el.type || '')));
};

export class Input {
  constructor(canvas, sendAction) {
    this.canvas = canvas;
    this.sendAction = sendAction;
    this.keys = new Set();
    this.yaw = 0;
    this.pitch = 0;
    this.locked = false;
    this.enabled = false; // 판 진행 중 + 살아있을 때만 true
    this.sky = false; // 하늘 시점: 마우스 회전 무시. 화면 위쪽 = 조종을 시작할 때 보던 방향(90도로 맞춤)이라 WASD·방향키 모두 화면 기준
    this.sensitivity = 1; // 설정의 감도 배수
    this.wheel = null; // 이모트 바퀴: G 를 누르고 있는 동안 마우스 이동량 {x, y} (그동안 시점은 안 돎)
    this.onWheel = () => {}; // 바퀴 메뉴 표시 갱신 (main 이 넣음): (null | 고른 번호 -1~3)
    this.onUi = () => {}; // 도움말·시점 키 (main 이 넣음): (행동 id, 누름 true / 뗌 false)
    this.setBinds(loadBinds());

    canvas.addEventListener('click', () => {
      if (!this.locked) canvas.requestPointerLock();
    });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === canvas;
      if (!this.locked) this.keys.clear();
    });
    document.addEventListener('mousemove', (e) => {
      if (this.wheel) {
        this.wheel.x += e.movementX;
        this.wheel.y += e.movementY;
        this.onWheel(this.wheelPick());
        return;
      }
      if (!this.locked || this.sky) return;
      this.yaw -= e.movementX * C.MOUSE_SENSITIVITY * this.sensitivity;
      this.pitch -= e.movementY * C.MOUSE_SENSITIVITY * this.sensitivity;
      const lim = Math.PI / 2 - 0.05;
      this.pitch = Math.max(-lim, Math.min(lim, this.pitch));
    });
    // 키보드·마우스 버튼을 같은 길로: 누른 코드(KeyF, Mouse0 …)를 keys 에 넣고, 그 코드에 묶인 행동을 실행
    document.addEventListener('mousedown', (e) => {
      if (!this.locked) return; // 잠기기 전 클릭은 화면 클릭 (잠그기)
      if (e.button > 2) e.preventDefault(); // 옆 버튼이 브라우저 뒤로 가기가 되지 않게
      this.down(`Mouse${e.button}`);
    });
    document.addEventListener('mouseup', (e) => {
      if (e.button > 2) e.preventDefault();
      this.up(`Mouse${e.button}`);
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    document.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      if (typing()) return; // 글 칠 때는 게임 키 아님
      if (this.down(normCode(e.code))) e.preventDefault(); // 방향키·Space 가 화면을 굴리지 않게
    });
    document.addEventListener('keyup', (e) => this.up(normCode(e.code)));
    window.addEventListener('blur', () => {
      this.keys.clear();
      if (this.wheel) {
        this.wheel = null;
        this.onWheel(null);
      }
      this.onUi('help', false);
    });
  }

  // 키 설정 바꾸기 (설정 창). binds: { 행동 id: 코드 }
  setBinds(binds) {
    this.binds = { ...binds };
    this.byCode = new Map();
    for (const [id, code] of Object.entries(this.binds)) {
      if (!this.byCode.has(code)) this.byCode.set(code, []);
      this.byCode.get(code).push(id);
    }
  }

  held(id) {
    return this.keys.has(this.binds[id]);
  }

  // 코드를 누름 → 묶인 행동들 실행. 행동이 하나라도 있으면 true
  down(code) {
    if (this.keys.has(code)) return true; // 마우스는 repeat 가 없어 겹쳐 올 수 있음
    this.keys.add(code);
    const ids = this.byCode.get(code);
    if (!ids) return false;
    for (const id of ids) this.press(id);
    return true;
  }

  up(code) {
    if (!this.keys.delete(code)) return;
    for (const id of this.byCode.get(code) || []) {
      if (id === 'emote' && this.wheel) {
        const n = this.wheelPick();
        this.wheel = null;
        this.onWheel(null);
        if (n >= 0) this.sendAction({ name: 'emote', n });
      }
      if (id === 'help' || id === 'view') this.onUi(id, false);
    }
  }

  press(id) {
    // 판과 상관없이 되는 것: 도움말·시점 (main 이 처리), 이모트 바퀴 (판이 끝난 뒤에도 됨)
    if (id === 'help' || id === 'view' || id === 'practice' || id === 'perf' || id === 'tutSkip') return this.onUi(id, true);
    if (id === 'viewL' || id === 'viewR') return this.sky && this.onUi(id, true); // 하늘 시점 돌리기 (main 이 yaw·카메라를 같이)
    if (id === 'emote') {
      if (this.locked && !this.wheel) {
        this.wheel = { x: 0, y: 0 };
        this.onWheel(-1);
      }
      return;
    }
    if (!this.enabled) return;
    const act = {
      jump: () => this.locked && this.sendAction({ name: 'jump' }), // 누른 순간 (공중이면 2단 점프)
      dash: () => this.sendAction({ name: 'dash' }),
      attack: () => this.locked && this.sendAction({ name: 'push' }),
      item: () => this.locked && this.sendAction({ name: 'fire' }),
      skill: () => this.sendAction({ name: 'skill' }), // 캐릭터 스킬 (쿨타임)
      ult: () => this.sendAction({ name: 'ult' }), // 필살기 (게이지)
      rotL: () => this.sendAction({ name: 'rotate', dir: -1 }),
      rotR: () => this.sendAction({ name: 'rotate', dir: 1 }),
      drop: () => this.sendAction({ name: 'drop' }),
      pieceUp: () => this.pieceMove(0, 1),
      pieceDown: () => this.pieceMove(0, -1),
      pieceLeft: () => this.pieceMove(-1, 0),
      pieceRight: () => this.pieceMove(1, 0),
    }[id];
    if (act) act();
  }

  // 바퀴에서 고른 것: 위 0 부터 시계 방향으로 칸마다 (EMOTE_NAMES 개, 5칸이면 72°씩), 덜 움직였으면 -1
  wheelPick() {
    return wheelSlot(this.wheel, C.EMOTE_NAMES.length, C.EMOTE_PICK_PX);
  }

  // 방향키 (블록 조종): 하늘 화면 기준 (sx 오른쪽, sy 위) → 격자 방향. 화면 위쪽이 보던 방향(90도 단위)이라 돌려서 보낸다
  pieceMove(sx, sy) {
    const c = Math.cos(this.yaw);
    const s = Math.sin(this.yaw);
    this.sendAction({ name: 'pieceMove', dx: Math.round(sx * s + sy * c), dy: Math.round(-sx * c + sy * s) });
  }

  setYawPitch(yaw, pitch) {
    this.yaw = yaw;
    this.pitch = pitch;
  }

  // 서버에 보낼 연속 입력
  sample() {
    const fwd = (this.held('fwd') ? 1 : 0) - (this.held('back') ? 1 : 0);
    const strafe = (this.held('right') ? 1 : 0) - (this.held('left') ? 1 : 0);
    // 하늘 시점도 화면 위쪽 = 보던 방향이라 이동 키를 그대로 앞·왼·뒤·오른쪽으로 보낸다 (조종 전후로 방향이 안 바뀜)
    return {
      type: 'input',
      fwd: this.locked ? fwd : 0,
      strafe: this.locked ? strafe : 0,
      jump: this.locked && this.held('jump'),
      yaw: this.yaw,
      pitch: this.pitch,
    };
  }
}
