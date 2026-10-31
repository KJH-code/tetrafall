using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// S5 봇 뒤로 미뤄 둔 테스트: test/hp.test.js · master.test.js · modes.test.js 킬 점수전 · botpos.test.js
public class S5Tests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }

    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    static List<JsonElement> Events(Game g) => g.DrainEvents().Select(e => J(e)).ToList();

    static string? Str(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static JsonElement SnapPlayer(Game g, int id) => J(g.Snapshot()).GetProperty("players").EnumerateArray().First(q => q.GetProperty("id").GetInt32() == id);

    static Func<double> Lcg(uint seed)
    {
        uint s = seed;
        return () =>
        {
            s = unchecked(s * 1664525u + 1013904223u);
            return s / 4294967296.0;
        };
    }

    // ---------- 체력전 (test/hp.test.js) ----------
    static (Game g, List<string> lines) SetupHp(bool hp = true, string mode = "survival", int n = 3)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, hpMode: hp);
        g.rng = () => 0.5;
        for (int i = 1; i <= n; i++) g.AddPlayer(i);
        if (mode != "survival") g.SetMode(mode);
        Assert.True(g.StartRound());
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        return (g, lines);
    }

    // a 가 b 를 피해 gain 만큼 때림 (넉백 0 → 제자리). 앞 타의 콤보 끝 무적이 풀릴 때까지 틱을 돌린 뒤
    static void Hit(Game g, int a, int b, double gain)
    {
        var t = g.players[b];
        for (int k = 0; k < 100 && g.Invulnerable(t); k++) g.Tick(TICK);
        Assert.True(g.ApplyKnockback(t, 1, 0, 0, 0, 0, gain, new Src(a, "push"), true), "맞음");
    }

    [Fact]
    public void Hp_off_by_default_no_hp_fields()
    {
        var (g, _) = SetupHp(hp: false);
        Hit(g, 1, 2, C.HP_MAX_BY_MODE["survival"] + 50);
        g.Tick(TICK);
        Assert.True(g.players[2].alive);
        var s = J(g.Snapshot());
        Assert.False(s.TryGetProperty("hpMode", out _));
        Assert.False(s.GetProperty("players")[1].TryGetProperty("hp", out _));
    }

    [Fact]
    public void Hp_on_survival_ko_at_zero_with_last_hit_credit()
    {
        double max = C.HP_MAX_BY_MODE["survival"];
        var (g, lines) = SetupHp();
        var p2 = g.players[2];
        Assert.Contains($"  체력전: 켬 (HP {JsNumber.ToJs(max)})", lines);
        Hit(g, 1, 2, 70);
        var s = J(g.Snapshot());
        Assert.True(s.GetProperty("hpMode").GetBoolean());
        Assert.Equal(max, s.GetProperty("hpMax").GetDouble());
        Assert.Equal(max - 70, SnapPlayer(g, 2).GetProperty("hp").GetDouble());
        g.Tick(TICK);
        Assert.True(p2.alive);
        Hit(g, 3, 2, max - 71);
        g.Tick(TICK);
        Assert.True(p2.alive, "HP 1 은 살아 있음");
        Hit(g, 1, 2, 1);
        var (x, y, z) = (p2.x, p2.y, p2.z);
        g.DrainEvents();
        g.Tick(TICK);
        Assert.False(p2.alive);
        Assert.Equal("hp", p2.deathCause);
        Assert.Equal((x, y, z), (p2.x, p2.y, p2.z));
        var death = Events(g).First(e => Str(e, "type") == "death");
        Assert.Equal("hp", Str(death, "cause"));
        Assert.Equal(1, death.GetProperty("by").GetInt32());
        Assert.Contains(lines, l => Regex.IsMatch(l, @"^ {2}\[사망\] P2 체력 @ .*킬 P1 밀치기"));
    }

    [Fact]
    public void Hp_kills_mode_scores_and_respawn_full()
    {
        var (g, _) = SetupHp(mode: "kills");
        Assert.Equal(C.HP_MAX_BY_MODE["kills"], J(g.Snapshot()).GetProperty("hpMax").GetDouble());
        Hit(g, 1, 2, C.HP_MAX_BY_MODE["kills"]);
        g.Tick(TICK);
        Assert.False(g.players[2].alive);
        Assert.Equal(1, g.scores[1]);
        Run(g, C.KILLS_RESPAWN_MS + 500);
        Assert.True(g.players[2].alive);
        Assert.Equal(C.HP_MAX_BY_MODE["kills"], SnapPlayer(g, 2).GetProperty("hp").GetDouble());
    }

    [Fact]
    public void Hp_master_only_survivors()
    {
        var (g, _) = SetupHp(mode: "master");
        var m = g.Master()!;
        int survivor = new[] { 1, 2, 3 }.First(id => id != m.id);
        m.damage = 999;
        g.Tick(TICK);
        Assert.True(m.alive && m.master);
        int other = new[] { 1, 2, 3 }.First(id => id != m.id && id != survivor);
        Hit(g, other, survivor, C.HP_MAX_BY_MODE["master"]);
        g.Tick(TICK);
        Assert.Contains(g.deaths, d => d.name == g.players[survivor].name && d.cause == "hp");
        Assert.True(g.players[survivor].master || g.phase == "over");
    }

    [Fact]
    public void Hp_option_between_rounds_and_never_in_practice()
    {
        var g = new Game();
        g.AddPlayer(1);
        g.AddPlayer(2);
        Assert.True(g.SetHpMode(true));
        Assert.False(g.SetHpMode(true));
        g.StartRound();
        Assert.False(g.SetHpMode(false));
        var pr = new Game(hpMode: true);
        pr.AddPlayer(1);
        pr.StartPractice();
        Assert.False(pr.hpMode);
        Assert.False(pr.SetHpMode(true));
    }

    [Fact]
    public void Hp_room_option_host_only_and_public_list()
    {
        var rooms = new Rooms();
        var a = rooms.Connect(new Sock());
        rooms.Message(a, J("{\"type\":\"create\"}"));
        var room = a.room!;
        var b = rooms.Connect(new Sock());
        rooms.Message(b, J($"{{\"type\":\"join\",\"code\":\"{room.code}\"}}"));
        rooms.Message(b, J("{\"type\":\"hpMode\",\"on\":true}"));
        Assert.False(room.game.hpMode);
        rooms.Message(a, J("{\"type\":\"hpMode\",\"on\":true}"));
        Assert.True(room.game.hpMode);
    }

    sealed class Sock : ISocket
    {
        public bool Open => true;
        public void Send(string text) { }
    }

    // ---------- 블록 마스터 밸런스 (test/master.test.js) ----------
    static Game Master(int n)
    {
        var g = new Game();
        g.rng = () => 0.5;
        for (int i = 1; i <= n; i++) g.AddPlayer(i);
        g.SetMode("master");
        g.StartRound();
        return g;
    }

    [Fact]
    public void Master_drop_speed_by_count()
    {
        foreach (var n in new[] { 2, 4, 8 })
        {
            var g = Master(n);
            Run(g, C.FIRST_SPAWN_DELAY_MS + C.MASTER_NEXT_PIECE_MS + 2 * TICK);
            var m = g.Master()!;
            var piece = g.ControlledPiece(m);
            Assert.NotNull(piece);
            g.HandleAction(m.id, new ActionMsg { name = "drop" });
            Assert.Equal(C.MASTER_DROP_STEP_BY_COUNT[n.ToString()], piece!.stepMs);
        }
        var s = new Game();
        s.rng = () => 0.5;
        s.AddPlayer(1);
        s.AddPlayer(2);
        s.StartRound();
        var pc = s.SpawnControlled(s.players[1]);
        s.DropPiece(pc);
        Assert.Equal(C.HARD_DROP_STEP_MS, pc.stepMs);
    }

    [Fact]
    public void Master_counter_item_stalls_master_side()
    {
        var g = Master(3);
        Run(g, C.MASTER_COUNTER_FIRST_MS - 500);
        Assert.DoesNotContain(g.items, it => it.type == "counter");
        Run(g, 600);
        var item = g.items.FirstOrDefault(it => it.type == "counter");
        Assert.NotNull(item);
        Assert.Single(g.items, it => it.type == "counter");
        var m = g.Master()!;
        var s = g.Players().First(p => !p.master && p.alive);
        s.x = item!.x + 0.5;
        s.y = item.y + 0.5;
        s.z = g.ColumnTop(item.x, item.y);
        s.vz = 0;
        s.kbx = 0;
        s.kby = 0;
        g.DrainEvents();
        g.PickupItems();
        var ev = Events(g).First(e => Str(e, "type") == "masterStall");
        Assert.Equal(s.id, ev.GetProperty("who").GetInt32());
        Assert.Equal(C.MASTER_COUNTER_STALL_MS, ev.GetProperty("ms").GetDouble());
        Assert.Equal(g.time + C.MASTER_COUNTER_STALL_MS, g.masterStallUntil);
        var held = g.ControlledPiece(m);
        if (held != null) g.HandleAction(m.id, new ActionMsg { name = "drop" });
        Run(g, C.MASTER_COUNTER_STALL_MS - 500);
        Assert.Null(g.ControlledPiece(m));
        Run(g, 1000);
        Assert.NotNull(g.ControlledPiece(m));
        double t0 = g.time;
        g.GivePower(s, "counter");
        g.GivePower(s, "counter");
        Assert.Equal(t0 + 2 * C.MASTER_COUNTER_STALL_MS, g.masterStallUntil);
    }

    [Fact]
    public void Counter_item_only_in_master_rounds()
    {
        foreach (var mode in new[] { "survival", "kills" })
        {
            var g = new Game();
            g.rng = () => 0.5;
            for (int i = 1; i <= 3; i++) g.AddPlayer(i);
            if (mode != "survival") g.SetMode(mode);
            g.StartRound();
            g.nextSpawnAt = double.PositiveInfinity;
            foreach (var p in g.Players()) p.z = 0;
            Run(g, C.MASTER_COUNTER_FIRST_MS + 2000);
            Assert.DoesNotContain(g.items, it => it.type == "counter");
        }
    }

    [Fact]
    public void Bot_goes_for_counter_item_even_if_farther()
    {
        var g = Master(3);
        var bot = new BotBrain(() => 0.5, () => "normal");
        var s = g.Players().First(p => !p.master);
        s.x = 2.5;
        s.y = 2.5;
        s.z = 0;
        var target = new Player { x = 8.5, y = 2.5, z = 0 };
        g.items = new List<Item> { new Item { type = "counter", x = 6, y = 2, z = 0 } };
        Assert.Equal("counter", bot.PickItem(g, s, target)?.type);
        g.items = new List<Item> { new Item { type = "jump", x = 6, y = 2, z = 0 } };
        Assert.Null(bot.PickItem(g, s, target));
    }

    [Fact]
    public void Kills_target_by_count_team_and_hp()
    {
        var cases = new (int n, bool team, bool hp, double want)[]
        {
            (2, false, false, C.KILLS_TARGET_BY_COUNT["off"]["2"]),
            (4, false, false, C.KILLS_TARGET_BY_COUNT["off"]["3"]),
            (8, false, true, C.KILLS_TARGET_BY_COUNT["hp"]["8"]),
            (5, false, true, C.KILLS_TARGET_BY_COUNT["hp"]["5"]),
            (7, false, true, C.KILLS_TARGET_BY_COUNT["hp"]["6"]),
            (4, true, false, C.KILLS_TARGET_TEAM_BY_COUNT["off"]["2"]),
            (8, true, true, C.KILLS_TARGET_TEAM_BY_COUNT["hp"]["8"]),
        };
        foreach (var (n, team, hp, want) in cases)
        {
            var lines = new List<string>();
            var g = new Game(lines.Add, hpMode: hp);
            g.rng = () => 0.5;
            for (int i = 1; i <= n; i++) g.AddPlayer(i);
            if (team) g.SetTeamMode(true);
            g.SetMode("kills");
            g.StartRound();
            Assert.Equal(want, g.killsTarget);
            Assert.Equal(want, J(g.Snapshot()).GetProperty("round").GetProperty("killsTarget").GetDouble());
            Assert.Contains(lines, l => l.Contains($"또는 {(team ? $"팀 {JsNumber.ToJs(want)}" : JsNumber.ToJs(want))}킬)"));
        }
        Assert.False(J(Master(3).Snapshot()).GetProperty("round").TryGetProperty("killsTarget", out _));
    }

    // ---------- 킬 점수전 (test/modes.test.js) ----------
    static (Game g, List<string> lines, Func<int, Player> p) SetupKills(int n, bool start = true)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add);
        g.rng = () => 0.5;
        for (int i = 1; i <= n; i++) g.AddPlayer(i);
        Assert.True(g.SetMode("kills"));
        if (start) StartQuiet(g);
        return (g, lines, id => g.players[id]);
    }

    static void StartQuiet(Game g)
    {
        Assert.True(g.StartRound());
        g.powerItemNextAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
    }

    static void FallOff(Player p)
    {
        p.x = -3;
        p.z = C.FALL_DEATH_Z - 1;
    }

    [Fact]
    public void Kills_score_selfdestruct_respawn_and_shield()
    {
        var (g, lines, p) = SetupKills(2);
        Assert.Contains(lines, l => l.StartsWith("  모드: 킬 점수전"));
        g.nextSpawnAt = double.PositiveInfinity;
        p(2).damage = 80;
        p(2).lastHit = new LastHit { by = 1, kind = "push", name = "P1" };
        FallOff(p(2));
        g.Tick(TICK);
        Assert.False(p(2).alive);
        Assert.Equal(1, g.scores[1]);
        Assert.Contains("  [점수] P1 +1 → 1", lines);
        p(1).lastHit = null;
        FallOff(p(1));
        g.Tick(TICK);
        Assert.Equal(0, g.scores[1]);
        Assert.Contains("  [점수] P1 자멸 -1 → 0", lines);
        Assert.Equal("playing", g.phase);
        Run(g, C.KILLS_RESPAWN_MS - 3 * TICK);
        Assert.False(p(2).alive);
        Assert.True(SnapPlayer(g, 2).GetProperty("respawnIn").GetDouble() > 0);
        Run(g, 4 * TICK);
        Assert.True(p(2).alive);
        Assert.Equal(0, p(2).damage);
        Assert.Contains(lines, l => l.StartsWith("  [부활] P2 →"));
        Assert.False(g.ApplyKnockback(p(2), 1, 0, 5, 3, C.STUN_MS, 10, new Src(1, "push")));
        var piece = g.MakePiece("O", 0, (int)Math.Floor(p(2).x), (int)Math.Floor(p(2).y), (int)Math.Ceiling(p(2).z) + 1);
        piece.phase = "falling";
        piece.controller = null;
        piece.stepMs = 30;
        piece.nextStepAt = g.time;
        piece.controlEndsAt = 0;
        g.AddPiece(piece, _ => { });
        Run(g, 300);
        Assert.True(p(2).alive);
        Run(g, C.KILLS_SHIELD_MS);
        Assert.Equal(0, p(2).shieldUntil);
        Assert.Empty(g.OverlappingSolid(g.Aabb(p(2))));
        Assert.True(g.ApplyKnockback(p(2), 1, 0, 5, 3, C.STUN_MS, 10, new Src(1, "push")));
    }

    [Fact]
    public void Kills_target_ends_round_and_time_up_ties()
    {
        var (g, lines, p) = SetupKills(3);
        g.nextSpawnAt = double.PositiveInfinity;
        Assert.Equal(C.KILLS_TARGET_BY_COUNT["off"]["3"], g.killsTarget);
        g.scores[1] = g.killsTarget - 1;
        p(2).lastHit = new LastHit { by = 1, kind = "push", name = "P1" };
        FallOff(p(2));
        g.Tick(TICK);
        Assert.Equal("over", g.phase);
        Assert.Equal(new[] { 1 }, g.winnerIds);
        Assert.Contains($"  {JsNumber.ToJs(g.killsTarget)}킬 → 판 끝", lines);
        Assert.Contains($"  점수: P1 {JsNumber.ToJs(g.killsTarget)} / P2 0 / P3 0", lines);
        StartQuiet(g);
        g.nextSpawnAt = double.PositiveInfinity;
        Assert.Empty(g.scores);
        g.scores[2] = 2;
        g.scores[3] = 2;
        foreach (var q in g.Players())
        {
            q.z = 0;
            q.vz = 0;
            q.kbx = 0;
            q.kby = 0;
            q.grounded = true;
        }
        Run(g, C.KILLS_TIME_MS + TICK);
        Assert.Equal("over", g.phase);
        Assert.Equal(new[] { 2, 3 }, g.winnerIds.OrderBy(x => x));
        Assert.Contains(lines, l => Regex.IsMatch(l, "ROUND 2 종료 .*승자: P2 P3 ====="));
    }

    [Fact]
    public void Kills_team_score_target()
    {
        var (g, lines, p) = SetupKills(4, start: false);
        g.SetTeamMode(true);
        foreach (var (id, t) in new[] { (1, "red"), (2, "blue"), (3, "red"), (4, "blue") }) g.SetTeam(id, t);
        StartQuiet(g);
        g.nextSpawnAt = double.PositiveInfinity;
        Assert.Equal(C.KILLS_TARGET_TEAM_BY_COUNT["off"]["2"], g.killsTarget);
        g.teamScores["red"] = g.killsTarget - 1;
        p(2).lastHit = new LastHit { by = 3, kind = "push", name = "P3" };
        FallOff(p(2));
        g.Tick(TICK);
        Assert.Equal("over", g.phase);
        Assert.Equal("red", g.winnerTeam);
        Assert.Equal(new double[] { 1, 0, 1, 0 }, new[] { p(1).wins, p(2).wins, p(3).wins, p(4).wins });
        Assert.Contains($"  팀 점수: 빨강 {JsNumber.ToJs(g.killsTarget)} : 0 파랑", lines);
    }

    // ---------- 봇 위치·복귀 (test/botpos.test.js) ----------
    static (Game g, Player human, Player bot, BotBrain brain) SetupBot(uint seed)
    {
        var g = new Game();
        g.rng = Lcg(seed);
        var human = g.AddPlayer(1)!;
        var bot = g.AddBot()!;
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        human.x = 8.5;
        human.y = 8.5;
        return (g, human, bot, g.bots[bot.id]);
    }

    static void Set(Player p, double x, double y, double z, bool grounded, double vz = 0, double kbx = 0, double kby = 0)
    {
        (p.x, p.y, p.z, p.grounded, p.vz, p.kbx, p.kby) = (x, y, z, grounded, vz, kbx, kby);
    }

    [Fact]
    public void Bot_falling_off()
    {
        var (g, _, bot, _) = SetupBot(1);
        Set(bot, 5, 5, 0, true);
        Assert.False(BotBrain.FallingOff(g, bot));
        bot.grounded = false;
        bot.z = 1;
        Assert.False(BotBrain.FallingOff(g, bot));
        bot.x = 1;
        bot.kbx = -8;
        Assert.True(BotBrain.FallingOff(g, bot));
        bot.x = -0.5;
        bot.kbx = 0;
        Assert.True(BotBrain.FallingOff(g, bot));
    }

    [Fact]
    public void Bot_recovers_with_air_dash_and_double_jump_10_seeds()
    {
        for (uint seed = 1; seed <= 10; seed++)
        {
            var (g, _, bot, _) = SetupBot(seed);
            Set(bot, 0.8, 5, 0.6, false, vz: 2, kbx: -6);
            bot.stunUntil = 0;
            bool dashed = false;
            for (double t = 0; t < 2500 && bot.alive; t += TICK)
            {
                g.Tick(TICK);
                if (bot.airDashes == 0) dashed = true;
            }
            Assert.True(dashed, $"seed {seed}: 공중 대시");
            Assert.True(bot.alive && bot.grounded && g.InXY((int)Math.Floor(bot.x), (int)Math.Floor(bot.y)), $"seed {seed}: 돌아옴");
        }
    }

    [Fact]
    public void Bot_cannot_recover_while_stunned()
    {
        var (g, _, bot, brain) = SetupBot(2);
        Set(bot, 0.8, 5, 2, false, kbx: -6);
        bot.stunUntil = g.time + 1000;
        Assert.False(brain.Recover(g, bot));
        Assert.Equal(C.AIR_DASHES, bot.airDashes);
    }

    [Fact]
    public void Bot_steps_in_from_edge_10_seeds()
    {
        for (uint seed = 1; seed <= 10; seed++)
        {
            var (g, _, bot, _) = SetupBot(seed);
            Set(bot, 0.4, 5, 0, true);
            Run(g, 1000);
            Assert.True(bot.x > 0.9, $"seed {seed}: x={bot.x}");
        }
    }

    [Fact]
    public void Bot_behind_spot_keeps_edge_margin()
    {
        var (g, human, bot, _) = SetupBot(3);
        human.x = 1.0;
        human.y = 0.6;
        bot.x = 5;
        bot.y = 5;
        Run(g, 2500);
        Assert.True(bot.y >= C.BOT_EDGE_MARGIN - 0.35 && bot.x >= C.BOT_EDGE_MARGIN - 0.35, $"봇 ({bot.x}, {bot.y})");
    }

    [Fact]
    public void Bot_kite_keeps_distance_faces_target_10_seeds()
    {
        for (uint seed = 1; seed <= 10; seed++)
        {
            var (g, human, bot, brain) = SetupBot(seed);
            human.x = 3.5;
            human.y = 5;
            Set(bot, 1.2, 5, 0, true);
            g.bots.Remove(bot.id); // 봇 자체 판단은 끄고 kite 만
            for (double t = 0; t < 2500; t += C.BOT_THINK_MS)
            {
                brain.input.jump = false;
                brain.Kite(g, bot, human, 3);
                g.HandleInput(bot.id, new InputMsg { fwd = brain.input.fwd, strafe = brain.input.strafe, jump = brain.input.jump, yaw = brain.input.yaw, pitch = brain.input.pitch });
                for (double k = 0; k < C.BOT_THINK_MS; k += TICK) g.Tick(TICK);
            }
            double d = JsMath.Hypot(bot.x - human.x, bot.y - human.y);
            Assert.True(bot.alive, $"seed {seed}");
            Assert.True(Math.Abs(d - 3) < 0.8, $"seed {seed}: 거리 {d}");
            Assert.True(Math.Min(Math.Min(bot.x, g.W - bot.x), Math.Min(bot.y, g.D - bot.y)) >= C.BOT_EDGE_MARGIN - 0.3, $"seed {seed}: 끝");
            double want = JsMath.Atan2(human.y - bot.y, human.x - bot.x);
            Assert.True(Math.Abs(want - bot.yaw) < 0.3 || Math.Abs(Math.Abs(want - bot.yaw) - 2 * Math.PI) < 0.3, $"seed {seed}: 상대를 봄");
        }
    }

    [Fact]
    public void Bot_kite_avoids_shadow_spot()
    {
        var (g, human, bot, brain) = SetupBot(4);
        human.x = 5;
        human.y = 5;
        bot.x = 2;
        bot.y = 5;
        var spot = brain.Kite(g, bot, human, 3, new List<int[]> { new[] { 1, 4 }, new[] { 2, 4 }, new[] { 1, 5 }, new[] { 2, 5 }, new[] { 1, 6 }, new[] { 2, 6 } });
        Assert.False(spot.x >= 1 && spot.x < 3 && spot.y >= 4 && spot.y < 7, $"자리 ({spot.x}, {spot.y})");
    }

    [Fact]
    public void Bot_low_recovery_dashes_and_double_jumps_at_once()
    {
        var (g, _, bot, brain) = SetupBot(5);
        Set(bot, -0.3, 5, 0.3, false, vz: 1, kbx: -5);
        bot.stunUntil = 0;
        Assert.True(brain.Recover(g, bot));
        Assert.Equal(0, bot.airDashes);
        Assert.True(bot.airJumpQueued);
    }
}
