// 방: 서버 하나에 게임 여러 개. 방 = 게임 + 들어온 접속 + 로그 파일.
// 접속은 처음엔 방 밖(목록 화면)에 있고, 방을 만들거나 코드로 들어간다. 나가거나 내보내지면 다시 방 밖으로.
// 사람이 0명이 되면 방을 바로 없앤다 (봇도 같이, 승수도 사라짐).
// 소켓은 { readyState, OPEN, send(text) } 만 쓴다 (테스트는 가짜 소켓).
import { CONFIG as C } from '../shared/config.js';
import { Game } from './game.js';

const maxPlayers = () => Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

// 이름 정리: 제어 문자 빼고 공백 하나로, max 글자까지 (게임 이름과 같은 방식)
function cleanText(raw, max) {
  const clean = String(raw ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return Array.from(clean).slice(0, max).join('');
}

export class Rooms {
  // openLog(code) → { log(msg), close() }: 방마다 로그 (서버는 파일, 테스트는 배열)
  // serverLog(msg): 방 밖 일 (방 만듦·없앰)
  constructor({ openLog = () => ({ log() {}, close() {} }), serverLog = () => {}, rng = Math.random, countdownMs = 0 } = {}) {
    this.openLog = openLog;
    this.serverLog = serverLog;
    this.rng = rng;
    this.countdownMs = countdownMs;
    this.rooms = new Map(); // code → room
    this.conns = new Set();
    this.nextId = 1; // 플레이어 id 는 방이 달라도 겹치지 않게 서버 전체에서 셈
    this.lastList = '';
  }

  // ---------- 접속 ----------
  connect(ws) {
    const conn = { id: this.nextId++, ws, room: null };
    this.conns.add(conn);
    this.sendList(conn);
    return conn;
  }

  disconnect(conn) {
    if (conn.room) this.leave(conn, null);
    this.conns.delete(conn);
  }

  message(conn, msg) {
    if (!msg || typeof msg !== 'object') return;
    if (!conn.room) {
      if (msg.type === 'create') this.create(conn, msg.name, msg.nick);
      else if (msg.type === 'practice') this.createPractice(conn, msg.nick, msg.char);
      else if (msg.type === 'join') this.join(conn, msg.code);
      return;
    }
    this.roomMessage(conn.room, conn, msg);
  }

  // ---------- 방 만들기·들어가기·나가기 ----------
  newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < C.ROOM_CODE_LEN; i++) code += C.ROOM_CODE_CHARS[Math.floor(this.rng() * C.ROOM_CODE_CHARS.length)];
      if (!this.rooms.has(code)) return code;
    }
  }

  create(conn, rawName, rawNick) {
    if (this.rooms.size >= C.ROOM_MAX) {
      send(conn.ws, { type: 'joinError', reason: `방이 이미 ${C.ROOM_MAX}개라 더 못 만듭니다` });
      return null;
    }
    const code = this.newCode();
    const nick = cleanText(rawNick, C.NAME_MAX_LEN);
    const name = cleanText(rawName, C.ROOM_NAME_MAX_LEN) || (nick ? `${nick}의 방` : `방 ${code}`);
    const out = this.openLog(code);
    const game = new Game((m) => out.log(m), { countdownMs: this.countdownMs, characters: true, skyStairs: C.SKY_STAIRS_DEFAULT });
    game.setMap(C.MAP_DEFAULT);
    const room = { code, name, public: false, game, conns: new Map(), out };
    this.rooms.set(code, room);
    out.log(`방 ${code} 만듦: ${name} (비공개)`);
    this.serverLog(`방 ${code} 만듦: ${name} (방 ${this.rooms.size}개)`);
    this.join(conn, code);
    return room;
  }

  // 연습 방: 비공개(목록에 안 뜸), 로그 파일 없음, 들어가면 바로 시작 + 허수아비 1개. 같은 코드로 친구가 들어오면 같이 연습
  createPractice(conn, rawNick, char) {
    if (this.rooms.size >= C.ROOM_MAX) {
      send(conn.ws, { type: 'joinError', reason: `방이 이미 ${C.ROOM_MAX}개라 더 못 만듭니다` });
      return null;
    }
    const code = this.newCode();
    const nick = cleanText(rawNick, C.NAME_MAX_LEN);
    const out = { log() {}, close() {} }; // 연습 판은 로그·stats 에서 뺌
    const game = new Game(() => {}, { countdownMs: 0, characters: true, skyStairs: false });
    const room = { code, name: nick ? `${nick}의 연습` : `연습 ${code}`, public: false, practice: true, game, conns: new Map(), out };
    this.rooms.set(code, room);
    this.serverLog(`방 ${code} 만듦: 연습 (방 ${this.rooms.size}개)`);
    const player = game.addPlayer(conn.id);
    conn.room = room;
    room.conns.set(conn.id, conn);
    if (nick) game.setNick(conn.id, nick);
    if (char) game.setChar(conn.id, String(char));
    game.startPractice();
    game.addDummy(conn.id);
    send(conn.ws, { type: 'welcome', id: conn.id, slot: player.slot, name: player.name, room: this.roomInfo(room) });
    send(conn.ws, { ...game.snapshot(true), room: this.roomInfo(room) });
    return room;
  }

  join(conn, rawCode) {
    const code = String(rawCode ?? '').trim().toUpperCase();
    const room = this.rooms.get(code);
    if (!room) {
      send(conn.ws, { type: 'joinError', reason: `${code || '빈 코드'}: 그런 방이 없습니다 (코드 확인, 사람이 다 나가면 방이 없어짐)` });
      return false;
    }
    const player = room.game.addPlayer(conn.id);
    if (!player) {
      send(conn.ws, { type: 'joinError', reason: `방이 꽉 찼습니다 (최대 ${maxPlayers()}명)` });
      return false;
    }
    conn.room = room;
    room.conns.set(conn.id, conn);
    if (room.practice) room.game.practiceJoin(conn.id); // 연습 방은 관전 말고 바로
    send(conn.ws, { type: 'welcome', id: conn.id, slot: player.slot, name: player.name, room: this.roomInfo(room) });
    send(conn.ws, { ...room.game.snapshot(true), room: this.roomInfo(room) });
    return true;
  }

  // reason: 방 밖으로 돌려보낼 때 보여줄 문구 (null = 연결이 끊김, 보낼 곳 없음)
  leave(conn, reason) {
    const room = conn.room;
    if (!room) return;
    room.game.removePlayer(conn.id);
    room.conns.delete(conn.id);
    conn.room = null;
    if (room.game.humanCount() === 0) this.close(room);
    if (reason !== null) {
      send(conn.ws, { type: 'left', reason: reason || '' });
      this.sendList(conn);
    }
  }

  close(room) {
    room.game.removeAllBots();
    room.out.log(`방 ${room.code} 닫음 (사람 0명)`);
    room.out.close();
    this.rooms.delete(room.code);
    this.serverLog(`방 ${room.code} 닫음 (방 ${this.rooms.size}개)`);
  }

  // ---------- 방 안 메시지 ----------
  roomMessage(room, conn, msg) {
    const game = room.game;
    const id = conn.id;
    const host = game.isHost(id);
    switch (msg.type) {
      case 'input':
        game.handleInput(id, msg);
        break;
      case 'action':
        game.handleAction(id, msg);
        break;
      case 'leave':
        this.leave(conn, '');
        break;
      case 'setPublic': // 호스트: 공개 목록에 보이기 (판 사이에만, 연습 방은 안 됨)
        if (host && !room.practice && !game.inRound() && room.public !== !!msg.on) {
          room.public = !!msg.on;
          room.out.log(`[호스트] 방 ${room.public ? '공개' : '비공개'}`);
        }
        break;
      case 'addBot':
        if (host && !game.addBot()) room.out.log('봇 추가 거부: 방이 꽉 찼거나 판 진행 중');
        break;
      case 'removeBot':
        if (host) game.removeBot();
        break;
      case 'spectate': // 호스트: 관전 ↔ 참가 (판 사이에만)
        if (host) game.setSpectator(Number(msg.target), msg.on);
        break;
      case 'kick': {
        // 호스트: 내보내기 (자기 자신은 안 됨, 판 사이에만). 사람은 방 밖 목록으로 돌려보내고, 봇은 바로 뺀다
        const target = Number(msg.target);
        if (!host || target === id || !game.players.has(target) || game.inRound()) break;
        room.out.log(`[호스트] ${game.players.get(target).name} 내보냄`);
        const tconn = room.conns.get(target);
        if (tconn) this.leave(tconn, '호스트가 방에서 내보냈습니다');
        else game.removePlayer(target);
        break;
      }
      case 'setName':
        game.setNick(id, msg.name);
        break;
      case 'setChar':
        game.setChar(id, String(msg.char));
        break;
      case 'teamMode':
        if (host) game.setTeamMode(!!msg.on);
        break;
      case 'setTeam':
        if (host) game.setTeam(Number(msg.target), String(msg.team));
        break;
      case 'shuffleTeams':
        if (host) game.shuffleTeams();
        break;
      case 'botLevel':
        if (host) game.setBotLevel(String(msg.level));
        break;
      case 'setMap':
        if (host) game.setMap(String(msg.map));
        break;
      case 'setMode':
        if (host) game.setMode(String(msg.mode));
        break;
      case 'skyStairs':
        if (host) game.setSkyStairs(!!msg.on);
        break;
      case 'practiceSet': // 연습: 토글 (방 전체) · 내 피해 %
        if (room.practice) game.practiceSet(id, String(msg.key), msg.value);
        break;
      case 'dummyAdd':
        if (room.practice) game.addDummy(id);
        break;
      case 'dummyRemove':
        if (room.practice) game.removeDummy(msg.id === undefined ? undefined : Number(msg.id));
        break;
      case 'dummySet':
        if (room.practice) game.setDummyDamage(msg.id === undefined ? undefined : Number(msg.id), msg.damage);
        break;
      case 'start':
        if (host && !game.startRound()) {
          room.out.log(`시작 거부: 참가자 ${game.participants().length}명 (최소 ${C.MIN_PLAYERS}명, 관전자 제외)`);
        }
        break;
      default:
    }
  }

  // ---------- 틱·보내기 ----------
  tick(dt) {
    for (const room of this.rooms.values()) room.game.tick(dt);
  }

  // 방마다 스냅샷 한 번 (이벤트는 보낼 때 비움)
  broadcast() {
    for (const room of this.rooms.values()) {
      const snap = room.game.snapshot(false);
      snap.events = room.game.drainEvents();
      snap.room = this.roomInfo(room);
      const payload = JSON.stringify(snap);
      for (const c of room.conns.values()) if (c.ws.readyState === c.ws.OPEN) c.ws.send(payload);
    }
  }

  roomInfo(room) {
    return { code: room.code, name: room.name, public: room.public, practice: !!room.practice };
  }

  // 공개 방 목록 (방 밖 화면). 판 중인지는 안 보여줌 (재혁 결정: 이름·인원·맵·팀전·봇 난이도, 모드)
  publicList() {
    const rooms = [];
    for (const r of this.rooms.values()) {
      if (!r.public) continue;
      const ps = [...r.game.players.values()];
      rooms.push({
        code: r.code,
        name: r.name,
        humans: ps.filter((p) => !p.isBot).length,
        bots: ps.filter((p) => p.isBot).length,
        max: maxPlayers(),
        map: r.game.mapChoice,
        mode: r.game.mode,
        teamMode: r.game.teamMode,
        botLevel: r.game.botLevel,
        skyStairs: r.game.skyStairs,
      });
    }
    return { type: 'rooms', rooms, count: this.rooms.size, max: C.ROOM_MAX };
  }

  sendList(conn) {
    send(conn.ws, this.publicList());
  }

  // 방 밖에 있는 사람들에게 목록 (바뀌었을 때만)
  broadcastList(force = false) {
    const list = this.publicList();
    const text = JSON.stringify(list);
    if (!force && text === this.lastList) return;
    this.lastList = text;
    for (const c of this.conns) if (!c.room && c.ws.readyState === c.ws.OPEN) c.ws.send(text);
  }
}
