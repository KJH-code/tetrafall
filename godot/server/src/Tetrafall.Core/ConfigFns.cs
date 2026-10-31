using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// shared/config.js 의 함수 값 (gen-config 가 못 만드는 것): 시작 위치 SPAWN_POINTS·spawnPointsFor
public static partial class C
{
    public sealed record SpawnPt(double x, double y, double yaw);

    static SpawnPt[] SpawnPoints(double W, double D, double inset)
    {
        var pts = new (double, double)[] { (inset, inset), (W - inset, D - inset), (W - inset, inset), (inset, D - inset), (W / 2, inset), (W / 2, D - inset), (inset, D / 2), (W - inset, D / 2) };
        return pts.Select(p => new SpawnPt(p.Item1, p.Item2, JsMath.Atan2(D / 2 - p.Item2, W / 2 - p.Item1))).ToArray();
    }

    public static readonly SpawnPt[] SPAWN_POINTS = SpawnPoints(GRID_W, GRID_D, 2.5);

    // 판 크기별 시작 위치
    public static SpawnPt[] spawnPointsFor(double W, double D) => SpawnPoints(W, D, 2.5);
}
