using Tetrafall.Core.Js;

namespace Tetrafall.Tests;

// JS 와 비트·글자까지 같은지 (판 해시 동등성의 바닥)
public class JsCompatTests
{
    static string Hex(double x) => Convert.ToHexString(BitConverter.GetBytes(x)).ToLowerInvariant();

    [Fact]
    public void JsMath_matches_V8_bits()
    {
        int n = 0;
        var bad = new List<string>();
        foreach (var row in Fixtures.Load("jsmath.json").EnumerateArray())
        {
            var v = row.EnumerateArray().Select(e => e.GetString()!).ToArray();
            double a = Fixtures.Bits(v[0]), b = Fixtures.Bits(v[1]), c = Fixtures.Bits(v[2]);
            void Eq(string what, double got, string want)
            {
                if (Hex(got) != want && bad.Count < 10) bad.Add($"{what}({a}, {b}, {c}) = {got}, JS {Fixtures.Bits(want)}");
            }
            Eq("sin", JsMath.Sin(a), v[3]);
            Eq("cos", JsMath.Cos(a), v[4]);
            Eq("exp", JsMath.Exp(a > 50 ? 50 : a), v[5]);
            Eq("atan2", JsMath.Atan2(a, b), v[6]);
            Eq("hypot2", JsMath.Hypot(a, b), v[7]);
            Eq("hypot3", JsMath.Hypot(a, b, c), v[8]);
            Eq("round(c)", JsMath.Round(c), v[9]);
            Eq("round(a)", JsMath.Round(a), v[10]);
            n++;
        }
        Assert.True(n > 1000);
        Assert.Empty(bad);
    }

    [Fact]
    public void JsNumber_matches_JSON_stringify()
    {
        var bad = new List<string>();
        foreach (var row in Fixtures.Load("jsnumber.json").EnumerateArray())
        {
            double x = Fixtures.Bits(row[0].GetString()!);
            var want = row[1].GetString()!;
            var got = new JsonOut().Num(x).ToString();
            if (got != want && bad.Count < 10) bad.Add($"{want} → C# {got}");
            for (int d = 0; d < 4; d++)
            {
                var f = JsNumber.ToFixed(x, d);
                if (f != row[2 + d].GetString() && bad.Count < 10) bad.Add($"{want}.toFixed({d}) = {row[2 + d].GetString()} → C# {f}");
            }
        }
        Assert.Empty(bad);
    }

    [Fact]
    public void Mulberry32_matches_sim_js()
    {
        foreach (var row in Fixtures.Load("mulberry32.json").EnumerateArray())
        {
            var rng = new Mulberry32((uint)row[0].GetDouble());
            foreach (var want in row[1].EnumerateArray()) Assert.Equal(want.GetString(), Hex(rng.Next()));
        }
    }

    [Fact]
    public void JsonOut_escapes_like_JSON_stringify()
    {
        var s = new JsonOut().Obj().P("a\"b", "줄\n탭\t\u0001\\ \ud800 끝").P("n", double.PositiveInfinity).P("z", -0.0).EndObj().ToString();
        Assert.Equal("{\"a\\\"b\":\"줄\\n탭\\t\\u0001\\\\ \\ud800 끝\",\"n\":null,\"z\":0}", s);
    }
}
