using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// shared/maps.js 의 시작 지형 (MapColumns·BaseColumns·ACCENTS). 이름 표(MAPS·MAP_IDS)는 Maps.g.cs (gen-config).
// 줄 단위로 옮김: 같은 칸·같은 높이 (테스트 MapsTests 가 JS 정답 자료로 확인)
public static partial class Maps
{
    // 기둥 높이 목록 [x, y, h] (z=0 부터 h 칸). W·D 는 판 크기, x 다음 y 순서로 정렬
    public static List<(int x, int y, int h)> MapColumns(string id, int W, int D)
    {
        var h = new Dictionary<int, int>();
        foreach (var (x, y, z) in BaseColumns(id, W, D)) h[x * 100 + y] = z;
        int Get(int x, int y) => h.TryGetValue(x * 100 + y, out var v) ? v : 0;
        void Set(int x, int y, int z)
        {
            if (z > 0) h[x * 100 + y] = z;
            else h.Remove(x * 100 + y);
        }
        switch (id)
        {
            case "pyramid": Pyramid(W, D, Get, Set); break;
            case "stairs": Stairs(W, D, Get, Set); break;
            case "bowl": Bowl(W, D, Get, Set); break;
            case "spiral": Spiral(W, D, Get, Set); break;
            case "pillars": Pillars(W, D, Get, Set); break;
            case "fortress": Fortress(W, D, Get, Set); break;
        }
        // JS 키 = x * 100 + y → Math.floor(k / 100), k % 100 (음수 칸은 없음)
        return h.Select(kv => (kv.Key / 100, kv.Key % 100, (int)Math.Min(kv.Value, C.MAP_MAX_H))).OrderBy(c => c.Item1).ThenBy(c => c.Item2).ToList();
    }

    // 가운데 칸 (홀수 판 1칸, 짝수 판 2칸)
    static int[] Mid(int n) => n % 2 != 0 ? new[] { (n - 1) / 2 } : new[] { n / 2 - 1, n / 2 };

    // (x, y) 를 판 가운데 기준 90° 씩 돌린 네 칸 (바람개비)
    static (int x, int y)[] Turns(int W, int D, int x, int y) => new[] { (x, y), (W - 1 - y, x), (W - 1 - x, D - 1 - y), (y, D - 1 - x) };

    static readonly (int dx, int dy)[] N4 = { (1, 0), (-1, 0), (0, 1), (0, -1) };

    // 사막: 피라미드 꼭대기 머릿돌 + 네 모서리 3층 오벨리스크 + 변마다 무너진 돌 1층
    static void Pyramid(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        void Raise(int x, int y, int hh)
        {
            if (get(x, y) < hh) set(x, y, hh);
        }
        var mx = Mid(W);
        var my = Mid(D);
        bool FlatTop(int x, int y) => N4.All(d => get(x + d.dx, y + d.dy) >= get(x, y));
        var ring = new List<(int, int)>();
        for (int x = mx[0] - 1; x <= mx[^1] + 1; x++)
            for (int y = my[0] - 1; y <= my[^1] + 1; y++)
                if (FlatTop(x, y)) ring.Add((x, y));
        foreach (var (x, y) in ring) set(x, y, get(x, y) + 1);
        foreach (var x in mx)
            foreach (var y in my)
                if (FlatTop(x, y)) set(x, y, get(x, y) + 1);
        foreach (var (dx, dy, hh) in new[] { (0, 0, 3), (1, 0, 2), (0, 1, 2), (2, 0, 1), (0, 2, 1) })
            foreach (var (x, y) in Turns(W, D, dx, dy)) Raise(x, y, hh);
        int k = W / 2 + 1;
        foreach (var kk in W >= 14 ? new[] { k, k + 2 } : new[] { k })
            foreach (var (x, y) in Turns(W, D, kk, 0)) Raise(x, y, 1);
    }

