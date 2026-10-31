using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-items.js — 아이템·설치 블록·폭탄·투사체 (S1: 스냅샷·물리가 쓰는 부분. 나머지는 S4)
public sealed partial class Game
{
    // 손에 든 것으로 우클릭하면 생길 것 (화면 미리보기): { kind, ...plan } 또는 null
    public void AimPreview(JsonOut o, Player p)
    {
        if (p.bricks > 0) BrickPlanPreview(o, p);
        else if (p.bombs > 0) BombPlanPreview(o, p);
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

// game-items.js 의 필드 아이템 (S2 가 같이 옮김: 블록 마스터 반격 아이템이 판 흐름에 들어가서)
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
