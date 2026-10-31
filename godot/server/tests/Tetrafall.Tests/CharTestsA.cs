using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// test/characters.test.js 50~1200 줄 (봇·연습·아이템 쓰는 것은 뒤에 '안 옮김')
public class CharTestsA
{
    const int BUILD = Pieces.CELL.BUILD;
    const int TERRAIN = Pieces.CELL.TERRAIN;

    // F 가 시작됨 (지상 이동 스킬은 준비부터)
    static bool FStarted(List<JsonElement> ev, string type = "charge") => ev.Any(e => e.IsType(type) || e.IsType("skillWindup"));

    static bool True(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;
    static bool IsFalse(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.False;
    static int Len(JsonElement e, string k) => e.GetProperty(k).GetArrayLength();

    static List<BBlock> Bb(Game g, string kind, int owner = 1) => g.bblocks.Values.Where(b => b.kind == kind && b.owner == owner).ToList();

    static PlayerInput In(double fwd = 0, bool jump = false) => new PlayerInput { fwd = fwd, strafe = 0, jump = jump };

    // 매 틱 누르고 있으면 지상 평타가 끝까지 이어져 한 콤보 마무리
    static (Game g, List<string> lines, Func<int, Player> p, List<JsonElement> events) FullChain(string ch, double damage)
    {
        var (g, lines, p) = Setup(ch, "ninja");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        p(2).damage = damage;
        g.DrainEvents();
        var events = new List<JsonElement>();
        for (double t = 0; t < 3000 && !lines.Any(l => l.Contains(" 마무리")); t += TICK)
        {
            Act(g, 1, "push");
            g.Tick(TICK);
            events.AddRange(Events(g));
        }
        return (g, lines, p, events);
    }

    [Fact]
    public void Chars_pick_between_rounds_default_tank_bot_random_log_line_off_game_unchanged()
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.AddPlayer(1);
        Assert.Equal(C.CHAR_DEFAULT, g.players[1].@char);
        g.rng = () => 0.99;
        Assert.Equal(C.CHARACTERS[^1], g.AddBot()!.@char);
        Assert.True(g.SetChar(1, "ninja"));
        Assert.False(g.SetChar(1, "wizard"));
        g.StartRound();
        Assert.False(g.SetChar(1, "tank"), "판 중엔 못 바꿈");
        Assert.Contains($"  캐릭터: P1 닌자 / P2(봇) {C.CHAR_NAMES[C.CHARACTERS[^1]]}", lines);
        var old = new Game();
        old.AddPlayer(1);
        Assert.Null(old.players[1].@char);
        Assert.False(old.SetChar(1, "ninja"));
    }

    [Fact]
    public void Ult_gauge_fills_by_damage_dealt_or_taken_full_to_use_zero_after()
    {
        var (g, _, p) = Setup("tank", "ninja");
        Place(p(1), 4, 4, 0);
        Place(p(2), 5, 4);
        Basic(g, 1);
        double dmg = C.BASIC_ATTACKS["tank"].chain[0].dmg!.Value;
        Assert.Equal(dmg * C.ULT_PER_DAMAGE, p(1).ult);
        Assert.Equal(dmg * C.ULT_PER_DAMAGE, p(2).ult);
        Act(g, 1, "ult");
        Assert.True(p(1).ult > 0, "안 찼으면 안 씀");
        p(1).ult = C.ULT_MAX;
        Run(g, C.STUN_MS + 100);
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
    }

    [Fact]
    public void Tank_less_knockback_charge_stops_on_first_hit_miss_about_3_cells()
    {
        var (g, lines, p) = Setup("tank", "builder", "builder");
        g.ApplyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 20, null, true);
        g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 20, null, true);
        Assert.Equal(20, p(1).damage);
        Assert.Equal(20, p(2).damage);
        Assert.True(Math.Abs(p(1).kbx / p(2).kbx - C.TANK_KB_TAKEN) < 1e-9);
        Run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
        g.ApplyKnockback(p(1), 1, 0, 2, 0, C.STUN_MS, 5, null, false, new KbOpts(fixed_: true));
        g.ApplyKnockback(p(2), 1, 0, 2, 0, C.STUN_MS, 5, null, false, new KbOpts(fixed_: true));
        Assert.Equal(2, p(1).kbx);
        Assert.Equal(2, p(2).kbx);
        Run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
        p(1).damage = 0;
        p(2).damage = 0;
        // 돌진
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 3.5, 4.5);
        Place(p(3), 8.5, 8.5);
        g.DrainEvents();
        Skill(g, 1);
        Assert.True(Events(g).Has("charge", e => e.Num("who") == 1), "돌진 이벤트 (남에게 보이게)");
        Run(g, C.TANK_CHARGE_MS + 100);
        Assert.Equal(C.TANK_CHARGE_DAMAGE, p(2).damage);
        Assert.True(p(1).x < 3.5, $"부딪히고 멈춤 x={p(1).x}");
        Assert.Contains(lines, l => l.StartsWith("  [돌진] P1 → P2"));
        double ready = p(1).skillReadyAt;
        Act(g, 1, "skill");
        Assert.Equal(ready, p(1).skillReadyAt);
        // 빗나가면 약 3칸
        Run(g, C.SKILL_CD_MS["tank"]);
        Place(p(1), 1.5, 1.5, 0);
        Skill(g, 1);
        Run(g, 1000);
        double d = p(1).x - 1.5;
        Assert.True(d > 2.5 && d < 4, $"빗나간 돌진 거리 {d}");
    }

    [Fact]
    public void Tank_slam_rises_then_hits_near_foes_upward()
    {
        var (g, lines, p) = Setup("tank", "ninja", "ninja");
        Place(p(1), 5, 5);
        Place(p(2), 6.5, 5);
        Place(p(3), 9.5, 9.5);
        p(1).ult = C.ULT_MAX;
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.True(Events(g).Has("slamWarn", e => e.NumOr("r") == C.TANK_SLAM_RANGE), "바닥 예고");
        Assert.Equal(0, p(2).damage);
        Run(g, C.TANK_SLAM_WINDUP_MS + TICK);
        Assert.Equal(C.TANK_SLAM_DAMAGE, p(2).damage);
        Assert.True(p(2).vz > 0 || p(2).z > 0.5, "위로 뜸");
        Assert.Equal(0, p(3).damage);
        Assert.Contains("  [필살] P1 내려찍기 (1명)", lines);
    }

    [Fact]
    public void Team_mode_slam_skips_teammates()
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.rng = () => 0.5;
        for (int i = 1; i <= 2; i++) g.AddPlayer(i);
        g.SetChar(1, "tank");
        g.SetTeamMode(true);
        g.SetTeam(1, "red");
        g.SetTeam(2, "red");
        g.AddPlayer(3);
        g.SetChar(3, "ninja");
        g.SetTeam(3, "blue");
        g.StartRound();
        Player p(int id) => g.players[id];
        Place(p(1), 5, 5);
        Place(p(2), 6, 5);
        Place(p(3), 4, 5);
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Run(g, C.TANK_SLAM_WINDUP_MS + TICK);
        Assert.Equal(0, p(2).damage);
        Assert.Equal(C.TANK_SLAM_DAMAGE, p(3).damage);
    }

    public static IEnumerable<object[]> FullChainChars() =>
        C.CHARACTERS.Where(c => C.BASIC_ATTACKS[c].chain[^1].finish && C.BASIC_ATTACKS[c].chain.Length > 1).Select(c => new object[] { c });

    [Theory]
    [MemberData(nameof(FullChainChars))]
    public void Basic_full_chain_one_combo_finish_at_0_and_150(string ch)
    {
        var chain = C.BASIC_ATTACKS[ch].chain;
        foreach (var dmg0 in new double[] { 0, 150 })
        {
            var (_, lines, p, events) = FullChain(ch, dmg0);
            int n = chain.Length;
            Assert.True(lines.Contains($"  [콤보] P1 → P2 {n}타 마무리"), $"{dmg0}%:\n{string.Join("\n", lines)}");
            var eff = chain.Select(d => d.loaded ?? d).ToList();
            Assert.Equal(eff.Sum(d => d.dmg!.Value), p(2).damage - dmg0);
            var atk = events.Where(e => e.IsType("attack") && e.NumOr("who") == 1).ToList();
            Assert.Equal(Enumerable.Range(1, chain.Length).Select(i => (double)i), atk.Select(e => e.Num("n")));
            Assert.Equal(eff.Select(d => d.windup), atk.Select(e => e.Num("windup")));
            Assert.True(atk.All(e => e.Str("char") == ch && IsFalse(e, "air")));
            Assert.True(True(atk[^1], "finish"), "마지막 타 예고");
            var hits = events.Where(e => e.IsType("hit") && e.NumOr("by") == 1).ToList();
            Assert.True(hits.All(e => True(e, "ok")) && True(hits[^1], "finish"));
        }
    }

    [Fact]
    public void Basic_stun_covers_next_hit_only_finish_flagged_full_combo_within_COMBO_MS()
    {
        var sets = C.CHARACTERS.Select(c => (c, C.BASIC_ATTACKS[c].chain, C.BASIC_ATTACKS[c].air))
            .Concat(new[] { ("bard 메탈", C.BASIC_ATTACKS["bard"].metal!.chain, C.BASIC_ATTACKS["bard"].metal!.air) });
        var finishAt = new Dictionary<string, (bool ground, bool air)>
        {
            ["ninja"] = (false, true), ["tank"] = (false, true), ["hunter"] = (false, true), ["bard"] = (false, false), ["bard 메탈"] = (true, true),
        };
        foreach (var (ch, chain, air) in sets)
        {
            var want = finishAt.TryGetValue(ch, out var w) ? w : (ground: true, air: false);
            double t = 0;
            for (int i = 0; i < chain.Length; i++)
            {
                var d = chain[i];
                Assert.True(d.finish == (want.ground && i == chain.Length - 1), $"{ch} {i + 1}타");
                if (i == chain.Length - 1) continue;
                Assert.True(d.stun!.Value >= d.rec + chain[i + 1].windup + 100, $"{ch} {i + 1}타 경직 {d.stun}");
                t += d.rec + chain[i + 1].windup;
            }
            Assert.True(t <= C.COMBO_MS, $"{ch} 최단 {t}");
            for (int i = 0; i < air.Length; i++)
            {
                var d = air[i];
                Assert.True(d.finish == (want.air && i == air.Length - 1), $"{ch} 공중 {i + 1}타");
                if (i < air.Length - 1) Assert.True(d.stun!.Value >= d.rec + air[i + 1].windup + 100, $"{ch} 공중 {i + 1}타 경직");
            }
        }
        Assert.Equal(4, C.BASIC_ATTACKS["ninja"].chain.Length);
        Assert.Equal(2, C.BASIC_ATTACKS["ninja"].air.Length);
        Assert.True(C.BASIC_ATTACKS["ninja"].chain[3].rec > 2 * C.BASIC_ATTACKS["ninja"].chain[2].rec, "연타 마지막 타 뒤 후딜은 김");
    }

    [Fact]
    public void Basic_mid_hit_kb_fixed_finish_scales_with_damage()
    {
        double Kb(double dmg, bool finish)
        {
            var (g, _, p) = Setup("tank", "ninja");
            Place(p(2), 5, 5);
            p(2).damage = dmg;
            var d = C.BASIC_ATTACKS["tank"].chain[finish ? 2 : 0];
            if (finish) g.ApplyKnockback(p(2), 1, 0, 1, 0, 500, 0, null);
            g.ApplyKnockback(p(2), 1, 0, d.kb!.Value, d.up!.Value, d.stun!.Value, d.dmg!.Value, null, finish, new KbOpts(fixed_: !finish, finish: finish));
            return p(2).kbx;
        }
        Assert.Equal(Kb(150, false), Kb(0, false));
        Assert.Equal(C.BASIC_ATTACKS["tank"].chain[0].kb!.Value, Kb(0, false));
        Assert.True(Kb(150, true) > Kb(0, true) * 2);
    }

    [Fact]
    public void Basic_chain_window_whiff_chain_hit_interrupts_windup()
    {
        var (g, _, p) = Setup("tank", "ninja", "ninja");
        var chain = C.BASIC_ATTACKS["tank"].chain;
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        Place(p(3), 9.5, 9.5);
        Basic(g, 1);
        Assert.Equal(1, p(1).chainN);
        Run(g, chain[0].rec + C.BASIC_CHAIN_WINDOW_MS + C.COMBO_IFRAME_MS + 100);
        Place(p(2), 4.2, 4.5);
        g.DrainEvents();
        Basic(g, 1);
        Assert.Equal(1, Events(g).Find("attack")!.Value.Num("n"));
        // 허공 이어 치기
        Run(g, 1000);
        p(1).yaw = Math.PI;
        p(1).chainN = 0;
        Basic(g, 1);
        Assert.False(p(1).atkLanded);
        Assert.Equal(1, p(1).chainN);
        Assert.True(p(1).pushReadyAt - g.time > chain[0].rec - 2 * TICK, "후딜은 다 받음");
        Run(g, p(1).pushReadyAt - g.time + TICK);
        g.DrainEvents();
        Basic(g, 1);
        Assert.Equal(2, Events(g).Find("attack")!.Value.Num("n"));
        // 준비 중에 맞으면 끊김
        Run(g, 1000);
        p(1).yaw = 0;
        Act(g, 1, "push");
        Assert.NotNull(p(1).atk);
        g.ApplyKnockback(p(1), -1, 0, 1, 0, 300, 5, new Src(3, "push"));
        Assert.Null(p(1).atk);
    }

    [Fact]
    public void Basic_air_attack_builder_single_falling_from_above_crits()
    {
        var (g, lines, p) = Setup("builder", "ninja");
        Place(p(1), 3, 4.5, 0, 1);
        (p(1).grounded, p(1).vz) = (false, -1);
        Place(p(2), 4, 4.5);
        g.DrainEvents();
        Act(g, 1, "push");
        var e = Events(g).Find("attack")!.Value;
        var a0 = C.BASIC_ATTACKS["builder"].air[0];
        Assert.Equal(1, e.Num("n"));
        Assert.True(True(e, "air"));
        Assert.Equal(a0.name, e.Str("name"));
        p(1).vz = -1;
        p(1).z = 1;
        Run(g, a0.windup + TICK / 2);
        Assert.True(lines.Any(l => l.Contains("넉백 치명타") && l.EndsWith($"공중 {a0.name}")), string.Join("\n", lines));
        Assert.Equal(JsMath.Round(a0.dmg!.Value * C.CRIT_DAMAGE_MULT), p(2).damage);
    }

    [Fact]
    public void Builder_finish_raises_block_under_target_and_lifts_them()
    {
        var (g, _, p, events) = FullChain("builder", 0);
        int cx = (int)Math.Floor(p(2).x);
        int cy = (int)Math.Floor(p(2).y);
        var rise = events.Find("wallRise", e => e.NumOr("who") == 1);
        Assert.True(rise != null, "블록 솟음 이벤트");
        var c0 = rise!.Value.GetProperty("cells")[0];
        int x = c0[0].GetInt32(), y = c0[1].GetInt32(), z = c0[2].GetInt32();
        Assert.Equal(BUILD, g.GridAt(x, y, z));
        Assert.Equal(0, z);
        Assert.True(Math.Abs(x - cx) <= 1 && Math.Abs(y - cy) <= 1);
        Assert.True(p(2).z >= 1 - 1e-6 || p(2).vz > 0, $"위로 z={p(2).z}");
    }

    [Fact]
    public void Basic_finish_windup_slows_move_no_hammer_item()
    {
        var (g, _, p) = Setup("tank", "ninja");
        Place(p(1), 3, 1.5, 0);
        p(1).atk = new Atk { n = 3, def = C.BASIC_ATTACKS["builder"].chain[2], at = g.time + 10000 };
        p(1).input = In(fwd: 1);
        Run(g, 200);
        double slow = p(1).x - 3;
        Assert.True(Math.Abs(slow - C.MOVE_SPEED * 0.2 * C.BASIC_FINISH_MOVE_MULT) < 0.1, $"{slow}");
        Assert.True(!C.ITEM_POOL.Contains("weapon") && !C.HELD_ITEMS.Contains("weapon"), "망치 아이템 없음");
    }

    [Fact]
    public void Cancel_F_after_landed_basic_cuts_recovery_chain_window_reopens()
    {
        var (g, _, p) = Setup("tank", "ninja");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        Basic(g, 1);
        Assert.True(p(1).atkLanded && g.time < p(1).pushReadyAt, "맞힌 뒤 후딜 중");
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.True(FStarted(Events(g)), "바로 돌진 (지상이라 준비부터)");
        Assert.True(p(1).pushReadyAt <= g.time, "후딜 끊김");
        Assert.True(p(1).chainUntil > g.time && p(1).chainN == 1, "이어 치기 창");
    }

    [Fact]
    public void Cancel_F_after_whiffed_basic_is_queued_until_recovery_ends()
    {
        var (g, _, p) = Setup("tank", "ninja");
        Place(p(1), 3, 4.5, Math.PI);
        Place(p(2), 4.2, 4.5);
        Basic(g, 1);
        Assert.False(p(1).atkLanded);
        double ready = p(1).pushReadyAt;
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.False(FStarted(Events(g)), "후딜 중엔 안 나감");
        Assert.Equal("skill", p(1).castQueued);
        Run(g, ready - g.time - TICK);
        Assert.False(FStarted(Events(g)));
        Run(g, 2 * TICK);
        Assert.True(FStarted(Events(g)), "후딜 끝나고 나감");
    }

    [Fact]
    public void Cancel_F_during_basic_windup_waits_for_hit_R_too()
    {
        foreach (var hit in new[] { true, false })
        {
            var (g, _, p) = Setup("tank", "ninja");
            Place(p(1), 3, 4.5, hit ? 0 : Math.PI);
            Place(p(2), 4.2, 4.5);
            Act(g, 1, "push");
            double at = p(1).atk!.at;
            g.DrainEvents();
            Act(g, 1, "skill");
            Assert.True(p(1).atk != null, "준비 중인 평타는 안 취소");
            Run(g, at - g.time + TICK / 2);
            var ev = Events(g);
            Assert.True(ev.Has("swing"), "평타 나감");
            Assert.Equal(hit, FStarted(ev));
            if (!hit)
            {
                Run(g, p(1).pushReadyAt - g.time + TICK);
                Assert.True(FStarted(Events(g)), "후딜 뒤 스킬");
            }
        }
        {
            var (g, _, p) = Setup("tank", "ninja");
            Place(p(1), 3, 4.5, 0);
            Place(p(2), 4.2, 4.5);
            p(1).ult = C.ULT_MAX;
            Act(g, 1, "push");
            Act(g, 1, "ult");
            Assert.Equal(C.ULT_MAX, p(1).ult);
            Run(g, p(1).atk!.at - g.time + TICK / 2);
            Assert.Equal(0, p(1).ult);
            Assert.True(p(1).slamAt > 0);
        }
    }

    // p3(갈고리)가 p1 뒤에서 평타 1타. prep 으로 p1 의 상태를 만든 뒤
    static (List<string> lines, List<JsonElement> ev, Func<int, Player> p, Game g) HitBy3(Action<Game, Func<int, Player>> prep, string first = "tank")
    {
        var (g, lines, p) = Setup(first, "ninja", "hook");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 8.5, 8.5);
        Place(p(3), 2, 4.5, 0);
        prep(g, p);
        g.DrainEvents();
        Basic(g, 3);
        return (lines, Events(g), p, g);
    }

    static bool Countered((List<string> lines, List<JsonElement> ev, Func<int, Player> p, Game g) r) => r.ev.Has("counter");

    [Fact]
    public void Counter_hit_during_whiff_recovery_skill_ult_windup()
    {
        var hookDef = C.BASIC_ATTACKS["hook"].chain[0];
        var walk = HitBy3((g, p) => p(1).input = In(fwd: 1));
        Assert.False(Countered(walk), "걷기만은 아님");
        var rec = HitBy3((g, p) =>
        {
            p(1).yaw = Math.PI / 2;
            Basic(g, 1);
        });
        Assert.True(rec.ev.Has("counter", e => e.NumOr("by") == 3 && e.NumOr("target") == 1), "이벤트");
        Assert.True(rec.lines.Contains("  [카운터] P3 → P1"), string.Join("\n", rec.lines));
        Assert.True(Math.Abs(rec.p(1).stunUntil - rec.p(1).counterAt!.Value - hookDef.stun!.Value * C.COUNTER_STUN_MULT) < 1e-6, "경직 길게");
        Assert.Equal(C.BASIC_HITSTOP_MS * C.COUNTER_HITSTOP_MULT, rec.p(3).freezeUntil - rec.p(1).counterAt!.Value);
        Assert.True(Countered(HitBy3((g, p) =>
        {
            p(1).yaw = Math.PI / 2;
            Act(g, 1, "skill");
            p(1).wallAt = g.time + 10000;
        }, "builder")), "솟는 벽 준비");
        Assert.False(Countered(HitBy3((g, p) =>
        {
            p(1).ult = C.ULT_MAX;
            Act(g, 1, "ult");
            p(1).slamAt = g.time + 10000;
        })), "탱크 내려찍기 준비 = 아머");
        Assert.False(Countered(HitBy3((g, p) =>
        {
            p(1).yaw = Math.PI / 2;
            Act(g, 1, "skill");
            p(1).chargeUntil = g.time + 10000;
            p(1).chargeDir = new XY(0, 0);
        })), "탱크 돌진 = 아머");
    }

    [Fact]
    public void Not_counter_basic_windup_landed_recovery_trade_already_stunned()
    {
        Assert.False(Countered(HitBy3((g, p) =>
        {
            Act(g, 1, "push");
            p(1).atk!.at = g.time + 10000;
        })), "준비 중");
        Assert.False(Countered(HitBy3((g, p) =>
        {
            Place(p(2), 4.2, 4.5);
            Basic(g, 1);
            Assert.True(p(1).atkLanded && g.time < p(1).pushReadyAt);
        })), "맞힌 뒤 후딜");
        {
            var (g, _, p) = Setup("tank", "ninja");
            Place(p(1), 3, 4.5, 0);
            Place(p(2), 4.2, 4.5, Math.PI);
            g.DrainEvents();
            Act(g, 1, "push");
            Act(g, 2, "push");
            Run(g, 300);
            var ev = Events(g);
            Assert.False(ev.Has("counter"), "동시에 누른 평타끼리는 카운터 아님");
            Assert.True(ev.Has("hit", e => e.NumOr("by") == 2 && True(e, "ok")));
            Assert.True(ev.Has("interrupt", e => e.NumOr("who") == 1 && e.Str("kind") == "basic" && e.NumOr("n") == 1), "탱크 평타 끊김");
            Assert.False(ev.Has("hit", e => e.NumOr("by") == 1), "끊긴 평타는 안 나감");
        }
        var r = HitBy3((g, p) =>
        {
            p(1).yaw = Math.PI / 2;
            Basic(g, 1);
        });
        var at = r.p(1).counterAt;
        Run(r.g, 200);
        r.p(3).pushReadyAt = 0;
        r.p(3).chainN = 0;
        Basic(r.g, 3);
        Assert.Equal(at, r.p(1).counterAt);
        Assert.Equal(2, r.p(1).comboHits);
    }

    [Fact]
    public void Interrupted_attacks_cost_nothing()
    {
        var (g, _, p) = Setup("tank", "ninja");
        List<JsonElement> Hit(bool finish = false)
        {
            g.ApplyKnockback(p(1), -1, 0, 1, 0, 300, 5, new Src(2, "push"), finish, new KbOpts(finish: finish));
            return Events(g).Where(e => e.IsType("interrupt") && e.NumOr("who") == 1).ToList();
        }
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 8.5, 8.5);
        Act(g, 1, "push");
        g.DrainEvents();
        Assert.Equal(new[] { "basic,1" }, Hit().Select(e => $"{e.Str("kind")},{e.GetProperty("n").GetRawText()}"));
        Assert.True(p(1).pushReadyAt <= g.time, "후딜 없음");
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "skill");
        Act(g, 1, "ult");
        Assert.True(p(1).skillReadyAt <= g.time);
        Assert.Equal(C.ULT_MAX, p(1).ult);
        Assert.Null(p(1).castQueued);
        Run(g, 1000);
        // 돌진 중에 맞음
        Place(p(1), 3, 4.5, Math.PI / 2);
        Act(g, 1, "skill");
        Assert.True(p(1).skillReadyAt > g.time);
        g.DrainEvents();
        Assert.Equal(new[] { "skill" }, Hit(true).Select(e => e.Str("kind")));
        Assert.True(p(1).skillReadyAt <= g.time, "쿨 돌려받음");
        Run(g, 1000);
        // 내려찍기 준비 중
        Place(p(1), 3, 4.5, 0);
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        g.DrainEvents();
        Assert.Equal(new[] { "ult" }, Hit(true).Select(e => e.Str("kind")));
        Assert.Equal(C.ULT_MAX, p(1).ult);
        Run(g, 1000);
        // 기억한 F 가 지워짐
        Place(p(1), 3, 4.5, 0);
        Act(g, 1, "push");
        Act(g, 1, "skill");
        Assert.Equal("skill", p(1).castQueued);
        g.DrainEvents();
        Hit();
        Assert.Null(p(1).castQueued);
        Assert.True(p(1).skillReadyAt <= g.time, "스킬 쿨 그대로");
        Run(g, 1000);
        Assert.False(Events(g).Has("charge"), "나중에도 안 나감");
    }

    [Fact]
    public void Log_finish_combo_line_after_its_basic_line()
    {
        var (_, lines, _, _) = FullChain("builder", 0);
        int i = lines.FindIndex(l => l.Contains("[콤보] P1 → P2 3타 마무리"));
        Assert.True(i > 0 && lines[i - 1].Contains("[평타] P1 → P2") && lines[i - 1].EndsWith("3타 내려찍기"), string.Join("\n", lines));
    }

    [Fact]
    public void Builder_F_ground_wall_rises_lifts_foe_expires()
    {
        var (g, lines, p) = Setup("builder", "ninja");
        Place(p(1), 4.5, 4.5, 0);
        Place(p(2), 5.5, 4.5);
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.True(Events(g).Has("wallWarn", e => Len(e, "cells") == 3), "바닥 예고");
        Assert.Equal(0, g.GridAt(5, 4, 0));
        Run(g, C.BUILDER_WALL_WARN_MS + TICK);
        foreach (var y in new[] { 3, 4, 5 }) Assert.Equal(BUILD, g.GridAt(5, y, 0));
        Assert.Equal(0, g.GridAt(5, 4, 1));
        Assert.Equal(C.BUILDER_WALL_DAMAGE, p(2).damage);
        Assert.True(p(2).z >= 1 - 1e-6, $"벽 위로 올라감 z={p(2).z}");
        Assert.True(lines.Contains("  [스킬] P1 솟는 벽 (3칸, 1명 띄움)"), string.Join("\n", lines));
        var walls = Bb(g, "wall");
        Assert.Equal(3, walls.Count);
        Assert.Single(walls.Select(b => b.group).Distinct());
        Assert.True(Events(g).Has("bblock", e => e.Str("kind") == "wall" && Len(e, "cells") == 3 && e.NumOr("ms") == C.BUILDER_BLOCK_MS));
        Assert.Equal(3, JsonDocument.Parse(g.Snapshot()).RootElement.GetProperty("bblocks").GetArrayLength());
        Assert.True(p(1).skillReadyAt > g.time + C.SKILL_CD_MS["builder"] - C.BUILDER_WALL_WARN_MS - 3 * TICK, $"쿨 {p(1).skillReadyAt - g.time}");
        Run(g, C.BUILDER_BLOCK_MS);
        Assert.Equal(0, g.GridAt(5, 4, 0));
        Assert.Empty(Bb(g, "wall"));
        Assert.True(Events(g).Has("bblockGone", e => e.Str("why") == "expire"));
    }

    [Fact]
    public void Builder_hammer_blasts_own_wall_group_only_forward()
    {
        var (g, lines, p) = Setup("builder", "ninja", "tank");
        Place(p(1), 2.5, 4.5, 0);
        Place(p(2), 4.6, 4.5);
        Place(p(3), 1.9, 4.5);
        Act(g, 1, "skill");
        Run(g, C.BUILDER_WALL_WARN_MS + TICK);
        g.PlaceBBlock(p(1), 3, 6, 0, "wall", 999);
        g.PlaceBBlock(p(1), 3, 2, 0, "third", 998);
        // 상대 평타로는 안 터짐
        Place(p(3), 1.9, 4.5, 0);
        p(3).pushReadyAt = 0;
        Basic(g, 3);
        Assert.Equal(BUILD, g.GridAt(3, 4, 0));
        Run(g, 1000);
        (p(2).damage, p(2).ult) = (0, 0);
        p(3).damage = 0;
        p(1).damage = 0;
        Place(p(1), 2.5, 4.5, 0);
        Place(p(2), 4.6, 4.5);
        Place(p(3), 1.9, 4.5);
        p(1).ult = 0;
        p(1).pushReadyAt = 0;
        p(1).chainN = 0;
        g.DrainEvents();
        Basic(g, 1);
        foreach (var y in new[] { 3, 4, 5 }) Assert.Equal(0, g.GridAt(3, y, 0));
        Assert.Equal(BUILD, g.GridAt(3, 6, 0));
        Assert.Equal(BUILD, g.GridAt(3, 2, 0));
        Assert.Equal(3 * C.BUILDER_BLAST_DAMAGE, p(2).damage);
        Assert.True(p(2).kbx > 0 && Math.Abs(p(2).kby) < 1e-9, "치는 방향 앞으로");
        Assert.Equal(0, p(3).damage);
        Assert.Equal(0, p(1).damage);
        Assert.Equal(3 * C.BUILDER_BLAST_ULT + 3 * C.BUILDER_BLAST_DAMAGE * C.ULT_PER_DAMAGE, p(1).ult);
        var ev = Events(g).Find("blast")!.Value;
        Assert.Equal(3, Len(ev, "cells"));
        Assert.Equal("{\"x\":1,\"y\":0}", ev.GetProperty("dir").GetRawText());
        Assert.True(lines.Any(l => l.StartsWith("  [폭발] P1 벽 3칸 → P2")), string.Join("\n", lines));
        Assert.Equal("blast", p(2).lastHit!.kind);
    }

    [Fact]
    public void Builder_third_hit_block_under_foe_or_ahead_max_3_not_under_me()
    {
        {
            var (g, _, p) = Setup("builder", "ninja");
            Place(p(1), 3.8, 4.5, 0);
            Place(p(2), 4.6, 4.5);
            (p(1).chainN, p(1).chainUntil) = (2, double.PositiveInfinity);
            Basic(g, 1);
            Run(g, 300);
            Assert.True(p(1).z < 0.5, $"나는 안 뜸 z={p(1).z}");
            var b = Bb(g, "third").FirstOrDefault();
            Assert.True(b != null && b.x >= 5, $"블록은 내 몸과 안 겹치는 앞 칸 x={b?.x}");
        }
        {
            var (g2, _, p2) = Setup("builder", "ninja");
            Place(p2(2), 9.5, 9.5);
            foreach (var y in new[] { 1.5, 3.5, 5.5, 7.5 })
            {
                Place(p2(1), 1.5, y, 0);
                g2.BasicRaise(p2(1), null);
                Run(g2, 10);
            }
            var thirds = Bb(g2, "third");
            Assert.Equal(C.BUILDER_THIRD_MAX, thirds.Count);
            Assert.Equal(new[] { "3,3", "3,5", "3,7" }, thirds.Select(t => $"{t.x},{t.y}").OrderBy(s => s, StringComparer.Ordinal));
            Assert.Equal(0, g2.GridAt(3, 1, 0));
        }
    }

    [Fact]
    public void Builder_F_air_pillar_2_cells_stand_on_top_shared_cd_off_field_boost_only()
    {
        var (g, lines, p) = Setup("builder", "ninja");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 4.5, 4.5, 0, 2.5);
        (p(1).grounded, p(1).vz) = (false, -3);
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.Equal(2, C.BUILDER_PAD_HEIGHT);
        Assert.Equal(BUILD, g.GridAt(4, 4, 1));
        Assert.Equal(BUILD, g.GridAt(4, 4, 0));
        var pads = Bb(g, "pad");
        Assert.Equal(2, pads.Count);
        Assert.Single(pads.Select(b => b.group).Distinct());
        Assert.True(pads.All(b => b.expiresAt == g.time + C.BUILDER_BLOCK_MS), "수명");
        Assert.Equal(2, p(1).z);
        Assert.Equal(0, p(1).vz);
        Assert.True(p(1).grounded);
        var ev = Events(g);
        Assert.True(ev.Has("padBoost", e => e.NumOr("who") == 1 && True(e, "stand") && Len(e, "cells") == 2));
        Assert.True(ev.Has("bblock", e => e.Str("kind") == "pad" && Len(e, "cells") == 2));
        Assert.True(p(1).skillReadyAt > g.time, "쿨");
        Run(g, 300);
        Assert.True(p(1).grounded && Math.Abs(p(1).z - 2) < 1e-6, $"서 있음 z={p(1).z}");
        Assert.True(lines.Contains("  [스킬] P1 발판 기둥 2칸 (4,4,0~1)"), string.Join("\n", lines));
        Run(g, C.BUILDER_BLOCK_MS + 100);
        Assert.Empty(Bb(g, "pad"));
        Assert.Equal(0, g.GridAt(4, 4, 1));
        Assert.Equal(0, g.GridAt(4, 4, 0));
        Place(p(1), 2.5, 2.5, 0);
        p(1).skillReadyAt = g.time + 1000;
        Act(g, 1, "skill");
        Assert.Equal(0, p(1).wallAt);
        // 필드 밖에서 떨어지는 중
        Run(g, C.SKILL_CD_MS["builder"]);
        Place(p(1), -0.8, 4.5, 0, -0.5);
        (p(1).grounded, p(1).vz) = (false, -5);
        Act(g, 1, "skill");
        Assert.Equal(C.BUILDER_PAD_BOOST, p(1).vz);
        Assert.Contains("  [스킬] P1 발판 (칸 없이 부스트)", lines);
    }

    [Fact]
    public void Builder_R_big_bomb_3x3_rises_explodes_after_fuse_hammer_early()
    {
        {
            var (g, lines, p) = Setup("builder", "ninja");
            Place(p(1), 1.5, 4.5, 0);
            Place(p(2), 4.5, 4.5);
            g.PlaceBBlock(p(1), 6, 4, 0, "wall", 900);
            g.PlaceBBlock(p(1), 9, 9, 0, "third", 901);
            p(1).ult = C.ULT_MAX;
            g.DrainEvents();
            Act(g, 1, "ult");
            Assert.Equal(0, p(1).ult);
            var big = Bb(g, "big");
            Assert.Equal(9, big.Count);
            Assert.Equal(new[] { 3, 4, 5 }, big.Select(b => b.x).Distinct().OrderBy(x => x));
            Assert.True(p(2).z >= 1 - 1e-6, $"위로 z={p(2).z}");
            Assert.True(Events(g).Has("bigBombWarn", e => Len(e, "cells") == 9 && e.NumOr("ms") == C.BUILDER_BIG_FUSE_MS));
            p(2).damage = 0;
            Run(g, C.BUILDER_BIG_FUSE_MS - 2 * TICK);
            Assert.Equal(9, Bb(g, "big").Count);
            Run(g, 3 * TICK);
            Assert.Empty(Bb(g, "big"));
            Assert.Equal(C.BUILDER_BIG_DAMAGE, p(2).damage);
            Assert.Equal("bigbomb", p(2).lastHit!.kind);
            Assert.Equal(0, g.GridAt(6, 4, 0));
            Assert.Equal(BUILD, g.GridAt(9, 9, 0));
            Assert.Equal(C.BUILDER_BLAST_ULT + C.BUILDER_BIG_DAMAGE * C.ULT_PER_DAMAGE, p(1).ult);
            Assert.True(lines.Any(l => l.Contains("[필살] P1 대폭발 (1명, 같이 터진 블록 1칸)")), string.Join("\n", lines));
        }
        {
            var (g2, _, q) = Setup("builder", "ninja");
            Place(q(1), 1.5, 4.5, 0);
            Place(q(2), 9.5, 9.5);
            q(1).ult = C.ULT_MAX;
            Act(g2, 1, "ult");
            Place(q(1), 2.4, 4.5, 0);
            Basic(g2, 1);
            Assert.Empty(Bb(g2, "big"));
            Assert.Empty(g2.bigBombs);
        }
    }

    // JS 끝 부분 (C.BUILDER_BLAST_HOLE 을 켜고 구멍 확인) 은 안 옮김: C# 에선 BUILDER_BLAST_HOLE 이 const 라 테스트에서 못 켬
    [Fact]
    public void Builder_blocks_removed_cells_forgotten_layer_drop_moves_down()
    {
        var (g, _, p) = Setup("builder", "ninja");
        Place(p(2), 9.5, 9.5);
        g.PlaceBBlock(p(1), 5, 5, 0, "third", 1);
        g.grid[g.Idx(5, 5, 0)] = 0;
        Run(g, TICK);
        Assert.Empty(g.bblocks);
        g.PlaceBBlock(p(1), 5, 5, 1, "third", 2);
        g.DropLayers(new List<int> { 0 });
        Assert.True(g.bblocks.ContainsKey(GameUtil.CellKey(5, 5, 0)), "한 층 내려감");
    }

    [Fact]
    public void Builder_pad_pillar_blasts_with_hammer_chain_falls_gauge()
    {
        var (g, lines, p) = Setup("builder", "ninja");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 4.5, 4.5, 0, 2.5);
        (p(1).grounded, p(1).vz) = (false, -3);
        Act(g, 1, "skill");
        Run(g, 300);
        Assert.True(p(1).grounded && Math.Abs(p(1).z - 2) < 1e-6, $"기둥 위 z={p(1).z}");
        p(1).ult = 0;
        p(1).chainN = 0;
        Basic(g, 1);
        Assert.Equal(0, g.GridAt(4, 4, 1));
        Assert.Equal(0, g.GridAt(4, 4, 0));
        Assert.Empty(Bb(g, "pad"));
        Assert.Equal(C.BUILDER_BLAST_ULT * 2, p(1).ult);
        Assert.True(lines.Any(l => l.StartsWith("  [폭발] P1 발판 2칸")), string.Join("\n", lines));
        Run(g, 600);
        Assert.True(p(1).z < 2 - 0.5, $"떨어짐 z={p(1).z}");
    }

    [Fact]
    public void Builder_air_F_pillar_blocked_cases()
    {
        var (g, _, p) = Setup("builder", "ninja");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 4.5, 4.5, 0, 1.3);
        (p(1).grounded, p(1).vz) = (false, -3);
        Act(g, 1, "skill");
        Assert.Single(Bb(g, "pad"));
        Assert.Equal(BUILD, g.GridAt(4, 4, 0));
        Assert.Equal(1, p(1).z);
        // 밑에 블록 (z 1)
        Run(g, C.BUILDER_BLOCK_MS + 100);
        g.grid[g.Idx(6, 6, 1)] = (byte)TERRAIN;
        g.grid[g.Idx(6, 6, 0)] = (byte)TERRAIN;
        Place(p(1), 6.5, 6.5, 0, 3.4);
        (p(1).grounded, p(1).vz, p(1).skillReadyAt) = (false, -3, 0);
        Act(g, 1, "skill");
        Assert.Equal(new[] { 2 }, Bb(g, "pad").Select(b => b.z));
        Assert.Equal(3, p(1).z);
        // 바로 밑 칸이 막힘
        Run(g, C.BUILDER_BLOCK_MS + 100);
        g.grid[g.Idx(2, 2, 2)] = (byte)TERRAIN;
        Place(p(1), 2.5, 2.5, 0, 3.6);
        (p(1).grounded, p(1).vz, p(1).skillReadyAt) = (false, -3, 0);
        Act(g, 1, "skill");
        Assert.Empty(Bb(g, "pad"));
        Assert.Equal(C.BUILDER_PAD_BOOST, p(1).vz);
        // 아래 칸에 다른 사람
        Place(p(2), 7.5, 2.5, 0, 0);
        Place(p(1), 7.5, 2.5, 0, 3.5);
        (p(1).grounded, p(1).vz, p(1).skillReadyAt) = (false, -3, 0);
        Act(g, 1, "skill");
        Assert.True(Bb(g, "pad").All(b => b.z >= 1), "사람이 있는 칸엔 안 세움");
        Assert.False(Bb(g, "pad").Any(b => b.z == 0));
    }

    [Fact]
    public void Ninja_basic_ground_4_jump_air_2_one_combo()
    {
        var chain = C.BASIC_ATTACKS["ninja"].chain;
        var air = C.BASIC_ATTACKS["ninja"].air;
        foreach (var dmg0 in new double[] { 0, 150 })
        {
            var (g, lines, p) = Setup("ninja", "builder");
            Place(p(1), 3, 4.5, 0);
            Place(p(2), 4.2, 4.5);
            p(2).damage = dmg0;
            var ev = new List<JsonElement>();
            for (double t = 0; t < 4000 && !lines.Any(l => l.Contains(" 마무리")); t += TICK)
            {
                var last = ev.Where(e => e.IsType("hit") && e.NumOr("by") == 1).Select(e => (JsonElement?)e).LastOrDefault();
                p(1).input = In(jump: last != null && last.Value.NumOr("n") == 4 && !True(last.Value, "air"));
                p(1).yaw = JsMath.Atan2(p(2).y - p(1).y, p(2).x - p(1).x);
                Act(g, 1, "push");
                g.Tick(TICK);
                ev.AddRange(Events(g));
            }
            var atk = ev.Where(e => e.IsType("attack") && e.NumOr("who") == 1).Select(e => $"{(True(e, "air") ? "공중" : "지상")}{e.Num("n")}");
            Assert.Equal(new[] { "지상1", "지상2", "지상3", "지상4", "공중1", "공중2" }, atk);
            Assert.True(lines.Contains("  [콤보] P1 → P2 6타 마무리"), string.Join("\n", lines));
            Assert.Equal(chain.Sum(d => d.dmg!.Value) + air.Sum(d => d.dmg!.Value), p(2).damage - dmg0);
            Assert.True(lines.Any(l => l.EndsWith("공중 2타 내려 차기")), "로그 이름");
        }
    }

    [Fact]
    public void Ninja_switch_targets_hit_number_and_streak_continue()
    {
        var (g, _, p) = Setup("ninja", "builder", "tank");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        Place(p(3), 3, 5.7, Math.PI / 2);
        Basic(g, 1);
        Run(g, C.BASIC_ATTACKS["ninja"].chain[0].rec);
        p(1).yaw = Math.PI / 2;
        g.DrainEvents();
        Basic(g, 1);
        var ev = Events(g);
        Assert.Equal(2, ev.Find("attack")!.Value.Num("n"));
        var h = ev.Find("hit", e => e.NumOr("target") == 3);
        Assert.True(h != null && True(h.Value, "ok") && h.Value.NumOr("streak") == 2, $"streak {h?.NumOr("streak")}");
        Assert.True(ev.Has("streak", e => e.NumOr("who") == 1 && e.NumOr("n") == 2 && e.NumOr("target") == 3));
        Assert.Equal(2, p(2).comboHits + p(3).comboHits);
    }

    [Fact]
    public void Ninja_F_damage_cd_cut_air_wallkick()
    {
        var (g, lines, p) = Setup("ninja", "tank", "tank");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 3, 4.6);
        Place(p(3), 9.5, 9.5);
        Skill(g, 1);
        Assert.True(Math.Abs(p(1).x - (3 + C.NINJA_BLINK_BEHIND)) < 0.11, $"상대 바로 뒤 x={p(1).x}");
        Assert.Equal(C.NINJA_SLASH_DAMAGE, p(2).damage);
        Assert.Equal(8, C.NINJA_SLASH_DAMAGE);
        // 평타 적중마다 쿨 감소
        Run(g, 1000);
        double ready = p(1).skillReadyAt;
        Place(p(1), 2, 4.5, 0);
        Place(p(2), 3, 4.5);
        p(1).chainN = 0;
        Basic(g, 1);
        Assert.Equal(ready - C.NINJA_HIT_CD_CUT_MS, p(1).skillReadyAt);
        // 공중 + 벽 차기
        Run(g, C.SKILL_CD_MS["ninja"]);
        for (int y = 0; y < C.GRID_D; y++) g.grid[g.Idx(5, y, 1)] = (byte)BUILD;
        g.GridChanged();
        Place(p(2), 4.2, 3.5);
        Place(p(1), 2.5, 4.5, 0, 1.2);
        (p(1).grounded, p(1).vz) = (false, -1);
        p(2).damage = 0;
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.True(p(1).x <= 5 - C.PLAYER_HALF + 1e-9 && p(1).x > 4.4, $"블록 앞 x={p(1).x}");
        Assert.Equal(C.NINJA_WALLKICK_UP, p(1).vz);
        var ev = Events(g);
        Assert.True(ev.Has("wallKick", e => e.NumOr("who") == 1));
        Assert.True(lines.Any(l => l.Contains("[스킬] P1 벽 차기")), string.Join("\n", lines));
        // 막힌 데가 없으면 벽 차기 없음
        Run(g, C.SKILL_CD_MS["ninja"]);
        for (int y = 0; y < C.GRID_D; y++) g.grid[g.Idx(5, y, 1)] = 0;
        g.GridChanged();
        Place(p(1), 1.5, 8.5, 0);
        g.DrainEvents();
        Skill(g, 1);
        Assert.False(Events(g).Has("wallKick"));
    }

    [Fact]
    public void Ninja_R_empower_star_volley_4th_unchanged_ends()
    {
        var (g, _, p) = Setup("ninja", "builder");
        var S = C.NINJA_STAR;
        Place(p(1), 2, 4.5, 0);
        Place(p(2), 4.5, 4.5);
        p(1).ult = C.ULT_MAX;
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        Assert.True(Events(g).Has("empower", e => e.NumOr("ms") == C.NINJA_EMPOWER_MS));
        Act(g, 1, "push");
        Run(g, S["windup"] + S["gap"] + 2 * TICK);
        var ev = Events(g);
        Assert.True(ev.Has("attack", e => True(e, "star") && e.NumOr("n") == 1));
        Assert.Equal(2, ev.Count(e => e.IsType("star")));
        Assert.Equal(2 * S["dmg"], p(2).damage);
        Assert.True(S["stun"] < C.BASIC_ATTACKS["ninja"].chain[0].stun!.Value, "경직은 근접보다 짧게");
        Assert.True(2 * S["dmg"] > C.BASIC_ATTACKS["ninja"].chain[0].dmg!.Value, "딜은 조금 더");
        // 4타는 올려 차기 그대로
        p(1).chainN = 3;
        p(1).chainUntil = double.PositiveInfinity;
        p(1).pushReadyAt = 0;
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.Equal("올려 차기", Events(g).Find("attack")!.Value.Str("name"));
        // 끝나면 원래대로
        Run(g, C.NINJA_EMPOWER_MS);
        p(1).chainN = 0;
        p(1).pushReadyAt = 0;
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.Equal("찌르기", Events(g).Find("attack")!.Value.Str("name"));
    }

    [Fact]
    public void Ninja_passive_speed_kb_taken_air_jump_refresh_on_falling_block()
    {
        var (g, _, p) = Setup("ninja", "builder");
        Place(p(1), 1.5, 1.5, 0);
        Place(p(2), 1.5, 8.5, 0);
        p(1).input = In(fwd: 1);
        p(2).input = In(fwd: 1);
        Run(g, 500);
        Assert.True(Math.Abs(p(1).x - p(2).x) < 1e-6, "이속 같음");
        p(1).input = p(2).input = In();
        Run(g, 500);
        g.ApplyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 0, null, true);
        g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 0, null, true);
        Assert.True(Math.Abs(p(1).kbx / p(2).kbx - C.NINJA_KB_TAKEN) < 1e-9);
        Run(g, 1500);
        var piece = new Piece { id = 0, shape = "O", rot = 0, cells = new[] { new[] { 0, 0 } }, px = 5, py = 5, pz = 3, landZ = 0, fits = false };
        g.AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.stepMs = 100000;
            pc.nextStepAt = g.time + 100000;
            pc.controlEndsAt = 0;
        });
        Place(p(1), 4.68, 5.5, 0, 3.2);
        (p(1).grounded, p(1).vz, p(1).airJumps) = (false, 0, 0);
        g.DrainEvents();
        g.Tick(TICK);
        Assert.Equal(C.AIR_JUMPS, p(1).airJumps);
        Assert.True(Events(g).Has("ninjaTouch", e => e.NumOr("who") == 1));
        p(1).airJumps = 0;
        g.Tick(TICK);
        Assert.Equal(0, p(1).airJumps);
    }

    [Fact]
    public void Tank_basic_three_ground_jump_air_finish_one_combo()
    {
        var chain = C.BASIC_ATTACKS["tank"].chain;
        var air = C.BASIC_ATTACKS["tank"].air;
        var (g, lines, p) = Setup("tank", "builder");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        var ev = new List<JsonElement>();
        for (double t = 0; t < 4000 && !lines.Any(l => l.Contains(" 마무리")); t += TICK)
        {
            var last = ev.Where(e => e.IsType("hit") && e.NumOr("by") == 1).Select(e => (JsonElement?)e).LastOrDefault();
            p(1).input = In(jump: last != null && last.Value.NumOr("n") == 3 && !True(last.Value, "air"));
            p(1).yaw = JsMath.Atan2(p(2).y - p(1).y, p(2).x - p(1).x);
            Act(g, 1, "push");
            g.Tick(TICK);
            ev.AddRange(Events(g));
        }
        var atk = ev.Where(e => e.IsType("attack") && e.NumOr("who") == 1).Select(e => $"{(True(e, "air") ? "공중" : "지상")}{e.Num("n")}");
        Assert.Equal(new[] { "지상1", "지상2", "지상3", "공중1" }, atk);
        Assert.True(lines.Contains("  [콤보] P1 → P2 4타 마무리"), string.Join("\n", lines));
        Assert.Equal(chain.Sum(d => d.dmg!.Value) + air[0].dmg!.Value, p(2).damage);
    }

    [Fact]
    public void Tank_armor_during_charge_damage_only_breaks_on_finish()
    {
        var (g, lines, p) = Setup("tank", "ninja", "builder");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 1.5, 3.5);
        Place(p(3), 9.5, 9.5);
        Skill(g, 1);
        g.DrainEvents();
        double x0 = p(1).x;
        Assert.True(g.ApplyKnockback(p(1), 0, 1, 5, 3, 500, 7, new Src(2, "push")));
        Assert.Equal(7, p(1).damage);
        Assert.True(p(1).stunUntil <= g.time && p(1).kby == 0, "넉백·경직 없음");
        Assert.True(g.time < p(1).chargeUntil, "돌진 계속");
        var ev = Events(g);
        Assert.True(ev.Has("armor", e => e.NumOr("who") == 1 && e.NumOr("by") == 2));
        Assert.False(ev.Has("counter"));
        Assert.True(lines.Contains("  [아머] P1 ← P2 버팀 (P1 7%)"), string.Join("\n", lines));
        Run(g, C.TANK_CHARGE_MS);
        Assert.True(p(1).x - x0 > 2, $"끝까지 돌진 {p(1).x - x0}");
        // 마무리 타면 깨짐
        Run(g, C.SKILL_CD_MS["tank"]);
        Place(p(1), 1.5, 4.5, 0);
        Skill(g, 1);
        g.DrainEvents();
        g.ApplyKnockback(p(1), 0, 1, 5, 3, 500, 7, new Src(2, "push"), true, new KbOpts(finish: true));
        var ev2 = Events(g);
        Assert.True(ev2.Has("armorBreak", e => e.NumOr("who") == 1));
        Assert.True(ev2.Has("interrupt", e => e.NumOr("who") == 1 && e.Str("kind") == "skill"));
        Assert.True(p(1).stunUntil > g.time && p(1).kby > 0, "보통처럼 맞음");
        Assert.False(ev2.Has("counter"), "깨질 때도 카운터 없음");
    }

    [Fact]
    public void Tank_R_armor_while_rising_ring_quake_lifts_then_sinks()
    {
        var (g, lines, p) = Setup("tank", "ninja", "builder");
        Place(p(1), 5, 5);
        Place(p(2), 5 + C.TANK_SLAM_RANGE + 0.6, 5);
        Place(p(3), 9.5, 0.5);
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        g.DrainEvents();
        g.ApplyKnockback(p(1), 1, 0, 5, 3, 500, 4, new Src(3, "push"));
        Assert.True(Events(g).Has("armor"), "떠오르는 동안 아머");
        Assert.True(p(1).slamAt > 0, "내려찍기 계속");
        Run(g, C.TANK_SLAM_WINDUP_MS + TICK);
        var riseN = Events(g).Find("quakeRise");
        Assert.True(riseN != null && Len(riseN.Value, "cells") > 0 && riseN.Value.NumOr("ms") == C.TANK_RING_MS);
        var cells = riseN!.Value.GetProperty("cells").EnumerateArray().Select(c => new[] { c[0].GetInt32(), c[1].GetInt32(), c[2].GetInt32() }).ToList();
        double Dist(int[] c) => JsMath.Hypot(c[0] + 0.5 - 5, c[1] + 0.5 - 5);
        var hitCell = cells.First(c => c[0] == Math.Floor(p(2).x - 0.01) || Dist(c) > C.TANK_SLAM_RANGE);
        Assert.Equal(BUILD, g.GridAt(hitCell[0], hitCell[1], hitCell[2]));
        Assert.True(cells.All(c => Dist(c) > C.TANK_SLAM_RANGE), "바깥 고리만");
        Assert.True(p(2).z >= 1 - 1e-6 || p(2).vz > 0, $"띄움 z={p(2).z}");
        Assert.True(p(2).alive, "압사 없음");
        Assert.True(lines.Any(l => l.Contains("솟는 땅 1명")), string.Join("\n", lines));
        Run(g, C.TANK_RING_MS + TICK);
        Assert.True(cells.All(c => g.GridAt(c[0], c[1], c[2]) == 0), "가라앉음");
        Assert.True(Events(g).Has("quakeFall"));
    }

    [Fact]
    public void Tank_passive_only_less_knockback_taken_gauge_same()
    {
        var (g, _, p) = Setup("tank", "builder");
        g.ApplyKnockback(p(1), 1, 0, 1, 0, 300, 10, new Src(2, "push"));
        Assert.Equal(10 * C.ULT_PER_DAMAGE, p(1).ult);
        Assert.Null(typeof(C).GetField("TANK_ULT_TAKEN_MULT"));
        Assert.Null(typeof(C).GetProperty("TANK_ULT_TAKEN_MULT"));
        Assert.Equal(10 * C.ULT_PER_DAMAGE, p(2).ult);
        Assert.Equal(0.92, C.TANK_KB_TAKEN);
    }

    // 매 타를 누를 수 있게 된 뒤 delay ms 늦게 누름. 띄우는 마지막 지상 타 뒤엔 점프
    static (List<string> lines, List<JsonElement> ev, double ms) LateCombo(string ch, double delay)
    {
        var (g, lines, p) = Setup(ch, "builder");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        int launchN = C.BASIC_ATTACKS[ch].chain.Length;
        var ev = new List<JsonElement>();
        double? first = null;
        for (double t = 0; t < 5000 && !lines.Any(l => l.Contains(" 마무리")); t += TICK)
        {
            var last = ev.Where(e => e.IsType("hit") && e.NumOr("by") == 1).Select(e => (JsonElement?)e).LastOrDefault();
            p(1).input = In();
            if (last != null && last.Value.NumOr("n") == launchN && !True(last.Value, "air") && p(1).grounded) Act(g, 1, "jump");
            p(1).yaw = JsMath.Atan2(p(2).y - p(1).y, p(2).x - p(1).x);
            if (p(1).atk == null && g.time >= p(1).pushReadyAt + delay) Act(g, 1, "push");
            g.Tick(TICK);
            foreach (var e in Events(g))
            {
                ev.Add(e);
                if (e.IsType("hit") && e.NumOr("by") == 1 && first == null) first = g.time;
            }
        }
        return (lines, ev, g.time - first!.Value);
    }

    [Fact]
    public void No_time_finish_during_chain_late_presses_still_finish()
    {
        foreach (var (ch, n) in new[] { ("ninja", 6), ("tank", 4) })
        {
            var (lines, _, ms) = LateCombo(ch, 60);
            Assert.True(lines.Contains($"  [콤보] P1 → P2 {n}타 마무리"), $"{ch}:\n{string.Join("\n", lines)}");
            Assert.True(ms > C.COMBO_MS, $"{ch} 콤보 {ms}ms > COMBO_MS");
        }
    }

    [Fact]
    public void No_infinite_combo_bounded_and_skill_hits_time_finish()
    {
        foreach (var ch in C.CHARACTERS)
        {
            var (g, lines, p) = Setup(ch, "builder");
            Place(p(1), 3, 4.5, 0);
            Place(p(2), 4.2, 4.5);
            int launchN = C.BASIC_ATTACKS[ch].chain.Length;
            JsonElement? lastHit = null;
            for (double t = 0; t < 8000; t += TICK)
            {
                (p(1).x, p(1).y) = (3, 4.5);
                (p(2).x, p(2).y) = (p(1).x + 1.1, p(1).y);
                p(2).z = Math.Max(p(2).z, 0);
                p(1).yaw = 0;
                p(1).input = In(jump: lastHit != null && lastHit.Value.NumOr("n") == launchN && !True(lastHit.Value, "air"));
                Act(g, 1, "push");
                Act(g, 1, "skill");
                p(1).skillReadyAt = Math.Min(p(1).skillReadyAt, g.time + 1000);
                g.Tick(TICK);
                foreach (var e in Events(g))
                    if (e.IsType("hit") && e.NumOr("by") == 1 && e.TryGetProperty("n", out var nv) && nv.ValueKind == JsonValueKind.Number && nv.GetDouble() != 0) lastHit = e;
            }
            var lens = lines.Where(l => l.Contains("[콤보] P1 → P2")).Select(l => int.Parse(Regex.Match(l, @"(\d+)타").Groups[1].Value)).ToList();
            Assert.True(lens.Count > (ch == "berserker" || ch == "bard" ? 0 : 1), $"{ch}: 콤보가 끝나고 다시 시작");
            var set = C.BASIC_ATTACKS[ch];
            int bound = set.chain.Length + set.air.Length + 4;
            Assert.True(lens.Max() <= bound, $"{ch}: 최대 {lens.Max()}타 (상한 {bound}) {string.Join(",", lens)}");
        }
        {
            var (g, _, p) = Setup("ninja", "builder");
            Place(p(2), 5, 5);
            g.ApplyKnockback(p(2), 1, 0, 1, 0, 2000, 1, new Src(1, "push"));
            Run(g, C.COMBO_MS + TICK);
            g.ApplyKnockback(p(2), 1, 0, 1, 0, 600, 1, new Src(1, "slash"));
            Assert.Equal(0, p(2).comboHits);
        }
        {
            var (g, _, p) = Setup("ninja", "builder");
            Place(p(2), 5, 5);
            g.ApplyKnockback(p(2), 1, 0, 1, 0, 2000, 1, new Src(1, "push"));
            Run(g, C.COMBO_MS + TICK);
            g.ApplyKnockback(p(2), 1, 0, 1, 0, 600, 1, new Src(1, "push"), false, new KbOpts(fixed_: true, chained: true));
            Assert.Equal(2, p(2).comboHits);
        }
    }

    [Fact]
    public void Jump_buffer_remembers_jump_during_hitstop()
    {
        var (g, _, p) = Setup("ninja", "builder");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 8.5, 8.5);
        p(1).freezeUntil = g.time + 100;
        p(1).input = In();
        Act(g, 1, "jump");
        Run(g, 150);
        Assert.True(p(1).z > 0.1 || p(1).vz > 0, $"뜀 z={p(1).z}");
        Run(g, 1500);
        p(1).freezeUntil = g.time + C.JUMP_BUFFER_MS + 100;
        Act(g, 1, "jump");
        Run(g, C.JUMP_BUFFER_MS + 200);
        Assert.True(p(1).z < 0.05, "버퍼 지나면 안 뜀");
    }
}

// 안 옮김: 봇: 돌진·순간 베기 길에 피할 칸(내가 던진 블록 그림자 등)이 있으면 안 씀 — 봇 머리(useSkills)는 S5
// 안 옮김: 봇 건축가: 떨어지면 공중 F 로 복귀, 내 블록 너머에 상대가 있으면 블록을 쳐서 터뜨림, 상대가 앞 3×3 쯤이면 대폭발 — 봇 머리(update·useSkills)는 S5
// 안 옮김: 봇 닌자: 필드 밖으로 떨어지면 안쪽으로 공중 F, R 은 표창 사거리 안 상대에게 — 봇 머리(update·useSkills)는 S5
// 일부만: 건축가 블록: … 테스트 옵션 BUILDER_BLAST_HOLE — 구멍 부분은 C# 에서 BUILDER_BLAST_HOLE 이 const 라 못 켜서 뺌 (앞 두 부분은 옮김)
