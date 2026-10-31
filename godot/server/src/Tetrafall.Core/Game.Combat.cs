using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// 넉백을 준 쪽 (JS src 객체 { by, kind, rage? }) — 킬 판정 lastHit·콤보·광전사 분노
public sealed class Src
{
    public int by;
    public string kind = "";
    public double? rage; // 광전사 R 마지막 날림: R 시작 때 피해 % (없으면 지금 피해 %)

    public Src(int by, string kind, double? rage = null)
    {
        this.by = by;
        this.kind = kind;
        this.rage = rage;
    }
}

// applyKnockback opts (평타): fixed = 중간 타 고정 넉백, finish = 마무리 타, chained = 연타를 이어 가는 중인 타
public readonly record struct KbOpts(bool fixed_ = false, bool finish = false, bool chained = false);

// 평타 한 줄 (shared/config.js BASIC_ATTACKS[char] 또는 바드 메탈 폼)
public readonly record struct BasicSetT(TAttack[] chain, TAttack[] air);

// 닌자 R 강화 표창 (JS: {...def, name: '표창', windup, step: 0, star: true}) — 생성된 TAttack 에 star 칸을 더함
public sealed partial class TAttack
{
    public bool star;

    public TAttack Clone() => (TAttack)MemberwiseClone();
}

// server/game-combat.js — 대시·밀치기·캐릭터 평타·스킬/필살기 발동·넉백·콤보 (S3)
public sealed partial class Game
{
    // shared/config.js basicSet: 바드 메탈 폼이면 metal 줄
    public static BasicSetT BasicSet(string? ch, string form)
    {
        var set = C.BASIC_ATTACKS[ch!];
        return set.metal != null && form == "metal" ? new BasicSetT(set.metal.chain, set.metal.air) : new BasicSetT(set.chain, set.air);
    }

    // game-util.js basicLabel: "2타 반대 찌르기", 공중이면 "공중 망치 내려찍기" (공중 연타가 있으면 "공중 2타 …")
    public static string BasicLabel(BasicSetT set, double n, bool air, TAttack def) =>
        air ? $"공중 {(set.air.Length > 1 ? $"{JsNumber.ToJs(n)}타 " : "")}{def.name}" : $"{JsNumber.ToJs(n)}타 {def.name}";

    public static bool Truthy(double? v) => v is double d && d != 0 && !double.IsNaN(d);
    public static double U(double? v) => v ?? double.NaN; // JS undefined 를 셈에 쓰면 NaN

    // ---------- 전투 ----------
    public void Dash(Player p)
    {
        double dx = JsMath.Cos(p.yaw), dy = JsMath.Sin(p.yaw);
        var mv = MoveDir(p);
        if (mv != null)
        {
            dx = mv.x;
            dy = mv.y;
        }
        p.kbx = dx * C.DASH_SPEED;
        p.kby = dy * C.DASH_SPEED;
        p.dashReadyAt = time + C.DASH_COOLDOWN_MS;
        if (!p.grounded) p.airDashes--;
    }

