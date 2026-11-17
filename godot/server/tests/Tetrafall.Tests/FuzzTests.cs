using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Sim;

namespace Tetrafall.Tests;

// C# 자체 퍼즈 그물 (JS 정답 자료 없음): 무작위 입력·메시지에도 예외·NaN 이 없고 방이 안 닫힘.
// 해시는 고정하지 않고 불변식만 봄. 난수는 전부 Mulberry32 시드 고정 (시드마다 따로 → 병렬이어도 같은 결과)
public class FuzzTests
{
    const int RULE_SEEDS = 42;       // 규칙 퍼즈 판 수 (모드 3 × 인원 7 = 21 조합을 두 번씩 — 클래스 전체 30초 안)
    const double RULE_EVENTS = 0.5;  // 규칙 퍼즈: 돌발 이벤트를 켜는 판 비율
    const int RULE_EVENT_SEEDS_MIN = 6; // 강제 이벤트가 한 번이라도 걸린 판이 이만큼은 있어야 함 (지금 시드로는 42판 중 13판)
    const double RULE_EVENT_FORCE = 0.002; // 돌발 이벤트 판: 틱마다 이벤트 하나를 강제로 시작할 확률 (약 17초에 한 번 — 진행 중인 것 위에 겹쳐 시작도)
    const int ROOM_SEEDS = 12;       // 방 메시지 퍼즈 시드 수
    const int ROOM_TICKS = 1500;     // 시드마다 틱 수 (50초)
    const int HUGE_YAW_TICKS = 30;   // 큰 각도 입력 뒤 돌리는 틱 수
    const string CLOSED = "오류로 닫음";
    const string OUTSIDE = "방 밖 메시지 오류"; // 방 밖 메시지 (create·join·rejoin …) 에서 난 예외 — 방은 안 닫히지만 이것도 0건
    static readonly double TICK = 1000 / C.TICK_RATE;

    sealed class Sock : ISocket
    {
        public string? token; // 마지막 welcome 의 자리 토큰 (rejoin 퍼즈용)
        public bool Open => true;
        public void Send(string text)
        {
            if (!text.StartsWith("{\"type\":\"welcome\"")) return;
            var m = Regex.Match(text, "\"token\":\"([^\"]*)\"");
            if (m.Success) token = m.Groups[1].Value;
        }
    }

    static string Where(Exception e) => e.StackTrace?.Split('\n').FirstOrDefault(l => l.Contains("Tetrafall.Core") || l.Contains("Tetrafall.Server"))?.Trim() ?? "?";

    // 아주 큰 yaw 한 번에 방 전체가 닫히던 버그 (JsMath 가 던짐 → 틱 예외 → Crash). 이동 입력이 있어야 yaw 로 삼각함수를 부름 (fwd 0 이면 예전에도 안 터짐)
    [Fact]
    public void Huge_yaw_input_does_not_close_room()
    {
        var logs = new List<string>();
        double clock = 0;
        int tok = 0;
        var rooms = new Rooms(serverLog: logs.Add, rng: new Mulberry32(1).AsFunc(), now: () => clock, newToken: () => $"t{++tok}");
        var conn = rooms.Connect(new Sock());
        rooms.MessageText(conn, "{\"type\":\"create\",\"nick\":\"큰각도\"}");
        var room = conn.room!;
        room.game.rng = new Mulberry32(2).AsFunc();
        rooms.MessageText(conn, "{\"type\":\"addBot\"}");
        rooms.MessageText(conn, "{\"type\":\"start\"}");
        Assert.Equal("playing", room.game.phase);
        var me = room.game.GetPlayer(conn.id)!;

        rooms.MessageText(conn, "{\"type\":\"input\",\"yaw\":1.25,\"fwd\":1}");
        Assert.Equal(1.25, me.yaw);
        // 경계: INPUT_YAW_MAX 까지는 받고, 넘으면 무시 (예전 yaw 유지)
        rooms.MessageText(conn, $"{{\"type\":\"input\",\"yaw\":{JsNumber.ToJs(-C.INPUT_YAW_MAX)},\"fwd\":1}}");
        Assert.Equal(-C.INPUT_YAW_MAX, me.yaw);
        rooms.MessageText(conn, "{\"type\":\"input\",\"yaw\":1.25,\"fwd\":1}");

        foreach (var yaw in new[] { "2e6", "1e300", "-1e300", "1000001" })
        {
            rooms.MessageText(conn, $"{{\"type\":\"input\",\"yaw\":{yaw},\"fwd\":1}}");
            for (int t = 0; t < HUGE_YAW_TICKS; t++)
            {
                clock += TICK;
                rooms.Tick(TICK);
                rooms.Broadcast();
            }
            Assert.True(!logs.Any(l => l.Contains(CLOSED)), $"yaw {yaw}: 방이 닫힘 — {string.Join(" / ", logs.Where(l => l.Contains(CLOSED)))}");
            Assert.True(rooms.Has(room.code) && conn.room == room, $"yaw {yaw}: 방이 없어짐");
            Assert.True(me.yaw == 1.25, $"yaw {yaw}: 무시 안 됨 (yaw {me.yaw})");
            Assert.Equal(1, me.input.fwd); // 큰 yaw 만 버리고 이동 입력은 받음
        }
    }

