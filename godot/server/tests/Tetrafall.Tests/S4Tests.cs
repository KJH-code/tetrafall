using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// S4 아이템·연습·튜토리얼: 판 해시 34개 중 C# 가 다 돌 수 있는 판 (지금 연습 판) 이 JS 와 같음, 튜토리얼 자동 조종 판이 JS 와 같음 (캐릭터가 옮겨진 만큼) +
// test/practice·tutorial.test.js 중 방·연습·튜토리얼 흐름
public class S4Tests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    sealed class Sock : ISocket
    {
        public readonly List<string> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(text);
    }

    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    static List<JsonElement> Events(Game g) => g.DrainEvents().Select(e => JsonDocument.Parse(e).RootElement).ToList();

    static string? Str(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    // test/practice.test.js seeded rng
    static Func<double> Lcg(uint seed)
    {
        uint s = seed;
        return () =>
        {
            s = unchecked(s * 1664525u + 1013904223u);
            return s / 4294967296.0;
        };
    }

    [Fact]
    public void Game_hash_matches_JS_for_every_scenario_CSharp_can_run()
    {
        int ran = 0;
        var notYet = new List<string>();
        foreach (var row in Fixtures.Load("game-hash.json").EnumerateArray())
        {
            var sc = Scenarios.ALL.First(s => s.name == row[0].GetString());
            string hx;
            int ticks;
            try
            {
                hx = Scenarios.Hash(sc, out ticks, out _);
            }
            catch (NotImplementedException)
            {
                notYet.Add(sc.name); // 아직 안 옮긴 곳 (봇 S5 등)
                continue;
            }
            Assert.Equal(row[2].GetInt32(), ticks);
            Assert.True(hx == row[1].GetString(), $"{sc.name}: 판 해시가 JS 와 다름 (Tetrafall.Trace trace + trace-diff)");
            ran++;
        }
        Assert.Empty(notYet); // S5 (봇) 뒤: 34판 전부 = 규칙 이식 끝
        Assert.Equal(34, ran);
    }

    [Fact]
    public void Tutorial_autopilot_rounds_match_JS()
    {
        int ran = 0;
        foreach (var row in Fixtures.Load("tutorial-trace.json").EnumerateArray())
        {
            string ch = row[0].GetString()!;
            using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            (int ticks, bool done, List<string?> results) r;
            try
            {
                r = Scenarios.RunTutorial(ch, (t, logs, snap) => h.AppendData(Encoding.UTF8.GetBytes(Scenarios.TraceLine(t, logs, snap) + "\n")));
            }
            catch (NotImplementedException)
            {
                continue; // 아직 안 옮긴 캐릭터 (S3)
            }
            Assert.Equal(row[1].GetInt32(), r.ticks);
            Assert.True(r.done && row[2].GetBoolean());
            Assert.True(Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant() == row[3].GetString(), $"튜토리얼 {ch}: JS 와 다름 (tutorial-trace.mjs {ch} + Tetrafall.Trace trace tut:{ch})");
            ran++;
        }
        Assert.Equal(8, ran); // 캐릭터 8명 다 (S3 끝)
    }

    // ---------- 연습 (test/practice.test.js) ----------
    sealed class Practice
    {
        public Rooms rooms = null!;
        public Conn a = null!;
        public Game g = null!;
        public Player me = null!;

        public void Msg(string json) => rooms.Message(a, J(json));

        public void Run(double ms)
        {
            for (double t = 0; t < ms; t += TICK) rooms.Tick(TICK);
        }

        public Player Dummy() => g.Dummies()[0];
    }

    static Practice SetupPractice()
    {
        var rooms = new Rooms(rng: Lcg(1));
        var a = rooms.Connect(new Sock());
        rooms.Message(a, J("{\"type\":\"practice\",\"nick\":\"재혁\",\"char\":\"ninja\"}"));
        var g = a.room!.game;
        return new Practice { rooms = rooms, a = a, g = g, me = g.players[a.id] };
    }

    [Fact]
    public void Practice_room_starts_with_one_dummy_and_never_ends()
    {
        var P = SetupPractice();
        var g = P.g;
        Assert.Equal("practice", g.mode);
        Assert.Equal("playing", g.phase);
        Assert.Equal("ninja", P.me.@char);
        Assert.Equal("재혁", P.me.nick);
        Assert.Single(g.Dummies());
        Assert.True(P.Dummy().dummy && P.Dummy().@char == null);
        Assert.Equal(1, g.HumanCount());
        var practice = J(g.Snapshot()).GetProperty("practice");
        Assert.Equal(new[] { "noCooldown", "fullUlt", "noBlocks", "noDeath", "dummies" }, practice.EnumerateObject().Select(x => x.Name));
        Assert.Equal((false, false, true, true), (practice.GetProperty("noCooldown").GetBoolean(), practice.GetProperty("fullUlt").GetBoolean(), practice.GetProperty("noBlocks").GetBoolean(), practice.GetProperty("noDeath").GetBoolean()));
        P.Run(20000);
        Assert.Equal("playing", g.phase);
        Assert.Empty(g.pieces);
        Assert.False(g.lava.active);
    }

    [Fact]
    public void Practice_toggles()
    {
        var P = SetupPractice();
        var g = P.g;
        var me = P.me;
        void Set(string key, string value) => P.Msg($"{{\"type\":\"practiceSet\",\"key\":\"{key}\",\"value\":{value}}}");
        Set("noBlocks", "false");
        P.Run(C.FIRST_SPAWN_DELAY_MS + 500);
        Assert.NotEmpty(g.pieces);
        Set("noBlocks", "true");
        Assert.Empty(g.pieces);
        me.x = 2.5;
        me.y = 2.5;
        me.yaw = 0;
        me.grounded = true;
        me.vz = 0;
        Set("noCooldown", "true");
        P.Msg("{\"type\":\"action\",\"name\":\"skill\"}");
        P.Run(500);
        Assert.True(me.skillReadyAt <= g.time);
        Set("fullUlt", "true");
        P.Run(TICK * 2);
        Assert.Equal(g.UltMax(me), me.ult);
        Set("myDamage", "120");
        Assert.Equal(120, me.damage);
        var home = (me.home!.x, me.home.y);
        me.x = -3;
        me.y = 4;
        me.z = C.FALL_DEATH_Z - 1;
        P.Run(TICK * 2);
        Assert.True(me.alive);
        Assert.Equal(home, (me.x, me.y));
        Assert.Equal(120, me.damage);
        Assert.Empty(g.deaths);
        Set("noDeath", "false");
        me.x = -3;
        me.y = 4;
        me.z = C.FALL_DEATH_Z - 1;
        P.Run(TICK * 2);
        Assert.False(me.alive);
        P.Run(C.PRACTICE_RESPAWN_MS + TICK * 2);
        Assert.True(me.alive);
        Assert.Equal("playing", g.phase);
        Set("noCooldown", "\"yes\"");
        Assert.True(g.practice!.noCooldown);
        Set("myDamage", "\"abc\"");
        Assert.Equal(120, me.damage);
        Set("myDamage", "5000");
        Assert.Equal(C.PRACTICE_DAMAGE_MAX, me.damage);
    }

    [Fact]
    public void Dummies_add_remove_set_and_reset_on_fall()
    {
        var P = SetupPractice();
        var g = P.g;
        P.me.x = 3;
        P.me.y = 5;
        P.me.yaw = 0;
        P.Msg("{\"type\":\"dummyAdd\"}");
        var d2 = g.Dummies()[1];
        Assert.True(Math.Abs(d2.x - (3 + C.PRACTICE_DUMMY_DIST)) < 1e-9 && d2.y == 5);
        for (int k = 0; k < 5; k++) P.Msg("{\"type\":\"dummyAdd\"}");
        Assert.Equal(C.PRACTICE_DUMMY_MAX, g.Dummies().Count);
        P.Msg("{\"type\":\"dummyRemove\"}");
        Assert.Equal(C.PRACTICE_DUMMY_MAX - 1, g.Dummies().Count);
        P.Msg($"{{\"type\":\"dummyRemove\",\"id\":{d2.id}}}");
        Assert.False(g.players.ContainsKey(d2.id));
        Assert.Empty(g.deaths);
        var d = g.Dummies()[0];
        P.Msg($"{{\"type\":\"dummySet\",\"id\":{d.id},\"damage\":150}}");
        Assert.Equal(150, d.damage);
        Assert.Equal(150, J(g.Snapshot()).GetProperty("practice").GetProperty("dummies")[0].GetProperty("damageSet").GetDouble());
        var home = (d.home!.x, d.home.y);
        d.x = -3;
        d.z = C.FALL_DEATH_Z - 1;
        d.damage = 40;
        P.rooms.Tick(TICK);
        Assert.True(d.alive);
        Assert.Equal((home.x, home.y, 150.0), (d.x, d.y, d.damage));
        Assert.Contains(Events(g), e => Str(e, "type") == "practiceReset" && e.GetProperty("who").GetInt32() == d.id && Str(e, "cause") == "fall");
    }

    [Fact]
    public void Practice_map_change_resets_everyone_on_terrain()
    {
        var P = SetupPractice();
        var g = P.g;
        Assert.Equal("flat", g.mapId);
        P.Msg("{\"type\":\"setMap\",\"map\":\"pyramid\"}");
        Assert.Equal("pyramid", g.mapId);
        Assert.Equal("playing", g.phase);
        Assert.Contains(g.grid, v => v == 1);
        Assert.Contains(Events(g), e => Str(e, "type") == "mapChange" && Str(e, "map") == "pyramid");
        var d = P.Dummy();
        Assert.Equal(g.SpawnZ(d.x, d.y), d.z);
        Assert.Equal(g.SpawnZ(P.me.x, P.me.y), P.me.z);
        P.Msg("{\"type\":\"setMap\",\"map\":\"nope\"}");
        Assert.Equal("pyramid", g.mapId);
        P.Msg("{\"type\":\"setMap\",\"map\":\"flat\"}");
        Assert.All(g.grid, v => Assert.Equal(0, v));
    }

    [Fact]
    public void Practice_char_change_mid_round_keeps_position_and_damage()
    {
        var P = SetupPractice();
        var me = P.me;
        me.x = 4.2;
        me.y = 3.3;
        me.damage = 77;
        me.skillReadyAt = P.g.time + 5000;
        P.Msg("{\"type\":\"setChar\",\"char\":\"cannon\"}");
        Assert.Equal("cannon", me.@char);
        Assert.Equal((4.2, 3.3, 77.0), (me.x, me.y, me.damage));
        Assert.Equal(0, me.skillReadyAt);
        Assert.Equal(C.CANNON_AMMO_MAX, me.cannonAmmo);
        Assert.Contains(Events(P.g), e => Str(e, "type") == "charChange" && Str(e, "char") == "cannon");
    }

    // ---------- 튜토리얼 (test/tutorial.test.js) ----------
    static (Rooms rooms, Conn conn, Game g, Player me) SetupTutorial(string ch = "tank")
    {
        var rooms = new Rooms(rng: Lcg(1));
        var conn = rooms.Connect(new Sock());
        rooms.Message(conn, J($"{{\"type\":\"tutorial\",\"nick\":\"재혁\",\"char\":\"{ch}\"}}"));
        var g = conn.room!.game;
        return (rooms, conn, g, g.players[conn.id]);
    }

    static void RunRooms(Rooms rooms, double ms)
    {
        for (double t = 0; t < ms; t += TICK) rooms.Tick(TICK);
    }

    [Fact]
    public void Tutorial_layouts_inside_field_for_all_sizes()
    {
        foreach (var W in new[] { 10, 14, 19 })
        {
            foreach (var st in C.TUTORIAL_STEPS)
            {
                var L = Tutorial.Layout(st, W, W);
                var tops = new Dictionary<(int, int), int>();
                foreach (var c in L.cells)
                {
                    Assert.True(c[0] >= 0 && c[0] < W && c[1] >= 0 && c[1] < W);
                    tops[(c[0], c[1])] = Math.Max(tops.GetValueOrDefault((c[0], c[1])), c[2] + 1);
                }
                int Top(double x, double y) => tops.GetValueOrDefault(((int)Math.Floor(x), (int)Math.Floor(y)));
                bool Inside(double x, double y) => x > 0.4 && x < W - 0.4 && y > 0.4 && y < W - 0.4;
                Assert.True(Inside(L.start.x, L.start.y));
                Assert.Equal(0, Top(L.start.x, L.start.y));
                foreach (var d in L.dummies) Assert.True(Inside(d.x, d.y) && Top(d.x, d.y) == 0);
                if (st.id == "jump") Assert.Equal(st.minZ, Top(L.target!.Value.x, L.target.Value.y));
            }
        }
    }

    [Fact]
    public void Tutorial_skip_to_the_end()
    {
        var (rooms, conn, g, me) = SetupTutorial("hook");
        var steps = C.TUTORIAL_STEPS;
        Assert.Equal("playing", g.phase);
        Assert.Equal(10, g.W);
        var snap = J(g.Snapshot()).GetProperty("tutorial");
        Assert.Equal((0, steps.Length, "move", false, false), (snap.GetProperty("i").GetInt32(), snap.GetProperty("n").GetInt32(), snap.GetProperty("id").GetString(), snap.GetProperty("ok").GetBoolean(), snap.GetProperty("done").GetBoolean()));
        RunRooms(rooms, 500);
        for (int i = 1; i < steps.Length; i++)
        {
            rooms.Message(conn, J("{\"type\":\"tutorialSkip\"}"));
            Assert.Equal(i, g.tutorial!.i);
            Assert.Equal(steps[i].id, g.tutorial.step.id);
            var L = Tutorial.Layout(steps[i], g.W, g.D);
            Assert.Equal(L.dummies.Count, g.Dummies().Count);
            Assert.Equal(L.items.Count, g.items.Count);
            Assert.True(JsMath.Hypot(me.x - L.start.x, me.y - L.start.y) < 1e-6);
            Assert.Equal(steps[i].kind == "climb", g.lava.active);
            RunRooms(rooms, 300);
        }
        rooms.Message(conn, J("{\"type\":\"tutorialSkip\"}"));
        var end = J(g.Snapshot()).GetProperty("tutorial");
        Assert.True(end.GetProperty("done").GetBoolean());
        Assert.Equal(JsonValueKind.Null, end.GetProperty("id").ValueKind);
        Assert.Equal(JsonValueKind.Null, end.GetProperty("target").ValueKind);
        Assert.Equal(steps.Length, g.tutorial!.results.Count(r => r == "skip"));
        Assert.Empty(g.Dummies());
        Assert.False(g.lava.active);
        RunRooms(rooms, 2000);
        Assert.Equal("playing", g.phase);
    }

    [Fact]
    public void Tutorial_ok_then_next_step_and_dummy_names()
    {
        var (rooms, _, g, me) = SetupTutorial();
        var L = Tutorial.Layout(C.TUTORIAL_STEPS[0], g.W, g.D);
        me.x = L.target!.Value.x;
        me.y = L.target.Value.y;
        RunRooms(rooms, 100);
        Assert.NotNull(g.tutorial!.okAt);
        Assert.Equal("ok", g.tutorial.results[0]);
        RunRooms(rooms, C.TUTORIAL_NEXT_MS / 2);
        Assert.Equal(0, g.tutorial.i);
        RunRooms(rooms, C.TUTORIAL_NEXT_MS);
        Assert.Equal(1, g.tutorial.i);
        foreach (var id in new[] { "push", "ringout", "crit", "skill", "ult", "item" })
        {
            while (g.tutorial.step.id != id) g.tutorial.Skip();
            Assert.Single(g.Dummies());
            Assert.Equal("허수아비", g.Dummies()[0].name);
        }
        RunRooms(rooms, 20000);
        Assert.True(g.items.Count <= Tutorial.Layout(g.tutorial.step, g.W, g.D).items.Count); // 단계가 놓은 것 말고는 저절로 안 나옴
    }

    [Fact]
    public void Tutorial_dodge_counts_only_escaped_blocks_and_climb_lava_resets()
    {
        var (rooms, _, g, me) = SetupTutorial();
        while (g.tutorial!.step.id != "dodge") g.tutorial.Skip();
        RunRooms(rooms, C.TUTORIAL_DODGE_EVERY_MS + 100);
        var pc = g.pieces[0];
        Assert.Contains(pc.cells, c => pc.px + c[0] == (int)Math.Floor(me.x) && pc.py + c[1] == (int)Math.Floor(me.y));
        RunRooms(rooms, C.TUTORIAL_DODGE_DROP_Z * C.TUTORIAL_DODGE_STEP_MS + 500);
        Assert.True(me.alive);
        Assert.Equal(0, g.tutorial.Dodged);
        while (g.tutorial.step.id != "climb") g.tutorial.Skip();
        RunRooms(rooms, 5000);
        double z1 = g.lava.z;
        Assert.True(z1 > C.TUTORIAL_LAVA_START_Z);
        RunRooms(rooms, C.TUTORIAL_LAVA_MS_PER_CELL * 3);
        var L = Tutorial.Layout(g.tutorial.step, g.W, g.D);
        Assert.True(me.alive && JsMath.Hypot(me.x - L.start.x, me.y - L.start.y) < 0.3);
        Assert.True(g.lava.z < z1 + 0.5);
    }
}
