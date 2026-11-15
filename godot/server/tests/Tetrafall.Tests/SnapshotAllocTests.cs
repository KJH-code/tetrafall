using System.Globalization;
using System.Text;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// 스냅샷·숫자 글자 할당 줄이기 (사이클 4 u2): 출력 글자는 그대로, 스냅샷 한 번의 힙 할당만 예산 아래로
public class SnapshotAllocTests
{
    // Scenarios.Run 의 준비 (연습 아닌 판) 와 같게: 시드·봇·캐릭터 뽑기·모드·맵·시작
    static Game Prepare(Scenario sc)
    {
        var rnd = new Mulberry32(sc.seed);
        var g = new Game(_ => { }, characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500, hpMode: sc.hp);
        g.rng = rnd.AsFunc();
        if (sc.away) g.AddPlayer(1);
        for (int i = sc.away ? 1 : 0; i < sc.n; i++)
        {
            var b = g.AddBot()!;
            if (sc.characters) g.SetChar(b.id, C.CHARACTERS[(int)Math.Floor(rnd.Next() * C.CHARACTERS.Length)]);
        }
        if (sc.team) g.SetTeamMode(true);
        if (sc.mode != "survival") g.SetMode(sc.mode);
        g.SetMap(sc.map);
        Assert.True(g.StartRound());
        return g;
    }

    // 300틱 데운 뒤 600틱 (판이 끝나면 거기까지, 최소 300틱) 동안 Snapshot(false, events 붙이기) 한 번의 평균 할당 바이트
    static double SnapshotAllocAvg(Scenario sc, out int measured)
    {
        const int WARM = 300, MEASURE = 600;
        double TICK = 1000 / C.TICK_RATE;
        var g = Prepare(sc);
        g.Snapshot(true); // Scenarios.Run 처럼 t=0 스냅샷
        List<string> events = new();
        Action<JsonOut> extra = o =>
        {
            o.Key("events").Arr();
            foreach (var e in events) o.Raw(e);
            o.EndArr();
        };
        long sum = 0;
        measured = 0;
        for (int t = 0; t < WARM + MEASURE && g.phase != "over"; t++)
        {
            g.Tick(TICK);
            events = g.DrainEvents();
            long a0 = GC.GetAllocatedBytesForCurrentThread();
            var snap = g.Snapshot(false, extra);
            long a1 = GC.GetAllocatedBytesForCurrentThread();
            Assert.NotEmpty(snap);
            if (t < WARM) continue;
            sum += a1 - a0;
            measured++;
        }
        Assert.True(measured >= 300, $"{sc.name}: 잰 틱 {measured} < 300 (판이 너무 일찍 끝남)");
        return (double)sum / measured;
    }

    [Fact]
    public void Snapshot_alloc_budget_8p()
    {
        var sc = Scenarios.ALL[22];
        Assert.Equal("8명 survival 캐릭터 하늘", sc.name);
        double avg = SnapshotAllocAvg(sc, out int n);
        Assert.True(avg <= 55 * 1024, $"{sc.name}: 스냅샷 한 번 평균 {avg / 1024:F1}KB > 55KB ({n}틱)");
    }

    [Fact]
    public void Snapshot_alloc_budget_2p()
    {
        var sc = Scenarios.ALL[2];
        Assert.Equal("2명 survival 하늘", sc.name);
        double avg = SnapshotAllocAvg(sc, out int n);
        Assert.True(avg <= 20 * 1024, $"{sc.name}: 스냅샷 한 번 평균 {avg / 1024:F1}KB > 20KB ({n}틱)");
    }

    // 바꾸기 전 JsNumber.ToJs 그대로 (참조 구현 — 글자가 한 글자도 안 바뀌었는지 보는 기준)
    static string OldToJs(double d)
    {
        if (double.IsNaN(d)) return "NaN";
        if (double.IsPositiveInfinity(d)) return "Infinity";
        if (double.IsNegativeInfinity(d)) return "-Infinity";
        if (d == 0) return "0"; // -0 도 "0"
        if (d == Math.Floor(d) && Math.Abs(d) < 1e15) return ((long)d).ToString(CultureInfo.InvariantCulture);
        var r = d.ToString("R", CultureInfo.InvariantCulture);
        bool neg = r[0] == '-';
        if (neg) r = r.Substring(1);
        int e = 0;
        int ei = r.IndexOfAny(new[] { 'E', 'e' });
        if (ei >= 0) { e = int.Parse(r.Substring(ei + 1), CultureInfo.InvariantCulture); r = r.Substring(0, ei); }
        int dot = r.IndexOf('.');
        string intPart = dot >= 0 ? r.Substring(0, dot) : r, frac = dot >= 0 ? r.Substring(dot + 1) : "";
        string digits = (intPart + frac).TrimStart('0');
        int lead = (intPart + frac).Length - digits.Length; // 앞 0 개수
        int n = intPart.Length + e - lead; // 소수점 위치 (JS 알고리즘의 n)
        digits = digits.TrimEnd('0');
        int k = digits.Length;
        var sb = new StringBuilder();
        if (neg) sb.Append('-');
        if (k <= n && n <= 21) { sb.Append(digits).Append('0', n - k); }
        else if (0 < n && n <= 21) { sb.Append(digits, 0, n).Append('.').Append(digits, n, k - n); }
        else if (-6 < n && n <= 0) { sb.Append("0.").Append('0', -n).Append(digits); }
        else
        {
            sb.Append(digits[0]);
            if (k > 1) sb.Append('.').Append(digits, 1, k - 1);
            int ex = n - 1;
            sb.Append('e').Append(ex >= 0 ? "+" : "-").Append(Math.Abs(ex));
        }
        return sb.ToString();
    }

