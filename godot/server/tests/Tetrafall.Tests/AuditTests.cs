using Tetrafall.Core;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// 2026-10-30 코드 감사 서버 결함 S1·S3~S10 (재혁 W1): test/w1-audit.test.js 와 같은 내용
public class AuditTests
{
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
}
