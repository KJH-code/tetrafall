using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 방 각본 (S6): tools/room-scenarios.mjs 의 각본을 C# Rooms 로 그대로 돌려, JS rooms.js 가 보낸 메시지·로그 (fixtures/protocol-rooms.json) 와
// 글자 하나까지 같은지. 각본 단계의 뜻은 room-scenarios.mjs 머리 주석
public class RoomScenarioTests
{
    const double TICK = 1000.0 / 30;

    sealed class FakeSocket(int i, List<(int, string)> sent, Action<string> onSend) : ISocket
    {
        public bool Open => true;

        public void Send(string text)
        {
            sent.Add((i, text));
            onSend(text);
        }
    }

    sealed class ListLog(string code, List<string> logs) : IRoomLog
    {
        public void Log(string msg) => logs.Add($"[{code}] {msg}");
        public void Close() => logs.Add($"[{code}] (닫음)");
    }

    public static IEnumerable<object[]> Names() => Fixtures.Load("protocol-rooms.json").EnumerateArray().Select((_, k) => new object[] { k });

    [Theory]
    [MemberData(nameof(Names))]
    public void Scenario_matches_js(int k)
    {
        var sc = Fixtures.Load("protocol-rooms.json")[k];
        var (sent, logs) = Run(sc);
        var name = sc.GetProperty("name").GetString();
        var wantLogs = sc.GetProperty("logs").EnumerateArray().Select(e => e.GetString()!).ToList();
        var wantSent = sc.GetProperty("sent").EnumerateArray().Select(e => (e[0].GetInt32(), e[1].GetString()!)).ToList();
        Assert.True(wantLogs.SequenceEqual(logs), $"{name}\n로그 다름: 처음 다른 줄 {FirstDiff(wantLogs, logs)}");
        for (int i = 0; i < Math.Min(sent.Count, wantSent.Count); i++)
            Assert.True(wantSent[i] == sent[i], $"{name}\n보낸 메시지 {i}번째 다름\nJS: {wantSent[i]}\nC#: {sent[i]}");
        Assert.Equal(wantSent.Count, sent.Count);
    }

    static string FirstDiff(List<string> a, List<string> b)
    {
        for (int i = 0; i < Math.Max(a.Count, b.Count); i++)
        {
            var x = i < a.Count ? a[i] : "(없음)";
            var y = i < b.Count ? b[i] : "(없음)";
            if (x != y) return $"{i}\nJS: {x}\nC#: {y}";
        }
        return "-";
    }

    // 각본 하나를 C# Rooms 로 (room-scenarios.mjs runJs 와 같은 순서)
    public static (List<(int, string)> sent, List<string> logs) Run(JsonElement sc)
    {
        var sent = new List<(int, string)>();
        var logs = new List<string>();
        int tk = 0;
        double clock = 0;
        var rooms = new Rooms(openLog: code => new ListLog(code, logs), serverLog: m => logs.Add($"[서버] {m}"), rng: new Mulberry32((uint)sc.GetProperty("seed").GetDouble()).AsFunc(), now: () => clock, newToken: () => $"token{++tk}");
        var conns = new List<Conn?> { null };
        var tokens = new List<string?> { null };
        var faults = new List<(string code, string where)>();
        rooms.fault = (room, where) =>
        {
            if (faults.Contains((room.code, where))) throw new Exception("펑");
        };
        foreach (var s in sc.GetProperty("steps").EnumerateArray())
        {
            string c = s.GetProperty("c").GetString()!;
            Conn Of(string key) => conns[s.GetProperty(key).GetInt32()]!;
            switch (c)
            {
                case "connect":
                {
                    int i = conns.Count;
                    tokens.Add(null);
                    var ws = new FakeSocket(i, sent, t =>
                    {
                        using var d = JsonDocument.Parse(t);
                        if (d.RootElement.GetProperty("type").GetString() == "welcome") tokens[i] = d.RootElement.GetProperty("token").GetString();
                    });
                    conns.Add(rooms.Connect(ws));
                    break;
                }
                case "msg":
                    rooms.Message(Of("i"), s.GetProperty("m"));
                    break;
                case "raw":
                    rooms.MessageText(Of("i"), s.GetProperty("text").GetString()!);
                    break;
                case "joinFirst":
                    rooms.JoinCode(Of("i"), conns[1]!.room!.code);
                    break;
                case "joinFirstOf":
                    rooms.JoinCode(Of("i"), Of("of").room!.code);
                    break;
                case "rejoinAs":
                {
                    var tok = tokens[s.GetProperty("of").GetInt32()];
                    var code = rooms.CodeOfToken(tok) ?? "NONE";
                    var o = new JsonOut();
                    o.Obj().P("type", "rejoin").P("code", s.TryGetProperty("lower", out _) ? $" {code.ToLowerInvariant()} " : code);
                    o.Key("token");
                    if (s.TryGetProperty("badToken", out var bad)) o.Raw(bad.GetRawText()); else o.Str(tok!);
                    using var d = JsonDocument.Parse(o.EndObj().ToString());
                    rooms.Message(Of("i"), d.RootElement);
                    break;
                }
                case "step":
                    rooms.Tick(TICK);
                    rooms.Broadcast();
                    break;
                case "ticks":
                    for (double t = 0; t < s.GetProperty("ms").GetDouble(); t += TICK) rooms.Tick(TICK);
                    break;
                case "disconnect":
                    rooms.Disconnect(Of("i"));
                    break;
                case "list":
                    rooms.BroadcastList(s.TryGetProperty("force", out var f) && f.GetBoolean());
                    break;
                case "clock":
                    clock += s.GetProperty("ms").GetDouble();
                    break;
                case "gameRng":
                    Of("i").room!.game.rng = new Mulberry32((uint)s.GetProperty("seed").GetDouble()).AsFunc();
                    break;
                case "fault":
                    faults.Add((Of("i").room!.code, s.GetProperty("where").GetString()!));
                    break;
                case "publicUrl":
                    rooms.SetPublicUrl(s.GetProperty("url").GetString());
                    break;
                default:
                    throw new InvalidOperationException($"모르는 단계 {c}");
            }
        }
        return (sent, logs.Select(CutError).ToList());
    }

    // '[코드] [오류] 틱: System.Exception: 펑 …' → '[코드] [오류] 틱' (스택은 언어마다 달라 비교 안 함, room-scenarios.mjs cutError 와 같음)
    static string CutError(string line)
    {
        var m = Regex.Match(line, @"^(\[[A-Z]+\] \[오류\] [^:]+):");
        return m.Success ? m.Groups[1].Value : line;
    }
}
