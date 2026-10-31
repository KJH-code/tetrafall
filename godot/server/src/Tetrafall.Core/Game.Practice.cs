using System.Text.Json;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-practice.js — 연습 모드·튜토리얼·허수아비. 혼자 쓰는 방에서 바로 시작, 판이 안 끝남
public sealed partial class Game
{
    public PracticeToggles? practice; // JS this.practice (startPractice 전엔 undefined)
    public int dummyCounter;
    public Tutorial? tutorial; // 튜토리얼 진행 (server/tutorial.js)

    bool PracticeNoBlocks() => practice!.noBlocks;
    bool PracticeNoDeath() => practice!.noDeath;

    // 연습: 피해 % 설정값 (0~PRACTICE_DAMAGE_MAX 정수, 아니면 null). v = JS Number(v)
    public static double? PracticeDamage(double n)
    {
        if (!double.IsFinite(n)) return null;
        return Math.Max(0, Math.Min(C.PRACTICE_DAMAGE_MAX, JsMath.Round(n)));
    }

    public bool StartPractice()
    {
        mode = "practice";
        practice = new PracticeToggles { noCooldown = false, fullUlt = false, noBlocks = true, noDeath = true };
        skyStairs = false;
        hpMode = false; // 연습·튜토리얼은 체력전 없음
        mapChoice = "flat";
        countdownMs = 0;
        if (!StartRound()) return false;
        foreach (var p in Players()) p.home = new XY(p.x, p.y);
        Log("[연습] 시작");
        return true;
    }

    // 튜토리얼: 연습 판 위에서 단계 하나씩. id = 배우는 사람
    public bool StartTutorial(int id)
    {
        if (!StartPractice()) return false;
        tutorial = new Tutorial(this, id);
        return true;
    }

    // 토글·내 피해 %. 맞는 값이면 true (value = 받은 JSON 값 그대로)
    public bool PracticeSet(int id, string key, JsonElement? value)
    {
        if (mode != "practice") return false;
        if (key == "myDamage")
        {
            var p = GetPlayer(id);
            var v = PracticeDamage(JsValue.ToNumber(value));
            if (p == null || p.dummy || v == null) return false;
            p.practiceDamage = v.Value;
            p.damage = v.Value;
            return true;
        }
        if (key is not ("noCooldown" or "fullUlt" or "noBlocks" or "noDeath") || value is not { ValueKind: JsonValueKind.True or JsonValueKind.False } b) return false;
        bool on = b.ValueKind == JsonValueKind.True;
        switch (key)
        {
            case "noCooldown": practice!.noCooldown = on; break;
            case "fullUlt": practice!.fullUlt = on; break;
            case "noBlocks": practice!.noBlocks = on; break;
            default: practice!.noDeath = on; break;
        }
        if (key == "noBlocks" && on)
        {
            pieces = pieces.Where(pc => pc.controller != null || pc.thrownBy != null).ToList(); // 떨어지던 자동·하늘 블록 치움 (조종·설치 블록은 그대로)
            RefreshPieceCells();
            lava = new Lava();
        }
        if (key == "noBlocks" && !on) nextSpawnAt = time + C.FIRST_SPAWN_DELAY_MS;
        return true;
    }

    // 허수아비 추가: 보낸 사람 앞 PRACTICE_DUMMY_DIST 칸. 자리가 꽉 찼거나 PRACTICE_DUMMY_MAX 개면 null
    public Player? AddDummy(int byId)
    {
        if (mode != "practice" || Dummies().Count >= C.PRACTICE_DUMMY_MAX) return null;
        int id = -(1000 + ++dummyCounter);
        var p = AddPlayer(id, true);
        if (p == null) return null;
        var by = GetPlayer(byId);
        double yaw = by != null ? by.yaw : 0;
        static double Clamp(double v, double n) => Math.Max(0.5, Math.Min(n - 0.5, v));
        double x = Clamp((by != null ? by.x : W / 2.0) + JsMath.Cos(yaw) * C.PRACTICE_DUMMY_DIST, W);
        double y = Clamp((by != null ? by.y : D / 2.0) + JsMath.Sin(yaw) * C.PRACTICE_DUMMY_DIST, D);
        p.name = $"허수아비{dummyCounter}";
        p.dummy = true;
        p.@char = null;
        p.home = new XY(x, y);
        p.dummyDamage = 0;
        p.combo = null;
        p.lastCombo = null;
        PracticeReset(p, null);
        p.yaw = yaw + Math.PI; // 나를 봄
        Log($"[연습] {p.name} 추가");
        return p;
    }

    // id = JS Number(msg.id) (없으면 null = 마지막 허수아비)
    public bool RemoveDummy(double? id)
    {
        var list = Dummies();
        var d = id == null ? list.LastOrDefault() : list.FirstOrDefault(x => x.id == id);
        if (d == null) return false;
        d.alive = false; // 판 중에 나간 사람처럼 사망 기록을 남기지 않게
        RemovePlayer(d.id);
        return true;
    }

    public bool SetDummyDamage(double? id, JsonElement? value)
    {
        var v = PracticeDamage(JsValue.ToNumber(value));
        if (v == null) return false;
        var list = id == null ? Dummies() : Dummies().Where(d => d.id == id).ToList();
        foreach (var d in list)
        {
            d.dummyDamage = v.Value;
            if (d.combo == null || !d.combo.active) d.damage = d.prevDamage = v.Value; // 설정으로 바뀐 건 맞은 걸로 안 셈
        }
        return list.Count > 0;
    }

