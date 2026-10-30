// 상승하는 위험 (용암 자리) 모습 — 테마 5종: water 물 · lava 용암 · swamp 독늪 · energy 에너지 · storm 번개 구름. 판정은 서버 (state.lava.z), 여기는 화면만.
// - 표면: 정점이 실제로 출렁이는 파도, 깊이(표면 - 아래 단단한 윗면)로 얕은 곳 밝게·투명, 하늘 반사(프레넬)·햇빛 반짝임, 종류별 질감
// - 만나는 곳: 블록·바닥이 표면을 뚫고 나온 곳 둘레에 거품/불꽃/증기 테 (격자로 만든 거리 표 hazard-field.js), 잠긴 블록은 위험 색으로 물들고 닿는 선 바로 위는 달아오름/젖음
// - 차오름: HAZARD_RISE_STEP 칸 오를 때마다 표면 번쩍 + 파도 커짐 + 닿는 곳 거품 오름 + 가까우면 화면 살짝 흔들림, 화면 가장자리 색 경고 (아이콘 없음).
//   소리는 renderer.onHazardRise = ({ kind: 'start'|'step', z, style }) => … 로 (B2)
// - 빠짐: 위험에 죽은 자리에서 종류별 튀김 + 몸이 잠기며 사라짐, 발 밑이 가까우면 표면이 들썩
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { noOutline } from '/toon.js';
import { hazardField, riseStep, vignetteStrength, farRings, HAZARD_MARGIN } from '/hazard-field.js';

const STYLE = { water: 0, lava: 1, swamp: 2, energy: 3, storm: 4 };
// 표면 그리는 법 (config HAZARD_LOOK, 2026-10-30 재혁 '액체 못생김' 시안): old 예전 · glow A 스스로 빛나는 흐르는 빛 띠 · toon B 만화풍 단색 층 + 뚜렷한 테·드문드문 물결 선.
// glow·toon 은 파도를 사인파 대신 겹친 잡음 (다른 크기·방향·흐름) 으로
const LOOKS = { old: 0, glow: 1, toon: 2 };

