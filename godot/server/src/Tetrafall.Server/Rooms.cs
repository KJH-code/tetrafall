using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Server;

// 방 (server/rooms.js). 서버 하나에 게임 여러 개. 방 = 게임 + 들어온 접속 + 로그 파일. 메시지·응답 JSON 은 JS 서버와 글자 하나까지 같게
// (기존 JS 화면이 이 서버에 그대로 붙음). 모든 메서드는 게임 루프 스레드 하나에서만 불림 (Program.cs) → 잠금 없음 (JS 와 같은 한 줄 실행)
// 뼈대 (2026-10-31): 접속·목록·만들기·들어가기·나가기·핑·틱·보내기. 나머지 방 안 메시지·재접속·연습은 TODO (godot/PLAN.md S-Rooms)

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
    public readonly List<Conn> conns = new(); // 들어온 순서 (JS Map 과 같은 보내기 순서)
    public readonly Dictionary<int, Seat> seats = new();
    public IRoomLog @out = null!;
}

public sealed class Rooms
{
    readonly Func<string, IRoomLog> openLog;
    readonly Action<string> serverLog;
    readonly Func<double> rng;
    readonly double countdownMs;
    readonly Func<double> now;
    readonly Func<string> newToken;
    public readonly Dictionary<string, Room> rooms = new();
    readonly List<string> roomOrder = new(); // JS Map 순서 (목록·틱 순서)
    public readonly List<Conn> conns = new();
    int nextId = 1; // 플레이어 id 는 방이 달라도 겹치지 않게 서버 전체에서 셈
    string lastList = "";
    (double workMs, double behindMs) load = (0, 0);
    string? publicUrl;

    static double MaxPlayers() => Math.Min(C.MAX_PLAYERS, 8);

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

    IEnumerable<Room> RoomList() => roomOrder.Select(c => rooms[c]);

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

    // 이름 정리: 제어 문자 빼고 공백 하나로, max 글자까지 (rooms.js cleanText 와 같음: JS \s·trim 의 공백 목록)
    const string JsSpace = "\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff";
    static readonly Regex Ctrl = new("[\\u0000-\\u001f\\u007f]");
    static readonly Regex Spaces = new($"[{JsSpace}]+");
    static readonly char[] TrimChars = "\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff".ToCharArray();

    public static string CleanText(JsonElement? raw, double max)
    {
        string s = JsString(raw);
        if (s.Length > C.TEXT_RAW_MAX) s = s[..(int)C.TEXT_RAW_MAX];
        s = Ctrl.Replace(s, "");
        s = Spaces.Replace(s, " ").Trim(TrimChars);
        var cps = new List<string>();
        for (int i = 0; i < s.Length && cps.Count < max; i += char.IsSurrogatePair(s, i) ? 2 : 1) cps.Add(char.IsSurrogatePair(s, i) ? s.Substring(i, 2) : s[i].ToString());
        return string.Concat(cps);
    }

