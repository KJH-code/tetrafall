using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 게임 상태 (server/game.js). JS 처럼 생성자·Emit·Tick 만 여기, 메서드는 묶음 파일 Game.<묶음>.cs 에 partial 로
// (game-grid.js → Game.Grid.cs, char-ninja.js → Game.CharNinja.cs …). 같은 이름 메서드가 두 곳이면 컴파일 에러 (JS 의 시작 때 에러와 같음).
// 아직 안 옮긴 메서드는 Game.Todo.cs 에 NotImplementedException 으로 (옮기면 거기서 지움)
public sealed partial class Game
{
    readonly Action<string> logOut;
    readonly List<string> pendingLogs = new(); // 콤보 마무리 줄은 다음 로그 줄 뒤에
    public double countdownMs;
    public bool characters;
    public bool skyStairs; // 호스트 옵션 (판 사이에만 바꿈)
    public bool hpMode; // 체력전
    public double killsTarget; // 킬 점수전 목표 (판 시작 때)
    public double masterStallUntil; // 블록 마스터: 반격 아이템으로 마스터 편 다음 블록이 이때까지 안 나옴
    public double counterItemAt; // 블록 마스터: 다음 반격 아이템 시각
    public double masterDropStep; // 블록 마스터 하드드롭 빠르기 (판 시작 때, JS 는 startRound 전엔 undefined)
    public bool sky; // 이번 판에 하늘 계단이 도는지
    public int H = (int)C.GRID_H;
    public List<int> skyTops = new(); // 하늘 계단 사슬마다 맨 위 블록 id
    public double skyChains = 1;
    public double skyLavaMs = C.SKY_LAVA_TRIGGER_MS;
    public Func<double> rng = Random.Shared.NextDouble; // 서버 난수는 전부 여기 (해시·sim 은 Mulberry32)
    public double time; // 게임 시간 (ms)
    public string phase = "lobby"; // lobby | countdown | playing | over
    public readonly OrderedDictionary<int, Player> players = new(); // id → player (JS Map: 넣은 순서, 지우고 넣으면 끝으로)
    public int? hostId;
    public int W = (int)C.GRID_W, D = (int)C.GRID_D; // 판 크기 (판 시작 때 인원으로, FIELD_SIZES)
    public C.SpawnPt[] spawnPoints = C.SPAWN_POINTS;
    public byte[] grid;
    public int[] gridPiece; // 칸마다 착지한 블록 id (갈고리 R 덩어리)
    public double gridVersion;
    public List<Piece> pieces = new(); // 떨어지는·조종 중인 블록들
    public int pieceCounter;
    public Dictionary<long, int> pieceCells = new(); // 칸 키 → 블록 id (충돌용, 돌지 않으니 순서 상관없음)
    public Lava lava = new();
    public string botLevel = C.BOT_LEVEL_DEFAULT;
    public bool teamMode;
    public string mode = C.MODE_DEFAULT; // survival | master | kills | practice
    public int masterTurn;
    public double roundEndsAt;
    public OrderedDictionary<int, double> scores = new(); // 킬 점수전: 플레이어 id → 점수
    public Dictionary<string, double> teamScores = new() { ["red"] = 0, ["blue"] = 0 };
    public List<int> winnerIds = new();
    public readonly Dictionary<string, double> teamWins = new() { ["red"] = 0, ["blue"] = 0 };
    public string? winnerTeam;
    public string mapChoice = "flat";
    public string mapId = "flat";
    public double baseAvgHeight;
    public List<Item> items = new();
    public List<Projectile> projectiles = new();
    public List<Bomb> bombs = new();
    public OrderedDictionary<long, BBlock> bblocks = new(); // 건축가 블록: 칸 키 → 블록 (JS Map 순서)
    public List<BigBomb> bigBombs = new();
    public List<Hole> holes = new();
    public List<Quake> quakes = new();
    public Profiler? prof; // 틱 구간 재기 (LoadBench, 보통 null)
    public List<Shell> shells = new();
    public List<Note> notes = new();
    public int shellCounter;
    public int bgroup;
    public int bombCounter;
    public double roundNumber;
    public double roundStartTime;
    public double roundEndTime;
    public double countdownEndsAt;
    public int? winnerId;
    public List<Death> deaths = new(); // 이번 판 사망 기록
    public LastDeath? lastDeath;
    public Dictionary<string, double> landed = GameUtil.EmptyLanded();
    public readonly Dictionary<string, double> totals = new() { ["rounds"] = 0, ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 };
    public readonly OrderedDictionary<string, Dictionary<string, double>> totalsByCount = new(); // 인원수별 누적 (JS 객체 키 순서 — 숫자 모양 키는 없음: '2인' 등)
    public double roundPlayerCount;
    public double roundBotCount;
    public readonly OrderedDictionary<int, BotBrain> bots = new(); // 봇 id (음수) → 머리
    public readonly OrderedDictionary<int, BotBrain> proxies = new(); // 끊긴 사람 id → 대신 조종하는 머리
    public int botCounter;
    public double nextSpawnAt;
    public double controlItemNextAt;
    public double powerItemNextAt;
    public bool gridDirty = true;
    List<string> events = new(); // 이벤트는 만들 때 JSON 글자로 (스냅샷에 그대로 붙임)