// 표면 셰이더 (STYLE 로 질감 갈래). far = 필드 밖 지평선까지 큰 판 (가운데 구멍은 버리고, 파도 없이 평평 — 안쪽 판은 가장자리로 갈수록 파도가 잦아들어 이음매 없음).
// shimmer = 먼 표면 반짝임·잔물결 법선 (그래픽 낮춤이면 끔)
function surfaceMaterial(style, far = false, shimmer = true, look = 'old') {
  return noOutline(new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: true,
    defines: { STYLE: STYLE[style] ?? 1, FAR: far ? 1 : 0, SHIMMER: shimmer ? 1 : 0, RINGS: C.HAZARD_FAR_RINGS, LOOK: LOOKS[look] ?? 0 },
    uniforms: {
      uTime: { value: 0 },
      uZ: { value: 0 },
      uWave: { value: new THREE.Vector2(0.05, 1) },
      uPulse: { value: 0 },
      uBulge: { value: new THREE.Vector4(0, 0, 0, 0) },
      uField: { value: null },
      uFieldRect: { value: new THREE.Vector4(0, 0, 1, 1) },
      uDeep: { value: new THREE.Color() },
      uMid: { value: new THREE.Color() },
      uShallow: { value: new THREE.Color() },
      uFoam: { value: new THREE.Color() },
      uSky: { value: new THREE.Color() },
      uSunDir: { value: new THREE.Vector3(0, 0, 1) },
      uAlpha: { value: new THREE.Vector2(1, 1) },
      uReflect: { value: 0.3 },
      uDepthFade: { value: 1 },
      uMargin: { value: 6 }, // 필드 둘레 안쪽 판 여백 (칸)
      uRings: { value: Array.from({ length: C.HAZARD_FAR_RINGS }, () => new THREE.Vector4(0, 0, 0, 0)) }, // 먼 섬·산이 표면에 걸친 원 (x, y, r, 켬)
      uFog: { value: new THREE.Color() },
      uFogRange: { value: new THREE.Vector3(40, 120, 145) }, // 안개 시작·끝, 판 끝 (투명해지는 곳)
      uHorizon: { value: new THREE.Color() },
    },
    vertexShader: `uniform float uTime; uniform vec2 uWave; uniform float uPulse; uniform vec4 uBulge; uniform vec4 uFieldRect; uniform float uMargin;
      varying vec3 vW; varying vec3 vN; varying vec2 vF;
      float vh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(vh(i), vh(i + vec2(1.0, 0.0)), f.x), mix(vh(i + vec2(0.0, 1.0)), vh(i + vec2(1.0, 1.0)), f.x), f.y); }
      // 잡음 파도: 크기·방향·흐름이 다른 세 겹 (반복이 안 보이게)
      float wave(vec2 p, float t) {
        vec2 a = p * 0.32 + vec2(t * 0.19, t * 0.11);
        vec2 b = mat2(0.8, -0.6, 0.6, 0.8) * p * 0.71 - vec2(t * 0.15, -t * 0.22);
        vec2 c = mat2(-0.5, 0.87, -0.87, -0.5) * p * 1.6 + vec2(t * 0.31, t * 0.07);
        return (vn(a) - 0.5) * 2.0 + (vn(b) - 0.5) * 1.1 + (vn(c) - 0.5) * 0.45;
      }
      void main() {
        vec4 w = modelMatrix * vec4(position, 1.0);
        vec2 p = w.xy;
        float t = uTime * uWave.y;
        vec2 d1 = vec2(0.94, 0.33); vec2 d2 = vec2(-0.41, 0.91); vec2 d3 = vec2(0.66, -0.75);
        // 파도는 필드 둘레 여백 바깥쪽으로 갈수록 잦아듦 → 바깥 큰 판(평평)과 이음매 없이 만남
        vec2 hf = uFieldRect.zw * 0.5;
        vec2 ctr = uFieldRect.xy + hf;
        float out_ = length(max(abs(p - ctr) - (hf - uMargin), 0.0));
        float wf = 1.0 - smoothstep(uMargin * 0.4, uMargin * 0.92, out_);
      #if FAR == 1
        wf = 0.0;
        // 지평선 쪽으로 둥글게 내려감 (hazard-field.js seaDrop 과 같은 식)
        float rr = max(0.0, length(p - ctr) - ${C.HAZARD_CURVE_FROM.toFixed(2)});
        w.z -= rr * rr * ${C.HAZARD_CURVE.toFixed(6)};
      #endif
        float a = uWave.x * (1.0 + uPulse * 1.6) * wf;
        float f1 = dot(d1, p) * 1.1 + t * 1.3;
        float f2 = dot(d2, p) * 1.6 - t * 1.1;
        float f3 = dot(d3, p) * 2.3 + t * 1.7;
      #if LOOK == 0
        float h = a * (sin(f1) + 0.6 * sin(f2) + 0.3 * sin(f3));
        vec2 g = a * (cos(f1) * 1.1 * d1 + 0.6 * cos(f2) * 1.6 * d2 + 0.3 * cos(f3) * 2.3 * d3);
      #else
        float aw = a * ${C.HAZARD_NOISE_WAVE.toFixed(3)};
        float h0 = wave(p, t);
        float h = aw * h0;
        vec2 g = aw * vec2(wave(p + vec2(0.2, 0.0), t) - h0, wave(p + vec2(0.0, 0.2), t) - h0) / 0.2;
      #endif
        // 발 밑 들썩 (가까이 선 사람)
        vec2 bp = p - uBulge.xy;
        float bump = uBulge.z * exp(-dot(bp, bp) * 1.6) * (0.65 + 0.35 * sin(uTime * 7.0));
        g += -3.2 * bp * bump;
        h += bump;
        w.z += h;
        vW = w.xyz;
        vN = normalize(vec3(-g, 1.0));
        vF = (p - uFieldRect.xy) / uFieldRect.zw;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: `uniform float uTime; uniform float uZ; uniform float uPulse; uniform sampler2D uField;
      uniform vec3 uDeep; uniform vec3 uMid; uniform vec3 uShallow; uniform vec3 uFoam; uniform vec3 uSky; uniform vec3 uSunDir;
      uniform vec2 uAlpha; uniform float uReflect; uniform float uDepthFade; uniform vec4 uFieldRect;
      uniform vec4 uRings[RINGS]; uniform vec3 uFog; uniform vec3 uFogRange; uniform vec3 uHorizon;
      varying vec3 vW; varying vec3 vN; varying vec2 vF;
      float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float noise(vec2 p) {
        vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
      }
      // 가장 가까운 점·두 번째 점 거리 (판·거품 무늬)
      vec2 worley(vec2 p, float t) {
        vec2 i = floor(p); vec2 f = fract(p);
        float d1 = 8.0; float d2 = 8.0;
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
          vec2 o = vec2(float(x), float(y));
          vec2 r = o + 0.5 + 0.4 * sin(t + 6.2831 * vec2(hash(i + o), hash(i + o + 17.0))) - f;
          float d = dot(r, r);
          if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d;
        }
        return sqrt(vec2(d1, d2));
      }
      void main() {
      #if FAR == 1
        // 가운데(안쪽 판 자리)는 버림
        vec2 hf0 = uFieldRect.zw * 0.5;
        if (all(lessThan(abs(vW.xy - (uFieldRect.xy + hf0)), hf0 - 0.02))) discard;
      #endif
        vec4 fld = texture2D(uField, clamp(vF, 0.0, 1.0));
        float dist = fld.r * 3.0;
        float ground = fld.g * 40.0 - 10.0;
        float depth = max(0.0, uZ - ground);
        float sh = 1.0 - smoothstep(0.0, uDepthFade, depth);
        vec3 V = normalize(cameraPosition - vW);
        vec3 N = normalize(vN);
      #if SHIMMER == 1
        // 잔물결 법선: 겹친 잡음 기울기 (멀수록 크게 보이는 결) → 수평선 쪽 햇빛 반짝임 길
        vec2 sq = vW.xy * 0.35 + uTime * vec2(0.05, 0.03);
        float e = 0.15;
        float n0 = noise(sq) + 0.5 * noise(sq * 2.7 - uTime * 0.07);
        float nx = noise(sq + vec2(e, 0.0)) + 0.5 * noise((sq + vec2(e, 0.0)) * 2.7 - uTime * 0.07);
        float ny = noise(sq + vec2(0.0, e)) + 0.5 * noise((sq + vec2(0.0, e)) * 2.7 - uTime * 0.07);
        N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * ${C.HAZARD_SHIMMER_NORMAL.toFixed(3)});
      #endif
        float fres = pow(1.0 - max(dot(N, V), 0.0), 3.0);
        vec2 q = vW.xy;
        float t = uTime;
        float n = noise(q * 0.7 + t * 0.12) + 0.5 * noise(q * 1.9 - t * 0.2);
        vec3 c = mix(uDeep, uMid, smoothstep(0.3, 1.3, n));
        float glow = 0.0; // 스스로 빛나는 정도 (반사에 덜 묻힘)
      #if STYLE == 0
        // 물: 반짝이는 잔물결 + 물마루
        float l = abs(fract(q.x * 0.33 + sin(q.y * 0.5 + t * 0.6) * 0.45 + t * 0.12) - 0.5);
        c = mix(c, uFoam, (1.0 - smoothstep(0.0, 0.025, l)) * 0.16);
        c += uFoam * step(0.975, noise(q * 7.0 + t * 1.5)) * 0.6;
      #elif STYLE == 1
        // 용암: 천천히 흐르는 식은 껍질 판 + 판 사이 뜨거운 금. 금은 맥동
        vec2 warp = vec2(noise(q * 0.45 + t * 0.04), noise(q * 0.45 + 9.1 - t * 0.03)) * 1.8; // 판 모양을 비틀어 벌집처럼 안 보이게
        vec2 fl = q * 0.62 + warp + vec2(t * 0.06, t * 0.035);
        vec2 wv = worley(fl, t * 0.25);
        float heat = smoothstep(0.25, 0.75, noise(q * 0.28 + t * 0.03)); // 뜨거운 곳 / 식은 곳
        float wide = 0.04 + 0.13 * heat * noise(q * 1.7 + 3.0);
        float crack = (1.0 - smoothstep(0.0, wide, wv.y - wv.x)) * mix(0.3, 1.0, heat);
        vec3 crust = mix(uDeep, uDeep * 2.6 + uMid * 0.08, noise(q * 2.3 + t * 0.05) * 0.7 + (1.0 - wv.x) * 0.3);
        c = mix(crust, mix(uMid, uShallow, 0.5 + 0.5 * sin(t * 2.0 + n * 4.0)), crack);
        c += uMid * heat * 0.12;
        c = mix(c, uShallow, sh * 0.5);
        glow = 0.85;
      #elif STYLE == 2
        // 독늪: 짙은 찌꺼기 얼룩 + 부풀었다 터지는 거품 방울
        c = mix(c, uDeep * 0.7, smoothstep(0.9, 1.4, noise(q * 0.5 - t * 0.05) * 2.0) * 0.6);
        vec2 cell = floor(q * 0.9);
        vec2 f = fract(q * 0.9) - 0.5;
        float rnd = hash(cell);
        vec2 ctr = (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.5;
        float life = fract(t * (0.25 + rnd * 0.35) + rnd);
        float bub = 1.0 - smoothstep(0.0, 0.04, abs(length(f - ctr) - life * 0.32));
        float cap = (1.0 - smoothstep(0.0, life * 0.3, length(f - ctr))) * 0.35;
        c = mix(c, uFoam, (bub + cap) * (1.0 - life) * step(0.35, rnd));
        glow = 0.35;
      #elif STYLE == 3
        // 에너지: 가운데에서 퍼지는 빛 띠 (맥동) + 반짝임
        float band = pow(0.5 + 0.5 * sin(length(q - vec2(uFieldRectC())) * 1.6 - t * 2.4 + n * 1.2), 6.0);
        c = mix(c, uFoam, band * 0.65);
        c = mix(c, vec3(1.0), step(0.985, hash(floor(q * 4.0) + floor(t * 6.0))) * 0.8);
        glow = 0.7;
      #else
        // 번개 구름: 소용돌이 구름 + 가끔 번쩍이는 갈래 번개
        vec2 rel = q - (uFieldRect.xy + uFieldRect.zw * 0.5);
        float ang = atan(rel.y, rel.x);
        float sw = sin(ang * 3.0 + length(rel) * 0.5 - t * 0.6) + noise(q * 0.8 + t * 0.3) * 2.0;
        c = mix(uDeep, uMid, smoothstep(0.0, 2.6, sw));
        float flash = pow(max(0.0, sin(t * 1.7) * sin(t * 2.9 + 1.3)), 10.0);
        float zig = abs(sin(q.x * 0.8 + sin(q.y * 2.3 + floor(t * 3.0)) * 1.4));
        c = mix(c, uFoam, (1.0 - smoothstep(0.0, 0.06, zig)) * (0.2 + flash * 0.8));
        c += uFoam * flash * 0.2;
        glow = 0.5;
      #endif
      #if LOOK > 0
        // 휘감긴 잡음 (반복 없이 흐름): 색 층·빛 띠·물결 선이 다 이것에서
        vec2 wq = q * 0.21 + vec2(noise(q * 0.13 + t * 0.04), noise(q * 0.13 - t * 0.035 + 5.2)) * 2.4;
        float fb = noise(wq + t * 0.05) * 0.62 + noise(wq * 2.3 - t * 0.07) * 0.28 + noise(wq * 5.3 + t * 0.11) * 0.1;
        float sparse = smoothstep(0.5, 0.72, noise(q * 0.27 + vec2(t * 0.03, -t * 0.02) + 11.0)); // 드문드문
      #if LOOK == 1
        // A 스스로 빛나는 표면: 맑은 두 색 + 흐르는 밝은 빛 띠 (등고선) + 반짝 (용암은 껍질·금 그대로 더 밝게)
      #if STYLE != 1
        c = mix(uDeep, uMid, smoothstep(0.22, 0.78, fb));
        float rib = smoothstep(0.8, 0.97, abs(fract(fb * 3.2 - t * 0.06) - 0.5) * 2.0) * (0.3 + 0.7 * sparse); // 흐르는 빛 띠 (등고선)
        c = mix(c, uShallow, rib * 0.85);
        c += uFoam * pow(rib, 3.0) * 0.35;
        c += uFoam * step(0.988, noise(q * 6.0 + t * 1.2)) * 0.5;
      #else
        c *= 1.15;
      #endif
        glow = max(glow, 0.8);
      #else
        // B 만화풍: 색 세 층 (뚜렷한 경계) + 드문드문 짧은 물결 선 (용암은 껍질·금을 층으로)
      #if STYLE != 1
        float lv = smoothstep(0.25, 0.75, fb);
        c = lv < 0.33 ? mix(uDeep, uMid, 0.45) : lv < 0.7 ? uMid : mix(uMid, uShallow, 0.55); // 가장 어두운 층도 구멍처럼 까맣지 않게
        float stroke = step(0.93, abs(fract(fb * 5.0 + t * 0.08) - 0.5) * 2.0); // 물결 선
        c = mix(c, uFoam, stroke * step(0.62, sparse) * 0.95);
      #else
        c = floor(c * 5.0 + 0.5) / 5.0;
      #endif
        glow = max(glow, 0.6);
      #endif
      #endif
        // 얕은 곳 밝게
      #if LOOK == 2
        c = mix(c, uShallow, step(0.5, sh) * 0.5);
      #else
        c = mix(c, uShallow, sh * 0.55 * (1.0 - glow * 0.5));
      #endif
        // 하늘 반사 + 햇빛 반짝임 (만화풍은 반사도 한 단)
      #if LOOK == 2
        c = mix(c, uSky, step(0.45, fres) * uReflect * 0.6);
      #else
        c = mix(c, uSky, fres * uReflect * (1.0 - glow * 0.6));
      #endif
        c += pow(max(dot(reflect(-V, N), uSunDir), 0.0), 90.0) * uReflect * 0.9;
        // 닿는 곳 테 (거품·불꽃·증기): 출렁이며 끊기는 띠
        float wob = 0.1 * sin(q.x * 3.1 + t * 2.3) + 0.1 * sin(q.y * 2.7 - t * 1.9);
        float foam = 1.0 - smoothstep(0.05, 0.3 + wob + uPulse * 0.3, dist);
        foam *= mix(0.45, 1.0, smoothstep(0.3, 0.7, noise(q * 5.0 + t * 0.9)));
        float halo = (1.0 - smoothstep(0.3, 1.1, dist)) * 0.25; // 테 바깥 옅은 번짐
      #if LOOK == 2
        foam = step(0.45, foam); // 만화풍: 뚜렷한 밝은 테
        halo = (1.0 - step(0.75, dist)) * 0.3;
      #elif LOOK == 1
        c += uShallow * halo * 0.8; // 빛나는 테 번짐
      #endif
        c = mix(c, uFoam, foam + halo * (1.0 - foam));
        c += uFoam * uPulse * 0.3;
        // 먼 섬·산이 잠기는 곳 테 (거품·불꽃·김)
        for (int i = 0; i < RINGS; i++) {
          vec4 rg = uRings[i];
          if (rg.w < 0.5) continue;
          float rd = abs(length(q - rg.xy) - rg.z);
          float ring = (1.0 - smoothstep(0.0, 0.6 + 0.25 * sin(t * 2.0 + float(i) * 1.7 + q.x), rd)) * mix(0.5, 1.0, noise(q * 3.0 + t));
          c = mix(c, uFoam, ring * 0.9);
          foam = max(foam, ring);
        }
        float a = mix(uAlpha.x, uAlpha.y, sh);
        a = mix(a, 1.0, smoothstep(-1.0, -4.0, ground)); // 바닥이 먼 곳(필드 밖 바다)은 불투명 — 아래 구름 바다가 비치지 않게
        a = max(a, foam);
        // 안개: 멀수록 안개색, 판 끝은 지평선 색으로 녹이며 투명 (하늘과 이음매 없이)
        float cd = length(vW - cameraPosition);
        c = mix(c, uFog, smoothstep(uFogRange.x, uFogRange.y, cd) * ${C.HAZARD_FOG_MIX.toFixed(3)});
        float edge = length(vW.xy - (uFieldRect.xy + uFieldRect.zw * 0.5));
        c = mix(c, uHorizon, smoothstep(uFogRange.z * 0.7, uFogRange.z, edge));
        a *= 1.0 - smoothstep(uFogRange.z * 0.9, uFogRange.z, edge);
        gl_FragColor = vec4(c, a);
        #include <colorspace_fragment>
      }`.replace('uFieldRectC()', 'uFieldRect.xy + uFieldRect.zw * 0.5'),
  }));
}

// 몸통: 표면 아래 상자 (윗면 없음 — 표면이 투명하면 안이 비쳐 보여야 해서). 옆·밑면만 짙은 색
function bodyMesh() {
  const mat = noOutline(new THREE.MeshBasicMaterial({ color: 0x000000 }));
  const hidden = new THREE.MeshBasicMaterial({ visible: false });
  const m = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), [mat, mat, mat, mat, hidden, mat]);
  m.visible = false;
  return m;
}

// 화면 가장자리 색 경고 (아이콘 없이). 화면 전체 사각형, 가운데는 투명
function overlay() {
  const scene = new THREE.Scene();
  const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const mat = new THREE.ShaderMaterial({
    transparent: true,
    depthTest: false,
    depthWrite: false,
    uniforms: { uColor: { value: new THREE.Color() }, uK: { value: 0 }, uTime: { value: 0 } },
    vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`,
    fragmentShader: `uniform vec3 uColor; uniform float uK; uniform float uTime; varying vec2 vUv;
      void main() {
        vec2 d = (vUv - 0.5) * vec2(1.25, 1.0);
        float e = smoothstep(0.42, 0.8, length(d));
        float beat = 0.8 + 0.2 * sin(uTime * (4.0 + uK * 6.0));
        float bottom = smoothstep(0.3, 0.0, vUv.y) * 0.35; // 아래쪽(발 쪽)을 조금 더
        gl_FragColor = vec4(uColor, clamp((e + bottom) * uK * beat, 0.0, 1.0));
        #include <colorspace_fragment>
      }`,
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
  quad.frustumCulled = false;
  scene.add(quad);
  return { scene, cam, mat };
}

