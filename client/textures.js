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

// 건축가 블록: 금 간 벽돌 (주인 색이 곱해짐). 한가운데서 갈라진 굵은 금 + 모서리 쇠 리벳 → 쳐서 터뜨리는 블록이 보이게
function cracked(ctx, n) {
  const r = rng(47);
  ctx.fillStyle = gray(240);
  ctx.fillRect(0, 0, n, n);
  for (let i = 0; i < 90; i++) {
    ctx.fillStyle = gray(215 + Math.floor(r() * 35));
    ctx.fillRect(r() * n, r() * n, 2, 2);
  }
  // 갈라진 금: 가운데에서 네 방향으로 지그재그
  ctx.strokeStyle = gray(70);
  ctx.lineWidth = 2.5;
  ctx.lineJoin = 'bevel';
  for (const [ex, ey] of [[0.05, 0.2], [0.95, 0.1], [0.85, 0.95], [0.1, 0.85]]) {
    ctx.beginPath();
    ctx.moveTo(n / 2, n / 2);
    for (let k = 1; k <= 3; k++) {
      const t = k / 3;
      ctx.lineTo(n * (0.5 + (ex - 0.5) * t) + (r() - 0.5) * 7, n * (0.5 + (ey - 0.5) * t) + (r() - 0.5) * 7);
    }
    ctx.stroke();
  }
  ctx.fillStyle = gray(60);
  for (const [x, y] of [[0.14, 0.14], [0.86, 0.14], [0.14, 0.86], [0.86, 0.86]]) {
    ctx.beginPath();
    ctx.arc(n * x, n * y, 3, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.strokeStyle = gray(50);
  ctx.lineWidth = 4;
  ctx.strokeRect(2, 2, n - 4, n - 4);
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
    stone: canvasTexture(stone),
    wood: canvasTexture(wood),
    sand: canvasTexture(sand),
    cracked: canvasTexture(cracked),
    floor: canvasTexture(tile, SIZE, floorRepeat),
  };
}
