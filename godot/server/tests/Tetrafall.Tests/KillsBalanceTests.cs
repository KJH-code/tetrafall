using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Sim;

namespace Tetrafall.Tests;

// 킬 점수전 밸런스 표 (ConfigBalance.cs BALANCE_KILLS, 고도 판 전용): Tune 모드 덮기 (modes) 로 킬 점수전 판에서만 같은 캐릭터·키를 바꿈.
// Game 은 판마다 StartRound 에서 tuneBase.For(mode) 를 고름 — 방은 Game 하나를 계속 쓰니 모드를 바꾸면 다음 판부터 그 모드 표
public class KillsBalanceTests
{
    static JsonElement J(string s) => JsonDocument.Parse(s).RootElement;

    sealed class Sock : ISocket
    {
        public bool Open => true;
        public void Send(string text) { }
    }

    static string W(Tune t)
    {
        var o = new JsonOut();
        t.Write(o);
        return o.ToString();
    }

    [Fact]
    public void Parse가_모드_덮기를_받음()
    {
        var t = Tune.Parse("kills:ninja.kbDealt=1.6,hook.kbTaken=0.95");
        Assert.Equal(1, t.KbDealt("ninja")); // 기본 표엔 안 들어감
        Assert.Equal(0.95, t.KbTaken("hook"));
        Assert.Equal(new[] { "kills" }, t.modes.Keys);
        Assert.Equal(1.6, t.modes["kills"].KbDealt("ninja"));
        Assert.Empty(t.modes["kills"].modes); // 덮는 표 안에는 modes 가 없음
        Assert.Equal(1.6, t.For("kills").KbDealt("ninja"));
        Assert.Equal(0.95, t.For("kills").KbTaken("hook")); // 기본 표도 옮겨 옴
        Assert.Equal(1, t.For("survival").KbDealt("ninja"));
        // 같은 모드에 여럿·다른 키
        var m = Tune.Parse("kills:ninja.kbDealt=1.6, kills:ninja.kbTaken=0.8,master:tank.skillCd=0.5");
        Assert.Equal(0.8, m.For("kills").KbTaken("ninja"));
        Assert.Equal(1.6, m.For("kills").KbDealt("ninja"));
        Assert.Equal(1, m.For("kills").SkillCd("tank"));
        Assert.Equal(0.5, m.For("master").SkillCd("tank"));
    }

    [Fact]
    public void Parse_모르는_모드_캐릭터_키_0이하는_던짐()
    {
        foreach (var bad in new[]
        {
            "practice:ninja.kbDealt=1.6", // 연습은 모드 덮기 없음 (MODE_NAMES 밖)
            "foo:ninja.kbDealt=1.6",
            ":ninja.kbDealt=1.6",
            "kills:nobody.kbDealt=1.6",
            "kills:ninja.speed=1.6",
            "kills:ninja.kbDealt=0", "kills:ninja.kbDealt=-1", "kills:ninja.kbDealt=NaN",
            "kills:ninja.kbDealt=abc", "kills:ninja.kbDealt=", "kills:ninja=2", "kills:", "kills",
            "kills:kills:ninja.kbDealt=1.6",
        })
        {
            Assert.Throws<ArgumentException>(() => Tune.Parse(bad));
            Assert.Throws<ArgumentException>(() => BotSim.ParseArgs(new[] { "--tune", bad }));
        }
        var t = new Tune();
        Assert.Throws<ArgumentException>(() => t.SetMode("practice", "ninja", "kbDealt", 1.6));
        Assert.Throws<ArgumentException>(() => t.SetMode("kills", "nobody", "kbDealt", 1.6));
        Assert.Throws<ArgumentException>(() => t.SetMode("kills", "ninja", "kbDealt", 0));
        Assert.Empty(t.modes); // 던진 값은 빈 덮기도 안 남김
    }

