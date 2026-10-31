using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-cannon.js — 대포수 (S3)
public sealed partial class Game
{
    // 쌓인 블록 1칸 부숨 (격자 칸 또는 떨어지는 블록의 한 칸). 시작 지형·바닥은 안 부숨. 부쉈으면 true
    bool BreakCell(int x, int y, int z)
    {
        long key = CellKey(x, y, z);
        if (pieceCells.TryGetValue(key, out int pid))
        {
            var pc = pieces.First(q => q.id == pid);
            pc.cells = pc.cells.Where(c => !(pc.px + c[0] == x && pc.py + c[1] == y)).ToArray();
            if (pc.cells.Length == 0) RemovePiece(pc);
            else
            {
                RefreshPieceCells();
                UpdateLanding(pc);
            }
            return true;
        }
        if (!InXY(x, y) || z < 0 || z >= H) return false;
        byte v = grid[Idx(x, y, z)];
        if (v == 0 || v == Pieces.CELL.TERRAIN) return false;
        grid[Idx(x, y, z)] = 0;
        GridChanged();
        return true;
    }

    // 시간 장전: 탄이 덜 찼으면 CANNON_RELOAD_MS 마다 한 발
    void CannonReload(Player p)
    {
        if (p.cannonAmmo >= C.CANNON_AMMO_MAX)
        {
            p.reloadAt = 0;
            return;
        }
        if (p.reloadAt == 0 || double.IsNaN(p.reloadAt)) p.reloadAt = time + C.CANNON_RELOAD_MS;
        else if (time >= p.reloadAt)
        {
            p.cannonAmmo++;
            p.reloadAt = p.cannonAmmo < C.CANNON_AMMO_MAX ? time + C.CANNON_RELOAD_MS : 0;
            Emit(o => o.P("type", "reload").P("who", p.id).P("ammo", p.cannonAmmo));
        }
    }

    // 조준 방향 (높이 포함): pitch 가 없으면 0
    static XYZ AimDir(Player p)
    {
        double pitch = double.IsNaN(p.pitch) ? 0 : p.pitch; // JS p.pitch || 0
        double cp = JsMath.Cos(pitch);
        return new XYZ(cp * JsMath.Cos(p.yaw), cp * JsMath.Sin(p.yaw), JsMath.Sin(pitch));
    }

    // 포탄 (big = R 대형 포탄) 을 조준 방향으로 쏨 + 반동
    Shell FireShell(Player p, bool big)
    {
        var dir = AimDir(p);
        double speed = big ? C.CANNON_R_SPEED : C.CANNON_SHELL_SPEED;
        double range = big ? C.CANNON_R_RANGE : C.CANNON_SHELL_RANGE;
        var sh = new Shell
        {
            id = ++shellCounter,
            big = big,
            owner = p.id,
            x = p.x + dir.x * 0.5,
            y = p.y + dir.y * 0.5,
            z = p.z + C.EYE_HEIGHT - 0.2 + dir.z * 0.5,
            dir = dir,
            speed = speed,
            dieAt = time + range / speed * 1000,
        };
        shells.Add(sh);
        double recoil = big ? C.CANNON_R_RECOIL : p.grounded ? C.CANNON_RECOIL : C.CANNON_RECOIL_AIR;
        double hl = JsMath.Hypot(dir.x, dir.y);
        if (hl == 0 || double.IsNaN(hl)) hl = 1;
        p.kbx -= dir.x / hl * recoil;
        p.kby -= dir.y / hl * recoil;
        Emit(o => o.P("type", "shellFire").P("who", p.id).P("id", sh.id).P("big", big).P("x", sh.x).P("y", sh.y).P("z", sh.z)
            .Key("dir").Obj().P("x", dir.x).P("y", dir.y).P("z", dir.z).EndObj().P("speed", speed).P("recoil", recoil));
        return sh;
    }

