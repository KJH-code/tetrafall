// 상승하는 위험 표면 (JS client/hazard.js surfaceMaterial 그대로 — 시안 A: 겹친 잡음 파도·맑은 두 색 + 흐르는 빛 띠·닿는 곳 테·먼 섬 잠김 테·지평선 바다). G3 가 가짐.
// 계산은 게임 좌표 (z 위): g() 고도 → 게임, gd() 게임 → 고도. 색 uniform 은 선형 (three 와 같음), 마지막에 sRGB 로 내보냄 (unshaded 라 고도가 되돌림)
// STYLE 0 물 · 1 용암 · 2 독늪 · 3 에너지 · 4 번개 구름, FAR 1 = 필드 밖 큰 판 (가운데 버림·지평선 쪽 내려감), SHIMMER 0 = 그래픽 낮춤.
// 셋은 #define (JS 처럼 컴파일 때 갈래가 정해짐 — uniform 갈래면 안 쓰는 질감 코드까지 다 돌아 그리기가 몇 배, 2026-10-31 잼) → g3.gd hazard_shader 가 갈래마다 셰이더를 만듦
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled, world_vertex_coords;

#ifndef STYLE
#define STYLE 1
#endif
#ifndef FAR
#define FAR 0
#endif
#ifndef SHIMMER
#define SHIMMER 1
#endif
uniform float HZ_CURVE_FROM; uniform float HZ_CURVE; uniform float HZ_NOISE_WAVE; uniform float HZ_SHIMMER_N; uniform float HZ_FOG_MIX;
uniform float uTime; uniform float uZ; uniform vec2 uWave = vec2(0.05, 1.0); uniform float uPulse; uniform vec4 uBulge;
uniform sampler2D uField : filter_linear, repeat_disable;
uniform vec4 uFieldRect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 uDeep; uniform vec3 uMid; uniform vec3 uShallow; uniform vec3 uFoam; uniform vec3 uSky; uniform vec3 uSunDir = vec3(0.0, 0.0, 1.0);
uniform vec2 uAlpha = vec2(1.0); uniform float uReflect = 0.3; uniform float uDepthFade = 1.0; uniform float uMargin = 6.0;
uniform vec4 uRings[16];
uniform vec3 uFog; uniform vec3 uFogRange = vec3(40.0, 120.0, 145.0); uniform vec3 uHorizon;

varying vec3 vW; varying vec3 vN; varying vec2 vF;

vec3 g(vec3 v) { return vec3(v.x, -v.z, v.y); }
vec3 gd(vec3 v) { return vec3(v.x, v.z, -v.y); }
vec3 srgb(vec3 c) { c = max(c, vec3(0.0)); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

float vh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(vh(i), vh(i + vec2(1.0, 0.0)), f.x), mix(vh(i + vec2(0.0, 1.0)), vh(i + vec2(1.0, 1.0)), f.x), f.y); }
      // 잡음 파도: 크기·방향·흐름이 다른 세 겹 (반복이 안 보이게)
      float wave(vec2 p, float t) {
        vec2 a = p * 0.32 + vec2(t * 0.19, t * 0.11);
        vec2 b = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p * 0.71 - vec2(t * 0.15, -t * 0.22);
        vec2 c = mat2(vec2(-0.5, 0.87), vec2(-0.87, -0.5)) * p * 1.6 + vec2(t * 0.31, t * 0.07);
        return (vn(a) - 0.5) * 2.0 + (vn(b) - 0.5) * 1.1 + (vn(c) - 0.5) * 0.45;
      }
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
      
void vertex() {
        vec3 ww = g(VERTEX); // 월드 (world_vertex_coords) → 게임
        vec2 p = ww.xy;
        float t = uTime * uWave.y;
        // 파도는 필드 둘레 여백 바깥쪽으로 갈수록 잦아듦 → 바깥 큰 판(평평)과 이음매 없이 만남
        vec2 hf = uFieldRect.zw * 0.5;
        vec2 ctr = uFieldRect.xy + hf;
        float out_ = length(max(abs(p - ctr) - (hf - uMargin), 0.0));
        float wf = 1.0 - smoothstep(uMargin * 0.4, uMargin * 0.92, out_);
      #if FAR == 1
        wf = 0.0;
        // 지평선 쪽으로 둥글게 내려감 (hazard-field.js seaDrop 과 같은 식)
        float rr = max(0.0, length(p - ctr) - HZ_CURVE_FROM);
        ww.z -= rr * rr * HZ_CURVE;
      #endif
        float a = uWave.x * (1.0 + uPulse * 1.6) * wf;
        float aw = a * HZ_NOISE_WAVE;
        float h0 = wave(p, t);
        float h = aw * h0;
        vec2 gr = aw * vec2(wave(p + vec2(0.2, 0.0), t) - h0, wave(p + vec2(0.0, 0.2), t) - h0) / 0.2;
        // 발 밑 들썩 (가까이 선 사람)
        vec2 bp = p - uBulge.xy;
        float bump = uBulge.z * exp(-dot(bp, bp) * 1.6) * (0.65 + 0.35 * sin(uTime * 7.0));
        gr += -3.2 * bp * bump;
        h += bump;
        ww.z += h;
        vW = ww;
        vN = normalize(vec3(-gr, 1.0));
        vF = (p - uFieldRect.xy) / uFieldRect.zw;
        	VERTEX = gd(ww);
}

