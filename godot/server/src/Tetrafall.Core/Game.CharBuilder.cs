using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-builder.js — 건축가 (S3). 건축가 블록: 격자에는 CELL.BUILD, 주인·종류·묶음·수명은 bblocks 에. 망치로 치면 폭발
public sealed partial class Game
{
    static int Sign(double v) => v > 0 ? 1 : v < 0 ? -1 : 0; // JS Math.sign (±0 은 0)

    // 지상 F: 솟는 벽 — 바로 앞(네 방향으로 맞춤) 줄에 가로 BUILDER_WALL_WIDTH × BUILDER_WALL_HEIGHT. 예고 → BUILDER_WALL_WARN_MS 뒤 솟음
    // 공중 F: 발판
    bool BuilderWall(Player p)
    {
        if (!p.grounded) return BuilderPad(p);
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        int[] along = Math.Abs(fx) >= Math.Abs(fy) ? new[] { Sign(fx), 0 } : new[] { 0, Sign(fy) };
        int[] side = { -along[1], along[0] };
        int cx = (int)Math.Floor(p.x) + along[0], cy = (int)Math.Floor(p.y) + along[1];
        int z0 = (int)Math.Max(0, JsMath.Round(p.z));
        int half = (int)Math.Floor(C.BUILDER_WALL_WIDTH / 2);
        var cells = new List<int[]>();
        for (int i = -half; i <= half; i++)
        {
            int x = cx + side[0] * i, y = cy + side[1] * i;
            if (!InXY(x, y) || grid[Idx(x, y, z0)] != 0) continue;
            for (int h = 0; h < C.BUILDER_WALL_HEIGHT; h++) if (z0 + h < H) cells.Add(new[] { x, y, z0 + h });
        }
        if (cells.Count == 0) return false;
        p.wallAt = time + C.BUILDER_WALL_WARN_MS;
        p.wallCells = cells;
        Emit(o =>
        {
            o.P("type", "wallWarn").P("who", p.id);
            WriteCells(o, "cells", cells);
            o.P("ms", C.BUILDER_WALL_WARN_MS);
        });
        Log($"  [스킬] {p.name} 솟는 벽 준비");
        return true;
    }

    void BuilderWallRise(Player p)
    {
        var cells = p.wallCells!;
        p.wallAt = 0;
        p.wallCells = null;
        int g = ++bgroup;
        // 예고 동안 건축가가 벽 칸으로 걸어 들어갔으면 그 칸은 안 솟음
        var placed = cells.Where(c => !OverlapsCell(p, c[0], c[1], c[2]) && PlaceBBlock(p, c[0], c[1], c[2], "wall", g)).ToList();
        if (placed.Count == 0) return;
        GridChanged();
        var launched = new List<int>();
        foreach (var t in Players().ToList())
        {
            if (!OnField(t) || !placed.Any(c => OverlapsCell(t, c[0], c[1], c[2]))) continue;
            EjectFromBlocks(t);
            if (!Foe(p, t) || launched.Contains(t.id)) continue;
            launched.Add(t.id);
            bool hit = ApplyKnockback(t, JsMath.Cos(p.yaw), JsMath.Sin(p.yaw), 0, C.BUILDER_WALL_KB_UP, C.BUILDER_WALL_STUN_MS, C.BUILDER_WALL_DAMAGE, new Src(p.id, "wall"));
            Emit(o => o.P("type", "hit").P("kind", "wall").P("by", p.id).P("target", t.id).P("ok", hit));
        }
        Emit(o =>
        {
            o.P("type", "wallRise").P("who", p.id);
            WriteCells(o, "cells", placed);
        });
        Emit(o =>
        {
            o.P("type", "bblock").P("who", p.id).P("kind", "wall").P("group", g);
            WriteCells(o, "cells", placed);
            o.P("ms", C.BUILDER_BLOCK_MS);
        });
        Log($"  [스킬] {p.name} 솟는 벽 ({placed.Count}칸{(launched.Count > 0 ? $", {launched.Count}명 띄움" : "")})");
        ClearLayers();
    }

