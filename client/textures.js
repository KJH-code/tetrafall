// 코드로 그린 텍스처 (파일 없음). 밝은 회색조로 그려서 재질·인스턴스 색이 그 위에 곱해진다.
// 블록 한 면 = 텍스처 한 장 (64px). 테두리를 어둡게 그려 툰 외곽선 대신 칸 경계가 보이게 한다.
import * as THREE from 'three';

const SIZE = 64;

function canvasTexture(draw, size = SIZE, repeat = null) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d');
  draw(ctx, size);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  if (repeat) {
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(repeat[0], repeat[1]);
  }
  return tex;
}

// 같은 그림이 매번 같게 (새로고침마다 무늬가 바뀌지 않게) 단순 난수
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const gray = (v) => `rgb(${v},${v},${v})`;

// 테트리스 블록: 밝은 위·왼쪽 빗면, 어두운 아래·오른쪽 빗면, 가운데 판, 바깥 테두리
function tetris(ctx, n) {
  const b = n * 0.16;
  ctx.fillStyle = gray(235);
  ctx.fillRect(0, 0, n, n);
  ctx.fillStyle = gray(255);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(n, 0);
  ctx.lineTo(n - b, b);
  ctx.lineTo(b, b);
  ctx.lineTo(b, n - b);
  ctx.lineTo(0, n);
  ctx.fill();
  ctx.fillStyle = gray(165);
  ctx.beginPath();
  ctx.moveTo(n, n);
  ctx.lineTo(0, n);
  ctx.lineTo(b, n - b);
  ctx.lineTo(n - b, n - b);
  ctx.lineTo(n - b, b);
  ctx.lineTo(n, 0);
  ctx.fill();
  ctx.fillStyle = gray(225);
  ctx.fillRect(b, b, n - 2 * b, n - 2 * b);
  ctx.fillStyle = 'rgba(255,255,255,.55)'; // 반짝이는 점
  ctx.fillRect(b * 1.4, b * 1.4, b * 0.9, b * 0.5);
  ctx.strokeStyle = gray(70);
  ctx.lineWidth = 3;
  ctx.strokeRect(1.5, 1.5, n - 3, n - 3);
}

// 테트리미노 (떨어지는·쌓인 블록, 2026-10-29): 둥근 장난감 블록 면 — 검은 테두리 없이 밝은 판 + 위·왼쪽 빛 + 아래·오른쪽 그늘 + 반짝 줄.
// 테마 지형(이어진 무광 돌)과 확실히 달라 보이게. 모서리는 모양(RoundedBox)이 둥글게
function piece(ctx, n) {
  const g = ctx.createLinearGradient(0, 0, n, n);
  g.addColorStop(0, gray(255));
  g.addColorStop(0.45, gray(238));
  g.addColorStop(1, gray(196));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, n, n);
  const b = n * 0.17;
  ctx.fillStyle = gray(232);
  ctx.beginPath();
  ctx.roundRect(b, b, n - 2 * b, n - 2 * b, n * 0.08);
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,.7)';
  ctx.lineWidth = n * 0.035;
  ctx.beginPath();
  ctx.moveTo(b, n - b);
  ctx.lineTo(b, b);
  ctx.lineTo(n - b, b);
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,255,255,.75)'; // 반짝 줄
  ctx.beginPath();
  ctx.roundRect(b * 1.5, b * 1.45, n * 0.3, n * 0.07, n * 0.035);
  ctx.fill();
}

