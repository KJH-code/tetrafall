using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 아직 안 옮긴 메서드 (부르면 NotImplementedException). 옮긴 묶음 세션이 여기서 지우고 Game.<묶음>.cs 에 진짜를 넣음.
// 괄호 = 옮길 작업 (godot/PLAN.md 5절). 방(Rooms)이 부르는 것은 Game.Pending.cs (S6 이 만든 자리) — 같은 뜻
public sealed partial class Game
{
    // S3 전투·캐릭터
    // updateCombat (S3) 의 '아무도 공격·스킬을 안 쓴 판' 부분만 (각본 trace 시나리오용). 전투 상태가 하나라도 있으면 멈춤
    public void UpdateCombat()
    {
        if (bblocks.Count > 0 || bigBombs.Count > 0 || holes.Count > 0 || quakes.Count > 0) throw Todo("updateCombat 건축가·탱크 (S3)");
        foreach (var p in Players())
        {
            if (p.comboHits > 0 && time >= p.stunUntil) EndCombo(p);
            if (!OnField(p))
            {
                p.chargeUntil = p.slamAt = p.wallAt = p.zipUntil = 0;
                p.leap = null;
                p.huntAim = null;
                p.rush = null;
                p.spin = null;
                p.amp = null;
                p.windup = null;
                p.hookFly = null;
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
            if (p.atk != null || p.star2 != null || p.@char != null || p.marks.Count > 0 || p.windup != null || p.hookFly != null || p.leap != null || p.rush != null || p.spin != null || p.amp != null || p.dive != null || p.huntAim != null
                || p.castQueued != null || p.atkQueued || time < p.chargeUntil || p.slamAt != 0 || p.wallAt != 0 || p.grab != null)
                throw Todo("updateCombat 평타·스킬·캐릭터 (S3)");
        }
    }
    public void EndCombo(Player t) => throw Todo("endCombo (S3)");
    public void Dash(Player p) => throw Todo("dash (S3)");
    public void BasicPress(Player p) => throw Todo("basicPress (S3)");
    public void Push(Player p) => throw Todo("push (S3)");
    public void Cast(Player p, string kind) => throw Todo("cast (S3)");
    public void HookGrabDrop(Player p) => throw Todo("hookGrabDrop (S3)");
    public void UpdateShells(double dt) => throw Todo("updateShells (S3)");
    public void UpdateNotes(double dt) => throw Todo("updateNotes (S3)");

    // S4 아이템·연습·튜토리얼
    public void BrickShock(Piece piece) => throw Todo("brickShock (S4)");
    bool PracticeNoBlocks() => throw Todo("practice.noBlocks (S4)");
    bool PracticeNoDeath() => throw Todo("practice.noDeath (S4)");
    public void UpdateProjectiles(double dt)
    {
        if (projectiles.Count > 0) throw Todo("updateProjectiles (S4)");
    }
    public void UpdateBombs()
    {
        if (bombs.Count > 0) throw Todo("updateBombs (S4)");
    }
    public void ThrowBrick(Player p) => throw Todo("throwBrick (S4)");
    public void Fire(Player p) => throw Todo("fire (S4)");
    public void ThrowBomb(Player p) => throw Todo("throwBomb (S4)");
    void BrickPlanPreview(JsonOut o, Player p) => throw Todo("aimPreview brickPlan (S4)");
    void BombPlanPreview(JsonOut o, Player p) => throw Todo("aimPreview bombPlan (S4)");
    public void UpdatePractice() => throw Todo("updatePractice (S4)");
    public void PracticeReset(Player p, string? cause) => throw Todo("practiceReset (S4)");
    void PracticeSnapshot(JsonOut o) => throw Todo("practiceSnapshot (S4)");
    void TutorialSnapshot(JsonOut o) => throw Todo("tutorial.snapshot (S4)");
    void TutorialUpdate(double dtMs)
    {
        if (tutorial != null) throw Todo("tutorial.update (S4)");
    }
}
