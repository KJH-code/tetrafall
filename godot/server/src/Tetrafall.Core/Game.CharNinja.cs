using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-ninja.js — 닌자 (S3)
public sealed partial class Game
{
    // 플레이어 몸 상자를 (x, y, z) 에 둔 것 (JS aabb({ x, y, z }))
    public static (double x0, double x1, double y0, double y1, double z0, double z1) AabbAt(double x, double y, double z) =>
        (x - C.PLAYER_HALF, x + C.PLAYER_HALF, y - C.PLAYER_HALF, y + C.PLAYER_HALF, z, z + C.PLAYER_HEIGHT);

    // 순간 베기: 보는 방향으로 NINJA_BLINK_DIST 만큼 (블록 앞까지, 상대가 있으면 그 바로 뒤까지) 순간이동하며 지나간 길의 상대를 벰.
    // 공중에서도 됨. 블록에 막히면 벽 차기: 위로 튀어 오름 + 작은 충격파
    public bool NinjaBlink(Player p)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double fromX = p.x, fromY = p.y, fromZ = p.z;
        double best = 0;
        bool blocked = false;
        for (double d = 0.1; d <= C.NINJA_BLINK_DIST + 1e-9; d += 0.1)
        {
            var b = AabbAt(p.x + fx * d, p.y + fy * d, p.z + 0.05); // 발이 바닥에 살짝 안 걸리게
            if (OverlappingSolid(b).Count > 0)
            {
                blocked = true;
                break;
            }
            best = d;
        }
        if (best < 0.3 && !blocked) return false;
        // 길 위의 상대: 지나갈 선분에서 NINJA_SLASH_WIDTH 안. 처음 만나는 상대 바로 뒤(NINJA_BLINK_BEHIND)에서 멈춤
        double? OnPath(Player t, double len)
        {
            double along = (t.x - fromX) * fx + (t.y - fromY) * fy;
            return along >= 0 && along <= len && JsMath.Hypot(fromX + fx * along - t.x, fromY + fy * along - t.y) <= C.NINJA_SLASH_WIDTH ? along : null;
        }
        double wall = best;
        foreach (var t in Players())
        {
            if (!Foe(p, t) || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            var along = OnPath(t, best);
            if (along != null) best = Math.Min(best, along.Value + C.NINJA_BLINK_BEHIND);
        }
        p.x += fx * best;
        p.y += fy * best;
        Emit(o =>
        {
            o.P("type", "blink").P("who", p.id);
            o.Key("from").Obj().P("x", fromX).P("y", fromY).P("z", fromZ).EndObj();
            o.Key("to").Obj().P("x", p.x).P("y", p.y).P("z", p.z).EndObj();
        });
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t) || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            if (OnPath(t, best) == null) continue;
            bool hit = ApplyKnockback(t, fx, fy, C.NINJA_SLASH_KB_SPEED, C.NINJA_SLASH_KB_UP, C.NINJA_SLASH_STUN_MS, C.NINJA_SLASH_DAMAGE, new Src(p.id, "slash"));
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "slash").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
        }
        bool kicked = blocked && best >= wall - 1e-9; // 상대 뒤에서 먼저 멈췄으면 벽 차기 아님
        Log($"  [스킬] {p.name} 순간 베기 {JsNumber.ToFixed(best, 1)}칸{(n != 0 ? $" ({n}명)" : "")}{(kicked ? " 벽 차기" : "")}");
        if (kicked) NinjaWallKick(p, fx, fy);
        return true;
    }

    // 벽 차기: 블록을 차고 위로 + 둘레 상대를 바깥으로 (피해 작게, 넉백만)
    public void NinjaWallKick(Player p, double fx, double fy)
    {
        p.vz = C.NINJA_WALLKICK_UP;
        p.grounded = false;
        p.kbx = 0;
        p.kby = 0;
        var hits = new List<string>();
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.NINJA_WALLKICK_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : -fx, d > 0.05 ? dy : -fy, C.NINJA_WALLKICK_KB_SPEED, C.NINJA_WALLKICK_KB_UP, C.NINJA_WALLKICK_STUN_MS, C.NINJA_WALLKICK_DAMAGE, new Src(p.id, "wallkick"));
            Emit(o => o.P("type", "hit").P("kind", "wallkick").P("by", p.id).P("target", t.id).P("ok", hit));
            if (hit) hits.Add(t.name);
        }
        Emit(o => o.P("type", "wallKick").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).Key("dir").Obj().P("x", fx).P("y", fy).EndObj());
        Log($"  [스킬] {p.name} 벽 차기{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
    }

    // R 강화: NINJA_EMPOWER_MS 동안 지상 1~3타·공중 평타가 표창 2연발
    public void NinjaEmpower(Player p)
    {
        p.empowerUntil = time + C.NINJA_EMPOWER_MS;
        Emit(o => o.P("type", "empower").P("who", p.id).P("ms", C.NINJA_EMPOWER_MS));
        Log($"  [필살] {p.name} 강화 ({JsNumber.ToJs(C.NINJA_EMPOWER_MS / 1000)}초 표창)");
    }

    // 패시브: 공중에서 떨어지는 블록에 닿으면 (밟거나 옆면) 공중 점프 회복. 한 블록에 한 번
    public void NinjaTouch(Player p)
    {
        if (p.grounded && !StandingOnPiece(p))
        {
            p.touchPiece = 0;
            return;
        }
        var box = Aabb(p);
        const double pad = 0.06;
        foreach (var pc in pieces)
        {
            if (pc.phase != "falling" || pc.id == p.touchPiece) continue;
            bool touch = PieceWorldCells(pc).Any(c => c[0] < box.x1 + pad && c[0] + 1 > box.x0 - pad && c[1] < box.y1 + pad && c[1] + 1 > box.y0 - pad && c[2] < box.z1 + pad && c[2] + 1 > box.z0 - pad);
            if (!touch) continue;
            p.touchPiece = pc.id;
            p.airJumps = C.AIR_JUMPS;
            Emit(o => o.P("type", "ninjaTouch").P("who", p.id).P("piece", pc.id));
            return;
        }
    }

    public bool StandingOnPiece(Player p)
    {
        int z = (int)JsMath.Round(p.z) - 1;
        for (int x = (int)Math.Floor(p.x - C.PLAYER_HALF); x <= Math.Floor(p.x + C.PLAYER_HALF); x++)
            for (int y = (int)Math.Floor(p.y - C.PLAYER_HALF); y <= Math.Floor(p.y + C.PLAYER_HALF); y++)
                if (pieceCells.ContainsKey(CellKey(x, y, z))) return true;
        return false;
    }
}
