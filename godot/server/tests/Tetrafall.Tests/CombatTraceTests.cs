using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// 전투 각본 판 (S3): tools/trace-scripted.mjs 의 캐릭터 각본을 '전투만 도는 틱' (판 흐름 S2·아이템 S4 없이) 으로 돌려
// 틱마다 줄 ({t, logs, snap}) 이 JS 와 글자까지 같은지 (fixtures/combat-trace.json 의 sha256). 갈라지면 C# 기록을 임시 파일에 쓰고 경로를 알려 줌
// → node godot/server/tools/trace-scripted.mjs <캐릭터> js.jsonl --combat 와 trace-diff.mjs 로 처음 갈라진 곳
public class CombatTraceTests
{
    const double TICK = 1000.0 / 30;

    // 옮긴 캐릭터 (각본이 끝까지 같아야 함). 나머지는 옮기는 묶음에서 여기에 더함
    static readonly HashSet<string> Ported = new() { "tank", "ninja" };

    // trace-scripted.mjs combatTick 과 같은 순서
    public static void CombatTick(Game g, double dtMs)
    {
        g.FlushLogs();
        g.time += dtMs;
        if (g.phase != "playing") return;
        double dt = dtMs / 1000;
        double remaining = dt;
        while (remaining > 0)
        {
            double h = Math.Min(remaining, C.MAX_STEP_DT);
            foreach (var p in g.Players()) if (g.OnField(p)) g.IntegratePlayer(p, h);
            remaining -= h;
        }
        foreach (var p in g.Players()) if (p.grounded && p.alive && g.OnField(p)) p.lastGround = g.GroundKind(p);
        g.UpdateCombat();
        if (g.shells.Count > 0) g.UpdateShells(dt);
        if (g.notes.Count > 0) g.UpdateNotes(dt);
    }

    // 각본 하나를 C# 로 (runScript 와 같은 순서). onLine(틱 줄 JSON 글자)
    public static void Run(JsonElement sc, Action<string> onLine)
    {
        var logs = new List<string>();
        var g = new Game(l => logs.Add(l), characters: true, skyStairs: false, countdownMs: 1); // 전투만: trace-scripted.mjs 와 같이 카운트다운 1ms + 바로 playing
        g.rng = new Mulberry32((uint)sc.GetProperty("seed").GetDouble()).AsFunc();
        var chars = sc.GetProperty("chars").EnumerateArray().Select(e => e.GetString()!).ToArray();
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.SetChar(1, chars[0]);
        g.SetChar(2, chars[1]);
        g.SetMap("flat");
        g.SetMode(sc.GetProperty("mode").GetString()!);
        if (!g.StartRound()) throw new InvalidOperationException("시작 못 함");
        g.phase = "playing";
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        onLine(Scenarios.TraceLine(0, logs, g.Snapshot(true)));
        logs.Clear();
        var steps = sc.GetProperty("steps").EnumerateArray().ToList();
        int k = 0, total = sc.GetProperty("ticks").GetInt32();
        for (int ticks = 0; ticks < total && g.phase != "over";)
        {
            for (; k < steps.Count && steps[k].GetProperty("t").GetInt32() == ticks; k++)
            {
                var st = steps[k];
                int who = st.GetProperty("who").GetInt32();
                var p = g.GetPlayer(who);
                var o = g.GetPlayer(who == 1 ? 2 : 1);
                if (st.TryGetProperty("input", out var inp))
                {
                    bool face = inp.TryGetProperty("face", out var f) && f.GetBoolean();
                    g.HandleInput(who, new InputMsg
                    {
                        fwd = inp.GetProperty("fwd").GetDouble(),
                        strafe = inp.GetProperty("strafe").GetDouble(),
                        jump = inp.GetProperty("jump").GetBoolean(),
                        pitch = inp.GetProperty("pitch").GetDouble(),
                        yaw = face && p != null && o != null ? JsMath.Atan2(o.y - p.y, o.x - p.x) : inp.TryGetProperty("yaw", out var y) ? y.GetDouble() : 0,
                    });
                }
                else if (st.TryGetProperty("action", out var act)) g.HandleAction(who, new ActionMsg { name = act.GetProperty("name").GetString()! });
                else if (st.TryGetProperty("set", out var set) && p != null && set.TryGetProperty("ult", out var u) && u.GetString() == "max") p.ult = g.UltMax(p);
                else if (st.TryGetProperty("set", out var set2) && set2.TryGetProperty("reset", out _))
                {
                    foreach (var (id, x) in new[] { (1, g.W / 2.0 - 1), (2, g.W / 2.0 + 0.2) })
                    {
                        var q = g.GetPlayer(id)!;
                        (q.x, q.y, q.z, q.vz, q.kbx, q.kby, q.grounded) = (x, g.D / 2.0, 0, 0, 0, 0, true);
                    }
                }
            }
            CombatTick(g, TICK);
            ticks++;
            var events = g.DrainEvents();
            string snap = g.Snapshot(ticks % 300 == 0, w =>
            {
                w.Key("events").Arr();
                foreach (var e in events) w.Raw(e);
                w.EndArr();
            });
            onLine(Scenarios.TraceLine(ticks, logs, snap));
            logs.Clear();
        }
    }

    static string Sha16(string s) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s))).ToLowerInvariant()[..16];

    public static IEnumerable<object[]> Names() => Fixtures.Load("combat-trace.json").EnumerateArray().Select(e => new object[] { e.GetProperty("name").GetString()! });

    [Theory]
    [MemberData(nameof(Names))]
    public void Combat_script_matches_js(string name)
    {
        var sc = Fixtures.Load("combat-trace.json").EnumerateArray().First(e => e.GetProperty("name").GetString() == name);
        var want = sc.GetProperty("hashes").EnumerateArray().Select(e => e.GetString()!).ToList();
        var lines = new List<string>();
        Exception? err = null;
        try
        {
            Run(sc, lines.Add);
        }
        catch (NotImplementedException e)
        {
            err = e;
        }
        int same = 0;
        while (same < Math.Min(lines.Count, want.Count) && Sha16(lines[same]) == want[same]) same++;
        if (!Ported.Contains(name)) return; // 아직 안 옮긴 캐릭터: 돌아가는 데까지만 (끝까지 같을 필요 없음)
        if (same == want.Count && lines.Count == want.Count && err == null) return;
        var path = Path.Combine(Path.GetTempPath(), $"cs-combat-{name}.jsonl");
        File.WriteAllLines(path, lines);
        Assert.Fail($"{name}: 틱 {same} 부터 다름 (JS {want.Count}줄, C# {lines.Count}줄{(err != null ? $", 멈춤: {err.Message}" : "")}) → C# 기록 {path}");
    }
}
