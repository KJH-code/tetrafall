using Tetrafall.Core;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// 2026-10-30 코드 감사 서버 결함 S1·S3~S10 (재혁 W1): test/w1-audit.test.js 와 같은 내용
public class AuditTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    [Fact]
    public void S1_갈고리_R_로_뽑는_중_나가면_뽑던_칸이_제자리로()
    {
        var (g, _, p) = Setup("hook", "ninja", "tank");
        var a = p(1);
        (p(2).x, p(2).y, p(2).z) = (1, 9, 0);
        Place(a, 3.5, 4.5);
        g.grid[g.Idx(5, 4, 0)] = Pieces.CELL.THROWN;
        g.GridChanged();
        a.pitch = -Math.Atan2(C.EYE_HEIGHT - 0.5, 2);
        a.ult = C.ULT_MAX;
        g.HandleAction(1, new ActionMsg { name = "ult" });
        Assert.NotNull(a.grab);
        Assert.Equal(0, g.grid[g.Idx(5, 4, 0)]);
        g.RemovePlayer(1);
        Assert.Equal(Pieces.CELL.THROWN, g.grid[g.Idx(5, 4, 0)]);
    }

    // 조종 블록 하나 잡은 게임 (조종권 아이템으로 p1 이 조종)
    static Game Controlling()
    {
        var g = new Game(_ => { });
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.StartRound();
        g.players[1].hasControl = true;
        g.nextSpawnAt = g.time;
        g.Tick(TICK);
        Assert.True(g.IsControlling(g.players[1]));
        return g;
    }

    static void Move(Game g, double dx, double dy) => g.HandleAction(1, new ActionMsg { name = "pieceMove", dx = dx, dy = dy });

    [Fact]
    public void S3_pieceMove는_한_칸씩_한_틱에_PIECE_MOVE_PER_TICK_번까지()
    {
        Assert.Equal(2, C.PIECE_MOVE_PER_TICK);
        var g = Controlling();
        var pc = g.ControlledPiece(g.players[1])!;
        (pc.px, pc.py) = (3, 3);
        Move(g, 99, 0);
        Assert.Equal(4, pc.px);
        Move(g, -50, 1e9);
        Assert.Equal((3, 4), (pc.px, pc.py));
        Move(g, 1, 0);
        Assert.Equal(3, pc.px); // 한 틱에 세 번째는 버림
        g.Tick(TICK);
        var pc2 = g.ControlledPiece(g.players[1])!;
        var (x0, y0) = (pc2.px, pc2.py);
        Move(g, double.NaN, double.NaN);
        Move(g, double.PositiveInfinity, double.NaN);
        Assert.Equal((x0, y0), (pc2.px, pc2.py));
        g.Tick(TICK);
        Move(g, 1, 0);
        Assert.Equal(x0 + 1, g.ControlledPiece(g.players[1])!.px);
    }

    [Fact]
    public void S7_호스트가_나가면_방장은_연결된_사람에게_먼저()
    {
        var g = new Game(_ => { });
        foreach (var id in new[] { 1, 2, 3 }) g.AddPlayer(id);
        g.SetAway(2, true);
        Assert.Equal(1, g.hostId);
        g.RemovePlayer(1);
        Assert.Equal(3, g.hostId); // 끊긴 2 가 아니라 연결된 3
        g.RemovePlayer(3);
        Assert.Equal(2, g.hostId); // 연결된 사람이 없으면 끊긴 사람에게라도
        g.RemovePlayer(2);
        Assert.Null(g.hostId);
    }


    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }
}
