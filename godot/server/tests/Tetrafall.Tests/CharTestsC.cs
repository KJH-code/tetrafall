using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// test/characters.test.js 2002줄부터 끝까지 (광전사 분노 ~ 팀전 같은 팀 공격 없음). 봇 테스트는 S5
public class CharTestsC
{
    static bool Ok(JsonElement e) => e.TryGetProperty("ok", out var v) && v.ValueKind == JsonValueKind.True;

    static bool Hit(JsonElement e, string kind) => e.IsType("hit") && e.Str("kind") == kind && Ok(e);

    static JsonElement Snap(Game g) => JsonDocument.Parse(g.Snapshot()).RootElement;

    static JsonElement SnapP(Game g, int id) => Snap(g).GetProperty("players").EnumerateArray().First(x => x.GetProperty("id").GetInt32() == id);

    static void Air(Player p, double vz)
    {
        p.grounded = false;
        p.vz = vz;
    }

    // ---------- 광전사 ----------

    [Fact]
    public void Berserker_rage_scales_knockback_fixed_unchanged_others_none()
    {
        double Kb(string ch, double dmg, KbOpts opts = default)
        {
            var (g, _, p) = Setup(ch, "tank");
            Place(p(2), 5, 5);
            p(1).damage = dmg;
            g.ApplyKnockback(p(2), 1, 0, 4, 0, 600, 0, new Src(1, "push"), true, opts);
            return p(2).kbx;
        }
        var b = Kb("berserker", 0);
        foreach (var d in new double[] { 100, 200, 300, 500 })
            Assert.True(Math.Abs(Kb("berserker", d) / b - (1 + d * C.BERSERKER_RAGE_PER_PERCENT)) < 1e-9, $"{d}%");
        Assert.Equal(Kb("berserker", 0, new KbOpts(fixed_: true)), Kb("berserker", 300, new KbOpts(fixed_: true)));
        Assert.Equal(Kb("hunter", 0), Kb("hunter", 300));
        double Swing(double dmg, bool air)
        {
            var (g, _, p) = Setup("berserker", "tank");
            Place(p(1), 4, 5, 0, air ? 1 : 0);
            if (air) p(1).grounded = false;
            Place(p(2), 5.2, 5, 0, air ? 1 : 0);
            p(1).damage = dmg;
            Basic(g, 1);
            return p(2).kbx;
        }
        Assert.True(Swing(0, false) > 0);
        Assert.Equal(Swing(0, false), Swing(200, false));
        Assert.True(Math.Abs(Swing(200, true) / Swing(0, true) - (1 + 200 * C.BERSERKER_RAGE_PER_PERCENT)) < 1e-6, "공중 회전 베기는 분노 배율");
    }

    [Fact]
    public void Berserker_basic_wide_swing_then_slam_air_spin_all_around()
    {
        var (g, _, p) = Setup("berserker", "tank", "builder");
        Place(p(1), 4, 5, 0);
        Place(p(2), 4 + 2.0, 5);
        Place(p(3), 1, 1);
        Basic(g, 1);
        Assert.Equal(7, p(2).damage);
        Run(g, 350);
        Basic(g, 1);
        Assert.Equal(17, p(2).damage);
        var (qg, _, qp) = Setup("berserker", "tank");
        Place(qp(1), 4, 5, 0, 1);
        qp(1).grounded = false;
        Place(qp(2), 3, 5, 0, 1);
        Basic(qg, 1);
        Assert.Equal(8, qp(2).damage);
        Assert.True(qp(2).kbx < 0, "바깥(뒤)으로");
    }

