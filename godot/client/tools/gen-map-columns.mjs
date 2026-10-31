// 대기실 지형 미리보기 자료 (G1 world/lobby_preview.gd): 맵마다 판 크기마다 shared/maps.js mapColumns 결과 → world/map_columns.json
// 실행 (레포 뿌리): node godot/client/tools/gen-map-columns.mjs. 맵 배치 (shared/maps.js) 를 바꾸면 다시 뽑음 (tests/test_world.gd 가 fixtures 와 맞는지 봄)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mapColumns, MAP_IDS } from '../../../shared/maps.js';
import { CONFIG as C } from '../../../shared/config.js';

const sizes = [...new Set(Object.values(C.FIELD_SIZES))].sort((a, b) => a - b);
const out = {};
for (const id of MAP_IDS) {
  out[id] = {};
  for (const n of sizes) out[id][n] = mapColumns(id, n, n);
}
const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '../world/map_columns.json');
fs.writeFileSync(file, JSON.stringify(out));
console.log(`map_columns: 맵 ${MAP_IDS.length} × 판 ${sizes.join('·')}`);
