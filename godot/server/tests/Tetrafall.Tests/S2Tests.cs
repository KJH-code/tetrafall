using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// S2 판 흐름·블록: 각본 입력 판 8개가 JS 와 처음부터 끝까지 글자까지 같음 (fixtures/scripted.json) +
// test/modes·sky·ghost.test.js 중 전투·봇·연습이 안 끼는 것
public class S2Tests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }

    static List<JsonElement> Events(Game g) => g.DrainEvents().Select(e => JsonDocument.Parse(e).RootElement).ToList();

    static string? Str(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static double Num(JsonElement e, string k) => e.GetProperty(k).GetDouble();

    // test/sky.test.js seeded (LCG)
    static Func<double> Seeded(uint seed)
    {
        uint s = seed;
        return () =>
        {
            s = unchecked(s * 1664525u + 1013904223u);
            return s / 4294967296.0;
        };
    }

    [Fact]
    public void Scripted_rounds_match_JS_to_the_end()
    {
        var want = Fixtures.Load("scripted.json").EnumerateArray().ToList();
        Assert.Equal(Scenarios.SCRIPTED.Count, want.Count);
        for (int i = 0; i < want.Count; i++)
        {
            using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var (ticks, _) = Scenarios.RunScripted(Scenarios.SCRIPTED[i], (t, logs, snap) => h.AppendData(Encoding.UTF8.GetBytes(Scenarios.TraceLine(t, logs, snap) + "\n")));
            string sha = Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant();
            Assert.Equal(want[i][1].GetInt32(), ticks);
            Assert.True(sha == want[i][2].GetString(), $"s{i} {Scenarios.SCRIPTED[i].name}: JS 와 다름 (node godot/server/tools/trace.mjs s{i} + Tetrafall.Trace trace s{i} → trace-diff)");
        }
    }

    // ---------- 블록 마스터 (test/modes.test.js) ----------
    static (Game g, List<string> lines, Func<int, Player> p) SetupMode(string mode, int n = 3, bool start = true)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add);
        g.rng = () => 0.5;
        for (int i = 1; i <= n; i++) g.AddPlayer(i);
        Assert.True(g.SetMode(mode));
        if (start) StartQuiet(g);
        return (g, lines, id => g.players[id]);
    }

    static void StartQuiet(Game g)
    {
        Assert.True(g.StartRound());
        g.powerItemNextAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
    }

    static void Place(Player p, double x, double y, double z = 0)
    {
        p.x = x;
        p.y = y;
        p.z = z;
        p.vz = 0;
        p.kbx = 0;
        p.kby = 0;
        p.grounded = true;
    }

    [Fact]
    public void Master_controls_blocks_only_no_auto_pieces()
    {
        var (g, lines, p) = SetupMode("master");
        var m = p(1);
        Assert.True(m.master && !p(2).master && !p(3).master);
        Assert.Contains(lines, l => l.StartsWith("  모드: 블록 마스터 (마스터 P1"));
        double z0 = m.z;
        Run(g, C.FIRST_SPAWN_DELAY_MS + 100);
        Assert.NotNull(g.ControlledPiece(m));
        Assert.Equal(z0, m.z);
        g.HandleAction(1, new ActionMsg { name = "push" });
        Assert.Equal(0, m.pushReadyAt);
        g.HandleAction(1, new ActionMsg { name = "drop" });
        Assert.Null(g.ControlledPiece(m));
        Run(g, C.MASTER_NEXT_PIECE_MS + 2 * TICK);
        Assert.NotNull(g.ControlledPiece(m));
        Place(p(2), 0.5, 0.5);
        Place(p(3), 9.5, 9.5);
        g.controlItemNextAt = 0;
        Run(g, 20000);
        Assert.All(g.pieces, pc => Assert.Equal(1, pc.controller));
        Assert.DoesNotContain(g.items, it => it.type == "control");
        Assert.Null(g.ItemTimers().control);
    }

    [Fact]
    public void Master_wins_when_survivors_crushed()
    {
        var (g, lines, p) = SetupMode("master");
        Run(g, C.FIRST_SPAWN_DELAY_MS + 100);
        var cells = g.PieceWorldCells(g.ControlledPiece(p(1))!);
        Place(p(2), cells[0][0] + 0.5, cells[0][1] + 0.5);
        Place(p(3), cells[^1][0] + 0.5, cells[^1][1] + 0.5);
        g.HandleAction(1, new ActionMsg { name = "drop" });
        Run(g, 3000);
        Assert.Equal("over", g.phase);
        Assert.Equal(new[] { 1 }, g.winnerIds);
        Assert.Equal(1, p(1).wins);
        Assert.Contains(lines, l => System.Text.RegularExpressions.Regex.IsMatch(l, @"\[사망\] P2 압사 .*킬 P1 조종블록"));
        Assert.Contains(lines, l => System.Text.RegularExpressions.Regex.IsMatch(l, "ROUND 1 종료 .*승자: P1 ====="));
        Assert.Contains("  결과: 마스터 P1 승 (생존자 전멸)", lines);
        Assert.True(!p(1).master && p(1).z <= C.GRID_H);
        Assert.True(g.StartEmote(p(1), 1.0));
    }

    [Fact]
    public void Master_time_up_survivors_win_and_master_rotates()
    {
        var (g, lines, p) = SetupMode("master");
        Place(p(2), 0.5, 0.5);
        Place(p(3), 9.5, 9.5);
        Run(g, C.MASTER_TIME_MS - 1000);
        Assert.Equal("playing", g.phase);
        var left = JsonDocument.Parse(g.Snapshot()).RootElement.GetProperty("round").GetProperty("left").GetDouble();
        Assert.True(left <= 1000);
        Run(g, 1100);
        Assert.Equal("over", g.phase);
        Assert.Equal(new[] { 2, 3 }, g.winnerIds.OrderBy(x => x));
        Assert.Equal(new double[] { 0, 1, 1 }, new[] { p(1).wins, p(2).wins, p(3).wins });
        Assert.Contains(lines, l => System.Text.RegularExpressions.Regex.IsMatch(l, "ROUND 1 종료 .*승자: P2 P3 ====="));
        var masters = new List<int>();
        for (int r = 0; r < 3; r++)
        {
            StartQuiet(g);
            masters.Add(g.Players().First(q => q.master).id);
            g.EndRound(null);
        }
        Assert.Equal(new[] { 2, 3, 1 }, masters);
    }

    [Fact]
    public void Master_leaving_gives_survivors_the_win()
    {
        var (g, _, p) = SetupMode("master");
        g.RemovePlayer(1);
        Assert.Equal("over", g.phase);
        Assert.Equal(new[] { 2, 3 }, g.winnerIds.OrderBy(x => x));
        Assert.Equal(1, p(2).wins);
    }

    [Fact]
    public void Kills_no_lava_and_sinks_when_tall()
    {
        var (g, lines, p) = SetupMode("kills", 2);
        g.nextSpawnAt = double.PositiveInfinity;
        for (int x = 0; x < C.GRID_W; x++) for (int y = 0; y < C.GRID_D; y++) for (int z = 0; z < 2; z++) if (x != 0 || y != 0) g.grid[g.Idx(x, y, z)] = 1;
        g.UpdateLava(TICK);
        Assert.False(g.lava.active);
        for (int z = 0; z < C.KILLS_SINK_HEIGHT - 1; z++) g.grid[g.Idx(5, 5, z)] = 1;
        Place(p(1), 2.5, 2.5, 2);
        var piece = g.MakePiece("O", 0, 4, 4, (int)C.KILLS_SINK_HEIGHT - 1);
        g.AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.stepMs = 1e9;
            pc.nextStepAt = 1e18;
            pc.controlEndsAt = 0;
        });
        g.LandPiece(piece);
        Assert.Equal(C.KILLS_SINK_HEIGHT - 1, g.ColumnTop(5, 5));
        Assert.Equal(1, g.ColumnTop(2, 2));
        Assert.Equal(1, p(1).z);
        Assert.Contains(lines, l => l.StartsWith("  [가라앉음]"));
    }

    [Fact]
    public void Master_side_zombie_blocks_and_kill_credit()
    {
        var (g, lines, p) = SetupMode("master");
        Run(g, C.FIRST_SPAWN_DELAY_MS + 100);
        var cells = g.PieceWorldCells(g.ControlledPiece(p(1))!);
        Place(p(2), cells[0][0] + 0.5, cells[0][1] + 0.5);
        Place(p(3), 0.5, 9.5);
        g.HandleAction(1, new ActionMsg { name = "drop" });
        Run(g, 2000);
        Assert.Equal("playing", g.phase);
        Assert.True(p(2).alive && p(2).master && p(2).zombie);
        Assert.Contains("  [마스터 편] P2 → 하늘에서 블록", lines);
        Assert.Equal(1, g.Master()!.id);
        var mine = g.ControlledPiece(p(2));
        Assert.True(mine != null && g.ControlledPiece(p(1)) != null);
        g.MovePiece(mine!, -10, 10);
        Place(p(3), g.PieceWorldCells(mine!)[0][0] + 0.5, g.PieceWorldCells(mine!)[0][1] + 0.5);
        g.HandleAction(2, new ActionMsg { name = "drop" });
        Run(g, 1500);
        Assert.Equal("over", g.phase);
        Assert.Contains(lines, l => System.Text.RegularExpressions.Regex.IsMatch(l, @"\[사망\] P3 압사 .*킬 P2 조종블록"));
        Assert.Equal(new[] { 1 }, g.winnerIds);
        Assert.Equal(new double[] { 1, 0, 0 }, new[] { p(1).wins, p(2).wins, p(3).wins });
        Assert.True(!p(2).master && !p(2).zombie && !p(2).alive);
        Assert.DoesNotContain(g.pieces, pc => pc.phase == "control");
    }

    [Fact]
    public void Master_tower_limit()
    {
        var (g, _, p) = SetupMode("master");
        Run(g, C.FIRST_SPAWN_DELAY_MS + 100);
        var piece = g.ControlledPiece(p(1))!;
        var foot = piece.cells.Select(c => (piece.px + c[0], piece.py + c[1])).ToList();
        foreach (var (x, y) in foot) for (int z = 0; z < C.MASTER_MAX_RISE; z++) g.grid[g.Idx(x, y, z)] = 1;
        g.GridChanged();
        g.UpdateLanding(piece);
        Assert.False(piece.fits);
        g.HandleAction(1, new ActionMsg { name = "drop" });
        Assert.Equal("control", piece.phase);
        foreach (var (x, y) in foot) g.grid[g.Idx(x, y, (int)C.MASTER_MAX_RISE - 1)] = 0;
        g.GridChanged();
        g.UpdateLanding(piece);
        Assert.True(piece.fits);
        var s = new Game();
        s.AddPlayer(1);
        s.AddPlayer(2);
        s.StartRound();
        for (int z = 0; z < 8; z++) s.grid[s.Idx(5, 5, z)] = 1;
        var pc = s.MakePiece("O", 0, 4, 4, (int)C.CONTROL_HOVER_Z);
        s.AddPiece(pc, q =>
        {
            q.phase = "control";
            q.controller = 1;
            q.stepMs = 80;
            q.nextStepAt = 0;
            q.controlEndsAt = 1e9;
        });
        s.UpdateLanding(pc);
        Assert.True(pc.fits);
    }

    [Fact]
    public void Master_side_pieces_start_at_random_spot()
    {
        var (g, _, p) = SetupMode("master");
        (int, int, (int w, int d)) At(double r)
        {
            g.rng = () => r;
            var pc = g.SpawnControlled(p(2), true);
            g.RemovePiece(pc);
            return (pc.px, pc.py, Pieces.Footprint(pc.cells));
        }
        var (x0, y0, _) = At(0);
        var (x1, y1, f) = At(0.999);
        Assert.Equal((0, 0), (x0, y0));
        Assert.Equal(((int)C.GRID_W - f.w, (int)C.GRID_D - f.d), (x1, y1));
    }

    // ---------- 하늘 계단 (test/sky.test.js) ----------
    static (Game g, List<string> lines) SetupSky(bool sky = true, uint seed = 1, int n = 2)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, skyStairs: sky);
        g.rng = Seeded(seed);
        for (int i = 1; i <= n; i++) g.AddPlayer(i);
        Assert.True(g.StartRound());
        g.powerItemNextAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        return (g, lines);
    }

    static List<Piece> Skies(Game g) => g.pieces.Where(pc => pc.sky).OrderBy(pc => pc.id).ToList();

    [Fact]
    public void Sky_chain_rules()
    {
        foreach (uint seed in new uint[] { 1, 2, 3, 4, 5 })
        {
            var (g, lines) = SetupSky(seed: seed);
            Assert.Equal(C.SKY_GRID_H, g.H);
            Assert.Equal(g.W * g.D * (int)C.SKY_GRID_H, g.grid.Length);
            Assert.Contains("  하늘 계단: 켬", lines);
            Run(g, C.FIRST_SPAWN_DELAY_MS + TICK * (C.SKY_COUNT + 1));
            var s = Skies(g);
            Assert.Equal(C.SKY_COUNT, s.Count);
            foreach (var pc in s)
            {
                Assert.Equal(C.SKY_FALL_STEP_MS, pc.stepMs);
                Assert.True(pc.pz + 1 <= C.SKY_TOP_Z);
                Assert.True(pc.pz > pc.landZ);
            }
            Assert.Equal(s[0].landZ + C.SKY_BASE_UP, s[0].pz);
            for (int i = 1; i < s.Count; i++)
            {
                int rise = s[i].pz - s[i - 1].pz;
                Assert.InRange(rise, C.SKY_RISE_MIN, C.SKY_RISE_MAX);
                double gap = GameUtil.CellGap(s[i], s[i - 1]);
                Assert.True(gap >= C.SKY_GAP_MIN && gap <= GameUtil.SkyReach(rise) * C.SKY_REACH_SAFETY, $"틈 {gap}");
            }
            var cols = new HashSet<int>();
            foreach (var pc in s) foreach (var c in pc.cells) Assert.True(cols.Add((pc.px + c[0]) * 100 + pc.py + c[1]));
        }
    }

    [Fact]
    public void Sky_blocks_step_together()
    {
        var (g, _) = SetupSky(seed: 3);
        Run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
        var before = Skies(g).ToDictionary(pc => pc.id, pc => pc.pz);
        for (int k = 1; k <= 3; k++)
        {
            Run(g, C.SKY_FALL_STEP_MS);
            foreach (var pc in Skies(g)) if (before.TryGetValue(pc.id, out var b) && pc.landZ < b - k) Assert.Equal(b - k, pc.pz);
        }
    }

    [Fact]
    public void Sky_lands_crushes_and_refills()
    {
        var (g, _) = SetupSky(seed: 2, n: 3);
        Run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
        var low = Skies(g)[0];
        int cx = low.cells[0][0], cy = low.cells[0][1];
        var p2 = g.players[2];
        p2.x = low.px + cx + 0.5;
        p2.y = low.py + cy + 0.5;
        p2.z = g.ColumnTop(low.px + cx, low.py + cy);
        p2.vz = 0;
        int steps = low.pz - low.landZ;
        Run(g, steps * C.SKY_FALL_STEP_MS + TICK);
        Assert.DoesNotContain(low, g.pieces);
        foreach (var c in low.cells) Assert.NotEqual(0, g.GridAt(low.px + c[0], low.py + c[1], low.landZ));
        Assert.False(p2.alive);
        Assert.Equal("crush", g.deaths[0].cause);
        Assert.Equal(C.SKY_COUNT, Skies(g).Count);
    }

    [Fact]
    public void Sky_blocks_melt_in_lava()
    {
        var (g, _) = SetupSky(seed: 4);
        Run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
        var low = Skies(g)[0];
        g.lava = new Lava { active = true, z = low.pz - 0.5, startedAt = g.time };
        g.DrainEvents();
        for (double t = 0; t < C.SKY_FALL_STEP_MS + TICK; t += TICK)
        {
            foreach (var p in g.Players())
            {
                p.z = 25;
                p.vz = 0;
            }
            g.Tick(TICK);
        }
        Assert.DoesNotContain(low, g.pieces);
        foreach (var c in low.cells) for (int z = 0; z < g.H; z++) Assert.Equal(0, g.GridAt(low.px + c[0], low.py + c[1], z));
        Assert.Contains(Events(g), e => Str(e, "type") == "melt" && e.GetProperty("cells").GetArrayLength() == 4);
    }

    [Fact]
    public void Sky_lava_by_time_off_by_height_only()
    {
        Assert.Equal(60000, C.SKY_LAVA_TRIGGER_MS);
        foreach (var sky in new[] { true, false })
        {
            var (g, lines) = SetupSky(sky: sky, n: 3);
            g.nextSpawnAt = double.PositiveInfinity; // 블록 없이 시간만 (JS 는 updateSpawning 을 비움)
            foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
            Run(g, C.SKY_LAVA_TRIGGER_MS - 500);
            Assert.False(g.lava.active);
            Run(g, 1000);
            Assert.Equal(sky, g.lava.active);
            if (sky) Assert.Contains(lines, l => l.StartsWith("  [용암] 1:00 지남 (하늘 계단)") && l.Contains("용암 상승 시작"));
        }
    }

    [Fact]
    public void PlacementScorer_equals_slow_score()
    {
        var rng = Seeded(42);
        for (int trial = 0; trial < 40; trial++)
        {
            var g = new Game();
            g.SetFieldSize(new[] { 10, 12, 14 }[trial % 3]);
            for (int x = 0; x < g.W; x++)
            {
                for (int y = 0; y < g.D; y++)
                {
                    int h = rng() < 0.6 ? 0 : (int)Math.Floor(rng() * 3);
                    for (int z = 0; z < h; z++) g.grid[g.Idx(x, y, z)] = Pieces.CELL.TERRAIN;
                }
            }
            var sc = g.PlacementScorer();
            Assert.Equal(g.LowestLayer(), sc.L);
            foreach (var shape in Pieces.SHAPE_NAMES)
            {
                for (int r = 0; r < 4; r++)
                {
                    var (w, d) = Pieces.Footprint(Pieces.RotatedCells(shape, r));
                    for (int px = 0; px <= g.W - w; px++)
                    {
                        for (int py = 0; py <= g.D - d; py++)
                        {
                            var pc = g.MakePiece(shape, r, px, py, 20);
                            Assert.Equal(g.PlacementScore(pc, sc.L), sc.Score(pc.cells, px, py, pc.landZ));
                        }
                    }
                }
            }
        }
    }

    [Fact]
    public void Sky_one_per_tick_and_same_seed_same_spots()
    {
        (List<int> counts, List<(string, double, int, int, int)> at) Place(uint seed)
        {
            var (g, _) = SetupSky(seed: seed, n: 4);
            var counts = new List<int>();
            while (g.time < C.FIRST_SPAWN_DELAY_MS + TICK * (C.SKY_COUNT + 2))
            {
                g.Tick(TICK);
                counts.Add(Skies(g).Count);
            }
            return (counts.Where((n, i) => i == 0 || n != counts[i - 1]).ToList(), Skies(g).Select(pc => (pc.shape, pc.rot, pc.px, pc.py, pc.pz)).ToList());
        }
        var a = Place(9);
        Assert.Equal(new[] { 0, 1, 2, 3, 4, 5, 6, 7 }, a.counts);
        Assert.Equal(a.at, Place(9).at);
    }

    [Fact]
    public void Sky_chains_and_lava_by_player_count()
    {
        foreach (var (n, lavaMs) in new[] { (4, 60000.0), (6, 55000.0), (8, 50000.0) })
        {
            double chains = C.SKY_CHAINS[n.ToString()];
            var (g, lines) = SetupSky(n: n, seed: (uint)n);
            Assert.Equal(chains, g.skyChains);
            Assert.Equal(lavaMs, g.skyLavaMs);
            Run(g, C.FIRST_SPAWN_DELAY_MS + TICK * (C.SKY_COUNT * chains + 2));
            var s = Skies(g);
            Assert.Equal(C.SKY_COUNT * chains, s.Count);
            for (int c = 0; c < chains; c++) Assert.Equal(C.SKY_COUNT, s.Count(pc => pc.chain == c));
            Run(g, lavaMs - g.Elapsed() + 2 * TICK);
            Assert.True(g.lava.active, $"{n}명 용암");
        }
    }

    // ---------- 유령 투하 (test/ghost.test.js) ----------
    static (Game g, List<string> lines, Func<int, Player> p) SetupGhost(bool sky = false, string? mode = null, bool team = false)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, skyStairs: sky);
        g.rng = () => 0.5;
        for (int i = 1; i <= 3; i++) g.AddPlayer(i);
        if (mode != null) g.SetMode(mode);
        if (team)
        {
            g.SetTeamMode(true);
            g.SetTeam(1, "red");
            g.SetTeam(2, "red");
            g.SetTeam(3, "blue");
        }
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        g.players[2].x = 2.5;
        g.players[2].y = 2.5;
        g.players[3].x = 7.5;
        g.players[3].y = 7.5;
        return (g, lines, id => g.players[id]);
    }

    static JsonElement SnapPlayer(Game g, int id) => JsonDocument.Parse(g.Snapshot()).RootElement.GetProperty("players").EnumerateArray().First(q => q.GetProperty("id").GetInt32() == id);

    [Fact]
    public void Ghost_drop_cooldown_and_rejections()
    {
        var (g, lines, p) = SetupGhost();
        JsonElement Cd() => SnapPlayer(g, 1).GetProperty("ghostCd");
        Assert.Equal(JsonValueKind.Null, Cd().ValueKind);
        g.DrainEvents();
        Assert.Null(g.GhostDrop(1, 5, 5));
        Assert.Contains(Events(g), e => Str(e, "type") == "ghostDropFail" && Num(e, "who") == 1 && Str(e, "reason") == "notDead");
        g.Kill(p(1), "fall");
        Assert.Equal(0, Cd().GetDouble());
        var pc = g.GhostDrop(1, 5, 5);
        Assert.True(pc != null && pc.ghostBy == 1 && pc.cells.Length == 1);
        Assert.Equal(C.GHOST_DROP_UP, pc!.pz);
        Assert.Contains(Events(g), e => Str(e, "type") == "ghostDrop" && Num(e, "who") == 1 && Num(e, "x") == 5 && Num(e, "y") == 5 && Num(e, "slot") == p(1).slot);
        Assert.Contains("  [유령] P1 → (5,5) 투하", lines);
        Assert.Equal(C.GHOST_DROP_CD_MS, Cd().GetDouble());
        string? Fails(double x, double y)
        {
            g.GhostDrop(1, x, y);
            return Str(Events(g).First(e => Str(e, "type") == "ghostDropFail"), "reason");
        }
        Assert.Equal("cooldown", Fails(6, 6));
        Run(g, C.GHOST_DROP_CD_MS);
        Assert.Equal("outside", Fails(-1, 3));
        g.piece = null;
        var I = g.MakePiece("I", 0, 0, 0, 10);
        I.id = 99;
        I.phase = "falling";
        I.controller = null;
        I.stepMs = 1e9;
        I.nextStepAt = double.PositiveInfinity;
        g.pieces = new List<Piece> { I };
        g.RefreshPieceCells();
        Assert.Equal("busy", Fails(2, 0));
        Assert.NotNull(g.GhostDrop(1, 8, 2));
    }

    [Fact]
    public void Ghost_drop_falls_at_round_speed_and_leaves_color()
    {
        foreach (var sky in new[] { false, true })
        {
            var (g, _, p) = SetupGhost(sky: sky);
            g.Kill(p(1), "fall");
            var pc = g.GhostDrop(1, 5, 5)!;
            Assert.Equal(sky ? C.SKY_FALL_STEP_MS : g.AutoFallStepMs(), pc.stepMs);
            Assert.Equal(sky ? C.GHOST_DROP_UP_SKY : C.GHOST_DROP_UP, pc.pz);
            var sp = JsonDocument.Parse(g.Snapshot()).RootElement.GetProperty("pieces").EnumerateArray().First(x => x.GetProperty("id").GetInt32() == pc.id);
            Assert.Equal(p(1).slot, sp.GetProperty("ghostSlot").GetInt32());
            Assert.Equal(p(1).color, sp.GetProperty("ghostColor").GetInt32());
            Run(g, pc.stepMs * (pc.pz + 1) + TICK);
            Assert.DoesNotContain(pc, g.pieces);
            Assert.Equal(Pieces.CELL.GHOST_BASE + p(1).color, g.GridAt(5, 5, 0));
            Assert.Equal(1, g.landed["ghost"]);
        }
    }

    [Fact]
    public void Ghost_drop_crush_credit_and_team()
    {
        var (g, lines, p) = SetupGhost();
        g.Kill(p(1), "fall");
        Place(p(2), 5.5, 5.5);
        var pc = g.GhostDrop(1, 5, 5)!;
        Run(g, pc.stepMs * C.GHOST_DROP_UP + TICK);
        Assert.False(p(2).alive);
        var d = g.deaths.First(x => x.name == "P2");
        Assert.Equal(("crush", "P1", "ghost"), (d.cause, d.killer, d.weapon));
        Assert.Contains(lines, l => l.StartsWith("  [사망] P2 압사") && l.Contains("킬 P1 유령블록"));
        (g, _, p) = SetupGhost(team: true);
        g.Kill(p(1), "fall");
        Place(p(2), 5.5, 5.5);
        var pc2 = g.GhostDrop(1, 5, 5)!;
        Run(g, pc2.stepMs * C.GHOST_DROP_UP + TICK);
        Assert.False(p(2).alive);
        Assert.Null(g.deaths.First(x => x.name == "P2").killer);
    }

    [Fact]
    public void Ghost_drop_only_in_survival_not_spectators()
    {
        foreach (var mode in new[] { "kills", "master" })
        {
            var (g, _, p) = SetupGhost(mode: mode);
            g.Kill(p(2), "fall");
            Assert.Null(g.GhostCd(p(2)));
            g.DrainEvents();
            Assert.Null(g.GhostDrop(2, 5, 5));
            Assert.Contains(Events(g), e => Str(e, "type") == "ghostDropFail" && Str(e, "reason") == "mode");
        }
        var (g2, _, p2) = SetupGhost();
        p2(1).spectator = true;
        p2(1).alive = false;
        Assert.Null(g2.GhostCd(p2(1)));
    }
}
