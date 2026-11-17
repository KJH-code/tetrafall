using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Tests;

// 돌발 이벤트 '번개' (c9, Game.Events.cs · ConfigEvents.cs EVENT_BOLT_*): 차례마다 필드 위 사람 절반 (올림) 의 발밑에 예고 고리 →
// EVENT_BOLT_WARN_MS 뒤 그 자리에 떨어져 고리 안 사람을 바깥으로 날림. 경직·무적은 안 맞음, 킬은 그 전에 마지막으로 민 사람, 봇도 예고를 보고 비킴
public class EventBoltTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    static List<JsonElement> EventsOf(Game g, string type) => g.DrainEvents().Select(J).Where(e => e.GetProperty("type").GetString() == type).ToList();

    static List<int> Hits(JsonElement bolt) => bolt.GetProperty("hits").EnumerateArray().Select(h => h.GetInt32()).ToList();

    // 사람 n명 (가만히 서 있음), 평지, 블록·아이템 없음, 이벤트 켬. 카운트다운을 지나 판 중 첫 틱까지 돌림 (그 틱에 UpdateRoundEvents 가 새 판을 알아챔)
    static (Game g, List<string> lines) Humans(int n, string mode = "survival", bool hp = false, uint seed = 11)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.rng = new Mulberry32(seed).AsFunc();
        for (int i = 0; i < n; i++) g.AddPlayer(i + 1);
        if (mode != "survival") Assert.True(g.SetMode(mode));
        if (hp) Assert.True(g.SetHpMode(true));
        Assert.True(g.SetRoundEvents(true));
        Play(g);
        return (g, lines);
    }

    static void Play(Game g)
    {
        Assert.True(g.StartRound());
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        while (g.phase != "playing") g.Tick(TICK);
        for (int i = 0; i < 20; i++) g.Tick(TICK); // 시작 무적 (부활 무적) 은 테스트가 따로 풂
        foreach (var p in g.Players()) p.shieldUntil = 0;
        g.DrainEvents();
    }

    // 바닥 위 (x, y) 에 세움
    static void Put(Game g, Player p, double x, double y, double dz = 0)
    {
        p.x = x;
        p.y = y;
        p.z = g.ColumnTop((int)Math.Floor(x), (int)Math.Floor(y)) + dz;
        p.vz = p.kbx = p.kby = 0;
        p.grounded = dz == 0;
    }

    // (x, y) 에 예고를 넣고 그 자리에서 바로 떨어뜨림 (물리 없이 UpdateRoundEvents 만 → 자리가 틱에 안 흔들림). 돌려줌: bolt 이벤트.
    // 예고 높이는 따로 안 주면 서버와 같이 대상 발 높이 (Game.BoltWarnZ)
    static JsonElement Strike(Game g, double x, double y, int target, double? z = null)
    {
        g.DrainEvents();
        g.bolts.Add(new BoltWarn { id = 900 + g.bolts.Count, x = x, y = y, z = z ?? g.BoltWarnZ(g.GetPlayer(target)!), at = g.time, target = target });
        g.UpdateRoundEvents(TICK);
        Assert.Empty(g.bolts);
        return Assert.Single(EventsOf(g, "bolt"));
    }

    // (a) 차례 4번 (시작 순간부터 EVENT_BOLT_GAP_MS 마다), 차례마다 대상 수 = ceil(n × EVENT_BOLT_SHARE), 겹침 없음. 예고마다 EVENT_BOLT_WARN_MS 뒤에 떨어짐
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(5)]
    [InlineData(8)]
    public void 차례_4번_대상은_사람_수의_절반_올림(int n)
    {
        // 킬 점수전 (한 명만 남아도 판이 안 끝남). n = 1 은 두 명 중 하나를 죽여 둠 (부활 안 함)
        var (g, lines) = Humans(Math.Max(2, n), "kills");
        foreach (var p in g.Players()) p.shieldUntil = double.PositiveInfinity; // 맞아 밀려 떨어지면 n 이 달라짐 — 대상은 무적이어도 뽑힘
        if (n == 1)
        {
            var dead = g.Players().Last();
            dead.shieldUntil = 0;
            g.Kill(dead, "fall");
            dead.respawnAt = double.PositiveInfinity;
        }
        Assert.Equal(n, g.Players().Count(g.OnField));
        lines.Clear();
        g.DrainEvents();
        double t0 = g.time;
        g.StartRoundEvent("bolt");
        Assert.Equal("bolt", g.evKind);
        Assert.Equal(t0 + C.EVENT_BOLT_MS, g.evEndsAt);
        var start = Assert.Single(EventsOf(g, "roundEvent"));
        Assert.Equal("bolt", start.GetProperty("kind").GetString());
        Assert.Equal(C.EVENT_BOLT_MS, start.GetProperty("ms").GetDouble());
        Assert.Contains("  [이벤트] 번개 6초", lines);
        var warns = new List<(double t, JsonElement e)>();
        var strikes = new List<(double t, JsonElement e)>();
        while (g.time < t0 + C.EVENT_BOLT_MS + 1000)
        {
            g.Tick(TICK);
            foreach (var json in g.DrainEvents())
            {
                var e = J(json);
                string type = e.GetProperty("type").GetString()!;
                if (type == "boltWarn") warns.Add((g.time - t0, e));
                else if (type == "bolt") strikes.Add((g.time - t0, e));
            }
        }
        int k = (int)Math.Ceiling(n * C.EVENT_BOLT_SHARE);
        Assert.Equal(new[] { 1, 1, 3, 4 }[Array.IndexOf(new[] { 1, 2, 5, 8 }, n)], k);
        var volleys = warns.GroupBy(w => w.t).OrderBy(v => v.Key).ToList();
        Assert.Equal(4, volleys.Count);
        for (int i = 0; i < 4; i++)
        {
            Assert.InRange(volleys[i].Key, i * C.EVENT_BOLT_GAP_MS, i * C.EVENT_BOLT_GAP_MS + TICK + 1e-6); // 0 · 1.5 · 3.0 · 4.5초 (틱 하나 안쪽)
            Assert.Equal(k, volleys[i].Count());
            // 한 차례 안에서 같은 사람이 두 번 안 뽑힘 (가만히 서 있어 자리가 사람마다 다름)
            Assert.Equal(k, volleys[i].Select(w => (w.e.GetProperty("x").GetDouble(), w.e.GetProperty("y").GetDouble())).Distinct().Count());
            foreach (var w in volleys[i])
            {
                Assert.Equal(C.EVENT_BOLT_RADIUS, w.e.GetProperty("r").GetDouble());
                Assert.Equal(C.EVENT_BOLT_WARN_MS, w.e.GetProperty("ms").GetDouble());
            }
        }
        // id 는 판 안에서 1 부터 차례로, 예고마다 한 번씩 EVENT_BOLT_WARN_MS 뒤에 떨어짐 (같은 id·자리)
        Assert.Equal(Enumerable.Range(1, 4 * k), warns.Select(w => w.e.GetProperty("id").GetInt32()));
        Assert.Equal(warns.Count, strikes.Count);
        foreach (var w in warns)
        {
            var s = Assert.Single(strikes, s => s.e.GetProperty("id").GetInt32() == w.e.GetProperty("id").GetInt32());
            Assert.InRange(s.t - w.t, C.EVENT_BOLT_WARN_MS - 1e-6, C.EVENT_BOLT_WARN_MS + TICK + 1e-6);
            Assert.Equal(w.e.GetProperty("x").GetDouble(), s.e.GetProperty("x").GetDouble());
            Assert.Equal(w.e.GetProperty("z").GetDouble(), s.e.GetProperty("z").GetDouble());
            Assert.Empty(Hits(s.e)); // 다 무적
        }
        Assert.Null(g.evKind); // 끝남
        Assert.Empty(g.bolts);
        Assert.Equal(4 * k, lines.Count(l => l.StartsWith("  [번개] ") && l.Contains(" 예고 (")));
        Assert.Equal(4 * k, lines.Count(l => l.StartsWith("  [번개] ") && l.EndsWith(" 무적이라 무시"))); // 서 있던 자리 그대로 (고리 안) 인데 무적
    }

    // 판 밖 공중 (밀려 떨어지는 중) 인 사람은 뽑혀도 예고가 안 뜸
    [Fact]
    public void 판_밖_공중이면_예고_없음()
    {
        var (g, _) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        a.x = -0.8; // 판 밖 (아직 안 떨어짐)
        a.z = 2;
        a.shieldUntil = b.shieldUntil = double.PositiveInfinity;
        g.StartRoundEvent("bolt");
        g.DrainEvents();
        for (int i = 0; i < 3; i++) g.UpdateRoundEvents(TICK); // 첫 차례: 두 명 중 한 명 (ceil(2 × 0.5))
        var warns = EventsOf(g, "boltWarn");
        Assert.True(warns.Count <= 1);
        foreach (var w in warns) Assert.Equal(b.x, w.GetProperty("x").GetDouble());
        // 대상을 a 로 고정해도 (필드 위 사람이 a 뿐) 예고 없음
        g.Kill(b, "fall");
        b.respawnAt = double.PositiveInfinity;
        g.bolts.Clear();
        g.StartRoundEvent("bolt");
        g.DrainEvents();
        g.UpdateRoundEvents(TICK);
        Assert.Empty(EventsOf(g, "boltWarn"));
        Assert.Empty(g.bolts);
    }

    // (b) 맞는 범위: 수평 EVENT_BOLT_RADIUS (몸 가운데까지), 발 높이 차 EVENT_BOLT_HEIGHT. 맞으면 피해 %·경직·띄움·바깥쪽 넉백
    [Fact]
    public void 반경_높이_안에서만_맞음()
    {
        var (g, lines) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        Put(g, b, 1.5, 1.5); // 멀리
        // 수평 1.15 안 → 맞음 (대상이 아니어도 = '옆'), 바깥쪽 (+x) 으로 날아감
        Put(g, a, 5.5, 5.5);
        lines.Clear();
        var e = Strike(g, 5.5 - 1.15, 5.5, target: b.id);
        Assert.Equal(new[] { a.id }, Hits(e));
        Assert.Equal(C.EVENT_BOLT_RADIUS, e.GetProperty("r").GetDouble());
        Assert.Equal(C.EVENT_BOLT_DAMAGE, a.damage);
        Assert.Equal(g.time + C.EVENT_BOLT_STUN_MS, a.stunUntil);
        Assert.Equal(C.EVENT_BOLT_UP, a.vz);
        Assert.True(a.kbx > 0 && Math.Abs(a.kby) < 1e-9, $"넉백 ({a.kbx}, {a.kby})");
        Assert.Equal("tank", a.@char); // 사람 기본 캐릭터 (덜 밀림)
        Assert.Equal(C.EVENT_BOLT_KB * C.DAMAGE_KB_BASE * C.TANK_KB_TAKEN, a.kbx, 9); // 무거운 타 (콤보 배율 없음) × 피해 0% 배율 × 탱크
        Assert.Null(a.lastHit); // 번개는 킬 귀속을 안 건드림
        Assert.Equal(new[] { $"  [번개] {b.name} 피함", $"  [번개] 옆 {a.name} 맞음" }, lines.Where(l => l.StartsWith("  [번개]")));
        // 수평 1.25 → 안 맞음
        g.Tick(TICK);
        a.stunUntil = a.iframeUntil = 0;
        a.comboHits = 0;
        a.damage = 0;
        Put(g, a, 5.5, 5.5);
        lines.Clear();
        e = Strike(g, 5.5 - 1.25, 5.5, target: a.id);
        Assert.Empty(Hits(e));
        Assert.Equal(0, a.damage);
        Assert.Equal(new[] { $"  [번개] {a.name} 피함" }, lines.Where(l => l.StartsWith("  [번개]")));
        // 발 높이 차 2.9 → 맞음, 3.1 → 안 맞음 (예고 바닥보다 위·아래 둘 다)
        foreach (double dz in new[] { 2.9, -2.9 })
        {
            a.stunUntil = a.iframeUntil = 0;
            a.comboHits = 0;
            a.damage = 0;
            Put(g, a, 5.5, 5.5);
            int z = (int)a.z + 4;
            a.z = z + dz;
            Assert.Equal(new[] { a.id }, Hits(Strike(g, 5.5, 5.5, a.id, z)));
            Assert.Equal(C.EVENT_BOLT_DAMAGE, a.damage);
        }
        foreach (double dz in new[] { 3.1, -3.1 })
        {
            a.stunUntil = a.iframeUntil = 0;
            a.comboHits = 0;
            a.damage = 0;
            Put(g, a, 5.5, 5.5);
            int z = (int)a.z + 4;
            a.z = z + dz;
            Assert.Empty(Hits(Strike(g, 5.5, 5.5, a.id, z)));
            Assert.Equal(0, a.damage);
        }
    }

    // 예고 뒤로 안 움직인 사람 (한가운데): 방향이 없어 rng 각으로 날아감 (넉백 크기는 같음)
    [Fact]
    public void 한가운데면_무작위_방향()
    {
        var (g, lines) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        Put(g, a, 5.5, 5.5);
        lines.Clear();
        var e = Strike(g, 5.5, 5.5, a.id);
        Assert.Equal(new[] { a.id }, Hits(e));
        Assert.Equal(C.EVENT_BOLT_KB * C.DAMAGE_KB_BASE * C.TANK_KB_TAKEN, JsMath.Hypot(a.kbx, a.kby), 9);
        Assert.Equal(new[] { $"  [번개] {a.name} 맞음" }, lines.Where(l => l.StartsWith("  [번개]")));
    }

    // (b) 무적 (부활 무적·콤보 뒤 무적)·경직 중인 사람은 안 맞음. 경직 중인 사람의 콤보 타 수는 그대로 (번개가 남의 콤보를 이어 주지 않음)
    [Fact]
    public void 무적_경직_중은_안_맞음()
    {
        var (g, lines) = Humans(3, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        var c = g.GetPlayer(3)!;
        Put(g, c, 1.5, 1.5);
        // 무적
        Put(g, a, 5.5, 5.5);
        a.shieldUntil = g.time + 5000;
        lines.Clear();
        Assert.Empty(Hits(Strike(g, 5.2, 5.5, a.id)));
        Assert.Equal(0, a.damage);
        Assert.Equal(0, a.stunUntil);
        Assert.Contains($"  [번개] {a.name} 무적이라 무시", lines);
        a.shieldUntil = 0;
        a.iframeUntil = g.time + 500; // 콤보 뒤 무적
        Assert.Empty(Hits(Strike(g, 5.2, 5.5, a.id)));
        Assert.Equal(0, a.damage);
        a.iframeUntil = 0;
        // 경직 중: c 가 b 를 두 번 때려 콤보 2타째 — 그 경직 안에 번개가 떨어져도 타 수·피해 %·경직 끝 시각·마지막으로 민 사람 그대로
        Put(g, a, 8.5, 1.5); // a 는 멀리
        Put(g, b, 5.5, 5.5);
        Assert.True(g.ApplyKnockback(b, 1, 0, 0.5, 1, C.STUN_MS, 5, new Src(c.id, "push")));
        g.Tick(TICK);
        Assert.True(g.ApplyKnockback(b, 1, 0, 0.5, 1, C.STUN_MS, 5, new Src(c.id, "push")));
        Assert.Equal(2, b.comboHits);
        Assert.True(g.time < b.stunUntil);
        var (dmg, stun, vz) = (b.damage, b.stunUntil, b.vz);
        lines.Clear();
        Assert.Empty(Hits(Strike(g, b.x - 0.3, b.y, b.id)));
        Assert.Equal(2, b.comboHits);
        Assert.Equal(dmg, b.damage);
        Assert.Equal(stun, b.stunUntil);
        Assert.Equal(vz, b.vz);
        Assert.Equal(c.id, b.lastHit!.by);
        Assert.Contains($"  [번개] {b.name} 경직 중이라 무시", lines);
        // 경직이 막 풀린 순간: 콤보가 끝나며 붙는 무적 (COMBO_IFRAME_MS) 이 번개도 막음
        b.stunUntil = g.time;
        Assert.Empty(Hits(Strike(g, b.x - 0.3, b.y, b.id)));
        Assert.Equal(0, b.comboHits);
        Assert.True(g.time < b.iframeUntil);
        // 무적까지 풀리면 맞음
        for (int i = 0; i < 90; i++) g.Tick(TICK);
        Assert.True(g.time >= b.iframeUntil && g.time >= b.stunUntil);
        Put(g, b, 5.5, 5.5);
        Assert.Equal(new[] { b.id }, Hits(Strike(g, b.x - 0.3, b.y, b.id)));
        Assert.Equal(dmg + C.EVENT_BOLT_DAMAGE, b.damage);
        Assert.Equal(c.id, b.lastHit!.by); // 번개는 lastHit 을 안 덮음
    }

    // 가장자리의 p 를 안쪽에 떨어진 번개로 판 밖으로 날리고 death 이벤트를 돌려줌
    static JsonElement BoltOff(Game g, Player p)
    {
        Put(g, p, 0.35, 5.5);
        p.stunUntil = p.iframeUntil = p.shieldUntil = 0;
        p.comboHits = 0;
        Assert.Equal(new[] { p.id }, Hits(Strike(g, 1.0, 5.5, p.id)));
        for (int i = 0; i < 300; i++)
        {
            g.Tick(TICK);
            var d = EventsOf(g, "death");
            if (d.Count > 0) return Assert.Single(d);
        }
        Assert.Fail($"번개에 밀린 사람이 안 떨어짐 ({p.x}, {p.y}, {p.z})");
        return default;
    }

    // (c) A 가 B 를 민 뒤 번개로 B 가 떨어지면 킬은 A. 아무도 안 민 사람이면 킬 없음
    [Fact]
    public void 번개로_떨어지면_킬은_마지막으로_민_사람()
    {
        var (g, lines) = Humans(3, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        var c = g.GetPlayer(3)!;
        Put(g, a, 5.5, 2.5);
        Put(g, b, 5.5, 5.5);
        Put(g, c, 8.5, 8.5);
        Assert.True(g.ApplyKnockback(b, 0, 1, 0.5, 1, C.STUN_MS, 5, new Src(a.id, "push")));
        for (int i = 0; i < 90; i++) g.Tick(TICK); // 착지·경직·콤보 뒤 무적이 다 풀림
        Assert.Equal(a.id, b.lastHit!.by);
        var d = BoltOff(g, b);
        Assert.Equal(b.id, d.GetProperty("who").GetInt32());
        Assert.Equal("fall", d.GetProperty("cause").GetString());
        Assert.Equal(a.id, d.GetProperty("by").GetInt32());
        Assert.Equal("push", d.GetProperty("weapon").GetString());
        Assert.Equal(1, g.scores.GetValueOrDefault(a.id));
        // 아무도 안 민 사람 (c): 킬 없음
        Assert.Null(c.lastHit);
        d = BoltOff(g, c);
        Assert.Equal(c.id, d.GetProperty("who").GetInt32());
        Assert.Equal(JsonValueKind.Null, d.GetProperty("by").ValueKind);
        Assert.Equal(1, g.scores.GetValueOrDefault(a.id)); // 그대로
        Assert.Equal(-1, g.scores.GetValueOrDefault(c.id)); // 킬 없는 낙사 = 자멸
    }

    // (d) 체력전: 번개 한 번에 HP 가 EVENT_BOLT_DAMAGE 만큼 깎임 (스냅샷 hp)
    [Fact]
    public void 체력전에서_HP_가_깎임()
    {
        var (g, _) = Humans(2, "kills", hp: true);
        var a = g.GetPlayer(1)!;
        Put(g, a, 5.5, 5.5);
        double Hp() => J(g.Snapshot()).GetProperty("players").EnumerateArray().First(q => q.GetProperty("id").GetInt32() == a.id).GetProperty("hp").GetDouble();
        double before = Hp();
        Assert.Equal(g.HpMax(a), before);
        Assert.Equal(new[] { a.id }, Hits(Strike(g, 5.3, 5.5, a.id)));
        Assert.Equal(before - C.EVENT_BOLT_DAMAGE, Hp());
        Assert.Equal(15, C.EVENT_BOLT_DAMAGE);
    }

    // (e) 판이 끝나면 남은 예고는 버려짐: 봇에게도 안 보이고 (ActiveBolts), 다음 판에 안 떨어짐. 예고 id 는 새 판에 1 부터
    [Fact]
    public void 판이_끝나면_남은_예고는_안_터짐()
    {
        var (g, _) = Humans(3, "kills");
        g.StartRoundEvent("bolt");
        for (int i = 0; i < 5; i++) g.Tick(TICK);
        Assert.Equal(2, g.bolts.Count); // ceil(3 × 0.5)
        Assert.Equal(2, g.ActiveBolts().Count);
        g.EndRound(null);
        Assert.Empty(g.ActiveBolts());
        g.DrainEvents();
        Play(g);
        Assert.Empty(g.bolts);
        Assert.Empty(g.ActiveBolts());
        for (double t = 0; t < C.EVENT_BOLT_WARN_MS + 500; t += TICK) g.Tick(TICK);
        Assert.Empty(EventsOf(g, "bolt"));
        foreach (var p in g.Players()) Assert.Equal(0, p.damage);
        g.StartRoundEvent("bolt");
        g.Tick(TICK);
        Assert.Equal(new[] { 1, 2 }, EventsOf(g, "boltWarn").Select(e => e.GetProperty("id").GetInt32()));
        // 다른 이벤트로 바뀌어도 이미 뜬 예고는 떨어짐 (같은 판 안)
        g.StartRoundEvent("ice");
        for (double t = 0; t < C.EVENT_BOLT_WARN_MS + 2 * TICK; t += TICK) g.Tick(TICK);
        Assert.Equal(2, EventsOf(g, "bolt").Count);
        Assert.Empty(g.bolts);
    }

    // 봇 하나 (상대 없음 — 다른 한 명은 죽어 있음) 가 평지에 서 있음. warn: 발밑에 예고를 띄움. 돌려줌: EVENT_BOLT_WARN_MS 뒤 그 자리에서 수평 거리
    static double BotDistAfterWarn(uint seed, bool warn, double dz = 0)
    {
        var g = new Game(null, characters: true);
        g.rng = new Mulberry32(seed).AsFunc();
        g.AddPlayer(1);
        var bot = g.AddBot()!;
        Assert.True(g.SetMode("kills"));
        Assert.True(g.SetRoundEvents(true));
        Play(g);
        var human = g.GetPlayer(1)!;
        g.Kill(human, "fall");
        human.respawnAt = double.PositiveInfinity;
        for (int i = 0; i < 60; i++) g.Tick(TICK); // 봇이 자리를 잡음
        Assert.True(g.OnField(bot));
        double x = bot.x, y = bot.y;
        double at = g.time + C.EVENT_BOLT_WARN_MS;
        if (warn) g.bolts.Add(new BoltWarn { id = 1, x = x, y = y, z = g.BoltWarnZ(bot) + dz, at = at, target = bot.id });
        while (g.time < at - TICK / 2) g.Tick(TICK); // 떨어지기 직전 틱까지 (떨어지는 틱의 물리는 판정 앞에 돎 — 한 틱 차이는 문턱에 안 걸림)
        return g.OnField(bot) ? JsMath.Hypot(bot.x - x, bot.y - y) : double.PositiveInfinity;
    }

    // (f) 봇은 번개 예고를 보고 비킴 (반응 시간은 블록 그림자와 같음 — 특혜 없음): 시드 20개 중 14개 이상이 예고 시각에 반경 밖.
    // 견줄 값: 예고가 없으면 같은 봇이 그 자리 근처에 그대로 있음 (봇이 비킨 것은 예고 때문)
    [Fact]
    public void 봇은_예고_고리_밖으로_비킴()
    {
        int out_ = 0, idleOut = 0;
        var dists = new List<string>();
        for (uint seed = 1; seed <= 20; seed++)
        {
            double d = BotDistAfterWarn(seed, warn: true);
            if (d > C.EVENT_BOLT_RADIUS) out_++;
            if (BotDistAfterWarn(seed, warn: false) > C.EVENT_BOLT_RADIUS) idleOut++;
            dists.Add(d.ToString("0.00"));
        }
        Assert.True(out_ >= 14, $"예고 시각에 반경 밖 {out_}/20 (거리 {string.Join(" ", dists)})");
        Assert.True(idleOut <= 6, $"예고가 없는데도 자리를 뜬 판 {idleOut}/20 — 견줄 값이 뜻이 없음");
    }

    // (f) 봇은 발 높이 차가 판정 밖 (EVENT_BOLT_HEIGHT 넘음 — Game.BoltStrike 와 같은 '>') 인 예고는 안 피함 (c9 리뷰 F4):
    // 그런 예고가 떠 있어도 예고가 없을 때와 한 치도 다르지 않게 움직임. 딱 EVENT_BOLT_HEIGHT 차 (맞는 높이) 는 피함
    [Fact]
    public void 봇은_높이가_안_닿는_예고는_안_피함()
    {
        int moved = 0;
        for (uint seed = 1; seed <= 20; seed++)
        {
            double idle = BotDistAfterWarn(seed, warn: false);
            foreach (double dz in new[] { C.EVENT_BOLT_HEIGHT + 0.5, -(C.EVENT_BOLT_HEIGHT + 0.5) })
                Assert.Equal(idle, BotDistAfterWarn(seed, warn: true, dz: dz));
            if (BotDistAfterWarn(seed, warn: true, dz: C.EVENT_BOLT_HEIGHT) > C.EVENT_BOLT_RADIUS) moved++;
        }
        Assert.True(moved >= 14, $"높이 차가 딱 EVENT_BOLT_HEIGHT 인 예고를 피한 판 {moved}/20");
    }

    // 필드 위 사람이 a 뿐일 때 번개 한 차례를 실제로 돌려 (BoltVolley) a 의 예고를 받고, 그 자리에서 바로 떨어뜨림. 돌려줌: (boltWarn, bolt)
    static (JsonElement warn, JsonElement bolt) VolleyOn(Game g, Player a)
    {
        g.bolts.Clear();
        g.StartRoundEvent("bolt");
        g.DrainEvents();
        g.UpdateRoundEvents(TICK);
        var warn = Assert.Single(EventsOf(g, "boltWarn"));
        var w = Assert.Single(g.bolts);
        Assert.Equal(a.id, w.target);
        w.at = g.time;
        g.UpdateRoundEvents(TICK);
        return (warn, Assert.Single(EventsOf(g, "bolt")));
    }

    // (h) 예고 높이는 대상 발 높이 (c9 리뷰 F3): 머리 위에 처마 (착지한 블록의 튀어나온 칸) 가 있어도 그 윗면이 아니라 발밑 —
    // 가만히 서 있으면 맞고 로그는 '맞음'. 예전 (기둥 꼭대기) 에는 처마가 +3칸 이상이면 '피함', +2칸이면 고리가 머리 위 블록 윗면에 그려졌음
    [Theory]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(5)]
    public void 처마_밑에_서_있어도_발밑에_예고되고_맞음(int up)
    {
        var (g, lines) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        g.Kill(b, "fall");
        b.respawnAt = double.PositiveInfinity;
        Put(g, a, 5.5, 5.5);
        int feet = (int)a.z;
        g.grid[g.Idx(5, 5, feet + up)] = 1; // 머리 위 처마: 발밑 기둥과 떨어진 칸
        Assert.Equal(feet + up + 1, g.ColumnTop(5, 5));
        lines.Clear();
        var (warn, bolt) = VolleyOn(g, a);
        Assert.Equal(feet, warn.GetProperty("z").GetDouble());
        Assert.Equal(feet, bolt.GetProperty("z").GetDouble());
        Assert.Equal(new[] { a.id }, Hits(bolt));
        Assert.Equal(C.EVENT_BOLT_DAMAGE, a.damage);
        Assert.Contains($"  [번개] {a.name} 맞음", lines);
        Assert.DoesNotContain($"  [번개] {a.name} 피함", lines);
    }

    // 공중 (점프·띄워짐) 인 대상은 발밑에서 아래로 처음 만나는 블록 윗면에 예고: 머리 위 처마도, 발보다 높은 옆 칸도 아님. 발밑에 블록이 없으면 바닥 0
    [Fact]
    public void 공중이면_발밑_아래_첫_블록_윗면에_예고()
    {
        var (g, _) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        g.Kill(b, "fall");
        b.respawnAt = double.PositiveInfinity;
        Put(g, a, 5.5, 5.5);
        int ground = (int)a.z;
        g.grid[g.Idx(5, 5, ground + 6)] = 1; // 머리 위 처마
        Put(g, a, 5.5, 5.5);
        a.z = ground + 1.5; // 처마 밑 공중
        a.grounded = false;
        Assert.Equal(ground, g.BoltWarnZ(a));
        var (warn, bolt) = VolleyOn(g, a);
        Assert.Equal(ground, warn.GetProperty("z").GetDouble());
        Assert.Equal(new[] { a.id }, Hits(bolt)); // 높이 차 1.5 — 맞음
        // 처마 위 공중이면 처마 윗면
        a.z = ground + 7.4;
        Assert.Equal(ground + 7, g.BoltWarnZ(a));
        // 서 있으면 발 높이 그대로 (칸 경계에 걸쳐 서서 가운데 기둥이 더 낮아도)
        a.z = ground + 7;
        a.grounded = true;
        Assert.Equal(ground + 7, g.BoltWarnZ(a));
        // 발밑에 블록이 하나도 없는 기둥: 바닥 0
        for (int z = 0; z < g.H; z++) g.grid[g.Idx(5, 5, z)] = 0;
        a.z = 2.3;
        a.grounded = false;
        Assert.Equal(0, g.BoltWarnZ(a));
    }

    // 탱크 아머 (F 돌진 중·R 떠오르는 동안) 가 번개를 버팀 (c9 리뷰 F7): 피해 % 만 들어가고 넉백·경직 없음, 로그의 때린 쪽은 '?' 가 아니라 '번개',
    // armor 이벤트의 by 는 없음 (null), 번개 로그·hits 는 '맞음' 그대로
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void 탱크_아머는_번개를_버티고_로그는_번개(bool charge)
    {
        var (g, lines) = Humans(2, "kills");
        var a = g.GetPlayer(1)!;
        var b = g.GetPlayer(2)!;
        Assert.Equal("tank", a.@char);
        Put(g, b, 1.5, 1.5);
        Put(g, a, 5.5, 5.5);
        if (charge) a.chargeUntil = g.time + 10000;
        else a.slamAt = g.time + 10000;
        lines.Clear();
        g.DrainEvents();
        g.bolts.Add(new BoltWarn { id = 901, x = 5.2, y = 5.5, z = g.BoltWarnZ(a), at = g.time, target = a.id });
        g.UpdateRoundEvents(TICK);
        var evs = g.DrainEvents().Select(J).ToList();
        var bolt = Assert.Single(evs, e => e.GetProperty("type").GetString() == "bolt");
        var armor = Assert.Single(evs, e => e.GetProperty("type").GetString() == "armor");
        Assert.Equal(new[] { a.id }, Hits(bolt));
        Assert.Equal(a.id, armor.GetProperty("who").GetInt32());
        Assert.Equal(JsonValueKind.Null, armor.GetProperty("by").ValueKind);
        Assert.Equal(C.EVENT_BOLT_DAMAGE, a.damage);
        Assert.Equal(0, a.stunUntil); // 경직·넉백 없음
        Assert.Equal(0, a.kbx);
        Assert.Null(a.lastHit);
        Assert.Contains($"  [아머] {a.name} ← 번개 버팀 ({a.name} {JsNumber.ToJs(a.damage)}%)", lines);
        Assert.DoesNotContain(lines, l => l.Contains("← ?"));
        Assert.Contains($"  [번개] {a.name} 맞음", lines);
    }

    // (g) 번개만 나오는 봇 8명 판 (생존·킬 점수전, 시드 3개씩): 예외 없이 끝까지 가고, 번개가 실제로 사람을 맞힘
    [Theory]
    [InlineData("survival")]
    [InlineData("kills")]
    public void 봇_8명_판이_끝까지_감(string mode)
    {
        for (uint seed = 1; seed <= 3; seed++)
        {
            var lines = new List<string>();
            var g = new Game(lines.Add, characters: true);
            g.rng = new Mulberry32(7000 + seed).AsFunc();
            if (mode != "survival") Assert.True(g.SetMode(mode));
            Assert.True(g.SetRoundEvents(true));
            g.eventKinds = new[] { "bolt" };
            for (int b = 0; b < 8; b++) g.AddBot();
            Assert.True(g.StartRound());
            int warns = 0, strikes = 0, hits = 0;
            while (g.phase != "over" && g.time < C.KILLS_TIME_MS + 30000)
            {
                g.Tick(TICK);
                foreach (var json in g.DrainEvents())
                {
                    var e = J(json);
                    string type = e.GetProperty("type").GetString()!;
                    if (type == "boltWarn") warns++;
                    else if (type == "bolt")
                    {
                        strikes++;
                        hits += Hits(e).Count;
                    }
                }
            }
            string desc = $"{mode} 시드 {seed}: 예고 {warns} 떨어짐 {strikes} 맞음 {hits}, {g.time / 1000:0}초";
            Assert.True(g.phase == "over", $"판이 안 끝남 — {desc}");
            Assert.True(lines.Count(l => l.StartsWith("  [이벤트] 번개 6초")) >= 1, $"번개 이벤트가 안 나옴 — {desc}");
            Assert.True(warns >= 1 && strikes >= 1 && strikes <= warns, desc);
            Assert.True(hits >= 1, $"맞은 사람이 없음 — {desc}");
            Assert.Equal(hits, lines.Count(l => l.StartsWith("  [번개] ") && l.EndsWith(" 맞음")));
        }
    }
}
