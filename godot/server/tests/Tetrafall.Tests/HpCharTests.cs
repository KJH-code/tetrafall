using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// 체력전 캐릭터별 HP (2026-10-31 재혁): HP = HP_MAX_BY_MODE × HP_CHAR_MULT (반올림, 캐릭터 켰을 때만) — test/hp.test.js 와 같은 것 + JS 판과 trace 같음
public class HpCharTests
{
    const double TICK = 1000.0 / 30;
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    [Fact]
    public void Per_character_hp_max_in_snapshot_top_stays_mode_value()
    {
        foreach (var mode in new[] { "survival", "kills", "master" })
        {
            var g = new Game(characters: true, hpMode: true);
            g.rng = () => 0.5;
            for (int i = 0; i < C.CHARACTERS.Length; i++)
            {
                g.AddPlayer(i + 1);
                g.SetChar(i + 1, C.CHARACTERS[i]);
            }
            if (mode != "survival") g.SetMode(mode);
            Assert.True(g.StartRound());
            double @base = C.HP_MAX_BY_MODE[mode];
            var s = J(g.Snapshot());
            Assert.Equal(@base, s.GetProperty("hpMax").GetDouble());
            foreach (var sp in s.GetProperty("players").EnumerateArray())
            {
                double want = Tetrafall.Core.Js.JsMath.Round(@base * C.HP_CHAR_MULT[sp.GetProperty("char").GetString()!]);
                Assert.Equal(want, sp.GetProperty("hpMax").GetDouble());
                Assert.Equal(want, sp.GetProperty("hp").GetDouble());
            }
        }
    }

    [Fact]
    public void Ko_threshold_per_character_and_off_without_characters()
    {
        var g = new Game(characters: true, hpMode: true);
        g.rng = () => 0.5;
        var hi = C.CHARACTERS.MaxBy(c => C.HP_CHAR_MULT[c])!;
        var lo = C.CHARACTERS.MinBy(c => C.HP_CHAR_MULT[c])!;
        string[] cs = { hi, lo, "builder" };
        for (int i = 0; i < 3; i++)
        {
            g.AddPlayer(i + 1);
            g.SetChar(i + 1, cs[i]);
        }
        Assert.True(g.StartRound());
        g.nextSpawnAt = double.PositiveInfinity;
        var (a, b) = (g.players[1], g.players[2]);
        double loMax = g.HpMax(b);
        Assert.True(g.HpMax(a) > loMax);
        a.damage = loMax;
        b.damage = loMax - 1;
        g.Tick(TICK);
        Assert.True(a.alive && b.alive);
        b.damage = loMax;
        g.Tick(TICK);
        Assert.False(b.alive);
        Assert.Equal("hp", b.deathCause);
        var off = new Game(hpMode: true);
        off.AddPlayer(1);
        off.players[1].@char = "tank";
        Assert.Equal(C.HP_MAX_BY_MODE["survival"], off.HpMax(off.players[1]));
    }

    [Fact]
    public void Hp_bot_rounds_match_JS_trace()
    {
        foreach (var row in Fixtures.Load("hp-trace.json").EnumerateArray())
        {
            string key = row[0].GetString()!;
            using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            int lines = 0;
            Scenarios.Run(Scenarios.Find(key), (t, logs, snap) =>
            {
                h.AppendData(Encoding.UTF8.GetBytes(Scenarios.TraceLine(t, logs, snap) + "\n"));
                lines++;
            });
            Assert.Equal(row[1].GetInt32(), lines);
            Assert.True(Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant() == row[2].GetString(), $"{key}: JS 와 다름 (trace.mjs {key} + Tetrafall.Trace trace {key} + trace-diff)");
        }
    }
}
