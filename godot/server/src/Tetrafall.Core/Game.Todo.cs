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

    // S2 판 흐름·블록
    public void UpdatePieces() => throw Todo("updatePieces (S2)");
    public void Kill(Player p, string cause) => throw Todo("kill (S2)");
    public void Respawn(Player p) => throw Todo("respawn (S2)");
    public void EndRound(Player? winner) => throw Todo("endRound (S2)");
    public void CheckRoundEnd()
    {
        if (phase != "playing") return;
        throw Todo("checkRoundEnd (S2)");
    }
    public void UpdateLava(double dtMs) => throw Todo("updateLava (S2)");
    public void MovePiece(Piece pc, int dx, int dy) => throw Todo("movePiece (S2)");
    public void RotatePiece(Piece pc, int dir) => throw Todo("rotatePiece (S2)");
    public void DropPiece(Piece pc) => throw Todo("dropPiece (S2)");

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

    // S2 (game-pieces.js): 떨어지는 블록 칸이 다 부서짐 (대포수 breakCell 이 부름)
    public void RemovePiece(Piece pc) => throw Todo("removePiece (S2)");

    // S2 (game-pieces.js): 유령 투하 — 방(Rooms)이 받은 x·y 값 그대로 (숫자 아닐 수 있음, JS 와 같은 검사는 옮길 때)
    public bool GhostDrop(int id, System.Text.Json.JsonElement? x, System.Text.Json.JsonElement? y) => throw Todo("ghostDrop (S2)");

    // S4 아이템·연습·튜토리얼
    // 방(Rooms)이 부르는 것: 연습 방 시작·들어오기·토글·허수아비, 튜토리얼 시작. 받은 값은 JSON 그대로 (JS 와 같은 검사는 옮길 때)
    public void StartPractice() => throw Todo("startPractice (S4)");
    public void PracticeJoin(int id) => throw Todo("practiceJoin (S4)");
    public bool PracticeSet(int id, string key, System.Text.Json.JsonElement? value) => throw Todo("practiceSet (S4)");
    public Player? AddDummy(int id) => throw Todo("addDummy (S4)");
    public bool RemoveDummy(double? id) => throw Todo("removeDummy (S4)");
    public bool SetDummyDamage(double? id, System.Text.Json.JsonElement? damage) => throw Todo("setDummyDamage (S4)");
    public void StartTutorial(int id) => throw Todo("startTutorial (S4)");
    public void UpdateItems() => throw Todo("updateItems (S4)");
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