    // 수정 동굴: 계단 맨 위 안쪽 줄 끝 첨탑 + 양옆 가장자리 수정 무리
    static void Stairs(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        foreach (var (x, y, dx) in new[] { (W - 1, 1, -1), (0, D - 2, 1) })
        {
            int top = get(x, y) + 2;
            for (int i = 0; top - i > get(x + i * dx, y); i++) set(x + i * dx, y, top - i);
        }
        var ys = W >= 16 ? new[] { 0.35, 0.65 } : new[] { 0.5 };
        foreach (var fy in ys)
        {
            int y = (int)JsMath.Round(fy * (D - 1));
            foreach (var (dx, dy, hh) in new[] { (0, 0, 3), (0, 1, 2), (0, -1, 2), (1, 0, 2), (1, 1, 1), (1, -1, 1), (2, 0, 1) })
                foreach (var (x, yy) in new[] { (dx, y + dy), (W - 1 - dx, D - 1 - y - dy) })
                    if (get(x, yy) < hh) set(x, yy, hh);
        }
    }

    // 화산: 벽마다 바닥까지 갈라진 틈 (바람개비) + 틈 옆 바깥 벽 4층 굴뚝
    static void Bowl(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        int k = W / 2 + 1;
        for (int d = 0; d < W / 2; d++)
        {
            if (get(k, d) == 0) break;
            foreach (var (x, y) in Turns(W, D, k, d)) set(x, y, 0);
        }
        foreach (var (x, y) in Turns(W, D, k - 2, 0)) set(x, y, get(x, y) + 1);
        foreach (var (x, y) in Turns(W, D, k + 2, 0)) set(x, y, get(x, y) + 1);
    }

    // 하늘 성: 4·5층 바깥 줄 성가퀴, 나선 끝 칸 7층 뾰족탑 (옆 칸 6층)
    static void Spiral(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        bool Outer(int x, int y) => x == 0 || y == 0 || x == W - 1 || y == D - 1;
        (int x, int y)? tip = null;
        for (int x = 0; x < W; x++)
        {
            for (int y = 0; y < D; y++)
            {
                if (!Outer(x, y) || get(x, y) != 5) continue;
                if (N4.Any(d => Outer(x + d.dx, y + d.dy) && x + d.dx >= 0 && x + d.dx < W && y + d.dy >= 0 && y + d.dy < D && get(x + d.dx, y + d.dy) == 0)) tip = (x, y);
            }
        }
        var merlon = new List<(int, int)>();
        for (int x = 0; x < W; x++)
            for (int y = 0; y < D; y++)
                if (Outer(x, y) && get(x, y) >= 4 && (x + y) % 2 == 0) merlon.Add((x, y));
        foreach (var (x, y) in merlon) set(x, y, get(x, y) + 1);
        if (tip is var (tx, ty))
        {
            foreach (var (dx, dy) in N4)
            {
                int nx = tx + dx, ny = ty + dy;
                if (nx >= 0 && ny >= 0 && nx < W && ny < D && get(nx, ny) >= 5) set(nx, ny, 6);
            }
            set(tx, ty, 7);
        }
    }

    // 버섯 숲: 네 모서리 기둥 3층 큰 버섯, 가운데 버섯 4층 (발판 한 칸씩 낮게)
    static void Pillars(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        var xs = new List<int>();
        for (int x = 1; x < W; x += 3) xs.Add(x);
        var ys = new List<int>();
        for (int y = 1; y < D; y += 3) ys.Add(y);
        void Grow(int x, int y, int top)
        {
            set(x, y, top);
            int dir = x + 2 < W ? 1 : -1;
            for (int s = 1; s < top - 1; s++)
                if (get(x + dir * s, y) < top - s) set(x + dir * s, y, top - s);
        }
        bool End(int k, int n) => k == 0 || k == n - 1;
        for (int i = 0; i < xs.Count; i++)
        {
            for (int j = 0; j < ys.Count; j++)
            {
                int x = xs[i], y = ys[j];
                if (get(x, y) == 3) Grow(x, y, 4);
                else if (End(i, xs.Count) && End(j, ys.Count)) Grow(x, y, 3);
            }
        }
    }

