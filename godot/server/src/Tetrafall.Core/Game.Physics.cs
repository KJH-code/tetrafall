using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-physics.js — 플레이어 물리: 이동·중력·충돌
public sealed partial class Game
{
    // ---------- 플레이어 물리 ----------
    public XY? MoveDir(Player p)
    {
        double f = p.input.fwd, s = p.input.strafe;
        if (f == 0 && s == 0) return null;
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double rx = JsMath.Sin(p.yaw), ry = -JsMath.Cos(p.yaw);
        double x = fx * f + rx * s;
        double y = fy * f + ry * s;
        double len = JsMath.Hypot(x, y);
        if (len == 0 || double.IsNaN(len)) len = 1; // JS `|| 1`
        return new XY(x / len, y / len);
    }

    public void IntegratePlayer(Player p, double dt)
    {
        if (p.ghostUntil != 0 && time >= p.ghostUntil)
        {
            p.ghostUntil = 0;
            EjectFromBlocks(p);
        }
        if (p.shieldUntil != 0 && time >= p.shieldUntil)
        {
            p.shieldUntil = 0; // 무적 동안 블록이 통과했으면 꼭대기로
            EjectFromBlocks(p);
        }
        if (time < p.freezeUntil) return; // 히트스톱
        bool stunned = time < p.stunUntil;
        double ix = 0, iy = 0;
        if (p.grounded)
        {
            p.airJumps = C.AIR_JUMPS; // 땅에 닿아 있으면 2단 점프 다시
            p.airDashes = C.AIR_DASHES;
        }
        if (time < p.chargeUntil)
        {
            ix = p.chargeDir!.x * C.TANK_CHARGE_SPEED; // 탱크 돌진
            iy = p.chargeDir.y * C.TANK_CHARGE_SPEED;
        }
        else if (p.leap != null && p.leap.endAt != 0 && time < p.leap.endAt)
        {
            ix = p.leap.vx; // 사냥꾼 도약
            iy = p.leap.vy;
        }
        else if (p.rush != null && time < p.rush.endAt)
        {
            ix = p.rush.vx; // 광전사 도약
            iy = p.rush.vy;
        }
        else if (time < p.zipUntil)
        {
            ix = p.zipDir!.x * C.HOOK_ZIP_SPEED; // 갈고리 블록 걸기
            iy = p.zipDir.y * C.HOOK_ZIP_SPEED;
        }
        else if (!stunned && !IsEmoting(p))
        {
            var mv = MoveDir(p);
            if (mv != null)
            {
                double speed =
                    C.MOVE_SPEED *
                    (time < p.speedUntil ? C.SPEED_MULT : 1) *
                    (p.atk != null && p.atk.def.finish ? C.BASIC_FINISH_MOVE_MULT : 1) * // 평타 마무리 준비 중
                    (p.spin != null ? C.BERSERKER_SPIN_MOVE_MULT : 1) * // 광전사 회전 중
                    (p.amp != null ? C.BARD_AMP_MOVE_MULT : 1) * // 바드 앰프 연주 중
                    (time < p.slowUntil ? 1 - C.BARD_SLOW : 1) * // 둔화
                    (p.dive != null ? C.BARD_DIVE_MOVE_MULT : 1); // 기타 꽂기 낙하 중
                ix = mv.x * speed;
                iy = mv.y * speed;
            }
            if ((p.input.jump || time < p.jumpQueuedUntil) && p.grounded)
            {
                p.vz = time < p.jumpUntil ? C.JUMP_BOOST_SPEED : C.JUMP_SPEED;
                p.grounded = false;
                p.jumpQueuedUntil = 0;
            }
            else if (p.airJumpQueued && !p.grounded && p.airJumps > 0)
            {
                // 2단 점프: 공중에서 점프를 새로 누르면 한 번 더. 땅에 닿으면 다시 생김
                p.vz = C.AIR_JUMP_SPEED;
                p.airJumps--;
                Emit(o => o.P("type", "airJump").P("who", p.id));
            }
        }
        p.airJumpQueued = false;
        double damp = JsMath.Exp(-(p.grounded ? C.KB_DAMPING_GROUND : C.KB_DAMPING_AIR) * dt);
        p.kbx *= damp;
        p.kby *= damp;
        if (Math.Abs(p.kbx) < 0.01) p.kbx = 0;
        if (Math.Abs(p.kby) < 0.01) p.kby = 0;
        if (p.grounded && p.dive == null)
        {
            p.glideCount = 0; // 땅·블록에 서면 천천히 낙하 횟수 다시
            p.diveUsed = false;
        }
        if (p.glideUntil != 0 && (p.grounded || time >= p.glideUntil)) p.glideUntil = 0;
        p.vz -= C.GRAVITY * (p.glideUntil != 0 ? C.BARD_GLIDE_GRAVITY : 1) * dt; // 바드 천천히 낙하: 중력 줄임
        if (p.glideUntil != 0 && p.vz < -C.BARD_GLIDE_FALL) p.vz = -C.BARD_GLIDE_FALL;
        if (p.dive != null && p.vz > -C.BARD_DIVE_SPEED) p.vz = -C.BARD_DIVE_SPEED; // 기타 꽂기: 빠르게 아래로
        MoveAxis(p, 0, (ix + p.kbx) * dt);
        MoveAxis(p, 1, (iy + p.kby) * dt);
        p.grounded = false;
        MoveAxis(p, 2, p.vz * dt);
    }