export class Hazard {
  // r: Renderer (scene·effects·blockMeshes·floor·playerMeshes·dome 을 씀)
  constructor(r) {
    this.r = r;
    this.look = null;
    this.low = false;
    this.bottom = -C.HAZARD_DEEP;
    this.body = bodyMesh();
    r.scene.add(this.body);
    this.surface = null; // 테마(종류)가 바뀌면 재질을 새로
    this.style = null;
    this.light = new THREE.PointLight(0xff6a20, 0, C.LAVA_LIGHT_RANGE, 1.4); // 늘 씬에 두고 세기만 (빛 개수가 바뀌면 셰이더를 다시 만듦)
    r.scene.add(this.light);
    this.fieldKey = '';
    this.field = null;
    this.tex = null;
    this.step = null; // 차오름 단계 (riseStep)
    this.pulse = 0;
    this.wasActive = false;
    this.alive = new Map(); // 지난 프레임 살아 있었는지 (빠짐 감지)
    this.sinks = new Map(); // id → { t0, x, y, z, yaw }
    this.ambAcc = 0;
    this.t = 0; // 화면 시계 (초, 프레임 dt 를 쌓음 — 물결·잠김이 프레임 시간과 같이 감)
    this.contactAcc = 0;
    this.vig = overlay();
    this.vigK = 0;
    // 블록 물들임 (잠긴 부분 색·닿는 선 바로 위 달아오름) — 여러 재질이 같은 uniform 을 나눠 씀
    this.tintU = {
      uHz: { value: new THREE.Vector4(0, 0, 0, 0) }, // 표면 z, 잠긴 깊이당 섞는 비율, 닿는 선 띠 세기, 켜짐
      uHzTint: { value: new THREE.Color() },
      uHzBand: { value: new THREE.Color() },
      uHzMode: { value: 0 }, // 1 = 띠가 빛남 (용암·에너지), 0 = 띠가 어두워짐 (젖음)
    };
    this.setLook(null);
  }

