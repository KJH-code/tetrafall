using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;
using Tetrafall.Sim;

namespace Tetrafall.Tests;

// 필드 아이템 (고도 판 전용 방 옵션 fieldItems, Game.Items.cs): 끄면 예전 판 그대로 (rng 도 안 부름),
// 켜면 판마다 ITEM_POOL 6종이 필드에 나옴 (첫 ITEM_FIRST_SPAWN_MS, 다음까지 ITEM_RESPAWN_MS, 동시에 ItemMax() 개 — 블록 마스터 판에도)
public class FieldItemTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    sealed class Sock : ISocket
    {
        public readonly List<string> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(text);
    }

    // rng 를 감싸 부른 횟수를 셈
    sealed class CountedRng
    {
        public int calls;
        readonly Func<double> inner;
        public CountedRng(uint seed) => inner = new Mulberry32(seed).AsFunc();
        public double Next()
        {
            calls++;
            return inner();
        }
    }

    // 사람 n명 (가만히 서 있음), 평지. 블록에 안 깔리게 무적 (판이 테스트 도중에 끝나지 않게)
    static (Game g, List<string> lines, CountedRng rng) Humans(int n = 2, string? mode = null, bool items = true, uint seed = 11)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        var r = new CountedRng(seed);
        g.rng = r.Next;
        for (int i = 0; i < n; i++) g.AddPlayer(i + 1);
        Assert.True(g.SetMap("flat"));
        if (mode != null) Assert.True(g.SetMode(mode));
        if (items) Assert.True(g.SetFieldItems(true));
        Assert.True(g.StartRound());
        while (g.phase != "playing") g.Tick(TICK);
        foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
        return (g, lines, r);
    }

    static List<Item> Pool(Game g) => g.items.Where(it => C.ITEM_POOL.Contains(it.type)).ToList();

    // 봇 n명 판 (시드 고정). opt: 판 시작 전 설정
    static (Game g, List<string> lines, CountedRng r) Bots(int n, uint seed, Action<Game> opt)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true, skyStairs: true);
        var r = new CountedRng(seed);
        g.rng = r.Next;
        opt(g);
        for (int i = 0; i < n; i++) g.AddBot();
        Assert.True(g.StartRound());
        return (g, lines, r);
    }

    [Fact]
    public void Off_matches_plain_game_tick_by_tick()
    {
        // 봇 4명 판을 같은 시드로: 옵션을 안 만진 판 / SetFieldItems(false) 한 판 / 켰다가 끈 판 → 틱마다 스냅샷·이벤트·rng 횟수가 같음
        var a = Bots(4, 5, _ => { });
        var b = Bots(4, 5, g => Assert.False(g.SetFieldItems(false))); // 같은 값 = 아무 일도 없음
        var c = Bots(4, 5, g =>
        {
            Assert.True(g.SetFieldItems(true));
            Assert.True(g.SetFieldItems(false));
        });
        Assert.Equal(a.r.calls, b.r.calls);
        Assert.Equal(a.r.calls, c.r.calls);
        for (int t = 0; t < 600; t++)
        {
            a.g.Tick(TICK);
            b.g.Tick(TICK);
            c.g.Tick(TICK);
            string sa = a.g.Snapshot(true), sb = b.g.Snapshot(true), sc = c.g.Snapshot(true);
            Assert.True(sa == sb, $"틱 {t}: SetFieldItems(false) 한 판의 스냅샷이 다름");
            Assert.True(sa == sc, $"틱 {t}: 켰다 끈 판의 스냅샷이 다름");
            var ea = a.g.DrainEvents();
            Assert.Equal(ea, b.g.DrainEvents());
            Assert.Equal(ea, c.g.DrainEvents());
            Assert.True(a.r.calls == b.r.calls && a.r.calls == c.r.calls, $"틱 {t}: rng 횟수 {a.r.calls} / {b.r.calls} / {c.r.calls}");
            Assert.DoesNotContain("fieldItems", sa);
            Assert.Contains("\"itemsEnabled\":false", sa);
            Assert.Contains("\"power\":null", sa);
            Assert.Empty(a.g.items);
        }
        Assert.Equal(a.lines, b.lines);
        // 켰다 끈 판은 [호스트] 줄 두 개만 더 있음
        Assert.Equal(a.lines, c.lines.Where(l => !l.StartsWith("[호스트] 필드 아이템")).ToList());
        Assert.Equal(new[] { "[호스트] 필드 아이템 켬", "[호스트] 필드 아이템 끔" }, c.lines.Where(l => l.StartsWith("[호스트] 필드 아이템")).ToArray());
    }

    [Fact]
    public void On_first_item_at_ITEM_FIRST_SPAWN_MS()
    {
        Assert.Equal(4000, C.ITEM_FIRST_SPAWN_MS); // JS 값 그대로
        Assert.False(C.ITEMS_ENABLED); // 전역 스위치는 끈 채 (방 옵션으로만 켬)
        var (g, _, _) = Humans();
        double at = g.roundStartTime + C.ITEM_FIRST_SPAWN_MS;
        Assert.Equal(at, g.powerItemNextAt);
        while (g.time + TICK < at)
        {
            g.Tick(TICK);
            Assert.Empty(g.items);
            Assert.Equal(at - g.time, g.ItemTimers().power);
        }
        g.Tick(TICK); // 시각이 된 첫 틱
        Assert.True(g.time >= at && g.time - at < TICK);
        var it = Assert.Single(g.items);
        Assert.Contains(it.type, C.ITEM_POOL);
        Assert.Equal(g.ColumnTop(it.x, it.y), it.z);
        Assert.Equal(g.time + C.ITEM_RESPAWN_MS, g.powerItemNextAt);

        // 끈 판은 같은 시간에 아무것도 안 나옴
        var (off, _, _) = Humans(items: false);
        while (off.time < at + 1000) off.Tick(TICK);
        Assert.Empty(off.items);
    }

    [Fact]
    public void On_caps_at_ItemMax_and_waits_ITEM_RESPAWN_MS()
    {
        Assert.Equal(6000, C.ITEM_RESPAWN_MS);
        Assert.Equal(2, C.ITEM_MAX_ON_FIELD);
        var (g, lines, _) = Humans();
        Assert.Equal(2, g.ItemMax()); // 2명 = 10×10 = 면적비 1
        double first = g.roundStartTime + C.ITEM_FIRST_SPAWN_MS;
        var spawnedAt = new List<double>();
        int prev = 0;
        bool removed = false;
        while (g.time < first + 4 * C.ITEM_RESPAWN_MS)
        {
            g.Tick(TICK);
            int n = Pool(g).Count;
            Assert.True(n <= g.ItemMax(), $"{g.time}ms: 필드 아이템 {n}개 > {g.ItemMax()}");
            if (n > prev) spawnedAt.Add(g.time);
            if (n >= g.ItemMax())
            {
                Assert.Null(g.ItemTimers().power); // 꽉 차면 시계가 안 돎
                if (spawnedAt.Count == 2 && !removed)
                {
                    g.items.RemoveAt(0); // 둘째가 나오자마자 하나를 치움 → 셋째는 둘째 + ITEM_RESPAWN_MS 까지 기다림
                    removed = true;
                    n--;
                }
            }
            prev = n;
        }
        Assert.DoesNotContain(lines, l => l.Contains("[아이템]")); // 가만히 선 사람이 주운 판이면 아래 시각이 뜻이 없음
        Assert.Equal(3, spawnedAt.Count); // 4초·10초·16초, 그 뒤엔 꽉 참 (2개)
        Assert.True(spawnedAt[0] >= first && spawnedAt[0] - first < TICK);
        for (int i = 1; i < spawnedAt.Count; i++)
        {
            double gap = spawnedAt[i] - spawnedAt[i - 1];
            Assert.True(gap >= C.ITEM_RESPAWN_MS && gap < C.ITEM_RESPAWN_MS + TICK, $"{i}번째 간격 {gap}ms");
        }
        Assert.Equal(2, Pool(g).Count);

        // 8명 (19×19): 상한 round(2 × 3.61) = 7, 봇 판 내내 안 넘음
        var b = Bots(8, 7, x => Assert.True(x.SetFieldItems(true)));
        Assert.Equal(7, b.g.ItemMax());
        int most = 0;
        for (int t = 0; t < 90 * C.TICK_RATE && b.g.phase != "over"; t++)
        {
            b.g.Tick(TICK);
            int n = Pool(b.g).Count;
            most = Math.Max(most, n);
            Assert.True(n <= b.g.ItemMax(), $"틱 {t}: 필드 아이템 {n}개 > {b.g.ItemMax()}");
        }
        Assert.True(most >= 2, $"8명 판에 필드 아이템이 동시에 {most}개까지만");
        Assert.Contains(b.lines, l => l.Contains("[아이템]")); // 봇이 주움
    }

    [Fact]
    public void On_spawns_in_master_too()
    {
        var (g, lines, _) = Humans(n: 3, mode: "master");
        Assert.Equal("master", g.mode);
        Assert.True(g.FieldItemsRun());
        Assert.Contains("\"itemsEnabled\":true", g.Snapshot());
        double at = g.roundStartTime + C.ITEM_FIRST_SPAWN_MS;
        while (g.time < at) g.Tick(TICK);
        Assert.Single(Pool(g));
        while (g.time < at + C.ITEM_RESPAWN_MS + 2 * TICK) g.Tick(TICK); // 둘째는 첫째가 실제로 나온 틱 + ITEM_RESPAWN_MS (틱 격자·부동소수 여유 2틱)
        Assert.DoesNotContain(lines, l => l.Contains("[아이템]")); // 가만히 선 생존자가 주운 판이면 아래 수가 뜻이 없음
        Assert.Equal(2, Pool(g).Count);
        // 반격 아이템 (counter) 은 필드 아이템 상한과 따로 — 켜도 예전처럼 나옴
        while (g.time < g.roundStartTime + C.MASTER_COUNTER_FIRST_MS + TICK) g.Tick(TICK);
        Assert.Contains(g.items, it => it.type == "counter");

        // 끈 마스터 판: 아이템 키 안내도 없고 ITEM_POOL 도 안 나옴
        var (off, _, _) = Humans(n: 3, mode: "master", items: false);
        Assert.Contains("\"itemsEnabled\":false", off.Snapshot());
        while (off.time < at + C.ITEM_RESPAWN_MS) off.Tick(TICK);
        Assert.Empty(Pool(off));
    }

    [Fact]
    public void Master_counter_item_takes_no_field_item_slot()
    {
        // c10 리뷰 F6: 반격 아이템 (counter) 이 ItemMax() 한 자리를 차지해 필드 아이템이 1개에서 안 채워지고 시계가 null 이었음
        var (g, lines, _) = Humans(n: 3, mode: "master");
        Assert.Equal(2, g.ItemMax());
        double counterAt = g.roundStartTime + C.MASTER_COUNTER_FIRST_MS;
        while (g.time < counterAt + TICK) g.Tick(TICK);
        Assert.Contains(g.items, it => it.type == "counter");
        // 필드 아이템을 하나만 남김 → 반격 아이템이 있어도 자리가 비었으니 시계가 돌고 (null 아님) 상한까지 다시 채워짐
        var pool = Pool(g);
        Assert.NotEmpty(pool);
        foreach (var it in pool.Skip(1)) g.items.Remove(it);
        Assert.Single(Pool(g));
        Assert.Equal(1, g.PoolItemCount());
        g.powerItemNextAt = g.time + 500;
        Assert.Equal(500, g.ItemTimers().power);
        Assert.Contains("\"power\":500", g.Snapshot());
        while (g.time < g.powerItemNextAt + TICK) g.Tick(TICK);
        Assert.Contains(g.items, it => it.type == "counter");
        Assert.Equal(2, Pool(g).Count); // 반격 아이템 + 필드 아이템 ItemMax() 개
        Assert.Equal(3, g.items.Count);
        Assert.Null(g.ItemTimers().power); // 필드 아이템이 꽉 찼을 때만 시계가 멈춤
        Assert.DoesNotContain(lines, l => l.Contains("[아이템]"));

        // 반격 아이템을 주워도 다음 필드 아이템 시계는 그대로 (예전엔 ITEM_RESPAWN_MS 뒤로 밀림), 필드 아이템을 주우면 밀림
        g.items.Remove(Pool(g)[0]);
        g.powerItemNextAt = g.time + 500;
        var surv = g.Players().First(p => g.OnField(p));
        var counter = g.items.First(it => it.type == "counter");
        double next = g.powerItemNextAt;
        surv.x = counter.x + 0.5;
        surv.y = counter.y + 0.5;
        surv.z = g.ColumnTop(counter.x, counter.y);
        g.PickupItems();
        Assert.DoesNotContain(g.items, it => it.type == "counter");
        Assert.Equal(next, g.powerItemNextAt);
        var field = Pool(g)[0];
        var other = g.Players().First(p => g.OnField(p) && p != surv);
        other.x = field.x + 0.5;
        other.y = field.y + 0.5;
        other.z = g.ColumnTop(field.x, field.y);
        g.PickupItems();
        Assert.Empty(Pool(g));
        Assert.Equal(g.time + C.ITEM_RESPAWN_MS, g.powerItemNextAt);
    }

    [Fact]
    public void Round_start_log_line_every_round_only_when_items_run()
    {
        // c10 리뷰 F7: [호스트] 줄은 켤 때 한 번뿐 → 같은 방 2판째부터는 로그로 아이템 판인지 못 가렸음
        const string LINE = "  필드 아이템: 켬";
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.AddPlayer(1);
        g.AddPlayer(2);
        Assert.True(g.SetFieldItems(true));
        for (int round = 1; round <= 2; round++)
        {
            Assert.True(g.StartRound());
            while (g.phase != "playing") g.Tick(TICK);
            Assert.Equal(round, lines.Count(l => l == LINE));
            int start = lines.FindLastIndex(l => l.StartsWith("===== ROUND"));
            Assert.True(lines.IndexOf(LINE, start) > start); // 그 판 시작 줄 뒤에
            g.EndRound(null);
        }
        Assert.Equal(1, lines.Count(l => l == "[호스트] 필드 아이템 켬"));
        // 끄면 다음 판부터 없음
        Assert.True(g.SetFieldItems(false));
        Assert.True(g.StartRound());
        while (g.phase != "playing") g.Tick(TICK);
        Assert.Equal(2, lines.Count(l => l == LINE));

        // 끈 판·블록 마스터 켠 판
        var (_, offLines, _) = Humans(items: false);
        Assert.DoesNotContain(LINE, offLines);
        var (_, masterLines, _) = Humans(n: 3, mode: "master");
        Assert.Contains(LINE, masterLines);

        // 연습·튜토리얼: 옵션이 켜진 채여도 아이템이 안 나오니 줄도 없음
        foreach (bool tutorial in new[] { false, true })
        {
            var pl = new List<string>();
            var pr = new Game(pl.Add, characters: true);
            pr.AddPlayer(1);
            pr.fieldItems = true;
            Assert.True(tutorial ? pr.StartTutorial(1) : pr.StartPractice());
            for (int t = 0; t < 3 * C.TICK_RATE; t++) pr.Tick(TICK);
            Assert.Equal("playing", pr.phase);
            Assert.DoesNotContain(LINE, pl);
        }
    }

    [Fact]
    public void Set_refused_in_round_practice_and_same_value()
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.AddPlayer(1);
        g.AddPlayer(2);
        Assert.False(g.fieldItems); // 기본 끔
        Assert.False(g.SetFieldItems(false)); // 같은 값
        Assert.DoesNotContain(lines, l => l.Contains("필드 아이템"));
        Assert.True(g.SetFieldItems(true));
        Assert.False(g.SetFieldItems(true));
        Assert.Equal(1, lines.Count(l => l == "[호스트] 필드 아이템 켬"));
        Assert.True(g.StartRound());
        Assert.False(g.SetFieldItems(false)); // 판 중 (카운트다운 포함)
        Assert.True(g.fieldItems);
        g.EndRound(null);
        Assert.True(g.SetFieldItems(false)); // 판 사이
        Assert.Equal(1, lines.Count(l => l == "[호스트] 필드 아이템 끔"));

        var cd = new Game(null, characters: true, countdownMs: 1500);
        cd.AddPlayer(1);
        cd.AddPlayer(2);
        Assert.True(cd.StartRound());
        Assert.Equal("countdown", cd.phase);
        Assert.False(cd.SetFieldItems(true)); // 카운트다운 중
        Assert.False(cd.fieldItems);

        var pr = new Game();
        pr.AddPlayer(1);
        Assert.True(pr.StartPractice());
        Assert.False(pr.SetFieldItems(true)); // 연습 방
        Assert.False(pr.fieldItems);
    }

    [Fact]
    public void Snapshot_fieldItems_only_when_on_and_itemsEnabled_true()
    {
        var g = new Game(null, characters: true);
        g.AddPlayer(1);
        g.AddPlayer(2);
        // 끔 (대기실): 키 없음, 아이템 키 안내도 없음
        var s = J(g.Snapshot());
        Assert.False(s.TryGetProperty("fieldItems", out _));
        Assert.False(s.GetProperty("itemsEnabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, s.GetProperty("itemTimers").GetProperty("power").ValueKind);
        // 켬 (대기실): fieldItems·itemsEnabled true, 시계는 판 중에만
        Assert.True(g.SetFieldItems(true));
        s = J(g.Snapshot());
        Assert.True(s.GetProperty("fieldItems").GetBoolean());
        Assert.True(s.GetProperty("itemsEnabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, s.GetProperty("itemTimers").GetProperty("power").ValueKind);
        // 판 중: 다음 아이템까지 남은 ms
        Assert.True(g.StartRound());
        while (g.phase != "playing") g.Tick(TICK);
        s = J(g.Snapshot());
        Assert.True(s.GetProperty("fieldItems").GetBoolean());
        Assert.True(s.GetProperty("itemsEnabled").GetBoolean());
        Assert.Equal(g.powerItemNextAt - g.time, s.GetProperty("itemTimers").GetProperty("power").GetDouble());
        // 나온 아이템은 스냅샷 items 에
        foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity;
        while (g.items.Count == 0) g.Tick(TICK);
        var it = Assert.Single(J(g.Snapshot()).GetProperty("items").EnumerateArray());
        Assert.Contains(it.GetProperty("type").GetString(), C.ITEM_POOL);
        // 다시 끄면 예전 글자 그대로
        g.EndRound(null);
        Assert.True(g.SetFieldItems(false));
        s = J(g.Snapshot());
        Assert.False(s.TryGetProperty("fieldItems", out _));
        Assert.False(s.GetProperty("itemsEnabled").GetBoolean());
    }

    [Fact]
    public void Practice_and_tutorial_never_spawn()
    {
        // 옵션이 켜진 채 들어와도 (필드를 직접 켬) 연습·튜토리얼은 안 나옴: 끈 쌍둥이와 틱마다 아이템·rng 횟수가 같음
        foreach (bool tutorial in new[] { false, true })
        {
            (Game g, CountedRng r) Make(bool on)
            {
                var g = new Game(null, characters: true);
                var r = new CountedRng(3);
                g.rng = r.Next;
                g.AddPlayer(1);
                g.fieldItems = on;
                Assert.True(tutorial ? g.StartTutorial(1) : g.StartPractice());
                return (g, r);
            }
            var a = Make(false);
            var b = Make(true);
            Assert.False(b.g.SetFieldItems(false)); // 연습 방에선 못 바꿈
            Assert.True(b.g.fieldItems);
            Assert.False(b.g.FieldItemsRun());
            string what = tutorial ? "튜토리얼" : "연습";
            for (int t = 0; t < 20 * C.TICK_RATE; t++)
            {
                a.g.Tick(TICK);
                b.g.Tick(TICK);
                Assert.True(a.r.calls == b.r.calls, $"{what} 틱 {t}: rng 횟수 {a.r.calls} / {b.r.calls}");
                Assert.Equal(a.g.items.Select(it => (it.type, it.x, it.y)), b.g.items.Select(it => (it.type, it.x, it.y)));
                Assert.Null(b.g.ItemTimers().power);
                // 스냅샷은 fieldItems 키 하나만 다름 (itemsEnabled 포함 나머지는 같음)
                Assert.Equal(a.g.Snapshot(true), b.g.Snapshot(true).Replace("\"fieldItems\":true,", ""));
            }
            Assert.Equal("playing", b.g.phase);
        }
    }

    [Fact]
    public void Room_message_host_only_and_listed_only_when_on()
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
        Assert.False(game.fieldItems); // 새 방은 끔
        Assert.DoesNotContain("fieldItems", List());
        Assert.DoesNotContain("fieldItems", Info(hostWs));

        rooms.Message(guest, J("{\"type\":\"fieldItems\",\"on\":true}")); // 방장이 아니면 무시
        Assert.False(game.fieldItems);
        rooms.Message(host, J("{\"type\":\"fieldItems\",\"on\":true}"));
        Assert.True(game.fieldItems);
        Assert.Contains("\"fieldItems\":true", List());
        Assert.Contains("\"fieldItems\":true", Info(hostWs));
        Assert.Contains("\"fieldItems\":true", game.Snapshot());

        rooms.Message(host, J("{\"type\":\"fieldItems\",\"on\":false}"));
        Assert.False(game.fieldItems);
        Assert.DoesNotContain("fieldItems", List());
        Assert.DoesNotContain("fieldItems", Info(hostWs));
        Assert.DoesNotContain("fieldItems", game.Snapshot());

        rooms.Message(host, J("{\"type\":\"fieldItems\"}")); // on 이 없으면 끔 = 같은 값 → 그대로
        Assert.False(game.fieldItems);
    }

    [Fact]
    public void Sim_items_flag_in_summary_only_when_on()
    {
        string[] common = { "--rounds", "2", "--players", "8", "--maps", "flat", "--workers", "1", "--no-log", "--no-mirror", "--balance", "on" };
        string Summary(SimOptions o, List<SimResult> rs) => BotSim.SummaryJson(null, o, BotSim.SummarizeSim(rs));

        var off = BotSim.ParseArgs(common);
        var offExplicit = BotSim.ParseArgs(common.Concat(new[] { "--items", "off" }).ToArray());
        var on = BotSim.ParseArgs(common.Concat(new[] { "--items", "on" }).ToArray());
        Assert.False(off.items);
        Assert.False(offExplicit.items);
        Assert.True(on.items);

        var offLog = new List<string>();
        var onLog = new List<string>();
        var offRes = BotSim.PlanJobs(off).Select(j => BotSim.RunJob(j, off, offLog.Add)).ToList();
        var offRes2 = BotSim.PlanJobs(offExplicit).Select(j => BotSim.RunJob(j, offExplicit)).ToList();
        var onRes = BotSim.PlanJobs(on).Select(j => BotSim.RunJob(j, on, onLog.Add)).ToList();

        string sOff = Summary(off, offRes), sOn = Summary(on, onRes);
        Assert.DoesNotContain("\"items\"", sOff);
        Assert.Equal(sOff, Summary(offExplicit, offRes2)); // --items off = 안 준 것과 글자까지 같음
        Assert.True(J(sOn).GetProperty("options").GetProperty("items").GetBoolean());

        // 끈 판 로그엔 아이템이 없고, 켠 판은 봇 8명이 끝까지 가며 (시간 초과 없음) 아이템을 주움
        Assert.DoesNotContain(offLog, l => l.Contains("필드 아이템") || l.Contains("[아이템]"));
        Assert.Equal(on.rounds, onLog.Count(l => l == "[호스트] 필드 아이템 켬"));
        Assert.Contains(onLog, l => l.Contains("[아이템]"));
        Assert.All(onRes, r => Assert.False(r.timeout));
    }
}
