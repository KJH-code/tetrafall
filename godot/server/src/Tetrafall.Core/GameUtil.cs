using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-util.js — Game 클래스 밖 도움 함수·로그 표
public static class GameUtil
{
    public const double EPS = 1e-6;
    public static readonly int[][] DIR6 = { new[] { 1, 0, 0 }, new[] { -1, 0, 0 }, new[] { 0, 1, 0 }, new[] { 0, -1, 0 }, new[] { 0, 0, 1 }, new[] { 0, 0, -1 } };

    // JS cellKey `${x},${y},${z}` 대신 숫자 하나 (같은 칸 = 같은 키). 칸 좌표는 ±1000 안
    public static long CellKey(int cx, int cy, int cz) => ((long)(cx + 1024) << 22) | ((long)(cy + 1024) << 11) | (long)(cz + 1024);

    // 플레이어 AABB 가 칸 (cx, cy, cz) 와 겹치는가 (경계에 닿기만 하면 아님)
    public static bool OverlapsCell(Player p, double cx, double cy, double cz) =>
        cx < p.x + C.PLAYER_HALF - EPS &&
        cx + 1 > p.x - C.PLAYER_HALF + EPS &&
        cy < p.y + C.PLAYER_HALF - EPS &&
        cy + 1 > p.y - C.PLAYER_HALF + EPS &&
        cz < p.z + C.PLAYER_HEIGHT - EPS &&
        cz + 1 > p.z + EPS;

    public static string FmtTime(double ms)
    {
        double s = Math.Floor(ms / 1000);
        return $"{JsNumber.ToJs(Math.Floor(s / 60))}:{JsNumber.ToJs(s % 60).PadLeft(2, '0')}";
    }

    // 하늘 계단: 올라갈 높이 h(칸)일 때 점프(+꼭대기에서 공중 점프)로 닿는 수평 거리 (칸)
    public static double SkyReach(double h)
    {
        double g = C.GRAVITY, v = C.JUMP_SPEED;
        if (C.AIR_JUMPS > 0)
        {
            double va = C.AIR_JUMP_SPEED;
            double d = va * va + 2 * g * ((v * v) / (2 * g) - h);
            return d < 0 ? 0 : C.MOVE_SPEED * (v / g + (va + Math.Sqrt(d)) / g);
        }
        double d2 = v * v - 2 * g * h;
        return d2 < 0 ? 0 : (C.MOVE_SPEED * (v + Math.Sqrt(d2))) / g;
    }

    // 인원별 표 ({ 인원: 값 }) 에서 n 이하 가장 큰 칸 (없으면 가장 작은 칸)
    public static T ByCount<T>(Dictionary<string, T> table, double n)
    {
        var keys = table.Keys.Select(double.Parse).OrderBy(k => k).ToList();
        var below = keys.Where(k => k <= n).ToList();
        double k = below.Count > 0 ? below[^1] : keys[0];
        return table[JsNumber.ToJs(k)];
    }

    public static double MaxPlayers() => Math.Min(C.MAX_PLAYERS, C.SPAWN_POINTS.Length);

    public static string ShareText(double crush, double fall, double lava)
    {
        double deaths = crush + fall + lava;
        if (deaths == 0) return "사망 없음";
        double share = crush / deaths;
        string pass = share >= C.PASS_CRUSH_SHARE ? "합격선 이상" : "합격선 미만";
        return $"{JsNumber.ToFixed(share * 100, 0)}% (합격선 {JsNumber.ToFixed(C.PASS_CRUSH_SHARE * 100, 0)}% → {pass})";
    }

    public static readonly Dictionary<string, string> BOT_LEVEL_KO = new() { ["easy"] = "쉬움", ["normal"] = "보통", ["hard"] = "어려움" };
    public static readonly Dictionary<string, string> TEAM_KO = new() { ["red"] = "빨강", ["blue"] = "파랑" };

    // 필살기 공격 종류 (탱크 아머를 깸)
    public static readonly HashSet<string> ULT_KINDS = new() { "slam", "bigbomb", "blockslam", "execute", "bigshell", "spin", "spinend", "amp", "ampend" };

    public static readonly Dictionary<string, string> BBLOCK_LOG = new() { ["wall"] = "벽", ["third"] = "3타 블록", ["pad"] = "발판" };
    // 판 끝 "  블록:" 줄 (npm run stats), 이 순서대로
    public static readonly Dictionary<string, string> LANDED_LOG = new() { ["auto"] = "자동", ["sky"] = "하늘", ["control"] = "조종", ["item"] = "설치", ["builder"] = "건축가", ["hook"] = "갈고리", ["ghost"] = "유령" };
    public static Dictionary<string, double> EmptyLanded() => LANDED_LOG.Keys.ToDictionary(k => k, _ => 0.0);
    // 사망 로그 "밟은 칸"
    public static readonly Dictionary<string, string> GROUND_LOG = new() { ["floor"] = "바닥", ["terrain"] = "지형", ["stack"] = "블록", ["sky"] = "하늘", ["piece"] = "낙하블록", ["none"] = "없음" };

    public static readonly Dictionary<string, string> WEAPON_LOG = new()
    {
        ["ghost"] = "유령블록", ["push"] = "밀치기", ["shell"] = "포탄", ["bigshell"] = "대형포탄", ["groundshot"] = "발밑포격", ["leapwave"] = "광폭도약", ["spin"] = "소용돌이회전", ["spinend"] = "소용돌이",
        ["note"] = "음파", ["riff"] = "기타리프", ["glide"] = "낙하음파", ["amp"] = "앰프", ["ampend"] = "앰프마무리", ["pounce"] = "덮치기", ["execute"] = "처형사격", ["wallkick"] = "벽차기", ["blast"] = "블록폭발",
        ["bigbomb"] = "대폭발", ["projectile"] = "투사체", ["shock"] = "충격파", ["bomb"] = "폭탄", ["control"] = "조종블록", ["thrown"] = "설치블록", ["slam"] = "내려찍기", ["hook"] = "갈고리", ["charge"] = "돌진",
        ["slash"] = "순간베기", ["wall"] = "솟는벽", ["blockslam"] = "블록내려찍기",
    };

    public static string CauseKo(string cause) => cause switch
    {
        "crush" => "압사",
        "fall" => "낙사",
        "lava" => "용암",
        "disconnect" => "접속 끊김",
        "hp" => "체력",
        _ => cause,
    };
}
