#!/bin/bash
# 웹 내보내기 템플릿 직접 빌드 (W5 2026-11-02): 고도 4.7.2-stable 소스 + emsdk 4.0.11 (고도 .github/workflows/web_builds.yml 의 EM_VERSION), 안 쓰는 모듈 끔.
# 결과 (이 컨테이너): wasm 39.5 → 32.9MB, brotli 6.90 → 5.39MB → 10Mbps 첫 화면 약 −1.3초 (tools/web_first.cjs). 4코어 (다른 일과 나눠 씀) 약 25분
# 남김: GL Compatibility 3D · gdscript · regex (튜토리얼·성능 표시) · websocket · ogg/vorbis · text_server_adv (한글) · freetype · svg (기본 테마 아이콘) · webp · godot_physics_2d/3d (래그돌)
# 실행: bash godot/client/tools/build-web-template.sh <작업 폴더>  → <작업 폴더>/godot/bin/godot.web.template_release.wasm32.nothreads.zip
# 쓰기: 웹 내보내기 전에 export_presets.cfg 웹 custom_template/release 에 그 zip 의 절대 경로 (커밋하지 말 것 — 없는 기계에선 내보내기가 실패),
#       또는 ~/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip 을 이 zip 으로 바꿔 넣음 (예전 것은 따로 둠)
set -e
W=${1:?작업 폴더}
mkdir -p "$W"
cd "$W"
[ -d godot ] || git clone -q --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git godot
[ -d emsdk ] || git clone -q --depth 1 https://github.com/emscripten-core/emsdk.git emsdk
(cd emsdk && ./emsdk install 4.0.11 && ./emsdk activate 4.0.11)
# shellcheck disable=SC1091
source emsdk/emsdk_env.sh
command -v scons > /dev/null || pip3 install scons
OFF="navigation_2d navigation_3d csg gridmap openxr webxr mobile_vr enet webrtc multiplayer theora mp3 jolt_physics noise gltf fbx jsonrpc upnp camera
interactive_music vhacd xatlas_unwrap raycast lightmapper_rd meshoptimizer basis_universal ktx dds tga bmp hdr tinyexr jpg zip objectdb_profiler
text_server_fb msdfgen mbedtls visual_shader"
ARGS=()
for m in $OFF; do ARGS+=("module_${m}_enabled=no"); done
cd godot
scons platform=web target=template_release threads=no production=yes optimize=size -j"$(nproc)" "${ARGS[@]}"
ls -la bin/godot.web.template_release.wasm32.nothreads.zip