    [Fact]
    public void For는_덮기가_없으면_같은_객체_있으면_새_표()
    {
        var t = C.BalanceTune();
        Assert.True(ReferenceEquals(t, t.For(null)));
        Assert.True(ReferenceEquals(t, t.For("survival")));
        Assert.True(ReferenceEquals(t, t.For("master")));
        Assert.True(ReferenceEquals(t, t.For("practice")));
        var k = t.For("kills");
        Assert.False(ReferenceEquals(t, k));
        Assert.Equal(1.6, k.KbDealt("ninja")); // 곱하지 않고 바꿈 (1.1 × 1.6 아님)
        Assert.Equal(0.9, k.KbTaken("ninja")); // 덮기에 없는 키는 기본 표 그대로
        Assert.Equal(0.85, k.KbDealt("cannon")); // 덮기에 없는 캐릭터도
        Assert.Equal(0.75, k.KbDealt("builder")); // 기본 표에 없던 자리는 더해짐
        Assert.Empty(k.modes);
        Assert.Equal(1.1, t.KbDealt("ninja")); // 원본은 그대로
        Assert.Equal(1, t.KbDealt("builder"));
        Assert.NotSame(k, t.For("kills")); // 부를 때마다 새 표
    }

    [Fact]
    public void Clone은_모드_덮기까지_깊게()
    {
        var t = C.BalanceTune();
        var c = t.Clone();
        Assert.Equal(1.6, c.For("kills").KbDealt("ninja"));
        Assert.NotSame(t.modes["kills"], c.modes["kills"]);
        c.SetMode("kills", "ninja", "kbDealt", 3);
        c.modes["kills"].Set("tank", "kbDealt", 2);
        Assert.Equal(1.6, t.For("kills").KbDealt("ninja"));
        Assert.Equal(1, t.For("kills").KbDealt("tank"));
        Assert.Equal(3, c.For("kills").KbDealt("ninja"));
    }

    [Fact]
    public void Write는_모드_덮기가_있을_때만_modes()
    {
        Assert.Equal("{\"kbTaken\":{\"ninja\":0.95},\"kbDealt\":{\"hook\":1.1}}", W(Tune.Parse("ninja.kbTaken=0.95,hook.kbDealt=1.1"))); // 예전 글자 그대로
        Assert.Equal("{}", W(new Tune()));
        Assert.Equal("{\"kbDealt\":{\"hook\":1.1},\"modes\":{\"survival\":{\"skillCd\":{\"tank\":0.5}},\"kills\":{\"kbDealt\":{\"ninja\":1.6}}}}",
            W(Tune.Parse("kills:ninja.kbDealt=1.6,hook.kbDealt=1.1,survival:tank.skillCd=0.5"))); // modes 는 끝에, MODE_NAMES 순서
    }

    [Fact]
    public void BALANCE_KILLS는_kbDealt만_아는_캐릭터만()
    {
        Assert.DoesNotContain(":", C.BALANCE_KILLS);
        var k = Tune.Parse(C.BALANCE_KILLS);
        foreach (var key in Tune.KEYS) if (key != "kbDealt") Assert.True(k.Table(key)!.Count == 0, $"{key}: 킬 점수전 표엔 kbDealt 만 (클라 쿨 표시와 어긋나지 않게)");
        Assert.Equal(C.BALANCE_KILLS.Split(',').Length, k.kbDealt.Count); // 같은 자리를 두 번 쓴 줄 없음
        foreach (var c in k.kbDealt.Keys) Assert.Contains(c, C.CHARACTERS);

        // BalanceTune: 기본 = BALANCE, kills 덮기 = BALANCE_KILLS, 부를 때마다 새 객체
        var a = C.BalanceTune();
        var b = C.BalanceTune();
        Assert.NotSame(a, b);
        Assert.NotSame(a.modes["kills"], b.modes["kills"]);
        Assert.Equal(new[] { "kills" }, a.modes.Keys);
        foreach (var key in Tune.KEYS) Assert.Equal(k.Table(key)!.OrderBy(x => x.Key), a.modes["kills"].Table(key)!.OrderBy(x => x.Key));
        foreach (var key in Tune.KEYS) Assert.Equal(Tune.Parse(C.BALANCE).Table(key)!.OrderBy(x => x.Key), a.Table(key)!.OrderBy(x => x.Key));
    }