    // 공중 F: 발밑으로 BUILDER_PAD_HEIGHT 칸 기둥을 세우고 나는 그 위에 섬. 한 칸도 못 놓으면 위로 부스트 (복귀기)
    bool BuilderPad(Player p)
    {
        int x = (int)Math.Floor(p.x), y = (int)Math.Floor(p.y);
        int top = (int)Math.Floor(p.z); // 서게 될 높이 (발밑 칸 윗면)
        int g = ++bgroup;
        var cells = new List<int[]>();
        for (int k = 1; k <= C.BUILDER_PAD_HEIGHT; k++)
        {
            int z = top - k;
            if (!InXY(x, y) || z < 0 || grid[Idx(x, y, z)] != 0 || pieceCells.ContainsKey(CellKey(x, y, z))) break;
            if (Players().Any(o => o != p && OnField(o) && OverlapsCell(o, x, y, z))) break;
            cells.Add(new[] { x, y, z });
        }
        var placed = cells.Where(c => PlaceBBlock(p, c[0], c[1], c[2], "pad", g)).ToList();
        if (placed.Count > 0)
        {
            GridChanged();
            Emit(o =>
            {
                o.P("type", "bblock").P("who", p.id).P("kind", "pad").P("group", g);
                WriteCells(o, "cells", placed);
                o.P("ms", C.BUILDER_BLOCK_MS);
            });
            p.z = top;
            p.vz = 0;
            p.grounded = true;
        }
        else
        {
            p.vz = C.BUILDER_PAD_BOOST;
            p.grounded = false;
        }
        Emit(o =>
        {
            o.P("type", "padBoost").P("who", p.id).Key("cell");
            if (placed.Count > 0) o.Arr().Num(placed[0][0]).Num(placed[0][1]).Num(placed[0][2]).EndArr(); else o.Null();
            WriteCells(o, "cells", placed);
            o.P("stand", placed.Count > 0);
        });
        Log($"  [스킬] {p.name} 발판{(placed.Count > 0 ? $" 기둥 {placed.Count}칸 ({x},{y},{placed[^1][2]}~{placed[0][2]})" : " (칸 없이 부스트)")}");
        return true;
    }

    // 건축가 블록 놓기 (빈 칸일 때만). 놓았으면 true
    bool PlaceBBlock(Player p, int x, int y, int z, string kind, int group)
    {
        if (!InXY(x, y) || z < 0 || z >= H || grid[Idx(x, y, z)] != 0 || pieceCells.ContainsKey(CellKey(x, y, z))) return false;
        grid[Idx(x, y, z)] = Pieces.CELL.BUILD;
        bblocks[CellKey(x, y, z)] = new BBlock { x = x, y = y, z = z, owner = p.id, kind = kind, group = group, expiresAt = time + C.BUILDER_BLOCK_MS, born = time };
        landed["builder"]++;
        return true;
    }

    void RemoveBBlock(BBlock b, string why)
    {
        bblocks.Remove(CellKey(b.x, b.y, b.z));
        if (grid[Idx(b.x, b.y, b.z)] == Pieces.CELL.BUILD) grid[Idx(b.x, b.y, b.z)] = 0;
        GridChanged();
        if (why != "blast") Emit(o =>
        {
            o.P("type", "bblockGone");
            WriteCells(o, "cells", new[] { new[] { b.x, b.y, b.z } });
            o.P("why", why);
        });
    }