    public void Push(Player p)
    {
        p.pushReadyAt = time + C.PUSH_COOLDOWN_MS;
        p.atkLanded = false;
        const string kind = "push";
        double speed = C.PUSH_KB_SPEED, up = C.PUSH_KB_UP, stun = C.STUN_MS;
        Emit(o => o.P("type", "swing").P("who", p.id).P("kind", kind));
        bool falling = !p.grounded && p.vz < 0; // 치명타: 떨어지면서 때림 (높이 조건은 상대마다)
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(C.PUSH_HALF_ANGLE_DEG * Math.PI / 180);
        foreach (var t in Players().ToList())
        {
            if (t == p || !OnField(t) || SameTeam(p, t)) continue; // 같은 팀은 그냥 통과
            double dx = t.x - p.x, dy = t.y - p.y;
            double dist = JsMath.Hypot(dx, dy);
            if (dist > C.PUSH_RANGE) continue;
            if (Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            if (dist > EPS && (dx * fx + dy * fy) / dist < cosHalf) continue;
            bool crit = falling && p.z - t.z >= C.CRIT_MIN_HEIGHT;
            double gain = crit ? JsMath.Round(C.DAMAGE_GAIN[kind] * C.CRIT_DAMAGE_MULT) : C.DAMAGE_GAIN[kind];
            bool hit = ApplyKnockback(t, fx, fy, crit ? speed * C.CRIT_KB_MULT : speed, up, stun, gain, new Src(p.id, kind));
            double stop = crit ? C.HITSTOP_MS * C.CRIT_HITSTOP_MULT : C.HITSTOP_MS;
            if (hit)
            {
                p.freezeUntil = time + stop; // 때린 쪽도 같이 멈칫
                t.freezeUntil = time + stop;
            }
            if (hit && !SameTeam(p, t)) p.atkLanded = true; // 맞혔으면 F·R 로 쿨 캔슬
            Emit(o => o.P("type", "hit").P("kind", kind).P("by", p.id).P("target", t.id).P("ok", hit).P("crit", hit && crit));
            Log($"  [밀치기] {p.name} → {t.name} {(hit ? $"넉백{(crit ? " 치명타" : "")} ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")}");
        }
    }

    // F·R 캔슬: 평타가 맞은 뒤 후딜이면 후딜을 끊고 바로. 빗나간 뒤 후딜이면 후딜이 끝나고. 평타 준비 중이면 기억했다가 판정 결과에 따라
    public void Cast(Player p, string kind)
    {
        if (p.atk != null || (time < p.pushReadyAt && !p.atkLanded))
        {
            p.castQueued = kind;
            p.atkQueued = false; // 나중에 누른 스킬이 먼저 누른 평타 선입력보다 우선
            return;
        }
        if (time < p.pushReadyAt) p.pushReadyAt = time; // 맞힌 평타의 후딜 캔슬
        if (kind == "skill") UseSkill(p);
        else if (!UseUlt(p))
        {
            // 못 씀 (게이지 그대로): 화면이 알 수 있게
            string reason = Truthy(p.slamAt) || Truthy(p.wallAt) || p.grab != null || p.huntAim != null || p.rush != null || p.spin != null || p.amp != null || time < p.chargeUntil ? "busy" : p.@char == "hook" ? "noBlock" : p.@char == "hunter" ? "noTarget" : "noSpace";
            Emit(o => o.P("type", "ultFail").P("who", p.id).P("reason", reason));
            Log($"  [필살] {p.name} 못 씀 ({reason})");
        }
    }

    // 기억한 F·R 을 지금 쓸 수 있으면 씀 (맞힌 평타 판정 직후 또는 후딜 끝)
    public void CastQueuedNow(Player p)
    {
        var kind = p.castQueued!;
        p.castQueued = null;
        if (time < p.stunUntil || IsControlling(p) || (kind == "skill" ? time < p.skillReadyAt : p.ult < UltMax(p)))
        {
            Emit(o => o.P("type", "castDrop").P("who", p.id).P("kind", kind)); // 기억했던 F·R 이 버려짐 (소모 없음)
            return;
        }
        Cast(p, kind);
    }

    // ---------- 캐릭터 평타 (BASIC_ATTACKS) ----------
    // 준비·후딜 중에 누르면 기다렸다 나감 (UpdateCombat)
    public void BasicPress(Player p)
    {
        if (p.atk != null || time < p.pushReadyAt)
        {
            p.atkQueued = true;
            return;
        }
        BasicStart(p);
    }

    // 몇 번째 타인지 정하고 준비 시작. 지상·공중 각각 이어 치기 창 안이면 다음 타, 아니면 1타
    public void BasicStart(Player p)
    {
        var set = BasicSet(p.@char, p.form);
        bool air = !p.grounded;
        bool live = time < p.chainUntil;
        double n = air ? (p.airN > 0 && live && p.airN < set.air.Length ? p.airN + 1 : 1) : p.chainN > 0 && live && p.chainN < set.chain.Length ? p.chainN + 1 : 1;
        var def = air ? set.air[(int)n - 1] : set.chain[(int)n - 1];
        if (def.dive && p.diveUsed) return; // 바드 기타 꽂기: 착지 전 1번
        if (def.loaded != null && p.loaded) def = def.loaded; // 갈고리 3타: 장전돼 있으면 탕
        if (def.ammo != null && p.cannonAmmo > 0) def = def.ammo; // 대포수: 탄이 있으면 포탄
        // 닌자 R 강화: 지상 1~3타와 공중 평타가 표창 2연발 (4타 올려 차기는 그대로)
        if (p.@char == "ninja" && time < p.empowerUntil && (air || n <= 3))
        {
            def = def.Clone();
            def.name = "표창";
            def.windup = C.NINJA_STAR["windup"];
            def.step = 0;
            def.star = true;
        }
        // 연타를 이어 가는 중인 타: 시간 마무리가 되지 않음
        bool chained = air ? (p.airN > 0 && live) || time < p.launchUntil : n > 1;
        p.atk = new Atk { n = n, def = def, air = air, chained = chained, at = time + def.windup };
        p.atkLanded = false;
        p.pushReadyAt = time + def.windup + def.rec;
        bool glided = def.glide && p.glideCount < C.BARD_GLIDE_MAX_PER_AIR; // 횟수를 다 쓰면 낙하도 고리도 없음
        if (glided) BardGlide(p, def.windup + def.rec);
        if (glided) p.atk.glided = true;
        if (def.dive) BardDive(p, def); // 바드 기타 꽂기: 누르는 순간 아래로
        var d = def;
        Emit(o => o.P("type", "attack").P("who", p.id).P("char", p.@char).P("n", n).P("air", air).P("name", d.name).P("windup", d.windup).P("finish", d.finish).P("star", d.star));
        if (def.windup <= 0) BasicHit(p);
    }

    // 판정: 앞으로 step 만큼 나가며 부채꼴 안을 침. 중간 타는 고정 넉백, 마무리 타·공중 평타는 % 배율
    public void BasicHit(Player p)
    {
        var atk = p.atk!;
        double n = atk.n;
        var def = atk.def;
        bool air = atk.air, chained = atk.chained, glided = atk.glided;
        p.atk = null;
        var set = BasicSet(p.@char, p.form);
        if (def.star)
        {
            StarVolley(p, n, air, def, chained);
            return;
        }
        if (def.shell)
        {
            CannonShot(p);
            BasicChain(p, n, air, false, def);
            return;
        }
        if (def.note || def.glide || def.dive)
        {
            // 기타 꽂기 판정은 낙하 중 (BardDiveUpdate)
            if (def.note) BardNote(p); // 천천히 낙하는 누를 때 시작 (BasicStart)
            bool l = glided && BardGlideRing(p, n, air, def, chained);
            BasicChain(p, n, air, l, def);
            return;
        }
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        if (Truthy(def.step))
        {
            // 앞으로 나가되 앞 상대를 지나치지 않게 (BASIC_STEP_GAP 앞에서 멈춤)
            double step = def.step!.Value;
            foreach (var t in Players())
            {
                if (!Foe(p, t) || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
                double along = (t.x - p.x) * fx + (t.y - p.y) * fy;
                double side = Math.Abs((t.x - p.x) * fy - (t.y - p.y) * fx);
                if (along > 0 && side < C.BASIC_STEP_GAP) step = Math.Min(step, Math.Max(0, along - C.BASIC_STEP_GAP));
            }
            MoveAxis(p, 0, fx * step);
            MoveAxis(p, 1, fy * step);
        }
        Emit(o => o.P("type", "swing").P("who", p.id).P("kind", "push").P("char", p.@char).P("n", n));
        if (def.shot)
        {
            p.loaded = false; // 탕: 쏘면 빈 총 (맞든 안 맞든)
            Emit(o => o.P("type", "bang").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", p.yaw));
        }
        double range = Truthy(def.range) ? def.range!.Value : C.PUSH_RANGE;
        double cosHalf = JsMath.Cos((def.angle ?? C.PUSH_HALF_ANGLE_DEG) * Math.PI / 180);
        bool falling = !p.grounded && p.vz < 0;
        bool finish = def.finish;
        bool single = air && set.air.Length == 1; // 공중 한 타짜리: 예전처럼 % 배율 넉백·보통 멈칫
        string label = BasicLabel(set, n, air, def);
        Player? landed = null; // 처음 맞힌 상대 (같은 팀 빼고)
        foreach (var t in Players().ToList())
        {
            if (t == p || !OnField(t) || SameTeam(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double dist = JsMath.Hypot(dx, dy);
            if (dist > range || Math.Abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
            if (dist > C.BASIC_STEP_GAP && (dx * fx + dy * fy) / dist < cosHalf) continue; // 몸이 붙어 있으면 방향 상관없이
            bool crit = air && falling && p.z - t.z >= C.CRIT_MIN_HEIGHT; // 치명타는 공중 평타만
            double gain = crit ? JsMath.Round(U(def.dmg) * C.CRIT_DAMAGE_MULT) : U(def.dmg);
            double speed = crit ? U(def.kb) * C.CRIT_KB_MULT : U(def.kb);
            bool radial = def.radial && dist > 0.05; // 사방 치는 타 (광전사 회전 베기): 바깥으로
            bool hit = ApplyKnockback(t, radial ? dx : fx, radial ? dy : fy, speed, U(def.up), def.stun ?? C.STUN_MS, gain, new Src(p.id, "push"), finish, new KbOpts(!single && !finish, finish, chained));
            if (hit)
            {
                double stop = (finish ? C.BASIC_FINISH_HITSTOP_MS : single ? C.HITSTOP_MS : C.BASIC_HITSTOP_MS) * (crit ? C.CRIT_HITSTOP_MULT : 1) * (t.counterAt == time ? C.COUNTER_HITSTOP_MULT : 1);
                p.freezeUntil = time + stop;
                t.freezeUntil = time + stop;
                if (landed == null && !SameTeam(p, t)) landed = t;
                if (def.mark && !SameTeam(p, t)) AddMark(p, t); // 사냥꾼 찔러 넣기: 표식 +1
            }
            Emit(o => o.P("type", "hit").P("kind", "push").P("by", p.id).P("target", t.id).P("ok", hit).P("crit", hit && crit).P("n", n).P("air", air).P("finish", finish).P("streak", hit ? p.streak : 0));
            Log($"  [평타] {p.name} → {t.name} {(hit ? $"넉백{(crit ? " 치명타" : "")} ({t.name} {JsNumber.ToJs(t.damage)}%)" : "무적이라 무시")} {label}");
        }
        BasicChain(p, n, air, landed != null, def);
        if (p.@char == "builder" && HammerBlocks(p, range, cosHalf)) p.atkLanded = true; // 망치로 내 블록을 치면 폭발
        if (def.raise) BasicRaise(p, landed);
    }

    // 평타 한 타가 끝난 뒤: 이어 치기 번호·창, 맞혔는지, 닌자 F 쿨 감소
    public void BasicChain(Player p, double n, bool air, bool landed, TAttack def)
    {
        var set = BasicSet(p.@char, p.form);
        // 띄우는 마지막 지상 타(마무리 아님) 뒤에는 후딜 + 이어 치기 창 동안 공중 1타가 연타로 이어짐
        if (!air && n == set.chain.Length && !def.finish) p.launchUntil = time + def.rec + C.BASIC_CHAIN_WINDOW_MS;
        if (air)
        {
            p.airN = n < set.air.Length ? n : 0;
            if (p.airN > 0 || p.chainN > 0) p.chainUntil = time + C.BASIC_CHAIN_WINDOW_MS; // 지상 타 번호도 그대로
        }
        else if (n < set.chain.Length)
        {
            p.chainN = n;
            p.chainUntil = time + C.BASIC_CHAIN_WINDOW_MS;
        }
        else p.chainN = 0;
        p.atkLanded = landed;
        p.lastBasic = new LastBasic { n = n, air = air, at = time };
        if (landed) NinjaCdCut(p);
    }

    // 닌자 적중 보상: 평타가 맞을 때마다 F 쿨 NINJA_HIT_CD_CUT_MS 줄어듦
    public void NinjaCdCut(Player p)
    {
        if (p.@char == "ninja") p.skillReadyAt = Math.Max(time, p.skillReadyAt - C.NINJA_HIT_CD_CUT_MS);
    }

    // 닌자 R 강화 표창 2연발: 첫 발은 지금, 둘째 발은 NINJA_STAR.gap 뒤 (UpdateCombat). 즉시 판정
    public void StarVolley(Player p, double n, bool air, TAttack def, bool chained)
    {
        bool landed = StarShot(p, n, air, def, 1, chained);
        BasicChain(p, n, air, landed, def);
        p.star2 = new Star2 { at = time + C.NINJA_STAR["gap"], n = n, air = air, def = def, chained = chained };
    }

    // 표창 한 발: 보는 방향 좁은 각 NINJA_STAR.range 안 가장 가까운 상대 하나. 마무리 타 자리면 둘째 발이 그 타의 마무리
    public bool StarShot(Player p, double n, bool air, TAttack def, int shot, bool chained = false)
    {
        var S = C.NINJA_STAR;
        var set = BasicSet(p.@char, p.form);
        double fx = JsMath.Cos(p.yaw), fy = JsMath.Sin(p.yaw);
        double cosHalf = JsMath.Cos(S["angle"] * Math.PI / 180);
        Player? best = null;
        double bd = double.PositiveInfinity;
        foreach (var t in Players())
        {
            if (t == p || !OnField(t) || SameTeam(p, t)) continue;
            double dx = t.x - p.x, dy = t.y - p.y;
            double dist = JsMath.Hypot(dx, dy);
            if (dist > S["range"] || Math.Abs(t.z - p.z) > S["range"] || dist < EPS || (dx * fx + dy * fy) / dist < cosHalf) continue;
            if (dist < bd)
            {
                bd = dist;
                best = t;
            }
        }
        bool fin = shot == 2 && def.finish;
        double fromX = p.x, fromY = p.y, fromZ = p.z + C.EYE_HEIGHT - 0.3;
        var b = best;
        Emit(o =>
        {
            o.P("type", "star").P("who", p.id).P("shot", shot).Key("target");
            if (b != null) o.Num(b.id); else o.Null();
            o.Key("from").Obj().P("x", fromX).P("y", fromY).P("z", fromZ).EndObj();
            if (b != null) o.Key("to").Obj().P("x", b.x).P("y", b.y).P("z", b.z + 0.8).EndObj();
            else o.Key("to").Obj().P("x", p.x + fx * S["range"]).P("y", p.y + fy * S["range"]).P("z", fromZ).EndObj();
        });
        if (best == null) return false;
        bool falling = !p.grounded && p.vz < 0;
        bool crit = air && falling && p.z - best.z >= C.CRIT_MIN_HEIGHT;
        double dmg = fin ? U(def.dmg) : S["dmg"];
        double gain = crit ? JsMath.Round(dmg * C.CRIT_DAMAGE_MULT) : dmg;
        bool hit = ApplyKnockback(best, fx, fy, (fin ? U(def.kb) : S["kb"]) * (crit ? C.CRIT_KB_MULT : 1), fin ? U(def.up) : S["up"], fin ? def.stun ?? C.STUN_MS : S["stun"], gain, new Src(p.id, "push"), fin, new KbOpts(!fin, fin, chained || shot == 2));
        if (hit)
        {
            double stop = (fin ? C.BASIC_FINISH_HITSTOP_MS : C.BASIC_HITSTOP_MS) * (crit ? C.CRIT_HITSTOP_MULT : 1) * (best.counterAt == time ? C.COUNTER_HITSTOP_MULT : 1);
            best.freezeUntil = time + stop;
        }
        bool ok = hit && !SameTeam(p, best);
        Emit(o => o.P("type", "hit").P("kind", "push").P("by", p.id).P("target", b!.id).P("ok", hit).P("crit", hit && crit).P("n", n).P("air", air).P("finish", fin).P("star", true).P("streak", hit ? p.streak : 0));
        Log($"  [평타] {p.name} → {best.name} {(hit ? $"넉백{(crit ? " 치명타" : "")} ({best.name} {JsNumber.ToJs(best.damage)}%)" : "무적이라 무시")} {BasicLabel(set, n, air, def)}");
        return ok;
    }

    // ---------- 캐릭터 스킬·필살기 ----------
    public bool OtherMoveActive(Player p) => Truthy(p.slamAt) || Truthy(p.wallAt) || p.grab != null || p.leap != null || p.windup != null || p.hookFly != null || p.huntAim != null || p.rush != null || p.spin != null || p.amp != null || time < p.chargeUntil;

    public bool UseSkill(Player p)
    {
        if (OtherMoveActive(p)) return false; // 다른 기술 발동 중
        p.skillReadyAt = time + C.SKILL_CD_MS[p.@char!]; // 먼저 걸어 둠
        if (p.grounded && C.SKILL_WINDUP_CHARS.Contains(p.@char))
        {
            // 이동 스킬 지상 예고: SKILL_WINDUP_MS 뒤 누른 순간 방향으로 나감 (UpdateCombat → FireWindup)
            p.windup = new Windup { at = time + C.SKILL_WINDUP_MS, yaw = p.yaw };
            Emit(o => o.P("type", "skillWindup").P("who", p.id).P("kind", p.@char).P("ms", C.SKILL_WINDUP_MS));
            Log($"  [스킬] {p.name} {C.CHAR_NAMES[p.@char!]} F 준비");
            return true;
        }
        return FireSkill(p);
    }

    // 이동 스킬 예고가 끝남: 누른 순간 방향으로 나감 (지금 보는 방향은 나간 뒤 돌려 둠)
    public void FireWindup(Player p)
    {
        double yaw = p.yaw;
        p.yaw = p.windup!.yaw;
        p.windup = null;
        if (!FireSkill(p)) Log($"  [스킬] {p.name} {C.CHAR_NAMES[p.@char!]} F 못 나감 (자리 없음, 쿨타임 안 씀)");
        p.yaw = yaw;
    }

    // F 를 실제로 냄 (쿨타임은 UseSkill 이 걸어 둠)
    public bool FireSkill(Player p)
    {
        bool ok = p.@char switch
        {
            "tank" => TankCharge(p),
            "ninja" => NinjaBlink(p),
            "builder" => BuilderWall(p),
            "hunter" => HunterLeap(p),
            "cannon" => CannonJump(p),
            "berserker" => BerserkerLeap(p),
            "bard" => BardSwitch(p),
            _ => HookPull(p),
        };
        if (!ok)
        {
            p.skillReadyAt = time; // 못 쓰는 상황이면 쿨타임 안 돎
            return false;
        }
        if (p.chainN > 0 && time < p.chainUntil) p.chainUntil = time + C.BASIC_CHAIN_WINDOW_MS; // 평타 → 스킬 → 평타
        Emit(o => o.P("type", "skill").P("who", p.id).P("char", p.@char).P("x", p.x).P("y", p.y).P("z", p.z));
        return true;
    }

    public bool UseUlt(Player p)
    {
        if (OtherMoveActive(p)) return false;
        if (p.@char == "tank") TankSlamStart(p);
        else if (p.@char == "ninja") NinjaEmpower(p);
        else if (p.@char == "builder")
        {
            if (!BuilderBigBomb(p)) return false; // 솟을 자리가 없으면 게이지 그대로
        }
        else if (p.@char == "cannon") CannonBig(p);
        else if (p.@char == "berserker") BerserkerSpin(p);
        else if (p.@char == "bard")
        {
            if (p.form == "metal") BardAmp(p);
            else BardSong(p);
        }
        else if (p.@char == "hunter")
        {
            if (!HunterAim(p)) return false; // 사냥꾼: 쏠 표식 대상이 없으면 게이지 그대로
        }
        else if (!HookGrab(p)) return false; // 갈고리: 닿는 블록이 없으면 게이지 그대로
        p.ult = 0;
        Emit(o => o.P("type", "ult").P("who", p.id).P("char", p.@char).P("x", p.x).P("y", p.y).P("z", p.z));
        return true;
    }

    // 남에게 맞힐 수 있는 상대인가 (필드 위·다른 팀·나 아님)
    public bool Foe(Player p, Player t) => t != p && OnField(t) && !SameTeam(p, t);

    // 틱마다: 콤보가 끊긴 사람 무적, 돌진 부딪힘, 내려찍기·솟는 벽·블록 내려찍기 발동
    public void UpdateCombat()
    {
        if (bblocks.Count > 0 || bigBombs.Count > 0 || holes.Count > 0) UpdateBBlocks();
        if (quakes.Count > 0) UpdateQuakes();
        foreach (var p in Players().ToList())
        {
            if (!players.ContainsKey(p.id)) continue;
            if (p.comboHits > 0 && time >= p.stunUntil) EndCombo(p);
            if (!OnField(p))
            {
                p.chargeUntil = p.slamAt = p.wallAt = p.zipUntil = 0;
                p.leap = null;
                p.huntAim = null;
                p.rush = null;
                p.spin = null;
                p.amp = null;
                p.windup = p.hookFly = null;
                p.glideUntil = 0;
                p.dive = null;
                p.marks.Clear();
                if (p.grab != null) HookGrabDrop(p);
                p.atk = null;
                p.atkQueued = false;
                p.castQueued = null;
                p.star2 = null;
                continue;
            }
            if (p.atk != null && time >= p.atk.at) BasicHit(p);
            if (p.star2 != null && time >= p.star2.at)
            {
                var s2 = p.star2;
                p.star2 = null;
                if (StarShot(p, s2.n, s2.air, s2.def, 2, s2.chained))
                {
                    p.atkLanded = true;
                    NinjaCdCut(p);
                }
            }
            if (p.@char == "ninja") NinjaTouch(p);
            if (p.marks.Count > 0) ExpireMarks(p);
            if (p.@char == "cannon") CannonReload(p);
            if (p.windup != null && time >= p.windup.at) FireWindup(p);
            if (p.hookFly != null && time >= p.hookFly.at) HookLand(p);
            if (p.leap != null) HunterLeapUpdate(p);
            if (p.rush != null) BerserkerLeapUpdate(p);
            if (p.spin != null) BerserkerSpinUpdate(p);
            if (p.amp != null) BardAmpUpdate(p);
            if (p.dive != null) BardDiveUpdate(p);
            if (p.huntAim != null && time >= p.huntAim.at) HunterShoot(p);
            if (p.castQueued != null && p.atk == null && (p.atkLanded || time >= p.pushReadyAt)) CastQueuedNow(p);
            else if (p.atkQueued && p.atk == null && time >= p.pushReadyAt)
            {
                p.atkQueued = false;
                if (time >= p.stunUntil && !IsControlling(p)) BasicStart(p);
            }
            if (time < p.chargeUntil) ChargeHit(p);
            if (Truthy(p.slamAt) && time >= p.slamAt) TankSlam(p);
            if (Truthy(p.wallAt) && time >= p.wallAt) BuilderWallRise(p);
            if (p.grab != null && time >= p.grab.at) HookSlam(p);
        }
    }

    // src: 누가 무엇으로 날렸는지 (킬 판정용 lastHit). heavy: 무거운 공격은 콤보 중에도 넉백을 안 줄임.
    // opts.fixed_: 평타 중간 타 — 넉백 고정. opts.finish: 평타 마무리 타 — 콤보 2타 이상이면 시간과 상관없이 마무리
    public bool ApplyKnockback(Player t, double dx, double dy, double speed, double up, double stunMs = C.STUN_MS, double gain = 0, Src? src = null, bool heavy = false, KbOpts opts = default)
    {
        if (Invulnerable(t)) return false; // 콤보 뒤 무적·부활 무적
        bool teammate = src != null && SameTeam(GetPlayer(src.by), t);
        if (teammate) return false; // 팀전에서 같은 팀 공격은 아무 효과 없음
        // 탱크 아머 (F 돌진 중·R 떠오르는 동안): 넉백·경직 없이 피해 % 만. 마무리 타·필살기면 깨지고 보통처럼
        bool armorBroken = false;
        if (!teammate && t.@char == "tank" && (time < t.chargeUntil || Truthy(t.slamAt)))
        {
            string name = GetPlayer(src?.by)?.name is { Length: > 0 } nm ? nm : "?";
            if (!opts.finish && !(src != null && ULT_KINDS.Contains(src.kind)))
            {
                if (src != null && src.by != t.id) t.lastHit = new LastHit { by = src.by, kind = src.kind, name = name };
                t.damage += gain;
                GainUlt(t, src, gain);
                Emit(o => o.P("type", "armor").P("who", t.id).P("by", src != null ? src.by : null));
                Log($"  [아머] {t.name} ← {name} 버팀 ({t.name} {JsNumber.ToJs(t.damage)}%)");
                return true;
            }
            armorBroken = true;
            Emit(o => o.P("type", "armorBreak").P("who", t.id).P("by", src != null ? src.by : null));
            Log($"  [아머] {t.name} ← {name} 깨짐");
        }
        // 콤보: 경직이 안 풀렸는데 또 맞으면 이어짐. 첫 타에서 COMBO_MS 가 지난 뒤 들어간 타가 마지막 타
        if (!teammate)
        {
            t.comboHits = time < t.stunUntil && t.comboHits > 0 ? t.comboHits + 1 : 1;
            if (t.comboHits == 1)
            {
                t.comboBy = new List<string>(); // 이 콤보를 넣은 사람들 (로그·통계용, 넣은 순서·겹침 없음)
                t.comboStartAt = time;
            }
            var hitter = src != null && src.by != t.id ? GetPlayer(src.by) : null;
            if (hitter != null && !t.comboBy!.Contains(hitter.name)) t.comboBy.Add(hitter.name);
        }
        // 카운터히트: 맞는 쪽이 평타 후딜, 스킬·필살기 준비 중이었음 → 경직·멈칫 길게
        bool counter = !teammate && !armorBroken && src != null && t.@char != null && time >= t.stunUntil && Busy(t);
        if (counter)
        {
            stunMs *= C.COUNTER_STUN_MULT;
            t.counterAt = time;
            Emit(o => o.P("type", "counter").P("by", src!.by).P("target", t.id));
            Log($"  [카운터] {GetPlayer(src!.by)?.name ?? "undefined"} → {t.name}");
        }
        // 연타를 이어 가는 중인 타(opts.chained)는 COMBO_MS 가 지나도 시간 마무리가 아님
        bool finisher = !teammate && t.comboHits >= 2 && (opts.finish || (time - t.comboStartAt >= C.COMBO_MS && !opts.chained));
        bool fixed_ = opts.fixed_ && !finisher;
        if (!fixed_) speed *= finisher ? C.COMBO_FINISH_KB : heavy ? 1 : C.COMBO_LIGHT_KB;
        // 광전사 분노: 주는 넉백 × (1 + 자기 피해 % × 계수). 고정 넉백 중간 타는 빼고. R 마지막 날림은 R 시작 때 피해 % (src.rage)
        var rager = !teammate && src != null && src.by != t.id ? GetPlayer(src.by) : null;
        if (!fixed_ && rager != null && rager.@char == "berserker") speed *= RageMult(src!.rage ?? rager.damage);
        if (!teammate && t.comboHits >= 2 && src != null) Emit(o => o.P("type", "combo").P("by", src.by).P("target", t.id).P("n", t.comboHits).P("finish", finisher));
        // 맞아서 끊긴 공격: 쿨타임·게이지를 돌려주고 interrupt 이벤트
        if (t.atk != null)
        {
            var an = t.atk.n;
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "basic").P("n", an));
            t.pushReadyAt = time; // 안 나간 평타는 후딜 없음
        }
        if (time < t.chargeUntil)
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "skill"));
            t.skillReadyAt = time; // 아무도 못 친 돌진은 쿨타임 안 씀
        }
        if (Truthy(t.slamAt))
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "ult"));
            t.ult = UltMax(t); // 준비 중에 끊긴 내려찍기는 게이지 돌려줌
        }
        if (t.grab != null)
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "ult"));
            HookGrabDrop(t); // 뽑던 블록은 제자리로
            t.ult = UltMax(t);
        }
        if (t.windup != null || t.hookFly != null)
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "skill"));
            t.skillReadyAt = time; // 준비 중·갈고리가 닿기 전에 끊긴 F 는 쿨타임 안 씀
            t.windup = t.hookFly = null;
        }
        t.zipUntil = 0; // 끌려가다 맞으면 멈춤
        if (t.leap != null)
        {
            if (!Truthy(t.leap.endAt))
            {
                Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "skill"));
                t.skillReadyAt = time; // 뛰기 전에 끊긴 도약은 쿨타임 안 씀
            }
            t.leap = null;
        }
        if (t.huntAim != null)
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "ult"));
            t.huntAim = null;
            t.ult = UltMax(t); // 조준 중에 끊긴 처형 사격은 게이지 돌려줌
        }
        t.rush = null; // 광전사 도약 중에 맞으면 충격파 없음 (쿨타임은 씀)
        t.glideUntil = 0; // 바드 천천히 낙하: 맞으면 풀림
        t.dive = null; // 기타 꽂기 낙하도 끊김
        if (t.spin != null)
        {
            Emit(o => o.P("type", "interrupt").P("who", t.id).P("kind", "ult"));
            Log($"  [필살] {t.name} 분노 소용돌이 끊김");
            t.spin = null; // 회전 중에 맞으면 끝
        }
        t.emoteUntil = 0; // 맞으면 이모트 끊김
        t.chargeUntil = 0; // 맞으면 돌진·내려찍기 끊김
        t.slamAt = 0;
        t.atk = null; // 맞으면 평타 준비·이어 치기 끊김
        t.star2 = null;
        t.streak = 0;
        t.atkQueued = false;
        if (t.castQueued != null)
        {
            var cq = t.castQueued;
            Emit(o => o.P("type", "castDrop").P("who", t.id).P("kind", cq)); // 맞아서 기억했던 F·R 이 버려짐
        }
        t.castQueued = null;
        t.chainN = 0;
        if (teammate) gain = 0;
        else if (src != null && src.by != t.id)
        {
            t.lastHit = new LastHit { by = src.by, kind = src.kind, name = GetPlayer(src.by)?.name };
            // 때린 쪽의 이어 넣은 타 수 (상대가 바뀌어도 STREAK_MS 안이면 이어짐 → 닌자 갈아타기 'N HIT')
            var by = GetPlayer(src.by);
            if (by != null)
            {
                by.streak = time < by.streakUntil ? by.streak + 1 : 1;
                by.streakUntil = time + C.STREAK_MS;
                if (by.streak >= 2) Emit(o => o.P("type", "streak").P("who", by.id).P("n", by.streak).P("target", t.id));
            }
        }
        double taken = t.@char == "tank" ? C.TANK_KB_TAKEN : t.@char == "ninja" ? C.NINJA_KB_TAKEN : 1; // 탱크 패시브: 덜 밀림, 닌자 약점: 잘 밀림
        double vuln = !teammate && time < t.vulnUntil ? C.BARD_VULN_MULT : 1; // 바드 취약의 노래 (% 배율 넉백에만)
        double mult = fixed_ ? 1 : (C.DAMAGE_KB_BASE + t.damage * C.DAMAGE_KB_PER_PERCENT) * taken * vuln;
        t.damage += gain;
        GainUlt(t, src, gain);
        double len = JsMath.Hypot(dx, dy);
        if (len == 0 || double.IsNaN(len)) len = 1; // JS: || 1
        t.kbx = dx / len * speed * mult;
        t.kby = dy / len * speed * mult;
        t.vz = up;
        t.grounded = false;
        t.wallBounced = false; // 벽 튕김은 맞을 때마다 한 번
        t.stunUntil = time + stunMs;
        t.freezeUntil = time + C.HITSTOP_MS * (counter ? C.COUNTER_HITSTOP_MULT : 1); // 멈칫 뒤에 날아간다
        if (finisher) EndCombo(t, t.stunUntil, true);
        return true;
    }

    // 필살기 게이지: 피해 % 를 주거나 받은 만큼
    public void GainUlt(Player t, Src? src, double gain)
    {
        if (gain <= 0) return;
        t.ult = Math.Min(UltMax(t), t.ult + gain * C.ULT_PER_DAMAGE);
        var by = src != null && src.by != t.id ? GetPlayer(src.by) : null;
        if (by != null) by.ult = Math.Min(UltMax(by), by.ult + gain * C.ULT_PER_DAMAGE);
    }

    // 카운터히트 대상: 빗나간 평타의 후딜, 돌진 중, 내려찍기·솟는 벽 준비·갈고리 블록 뽑는 중 등
    public bool Busy(Player t) =>
        (time < t.pushReadyAt && t.atk == null && !t.atkLanded) || time < t.chargeUntil || Truthy(t.slamAt) || Truthy(t.wallAt) || t.grab != null || t.leap != null || t.windup != null || t.huntAim != null || t.rush != null || t.spin != null || t.amp != null;

    // 공격이 안 들어가는 상태: 콤보 뒤 무적·부활 무적. 경직이 이미 풀린 콤보는 여기서 먼저 끝냄
    public bool Invulnerable(Player t)
    {
        if (t.comboHits > 0 && time >= t.stunUntil) EndCombo(t);
        return time < t.iframeUntil || time < t.shieldUntil;
    }

    // 콤보 끝: 그때부터 COMBO_IFRAME_MS 무적 (마지막 타는 경직이 끝날 때까지 + 무적)
    public void EndCombo(Player t, double? from = null, bool finished = false)
    {
        if (t.comboHits >= 2)
        {
            var by = t.comboBy != null && t.comboBy.Count > 0 ? string.Join("+", t.comboBy) : "?";
            string line = $"  [콤보] {by} → {t.name} {JsNumber.ToJs(t.comboHits)}타{(finished ? " 마무리" : "")}"; // 때린 사람 여럿이면 P1+P3
            if (finished) LogLater(line); // 마무리 타는 그 공격 줄 뒤에
            else Log(line);
        }
        t.comboHits = 0;
        t.iframeUntil = (from ?? time) + C.COMBO_IFRAME_MS;
    }
}