    [Fact]
    public void 방은_킬_점수전_판만_킬_표_다음_판_생존이면_기본_표()
    {
        var rooms = new Rooms(tune: C.BalanceTune());
        var conn = rooms.Connect(new Sock());
        rooms.Message(conn, J("{\"type\":\"create\"}"));
        var room = conn.room!;
        var g = room.game;
        rooms.Message(conn, J("{\"type\":\"setChar\",\"char\":\"ninja\"}"));
        rooms.Message(conn, J("{\"type\":\"addBot\"}"));
        rooms.Message(conn, J("{\"type\":\"setMode\",\"mode\":\"kills\"}"));
        Assert.Equal("kills", g.mode);
        Assert.Equal(1.6, g.tune!.KbDealt("ninja")); // 모드를 고르면 판 전 (대기실) 에도 그 모드 표 (사이클 5 리뷰 F6 — 예전엔 판 전엔 기본 표)
        rooms.Message(conn, J("{\"type\":\"start\"}"));
        Assert.True(g.InRound());
        Assert.Equal(1.6, g.tune!.KbDealt("ninja"));
        Assert.Equal(0.9, g.tune.KbTaken("ninja"));
        Assert.Equal(1.1, g.tuneBase!.KbDealt("ninja")); // 방이 받은 표는 그대로

        // 판 중엔 모드를 못 바꿈 → 표도 그대로
        rooms.Message(conn, J("{\"type\":\"setMode\",\"mode\":\"survival\"}"));
        Assert.Equal("kills", g.mode);
        Assert.Equal(1.6, g.tune!.KbDealt("ninja"));

        g.EndRound(null);
        rooms.Message(conn, J("{\"type\":\"setMode\",\"mode\":\"survival\"}"));
        Assert.Equal("survival", g.mode);
        Assert.True(ReferenceEquals(g.tuneBase, g.tune)); // 판 사이에 바꾸면 그 자리에서 기본 표 (예전엔 다음 판 시작까지 킬 표)
        rooms.Message(conn, J("{\"type\":\"start\"}"));
        Assert.True(g.InRound());
        Assert.Equal(1.1, g.tune!.KbDealt("ninja"));
        Assert.True(ReferenceEquals(g.tuneBase, g.tune)); // 덮기 없는 모드는 받은 표 그대로

        // 표 없는 방: 모드를 바꿔도 null
        var plain = new Rooms();
        var pc = plain.Connect(new Sock());
        plain.Message(pc, J("{\"type\":\"create\"}"));
        var pg = pc.room!.game;
        plain.Message(pc, J("{\"type\":\"addBot\"}"));
        plain.Message(pc, J("{\"type\":\"setMode\",\"mode\":\"kills\"}"));
        plain.Message(pc, J("{\"type\":\"start\"}"));
        Assert.True(pg.InRound());
        Assert.Null(pg.tune);
        Assert.Null(pg.tuneBase);
    }

