using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 아직 안 옮긴 메서드 (부르면 NotImplementedException). 옮긴 묶음 세션이 여기서 지우고 Game.<묶음>.cs 에 진짜를 넣음.
// 괄호 = 옮길 작업 (godot/PLAN.md 5절)
public sealed partial class Game
{
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
}
