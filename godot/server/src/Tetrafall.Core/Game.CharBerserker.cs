using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/char-berserker.js — 광전사 (S3)
public sealed partial class Game
{
    // 분노 배율: 피해 % 에 비례, 상한 없음
    public double RageMult(double damage) => 1 + damage * C.BERSERKER_RAGE_PER_PERCENT;

    // F 광폭 도약: 보는 방향으로 크게 뜀 → 땅에 닿으면 착지 충격파 (BerserkerLeapUpdate)
    public bool BerserkerLeap(Player p)
    {
        double sec = C.BERSERKER_LEAP_MS / 1000;
        double v = C.BERSERKER_LEAP_DIST / sec;
        p.rush = new Rush { endAt = time + C.BERSERKER_LEAP_MS, vx = JsMath.Cos(p.yaw) * v, vy = JsMath.Sin(p.yaw) * v, landBy = time + C.BERSERKER_LEAP_MS + C.BERSERKER_LEAP_LAND_MS };
        p.vz = C.BERSERKER_LEAP_UP;
        p.grounded = false;
        p.kbx = 0;
        p.kby = 0;
        double tx = p.x + JsMath.Cos(p.yaw) * C.BERSERKER_LEAP_DIST, ty = p.y + JsMath.Sin(p.yaw) * C.BERSERKER_LEAP_DIST, tz = p.z;
        Emit(o =>
        {
            o.P("type", "rush").P("who", p.id);
            o.Key("from").Obj().P("x", p.x).P("y", p.y).P("z", p.z).EndObj();
            o.Key("to").Obj().P("x", tx).P("y", ty).P("z", tz).EndObj();
            o.P("ms", C.BERSERKER_LEAP_MS);
        });
        Log($"  [스킬] {p.name} 광폭 도약");
        return true;
    }

    public void BerserkerLeapUpdate(Player p)
    {
        if (time < p.rush!.endAt) return;
        if (!p.grounded)
        {
            if (time >= p.rush.landBy) p.rush = null; // 너무 오래 떨어짐 (낭떠러지): 충격파 없음
            return;
        }
        p.rush = null;
        var hits = new List<string>();
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.BERSERKER_WAVE_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), C.BERSERKER_WAVE_KB_SPEED, C.BERSERKER_WAVE_KB_UP, C.BERSERKER_WAVE_STUN_MS, C.BERSERKER_WAVE_DAMAGE, new Src(p.id, "leapwave"), true);
            Emit(o => o.P("type", "hit").P("kind", "leapwave").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
            if (hit) hits.Add($"{t.name} {JsNumber.ToJs(t.damage)}%");
        }
        if (hits.Count > 0 && p.chainN > 0) p.chainUntil = time + C.BASIC_CHAIN_WINDOW_MS; // F → 평 평
        Emit(o => o.P("type", "rushLand").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.BERSERKER_WAVE_RANGE));
        Log($"  [스킬] {p.name} 착지 충격파{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
    }

    // R 분노 소용돌이: 피해 % 를 깎고 (최대 BERSERKER_RAGE_CUT), 깎은 뒤 피해 % 를 마지막 날림 분노로 기억
    public void BerserkerSpin(Player p)
    {
        double before = p.damage;
        double cut = Math.Min(C.BERSERKER_RAGE_CUT, p.damage);
        p.damage -= cut;
        double rage = p.damage;
        p.spin = new Spin { endAt = time + C.BERSERKER_SPIN_MS, nextTick = time, rage = rage };
        Emit(o => o.P("type", "spin").P("who", p.id).P("ms", C.BERSERKER_SPIN_MS).P("rage", RageMult(rage)).P("cut", cut).P("damage", p.damage));
        Log($"  [필살] {p.name} 분노 소용돌이 (분노 ×{JsNumber.ToFixed(RageMult(rage), 2)}, 피해 {JsNumber.ToJs(before)}% → {JsNumber.ToJs(p.damage)}%)");
    }

    public void BerserkerSpinUpdate(Player p)
    {
        var S = p.spin!;
        if (time >= S.nextTick && time < S.endAt)
        {
            S.nextTick += C.BERSERKER_SPIN_TICK_MS;
            foreach (var t in Players().ToList())
            {
                if (!Foe(p, t)) continue;
                double dx = t.x - p.x, dy = t.y - p.y;
                double d = JsMath.Hypot(dx, dy);
                if (d > C.BERSERKER_SPIN_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
                // 작은 밀침: 바깥으로, 고정 넉백, 연타로 침 (시간 마무리 안 됨)
                bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), C.BERSERKER_SPIN_TICK_KB, C.BERSERKER_SPIN_TICK_UP, C.BERSERKER_SPIN_TICK_STUN_MS, C.BERSERKER_SPIN_TICK_DAMAGE, new Src(p.id, "spin"), false, new KbOpts(fixed_: true, chained: true));
                Emit(o => o.P("type", "hit").P("kind", "spin").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
            }
        }
        if (time < S.endAt) return;
        p.spin = null;
        var hits = new List<string>();
        foreach (var t in Players().ToList())
        {
            if (!Foe(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double d = JsMath.Hypot(dx, dy);
            if (d > C.BERSERKER_SPIN_END_RANGE || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            bool hit = ApplyKnockback(t, d > 0.05 ? dx : JsMath.Cos(p.yaw), d > 0.05 ? dy : JsMath.Sin(p.yaw), C.BERSERKER_SPIN_END_KB_SPEED, C.BERSERKER_SPIN_END_KB_UP, C.BERSERKER_SPIN_END_STUN_MS, C.BERSERKER_SPIN_END_DAMAGE, new Src(p.id, "spinend", S.rage), true, new KbOpts(finish: true));
            Emit(o => o.P("type", "hit").P("kind", "spinend").P("by", p.id).P("target", t.id).P("ok", hit).P("streak", hit ? p.streak : 0));
            if (hit) hits.Add($"{t.name} {JsNumber.ToJs(t.damage)}%");
        }
        Emit(o => o.P("type", "spinEnd").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("r", C.BERSERKER_SPIN_END_RANGE).P("rage", RageMult(S.rage)));
        Log($"  [필살] {p.name} 소용돌이 끝{(hits.Count > 0 ? $" → {string.Join(", ", hits)}" : "")}");
    }
}
