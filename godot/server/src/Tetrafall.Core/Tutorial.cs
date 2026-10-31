using System.Text.Json;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/tutorial.js + shared/tutorial.js (서버가 쓰는 부분: 단계 고르기·펴기·판정·다음 단계).
// 연습 모드 판 위에서 단계 하나씩: 단계가 바뀌면 지형·허수아비·아이템을 다시 놓고, 틱마다·이벤트마다 완료를 판정 → tutorialOk → TUTORIAL_NEXT_MS 뒤 다음
public sealed class TutorialLayout
{
    public (double x, double y, double yaw) start;
    public (double x, double y, double z)? target;
    public List<int[]> cells = new();
    public List<(double x, double y, double damage)> dummies = new();
    public List<(double x, double y, string type)> items = new();
}

public sealed class Tutorial
{
    readonly Game g;
    readonly int pid;
    public int i;
    public bool done;
    public double? okAt;
    public readonly List<string?> results = new(); // 단계마다 'ok' | 'skip'
    public readonly List<TTutorialSteps> steps;
    TutorialLayout layout = null!;
    Ctx ctx = null!;
    double startAt;
    (int id, double at)? drop; // dodge: 지금 떨어지는 블록
    double nextDropAt;

    sealed class Ctx
    {
        public double dummyMax, dodged, crushedAt = double.NegativeInfinity;
        public bool dashed, ringout, crit, skill, ult, picked, itemUsed;
        public double? lastHeld;
    }

    public Tutorial(Game game, int playerId)
    {
        g = game;
        pid = playerId;
        var p = game.GetPlayer(playerId);
        steps = TutorialSteps(p?.@char); // 캐릭터에 없는 단계는 뺌 (바드 치명타)
        Begin(0);
    }

    public TTutorialSteps step => steps[i];

    public double Dodged => ctx.dodged; // 테스트용 (JS tutorial.ctx.dodged)

    Player? Me() => g.GetPlayer(pid);

    // ---- shared/tutorial.js ----
    public static List<TTutorialSteps> TutorialSteps(string? ch) => C.TUTORIAL_STEPS.Where(st => !(st.skipChars ?? Array.Empty<string>()).Contains(ch)).ToList();

    // 필드 가운데 기준 → 필드 좌표 (블록·아이템은 가운데 칸 기준 칸 번호, 사람·허수아비·목표는 그 칸 가운데 기준)
    public static TutorialLayout Layout(TTutorialSteps step, int W, int D)
    {
        int cx = W / 2, cy = D / 2;
        double px = cx + 0.5, py = cy + 0.5;
        var s = step.start ?? new double[] { 0, 0, 0 };
        double sx = s.Length > 0 ? s[0] : 0, sy = s.Length > 1 ? s[1] : 0, yaw = s.Length > 2 ? s[2] : 0;
        var out_ = new TutorialLayout
        {
            start = (px + sx, py + sy, yaw),
            target = step.target != null ? (px + step.target[0], py + step.target[1], step.minZ ?? 0) : null,
        };
        foreach (var d in step.dummies ?? Array.Empty<double[]>()) out_.dummies.Add((px + d[0], py + d[1], d.Length > 2 ? d[2] : 0));
        foreach (var it in step.items ?? Array.Empty<object[]>()) out_.items.Add((cx + (double)it[0], cy + (double)it[1], (string)it[2]));
        void Put(int x, int y, double h)
        {
            if (!(x >= 0 && x < W && y >= 0 && y < D)) return;
            for (int z = 0; z < h; z++) out_.cells.Add(new[] { x, y, z });
        }
        foreach (var b in step.blocks ?? Array.Empty<double[]>())
            for (int x = cx + (int)b[0]; x <= cx + (int)b[2]; x++)
                for (int y = cy + (int)b[1]; y <= cy + (int)b[3]; y++) Put(x, y, b[4]);
        foreach (var st in step.stairs ?? Array.Empty<double[]>())
            for (int y = cy + (int)st[1]; y <= cy + (int)st[2]; y++) Put(cx + (int)st[0], y, st[3]);
        return out_;
    }

    // 완료 판정
    static bool Judge(TTutorialSteps step, Ctx c, (double x, double y, double z, bool grounded)? me, (double x, double y, double z)? t)
    {
        switch (step.kind)
        {
            case "reach":
                if (me == null || t == null) return false;
                bool near = JsMath.Hypot(me.Value.x - t.Value.x, me.Value.y - t.Value.y) <= C.TUTORIAL_REACH_R;
                return near && (step.minZ is not double mz || mz == 0 || (me.Value.grounded && me.Value.z >= mz - 0.01));
            case "dash": return c.dashed;
            case "damage": return c.dummyMax >= step.pct;
            case "ringout": return c.ringout;
            case "crit": return c.crit;
            case "skill": return c.skill;
            case "ult": return c.ult;
            case "item": return c.itemUsed;
            case "dodge": return c.dodged >= step.n;
            case "climb": return me != null && me.Value.grounded && me.Value.z >= step.z - 0.01;
            default: return false;
        }
    }