    [Fact]
    public void Berserker_leap_lands_with_shockwave_interrupted_leap_has_none()
    {
        var (g, lines, p) = Setup("berserker", "tank");
        Place(p(1), 2, 5, 0);
        Place(p(2), 6.8, 5);
        Act(g, 1, "skill");
        Assert.NotNull(p(1).rush);
        Assert.True(p(1).skillReadyAt >= g.time + C.SKILL_CD_MS["berserker"] - 1);
        g.DrainEvents();
        Run(g, 1200);
        Assert.True(Math.Abs(p(1).x - (2 + C.BERSERKER_LEAP_DIST)) < 0.4, $"x {p(1).x}");
        Assert.Null(p(1).rush);
        Assert.True(C.BERSERKER_WAVE_DAMAGE == p(2).damage, string.Join("\n", lines));
        Assert.True(p(2).kbx > 0);
        var (qg, _, qp) = Setup("berserker", "tank");
        Place(qp(1), 2, 5, 0);
        Place(qp(2), 6.8, 5);
        Act(qg, 1, "skill");
        Run(qg, 200);
        qg.ApplyKnockback(qp(1), -1, 0, 1, 0, 300, 1, new Src(2, "push"));
        Run(qg, 1500);
        Assert.Equal(0, qp(2).damage);
    }

    [Fact]
    public void Berserker_spin_cuts_rage_slows_pushes_out_end_blast_interrupted_by_hit()
    {
        var (ag, _, ap) = Setup("berserker", "tank");
        Assert.Equal(20, C.BERSERKER_RAGE_CUT);
        Assert.Equal(0.3, C.BERSERKER_SPIN_MOVE_MULT);
        ap(1).damage = 15;
        ap(1).ult = C.ULT_MAX;
        Act(ag, 1, "ult");
        Assert.Equal(0, ap(1).damage);
        Assert.NotNull(ap(1).spin);
        Place(ap(1), 4, 3, Math.PI / 2);
        ap(1).input = new PlayerInput { fwd = 1, strafe = 0, jump = false };
        var y0 = ap(1).y;
        Run(ag, 300);
        var sp = (ap(1).y - y0) / 0.3;
        Assert.True(Math.Abs(sp - C.MOVE_SPEED * C.BERSERKER_SPIN_MOVE_MULT) < 0.2, $"회전 중 속도 {sp:F2}");
        var (bg50, _, bp50) = Setup("berserker", "tank");
        bp50(1).damage = 50;
        bp50(1).ult = C.ULT_MAX;
        Act(bg50, 1, "ult");
        Assert.Equal(50 - C.BERSERKER_RAGE_CUT, bp50(1).damage);
        double SpinKb(double startDmg)
        {
            var (g, lines, p) = Setup("berserker", "tank");
            Place(p(1), 4, 5, 0);
            Place(p(2), 5, 5);
            p(1).damage = startDmg;
            p(1).ult = C.ULT_MAX;
            Act(g, 1, "ult");
            Assert.Equal(startDmg - Math.Min(C.BERSERKER_RAGE_CUT, startDmg), p(1).damage);
            int ticks = 0;
            bool @out = true;
            double endKb = 0;
            for (double t = 0; t < C.BERSERKER_SPIN_MS + 200; t += TICK)
            {
                g.Tick(TICK);
                foreach (var e in Events(g))
                {
                    if (Hit(e, "spin"))
                    {
                        ticks++;
                        if (p(2).kbx <= 0) @out = false;
                    }
                    if (Hit(e, "spinend")) endKb = p(2).kbx;
                }
                if (p(1).spin != null) (p(2).x, p(2).y, p(2).z) = (5, 5, 0);
            }
            Assert.True(ticks >= 5, $"작은 밀침 {ticks}번");
            Assert.True(@out, "바깥으로만 (빨아들이지 않음)");
            Assert.True(endKb > 0, string.Join("\n", lines));
            return endKb;
        }
        var k200 = SpinKb(200);
        var k40 = SpinKb(40);
        double After(double d) => d - Math.Min(C.BERSERKER_RAGE_CUT, d);
        Assert.True(Math.Abs(k200 / k40 - (1 + After(200) * C.BERSERKER_RAGE_PER_PERCENT) / (1 + After(40) * C.BERSERKER_RAGE_PER_PERCENT)) < 1e-6, "끝 날림 = 깎은 뒤 분노");
        var (bg, _, bp) = Setup("berserker", "tank");
        Place(bp(1), 4, 5, 0);
        Place(bp(2), 8, 5);
        bp(1).ult = C.ULT_MAX;
        Act(bg, 1, "ult");
        Run(bg, 300);
        bg.DrainEvents();
        bg.ApplyKnockback(bp(1), -1, 0, 1, 0, 300, 1, new Src(2, "push"));
        Assert.Null(bp(1).spin);
        Assert.True(Events(bg).Has("interrupt", e => e.Num("who") == 1 && e.Str("kind") == "ult"));
        Assert.Equal(0, SnapP(bg, 1).GetProperty("berserker").Num("spinLeft"));
    }

