using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Sim;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// 방 밸런스 표 (ConfigBalance.cs, 고도 판 전용): 서버 방 (대전·연습·튜토리얼) 의 판만 이 표로 돎.
// Rooms 에 안 주면 표 없음 (테스트·LoadBench·Trace 는 예전 그대로), sim 은 --balance on 일 때만
public class BalanceTests
{
    static JsonElement J(string s) => JsonDocument.Parse(s).RootElement;

    sealed class Sock : ISocket
    {
        public bool Open => true;
        public void Send(string text) { }
    }

    // 방 하나 만들기 (type: create·practice·tutorial)
    static Room MakeRoom(Rooms rooms, string type)
    {
        var conn = rooms.Connect(new Sock());
        rooms.Message(conn, J($"{{\"type\":\"{type}\"}}"));
        return conn.room!;
    }

    [Fact]
    public void 표의_모든_줄이_Tune_Parse를_지남()
    {
        var t = Tune.Parse(C.BALANCE); // 모르는 캐릭터·키, 0 이하면 여기서 던짐
        int n = 0;
        foreach (var key in Tune.KEYS)
        {
            var table = t.Table(key)!;
            n += table.Count;
            if (key != "kbTaken" && key != "kbDealt") Assert.True(table.Count == 0, $"{key}: 표에는 kbTaken·kbDealt 만 (클라 쿨 표시와 어긋나지 않게)");
        }
        Assert.Equal(C.BALANCE.Split(',').Length, n); // 같은 자리를 두 번 쓴 줄 없음
        Assert.True(n > 0);
        // BalanceTune 은 부를 때마다 같은 값의 새 객체
        var a = C.BalanceTune();
        var b = C.BalanceTune();
        Assert.NotSame(a, b);
        foreach (var key in Tune.KEYS) Assert.Equal(t.Table(key)!.OrderBy(x => x.Key), a.Table(key)!.OrderBy(x => x.Key));
    }

    [Fact]
    public void 방은_표로_만든_판을_돌림_인자_없으면_null()
    {
        var rooms = new Rooms(tune: C.BalanceTune());
        var r1 = MakeRoom(rooms, "create");
        var r2 = MakeRoom(rooms, "create");
        Assert.NotSame(r1, r2);
        foreach (var r in new[] { r1, r2 })
        {
            Assert.NotNull(r.game.tune);
            Assert.Equal(0.85, r.game.tune!.KbDealt("cannon"));
            foreach (var key in Tune.KEYS) Assert.Equal(C.BalanceTune().Table(key)!.OrderBy(x => x.Key), r.game.tune.Table(key)!.OrderBy(x => x.Key));
        }
        Assert.NotSame(r1.game.tune, r2.game.tune); // 판마다 따로 (한 방이 고쳐도 다른 방은 그대로)
        r1.game.tune!.Set("cannon", "kbDealt", 2);
        Assert.Equal(0.85, r2.game.tune!.KbDealt("cannon"));
        Assert.Equal(0.85, MakeRoom(rooms, "create").game.tune!.KbDealt("cannon")); // 뒤에 만든 방도 원래 표

        // 인자 없으면 표 없음 → 곱셈 자체가 없는 예전 판
        var plain = new Rooms();
        Assert.Null(MakeRoom(plain, "create").game.tune);
        Assert.Null(MakeRoom(plain, "practice").game.tune);
        Assert.Null(MakeRoom(plain, "tutorial").game.tune);
    }

    [Fact]
    public void 연습_튜토리얼_방도_같은_표()
    {
        var rooms = new Rooms(tune: C.BalanceTune());
        var practice = MakeRoom(rooms, "practice");
        var tutorial = MakeRoom(rooms, "tutorial");
        Assert.True(practice.practice);
        Assert.False(practice.tutorial);
        Assert.True(tutorial.tutorial);
        Assert.NotNull(tutorial.game.tutorial);
        foreach (var r in new[] { practice, tutorial })
        {
            Assert.NotNull(r.game.tune);
            foreach (var key in Tune.KEYS) Assert.Equal(C.BalanceTune().Table(key)!.OrderBy(x => x.Key), r.game.tune!.Table(key)!.OrderBy(x => x.Key));
        }
        Assert.NotSame(practice.game.tune, tutorial.game.tune);
    }