    static int? NextStep(int i, int n) => i + 1 < n ? i + 1 : null;

    // ---- server/tutorial.js ----
    // 단계 시작: 지형·허수아비·아이템·토글을 단계 표대로, 나는 처음 자리로
    void Begin(int idx)
    {
        i = idx;
        okAt = null;
        var st = step;
        var L = layout = Layout(st, g.W, g.D);
        ctx = new Ctx();
        startAt = g.time;
        drop = null;
        nextDropAt = g.time + C.TUTORIAL_DODGE_EVERY_MS;
        foreach (var d in g.Dummies()) g.RemoveDummy(d.id);
        g.practice!.noCooldown = st.noCooldown;
        g.practice.fullUlt = st.fullUlt;
        g.practice.noBlocks = true;
        g.practice.noDeath = true;
        var p = Me();
        if (p != null)
        {
            p.home = new XY(L.start.x, L.start.y);
            p.practiceDamage = 0;
            p.yaw = L.start.yaw;
            p.skillReadyAt = 0;
            if (!st.fullUlt) p.ult = 0;
            p.ammo = 0;
            p.bricks = 0;
            p.bombs = 0;
        }
        // 쌓인 블록처럼 보이는 칸: 단계마다 모양 색 하나
        byte v = Pieces.CellOfShape(Pieces.SHAPE_NAMES[idx % Pieces.SHAPE_NAMES.Length]);
        g.ResetArena("flat", L.cells.Select(c => (c[0], c[1], c[2], v)).ToList());
        foreach (var d in L.dummies) AddDummy(d.x, d.y, d.damage);
        var ds = g.Dummies();
        ds.Reverse(); // 놓은 순서
        for (int k = 0; k < ds.Count; k++) ds[k].name = ds.Count > 1 ? $"허수아비 {k + 1}" : "허수아비";
        foreach (var it in L.items)
        {
            int ix = (int)Math.Floor(it.x), iy = (int)Math.Floor(it.y);
            g.items.Add(new Item { type = it.type, x = ix, y = iy, z = g.ColumnTop(ix, iy) });
        }
        if (p != null && st.marks is double marks && marks != 0 && p.@char == "hunter")
            foreach (var d in g.Dummies())
                for (int k = 0; k < marks; k++) g.AddMark(p, d); // 사냥꾼 F·R 은 표식이 있어야
        if (st.kind == "climb") g.lava = new Lava { active = true, z = C.TUTORIAL_LAVA_START_Z, startedAt = g.time };
        g.Emit(o => o.P("type", "tutorialStep").P("i", idx).P("id", st.id).P("yaw", L.start.yaw).P("who", pid));
        g.Log($"[튜토리얼] {idx + 1}/{steps.Count} {st.id}");
    }

    Player? AddDummy(double x, double y, double damage)
    {
        var d = g.AddDummy(pid);
        if (d == null) return null;
        d.home = new XY(x, y);
        d.dummyDamage = damage;
        g.PracticeReset(d, null);
        d.yaw = Math.PI; // 처음 자리(-x) 쪽을 봄
        return d;
    }

    // 이벤트마다 (game.emit): 치명타·스킬·필살기·아이템·떨어짐
    public void OnEvent(JsonElement e)
    {
        if (done || okAt != null) return;
        var c = ctx;
        string? type = e.TryGetProperty("type", out var tv) ? tv.GetString() : null;
        bool Is(string k, double v) => e.TryGetProperty(k, out var x) && x.ValueKind == JsonValueKind.Number && x.GetDouble() == v;
        bool Truthy(string k) => JsValue.Truthy(e.TryGetProperty(k, out var x) ? x : null);
        if (type == "hit" && Is("by", pid) && Truthy("crit")) c.crit = true;
        else if (type == "skill" && Is("who", pid)) c.skill = true;
        else if (type == "ult" && Is("who", pid)) c.ult = true;
        else if (type == "pickup" && Is("who", pid)) c.picked = true;
        else if (type == "practiceReset")
        {
            int who = e.GetProperty("who").GetInt32();
            string? cause = e.GetProperty("cause").GetString();
            var d = g.GetPlayer(who);
            if (d != null && d.dummy && cause == "fall") c.ringout = true;
            if (who == pid)
            {
                if (cause == "crush") c.crushedAt = g.time;
                if (step.kind == "climb") g.lava.z = C.TUTORIAL_LAVA_START_Z; // 다시 처음부터
            }
        }
    }

    // 넘기기: 지금 단계를 건너뜀 (체크 보여 주는 중이어도 바로 다음)
    public bool Skip()
    {
        if (done) return false;
        if (okAt == null) SetResult(i, "skip");
        Advance();
        return true;
    }

