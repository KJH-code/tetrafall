// 본문 글꼴 부분 집합 만들기 (W4, 2026-11-02 재혁 '부분 글꼴 넣기'): JS 에서 system-ui 로 그려지는 작은 글 (설명·표·안내·키 칸 이름 등) 을
// 고도도 비슷한 본문 고딕으로 — Noto Sans KR Regular (OFL, Google Fonts 공식 배포본) 에서 게임이 실제로 쓰는 글자만 남김.
//
// 글자 모으기: godot/client 의 .gd (tests·build·.godot 빼고 — config.gd 의 캐릭터 설명·튜토리얼 문구·맵 이름, ui 스크립트, keys.gd 키 이름) 안
// "…" 글 속 글자 (tests/test_core.gd 글꼴 검사와 같은 방식) + 영문·숫자·기호 (U+0020–007E) + 자주 쓰는 문장 부호·화살표 (EXTRA).
// 사람이 쳐 넣는 이름처럼 여기 없는 글자는 ui_style BODY 의 대체 글꼴 (Black Han Sans·DejaVu 기호) 로 그려짐.
//
// 쓰는 법 (레포 뿌리에서, pyftsubset 은 pip install fonttools brotli):
//   curl -sS -A curl "https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400"   → 나온 fonts.gstatic.com …ttf 주소를 받음
//   node godot/client/tools/subset-body-font.mjs <NotoSansKR-Regular.ttf>
// 결과: godot/client/assets/fonts/noto-sans-kr-body.woff2 (+ 글자 수·크기 출력). 게임 문구를 바꾸면 다시 돌림 (tests/test_ui_nodes.gd 가 빠진 글자를 잡음)
import { readdirSync, readFileSync, writeFileSync, statSync, mkdtempSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..'); // godot/client
const OUT = join(ROOT, 'assets/fonts/noto-sans-kr-body.woff2');
const SKIP = new Set(['tests', 'build', '.godot', 'addons']);
// 화면에 자주 나오는 문장 부호·기호 (Noto Sans KR 에 있는 것만 들어감, 없는 건 pyftsubset 이 건너뜀)
const EXTRA = '·—–…‘’“”←→↑↓↺▶▸◀◆◇●○■□▲▼★☆✓✔×÷°±%‰№™©®、。「」『』《》〈〉ㆍ';

export function collect(root = ROOT) {
  const chars = new Set();
  for (let c = 0x20; c <= 0x7e; c++) chars.add(String.fromCharCode(c));
  for (const ch of EXTRA) chars.add(ch);
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) {
        if (!SKIP.has(name) && !name.startsWith('.')) walk(p);
      } else if (name.endsWith('.gd')) {
        for (const m of readFileSync(p, 'utf8').matchAll(/"([^"\n]*)"/g)) for (const ch of m[1]) if (ch.codePointAt(0) > 32) chars.add(ch);
      }
    }
  };
  walk(root);
  return [...chars].sort((a, b) => a.codePointAt(0) - b.codePointAt(0)).join('');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const src = process.argv[2];
  if (!src) {
    console.error('쓰는 법: node godot/client/tools/subset-body-font.mjs <NotoSansKR-Regular.ttf>');
    process.exit(1);
  }
  const text = collect();
  const tmp = join(mkdtempSync(join(tmpdir(), 'tf-font-')), 'chars.txt');
  writeFileSync(tmp, text);
  execFileSync('pyftsubset', [src, `--text-file=${tmp}`, `--output-file=${OUT}`, '--flavor=woff2', '--no-hinting', '--desubroutinize', '--name-IDs=*', '--name-languages=*'], { stdio: 'inherit' });
  const hangul = [...text].filter((c) => c >= '가' && c <= '힣').length;
  console.log(`글자 ${[...text].length}개 (한글 음절 ${hangul}) → ${OUT} ${(statSync(OUT).size / 1024).toFixed(1)}KB`);
}
