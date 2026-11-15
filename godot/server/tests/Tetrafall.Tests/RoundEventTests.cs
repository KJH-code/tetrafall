using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 돌발 이벤트 (고도 판 전용 방 옵션, Game.Events.cs · ConfigEvents.cs): 끄면 예전 판 그대로 (rng 도 안 부름),
// 켜면 생존·킬 점수전 판 중에 EVENT_GAP_MS 마다 블록 폭우·돌풍·보급·저중력·빙판 중 하나
public class RoundEventTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    sealed class Sock : ISocket
    {
        public readonly List<string> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(text);
    }

    // rng 를 감싸 부른 횟수를 셈. script 가 남아 있으면 그 값을 먼저 돌려줌 (이벤트 종류·방향 고르기)
    sealed class CountedRng
    {
        public int calls;
        public readonly Queue<double> script = new();
        readonly Func<double> inner;
        public CountedRng(uint seed) => inner = new Mulberry32(seed).AsFunc();
        public double Next()
        {
            calls++;
            return script.Count > 0 ? script.Dequeue() : inner();
        }
    }

    // 사람 n명 (가만히 서 있음), 평지. 블록에 안 깔리게 무적 (판이 테스트 도중에 끝나지 않게)
    static (Game g, List<string> lines, CountedRng rng) Humans(int n = 2, bool sky = false, string? mode = null, bool events = true, uint seed = 11)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true, skyStairs: sky);
        var r = new CountedRng(seed);
        g.rng = r.Next;
        for (int i = 0; i < n; i++) g.AddPlayer(i + 1);
        if (mode != null) Assert.True(g.SetMode(mode));
        if (events) Assert.True(g.SetRoundEvents(true));
        Assert.True(g.StartRound());
        foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
        return (g, lines, r);
    }

    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }

    static List<JsonElement> EventsOf(Game g, string type) => g.DrainEvents().Select(J).Where(e => e.GetProperty("type").GetString() == type).ToList();

    static int AutoCount(Game g) => g.pieces.Count(pc => pc.controller == null && pc.thrownBy == null && !pc.sky && pc.ghostBy == null);

    // 땅에 선 p 가 점프해 땅에 다시 닿을 때까지의 꼭짓점 높이 (뛴 자리 기준). step: 한 틱 (판 중이면 g.Tick, 결과 화면이면 IntegratePlayer 직접)
    static double JumpApex(Player p, Action step)
    {
        double z0 = p.z, top = z0;
        p.input.jump = true;
        step();
        p.input.jump = false;
        Assert.False(p.grounded);
        for (int i = 0; i < 10 * C.TICK_RATE && !p.grounded; i++)
        {
            top = Math.Max(top, p.z);
            step();
        }
        Assert.True(p.grounded);
        return top - z0;
    }

    // 땅에 선 p 에게 넉백 kbx 를 직접 넣고, 0 이 될 때까지 (넉백 감쇠) 간 x 거리. 내내 땅 위
    const double SLIDE_KB = 5;
    static double Slide(Player p, Action step)
    {
        double x0 = p.x;
        p.kbx = SLIDE_KB;
        for (int i = 0; i < 10 * C.TICK_RATE && p.kbx != 0; i++)
        {
            step();
            Assert.True(p.grounded);
        }
        Assert.Equal(0, p.kbx);
        return p.x - x0;
    }

    // 사람 둘 판의 첫 틱 뒤 (이벤트를 시작할 수 있게), 1번은 가운데에 혼자 (2번은 구석에 비켜 둠)
    static (Game g, List<string> lines, CountedRng rng, Player a) Solo()
    {
        var (g, lines, r) = Humans();
        g.nextSpawnAt = double.PositiveInfinity;
        g.Tick(TICK); // 첫 틱이 새 판을 알아챔 → 그 뒤에 이벤트 시작
        CharKit.Place(g.players[2], 1.5, 1.5);
        CharKit.Place(g.players[1], g.W / 2.0, g.D / 2.0);
        return (g, lines, r, g.players[1]);
    }

    [Fact]
    public void 끄면_rng를_안_부르고_스냅샷이_그대로()
    {
        // 봇 4명 판을 같은 시드로: 한 번도 안 켠 판 / 켰다가 끈 판 → 틱마다 스냅샷·이벤트·로그·rng 횟수가 같음
        (Game g, List<string> lines, CountedRng r) Bots(Action<Game> opt)
        {
            var lines = new List<string>();
            var g = new Game(lines.Add, characters: true);
            var r = new CountedRng(5);
            g.rng = r.Next;
            opt(g);
            for (int i = 0; i < 4; i++) g.AddBot();
            Assert.True(g.StartRound());
            return (g, lines, r);
        }
        var a = Bots(_ => { });
        var b = Bots(g =>
        {
            Assert.True(g.SetRoundEvents(true));
            Assert.True(g.SetRoundEvents(false));
        });
        var on = Bots(g => Assert.True(g.SetRoundEvents(true)));
        Assert.Equal(a.r.calls, b.r.calls);
        bool sawEvent = false;
        for (int t = 0; t < 60 * C.TICK_RATE; t++)
        {
            a.g.Tick(TICK);
            b.g.Tick(TICK);
            on.g.Tick(TICK);
            string sa = a.g.Snapshot(true), sb = b.g.Snapshot(true);
            Assert.True(sa == sb, $"틱 {t}: 끈 판의 스냅샷이 다름");
            Assert.Equal(a.g.DrainEvents(), b.g.DrainEvents());
            Assert.True(a.r.calls == b.r.calls, $"틱 {t}: rng 횟수 {a.r.calls} / {b.r.calls}");
            Assert.DoesNotContain("roundEvent", sa);
            Assert.Contains("\"itemsEnabled\":false", sa);
            if (on.g.phase == "playing")
            {
                string so = on.g.Snapshot();
                Assert.Contains("\"roundEvents\":true", so);
                Assert.Contains("\"itemsEnabled\":true", so);
                sawEvent |= so.Contains("\"roundEvent\":{");
            }
        }
        // 켰다 끈 판은 [호스트] 줄 두 개만 더 있음
        Assert.Equal(a.lines, b.lines.Where(l => !l.StartsWith("[호스트] 돌발 이벤트")).ToList());
        Assert.Equal(2, b.lines.Count(l => l.StartsWith("[호스트] 돌발 이벤트")));
        Assert.DoesNotContain(a.lines, l => l.Contains("[이벤트]"));
        Assert.Contains(on.lines, l => l.Contains("[이벤트]"));

        // 가만히 선 사람 둘 (블록 없음): 끄면 EVENT_FIRST_MS 를 지나도 rng 를 한 번도 안 부름, 켜면 그때 부름
        foreach (bool events in new[] { false, true })
        {
            var (g, lines, r) = Humans(events: events);
            g.nextSpawnAt = double.PositiveInfinity;
            int before = r.calls;
            Run(g, C.EVENT_FIRST_MS + 1000);
            Assert.Equal("playing", g.phase);
            if (events) Assert.True(r.calls > before);
            else Assert.Equal(before, r.calls);
            Assert.Equal(events ? 1 : 0, lines.Count(l => l.Contains("[이벤트]")));
            Assert.Equal(events ? 1 : 0, EventsOf(g, "roundEvent").Count);
        }
    }

    [Fact]
    public void 폭우_동안_자동_블록이_상한보다_많음_하늘계단_켬끔()
    {
        double want = Math.Ceiling(C.EVENT_RAIN_MS / C.EVENT_RAIN_GAP_MS); // 폭우 한 번에 떨어지는 블록 수
        foreach (bool sky in new[] { false, true })
        {
            var (g, lines, _) = Humans(sky: sky);
            Assert.Equal(sky, g.sky);
            Run(g, 5000); // 보통 자동 블록·하늘 블록이 먼저 차 있게
            Assert.True(AutoCount(g) <= g.TargetConcurrent());
            if (sky) Assert.Equal(0, AutoCount(g)); // 하늘 계단 판엔 원래 보통 자동 블록이 없음
            double landed0 = g.landed["auto"];
            int autos0 = AutoCount(g);
            g.DrainEvents();
            g.StartRoundEvent("rain");
            var ev = Assert.Single(EventsOf(g, "roundEvent"));
            Assert.Equal("rain", ev.GetProperty("kind").GetString());
            Assert.Equal(C.EVENT_RAIN_MS, ev.GetProperty("ms").GetDouble());
            Assert.Contains($"  [이벤트] 블록 폭우 {JsNumber.ToJs(C.EVENT_RAIN_MS / 1000)}초", lines);
            var seen = new HashSet<int>();
            int max = 0;
            bool snap = false;
            for (double t = 0; t < C.EVENT_RAIN_MS; t += TICK)
            {
                g.Tick(TICK);
                foreach (var pc in g.pieces) if (pc.controller == null && !pc.sky) seen.Add(pc.id);
                max = Math.Max(max, AutoCount(g));
                if (!snap && g.RoundEventActive())
                {
                    var re = J(g.Snapshot()).GetProperty("roundEvent");
                    Assert.Equal("rain", re.GetProperty("kind").GetString());
                    Assert.InRange(re.GetProperty("left").GetDouble(), 1, C.EVENT_RAIN_MS);
                    Assert.Equal(JsonValueKind.Null, re.GetProperty("dir").ValueKind);
                    snap = true;
                }
            }
            Assert.True(snap);
            Assert.True(max > g.TargetConcurrent(), $"하늘 계단 {sky}: 동시 자동 블록 {max} ≤ 상한 {g.TargetConcurrent()}");
            Assert.True(seen.Count - autos0 >= want - 1, $"하늘 계단 {sky}: 폭우 블록 {seen.Count - autos0}개 (기대 {want})");
            // 폭우가 끝나면 스냅샷에서 빠지고, 떨어지던 블록은 실제로 착지함 (하늘 계단 판에서도)
            Run(g, 2 * TICK);
            Assert.False(g.RoundEventActive());
            Assert.False(J(g.Snapshot()).TryGetProperty("roundEvent", out _));
            Run(g, C.PIECE_SPAWN_Z * C.AUTO_FALL_STEP_MS + 2000);
            Assert.Equal("playing", g.phase);
            Assert.True(g.landed["auto"] - landed0 >= want - 1, $"하늘 계단 {sky}: 착지한 자동 블록 {g.landed["auto"] - landed0}개 (기대 {want})");
        }
    }

    [Fact]
    public void 돌풍_방향으로_밀림_땅과_공중()
    {
        double S = C.EVENT_WIND_SPEED;
        foreach (var (dx, dy) in C.EVENT_WIND_DIRS)
        {
            var (g, lines, _) = Humans(n: 3);
            g.nextSpawnAt = double.PositiveInfinity;
            g.Tick(TICK); // 첫 틱이 새 판을 알아채고 지난 이벤트를 비움 → 그 뒤에 시작
            var (a, b, dead) = (g.players[1], g.players[2], g.players[3]);
            double cx = g.W / 2.0, cy = g.D / 2.0;
            CharKit.Place(a, cx, cy);
            CharKit.Place(b, cx, cy, z: 8);
            dead.alive = false; // 필드에 없는 사람은 안 밀림
            g.DrainEvents();
            g.StartRoundEvent("wind", new XY(dx, dy));
            var ev = Assert.Single(EventsOf(g, "roundEvent"));
            Assert.Equal("wind", ev.GetProperty("kind").GetString());
            Assert.Equal(C.EVENT_WIND_MS, ev.GetProperty("ms").GetDouble());
            Assert.Equal(dx, ev.GetProperty("dir").GetProperty("x").GetDouble());
            Assert.Equal(dy, ev.GetProperty("dir").GetProperty("y").GetDouble());
            string axis = dx != 0 ? (dx > 0 ? "+x" : "-x") : (dy > 0 ? "+y" : "-y");
            Assert.Contains($"  [이벤트] 돌풍 {axis} {JsNumber.ToJs(C.EVENT_WIND_MS / 1000)}초", lines);
            var re = J(g.Snapshot()).GetProperty("roundEvent");
            Assert.Equal("wind", re.GetProperty("kind").GetString());
            Assert.Equal(dx, re.GetProperty("dir").GetProperty("x").GetDouble());
            Assert.Equal(dy, re.GetProperty("dir").GetProperty("y").GetDouble());

            // 땅: 2초 동안 바람 쪽으로 약 S × 2 칸 (처음 잠깐 빨라지는 동안 빼고), 옆으로는 안 감
            double secs = Math.Min(2, C.EVENT_WIND_MS / 1000 - 0.5);
            double ax0 = a.x, ay0 = a.y;
            double bAt = 0, bPrev = 0, bSpeed = 0;
            for (double t = 0; t < secs * 1000; t += TICK)
            {
                // 공중: b 를 계속 띄워 둠 (높이만 되돌림) → 흐르는 빠르기가 땅과 같은 약 S
                b.z = 8;
                b.vz = 0;
                g.Tick(TICK);
                Assert.True(a.grounded);
                Assert.False(b.grounded);
                bAt = (b.x - cx) * dx + (b.y - cy) * dy;
                bSpeed = (bAt - bPrev) / (TICK / 1000);
                bPrev = bAt;
            }
            double along = (a.x - ax0) * dx + (a.y - ay0) * dy, side = (a.x - ax0) * dy + (a.y - ay0) * dx;
            Assert.InRange(along, 0.7 * S * secs, 1.1 * S * secs);
            Assert.Equal(0, side, 9);
            Assert.InRange(Math.Sqrt(a.kbx * a.kbx + a.kby * a.kby), 0.8 * S, 1.2 * S);
            // 공중은 감쇠가 느려 천천히 빨라짐: 바람 쪽으로 가고 있고 S 를 넘지 않음 (정상 빠르기는 아래에서)
            Assert.True(bAt > 0.3 * S * secs, $"공중 {axis}: {bAt}");
            Assert.InRange(bSpeed, 0.5 * S, 1.1 * S);
            Assert.Equal(0, dead.kbx);
            Assert.Equal(0, dead.kby);

            // 바람이 끝나면 더 안 밀림 (넉백 감쇠로 멈춤)
            Run(g, C.EVENT_WIND_MS - secs * 1000 + 1500);
            Assert.False(g.RoundEventActive());
            Assert.Equal(0, a.kbx);
            Assert.Equal(0, a.kby);
            double ax1 = a.x, ay1 = a.y;
            Run(g, 500);
            Assert.Equal(ax1, a.x);
            Assert.Equal(ay1, a.y);
        }

        // 정상 빠르기: 넉백 감쇠 (땅 6 · 공중 1.2) 가 달라도 둘 다 약 S — 틱마다 넣는 양 S·k·dt 와 감쇠 exp(-k·dt) 의 균형
        foreach (double k in new[] { C.KB_DAMPING_GROUND, C.KB_DAMPING_AIR })
        {
            double dt = TICK / 1000, kb = 0, moved = 0;
            for (int i = 0; i < 20 * C.TICK_RATE; i++)
            {
                kb *= Math.Exp(-k * dt); // IntegratePlayer: 줄이고 → 그 속도로 움직이고
                moved = kb;
                kb += S * k * dt; // UpdateRoundEvents: 틱 끝에 더함
            }
            Assert.InRange(moved, 0.85 * S, 1.05 * S);
        }
    }

    [Fact]
    public void 보급_아이템_N개()
    {
        var (g, lines, _) = Humans();
        g.nextSpawnAt = double.PositiveInfinity;
        Assert.Empty(g.items);
        g.DrainEvents();
        g.StartRoundEvent("supply");
        Assert.Equal(C.EVENT_SUPPLY_COUNT, g.items.Count);
        Assert.All(g.items, it => Assert.Contains(it.type, C.ITEM_POOL));
        Assert.Equal(g.items.Count, g.items.Select(it => (it.x, it.y)).Distinct().Count());
        var ev = Assert.Single(EventsOf(g, "roundEvent"));
        Assert.Equal("supply", ev.GetProperty("kind").GetString());
        Assert.False(ev.TryGetProperty("dir", out _));
        Assert.Contains($"  [이벤트] 보급 {JsNumber.ToJs(C.EVENT_SUPPLY_COUNT)}개", lines);
        Assert.False(g.RoundEventActive()); // 보급은 그 자리에서 끝남
        var s = J(g.Snapshot());
        Assert.True(s.GetProperty("itemsEnabled").GetBoolean());
        Assert.Equal(C.EVENT_SUPPLY_COUNT, s.GetProperty("items").GetArrayLength());
        Assert.False(s.TryGetProperty("roundEvent", out _));

        // 예전 줍기 그대로: 그 칸에 서면 먹고 '획득' 로그
        var it0 = g.items[0];
        var p = g.players[1];
        CharKit.Place(p, it0.x + 0.5, it0.y + 0.5, z: it0.z);
        g.Tick(TICK);
        Assert.Equal(C.EVENT_SUPPLY_COUNT - 1, g.items.Count);
        var pick = Assert.Single(EventsOf(g, "pickup"));
        Assert.Equal(1, pick.GetProperty("who").GetInt32());
        Assert.Equal(it0.type, pick.GetProperty("item").GetString());
        Assert.Contains(lines, l => l.Contains("[아이템]") && l.Contains("획득"));
    }

    [Fact]
    public void 마스터_연습에선_안_돎()
    {
        double ms = C.EVENT_FIRST_MS + C.EVENT_GAP_MS + 2000;
        void None(Game g, List<string> lines, CountedRng r, string what)
        {
            int n = 0;
            r.script.Clear();
            for (double t = 0; t < ms && g.phase == "playing"; t += TICK)
            {
                g.Tick(TICK);
                n += EventsOf(g, "roundEvent").Count;
                Assert.False(g.RoundEventActive());
            }
            Assert.True(n == 0, $"{what}: roundEvent {n}개");
            Assert.DoesNotContain(lines, l => l.Contains("[이벤트]"));
            Assert.DoesNotContain(g.items, it => C.ITEM_POOL.Contains(it.type));
        }

        // 블록 마스터: 옵션은 켜지지만 (대기실에서 모드를 나중에 바꿀 수 있음) 판에선 안 돎
        {
            var (g, lines, r) = Humans(n: 3, mode: "master");
            Assert.True(g.roundEvents);
            None(g, lines, r, "블록 마스터");
            Assert.True(g.time - g.roundStartTime > C.EVENT_FIRST_MS); // 첫 이벤트 시각을 지나도록 돌았음
            Assert.Contains("\"roundEvents\":true", g.Snapshot());
        }
        // 연습·튜토리얼: 옵션을 못 켬. 켜진 채 들어와도 안 돎
        foreach (bool tutorial in new[] { false, true })
        {
            var lines = new List<string>();
            var g = new Game(lines.Add, characters: true);
            var r = new CountedRng(3);
            g.rng = r.Next;
            g.AddPlayer(1);
            g.roundEvents = true;
            Assert.True(tutorial ? g.StartTutorial(1) : g.StartPractice());
            Assert.False(g.SetRoundEvents(false));
            Assert.True(g.roundEvents);
            None(g, lines, r, tutorial ? "튜토리얼" : "연습");
            Assert.Equal("playing", g.phase);
        }
        // 생존·킬 점수전에선 같은 시간에 두 번 (EVENT_FIRST_MS, + EVENT_GAP_MS)
        foreach (string? mode in new[] { null, "kills" })
        {
            var (g, lines, _) = Humans(n: 3, mode: mode);
            g.nextSpawnAt = double.PositiveInfinity;
            Run(g, ms);
            Assert.Equal("playing", g.phase);
            Assert.Equal(2, lines.Count(l => l.Contains("[이벤트]")));
        }
    }

    [Fact]
    public void 마스터에선_아이템_칸을_안_띄움()
    {
        // itemsEnabled = 이벤트가 실제로 도는 판만 (RoundEventsRun). 대기실 스냅샷도 같은 값 (아이템 키 안내)
        foreach (var (mode, events, want) in new[] { ("survival", true, true), ("kills", true, true), ("master", true, false), ("master", false, false), ("survival", false, false) })
        {
            var g = new Game(null, characters: true);
            for (int i = 0; i < 3; i++) g.AddPlayer(i + 1);
            Assert.True(mode == "survival" || g.SetMode(mode));
            Assert.Equal(events, g.SetRoundEvents(events));
            Assert.Equal(want, g.RoundEventsRun());
            Assert.Equal(want, J(g.Snapshot()).GetProperty("itemsEnabled").GetBoolean()); // 대기실
            Assert.True(g.StartRound());
            g.Tick(TICK);
            var s = J(g.Snapshot());
            Assert.Equal(want, s.GetProperty("itemsEnabled").GetBoolean()); // 판 중
            Assert.Equal(events, s.TryGetProperty("roundEvents", out _)); // 옵션 표시는 그대로 (마스터도)
        }
        // 대기실에서 모드를 바꾸면 따라 바뀜
        var lobby = new Game(null, characters: true);
        for (int i = 0; i < 3; i++) lobby.AddPlayer(i + 1);
        Assert.True(lobby.SetRoundEvents(true));
        Assert.True(J(lobby.Snapshot()).GetProperty("itemsEnabled").GetBoolean());
        Assert.True(lobby.SetMode("master"));
        Assert.False(J(lobby.Snapshot()).GetProperty("itemsEnabled").GetBoolean());
        Assert.True(lobby.SetMode("kills"));
        Assert.True(J(lobby.Snapshot()).GetProperty("itemsEnabled").GetBoolean());
    }

    [Fact]
    public void 히트스톱_중엔_돌풍이_안_쌓임()
    {
        // 가장 긴 멈춤 (치명 × 카운터) 동안 넉백 감쇠가 안 돌아 바람이 쌓이면 풀릴 때 한꺼번에 밀림 → 멈춘 동안은 안 더함
        double S = C.EVENT_WIND_SPEED, stop = C.HITSTOP_MS * C.CRIT_HITSTOP_MULT * C.COUNTER_HITSTOP_MULT;
        foreach (var (dx, dy) in C.EVENT_WIND_DIRS)
        {
            var (g, _, _) = Humans(n: 2);
            g.nextSpawnAt = double.PositiveInfinity;
            g.Tick(TICK);
            var (a, b) = (g.players[1], g.players[2]);
            double cx = g.W / 2.0, cy = g.D / 2.0;
            CharKit.Place(a, cx - 2 * dy, cy - 2 * dx); // 바람 옆으로 2칸씩 떨어져 나란히
            CharKit.Place(b, cx + 2 * dy, cy + 2 * dx);
            double ax0 = a.x, ay0 = a.y, bx0 = b.x, by0 = b.y;
            g.StartRoundEvent("wind", new XY(dx, dy));
            a.freezeUntil = g.time + stop;
            double maxKb = 0;
            for (double t = 0; t < stop + 1000; t += TICK)
            {
                bool frozen = g.time + TICK < a.freezeUntil; // 이 틱의 IntegratePlayer·돌풍이 보는 값 (Tick 이 시각을 먼저 올림)
                g.Tick(TICK);
                if (frozen)
                {
                    Assert.Equal(0, a.kbx);
                    Assert.Equal(0, a.kby);
                    Assert.Equal(ax0, a.x);
                    Assert.Equal(ay0, a.y);
                }
                maxKb = Math.Max(maxKb, Math.Sqrt(a.kbx * a.kbx + a.kby * a.kby));
            }
            // 풀린 뒤에도 정상 빠르기 (약 S) 를 안 넘고, 안 멈춘 사람보다 덜 감
            Assert.InRange(maxKb, 0.8 * S, 1.2 * S);
            double along = (a.x - ax0) * dx + (a.y - ay0) * dy, free = (b.x - bx0) * dx + (b.y - by0) * dy;
            Assert.True(along > 0 && along < free, $"돌풍 ({dx}, {dy}): 멈췄던 사람 {along}칸 / 안 멈춘 사람 {free}칸");
        }
    }

    [Fact]
    public void 저중력_동안_점프_꼭짓점이_높음()
    {
        // 같은 판에서 평소 → 저중력. 꼭짓점 비는 연속식 1/G (2.22) 가 아니라 30Hz 틱 적분이라 약 2.34
        var (g, _, _, a) = Solo();
        double cx = g.W / 2.0, cy = g.D / 2.0;
        // 맞고 뜬 사람: 위로 vz·옆으로 kbx 를 직접 넣고 땅에 닿을 때까지 간 x 거리
        double Fly()
        {
            CharKit.Place(a, cx - 2, cy);
            a.vz = 6;
            a.kbx = 4;
            a.grounded = false;
            double x0 = a.x;
            for (int i = 0; i < 10 * C.TICK_RATE && !a.grounded; i++) g.Tick(TICK);
            Assert.True(a.grounded);
            return a.x - x0;
        }
        Assert.Equal(1, g.GravityMult());
        double normal = JumpApex(a, () => g.Tick(TICK));
        double normalFly = Fly();
        g.StartRoundEvent("lowgrav");
        Assert.Equal(C.EVENT_LOWGRAV_G, g.GravityMult());
        Assert.Equal(1, g.GroundDampMult());
        CharKit.Place(a, cx, cy);
        double low = JumpApex(a, () => g.Tick(TICK));
        double lowFly = Fly();
        Assert.True(g.RoundEventActive()); // 내내 저중력 안
        Assert.InRange(low / normal, 2.1, 2.5);
        Assert.True(lowFly > 1.3 * normalFly, $"맞고 뜬 거리 저중력 {lowFly} / 평소 {normalFly}");
    }

    [Fact]
    public void 빙판_동안_땅_넉백이_2배_넘게_미끄러짐()
    {
        var (g, _, _, a) = Solo();
        double cx = g.W / 2.0, cy = g.D / 2.0;
        var b = g.players[2];
        Assert.Equal(1, g.GroundDampMult());
        CharKit.Place(a, cx - 2, cy);
        double normal = Slide(a, () => g.Tick(TICK));
        g.StartRoundEvent("ice");
        Assert.Equal(C.EVENT_ICE_DAMP, g.GroundDampMult());
        Assert.Equal(1, g.GravityMult());
        CharKit.Place(a, cx - 2, cy);
        double ice = Slide(a, () => g.Tick(TICK));
        Assert.True(normal > 0);
        Assert.True(ice >= 2 * normal, $"미끄러진 거리 빙판 {ice} / 평소 {normal}");
        // 공중 넉백 감쇠는 그대로 (빙판은 땅에 섰을 때만)
        Assert.True(g.RoundEventActive());
        CharKit.Place(b, 1.5, 1.5, z: 8);
        b.grounded = false;
        b.kbx = 3;
        g.Tick(TICK);
        Assert.False(b.grounded);
        Assert.Equal(3 * Math.Exp(-C.KB_DAMPING_AIR * TICK / 1000), b.kbx, 9);
    }

    [Fact]
    public void 판이_끝나면_중력_감쇠가_원래대로()
    {
        // UpdateRoundEvents 는 판이 끝난 틱에 바로 돌아가 evKind 가 결과 화면·다음 판 첫 틱까지 남음 → 배율은 RoundEventActive 로 거름.
        // 결과 화면엔 Tick 이 물리를 안 돌려 IntegratePlayer 를 직접 부름 (틱과 같은 dt)
        (double apex, double slide) Measure(Game g, Action step)
        {
            var a = g.players[1];
            CharKit.Place(g.players[2], 1.5, 1.5);
            CharKit.Place(a, g.W / 2.0, g.D / 2.0);
            double apex = JumpApex(a, step);
            CharKit.Place(a, g.W / 2.0 - 2, g.D / 2.0);
            return (apex, Slide(a, step));
        }
        var (g0, _, _, _) = Solo();
        var normal = Measure(g0, () => g0.Tick(TICK)); // 평소: 이벤트 없는 판 중
        foreach (string kind in new[] { "lowgrav", "ice" })
        {
            var (g, _, _, _) = Solo();
            g.StartRoundEvent(kind);
            g.Tick(TICK);
            Assert.True(g.RoundEventActive());
            Assert.NotEqual(1, kind == "lowgrav" ? g.GravityMult() : g.GroundDampMult());
            g.EndRound(null);
            Assert.Equal("over", g.phase);
            Assert.True(g.evKind == kind && g.time < g.evEndsAt); // 지난 이벤트가 아직 남아 있지만
            Assert.False(g.RoundEventActive());
            Assert.Equal(1, g.GravityMult());
            Assert.Equal(1, g.GroundDampMult());
            var over = Measure(g, () => g.IntegratePlayer(g.players[1], TICK / 1000));
            Assert.Equal(normal.apex, over.apex, 9);
            Assert.Equal(normal.slide, over.slide, 9);
            // 다음 판 첫 틱 전 (카운트다운 0 → 바로 playing): 첫 틱에선 물리가 UpdateRoundEvents (지난 것 비우기) 보다 먼저 돎
            Assert.True(g.StartRound());
            Assert.Equal("playing", g.phase);
            Assert.True(g.evKind == kind && g.time < g.evEndsAt);
            Assert.Equal(1, g.GravityMult());
            Assert.Equal(1, g.GroundDampMult());
            foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
            g.nextSpawnAt = double.PositiveInfinity;
            var next = Measure(g, () => g.Tick(TICK));
            Assert.Null(g.evKind);
            Assert.Equal(normal.apex, next.apex, 9);
            Assert.Equal(normal.slide, next.slide, 9);
        }
    }

    [Fact]
    public void 새_종류_이벤트_로그_스냅샷()
    {
        foreach (var (kind, name, ms) in new[] { ("lowgrav", "저중력", C.EVENT_LOWGRAV_MS), ("ice", "빙판", C.EVENT_ICE_MS) })
        {
            var (g, lines, r, _) = Solo();
            g.DrainEvents();
            int calls = r.calls;
            g.StartRoundEvent(kind);
            Assert.Equal(calls, r.calls); // rng 안 씀
            var ev = Assert.Single(EventsOf(g, "roundEvent"));
            Assert.Equal(kind, ev.GetProperty("kind").GetString());
            Assert.Equal(ms, ev.GetProperty("ms").GetDouble());
            Assert.False(ev.TryGetProperty("dir", out _));
            Assert.Contains($"  [이벤트] {name} 6초", lines);
            Assert.True(g.RoundEventActive());
            Assert.Equal(kind, g.evKind);
            var re = J(g.Snapshot()).GetProperty("roundEvent");
            Assert.Equal(kind, re.GetProperty("kind").GetString());
            Assert.InRange(re.GetProperty("left").GetDouble(), 1, ms);
            Assert.Equal(JsonValueKind.Null, re.GetProperty("dir").ValueKind);
            // 끝나면 스냅샷에서 빠지고 배율도 1
            Run(g, ms + 2 * TICK);
            Assert.Equal("playing", g.phase);
            Assert.False(g.RoundEventActive());
            Assert.False(J(g.Snapshot()).TryGetProperty("roundEvent", out _));
            Assert.Equal(1, g.GravityMult());
            Assert.Equal(1, g.GroundDampMult());
        }
    }

    [Fact]
    public void 새_판_첫_틱_전_스냅샷에_지난_판_이벤트가_없음()
    {
        // 카운트다운 0: StartRound 가 바로 playing → 첫 틱 전 스냅샷. 순서 주의: 첫 틱이 새 판을 알아챈 뒤에 이벤트를 시작해야 재현됨
        var (g, _, _) = Humans();
        g.nextSpawnAt = double.PositiveInfinity;
        g.Tick(TICK);
        g.StartRoundEvent("rain");
        g.Tick(TICK);
        Assert.True(g.RoundEventActive());
        Assert.Equal("rain", J(g.Snapshot()).GetProperty("roundEvent").GetProperty("kind").GetString());
        g.EndRound(null);
        Assert.False(g.RoundEventActive()); // 판이 끝남
        Assert.True(g.StartRound());
        Assert.Equal("playing", g.phase);
        Assert.True(g.evKind == "rain" && g.time < g.evEndsAt); // 지난 판 것이 아직 남아 있지만 (틱이 비움)
        Assert.False(g.RoundEventActive());
        var s = J(g.Snapshot());
        Assert.True(s.GetProperty("roundEvents").GetBoolean());
        Assert.False(s.TryGetProperty("roundEvent", out _));
        g.Tick(TICK);
        Assert.Null(g.evKind);
        Assert.False(J(g.Snapshot()).TryGetProperty("roundEvent", out _));
        // 새 판에서 시작한 이벤트는 다시 실림
        g.StartRoundEvent("wind", new XY(0, 1));
        Assert.Equal("wind", J(g.Snapshot()).GetProperty("roundEvent").GetProperty("kind").GetString());
    }

    [Fact]
    public void 같은_시드면_같은_이벤트_순서()
    {
        // 봇 4명 킬 점수전 (판이 길어 이벤트가 여러 번): 로그 전체와 이벤트 시각·종류가 같은 시드면 같음
        (List<string> lines, List<(double t, string kind, string? dir)> evs) Play(uint seed)
        {
            var lines = new List<string>();
            var g = new Game(lines.Add, characters: true);
            g.rng = new Mulberry32(seed).AsFunc();
            Assert.True(g.SetMode("kills"));
            Assert.True(g.SetRoundEvents(true));
            for (int i = 0; i < 4; i++) g.AddBot();
            Assert.True(g.StartRound());
            var evs = new List<(double, string, string?)>();
            while (g.phase == "playing" && g.time < C.KILLS_TIME_MS + 5000)
            {
                g.Tick(TICK);
                foreach (var e in EventsOf(g, "roundEvent"))
                    evs.Add((g.time - g.roundStartTime, e.GetProperty("kind").GetString()!, e.TryGetProperty("dir", out var d) ? d.GetRawText() : null));
            }
            return (lines, evs);
        }
        var a = Play(21);
        var b = Play(21);
        Assert.Equal(a.lines, b.lines);
        Assert.Equal(a.evs, b.evs);
        Assert.True(a.evs.Count >= 2, $"이벤트 {a.evs.Count}개");
        Assert.Equal(a.evs.Count, a.lines.Count(l => l.Contains("[이벤트]")));
        // 시각: 판 시작 + EVENT_FIRST_MS, 그 뒤 EVENT_GAP_MS 마다 (틱 하나 안쪽)
        for (int i = 0; i < a.evs.Count; i++)
        {
            double want = C.EVENT_FIRST_MS + i * C.EVENT_GAP_MS;
            Assert.InRange(a.evs[i].t, want - 1e-6, want + TICK);
            Assert.Contains(a.evs[i].kind, C.EVENT_KINDS);
            Assert.Equal(a.evs[i].kind == "wind", a.evs[i].dir != null);
        }
        // 종류·방향은 rng 값에서: floor(rng × 종류 수), 돌풍이면 한 번 더 floor(rng × 4)
        for (int k = 0; k < C.EVENT_KINDS.Length; k++)
        {
            for (int d = 0; d < C.EVENT_WIND_DIRS.Length; d++)
            {
                var (g, lines, r) = Humans();
                g.nextSpawnAt = double.PositiveInfinity;
                Run(g, C.EVENT_FIRST_MS - 2 * TICK);
                g.DrainEvents();
                r.script.Enqueue((k + 0.5) / C.EVENT_KINDS.Length);
                r.script.Enqueue((d + 0.5) / C.EVENT_WIND_DIRS.Length); // 돌풍이 아니면 다음 rng (블록·아이템 자리) 가 가져감
                Run(g, 4 * TICK);
                var ev = Assert.Single(EventsOf(g, "roundEvent"));
                Assert.Equal(C.EVENT_KINDS[k], ev.GetProperty("kind").GetString());
                if (C.EVENT_KINDS[k] == "wind")
                {
                    Assert.Equal(C.EVENT_WIND_DIRS[d].x, ev.GetProperty("dir").GetProperty("x").GetDouble());
                    Assert.Equal(C.EVENT_WIND_DIRS[d].y, ev.GetProperty("dir").GetProperty("y").GetDouble());
                }
            }
        }
    }

    [Fact]
    public void 판_중엔_옵션_못_바꿈()
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.AddPlayer(1);
        g.AddPlayer(2);
        Assert.False(g.roundEvents); // 기본 끔
        Assert.False(g.SetRoundEvents(false)); // 같은 값
        Assert.True(g.SetRoundEvents(true));
        Assert.False(g.SetRoundEvents(true));
        Assert.Contains("[호스트] 돌발 이벤트 켬", lines);
        Assert.True(g.StartRound());
        Assert.False(g.SetRoundEvents(false)); // 판 중
        Assert.True(g.roundEvents);
        g.EndRound(null);
        Assert.True(g.SetRoundEvents(false)); // 판 사이
        Assert.Contains("[호스트] 돌발 이벤트 끔", lines);
        var pr = new Game();
        pr.AddPlayer(1);
        Assert.True(pr.StartPractice());
        Assert.False(pr.SetRoundEvents(true)); // 연습 방
        Assert.False(pr.roundEvents);
    }

    [Fact]
    public void 방_메시지는_방장만_방_정보와_공개_목록엔_켰을_때만()
    {
        var rooms = new Rooms(rng: new Mulberry32(1).AsFunc());
        var hostWs = new Sock();
        var host = rooms.Connect(hostWs);
        rooms.Message(host, J("{\"type\":\"create\",\"nick\":\"방장\"}"));
        rooms.Message(host, J("{\"type\":\"setPublic\",\"on\":true}"));
        var game = host.room!.game;
        var guest = rooms.Connect(new Sock());
        rooms.Message(guest, J($"{{\"type\":\"join\",\"code\":\"{host.room.code}\"}}"));
        Assert.Same(host.room, guest.room);

        string List()
        {
            var ws = new Sock();
            rooms.Connect(ws); // 방 밖에 들어오면 공개 목록을 받음
            return ws.msgs.Last(m => m.StartsWith("{\"type\":\"rooms\""));
        }
        string Info(Sock ws)
        {
            ws.msgs.Clear();
            rooms.Broadcast();
            return J(ws.msgs.Last(m => m.StartsWith("{\"type\":\"state\""))).GetProperty("room").GetRawText();
        }
        Assert.DoesNotContain("roundEvents", List());
        Assert.DoesNotContain("roundEvents", Info(hostWs));

        rooms.Message(guest, J("{\"type\":\"roundEvents\",\"on\":true}")); // 방장이 아니면 무시
        Assert.False(game.roundEvents);
        rooms.Message(host, J("{\"type\":\"roundEvents\",\"on\":true}"));
        Assert.True(game.roundEvents);
        Assert.Contains("\"roundEvents\":true", List());
        Assert.Contains("\"roundEvents\":true", Info(hostWs));
        Assert.Contains("\"roundEvents\":true", game.Snapshot());

        rooms.Message(host, J("{\"type\":\"roundEvents\",\"on\":false}"));
        Assert.False(game.roundEvents);
        Assert.DoesNotContain("roundEvents", List());
        Assert.DoesNotContain("roundEvents", Info(hostWs));
        Assert.DoesNotContain("roundEvents", game.Snapshot());
    }
}