    // 허수아비들: id 오름차순을 뒤집음 (= 놓은 순서, id 가 -1001, -1002 …)
    public List<Player> Dummies()
    {
        var l = Players().Where(p => p.dummy).OrderBy(p => p.id).ToList();
        l.Reverse();
        return l;
    }

    // 제자리로 (허수아비: 추가한 자리, 사람: 처음 자리). 피해 % 는 설정값. cause 가 있으면 떨어지거나 깔려서
    public void PracticeReset(Player p, string? cause)
    {
        if (p.dummy && p.combo != null && p.combo.active) FinishDummyCombo(p);
        double hx, hy;
        if (p.home != null) (hx, hy) = (p.home.x, p.home.y);
        else
        {
            var sp = spawnPoints[p.slot % spawnPoints.Length];
            (hx, hy) = (sp.x, sp.y);
        }
        Respawn(p);
        int z = SpawnZ(hx, hy);
        p.x = hx;
        p.y = hy;
        p.z = z;
        p.damage = p.dummy ? p.dummyDamage : p.practiceDamage;
        p.shieldUntil = 0;
        p.spectator = false;
        p.prevX = p.x;
        p.prevY = p.y;
        p.prevZ = p.z;
        p.prevDamage = p.damage;
        p.prevCombo = 0;
        if (cause != null) Emit(o => o.P("type", "practiceReset").P("who", p.id).P("cause", cause));
    }

    // 들어온 친구: 관전 말고 바로 처음 자리에서
    public void PracticeJoin(int id)
    {
        var p = GetPlayer(id);
        if (p == null || mode != "practice" || !InRound()) return;
        p.home = new XY(p.x, p.y);
        PracticeReset(p, null);
    }

    // 틱마다: 쿨 없음·게이지 가득, 허수아비 콤보 기록·피해 % 되돌리기
    public void UpdatePractice()
    {
        var P = practice!;
        foreach (var p in Participants()) if (!p.alive && p.respawnAt != 0 && time >= p.respawnAt) PracticeReset(p, null); // "안 죽음" 끔
        foreach (var p in Players())
        {
            if (!p.alive || p.dummy) continue;
            if (P.noCooldown && p.skillReadyAt > time) p.skillReadyAt = time;
            if (P.fullUlt && p.@char != null) p.ult = UltMax(p);
        }
        foreach (var d in Dummies())
        {
            if (!d.alive) continue;
            bool hit = d.damage > d.prevDamage || d.comboHits > d.prevCombo;
            if (hit)
            {
                if (d.combo == null || !d.combo.active) d.combo = new DummyCombo { active = true, hits = 0, damage = 0, dist = 0, height = 0, sx = d.prevX, sy = d.prevY, sz = d.prevZ, dmg0 = d.prevDamage };
                d.combo.hits++;
                d.combo.damage = d.damage - d.combo.dmg0;
            }
            var c = d.combo;
            if (c != null && c.active)
            {
                c.dist = Math.Max(c.dist, JsMath.Hypot(d.x - c.sx, d.y - c.sy));
                c.height = Math.Max(c.height, d.z - c.sz);
                if (hit)
                {
                    var co = ComboOut.Of(c);
                    Emit(o =>
                    {
                        o.P("type", "dummyCombo").P("id", d.id);
                        co.WriteFields(o);
                        o.P("done", false);
                    });
                }
                else if (d.comboHits == 0 && time >= d.stunUntil && d.grounded) FinishDummyCombo(d);
            }
            else if (d.grounded && d.damage != d.dummyDamage) d.damage = d.dummyDamage;
            d.prevX = d.x;
            d.prevY = d.y;
            d.prevZ = d.z;
            d.prevDamage = d.damage;
            d.prevCombo = d.comboHits;
        }
    }

    // 허수아비 콤보 끝: 기록을 남기고 피해 % 를 설정값으로 (JS finishCombo)
    void FinishDummyCombo(Player d)
    {
        var c = d.combo!;
        c.active = false;
        var last = ComboOut.Of(c);
        d.lastCombo = last;
        Emit(o =>
        {
            o.P("type", "dummyCombo").P("id", d.id);
            last.WriteFields(o);
            o.P("done", true);
        });
        d.damage = d.dummyDamage;
        d.prevDamage = d.damage;
    }

    void PracticeSnapshot(JsonOut o)
    {
        var P = practice!;
        o.Obj().P("noCooldown", P.noCooldown).P("fullUlt", P.fullUlt).P("noBlocks", P.noBlocks).P("noDeath", P.noDeath);
        o.Key("dummies").Arr();
        foreach (var d in Dummies())
        {
            o.Obj().P("id", d.id).P("damageSet", d.dummyDamage).Key("combo");
            if (d.combo != null)
            {
                o.Obj();
                ComboOut.Of(d.combo).WriteFields(o);
                o.P("active", d.combo.active).EndObj();
            }
            else o.Null();
            o.Key("last");
            if (d.lastCombo != null)
            {
                o.Obj();
                d.lastCombo.WriteFields(o);
                o.EndObj();
            }
            else o.Null();
            o.EndObj();
        }
        o.EndArr().EndObj();
    }

    void TutorialSnapshot(JsonOut o) => tutorial!.Snapshot(o);

    void TutorialUpdate(double dtMs) => tutorial?.Update(dtMs);
}