    // JsMath 정밀 구간 (|x| ≤ 약 1.6e6) 밖: V8 과 비트 일치는 아니지만 던지지 않고 [-1, 1] 안의 값
    [Fact]
    public void JsMath_huge_angle_does_not_throw()
    {
        foreach (var x in new[] { 2e6, -3e7, 1e20, 1e300, -1e300, double.MaxValue })
        {
            double s = JsMath.Sin(x), c = JsMath.Cos(x);
            Assert.True(double.IsFinite(s) && s >= -1 && s <= 1, $"sin({x}) = {s}");
            Assert.True(double.IsFinite(c) && c >= -1 && c <= 1, $"cos({x}) = {c}");
            Assert.True(Math.Abs(s * s + c * c - 1) < 1e-12, $"sin²+cos² ({x}) = {s * s + c * c}"); // 같은 줄인 각을 씀
        }
        // 조금 넘는 각은 실제 값과도 가까움 (2π 로 한 번 줄이는 오차 ≈ |x| × 1e-16)
        foreach (var x in new[] { 2e6, -3e7 })
        {
            Assert.True(Math.Abs(JsMath.Sin(x) - Math.Sin(x)) < 1e-6, $"sin({x})");
            Assert.True(Math.Abs(JsMath.Cos(x) - Math.Cos(x)) < 1e-6, $"cos({x})");
        }
        // 무한·NaN 은 예전 그대로 NaN
        Assert.True(double.IsNaN(JsMath.Sin(double.PositiveInfinity)) && double.IsNaN(JsMath.Cos(double.NegativeInfinity)) && double.IsNaN(JsMath.Sin(double.NaN)));
    }

    // ---------- 규칙 퍼즈 ----------
    static readonly string[] MODES = { "survival", "master", "kills" };
    static readonly string?[] ACTIONS = { "jump", "dash", "push", "fire", "skill", "ult", "pieceMove", "rotate", "drop", "emote", "zzz", "", null };
    static readonly double[] WEIRD = { double.NaN, double.PositiveInfinity, double.NegativeInfinity, 1e300, -1e300, -1e308, 2e6, -3e7, 1e9, -7, -0.0, 0.5 };