  // 테마의 위험 모습 (world.js 가 맵 테마를 바꿀 때). 없으면 HAZARD_FALLBACK 테마의 것
  setLook(h) {
    this.look = h || C.WORLD_THEMES[C.HAZARD_FALLBACK].hazard;
    const L = this.look;
    const mode = this.mode || C.HAZARD_LOOK;
    if (this.style !== L.style || !this.surface || this.builtLow !== this.low || this.builtMode !== mode) {
      for (const m of [this.surface, this.far]) {
        if (!m) continue;
        this.r.scene.remove(m);
        m.geometry.dispose();
        m.material.dispose();
      }
      this.style = L.style;
      this.builtLow = this.low;
      this.builtMode = mode;
      this.surface = new THREE.Mesh(this.surfaceGeometry(), surfaceMaterial(L.style, false, !this.low, mode));
      this.surface.visible = false;
      this.surface.renderOrder = 1; // 투명: 블록 뒤에 그림
      // 지평선까지 바다: 필드 밖 큰 판 하나 (같은 uniform 을 나눠 씀 → 색·높이·시간이 늘 같음)
      const R = C.HAZARD_FAR_SIZE;
      const farMat = surfaceMaterial(L.style, true, !this.low, mode);
      farMat.uniforms = this.surface.material.uniforms;
      this.far = new THREE.Mesh(new THREE.PlaneGeometry(2 * R, 2 * R, C.HAZARD_FAR_SEG, C.HAZARD_FAR_SEG), farMat);
      this.far.visible = false;
      this.far.renderOrder = 1;
      this.far.frustumCulled = false;
      this.r.scene.add(this.surface, this.far);
      this.fieldKey = '';
    }
    const u = this.surface.material.uniforms;
    for (const k of ['Deep', 'Mid', 'Shallow', 'Foam']) u[`u${k}`].value.set(L[k.toLowerCase()]);
    u.uAlpha.value.set(...L.alpha);
    u.uReflect.value = L.reflect;
    u.uDepthFade.value = L.depthFade;
    this.body.material[0].color.set(L.deep);
    this.light.color.set(L.light[0]);
    this.tintU.uHzTint.value.set(L.tint);
    this.tintU.uHzBand.value.set(L.band[0]);
    this.tintU.uHzMode.value = L.band[2] ? 1 : 0;
    this.vig.mat.uniforms.uColor.value.set(L.vignette);
    this.fieldKey = '';
    this.layout();
  }