    void SetResult(int k, string r)
    {
        while (results.Count <= k) results.Add(null); // JS 배열 빈 칸 → JSON null
        results[k] = r;
    }

    void Advance()
    {
        var n = NextStep(i, steps.Count);
        if (n == null)
        {
            done = true;
            okAt = null;
            foreach (var d in g.Dummies()) g.RemoveDummy(d.id);
            g.lava = new Lava();
            int ok = results.Count(r => r == "ok");
            g.Emit(o => o.P("type", "tutorialDone").P("who", pid).P("ok", ok));
            g.Log("[튜토리얼] 끝");
            return;
        }
        Begin(n.Value);
    }

    public void Update(double dtMs)
    {
        if (done) return;
        if (okAt != null)
        {
            if (g.time >= okAt + C.TUTORIAL_NEXT_MS) Advance();
            return;
        }
        var p = Me();
        if (p == null) return;
        var st = step;
        var c = ctx;
        if (p.dashReadyAt > startAt) c.dashed = true;
        // 허수아비 피해 % 는 콤보가 끝나도 안 돌아감 (진짜 판처럼 쌓임)
        foreach (var d in g.Dummies())
        {
            if (d.damage > d.dummyDamage) d.dummyDamage = d.damage;
            c.dummyMax = Math.Max(c.dummyMax, d.damage);
        }
        double held = p.ammo + p.bricks + p.bombs;
        if (c.picked && c.lastHeld != null && held < c.lastHeld) c.itemUsed = true;
        c.lastHeld = held;
        if (st.kind == "dodge") UpdateDodge(p);
        if (st.kind == "climb") UpdateLava(p, dtMs);
        bool okNow = Judge(st, c, (p.x, p.y, p.z, p.grounded && p.alive), layout.target);
        if (okNow)
        {
            okAt = g.time;
            SetResult(i, "ok");
            g.Emit(o => o.P("type", "tutorialOk").P("i", i).P("id", st.id).P("who", pid));
            g.Log($"[튜토리얼] {st.id} 해냄 ({JsNumber.ToFixed((g.time - startAt) / 1000, 1)}초)");
        }
    }

    // 그림자 보고 피하기: 내 자리를 덮는 O 블록을 낮은 데서 하나씩. 내려앉았는데 그동안 안 깔렸으면 하나 피함
    void UpdateDodge(Player p)
    {
        if (drop is var (dropId, dropAt))
        {
            if (g.pieces.Any(pc => pc.id == dropId)) return;
            if (ctx.crushedAt < dropAt) ctx.dodged++;
            drop = null;
            nextDropAt = g.time + C.TUTORIAL_DODGE_EVERY_MS;
            return;
        }
        if (g.time < nextDropAt || !p.alive) return;
        int px = Math.Max(0, Math.Min(g.W - 2, (int)Math.Floor(p.x) - (g.rng() < 0.5 ? 1 : 0)));
        int py = Math.Max(0, Math.Min(g.D - 2, (int)Math.Floor(p.y) - (g.rng() < 0.5 ? 1 : 0)));
        int top = Math.Max(Math.Max(g.ColumnTop(px, py), g.ColumnTop(px + 1, py)), Math.Max(g.ColumnTop(px, py + 1), g.ColumnTop(px + 1, py + 1)));
        int pz = (int)Math.Min(g.H - 1, top + C.TUTORIAL_DODGE_DROP_Z);
        var piece = g.MakePiece("O", 0, px, py, pz);
        double stepMs = C.TUTORIAL_DODGE_STEP_MS;
        g.AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.stepMs = stepMs;
            pc.nextStepAt = g.time + stepMs;
            pc.controlEndsAt = 0;
        });
        drop = (piece.id, g.time);
    }

    // 용암: 천천히 오르다 꼭대기 조금 아래에서 멈춤. 닿으면 처음 자리
    void UpdateLava(Player p, double dtMs)
    {
        double top = step.z!.Value - C.TUTORIAL_LAVA_TOP_GAP;
        g.lava.z = Math.Min(top, g.lava.z + dtMs / C.TUTORIAL_LAVA_MS_PER_CELL);
        if (p.alive && g.OnField(p) && p.z < g.lava.z - 0.05) g.Kill(p, "lava");
    }

    public void Snapshot(JsonOut o)
    {
        var t = layout.target;
        o.Obj().P("i", i).P("n", steps.Count).P("id", done ? null : step.id).P("ok", okAt != null).P("done", done);
        o.Key("target");
        if (!done && t != null) o.Obj().P("x", t.Value.x).P("y", t.Value.y).P("z", t.Value.z).EndObj();
        else o.Null();
        o.P("dodged", ctx.dodged).Key("results").Arr();
        foreach (var r in results) o.Str(r);
        o.EndArr().EndObj();
    }
}
