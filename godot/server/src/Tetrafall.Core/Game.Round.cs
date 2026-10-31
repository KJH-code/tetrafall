using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-round.js — 판 흐름: 시작·끝·사망·부활·점수 (S1: 시작. 나머지는 S2)
public sealed partial class Game
{
    // ---------- 판 흐름 ----------
    public bool StartRound()
    {
        if (!CanStart()) return false;
        int fielded = Participants().Count - (mode == "master" ? 1 : 0);
        sky = skyStairs && mode != "master"; // 블록 마스터는 자동 블록이 없음
        skyTops = new List<int>();
        skyChains = ByCount(C.SKY_CHAINS, fielded);
        skyLavaMs = ByCount(C.SKY_LAVA_TRIGGER_BY_COUNT, fielded);
        SetFieldSize(FieldSizeFor(fielded));
        string hpKey = hpMode ? "hp" : "off";
        killsTarget = ByCount((teamMode ? C.KILLS_TARGET_TEAM_BY_COUNT : C.KILLS_TARGET_BY_COUNT)[hpKey], Participants().Count); // 킬 점수전 목표
        masterDropStep = ByCount(C.MASTER_DROP_STEP_BY_COUNT, Participants().Count); // 블록 마스터 하드드롭 빠르기
        masterStallUntil = 0;
        mapId = mapChoice == "random" ? Maps.MAP_IDS[(int)Math.Floor(rng() * Maps.MAP_IDS.Length)] : mapChoice;
        foreach (var (x, y, h) in Maps.MapColumns(mapId, W, D))
        {
            for (int z = 0; z < h && z < H; z++) grid[Idx(x, y, z)] = Pieces.CELL.TERRAIN;
        }
        baseAvgHeight = AvgHeight();
        gridVersion++;
        gridDirty = true;
        pieces = new List<Piece>();
        pieceCells.Clear();
        lava = new Lava();
        items = new List<Item>();
        projectiles = new List<Projectile>();
        bombs = new List<Bomb>();
        bblocks = new OrderedDictionary<long, BBlock>();
        bigBombs = new List<BigBomb>();
        holes = new List<Hole>();
        var oldQuakes = quakes; // 판 시작 때 버리는 솟는 땅 → events 를 비운 뒤 quakeFall 로 알림
        quakes = new List<Quake>();
        shells = new List<Shell>();
        notes = new List<Note>();
        bgroup = 0;
        bombCounter = 0;
        lastDeath = null;
        deaths = new List<Death>();
        landed = EmptyLanded();
        events = new List<string>();
        foreach (var q in oldQuakes) Emit(o => o.P("type", "quakeFall").P("id", q.id).Key("gone").Arr().EndArr().Key("cells").Arr().EndArr());
        winnerId = null;
        winnerTeam = null;
        winnerIds = new List<int>();
        scores = new OrderedDictionary<int, double>();
        teamScores = new Dictionary<string, double> { ["red"] = 0, ["blue"] = 0 };
        roundNumber++;
        foreach (var p in Players())
        {
            var sp = spawnPoints[p.slot % spawnPoints.Length];
            p.x = sp.x;
            p.y = sp.y;
            p.z = SpawnZ(sp.x, sp.y);
            p.yaw = sp.yaw;
            p.pitch = 0;
            p.vz = 0;
            p.kbx = 0;
            p.kby = 0;
            p.grounded = true;
            p.lastGround = null;
            p.alive = !p.spectator;
            p.stunUntil = 0;
            p.freezeUntil = 0;
            p.jumpUntil = 0;
            p.airJumps = C.AIR_JUMPS;
            p.airDashes = C.AIR_DASHES;
            p.ghostUntil = 0;
            p.speedUntil = 0;
            p.bombs = 0;
            p.bricks = 0;
            p.brickSide = false;
            p.damage = 0;
            p.dashReadyAt = 0;
            p.pushReadyAt = 0;
            p.hasControl = false;
            p.ammo = 0;
            p.deathCause = null;
            p.lastHit = null;
            p.killStreak = 0;
            p.emoteUntil = 0;
            p.emoteReadyAt = 0;
            p.master = false;
            p.zombie = false;
            p.nextPieceAt = 0;
            p.respawnAt = 0;
            p.shieldUntil = 0;
            p.skillReadyAt = 0;
            ResetCharState(p);
        }
        if (mode == "master")
        {
            // 마스터는 자리 순서로 돌아감. 필드 위 하늘에 둠
            var ps = Participants().OrderBy(p => p.slot).ToList();
            var m = ps[masterTurn % ps.Count];
            masterTurn++;
            m.master = true;
            m.x = W / 2.0;
            m.y = D / 2.0;
            m.z = H + 4;
        }
        if (countdownMs > 0)
        {
            phase = "countdown";
            countdownEndsAt = time + countdownMs;
        }
        else BeginPlay();
        return true;
    }

