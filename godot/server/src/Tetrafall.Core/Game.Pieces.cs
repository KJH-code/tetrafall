using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-pieces.js — 블록: 떨어지기·조종·착지·압사·층 지우기·용암·유령 투하
// (S1: 스냅샷·충돌이 쓰는 부분. 나머지는 S2)
public sealed partial class Game
{
    // 떨어지는 블록이 이 사람을 깔기까지 남은 시간 (ms). CRUSH_WARN_MS 안에 깔 블록이 없으면 null
    public double? CrushDanger(Player p)
    {
        if (IsGhost(p) || time < p.shieldUntil) return null; // 블록이 통과하는 사람 (유령·부활 무적)
        double? best = null;
        var b = Aabb(p);
        foreach (var piece in pieces)
        {
            if (piece.phase != "falling") continue;
            if (!(piece.pz + 1 > p.z && piece.landZ < p.z + C.PLAYER_HEIGHT)) continue;
            bool over = piece.cells.Any(c =>
            {
                int x = piece.px + c[0], y = piece.py + c[1];
                return x < b.x1 && x + 1 > b.x0 && y < b.y1 && y + 1 > b.y0;
            });
            if (!over) continue;
            double steps = Math.Max(0, Math.Ceiling(piece.pz - (p.z + C.PLAYER_HEIGHT)));
            double eta = Math.Max(0, steps * piece.stepMs + (piece.nextStepAt - time) - piece.stepMs);
            if (eta <= C.CRUSH_WARN_MS && (best == null || eta < best)) best = eta;
        }
        return best;
    }

    public List<int[]> PieceWorldCells(Piece piece) => piece.cells.Select(c => new[] { piece.px + c[0], piece.py + c[1], piece.pz }).ToList();

    public void RefreshPieceCells()
    {
        pieceCells.Clear();
        foreach (var piece in pieces)
            foreach (var c in PieceWorldCells(piece)) pieceCells[CellKey(c[0], c[1], c[2])] = piece.id;
    }

    public Piece? ControlledPiece(Player p) => pieces.FirstOrDefault(pc => pc.phase == "control" && pc.controller == p.id);

    // 현재 xy 에서 착지 z. 격자만 본다
    public int ComputeLandZ(Piece piece)
    {
        int landZ = 0;
        foreach (var c in piece.cells)
        {
            int top = ColumnTop(piece.px + c[0], piece.py + c[1]);
            if (top > landZ) landZ = top;
        }
        return landZ;
    }

    public bool PieceFits(Piece piece)
    {
        if (piece.landZ + 1 > H || piece.landZ > piece.pz) return false;
        // 블록 마스터: 조종 중인 블록은 주변보다 너무 높게 못 놓음
        if (mode == "master" && piece.phase == "control" && TooTall(piece.cells.Select(c => (piece.px + c[0], piece.py + c[1])), piece.landZ)) return false;
        return true;
    }

    public void UpdateLanding(Piece piece)
    {
        piece.landZ = ComputeLandZ(piece);
        piece.fits = PieceFits(piece);
    }

    public Piece MakePiece(string shape, double rot, int px, int py, int pz)
    {
        var piece = new Piece { id = 0, shape = shape, rot = rot, cells = Pieces.RotatedCells(shape, rot), px = px, py = py, pz = pz, landZ = 0, fits = false };
        UpdateLanding(piece);
        return piece;
    }

    // 그림자(경고)를 보일지
    public bool ShadowVisible(Piece piece, double eta)
    {
        if (piece.phase != "falling") return false;
        return piece.sky ? piece.pz - piece.landZ <= C.SKY_SHADOW_CELLS : eta <= C.SHADOW_LEAD_MS;
    }

    // ---------- 용암 ----------
    public double AvgHeight()
    {
        double sum = 0;
        for (int x = 0; x < W; x++) for (int y = 0; y < D; y++) sum += ColumnTop(x, y);
        return sum / (W * D);
    }

    // ---------- 유령 투하 ----------
    // 이 사람이 유령 투하를 할 수 있는 상태면 남은 쿨 ms (0 = 바로), 아니면 null
    public double? GhostCd(Player p)
    {
        if (!C.GHOST_DROP_ENABLED || phase != "playing" || mode != "survival") return null;
        if (p.alive || p.spectator || p.master || p.dummy || (p.isBot && !C.GHOST_DROP_BOTS) || !players.ContainsKey(p.id)) return null;
        return Math.Max(0, (p.ghostReadyAt ?? 0) - time);
    }
}
