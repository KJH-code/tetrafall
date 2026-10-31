using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/char-bard.js — 바드 (S3)
public sealed partial class Game
{
    // 류트 음파: 조준 방향으로 느린 음파를 날림 (UpdateNotes)
    void BardNote(Player p)
    {
        var dir = AimDir(p);
        var nt = new Note
        {
            id = ++shellCounter,
            owner = p.id,
            x = p.x + dir.x * 0.5,
            y = p.y + dir.y * 0.5,
            z = p.z + C.EYE_HEIGHT - 0.3 + dir.z * 0.5,
            dir = dir,
            dieAt = time + C.BARD_NOTE_RANGE / C.BARD_NOTE_SPEED * 1000,
        };
        notes.Add(nt);
        Emit(o => o.P("type", "noteFire").P("who", p.id).P("id", nt.id).P("x", nt.x).P("y", nt.y).P("z", nt.z)
            .Key("dir").Obj().P("x", dir.x).P("y", dir.y).P("z", dir.z).EndObj().P("speed", C.BARD_NOTE_SPEED));
    }

    // 음파 이동: 처음 닿는 사람 (약한 넉백 + 둔화) 또는 블록·바닥에서 사라짐
    public void UpdateNotes(double dt)
    {
        var def = C.BASIC_ATTACKS["bard"].chain[0];
        foreach (var nt in notes.ToList())
        {
            int sub = (int)Math.Max(1, Math.Ceiling(C.BARD_NOTE_SPEED * dt / 0.15));
            double h = dt / sub;
            double r = C.BARD_NOTE_RADIUS;
            string? end = null;
            for (int s = 0; s < sub && end == null; s++)
            {
                nt.x += nt.dir.x * C.BARD_NOTE_SPEED * h;
                nt.y += nt.dir.y * C.BARD_NOTE_SPEED * h;
                nt.z += nt.dir.z * C.BARD_NOTE_SPEED * h;
                var owner = GetPlayer(nt.owner);
                foreach (var t in Players().ToList())
                {
                    if (!OnField(t) || t.id == nt.owner || owner == null || SameTeam(owner, t)) continue;
                    if (!(nt.x > t.x - C.PLAYER_HALF - r && nt.x < t.x + C.PLAYER_HALF + r && nt.y > t.y - C.PLAYER_HALF - r && nt.y < t.y + C.PLAYER_HALF + r && nt.z > t.z - r && nt.z < t.z + C.PLAYER_HEIGHT + r)) continue;
                    bool hit = ApplyKnockback(t, nt.dir.x, nt.dir.y, U(def.kb), U(def.up), def.stun ?? C.STUN_MS, def.dmg ?? 0, new Src(nt.owner, "note"), false, new KbOpts(fixed_: true));
                    if (hit) t.slowUntil = time + C.BARD_SLOW_MS; // 둔화: 갱신만
                    Emit(o => o.P("type", "hit").P("kind", "note").P("by", nt.owner).P("target", t.id).P("ok", hit).P("streak", hit && owner != null ? owner.streak : 0));
                    Log($"  [음파] {owner.name} → {t.name} {(hit ? $"둔화 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}");
                    end = "player";
                    break;
                }
                if (end == null && SolidAt((int)Math.Floor(nt.x), (int)Math.Floor(nt.y), (int)Math.Floor(nt.z))) end = "block";
            }
            if (end == null && time >= nt.dieAt) end = "expire";
            if (end == null) continue;
            notes = notes.Where(x => x != nt).ToList();
            var what = end;
            Emit(o => o.P("type", "noteEnd").P("id", nt.id).P("who", nt.owner).P("what", what).P("x", nt.x).P("y", nt.y).P("z", nt.z));
        }
    }