    // 대기실 스냅샷 players[].hpMax 는 지금 고른 모드의 표 (사이클 5 리뷰 F6). 탱크에 킬 점수전만 hpMult 2 (기본 HP_CHAR_MULT 0.7):
    // 예전엔 tune 이 StartRound 에서만 바뀌어 첫 판 전에 kills 를 고르면 대기실 84 (실제 판 240), kills 판 → 판 끝 → survival 이면 대기실 800 (실제 판 280)
    [Fact]
    public void 대기실_hpMax는_지금_고른_모드_표()
    {
        var g = new Game(null, characters: true, hpMode: true, tune: Tune.Parse("kills:tank.hpMult=2"));
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.SetChar(1, "tank"); // 처음 캐릭터가 이미 탱크면 false
        Assert.Equal("tank", g.GetPlayer(1)!.@char);
        double Lobby() => J(g.Snapshot()).GetProperty("players").EnumerateArray().First(p => p.GetProperty("id").GetInt32() == 1).GetProperty("hpMax").GetDouble();
        double kills = C.HP_MAX_BY_MODE["kills"] * 2, survival = JsMath.Round(C.HP_MAX_BY_MODE["survival"] * C.HP_CHAR_MULT["tank"]);
        Assert.Equal(240, kills);
        Assert.Equal(280, survival);
        Assert.Equal(survival, Lobby());
        // 첫 판 전에 kills 를 고름 → 대기실도 판도 240
        Assert.True(g.SetMode("kills"));
        Assert.Equal(kills, Lobby());
        Assert.True(g.StartRound());
        Assert.Equal(kills, Lobby());
        // 판 끝 → survival 로 바꿈 → 대기실도 판도 280
        g.EndRound(null);
        Assert.Equal(kills, Lobby());
        Assert.True(g.SetMode("survival"));
        Assert.Equal(survival, Lobby());
        Assert.True(g.StartRound());
        Assert.Equal(survival, Lobby());
        // 연습으로 들어가도 연습 표 (덮기 없음 = 받은 표): 체력전은 꺼지지만 tune 은 기본 표
        g.EndRound(null);
        Assert.True(g.SetMode("kills"));
        Assert.True(g.StartPractice());
        Assert.True(ReferenceEquals(g.tuneBase, g.tune));
    }

    [Fact]
    public void 연습_방은_킬_표가_안_붙음()
    {
        var rooms = new Rooms(tune: C.BalanceTune());
        var conn = rooms.Connect(new Sock());
        rooms.Message(conn, J("{\"type\":\"practice\"}"));
        var g = conn.room!.game;
        Assert.Equal("practice", g.mode);
        Assert.True(ReferenceEquals(g.tuneBase, g.tune));
        Assert.Equal(1.1, g.tune!.KbDealt("ninja"));
    }

    // 같은 밀치기 한 번 (닌자가 탱크를 때림) 의 넉백: 킬 점수전 판 / 생존 판 = 1.6 / 1.1
    [Fact]
    public void 닌자_넉백이_킬_점수전에서_1_6_나누기_1_1배()
    {
        double Kb(string mode)
        {
            var rooms = new Rooms(tune: C.BalanceTune());
            var conn = rooms.Connect(new Sock());
            rooms.Message(conn, J("{\"type\":\"create\"}"));
            var g = conn.room!.game;
            rooms.Message(conn, J("{\"type\":\"setChar\",\"char\":\"ninja\"}"));
            rooms.Message(conn, J("{\"type\":\"addBot\"}"));
            if (mode != g.mode) rooms.Message(conn, J($"{{\"type\":\"setMode\",\"mode\":\"{mode}\"}}"));
            var ninja = g.Players().Single(p => !p.isBot);
            var target = g.Players().Single(p => p.isBot);
            g.SetChar(target.id, "tank");
            rooms.Message(conn, J("{\"type\":\"start\"}"));
            Assert.Equal(mode, g.mode);
            Assert.True(g.InRound());
            target.damage = 40;
            Assert.True(g.ApplyKnockback(target, 1, 0, 5, 0, C.STUN_MS, 10, new Src(ninja.id, "push"), true));
            return target.kbx;
        }
        double kills = Kb("kills");
        double surv = Kb("survival");
        Assert.True(surv > 0);
        Assert.True(Math.Abs(kills / surv - 1.6 / 1.1) < 1e-9, $"킬 {kills} / 생존 {surv} = {kills / surv}");
    }

