// 방: 서버 하나에 게임 여러 개. 방 = 게임 + 들어온 접속 + 로그 파일.
// 접속은 처음엔 방 밖(목록 화면)에 있고, 방을 만들거나 코드로 들어간다. 나가거나 내보내지면 다시 방 밖으로.
// 사람이 0명이 되면 방을 없앤다 (봇도 같이, 승수도 사라짐).
// 재접속 (2026-10-28): 들어오면 자리 토큰 (welcome.token). 연결이 끊기면 자리를 RECONNECT_GRACE_MS 동안 유지 (판 중이면 봇 대리),
// 그 안에 { type: 'rejoin', code, token } 으로 오면 같은 자리 (같은 플레이어 id). 지나면 예전처럼 나감. 같은 토큰이 또 오면 새 접속이 자리를 가져감.
// 소켓은 { readyState, OPEN, send(text) } 만 쓴다 (테스트는 가짜 소켓).
import { randomBytes } from 'node:crypto';
import { CONFIG as C } from '../shared/config.js';
import { Game } from './game.js';

const maxPlayers = () => Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);

// 방 주소: 터널 주소 + ?room=코드 (tools/online.js 콘솔 안내와 같은 모양)
export function roomLinkOf(base, code) {
  return `${base.replace(/\/+$/, '')}/?room=${code}`;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

// 이름 정리: 제어 문자 빼고 공백 하나로, max 글자까지 (게임 이름과 같은 방식)
function cleanText(raw, max) {
  const clean = String(raw ?? '')
    .slice(0, C.TEXT_RAW_MAX) // 먼저 자름 (긴 문자열에 정규식을 통째로 돌리지 않게)
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return Array.from(clean).slice(0, max).join('');
}

export class Rooms {
  // openLog(code) → { log(msg), close() }: 방마다 로그 (서버는 파일, 테스트는 배열)
  // serverLog(msg): 방 밖 일 (방 만듦·없앰)
  // now(): 메시지 빈도 제한용 시계 (ms, 테스트는 가짜)
  constructor({ openLog = () => ({ log() {}, close() {} }), serverLog = () => {}, rng = Math.random, countdownMs = 0, now = () => performance.now() } = {}) {
    this.now = now;
    this.openLog = openLog;
    this.serverLog = serverLog;
    this.rng = rng;
    this.countdownMs = countdownMs;
    this.rooms = new Map(); // code → room
    this.conns = new Set();
    this.nextId = 1; // 플레이어 id 는 방이 달라도 겹치지 않게 서버 전체에서 셈
    this.lastList = '';
    this.load = { workMs: 0, behindMs: 0 }; // 서버 틱 부하 (index.js 가 noteTick 으로 알려 줌) → pong 에 실어 보냄
  }

  // 서버 틱 한 번의 일한 시간·밀린 시간 (ms). 화면 핑 표시에 "서버가 늦음" 을 보이려고. 일한 시간은 천천히 줄어드는 최댓값
  noteTick(workMs, behindMs) {
    this.load = { workMs: Math.max(workMs, this.load.workMs * C.NET_LOAD_DECAY), behindMs };
  }

  // ---------- 접속 ----------
  connect(ws) {
    const conn = { id: this.nextId++, ws, room: null, bucket: C.NET_MSG_BURST, bucketAt: this.now(), dropped: 0 };
    this.conns.add(conn);
    this.sendList(conn);
    return conn;
  }

  // 연결 끊김: 방 안이면 자리 유지 (setAway), 방 밖이면 그냥 지움
  disconnect(conn) {
    const room = conn.room;
    try {
      this.disconnectIn(conn, room);
    } catch (err) {
      if (room) this.crash(room, '접속 끊김', err);
    }
    this.conns.delete(conn);
  }

  disconnectIn(conn, room) {
    const seat = room && room.seats.get(conn.id);
    if (seat && seat.conn === conn) {
      seat.conn = null;
      seat.awayAt = room.game.time;
      room.conns.delete(conn.id);
      conn.room = null;
      room.game.setAway(conn.id, true);
    } else if (room) this.leave(conn, null);
  }

  // 방 하나에서 난 예외 (2026-10-30 감사: 예전엔 방 하나의 예외가 서버 전체를 죽임): 그 방만 로그 남기고 닫음, 사람들은 방 밖 목록으로. 다른 방은 계속
  crash(room, where, err) {
    if (!this.rooms.has(room.code)) return;
    const text = err && err.stack ? err.stack : String(err);
    try {
      room.out.log(`[오류] ${where}: ${text}`);
    } catch {
      // 로그도 못 쓰면 서버 콘솔에만
    }
    this.serverLog(`방 ${room.code} 오류로 닫음 (${where}: ${err && err.message ? err.message : err})`);
    this.rooms.delete(room.code);
    for (const c of room.conns.values()) {
      c.room = null;
      send(c.ws, { type: 'left', reason: '방에 오류가 나서 방을 닫았습니다 (서버는 그대로)' });
      this.sendList(c);
    }
    room.conns.clear();
    room.seats.clear();
    try {
      room.out.close();
    } catch {
      // 위와 같음
    }
  }

  // 연결마다 1초에 NET_MSG_RATE 개 (잠깐 몰리면 NET_MSG_BURST 개까지). 넘는 메시지는 버림
  allow(conn) {
    const now = this.now();
    conn.bucket = Math.min(C.NET_MSG_BURST, conn.bucket + ((now - conn.bucketAt) * C.NET_MSG_RATE) / 1000);
    conn.bucketAt = now;
    if (conn.bucket >= 1) {
      conn.bucket -= 1;
      return true;
    }
    if (conn.dropped++ === 0) this.serverLog(`접속 ${conn.id}: 메시지가 너무 많아 버림 (초당 ${C.NET_MSG_RATE}개까지)`);
    return false;
  }

  // 토큰으로 같은 자리에 다시 붙기. 방·토큰이 안 맞거나 자리 유지 시간이 지났으면 rejoinError (화면은 보통 들어가기로 다시)
  rejoin(conn, rawCode, token) {
    const code = String(rawCode ?? '').trim().toUpperCase();
    const room = this.rooms.get(code);
    const found = room && typeof token === 'string' ? [...room.seats.entries()].find(([, s]) => s.token === token) : null;
    if (!found) {
      send(conn.ws, { type: 'rejoinError', code, reason: '자리가 없습니다 (시간이 지났거나 방이 없어짐)' });
      return false;
    }
    const [id, seat] = found;
    const old = seat.conn;
    if (old) {
      // 같은 토큰이 다른 창에서 또 옴: 새 창이 자리를 가져감, 옛 창은 방 밖 목록으로 (새 id — 같은 id 로 다른 방에 못 들어가게)
      room.conns.delete(old.id);
      old.room = null;
      old.id = this.nextId++;
      send(old.ws, { type: 'left', reason: '다른 창에서 이 자리로 들어왔습니다', replaced: true });
      this.sendList(old);
      room.game.log(`  [복귀] ${room.game.players.get(id).name} 다른 창으로 옮김`);
    }
    const awayMs = seat.awayAt === null ? 0 : room.game.time - seat.awayAt;
    conn.id = id;
    conn.room = room;
    room.conns.set(id, conn);
    seat.conn = conn;
    seat.awayAt = null;
    room.game.setAway(id, false);
    if (!old) room.game.log(`  (복귀까지 ${(awayMs / 1000).toFixed(1)}초)`); // npm run stats 가 셈
    const player = room.game.players.get(id);
    send(conn.ws, { type: 'welcome', id, slot: player.slot, name: player.name, room: this.roomInfo(room), token: seat.token, rejoined: true });
    send(conn.ws, { ...room.game.snapshot(true), room: this.roomInfo(room) });
    return true;
  }

  // 자리 토큰 (추측 불가): 이 방 안에서 겹치지 않게
  newSeat(room, conn) {
    const token = randomBytes(C.RECONNECT_TOKEN_BYTES).toString('hex');
    room.seats.set(conn.id, { token, conn, awayAt: null });
    return token;
  }

  // 끊긴 자리 중 유지 시간이 지난 것: 예전처럼 나감 (판 중이면 접속 끊김 사망), 사람이 0명이면 방도 없앰
  expireSeats(room) {
    for (const [id, seat] of room.seats) {
      if (seat.awayAt === null || room.game.time - seat.awayAt < C.RECONNECT_GRACE_MS) continue;
      const p = room.game.players.get(id);
      room.game.log(`  [끊김 만료] ${p ? p.name : id} ${C.RECONNECT_GRACE_MS / 1000}초 안에 안 돌아옴`);
      room.seats.delete(id);
      room.game.removePlayer(id);
    }
    if (room.game.humanCount() === 0) this.close(room);
  }

  message(conn, msg) {
    if (!msg || typeof msg !== 'object' || !this.allow(conn)) return;
    const room = conn.room;
    try {
      this.messageIn(conn, msg);
    } catch (err) {
      if (room) this.crash(room, `메시지 ${String(msg.type).slice(0, 20)}`, err);
      else this.serverLog(`방 밖 메시지 오류 (${String(msg.type).slice(0, 20)}): ${err && err.message}`);
    }
  }

  messageIn(conn, msg) {
    // 핑: 보낸 시각 t 를 그대로 돌려줌 (왕복 시간은 화면이 잼) + 서버 틱 부하. 방 안·밖 둘 다
    if (msg.type === 'ping') {
      if (Number.isFinite(msg.t)) send(conn.ws, { type: 'pong', t: msg.t, workMs: Math.round(this.load.workMs * 10) / 10, behindMs: Math.round(this.load.behindMs), tickMs: 1000 / C.TICK_RATE });
      return;
    }
    if (!conn.room) {
      if (msg.type === 'create') this.create(conn, msg.name, msg.nick);
      else if (msg.type === 'practice') this.createPractice(conn, msg.nick, msg.char);
      else if (msg.type === 'tutorial') this.createPractice(conn, msg.nick, msg.char, true);
      else if (msg.type === 'join') this.join(conn, msg.code);
      else if (msg.type === 'rejoin') this.rejoin(conn, msg.code, msg.token);
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
    const room = { code, name, public: false, game, conns: new Map(), seats: new Map(), out }; // seats: 플레이어 id → { token, conn, awayAt }
    this.rooms.set(code, room);
    out.log(`방 ${code} 만듦: ${name} (비공개)`);
    this.serverLog(`방 ${code} 만듦: ${name} (방 ${this.rooms.size}개)`);
    this.join(conn, code);
    return room;
  }

  // 연습 방: 비공개(목록에 안 뜸), 로그 파일 없음, 들어가면 바로 시작 + 허수아비 1개. 같은 코드로 친구가 들어오면 같이 연습
  // tutorial: 튜토리얼 방 (연습 위에 단계, 허수아비·지형은 단계가 놓음, 이것도 로그 파일 없음)
  createPractice(conn, rawNick, char, tutorial = false) {
    if (this.rooms.size >= C.ROOM_MAX) {
      send(conn.ws, { type: 'joinError', reason: `방이 이미 ${C.ROOM_MAX}개라 더 못 만듭니다` });
      return null;
    }
    const code = this.newCode();
    const nick = cleanText(rawNick, C.NAME_MAX_LEN);
    const out = { log() {}, close() {} }; // 연습 판은 로그·stats 에서 뺌
    const game = new Game(() => {}, { countdownMs: 0, characters: true, skyStairs: false });
    const room = { code, name: nick ? `${nick}의 ${tutorial ? '튜토리얼' : '연습'}` : `${tutorial ? '튜토리얼' : '연습'} ${code}`, public: false, practice: true, tutorial, game, conns: new Map(), seats: new Map(), out };
    this.rooms.set(code, room);
    this.serverLog(`방 ${code} 만듦: ${tutorial ? '튜토리얼' : '연습'} (방 ${this.rooms.size}개)`);
    const player = game.addPlayer(conn.id);
    conn.room = room;
    room.conns.set(conn.id, conn);
    if (nick) game.setNick(conn.id, nick);
    if (char) game.setChar(conn.id, String(char));
    if (tutorial) game.startTutorial(conn.id);
    else {
      game.startPractice();
      game.addDummy(conn.id);
    }
    const token = this.newSeat(room, conn);
    send(conn.ws, { type: 'welcome', id: conn.id, slot: player.slot, name: player.name, room: this.roomInfo(room), token });
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
    const token = this.newSeat(room, conn);
    send(conn.ws, { type: 'welcome', id: conn.id, slot: player.slot, name: player.name, room: this.roomInfo(room), token });
    send(conn.ws, { ...room.game.snapshot(true), room: this.roomInfo(room) });
    return true;
  }

  // reason: 방 밖으로 돌려보낼 때 보여줄 문구 (null = 연결이 끊김, 보낼 곳 없음)
  leave(conn, reason) {
    const room = conn.room;
    if (!room) return;
    room.game.removePlayer(conn.id);
    room.conns.delete(conn.id);
    room.seats.delete(conn.id);
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
        else {
          room.seats.delete(target); // 끊긴 사람도 자리 없앰
          game.removePlayer(target);
        }
        break;
      }
      case 'setName':
        game.setNick(id, msg.name);
        break;
      case 'setChar':
        game.setChar(id, String(msg.char));
        break;
      case 'setColor': // 대기실 색 고르기 (PLAYER_PALETTE 번호, 쓰는 색·판 중이면 무시)
        game.setColor(id, msg.color);
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
      case 'setMap': // 연습 방은 누구나, 판 중에도 바로
        if (host || room.practice) game.setMap(String(msg.map));
        break;
      case 'setMode':
        if (host) game.setMode(String(msg.mode));
        break;
      case 'skyStairs':
        if (host) game.setSkyStairs(!!msg.on);
        break;
      case 'hpMode': // 체력전 (대기실 옵션)
        if (host) game.setHpMode(!!msg.on);
        break;
      case 'ghostDrop': // 유령 투하: 죽은 사람이 고른 칸에 1칸 블록 (생존 모드)
        game.ghostDrop(id, msg.x, msg.y);
        break;
      case 'tutorialSkip': // 튜토리얼: 이 단계 넘기기
        if (room.tutorial && game.tutorial) game.tutorial.skip();
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
    for (const room of [...this.rooms.values()]) {
      try {
        room.game.tick(dt);
        this.expireSeats(room);
      } catch (err) {
        this.crash(room, '틱', err);
      }
    }
  }

  // 방마다 스냅샷 한 번 (이벤트는 보낼 때 비움)
  broadcast() {
    for (const room of [...this.rooms.values()]) {
      let payload;
      try {
        const snap = room.game.snapshot(false);
        snap.events = room.game.drainEvents();
        snap.room = this.roomInfo(room);
        payload = JSON.stringify(snap);
      } catch (err) {
        this.crash(room, '스냅샷', err);
        continue;
      }
      for (const c of room.conns.values()) if (c.ws.readyState === c.ws.OPEN) c.ws.send(payload);
    }
  }

  roomInfo(room) {
    // link: 친구에게 줄 방 주소 (npm run online 의 터널 주소가 있을 때만, 없으면 필드 없음 → 화면이 지금 주소로)
    const info = { code: room.code, name: room.name, public: room.public, practice: !!room.practice };
    if (room.tutorial) info.tutorial = true; // 튜토리얼 방만 (보통 방 정보는 예전 그대로)
    if (this.publicUrl) info.link = roomLinkOf(this.publicUrl, room.code);
    return info;
  }

  // npm run online 이 찾은 터널 주소 (https 만). 이미 있는 방 사람들에게도 다음 스냅샷부터 새 링크
  setPublicUrl(url) {
    const u = typeof url === 'string' && /^https:\/\/[a-z0-9.-]+$/i.test(url.replace(/\/+$/, '')) ? url.replace(/\/+$/, '') : null;
    this.publicUrl = u;
    return !!u;
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
        hpMode: r.game.hpMode,
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
