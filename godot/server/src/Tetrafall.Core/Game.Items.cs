using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-items.js — 아이템·손 아이템(설치 블록·폭탄)·투사체
public sealed partial class Game
{
    // 손에 든 것으로 우클릭하면 생길 것 (화면 미리보기): { kind, ...plan } 또는 null
    public void AimPreview(JsonOut o, Player p)
    {
        if (p.bricks > 0)
        {
            var b = BrickPlan(p);
            o.Obj().P("kind", "brick");
            WriteCells(o, b.cells);
            o.P("z", b.z);
            if (b.spawnZ != null) o.P("spawnZ", b.spawnZ.Value);
            o.P("ok", b.ok).EndObj();
        }
        else if (p.bombs > 0)
        {
            var b = BombPlan(p);
            o.Obj().P("kind", "bomb");
            WriteCells(o, b.cells);
            o.P("ok", b.ok).EndObj();
        }
        else o.Null();
    }

    // 조종권 아이템이 나오는 판인지
    public bool ControlItemOn() => C.CONTROL_ITEM && mode != "master" && !sky;

    // 조종권이 필드·누군가의 손·조종 중인 블록 어딘가에 있음
    public bool ControlInPlay() => items.Any(it => it.type == "control") || Players().Any(p => p.hasControl) || pieces.Any(pc => pc.controller != null);

    // 다음 조종권·아이템까지 남은 ms (시계가 안 돌면 null)
    public (double? control, double? power) ItemTimers()
    {
        if (phase != "playing") return (null, null);
        int powerCount = items.Count(it => it.type != "control");
        return (
            !ControlItemOn() || ControlInPlay() ? null : Math.Max(0, controlItemNextAt - time),
            !C.ITEMS_ENABLED || powerCount >= ItemMax() ? null : Math.Max(0, powerItemNextAt - time));
    }

    public bool IsGhost(Player p) => time < p.ghostUntil;

    // 유령화가 끝났는데 블록 안이면 그 기둥 꼭대기로 밀어 올린다
    public void EjectFromBlocks(Player p)
    {
        for (int i = 0; i < H + 2; i++)
        {
            var hits = OverlappingSolid(Aabb(p));
            if (hits.Count == 0) return;
            double top = double.NegativeInfinity;
            foreach (var h in hits) if (h[2] + 1 > top) top = h[2] + 1;
            p.z = top;
            p.vz = 0;
        }
    }
}

// game-items.js 의 필드 아이템
public sealed partial class Game
{
    // ---------- 아이템 ----------
    public bool SpawnItem(string type)
    {
        for (int i = 0; i < C.SPAWN_TRIES; i++)
        {
            int x = (int)Math.Floor(rng() * W);
            int y = (int)Math.Floor(rng() * D);
            int z = ColumnTop(x, y);
            if (z >= H) continue;
            if (lava.active && z < lava.z + 1) continue; // 용암에 잠길 자리는 피함
            if (items.Any(it => it.x == x && it.y == y)) continue;
            items.Add(new Item { type = type, x = x, y = y, z = z });
            return true;
        }
        return false;
    }

    public void UpdateItems()
    {
        if (tutorial != null)
        {
            PickupItems(); // 튜토리얼: 단계가 놓은 아이템만
            return;
        }
        if (ControlItemOn() && !ControlInPlay() && time >= controlItemNextAt)
        {
            if (!SpawnItem("control")) controlItemNextAt = time + 1000;
        }
        int powerCount = items.Count(it => it.type != "control");
        if (C.ITEMS_ENABLED && powerCount < ItemMax() && time >= powerItemNextAt)
        {
            string type = C.ITEM_POOL[(int)Math.Floor(rng() * C.ITEM_POOL.Length)];
            powerItemNextAt = time + (SpawnItem(type) ? C.ITEM_RESPAWN_MS : 1000);
        }
        if (mode == "master" && phase == "playing" && !items.Any(it => it.type == "counter") && time >= counterItemAt)
            counterItemAt = time + (SpawnItem("counter") ? C.MASTER_COUNTER_RESPAWN_MS : 1000); // 블록 마스터 반격 아이템 (한 번에 하나)
        PickupItems();
    }

