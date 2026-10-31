using System.Security.Cryptography;
using System.Text;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Trace;

// tools/game-hash.js SCENARIOS·runScenario 와 같은 판 (같은 순서·시드). trace.mjs 와 같은 JSONL, game-hash 와 같은 sha256
public sealed record Scenario(string name, int n, string mode, bool team, bool characters, bool sky, string map, uint seed, bool away = false);

// 각본 입력 판 (tools/scripted.mjs SCRIPTED 와 같은 순서): 사람 n 명, 캐릭터 끔
public sealed record ScriptedScenario(string name, int n, string mode, bool team, bool sky, bool hp, string map, uint seed);

public static class Scenarios
{
    public static readonly List<ScriptedScenario> SCRIPTED = new()
    {
        new("각본 2명 생존 하늘", 2, "survival", false, true, false, "flat", 7001),
        new("각본 4명 생존", 4, "survival", false, false, false, "pyramid", 7002),
        new("각본 4명 생존 팀 하늘", 4, "survival", true, true, false, "stairs", 7003),
        new("각본 3명 블록 마스터", 3, "master", false, false, false, "bowl", 7004),
        new("각본 4명 킬 점수전 하늘", 4, "kills", false, true, false, "spiral", 7005),
        new("각본 8명 생존 하늘", 8, "survival", false, true, false, "fortress", 7006),
        new("각본 4명 킬 점수전 팀 체력전", 4, "kills", true, false, true, "pillars", 7007),
        new("각본 6명 블록 마스터 하늘", 6, "master", false, true, false, "stairs", 7008),
    };

    // tools/scripted.mjs setupScripted·driveScripted 그대로
    public static (int ticks, string phase) RunScripted(ScriptedScenario sc, Action<int, List<string>, string> onLine, int maxTicks = int.MaxValue)
    {
        double TICK = 1000 / C.TICK_RATE;
        var logs = new List<string>();
        var g = new Game(line => logs.Add(line), characters: false, skyStairs: sc.sky, countdownMs: 1500, hpMode: sc.hp);
        g.rng = new Mulberry32(sc.seed).AsFunc();
        for (int i = 1; i <= sc.n; i++) g.AddPlayer(i);
        if (sc.team) g.SetTeamMode(true);
        if (sc.mode != "survival") g.SetMode(sc.mode);
        g.SetMap(sc.map);
        if (!g.StartRound()) throw new InvalidOperationException("시작 못 함");
        var rr = new Mulberry32(sc.seed ^ 0x9e3779b9);
        onLine(0, logs, g.Snapshot(true));
        logs = new List<string>();
        double t = 0;
        int ticks = 0;
        while (t < 120000 && g.phase != "over" && ticks < maxTicks)
        {
            DriveScripted(g, rr, ticks);
            g.Tick(TICK);
            t += TICK;
            ticks++;
            var events = g.DrainEvents();
            string snap = g.Snapshot(ticks % 300 == 0, o =>
            {
                o.Key("events").Arr();
                foreach (var e in events) o.Raw(e);
                o.EndArr();
            });
            onLine(ticks, logs, snap);
            logs = new List<string>();
        }
        return (ticks, g.phase);
    }

    static void DriveScripted(Game g, Mulberry32 rr, int ticks)
    {
        foreach (var p in g.Players().ToList())
        {
            if (ticks % 15 == 0)
            {
                bool edge = Math.Min(Math.Min(p.x, p.y), Math.Min(g.W - p.x, g.D - p.y)) < 2; // 가장자리 근처면 가운데로
                double yaw = edge ? JsMath.Atan2(g.D / 2.0 - p.y, g.W / 2.0 - p.x) : (rr.Next() - 0.5) * 2 * Math.PI;
                double fwd = rr.Next() < 0.6 ? 1 : 0;
                double strafe = Math.Floor(rr.Next() * 3) - 1;
                bool jump = rr.Next() < 0.2;
                g.HandleInput(p.id, new InputMsg { fwd = fwd, strafe = strafe, jump = jump, yaw = yaw, pitch = 0 });
            }
            if (rr.Next() < 0.03) g.HandleAction(p.id, new ActionMsg { name = "jump" });
            if (rr.Next() < 0.004) g.HandleAction(p.id, new ActionMsg { name = "emote", n = Math.Floor(rr.Next() * 5) });
            if (g.IsControlling(p))
            {
                double r = rr.Next();
                if (r < 0.1)
                {
                    double dx = Math.Floor(rr.Next() * 3) - 1, dy = Math.Floor(rr.Next() * 3) - 1;
                    g.HandleAction(p.id, new ActionMsg { name = "pieceMove", dx = dx, dy = dy });
                }
                else if (r < 0.13) g.HandleAction(p.id, new ActionMsg { name = "rotate", dir = rr.Next() < 0.5 ? 1 : -1 });
                else if (r < 0.16) g.HandleAction(p.id, new ActionMsg { name = "drop" });
            }
            if (g.GhostCd(p) == 0 && rr.Next() < 0.05)
            {
                double gx = rr.Next() * g.W, gy = rr.Next() * g.D;
                g.GhostDrop(p.id, gx, gy);
            }
        }
    }

