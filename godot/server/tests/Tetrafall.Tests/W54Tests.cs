using Tetrafall.Core;

namespace Tetrafall.Tests;

// W54 (2026-11-14): 사거리·타이밍은 클라이언트 보이는 쪽만 손봄 — 서버 평타 표 (준비·후딜·사거리·step) 가 v0.1.21 값 그대로임을 고정.
// 바꾸려면 (재혁 승인 뒤) 이 표를 일부러 같이 고쳐야 함. 고도 쪽 같은 고정: godot/client/tests/test_w54.gd
public class W54Tests
{
    static readonly Dictionary<string, double[][]> Expected = new()
    {
        ["tank"] = [[120, 300, 1.8, 0.4], [150, 350, 1.8, 0.8], [300, 500, 1.8, 0.3], [150, 400, 1.8, 0.0]],
        ["ninja"] = [[60, 150, 1.8, 0.3], [60, 150, 1.8, 0.3], [70, 170, 1.8, 0.3], [120, 350, 1.8, 0.2], [60, 150, 1.8, 0.0], [100, 450, 1.8, 0.0]],
        ["hunter"] = [[100, 250, 1.8, 0.3], [100, 250, 1.8, 0.3], [200, 450, 1.8, 0.4], [150, 400, 1.8, 0.0]],
        ["hook"] = [[150, 300, 1.8, 0.0], [150, 300, 1.8, 0.4], [200, 450, 1.8, 0.3], [150, 400, 1.8, 0.0]],
    };

    [Fact]
    public void 서버_평타_표는_W54_전과_같다()
    {
        Assert.Equal(1.8, C.PUSH_RANGE);
        Assert.Equal(0.3, C.PLAYER_HALF);
        foreach (var (ch, rows) in Expected)
        {
            var set = C.BASIC_ATTACKS[ch];
            var defs = set.chain.Concat(set.air).ToArray();
            Assert.Equal(rows.Length, defs.Length);
            for (int i = 0; i < rows.Length; i++)
            {
                var d = defs[i];
                Assert.Equal(rows[i][0], d.windup);
                Assert.Equal(rows[i][1], d.rec);
                Assert.Equal(rows[i][2], Game.Truthy(d.range) ? d.range!.Value : C.PUSH_RANGE);
                Assert.Equal(rows[i][3], d.step ?? 0);
            }
        }
        var tang = C.BASIC_ATTACKS["hook"].chain[2].loaded!;
        Assert.Equal(2.0, tang.range);
        Assert.Equal(200, tang.windup);
    }
}