    [Fact]
    public void TF_BALANCE_off면_null()
    {
        var printed = new List<string>();
        Assert.Null(ServerBalance.FromEnv("off", printed.Add));
        Assert.Equal(new[] { "밸런스 표: 끔 (TF_BALANCE=off)" }, printed);

        foreach (var v in new string?[] { null, "", "on", "OFF" }) // "off" 글자 그대로만 끔
        {
            printed.Clear();
            var t = ServerBalance.FromEnv(v, printed.Add);
            Assert.NotNull(t);
            Assert.Equal(0.85, t!.KbDealt("cannon"));
            Assert.Equal(new[] { $"밸런스 표: {C.BALANCE}" }, printed);
        }
    }

    static (string chars, string options) SimRun(params string[] extra)
    {
        var o = BotSim.ParseArgs(new[] { "--rounds", "14", "--players", "2,4", "--workers", "2", "--no-log" }.Concat(extra).ToArray());
        var s = BotSim.SummarizeSim(BotSim.RunParallel(BotSim.PlanJobs(o), o));
        var j = new JsonOut();
        s.Write(j);
        var jo = new JsonOut();
        o.Write(jo);
        return (JsonDocument.Parse(j.ToString()).RootElement.GetProperty("chars").GetRawText(), jo.ToString());
    }

    [Fact]
    public void sim_balance_on은_같은_tune_글자와_같은_결과()
    {
        var off = SimRun();
        var on = SimRun("--balance", "on");
        var tune = SimRun("--tune", C.BALANCE);
        Assert.Equal(tune.chars, on.chars);
        Assert.NotEqual(off.chars, on.chars); // 표가 실제로 판을 바꿈
        Assert.Equal(off.chars, SimRun("--balance", "off").chars);

        // summary.json options: 켰을 때만 "balance":true — 끄면 (기본) 예전과 글자까지 같음
        Assert.Contains("\"balance\":true", on.options);
        Assert.DoesNotContain("balance", off.options);
        Assert.Equal(off.options, SimRun("--balance", "off").options);
        Assert.DoesNotContain("\"tune\"", on.options); // 표는 options.tune 에 안 풀어 씀 (--tune 을 줬을 때만)
    }

    [Fact]
    public void sim_balance_위에_tune을_덮음_같은_자리는_tune이_이김()
    {
        Assert.Null(BotSim.ParseArgs(Array.Empty<string>()).GameTune()); // 기본: 표 없음
        Assert.Null(BotSim.ParseArgs(new[] { "--balance", "off" }).GameTune());

        var t = BotSim.ParseArgs(new[] { "--balance", "on", "--tune", "cannon.kbDealt=1.5,tank.skillCd=0.5" }).GameTune()!;
        Assert.Equal(1.5, t.KbDealt("cannon")); // 같은 캐릭터·키 → --tune
        Assert.Equal(0.5, t.SkillCd("tank")); // 표에 없는 자리는 더해짐
        Assert.Equal(C.BalanceTune().KbDealt("berserker"), t.KbDealt("berserker")); // 나머지는 표 그대로
        Assert.Equal(C.BalanceTune().KbTaken("ninja"), t.KbTaken("ninja"));

        // 그 위에 --hp-mult (예전 GameTune 규칙 그대로)
        var h = BotSim.ParseArgs(new[] { "--balance", "on", "--hp-mult", "tank=1.3" }).GameTune()!;
        Assert.Equal(1.3, h.HpMult("tank"));
        Assert.Equal(C.BalanceTune().KbDealt("cannon"), h.KbDealt("cannon"));
    }

    [Fact]
    public void 튜토리얼_자동조종이_표로도_8명_끝까지()
    {
        foreach (var ch in C.CHARACTERS)
        {
            var r = Scenarios.RunTutorial(ch, (_, _, _) => { }, tune: C.BalanceTune());
            Assert.True(r.done, $"{ch}: 밸런스 표로 튜토리얼이 안 끝남 ({r.ticks}틱, 결과 {string.Join(",", r.results)})");
        }
    }

    // 탱크 패시브 (덜 밀림) 가 표 때문에 뒤집히지 않게: 누구도 탱크보다 덜 밀리지 않음
    [Fact]
    public void 탱크보다_덜_밀리는_캐릭터_없음()
    {
        var t = C.BalanceTune();
        double tank = C.TANK_KB_TAKEN * t.KbTaken("tank");
        Assert.Equal(C.TANK_KB_TAKEN, tank); // 표가 탱크의 받는 넉백은 안 건드림
        foreach (var ch in C.CHARACTERS)
        {
            if (ch == "tank") continue;
            double taken = (ch == "ninja" ? C.NINJA_KB_TAKEN : 1) * t.KbTaken(ch);
            Assert.True(taken > tank, $"{ch}: 받는 넉백 {taken} 이 탱크 {tank} 이하");
        }
    }
}