    [Fact]
    public void JsNumber_write_same_as_old()
    {
        var xs = new List<double>();
        foreach (var row in Fixtures.Load("jsnumber.json").EnumerateArray()) xs.Add(Fixtures.Bits(row[0].GetString()!));
        int fixtureCount = xs.Count;
        Assert.True(fixtureCount > 100);
        xs.AddRange(new[]
        {
            0.0, -0.0, 1e21, -1e21, 1e-7, 1e-6, 999999999999999.0, 1e15, double.Epsilon, -double.Epsilon,
            double.MaxValue, double.MinValue, double.NaN, double.PositiveInfinity, double.NegativeInfinity,
            -1e-7, -1e-6, 1e20, 1e22, 123456789012345680000.0, 0.1, 0.000001234, 1e15 + 0.5, -999999999999999.5,
        });
        // 무작위: x·10^k (k ∈ [−10, 25]), 음수·정수 섞음
        var rng = new Mulberry32(20261115);
        for (int i = 0; i < 200000; i++)
        {
            double x = rng.Next() * Math.Pow(10, Math.Floor(rng.Next() * 36) - 10);
            double kind = rng.Next();
            if (kind < 0.25) x = Math.Floor(x); // 정수
            if (rng.Next() < 0.5) x = -x;
            xs.Add(x);
        }
        var sb = new StringBuilder(64);
        var bad = new List<string>();
        foreach (var x in xs)
        {
            string want = OldToJs(x);
            sb.Clear();
            sb.Append('[');
            JsNumber.Write(sb, x);
            sb.Append(']'); // 앞뒤 글자를 안 건드리는지도
            string got = sb.ToString();
            if (got != "[" + want + "]" && bad.Count < 10) bad.Add($"{x:R}: 예전 {want} → Write {got}");
            string viaToJs = JsNumber.ToJs(x);
            if (viaToJs != want && bad.Count < 10) bad.Add($"{x:R}: 예전 {want} → ToJs {viaToJs}");
        }
        Assert.Empty(bad);
        Assert.True(xs.Count >= fixtureCount + 200000);
    }

    [Fact]
    public void JsNumber_write_zero_alloc()
    {
        var rng = new Mulberry32(7);
        var xs = new double[10000];
        for (int i = 0; i < xs.Length; i++)
        {
            double x = rng.Next() * Math.Pow(10, Math.Floor(rng.Next() * 30) - 8);
            if (i % 3 == 0) x = Math.Floor(x * 100); // 정수
            if (i % 5 == 0) x = -x;
            xs[i] = x;
        }
        var sb = new StringBuilder(1 << 16);
        void WriteAll()
        {
            for (int i = 0; i < xs.Length; i++)
            {
                if (i % 500 == 0) sb.Clear();
                JsNumber.Write(sb, xs[i]);
                sb.Append(',');
            }
        }
        WriteAll(); // 데우기 (JIT)
        WriteAll();
        long a0 = GC.GetAllocatedBytesForCurrentThread();
        WriteAll();
        long a1 = GC.GetAllocatedBytesForCurrentThread();
        Assert.Equal(0, a1 - a0);
    }

    [Fact]
    public void Utf8_cached_once()
    {
        // 글자 객체를 실행 중에 만듦 (리터럴은 붙박이라 다른 테스트와 같은 객체일 수 있음)
        var sb = new StringBuilder();
        for (int i = 0; i < 500; i++) sb.Append("{\"type\":\"state\",\"이름\":\"가😀\",").Append(i).Append('}');
        string text = sb.ToString();
        byte[] a = WsSocket.Utf8(text), b = WsSocket.Utf8(text);
        Assert.Same(a, b);
        Assert.Equal(Encoding.UTF8.GetBytes(text), a);
        string copy = new string(text.AsSpan()); // 내용은 같아도 다른 객체 → 따로 (참조가 열쇠)
        Assert.Equal(a, WsSocket.Utf8(copy));
    }
}
