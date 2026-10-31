using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Tetrafall.Sim;

// npm run sim 의 C# 판: dotnet run -c Release --project godot/server/src/Tetrafall.Sim -- --rounds 200 --players 2,4 …
// 옵션·결과 모양은 tools/sim.js 와 같음 (sim-logs/<시각>/summary.json + 워커 로그 → npm run stats -- sim-logs/<시각>)
try
{
    var o = BotSim.ParseArgs(args);
    string root = FindRoot();
    JsonElement? baseSum = null;
    if (o.@base != null)
    {
        string f = Directory.Exists(o.@base) ? Path.Combine(o.@base, "summary.json") : o.@base;
        baseSum = JsonDocument.Parse(File.ReadAllText(f)).RootElement.GetProperty("summary");
    }
    var jobs = BotSim.PlanJobs(o);
    string stamp = DateTime.UtcNow.ToString("yyyy-MM-dd-HH-mm-ss");
    string outDir = o.@out ?? Path.Combine(root, "sim-logs", stamp);
    Directory.CreateDirectory(outDir);
    Console.WriteLine($"봇 판 {jobs.Count}판 (인원 {string.Join("·", o.players)}, 맵 {o.maps.Count}개, 캐릭터 {o.chars.Count}명{(o.mirror ? ", 자리 바꿔 2번" : "")}, 난이도 {o.level}, 하늘 계단 {(o.sky ? "켬" : "끔")}, 시드 {o.seed}) · 워커 {Math.Min(o.workers, jobs.Count)}개");
    var sw = Stopwatch.StartNew();
    long last = 0;
    var results = BotSim.RunParallel(jobs, o, o.log ? outDir : null, (d, n) =>
    {
        if (!Console.IsOutputRedirected && sw.ElapsedMilliseconds - Interlocked.Read(ref last) > 500)
        {
            Interlocked.Exchange(ref last, sw.ElapsedMilliseconds);
            Console.Write($"\r  {d}/{n}");
        }
    });
    if (!Console.IsOutputRedirected) Console.Write("\r");
    var s = BotSim.SummarizeSim(results);
    Console.WriteLine($"  {sw.Elapsed.TotalSeconds:F1}초 걸림\n");
    Console.WriteLine(BotSim.FormatSim(s, baseSum));
    string? commit = null;
    try
    {
        commit = File.ReadAllText(Path.Combine(root, ".git", "HEAD")).Trim();
        if (commit.StartsWith("ref: ")) commit = File.ReadAllText(Path.Combine(root, ".git", commit[5..])).Trim();
    }
    catch { }
    File.WriteAllText(Path.Combine(outDir, "summary.json"), BotSim.SummaryJson(commit, o, s), new UTF8Encoding(false));
    string rel = Path.GetRelativePath(Environment.CurrentDirectory, outDir);
    Console.WriteLine($"\n저장: {rel}/summary.json{(o.log ? $" · 자세히: npm run stats -- {rel}" : "")}");
    return 0;
}
catch (ArgumentException e)
{
    Console.Error.WriteLine(e.Message);
    return 1;
}

// 레포 뿌리 (shared/config.js 가 있는 곳): TF_ROOT 또는 위로 찾기
static string FindRoot()
{
    var env = Environment.GetEnvironmentVariable("TF_ROOT");
    if (!string.IsNullOrEmpty(env)) return env;
    foreach (var start in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
    {
        var d = new DirectoryInfo(start);
        while (d != null)
        {
            if (File.Exists(Path.Combine(d.FullName, "shared", "config.js"))) return d.FullName;
            d = d.Parent;
        }
    }
    return Environment.CurrentDirectory;
}