  // 표면 그리는 법 바꾸기 (old·glow·toon, 확인용 __tf.renderer.hazard.setMode)
  setMode(name) {
    this.mode = name;
    if (this.look) this.setLook(this.look);
  }

  surfaceGeometry() {
    const seg = C.HAZARD_SEG[this.low ? 1 : 0];
    return new THREE.PlaneGeometry(1, 1, seg, seg);
  }

  setLow(on) {
    if (this.low === !!on) return;
    this.low = !!on;
    if (this.look) this.setLook(this.look); // 반짝임·거품 갈래가 달라서 재질을 새로 (격자 수도)
  }

  // 판 크기가 바뀌면 (setField)
  layout() {
    const { W, D } = this.r;
    const s = [W + 2 * HAZARD_MARGIN, D + 2 * HAZARD_MARGIN];
    this.surface?.scale.set(s[0], s[1], 1);
    this.body.scale.set(s[0], s[1], 1);
    this.fieldKey = '';
  }

  // 블록·바닥 재질에 물들임을 심음 (한 번만. 테마가 블록 재질을 바꾸면 새 재질에 다시)
  tint(m) {
    if (!m || m.userData.hz || !m.isMeshToonMaterial) return;
    m.userData.hz = true;
    const prev = m.onBeforeCompile;
    const prevKey = m.customProgramCacheKey;
    const U = this.tintU;
    m.onBeforeCompile = (sh, rr) => {
      prev?.call(m, sh, rr);
      Object.assign(sh.uniforms, U);
      sh.vertexShader = `varying vec3 vHzW;\n${sh.vertexShader}`.replace(
        '#include <project_vertex>',
        `#include <project_vertex>
        vec4 hzw = vec4(transformed, 1.0);
        #ifdef USE_INSTANCING
        hzw = instanceMatrix * hzw;
        #endif
        vHzW = (modelMatrix * hzw).xyz;`,
      );
      sh.fragmentShader = `varying vec3 vHzW;\nuniform vec4 uHz;\nuniform vec3 uHzTint;\nuniform vec3 uHzBand;\nuniform float uHzMode;\n${sh.fragmentShader}`.replace(
        '#include <opaque_fragment>',
        `#include <opaque_fragment>
        if (uHz.w > 0.5) {
          float hzD = uHz.x - vHzW.z;
          if (hzD > 0.0) gl_FragColor.rgb = mix(gl_FragColor.rgb, uHzTint, clamp(0.35 + hzD * uHz.y, 0.0, 0.85));
          else {
            float hb = (1.0 - smoothstep(0.0, 0.5, -hzD)) * uHz.z;
            gl_FragColor.rgb = uHzMode > 0.5 ? gl_FragColor.rgb + uHzBand * hb : mix(gl_FragColor.rgb, gl_FragColor.rgb * uHzBand, hb);
          }
        }`,
      );
    };
    m.customProgramCacheKey = () => `${prevKey ? prevKey.call(m) : ''}-hz`;
    m.needsUpdate = true;
  }

