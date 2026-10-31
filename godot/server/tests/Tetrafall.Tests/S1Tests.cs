using System.Security.Cryptography;
using System.Text;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// S1 바닥: 시작 지형·물리·판 시작이 JS 와 같은지 (정답 자료 = tools/fixtures.mjs), 표 생성기, 물리 단위 테스트 (test/game.test.js 물리 부분)
public class S1Tests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    [Fact]
    public void Maps_match_JS_mapColumns_for_all_maps_and_sizes()
    {
        int n = 0;
        foreach (var kv in Fixtures.Load("maps.json").EnumerateObject())
        {
            var parts = kv.Name.Split(':');
            var want = kv.Value.EnumerateArray().Select(c => (c[0].GetInt32(), c[1].GetInt32(), c[2].GetInt32())).ToList();
            var got = Maps.MapColumns(parts[0], int.Parse(parts[1]), int.Parse(parts[1]));
            Assert.True(want.SequenceEqual(got), $"{kv.Name}: 칸 {got.Count} (JS {want.Count})");
            n++;
        }
        Assert.Equal(70, n);
    }

    // 물리만 (판 흐름·블록 없이) 무작위 입력·넉백 300틱: 10틱마다 위치·속도·착지·밟은 칸이 비트까지 같음
    [Fact]
    public void Physics_matches_JS_bits()
    {
        int pk = 0;
        foreach (var run in Fixtures.Load("physics.json").EnumerateArray())
        {
            string map = run.GetProperty("map").GetString()!;
            int n = run.GetProperty("n").GetInt32();
            var rr = new Mulberry32((uint)(500 + pk++));
            var g = new Game(countdownMs: 1);
            g.rng = rr.AsFunc();
            for (int i = 1; i <= n; i++) g.AddPlayer(i);
            g.SetMap(map);
            g.StartRound();
            g.phase = "playing";
            var frames = run.GetProperty("frames").EnumerateArray().ToList();
            int f = 0;
            for (int k = 0; k < 300; k++)
            {
                foreach (var p in g.Players())
                {
                    if (k % 10 == 0)
                    {
                        double fwd = Math.Floor(rr.Next() * 3) - 1, strafe = Math.Floor(rr.Next() * 3) - 1;
                        bool jump = rr.Next() < 0.3;
                        double yaw = (rr.Next() - 0.5) * 8;
                        g.HandleInput(p.id, new InputMsg { fwd = fwd, strafe = strafe, jump = jump, yaw = yaw, pitch = 0 });
                    }
                    if (rr.Next() < 0.04) g.HandleAction(p.id, new ActionMsg { name = "jump" });
                    if (rr.Next() < 0.02)
                    {
                        p.kbx = (rr.Next() - 0.5) * 30;
                        p.kby = (rr.Next() - 0.5) * 30;
                        p.vz = rr.Next() * 6;
                        p.stunUntil = g.time + 400;
                        p.wallBounced = false;
                        p.grounded = false;
                    }
                }
                PhysicsTick(g);
                if (k % 10 != 9) continue;
                var want = frames[f++].EnumerateArray().ToList();
                int j = 0;
                foreach (var p in g.Players())
                {
                    var w = want[j++].EnumerateArray().ToList();
                    var got = new object?[] { p.x, p.y, p.z, p.vz, p.kbx, p.kby, p.grounded, p.lastGround, p.airJumps };
                    for (int q = 0; q < 6; q++) Assert.True(BitConverter.DoubleToInt64Bits(w[q].GetDouble()) == BitConverter.DoubleToInt64Bits((double)got[q]!), $"{map} {n}인 틱 {k} P{p.id} 칸 {q}: {got[q]} (JS {w[q].GetDouble()})");
                    Assert.Equal(w[6].GetBoolean(), p.grounded);
                    Assert.Equal(w[7].ValueKind == System.Text.Json.JsonValueKind.Null ? null : w[7].GetString(), p.lastGround);
                    Assert.Equal(w[8].GetDouble(), p.airJumps);
                }
            }
            Assert.Equal(run.GetProperty("events").GetInt32(), g.DrainEvents().Count);
        }
        Assert.Equal(21, pk);
    }

    // game.js tick 의 물리 부분 (판 흐름·블록·전투는 S2·S3 — 그 전까지 물리 테스트는 이것으로)
    static void PhysicsTick(Game g)
    {
        g.FlushLogs();
        g.time += TICK;
        double remaining = TICK / 1000;
        while (remaining > 0)
        {
            double h = Math.Min(remaining, C.MAX_STEP_DT);
            foreach (var p in g.Players()) if (g.OnField(p)) g.IntegratePlayer(p, h);
            remaining -= h;
        }
        foreach (var p in g.Players()) if (p.grounded && p.alive && g.OnField(p)) p.lastGround = g.GroundKind(p);
    }

    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) PhysicsTick(g);
    }

    static (Game g, Player p1, Player p2) Setup()
    {
        var g = new Game(countdownMs: 1);
        g.rng = () => 0.5;
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.StartRound();
        g.phase = "playing";
        return (g, g.players[1], g.players[2]);
    }

    [Fact]
    public void Trace_first_line_matches_JS_for_33_scenarios()
    {
        foreach (var row in Fixtures.Load("trace-t0.json").EnumerateArray())
        {
            int i = row[0].GetInt32();
            string? line = null;
            Scenarios.Run(Scenarios.ALL[i], (t, logs, snap) => line ??= Scenarios.TraceLine(t, logs, snap), maxTicks: 0);
            string sha = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(line!))).ToLowerInvariant();
            Assert.True(sha == row[1].GetString(), $"시나리오 {i} {Scenarios.ALL[i].name}: t=0 이 JS 와 다름 (trace-diff 로 확인)");
        }
    }

    [Fact]
    public void Config_tables_generated()
    {
        Assert.Equal(10, C.KILLS_TARGET_BY_COUNT["hp"]["8"]);
        Assert.Equal(6, GameUtil.ByCount(C.KILLS_TARGET_BY_COUNT["hp"], 3));
        Assert.Equal(9, GameUtil.ByCount(C.KILLS_TARGET_BY_COUNT["hp"], 7)); // 7 칸 없음 → 6 칸
        Assert.Equal(2, GameUtil.ByCount(C.KILLS_TARGET_BY_COUNT["off"], 1)); // 가장 작은 칸
        Assert.Equal(8, C.BASIC_ATTACKS.Count);
        Assert.Equal("주먹", C.BASIC_ATTACKS["tank"].chain[0].name);
        Assert.True(C.BASIC_ATTACKS["tank"].air[0].finish);
        Assert.Null(C.BASIC_ATTACKS["tank"].chain[0].range);
        Assert.True(C.BASIC_ATTACKS["bard"].metal!.air[0].dive);
        Assert.Equal(0.25, C.BOT_LEVELS["easy"]["DODGE_CHANCE"]);
        Assert.Equal("move", C.TUTORIAL_STEPS[0].id);
        Assert.Equal("knockback", (string)C.TUTORIAL_STEPS.First(s => s.id == "item").items![0][2]);
        Assert.Equal(8, C.SPAWN_POINTS.Length);
        Assert.Equal(2.5, C.spawnPointsFor(14, 14)[0].x);
    }

    [Fact]
    public void Stands_on_block()
    {
        var (g, p1, _) = Setup();
        g.grid[g.Idx(2, 2, 0)] = 1;
        g.grid[g.Idx(2, 2, 1)] = 1;
        p1.x = 2.5;
        p1.y = 2.5;
        p1.z = 5;
        Run(g, 2000);
        Assert.True(Math.Abs(p1.z - 2) < 1e-6, $"z={p1.z}");
        Assert.True(p1.grounded);
    }

    [Fact]
    public void Jump_climbs_one_step_not_two()
    {
        var (g, p1, _) = Setup();
        for (int y = 0; y < C.GRID_D; y++)
        {
            for (int x = 3; x < C.GRID_W; x++) g.grid[g.Idx(x, y, 0)] = 1;
            g.grid[g.Idx(5, y, 1)] = 1;
            g.grid[g.Idx(5, y, 2)] = 1;
        }
        p1.x = 2.5;
        p1.y = 2.5;
        bool landedOnStep = false;
        double maxX = 0;
        for (int i = 0; i < 120; i++)
        {
            g.HandleInput(1, new InputMsg { fwd = 1, strafe = 0, jump = true, yaw = 0, pitch = 0 });
            PhysicsTick(g);
            if (p1.grounded && Math.Abs(p1.z - 1) < 1e-6 && p1.x > 3) landedOnStep = true;
            maxX = Math.Max(maxX, p1.x);
        }
        Assert.True(landedOnStep, "1칸 턱 위에 착지해야 함");
        Assert.True(maxX <= 5 - C.PLAYER_HALF + 1e-6, $"2칸 벽에 막혀야 함: maxX={maxX}");
    }

    // test/game.test.js wallJumpRun: x=5 에 벽, 꾹 누르며 걸어감, pulses 면 0.25초에 공중에서 다시 누름
    static (double maxX, int airJumps) WallJumpRun(int height, bool pulses)
    {
        var (g, p1, _) = Setup();
        for (int y = 0; y < C.GRID_D; y++) for (int z = 0; z < height; z++) g.grid[g.Idx(5, y, z)] = 1;
        p1.x = 3.5;
        p1.y = 2.5;
        double maxX = 0;
        int airJumps = 0;
        g.DrainEvents();
        for (double t = 0; t < 1500; t += TICK)
        {
            g.HandleInput(1, new InputMsg { fwd = 1, strafe = 0, jump = true, yaw = 0, pitch = 0 });
            if (pulses && Math.Abs(t - 250) < TICK / 2) g.HandleAction(1, new ActionMsg { name = "jump" });
            PhysicsTick(g);
            maxX = Math.Max(maxX, p1.x);
            airJumps += g.DrainEvents().Count(e => e.Contains("\"airJump\""));
        }
        return (maxX, airJumps);
    }

    [Fact]
    public void Double_jump_clears_two_not_three()
    {
        var twice = WallJumpRun(2, true);
        Assert.True(twice.maxX > 6, $"2단 점프로 2칸 벽: maxX={twice.maxX}");
        Assert.Equal(1, twice.airJumps);
        var held = WallJumpRun(2, false);
        Assert.True(held.maxX <= 5 - C.PLAYER_HALF + 1e-6, $"꾹 누르면 못 넘음: maxX={held.maxX}");
        Assert.Equal(0, held.airJumps);
        var tall = WallJumpRun(3, true);
        Assert.True(tall.maxX <= 5 - C.PLAYER_HALF + 1e-6, $"3칸 벽은 못 넘음: maxX={tall.maxX}");
    }

    [Fact]
    public void Double_jump_once_per_air_refills_on_ground()
    {
        var (g, p1, _) = Setup();
        void Press()
        {
            g.HandleAction(1, new ActionMsg { name = "jump" });
            PhysicsTick(g);
        }
        g.HandleInput(1, new InputMsg { fwd = 0, strafe = 0, jump = true, yaw = 0, pitch = 0 });
        PhysicsTick(g);
        g.HandleInput(1, new InputMsg { fwd = 0, strafe = 0, jump = false, yaw = 0, pitch = 0 });
        Press();
        Assert.Equal(0, p1.airJumps);
        double vz = p1.vz;
        Press();
        Assert.True(p1.vz < vz, "세 번째 점프는 안 됨");
        Run(g, 1500);
        Assert.True(p1.grounded);
        Assert.Equal(C.AIR_JUMPS, p1.airJumps);
        Assert.Single(g.DrainEvents(), e => e.Contains("\"airJump\""));
    }

    [Fact]
    public void Ghost_passes_walls_sideways_and_ejects_on_end()
    {
        var (g, p1, _) = Setup();
        for (int y = 0; y < C.GRID_D; y++) for (int z = 0; z < 3; z++) g.grid[g.Idx(4, y, z)] = 1;
        p1.x = 3.5;
        p1.y = 5;
        p1.ghostUntil = g.time + C.GHOST_MS; // givePower 'ghost' (S4) 와 같은 값
        for (double t = 0; t < 800; t += TICK)
        {
            g.HandleInput(1, new InputMsg { fwd = 1, strafe = 0, jump = false, yaw = 0, pitch = 0 });
            PhysicsTick(g);
        }
        Assert.True(p1.x > 5, $"벽 통과 x={p1.x}");
        Assert.True(Math.Abs(p1.z) < 1e-6);
        g.HandleInput(1, new InputMsg { fwd = 0, strafe = 0, jump = false, yaw = 0, pitch = 0 });
        p1.x = 4.5;
        p1.z = 0;
        Run(g, C.GHOST_MS);
        Assert.True(p1.alive && p1.z >= 3 - 1e-6, $"끝나면 벽 꼭대기 z={p1.z}");
    }

    [Fact]
    public void Wall_bounce_turns_knockback_up_once()
    {
        var (g, p1, _) = Setup();
        for (int y = 0; y < C.GRID_D; y++) for (int z = 0; z < 3; z++) g.grid[g.Idx(4, y, z)] = 1;
        p1.x = 3.5;
        p1.y = 5;
        p1.kbx = 20;
        p1.stunUntil = g.time + 500;
        PhysicsTick(g);
        Assert.True(p1.wallBounced);
        Assert.True(p1.vz > 0);
        Assert.Equal(4 - C.PLAYER_HALF, p1.x, 9);
    }

    [Fact]
    public void Start_positions_on_terrain_and_spawn_points_per_size()
    {
        foreach (var id in new[] { "pyramid", "stairs" })
        {
            var g = new Game();
            g.AddPlayer(1);
            g.AddPlayer(2);
            Assert.True(g.SetMap(id));
            g.countdownMs = 1;
            g.StartRound();
            Assert.Equal(id, g.mapId);
            Assert.True(g.grid.Sum(v => (int)v) > 0);
            foreach (var p in g.Players()) Assert.Equal(g.SpawnZ(p.x, p.y), p.z);
        }
        var g8 = new Game(countdownMs: 1);
        for (int i = 1; i <= 8; i++) g8.AddPlayer(i);
        Assert.Null(g8.AddPlayer(9)); // 9번째 거절
        g8.StartRound();
        Assert.Equal(19, g8.W);
        Assert.Equal(8, g8.Players().Select(p => (p.x, p.y)).Distinct().Count());
        foreach (var p in g8.Players()) Assert.True(p.x >= 1.5 && p.y >= 1.5 && p.x <= g8.W - 1.5 && p.y <= g8.D - 1.5);
    }

    [Fact]
    public void Input_clamps_and_emote_rules()
    {
        var (g, p1, _) = Setup();
        g.HandleInput(1, new InputMsg { fwd = 5, strafe = double.NaN, jump = true, yaw = double.PositiveInfinity, pitch = 3 });
        Assert.Equal(1, p1.input.fwd);
        Assert.Equal(0, p1.input.strafe);
        Assert.Equal(1.5, p1.pitch);
        Assert.False(g.StartEmote(p1, 1.5), "정수만");
        Assert.False(g.StartEmote(p1, (double)C.EMOTE_NAMES.Length), "바퀴 칸 수까지");
        Assert.True(g.StartEmote(p1, 0.0));
        Assert.False(g.StartEmote(p1, 1.0), "쿨");
        // 이모트 중엔 못 움직임
        double x = p1.x;
        g.HandleInput(1, new InputMsg { fwd = 1, strafe = 0, jump = false, yaw = 0, pitch = 0 });
        PhysicsTick(g);
        Assert.Equal(x, p1.x);
    }

    [Fact]
    public void Nick_cleaning_like_JS()
    {
        var g = new Game();
        g.AddPlayer(1);
        Assert.True(g.SetNick(1, "  재혁\u0001  최고 　"));
        Assert.Equal("재혁 최고", g.players[1].nick);
        Assert.True(g.SetNick(1, "가나다라마바사아자차카타파하가나다라"));
        Assert.Equal((int)C.NAME_MAX_LEN, JsText.CodePoints(g.players[1].nick).Count());
        Assert.True(g.SetNick(1, 5.0));
        Assert.Equal("5", g.players[1].nick);
    }
}