    // 한 시드 = 한 구성 (모드·인원은 시드로 골고루, 나머지는 무작위) 으로 판 하나. 문제가 있으면 한 줄, 없으면 null
    // forced: 강제로 시작한 돌발 이벤트 수 (그물이 그 경로를 실제로 지나는지 확인용)
    static string? RuleFuzz(int seed, out int forced)
    {
        forced = 0;
        var r = new Mulberry32((uint)seed * 2654435761u);
        double R() => r.Next();
        int I(int n) => (int)Math.Floor(R() * n);
        double Weird() => WEIRD[I(WEIRD.Length)];
        string mode = MODES[seed % MODES.Length];
        int n = (int)C.MIN_PLAYERS + seed / MODES.Length % ((int)C.MAX_PLAYERS - (int)C.MIN_PLAYERS + 1);
        bool hp = R() < 0.4, team = R() < 0.3, sky = R() < 0.5, events = R() < RULE_EVENTS;
        string map = Maps.MAP_IDS[I(Maps.MAP_IDS.Length)];
        string tag = $"시드 {seed} {mode} {n}명 체력전 {hp} 팀전 {team} 하늘 계단 {sky} 돌발 이벤트 {events} {map}";
        string step = "준비";
        int tick = 0;
        try
        {
            var g = new Game(null, characters: true, skyStairs: sky);
            g.rng = new Mulberry32((uint)seed).AsFunc();
            g.SetMap(map);
            g.SetMode(mode);
            if (hp) g.SetHpMode(true);
            if (events && !g.SetRoundEvents(true)) return $"{tag}: 돌발 이벤트 켜기 거절";
            var humans = new List<int>();
            int nh = 1 + I(Math.Min(4, n));
            for (int i = 0; i < n; i++)
            {
                if (i < nh) humans.Add(g.AddPlayer(100 + i)!.id);
                else g.AddBot();
            }
            foreach (var p in g.players.Values.ToList()) g.SetChar(p.id, C.CHARACTERS[I(C.CHARACTERS.Length)]);
            if (team) g.SetTeamMode(true);
            step = "시작";
            if (!g.StartRound()) return $"{tag}: 판 시작 거절";
            double t0 = g.time;
            while (g.InRound() && g.time - t0 < BotSim.SIM_ROUND_CAP_MS)
            {
                step = "입력";
                foreach (var id in humans)
                {
                    // 사람마다 매 틱 입력 하나 + 행동 하나
                    g.HandleInput(id, new InputMsg
                    {
                        fwd = R() < 0.03 ? Weird() : R() < 0.02 ? null : R() * 2 - 1,
                        strafe = R() < 0.03 ? Weird() : R() * 2 - 1,
                        yaw = R() < 0.03 ? Weird() : R() < 0.01 ? (R() - 0.5) * 2 * C.INPUT_YAW_MAX : R() * 2 * Math.PI,
                        pitch = R() < 0.03 ? Weird() : R() * 3 - 1.5,
                        jump = R() < 0.2,
                    });
                    g.HandleAction(id, new ActionMsg
                    {
                        name = ACTIONS[I(ACTIONS.Length)],
                        n = R() < 0.5 ? I(9) - 1.0 : R() < 0.5 ? Weird() : "x",
                        dx = R() < 0.1 ? Weird() : I(3) - 1,
                        dy = R() < 0.1 ? Weird() : I(3) - 1,
                        dir = R() < 0.1 ? Weird() : I(3) - 1,
                    });
                    // 유령 투하: 죽은 사람만 되지만 산 사람이 보내도 거절돼야 함
                    if (R() < (g.GetPlayer(id)?.alive == false ? 0.05 : 0.005)) g.GhostDrop(id, R() < 0.1 ? Weird() : R() * 24 - 2, R() < 0.1 ? Weird() : R() * 24 - 2);
                    if (R() < 0.0005) g.SetAway(id, R() < 0.5);
                }
                if (humans.Count > 1 && R() < 0.0003)
                {
                    step = "나감";
                    g.RemovePlayer(humans[^1]);
                    humans.RemoveAt(humans.Count - 1);
                }
                // 돌발 이벤트가 도는 판 (마스터는 켜도 안 돎): 가끔 폭우·돌풍·보급·저중력·빙판을 강제로 시작 (제때 오는 것 말고도)
                if (g.RoundEventsRun() && g.phase == "playing" && R() < RULE_EVENT_FORCE)
                {
                    step = "돌발 이벤트";
                    var (wx, wy) = C.EVENT_WIND_DIRS[I(C.EVENT_WIND_DIRS.Length)];
                    g.StartRoundEvent(C.EVENT_KINDS[I(C.EVENT_KINDS.Length)], new XY(wx, wy));
                    forced++;
                }
                step = "틱";
                g.Tick(TICK);
                tick++;
                step = "검사";
                foreach (var p in g.players.Values)
                {
                    if (!p.alive) continue;
                    if (!(double.IsFinite(p.x) && double.IsFinite(p.y) && double.IsFinite(p.z) && double.IsFinite(p.vz) && double.IsFinite(p.kbx) && double.IsFinite(p.kby) && double.IsFinite(p.damage) && double.IsFinite(p.yaw)))
                        return $"{tag} 틱 {tick}: {p.name} ({p.@char}) 숫자가 유한하지 않음 x {p.x} y {p.y} z {p.z} vz {p.vz} kb {p.kbx},{p.kby} 피해 {p.damage} yaw {p.yaw}";
                }
                step = "스냅샷";
                var snap = g.Snapshot(tick % 150 == 0, o =>
                {
                    o.Key("events").Arr();
                    foreach (var e in g.DrainEvents()) o.Raw(e);
                    o.EndArr();
                });
                if (snap.Contains("NaN") || snap.Contains("Infinity")) return $"{tag} 틱 {tick}: 스냅샷에 NaN·Infinity";
            }
            if (g.InRound()) return $"{tag}: 판이 {BotSim.SIM_ROUND_CAP_MS / 1000}초 안에 안 끝남 (산 사람 {g.players.Values.Count(p => p.alive)}명)";
            return null;
        }
        catch (Exception e)
        {
            return $"{tag} 틱 {tick} [{step}]: 예외 {e.GetType().Name}: {e.Message} @ {Where(e)}";
        }
    }

