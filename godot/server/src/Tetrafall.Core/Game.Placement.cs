using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-placement.js — 블록 자리 고르기: 하늘 계단 사슬·자동 블록 (CLEAR_BIAS 점수)
public sealed partial class Game
{
    // ---- 하늘 계단 ----
    // 하늘 블록이 SKY_COUNT 개가 되도록 맨 위에 하나씩 (한 틱에 SKY_SPAWN_PER_TICK 개까지, 블록이 가장 적은 사슬부터)
    public void FillSky()
    {
        var n = new double[(int)skyChains];
        foreach (var pc in pieces) if (pc.sky && pc.chain < skyChains) n[pc.chain]++;
        for (int k = 0; k < C.SKY_SPAWN_PER_TICK; k++)
        {
            int c = Array.IndexOf(n, n.Min());
            if (n[c] >= C.SKY_COUNT || SpawnSky(c) == null) return;
            n[c]++;
        }
    }

    public Piece? SpawnSky(int chain = 0)
    {
        var skies = pieces.Where(pc => pc.sky && pc.chain == chain).ToList();
        // 사슬 맨 위 = 마지막에 붙인 블록. 그게 착지·녹아 없으면 가장 높은 하늘 블록, 하나도 없으면 새 사슬
        int topId = chain < skyTops.Count ? skyTops[chain] : int.MinValue;
        var top = skies.FirstOrDefault(pc => pc.id == topId);
        if (top == null)
        {
            foreach (var pc in skies) if (top == null || pc.pz > top.pz) top = pc;
        }
        var piece = ChooseSkyPlacement(top);
        if (piece == null) return null;
        // 모든 하늘 블록이 같은 순간에 한 칸씩 내려가게 판 시작 시각 기준 SKY_FALL_STEP_MS 박자에 맞춤
        double step = C.SKY_FALL_STEP_MS;
        double nextStepAt = roundStartTime + (Math.Floor((time - roundStartTime) / step) + 1) * step;
        AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.sky = true;
            pc.chain = chain;
            pc.stepMs = step;
            pc.nextStepAt = nextStepAt;
            pc.controlEndsAt = 0;
        });
        while (skyTops.Count <= chain) skyTops.Add(int.MinValue); // JS 배열 빈 칸 (undefined)
        skyTops[chain] = piece.id;
        return piece;
    }

    sealed class SkyCand
    {
        public string shape = "";
        public int rot, px, py, pz;
        public double score, w;
    }

    // 하늘 블록 자리: 맨 위 블록(top) 옆, 높이 = top 지금 높이 + SKY_RISE_MIN~MAX, 칸 사이 거리 SKY_GAP_MIN ~ skyReach(높이차) × SKY_REACH_SAFETY.
    // 조건을 만족하는 후보 중에서는 CLEAR_BIAS 점수로 가중 무작위. top 이 없으면 착지 높이 + SKY_BASE_UP
    public Piece? ChooseSkyPlacement(Piece? top)
    {
        var sc = PlacementScorer();
        int W_ = W;
        var busy = new byte[W * D]; // 다른 공중 블록이 있는 기둥
        foreach (var pc in pieces) foreach (var c in pc.cells) if (InXY(pc.px + c[0], pc.py + c[1])) busy[(pc.py + c[1]) * W_ + pc.px + c[0]] = 1;
        var others = pieces.Select(pc => (pz: pc.pz, xy: pc.cells.SelectMany(c => new[] { pc.px + c[0], pc.py + c[1] }).ToArray())).ToList();
        int[]? topXY = top?.cells.SelectMany(c => new[] { top.px + c[0], top.py + c[1] }).ToArray();
        // 칸 4개(cxy 납작) 와 칸 목록 xy 사이 가장 가까운 거리의 제곱
        static double Gap2(int[] cxy, int px, int py, int[] xy)
        {
            double best = double.PositiveInfinity;
            for (int i = 0; i < 8; i += 2)
            {
                int ax = px + cxy[i], ay = py + cxy[i + 1];
                for (int j = 0; j < xy.Length; j += 2)
                {
                    double dx = Math.Max(0, Math.Abs(ax - xy[j]) - 1);
                    double dy = Math.Max(0, Math.Abs(ay - xy[j + 1]) - 1);
                    double d = dx * dx + dy * dy;
                    if (d < best) best = d;
                }
            }
            return best;
        }
        double minGap2 = C.SKY_GAP_MIN * C.SKY_GAP_MIN;
        var rises = new List<double>();
        for (double r = C.SKY_RISE_MIN; r <= C.SKY_RISE_MAX; r++) rises.Add(r);
        // 높이차는 무작위로 하나 먼저, 그 높이에 자리가 없으면 나머지 (JS 는 top 이 없어도 rng 를 부름)
        int fi = (int)Math.Floor(rng() * rises.Count);
        var first = rises[fi];
        rises.RemoveAt(fi);
        var order_ = top != null ? new List<double> { first }.Concat(rises).ToList() : new List<double> { 0 };
        foreach (var r in order_)
        {
            double pz0 = top != null ? top.pz + r : 0;
            if (top != null && pz0 + 1 > C.SKY_TOP_Z) continue;
            double maxGap = top != null ? SkyReach(r) * C.SKY_REACH_SAFETY : double.PositiveInfinity;
            double maxGap2 = maxGap * maxGap;
            var tb = top != null ? CellBox(top) : default;
            var cands = new List<SkyCand>();
            double best = double.NegativeInfinity;
            foreach (var shape in Pieces.SHAPE_NAMES)
            {
                for (int rot = 0; rot < 4; rot++)
                {
                    var cells = Pieces.RotatedCells(shape, rot);
                    var cxy = cells.SelectMany(c => new[] { c[0], c[1] }).ToArray();
                    var (w, d) = Pieces.Footprint(cells);
                    for (int px = 0; px <= W - w; px++)
                    {
                        // 맨 위 블록과 x 로만 봐도 멀면 이 열 전체를 건너뜀
                        if (top != null && Math.Max(0, Math.Max(tb.x0 - (px + w), px - tb.x1)) > maxGap) continue;
                        for (int py = 0; py <= D - d; py++)
                        {
                            if (top != null)
                            {
                                double bx = Math.Max(0, Math.Max(tb.x0 - (px + w), px - tb.x1));
                                double by = Math.Max(0, Math.Max(tb.y0 - (py + d), py - tb.y1));
                                if (bx * bx + by * by > maxGap2) continue;
                            }
                            int landZ = 0;
                            bool hit = false;
                            for (int i = 0; i < 8; i += 2)
                            {
                                int k = (py + cxy[i + 1]) * W_ + px + cxy[i];
                                if (busy[k] != 0) hit = true;
                                if (sc.tops[k] > landZ) landZ = sc.tops[k];
                            }
                            if (hit) continue;
                            if (top != null && Gap2(cxy, px, py, topXY!) > maxGap2) continue;
                            double pz = top != null ? pz0 : Math.Min(C.SKY_TOP_Z - 1, landZ + C.SKY_BASE_UP);
                            if (pz <= landZ) continue; // 놓자마자 착지하는 자리
                            if (landZ + 1 > H) continue; // pieceFits
                            bool close = false;
                            foreach (var o in others) if (Math.Abs(o.pz - pz) <= 2 && Gap2(cxy, px, py, o.xy) < minGap2) close = true;
                            if (close) continue;
                            double score = C.CLEAR_BIAS > 0 ? sc.Score(cells, px, py, landZ) : 0;
                            if (score > best) best = score;
                            cands.Add(new SkyCand { shape = shape, rot = rot, px = px, py = py, pz = (int)pz, score = score });
                        }
                    }
                }
            }
            if (cands.Count == 0) continue;
            double total = 0;
            foreach (var c in cands) total += c.w = JsMath.Exp(C.CLEAR_BIAS * (c.score - best));
            double x = rng() * total;
            var pick = cands[^1];
            foreach (var c in cands)
            {
                x -= c.w;
                if (x <= 0)
                {
                    pick = c;
                    break;
                }
            }
            return MakePiece(pick.shape, pick.rot, pick.px, pick.py, pick.pz);
        }
        return null;
    }

    // placementScore 를 지금 격자로 빠르게: 기둥 높이·가장 낮은 층을 한 번만 재고, 덩어리 찾기는 배열 스택·도장(stamp)으로.
    // Score(cells, px, py, z) 는 같은 자리의 PlacementScore(piece, L) 와 같은 값
    public sealed class Scorer
    {
        public short[] tops = Array.Empty<short>();
        public double L;
        public Func<int[][], int, int, int, double> Score = null!;
    }

    public Scorer PlacementScorer()
    {
        int W_ = W, D_ = D, N = W * D;
        var tops = new short[N];
        double L = double.PositiveInfinity;
        for (int x = 0; x < W_; x++)
        {
            for (int y = 0; y < D_; y++)
            {
                int t = ColumnTop(x, y);
                tops[y * W_ + x] = (short)t;
                if (t < L) L = t;
            }
        }
        var S = C.CLEAR_SCORE;
        double S_HOLE = S["HOLE"], S_FILL = S["FILL"], S_CLEAR = S["CLEAR"], S_BAD = S["BAD_GAP"];
        var seen = new uint[N];
        var cov = new uint[N];
        var stack = new int[N];
        uint stamp = 1;
        // 가장 낮은 층의 빈 칸 덩어리를 한 번만 나눠 둠
        var comp = new int[N];
        Array.Fill(comp, -1);
        var size = new List<int>();
        int baseRemaining = 0, baseBad = 0;
        int Nb(int c, int k)
        {
            int cx = c % W_;
            return k == 0 ? (cx + 1 < W_ ? c + 1 : -1) : k == 1 ? (cx > 0 ? c - 1 : -1) : k == 2 ? (c + W_ < N ? c + W_ : -1) : c - W_;
        }
        for (int i = 0; i < N; i++)
        {
            if (tops[i] != L || comp[i] >= 0) continue;
            int id = size.Count;
            int n = 0, sp = 0;
            stack[sp++] = i;
            comp[i] = id;
            while (sp > 0)
            {
                int c = stack[--sp];
                n++;
                for (int k = 0; k < 4; k++)
                {
                    int q = Nb(c, k);
                    if (q >= 0 && tops[q] == L && comp[q] < 0)
                    {
                        comp[q] = id;
                        stack[sp++] = q;
                    }
                }
            }
            size.Add(n);
            baseRemaining += n;
            if (n % 4 != 0) baseBad++;
        }
        var ringMark = new uint[N];
        var ring = new int[16]; // 블록 4칸 둘레는 많아야 10칸
        // 덩어리 id 에서 덮인 칸(covStamp)을 뺀 조각들의 크기를 out 에
        void Parts(int id, int[] covered, int coveredIn, uint covStamp, List<int> out_)
        {
            uint rs = ++stamp;
            int nr = 0;
            foreach (var c in covered)
            {
                for (int k = 0; k < 4; k++)
                {
                    int q = Nb(c, k);
                    if (q < 0 || comp[q] != id || cov[q] == covStamp || ringMark[q] == rs) continue;
                    ringMark[q] = rs;
                    ring[nr++] = q;
                }
            }
            if (nr == 0) return; // 덩어리가 통째로 덮임
            int left = size[id] - coveredIn;
            // 지름길: 남은 칸은 모두 둘레 칸을 거쳐 이어져 있었음 → 둘레 칸끼리 블록 둘레 상자 (한 칸 넓힘) 안에서 서로 이어지면 남은 칸은 한 조각 (아래 전체 BFS 와 같은 답)
            int bx0 = int.MaxValue, by0 = int.MaxValue, bx1 = int.MinValue, by1 = int.MinValue;
            foreach (var c in covered)
            {
                int cx = c % W_, cy = c / W_;
                if (cx < bx0) bx0 = cx;
                if (cx > bx1) bx1 = cx;
                if (cy < by0) by0 = cy;
                if (cy > by1) by1 = cy;
            }
            bx0--;
            by0--;
            bx1++;
            by1++;
            {
                uint ls = ++stamp;
                int head = 0, tail = 0, met = 0;
                stack[tail++] = ring[0];
                seen[ring[0]] = ls;
                while (head < tail)
                {
                    int c = stack[head++];
                    if (ringMark[c] == rs) met++;
                    int cx = c % W_, cy = c / W_;
                    for (int k = 0; k < 4; k++)
                    {
                        int q = Nb(c, k);
                        if (q < 0 || comp[q] != id || cov[q] == covStamp || seen[q] == ls) continue;
                        int qx = q % W_, qy = q / W_;
                        if (qx < bx0 || qx > bx1 || qy < by0 || qy > by1) continue;
                        seen[q] = ls;
                        stack[tail++] = q;
                    }
                }
                if (met == nr)
                {
                    out_.Add(left);
                    return;
                }
            }
            uint ss = ++stamp;
            int found = 0;
            for (int r = 0; r < nr; r++)
            {
                int r0 = ring[r];
                if (seen[r0] == ss) continue;
                int n = 0, head = 0, tail = 0;
                stack[tail++] = r0;
                seen[r0] = ss;
                while (head < tail)
                {
                    int c = stack[head++];
                    n++;
                    if (ringMark[c] == rs && ++found == nr && out_.Count == 0)
                    {
                        out_.Add(left); // 첫 조각이 둘레를 다 만남 → 남은 칸 전부 한 조각
                        return;
                    }
                    for (int k = 0; k < 4; k++)
                    {
                        int q = Nb(c, k);
                        if (q < 0 || comp[q] != id || cov[q] == covStamp || seen[q] == ss) continue;
                        seen[q] = ss;
                        stack[tail++] = q;
                    }
                }
                out_.Add(n);
                left -= n;
            }
        }
        var covered = new int[4];
        var outList = new List<int>();
        double Score(int[][] cells, int px, int py, int z)
        {
            double holes = 0;
            foreach (var c in cells) holes += z - tops[(py + c[1]) * W_ + px + c[0]];
            if (holes > 0) return -S_HOLE * holes - (z - L);
            if (z != L) return -(z - L);
            uint covStamp = ++stamp;
            for (int k = 0; k < 4; k++)
            {
                int c = (py + cells[k][1]) * W_ + px + cells[k][0];
                cov[c] = covStamp;
                covered[k] = c;
            }
            int remaining = baseRemaining - 4;
            // 빠른 길: 블록 둘레(대각선 포함) 칸이 모두 필드 안의 빈 칸이면 남은 칸은 한 조각 → bad 그대로
            bool ringOpen = true;
            for (int k = 0; k < 4 && ringOpen; k++)
            {
                int c = covered[k];
                int cx = c % W_;
                int cy = (c - cx) / W_;
                for (int oy = -1; oy <= 1 && ringOpen; oy++)
                {
                    for (int ox = -1; ox <= 1; ox++)
                    {
                        int x = cx + ox, y = cy + oy;
                        if (x < 0 || y < 0 || x >= W_ || y >= D_)
                        {
                            ringOpen = false;
                            break;
                        }
                        int q = y * W_ + x;
                        if (cov[q] != covStamp && tops[q] != L)
                        {
                            ringOpen = false;
                            break;
                        }
                    }
                }
            }
            if (ringOpen) return S_FILL + (remaining == 0 ? S_CLEAR : 0) - S_BAD * baseBad;
            int bad = baseBad;
            for (int k = 0; k < 4; k++)
            {
                int id = comp[covered[k]];
                bool dup = false;
                for (int j = 0; j < k; j++) if (comp[covered[j]] == id) dup = true;
                if (dup) continue; // 덩어리마다 한 번
                int coveredIn = 0;
                for (int j = 0; j < 4; j++) if (comp[covered[j]] == id) coveredIn++;
                if (size[id] % 4 != 0) bad--;
                outList.Clear();
                Parts(id, covered, coveredIn, covStamp, outList);
                foreach (var n in outList) if (n % 4 != 0) bad++;
            }
            return S_FILL + (remaining == 0 ? S_CLEAR : 0) - S_BAD * bad;
        }
        return new Scorer { tops = tops, L = L, Score = Score };
    }

    sealed class AutoCand
    {
        public string shape = "";
        public int r, px, py;
        public double score, w;
    }

    // 자동 블록 고르기: 들어갈 수 있는 모든 (모양, 회전, 위치) 중에서 가중 무작위로 하나 (가중치 = exp(CLEAR_BIAS × 점수))
    public Piece? ChooseAutoPlacement(string randomShape)
    {
        var shapes = C.CLEAR_BIAS > 0 && C.CLEAR_PICK_SHAPE ? Pieces.SHAPE_NAMES : new[] { randomShape };
        var sc = PlacementScorer();
        int W_ = W;
        var busy = new byte[W * D];
        foreach (var pc in pieces) foreach (var c in pc.cells) if (InXY(pc.px + c[0], pc.py + c[1])) busy[(pc.py + c[1]) * W_ + pc.px + c[0]] = 1;
        var cands = new List<AutoCand>();
        double best = double.NegativeInfinity;
        foreach (var shape in shapes)
        {
            for (int r = 0; r < 4; r++)
            {
                var cells = Pieces.RotatedCells(shape, r);
                var (w, d) = Pieces.Footprint(cells);
                for (int px = 0; px <= W - w; px++)
                {
                    for (int py = 0; py <= D - d; py++)
                    {
                        int landZ = 0;
                        bool hit = false;
                        foreach (var c in cells)
                        {
                            int i = (py + c[1]) * W_ + px + c[0];
                            if (busy[i] != 0) hit = true;
                            if (sc.tops[i] > landZ) landZ = sc.tops[i];
                        }
                        if (landZ + 1 > H || landZ > C.PIECE_SPAWN_Z) continue; // pieceFits
                        if (hit) continue;
                        double score = C.CLEAR_BIAS > 0 ? sc.Score(cells, px, py, landZ) : 0;
                        if (score > best) best = score;
                        cands.Add(new AutoCand { shape = shape, r = r, px = px, py = py, score = score });
                    }
                }
            }
        }
        if (cands.Count == 0) return null;
        double total = 0;
        foreach (var c in cands)
        {
            c.w = JsMath.Exp(C.CLEAR_BIAS * (c.score - best)); // best 기준으로 빼서 overflow 방지
            total += c.w;
        }
        double x = rng() * total;
        var pick = cands[^1];
        foreach (var c in cands)
        {
            x -= c.w;
            if (x <= 0)
            {
                pick = c;
                break;
            }
        }
        return MakePiece(pick.shape, pick.r, pick.px, pick.py, (int)C.PIECE_SPAWN_Z);
    }

    // 가장 낮은 기둥 높이 = 아직 안 찬 가장 낮은 층
    public double LowestLayer()
    {
        double L = double.PositiveInfinity;
        for (int x = 0; x < W; x++) for (int y = 0; y < D; y++) L = Math.Min(L, ColumnTop(x, y));
        return L;
    }

    // 자동 블록 자리 점수 (느린 판, 테스트가 PlacementScorer 와 같은지 봄)
    public double PlacementScore(Piece piece, double L)
    {
        var S = C.CLEAR_SCORE;
        int z = piece.landZ;
        double holes = 0;
        foreach (var c in piece.cells) holes += z - ColumnTop(piece.px + c[0], piece.py + c[1]);
        if (holes > 0) return -S["HOLE"] * holes - (z - L);
        if (z != L) return -(z - L);
        var covered = new HashSet<int>(piece.cells.Select(c => (piece.px + c[0]) * 100 + (piece.py + c[1])));
        bool Open(int x, int y) => ColumnTop(x, y) == L && !covered.Contains(x * 100 + y);
        int remaining = 0, bad = 0;
        var seen = new HashSet<int>();
        for (int x = 0; x < W; x++)
        {
            for (int y = 0; y < D; y++)
            {
                if (!Open(x, y) || seen.Contains(x * 100 + y)) continue;
                int size = 0;
                var stack = new Stack<(int, int)>();
                stack.Push((x, y));
                seen.Add(x * 100 + y);
                while (stack.Count > 0)
                {
                    var (cx, cy) = stack.Pop();
                    size++;
                    foreach (var (nx, ny) in new[] { (cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1) })
                    {
                        if (nx < 0 || ny < 0 || nx >= W || ny >= D) continue;
                        if (!Open(nx, ny) || seen.Contains(nx * 100 + ny)) continue;
                        seen.Add(nx * 100 + ny);
                        stack.Push((nx, ny));
                    }
                }
                remaining += size;
                if (size % 4 != 0) bad++;
            }
        }
        return S["FILL"] + (remaining == 0 ? S["CLEAR"] : 0) - S["BAD_GAP"] * bad;
    }
}
