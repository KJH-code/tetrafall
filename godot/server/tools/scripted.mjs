// 각본 입력 판 (godot/PLAN.md 5절: 봇(S5) 전에 판 흐름·블록(S2)을 trace 로 맞출 때). 사람 n 명이 시드 고정 무작위 입력으로 움직이고
// 블록을 조종하고 유령 투하를 함 (캐릭터 끔 — 평타·스킬 없음). C# 쪽은 src/Tetrafall.Trace/Scenarios.cs Scripted 가 같은 입력을 냄
// trace.mjs 가 이름 앞 's' 로 고름: node godot/server/tools/trace.mjs s3 js.jsonl
import { mulberry32 } from '../../../tools/sim.js';

export const SCRIPTED = [
  { name: '각본 2명 생존 하늘', n: 2, mode: 'survival', team: false, sky: true, hp: false, map: 'flat', seed: 7001 },
  { name: '각본 4명 생존', n: 4, mode: 'survival', team: false, sky: false, hp: false, map: 'pyramid', seed: 7002 },
  { name: '각본 4명 생존 팀 하늘', n: 4, mode: 'survival', team: true, sky: true, hp: false, map: 'stairs', seed: 7003 },
  { name: '각본 3명 블록 마스터', n: 3, mode: 'master', team: false, sky: false, hp: false, map: 'bowl', seed: 7004 },
  { name: '각본 4명 킬 점수전 하늘', n: 4, mode: 'kills', team: false, sky: true, hp: false, map: 'spiral', seed: 7005 },
  { name: '각본 8명 생존 하늘', n: 8, mode: 'survival', team: false, sky: true, hp: false, map: 'fortress', seed: 7006 },
  { name: '각본 4명 킬 점수전 팀 체력전', n: 4, mode: 'kills', team: true, sky: false, hp: true, map: 'pillars', seed: 7007 },
  { name: '각본 6명 블록 마스터 하늘', n: 6, mode: 'master', team: false, sky: true, hp: false, map: 'stairs', seed: 7008 },
];

// 판 만들기 (trace.mjs 가 부름): 게임 난수는 mulberry32(seed), 입력 난수는 따로 (seed ^ 0x9e3779b9)
export function setupScripted(Game, sc, log) {
  const g = new Game(log, { characters: false, skyStairs: sc.sky, countdownMs: 1500, hpMode: sc.hp });
  g.rng = mulberry32(sc.seed);
  for (let i = 1; i <= sc.n; i++) g.addPlayer(i);
  if (sc.team) g.setTeamMode(true);
  if (sc.mode !== 'survival') g.setMode(sc.mode);
  g.setMap(sc.map);
  if (!g.startRound()) throw new Error('시작 못 함');
  return { g, rr: mulberry32((sc.seed ^ 0x9e3779b9) >>> 0) };
}

// 틱 하나 전 입력 (ticks = 지금까지 돈 틱 수)
export function driveScripted(g, rr, ticks) {
  for (const p of [...g.players.values()]) {
    if (ticks % 15 === 0) {
      const edge = Math.min(p.x, p.y, g.W - p.x, g.D - p.y) < 2; // 가장자리 근처면 가운데로
      const yaw = edge ? Math.atan2(g.D / 2 - p.y, g.W / 2 - p.x) : (rr() - 0.5) * 2 * Math.PI;
      g.handleInput(p.id, { fwd: rr() < 0.6 ? 1 : 0, strafe: Math.floor(rr() * 3) - 1, jump: rr() < 0.2, yaw, pitch: 0 });
    }
    if (rr() < 0.03) g.handleAction(p.id, { name: 'jump' });
    if (rr() < 0.004) g.handleAction(p.id, { name: 'emote', n: Math.floor(rr() * 5) });
    if (g.isControlling(p)) {
      const r = rr();
      if (r < 0.1) g.handleAction(p.id, { name: 'pieceMove', dx: Math.floor(rr() * 3) - 1, dy: Math.floor(rr() * 3) - 1 });
      else if (r < 0.13) g.handleAction(p.id, { name: 'rotate', dir: rr() < 0.5 ? 1 : -1 });
      else if (r < 0.16) g.handleAction(p.id, { name: 'drop' });
    }
    if (g.ghostCd(p) === 0 && rr() < 0.05) g.ghostDrop(p.id, rr() * g.W, rr() * g.D);
  }
}