    // ---------- 바드 ----------

    [Fact]
    public void Bard_form_switch_riff_heal_cooldown_basic_per_form()
    {
        var (g, lines, p) = Setup("bard", "tank");
        Assert.Equal("bard", p(1).form);
        Place(p(1), 4, 5, 0);
        Place(p(2), 5.2, 5);
        Act(g, 1, "skill");
        Assert.Equal("metal", p(1).form);
        Assert.Equal(C.BARD_RIFF_DAMAGE, p(2).damage);
        Assert.True(p(2).kbx > 0);
        Assert.True(p(1).skillReadyAt >= g.time + C.SKILL_CD_MS["bard"] - 1);
        Act(g, 1, "skill");
        Assert.Equal("metal", p(1).form);
        Run(g, 1500);
        Place(p(1), 4, 5, 0);
        Place(p(2), 5.2, 5);
        var before = p(2).damage;
        Basic(g, 1);
        Assert.Equal(C.BASIC_ATTACKS["bard"].metal.chain[0].dmg, p(2).damage - before);
        Run(g, C.SKILL_CD_MS["bard"]);
        p(1).damage = 25;
        Act(g, 1, "skill");
        Assert.Equal("bard", p(1).form);
        Assert.Equal(25 - C.BARD_HEAL, p(1).damage);
        Assert.True(lines.Any(l => l.Contains("[스킬] P1 음유시인 폼 (치유 P1 25% → 15%)")), string.Join("\n", lines));
        Run(g, C.SKILL_CD_MS["bard"]);
        Act(g, 1, "skill");
        Run(g, C.SKILL_CD_MS["bard"]);
        p(1).damage = 4;
        Act(g, 1, "skill");
        Assert.Equal(0, p(1).damage);
        p(1).form = "metal";
        g.Respawn(p(1));
        Assert.Equal("bard", p(1).form);
    }

    [Fact]
    public void Bard_heal_team_mode_heals_near_mates_only()
    {
        var g = new Game(_ => { }, characters: true);
        g.rng = () => 0.5;
        for (int i = 1; i <= 4; i++) g.AddPlayer(i);
        g.SetChar(1, "bard");
        g.SetTeamMode(true);
        g.SetTeam(1, "red");
        g.SetTeam(2, "red");
        g.SetTeam(3, "red");
        g.SetTeam(4, "blue");
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        Player p(int id) => g.players[id];
        while (g.phase != "playing") g.Tick(TICK);
        Place(p(1), 3, 5);
        Place(p(2), 4, 5);
        Place(p(3), 3 + C.BARD_HEAL_RANGE + 2, 5);
        Place(p(4), 3, 6);
        p(1).form = "metal";
        for (int i = 1; i <= 4; i++) p(i).damage = 50;
        Act(g, 1, "skill");
        Assert.Equal(new double[] { 40, 40, 50, 50 }, new[] { 1, 2, 3, 4 }.Select(i => p(i).damage).ToArray());
    }

