using Tetrafall.Core;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// test/quake.test.js (탱크 R 솟는 땅 이벤트 id) + test/windup.test.js (이동 스킬 예고) — 연습 모드가 끼는 부분은 S4
public class WindupQuakeTests
{
    static (Game g, Player p) QuakeSetup()
    {
        var g = new Game(characters: true);
        g.rng = () => 0.5;
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.SetChar(1, "tank");
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        var p = g.players[1];
        (p.x, p.y, p.z) = (5, 5, 0);
        (g.players[2].x, g.players[2].y) = (0.5, 0.5);
        return (g, p);
    }

    [Fact]
    public void Quake_rise_and_fall_share_id_new_id_each_rise()
    {
        var (g, p) = QuakeSetup();
        g.DrainEvents();
        g.TankRing(p);
        var r1 = Events(g).Find("quakeRise")!.Value;
        int id1 = (int)r1.Num("id");
        Assert.Equal(r1.Num("id"), id1);
        Run(g, C.TANK_RING_MS + TICK * 2);
        var f1 = Events(g).Find("quakeFall")!.Value;
        Assert.Equal(id1, f1.Num("id"));
        Assert.Equal(r1.Cells("cells"), f1.Cells("gone"));
        Assert.Equal(f1.Cells("gone"), f1.Cells("cells"));
        g.TankRing(p);
        var r2 = Events(g).Find("quakeRise")!.Value;
        Assert.NotEqual(id1, r2.Num("id"));
    }

    [Fact]
    public void Quake_keeps_id_when_layer_cleared_cells_moved_down()
    {
        var (g, p) = QuakeSetup();
        for (int x = 0; x < g.W; x++) for (int y = 0; y < g.D; y++) g.grid[g.Idx(x, y, 0)] = Pieces.CELL.TERRAIN;
        g.GridChanged();
        p.z = 1;
        g.DrainEvents();
        g.TankRing(p);
        var rise = Events(g).Find("quakeRise")!.Value;
        Assert.All(rise.GetProperty("cells").EnumerateArray(), c => Assert.Equal(1, c[2].GetInt32()));
        g.DropLayers(new List<int> { 0 });
        Run(g, C.TANK_RING_MS + TICK * 2);
        var fall = Events(g).Find("quakeFall")!.Value;
        Assert.Equal(rise.Num("id"), fall.Num("id"));
        var gone = fall.GetProperty("gone").EnumerateArray().ToList();
        Assert.True(gone.Count > 0 && gone.All(c => c[2].GetInt32() == 0), "내려간 칸");
    }

    [Fact]
    public void Quake_dropped_on_new_round_emits_empty_fall()
    {
        var (g, p) = QuakeSetup();
        g.TankRing(p);
        var rise = Events(g).Find("quakeRise")!.Value;
        g.EndRound(null);
        g.StartRound();
        var fall = Events(g).Find("quakeFall")!.Value;
        Assert.Equal($"{{\"type\":\"quakeFall\",\"id\":{rise.Num("id")},\"gone\":[],\"cells\":[]}}", fall.GetRawText());
    }

    // ---------- windup.test.js ----------

    [Fact]
    public void Windup_values_and_chars()
    {
        Assert.Equal(150, C.SKILL_WINDUP_MS);
        Assert.Equal(new[] { "hook", "ninja", "tank" }, C.SKILL_WINDUP_CHARS.OrderBy(x => x, StringComparer.Ordinal));
    }

