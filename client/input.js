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

    canvas.addEventListener('click', () => {
      if (!this.locked) canvas.requestPointerLock();
    });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === canvas;
      if (!this.locked) this.keys.clear();
    });
    document.addEventListener('mousemove', (e) => {
      if (!this.locked) return;
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

    document.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
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
        default:
      }
    });
    document.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());
  }

  setYawPitch(yaw, pitch) {
    this.yaw = yaw;
    this.pitch = pitch;
  }

  // 서버에 보낼 연속 입력
  sample() {
    const k = this.keys;
    const fwd = (k.has('KeyW') ? 1 : 0) - (k.has('KeyS') ? 1 : 0);
    const strafe = (k.has('KeyD') ? 1 : 0) - (k.has('KeyA') ? 1 : 0);
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