    [Fact]
    public void Random_inputs_keep_game_finite_and_running()
    {
        var bad = new string?[RULE_SEEDS];
        var forced = new int[RULE_SEEDS];
        Parallel.For(0, RULE_SEEDS, i => bad[i] = RuleFuzz(i + 1, out forced[i]));
        var list = bad.Where(b => b != null).Order(StringComparer.Ordinal).ToList();
        Assert.True(list.Count == 0, $"규칙 퍼즈 문제 {list.Count}건:\n{string.Join("\n", list)}");
        // 돌발 이벤트 경로 (폭우·돌풍·보급·저중력·빙판) 가 그물 안에 있음: 여러 판에서 강제로 시작됨
        Assert.True(forced.Count(f => f > 0) >= RULE_EVENT_SEEDS_MIN, $"돌발 이벤트를 강제로 시작한 판 {forced.Count(f => f > 0)}개 (이벤트 수 {string.Join(",", forced)})");
    }

    // ---------- 방 메시지 퍼즈 ----------
    // Rooms.cs 의 모든 case "…" + 방 밖 메시지 (create·join·rejoin·practice·tutorial·ping) + 모르는 종류. 판 안 메시지를 더 자주
    static readonly string[] MSG_TYPES =
    {
        "input", "input", "input", "input", "input", "input", "action", "action", "action", "action", "action", "action", "action", "action",
        "leave", "setPublic", "addBot", "addBot", "removeBot", "spectate", "kick", "setName", "setChar", "setColor", "teamMode", "setTeam", "shuffleTeams",
        "botLevel", "setMap", "setMode", "skyStairs", "hpMode", "roundEvents", "fieldItems", "ghostDrop", "ghostDrop", "tutorialSkip", "practiceSet", "dummyAdd", "dummyRemove", "dummySet",
        "start", "start", "start", "start", "ping", "create", "create", "join", "join", "rejoin", "practice", "tutorial", "zzz",
    };
    static readonly string[] MSG_FIELDS =
    {
        "fwd", "strafe", "yaw", "pitch", "jump", "name", "n", "dx", "dy", "dir", "on", "target", "team", "level", "map", "mode", "x", "y", "key", "value",
        "char", "color", "code", "token", "nick", "id", "damage", "t", "type",
    };
    static readonly string LONG = "\"" + new string('가', 5000) + "\"";
    static readonly string[] MSG_VALUES =
    {
        "1", "0", "-1", "2", "3", "3.7", "-0.5", "1e5", "-1e5", "2e6", "1e300", "-1e300", "1e999", "-1e999", "99999999999", "1e-320",
        "\"\"", "\"NaN\"", "\"Infinity\"", "\"-Infinity\"", "\"1e999\"", "\"7\"", "\"red\"", "\"blue\"", "\"tank\"", "\"bard\"", "\"builder\"", "\"hook\"",
        "\"kills\"", "\"master\"", "\"survival\"", "\"practice\"", "\"hard\"", "\"easy\"", "\"pillars\"", "\"random\"", "\"fortress\"",
        "\"skill\"", "\"ult\"", "\"dash\"", "\"push\"", "\"jump\"", "\"fire\"", "\"drop\"", "\"pieceMove\"", "\"rotate\"", "\"emote\"",
        "\"myDamage\"", "\"cooldowns\"", "\"__proto__\"", "\"ABCD\"", "true", "false", "null", "[]", "{}", "[1,2]", "[[]]", "{\"a\":1}", "{\"type\":\"start\"}", LONG,
    };
    // JSON 이 아니거나 객체가 아닌 메시지
    static readonly string[] MSG_JUNK = { "[1,2", "\"str\"", "null", "3", "true", "[]", "[1,{\"type\":\"start\"}]", "{}", "{\"type\":null}", "{\"type\":[\"input\"]}", "{\"type\":{}}", "" };