    [Fact]
    public void Bard_note_slow_projectile_weak_kb_slow_refreshes_not_stacks()
    {
        var (g, _, p) = Setup("bard", "tank");
        Place(p(1), 2, 5, 0);
        Place(p(2), 6, 5);
        g.DrainEvents();
        Basic(g, 1);
        Assert.Equal(0, p(2).damage);
        Assert.True(Events(g).Has("noteFire", e => e.Num("who") == 1));
        Assert.Equal(1, Snap(g).GetProperty("notes").GetArrayLength());
        Run(g, (4 / C.BARD_NOTE_SPEED) * 1000 + 100);
        Assert.Equal(C.BASIC_ATTACKS["bard"].chain[0].dmg, p(2).damage);
        Assert.True(p(2).slowUntil > g.time);
        var until = p(2).slowUntil;
        Assert.True(Math.Abs(SnapP(g, 2).Num("slowLeft") - (until - g.time)) < 1);
        Run(g, 700);
        Place(p(2), 5, 5);
        p(2).slowUntil = g.time + 2000;
        p(2).input = new PlayerInput { fwd = 1, strafe = 0, jump = false };
        p(2).yaw = Math.PI / 2;
        var y0 = p(2).y;
        Run(g, 300);
        var sp = (p(2).y - y0) / 0.3;
        Assert.True(Math.Abs(sp - C.MOVE_SPEED * (1 - C.BARD_SLOW)) < 0.3, $"속도 {sp:F2}");
        Run(g, 1000);
        Place(p(1), 2, 5, 0);
        Place(p(2), 4, 5);
        p(2).slowUntil = g.time + 1500;
        g.DrainEvents();
        Act(g, 1, "push");
        double hitAt = 0;
        for (int k = 0; k < 30 && hitAt == 0; k++)
        {
            g.Tick(TICK);
            if (Events(g).Any(e => Hit(e, "note"))) hitAt = g.time;
        }
        Assert.True(hitAt != 0, "두 번째 음파 맞음");
        Assert.True(Math.Abs(p(2).slowUntil - (hitAt + C.BARD_SLOW_MS)) <= TICK, $"갱신 {p(2).slowUntil - hitAt}");
    }

    [Fact]
    public void Bard_vuln_song_front_only_mult_on_percent_kb()
    {
        var (g, _, p) = Setup("bard", "tank", "builder");
        Place(p(1), 4, 5, 0);
        Place(p(2), 7, 6);
        Place(p(3), 2, 5);
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        Assert.True(p(2).vulnUntil >= g.time + C.BARD_VULN_MS - 1);
        Assert.Equal(0, p(3).vulnUntil);
        double Kb(bool vuln, bool @fixed)
        {
            var (qg, _, qp) = Setup("tank", "builder");
            Place(qp(2), 5, 5);
            qp(2).damage = 100;
            if (vuln) qp(2).vulnUntil = qg.time + 1000;
            qg.ApplyKnockback(qp(2), 1, 0, 4, 0, 500, 0, new Src(1, "push"), true, new KbOpts(fixed_: @fixed));
            return qp(2).kbx;
        }
        Assert.True(Math.Abs(Kb(true, false) / Kb(false, false) - C.BARD_VULN_MULT) < 1e-9, "×1.3");
        Assert.Equal(Kb(false, true), Kb(true, true));
        Run(g, C.BARD_VULN_MS + TICK);
        Assert.Equal(0, SnapP(g, 2).Num("vulnLeft"));
    }

    [Fact]
    public void Bard_air_basic_glides_during_move_extends_ends_hit_cancels()
    {
        var def = C.BASIC_ATTACKS["bard"].air[0];
        var ms = def.windup + def.rec;
        var (g, _, p) = Setup("bard", "tank");
        Place(p(1), 4, 5, 0, 10);
        Air(p(1), -5);
        Place(p(2), 8, 8);
        Act(g, 1, "push");
        Assert.True(Math.Abs(p(1).glideUntil - (g.time + ms)) < 1e-6, "누르는 순간부터 동작 동안");
        Run(g, ms - 2 * TICK);
        Assert.True(p(1).glideUntil > g.time && p(1).vz >= -C.BARD_GLIDE_FALL - 1e-9, $"동작 중 천천히 vz {p(1).vz}");
        Run(g, 4 * TICK + 200);
        Assert.Equal(0, p(1).glideUntil);
        Assert.True(p(1).vz < -C.BARD_GLIDE_FALL - 1, $"일반 낙하 vz {p(1).vz:F2}");
        var (qg, _, qp) = Setup("bard", "tank");
        Place(qp(1), 4, 5, 0, 14);
        Air(qp(1), 0);
        Place(qp(2), 8, 8);
        Act(qg, 1, "push");
        Run(qg, ms - TICK);
        Act(qg, 1, "push");
        Run(qg, 3 * TICK);
        Assert.True(qp(1).glideUntil > qg.time, "연장");
        Assert.True(qp(1).vz >= -C.BARD_GLIDE_FALL - 1e-9);
        qg.ApplyKnockback(qp(1), 1, 0, 1, 0, 300, 1, new Src(2, "push"));
        Assert.Equal(0, qp(1).glideUntil);
    }

