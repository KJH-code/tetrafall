// 튜토리얼 화면 (2026-10-29 재혁): 처음 켜면 묻기(#tutorial .ask) → 캐릭터 고르기(.pick) → 튜토리얼 방 (판 중 진행 띠 #tut-band) → 끝(.done: 봇 3명과 한 판 / 메뉴로).
// 단계 판정·지형은 서버 (server/tutorial.js), 띠 문구는 shared/tutorial.js stepText 로 지금 키 설정 이름을 넣어 만듦. 다 했거나 건너뛰면 tf-tutorial = done
import { CONFIG as C } from '/shared/config.js';
import { stepText, tutorialStep, progressLabel } from '/shared/tutorial.js';
import { portrait } from '/portrait.js';

const $ = (id) => document.getElementById(id);

// tf-tutorial: 없음 = 아직 안 물어봄, 'skipped' = 묻기에서 건너뜀 (링크로 들어간 대기실에 핵심 키 한 줄은 보임), 'done' = 튜토리얼을 함
export function tutorialState() {
  try {
    return localStorage.getItem('tf-tutorial');
  } catch {
    return 'skipped';
  }
}

function mark(v) {
  try {
    localStorage.setItem('tf-tutorial', v);
  } catch {
    // 저장이 막혀 있으면 다음에 또 물어봄
  }
}

// deps: { send, keyName(id) → 키 글자, sound, nick() → 이름, leaveRoom(), quickMatch() (봇 3명과 한 판), loadChar(), saveChar(char), color() }
export class TutorialUI {
  constructor(deps) {
    this.d = deps;
    this.el = $('tutorial');
    this.band = $('tut-band');
    this.char = deps.loadChar() || C.CHAR_DEFAULT;
    this.shownKey = '';
    this.doneShown = false;
    $('tut-yes').addEventListener('click', () => this.pane('pick'));
    $('tut-no').addEventListener('click', () => {
      if (tutorialState() !== 'done') mark('skipped');
      this.close();
    });
    $('tut-back').addEventListener('click', () => this.pane('ask'));
    $('tut-go').addEventListener('click', () => this.start());
    $('tut-skip-step').addEventListener('click', () => this.skipStep());
    $('tut-menu').addEventListener('click', () => {
      this.close();
      this.d.leaveRoom();
    });
    $('tut-match').addEventListener('click', () => {
      this.close();
      this.d.quickMatch();
    });
  }

  get open() {
    return !this.el.classList.contains('hidden');
  }

  pane(name) {
    this.el.classList.remove('hidden');
    for (const p of this.el.querySelectorAll('.pane')) p.classList.toggle('hidden', !p.classList.contains(name));
    if (name === 'pick') this.drawChars();
    this.paneName = name;
  }

  close() {
    this.el.classList.add('hidden');
    this.paneName = null;
  }

  // 처음 켤 때 (타이틀 뒤): 묻기. 메뉴·설정 '튜토리얼' 은 바로 캐릭터 고르기
  ask() {
    this.pane('ask');
  }

  pick() {
    this.pane('pick');
  }

  drawChars() {
    const box = $('tut-chars');
    if (!box.children.length) {
      for (const ch of C.FIGURE_CHARS) {
        const card = document.createElement('div');
        card.className = 'tc';
        card.dataset.char = ch;
        card.innerHTML = `<div class="face"></div><div class="nm">${C.CHAR_NAMES[ch]}</div>`;
        card.addEventListener('click', () => this.choose(ch));
        box.append(card);
      }
    }
    for (const card of box.children) {
      const url = portrait(card.dataset.char, this.d.color(), 120, true);
      card.querySelector('.face').style.backgroundImage = url ? `url("${url}")` : '';
    }
    this.choose(this.char);
  }

  choose(ch) {
    this.char = C.FIGURE_CHARS.includes(ch) ? ch : C.CHAR_DEFAULT;
    for (const card of $('tut-chars').children) card.classList.toggle('sel', card.dataset.char === this.char);
    $('tut-char-intro').innerHTML = `<b>${C.CHAR_NAMES[this.char]}</b> — ${C.CHAR_INTRO[this.char] || ''}`;
  }

  start() {
    mark('done');
    this.close();
    this.d.saveChar(this.char); // 들어가면 대기실 고른 캐릭터로도 남음 (welcome 이 setChar 를 보냄)
    this.doneShown = false;
    this.shownKey = '';
    this.d.send({ type: 'tutorial', nick: this.d.nick(), char: this.char });
  }

  skipStep() {
    this.d.send({ type: 'tutorialSkip' });
  }

  // 스냅샷마다: 튜토리얼 방이면 띠 (단계 문구·진행·해냄), 끝이면 끝 화면
  update(state, me) {
    const t = state && state.tutorial;
    if (!t) {
      this.band.classList.add('hidden');
      return;
    }
    if (t.done) {
      this.band.classList.add('hidden');
      if (!this.doneShown) {
        this.doneShown = true;
        const ok = (t.results || []).filter((r) => r === 'ok').length;
        $('tut-sum').textContent = `${t.n}단계 중 ${ok}단계 해냄`;
        this.pane('done');
        if (document.pointerLockElement) document.exitPointerLock();
      }
      return;
    }
    this.band.classList.remove('hidden');
    this.band.classList.toggle('done', !!t.ok);
    const step = tutorialStep(t.id);
    const char = (me && me.char) || this.char;
    const key = `${t.i}|${t.id}|${char}|${this.d.bindsKey()}`;
    if (key !== this.shownKey && step) {
      this.shownKey = key;
      this.band.querySelector('.prog').textContent = progressLabel(t.i, t.n);
      const txt = this.band.querySelector('.txt');
      txt.textContent = '';
      // 키 이름은 노랑 글자로: 붙어 있는 자리표 ({fwd}{left}{back}{right}) 는 한 덩어리 (WASD), 설명({skillDesc}) 은 그냥 글자. 문구에 HTML 을 안 넣음
      for (const part of step.text.split(/((?:\{\w+\})+)/)) {
        if (!part) continue;
        const ids = [...part.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
        if (ids.length && !ids.some((id) => id === 'skillDesc' || id === 'ultDesc')) {
          const b = document.createElement('span');
          b.className = 'k';
          b.textContent = this.d.keyGroup(ids);
          txt.append(b);
        } else txt.append(stepText({ text: part }, { char, keyName: this.d.keyName }));
      }
    }
  }

  onEvent(e, myId) {
    if (e.type === 'tutorialOk' && e.who === myId) this.d.sound.play('clear');
    else if (e.type === 'tutorialDone' && e.who === myId) this.d.sound.play('win');
  }
}