    public (double x0, double x1, double y0, double y1, double z0, double z1) Aabb(Player p) =>
        (p.x - C.PLAYER_HALF, p.x + C.PLAYER_HALF, p.y - C.PLAYER_HALF, p.y + C.PLAYER_HALF, p.z, p.z + C.PLAYER_HEIGHT);

    public List<int[]> OverlappingSolid((double x0, double x1, double y0, double y1, double z0, double z1) b)
    {
        var out_ = new List<int[]>();
        int cx0 = (int)Math.Floor(b.x0 + EPS), cx1 = (int)Math.Floor(b.x1 - EPS);
        int cy0 = (int)Math.Floor(b.y0 + EPS), cy1 = (int)Math.Floor(b.y1 - EPS);
        int cz0 = (int)Math.Floor(b.z0 + EPS), cz1 = (int)Math.Floor(b.z1 - EPS);
        for (int cz = cz0; cz <= cz1; cz++)
            for (int cy = cy0; cy <= cy1; cy++)
                for (int cx = cx0; cx <= cx1; cx++)
                    if (SolidAt(cx, cy, cz)) out_.Add(new[] { cx, cy, cz });
        return out_;
    }

    static double GetAxis(Player p, int a) => a == 0 ? p.x : a == 1 ? p.y : p.z;

    static void SetAxis(Player p, int a, double v)
    {
        if (a == 0) p.x = v;
        else if (a == 1) p.y = v;
        else p.z = v;
    }

    // axis: 0 = x, 1 = y, 2 = z
    public void MoveAxis(Player p, int axis, double delta)
    {
        if (delta == 0) return;
        double prevZ = p.z;
        SetAxis(p, axis, GetAxis(p, axis) + delta);
        var hits = OverlappingSolid(Aabb(p));
        if (hits.Count > 0 && IsGhost(p))
        {
            // 유령: 옆·위로는 통과. 아래로는 "원래 그 위에 있던" 칸에만 착지 (한쪽 통과 발판)
            if (axis != 2 || delta > 0) return;
            hits = hits.Where(h => h[2] + 1 <= prevZ + 1e-6).ToList();
        }
        if (hits.Count == 0) return;
        if (axis == 2)
        {
            if (delta < 0)
            {
                double top = double.NegativeInfinity;
                foreach (var h in hits) if (h[2] + 1 > top) top = h[2] + 1;
                p.z = top;
                p.vz = 0;
                p.grounded = true;
            }
            else
            {
                double bottom = double.PositiveInfinity;
                foreach (var h in hits) if (h[2] < bottom) bottom = h[2];
                p.z = bottom - C.PLAYER_HEIGHT;
                p.vz = 0;
            }
            return;
        }
        if (delta > 0)
        {
            double edge = double.PositiveInfinity;
            foreach (var h in hits) if (h[axis] < edge) edge = h[axis];
            SetAxis(p, axis, edge - C.PLAYER_HALF);
        }
        else
        {
            double edge = double.NegativeInfinity;
            foreach (var h in hits) if (h[axis] + 1 > edge) edge = h[axis] + 1;
            SetAxis(p, axis, edge + C.PLAYER_HALF);
        }
        // 넉백으로 날아가다 벽에 박히면 그 속도를 위로 바꿔 넘김 (맞을 때마다 한 번)
        double speed = Math.Abs(axis == 0 ? p.kbx : p.kby);
        if (time < p.stunUntil && speed >= C.WALL_BOUNCE_MIN_SPEED)
        {
            if (!p.wallBounced)
            {
                p.wallBounced = true;
                p.vz = Math.Max(p.vz, Math.Min(C.WALL_BOUNCE_MAX_UP, speed * C.WALL_BOUNCE_RATIO));
                p.grounded = false;
            }
            if (p.vz > 0) return;
        }
        if (axis == 0) p.kbx = 0;
        else p.kby = 0;
    }

    // 발밑 칸 종류 (GROUND_LOG 키): 몸 가운데 → 네 모서리 순으로 처음 닿는 칸
    public string GroundKind(Player p)
    {
        int cz = (int)JsMath.Round(p.z) - 1;
        if (cz < 0) return "floor";
        double h = C.PLAYER_HALF * 0.9;
        foreach (var (ox, oy) in new[] { (0.0, 0.0), (-h, -h), (h, -h), (-h, h), (h, h) })
        {
            int x = (int)Math.Floor(p.x + ox);
            int y = (int)Math.Floor(p.y + oy);
            if (pieceCells.TryGetValue(CellKey(x, y, cz), out var id)) return pieces.FirstOrDefault(pc => pc.id == id)?.sky == true ? "sky" : "piece";
            int v = GridAt(x, y, cz);
            if (v != 0) return v == Pieces.CELL.TERRAIN ? "terrain" : "stack";
        }
        return "stack"; // 칸 경계에 걸쳐 서 있음: 블록 위로 셈
    }
}
