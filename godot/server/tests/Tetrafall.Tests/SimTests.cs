using System.Security.Cryptography;
using System.Text;
using Tetrafall.Core.Js;
using Tetrafall.Sim;

namespace Tetrafall.Tests;

// S7: C# 봇 판 시뮬레이션이 tools/sim.js 와 같은 판·같은 요약·같은 로그 (fixtures/sim.json), 워커 수가 달라도 같은 결과
public class SimTests
{
    [Fact]
    public void Sim_summary_text_and_logs_match_JS()
    {
        var want = Fixtures.Load("sim.json");
        var o = BotSim.ParseArgs(new[] { "--rounds", "28", "--players", "2,3", "--workers", "1" });
        var jobs = BotSim.PlanJobs(o);
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var results = jobs.Select(j => BotSim.RunJob(j, o, m => h.AppendData(Encoding.UTF8.GetBytes(m + "\n")))).ToList();
        Assert.Equal(want.GetProperty("jobs").GetInt32(), results.Count);
        var s = BotSim.SummarizeSim(results);
        var j = new JsonOut();
        s.Write(j);
        Assert.Equal(want.GetProperty("summary").GetString(), j.ToString());
        Assert.Equal(want.GetProperty("text").GetString(), BotSim.FormatSim(s));
        Assert.Equal(want.GetProperty("logSha").GetString(), Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant());
    }

    [Fact]
    public void Sim_same_result_for_any_worker_count()
    {
        string Run(int workers)
        {
            var o = BotSim.ParseArgs(new[] { "--rounds", "7", "--players", "2", "--workers", workers.ToString(), "--no-log" });
            var j = new JsonOut();
            BotSim.SummarizeSim(BotSim.RunParallel(BotSim.PlanJobs(o), o)).Write(j);
            return j.ToString();
        }
        Assert.Equal(Run(1), Run(3));
    }

    [Fact]
    public void Pretty_matches_JSON_stringify_indent_1()
    {
        Assert.Equal("{\n \"a\": [\n  1,\n  \"x\"\n ],\n \"b\": {},\n \"c\": [],\n \"d\": null\n}", BotSim.Pretty("{\"a\":[1,\"x\"],\"b\":{},\"c\":[],\"d\":null}"));
    }

    // --hp-mult 숫자 하나: 0 이하·숫자가 아닌 것 ("1.2.3") 은 ArgumentException (Program 이 잡아 종료 코드 1).
    // 예전엔 그대로 넘어가 판마다 Tune.Set 이 워커 안에서 던짐 (AggregateException → 처리 안 된 예외로 죽음)
    [Theory]
    [InlineData("0")]
    [InlineData("0.0")]
    [InlineData("1.2.3")]
    [InlineData(".")]
    [InlineData("tank=0")]
    [InlineData("tank=-1")]
    [InlineData("nobody=1.1")]
    public void HpMult_rejects_bad_values(string v)
    {
        Assert.Throws<ArgumentException>(() => BotSim.ParseHpMult(v));
        Assert.Throws<ArgumentException>(() => BotSim.ParseArgs(new[] { "--hp", "on", "--hp-mult", v }));
    }

    [Fact]
    public void HpMult_single_number_applies_to_all_characters()
    {
        var all = BotSim.ParseHpMult("1.1");
        Assert.Equal(Tetrafall.Core.C.CHARACTERS.Length, all.Count);
        Assert.All(Tetrafall.Core.C.CHARACTERS, c => Assert.Equal(1.1, all[c]));
        Assert.Equal(0.5, BotSim.ParseHpMult(".5")["tank"]);
        var some = BotSim.ParseHpMult("tank=1.2,ninja=0.9");
        Assert.Equal(new[] { "tank", "ninja" }, some.Keys.ToArray());
        Assert.Equal(1.2, some["tank"]);
        Assert.Equal(0.9, some["ninja"]);
    }
}