    // R 대폭발: 앞 BUILDER_BIG_GAP 칸 띄우고 BUILDER_BIG_SIZE × BUILDER_BIG_SIZE 기둥 꼭대기에서 블록이 솟음 → BUILDER_BIG_FUSE_MS 뒤 자동 대폭발
    bool BuilderBigBomb(Player p)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        int[] along = Math.Abs(fx) >= Math.Abs(fy) ? new[] { Sign(fx), 0 } : new[] { 0, Sign(fy) };
        int[] side = { -along[1], along[0] };
        int half = (int)Math.Floor(C.BUILDER_BIG_SIZE / 2);
        int g = ++bgroup;
        var placed = new List<int[]>();
        for (int a = 0; a < C.BUILDER_BIG_SIZE; a++)
        {
            for (int i = -half; i <= half; i++)
            {
                int x = (int)Math.Floor(p.x) + along[0] * (int)(C.BUILDER_BIG_GAP + 1 + a) + side[0] * i;
                int y = (int)Math.Floor(p.y) + along[1] * (int)(C.BUILDER_BIG_GAP + 1 + a) + side[1] * i;
                if (!InXY(x, y)) continue;
                int z = ColumnTop(x, y);
                if (PlaceBBlock(p, x, y, z, "big", g)) placed.Add(new[] { x, y, z });
            }
        }
        if (placed.Count == 0) return false;
        GridChanged();
        var launched = new List<int>();
        foreach (var t in Players().ToList())
        {
            if (!OnField(t) || !placed.Any(c => OverlapsCell(t, c[0], c[1], c[2]))) continue;
            EjectFromBlocks(t);
            if (!Foe(p, t) || launched.Contains(t.id)) continue;
            launched.Add(t.id);
            bool hit = ApplyKnockback(t, along[0], along[1], 0, C.BUILDER_BIG_RISE_UP, C.BUILDER_BIG_RISE_STUN_MS, 0, new Src(p.id, "bigbomb"));
            Emit(o => o.P("type", "hit").P("kind", "bigbomb").P("by", p.id).P("target", t.id).P("ok", hit));
        }
        bigBombs.Add(new BigBomb { owner = p.id, group = g, at = time + C.BUILDER_BIG_FUSE_MS, dir = new XY(along[0], along[1]) });
        Emit(o =>
        {
            o.P("type", "bigBombWarn").P("who", p.id);
            WriteCells(o, "cells", placed);
            o.P("ms", C.BUILDER_BIG_FUSE_MS).P("group", g);
        });
        Log($"  [필살] {p.name} 대폭발 준비 ({placed.Count}칸{(launched.Count > 0 ? $", {launched.Count}명 띄움" : "")})");
        ClearLayers();
        return true;
    }

    // 대폭발 터짐 (자동 또는 망치). 범위 안 사람 한 번씩 dir 쪽으로 날림, 범위 안 내 블록(벽·3타)도 같이 터짐
    void ExplodeBig(BigBomb bomb, XY dir)
    {
        bigBombs = bigBombs.Where(b => b != bomb).ToList();
        var p = GetPlayer(bomb.owner);
        var cells = bblocks.Values.Where(b => b.group == bomb.group).ToList();
        foreach (var b in cells) RemoveBBlock(b, "blast");
        if (cells.Count == 0) return;
        HoleUnder(cells);
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (p == null || !Foe(p, t) || !cells.Any(b => NearCell(t, b, C.BUILDER_BIG_RANGE))) continue;
            bool hit = ApplyKnockback(t, dir.x, dir.y, C.BUILDER_BIG_KB_SPEED, C.BUILDER_BIG_KB_UP, C.BUILDER_BIG_STUN_MS, C.BUILDER_BIG_DAMAGE, new Src(bomb.owner, "bigbomb"), true);
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "bigbomb").P("by", bomb.owner).P("target", t.id).P("ok", hit));
        }
        Emit(o =>
        {
            o.P("type", "bigBomb").P("who", bomb.owner);
            WriteCells(o, "cells", cells.Select(b => new[] { b.x, b.y, b.z }));
            o.Key("dir").Obj().P("x", dir.x).P("y", dir.y).EndObj();
        });
        // 범위 안 내 블록도 같이 (묶음째)
        var near = bblocks.Values.Where(b => b.owner == bomb.owner && b.kind != "big" && cells.Any(c => Math.Abs(c.x - b.x) <= 1 && Math.Abs(c.y - b.y) <= 1 && Math.Abs(c.z - b.z) <= 1)).ToList();
        int also = 0;
        var done = new HashSet<int>();
        foreach (var b in near)
        {
            if (!bblocks.ContainsKey(CellKey(b.x, b.y, b.z)) || done.Contains(b.group)) continue;
            done.Add(b.group);
            also += Blast(b, dir);
        }
        Log($"  [필살] {(p != null ? p.name : "?")} 대폭발 ({n}명{(also != 0 ? $", 같이 터진 블록 {also}칸" : "")})");
    }

    // 사람 몸(가로 상자)이 칸 가장자리에서 r 안, 높이 차 BUILDER_BLAST_HEIGHT 안
    static bool NearCell(Player t, BBlock b, double r)
    {
        double gx = Math.Max(Math.Max(b.x - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - (b.x + 1)), 0);
        double gy = Math.Max(Math.Max(b.y - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - (b.y + 1)), 0);
        return JsMath.Hypot(gx, gy) <= r && Math.Abs(t.z - b.z) <= C.BUILDER_BLAST_HEIGHT;
    }

    // 망치(평타) 판정이 닿은 내 블록을 터뜨림. 터뜨렸으면 true
    bool HammerBlocks(Player p, double range, double cosHalf)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        var hitGroups = new HashSet<int>();
        var targets = new List<BBlock>();
        foreach (var b in bblocks.Values)
        {
            if (b.owner != p.id || hitGroups.Contains(b.group)) continue; // 발판도 터짐
            double dx = b.x + 0.5 - p.x, dy = b.y + 0.5 - p.y;
            double dist = JsMath.Hypot(dx, dy);
            if (dist > range + 0.5 || b.z + 1 < p.z - 0.1 || b.z > p.z + C.PLAYER_HEIGHT) continue;
            if (dist > C.BASIC_STEP_GAP + 0.5 && (dx * fx + dy * fy) / dist < cosHalf) continue;
            hitGroups.Add(b.group);
            targets.Add(b);
        }
        foreach (var b in targets)
        {
            if (b.kind == "big")
            {
                var bomb = bigBombs.FirstOrDefault(x => x.group == b.group);
                if (bomb != null) ExplodeBig(bomb, new XY(fx, fy));
            }
            else if (bblocks.ContainsKey(CellKey(b.x, b.y, b.z))) Blast(b, new XY(fx, fy));
        }
        return targets.Count > 0;
    }

    // 벽·3타 블록·발판 폭발. 벽·발판 기둥은 같은 묶음끼리 이어진 칸으로 연쇄. 사람은 한 번씩, 가까운 터진 칸 수 × BUILDER_BLAST_DAMAGE.
    // 치는 방향(dir) 앞쪽 사람만 dir 쪽으로 날림, 건축가 자신은 안 맞음. 터진 칸 수를 돌려줌
    int Blast(BBlock start, XY dir)
    {
        var p = GetPlayer(start.owner);
        var order = new List<BBlock> { start };
        var seen = new HashSet<long> { CellKey(start.x, start.y, start.z) };
        if (start.kind is "wall" or "pad")
        {
            for (int i = 0; i < order.Count; i++)
            {
                var c = order[i];
                foreach (var o in DIR6)
                {
                    long k = CellKey(c.x + o[0], c.y + o[1], c.z + o[2]);
                    if (bblocks.TryGetValue(k, out var nb) && !seen.Contains(k) && nb.group == start.group)
                    {
                        seen.Add(k);
                        order.Add(nb);
                    }
                }
            }
        }
        foreach (var b in order) RemoveBBlock(b, "blast");
        HoleUnder(order);
        if (p != null) p.ult = Math.Min(UltMax(p), p.ult + order.Count * C.BUILDER_BLAST_ULT); // 패시브: 내 블록 폭발 1칸당 게이지
        var hits = new List<string>();
        foreach (var t in Players().ToList())
        {
            if (p == null || !Foe(p, t)) continue;
            var near = order.Where(b => NearCell(t, b, C.BUILDER_BLAST_RANGE) && (t.x - (b.x + 0.5)) * dir.x + (t.y - (b.y + 0.5)) * dir.y > -0.5).ToList();
            if (near.Count == 0) continue;
            bool hit = ApplyKnockback(t, dir.x, dir.y, C.BUILDER_BLAST_KB_SPEED, C.BUILDER_BLAST_KB_UP, C.BUILDER_BLAST_STUN_MS, near.Count * C.BUILDER_BLAST_DAMAGE, new Src(start.owner, "blast"), true);
            Emit(o => o.P("type", "hit").P("kind", "blast").P("by", start.owner).P("target", t.id).P("ok", hit));
            hits.Add($"{t.name}{(hit ? $" {JsNumber.ToJs(t.damage)}%" : " 무적")}");
        }
        Emit(o =>
        {
            o.P("type", "blast").P("who", start.owner).P("kind", start.kind).P("group", start.group);
            WriteCells(o, "cells", order.Select(b => new[] { b.x, b.y, b.z }));
            o.Key("dir").Obj().P("x", dir.x).P("y", dir.y).EndObj();
        });
        Log($"  [폭발] {(p != null ? p.name : "?")} {BBLOCK_LOG.GetValueOrDefault(start.kind, "undefined")} {order.Count}칸{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
        return order.Count;
    }

    // 테스트 옵션: 터진 칸 바로 아래 바닥 1칸을 BUILDER_HOLE_MS 동안 구멍으로
    void HoleUnder(List<BBlock> cells)
    {
        if (!C.BUILDER_BLAST_HOLE) return;
        foreach (var b in cells)
        {
            int z = b.z - 1;
            if (z < 0 || bblocks.ContainsKey(CellKey(b.x, b.y, z)) || pieceCells.ContainsKey(CellKey(b.x, b.y, z))) continue;
            byte v = grid[Idx(b.x, b.y, z)];
            if (v == 0) continue;
            grid[Idx(b.x, b.y, z)] = 0;
            holes.Add(new Hole { x = b.x, y = b.y, z = z, v = v, id = gridPiece[Idx(b.x, b.y, z)], at = time + C.BUILDER_HOLE_MS });
        }
        GridChanged();
    }

    // 틱마다: 수명 끝난 건축가 블록 사라짐, 다른 이유로 없어진 칸은 기록에서 지움, 대폭발 시간, 구멍 메우기
    void UpdateBBlocks()
    {
        foreach (var b in bblocks.Values.ToList())
        {
            if (grid[Idx(b.x, b.y, b.z)] != Pieces.CELL.BUILD) bblocks.Remove(CellKey(b.x, b.y, b.z));
            else if (time >= b.expiresAt && b.kind != "big") RemoveBBlock(b, "expire");
        }
        foreach (var bomb in bigBombs.ToList()) if (time >= bomb.at) ExplodeBig(bomb, bomb.dir!);
        foreach (var h in holes.ToList())
        {
            if (time < h.at) continue;
            if (grid[Idx(h.x, h.y, h.z)] != 0 || Players().Any(o => OnField(o) && OverlapsCell(o, h.x, h.y, h.z))) continue; // 사람이 있으면 다음 틱
            grid[Idx(h.x, h.y, h.z)] = (byte)h.v;
            gridPiece[Idx(h.x, h.y, h.z)] = h.id;
            holes = holes.Where(x => x != h).ToList();
            GridChanged();
        }
    }

    // 건축가 내려찍기: 맞힌 사람 발밑 (빗나가면 앞 1.5칸) 기둥 꼭대기에 건축가 블록 1칸 ('third', 최대 BUILDER_THIRD_MAX 개).
    // 내 몸과 겹치는 칸이면 앞으로 0.5칸씩 (game-combat.js basicRaise)
    void BasicRaise(Player p, Player? t)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double bx = t != null ? t.x : p.x + fx * 1.5;
        double by = t != null ? t.y : p.y + fy * 1.5;
        bool Mine(double x, double y)
        {
            int cx = (int)Math.Floor(x), cy = (int)Math.Floor(y);
            return OverlapsCell(p, cx, cy, ColumnTop(cx, cy)) || (cx == (int)Math.Floor(p.x) && cy == (int)Math.Floor(p.y));
        }
        for (int i = 0; i < 3 && InXY((int)Math.Floor(bx), (int)Math.Floor(by)) && Mine(bx, by); i++)
        {
            bx += fx * 0.5;
            by += fy * 0.5;
        }
        int cx0 = (int)Math.Floor(bx), cy0 = (int)Math.Floor(by);
        if (!InXY(cx0, cy0) || Mine(bx, by)) return;
        int z = ColumnTop(cx0, cy0);
        int g = ++bgroup;
        if (!PlaceBBlock(p, cx0, cy0, z, "third", g)) return;
        // 3타 블록은 동시에 BUILDER_THIRD_MAX 개까지: 넘으면 제일 오래된 것부터 사라짐
        var thirds = bblocks.Values.Where(b => b.owner == p.id && b.kind == "third").OrderBy(b => b.born).ToList(); // 안정 정렬 (JS sort)
        foreach (var b in thirds.Take(Math.Max(0, thirds.Count - (int)C.BUILDER_THIRD_MAX))) RemoveBBlock(b, "old");
        GridChanged();
        foreach (var o in Players().ToList()) if (OnField(o) && OverlapsCell(o, cx0, cy0, z)) EjectFromBlocks(o);
        Emit(o =>
        {
            o.P("type", "wallRise").P("who", p.id);
            WriteCells(o, "cells", new[] { new[] { cx0, cy0, z } });
        });
        Emit(o =>
        {
            o.P("type", "bblock").P("who", p.id).P("kind", "third").P("group", g);
            WriteCells(o, "cells", new[] { new[] { cx0, cy0, z } });
            o.P("ms", C.BUILDER_BLOCK_MS);
        });
        Log($"  [평타] {p.name} 블록 솟음 ({cx0},{cy0},{z})");
        ClearLayers();
    }
}
