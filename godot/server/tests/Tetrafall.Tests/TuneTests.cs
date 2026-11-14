using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Sim;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// 판별 캐릭터 조정 층 Tune (고도 판 전용): 한 판만 캐릭터별 배율을 덮어씀. 없으면 (null) 예전과 글자까지 같고, 전역 표 (C.*) 는 안 건드림
public class TuneTests
{
    static readonly Src BY1 = new(1, "push"); // 1번이 때림 (필살기 아님)

    // CharKit.Setup 과 같은 판 + tune
    static (Game g, Func<int, Player> p) Setup(Tune? tune, params string[] chars)
    {
        var g = new Game(characters: true, tune: tune);
        g.rng = () => 0.5;
        for (int i = 0; i < chars.Length; i++)
        {
            g.AddPlayer(i + 1);
            g.SetChar(i + 1, chars[i]);
        }
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        return (g, id => g.players[id]);
    }

    // 6키를 전부 '안 바꾸는 값' 으로: 배율 1, hpMult 는 원래 표 값
    static Tune AllOnes()
    {
        var t = new Tune();
        foreach (var c in C.CHARACTERS)
        {
            foreach (var key in Tune.KEYS) if (key != "hpMult") t.Set(c, key, 1);
            t.Set(c, "hpMult", C.HP_CHAR_MULT[c]);
        }
        return t;
    }

    // 8명 봇 판을 ticks 틱: 틱마다 이벤트·스냅샷 글자 (1초마다 격자도) + 로그 줄
    static List<string> BotTrace(Tune? tune, bool hp, int ticks)
    {
        var lines = new List<string>();
        var g = new Game(m => lines.Add("L " + m), characters: true, skyStairs: true, hpMode: hp, tune: tune);
        g.rng = new Mulberry32(20261114).AsFunc();
        for (int i = 0; i < C.CHARACTERS.Length; i++) g.SetChar(g.AddBot()!.id, C.CHARACTERS[i]);
        Assert.True(g.StartRound());
        for (int i = 0; i < ticks; i++)
        {
            g.Tick(TICK);
            foreach (var e in g.DrainEvents()) lines.Add("E " + e);
            lines.Add(g.Snapshot(i % 30 == 0));
        }
        return lines;
    }

    [Fact]
    public void Null_and_all_ones_give_same_trace()
    {
        foreach (var hp in new[] { false, true })
        {
            var a = BotTrace(null, hp, 900);
            var b = BotTrace(AllOnes(), hp, 900);
            Assert.True(a.Count >= 900);
            Assert.Equal(a.Count, b.Count);
            for (int i = 0; i < a.Count; i++) Assert.True(a[i] == b[i], $"체력전 {hp}: {i}번째 줄이 다름");
            Assert.Contains(a, l => l.Contains("\"type\":\"hit\"")); // 빈 판이 아님 (실제로 치고받음)
        }
    }

    [Fact]
    public void KbTaken_scales_knockback_exactly()
    {
        foreach (var ch in new[] { "builder", "ninja", "tank" }) // 원래 배율 1 · 1.1 · 0.92 위에 곱함
        {
            var (g0, p0) = Setup(null, "hook", ch);
            var (g1, p1) = Setup(Tune.Parse($"{ch}.kbTaken=0.5"), "hook", ch);
            foreach (var (g, p) in new[] { (g0, p0), (g1, p1) })
            {
                p(2).damage = 40;
                Assert.True(g.ApplyKnockback(p(2), 3, 4, 5, 0, C.STUN_MS, 10, BY1, true));
            }
            Assert.True(p0(2).kbx != 0 && p0(2).kby != 0);
            Assert.Equal(p0(2).kbx * 0.5, p1(2).kbx); // 정확히 절반 (비트까지)
            Assert.Equal(p0(2).kby * 0.5, p1(2).kby);
            Assert.Equal(p0(2).damage, p1(2).damage); // 피해 % 는 그대로
            // 맞는 쪽 캐릭터에만: 다른 캐릭터 (hook) 는 그대로
            g0.ApplyKnockback(p0(1), 1, 0, 5, 0, C.STUN_MS, 10, null, true);
            g1.ApplyKnockback(p1(1), 1, 0, 5, 0, C.STUN_MS, 10, null, true);
            Assert.Equal(p0(1).kbx, p1(1).kbx);
        }
        // 고정 넉백 중간 타는 % 배율이 없으니 그대로 (탱크·닌자 패시브와 같은 규칙)
        var (gf, pf) = Setup(Tune.Parse("builder.kbTaken=0.5"), "hook", "builder");
        gf.ApplyKnockback(pf(2), 1, 0, 2, 0, C.STUN_MS, 5, BY1, false, new KbOpts(fixed_: true));
        Assert.Equal(2, pf(2).kbx);
    }