    // 필드 아이템 줍기 (닿으면)
    public void PickupItems()
    {
        for (int i = items.Count - 1; i >= 0; i--)
        {
            var it = items[i];
            it.z = ColumnTop(it.x, it.y);
            foreach (var p in Players().ToList())
            {
                if (!OnField(p)) continue;
                double dx = p.x - (it.x + 0.5), dy = p.y - (it.y + 0.5);
                if (JsMath.Hypot(dx, dy) > C.ITEM_PICK_RADIUS) continue;
                if (Math.Abs(p.z - it.z) > C.ITEM_HEIGHT_TOL) continue;
                if (C.HELD_ITEMS.Contains(it.type) && HeldItem(p) != null) continue; // 손 아이템은 하나만
                items.RemoveAt(i);
                if (it.type == "control")
                {
                    p.hasControl = true;
                    Emit(o => o.P("type", "pickup").P("who", p.id).P("item", "control"));
                    Log($"  [아이템] {p.name} 조종권 획득");
                    StartControlNow(p);
                }
                else
                {
                    GivePower(p, it.type);
                    powerItemNextAt = Math.Max(powerItemNextAt, time + C.ITEM_RESPAWN_MS);
                    Emit(o => o.P("type", "pickup").P("who", p.id).P("item", it.type));
                }
                break;
            }
        }
    }

    public void GivePower(Player p, string type)
    {
        switch (type)
        {
            case "knockback":
                p.ammo += C.KNOCKBACK_AMMO;
                Log($"  [아이템] {p.name} 넉백 아이템 획득 (탄 {JsNumber.ToJs(p.ammo)})");
                break;
            case "jump":
                p.jumpUntil = time + C.JUMP_BOOST_MS;
                Log($"  [아이템] {p.name} 점프력 상승 획득");
                break;
            case "ghost":
                p.ghostUntil = time + C.GHOST_MS;
                Log($"  [아이템] {p.name} 유령화 획득");
                break;
            case "brick":
                p.bricks = C.BRICK_USES;
                p.brickSide = false;
                Log($"  [아이템] {p.name} 설치 블록 1×2 획득 ({JsNumber.ToJs(p.bricks)}개)");
                break;
            case "bomb":
                p.bombs = C.BOMB_USES;
                Log($"  [아이템] {p.name} 폭탄 획득");
                break;
            case "speed":
                p.speedUntil = time + C.SPEED_MS;
                Log($"  [아이템] {p.name} 이속 증가 획득");
                break;
            case "counter":
                // 블록 마스터 반격: 마스터 편 전원의 다음 블록이 늦게 나옴 (겹쳐 먹으면 이어 붙음)
                masterStallUntil = Math.Max(masterStallUntil, time) + C.MASTER_COUNTER_STALL_MS;
                counterItemAt = time + C.MASTER_COUNTER_RESPAWN_MS;
                Emit(o => o.P("type", "masterStall").P("who", p.id).P("until", masterStallUntil).P("ms", C.MASTER_COUNTER_STALL_MS));
                Log($"  [아이템] {p.name} 반격 → 마스터 편 블록 {JsNumber.ToJs(C.MASTER_COUNTER_STALL_MS / 1000)}초 멈춤");
                break;
        }
    }
}

// game-items.js 의 손 아이템 (설치 블록·폭탄·넉백 투사체)
public sealed record BrickPlanResult(List<int[]> cells, int z, int? spawnZ, bool ok);
public sealed record BombPlanResult(List<int[]> cells, bool ok);

public sealed partial class Game
{
    static void WriteCells(JsonOut o, List<int[]> cells)
    {
        o.Key("cells").Arr();
        foreach (var c in cells)
        {
            o.Arr();
            foreach (var v in c) o.Num(v);
            o.EndArr();
        }
        o.EndArr();
    }

    public void Fire(Player p)
    {
        p.ammo--;
        double cp = JsMath.Cos(p.pitch);
        double dx = cp * JsMath.Cos(p.yaw), dy = cp * JsMath.Sin(p.yaw), dz = JsMath.Sin(p.pitch);
        projectiles.Add(new Projectile { x = p.x + dx * 0.6, y = p.y + dy * 0.6, z = p.z + C.EYE_HEIGHT + dz * 0.6, dx = dx, dy = dy, dz = dz, owner = p.id, dieAt = time + C.PROJECTILE_LIFE_MS });
        Emit(o => o.P("type", "fire").P("who", p.id));
        Log($"  [발사] {p.name} (남은 탄 {JsNumber.ToJs(p.ammo)})");
    }