    [Fact]
    public void sim_tune_우선순위()
    {
        Tune T(params string[] argv) => BotSim.ParseArgs(argv).GameTune()!;

        // 모드 없는 --tune 은 모든 모드에서 이김 (킬 덮기의 같은 자리도)
        var a = T("--balance", "on", "--tune", "ninja.kbDealt=1.3");
        Assert.Equal(1.3, a.For("kills").KbDealt("ninja"));
        Assert.Equal(1.3, a.For("survival").KbDealt("ninja"));
        Assert.Equal(1.45, a.For("kills").KbDealt("hunter")); // 나머지 킬 덮기는 그대로

        // 모드:값 은 그 모드에서만
        var b = T("--balance", "on", "--tune", "kills:hook.kbDealt=2");
        Assert.Equal(2, b.For("kills").KbDealt("hook"));
        Assert.Equal(1.2, b.For("survival").KbDealt("hook"));
        Assert.Equal(1.6, b.For("kills").KbDealt("ninja"));

        // 둘 다 주면 모드:값 이 그 모드에서 이김
        var c = T("--balance", "on", "--tune", "hook.kbDealt=1.5,kills:hook.kbDealt=2");
        Assert.Equal(2, c.For("kills").KbDealt("hook"));
        Assert.Equal(1.5, c.For("survival").KbDealt("hook"));

        // --balance off 면 --tune 그대로
        var d = T("--balance", "off", "--tune", "kills:hook.kbDealt=2");
        Assert.Equal(1, d.KbDealt("hook"));
        Assert.Equal(2, d.For("kills").KbDealt("hook"));
        Assert.Equal(1, d.For("kills").KbDealt("ninja"));

        // --hp-mult 는 예전처럼 기본 표에, 킬 덮기는 남음
        var h = T("--balance", "on", "--hp-mult", "tank=1.3");
        Assert.Equal(1.3, h.HpMult("tank"));
        Assert.Equal(1.3, h.For("kills").HpMult("tank"));
        Assert.Equal(1.6, h.For("kills").KbDealt("ninja"));

        // --balance on 만: BalanceTune 과 같음
        var e = T("--balance", "on");
        Assert.Equal(1.6, e.For("kills").KbDealt("ninja"));
        Assert.Equal(1.1, e.For("survival").KbDealt("ninja"));

        // summary.json options.tune: 모드 값을 줬을 때만 modes
        var jo = new JsonOut();
        BotSim.ParseArgs(new[] { "--tune", "kills:hook.kbDealt=2" }).Write(jo);
        Assert.Equal("{\"modes\":{\"kills\":{\"kbDealt\":{\"hook\":2}}}}", J(jo.ToString()).GetProperty("tune").GetRawText());
    }

    // sim 킬 점수전: --balance on (표의 킬 덮기) 과 --balance on --tune <BALANCE_KILLS> (모드 없는 값으로 덮기) 은 같은 판
    [Fact]
    public void sim_킬_점수전_balance_on은_킬_표를_tune으로_준_판과_같음()
    {
        string Chars(params string[] extra)
        {
            var o = BotSim.ParseArgs(new[] { "--rounds", "4", "--players", "4", "--maps", "flat,bowl", "--workers", "2", "--no-log", "--mode", "kills" }.Concat(extra).ToArray());
            var s = BotSim.SummarizeSim(BotSim.RunParallel(BotSim.PlanJobs(o), o));
            var j = new JsonOut();
            s.Write(j);
            return J(j.ToString()).GetProperty("chars").GetRawText();
        }
        var on = Chars("--balance", "on");
        Assert.Equal(Chars("--balance", "on", "--tune", C.BALANCE_KILLS), on);
        Assert.NotEqual(Chars("--tune", C.BALANCE), on); // 킬 표가 실제로 판을 바꿈
    }

    [Fact]
    public void TF_BALANCE_콘솔_한_줄에_킬_표()
    {
        var printed = new List<string>();
        var t = ServerBalance.FromEnv(null, printed.Add);
        Assert.Equal(new[] { $"밸런스 표: {C.BALANCE} · 킬 점수전: {C.BALANCE_KILLS}" }, printed);
        Assert.Equal(1.6, t!.For("kills").KbDealt("ninja"));
        printed.Clear();
        Assert.Null(ServerBalance.FromEnv("off", printed.Add)); // 끄면 킬 표도 같이 꺼짐
        Assert.Equal(new[] { "밸런스 표: 끔 (TF_BALANCE=off)" }, printed);
    }
}