    [Fact]
    public void Bard_glide_max_per_air_resets_on_ground()
    {
        Assert.Equal(3, C.BARD_GLIDE_MAX_PER_AIR);
        var def = C.BASIC_ATTACKS["bard"].air[0];
        var ms = def.windup + def.rec;
        var (g, _, p) = Setup("bard", "tank");
        Place(p(2), 1, 9);
        Place(p(1), 4, 5, 0, 14);
        Air(p(1), 0);
        int glides = 0;
        for (int i = 0; i < 4; i++)
        {
            g.DrainEvents();
            Act(g, 1, "push");
            Run(g, ms + TICK);
            if (Events(g).Has("glide")) glides++;
        }
        Assert.Equal(3, glides);
        Assert.Equal(0, SnapP(g, 1).GetProperty("bard").Num("glidesLeft"));
        Place(p(1), 4, 5, 0, 0);
        Run(g, 2 * TICK);
        Assert.Equal(0, p(1).glideCount);
        (p(1).z, p(1).grounded, p(1).vz) = (6, false, 0);
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.True(Events(g).Has("glide"), "착지 뒤 다시 됨");
    }

    [Fact]
    public void Bard_glide_ring_hits_all_around_fixed_kb_no_slow_team_passes_used_up_none()
    {
        var def = C.BASIC_ATTACKS["bard"].air[0];
        Assert.Equal(new double?[] { 3, 1.5, 1, 300, 1.2 }, new[] { def.dmg, def.kb, def.up, def.stun, def.range });
        var ms = def.windup + def.rec;
        (Game g, List<string> lines, Func<int, Player> p, List<JsonElement> ev) Ring(double dmg2)
        {
            var (g, lines, p) = Setup("bard", "tank", "builder");
            Place(p(1), 6, 5, 0, 6);
            Place(p(2), 5, 5, 0, 6);
            Place(p(3), 6, 6.5, 0, 6);
            foreach (var id in new[] { 1, 2, 3 }) Air(p(id), 0);
            p(2).damage = dmg2;
            g.DrainEvents();
            Act(g, 1, "push");
            Run(g, def.windup + TICK);
            return (g, lines, p, Events(g));
        }
        var a = Ring(0);
        var r = a.ev.Find("glideRing");
        Assert.True(r != null, "고리 이벤트");
        if (r == null) return;
        Assert.Equal("[2]", r.Value.GetProperty("hits").GetRawText());
        Assert.Equal(1.2, r.Value.Num("r"));
        Assert.Equal(3, a.p(2).damage);
        Assert.True(a.p(2).kbx < 0, "바깥(뒤)으로 밀림");
        Assert.True(a.p(2).stunUntil > a.g.time, "경직");
        Assert.Equal(0, a.p(2).slowUntil);
        Assert.Equal(0, a.p(3).damage);
        Assert.True(a.lines.Any(l => Regex.IsMatch(l, @"\[평타\] P1 → P2 넉백 .* 공중 천천히 낙하")), "평타 로그 (stats 공중 평타 명중)");
        var b = Ring(150);
        Assert.True(Math.Abs(b.p(2).kbx - a.p(2).kbx) < 1e-9, "고정 넉백: 피해 % 와 무관");
        // 같은 팀은 통과 (JS: team = 0 둘 다 — C# team 은 글자라 있는 팀 "red" 로 같게. 둘 다 같은 팀이라 판은 JS 처럼 끝남)
        var (tg, _, tp) = Setup("bard", "tank");
        tg.teamMode = true;
        tp(1).team = tp(2).team = "red";
        Place(tp(1), 6, 5, 0, 6);
        Place(tp(2), 5, 5, 0, 6);
        foreach (var id in new[] { 1, 2 }) Air(tp(id), 0);
        Act(tg, 1, "push");
        Run(tg, def.windup + TICK);
        Assert.Equal(0, tp(2).damage);
        var (g, _, p) = Setup("bard", "tank");
        Place(p(2), 1, 9);
        Place(p(1), 4, 5, 0, 20);
        Air(p(1), 0);
        var rings = new List<int>();
        for (int i = 0; i < 4; i++)
        {
            Act(g, 1, "push");
            Run(g, ms + TICK);
            rings.Add(Events(g).Count(e => e.IsType("glideRing")));
        }
        Assert.Equal(new[] { 1, 1, 1, 0 }, rings);
    }

