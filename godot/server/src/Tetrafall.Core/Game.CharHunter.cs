using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-hunter.js — 사냥꾼 (S1: 스냅샷이 쓰는 부분. 나머지는 S3)
public sealed partial class Game
{
    // R 게이지 필요량 (사냥꾼은 HUNTER_ULT_MULT 배)
    public double UltMax(Player? p) => C.ULT_MAX * (p != null && p.@char == "hunter" ? C.HUNTER_ULT_MULT : 1);

    public double MarkOf(Player p, Player t) => t.marks.TryGetValue(p.id, out var m) ? m.n : 0;

    public bool LineBlocked(Player p, Player t)
    {
        double ax = p.x, ay = p.y, az = p.z + C.EYE_HEIGHT;
        double bx = t.x, by = t.y, bz = t.z + C.PLAYER_HEIGHT * 0.6;
        double len = JsMath.Hypot(bx - ax, by - ay, bz - az);
        for (double d = 0.3; d < len - 0.3; d += 0.1)
        {
            double k = d / len;
            if (SolidAt((int)Math.Floor(ax + (bx - ax) * k), (int)Math.Floor(ay + (by - ay) * k), (int)Math.Floor(az + (bz - az) * k))) return true;
        }
        return false;
    }

    // R 대상: 보는 방향 HUNTER_SHOT_ANGLE_DEG·HUNTER_SHOT_RANGE 안 내 표식이 있는 상대 (시선 검사는 따로)
    public List<Player> ShotTargets(Player p)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(((C.HUNTER_SHOT_ANGLE_DEG / 2) * Math.PI) / 180);
        return Players().Where(t =>
        {
            if (!Foe(p, t) || MarkOf(p, t) == 0) return false;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            return d <= C.HUNTER_SHOT_RANGE && (d < EPS || (dx * fx + dy * fy) / d >= cosHalf);
        }).ToList();
    }
}
