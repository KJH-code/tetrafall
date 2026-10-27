// 캐릭터 초상 (얼굴 카드): 3D 몸을 화면 밖 캔버스에 한 번 그려 dataURL 로 캐시한다.
// HUD 아래 플레이어 판·캐릭터 고르기 카드·승리 화면이 쓴다. 게임 화면(render.js)과 완전히 따로 돌아
// 메인 장면·카메라를 건드리지 않고, 같은 (캐릭터, 색, 크기) 는 한 번만 그린다.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { buildCharacter } from '/character.js';
import { figureAnim } from '/figure.js';

const LEFT_SIDE = ['cannon']; // 오른손·오른어깨 무기가 커서 왼쪽(+y)에서 봐야 얼굴이 보이는 캐릭터
const cache = new Map(); // `${char}|${color}|${size}|${full}` → dataURL
let gl = null; // 초상 전용 렌더러 (하나만, 다 쓰면 그대로 둠)
let models = null; // models.js 결과 (있으면 무기를 든 모습)

// 몸 색이 어두워도 카드에서 윤곽이 보이게: 앞·위·뒤에서 비추는 고정 조명
function makeScene() {
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xffffff, 1.05));
  const key = new THREE.DirectionalLight(0xffffff, 1.5);
  key.position.set(3, -2, 4);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x99bbff, 0.9);
  rim.position.set(-3, 2, 1);
  scene.add(rim);
  return scene;
}

function renderer(size) {
  if (!gl) {
    gl = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
    gl.setClearColor(0x000000, 0);
  }
  gl.setSize(size, size, false);
  return gl;
}

// 가만히 선 자세 한 프레임 (숨쉬기 위상 t 를 조금 줘서 팔이 굳어 보이지 않게)
function pose(ch) {
  if (!ch.figure) return;
  figureAnim(ch.figure, { air: false, walking: false, hs: 0, walk: 0, t: 0.8, flip: -1, emote: -1, emoteT: 0, punch: 0, dizzy: 0, whirl: -1, sniffAt: null }, 0.016);
}

// char: 캐릭터 id (없으면 기본 몸), color: 0xRRGGBB, size: 한 변 픽셀,
// full: true 면 온몸 (캐릭터 고르기 카드), false 면 얼굴·어깨 (HUD 판)
export function portrait(char, color, size = 96, full = false) {
  const key = `${char || ''}|${color}|${size}|${full ? 1 : 0}`;
  const hit = cache.get(key);
  if (hit) return hit;
  let url = '';
  try {
    const scene = makeScene();
    const ch = buildCharacter(color, models, char);
    pose(ch);
    scene.add(ch.group);
    // 몸의 실제 크기에 맞춰 화면을 채운다 (캐릭터마다 투구·뿔로 키가 달라 고정값이면 머리가 잘린다).
    // 전신은 rig 전체, 얼굴 카드는 목 관절 위(머리)를 기준으로 — 가슴 높이로 든 무기가 얼굴을 가리지 않게.
    ch.group.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(ch.rig);
    const zTop = Number.isFinite(box.max.z) ? box.max.z : C.PLAYER_HEIGHT;
    const zBot = Number.isFinite(box.min.z) ? box.min.z : 0;
    const h = Math.max(0.3, zTop - zBot);
    let top = zTop + h * 0.04;
    let bot = zBot - h * 0.03;
    const neck = ch.figure && ch.figure.neck;
    if (!full && neck) {
      const hb = new THREE.Box3().setFromObject(neck);
      const neckZ = neck.getWorldPosition(new THREE.Vector3()).z;
      const headH = Math.max(0.12, (Number.isFinite(hb.max.z) ? hb.max.z : neckZ + 0.3) - neckZ);
      top = neckZ + headH * 1.3;
      bot = neckZ - headH * 1.0;
    } else if (!full) {
      bot = zTop - h * 0.4;
    }
    const fov = 26;
    const half = ((top - bot) / 2) * 1.08;
    const dist = half / Math.tan((fov / 2) * (Math.PI / 180));
    const ang = ((full ? 38 : 46) * Math.PI) / 180; // 앞(+x)에서 돌린 각 — 얼굴 카드는 조금 더 옆에서
    const side = LEFT_SIDE.includes(char) ? 1 : -1; // 대포수는 오른쪽 어깨의 포신이 얼굴을 가려 반대쪽에서
    const at = new THREE.Vector3(0, 0, (top + bot) / 2);
    const cam = new THREE.PerspectiveCamera(fov, 1, 0.05, 60);
    cam.up.set(0, 0, 1); // 게임과 같은 z-up
    cam.position.set(Math.cos(ang) * dist, side * Math.sin(ang) * dist, at.z + (full ? 0 : (top - bot) * 0.1));
    cam.lookAt(at);
    const g = renderer(size);
    g.render(scene, cam);
    url = g.domElement.toDataURL('image/png');
    ch.group.removeFromParent();
  } catch (e) {
    url = ''; // 초상을 못 그려도 화면은 글자·색으로 돌아간다
  }
  cache.set(key, url);
  return url;
}

// models.js 를 다 불러온 뒤 render.js/main.js 가 넘겨주면 무기를 든 초상으로 다시 그린다
export function setPortraitModels(m) {
  if (models === m) return;
  models = m;
  cache.clear();
}
