// 키보드·마우스 입력. 연속 입력은 주기적으로, 단발 행동은 즉시 서버에 보낸다.
import { CONFIG as C } from '/shared/config.js';

export class Input {
  constructor(canvas, sendAction) {
    this.canvas = canvas;
    this.sendAction = sendAction;
    this.keys = new Set();
    this.yaw = 0;
    this.pitch = 0;
    this.locked = false;
    this.enabled = false; // 판 진행 중 + 살아있을 때만 true
    this.sky = false; // 하늘 시점: WASD 가 화면 기준(W=화면 위), 마우스 회전 무시
    this.wheel = null; // 이모트 바퀴: G 를 누르고 있는 동안 마우스 이동량 {x, y} (그동안 시점은 안 돎)
    this.onWheel = () => {}; // 바퀴 메뉴 표시 갱신 (main 이 넣음): (null | 고른 번호 -1~3)

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
      this.yaw -= e.movementX * C.MOUSE_SENSITIVITY;
      this.pitch -= e.movementY * C.MOUSE_SENSITIVITY;
      const lim = Math.PI / 2 - 0.05;
      this.pitch = Math.max(-lim, Math.min(lim, this.pitch));
    });
    document.addEventListener('mousedown', (e) => {
      if (!this.locked || !this.enabled) return;
      if (e.button === 0) this.sendAction({ name: 'push' });
      if (e.button === 2) this.sendAction({ name: 'fire' });
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    // 마우스 휠로 핫바 칸 돌리기 (터치패드가 한 번에 여러 번 보내서 WHEEL_STEP_MS 에 한 칸)
    let lastWheel = 0;
    document.addEventListener('wheel', (e) => {
      if (!this.locked || !this.enabled || !e.deltaY) return;
      const now = performance.now();
      if (now - lastWheel < C.WHEEL_STEP_MS) return;
      lastWheel = now;
      this.sendAction({ name: 'handNext', dir: e.deltaY > 0 ? 1 : -1 });
    });

    document.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
      if (e.code === 'KeyG' && this.locked && !this.wheel) {
        // 이모트 바퀴 열기 (판이 끝난 뒤에도 됨)
        this.wheel = { x: 0, y: 0 };
        this.onWheel(-1);
        return;
      }
      if (!this.enabled) return;
      switch (e.code) {
        case 'ShiftLeft':
        case 'ShiftRight':
          this.sendAction({ name: 'dash' });
          break;
        case 'ArrowUp':
          this.sendAction({ name: 'pieceMove', dx: 0, dy: 1 });
          e.preventDefault();
          break;
        case 'ArrowDown':
          this.sendAction({ name: 'pieceMove', dx: 0, dy: -1 });
          e.preventDefault();
          break;
        case 'ArrowLeft':
          this.sendAction({ name: 'pieceMove', dx: -1, dy: 0 });
          e.preventDefault();
          break;
        case 'ArrowRight':
          this.sendAction({ name: 'pieceMove', dx: 1, dy: 0 });
          e.preventDefault();
          break;
        case 'KeyQ':
          this.sendAction({ name: 'rotate', dir: -1 });
          break;
        case 'KeyE':
          this.sendAction({ name: 'rotate', dir: 1 });
          break;
        case 'Enter':
          this.sendAction({ name: 'drop' });
          break;
        case 'Digit1':
        case 'Digit2':
        case 'Digit3':
          this.sendAction({ name: 'hand', n: Number(e.code.slice(5)) }); // 핫바 칸 고르기
          break;
        default:
      }
    });
    document.addEventListener('keyup', (e) => {
      this.keys.delete(e.code);
      if (e.code === 'KeyG' && this.wheel) {
        const n = this.wheelPick();
        this.wheel = null;
        this.onWheel(null);
        if (n >= 0) this.sendAction({ name: 'emote', n });
      }
    });
    window.addEventListener('blur', () => {
      this.keys.clear();
      if (this.wheel) {
        this.wheel = null;
        this.onWheel(null);
      }
    });
  }

  // 바퀴에서 고른 것: 위 0 · 오른쪽 1 · 아래 2 · 왼쪽 3, 덜 움직였으면 -1
  wheelPick() {
    const w = this.wheel;
    if (!w || Math.hypot(w.x, w.y) < C.EMOTE_PICK_PX) return -1;
    if (Math.abs(w.x) > Math.abs(w.y)) return w.x > 0 ? 1 : 3;
    return w.y < 0 ? 0 : 2;
  }

  setYawPitch(yaw, pitch) {
    this.yaw = yaw;
    this.pitch = pitch;
  }

  // 서버에 보낼 연속 입력
  sample() {
    const k = this.keys;
    let fwd = (k.has('KeyW') ? 1 : 0) - (k.has('KeyS') ? 1 : 0);
    let strafe = (k.has('KeyD') ? 1 : 0) - (k.has('KeyA') ? 1 : 0);
    if (this.sky) {
      // 하늘 시점 화면: 위 = +y, 오른쪽 = +x. 화면 기준 이동을 바라보는 방향 기준 fwd/strafe 로 바꾼다
      const len = Math.hypot(strafe, fwd) || 1; // 대각선도 서버 clamp(-1..1) 안에 들도록 정규화
      const mx = strafe / len;
      const my = fwd / len;
      fwd = mx * Math.cos(this.yaw) + my * Math.sin(this.yaw);
      strafe = mx * Math.sin(this.yaw) - my * Math.cos(this.yaw);
    }
    return {
      type: 'input',
      fwd: this.locked ? fwd : 0,
      strafe: this.locked ? strafe : 0,
      jump: this.locked && k.has('Space'),
      yaw: this.yaw,
      pitch: this.pitch,
    };
  }
}
