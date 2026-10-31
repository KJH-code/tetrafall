using System.Diagnostics;

namespace Tetrafall.Core;

// 틱 구간 재기 (서버 부하 측정 LoadBench 가 켬, 보통은 null 이라 비용 없음). Game.Tick 이 Begin → Lap(구간) 순서로 부름, 같은 구간은 더함
public sealed class Profiler
{
    readonly Stopwatch sw = new();
    double last;
    public readonly Dictionary<string, double> cur = new();

    public void Begin()
    {
        sw.Restart();
        last = 0;
    }

    public void Lap(string key)
    {
        double now = sw.Elapsed.TotalMilliseconds;
        cur[key] = cur.GetValueOrDefault(key) + now - last;
        last = now;
    }
}