    // JS String(x ?? '')
    static string JsString(JsonElement? e)
    {
        if (e is not { } v) return "";
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() ?? "",
            JsonValueKind.Null or JsonValueKind.Undefined => "",
            JsonValueKind.Number => JsNumber.ToJs(v.GetDouble()),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Object => "[object Object]",
            _ => string.Join(",", v.EnumerateArray().Select(x => x.ValueKind is JsonValueKind.Null ? "" : JsString(x))),
        };
    }

    static JsonElement? Field(JsonElement msg, string name) => msg.TryGetProperty(name, out var v) ? v : null;

    public void NoteTick(double workMs, double behindMs) => load = (Math.Max(workMs, load.workMs * C.NET_LOAD_DECAY), behindMs);

    // ---------- 접속 ----------
    public Conn Connect(ISocket ws)
    {
        var conn = new Conn { id = nextId++, ws = ws, bucket = C.NET_MSG_BURST, bucketAt = now() };
        conns.Add(conn);
        SendList(conn);
        return conn;
    }

    public void Disconnect(Conn conn)
    {
        var room = conn.room;
        try
        {
            if (room != null) Leave(conn, null); // TODO(S-Rooms): 재접속 — 자리 유지 (setAway·봇 대리) 는 판 묶음이 옮겨진 뒤
        }
        catch (Exception err)
        {
            if (room != null) Crash(room, "접속 끊김", err);
        }
        conns.Remove(conn);
    }

    // 방 하나에서 난 예외: 그 방만 로그 남기고 닫음, 사람들은 방 밖 목록으로. 다른 방은 계속
    public void Crash(Room room, string where, Exception err)
    {
        if (!rooms.ContainsKey(room.code)) return;
        try { room.@out.Log($"[오류] {where}: {err}"); } catch { }
        serverLog($"방 {room.code} 오류로 닫음 ({where}: {err.Message})");
        rooms.Remove(room.code);
        roomOrder.Remove(room.code);
        foreach (var c in room.conns)
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
        if (msg.ValueKind != JsonValueKind.Object || !Allow(conn)) return;
        var room = conn.room;
        string type = JsString(Field(msg, "type"));
        try
        {
            MessageIn(conn, msg, type);
        }
        catch (Exception err)
        {
            string t = type.Length > 20 ? type[..20] : type;
            if (room != null) Crash(room, $"메시지 {t}", err);
            else serverLog($"방 밖 메시지 오류 ({t}): {err.Message}");
        }
    }

    void MessageIn(Conn conn, JsonElement msg, string type)
    {
        // 핑: 보낸 시각 t 를 그대로 돌려줌 + 서버 틱 부하. 방 안·밖 둘 다
        if (type == "ping")
        {
            if (Field(msg, "t") is { ValueKind: JsonValueKind.Number } t && double.IsFinite(t.GetDouble()))
                Send(conn.ws, o => o.P("type", "pong").P("t", t.GetDouble()).P("workMs", JsMath.Round(load.workMs * 10) / 10).P("behindMs", JsMath.Round(load.behindMs)).P("tickMs", 1000 / C.TICK_RATE));
            return;
        }
        if (conn.room == null)
        {
            if (type == "create") Create(conn, Field(msg, "name"), Field(msg, "nick"));
            else if (type == "join") Join(conn, Field(msg, "code"));
            // TODO(S-Rooms): practice·tutorial·rejoin
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
            if (!rooms.ContainsKey(code)) return code;
        }
    }

    public Room? Create(Conn conn, JsonElement? rawName, JsonElement? rawNick)
    {
        if (rooms.Count >= C.ROOM_MAX)
        {
            Send(conn.ws, o => o.P("type", "joinError").P("reason", $"방이 이미 {JsNumber.ToJs(C.ROOM_MAX)}개라 더 못 만듭니다"));
            return null;
        }
        var code = NewCode();
        var nick = CleanText(rawNick, C.NAME_MAX_LEN);
        var name = CleanText(rawName, C.ROOM_NAME_MAX_LEN);
        if (name == "") name = nick != "" ? $"{nick}의 방" : $"방 {code}";
        var @out = openLog(code);
        var game = new Game(m => @out.Log(m), characters: true, skyStairs: C.SKY_STAIRS_DEFAULT, countdownMs: countdownMs);
        game.SetMap(C.MAP_DEFAULT);
        var room = new Room { code = code, name = name, game = game, @out = @out };
        rooms[code] = room;
        roomOrder.Add(code);
        @out.Log($"방 {code} 만듦: {name} (비공개)");
        serverLog($"방 {code} 만듦: {name} (방 {rooms.Count}개)");
        JoinCode(conn, code);
        return room;
    }

    public bool Join(Conn conn, JsonElement? rawCode) => JoinCode(conn, JsString(rawCode));

    public bool JoinCode(Conn conn, string rawCode)
    {
        var code = rawCode.Trim(TrimChars).ToUpperInvariant();
        if (!rooms.TryGetValue(code, out var room))
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
        room.conns.Add(conn);
        var token = NewSeat(room, conn);
        Send(conn.ws, o => o.P("type", "welcome").P("id", conn.id).P("slot", player.slot).P("name", player.name).Key("room").Raw(RoomInfo(room)).P("token", token));
        Send(conn.ws, room.game.Snapshot(true, o => o.Key("room").Raw(RoomInfo(room))));
        return true;
    }

    string NewSeat(Room room, Conn conn)
    {
        var token = newToken();
        room.seats[conn.id] = new Seat { token = token, conn = conn };
        return token;
    }

    // reason: 방 밖으로 돌려보낼 때 보여줄 문구 (null = 연결이 끊김, 보낼 곳 없음)
    public void Leave(Conn conn, string? reason)
    {
        var room = conn.room;
        if (room == null) return;
        room.game.RemovePlayer(conn.id);
        room.conns.Remove(conn);
        room.seats.Remove(conn.id);
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
        rooms.Remove(room.code);
        roomOrder.Remove(room.code);
        serverLog($"방 {room.code} 닫음 (방 {rooms.Count}개)");
    }

    // ---------- 방 안 메시지 ----------
    void RoomMessage(Room room, Conn conn, JsonElement msg, string type)
    {
        switch (type)
        {
            case "leave":
                Leave(conn, "");
                break;
            // TODO(S-Rooms): input·action·setPublic·addBot·removeBot·spectate·kick·setName·setChar·setColor·teamMode·setTeam·shuffleTeams·
            //   botLevel·setMap·setMode·skyStairs·hpMode·ghostDrop·tutorialSkip·practiceSet·dummyAdd·dummyRemove·dummySet·start
            default:
                break;
        }
    }

    // ---------- 틱·보내기 ----------
    public void Tick(double dt)
    {
        foreach (var room in RoomList().ToList())
        {
            try
            {
                room.game.Tick(dt);
                // TODO(S-Rooms): expireSeats (재접속 자리 유지 시간)
            }
            catch (Exception err)
            {
                Crash(room, "틱", err);
            }
        }
    }

    // 방마다 스냅샷 한 번 (이벤트는 보낼 때 비움)
    public void Broadcast()
    {
        foreach (var room in RoomList().ToList())
        {
            string payload;
            try
            {
                var events = room.game.DrainEvents();
                payload = room.game.Snapshot(false, o =>
                {
                    o.Key("events").Arr();
                    foreach (var e in events) o.Raw(e);
                    o.EndArr();
                    o.Key("room").Raw(RoomInfo(room));
                });
            }
            catch (Exception err)
            {
                Crash(room, "스냅샷", err);
                continue;
            }
            foreach (var c in room.conns) if (c.ws.Open) c.ws.Send(payload);
        }
    }

    string RoomInfo(Room room)
    {
        var o = new JsonOut();
        o.Obj().P("code", room.code).P("name", room.name).P("public", room.isPublic).P("practice", room.practice);
        if (room.tutorial) o.P("tutorial", true);
        if (publicUrl != null) o.P("link", $"{publicUrl.TrimEnd('/')}/?room={room.code}");
        return o.EndObj().ToString();
    }

    public bool SetPublicUrl(string? url)
    {
        var u = url?.TrimEnd('/');
        publicUrl = u != null && Regex.IsMatch(u, "^https://[a-z0-9.-]+$", RegexOptions.IgnoreCase) ? u : null;
        return publicUrl != null;
    }

    // 공개 방 목록 (방 밖 화면)
    string PublicList()
    {
        var o = new JsonOut();
        o.Obj().P("type", "rooms").Key("rooms").Arr();
        foreach (var r in RoomList())
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
