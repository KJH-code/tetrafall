using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Tetrafall.Trace;

// C# 판 기록 (JS godot/server/tools/trace.mjs · tools/game-hash.js 와 같은 판):
//   dotnet run --project src/Tetrafall.Trace -- --list
//   dotnet run --project src/Tetrafall.Trace -- trace <번호|이름 일부> cs.jsonl [--ticks N]   → node tools/trace-diff.mjs js.jsonl cs.jsonl
//   dotnet run --project src/Tetrafall.Trace -- hash [--verbose]                             → node tools/game-hash.js 와 같은 해시면 34판 동등
var a = args.ToList();
if (a.Count == 0 || a[0] == "--list")
{
    for (int i = 0; i < Scenarios.ALL.Count; i++)
    {
        var s = Scenarios.ALL[i];
        Console.WriteLine($"{i}\t{s.name}\t맵 {s.map}\t시드 {s.seed}");
    }
    return 0;
}
int maxTicks = int.MaxValue;
int ti = a.IndexOf("--ticks");
if (ti >= 0)
{
    maxTicks = int.Parse(a[ti + 1]);
    a.RemoveRange(ti, 2);
}
if (a[0] == "trace")
{
    var sc = Scenarios.Find(a.Count > 1 ? a[1] : "0");
    string outPath = a.Count > 2 ? a[2] : "cs.jsonl";
    using var w = new StreamWriter(outPath, false, new UTF8Encoding(false)) { NewLine = "\n" };
    try
    {
        var (ticks, _) = Scenarios.Run(sc, (t, logs, snap) => w.WriteLine(Scenarios.TraceLine(t, logs, snap)), maxTicks);
        Console.WriteLine($"{sc.name}: {ticks}틱 → {outPath}");
    }
    catch (NotImplementedException e)
    {
        w.Flush();
        Console.WriteLine($"{sc.name}: 여기서 멈춤 — {e.Message} → {outPath} (그 앞까지)");
        return 2;
    }
    return 0;
}
if (a[0] == "hash")
{
    bool verbose = a.Contains("--verbose");
    using var all = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
    var sw = Stopwatch.StartNew();
    foreach (var sc in Scenarios.ALL)
    {
        string hx;
        int ticks;
        string phase;
        try
        {
            hx = Scenarios.Hash(sc, out ticks, out phase);
        }
        catch (NotImplementedException e)
        {
            Console.WriteLine($"(못 돎) {sc.name}: {e.Message}");
            return 2;
        }
        all.AppendData(Encoding.UTF8.GetBytes(hx));
        if (verbose) Console.WriteLine($"{hx[..16]}  {ticks,5}틱 {phase,-8} {sc.name}");
    }
    Console.WriteLine($"판 {Scenarios.ALL.Count}개 해시 {Convert.ToHexString(all.GetHashAndReset()).ToLowerInvariant()} ({sw.Elapsed.TotalSeconds:F1}초)");
    return 0;
}
Console.Error.WriteLine("명령: --list | trace <번호> <출력> [--ticks N] | hash [--verbose]");
return 1;
