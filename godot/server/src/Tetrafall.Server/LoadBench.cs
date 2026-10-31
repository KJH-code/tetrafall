using System.Diagnostics;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Server;

// 서버 부하 (C# 쪽, tools/load.mjs 와 같은 일): 진짜 Rooms 를 가짜 소켓으로 — 방 4개 × 8명 (사람 1 + 봇 7), 모드 생존·킬·마스터·생존,
// 서버 틱 루프 한 번 (rooms.Tick + Broadcast) 의 시간을 틱마다 재서 평균·중앙값·99%·최대 (앞 WARM 틱은 데우기라 뺌). 실행: dotnet Tetrafall.Server.dll load [틱 수=3600]
public static class LoadBench
{
    sealed class Sink : ISocket
    {
        public long bytes;
        public bool Open => true;
        public void Send(string text) => bytes += text.Length;
    }

    static JsonElement Msg(object o) => JsonSerializer.SerializeToElement(o);

    public static int Run(string[] args)
    {
        int TICKS = args.Length > 1 ? int.Parse(args[1]) : 3600;
        const int WARM = 300;
        string[] MODES = { "survival", "kills", "master", "survival" };
        double TICK = 1000 / C.TICK_RATE;
        var rooms = new Rooms(rng: new Mulberry32(1).AsFunc(), countdownMs: 0);
        var sinks = new List<Sink>();
        var list = new List<(Conn conn, Room room)>();
        for (int r = 0; r < MODES.Length; r++)
        {
            var ws = new Sink();
            sinks.Add(ws);
            var conn = rooms.Connect(ws);
            rooms.Message(conn, Msg(new { type = "create", nick = $"P{r}" }));
            var room = conn.room!;
            room.game.rng = new Mulberry32((uint)(100 + r)).AsFunc();
            for (int i = 0; i < 7; i++) rooms.Message(conn, Msg(new { type = "addBot" }));
            rooms.Message(conn, Msg(new { type = "setMode", mode = MODES[r] }));
            rooms.Message(conn, Msg(new { type = "start" }));
            list.Add((conn, room));
        }
        var times = new double[TICKS];
        int rounds = 0;
        var sw = new Stopwatch();
        for (int t = 0; t < TICKS; t++)
        {
            sw.Restart();
            rooms.Tick(TICK);
            rooms.Broadcast();
            times[t] = sw.Elapsed.TotalMilliseconds;
            foreach (var (conn, room) in list)
            {
                if (room.game.phase != "over") continue;
                rounds++;
                rooms.Message(conn, Msg(new { type = "start" }));
            }
        }
        var steady = times.Skip(WARM).OrderBy(x => x).ToArray();
        double R3(double x) => Math.Round(x * 1000) / 1000;
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            server = "cs",
            rooms = list.Count,
            players = list.Select(x => x.room.game.players.Count),
            ticks = TICKS,
            warm = WARM,
            rounds,
            avgMs = R3(steady.Average()),
            p50Ms = R3(steady[(int)(steady.Length * 0.5)]),
            p99Ms = R3(steady[(int)(steady.Length * 0.99)]),
            maxMs = R3(steady[^1]),
            maxWarmMs = R3(times.Take(WARM).Max()),
            budgetMs = R3(TICK),
            sentMB = R3(sinks.Sum(s => s.bytes) / 1e6),
        }));
        return 0;
    }
}