    // 음유 공중 평타: 천천히 낙하 (IntegratePlayer 가 중력을 줄임)
    void BardGlide(Player p, double ms)
    {
        p.glideUntil = time + ms; // 이어 치면 다시 늘어남
        p.glideCount++;
        if (p.vz < -C.BARD_GLIDE_FALL) p.vz = -C.BARD_GLIDE_FALL;
        Emit(o => o.P("type", "glide").P("who", p.id).P("ms", ms));
    }

    // 천천히 낙하 음파 고리: 몸 둘레 def.range 안 상대를 바깥으로 작게 밀침 (고정 넉백). 맞힌 사람이 있으면 true
    bool BardGlideRing(Player p, double n, bool air, TAttack def, bool chained)
    {
        var set = BasicSet(p.@char, p.form);
        string label = BasicLabel(set, n, air, def);
        var hits = new List<int>();
        foreach (var t in Players().ToList())
        {
            if (t == p || !OnField(t) || SameTeam(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > U(def.range) || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), U(def.kb), U(def.up), def.stun ?? C.STUN_MS, def.dmg ?? 0, new Src(p.id, "glide"), false, new KbOpts(fixed_: true, chained: chained));
            if (hit)
            {
                p.freezeUntil = time + C.BASIC_HITSTOP_MS;
                t.freezeUntil = time + C.BASIC_HITSTOP_MS;
                hits.Add(t.id);
            }
            Emit(o => o.P("type", "hit").P("kind", "glide").P("by", p.id).P("target", t.id).P("ok", hit).P("n", n).P("air", air).P("finish", false).P("streak", hit ? p.streak : 0));
            Log($"  [평타] {p.name} → {t.name} {(hit ? $"넉백 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")} {label}");
        }
        Emit(o =>
        {
            o.P("type", "glideRing").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", def.range).Key("hits").Arr();
            foreach (var id in hits) o.Num(id);
            o.EndArr();
        });
        return hits.Count > 0;
    }

    // 메탈 공중 평타 기타 꽂기 시작: 아래로 빠르게, 수평으로는 느리게
    void BardDive(Player p, TAttack def)
    {
        p.dive = new Dive { until = time + C.BARD_DIVE_MAX_MS, def = def };
        p.diveUsed = true;
        p.glideUntil = 0;
        p.vz = Math.Min(p.vz, -C.BARD_DIVE_SPEED);
        p.kbx *= C.BARD_DIVE_MOVE_MULT;
        p.kby *= C.BARD_DIVE_MOVE_MULT;
        Emit(o => o.P("type", "dive").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("speed", C.BARD_DIVE_SPEED));
    }