    static List<string> RoomFuzz(int seed)
    {
        var r = new Mulberry32((uint)seed * 2246822519u);
        double R() => r.Next();
        int I(int n) => (int)Math.Floor(R() * n);
        var logs = new List<string>();
        var bad = new List<string>();
        double clock = 0;
        int tok = 0;
        uint roomSeed = (uint)seed * 1000;
        var rooms = new Rooms(serverLog: logs.Add, rng: new Mulberry32((uint)seed).AsFunc(), now: () => clock, newToken: () => $"s{seed}t{++tok}");
        var socks = new List<Sock>();
        var conns = new List<Conn>();
        var seeded = new HashSet<Room>();
        string code = "", token = "";
        void Add()
        {
            socks.Add(new Sock());
            conns.Add(rooms.Connect(socks[^1]));
        }
        // 새로 생긴 방의 게임 난수도 시드 고정, 살아 있는 방 코드·자리 토큰을 기억 (join·rejoin 이 실제로 되게)
        void Note()
        {
            for (int i = 0; i < conns.Count; i++)
            {
                if (conns[i].room is { } room)
                {
                    code = room.code;
                    if (seeded.Add(room)) room.game.rng = new Mulberry32(++roomSeed).AsFunc();
                }
                if (socks[i].token != null) token = socks[i].token!;
            }
        }
        void Say(Conn c, string text)
        {
            rooms.MessageText(c, text);
            Note();
        }
        int tick = 0;
        try
        {
            for (int i = 0; i < 4; i++) Add();
            Say(conns[0], "{\"type\":\"create\",\"name\":\"퍼즈\"}");
            for (int i = 1; i < 3; i++) Say(conns[i], $"{{\"type\":\"join\",\"code\":\"{code}\"}}");
            for (int i = 0; i < 3; i++) Say(conns[0], "{\"type\":\"addBot\"}");
            for (; tick < ROOM_TICKS; tick++)
            {
                clock += TICK;
                for (int ci = 0; ci < conns.Count; ci++)
                {
                    var c = conns[ci];
                    if (R() < 0.25)
                    {
                        var parts = new Dictionary<string, string> { ["type"] = $"\"{MSG_TYPES[I(MSG_TYPES.Length)]}\"" };
                        int nf = I(6);
                        for (int k = 0; k < nf; k++)
                        {
                            var f = MSG_FIELDS[I(MSG_FIELDS.Length)];
                            var v = MSG_VALUES[I(MSG_VALUES.Length)];
                            if (f == "type" && R() < 0.9) continue; // 가끔만 type 을 이상한 값으로
                            if (f == "code" && R() < 0.7) v = $"\"{code}\"";
                            if (f == "token" && R() < 0.7) v = $"\"{token}\"";
                            if (f == "target" && R() < 0.5) v = JsNumber.ToJs(conns[I(conns.Count)].id);
                            parts[f] = v;
                        }
                        var text = "{" + string.Join(",", parts.Select(p => $"\"{p.Key}\":{p.Value}")) + "}";
                        if (R() < 0.2)
                        {
                            using var doc = JsonDocument.Parse(text);
                            rooms.Message(c, doc.RootElement);
                            Note();
                        }
                        else Say(c, text);
                    }
                    if (R() < 0.005) Say(c, MSG_JUNK[I(MSG_JUNK.Length)]);
                }
                // 가끔 끊고 새 창으로 (자리는 남음 → rejoin 토큰으로 돌아올 수 있음)
                if (R() < 0.002)
                {
                    int i = I(conns.Count);
                    rooms.Disconnect(conns[i]);
                    socks[i] = new Sock();
                    conns[i] = rooms.Connect(socks[i]);
                }
                rooms.Tick(TICK);
                rooms.Broadcast();
            }
        }
        catch (Exception e)
        {
            bad.Add($"시드 {seed} 틱 {tick}: 방 밖으로 샌 예외 {e.GetType().Name}: {e.Message} @ {Where(e)}");
        }
        foreach (var l in logs.Where(l => l.Contains(CLOSED) || l.Contains(OUTSIDE))) bad.Add($"시드 {seed}: {l}");
        return bad;
    }

    [Fact]
    public void Random_room_messages_never_crash_room()
    {
        var bad = new List<string>[ROOM_SEEDS];
        Parallel.For(0, ROOM_SEEDS, i => bad[i] = RoomFuzz(i + 1));
        var list = bad.SelectMany(b => b).Order(StringComparer.Ordinal).ToList();
        Assert.True(list.Count == 0, $"방 메시지 퍼즈: {CLOSED}·{OUTSIDE} {list.Count}건:\n{string.Join("\n", list)}");
    }
}