    // 중세 성: 탑 바깥 모서리 4층 망루, 성벽마다 2칸 성문 틈
    static void Fortress(int W, int D, Func<int, int, int> get, Action<int, int, int> set)
    {
        foreach (var (x, y) in new[] { (0, 0), (W - 1, 0), (0, D - 1), (W - 1, D - 1) }) set(x, y, 4);
        int k = W / 2 + 1;
        foreach (var kk in new[] { k, k + 1 })
            foreach (var (x, y) in Turns(W, D, kk, 0)) set(x, y, 0);
    }

    // 예전 배치 (포인트 없이)
    public static List<(int x, int y, int h)> BaseColumns(string id, int W, int D)
    {
        var out_ = new List<(int, int, int)>();
        if (id == "pyramid")
        {
            double cx = (W - 1) / 2.0, cy = (D - 1) / 2.0;
            for (int x = 0; x < W; x++)
            {
                for (int y = 0; y < D; y++)
                {
                    double ring = Math.Max(Math.Abs(x - cx), Math.Abs(y - cy));
                    double h = Math.Max(0, Math.Floor((W / 2.0 - 1.5 - ring) + 1));
                    if (h > 0) out_.Add((x, y, (int)Math.Min(h, 3)));
                }
            }
        }
        else if (id == "bowl")
        {
            double cx = (W - 1) / 2.0, cy = (D - 1) / 2.0;
            double flat = Math.Min(W, D) / 2.0 - 5;
            for (int x = 0; x < W; x++)
            {
                for (int y = 0; y < D; y++)
                {
                    double h = Math.Floor(Math.Max(Math.Abs(x - cx), Math.Abs(y - cy)) - flat) - 1;
                    if (h > 0) out_.Add((x, y, (int)h));
                }
            }
        }
        else if (id == "spiral")
        {
            double cx = W / 2.0, cy = D / 2.0;
            for (int x = 0; x < W; x++)
            {
                for (int y = 0; y < D; y++)
                {
                    if (Math.Max(Math.Abs(x + 0.5 - cx), Math.Abs(y + 0.5 - cy)) < W / 2.0 - 1.5) continue;
                    double a = (JsMath.Atan2(y + 0.5 - cy, x + 0.5 - cx) + 2 * Math.PI) % (2 * Math.PI);
                    double h = Math.Floor((a / (2 * Math.PI)) * 6);
                    if (h > 0) out_.Add((x, y, (int)h));
                }
            }
        }
        else if (id == "pillars")
        {
            static double Near(int n) => 1 + 3 * JsMath.Round((n / 2.0 - 1 - 1) / 3);
            double m0 = Near(W), m1 = Near(D);
            for (int x = 1; x < W; x += 3)
            {
                for (int y = 1; y < D; y += 3)
                {
                    int top = x == m0 && y == m1 ? 3 : 2;
                    out_.Add((x, y, top));
                    for (int s = 1; s < top && x + s < W; s++) out_.Add((x + s, y, top - s));
                }
            }
        }
        else if (id == "fortress")
        {
            bool Tower(int x, int y) => (x < 2 || x >= W - 2) && (y < 2 || y >= D - 2);
            int[] midX = { W / 2 - 1, W / 2 }, midY = { D / 2 - 1, D / 2 };
            for (int x = 0; x < W; x++)
            {
                for (int y = 0; y < D; y++)
                {
                    bool edge = x == 0 || y == 0 || x == W - 1 || y == D - 1;
                    if (Tower(x, y)) out_.Add((x, y, 3));
                    else if (edge) out_.Add((x, y, 2));
                    else if ((midX.Contains(x) && (y == 1 || y == D - 2)) || (midY.Contains(y) && (x == 1 || x == W - 2))) out_.Add((x, y, 1));
                }
            }
        }
        else if (id == "stairs")
        {
            double run = W / 5.0;
            for (int x = 0; x < W; x++)
            {
                int up = (int)Math.Floor(x / run);
                int down = (int)Math.Floor((W - 1 - x) / run);
                foreach (var y in new[] { 0, 1 }) if (up > 0) out_.Add((x, y, up));
                foreach (var y in new[] { D - 2, D - 1 }) if (down > 0) out_.Add((x, y, down));
            }
        }
        return out_;
    }
}
