using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-round.js — 판 흐름: 시작·끝·사망·부활·점수
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
            p.ult = 0;
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

    // 판 시작·부활 때 새로 하는 캐릭터·평타 상태 (JS startRound·respawn 에 같이 있는 필드: comboHits 부터 touchPiece 까지)
    static void ResetCharState(Player p)
    {
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

    // 팀전이면 winner 대신 winnerTeam: 그 팀 참가자 모두 승수 +1. winners: 승자가 여럿일 때 (블록 마스터 생존자들, 킬 점수전 동점)
    public void EndRound(Player? winner, string? winnerTeam = null, List<Player>? winners = null)
    {
        foreach (var p in Players()) if (p.comboHits >= 2) EndCombo(p); // 판이 끝날 때 이어지던 콤보도 로그에
        phase = "over";
        // 판을 끝낸 죽음 (화면: 마지막 킬 슬로모션). FINAL_KILL_WINDOW_MS 안의 죽음만
        var list = winners ?? (winner != null ? new List<Player> { winner } : new List<Player>());
        var d0 = lastDeath;
        if (d0 != null && time - d0.at <= C.FINAL_KILL_WINDOW_MS)
            Emit(o =>
            {
                o.P("type", "finalKill").P("who", d0.who).P("cause", d0.cause).P("by", d0.by).P("x", d0.x).P("y", d0.y).P("z", d0.z);
                WriteXY(o.Key("out"), d0.@out);
                o.P("at", d0.at).Key("winners").Arr();
                foreach (var w in list) o.Num(w.id);
                o.EndArr().P("winnerTeam", winnerTeam);
            });
        roundEndTime = time;
        winnerIds = list.Select(p => p.id).ToList();
        winnerId = list.Count == 1 ? list[0].id : null;
        this.winnerTeam = winnerTeam;
        foreach (var w in list) w.wins++;
        if (winnerTeam != null)
        {
            teamWins[winnerTeam]++;
            foreach (var p in Participants()) if (p.team == winnerTeam) p.wins++;
        }
        double dur = time - roundStartTime;
        int crush = deaths.Count(d => d.cause == "crush"), fall = deaths.Count(d => d.cause == "fall"), lavaN = deaths.Count(d => d.cause == "lava");
        totals["rounds"]++;
        totals["crush"] += crush;
        totals["fall"] += fall;
        totals["lava"] += lavaN;
        string deathStr = deaths.Count > 0 ? string.Join(", ", deaths.Select(d => $"{d.name} {CauseKo(d.cause)}@{FmtTime(d.t)}")) : "없음";
        string winText = winnerTeam != null ? $"{TEAM_KO[winnerTeam]}팀" : list.Count > 0 ? string.Join(" ", list.Select(p => p.name)) : "무승부"; // 여럿이면 공백으로 (npm run stats)
        Log($"===== ROUND {JsNumber.ToJs(roundNumber)} 종료 | 길이 {FmtTime(dur)} | 승자: {winText} =====");
        Log($"  사망: {deathStr}");
        Log($"  블록: {string.Join(" / ", landed.Select(kv => $"{LANDED_LOG[kv.Key]} {JsNumber.ToJs(kv.Value)}"))}");
        int left = grid.Count(v => v != 0 && v != Pieces.CELL.TERRAIN);
        Log($"  지형 변화: 남은 칸 {left} / 평균 높이 +{JsNumber.ToFixed(AvgHeight() - baseAvgHeight, 2)}"); // 판 끝에 시작 지형 말고 남은 블록 칸
        if (mode == "master")
        {
            var m = Master();
            Log($"  결과: {(list.Any(p => p.master) ? $"마스터 {m!.name} 승 (생존자 전멸)" : list.Count > 0 ? $"생존자 {list.Count}명 승" : "무승부")}");
            // 마스터 편으로 넘어갔던 사람은 원래대로 (죽은 상태), 하늘에 떠 있던 다음 블록들은 치움
            foreach (var z in Players())
            {
                if (!z.zombie) continue;
                z.master = false;
                z.zombie = false;
                z.alive = false;
            }
            pieces = pieces.Where(pc => pc.phase != "control").ToList();
            RefreshPieceCells();
            if (m != null)
            {
                // 판이 끝나면 마스터도 필드 가운데 꼭대기로 내려와 보통 사람처럼
                int cx = W / 2, cy = D / 2;
                m.master = false;
                m.x = cx + 0.5;
                m.y = cy + 0.5;
                m.z = ColumnTop(cx, cy);
                m.vz = 0;
            }
        }
        else if (mode == "kills")
        {
            Log($"  점수: {string.Join(" / ", Participants().OrderBy(p => p.slot).Select(p => $"{p.name} {JsNumber.ToJs(ScoreOf(p.id))}"))}");
            if (teamMode) Log($"  팀 점수: 빨강 {JsNumber.ToJs(teamScores["red"])} : {JsNumber.ToJs(teamScores["blue"])} 파랑");
        }
        Log($"  승수: {string.Join(" / ", Participants().OrderBy(p => p.slot).Select(p => $"{p.name} {JsNumber.ToJs(p.wins)}"))}");
        if (teamMode) Log($"  팀 승수: 빨강 {JsNumber.ToJs(teamWins["red"])} : {JsNumber.ToJs(teamWins["blue"])} 파랑");
        Log($"  이번 판: 압사 {crush} / 낙사 {fall} / 용암 {lavaN}{(lava.active ? $" (용암 시작 @ {FmtTime(lava.startedAt - roundStartTime)})" : "")}");
        string per = JsNumber.ToFixed(totals["crush"] / totals["rounds"], 2);
        Log($"  누적 {JsNumber.ToJs(totals["rounds"])}판: 압사 {JsNumber.ToJs(totals["crush"])} (판당 {per}) / 낙사 {JsNumber.ToJs(totals["fall"])} / 용암 {JsNumber.ToJs(totals["lava"])}");
        double n = roundPlayerCount;
        // 봇이 낀 판은 따로 센다
        string label = roundBotCount != 0 ? $"{JsNumber.ToJs(n)}인(봇 {JsNumber.ToJs(roundBotCount)})" : $"{JsNumber.ToJs(n)}인";
        if (!totalsByCount.TryGetValue(label, out var t))
        {
            t = new Dictionary<string, double> { ["rounds"] = 0, ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 };
            totalsByCount[label] = t;
        }
        t["rounds"]++;
        t["crush"] += crush;
        t["fall"] += fall;
        t["lava"] += lavaN;
        Log($"  누적 사망 중 압사 비율: {ShareText(totals["crush"], totals["fall"], totals["lava"])}");
        if (totalsByCount.Count > 1 || label != "2인")
        {
            // 인원이 섞이면 인원수별로도 찍는다
            foreach (var (k, v) in totalsByCount)
                Log($"    {k} 판 {JsNumber.ToJs(v["rounds"])}판: 압사 {JsNumber.ToJs(v["crush"])} / 낙사 {JsNumber.ToJs(v["fall"])} / 용암 {JsNumber.ToJs(v["lava"])} → {ShareText(v["crush"], v["fall"], v["lava"])}");
        }
    }

    double ScoreOf(int id) => scores.TryGetValue(id, out var v) ? v : 0;

    public void CheckRoundEnd()
    {
        if (phase != "playing") return;
        if (mode == "practice") return; // 연습 판은 안 끝남
        if (mode == "master")
        {
            CheckMasterEnd();
            return;
        }
        if (mode == "kills")
        {
            CheckKillsEnd();
            return;
        }
        var alive = Players().Where(p => p.alive).ToList();
        if (teamMode)
        {
            // 살아 있는 사람이 한 팀뿐이면 그 팀 승리 (둘 다 없으면 무승부)
            var teams = new HashSet<string>(alive.Select(p => p.team));
            if (teams.Count <= 1) EndRound(null, alive.Count > 0 ? alive[0].team : null);
            return;
        }
        if (alive.Count <= 1 && players.Count >= 1) EndRound(alive.FirstOrDefault());
    }

    // 블록 마스터: 생존자가 다 죽으면 마스터 승, 시간이 끝나면 살아 있는 생존자 모두 승. 마스터가 나가면 생존자 승
    void CheckMasterEnd()
    {
        var m = Master();
        var survivors = Participants().Where(p => !p.master && p.alive).ToList();
        if (m == null) EndRound(null, null, survivors);
        else if (survivors.Count == 0) EndRound(m);
        else if (time >= roundEndsAt)
        {
            Log($"  시간 끝 ({FmtTime(C.MASTER_TIME_MS)}) → 생존자 승");
            EndRound(null, null, survivors);
        }
    }

    // 킬 점수전: 시간이 끝나거나 목표 점수에 닿거나 상대가 다 나가면 끝. 점수가 가장 높은 사람(동점이면 모두)·팀 승
    void CheckKillsEnd()
    {
        var ps = Participants();
        string? reason = null;
        if (time >= roundEndsAt) reason = $"시간 끝 ({FmtTime(C.KILLS_TIME_MS)})";
        if (teamMode)
        {
            double red = teamScores["red"], blue = teamScores["blue"];
            if (Math.Max(red, blue) >= killsTarget) reason = $"팀 {JsNumber.ToJs(killsTarget)}킬";
            if (!ps.Any(p => p.team == "red") || !ps.Any(p => p.team == "blue")) reason = "한 팀이 다 나감";
            if (reason == null) return;
            Log($"  {reason} → 판 끝");
            EndRound(null, red > blue ? "red" : blue > red ? "blue" : null);
            return;
        }
        double top = ps.Select(p => ScoreOf(p.id)).DefaultIfEmpty(double.NegativeInfinity).Max();
        if (top >= killsTarget) reason = $"{JsNumber.ToJs(killsTarget)}킬";
        if (ps.Count < C.MIN_PLAYERS) reason = "상대가 다 나감";
        if (reason == null) return;
        Log($"  {reason} → 판 끝");
        EndRound(null, null, ps.Where(p => ScoreOf(p.id) == top).ToList());
    }

    // 킬 점수전 점수: 킬 낸 사람 +1, 킬 없이 죽으면(자멸) 죽은 사람 -1. 킬 낸 사람이 이미 나갔으면 점수 없음
    void ScoreDeath(Player p, LastHit? credit)
    {
        var by = credit != null ? GetPlayer(credit.by) : null;
        p.respawnAt = time + C.KILLS_RESPAWN_MS;
        if (credit != null && by == null) return;
        var who = by ?? p;
        double d = by != null ? 1 : -1;
        scores[who.id] = ScoreOf(who.id) + d;
        if (teamMode) teamScores[who.team] += d;
        Log($"  [점수] {who.name} {(d > 0 ? "+1" : "자멸 -1")} → {JsNumber.ToJs(scores[who.id])}{(teamMode ? $" (팀 빨강 {JsNumber.ToJs(teamScores["red"])} : {JsNumber.ToJs(teamScores["blue"])} 파랑)" : "")}");
    }

    // 킬 점수전 부활 자리: 가장 높은 기둥들(가장 높은 것 -1칸까지) 중 살아 있는 상대에게서 가장 먼 곳. 떨어지는 블록 밑은 피함
    public (double x, double y, double z) RespawnSpot(Player p)
    {
        var busy = new HashSet<int>();
        foreach (var pc in pieces) foreach (var c in pc.cells) busy.Add((pc.px + c[0]) * 100 + (pc.py + c[1]));
        var others = Players().Where(o => o != p && OnField(o)).ToList();
        var cols = new List<(int x, int y, int top)>();
        for (int x = 0; x < W; x++)
        {
            for (int y = 0; y < D; y++)
            {
                int top = ColumnTop(x, y);
                if (top <= H - 3 && !busy.Contains(x * 100 + y)) cols.Add((x, y, top));
            }
        }
        if (cols.Count == 0) return (W / 2.0, D / 2.0, ColumnTop(W / 2, D / 2));
        int maxTop = cols.Max(c => c.top);
        (int x, int y, int top)? best = null;
        double bestD = -1;
        foreach (var c in cols)
        {
            if (c.top < maxTop - 1) continue;
            double d = double.PositiveInfinity;
            foreach (var o in others) d = Math.Min(d, JsMath.Hypot(o.x - (c.x + 0.5), o.y - (c.y + 0.5)));
            if (d > bestD)
            {
                bestD = d;
                best = c;
            }
        }
        return (best!.Value.x + 0.5, best.Value.y + 0.5, best.Value.top);
    }

    public void Respawn(Player p)
    {
        var s = RespawnSpot(p);
        p.x = s.x;
        p.y = s.y;
        p.z = s.z;
        p.vz = 0;
        p.kbx = 0;
        p.kby = 0;
        p.grounded = true;
        p.lastGround = null;
        p.alive = true;
        p.stunUntil = 0;
        p.freezeUntil = 0;
        p.jumpUntil = 0;
        p.airJumps = C.AIR_JUMPS;
        p.airDashes = C.AIR_DASHES;
        p.ghostUntil = 0;
        p.speedUntil = 0;
        p.bombs = 0;
        p.bricks = 0;
        p.ammo = 0;
        p.damage = 0;
        ResetCharState(p);
        p.hasControl = false;
        p.deathCause = null;
        p.lastHit = null;
        p.emoteUntil = 0;
        p.respawnAt = 0;
        p.shieldUntil = time + C.KILLS_SHIELD_MS;
        Emit(o => o.P("type", "respawn").P("who", p.id));
        Log($"  [부활] {p.name} → ({JsNumber.ToJs(Math.Floor(s.x))},{JsNumber.ToJs(Math.Floor(s.y))}) z={JsNumber.ToJs(s.z)}");
    }

    // 킬: src(그 블록을 조종·투척한 사람)가 있으면 그 사람, 없으면 판 안에서 마지막으로 나를 날린 사람 (시간 제한 없음). 내 블록에 내가 깔리면 킬 없음
    public void Kill(Player p, string cause, LastHit? src = null)
    {
        if (!p.alive) return;
        if (mode == "practice" && (p.dummy || PracticeNoDeath()))
        {
            PracticeReset(p, cause); // 연습: 허수아비·안 죽음은 바로 제자리
            return;
        }
        p.alive = false;
        p.deathCause = cause;
        p.hasControl = false;
        double t = time - roundStartTime;
        LastHit? credit = src != null ? new LastHit { by = src.by, kind = src.kind, name = GetPlayer(src.by)?.name } : p.lastHit;
        if (credit != null && (credit.by == p.id || credit.name == null || credit.name == "" || SameTeam(GetPlayer(credit.by), p))) credit = null; // 팀 블록에 깔려도 킬 아님
        deaths.Add(new Death { name = p.name, cause = cause, t = t, hasKiller = true, killer = credit?.name, weapon = credit?.kind });
        // 화면 KO 연출: 죽은 자리 + 낙사면 떨어진 쪽
        var @out = cause == "fall" ? Outward(p) : null;
        lastDeath = new LastDeath { who = p.id, cause = cause, by = credit?.by, x = p.x, y = p.y, z = p.z, @out = @out, at = time };
        Emit(o =>
        {
            o.P("type", "death").P("who", p.id).P("cause", cause).P("by", credit?.by).P("weapon", credit?.kind).P("byName", credit?.name).P("x", p.x).P("y", p.y).P("z", p.z);
            WriteXY(o.Key("out"), @out);
        });
        // 킬 알림: 죽음마다 하나. killer 가 null 이면 킬 없음 (자멸). streak = 그 킬러가 죽지 않고 이어 낸 킬 수
        var killer = credit != null ? GetPlayer(credit.by) : null;
        p.killStreak = 0;
        if (killer != null) killer.killStreak = killer.killStreak + 1;
        Emit(o => o.P("type", "kill").P("killer", killer?.id).P("killerName", credit?.name).P("victim", p.id).P("victimName", p.name).P("cause", cause).P("weapon", credit?.kind).P("streak", killer != null ? killer.killStreak : 0));
        string killText = credit != null ? $", 킬 {credit.name} {WEAPON_LOG[credit.kind]}" : ", 킬 없음";
        Log($"  [사망] {p.name} {CauseKo(cause)} @ {FmtTime(t)} (위치 {JsNumber.ToFixed(p.x, 1)}, {JsNumber.ToFixed(p.y, 1)}, {JsNumber.ToFixed(p.z, 1)}, 피해 {JsNumber.ToJs(p.damage)}%{killText}, 밟은 칸 {GROUND_LOG[p.lastGround ?? "none"]})");
        if (mode == "kills" && phase == "playing") ScoreDeath(p, credit);
        if (mode == "master" && phase == "playing" && !p.master && Master() != null) JoinMasterSide(p);
        if (mode == "practice") p.respawnAt = time + C.PRACTICE_RESPAWN_MS; // 연습 ("안 죽음" 끔): 잠깐 뒤 제자리
        p.ghostReadyAt = time; // 유령 투하: 죽자마자 첫 1개
    }

    // 낙사한 쪽: 필드 밖이면 가장 가까운 필드 점에서 그 사람 쪽, 필드 안이면 가장 가까운 가장자리 바깥 (단위 벡터)
    public XY Outward(Player p)
    {
        double cx = Math.Max(0, Math.Min(W, p.x)), cy = Math.Max(0, Math.Min(D, p.y));
        double dx = p.x - cx, dy = p.y - cy;
        if (JsMath.Hypot(dx, dy) < 1e-6)
        {
            var edges = new[] { (p.x, -1.0, 0.0), (W - p.x, 1.0, 0.0), (p.y, 0.0, -1.0), (D - p.y, 0.0, 1.0) }.OrderBy(e => e.Item1).ToList(); // 안정 정렬 (JS sort)
            (_, dx, dy) = edges[0];
        }
        double len = JsMath.Hypot(dx, dy);
        if (len == 0 || double.IsNaN(len)) len = 1;
        return new XY(dx / len, dy / len);
    }
}