    [Fact]
    public void Bard_glide_ring_kill_weapon_is_glide()
    {
        var (g, lines, p) = Setup("bard", "tank");
        Place(p(1), 6, 5, 0, 6);
        Place(p(2), 5, 5, 0, 6);
        foreach (var id in new[] { 1, 2 }) Air(p(id), 0);
        Act(g, 1, "push");
        Run(g, C.BASIC_ATTACKS["bard"].air[0].windup + TICK);
        Assert.Equal("glide", p(2).lastHit!.kind);
        g.Kill(p(2), "fall");
        Assert.Contains(lines, l => Regex.IsMatch(l, @"\[사망\] P2 .*킬 P1 낙하음파"));
    }

    [Fact]
    public void Bard_amp_front_cone_ticks_end_blast_no_basic_not_interrupted()
    {
        var (g, lines, p) = Setup("bard", "tank", "builder");
        Place(p(1), 3, 5, 0);
        Place(p(2), 5, 5);
        Place(p(3), 3, 7.5);
        p(1).form = "metal";
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Assert.NotNull(p(1).amp);
        Act(g, 1, "push");
        Assert.Null(p(1).atk);
        int ticks = 0;
        bool end = false;
        for (double t = 0; t < C.BARD_AMP_MS + 200; t += TICK)
        {
            if (p(1).amp != null) (p(2).x, p(2).y, p(2).z) = (5, 5, 0);
            (p(1).x, p(1).y, p(1).yaw) = (3, 5, 0);
            g.Tick(TICK);
            foreach (var e in Events(g))
            {
                if (Hit(e, "amp") && e.Num("target") == 2) ticks++;
                if (Hit(e, "ampend") && e.Num("target") == 2) end = true;
            }
        }
        Assert.True(ticks >= 8, $"작은 밀침 {ticks}번");
        Assert.True(end, string.Join("\n", lines));
        Assert.Equal(0, p(3).damage);
        var (qg, _, qp) = Setup("bard", "tank", "builder");
        Place(qp(1), 3, 5, 0);
        Place(qp(2), 8, 8);
        Place(qp(3), 4.5, 5);
        qp(1).form = "metal";
        qp(1).ult = C.ULT_MAX;
        Act(qg, 1, "ult");
        Run(qg, 500);
        qg.DrainEvents();
        qg.ApplyKnockback(qp(1), -1, 0, 3, 0, 1000, 5, new Src(2, "push"), true);
        Assert.True(qp(1).amp != null, "안 끊김");
        Assert.True(qp(1).kbx < 0, "넉백은 받음");
        Assert.False(Events(qg).Has("interrupt", e => e.Num("who") == 1));
        int stunTicks = 0;
        bool ended = false;
        for (double t = 0; t < C.BARD_AMP_MS; t += TICK)
        {
            (qp(3).x, qp(3).y, qp(3).z) = (qp(1).x + 1.5, qp(1).y, qp(1).z);
            qp(1).yaw = 0;
            qg.Tick(TICK);
            foreach (var e in Events(qg))
            {
                if (Hit(e, "amp") && qg.time < qp(1).stunUntil) stunTicks++;
                if (e.IsType("ampEnd")) ended = true;
            }
        }
        Assert.True(stunTicks >= 1, $"경직 중에도 연주 {stunTicks}");
        Assert.True(ended, "끝까지");
    }

    [Fact]
    public void Bard_amp_stays_in_place_cone_locked_end_kb_4()
    {
        Assert.Equal(0, C.BARD_AMP_MOVE_MULT);
        Assert.Equal(4, C.BARD_AMP_END_KB_SPEED);
        var (g, _, p) = Setup("bard", "tank", "builder");
        Place(p(1), 4, 5, 0);
        Place(p(2), 8, 8);
        Place(p(3), 4, 7);
        p(1).form = "metal";
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        p(1).input = new PlayerInput { fwd = 1, strafe = 0, jump = false };
        p(1).yaw = Math.PI / 2;
        var x0 = p(1).x;
        var y0 = p(1).y;
        Run(g, 600);
        Assert.True(Math.Sqrt((p(1).x - x0) * (p(1).x - x0) + (p(1).y - y0) * (p(1).y - y0)) < 0.01, "제자리");
        Assert.Equal(0, SnapP(g, 1).GetProperty("bard").Num("ampYaw"));
        Assert.Equal(0, p(3).damage);
    }