    // 판 시작·부활 때 새로 하는 캐릭터·평타 상태 (JS startRound·respawn 의 같은 필드 묶음: ult 부터 touchPiece 까지)
    static void ResetCharState(Player p)
    {
        p.ult = 0;
        p.comboHits = 0;
        p.comboStartAt = 0;
        p.iframeUntil = 0;
        p.chargeUntil = 0;
        p.slamAt = 0;
        p.wallAt = 0;
        p.wallCells = null;
        p.loaded = true;
        p.zipUntil = 0;
        p.zipDir = null;
        p.grab = null;
        p.marks = new OrderedDictionary<int, Mark>();
        p.leap = null;
        p.windup = null;
        p.hookFly = null;
        p.huntAim = null;
        p.rush = null;
        p.spin = null;
        p.form = "bard";
        p.glideUntil = 0;
        p.glideCount = 0;
        p.dive = null;
        p.diveUsed = false;
        p.amp = null;
        p.slowUntil = 0;
        p.vulnUntil = 0;
        p.cannonAmmo = C.CANNON_AMMO_MAX;
        p.reloadAt = 0;
        p.atk = null;
        p.atkQueued = false;
        p.atkLanded = false;
        p.castQueued = null;
        p.chainN = 0;
        p.chainUntil = 0;
        p.launchUntil = 0;
        p.airN = 0;
        p.lastBasic = null;
        p.streak = 0;
        p.streakUntil = 0;
        p.empowerUntil = 0;
        p.star2 = null;
        p.touchPiece = 0;
    }

    // 카운트다운이 끝나면 (또는 바로) 판 시작. 판 시간·블록·아이템 시계는 여기서부터
    public void BeginPlay()
    {
        phase = "playing";
        var ps = Participants();
        roundPlayerCount = ps.Count;
        roundBotCount = ps.Count(p => p.isBot);
        roundStartTime = time;
        nextSpawnAt = time + C.FIRST_SPAWN_DELAY_MS;
        counterItemAt = time + C.MASTER_COUNTER_FIRST_MS;
        controlItemNextAt = time + C.CONTROL_ITEM_RESPAWN_MS;
        powerItemNextAt = time + C.ITEM_FIRST_SPAWN_MS;
        string lv = ps.Any(p => p.isBot) ? $", 봇 {BOT_LEVEL_KO[botLevel]}" : "";
        var sorted = ps.OrderBy(p => p.slot).ToList();
        Log($"===== ROUND {JsNumber.ToJs(roundNumber)} 시작 ({ps.Count}명: {string.Join(" ", sorted.Select(p => p.name))}, 맵 {Maps.MAPS[mapId].Log}{lv}) =====");
        if (teamMode) Log($"  팀: {TeamLine()}");
        if (sky) Log("  하늘 계단: 켬");
        if (hpMode) Log($"  체력전: 켬 (HP {JsNumber.ToJs(HpMax())})");
        // JS 는 위에서 ps 를 제자리 정렬 (ps.sort) → 캐릭터 줄도 자리 순
        if (characters) Log($"  캐릭터: {string.Join(" / ", sorted.Select(p => $"{p.name} {C.CHAR_NAMES[p.@char!]}"))}");
        if (mode == "master")
        {
            roundEndsAt = time + C.MASTER_TIME_MS;
            var m = Master(); // 카운트다운 중에 마스터가 나갔으면 없음 → checkRoundEnd 가 생존자 승으로 끝냄
            Log($"  모드: {C.MODE_NAMES["master"]} ({(m != null ? $"마스터 {m.name}" : "마스터가 나감")}, {FmtTime(C.MASTER_TIME_MS)} 버티기)");
        }
        else if (mode == "kills")
        {
            roundEndsAt = time + C.KILLS_TIME_MS;
            Log($"  모드: {C.MODE_NAMES["kills"]} ({FmtTime(C.KILLS_TIME_MS)} 또는 {(teamMode ? $"팀 {JsNumber.ToJs(killsTarget)}" : JsNumber.ToJs(killsTarget))}킬)");
        }
        else roundEndsAt = 0;
        CheckRoundEnd(); // 카운트다운 중에 나가서 혼자 남았으면 바로 끝
    }
}
