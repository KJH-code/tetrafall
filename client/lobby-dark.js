// 대기실 (방 안·판 전) 배경: 그 방 맵 테마의 어두운 '엔딩 아트' 장면 (타이틀·메뉴와 같은 느낌, 2026-10-30 재혁).
// 방 섬·사람·블록은 게임 장면 그대로 두고 둘레만 바꿈: 하늘 구·먼 섬 숨김 → 테마 배경색·안개, 해·하늘빛을 테마 빛으로 낮춤,
// 섬 둘레에 title-world.js 무대 (ring: 소품을 사방으로, 섬 자리는 비움) + 섬 아래 거울 호수. 보통 그래픽이면 블룸 (외곽선 그대로 위에).
// 맵을 바꾸면 그 테마로 다시 만듦 (맵 미리보기). 판이 시작되면 render.js 가 restore → world.apply 로 밝은 판
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { Pass } from 'three/addons/postprocessing/Pass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { CONFIG as C } from '/shared/config.js';
import { TitleStage } from '/title-world.js';

// 게임 장면을 (외곽선 켜져 있으면 OutlineEffect 로) 렌더 타깃에 그리는 패스 — 블룸 앞 단계
class ScenePass extends Pass {
  constructor(r) {
    super();
    this.r = r;
    this.camera = r.camera;
    this.needsSwap = false; // RenderPass 처럼 readBuffer 에 그리고 다음 패스가 그걸 읽음
  }

  render(renderer, writeBuffer, readBuffer) {
    renderer.setRenderTarget(this.renderToScreen ? null : readBuffer);
    renderer.clear();
    if (this.r.outlineOn) this.r.outline.render(this.r.scene, this.camera);
    else renderer.render(this.r.scene, this.camera);
  }
}

