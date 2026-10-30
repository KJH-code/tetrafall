// 메뉴(방 목록) 뒤 3D 배경: 화면만의 가짜 대기 장면. 서버 없이 renderer 가 그림 (Renderer.render 에 state 가 없을 때).
// 무작위 맵 테마 섬 + 캐릭터 몇 명이 섬 위에서 대기 (가만·버릇은 figure.js, 가끔 이모트) + 천천히 도는 카메라.
// 판정·규칙과 무관. 방에 들어가 진짜 state 가 오면 renderer 가 이 장면을 버림 (가짜 몸은 다음 프레임 players 정리에서 지워짐)
import { CONFIG as C } from '../shared/config.js';
import { MAP_IDS, mapColumns } from '../shared/maps.js';
import { CELL } from '../shared/pieces.js';

// 가짜 몸 id: 진짜 플레이어(양수)·허수아비(-1000…)와 안 겹치게
const ID0 = -9000;

export class MenuScene {
  // rnd: 0~1 난수 (테스트에서 고정), low: 그래픽 낮춤, mapId: 섬 맵 (없으면 무작위 — 타이틀 뒤면 그 테마의 맵, shared/title.js titleMapFor)
  constructor(rnd = Math.random, low = false, mapId = null) {
    this.rnd = rnd;
    this.mapId = MAP_IDS.includes(mapId) ? mapId : MAP_IDS[Math.floor(rnd() * MAP_IDS.length)];
    const W = C.GRID_W;
    const D = C.GRID_D;
    const H = C.GRID_H;
    this.W = W;
    this.D = D;
    const grid = new Uint8Array(W * D * H);
    const top = new Map(); // 칸 → 기둥 높이
    for (const [x, y, h] of mapColumns(this.mapId, W, D)) {
      for (let z = 0; z < h; z++) grid[(z * D + y) * W + x] = CELL.TERRAIN;
      top.set(`${x},${y}`, Math.max(top.get(`${x},${y}`) || 0, h));
    }
    this.time = 0;
    this.camYaw = rnd() * Math.PI * 2;
    // 서는 자리: 필드 안쪽에서 서로 2칸 넘게 떨어진 칸 (기둥이면 그 위)
    const n = C.MENU_CHARS[low ? 1 : 0];
    const chars = [...C.CHARACTERS].sort(() => rnd() - 0.5).slice(0, n);
    const spots = [];
    for (let tries = 0; spots.length < chars.length && tries < 200; tries++) {
      const x = 2 + Math.floor(rnd() * (W - 4));
      const y = 2 + Math.floor(rnd() * (D - 4));
      if (spots.some((s) => Math.hypot(s.x - x, s.y - y) < 2.5)) continue;
      spots.push({ x, y, z: top.get(`${x},${y}`) || 0 });
    }
    const palette = [...C.PLAYER_PALETTE.keys()].sort(() => rnd() - 0.5);
    this.players = spots.map((s, i) => ({
      id: ID0 - i,
      slot: i,
      color: palette[i % palette.length],
      name: '',
      char: chars[i],
      x: s.x + 0.5,
      y: s.y + 0.5,
      z: s.z,
      yaw: Math.atan2(D / 2 - (s.y + 0.5), W / 2 - (s.x + 0.5)) + (rnd() - 0.5) * 1.2, // 대충 가운데 쪽을 봄
      pitch: 0,
      alive: true,
      damage: 0,
      emote: -1,
      emoteLeft: 0,
      nextEmote: C.MENU_EMOTE_EVERY_MS * (0.3 + rnd()),
      turnAt: 0,
    }));
    this.state = {
      type: 'state',
      menu: true, // 머리 위 이름·% 숨김 (render.js)
      phase: 'lobby',
      time: 0,
      players: this.players,
      pieces: [],
      items: [],
      projectiles: [],
      lava: { active: false, z: C.LAVA_START_Z },
      map: { choice: this.mapId, id: this.mapId },
      field: { w: W, d: D, h: H },
      grid,
      gridVersion: 1,
    };
  }

  // 한 프레임: 시간·이모트·고개 돌리기. 돌려주는 값 = renderer.render 에 넘길 state 와 카메라
  // spin: 카메라가 섬 둘레를 도는지 (타이틀 동안은 멈춤)
  step(dt, spin = true) {
    const ms = dt * 1000;
    this.time += ms;
    const rnd = this.rnd;
    for (const p of this.players) {
      p.nextEmote -= ms;
      if (p.emoteLeft > 0) {
        p.emoteLeft = Math.max(0, p.emoteLeft - ms);
        if (p.emoteLeft === 0) p.emote = -1;
      } else if (p.nextEmote <= 0) {
        p.emote = Math.floor(rnd() * C.EMOTE_NAMES.length);
        p.emoteLeft = C.EMOTE_MS;
        p.nextEmote = C.MENU_EMOTE_EVERY_MS * (0.6 + rnd() * 0.8);
      }
      // 가끔 다른 쪽을 봄 (천천히 돌아감)
      p.turnAt -= ms;
      if (p.turnAt <= 0) {
        p.wantYaw = p.yaw + (rnd() - 0.5) * 1.6;
        p.turnAt = 2500 + rnd() * 4000;
      }
      if (p.wantYaw !== undefined) p.yaw += (p.wantYaw - p.yaw) * Math.min(1, dt * 2);
    }
    this.state.time = this.time;
    this.state.recvAt = performance.now();
    if (spin) this.camYaw += dt * C.MENU_CAM_SPEED;
    return { state: this.state, cam: { yaw: this.camYaw, pitch: C.MENU_CAM_PITCH, follow: null, overviewDist: C.MENU_CAM_DIST } };
  }
}