    [Fact]
    public void KbDealt_scales_knockback()
    {
        double Kb(Tune? tune, Src? src, KbOpts opts = default, bool heavy = true)
        {
            var (g, p) = Setup(tune, "hook", "builder", "cannon");
            p(2).damage = 40;
            Assert.True(g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 10, src, heavy, opts));
            return p(2).kbx;
        }
        var tune = Tune.Parse("hook.kbDealt=1.5");
        double @base = Kb(null, BY1);
        Assert.True(@base > 0);
        Assert.True(Math.Abs(Kb(tune, BY1) / @base - 1.5) < 1e-12, "hook 이 때리면 1.5배");
        Assert.True(Math.Abs(Kb(tune, BY1, heavy: false) / Kb(null, BY1, heavy: false) - 1.5) < 1e-12, "가벼운 타도");
        Assert.Equal(@base, Kb(tune, new Src(3, "push"))); // 표에 없는 캐릭터 (cannon) 가 때리면 그대로
        Assert.Equal(Kb(null, null), Kb(tune, null)); // 때린 사람 없음 (블록·폭발 등)
        Assert.Equal(Kb(null, new Src(2, "push")), Kb(Tune.Parse("builder.kbDealt=1.5"), new Src(2, "push"))); // 자기가 자기를
        Assert.Equal(5, Kb(tune, BY1, new KbOpts(fixed_: true))); // 고정 넉백 중간 타는 그대로 (광전사 분노와 같은 규칙)
    }

    [Fact]
    public void DmgDealt_scales_gain_both_paths()
    {
        var tune = Tune.Parse("hook.dmgDealt=1.5");
        // 보통 길
        var (g, p) = Setup(tune, "hook", "builder", "tank");
        var (g0, p0) = Setup(null, "hook", "builder", "tank");
        g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 20, BY1, true);
        g0.ApplyKnockback(p0(2), 1, 0, 5, 0, C.STUN_MS, 20, BY1, true);
        Assert.Equal(20, p0(2).damage);
        Assert.Equal(30, p(2).damage);
        Assert.Equal(p0(2).kbx, p(2).kbx); // 이번 타 넉백은 맞기 전 피해 % 로 — 그대로
        // 탱크 아머 길 (F 돌진 중): 넉백 없이 피해 % 만 — 여기도 곱함
        foreach (var (gg, pp, want) in new[] { (g, p, 30.0), (g0, p0, 20.0) })
        {
            pp(3).chargeUntil = gg.time + 1000;
            gg.DrainEvents();
            Assert.True(gg.ApplyKnockback(pp(3), 1, 0, 5, 0, C.STUN_MS, 20, BY1, true));
            Assert.True(Events(gg).Has("armor"), "아머로 버팀");
            Assert.Equal(0, pp(3).kbx);
            Assert.Equal(want, pp(3).damage);
        }
        // 때린 사람이 없거나 (블록·용암 등) 자기 자신이면 그대로, 표에 없는 캐릭터도 그대로
        var (g2, p2) = Setup(Tune.Parse("hook.dmgDealt=1.5,builder.dmgDealt=3"), "hook", "builder", "cannon");
        g2.ApplyKnockback(p2(1), 1, 0, 5, 0, C.STUN_MS, 20, null, true);
        Assert.Equal(20, p2(1).damage);
        g2.ApplyKnockback(p2(2), 1, 0, 5, 0, C.STUN_MS, 20, new Src(2, "push"), true);
        Assert.Equal(20, p2(2).damage);
        g2.ApplyKnockback(p2(1), 1, 0, 5, 0, C.STUN_MS, 20, new Src(3, "push"), true);
        Assert.Equal(40, p2(1).damage);
    }

    [Fact]
    public void SkillCd_scales_cooldown()
    {
        var (g, p) = Setup(Tune.Parse("ninja.skillCd=0.5"), "ninja", "tank");
        Place(p(1), 3, 3, 0);
        Place(p(2), 7, 7, 0);
        double t0 = g.time;
        Act(g, 1, "skill");
        Act(g, 2, "skill");
        Assert.Equal(t0 + C.SKILL_CD_MS["ninja"] * 0.5, p(1).skillReadyAt);
        Assert.Equal(t0 + C.SKILL_CD_MS["tank"], p(2).skillReadyAt); // 표에 없는 캐릭터는 그대로
        // 쿨타임이 실제로 절반에 풀림: 원래 쿨의 0.6 배 뒤 한쪽만 다시 씀
        Run(g, C.SKILL_CD_MS["ninja"] * 0.6);
        Place(p(1), 3, 3, 0);
        double t1 = g.time;
        Act(g, 1, "skill");
        Assert.Equal(t1 + C.SKILL_CD_MS["ninja"] * 0.5, p(1).skillReadyAt);
        var (g0, p0) = Setup(null, "ninja", "tank");
        Place(p0(1), 3, 3, 0);
        Act(g0, 1, "skill");
        double ready = p0(1).skillReadyAt;
        Assert.Equal(g0.time + C.SKILL_CD_MS["ninja"], ready);
        Run(g0, C.SKILL_CD_MS["ninja"] * 0.6);
        Place(p0(1), 3, 3, 0);
        Act(g0, 1, "skill");
        Assert.Equal(ready, p0(1).skillReadyAt); // 조정 없으면 아직 쿨타임
    }

    [Fact]
    public void UltGain_scales_gauge()
    {
        var (g, p) = Setup(Tune.Parse("hook.ultGain=2,builder.ultGain=0.5"), "hook", "builder", "cannon");
        g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 10, BY1, true);
        Assert.Equal(10 * C.ULT_PER_DAMAGE * 2, p(1).ult); // 준 쪽: 자기 캐릭터 배율
        Assert.Equal(10 * C.ULT_PER_DAMAGE * 0.5, p(2).ult); // 받은 쪽: 자기 캐릭터 배율
        g.ApplyKnockback(p(3), 1, 0, 5, 0, C.STUN_MS, 10, BY1, true);
        Assert.Equal(10 * C.ULT_PER_DAMAGE, p(3).ult); // 표에 없는 캐릭터는 그대로
        Assert.Equal(20 * C.ULT_PER_DAMAGE * 2, p(1).ult);
        // 상한은 그대로
        p(1).ult = g.UltMax(p(1)) - 1;
        Run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
        g.ApplyKnockback(p(3), 1, 0, 5, 0, C.STUN_MS, 10, BY1, true);
        Assert.Equal(g.UltMax(p(1)), p(1).ult);
        var (g0, p0) = Setup(null, "hook", "builder");
        g0.ApplyKnockback(p0(2), 1, 0, 5, 0, C.STUN_MS, 10, BY1, true);
        Assert.Equal(10 * C.ULT_PER_DAMAGE, p0(1).ult);
        Assert.Equal(10 * C.ULT_PER_DAMAGE, p0(2).ult);
    }

    [Fact]
    public void HpMult_overrides_hpMax()
    {
        var g = new Game(characters: true, hpMode: true, tune: Tune.Parse("tank.hpMult=2,ninja.hpMult=0.5"));
        g.rng = () => 0.5;
        string[] cs = { "tank", "ninja", "hook" };
        for (int i = 0; i < cs.Length; i++)
        {
            g.AddPlayer(i + 1);
            g.SetChar(i + 1, cs[i]);
        }
        Assert.True(g.StartRound());
        double @base = C.HP_MAX_BY_MODE["survival"];
        Assert.Equal(JsMath.Round(@base * 2), g.HpMax(g.players[1])); // 원래 표 (0.7) 에 곱하는 게 아니라 대신 씀
        Assert.Equal(JsMath.Round(@base * 0.5), g.HpMax(g.players[2]));
        Assert.Equal(JsMath.Round(@base * C.HP_CHAR_MULT["hook"]), g.HpMax(g.players[3])); // 표에 없으면 원래 값
        Assert.Equal(@base, g.HpMax()); // 맨 위 hpMax 는 모드 값 그대로
        var s = JsonDocument.Parse(g.Snapshot()).RootElement;
        Assert.Equal(@base, s.GetProperty("hpMax").GetDouble());
        var hp = s.GetProperty("players").EnumerateArray().ToDictionary(x => x.GetProperty("char").GetString()!, x => x.GetProperty("hpMax").GetDouble());
        Assert.Equal(JsMath.Round(@base * 2), hp["tank"]);
        Assert.Equal(JsMath.Round(@base * 0.5), hp["ninja"]);
        // KO 기준도 그 값: 원래 탱크 HP 를 넘겨도 안 죽고, 조정한 HP 에서 죽음
        g.nextSpawnAt = double.PositiveInfinity;
        g.players[1].damage = JsMath.Round(@base * C.HP_CHAR_MULT["tank"]) + 1;
        g.Tick(TICK);
        Assert.True(g.players[1].alive);
        g.players[1].damage = JsMath.Round(@base * 2);
        g.Tick(TICK);
        Assert.False(g.players[1].alive);
        Assert.Equal("hp", g.players[1].deathCause);
        // 캐릭터를 안 켠 판은 조정이 있어도 모드 값
        var off = new Game(hpMode: true, tune: Tune.Parse("tank.hpMult=2"));
        off.AddPlayer(1);
        off.players[1].@char = "tank";
        Assert.Equal(@base, off.HpMax(off.players[1]));
    }

    [Fact]
    public void Two_games_in_one_process_do_not_share()
    {
        var cd = C.SKILL_CD_MS.ToDictionary(x => x.Key, x => x.Value);
        var hpTable = C.HP_CHAR_MULT.ToDictionary(x => x.Key, x => x.Value);
        var (ga, pa) = Setup(Tune.Parse("builder.kbTaken=0.5,hook.skillCd=0.5,hook.hpMult=3"), "hook", "builder");
        var (gb, pb) = Setup(Tune.Parse("builder.kbTaken=2,hook.skillCd=2"), "hook", "builder");
        var (g0, p0) = Setup(null, "hook", "builder");
        Assert.NotSame(ga.tune, gb.tune);
        Assert.Null(g0.tune);
        // 번갈아 불러도 판마다 자기 값
        foreach (var (g, p) in new[] { (ga, pa), (g0, p0), (gb, pb) })
        {
            p(2).damage = 30;
            Assert.True(g.ApplyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 0, null, true));
        }
        Assert.Equal(p0(2).kbx * 0.5, pa(2).kbx);
        Assert.Equal(p0(2).kbx * 2, pb(2).kbx);
        foreach (var (g, p) in new[] { (ga, pa), (g0, p0), (gb, pb) }) Place(p(1), 3, 3, 0);
        Act(ga, 1, "skill");
        Act(gb, 1, "skill");
        Act(g0, 1, "skill");
        Assert.Equal(ga.time + C.SKILL_CD_MS["hook"] * 0.5, pa(1).skillReadyAt);
        Assert.Equal(gb.time + C.SKILL_CD_MS["hook"] * 2, pb(1).skillReadyAt);
        Assert.Equal(g0.time + C.SKILL_CD_MS["hook"], p0(1).skillReadyAt);
        // hpMult 는 그 판에만
        ga.hpMode = gb.hpMode = g0.hpMode = true;
        double @base = C.HP_MAX_BY_MODE["survival"];
        Assert.Equal(JsMath.Round(@base * 3), ga.HpMax(pa(1)));
        Assert.Equal(JsMath.Round(@base * C.HP_CHAR_MULT["hook"]), gb.HpMax(pb(1)));
        Assert.Equal(JsMath.Round(@base * C.HP_CHAR_MULT["hook"]), g0.HpMax(p0(1)));
        // 전역 표는 그대로
        Assert.Equal(cd, C.SKILL_CD_MS);
        Assert.Equal(hpTable, C.HP_CHAR_MULT);
        // 스레드 둘에서 같이 돌려도 (sim 워커) 판마다 자기 조정대로 — 혼자 돌린 것과 같은 글자
        string Last(Tune? t) => BotTrace(t, true, 200)[^1];
        var ta = Tune.Parse("tank.kbTaken=0.5,hook.kbDealt=1.5");
        var tb = Tune.Parse("tank.kbTaken=2,ninja.dmgDealt=2");
        string wantA = Last(ta), wantB = Last(tb), want0 = Last(null);
        var got = new string[3];
        Parallel.Invoke(() => got[0] = Last(ta), () => got[1] = Last(tb), () => got[2] = Last(null));
        Assert.Equal(wantA, got[0]);
        Assert.Equal(wantB, got[1]);
        Assert.Equal(want0, got[2]);
        Assert.NotEqual(want0, wantA);
        Assert.NotEqual(wantA, wantB);
    }

    [Fact]
    public void HpMult_option_leaves_global_table_untouched()
    {
        var before = C.HP_CHAR_MULT.ToDictionary(x => x.Key, x => x.Value);
        var o = BotSim.ParseArgs(new[] { "--hp", "on", "--hp-mult", "tank=2" });
        Assert.Equal(before["tank"], C.HP_CHAR_MULT["tank"]);
        Assert.Equal(before, C.HP_CHAR_MULT);
        Assert.Equal(2, o.hpMult!["tank"]);
        Assert.Null(o.tune);
        // 판에는 Tune.hpMult 로 들어감 (다른 키는 비어 있음 → 배율 1)
        var t = o.GameTune()!;
        Assert.Equal(2, t.HpMult("tank"));
        Assert.Null(t.HpMult("ninja"));
        Assert.Equal(1, t.KbTaken("tank"));
        // 판을 돌린 뒤에도 그대로
        BotSim.RunJob(BotSim.PlanJobs(BotSim.ParseArgs(new[] { "--rounds", "1", "--players", "2", "--maps", Maps.MAP_IDS[0], "--hp", "on", "--hp-mult", "1.3", "--no-mirror" }))[0], o);
        Assert.Equal(before, C.HP_CHAR_MULT);
        // 옵션이 없으면 판에 조정 없음 (예전과 같은 판)
        Assert.Null(BotSim.ParseArgs(Array.Empty<string>()).GameTune());
        // --tune 과 같이: 합침, 같은 캐릭터면 --tune 의 hpMult 가 이김. o.tune 자체는 안 바뀜
        var both = BotSim.ParseArgs(new[] { "--hp-mult", "tank=2,ninja=0.8", "--tune", "tank.hpMult=3,ninja.kbTaken=0.9" });
        var bt = both.GameTune()!;
        Assert.Equal(3, bt.HpMult("tank"));
        Assert.Equal(0.8, bt.HpMult("ninja"));
        Assert.Equal(0.9, bt.KbTaken("ninja"));
        Assert.Null(both.tune!.HpMult("ninja"));
    }

    [Fact]
    public void Parse_rejects_unknown_char_key_or_nonpositive()
    {
        var t = Tune.Parse("ninja.kbTaken=0.95, hook.kbDealt=1.1,hook.hpMult=1.2");
        Assert.Equal(0.95, t.KbTaken("ninja"));
        Assert.Equal(1.1, t.KbDealt("hook"));
        Assert.Equal(1.2, t.HpMult("hook"));
        // 없는 칸: 배율은 1, hpMult 는 null. 캐릭터 없음 (null) 도
        Assert.Equal(1, t.KbTaken("hook"));
        Assert.Equal(1, t.DmgDealt("ninja"));
        Assert.Equal(1, t.SkillCd("ninja"));
        Assert.Equal(1, t.UltGain("ninja"));
        Assert.Null(t.HpMult("ninja"));
        Assert.Equal(1, t.KbTaken(null));
        Assert.Equal(1, t.KbDealt(null));
        Assert.Null(t.HpMult(null));
        foreach (var bad in new[]
        {
            "nobody.kbDealt=2", // 모르는 캐릭터
            "hook.speed=2", // 모르는 키
            "hook.kbDealt=abc", // 숫자 아님
            "hook.kbDealt=", "hook.kbDealt", "hook=2", "kbDealt=2", "", "hook.kbDealt=1.1,",
            "hook.kbDealt=0", "hook.kbDealt=-1", "hook.kbDealt=NaN", "hook.kbDealt=Infinity", // 0 이하·수가 아님
            "hook.hpMult=0",
        })
        {
            Assert.Throws<ArgumentException>(() => Tune.Parse(bad));
            Assert.Throws<ArgumentException>(() => BotSim.ParseArgs(new[] { "--tune", bad }));
        }
        Assert.Throws<ArgumentException>(() => BotSim.ParseArgs(new[] { "--tune" })); // 값 없음
        // 키 6개 모두 받음
        var all = Tune.Parse(string.Join(",", Tune.KEYS.Select(k => $"cannon.{k}=1.25")));
        Assert.Equal(new[] { "kbTaken", "kbDealt", "dmgDealt", "skillCd", "ultGain", "hpMult" }, Tune.KEYS);
        Assert.Equal(1.25, all.KbTaken("cannon"));
        Assert.Equal(1.25, all.KbDealt("cannon"));
        Assert.Equal(1.25, all.DmgDealt("cannon"));
        Assert.Equal(1.25, all.SkillCd("cannon"));
        Assert.Equal(1.25, all.UltGain("cannon"));
        Assert.Equal(1.25, all.HpMult("cannon"));
    }

    [Fact]
    public void Summary_options_tune_only_when_given()
    {
        string Options(params string[] argv)
        {
            var j = new JsonOut();
            BotSim.ParseArgs(argv).Write(j);
            return j.ToString();
        }
        var with = JsonDocument.Parse(Options("--tune", "hook.kbDealt=1.15,ninja.kbTaken=0.95,hook.hpMult=1.2")).RootElement;
        Assert.Equal("{\"kbTaken\":{\"ninja\":0.95},\"kbDealt\":{\"hook\":1.15},\"hpMult\":{\"hook\":1.2}}", with.GetProperty("tune").GetRawText());
        Assert.False(with.TryGetProperty("hpMult", out _));
        Assert.False(JsonDocument.Parse(Options()).RootElement.TryGetProperty("tune", out _));
        // --hp-mult 만 주면 예전처럼 hpMult 키만
        var hp = JsonDocument.Parse(Options("--hp-mult", "tank=1.3")).RootElement;
        Assert.Equal("{\"tank\":1.3}", hp.GetProperty("hpMult").GetRawText());
        Assert.False(hp.TryGetProperty("tune", out _));
    }

    [Fact]
    public void Sim_tune_changes_result()
    {
        List<string> Run(params string[] extra)
        {
            var o = BotSim.ParseArgs(new[] { "--chars", "hook,cannon", "--players", "2", "--rounds", "28", "--seed", "1", "--no-log" }.Concat(extra).ToArray());
            return BotSim.RunParallel(BotSim.PlanJobs(o), o).Select(r => $"{r.id} {r.map} {string.Join("/", r.chars)} 승 {string.Join(",", r.winSeats)} {JsNumber.ToJs(r.lenMs)}ms {JsNumber.ToJs(r.causes["crush"])}/{JsNumber.ToJs(r.causes["fall"])}/{JsNumber.ToJs(r.causes["lava"])} {r.timeout}").ToList();
        }
        var plain = Run();
        var tuned = Run("--tune", "hook.kbDealt=1.5");
        Assert.Equal(plain.Count, tuned.Count);
        Assert.NotEqual(plain, tuned); // 방향은 묻지 않음 — 판이 달라지기만 하면
        Assert.Equal(tuned, Run("--tune", "hook.kbDealt=1.5")); // 같은 조정이면 같은 판
        Assert.Equal(plain, Run("--tune", "hook.kbDealt=1")); // 배율 1 은 조정 없음과 같은 판
    }
}