    [Fact]
    public void Bard_metal_air_dive_spikes_below_or_lands_shock_once_per_air()
    {
        var def = C.BASIC_ATTACKS["bard"].metal.air[0];
        Assert.True(def.dive);
        var (g, _, p) = Setup("bard", "tank");
        p(1).form = "metal";
        Place(p(1), 4, 5, 0, 5);
        Air(p(1), 2);
        Place(p(2), 4.3, 5, 0, 2);
        p(2).grounded = false;
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.True(p(1).vz <= -C.BARD_DIVE_SPEED, "바로 아래로");
        Assert.True(Events(g).Has("dive", e => e.Num("who") == 1));
        for (int k = 0; k < 20 && p(2).damage == 0; k++)
        {
            p(2).vz = 0;
            g.Tick(TICK);
        }
        Assert.Equal(def.dmg, p(2).damage);
        Assert.True(p(2).vz < 0, "아래로 꽂음");
        var (qg, _, qp) = Setup("bard", "tank");
        qp(1).form = "metal";
        Place(qp(1), 4, 5, 0, 6);
        Air(qp(1), 0);
        Place(qp(2), 5.2, 5);
        Act(qg, 1, "push");
        double ms = 0;
        while (!qp(1).grounded && ms < 2000)
        {
            qg.Tick(TICK);
            ms += TICK;
        }
        Assert.True(ms <= (6 / C.BARD_DIVE_SPEED) * 1000 + 3 * TICK, $"빠르게 착지 {ms:F0}ms");
        Run(qg, 2 * TICK);
        Assert.Equal(def.dmg, qp(2).damage);
        Assert.True(qp(2).vz > 0 || qp(2).z > 0.05, "위로");
        var (rg, _, rp) = Setup("bard", "tank");
        rp(1).form = "metal";
        Place(rp(1), 4, 5, 0, 30);
        Air(rp(1), 0);
        Act(rg, 1, "push");
        Run(rg, 700);
        rp(1).dive = null;
        (rp(1).z, rp(1).vz, rp(1).grounded) = (20, 0, false);
        rg.DrainEvents();
        Act(rg, 1, "push");
        Assert.False(Events(rg).Has("dive"), "착지 전 두 번째는 안 됨");
        Place(rp(1), 4, 5, 0, 0);
        Run(rg, 2 * TICK);
        Assert.False(rp(1).diveUsed);
    }

    // ---------- 팀전 ----------

    static (Game g, Func<int, Player> p) TeamChars(string ch)
    {
        var g = new Game(_ => { }, characters: true);
        g.rng = () => 0.5;
        for (int i = 1; i <= 4; i++) g.AddPlayer(i);
        g.SetChar(1, ch);
        for (int i = 2; i <= 4; i++) g.SetChar(i, "tank");
        g.SetTeamMode(true);
        g.SetTeam(1, "red");
        g.SetTeam(2, "red");
        g.SetTeam(3, "blue");
        g.SetTeam(4, "blue");
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        while (g.phase != "playing") g.Tick(TICK);
        return (g, id => g.players[id]);
    }

