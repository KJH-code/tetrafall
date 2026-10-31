using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Trace;

// shared/tutorial-pilot.js 그대로 (확인용 튜토리얼 자동 조종): 스냅샷(JSON)만 보고 단계마다 입력·행동을 냄
public sealed class TutorialPilot
{
    string? stepId;
    int k;
    Dictionary<string, object?> mem = new();
    double? prevZ;

    public (InputMsg input, List<string> actions) Next(JsonElement state, int myId)
    {
        JsonElement? me = null;
        foreach (var p in state.GetProperty("players").EnumerateArray()) if (p.GetProperty("id").GetDouble() == myId) me = p;
        var tut = state.GetProperty("tutorial");
        var input = new InputMsg { fwd = 0, strafe = 0, jump = false, yaw = me?.GetProperty("yaw").GetDouble() ?? 0, pitch = 0 };
        var actions = new List<string>();
        if (me == null || tut.ValueKind == JsonValueKind.Null || tut.GetProperty("done").GetBoolean() || tut.GetProperty("ok").GetBoolean() || !me.Value.GetProperty("alive").GetBoolean()) return (input, actions);
        var M = me.Value;
        string? id = tut.GetProperty("id").GetString();
        if (id != stepId)
        {
            stepId = id;
            k = 0;
            mem = new();
        }
        int kk = ++k;
        double mx = M.GetProperty("x").GetDouble(), my = M.GetProperty("y").GetDouble(), mz = M.GetProperty("z").GetDouble();
        double vz = prevZ == null ? 0 : mz - prevZ.Value;
        prevZ = mz;
        bool onGround = Math.Abs(vz) < 1e-3;
        double Dist(double x, double y) => JsMath.Hypot(x - mx, y - my);
        void Face(double x, double y) => input.yaw = JsMath.Atan2(y - my, x - mx);
        void Go(double x, double y, double stop = 0.25)
        {
            Face(x, y);
            input.fwd = Dist(x, y) > stop ? 1 : 0;
        }
        JsonElement? dummy = null;
        foreach (var p in state.GetProperty("players").EnumerateArray())
            if (dummy == null && p.GetProperty("dummy").GetBoolean() && p.GetProperty("alive").GetBoolean()) dummy = p;
        double dx_ = dummy?.GetProperty("x").GetDouble() ?? 0, dy_ = dummy?.GetProperty("y").GetDouble() ?? 0, dz_ = dummy?.GetProperty("z").GetDouble() ?? 0;
        var field = state.GetProperty("field");
        double W = field.GetProperty("w").GetDouble(), D = field.GetProperty("d").GetDouble();
        double Tx() => tut.GetProperty("target").GetProperty("x").GetDouble();
        double Ty() => tut.GetProperty("target").GetProperty("y").GetDouble();
        bool Has(string key) => mem.TryGetValue(key, out var v) && v is not null && !(v is bool b && !b) && !(v is int i && i == 0);
        switch (id)
        {
            case "move":
                Go(Tx(), Ty(), 0.15);
                break;
            case "jump":
            {
                Go(Tx(), Ty(), 0.15);
                double wallX = Math.Floor(Tx()) - 2;
                if (onGround && mz < 0.5 && mx > wallX - 1.4)
                {
                    input.jump = true;
                    mem["jumpAt"] = kk;
                }
                if (Has("jumpAt") && kk - (int)mem["jumpAt"]! >= 7 && !Has("air") && mz > 0.4)
                {
                    actions.Add("jump");
                    mem["air"] = true;
                }
                if (onGround) mem["air"] = false;
                break;
            }
            case "dash":
                input.yaw = 0;
                if (kk % 30 == 3) actions.Add("dash");
                break;
            case "push":
            case "ringout":
                if (dummy == null) break;
                Go(dx_, dy_, 1.0);
                if (Dist(dx_, dy_) < 1.5 && kk % 6 == 0) actions.Add("push");
                break;
            case "crit":
            {
                if (dummy == null) break;
                double d = Dist(dx_, dy_);
                Face(dx_, dy_);
                if (onGround)
                {
                    input.fwd = d > 1.9 ? 1 : d < 1.4 ? -1 : 0;
                    if (d <= 1.9 && d >= 1.2 && kk % 4 == 0) input.jump = true;
                }
                else
                {
                    input.fwd = d > 0.9 ? 1 : 0;
                    if (vz < 0 && mz > dz_ + 0.35 && d < 1.8) actions.Add("push");
                }
                break;
            }
            case "skill":
            case "ult":
            {
                if (dummy == null) break;
                if (id == "ult" && M.GetProperty("char").GetString() == "hook")
                {
                    if (!Has("pillar")) mem["pillar"] = FindPillar(W, D);
                    if (mem["pillar"] is (double px, double py)) Face(px, py);
                }
                else Face(dx_, dy_);
                if (Dist(dx_, dy_) > 3) input.fwd = 1;
                if (kk % 15 == 5) actions.Add(id);
                break;
            }
            case "item":
            {
                var items = state.GetProperty("items");
                JsonElement? it = items.GetArrayLength() > 0 ? items[0] : null;
                if (M.GetProperty("held").ValueKind == JsonValueKind.Null && it != null) Go(it.Value.GetProperty("x").GetDouble() + 0.5, it.Value.GetProperty("y").GetDouble() + 0.5, 0.1);
                else if (dummy != null)
                {
                    Face(dx_, dy_);
                    if (kk % 10 == 0) actions.Add("fire");
                }
                break;
            }
            case "dodge":
            {
                var shade = new HashSet<(double, double)>();
                foreach (var pc in state.GetProperty("pieces").EnumerateArray())
                    if (pc.GetProperty("phase").GetString() == "falling")
                        foreach (var c in pc.GetProperty("shadow").EnumerateArray()) shade.Add((c[0].GetDouble(), c[1].GetDouble()));
                bool Covered(double x, double y)
                {
                    foreach (var ox in new[] { -0.4, 0.4 })
                        foreach (var oy in new[] { -0.4, 0.4 })
                            if (shade.Contains((Math.Floor(x + ox), Math.Floor(y + oy)))) return true;
                    return false;
                }
                var flee = mem.TryGetValue("flee", out var fv) ? ((double x, double y)?)fv : null;
                if (flee != null && !Covered(flee.Value.x, flee.Value.y) && shade.Count > 0) Go(flee.Value.x, flee.Value.y, 0.1);
                else if (Covered(mx, my))
                {
                    (double x, double y, double score)? best = null;
                    for (int a = 0; a < 16; a++)
                    {
                        double x = mx + JsMath.Cos((a / 16.0) * Math.PI * 2) * 2.4;
                        double y = my + JsMath.Sin((a / 16.0) * Math.PI * 2) * 2.4;
                        if (x < 1 || y < 1 || x > W - 1 || y > D - 1 || Covered(x, y)) continue;
                        double score = JsMath.Hypot(x - W / 2, y - D / 2);
                        if (best == null || score < best.Value.score) best = (x, y, score);
                    }
                    mem["flee"] = best == null ? null : ((double, double)?)(best.Value.x, best.Value.y);
                    if (best != null) Go(best.Value.x, best.Value.y, 0.1);
                }
                else mem["flee"] = null;
                break;
            }
            case "climb":
                input.yaw = 0;
                input.fwd = mz >= 4.9 && mx >= Math.Floor(W / 2) + 1.3 ? 0 : 1;
                input.jump = input.fwd == 1;
                break;
        }
        return (input, actions);
    }

    // 단계 표에서 기둥 칸 (갈고리 R 이 잡을 블록)
    static (double, double)? FindPillar(double W, double D)
    {
        var step = C.TUTORIAL_STEPS.First(st => st.id == "ult");
        var cells = Tutorial.Layout(step, (int)W, (int)D).cells;
        return cells.Count > 0 ? (cells[0][0] + 0.5, cells[0][1] + 0.5) : null;
    }
}
