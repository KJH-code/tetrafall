using System.Diagnostics;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Server;

// 서버 부하 (C# 쪽, tools/load.mjs 와 같은 일): 진짜 Rooms 를 가짜 소켓으로 — 방 4개 × 8명 (사람 1 + 봇 7), 모드 생존·킬·마스터·생존,
// 서버 틱 루프 한 번 (rooms.Tick + Broadcast) 의 시간을 틱마다 재서 평균·중앙값·99%·최대 (앞 WARM 틱은 데우기라 뺌). 실행: dotnet Tetrafall.Server.dll load [틱 수=3600] [--serial (방을 한 스레드에서 차례로)] [--prof (구간 표·느린 틱)]
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
        bool prof = args.Contains("--prof"), serial = args.Contains("--serial");
        args = args.Where(a => !a.StartsWith("--")).ToArray();
        int TICKS = args.Length > 1 ? int.Parse(args[1]) : 3600;
        const int WARM = 300;
        string[] MODES = { "survival", "kills", "master", "survival" };
        double TICK = 1000 / C.TICK_RATE;
        var rooms = new Rooms(rng: new Mulberry32(1).AsFunc(), countdownMs: 0) { parallel = !serial };
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
            if (prof) room.game.prof = new Profiler();
            list.Add((conn, room));
        }
        var secs = new Dictionary<string, double[]>(); // 구간 → 틱마다 (방 합)
        var worst = new List<(int t, double ms, string detail)>();
        int gc0 = GC.CollectionCount(0), gc1 = GC.CollectionCount(1), gc2 = GC.CollectionCount(2);
        var times = new double[TICKS];
        int rounds = 0;
        var sw = new Stopwatch();
        for (int t = 0; t < TICKS; t++)
        {
            sw.Restart();
            int g0 = GC.CollectionCount(0);
            rooms.Tick(TICK);
            double tickMs = sw.Elapsed.TotalMilliseconds;
            rooms.Broadcast();
            times[t] = sw.Elapsed.TotalMilliseconds;
            if (prof)
            {
                var parts = new List<string>();
                foreach (var (conn, room) in list)
                {
                    var cur = room.game.prof!.cur;
                    foreach (var (k, v) in cur)
                    {
                        if (!secs.TryGetValue(k, out var arr)) secs[k] = arr = new double[TICKS];
                        arr[t] += v;
                    }
                    double sum = cur.Values.Sum();
                    if (sum > 2) parts.Add($"{room.game.mode}:" + string.Join(",", cur.Where(kv => kv.Value > 0.5).Select(kv => $"{kv.Key} {kv.Value:F1}")));
                    cur.Clear();
                }
                if (!secs.TryGetValue("snapshot", out var sa)) secs["snapshot"] = sa = new double[TICKS];
                sa[t] = times[t] - tickMs;
                if (sa[t] > 2) parts.Add($"snapshot {sa[t]:F1}");
                if (GC.CollectionCount(0) != g0) parts.Add("GC");
                worst.Add((t, times[t], string.Join(" | ", parts)));
            }
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
            server = serial ? "cs 차례로" : "cs 병렬",
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
            over16 = steady.Count(x => x > 16),
            over33 = steady.Count(x => x > TICK),
            budgetMs = R3(TICK),
            sentMB = R3(sinks.Sum(s => s.bytes) / 1e6),
        }));
        if (prof)
        {
            Console.WriteLine($"GC 횟수 gen0 {GC.CollectionCount(0) - gc0} · gen1 {GC.CollectionCount(1) - gc1} · gen2 {GC.CollectionCount(2) - gc2}");
            Console.WriteLine("구간 (방 4개 합, 데우기 뺌)  평균ms  99%ms  최대ms");
            foreach (var (k, arr) in secs)
            {
                var st = arr.Skip(WARM).OrderBy(x => x).ToArray();
                Console.WriteLine($"{k,-12} {st.Average(),8:F3} {st[(int)(st.Length * 0.99)],7:F2} {st[^1],7:F2}");
            }
            Console.WriteLine("느린 틱 10개:");
            foreach (var w in worst.OrderByDescending(x => x.ms).Take(10)) Console.WriteLine($"  t={w.t} {w.ms:F1}ms  {w.detail}");
        }
        return 0;
    }
}
