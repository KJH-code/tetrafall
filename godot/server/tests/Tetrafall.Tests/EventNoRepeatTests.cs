using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Tests;

// 돌발 이벤트 같은 종류 연속 금지 (Game.Events.cs PickEventKind): 판 첫 이벤트는 5종 중 하나, 그 뒤로는 직전 종류를 뺀 4종 중 하나.
// 보급 (evKind 에 안 남음) 도 직전으로 침. 새 판이면 직전 기록을 비움
public class EventNoRepeatTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    static List<string> RoundEventKinds(Game g) =>
        g.DrainEvents().Select(J).Where(e => e.GetProperty("type").GetString() == "roundEvent").Select(e => e.GetProperty("kind").GetString()!).ToList();

    [Fact]
    public void PickEventKind_직전과_다르고_고르게()
    {
        var lasts = new List<string?> { null };
        lasts.AddRange(C.EVENT_KINDS);
        foreach (var last in lasts)
        {
            var count = new Dictionary<string, int>();
            for (int i = 0; i < 1000; i++)
            {
                string k = Game.PickEventKind(i / 1000.0, last)!; // 5종이면 늘 있음
                Assert.NotEqual(last, k);
                Assert.Contains(k, C.EVENT_KINDS);
                count[k] = count.GetValueOrDefault(k) + 1;
            }
            if (last == null)
            {
                Assert.Equal(C.EVENT_KINDS.Length, count.Count);
                foreach (var k in C.EVENT_KINDS) Assert.True(count[k] == 200, $"last null: {k} {count[k]}번");
            }
            else
            {
                Assert.Equal(C.EVENT_KINDS.Length - 1, count.Count);
                foreach (var k in C.EVENT_KINDS.Where(k => k != last)) Assert.True(count[k] == 250, $"last {last}: {k} {count.GetValueOrDefault(k)}번");
            }
        }
        // 4종은 원래 순서 그대로 r 구간에 놓임 (직전이 돌풍이면 폭우·보급·저중력·빙판)
        Assert.Equal(new[] { "rain", "supply", "lowgrav", "ice" }, new[] { 0.1, 0.3, 0.6, 0.9 }.Select(r => Game.PickEventKind(r, "wind")));
        Assert.Equal(new[] { "rain", "wind", "supply", "lowgrav", "ice" }, new[] { 0.1, 0.3, 0.5, 0.7, 0.9 }.Select(r => Game.PickEventKind(r, null)));
    }

    // rng 앞에 정한 값을 끼움 (이벤트 종류 고르기). 나머지는 시드 rng
    sealed class ScriptRng
    {
        public readonly Queue<double> script = new();
        readonly Func<double> inner;
        public ScriptRng(uint seed) => inner = new Mulberry32(seed).AsFunc();
        public double Next() => script.Count > 0 ? script.Dequeue() : inner();
    }

    // 사람 3명 킬 점수전 (가만히 서 있음, 무적), 블록·아이템 없음 — 판이 이벤트 두 번 동안 안 끝나게
    static (Game g, ScriptRng r) Kills()
    {
        var g = new Game(null, characters: true);
        var r = new ScriptRng(7);
        g.rng = r.Next;
        for (int i = 0; i < 3; i++) g.AddPlayer(i + 1);
        Assert.True(g.SetMode("kills"));
        Assert.True(g.SetRoundEvents(true));
        Begin(g);
        return (g, r);
    }

    static void Begin(Game g)
    {
        Assert.True(g.StartRound());
        foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
    }

    // 판 시작 뒤 n 번째 (0 부터) 이벤트를 r 로 고르게 하고 그 종류를 돌려줌
    static string EventAt(Game g, ScriptRng rng, int n, double r)
    {
        double at = g.roundStartTime + C.EVENT_FIRST_MS + n * C.EVENT_GAP_MS;
        while (g.time < at - 2 * TICK) g.Tick(TICK);
        g.DrainEvents();
        rng.script.Clear();
        rng.script.Enqueue(r);
        for (int i = 0; i < 4; i++) g.Tick(TICK);
        Assert.Equal("playing", g.phase);
        return Assert.Single(RoundEventKinds(g));
    }

    [Fact]
    public void 판_안에선_직전과_다른_종류_새_판이면_다시_5종()
    {
        var (g, r) = Kills();
        Assert.Equal("rain", EventAt(g, r, 0, 0.1)); // 첫 이벤트: 5종 중 floor(0.5) = 폭우
        Assert.Equal("wind", EventAt(g, r, 1, 0.1)); // 같은 r 이어도 직전 (폭우) 를 빼고 4종 중 floor(0.4) = 돌풍
        Assert.Equal("rain", EventAt(g, r, 2, 0.1)); // 직전은 돌풍 → 폭우 다시 가능
        // 다음 판: 직전 기록을 비움 → 지난 판 마지막 (폭우) 도 첫 이벤트로 나옴
        g.EndRound(null);
        Begin(g);
        Assert.Equal("rain", EventAt(g, r, 0, 0.1));
    }

    [Fact]
    public void 보급도_직전으로_침()
    {
        var (g, r) = Kills();
        Assert.Equal("supply", EventAt(g, r, 0, 0.5)); // 5종 중 floor(2.5) = 보급 (그 자리에서 끝나 evKind 는 null)
        Assert.Null(g.evKind);
        Assert.Equal("lowgrav", EventAt(g, r, 1, 0.5)); // 보급을 빼고 4종 중 floor(2) = 저중력
    }

    // 종류를 줄인 config (사이클 5 리뷰 F5): 1종이면 직전을 빼면 남는 게 없어 직전 그대로, 0종이면 null (이벤트 없음).
    // 예전엔 1종 판의 두 번째 이벤트 (판 시작 + EVENT_FIRST_MS + EVENT_GAP_MS) 에서 빈 배열을 찾아 IndexOutOfRange → 틱 예외로 방이 닫혔음
    [Fact]
    public void PickEventKind_1종_0종()
    {
        string[] one = { "ice" };
        foreach (var r in new[] { 0.0, 0.5, 0.999 })
        {
            Assert.Equal("ice", Game.PickEventKind(r, null, one));
            Assert.Equal("ice", Game.PickEventKind(r, "ice", one)); // 뺄 수 없음 → 같은 종류
            Assert.Equal("ice", Game.PickEventKind(r, "wind", one)); // 직전이 목록에 없으면 목록 그대로
            Assert.Null(Game.PickEventKind(r, null, Array.Empty<string>()));
            Assert.Null(Game.PickEventKind(r, "ice", Array.Empty<string>()));
        }
        // 2인자 판은 config 5종 그대로 (위 테스트와 같은 값)
        foreach (var r in new[] { 0.1, 0.3, 0.6, 0.9 }) Assert.Equal(Game.PickEventKind(r, "wind", C.EVENT_KINDS), Game.PickEventKind(r, "wind"));
    }

    // 실제 판에서 1종·0종: 이벤트 세 번 시각을 지나도 예외 없이 판이 돎. 이벤트마다 rng 는 정확히 한 번 (종류 고르기 — 빙판·0종은 방향 rng 없음)
    [Fact]
    public void 종류가_1종_0종이어도_판이_돎_rng_한_번()
    {
        foreach (var kinds in new[] { new[] { "ice" }, Array.Empty<string>() })
        {
            var g = new Game(null, characters: true);
            int calls = 0;
            var inner = new Mulberry32(11).AsFunc();
            g.rng = () => { calls++; return inner(); };
            for (int i = 0; i < 3; i++) g.AddPlayer(i + 1);
            Assert.True(g.SetMode("kills"));
            Assert.True(g.SetRoundEvents(true));
            g.eventKinds = kinds;
            Begin(g);
            var seen = new List<string>();
            for (int n = 0; n < 3; n++)
            {
                double at = g.roundStartTime + C.EVENT_FIRST_MS + n * C.EVENT_GAP_MS;
                while (g.time < at - 2 * TICK) g.Tick(TICK);
                seen.AddRange(RoundEventKinds(g));
                int before = calls;
                for (int i = 0; i < 4; i++) g.Tick(TICK); // 이벤트 시각을 지남 (봇·아이템·블록 없음 — 이 틱들의 rng 는 이벤트 고르기뿐)
                Assert.Equal(1, calls - before);
                Assert.Equal("playing", g.phase);
                seen.AddRange(RoundEventKinds(g));
            }
            Assert.Equal(kinds.Length == 0 ? new string[0] : new[] { "ice", "ice", "ice" }, seen);
        }
    }

    // 실제 봇 판 (시드 40개, 봇 4명 킬 점수전, 이벤트 켬, 판이 끝날 때까지): 같은 종류가 연이어 나온 적 0번, 종류마다 고르게
    [Fact]
    public void 실제_판_40개에서_연속_0번()
    {
        const int SEEDS = 40;
        var seqs = new List<string>[SEEDS];
        Parallel.For(0, SEEDS, i =>
        {
            var g = new Game(null, characters: true);
            g.rng = new Mulberry32((uint)(5000 + i)).AsFunc();
            Assert.True(g.SetMode("kills"));
            Assert.True(g.SetRoundEvents(true));
            for (int b = 0; b < 4; b++) g.AddBot();
            Assert.True(g.StartRound());
            var seq = new List<string>();
            while (g.phase == "playing" && g.time - g.roundStartTime < C.KILLS_TIME_MS + 5000)
            {
                g.Tick(TICK);
                seq.AddRange(RoundEventKinds(g));
            }
            Assert.NotEqual("playing", g.phase); // 판이 끝남 (목표 킬 또는 시간)
            seqs[i] = seq;
        });
        int repeats = 0;
        var count = new Dictionary<string, int>();
        foreach (var seq in seqs)
        {
            for (int j = 0; j < seq.Count; j++)
            {
                count[seq[j]] = count.GetValueOrDefault(seq[j]) + 1;
                if (j > 0 && seq[j] == seq[j - 1]) repeats++;
            }
        }
        int total = count.Values.Sum();
        string desc = string.Join(" ", C.EVENT_KINDS.Select(k => $"{k}={count.GetValueOrDefault(k)}"));
        Assert.True(repeats == 0, $"연속 {repeats}번 ({desc})");
        Assert.True(total >= 120, $"이벤트 {total}개 ({desc})");
        foreach (var k in C.EVENT_KINDS) Assert.True(count.GetValueOrDefault(k) >= total * 0.1, $"{k} 가 10% 아래 ({desc})");
    }
}
