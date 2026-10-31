using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 게임 상태 (server/game.js). JS 처럼 생성자·Emit·Tick 만 여기, 메서드는 묶음 파일 Game.<묶음>.cs 에 partial 로
// (game-grid.js → Game.Grid.cs, char-ninja.js → Game.CharNinja.cs …). 같은 이름 메서드가 두 곳이면 컴파일 에러 (JS 의 시작 때 에러와 같음)
// 뼈대 (2026-10-31): 대기실까지만 — 플레이어 넣고 빼기·스냅샷. 판(startRound 이후)은 묶음별로 옮김 (godot/PLAN.md)
public sealed partial class Game
{
    readonly Action<string> logOut;
    readonly List<string> pendingLogs = new();
    public Func<double> rng = Random.Shared.NextDouble; // 서버 난수는 전부 여기 (해시·sim 은 Mulberry32)
    public double time;
    public string phase = "lobby"; // lobby | countdown | playing | over
    public readonly Dictionary<int, Player> players = new(); // 넣은 순서 유지 (JS Map 과 같게 — 지우면 순서가 바뀔 수 있어 OrderedPlayers 로 돎)
    readonly List<int> order = new();
    public int? hostId;
    public double countdownMs;
    public bool characters;
    public bool skyStairs;
    public bool sky;
    public double W = C.GRID_W, D = C.GRID_D, H = C.GRID_H;
    public byte[] grid;
    public int gridVersion;
    public bool gridDirty = true;
    public string mode = C.MODE_DEFAULT;
    public string mapChoice = "flat";
    public string mapId = "flat";
    public string botLevel = C.BOT_LEVEL_DEFAULT;
    public bool teamMode;
    public bool hpMode;
    public double roundNumber, roundStartTime, roundEndTime, countdownEndsAt, nextSpawnAt;
    public int? winnerId;
    public string? winnerTeam;
    public readonly List<int> winnerIds = new();
    public readonly Dictionary<string, double> totals = new() { ["rounds"] = 0, ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 };
    public readonly Dictionary<string, double> teamWins = new() { ["red"] = 0, ["blue"] = 0 };
    public readonly Dictionary<string, double> teamScores = new() { ["red"] = 0, ["blue"] = 0 };
    public readonly Dictionary<int, double> scores = new();
    public (bool active, double z) lava = (false, C.LAVA_START_Z);
    List<string> events = new(); // 이벤트는 만들 때 JSON 글자로 (스냅샷에 그대로 붙임)
    public int botCounter;

    public Game(Action<string>? log = null, bool characters = false, bool skyStairs = false, double countdownMs = 0)
    {
        logOut = log ?? (_ => { });
        this.characters = characters;
        this.skyStairs = skyStairs;
        this.countdownMs = countdownMs;
        grid = new byte[(int)(W * D * H)];
    }

    // 콤보 마무리 줄은 다음 로그 줄 뒤에 (JS pendingLogs 와 같음)
    public void Log(string m)
    {
        logOut(m);
        FlushLogs();
    }

    void FlushLogs()
    {
        while (pendingLogs.Count > 0)
        {
            var l = pendingLogs[0];
            pendingLogs.RemoveAt(0);
            logOut(l);
        }
    }

    // 이벤트 하나 = JSON 객체 글자. 예: Emit(o => o.P("type", "land").P("who", id))
    public void Emit(Action<JsonOut> write)
    {
        var o = new JsonOut();
        o.Obj();
        write(o);
        o.EndObj();
        events.Add(o.ToString());
    }

    public List<string> DrainEvents()
    {
        var out_ = events;
        events = new List<string>();
        return out_;
    }

    public IEnumerable<Player> Players()
    {
        foreach (var id in order) yield return players[id];
    }

    public void Tick(double dtMs)
    {
        FlushLogs();
        time += dtMs;
        if (phase != "playing") return;
        throw new NotImplementedException("판 진행은 아직 안 옮김 (godot/PLAN.md 작업 목록)");
    }
}