void fragment() {
	vec3 cam_g = g(CAMERA_POSITION_WORLD);

      #if FAR == 1
        // 가운데(안쪽 판 자리)는 버림
        vec2 hf0 = uFieldRect.zw * 0.5;
        if (all(lessThan(abs(vW.xy - (uFieldRect.xy + hf0)), hf0 - 0.02))) discard;
      #endif
        vec4 fld = texture(uField, clamp(vF, 0.0, 1.0));
        float dist = fld.r * 3.0;
        float ground = fld.g * 40.0 - 10.0;
        float depth = max(0.0, uZ - ground);
        float sh = 1.0 - smoothstep(0.0, uDepthFade, depth);
        vec3 V = normalize(cam_g - vW);
        vec3 N = normalize(vN);
      #if SHIMMER == 1
        // 잔물결 법선: 겹친 잡음 기울기 (멀수록 크게 보이는 결) → 수평선 쪽 햇빛 반짝임 길
        vec2 sq = vW.xy * 0.35 + uTime * vec2(0.05, 0.03);
        float e = 0.15;
        float n0 = noise(sq) + 0.5 * noise(sq * 2.7 - uTime * 0.07);
        float nx = noise(sq + vec2(e, 0.0)) + 0.5 * noise((sq + vec2(e, 0.0)) * 2.7 - uTime * 0.07);
        float ny = noise(sq + vec2(0.0, e)) + 0.5 * noise((sq + vec2(0.0, e)) * 2.7 - uTime * 0.07);
        N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * HZ_SHIMMER_N);
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
        float band = pow(0.5 + 0.5 * sin(length(q - vec2(uFieldRect.xy + uFieldRect.zw * 0.5)) * 1.6 - t * 2.4 + n * 1.2), 6.0);
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
        // 휘감긴 잡음 (반복 없이 흐름): 색 층·빛 띠·물결 선이 다 이것에서
        vec2 wq = q * 0.21 + vec2(noise(q * 0.13 + t * 0.04), noise(q * 0.13 - t * 0.035 + 5.2)) * 2.4;
        float fb = noise(wq + t * 0.05) * 0.62 + noise(wq * 2.3 - t * 0.07) * 0.28 + noise(wq * 5.3 + t * 0.11) * 0.1;
        float sparse = smoothstep(0.5, 0.72, noise(q * 0.27 + vec2(t * 0.03, -t * 0.02) + 11.0)); // 드문드문
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
        // 얕은 곳 밝게
        c = mix(c, uShallow, sh * 0.55 * (1.0 - glow * 0.5));
        // 하늘 반사 + 햇빛 반짝임 (만화풍은 반사도 한 단)
        c = mix(c, uSky, fres * uReflect * (1.0 - glow * 0.6));
        c += pow(max(dot(reflect(-V, N), uSunDir), 0.0), 90.0) * uReflect * 0.9;
        // 닿는 곳 테 (거품·불꽃·증기): 출렁이며 끊기는 띠
        float wob = 0.1 * sin(q.x * 3.1 + t * 2.3) + 0.1 * sin(q.y * 2.7 - t * 1.9);
        float foam = 1.0 - smoothstep(0.05, 0.3 + wob + uPulse * 0.3, dist);
        foam *= mix(0.45, 1.0, smoothstep(0.3, 0.7, noise(q * 5.0 + t * 0.9)));
        float halo = (1.0 - smoothstep(0.3, 1.1, dist)) * 0.25; // 테 바깥 옅은 번짐
        c += uShallow * halo * 0.8; // 빛나는 테 번짐
        c = mix(c, uFoam, foam + halo * (1.0 - foam));
        c += uFoam * uPulse * 0.3;
        // 먼 섬·산이 잠기는 곳 테 (거품·불꽃·김)
        for (int i = 0; i < 16; i++) {
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
        float cd = length(vW - cam_g);
        c = mix(c, uFog, smoothstep(uFogRange.x, uFogRange.y, cd) * HZ_FOG_MIX);
        float edge = length(vW.xy - (uFieldRect.xy + uFieldRect.zw * 0.5));
        c = mix(c, uHorizon, smoothstep(uFogRange.z * 0.7, uFogRange.z, edge));
        a *= 1.0 - smoothstep(uFogRange.z * 0.9, uFogRange.z, edge);
        	ALBEDO = srgb(c);
	ALPHA = clamp(a, 0.0, 1.0);
}
