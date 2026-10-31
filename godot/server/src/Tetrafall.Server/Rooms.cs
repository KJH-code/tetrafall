using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using static Tetrafall.Core.Js.JsValue;

namespace Tetrafall.Server;

// 방 (server/rooms.js). 서버 하나에 게임 여러 개. 방 = 게임 + 들어온 접속 + 로그 파일. 메시지·응답 JSON·로그는 JS 서버와 글자 하나까지 같게
// (기존 JS 화면이 이 서버에 그대로 붙음, npm run stats 가 로그를 그대로 읽음). 모든 메서드는 게임 루프 스레드 하나에서만 불림 (Program.cs) → 잠금 없음
// 재접속: 들어오면 자리 토큰 (welcome.token). 연결이 끊기면 자리를 RECONNECT_GRACE_MS 동안 유지 (판 중이면 봇 대리 — game.SetAway),
// 그 안에 { type: 'rejoin', code, token } 으로 오면 같은 자리 (같은 플레이어 id). 지나면 예전처럼 나감. 같은 토큰이 또 오면 새 접속이 자리를 가져감

public interface ISocket
{
    bool Open { get; }
    void Send(string text);
}

public sealed class Conn
{
    public int id;
    public ISocket ws = null!;
    public Room? room;
    public double bucket, bucketAt;
    public int dropped;
}

public sealed class Seat
{
    public string token = "";
    public Conn? conn;
    public double? awayAt;
}

public interface IRoomLog
{
    void Log(string msg);
    void Close();
}

public sealed class Room
{
    public string code = "";
    public string name = "";
    public bool isPublic, practice, tutorial;
    public Game game = null!;
    public readonly OrderedMap<int, Conn> conns = new(); // 플레이어 id → 접속 (JS Map: 넣은 순서 = 보내기 순서)
    public readonly OrderedMap<int, Seat> seats = new(); // 플레이어 id → 자리 { token, conn, awayAt }
    public IRoomLog @out = null!;
}

// JS Map 처럼 넣은 순서를 지키는 사전 (있는 키에 다시 넣으면 자리 그대로, 지웠다 넣으면 끝으로)
public sealed class OrderedMap<TKey, TValue> where TKey : notnull
{
    readonly Dictionary<TKey, TValue> map = new();
    readonly List<TKey> keys = new();

    public int Count => keys.Count;
    public bool Has(TKey k) => map.ContainsKey(k);
    public TValue? Get(TKey k) => map.TryGetValue(k, out var v) ? v : default;

    public void Set(TKey k, TValue v)
    {
        if (!map.ContainsKey(k)) keys.Add(k);
        map[k] = v;
    }

    public bool Delete(TKey k)
    {
        if (!map.Remove(k)) return false;
        keys.Remove(k);
        return true;
    }

    public void Clear()
    {
        map.Clear();
        keys.Clear();
    }

    public List<KeyValuePair<TKey, TValue>> Entries() => keys.Select(k => new KeyValuePair<TKey, TValue>(k, map[k])).ToList();
    public List<TValue> Values() => keys.Select(k => map[k]).ToList();
}

public sealed class Rooms
{
    readonly Func<string, IRoomLog> openLog;
    readonly Action<string> serverLog;
    readonly Func<double> rng;
    readonly double countdownMs;
    readonly Func<double> now;
    readonly Func<string> newToken;
    readonly OrderedMap<string, Room> rooms = new(); // code → room
    public readonly List<Conn> conns = new(); // JS Set (넣은 순서)
    int nextId = 1; // 플레이어 id 는 방이 달라도 겹치지 않게 서버 전체에서 셈
    string lastList = "";
    (double workMs, double behindMs) load = (0, 0);
    string? publicUrl;

    // 테스트용: 방 하나에서 예외가 나는 경우 (JS 테스트는 game.tick 등을 갈아 끼움). where = "틱" | "메시지" | "스냅샷"
    public Action<Room, string>? fault;