  // 그리기 끝 (Renderer.draw 가 부름): 화면 가장자리 경고
  drawOverlay(renderer) {
    if (this.vigK < 0.01) return;
    const auto = renderer.autoClear;
    renderer.autoClear = false;
    renderer.render(this.vig.scene, this.vig.cam);
    renderer.autoClear = auto;
  }

  // 매 프레임 (render 의 플레이어 다음): state.lava 에 맞춰 표면·몸통·빛·입자·경고·빠짐
  update(state, dt, myId, grid) {
    const r = this.r;
    const L = this.look;
    const lava = state.lava;
    const on = !!(lava && lava.active);
    this.t += dt;
    const now = this.t;
    const zs = on ? lava.z : -99;
    this.tintU.uHz.value.set(zs, L.tintDepth, L.band[1] * (0.85 + 0.15 * Math.sin(now * 5)), on ? 1 : 0);
    for (const mesh of Object.values(r.blockMeshes)) for (const m of [].concat(mesh.material)) this.tint(m);
    for (const m of [].concat(r.floor.material)) this.tint(m);
    this.surface.visible = on;
    this.far.visible = on;
    this.body.visible = false; // 지평선까지 바다라 몸통 상자는 안 씀 (밑에서 볼 일 없음)
    // 하늘 지평선 아래도 액체 색으로 (먼 판 끝 너머가 구름 바다 색으로 남지 않게). 꺼지면 되돌림
    const du = r.dome.material.uniforms;
    if (on) {
      if (!this.belowSaved) this.belowSaved = du.below.value.clone();
      du.below.value.copy(this.belowSaved).lerp(new THREE.Color(L.deep).lerp(r.scene.fog.color, C.HAZARD_FOG_MIX), 0.9);
    } else if (this.belowSaved) {
      du.below.value.copy(this.belowSaved);
      this.belowSaved = null;
    }
    this.pulse = Math.max(0, this.pulse - dt * C.HAZARD_PULSE_DECAY);
    const me = state.players.find((p) => p.id === myId);
    if (!on) {
      this.light.intensity = 0;
      this.vigK = 0;
      this.wasActive = false;
      this.step = null;
      this.trackDeaths(state, zs, false);
      this.stepSinks();
      return;
    }
    const { W, D, H } = r;
    const cx = W / 2;
    const cy = D / 2;
    // 차오름: 처음 시작 / 단계마다
    const step = riseStep(zs);
    if (!this.wasActive) this.rise('start', zs, me);
    else if (this.step !== null && step > this.step) this.rise('step', zs, me);
    this.wasActive = true;
    this.step = step;
    // 닿는 곳 거리 표 (격자나 표면 칸이 바뀔 때만)
    const key = `${state.gridVersion}|${Math.floor(zs)}|${zs < 0}|${W}|${D}|${H}`;
    if (key !== this.fieldKey && grid) {
      this.fieldKey = key;
      this.field = hazardField(grid, W, D, H, zs);
      this.uploadField();
    }
    const h = Math.max(0.01, zs - this.bottom - 0.2);
    this.body.scale.z = h;
    this.body.position.set(cx, cy, this.bottom + h / 2);
    this.surface.position.set(cx, cy, zs);
    this.far.position.set(cx, cy, zs);
    const u = this.surface.material.uniforms;
    u.uMargin.value = HAZARD_MARGIN;
    u.uFog.value.copy(r.scene.fog.color);
    u.uFogRange.value.set(r.scene.fog.near, r.scene.fog.far, C.HAZARD_FAR_SIZE);
    u.uHorizon.value.copy(du.horizon.value);
    // 먼 섬·산이 표면에 걸친 곳 (거품·김 테, 그래픽 낮춤이면 없음)
    const rings = this.low ? [] : farRings(r.world.farObjects ? r.world.farObjects() : [], zs, C.HAZARD_FAR_RINGS, cx, cy);
    u.uRings.value.forEach((v, i) => (rings[i] ? v.set(rings[i].x, rings[i].y, rings[i].r, 1) : v.set(0, 0, 0, 0)));
    u.uTime.value = now;
    u.uZ.value = zs;
    u.uPulse.value = this.pulse;
    u.uWave.value.set(L.wave[0] * (this.low ? 0.5 : 1), L.wave[1]);
    u.uSky.value.copy(r.dome.material.uniforms.mid.value).lerp(r.dome.material.uniforms.horizon.value, 0.5);
    u.uSunDir.value.copy(r.dome.material.uniforms.sunDir.value);
    // 발 밑 들썩: 살아 있는 사람 중 표면에 가장 가까운 (나 먼저)
    let bulge = null;
    for (const p of state.players) {
      if (!p.alive || p.master) continue;
      const gap = p.z - zs;
      if (gap < C.HAZARD_BULGE_DIST && gap > -0.3 && (!bulge || p.id === myId || gap < bulge.gap)) bulge = { x: p.x, y: p.y, gap, mine: p.id === myId };
      if (bulge && bulge.mine) break;
    }
    if (bulge) u.uBulge.value.set(bulge.x, bulge.y, C.HAZARD_BULGE_AMP * (1 - Math.max(0, bulge.gap) / C.HAZARD_BULGE_DIST), 0);
    else u.uBulge.value.z = 0;
    // 빛: 일렁임 + 번쩍
    this.light.intensity = C.LAVA_LIGHT_INTENSITY * L.light[1] * (0.85 + 0.15 * Math.sin(now * 7) * Math.sin(now * 2.3)) * (1 + this.pulse);
    this.light.position.set(cx, cy, zs + 1.2);
    // 떠다니는 입자: 표면 아무 데서나 + 닿는 곳 (증기·거품·불꽃)
    const k = this.low ? C.WORLD_LOW_DETAIL : 1;
    this.ambAcc += dt * C.LAVA_EMBER_RATE * L.ambient * k;
    for (; this.ambAcc >= 1; this.ambAcc--) {
      const pos = { x: -1 + Math.random() * (W + 2), y: -1 + Math.random() * (D + 2), z: zs + 0.05 };
      r.effects.burst(pos, null, L.particles[Math.random() < 0.5 ? 0 : 1], 1, L.particleSpeed, 0.06, 0.8);
    }
    const contacts = this.field ? this.field.contacts : [];
    if (contacts.length && !this.low) {
      this.contactAcc += dt * C.HAZARD_CONTACT_RATE * (1 + this.pulse * 3);
      for (; this.contactAcc >= 1; this.contactAcc--) {
        const c = contacts[Math.floor(Math.random() * contacts.length)];
        const a = (Math.random() - 0.5) * 0.9;
        r.effects.burst({ x: c.x + c.ny * a + c.nx * 0.12, y: c.y + c.nx * a + c.ny * 0.12, z: zs + 0.04 }, null, L.contact, 1, L.particleSpeed * 0.5, 0.07, 0.9);
      }
    }
    // 화면 가장자리 경고: 내 발이 가까울수록
    const want = me && me.alive && !me.master ? vignetteStrength(me.z - zs, this.pulse) : 0;
    this.vigK += (want - this.vigK) * (1 - Math.exp(-6 * dt));
    this.vig.mat.uniforms.uK.value = this.vigK;
    this.vig.mat.uniforms.uTime.value = now;
    this.trackDeaths(state, zs, true);
    this.stepSinks();
  }