    // 던지는 것(설치 블록·폭탄)의 기준 칸 [x, y] 또는 null: 눈에서 조준 방향으로 BRICK_MIN_DIST~BRICK_RANGE 사이에서 지형에 처음 닿는 칸
    public (int x, int y)? AimAnchor(Player p, double yaw, double pitch)
    {
        double cp = JsMath.Cos(pitch);
        double dx = cp * JsMath.Cos(yaw), dy = cp * JsMath.Sin(yaw), dz = JsMath.Sin(pitch);
        double hlen = JsMath.Hypot(dx, dy);
        double ez = p.z + C.EYE_HEIGHT;
        (int, int)? anchor = null;
        // 수평 거리로 0.05칸씩
        for (double h = C.BRICK_MIN_DIST; hlen > 1e-6 && h <= C.BRICK_RANGE; h += 0.05)
        {
            double t = h / hlen;
            int cx = (int)Math.Floor(p.x + dx * t), cy = (int)Math.Floor(p.y + dy * t);
            if (!InXY(cx, cy)) break;
            anchor = (cx, cy);
            if (ez + dz * t <= ColumnTop(cx, cy)) break; // 시선이 지형에 닿음
        }
        return anchor;
    }

    public BrickPlanResult BrickPlan(Player p) => BrickPlan(p, p.yaw, p.pitch);

    public BrickPlanResult BrickPlan(Player p, double yaw, double pitch)
    {
        var anchor = AimAnchor(p, yaw, pitch);
        if (anchor == null) return new(new List<int[]>(), 0, null, false);
        double fx = JsMath.Cos(yaw), fy = JsMath.Sin(yaw);
        var along = Math.Abs(fx) >= Math.Abs(fy) ? ((int)JsMath.Sign(fx), 0) : (0, (int)JsMath.Sign(fy));
        var left = (-along.Item2, along.Item1);
        var (ax, ay) = anchor.Value;
        var offs = new[] { (0, 0), p.brickSide ? left : along };
        var cells = offs.Select(o => (x: ax + o.Item1, y: ay + o.Item2)).ToList();
        if (!cells.All(c => InXY(c.x, c.y))) return new(cells.Select(c => new[] { c.x, c.y, 0 }).ToList(), 0, null, false);
        int z = cells.Max(c => ColumnTop(c.x, c.y));
        int spawnZ = (int)Math.Min(z + C.BRICK_DROP_HEIGHT, H - 1);
        bool ok = z < H - 1 &&
            !cells.Any(c => pieceCells.ContainsKey(GameUtil.CellKey(c.x, c.y, spawnZ))) && // 생길 자리에 떨어지는 블록이 있음
            !cells.Any(c => GameUtil.OverlapsCell(p, c.x, c.y, p.z)); // 내 머리 위
        return new(cells.Select(c => new[] { c.x, c.y, z }).ToList(), z, spawnZ, ok);
    }