    public static readonly List<Scenario> ALL = Build();

    static List<Scenario> Build()
    {
        var list = new List<Scenario>();
        int k = 0;
        foreach (var n in new[] { 2, 4, 8 })
        {
            foreach (var (mode, team) in new[] { ("survival", false), ("survival", true), ("master", false), ("kills", false), ("kills", true) })
            {
                if (team && n < 4) continue;
                foreach (var characters in new[] { true, false })
                {
                    foreach (var sky in new[] { true, false })
                    {
                        if (!characters && (mode != "survival" || n == 8)) continue; // 예전 규칙 판은 조금만
                        list.Add(new Scenario($"{n}명 {mode}{(team ? " 팀" : "")}{(characters ? " 캐릭터" : "")}{(sky ? " 하늘" : "")}", n, mode, team, characters, sky, Maps.MAP_IDS[k % Maps.MAP_IDS.Length], (uint)(1000 + k)));
                        k++;
                    }
                }
            }
        }
        list.Add(new Scenario("4명 끊긴 사람 봇 대리", 4, "survival", false, true, true, "pyramid", 9002, away: true));
        list.Add(new Scenario("연습 허수아비", 1, "practice", false, true, false, "flat", 9001));
        return list;
    }

    public static Scenario Find(string key) =>
        int.TryParse(key, out var i) ? ALL[i] : ALL.FirstOrDefault(s => s.name.Contains(key)) ?? throw new ArgumentException($"시나리오 없음: {key}");

    const double CAP_MS = 120000;

    // 판 하나를 돌림. onLine(틱, 로그, 스냅샷 글자) 은 틱마다 (t=0 = 판 시작 직후 격자 포함 스냅샷, events 키 없음)
    // maxTicks: 이 틱까지만 (trace 일부만 비교할 때)
    public static (int ticks, string phase) Run(Scenario sc, Action<int, List<string>, string> onLine, int maxTicks = int.MaxValue)
    {
        double TICK = 1000 / C.TICK_RATE;
        var rnd = new Mulberry32(sc.seed);
        var logs = new List<string>();
        var g = new Game(line => logs.Add(line), characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500);
        g.rng = rnd.AsFunc();
        if (sc.mode == "practice")
        {
            g.AddPlayer(1);
            g.SetChar(1, "ninja");
            throw new NotImplementedException("연습 시나리오 (S4: startPractice·addDummy)");
        }
        if (sc.away) g.AddPlayer(1);
        for (int i = sc.away ? 1 : 0; i < sc.n; i++)
        {
            var b = g.AddBot()!;
            if (sc.characters) g.SetChar(b.id, C.CHARACTERS[(int)Math.Floor(rnd.Next() * C.CHARACTERS.Length)]);
        }
        if (sc.team) g.SetTeamMode(true);
        if (sc.mode != "survival") g.SetMode(sc.mode);
        g.SetMap(sc.map);
        if (!g.StartRound()) throw new InvalidOperationException($"{sc.name}: 시작 못 함");
        onLine(0, logs, g.Snapshot(true));
        logs = new List<string>();
        double t = 0;
        int ticks = 0;
        double cap = sc.mode == "practice" ? 20000 : CAP_MS;
        while (t < cap && g.phase != "over" && ticks < maxTicks)
        {
            if (sc.away && ticks == 0) g.SetAway(1, true);
            if (sc.away && ticks == 900) g.SetAway(1, false);
            g.Tick(TICK);
            t += TICK;
            ticks++;
            var events = g.DrainEvents();
            // JS 는 스냅샷을 먼저 만든 뒤 events 를 뽑음 (snapshot 은 이벤트를 안 만듦 → 순서 같음)
            string snap = g.Snapshot(ticks % 300 == 0, o =>
            {
                o.Key("events").Arr();
                foreach (var e in events) o.Raw(e);
                o.EndArr();
            });
            onLine(ticks, logs, snap);
            logs = new List<string>();
        }
        return (ticks, g.phase);
    }

    // trace.mjs 한 줄: {"t":틱,"logs":[...],"snap":"스냅샷 글자"}
    public static string TraceLine(int t, List<string> logs, string snap)
    {
        var o = new JsonOut();
        o.Obj().P("t", t).Key("logs").Arr();
        foreach (var l in logs) o.Str(l);
        o.EndArr().P("snap", snap).EndObj();
        return o.ToString();
    }

    // tools/game-hash.js runScenario 와 같은 해시: 로그 줄마다 "L줄\n", 틱마다 스냅샷 (t=0 은 안 넣음)
    public static string Hash(Scenario sc, out int ticks, out string phase)
    {
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        (ticks, phase) = Run(sc, (t, logs, snap) =>
        {
            foreach (var l in logs) h.AppendData(Encoding.UTF8.GetBytes($"L{l}\n"));
            if (t > 0) h.AppendData(Encoding.UTF8.GetBytes(snap));
        });
        return Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant();
    }
}