    static (double dmg, bool touched, int marks, double vuln, double slow, bool alive) Barrage(string ch, int victim)
    {
        var (g, p) = TeamChars(ch);
        var others = new[] { 2, 3, 4 }.Where(i => i != victim).ToArray();
        Place(p(others[0]), 1, 1);
        Place(p(others[1]), 1, 9);
        void Keep()
        {
            (p(1).x, p(1).y, p(1).yaw, p(1).pitch) = (3, 5, 0, 0);
            (p(victim).x, p(victim).y) = (4.2, 5);
            p(victim).z = Math.Max(p(victim).z, 0);
        }
        Place(p(1), 3, 5, 0);
        Place(p(victim), 4.2, 5);
        if (ch == "hook") foreach (var y in new[] { 4, 5, 6 }) g.grid[g.Idx(6, y, 1)] = Pieces.CELL.TERRAIN;
        if (ch == "hunter" && victim == 3) p(victim).marks[1] = new Mark { n = 2, at = g.time };
        g.GridChanged();
        bool touched = false;
        void Step()
        {
            g.Tick(TICK);
            var v = p(victim);
            if (Math.Abs(v.kbx) + Math.Abs(v.kby) > 0 || g.time < v.stunUntil) touched = true;
        }
        void Do(string name)
        {
            Keep();
            Act(g, 1, name);
            for (double t = 0; t < 700; t += TICK)
            {
                if (ch != "berserker" && ch != "ninja") Keep();
                Step();
            }
        }
        void Wait(double ms)
        {
            for (double t = 0; t < ms; t += TICK) Step();
        }
        for (int i = 0; i < 3; i++) Do("push");
        Do("skill");
        p(1).ult = g.UltMax(p(1));
        Do("ult");
        Wait(3200);
        if (ch == "bard")
        {
            p(1).skillReadyAt = 0;
            Do("skill");
            Do("push");
            p(1).ult = g.UltMax(p(1));
            Do("ult");
            Wait(3200);
        }
        var vv = p(victim);
        return (vv.damage, touched, vv.marks.Count, vv.vulnUntil, vv.slowUntil, vv.alive);
    }

    [Theory]
    [InlineData("tank")]
    [InlineData("ninja")]
    [InlineData("builder")]
    [InlineData("hook")]
    [InlineData("hunter")]
    [InlineData("cannon")]
    [InlineData("berserker")]
    [InlineData("bard")]
    public void Team_no_friendly_fire_for_every_char(string ch)
    {
        Assert.Contains(ch, C.CHARACTERS);
        var mate = Barrage(ch, 2);
        Assert.Equal((0.0, false, 0, 0.0, 0.0, true), mate);
        var foe = Barrage(ch, 3);
        Assert.True(foe.dmg > 0, $"{ch}: 상대에겐 들어감 ({foe.dmg}%)");
    }

    [Fact]
    public void Team_no_friendly_fire_covers_all_characters()
    {
        Assert.Equal(new[] { "tank", "ninja", "builder", "hook", "hunter", "cannon", "berserker", "bard" }, C.CHARACTERS); // 위 Theory 가 C.CHARACTERS 전부 (JS for … of C.CHARACTERS)
    }
}

// 안 옮김: 봇 광전사: 피해 % 높고 붙어 있으면 R, 조금 떨어진 상대에게 F 로 붙음 — 봇은 S5
// 안 옮김: 봇 바드: 음유시인이면 거리 두고 음파, 앞에 상대가 있으면 취약의 노래, 붙으면 메탈로 전환, 메탈이면 앞 상대에게 앰프 — 봇은 S5
// 안 옮김: 봇 바드 음유: 공중에서 상대가 낙하 음파 고리 안이면 공중 평타로 맞힘 — 봇은 S5
// 안 옮김: 봇 예고 피하기 (재혁 2026-10-26): 탱크 R 예고를 보고 BOT_REACTION_MS 뒤에 바깥으로 피함 — 봇은 S5
// 안 옮김: 봇 탱크 아머 돌진: 상대 평타 준비를 본 지 BOT_REACTION_MS 가 안 됐으면 안 씀 — 봇은 S5
// 안 옮김: 봇 지능 (재혁 2026-10-26): 탱크·닌자는 지상 마지막 타로 띄운 뒤 1.2초 안에 점프해 공중 평타로 이어 감 — 봇은 S5
// 안 옮김: 봇 지능: 사냥꾼은 찔러 넣기(표식) 뒤 F 가 있으면 덮침으로 잇고 … — 봇은 S5
// 안 옮김: 봇 지능: 바드는 취약이 걸린 상대에게 다가가 메탈로 바꾸고 … — 봇은 S5
// 안 옮김: 봇 캐릭터 F 복귀 (2026-10-26): 필드 밖으로 떨어질 참이면 … F — 봇은 S5
// 안 옮김: 봇 원거리 거리 두기 (A2 kite 연결): 대포수·바드 음유는 붙은 상대에게서 거리를 벌리며 쏘고 … — 봇은 S5