    // 조준한 칸 위 공중에 블록을 만들어 떨어뜨린다. 떨어지는 동안은 보통 블록과 같다
    public bool ThrowBrick(Player p)
    {
        var plan = BrickPlan(p);
        if (!plan.ok) return false;
        p.bricks--;
        int ax = plan.cells[0][0], ay = plan.cells[0][1];
        var piece = new Piece { id = 0, shape = "1×2", rot = 0, cells = plan.cells.Select(c => new[] { c[0] - ax, c[1] - ay }).ToArray(), px = ax, py = ay, pz = plan.spawnZ!.Value, landZ = 0, fits = false };
        UpdateLanding(piece);
        AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.thrownBy = p.id;
            pc.stepMs = C.BRICK_FALL_STEP_MS;
            pc.nextStepAt = time + C.BRICK_FALL_STEP_MS;
            pc.controlEndsAt = 0;
        });
        Emit(o =>
        {
            o.P("type", "throw").P("who", p.id);
            WriteCells(o, plan.cells);
        });
        Log($"  [투척] {p.name} {piece.shape} → ({ax},{ay}) z={plan.z} (남은 {JsNumber.ToJs(p.bricks)}개)");
        if (p.bricks == 0) p.brickSide = false;
        return true;
    }

    // ---- 폭탄 ----
    // 설치 블록과 같은 조준. cells 는 미리보기용 부서질 범위 (가로세로 ±BOMB_RADIUS), 첫 칸이 폭탄 자리
    public BombPlanResult BombPlan(Player p) => BombPlan(p, p.yaw, p.pitch);

    public BombPlanResult BombPlan(Player p, double yaw, double pitch)
    {
        var anchor = AimAnchor(p, yaw, pitch);
        if (anchor == null) return new(new List<int[]>(), false);
        var (ax, ay) = anchor.Value;
        int z = ColumnTop(ax, ay);
        var cells = new List<int[]> { new[] { ax, ay, z } };
        int R = (int)C.BOMB_RADIUS;
        for (int dx = -R; dx <= R; dx++)
            for (int dy = -R; dy <= R; dy++)
                if ((dx != 0 || dy != 0) && InXY(ax + dx, ay + dy)) cells.Add(new[] { ax + dx, ay + dy, z });
        return new(cells, z < H);
    }

    public bool ThrowBomb(Player p)
    {
        if (p.bombs <= 0) return false;
        var plan = BombPlan(p);
        if (!plan.ok) return false;
        p.bombs--;
        int x = plan.cells[0][0], y = plan.cells[0][1], z = plan.cells[0][2];
        bombs.Add(new Bomb { id = ++bombCounter, x = x, y = y, z = z, by = p.id, explodeAt = time + C.BOMB_FUSE_MS });
        Emit(o => o.P("type", "bombPlace").P("who", p.id).P("x", x).P("y", y).P("z", z));
        Log($"  [폭탄] {p.name} → ({x},{y}) z={z} 설치, {JsNumber.ToJs(C.BOMB_FUSE_MS / 1000)}초 뒤 폭발");
        return true;
    }

    public void UpdateBombs()
    {
        foreach (var b in bombs.ToList())
        {
            b.z = ColumnTop(b.x, b.y);
            if (time < b.explodeAt) continue;
            bombs.Remove(b);
            ExplodeBomb(b);
        }
    }

    // 폭탄 칸 중심 ±BOMB_RADIUS 정육면체 블록을 부수고 BOMB_BLAST_RANGE 안의 사람을 날린다 (던진 사람 면제)
    public void ExplodeBomb(Bomb b)
    {
        int R = (int)C.BOMB_RADIUS;
        int removed = 0;
        for (int x = b.x - R; x <= b.x + R; x++)
            for (int y = b.y - R; y <= b.y + R; y++)
                for (int z = b.z - R; z <= b.z + R; z++)
                {
                    if (!InXY(x, y) || z < 0 || z >= H || grid[Idx(x, y, z)] == 0) continue;
                    grid[Idx(x, y, z)] = 0;
                    removed++;
                }
        var by = GetPlayer(b.by);
        double cx = b.x + 0.5, cy = b.y + 0.5, cz = b.z + 0.5;
        Emit(o => o.P("type", "boom").P("who", b.by).P("x", cx).P("y", cy).P("z", cz));
        Log($"  [폭탄] {(by != null ? by.name : "?")} 의 폭탄 폭발 ({b.x},{b.y}) z={b.z}, 블록 {removed}칸 파괴");
        foreach (var t in Players().ToList())
        {
            if (!OnField(t) || t.id == b.by || SameTeam(by, t)) continue; // 같은 팀은 안 맞음
            double dx = t.x - cx, dy = t.y - cy;
            if (JsMath.Hypot(dx, dy) > C.BOMB_BLAST_RANGE || Math.Abs(t.z + C.PLAYER_HEIGHT / 2 - cz) > C.BOMB_BLAST_RANGE) continue;
            double a = rng() * Math.PI * 2; // 바로 위에 서 있으면 방향이 없어서 무작위
            bool hit = JsMath.Hypot(dx, dy) > 0.05
                ? ApplyKnockback(t, dx, dy, C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN["bomb"], new Src(b.by, "bomb"), true)
                : ApplyKnockback(t, JsMath.Cos(a), JsMath.Sin(a), C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN["bomb"], new Src(b.by, "bomb"), true);
            Emit(o => o.P("type", "hit").P("kind", "bomb").P("by", b.by).P("target", t.id).P("ok", hit));
            Log($"  [폭탄] {(by != null ? by.name : "?")} → {t.name} {(hit ? $"넉백 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}");
        }
        if (removed > 0) GridChanged();
    }

    // 던진 블록이 착지하면 바로 옆(BRICK_SHOCK_RANGE 안)에 있던 사람을 바깥쪽으로 날린다
    public void BrickShock(Piece piece)
    {
        var by = GetPlayer(piece.thrownBy);
        var cells = PieceWorldCells(piece);
        double x0 = cells.Min(c => c[0]), x1 = cells.Max(c => c[0]) + 1;
        double y0 = cells.Min(c => c[1]), y1 = cells.Max(c => c[1]) + 1;
        double z = cells[0][2];
        double cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
        foreach (var t in Players().ToList())
        {
            if (!OnField(t) || t.id == piece.thrownBy || SameTeam(GetPlayer(piece.thrownBy), t)) continue; // 던진 사람·같은 팀은 안 맞음
            double gx = Math.Max(Math.Max(x0 - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - x1), 0);
            double gy = Math.Max(Math.Max(y0 - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - y1), 0);
            if (JsMath.Hypot(gx, gy) > C.BRICK_SHOCK_RANGE || Math.Abs(t.z - z) > C.BRICK_SHOCK_HEIGHT) continue;
            bool hit = ApplyKnockback(t, t.x - cx, t.y - cy, C.BRICK_SHOCK_KB_SPEED, C.BRICK_SHOCK_KB_UP, C.BRICK_SHOCK_STUN_MS, C.DAMAGE_GAIN["shock"], new Src(piece.thrownBy!.Value, "shock"), true);
            Emit(o => o.P("type", "hit").P("kind", "shock").P("by", piece.thrownBy).P("target", t.id).P("ok", hit));
            Log($"  [충격파] {(by != null ? by.name : "?")} → {t.name} {(hit ? $"넉백 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}");
        }
    }

    // ---------- 투사체 ----------
    public void UpdateProjectiles(double dt)
    {
        double sub = Math.Max(1, Math.Ceiling((C.PROJECTILE_SPEED * dt) / 0.2));
        double h = dt / sub;
        for (int i = projectiles.Count - 1; i >= 0; i--)
        {
            var pr = projectiles[i];
            bool dead = time >= pr.dieAt;
            for (int s = 0; s < sub && !dead; s++)
            {
                pr.x += pr.dx * C.PROJECTILE_SPEED * h;
                pr.y += pr.dy * C.PROJECTILE_SPEED * h;
                pr.z += pr.dz * C.PROJECTILE_SPEED * h;
                if (SolidAt((int)Math.Floor(pr.x), (int)Math.Floor(pr.y), (int)Math.Floor(pr.z)))
                {
                    dead = true;
                    break;
                }
                foreach (var t in Players().ToList())
                {
                    if (!OnField(t) || t.id == pr.owner || SameTeam(GetPlayer(pr.owner), t)) continue; // 같은 팀은 통과
                    double r = C.PROJECTILE_RADIUS;
                    if (pr.x > t.x - C.PLAYER_HALF - r && pr.x < t.x + C.PLAYER_HALF + r && pr.y > t.y - C.PLAYER_HALF - r && pr.y < t.y + C.PLAYER_HALF + r && pr.z > t.z - r && pr.z < t.z + C.PLAYER_HEIGHT + r)
                    {
                        var shooter = GetPlayer(pr.owner);
                        bool hit = ApplyKnockback(t, pr.dx, pr.dy, C.PROJECTILE_KB_SPEED, C.PROJECTILE_KB_UP, C.STUN_MS, C.DAMAGE_GAIN["projectile"], new Src(pr.owner, "projectile"), true);
                        Emit(o => o.P("type", "hit").P("kind", "projectile").P("by", pr.owner).P("target", t.id).P("ok", hit));
                        Log($"  [투사체] {(shooter != null ? shooter.name : "?")} → {t.name} {(hit ? "넉백" : "무적이라 무시")}");
                        dead = true;
                        break;
                    }
                }
            }
            if (dead) projectiles.RemoveAt(i);
        }
    }
}