    // 기타 꽂기 판정 (한 번): 내려가며 아래 상대에 닿으면 아래로 꽂음, 아니면 착지 때 발밑 충격
    void BardDiveUpdate(Player p)
    {
        var D = p.dive!;
        var def = D.def!;
        bool HitOne(Player t, double dx, double dy, double up, string how)
        {
            bool hit = ApplyKnockback(t, dx, dy, U(def.kb), up, def.stun ?? C.STUN_MS, def.dmg ?? 0, new Src(p.id, "push"), true, new KbOpts(finish: true));
            Emit(o => o.P("type", "hit").P("kind", "push").P("by", p.id).P("target", t.id).P("ok", hit).P("n", 1).P("air", true).P("finish", true).P("dive", how).P("streak", hit ? p.streak : 0));
            Log($"  [평타] {p.name} → {t.name} {(hit ? $"넉백 ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")} 공중 기타 꽂기{(how == "land" ? " 착지" : "")}");
            return hit;
        }
        // 내려가며 닿음: 수평 BARD_DIVE_HIT_R 안, 상대 머리가 내 발 근처~아래
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            if (JsMath.Hypot(dx, dy) > C.BARD_DIVE_HIT_R || t.z > p.z + 0.3 || t.z + C.PLAYER_HEIGHT < p.z - 0.6) continue;
            p.dive = null;
            bool landed = HitOne(t, dx != 0 && !double.IsNaN(dx) ? dx : JsMath.Cos(p.yaw), dy != 0 && !double.IsNaN(dy) ? dy : JsMath.Sin(p.yaw), U(def.up), "air");
            p.atkLanded = landed;
            Emit(o => o.P("type", "diveEnd").P("who", p.id).P("what", "hit").P("x", p.x).P("y", p.y).P("z", p.z));
            return;
        }
        if (p.grounded)
        {
            p.dive = null;
            bool any = false;
            foreach (var t in Players().ToList())
            {
                if (!Foe(p, t)) continue;
                double dx = t.x - p.x, dy = t.y - p.y;
                double d = JsMath.Hypot(dx, dy);
                if (d > C.BARD_DIVE_LAND_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
                if (HitOne(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), C.BARD_DIVE_LAND_UP, "land")) any = true;
            }
            p.atkLanded = any;
            Emit(o => o.P("type", "diveEnd").P("who", p.id).P("what", "land").P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.BARD_DIVE_LAND_RANGE));
            return;
        }
        if (time >= D.until)
        {
            p.dive = null;
            Emit(o => o.P("type", "diveEnd").P("who", p.id).P("what", "expire").P("x", p.x).P("y", p.y).P("z", p.z));
        }
    }

    // F 폼 전환: 음유 → 메탈 = 충격파 + 기타 리프, 메탈 → 음유 = 치유파
    bool BardSwitch(Player p)
    {
        p.glideUntil = 0;
        if (p.form != "metal")
        {
            p.form = "metal";
            var hits = new List<string>();
            foreach (var t in Players().ToList())
            {
                if (!Foe(p, t)) continue;
                double dx = t.x - p.x, dy = t.y - p.y;
                double d = JsMath.Hypot(dx, dy);
                if (d > C.BARD_RIFF_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
                bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), C.BARD_RIFF_KB_SPEED, C.BARD_RIFF_KB_UP, C.BARD_RIFF_STUN_MS, C.BARD_RIFF_DAMAGE, new Src(p.id, "riff"), true);
                Emit(o => o.P("type", "hit").P("kind", "riff").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
                if (hit) hits.Add($"{t.name} {JsNumber.ToJs(t.damage)}%");
            }
            Emit(o => o.P("type", "form").P("who", p.id).P("form", "metal").P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.BARD_RIFF_RANGE));
            Log($"  [스킬] {p.name} 메탈 폼 (기타 리프{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")})");
        }
        else
        {
            p.form = "bard";
            var healed = new List<(int id, double from, double to)>();
            foreach (var t in Players())
            {
                if (!OnField(t) || (t != p && (!teamMode || !SameTeam(p, t) || JsMath.Hypot(t.x - p.x, t.y - p.y) > C.BARD_HEAL_RANGE))) continue;
                double before = t.damage;
                t.damage = Math.Max(0, t.damage - C.BARD_HEAL);
                healed.Add((t.id, before, t.damage));
            }
            Emit(o =>
            {
                o.P("type", "form").P("who", p.id).P("form", "bard").P("x", p.x).P("y", p.y).P("z", p.z).Key("healed").Arr();
                foreach (var h in healed) o.Obj().P("id", h.id).P("from", h.from).P("to", h.to).EndObj();
                o.EndArr();
            });
            Log($"  [스킬] {p.name} 음유시인 폼 (치유 {string.Join(", ", healed.Select(h => $"{players[h.id].name} {JsNumber.ToJs(h.from)}% → {JsNumber.ToJs(h.to)}%"))})");
        }
        p.chainN = 0; // 평타 세트가 바뀜
        p.airN = 0;
        return true;
    }

    // 음유 R 취약의 노래: 앞 넓은 범위 상대가 BARD_VULN_MS 동안 받는 넉백 ×BARD_VULN_MULT
    void BardSong(Player p)
    {
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(C.BARD_SONG_ANGLE_DEG / 2 * Math.PI / 180);
        var hit = new List<Player>();
        foreach (var t in Players())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.BARD_SONG_RANGE || Math.Abs(t.z - p.z) > 2 || (d > 0.3 && (dx * fx + dy * fy) / d < cosHalf)) continue;
            t.vulnUntil = time + C.BARD_VULN_MS;
            hit.Add(t);
        }
        Emit(o =>
        {
            o.P("type", "song").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", p.yaw).Key("targets").Arr();
            foreach (var t in hit) o.Num(t.id);
            o.EndArr().P("ms", C.BARD_VULN_MS);
        });
        Log($"  [필살] {p.name} 취약의 노래{(hit.Count > 0 ? $" → {string.Join(", ", hit.Select(t => t.name))}" : "")}");
    }

    // 메탈 R 앰프 음파 시작
    void BardAmp(Player p)
    {
        p.amp = new Amp { endAt = time + C.BARD_AMP_MS, nextTick = time, yaw = p.yaw };
        Emit(o => o.P("type", "amp").P("who", p.id).P("ms", C.BARD_AMP_MS).P("yaw", p.yaw).P("lockYaw", C.BARD_AMP_LOCK_YAW));
        Log($"  [필살] {p.name} 앰프 음파");
    }

    // 앰프 원뿔 방향: 시작 때 방향 고정 (BARD_AMP_LOCK_YAW) 또는 지금 보는 방향
    public double AmpYaw(Player p) => C.BARD_AMP_LOCK_YAW && p.amp != null ? p.amp.yaw : p.yaw;

    // 앞 원뿔 안 상대 (앰프)
    List<Player> AmpTargets(Player p, double yaw)
    {
        double fx = JsMath.Cos(yaw), fy = JsMath.Sin(yaw);
        double cosHalf = JsMath.Cos(C.BARD_AMP_ANGLE_DEG / 2 * Math.PI / 180);
        return Players().Where(t =>
        {
            if (!Foe(p, t)) return false;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            return d <= C.BARD_AMP_RANGE && Math.Abs(t.z - p.z) <= C.PLAYER_HEIGHT && (d < 0.3 || (dx * fx + dy * fy) / d >= cosHalf);
        }).ToList();
    }

    void BardAmpUpdate(Player p)
    {
        var A = p.amp!;
        double yaw = AmpYaw(p);
        double fx = JsMath.Cos(yaw), fy = JsMath.Sin(yaw);
        if (time >= A.nextTick && time < A.endAt)
        {
            A.nextTick += C.BARD_AMP_TICK_MS;
            foreach (var t in AmpTargets(p, AmpYaw(p)))
            {
                bool hit = ApplyKnockback(t, fx, fy, C.BARD_AMP_TICK_KB, C.BARD_AMP_TICK_UP, C.BARD_AMP_TICK_STUN_MS, C.BARD_AMP_TICK_DAMAGE, new Src(p.id, "amp"), false, new KbOpts(fixed_: true, chained: true));
                Emit(o => o.P("type", "hit").P("kind", "amp").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
            }
        }
        if (time < A.endAt) return;
        p.amp = null;
        var hits = new List<string>();
        foreach (var t in AmpTargets(p, yaw))
        {
            bool hit = ApplyKnockback(t, fx, fy, C.BARD_AMP_END_KB_SPEED, C.BARD_AMP_END_KB_UP, C.BARD_AMP_END_STUN_MS, C.BARD_AMP_END_DAMAGE, new Src(p.id, "ampend"), true, new KbOpts(finish: true));
            Emit(o => o.P("type", "hit").P("kind", "ampend").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
            if (hit) hits.Add($"{t.name} {JsNumber.ToJs(t.damage)}%");
        }
        Emit(o => o.P("type", "ampEnd").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", yaw));
        Log($"  [필살] {p.name} 앰프 끝{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
    }
}
