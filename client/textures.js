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