    [Theory]
    [InlineData("tank")]
    [InlineData("ninja")]
    [InlineData("hook")]
    public void Windup_on_ground_then_fires_in_pressed_direction(string ch)
    {
        var (g, lines, p) = Setup(ch, "builder", "builder");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 4, 4.6);
        Place(p(3), 9.5, 9.5);
        g.DrainEvents();
        Act(g, 1, "skill");
        var ev = Events(g);
        Assert.True(ev.Has("skillWindup", e => e.Num("who") == 1 && e.Str("kind") == ch && e.Num("ms") == C.SKILL_WINDUP_MS), ch);
        Assert.False(ev.Has("skill"), "아직 안 나감");
        Assert.True(p(1).skillReadyAt > g.time, "쿨타임은 누를 때");
        Assert.Contains($"  [스킬] P1 {C.CHAR_NAMES[ch]} F 준비", lines);
        p(1).yaw = Math.PI;
        Run(g, C.SKILL_WINDUP_MS - TICK);
        Assert.False(Events(g).Has("skill"), "준비 중");
        Assert.Equal(0, p(2).damage);
        Run(g, 2 * TICK);
        Assert.True(Events(g).Has("skill", e => e.Num("who") == 1), "나감");
        if (ch == "tank") Assert.True(p(1).chargeDir!.x > 0.99, "돌진은 누른 방향");
        if (ch == "ninja") Assert.True(p(1).x > 4, $"순간 베기는 누른 방향 x={p(1).x}");
        if (ch == "hook")
        {
            Assert.True(p(1).hookFly != null && Math.Cos(p(1).hookFly!.yaw) > 0.99, "갈고리는 누른 방향으로 던짐");
            Run(g, C.HOOK_FLY_MS + TICK);
        }
        Run(g, 400);
        Assert.True(p(2).damage > 0, "맞음");
    }

    [Fact]
    public void Windup_in_air_fires_at_once_other_chars_never_wind_up()
    {
        foreach (var ch in new[] { "tank", "ninja", "hook" })
        {
            var (g, _, p) = Setup(ch, "builder");
            Place(p(1), 1.5, 4.5, 0, 1);
            Place(p(2), 9.5, 9.5);
            (p(1).grounded, p(1).vz) = (false, 1);
            g.DrainEvents();
            Act(g, 1, "skill");
            var ev = Events(g);
            Assert.False(ev.Has("skillWindup"), ch);
            Assert.True(ev.Has("skill", e => e.Num("who") == 1), $"{ch}: 바로 나감");
            Assert.Null(p(1).windup);
        }
        foreach (var ch in new[] { "builder", "hunter", "cannon", "berserker" })
        {
            var (g, _, p) = Setup(ch, "tank");
            Place(p(1), 4.5, 4.5, 0);
            Place(p(2), 9.5, 9.5);
            g.DrainEvents();
            Act(g, 1, "skill");
            Assert.False(Events(g).Has("skillWindup"), ch);
            Assert.Null(p(1).windup);
        }
    }

    [Fact]
    public void Windup_interrupted_by_hit_refunds_cooldown_and_is_counter_target()
    {
        var (g, _, p) = Setup("ninja", "tank", "builder");
        Place(p(1), 3, 4.5, Math.PI);
        Place(p(2), 2, 4.5, 0);
        Place(p(3), 9.5, 9.5);
        Act(g, 1, "skill");
        Assert.NotNull(p(1).windup);
        Assert.True(g.Busy(p(1)), "준비 중 = 카운터 대상");
        g.DrainEvents();
        g.ApplyKnockback(p(1), 1, 0, 3, 1, 300, 5, new Src(2, "push"));
        var ev = Events(g);
        Assert.True(ev.Has("interrupt", e => e.Num("who") == 1 && e.Str("kind") == "skill"));
        Assert.Null(p(1).windup);
        Assert.Equal(g.time, p(1).skillReadyAt);
        Run(g, C.SKILL_WINDUP_MS + TICK);
        Assert.False(Events(g).Has("skill", e => e.Num("who") == 1), "끊긴 F 는 안 나감");
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Hook_hit_decided_when_hook_arrives(bool dodge)
    {
        var (g, lines, p) = Setup("hook", "ninja");
        Place(p(1), 1.5, 4.5, 0, 0.5);
        (p(1).grounded, p(1).vz) = (false, 0);
        Place(p(2), 4.5, 4.5);
        g.DrainEvents();
        Act(g, 1, "skill");
        var ev = Events(g);
        Assert.True(ev.Has("hookThrow", e => e.Num("who") == 1 && e.Num("ms") == C.HOOK_FLY_MS));
        Assert.False(ev.Has("hook"), "아직 안 닿음");
        Assert.True(p(1).skillReadyAt > g.time, "쿨타임");
        Assert.Equal(0, p(2).damage);
        if (dodge) Place(p(2), 4.5, 6.5);
        while (p(1).hookFly != null) g.Tick(TICK);
        var hit = Events(g).Find("hook");
        Assert.NotNull(hit);
        if (dodge)
        {
            Assert.Equal(System.Text.Json.JsonValueKind.Null, hit!.Value.GetProperty("target").ValueKind);
            Assert.Equal(0, p(2).damage);
            Assert.Contains("  [스킬] P1 갈고리 빗나감", lines);
        }
        else
        {
            Assert.Equal(2, hit!.Value.Num("target"));
            Assert.Equal(C.HOOK_DAMAGE, p(2).damage);
        }
    }

    [Fact]
    public void Hook_on_ground_windup_plus_flight_interrupt_refunds()
    {
        var (g, _, p) = Setup("hook", "ninja", "tank");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 4.5, 4.5);
        Place(p(3), 9.5, 9.5);
        Act(g, 1, "skill");
        Run(g, C.SKILL_WINDUP_MS + TICK);
        Assert.NotNull(p(1).hookFly);
        Assert.Equal(0, p(2).damage);
        g.DrainEvents();
        g.ApplyKnockback(p(1), 0, 1, 3, 1, 300, 5, new Src(3, "push"));
        Assert.True(Events(g).Has("interrupt", e => e.Num("who") == 1 && e.Str("kind") == "skill"));
        Assert.Null(p(1).hookFly);
        Assert.Equal(g.time, p(1).skillReadyAt);
        Run(g, C.HOOK_FLY_MS + TICK);
        Assert.Equal(0, p(2).damage);
    }
}