    // 평타 포탄: 탄 1발 쓰고 쏨
    void CannonShot(Player p)
    {
        p.cannonAmmo--;
        if (p.reloadAt == 0 || double.IsNaN(p.reloadAt)) p.reloadAt = time + C.CANNON_RELOAD_MS;
        FireShell(p, false);
        Log($"  [포탄] {p.name} 발사 (남은 {JsNumber.ToJs(p.cannonAmmo)}발)");
    }

    // F 발밑 포격: 위로 크게 + 발밑 범위 넉백
    bool CannonJump(Player p)
    {
        p.vz = C.CANNON_JUMP_UP;
        p.grounded = false;
        var hits = new List<string>();
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.CANNON_FBLAST_RANGE || Math.Abs(t.z - p.z) > 1.5) continue;
            double a = rng() * Math.PI * 2;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(a), d > 0.05 ? dy : JsMath.Sin(a), C.CANNON_FBLAST_KB_SPEED, C.CANNON_FBLAST_KB_UP, C.CANNON_FBLAST_STUN_MS, C.CANNON_FBLAST_DAMAGE, new Src(p.id, "groundshot"), true);
            Emit(o => o.P("type", "hit").P("kind", "groundshot").P("by", p.id).P("target", t.id).P("ok", hit));
            if (hit) hits.Add(t.name);
        }
        Emit(o => o.P("type", "groundShot").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.CANNON_FBLAST_RANGE));
        Log($"  [스킬] {p.name} 발밑 포격{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
        return true;
    }

    // R 대형 포탄
    void CannonBig(Player p)
    {
        FireShell(p, true);
        Log($"  [필살] {p.name} 대형 포탄 발사");
    }

    // 포탄 이동: 보통 포탄은 처음 닿는 것에서 멈춤 (사람 넉백 / 쌓인 블록 1칸 부숨). 대형 포탄은 관통하며 쌓인 블록 부수고 사람 밀침, 끝에서 폭발
    public void UpdateShells(double dt)
    {
        foreach (var sh in shells.ToList())
        {
            int sub = (int)Math.Max(1, Math.Ceiling(sh.speed * dt / 0.15));
            double h = dt / sub;
            string? end = null;
            for (int s = 0; s < sub && end == null; s++)
            {
                sh.x += sh.dir.x * sh.speed * h;
                sh.y += sh.dir.y * sh.speed * h;
                sh.z += sh.dir.z * sh.speed * h;
                double r = sh.big ? C.CANNON_R_RADIUS : C.CANNON_SHELL_RADIUS;
                var owner = GetPlayer(sh.owner);
                // 사람
                foreach (var t in Players().ToList())
                {
                    if (!OnField(t) || t.id == sh.owner || sh.hit.Contains(t.id) || SameTeam(owner, t)) continue; // 같은 팀은 통과
                    if (!(sh.x > t.x - C.PLAYER_HALF - r && sh.x < t.x + C.PLAYER_HALF + r && sh.y > t.y - C.PLAYER_HALF - r && sh.y < t.y + C.PLAYER_HALF + r && sh.z > t.z - r && sh.z < t.z + C.PLAYER_HEIGHT + r)) continue;
                    sh.hit.Add(t.id);
                    bool big = sh.big;
                    bool hit = ApplyKnockback(t, sh.dir.x, sh.dir.y, big ? C.CANNON_R_KB_SPEED : C.CANNON_SHELL_KB_SPEED, big ? C.CANNON_R_KB_UP : C.CANNON_SHELL_KB_UP, big ? C.CANNON_R_STUN_MS : C.CANNON_SHELL_STUN_MS, big ? C.CANNON_R_DAMAGE : C.CANNON_SHELL_DAMAGE, new Src(sh.owner, big ? "bigshell" : "shell"), true);
                    Emit(o => o.P("type", "hit").P("kind", big ? "bigshell" : "shell").P("by", sh.owner).P("target", t.id).P("ok", hit));
                    Log($"  [포탄] {(owner != null ? owner.name : "?")} → {t.name} {(hit ? $"넉백 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}{(big ? " 대형" : "")}");
                    if (!big)
                    {
                        end = "player";
                        break;
                    }
                }
                if (end != null) break;
                // 블록·바닥
                if (sh.big)
                {
                    var broke = new List<int[]>();
                    for (int x = (int)Math.Floor(sh.x - r); x <= Math.Floor(sh.x + r); x++)
                        for (int y = (int)Math.Floor(sh.y - r); y <= Math.Floor(sh.y + r); y++)
                            for (int z = (int)Math.Floor(sh.z - r); z <= Math.Floor(sh.z + r); z++)
                                if (BreakCell(x, y, z)) broke.Add(new[] { x, y, z });
                    if (broke.Count > 0)
                    {
                        Emit(o =>
                        {
                            o.P("type", "blockBreak").P("who", sh.owner);
                            WriteCells(o, "cells", broke);
                            o.P("big", true);
                        });
                        Log($"  [포탄] {(owner != null ? owner.name : "?")} 대형 포탄 블록 {broke.Count}칸 부숨");
                    }
                    if (sh.z < 0 && InXY((int)Math.Floor(sh.x), (int)Math.Floor(sh.y))) end = "floor";
                }
                else
                {
                    int cx = (int)Math.Floor(sh.x), cy = (int)Math.Floor(sh.y), cz = (int)Math.Floor(sh.z);
                    if (SolidAt(cx, cy, cz))
                    {
                        bool broke = BreakCell(cx, cy, cz);
                        if (broke)
                        {
                            Emit(o =>
                            {
                                o.P("type", "blockBreak").P("who", sh.owner);
                                WriteCells(o, "cells", new[] { new[] { cx, cy, cz } });
                                o.P("big", false);
                            });
                            Log($"  [포탄] {(owner != null ? owner.name : "?")} 블록 부숨 ({cx},{cy},{cz})");
                        }
                        end = broke ? "block" : "terrain";
                    }
                }
            }
            if (end == null && time >= sh.dieAt) end = "expire";
            if (end == null) continue;
            shells = shells.Where(x => x != sh).ToList();
            var what = end;
            Emit(o => o.P("type", "shellEnd").P("id", sh.id).P("who", sh.owner).P("big", sh.big).P("what", what).P("x", sh.x).P("y", sh.y).P("z", sh.z));
            if (sh.big) BigShellBlast(sh);
        }
    }

    // 대형 포탄 끝 폭발: 둘레 사람을 바깥으로
    void BigShellBlast(Shell sh)
    {
        var owner = GetPlayer(sh.owner);
        int n = 0;
        foreach (var t in Players().ToList())
        {
            if (owner == null || !Foe(owner, t)) continue;
            double dx = t.x - sh.x, dy = t.y - sh.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.CANNON_R_BLAST_RANGE || Math.Abs(t.z + 0.8 - sh.z) > C.CANNON_R_BLAST_RANGE) continue;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : sh.dir.x, d > 0.05 ? dy : sh.dir.y, C.CANNON_R_BLAST_KB_SPEED, C.CANNON_R_BLAST_KB_UP, C.CANNON_R_BLAST_STUN_MS, C.CANNON_R_BLAST_DAMAGE, new Src(sh.owner, "bigshell"), true);
            if (hit) n++;
            Emit(o => o.P("type", "hit").P("kind", "bigshell").P("by", sh.owner).P("target", t.id).P("ok", hit));
        }
        Emit(o => o.P("type", "bigShellBlast").P("who", sh.owner).P("x", sh.x).P("y", sh.y).P("z", sh.z).P("r", C.CANNON_R_BLAST_RANGE));
        Log($"  [필살] {(owner != null ? owner.name : "?")} 대형 포탄 폭발 ({n}명)");
    }
}
