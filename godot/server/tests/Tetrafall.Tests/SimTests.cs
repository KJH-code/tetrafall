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
}
