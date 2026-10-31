namespace Tetrafall.Core;

// shared/pieces.js — 테트리미노 7종 (xy 평면 1칸 두께, 수직축 회전만). 칸 = [dx, dy], 회전 결과는 min dx = min dy = 0 으로 맞춤
public static class Pieces
{
    public static readonly Dictionary<string, int[][]> SHAPES = new()
    {
        ["I"] = new[] { new[] { 0, 0 }, new[] { 1, 0 }, new[] { 2, 0 }, new[] { 3, 0 } },
        ["O"] = new[] { new[] { 0, 0 }, new[] { 1, 0 }, new[] { 0, 1 }, new[] { 1, 1 } },
        ["T"] = new[] { new[] { 0, 0 }, new[] { 1, 0 }, new[] { 2, 0 }, new[] { 1, 1 } },
        ["S"] = new[] { new[] { 1, 0 }, new[] { 2, 0 }, new[] { 0, 1 }, new[] { 1, 1 } },
        ["Z"] = new[] { new[] { 0, 0 }, new[] { 1, 0 }, new[] { 1, 1 }, new[] { 2, 1 } },
        ["J"] = new[] { new[] { 0, 0 }, new[] { 0, 1 }, new[] { 1, 1 }, new[] { 2, 1 } },
        ["L"] = new[] { new[] { 2, 0 }, new[] { 0, 1 }, new[] { 1, 1 }, new[] { 2, 1 } },
    };

    public static readonly string[] SHAPE_NAMES = { "I", "O", "T", "S", "Z", "J", "L" };

    // 격자 칸 값: 0 = 빈칸. GHOST_BASE + 색 번호 = 유령 투하 1칸 블록
    public static class CELL
    {
        public const byte TERRAIN = 1, BUILD = 2, THROWN = 3, SHAPE_BASE = 10, GHOST_BASE = 20;
    }

    public static byte CellOfShape(string? shape)
    {
        int i = shape == null ? -1 : Array.IndexOf(SHAPE_NAMES, shape);
        return i < 0 ? CELL.THROWN : (byte)(CELL.SHAPE_BASE + i);
    }

    static int[][] Normalize(int[][] cells)
    {
        int minX = int.MaxValue, minY = int.MaxValue;
        foreach (var c in cells)
        {
            if (c[0] < minX) minX = c[0];
            if (c[1] < minY) minY = c[1];
        }
        return cells.Select(c => new[] { c[0] - minX, c[1] - minY }).ToArray();
    }

    // 수직축 기준 시계방향 90도 회전을 rot 번 적용한 칸 목록
    public static int[][] RotatedCells(string shape, double rot)
    {
        var cells = SHAPES[shape].Select(c => new[] { c[0], c[1] }).ToArray();
        int r = (int)(((rot % 4) + 4) % 4);
        for (int i = 0; i < r; i++) cells = Normalize(cells.Select(c => new[] { c[1], -c[0] }).ToArray());
        return cells;
    }

    // 조각의 폭/깊이
    public static (int w, int d) Footprint(int[][] cells)
    {
        int w = 0, d = 0;
        foreach (var c in cells)
        {
            if (c[0] + 1 > w) w = c[0] + 1;
            if (c[1] + 1 > d) d = c[1] + 1;
        }
        return (w, d);
    }
}
