using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/char-hunter.js — 사냥꾼 (S1: 스냅샷이 쓰는 부분, S3: 표식·추적 도약·처형 사격)
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

    // 표식 +1 (최대 HUNTER_MARK_MAX), 쌓인 시각 갱신
    public void AddMark(Player p, Player t)
    {
        var m = t.marks.TryGetValue(p.id, out var old) ? old : new Mark { n = 0, at = 0 };
        m.n = Math.Min(C.HUNTER_MARK_MAX, m.n + 1);
        m.at = time;
        t.marks[p.id] = m;
        Emit(o => o.P("type", "mark").P("by", p.id).P("target", t.id).P("n", m.n));
        Log($"  [표식] {p.name} → {t.name} {JsNumber.ToJs(m.n)}개");
    }

    // 마지막으로 쌓인 뒤 HUNTER_MARK_MS 지난 표식은 사라짐
    public void ExpireMarks(Player t)
    {
        foreach (var (by, m) in t.marks.ToList())
        {
            if (time - m.at < C.HUNTER_MARK_MS) continue;
            t.marks.Remove(by);
            Emit(o => o.P("type", "markGone").P("by", by).P("target", t.id));
        }
    }

    // F 추적 도약: 예고 HUNTER_LEAP_WINDUP_MS 뒤 표식 있는 가장 가까운 상대에게 (없으면 보는 방향 HUNTER_LEAP_DIST)
    public bool HunterLeap(Player p)
    {
        Player? target = null;
        double bd = double.PositiveInfinity;
        foreach (var t in Players())
        {
            if (!Foe(p, t) || MarkOf(p, t) == 0 || Math.Abs(t.z - p.z) > 3) continue;
            double d = JsMath.Hypot(t.x - p.x, t.y - p.y);
            if (d <= C.HUNTER_LEAP_RANGE && d < bd)
            {
                bd = d;
                target = t;
            }
        }
        p.leap = new Leap { at = time + C.HUNTER_LEAP_WINDUP_MS, target = target?.id, endAt = 0, yaw = p.yaw };
        var tg = p.leap.target;
        Emit(o => o.P("type", "leapWarn").P("who", p.id).P("target", tg).P("ms", C.HUNTER_LEAP_WINDUP_MS));
        Log($"  [스킬] {p.name} 추적 도약 준비{(target != null ? $" → {target.name}" : "")}");
        return true;
    }

    public void HunterLeapUpdate(Player p)
    {
        var L = p.leap!;
        if (L.endAt == 0)
        {
            if (time < L.at) return;
            var t = L.target != null ? GetPlayer(L.target) : null;
            XY to;
            if (t != null && Foe(p, t))
            {
                double dx = t.x - p.x, dy = t.y - p.y;
                double d = JsMath.Hypot(dx, dy);
                if (d == 0) d = 1;
                double go = Math.Max(0, d - C.HUNTER_LEAP_BEHIND);
                to = new XY(p.x + dx / d * go, p.y + dy / d * go);
                p.yaw = JsMath.Atan2(dy, dx);
            }
            else to = new XY(p.x + JsMath.Cos(L.yaw) * C.HUNTER_LEAP_DIST, p.y + JsMath.Sin(L.yaw) * C.HUNTER_LEAP_DIST);
            double sec = C.HUNTER_LEAP_MS / 1000;
            L.vx = (to.x - p.x) / sec;
            L.vy = (to.y - p.y) / sec;
            L.to = new XY(to.x, to.y);
            L.to0 = new XY(to.x, to.y);
            L.endAt = time + C.HUNTER_LEAP_MS;
            p.vz = C.HUNTER_LEAP_UP;
            p.grounded = false;
            p.kbx = 0;
            p.kby = 0;
            var tg = L.target;
            Emit(o =>
            {
                o.P("type", "leap").P("who", p.id).P("target", tg);
                o.Key("from").Obj().P("x", p.x).P("y", p.y).P("z", p.z).EndObj();
                o.Key("to").Obj().P("x", to.x).P("y", to.y).P("z", p.z).EndObj();
                o.P("ms", C.HUNTER_LEAP_MS);
            });
            return;
        }
        if (time < L.endAt)
        {
            HunterLeapHome(p, L);
            return;
        }
        p.leap = null;
        var t2 = L.target != null ? GetPlayer(L.target) : null;
        if (t2 == null || !Foe(p, t2) || JsMath.Hypot(t2.x - p.x, t2.y - p.y) > C.HUNTER_POUNCE_RANGE || Math.Abs(t2.z - p.z) > C.PLAYER_HEIGHT) return;
        // 덮침은 연타를 잇는 타: COMBO_MS 가 지나도 시간 마무리 아님
        bool hit = ApplyKnockback(t2, t2.x - p.x, t2.y - p.y, 0, 0, C.HUNTER_POUNCE_STUN_MS, C.HUNTER_POUNCE_DAMAGE, new Src(p.id, "pounce"), false, new KbOpts(chained: true));
        Emit(o => o.P("type", "hit").P("kind", "pounce").P("by", p.id).P("target", t2.id).P("ok", hit).P("streak", hit ? p.streak : 0));
        Log($"  [스킬] {p.name} 덮침 → {t2.name}{(hit ? $" ({t2.name} {JsNumber.ToJs(t2.damage)}%)" : " 무적이라 무시")}");
    }

    // 도약 유도: 내릴 자리를 대상 쪽으로 옮기고 (처음 자리에서 최대 HUNTER_LEAP_HOMING_MAX), 남은 시간에 맞춰 속도
    public void HunterLeapHome(Player p, Leap L)
    {
        var t = L.target != null ? GetPlayer(L.target) : null;
        double left = (L.endAt - time) / 1000;
        if (t == null || !Foe(p, t) || left < 0.01) return; // 마지막 순간은 그대로
        double dx = t.x - p.x, dy = t.y - p.y;
        double d = JsMath.Hypot(dx, dy);
        if (d == 0) d = 1;
        double go = Math.Max(0, d - C.HUNTER_LEAP_BEHIND);
        double wx = p.x + dx / d * go, wy = p.y + dy / d * go;
        double nx = L.to!.x + (wx - L.to.x) * C.HUNTER_LEAP_HOMING;
        double ny = L.to.y + (wy - L.to.y) * C.HUNTER_LEAP_HOMING;
        double ox = nx - L.to0!.x, oy = ny - L.to0.y;
        double off = JsMath.Hypot(ox, oy);
        if (off > C.HUNTER_LEAP_HOMING_MAX)
        {
            nx = L.to0.x + ox / off * C.HUNTER_LEAP_HOMING_MAX;
            ny = L.to0.y + oy / off * C.HUNTER_LEAP_HOMING_MAX;
        }
        L.to = new XY(nx, ny);
        L.vx = (nx - p.x) / left;
        L.vy = (ny - p.y) / left;
        p.yaw = JsMath.Atan2(dy, dx);
    }

    // R 처형 사격 조준: 대상이 하나도 없으면 안 쓰임 (게이지 그대로)
    public bool HunterAim(Player p)
    {
        var ts = ShotTargets(p).Where(t => !LineBlocked(p, t)).ToList();
        if (ts.Count == 0) return false;
        p.huntAim = new HuntAim { at = time + C.HUNTER_SHOT_WINDUP_MS };
        Emit(o =>
        {
            o.P("type", "aim").P("who", p.id).Key("targets").Arr();
            foreach (var t in ts) o.Num(t.id);
            o.EndArr().P("ms", C.HUNTER_SHOT_WINDUP_MS);
        });
        Log($"  [필살] {p.name} 처형 사격 조준 ({string.Join(", ", ts.Select(t => $"{t.name} {JsNumber.ToJs(MarkOf(p, t))}개"))})");
        return true;
    }

    // 쏨 (즉시 판정): 지금 보는 방향 안 표식 대상 전부. 블록이 가리면 막힘. 표식 수만큼 세게, 표식 소모. 최대 표식 대상을 맞히면 게이지 돌려받음
    public void HunterShoot(Player p)
    {
        p.huntAim = null;
        var shots = new List<(int target, double marks, bool blocked, bool? ok, double x, double y, double z)>();
        bool refund = false;
        foreach (var t in ShotTargets(p))
        {
            double n = MarkOf(p, t);
            if (LineBlocked(p, t))
            {
                shots.Add((t.id, n, true, null, t.x, t.y, t.z + 1));
                continue;
            }
            bool hit = ApplyKnockback(t, t.x - p.x, t.y - p.y, C.HUNTER_SHOT_KB_BASE + n * C.HUNTER_SHOT_KB_PER_MARK, C.HUNTER_SHOT_UP, C.HUNTER_SHOT_STUN_MS, n * C.HUNTER_SHOT_DAMAGE_PER_MARK, new Src(p.id, "execute"), true);
            Emit(o => o.P("type", "hit").P("kind", "execute").P("by", p.id).P("target", t.id).P("ok", hit).P("marks", n));
            if (hit)
            {
                t.marks.Remove(p.id);
                if (n >= C.HUNTER_MARK_MAX) refund = true;
            }
            shots.Add((t.id, n, false, hit, t.x, t.y, t.z + 1));
        }
        Emit(o =>
        {
            o.P("type", "shot").P("who", p.id);
            o.Key("from").Obj().P("x", p.x).P("y", p.y).P("z", p.z + C.EYE_HEIGHT).EndObj();
            o.Key("shots").Arr();
            foreach (var s in shots)
            {
                o.Obj().P("target", s.target).P("marks", s.marks).P("blocked", s.blocked);
                if (s.ok is bool ok) o.P("ok", ok);
                o.Key("to").Obj().P("x", s.x).P("y", s.y).P("z", s.z).EndObj().EndObj();
            }
            o.EndArr();
        });
        if (refund)
        {
            p.ult = UltMax(p);
            Emit(o => o.P("type", "ultRefund").P("who", p.id));
        }
        var txt = string.Join(", ", shots.Select(x => $"{players[x.target].name} {JsNumber.ToJs(x.marks)}개{(x.blocked ? " 막힘" : "")}"));
        Log($"  [필살] {p.name} 처형 사격 ({(txt != "" ? txt : "대상 없음")}){(refund ? " 게이지 회수" : "")}");
    }
}
