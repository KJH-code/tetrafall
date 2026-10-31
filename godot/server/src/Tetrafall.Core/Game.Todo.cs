using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 아직 안 옮긴 메서드 (부르면 NotImplementedException). 옮긴 묶음 세션이 여기서 지우고 Game.<묶음>.cs 에 진짜를 넣음.
// 괄호 = 옮길 작업 (godot/PLAN.md 5절)
public sealed class Tutorial
{
    public void Skip() => throw new NotImplementedException("아직 안 옮김: tutorial.skip (S4) (godot/PLAN.md)"); // 튜토리얼: 이 단계 넘기기
}

public sealed partial class Game
{
    public Tutorial? tutorial; // 튜토리얼 진행 (S4, server/tutorial.js)

    static Exception Todo(string what) => new NotImplementedException($"아직 안 옮김: {what} (godot/PLAN.md)");

    // S3 전투·캐릭터 (아직 안 옮긴 캐릭터: 건축가·갈고리·바드)
    public void HookGrabDrop(Player p) => throw Todo("hookGrabDrop (S3 갈고리)");
    public void UpdateNotes(double dt) => throw Todo("updateNotes (S3 바드)");
    bool HammerBlocks(Player p, double range, double cosHalf) => false; // TODO(S3 건축가): 내 블록이 없으면 false 와 같음
    void BasicRaise(Player p, Player? t) => throw Todo("basicRaise (S3 건축가)");
    void BardNote(Player p) => throw Todo("bardNote (S3 바드)");
    bool BardGlideRing(Player p, double n, bool air, TAttack def, bool chained) => throw Todo("bardGlideRing (S3 바드)");
    void BardGlide(Player p, double ms) => throw Todo("bardGlide (S3 바드)");
    void BardDive(Player p, TAttack def) => throw Todo("bardDive (S3 바드)");
    bool BuilderWall(Player p) => throw Todo("builderWall (S3 건축가)");
    bool BardSwitch(Player p) => throw Todo("bardSwitch (S3 바드)");
    bool HookPull(Player p) => throw Todo("hookPull (S3 갈고리)");
    bool BuilderBigBomb(Player p) => throw Todo("builderBigBomb (S3 건축가)");
    void BardAmp(Player p) => throw Todo("bardAmp (S3 바드)");
    void BardSong(Player p) => throw Todo("bardSong (S3 바드)");
    bool HookGrab(Player p) => throw Todo("hookGrab (S3 갈고리)");
    void UpdateBBlocks() => throw Todo("updateBBlocks (S3 건축가)");
    void HookLand(Player p) => throw Todo("hookLand (S3 갈고리)");
    void BardAmpUpdate(Player p) => throw Todo("bardAmpUpdate (S3 바드)");
    void BardDiveUpdate(Player p) => throw Todo("bardDiveUpdate (S3 바드)");
    void BuilderWallRise(Player p) => throw Todo("builderWallRise (S3 건축가)");
    void HookSlam(Player p) => throw Todo("hookSlam (S3 갈고리)");

    // S4 아이템·연습·튜토리얼
    // 방(Rooms)이 부르는 것: 연습 방 시작·들어오기·토글·허수아비, 튜토리얼 시작. 받은 값은 JSON 그대로 (JS 와 같은 검사는 옮길 때)
    public void StartPractice() => throw Todo("startPractice (S4)");
    public void PracticeJoin(int id) => throw Todo("practiceJoin (S4)");
    public bool PracticeSet(int id, string key, System.Text.Json.JsonElement? value) => throw Todo("practiceSet (S4)");
    public Player? AddDummy(int id) => throw Todo("addDummy (S4)");
    public bool RemoveDummy(double? id) => throw Todo("removeDummy (S4)");
    public bool SetDummyDamage(double? id, System.Text.Json.JsonElement? damage) => throw Todo("setDummyDamage (S4)");
    public void StartTutorial(int id) => throw Todo("startTutorial (S4)");
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