// 돌 (시작 지형): 얼룩 + 금
function stone(ctx, n) {
  const r = rng(7);
  ctx.fillStyle = gray(215);
  ctx.fillRect(0, 0, n, n);
  for (let i = 0; i < 90; i++) {
    const v = 185 + Math.floor(r() * 60);
    ctx.fillStyle = gray(v);
    const s = 2 + r() * 7;
    ctx.fillRect(r() * n, r() * n, s, s);
  }
  ctx.strokeStyle = gray(150);
  ctx.lineWidth = 1.5;
  for (let i = 0; i < 3; i++) {
    ctx.beginPath();
    let x = r() * n;
    let y = r() * n;
    ctx.moveTo(x, y);
    for (let k = 0; k < 4; k++) {
      x += (r() - 0.5) * 18;
      y += (r() - 0.5) * 18;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.strokeStyle = gray(105);
  ctx.lineWidth = 3;
  ctx.strokeRect(1.5, 1.5, n - 3, n - 3);
}

// 나무 (쌓기 블록): 판자 세 줄 + 나뭇결
function wood(ctx, n) {
  const r = rng(11);
  ctx.fillStyle = gray(225);
  ctx.fillRect(0, 0, n, n);
  ctx.strokeStyle = gray(185);
  ctx.lineWidth = 1;
  for (let i = 0; i < 14; i++) {
    const y = r() * n;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.bezierCurveTo(n * 0.3, y + (r() - 0.5) * 6, n * 0.7, y + (r() - 0.5) * 6, n, y);
    ctx.stroke();
  }
  ctx.strokeStyle = gray(120);
  ctx.lineWidth = 2;
  for (const y of [n / 3, (2 * n) / 3]) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(n, y);
    ctx.stroke();
  }
  ctx.strokeStyle = gray(90);
  ctx.lineWidth = 3;
  ctx.strokeRect(1.5, 1.5, n - 3, n - 3);
}

// 모래 (착지한 설치 블록): 잔 점
function sand(ctx, n) {
  const r = rng(23);
  ctx.fillStyle = gray(230);
  ctx.fillRect(0, 0, n, n);
  for (let i = 0; i < 260; i++) {
    ctx.fillStyle = gray(190 + Math.floor(r() * 60));
    ctx.fillRect(r() * n, r() * n, 1.5, 1.5);
  }
  ctx.strokeStyle = gray(130);
  ctx.lineWidth = 3;
  ctx.strokeRect(1.5, 1.5, n - 3, n - 3);
}

// 꼰 밧줄: 비스듬한 가닥 줄무늬 (밝은 삼베 + 어두운 홈). 길이 방향으로 반복해서 씀
function rope(ctx, n) {
  ctx.fillStyle = gray(225);
  ctx.fillRect(0, 0, n, n);
  ctx.strokeStyle = gray(120);
  ctx.lineWidth = n / 9;
  for (let i = -2; i < 6; i++) {
    ctx.beginPath();
    ctx.moveTo(i * (n / 3), n);
    ctx.lineTo(i * (n / 3) + n, 0);
    ctx.stroke();
  }
  ctx.strokeStyle = gray(250);
  ctx.lineWidth = n / 30;
  for (let i = -2; i < 6; i++) {
    ctx.beginPath();
    ctx.moveTo(i * (n / 3) + n / 9, n);
    ctx.lineTo(i * (n / 3) + n / 9 + n, 0);
    ctx.stroke();
  }
}

// 바닥 타일 한 칸 (필드 크기만큼 반복)
function tile(ctx, n) {
  const r = rng(31);
  ctx.fillStyle = gray(225);
  ctx.fillRect(0, 0, n, n);
  for (let i = 0; i < 40; i++) {
    ctx.fillStyle = gray(205 + Math.floor(r() * 40));
    ctx.fillRect(r() * n, r() * n, 3, 3);
  }
  ctx.strokeStyle = gray(150);
  ctx.lineWidth = 4;
  ctx.strokeRect(2, 2, n - 4, n - 4);
}

// floorRepeat: [가로 칸 수, 세로 칸 수] — 바닥 한 판에 타일을 칸마다 하나씩
export function makeTextures(floorRepeat) {
  return {
    tetris: canvasTexture(tetris),
    piece: canvasTexture(piece),
    stone: canvasTexture(stone),
    wood: canvasTexture(wood),
    sand: canvasTexture(sand),
    rope: canvasTexture(rope, 32, [1, 1]),
    floor: canvasTexture(tile, SIZE, floorRepeat),
  };
}

// ---- 테마별 테트리미노 칸 면 (client/piece-look.js, config WORLD_THEMES.*.piece.style). 밝은 회색조 → 조각 색이 곱해짐
const PIECE_FACES = {
  toy: piece, // 기본 둥근 장난감 블록 (테마 없음)
  // 칠한 나무 장난감: 나뭇결 + 둥근 칠 판
  wood(ctx, n) {
    const r = rng(11);
    ctx.fillStyle = gray(236);
    ctx.fillRect(0, 0, n, n);
    for (let i = 0; i < 14; i++) {
      const y = r() * n;
      ctx.strokeStyle = `rgba(120,90,60,${0.08 + r() * 0.1})`;
      ctx.lineWidth = 1 + r() * 2;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.bezierCurveTo(n * 0.3, y + (r() - 0.5) * 10, n * 0.7, y + (r() - 0.5) * 10, n, y + (r() - 0.5) * 6);
      ctx.stroke();
    }
    const b = n * 0.14;
    ctx.strokeStyle = 'rgba(255,255,255,.45)';
    ctx.lineWidth = n * 0.04;
    ctx.beginPath();
    ctx.roundRect(b, b, n - 2 * b, n - 2 * b, n * 0.1);
    ctx.stroke();
  },
  // 사암·테라코타: 가로 층 + 점 + 깨진 테
  sandstone(ctx, n) {
    const r = rng(23);
    ctx.fillStyle = gray(232);
    ctx.fillRect(0, 0, n, n);
    for (let i = 0; i < 5; i++) {
      ctx.fillStyle = `rgba(${r() < 0.5 ? '255,255,255' : '90,60,40'},${0.06 + r() * 0.08})`;
      ctx.fillRect(0, (i / 5) * n + r() * 6, n, n / 5 - 4);
    }
    for (let i = 0; i < 160; i++) {
      ctx.fillStyle = `rgba(80,50,30,${r() * 0.25})`;
      ctx.fillRect(r() * n, r() * n, 1.5, 1.5);
    }
    ctx.strokeStyle = 'rgba(70,40,20,.45)';
    ctx.lineWidth = n * 0.035;
    ctx.strokeRect(n * 0.02, n * 0.02, n * 0.96, n * 0.96);
  },
  // 보석: 대각 깎은 면 + 밝은 심
  gem(ctx, n) {
    ctx.fillStyle = gray(210);
    ctx.fillRect(0, 0, n, n);
    const c = n / 2;
    const facets = [[0, 0, n, 0, 248], [n, 0, n, n, 200], [n, n, 0, n, 170], [0, n, 0, 0, 228]];
    for (const [x1, y1, x2, y2, v] of facets) {
      ctx.fillStyle = gray(v);
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.lineTo(c, c);
      ctx.fill();
    }
    ctx.fillStyle = 'rgba(255,255,255,.55)';
    ctx.beginPath();
    ctx.moveTo(c, n * 0.28);
    ctx.lineTo(n * 0.72, c);
    ctx.lineTo(c, n * 0.72);
    ctx.lineTo(n * 0.28, c);
    ctx.fill();
  },
  // 흑요석: 어두운 몸 + 밝은 금 (금이 조각 색으로 빛남 — piece-look crack)
  obsidian(ctx, n) {
    const r = rng(37);
    ctx.fillStyle = gray(62);
    ctx.fillRect(0, 0, n, n);
    ctx.fillStyle = 'rgba(255,255,255,.08)';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(n * 0.7, 0);
    ctx.lineTo(0, n * 0.7);
    ctx.fill();
    ctx.strokeStyle = gray(255);
    ctx.lineCap = 'round';
    for (let k = 0; k < 3; k++) {
      let x = r() * n;
      let y = r() < 0.5 ? 0 : n;
      ctx.lineWidth = n * (0.035 - k * 0.008);
      ctx.beginPath();
      ctx.moveTo(x, y);
      for (let i = 0; i < 5; i++) {
        x += (r() - 0.5) * n * 0.45;
        y += (y < n / 2 ? 1 : -1) * n * (0.12 + r() * 0.1);
        ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
  },
  // 대리석: 흰 바탕 + 회색 결 (금 테는 piece-look band)
  marble(ctx, n) {
    const r = rng(41);
    ctx.fillStyle = gray(244);
    ctx.fillRect(0, 0, n, n);
    for (let k = 0; k < 4; k++) {
      ctx.strokeStyle = `rgba(110,110,130,${0.12 + r() * 0.14})`;
      ctx.lineWidth = 1 + r() * 2.5;
      ctx.beginPath();
      let x = r() * n;
      let y = 0;
      ctx.moveTo(x, y);
      while (y < n) {
        x += (r() - 0.5) * n * 0.3;
        y += n * 0.12;
        ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
  },
  // 버섯 갓: 말랑한 그라데이션 + 흰 점
  jelly(ctx, n) {
    const r = rng(53);
    const g = ctx.createRadialGradient(n * 0.35, n * 0.3, n * 0.05, n * 0.5, n * 0.5, n * 0.75);
    g.addColorStop(0, gray(255));
    g.addColorStop(1, gray(200));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, n, n);
    for (let i = 0; i < 5; i++) {
      ctx.fillStyle = 'rgba(255,255,255,.85)';
      ctx.beginPath();
      ctx.ellipse(n * (0.15 + r() * 0.7), n * (0.15 + r() * 0.7), n * (0.05 + r() * 0.05), n * (0.04 + r() * 0.04), r() * 3, 0, Math.PI * 2);
      ctx.fill();
    }
  },
  // 깎은 돌: 끌 자국 + 테 홈
  stone(ctx, n) {
    const r = rng(67);
    ctx.fillStyle = gray(222);
    ctx.fillRect(0, 0, n, n);
    for (let i = 0; i < 40; i++) {
      ctx.strokeStyle = `rgba(${r() < 0.5 ? '255,255,255' : '40,40,50'},${0.08 + r() * 0.1})`;
      ctx.lineWidth = 1.5;
      const x = r() * n;
      const y = r() * n;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + n * 0.08, y + n * 0.03);
      ctx.stroke();
    }
    const b = n * 0.1;
    ctx.strokeStyle = 'rgba(30,30,40,.35)';
    ctx.lineWidth = n * 0.03;
    ctx.strokeRect(b, b, n - 2 * b, n - 2 * b);
    ctx.strokeStyle = 'rgba(255,255,255,.3)';
    ctx.strokeRect(b + n * 0.03, b + n * 0.03, n - 2 * b, n - 2 * b);
  },
};
export const PIECE_STYLES = Object.keys(PIECE_FACES);
const pieceTexCache = new Map();
export function pieceTexture(style) {
  if (!PIECE_FACES[style]) return null;
  if (!pieceTexCache.has(style)) pieceTexCache.set(style, canvasTexture(PIECE_FACES[style], 128));
  return pieceTexCache.get(style);
}
