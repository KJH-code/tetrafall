using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Trace;

namespace Tetrafall.Tests;

// 고도 판 전용 C# 자체 기준선 (Scenarios.CS, fixtures/cs-hash.json — JS 와 비교 안 함): 실제 방 설정 (밸런스 표·돌발 이벤트·캐릭터·하늘 계단)
// 으로 돈 판들의 틱별 해시. 뒤 변경이 이 길을 몰래 바꾸면 떨어짐 — 의도한 변경이면 cshash --write 로 다시 고정 (godot/server/README.md)
public class CsHashTests
{
    const string REFIX = "의도한 변경이면 `dotnet run --project src/Tetrafall.Trace -- cshash --write tests/Tetrafall.Tests/fixtures/cs-hash.json` 로 다시 고정하고 커밋에 바뀐 판과 까닭을 적기";

    sealed record Ran(string hash, int ticks, string phase, Dictionary<string, int> eventKinds);

    // CS 판 전부 한 번만 돌림 (①·② 가 같이 씀): 해시 + 스냅샷 events 의 roundEvent 종류별 횟수
    static readonly Lazy<Dictionary<string, Ran>> RUNS = new(() =>
    {
        var res = new Dictionary<string, Ran>();
        foreach (var sc in Scenarios.CS)
        {
            var kinds = new Dictionary<string, int>();
            string hx = Scenarios.Hash(sc, out int ticks, out string phase, snap =>
            {
                if (!snap.Contains("roundEvent")) return;
                foreach (var e in JsonDocument.Parse(snap).RootElement.GetProperty("events").EnumerateArray())
                {
                    if (e.GetProperty("type").GetString() != "roundEvent") continue;
                    string k = e.GetProperty("kind").GetString()!;
                    kinds[k] = kinds.GetValueOrDefault(k) + 1;
                }
            });
            res[sc.name] = new Ran(hx, ticks, phase, kinds);
        }
        return res;
    });

    static List<(string name, string hash, int ticks, string phase)> Fixture() =>
        Fixtures.Load("cs-hash.json").EnumerateArray().Select(r => (r[0].GetString()!, r[1].GetString()!, r[2].GetInt32(), r[3].GetString()!)).ToList();

    [Fact]
    public void Cs_hash_matches_fixture()
    {
        var bad = new List<string>();
        foreach (var row in Fixture())
        {
            if (!RUNS.Value.TryGetValue(row.name, out var r))
            {
                bad.Add($"{row.name}: Scenarios.CS 에 없음 — {REFIX}");
                continue;
            }
            if (r.hash != row.hash || r.ticks != row.ticks)
                bad.Add($"{row.name}: C# 기준선과 다름 (해시 {r.hash[..16]} / 고정 {row.hash[..16]}, 틱 {r.ticks} / 고정 {row.ticks}) — {REFIX}");
        }
        Assert.True(bad.Count == 0, string.Join("\n", bad));
    }

    [Fact]
    public void Cs_scenarios_cover_every_event_kind()
    {
        var total = new Dictionary<string, int>();
        foreach (var sc in Scenarios.CS)
        {
            var kinds = RUNS.Value[sc.name].eventKinds;
            if (sc.mode == "master") Assert.True(kinds.Values.Sum() == 0, $"{sc.name}: 블록 마스터는 돌발 이벤트를 켜도 안 돌아야 함 ({string.Join(" ", kinds.Select(kv => $"{kv.Key}={kv.Value}"))})");
            foreach (var (k, v) in kinds) total[k] = total.GetValueOrDefault(k) + v;
        }
        Assert.Contains(Scenarios.CS, sc => sc.mode == "master" && sc.events); // 켜 둔 마스터 판이 있어야 위 확인이 뜻이 있음
        foreach (var k in C.EVENT_KINDS) Assert.True(total.GetValueOrDefault(k) >= 1, $"CS 판 전체에 돌발 이벤트 {k} 가 한 번도 안 나옴 ({string.Join(" ", total.Select(kv => $"{kv.Key}={kv.Value}"))})");
        Assert.Empty(total.Keys.Except(C.EVENT_KINDS)); // 표에 없는 종류 없음
    }

    [Fact]
    public void Balance_actually_flows()
    {
        // 가장 짧은 CS 생존 판을 밸런스 표 없이 돌리면 해시가 고정값과 달라야 함 (표가 Run → Game 까지 실제로 닿음)
        var fx = Fixture();
        var (sc, row) = Scenarios.CS.Where(s => s.mode == "survival" && s.balance)
            .Select(s => (s, fx.First(r => r.name == s.name)))
            .OrderBy(p => p.Item2.ticks).First();
        string off = Scenarios.Hash(sc with { balance = false }, out _, out _);
        Assert.NotEqual(row.hash, off);
    }

    [Fact]
    public void Fixture_names_match_CS()
    {
        Assert.Equal(Scenarios.CS.Select(s => s.name).ToList(), Fixture().Select(r => r.name).ToList());
    }

    [Fact]
    public void 번호가_목록_밖이면_시나리오_없음()
    {
        // trace c99·c-1·h999·999·s99 가 ArgumentOutOfRangeException 으로 죽지 않고 이름 못 찾을 때와 같은 '시나리오 없음'
        foreach (string key in new[] { "c99", "c-1", $"c{Scenarios.CS.Count}", "h999", "h-1", "999", "-1", $"{Scenarios.ALL.Count}" })
            Assert.Contains("시나리오 없음", Assert.Throws<ArgumentException>(() => Scenarios.Find(key)).Message);
        foreach (string key in new[] { "s99", "s-1", $"s{Scenarios.SCRIPTED.Count}", "s99999999999" })
            Assert.Contains("시나리오 없음", Assert.Throws<ArgumentException>(() => Scenarios.FindScripted(key)).Message);
        // 목록 안 번호는 그대로
        Assert.Same(Scenarios.CS[0], Scenarios.Find("c0"));
        Assert.Same(Scenarios.CS[^1], Scenarios.Find($"c{Scenarios.CS.Count - 1}"));
        Assert.Same(Scenarios.ALL[^1], Scenarios.Find($"{Scenarios.ALL.Count - 1}"));
        var h0 = Scenarios.Find("h0");
        Assert.True(h0.hp && h0.name == Scenarios.ALL[0].name + " 체력전");
        Assert.Same(Scenarios.SCRIPTED[^1], Scenarios.FindScripted($"s{Scenarios.SCRIPTED.Count - 1}"));
    }

    [Fact]
    public void Cshash_write_뒤가_옵션이면_사용법_오류()
    {
        // cshash --write --verbose: '--verbose' 를 경로로 받아 지금 폴더에 파일을 만들던 것 → 판을 돌리기 전에 사용법 오류 (종료 코드 1)
        var main = typeof(Scenarios).Assembly.EntryPoint!;
        foreach (var args in new[] { new[] { "cshash", "--write", "--verbose" }, new[] { "cshash", "--write" } })
            Assert.Equal(1, main.Invoke(null, new object[] { args }));
        Assert.False(File.Exists("--verbose"));
    }
}