    // countdownMs: 판 시작 전 카운트다운 (서버 C.ROUND_COUNTDOWN_MS, 테스트 기본 0). characters·skyStairs·hpMode: JS 옵션과 같음
    public Game(Action<string>? log = null, bool characters = false, bool skyStairs = false, double countdownMs = 0, bool hpMode = false)
    {
        logOut = log ?? (_ => { });
        this.countdownMs = countdownMs;
        this.characters = characters;
        this.skyStairs = skyStairs;
        this.hpMode = hpMode;
        grid = new byte[W * D * H];
        gridPiece = new int[grid.Length];
    }

    public void Log(string m)
    {
        logOut(m);
        FlushLogs();
    }

    public void FlushLogs()
    {
        while (pendingLogs.Count > 0)
        {
            var l = pendingLogs[0];
            pendingLogs.RemoveAt(0);
            logOut(l);
        }
    }

    // 다음 로그 줄 뒤에 찍을 줄 (콤보 마무리)
    public void LogLater(string m) => pendingLogs.Add(m);

    // 이벤트 하나 = JSON 객체 글자. 예: Emit(o => o.P("type", "land").P("who", id))
    public void Emit(Action<JsonOut> write)
    {
        var o = new JsonOut();
        o.Obj();
        write(o);
        o.EndObj();
        string json = o.ToString();
        events.Add(json);
        if (tutorial != null) tutorial.OnEvent(System.Text.Json.JsonDocument.Parse(json).RootElement); // 튜토리얼 완료 판정 (치명타·스킬·낙사 등)
    }

    public List<string> DrainEvents()
    {
        var out_ = events;
        events = new List<string>();
        return out_;
    }

    // JS this.players.values() (넣은 순서)
    public IEnumerable<Player> Players() => players.Values;

    public Player? GetPlayer(int? id) => id.HasValue && players.TryGetValue(id.Value, out var p) ? p : null;

    // ---------- 틱 ----------
    public void Tick(double dtMs)
    {
        FlushLogs();
        time += dtMs;
        if (phase == "countdown" && time >= countdownEndsAt) BeginPlay();
        if (phase != "playing") return;
        prof?.Begin();
        double dt = dtMs / 1000;
        foreach (var (id, brain) in bots.ToList())
        {
            var p = GetPlayer(id);
            if (p != null && p.alive) brain.Update(this, p);
            else if (p != null && C.GHOST_DROP_BOTS && GhostCd(p) == 0) brain.GhostDrop(this, p);
        }
        foreach (var (id, brain) in proxies.ToList())
        {
            var p = GetPlayer(id);
            if (p != null && p.alive && OnField(p)) brain.Update(this, p);
        }
        prof?.Lap("bots");
        UpdatePieces();
        prof?.Lap("pieces");
        double remaining = dt;
        while (remaining > 0)
        {
            double h = Math.Min(remaining, C.MAX_STEP_DT);
            foreach (var p in Players()) if (OnField(p)) IntegratePlayer(p, h);
            remaining -= h;
        }
        foreach (var p in Players()) if (p.grounded && p.alive && OnField(p)) p.lastGround = GroundKind(p);
        prof?.Lap("physics");
        UpdateCombat();
        prof?.Lap("combat");
        if (hpMode) HpKnockouts();
        foreach (var p in Players().ToList())
        {
            if (OnField(p) && p.z < C.FALL_DEATH_Z) Kill(p, "fall");
        }
        if (mode == "kills")
        {
            foreach (var p in Participants()) if (!p.alive && p.respawnAt != 0 && time >= p.respawnAt) Respawn(p);
        }
        if (mode == "practice") UpdatePractice();
        TutorialUpdate(dtMs);
        UpdateLava(dtMs);
        UpdateItems();
        UpdateProjectiles(dt);
        if (shells.Count > 0) UpdateShells(dt);
        if (notes.Count > 0) UpdateNotes(dt);
        UpdateBombs();
        prof?.Lap("rest");
        if (C.ROUND_TIME_LIMIT_MS > 0 && time - roundStartTime >= C.ROUND_TIME_LIMIT_MS)
        {
            Log("  시간 초과 → 무승부");
            EndRound(null);
            return;
        }
        CheckRoundEnd();
        prof?.Lap("rest");
    }
}
