using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-hook.js — 갈고리 (S3)
public sealed partial class Game
{
    // 갈고리가 닿은 블록 칸 { x, y, z, d(수평 거리) }
    public sealed record HookHit(int x, int y, int z, double d);

    // 보는 방향 HOOK_RANGE 안 (반각 HOOK_HALF_ANGLE_DEG, 높이 차 2칸 안) 가장 가까운 상대
    Player? HookTarget(Player p)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(C.HOOK_HALF_ANGLE_DEG * Math.PI / 180);
        Player? best = null;
        double bd = double.PositiveInfinity;
        foreach (var t in Players())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.HOOK_RANGE || d < 0.3 || Math.Abs(t.z - p.z) > 2 || (dx * fx + dy * fy) / d < cosHalf) continue;
            if (d < bd)
            {
                bd = d;
                best = t;
            }
        }
        return best;
    }

    // 갈고리가 닿는 첫 블록 (격자 칸 또는 떨어지는 블록, 필드 바닥은 아님). 조준 방향(yaw + pitch) 3D 직선을 눈 높이에서 HOOK_RANGE 만큼.
    // 놓치면 보조로 발 층·한 칸 위 층을 수평으로. skip(x, y, z): 이 칸은 없는 셈 (R: 조종 중인 블록)
    public HookHit? HookRayBlock(Player p, double yaw, double pitch, Func<int, int, int, bool>? skip = null)
    {
        bool Solid(int x, int y, int z) => z >= 0 && z < H && ((InXY(x, y) && grid[Idx(x, y, z)] != 0) || pieceCells.ContainsKey(CellKey(x, y, z))) && !(skip != null && skip(x, y, z));
        double cp = JsMath.Cos(pitch);
        double dxr = JsMath.Cos(yaw) * cp, dyr = JsMath.Sin(yaw) * cp, dzr = JsMath.Sin(pitch);
        double ex = p.x, ey = p.y, ez = p.z + C.EYE_HEIGHT;
        for (double d = 0; d <= C.HOOK_RANGE + 1e-9; d += 0.05)
        {
            double px = ex + dxr * d, py = ey + dyr * d, pz = ez + dzr * d;
            if (pz < 0 && InXY((int)Math.Floor(px), (int)Math.Floor(py))) break; // 필드 바닥에 닿음
            int x = (int)Math.Floor(px), y = (int)Math.Floor(py), z = (int)Math.Floor(pz);
            if (Solid(x, y, z)) return new HookHit(x, y, z, JsMath.Hypot(px - p.x, py - p.y));
        }
        double fx = JsMath.Cos(yaw), fy = JsMath.Sin(yaw);
        for (double d = C.PLAYER_HALF; d <= C.HOOK_RANGE + 1e-9; d += 0.1)
        {
            int x = (int)Math.Floor(p.x + fx * d), y = (int)Math.Floor(p.y + fy * d);
            int z0 = (int)Math.Floor(p.z + 0.05);
            foreach (var z in new[] { z0, z0 + 1 }) if (Solid(x, y, z)) return new HookHit(x, y, z, d);
        }
        return null;
    }

    static double Pitch0(Player p) => double.IsNaN(p.pitch) ? 0 : p.pitch; // JS p.pitch || 0

    // R 보조 판정: 보는 방향 반각 HOOK_GRAB_CONE_DEG, 수평 HOOK_RANGE 안, 발 층 -1 ~ +2 층의 블록 중 가장 가까운 것 (같으면 높은 칸)
    HookHit? HookConeBlock(Player p, Func<int, int, int, bool>? skip = null)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(C.HOOK_GRAB_CONE_DEG * Math.PI / 180);
        int z0 = (int)Math.Floor(p.z + 0.05);
        HookHit? best = null;
        int R = (int)Math.Ceiling(C.HOOK_RANGE) + 1;
        for (int x = (int)Math.Floor(p.x) - R; x <= (int)Math.Floor(p.x) + R; x++)
        {
            for (int y = (int)Math.Floor(p.y) - R; y <= (int)Math.Floor(p.y) + R; y++)
            {
                double dx = x + 0.5 - p.x, dy = y + 0.5 - p.y;
                double d = JsMath.Hypot(dx, dy);
                if (d > C.HOOK_RANGE + 0.5 || d < 0.5 || (dx * fx + dy * fy) / d < cosHalf) continue;
                for (int z = Math.Max(0, z0 - 1); z <= Math.Min(H - 1, z0 + 2); z++)
                {
                    if (!((InXY(x, y) && grid[Idx(x, y, z)] != 0) || pieceCells.ContainsKey(CellKey(x, y, z))) || (skip != null && skip(x, y, z))) continue;
                    if (best == null || d < best.d - 1e-9 || (Math.Abs(d - best.d) < 1e-9 && z > best.z)) best = new HookHit(x, y, z, d);
                }
            }
        }
        return best;
    }

    // 상대를 내 앞 HOOK_PULL_TO 거리까지 끌어옴 (블록에 막히면 거기까지). 콤보 한 타 (넉백 없이 경직 + 피해)
    bool PullTo(Player p, Player t, double stunMs, double gain, string kind)
    {
        if (Invulnerable(t)) return false;
        double dx = p.x - t.x, dy = p.y - t.y;
        double d = JsMath.Hypot(dx, dy);
        if (d == 0) d = 1;
        double go = Math.Max(0, d - C.HOOK_PULL_TO);
        MoveAxis(t, 0, dx / d * go);
        MoveAxis(t, 1, dy / d * go);
        bool hit = ApplyKnockback(t, dx, dy, 0, 0, stunMs, gain, new Src(p.id, kind));
        t.kbx = 0;
        t.kby = 0;
        return hit;
    }

    // F: 갈고리를 던짐. 판정은 HOOK_FLY_MS 뒤 갈고리가 닿는 순간 (HookLand). 빗나가도 쿨타임
    bool HookPull(Player p)
    {
        p.hookFly = new Windup { at = time + C.HOOK_FLY_MS, yaw = p.yaw };
        Emit(o => o.P("type", "hookThrow").P("who", p.id).P("yaw", p.yaw).P("ms", C.HOOK_FLY_MS));
        return true;
    }

    // 갈고리가 닿는 순간: 던진 방향, 지금 내 위치에서 상대·블록 판정
    void HookLand(Player p)
    {
        double yaw = p.yaw;
        p.yaw = p.hookFly!.yaw;
        p.hookFly = null;
        HookResolve(p);
        p.yaw = yaw;
    }

    bool HookResolve(Player p)
    {
        var t = HookTarget(p);
        var block = HookRayBlock(p, p.yaw, Pitch0(p));
        double td = t != null ? JsMath.Hypot(t.x - p.x, t.y - p.y) : double.PositiveInfinity;
        if (block != null && block.d < td)
        {
            double go = Math.Max(0, block.d - C.PLAYER_HALF - 0.05);
            p.zipDir = new XY(JsMath.Cos(p.yaw), JsMath.Sin(p.yaw)); // 던진 방향
            p.zipUntil = time + go / C.HOOK_ZIP_SPEED * 1000;
            p.vz = Math.Max(p.vz, C.HOOK_ZIP_UP);
            p.grounded = false;
            p.kbx = 0;
            p.kby = 0;
            Emit(o => o.P("type", "hook").P("who", p.id).PNull("target").Key("block").Arr().Num(block.x).Num(block.y).Num(block.z).EndArr().P("yaw", p.yaw));
            Log($"  [스킬] {p.name} 갈고리 → 블록 ({block.x},{block.y},{block.z}) {JsNumber.ToFixed(go, 1)}칸 끌려감");
            return true;
        }
        Emit(o =>
        {
            o.P("type", "hook").P("who", p.id).Key("target");
            if (t != null) o.Num(t.id); else o.Null();
            o.PNull("block").P("yaw", p.yaw);
        });
        if (t == null)
        {
            Log($"  [스킬] {p.name} 갈고리 빗나감");
            return true; // 빗나가도 쿨타임
        }
        bool hit = PullTo(p, t, C.HOOK_STUN_MS, C.HOOK_DAMAGE, "hook");
        if (hit && !p.loaded)
        {
            p.loaded = true; // 끌어오면 장전
            Emit(o => o.P("type", "reload").P("who", p.id));
        }
        Log($"  [스킬] {p.name} 갈고리 → {t.name}{(hit ? $" ({t.name} {JsNumber.ToJs(t.damage)}%) 장전" : " 무적이라 무시")}");
        return true;
    }

    // game-util.js pieceCellValue: 떨어지는 블록 칸의 격자 값
    static byte PieceCellValue(Piece pc)
    {
        if (pc.ghostBy is int gb && gb != 0) return (byte)(Pieces.CELL.GHOST_BASE + pc.ghostColor);
        return pc.thrownBy is int tb && tb != 0 ? Pieces.CELL.THROWN : Pieces.CellOfShape(pc.shape);
    }

    // R 으로 뽑을 덩어리: 떨어지는 블록이면 통째로, 쌓인 블록이면 같은 블록 id·같은 색으로 6방향 이어진 칸 전부, 시작 지형·건축가 블록·id 없는 칸은 1칸
    (Piece? piece, List<GrabCell> cells) HookGroup(HookHit b)
    {
        long key = CellKey(b.x, b.y, b.z);
        if (pieceCells.TryGetValue(key, out int pid))
        {
            var pc = pieces.First(x => x.id == pid);
            byte pv = PieceCellValue(pc);
            return (pc, PieceWorldCells(pc).Select(c => new GrabCell { x = c[0], y = c[1], z = c[2], v = pv, meta = null }).ToList());
        }
        int i0 = Idx(b.x, b.y, b.z);
        byte v = grid[i0];
        int id = gridPiece[i0];
        var meta = bblocks.TryGetValue(key, out var bb) ? bb : null;
        if (id == 0 || meta != null || !(v == Pieces.CELL.THROWN || v >= Pieces.CELL.SHAPE_BASE)) return (null, new List<GrabCell> { new() { x = b.x, y = b.y, z = b.z, v = v, meta = meta } });
        var cells = new List<GrabCell>();
        var seen = new HashSet<long> { key };
        var stack = new List<int[]> { new[] { b.x, b.y, b.z } };
        while (stack.Count > 0)
        {
            var c = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            cells.Add(new GrabCell { x = c[0], y = c[1], z = c[2], v = v, meta = null });
            foreach (var dd in DIR6)
            {
                int nx = c[0] + dd[0], ny = c[1] + dd[1], nz = c[2] + dd[2];
                long k = CellKey(nx, ny, nz);
                if (seen.Contains(k) || !InXY(nx, ny) || nz < 0 || nz >= H) continue;
                seen.Add(k);
                int j = Idx(nx, ny, nz);
                if (grid[j] == v && gridPiece[j] == id) stack.Add(new[] { nx, ny, nz });
            }
        }
        return (null, cells);
    }

    // R 블록 내려찍기 1단계: 보는 방향 첫 블록의 덩어리를 뽑음 (격자에서 빠짐). 없으면 false (게이지 그대로)
    bool HookGrab(Player p)
    {
        bool Skip(int x, int y, int z) => ControlledCell(x, y, z); // 조종 중인 블록은 안 잡음
        var b = HookRayBlock(p, p.yaw, Pitch0(p), Skip) ?? HookConeBlock(p, Skip);
        if (b == null) return false;
        var (piece, cells) = HookGroup(b);
        if (piece != null) RemovePiece(piece);
        else
        {
            foreach (var c in cells)
            {
                grid[Idx(c.x, c.y, c.z)] = 0;
                if (c.meta != null) bblocks.Remove(CellKey(c.x, c.y, c.z));
            }
            GridChanged();
        }
        foreach (var pc in pieces.ToList()) UpdateLanding(pc);
        var meta = cells.Count == 1 ? cells[0].meta : null; // 건축가 블록은 속성 그대로 옮김
        p.grab = new Grab { at = time + C.HOOK_GRAB_MS, cells = cells, meta = meta, from = new double[] { b.x, b.y, b.z }, dir = new XY(JsMath.Cos(p.yaw), JsMath.Sin(p.yaw)) };
        Emit(o =>
        {
            o.P("type", "blockGrab").P("who", p.id).Key("from").Arr().Num(b.x).Num(b.y).Num(b.z).EndArr();
            WriteCells(o, "cells", cells.Select(c => new[] { c.x, c.y, c.z }));
            o.P("v", cells[0].v).P("ms", C.HOOK_GRAB_MS).P("builder", meta != null).P("sky", piece != null && piece.sky);
        });
        Log($"  [필살] {p.name} 블록 뽑기 ({b.x},{b.y},{b.z}){(cells.Count > 1 ? $" {cells.Count}칸" : "")}{(piece != null ? (piece.sky ? " 하늘 블록" : " 떨어지는 블록") : "")}");
        return true;
    }

    // 조종 중인 블록의 칸인가
    bool ControlledCell(int x, int y, int z)
    {
        if (!pieceCells.TryGetValue(CellKey(x, y, z), out int id)) return false;
        var pc = pieces.FirstOrDefault(q => q.id == id);
        return pc != null && pc.controller != null;
    }

    void HookSlam(Player p)
    {
        var g = p.grab!;
        p.grab = null;
        var dir = g.dir!;
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t) || Math.Abs(t.z - p.z) > 2) continue;
            double along = (t.x - p.x) * dir.x + (t.y - p.y) * dir.y;
            double side = Math.Abs((t.x - p.x) * dir.y - (t.y - p.y) * dir.x);
            if (along < 0.3 || along > C.HOOK_SLAM_LEN + 0.5 || side > C.HOOK_SLAM_WIDTH) continue;
            bool hit = ApplyKnockback(t, dir.x, dir.y, C.HOOK_SLAM_KB_SPEED, C.HOOK_SLAM_KB_UP, C.HOOK_SLAM_STUN_MS, C.HOOK_SLAM_DAMAGE, new Src(p.id, "blockslam"), true);
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "blockslam").P("by", p.id).P("target", t.id).P("ok", hit));
        }
        // 덩어리를 뽑은 모양 그대로 끝 칸을 중심으로, 모양 칸 아래 가장 높은 기둥 위에 박음. 필드 밖·떨어지는 블록과 겹치는 칸은 버림
        int ex = (int)Math.Floor(p.x + dir.x * C.HOOK_SLAM_LEN), ey = (int)Math.Floor(p.y + dir.y * C.HOOK_SLAM_LEN);
        int cx = (int)JsMath.Round(g.cells.Aggregate(0.0, (a, c) => a + c.x) / g.cells.Count - 0.5);
        int cy = (int)JsMath.Round(g.cells.Aggregate(0.0, (a, c) => a + c.y) / g.cells.Count - 0.5);
        var at = g.cells.Select(c => new GrabCell { x = ex + c.x - cx, y = ey + c.y - cy, z = c.z, v = c.v, meta = c.meta }).Where(c => InXY(c.x, c.y)).ToList();
        int z = 0;
        foreach (var c in at) z = Math.Max(z, ColumnTop(c.x, c.y));
        var placed = z < H ? at.Where(c => !pieceCells.ContainsKey(CellKey(c.x, c.y, z))).ToList() : new List<GrabCell>();
        int id = placed.Count > 1 ? ++pieceCounter : 0; // 다시 덩어리로 잡히게 새 id (1칸은 id 없음)
        foreach (var c in placed)
        {
            int i = Idx(c.x, c.y, z);
            grid[i] = c.v;
            gridPiece[i] = id;
            if (c.meta != null) bblocks[CellKey(c.x, c.y, z)] = new BBlock { x = c.x, y = c.y, z = z, owner = c.meta.owner, kind = c.meta.kind, group = c.meta.group, expiresAt = c.meta.expiresAt, born = c.meta.born };
        }
        var cells = placed.Select(c => new[] { c.x, c.y, z }).ToList();
        if (cells.Count > 0)
        {
            landed["hook"]++;
            GridChanged();
            foreach (var pc in pieces.ToList()) UpdateLanding(pc);
            // 박힌 칸 사람은 압사 대신 밀쳐냄 (내려찍은 방향으로 덩어리 밖, 막히면 블록 위로)
            foreach (var t in Players().ToList())
            {
                if (!OnField(t) || !cells.Any(c => OverlapsCell(t, c[0], c[1], z))) continue;
                XY? moved = null;
                for (double d = 0.1; d <= 4.5 && moved == null; d += 0.1)
                {
                    double mx = t.x + dir.x * d, my = t.y + dir.y * d;
                    if (OverlappingSolid(AabbAt(mx, my, t.z)).Count == 0) moved = new XY(mx, my);
                }
                if (moved != null) (t.x, t.y) = (moved.x, moved.y);
                else EjectFromBlocks(t);
            }
        }
        Emit(o =>
        {
            o.P("type", "blockSlam").P("who", p.id).Key("dir").Obj().P("x", dir.x).P("y", dir.y).EndObj().P("len", C.HOOK_SLAM_LEN).Key("cell");
            if (cells.Count > 0) o.Arr().Num(cells[0][0]).Num(cells[0][1]).Num(cells[0][2]).EndArr(); else o.Null();
            WriteCells(o, "cells", cells);
            o.P("builder", g.meta != null);
        });
        string where = cells.Count == 0 ? " → 필드 밖으로 사라짐" : cells.Count == 1 ? $" → ({string.Join(",", cells[0])}) 박힘" : $" → {cells.Count}칸 박힘 ({string.Join(",", cells[0])})";
        Log($"  [필살] {p.name} 블록 내려찍기 ({n}명){where}");
        ClearLayers();
    }

    // 뽑는 중에 맞음: 덩어리를 제자리로 (빈 칸만)
    public void HookGrabDrop(Player p)
    {
        var g = p.grab!;
        p.grab = null;
        int id = g.cells.Count > 1 ? ++pieceCounter : 0;
        foreach (var c in g.cells)
        {
            if (c.z >= H || grid[Idx(c.x, c.y, c.z)] != 0 || pieceCells.ContainsKey(CellKey(c.x, c.y, c.z))) continue;
            grid[Idx(c.x, c.y, c.z)] = c.v;
            gridPiece[Idx(c.x, c.y, c.z)] = id;
            if (c.meta != null) bblocks[CellKey(c.x, c.y, c.z)] = new BBlock { x = c.x, y = c.y, z = c.z, owner = c.meta.owner, kind = c.meta.kind, group = c.meta.group, expiresAt = c.meta.expiresAt, born = c.meta.born };
        }
        GridChanged();
        foreach (var pc in pieces.ToList()) UpdateLanding(pc);
    }
}