  // 차오름 한 번: 표면 번쩍·파도 커짐·닿는 곳 거품 오름·가까우면 흔들림 + 소리 훅
  rise(kind, z, me) {
    const r = this.r;
    this.pulse = 1;
    const gap = me && me.alive ? me.z - z : Infinity;
    const [amp, ms, near] = C.HAZARD_RISE_SHAKE;
    if (gap < near) r.effects.shake(amp * (kind === 'start' ? 2 : 1), ms);
    const contacts = this.field ? this.field.contacts : [];
    const n = Math.min(contacts.length, this.low ? 4 : 14);
    for (let i = 0; i < n; i++) {
      const c = contacts[Math.floor(Math.random() * contacts.length)];
      r.effects.burst({ x: c.x, y: c.y, z: z + 0.05 }, null, this.look.contact, 3, this.look.particleSpeed, 0.08, 0.7);
    }
    r.onHazardRise?.({ kind, z, style: this.look.style });
  }

  // 위험에 죽은 사람 (지난 프레임 살아 있었고 지금 죽었고 표면 근처): 튀김 + 잠기며 사라짐
  trackDeaths(state, zs, on) {
    for (const p of state.players) {
      const was = this.alive.get(p.id);
      this.alive.set(p.id, p.alive);
      if (!on || !was || p.alive || p.master) continue;
      if (p.z > zs + 0.6) continue; // 위험 말고 다른 이유
      this.splash(p.x, p.y, zs);
      const s = this.r.smooth.get(p.id) || p;
      this.sinks.set(p.id, { t0: this.t, x: s.x, y: s.y, z: zs - 0.35, zs });
    }
  }