export class LobbyDark {
  // r: Renderer, theme: TITLE_THEMES 키 (= 맵 테마 id), flash: 맵을 바꿔 들어옴 → 테마 빛으로 번쩍했다 가라앉음 (LOBBY_DARK.flashMs)
  constructor(r, theme, flash = false) {
    this.r = r;
    this.theme = theme;
    this.T = C.TITLE_THEMES[theme];
    this.low = r.lowGfx;
    this.W = r.W;
    this.D = r.D;
    const L = C.LOBBY_DARK;
    const R = Math.max(r.W, r.D) * L.clear + 3;
    this.stage = new TitleStage(theme, { low: this.low, logoW: 0, logoH: 0, camDist: R, ring: true, clear: R, floorZ: -L.drop });
    this.stage.scene.position.set(r.W / 2, r.D / 2, 0); // 무대 가운데 = 섬 가운데
    // 무대 빛: 로고용 앞 빛은 섬 위로
    this.stage.lights[1]?.[0].position.set(-R * 0.4, -R * 0.6, 14);
    this.stage.backLight.position.set(0, R * 0.5, 6);
    // 빛 수를 테마마다 같게 (LOBBY_DARK.lights): 모자라면 세기 0 빛으로 채움 → 대기실 첫 진입·맵 바꿈에 게임 장면 재질 셰이더를 다시 안 만듦 (메뉴에서 미리 데운 것 그대로)
    const count = (type) => this.stage.lights.filter(([l]) => l.type === type).length;
    for (const [type, want] of [['PointLight', L.lights.point], ['DirectionalLight', L.lights.dir]]) {
      for (let k = count(type); k < want; k++) this.stage.light(type === 'PointLight' ? new THREE.PointLight(0, 0) : new THREE.DirectionalLight(0, 0), 0);
    }
    r.scene.add(this.stage.scene);
    if (!this.low) {
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.composer = new EffectComposer(r.renderer);
      this.composer.addPass(new ScenePass(r));
      const [str, rad, thr] = C.TITLE_BLOOM;
      this.bloom = new UnrealBloomPass(new THREE.Vector2(w, h), str, rad, thr);
      this.composer.addPass(this.bloom);
      this.composer.addPass(new OutputPass());
      this.sizeKey = '';
    }
    // 맵 바꿈 번쩍: 화면 전체 판 (테마 빛 색, 더하기)
    this.flashAt = flash ? performance.now() : -Infinity;
    this.flashScene = new THREE.Scene();
    this.flashCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.flashMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(this.T.glow).lerp(new THREE.Color(0xffffff), 0.5), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthTest: false, depthWrite: false });
    this.flashScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.flashMat));
    this.apply();
  }

  // 맵 바꿈 번쩍 (그린 뒤 위에): 처음 세게 → LOBBY_DARK.flashMs 동안 가라앉음
  drawFlash(renderer) {
    const k = 1 - (performance.now() - this.flashAt) / C.LOBBY_DARK.flashMs;
    if (!(k > 0)) return;
    this.flashMat.opacity = C.LOBBY_DARK.flash * k * k;
    const ac = renderer.autoClear;
    renderer.autoClear = false;
    renderer.render(this.flashScene, this.flashCam);
    renderer.autoClear = ac;
  }

  // 게임 장면 둘레를 어둡게 (매 프레임: 맵 테마가 다시 칠해도 덮어씀)
  apply() {
    const { r, T } = this;
    const L = C.LOBBY_DARK;
    r.scene.background = r.scene.background || new THREE.Color();
    r.scene.background.set(T.bg);
    r.scene.fog.color.set(T.fog[0]);
    r.scene.fog.near = Math.max(this.W, this.D) + L.fog[0];
    r.scene.fog.far = Math.max(this.W, this.D) + T.fog[2] + L.fog[1];
    r.dome.visible = false;
    r.world.group.visible = false;
    r.hemi.color.set(T.amb[0]);
    r.hemi.groundColor.set(T.bg);
    r.hemi.intensity = T.amb[1] * L.hemi;
    r.sun.color.set(T.key[0]);
    r.sun.intensity = T.key[1] * L.sun;
  }

  // 매 프레임
  update() {
    this.drawn = true; // 이번 프레임에 그려짐 (확인용)
    this.frames = (this.frames || 0) + 1;
    this.apply();
    this.stage.update(performance.now() / 1000, 1, window.innerHeight * 0.5 * this.r.renderer.getPixelRatio());
  }

  // 같은 테마·판 크기·그래픽 설정이면 그대로 씀
  fits(theme) {
    return theme === this.theme && this.W === this.r.W && this.D === this.r.D && this.low === this.r.lowGfx;
  }

  // 그리기 (블룸이면 composer, 아니면 null → render.js 가 예전대로)
  draw(camera) {
    if (!this.composer) return false;
    const R = this.r.renderer;
    const sz = R.getSize(new THREE.Vector2());
    const key = `${sz.x}x${sz.y}x${R.getPixelRatio()}`;
    if (key !== this.sizeKey) {
      this.sizeKey = key;
      this.composer.setPixelRatio(R.getPixelRatio());
      this.composer.setSize(sz.x, sz.y);
    }
    this.composer.passes[0].camera = camera;
    this.composer.render();
    return true;
  }

  // 장면에서만 떼고 재질·셰이더는 살려 둠 (메뉴 미리 데우기: 진짜 대기실이 같은 셰이더를 다시 쓰게, 그 뒤 dispose)
  detach() {
    const { r } = this;
    r.scene.remove(this.stage.scene);
    r.dome.visible = true;
    r.world.group.visible = true;
    r.world.dirty = true; // 하늘·안개·빛은 다음에 밝은 판을 그릴 때 다시 칠함 (지금 world.apply 하면 재질을 새로 만들어 데운 셰이더가 버려짐)
  }

  // 치움. restore: 밝은 판으로 되돌림 (하늘 구·먼 섬·맵 테마 다시 칠하기) — 다른 테마 대기실로 바로 바꿀 땐 false
  dispose(restore = true) {
    const { r } = this;
    if (this.stage.scene.parent) r.scene.remove(this.stage.scene);
    this.stage.dispose();
    if (this.composer) {
      this.bloom.dispose();
      this.composer.dispose();
    }
    this.flashMat.dispose();
    this.flashScene.children[0].geometry.dispose();
    if (!restore) return;
    r.dome.visible = true;
    r.world.group.visible = true;
    r.world.apply(r.world.id); // 하늘·안개·빛 원래대로
  }
}