    // 방마다 틱·스냅샷을 병렬로 (false 면 예전처럼 한 스레드에서 차례로 — 부하 비교용)
    public bool parallel = true;

    static double MaxPlayers() => Math.Min(C.MAX_PLAYERS, 8); // shared/config.js SPAWN_POINTS 8곳

    // openLog(code) → 방마다 로그 (서버는 파일, 테스트는 목록), serverLog: 방 밖 일, now(): 메시지 빈도 제한용 시계 (ms),
    // newToken(): 자리 토큰 (기본 RECONNECT_TOKEN_BYTES 바이트 난수의 16진수, 테스트는 정해진 값)
    public Rooms(Func<string, IRoomLog>? openLog = null, Action<string>? serverLog = null, Func<double>? rng = null, double countdownMs = 0, Func<double>? now = null, Func<string>? newToken = null)
    {
        this.openLog = openLog ?? (_ => new NullLog());
        this.serverLog = serverLog ?? (_ => { });
        this.rng = rng ?? Random.Shared.NextDouble;
        this.countdownMs = countdownMs;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        this.now = now ?? (() => sw.Elapsed.TotalMilliseconds);
        this.newToken = newToken ?? (() => Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes((int)C.RECONNECT_TOKEN_BYTES)).ToLowerInvariant());
    }

    sealed class NullLog : IRoomLog
    {
        public void Log(string msg) { }
        public void Close() { }
    }

    public Room? Get(string code) => rooms.Get(code);

    // 이 토큰의 자리가 있는 방 코드 (테스트·도구용)
    public string? CodeOfToken(string? token) => token == null ? null : rooms.Values().FirstOrDefault(r => r.seats.Values().Any(x => x.token == token))?.code;
    public bool Has(string code) => rooms.Has(code);
    public int Count => rooms.Count;

    static void Send(ISocket ws, string text)
    {
        if (ws.Open) ws.Send(text);
    }

    static void Send(ISocket ws, Action<JsonOut> write)
    {
        var o = new JsonOut();
        o.Obj();
        write(o);
        o.EndObj();
        Send(ws, o.ToString());
    }

    // 이름 정리: String(raw ?? '') 를 제어 문자 빼고 공백 하나로, max 글자까지 (게임 이름과 같은 방식)
    public static string CleanText(JsonElement? raw, double max) => JsText.Clean(StrOrEmpty(raw), max);

    // 서버 틱 한 번의 일한 시간·밀린 시간 (ms). 일한 시간은 천천히 줄어드는 최댓값 → pong 에 실어 보냄
    public void NoteTick(double workMs, double behindMs) => load = (Math.Max(workMs, load.workMs * C.NET_LOAD_DECAY), behindMs);

    // ---------- 접속 ----------
    public Conn Connect(ISocket ws)
    {
        var conn = new Conn { id = nextId++, ws = ws, bucket = C.NET_MSG_BURST, bucketAt = now() };
        conns.Add(conn);
        SendList(conn);
        return conn;
    }

    // 연결 끊김: 방 안이면 자리 유지 (setAway), 방 밖이면 그냥 지움
    public void Disconnect(Conn conn)
    {
        var room = conn.room;
        try
        {
            DisconnectIn(conn, room);
        }
        catch (Exception err)
        {
            if (room != null) Crash(room, "접속 끊김", err);
        }
        conns.Remove(conn);
    }

    void DisconnectIn(Conn conn, Room? room)
    {
        var seat = room?.seats.Get(conn.id);
        if (room != null && seat != null && seat.conn == conn)
        {
            seat.conn = null;
            seat.awayAt = room.game.time;
            room.conns.Delete(conn.id);
            conn.room = null;
            room.game.SetAway(conn.id, true);
        }
        else if (room != null) Leave(conn, null);
    }

    // 방 하나에서 난 예외: 그 방만 로그 남기고 닫음, 사람들은 방 밖 목록으로. 다른 방은 계속
    public void Crash(Room room, string where, Exception err)
    {
        if (!rooms.Has(room.code)) return;
        try { room.@out.Log($"[오류] {where}: {err}"); } catch { } // 로그도 못 쓰면 서버 콘솔에만
        serverLog($"방 {room.code} 오류로 닫음 ({where}: {err.Message})");
        rooms.Delete(room.code);
        foreach (var c in room.conns.Values())
        {
            c.room = null;
            Send(c.ws, o => o.P("type", "left").P("reason", "방에 오류가 나서 방을 닫았습니다 (서버는 그대로)"));
            SendList(c);
        }
        room.conns.Clear();
        room.seats.Clear();
        try { room.@out.Close(); } catch { }
    }

    // 연결마다 1초에 NET_MSG_RATE 개 (잠깐 몰리면 NET_MSG_BURST 개까지). 넘는 메시지는 버림
    bool Allow(Conn conn)
    {
        double t = now();
        conn.bucket = Math.Min(C.NET_MSG_BURST, conn.bucket + (t - conn.bucketAt) * C.NET_MSG_RATE / 1000);
        conn.bucketAt = t;
        if (conn.bucket >= 1)
        {
            conn.bucket -= 1;
            return true;
        }
        if (conn.dropped++ == 0) serverLog($"접속 {conn.id}: 메시지가 너무 많아 버림 (초당 {JsNumber.ToJs(C.NET_MSG_RATE)}개까지)");
        return false;
    }

    // 토큰으로 같은 자리에 다시 붙기. 방·토큰이 안 맞거나 자리 유지 시간이 지났으면 rejoinError (화면은 보통 들어가기로 다시)
    public bool Rejoin(Conn conn, JsonElement? rawCode, JsonElement? rawToken)
    {
        var code = JsText.Trim(StrOrEmpty(rawCode)).ToUpperInvariant();
        var room = rooms.Get(code);
        var token = AsString(rawToken);
        var found = room != null && token != null ? room.seats.Entries().FirstOrDefault(e => e.Value.token == token) : default;
        if (room == null || found.Value == null)
        {
            Send(conn.ws, o => o.P("type", "rejoinError").P("code", code).P("reason", "자리가 없습니다 (시간이 지났거나 방이 없어짐)"));
            return false;
        }
        var (id, seat) = (found.Key, found.Value);
        var old = seat.conn;
        if (old != null)
        {
            // 같은 토큰이 다른 창에서 또 옴: 새 창이 자리를 가져감, 옛 창은 방 밖 목록으로 (새 id — 같은 id 로 다른 방에 못 들어가게)
            room.conns.Delete(old.id);
            old.room = null;
            old.id = nextId++;
            Send(old.ws, o => o.P("type", "left").P("reason", "다른 창에서 이 자리로 들어왔습니다").P("replaced", true));
            SendList(old);
            room.game.Log($"  [복귀] {room.game.players[id].name} 다른 창으로 옮김");
        }
        double awayMs = seat.awayAt is { } at ? room.game.time - at : 0;
        conn.id = id;
        conn.room = room;
        room.conns.Set(id, conn);
        seat.conn = conn;
        seat.awayAt = null;
        room.game.SetAway(id, false);
        if (old == null) room.game.Log($"  (복귀까지 {JsNumber.ToFixed(awayMs / 1000, 1)}초)"); // npm run stats 가 셈
        var player = room.game.players[id];
        Send(conn.ws, o => o.P("type", "welcome").P("id", id).P("slot", player.slot).P("name", player.name).Key("room").Raw(RoomInfo(room)).P("token", seat.token).P("rejoined", true));
        Send(conn.ws, room.game.Snapshot(true, o => o.Key("room").Raw(RoomInfo(room))));
        return true;
    }

    // 자리 토큰 (추측 불가)
    string NewSeat(Room room, Conn conn)
    {
        var token = newToken();
        room.seats.Set(conn.id, new Seat { token = token, conn = conn });
        return token;
    }

    // 끊긴 자리 중 유지 시간이 지난 것: 예전처럼 나감 (판 중이면 접속 끊김 사망), 사람이 0명이면 방도 없앰
    void ExpireSeats(Room room)
    {
        foreach (var (id, seat) in room.seats.Entries())
        {
            if (seat.awayAt is not { } at || room.game.time - at < C.RECONNECT_GRACE_MS) continue;
            room.game.players.TryGetValue(id, out var p);
            room.game.Log($"  [끊김 만료] {(p != null ? p.name : JsNumber.ToJs(id))} {JsNumber.ToJs(C.RECONNECT_GRACE_MS / 1000)}초 안에 안 돌아옴");
            room.seats.Delete(id);
            room.game.RemovePlayer(id);
        }
        if (room.game.HumanCount() == 0) Close(room);
    }

    // 글자 메시지 하나 (JSON 이 아니면 버림 — index.js 와 같음)
    public void MessageText(Conn conn, string text)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(text); }
        catch (JsonException) { return; }
        using (doc) Message(conn, doc.RootElement);
    }

    public void Message(Conn conn, JsonElement msg)
    {
        // JS: !msg || typeof msg !== 'object' (배열도 object)
        if (msg.ValueKind is not (JsonValueKind.Object or JsonValueKind.Array) || !Allow(conn)) return;
        var room = conn.room;
        try
        {
            MessageIn(conn, msg);
        }
        catch (Exception err)
        {
            var t = Str(Field(msg, "type"));
            if (t.Length > 20) t = t[..20];
            if (room != null) Crash(room, $"메시지 {t}", err);
            else serverLog($"방 밖 메시지 오류 ({t}): {err.Message}");
        }
    }

    void MessageIn(Conn conn, JsonElement msg)
    {
        var type = AsString(Field(msg, "type")); // msg.type === '…' 비교는 글자일 때만 맞음
        // 핑: 보낸 시각 t 를 그대로 돌려줌 (왕복 시간은 화면이 잼) + 서버 틱 부하. 방 안·밖 둘 다
        if (type == "ping")
        {
            if (AsNumber(Field(msg, "t")) is { } t && double.IsFinite(t))
                Send(conn.ws, o => o.P("type", "pong").P("t", t).P("workMs", JsMath.Round(load.workMs * 10) / 10).P("behindMs", JsMath.Round(load.behindMs)).P("tickMs", 1000 / C.TICK_RATE));
            return;
        }
        if (conn.room == null)
        {
            if (type == "create") Create(conn, Field(msg, "name"), Field(msg, "nick"));
            else if (type == "practice") CreatePractice(conn, Field(msg, "nick"), Field(msg, "char"));
            else if (type == "tutorial") CreatePractice(conn, Field(msg, "nick"), Field(msg, "char"), true);
            else if (type == "join") Join(conn, Field(msg, "code"));
            else if (type == "rejoin") Rejoin(conn, Field(msg, "code"), Field(msg, "token"));
            return;
        }
        RoomMessage(conn.room, conn, msg, type);
    }

    // ---------- 방 만들기·들어가기·나가기 ----------
    string NewCode()
    {
        for (; ; )
        {
            var code = "";
            for (int i = 0; i < C.ROOM_CODE_LEN; i++) code += C.ROOM_CODE_CHARS[(int)Math.Floor(rng() * C.ROOM_CODE_CHARS.Length)];
            if (!rooms.Has(code)) return code;
        }
    }

    bool Full(Conn conn)
    {
        if (rooms.Count < C.ROOM_MAX) return false;
        Send(conn.ws, o => o.P("type", "joinError").P("reason", $"방이 이미 {JsNumber.ToJs(C.ROOM_MAX)}개라 더 못 만듭니다"));
        return true;
    }

    public Room? Create(Conn conn, JsonElement? rawName, JsonElement? rawNick)
    {
        if (Full(conn)) return null;
        var code = NewCode();
        var nick = CleanText(rawNick, C.NAME_MAX_LEN);
        var name = CleanText(rawName, C.ROOM_NAME_MAX_LEN);
        if (name == "") name = nick != "" ? $"{nick}의 방" : $"방 {code}";
        var @out = openLog(code);
        var game = new Game(m => @out.Log(m), characters: true, skyStairs: C.SKY_STAIRS_DEFAULT, countdownMs: countdownMs);
        game.SetMap(C.MAP_DEFAULT);
        var room = new Room { code = code, name = name, game = game, @out = @out };
        rooms.Set(code, room);
        @out.Log($"방 {code} 만듦: {name} (비공개)");
        serverLog($"방 {code} 만듦: {name} (방 {rooms.Count}개)");
        JoinCode(conn, code);
        return room;
    }

    // 연습 방: 비공개(목록에 안 뜸), 로그 파일 없음, 들어가면 바로 시작 + 허수아비 1개. 같은 코드로 친구가 들어오면 같이 연습
    // tutorial: 튜토리얼 방 (연습 위에 단계, 허수아비·지형은 단계가 놓음, 이것도 로그 파일 없음)
    public Room? CreatePractice(Conn conn, JsonElement? rawNick, JsonElement? @char, bool tutorial = false)
    {
        if (Full(conn)) return null;
        var code = NewCode();
        var nick = CleanText(rawNick, C.NAME_MAX_LEN);
        var kind = tutorial ? "튜토리얼" : "연습";
        var game = new Game(_ => { }, characters: true, skyStairs: false, countdownMs: 0); // 연습 판은 로그·stats 에서 뺌
        var room = new Room { code = code, name = nick != "" ? $"{nick}의 {kind}" : $"{kind} {code}", practice = true, tutorial = tutorial, game = game, @out = new NullLog() };
        rooms.Set(code, room);
        serverLog($"방 {code} 만듦: {kind} (방 {rooms.Count}개)");
        var player = game.AddPlayer(conn.id)!;
        conn.room = room;
        room.conns.Set(conn.id, conn);
        if (nick != "") game.SetNick(conn.id, nick);
        if (Truthy(@char)) game.SetChar(conn.id, Str(@char));
        if (tutorial) game.StartTutorial(conn.id);
        else
        {
            game.StartPractice();
            game.AddDummy(conn.id);
        }
        var token = NewSeat(room, conn);
        Send(conn.ws, o => o.P("type", "welcome").P("id", conn.id).P("slot", player.slot).P("name", player.name).Key("room").Raw(RoomInfo(room)).P("token", token));
        Send(conn.ws, game.Snapshot(true, o => o.Key("room").Raw(RoomInfo(room))));
        return room;
    }

    public bool Join(Conn conn, JsonElement? rawCode) => JoinCode(conn, StrOrEmpty(rawCode));

    public bool JoinCode(Conn conn, string rawCode)
    {
        var code = JsText.Trim(rawCode).ToUpperInvariant();
        var room = rooms.Get(code);
        if (room == null)
        {
            Send(conn.ws, o => o.P("type", "joinError").P("reason", $"{(code != "" ? code : "빈 코드")}: 그런 방이 없습니다 (코드 확인, 사람이 다 나가면 방이 없어짐)"));
            return false;
        }
        var player = room.game.AddPlayer(conn.id);
        if (player == null)
        {
            Send(conn.ws, o => o.P("type", "joinError").P("reason", $"방이 꽉 찼습니다 (최대 {JsNumber.ToJs(MaxPlayers())}명)"));
            return false;
        }
        conn.room = room;
        room.conns.Set(conn.id, conn);
        if (room.practice) room.game.PracticeJoin(conn.id); // 연습 방은 관전 말고 바로
        var token = NewSeat(room, conn);
        Send(conn.ws, o => o.P("type", "welcome").P("id", conn.id).P("slot", player.slot).P("name", player.name).Key("room").Raw(RoomInfo(room)).P("token", token));
        Send(conn.ws, room.game.Snapshot(true, o => o.Key("room").Raw(RoomInfo(room))));
        return true;
    }

    // reason: 방 밖으로 돌려보낼 때 보여줄 문구 (null = 연결이 끊김, 보낼 곳 없음)
    public void Leave(Conn conn, string? reason)
    {
        var room = conn.room;
        if (room == null) return;
        room.game.RemovePlayer(conn.id);
        room.conns.Delete(conn.id);
        room.seats.Delete(conn.id);
        conn.room = null;
        if (room.game.HumanCount() == 0) Close(room);
        if (reason != null)
        {
            Send(conn.ws, o => o.P("type", "left").P("reason", reason));
            SendList(conn);
        }
    }

    void Close(Room room)
    {
        room.game.RemoveAllBots();
        room.@out.Log($"방 {room.code} 닫음 (사람 0명)");
        room.@out.Close();
        rooms.Delete(room.code);
        serverLog($"방 {room.code} 닫음 (방 {rooms.Count}개)");
    }

    // ---------- 방 안 메시지 ----------
    void RoomMessage(Room room, Conn conn, JsonElement msg, string? type)
    {
        fault?.Invoke(room, "메시지");
        var game = room.game;
        int id = conn.id;
        bool host = game.IsHost(id);
        JsonElement? F(string k) => Field(msg, k);
        int Target() => AsId(ToNumber(F("target"))); // Number(msg.target)
        switch (type)
        {
            case "input":
                game.HandleInput(id, InputOf(msg));
                break;
            case "action":
                game.HandleAction(id, ActionOf(msg));
                break;
            case "leave":
                Leave(conn, "");
                break;
            case "setPublic": // 호스트: 공개 목록에 보이기 (판 사이에만, 연습 방은 안 됨)
                if (host && !room.practice && !game.InRound() && room.isPublic != Truthy(F("on")))
                {
                    room.isPublic = Truthy(F("on"));
                    room.@out.Log($"[호스트] 방 {(room.isPublic ? "공개" : "비공개")}");
                }
                break;
            case "addBot":
                if (host && game.AddBot() == null) room.@out.Log("봇 추가 거부: 방이 꽉 찼거나 판 진행 중");
                break;
            case "removeBot":
                if (host) game.RemoveBot();
                break;
            case "spectate": // 호스트: 관전 ↔ 참가 (판 사이에만)
                if (host) game.SetSpectator(Target(), Truthy(F("on")));
                break;
            case "kick":
            {
                // 호스트: 내보내기 (자기 자신은 안 됨, 판 사이에만). 사람은 방 밖 목록으로 돌려보내고, 봇은 바로 뺀다
                int target = Target();
                if (!host || target == id || !game.players.ContainsKey(target) || game.InRound()) break;
                room.@out.Log($"[호스트] {game.players[target].name} 내보냄");
                var tconn = room.conns.Get(target);
                if (tconn != null) Leave(tconn, "호스트가 방에서 내보냈습니다");
                else
                {
                    room.seats.Delete(target); // 끊긴 사람도 자리 없앰
                    game.RemovePlayer(target);
                }
                break;
            }
            case "setName":
                game.SetNick(id, StrOrEmpty(F("name")));
                break;
            case "setChar":
                game.SetChar(id, Str(F("char")));
                break;
            case "setColor": // 대기실 색 고르기 (PLAYER_PALETTE 번호, 쓰는 색·판 중이면 무시)
                game.SetColor(id, AsNumber(F("color")));
                break;
            case "teamMode":
                if (host) game.SetTeamMode(Truthy(F("on")));
                break;
            case "setTeam":
                if (host) game.SetTeam(Target(), Str(F("team")));
                break;
            case "shuffleTeams":
                if (host) game.ShuffleTeams();
                break;
            case "botLevel":
                if (host) game.SetBotLevel(Str(F("level")));
                break;
            case "setMap": // 연습 방은 누구나, 판 중에도 바로
                if (host || room.practice) game.SetMap(Str(F("map")));
                break;
            case "setMode":
                if (host) game.SetMode(Str(F("mode")));
                break;
            case "skyStairs":
                if (host) game.SetSkyStairs(Truthy(F("on")));
                break;
            case "hpMode": // 체력전 (대기실 옵션)
                if (host) game.SetHpMode(Truthy(F("on")));
                break;
            case "ghostDrop": // 유령 투하: 죽은 사람이 고른 칸에 1칸 블록 (생존 모드)
                game.GhostDrop(id, F("x"), F("y"));
                break;
            case "tutorialSkip": // 튜토리얼: 이 단계 넘기기
                if (room.tutorial && game.tutorial != null) game.tutorial.Skip();
                break;
            case "practiceSet": // 연습: 토글 (방 전체) · 내 피해 %
                if (room.practice) game.PracticeSet(id, Str(F("key")), F("value"));
                break;
            case "dummyAdd":
                if (room.practice) game.AddDummy(id);
                break;
            case "dummyRemove":
                if (room.practice) game.RemoveDummy(F("id") == null ? null : ToNumber(F("id")));
                break;
            case "dummySet":
                if (room.practice) game.SetDummyDamage(F("id") == null ? null : ToNumber(F("id")), F("damage"));
                break;
            case "start":
                if (host && !game.StartRound())
                    room.@out.Log($"시작 거부: 참가자 {game.Participants().Count}명 (최소 {JsNumber.ToJs(C.MIN_PLAYERS)}명, 관전자 제외)");
                break;
            default:
                break;
        }
    }

    // 받은 입력 메시지 → InputMsg (JS handleInput 이 보는 대로: 숫자만 숫자, jump 는 !!)
    static InputMsg InputOf(JsonElement msg) => new()
    {
        fwd = AsNumber(Field(msg, "fwd")),
        strafe = AsNumber(Field(msg, "strafe")),
        yaw = AsNumber(Field(msg, "yaw")),
        pitch = AsNumber(Field(msg, "pitch")),
        jump = Truthy(Field(msg, "jump")),
    };

    // 받은 행동 메시지 → ActionMsg (name 은 글자일 때만 맞음, n 은 숫자만 — Number.isInteger, dx·dy·dir 는 JS 처럼 Number() — `| 0`·`> 0`)
    static ActionMsg ActionOf(JsonElement msg) => new()
    {
        name = AsString(Field(msg, "name")) ?? "",
        n = AsNumber(Field(msg, "n")),
        dx = ToNumber(Field(msg, "dx")), // 없으면 NaN (`| 0` → 0, `> 0` → 거짓)
        dy = ToNumber(Field(msg, "dy")),
        dir = ToNumber(Field(msg, "dir")),
    };

    // ---------- 틱·보내기 ----------
    // 방마다 게임 틱은 병렬 (방끼리 공유 상태 없음: 게임·난수·로그가 방마다). 끊김 만료·방 닫기는 그 뒤 방 순서대로 이 스레드에서
    public void Tick(double dt)
    {
        var list = rooms.Values().ToList();
        var errs = new Exception?[list.Count];
        void One(int i)
        {
            try
            {
                fault?.Invoke(list[i], "틱");
                list[i].game.Tick(dt);
            }
            catch (Exception err)
            {
                errs[i] = err;
            }
        }
        if (parallel && list.Count > 1) Parallel.For(0, list.Count, One);
        else for (int i = 0; i < list.Count; i++) One(i);
        for (int i = 0; i < list.Count; i++)
        {
            var room = list[i];
            if (errs[i] == null)
            {
                try
                {
                    ExpireSeats(room);
                    continue;
                }
                catch (Exception err)
                {
                    errs[i] = err;
                }
            }
            Crash(room, "틱", errs[i]!);
        }
    }

    // 방마다 스냅샷 한 번 (이벤트는 보낼 때 비움)
    // 스냅샷 글자는 방마다 병렬로 만들고, 보내기는 방 순서대로 이 스레드에서
    public void Broadcast()
    {
        var list = rooms.Values().ToList();
        var payloads = new string?[list.Count];
        var errs = new Exception?[list.Count];
        void One(int i)
        {
            var room = list[i];
            try
            {
                fault?.Invoke(room, "스냅샷");
                payloads[i] = room.game.Snapshot(false, o =>
                {
                    o.Key("events").Arr();
                    foreach (var e in room.game.DrainEvents()) o.Raw(e);
                    o.EndArr();
                    o.Key("room").Raw(RoomInfo(room));
                });
            }
            catch (Exception err)
            {
                errs[i] = err;
            }
        }
        if (parallel && list.Count > 1) Parallel.For(0, list.Count, One);
        else for (int i = 0; i < list.Count; i++) One(i);
        for (int i = 0; i < list.Count; i++)
        {
            if (errs[i] != null)
            {
                Crash(list[i], "스냅샷", errs[i]!);
                continue;
            }
            foreach (var c in list[i].conns.Values()) if (c.ws.Open) c.ws.Send(payloads[i]!);
        }
    }

    string RoomInfo(Room room)
    {
        // link: 친구에게 줄 방 주소 (npm run online 의 터널 주소가 있을 때만, 없으면 필드 없음 → 화면이 지금 주소로)
        var o = new JsonOut();
        o.Obj().P("code", room.code).P("name", room.name).P("public", room.isPublic).P("practice", room.practice);
        if (room.tutorial) o.P("tutorial", true); // 튜토리얼 방만
        if (publicUrl != null) o.P("link", RoomLinkOf(publicUrl, room.code));
        return o.EndObj().ToString();
    }

    // 방 주소: 터널 주소 + ?room=코드 (tools/online.js 콘솔 안내와 같은 모양)
    public static string RoomLinkOf(string @base, string code) => $"{Regex.Replace(@base, "/+$", "")}/?room={code}";

    // npm run online 이 찾은 터널 주소 (https 만). 이미 있는 방 사람들에게도 다음 스냅샷부터 새 링크
    public bool SetPublicUrl(string? url)
    {
        var u = url == null ? null : Regex.Replace(url, "/+$", "");
        publicUrl = u != null && Regex.IsMatch(u, "^https://[a-z0-9.-]+$", RegexOptions.IgnoreCase) ? u : null;
        return publicUrl != null;
    }

    // 공개 방 목록 (방 밖 화면). 판 중인지는 안 보여줌 (이름·인원·맵·팀전·봇 난이도, 모드)
    string PublicList()
    {
        var o = new JsonOut();
        o.Obj().P("type", "rooms").Key("rooms").Arr();
        foreach (var r in rooms.Values())
        {
            if (!r.isPublic) continue;
            var ps = r.game.Players().ToList();
            o.Obj().P("code", r.code).P("name", r.name).P("humans", ps.Count(p => !p.isBot)).P("bots", ps.Count(p => p.isBot)).P("max", MaxPlayers())
                .P("map", r.game.mapChoice).P("mode", r.game.mode).P("teamMode", r.game.teamMode).P("botLevel", r.game.botLevel).P("skyStairs", r.game.skyStairs).P("hpMode", r.game.hpMode).EndObj();
        }
        o.EndArr().P("count", rooms.Count).P("max", C.ROOM_MAX).EndObj();
        return o.ToString();
    }

    void SendList(Conn conn) => Send(conn.ws, PublicList());

    // 방 밖에 있는 사람들에게 목록 (바뀌었을 때만)
    public void BroadcastList(bool force = false)
    {
        var text = PublicList();
        if (!force && text == lastList) return;
        lastList = text;
        foreach (var c in conns) if (c.room == null && c.ws.Open) c.ws.Send(text);
    }
}
