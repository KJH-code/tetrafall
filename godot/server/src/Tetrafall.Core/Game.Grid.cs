using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-grid.js — 격자: 칸 읽기·판 크기·기둥 높이
public sealed partial class Game
{
    public bool InXY(int cx, int cy) => cx >= 0 && cx < W && cy >= 0 && cy < D;

    // 판 크기: 필드에 나가는 사람·봇 수 → FIELD_SIZES (블록 마스터는 마스터 빼고)
    public double FieldSizeFor(double n) => GameUtil.ByCount(C.FIELD_SIZES, n);

    public void SetFieldSize(double size)
    {
        H = (int)(sky ? C.SKY_GRID_H : C.GRID_H);
        W = (int)size;
        D = (int)size;
        spawnPoints = C.spawnPointsFor(size, size);
        grid = new byte[W * D * H];
        gridPiece = new int[grid.Length];
    }

    // 넓이 배율 (10×10 = 1)
    public double AreaScale() => (double)(W * D) / (C.GRID_W * C.GRID_D);

    public double ItemMax() => JsMath.Round(C.ITEM_MAX_ON_FIELD * AreaScale());

    public int Idx(int cx, int cy, int cz) => (cz * D + cy) * W + cx;

    public int GridAt(int cx, int cy, int cz)
    {
        if (!InXY(cx, cy) || cz < 0 || cz >= H) return 0;
        return grid[Idx(cx, cy, cz)];
    }

    // 플레이어 충돌용: 바닥, 쌓인 블록, 떨어지는 블록
    public bool SolidAt(int cx, int cy, int cz)
    {
        if (cz < 0) return InXY(cx, cy); // 필드 안은 바닥, 밖은 허공
        if (InXY(cx, cy) && cz < H && grid[Idx(cx, cy, cz)] != 0) return true;
        return pieceCells.ContainsKey(GameUtil.CellKey(cx, cy, cz));
    }

    // 그 기둥에서 가장 높은 블록 바로 위 z (블록 없으면 0)
    public int ColumnTop(int cx, int cy)
    {
        for (int z = H - 1; z >= 0; z--)
        {
            if (grid[Idx(cx, cy, z)] != 0) return z + 1;
        }
        return 0;
    }

    // 격자가 바뀐 뒤: 떨어지는 블록 착지점, 아이템·폭탄 높이 다시 계산
    public void GridChanged()
    {
        gridVersion++;
        gridDirty = true;
        foreach (var pc in pieces) UpdateLanding(pc);
        foreach (var it in items) it.z = ColumnTop(it.x, it.y);
        foreach (var b in bombs) b.z = ColumnTop(b.x, b.y);
    }
}
