using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-tank.js — 탱크 (S3)
public sealed partial class Game
{
    public int quakeCounter; // 솟는 땅 id (quakeRise·quakeFall 짝)

    // 돌진: TANK_CHARGE_MS 동안 보는 방향으로 빠르게. 처음 부딪힌 상대를 치고 멈춤 (UpdateCombat)
    bool TankCharge(Player p)
    {
        p.chargeUntil = time + C.TANK_CHARGE_MS;
        p.chargeDir = new XY(JsMath.Cos(p.yaw), JsMath.Sin(p.yaw));
        Emit(o => o.P("type", "charge").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", p.yaw));
        Log($"  [스킬] {p.name} 돌진");
        return true;
    }

    void ChargeHit(Player p)
    {
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t) || JsMath.Hypot(t.x - p.x, t.y - p.y) > C.TANK_CHARGE_HIT_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            p.chargeUntil = 0;
            p.kbx = 0;
            p.kby = 0;
            bool hit = ApplyKnockback(t, p.chargeDir!.x, p.chargeDir.y, C.TANK_CHARGE_KB_SPEED, C.TANK_CHARGE_KB_UP, C.TANK_CHARGE_STUN_MS, C.TANK_CHARGE_DAMAGE, new Src(p.id, "charge"));
            Emit(o => o.P("type", "hit").P("kind", "charge").P("by", p.id).P("target", t.id).P("ok", hit));
            Log($"  [돌진] {p.name} → {t.name} {(hit ? $"({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}");
            return;
        }
    }

    // 내려찍기: 떠올랐다가 TANK_SLAM_WINDUP_MS 뒤 쾅 (바닥에 범위 예고). 주변을 위로 띄움
    void TankSlamStart(Player p)
    {
        p.slamAt = time + C.TANK_SLAM_WINDUP_MS;
        p.vz = C.TANK_SLAM_JUMP;
        p.grounded = false;
        Emit(o => o.P("type", "slamWarn").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.TANK_SLAM_RANGE).P("ms", C.TANK_SLAM_WINDUP_MS));
        Log($"  [필살] {p.name} 내려찍기 준비");
    }

    void TankSlam(Player p)
    {
        p.slamAt = 0;
        p.vz = Math.Min(p.vz, -C.TANK_SLAM_JUMP); // 쾅 내려옴
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            if (JsMath.Hypot(dx, dy) > C.TANK_SLAM_RANGE || Math.Abs(t.z - p.z) > 2.5) continue;
            double a = rng() * Math.PI * 2; // 겹쳐 서 있으면 방향이 없어서 무작위
            double len = JsMath.Hypot(dx, dy);
            bool hit = ApplyKnockback(t, len > 0.05 ? dx : JsMath.Cos(a), len > 0.05 ? dy : JsMath.Sin(a), C.TANK_SLAM_KB_SPEED, C.TANK_SLAM_KB_UP, C.TANK_SLAM_STUN_MS, C.TANK_SLAM_DAMAGE, new Src(p.id, "slam"), true);
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "slam").P("by", p.id).P("target", t.id).P("ok", hit));
        }
        Emit(o => o.P("type", "slam").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.TANK_SLAM_RANGE));
        int lifted = TankRing(p);
        Log($"  [필살] {p.name} 내려찍기 ({n}명{(lifted != 0 ? $", 솟는 땅 {lifted}명" : "")})");
    }

    // R 바깥 고리: 충격파 바깥 TANK_RING_WIDTH 칸 고리의 기둥 꼭대기에 블록 1층이 솟아 위 사람을 띄움 → TANK_RING_MS 뒤 가라앉음
    int TankRing(Player p)
    {
        double r0 = C.TANK_SLAM_RANGE, r1 = r0 + C.TANK_RING_WIDTH;
        var cells = new List<int[]>();
        for (int x = (int)Math.Floor(p.x - r1); x <= Math.Floor(p.x + r1); x++)
        {
            for (int y = (int)Math.Floor(p.y - r1); y <= Math.Floor(p.y + r1); y++)
            {
                double d = JsMath.Hypot(x + 0.5 - p.x, y + 0.5 - p.y);
                if (d <= r0 || d > r1 || !InXY(x, y)) continue;
                int z = ColumnTop(x, y);
                if (z >= H || Math.Abs(z - p.z) > 2.5 || pieceCells.ContainsKey(CellKey(x, y, z))) continue;
                grid[Idx(x, y, z)] = Pieces.CELL.BUILD;
                cells.Add(new[] { x, y, z });
            }
        }
        if (cells.Count == 0) return 0;
        GridChanged();
        int qid = ++quakeCounter;
        quakes.Add(new Quake { id = qid, cells = cells, at = time + C.TANK_RING_MS });
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (!OnField(t) || !cells.Any(c => OverlapsCell(t, c[0], c[1], c[2]))) continue;
            EjectFromBlocks(t);
            if (!Foe(p, t)) continue;
            bool hit = ApplyKnockback(t, t.x - p.x, t.y - p.y, 0, C.TANK_RING_UP, C.TANK_RING_STUN_MS, 0, new Src(p.id, "slam"), true);
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "quake").P("by", p.id).P("target", t.id).P("ok", hit));
        }
        Emit(o =>
        {
            o.P("type", "quakeRise").P("id", qid).P("who", p.id);
            WriteCells(o, "cells", cells);
            o.P("ms", C.TANK_RING_MS);
        });
        return n;
    }

    // 솟은 땅이 가라앉음 (그 사이 다른 블록이 덮어쓴 칸은 그대로)
    void UpdateQuakes()
    {
        foreach (var q in quakes.ToList())
        {
            if (time < q.at) continue;
            quakes = quakes.Where(x => x != q).ToList();
            var gone = q.cells.Where(c => grid[Idx(c[0], c[1], c[2])] == Pieces.CELL.BUILD && !bblocks.ContainsKey(CellKey(c[0], c[1], c[2]))).ToList();
            foreach (var c in gone) grid[Idx(c[0], c[1], c[2])] = 0;
            if (gone.Count > 0) GridChanged();
            Emit(o =>
            {
                o.P("type", "quakeFall").P("id", q.id);
                WriteCells(o, "gone", gone);
                WriteCells(o, "cells", gone); // 예전 이름 (gone 과 같음)
            });
        }
    }

    // [[x, y, z], …] 칸 목록
    static void WriteCells(JsonOut o, string key, IEnumerable<int[]> cells)
    {
        o.Key(key).Arr();
        foreach (var c in cells)
        {
            o.Arr();
            foreach (var v in c) o.Num(v);
            o.EndArr();
        }
        o.EndArr();
    }
}