  splash(x, y, z) {
    const L = this.look;
    const e = this.r.effects;
    const pos = { x, y, z: z + 0.1 };
    e.burst(pos, null, L.splash[0], this.low ? 12 : 34, L.particleSpeed * 1.8, 0.16, 1.0); // 위로 튀는 물보라·불똥·거품·파편
    e.burst(pos, null, L.splash[1], this.low ? 8 : 22, L.particleSpeed * 1.1, 0.13, 1.3);
    e.ring({ x, y, z: z + 0.06 }, L.foam, 3.2, 0.7, true); // 퍼지는 물결 고리 두 겹
    e.ring({ x, y, z: z + 0.06 }, L.splash[0], 2.0, 0.45, true);
    this.pulse = Math.max(this.pulse, 0.6);
  }

  // 잠기는 몸: render 가 죽은 몸을 숨긴 뒤 여기서 HAZARD_SINK_MS 동안 다시 보이게 하고 아래로 내림 (래그돌은 산 몸만이라 안 겹침)
  stepSinks() {
    for (const [id, s] of this.sinks) {
      const g = this.r.playerMeshes.get(id);
      const t = ((this.t - s.t0) * 1000) / C.HAZARD_SINK_MS;
      if (!g || t >= 1) {
        this.sinks.delete(id);
        continue;
      }
      // 처음엔 표면에 걸려 허우적 (출렁), 그다음 천천히 가라앉음
      const u = Math.max(0, (t - C.HAZARD_SINK_FLOAT) / (1 - C.HAZARD_SINK_FLOAT));
      const e = u * u * (3 - 2 * u);
      g.visible = true;
      g.position.set(s.x, s.y, s.z + Math.sin(t * 22) * 0.05 * (1 - u) - e * C.HAZARD_SINK_DEPTH);
      g.rotation.x = Math.sin(t * 11) * 0.22 * (1 - t);
      g.rotation.y = Math.cos(t * 8) * 0.15 * (1 - t);
      if (g.userData.arrow) g.userData.arrow.visible = false;
      if (g.userData.ring) g.userData.ring.visible = false;
      if (Math.random() < 0.3) this.r.effects.burst({ x: s.x, y: s.y, z: s.zs + 0.05 }, null, this.look.contact, 1, 2, 0.08, 0.6);
    }
  }

  uploadField() {
    const f = this.field;
    const data = new Uint8Array(f.nx * f.ny * 4);
    for (let i = 0; i < f.nx * f.ny; i++) {
      data[i * 4] = Math.round((f.dist[i] / 3) * 255);
      data[i * 4 + 1] = Math.round(Math.max(0, Math.min(1, (f.ground[i] + 10) / 40)) * 255);
      data[i * 4 + 3] = 255;
    }
    if (!this.tex || this.tex.image.width !== f.nx || this.tex.image.height !== f.ny) {
      this.tex?.dispose();
      this.tex = new THREE.DataTexture(data, f.nx, f.ny, THREE.RGBAFormat);
      this.tex.magFilter = this.tex.minFilter = THREE.LinearFilter;
    } else this.tex.image.data.set(data);
    this.tex.needsUpdate = true;
    const u = this.surface.material.uniforms;
    u.uField.value = this.tex;
    u.uFieldRect.value.set(f.x0, f.y0, f.w, f.d);
  }
}
