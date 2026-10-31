using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-players.js — 플레이어 관리·대기실 설정·팀전·끊김 (봇 대리)
public sealed partial class Game
{
    // ---------- 플레이어 관리 ----------
    public Player? AddPlayer(int id, bool isBot = false)
    {
        var used = new HashSet<int>(Players().Select(p => p.slot));
        int slot = -1;
        for (int s = 0; s < MaxPlayers(); s++)
        {
            if (!used.Contains(s))
            {
                slot = s;
                break;
            }
        }
        if (slot < 0) return null;
        var sp = spawnPoints[slot % spawnPoints.Length];
        // 필드 순서는 JS 객체와 같게 (rng 를 부르는 char 는 color·team 다음)
        var p = new Player
        {
            id = id,
            slot = slot,
            color = FreeColor(),
            name = $"P{slot + 1}{(isBot ? "(봇)" : "")}",
            isBot = isBot,
            x = sp.x,
            y = sp.y,
            yaw = sp.yaw,
            alive = !InRound(), // 진행 중(카운트다운 포함) 난입은 관전 (죽은 상태)
        };
        p.team = SmallerTeam();
        p.@char = characters ? (isBot ? C.CHARACTERS[(int)Math.Floor(rng() * C.CHARACTERS.Length)] : C.CHAR_DEFAULT) : null; // 봇은 무작위
        players[id] = p;
        if (hostId == null && !isBot) hostId = id;
        Log($"{p.name} 접속 (slot {slot}){(hostId == id ? " — 호스트" : "")}");
        return p;
    }

    // 방에서 아무도 안 쓰는 색 중 가장 앞 번호
    int FreeColor()
    {
        var used = new HashSet<int>(Players().Select(p => p.color));
        for (int c = 0; c < C.PLAYER_PALETTE.Length; c++) if (!used.Contains(c)) return c;
        return 0;
    }

    // 색 고르기: 판 사이에만, 팔레트 안 번호, 방에서 다른 사람이 쓰는 색은 안 됨. raw 는 JS 값 (정수 double 만)
    public bool SetColor(int id, object? raw)
    {
        var p = GetPlayer(id);
        if (p == null || InRound() || raw is not double c || c != Math.Floor(c) || !double.IsFinite(c) || c < 0 || c >= C.PLAYER_PALETTE.Length) return false;
        if (c == p.color) return true;
        if (Players().Any(o => o != p && o.color == c)) return false;
        p.color = (int)c;
        Log($"{p.name} 색: {JsNumber.ToJs(c)}");
        return true;
    }

    // 봇 추가 (판 진행 중에는 안 됨)
    public Player? AddBot()
    {
        if (InRound()) return null;
        int id = -++botCounter;
        var p = AddPlayer(id, true);
        if (p != null) bots[id] = new BotBrain(() => rng(), () => botLevel);
        return p;
    }

    // 가장 나중에 넣은 봇 하나 빼기
    public bool RemoveBot()
    {
        if (InRound() || bots.Count == 0) return false;
        RemovePlayer(bots.Keys.Min()); // 음수라 가장 작은 게 가장 최근
        return true;
    }

    public void RemoveAllBots()
    {
        foreach (var id in bots.Keys.ToList()) RemovePlayer(id);
    }

    // 접속 끊김·복귀 (rooms 가 부름): 자리는 그대로, 끊긴 동안 봇이 대신 조종
    public bool SetAway(int id, bool on)
    {
        var p = GetPlayer(id);
        if (p == null || p.isBot || p.away == on) return false;
        p.away = on;
        if (on)
        {
            proxies[id] = new BotBrain(() => rng(), () => botLevel);
            Log($"  [끊김] {p.name} 자리 유지 {JsNumber.ToJs(C.RECONNECT_GRACE_MS / 1000)}초{(InRound() ? " (봇 대리)" : "")}");
        }
        else
        {
            proxies.Remove(id);
            p.input.fwd = 0;
            p.input.strafe = 0;
            p.input.jump = false;
            Log($"  [복귀] {p.name}");
        }
        return true;
    }

    public int HumanCount() => Players().Count(p => !p.isBot);

    public void RemovePlayer(int id)
    {
        var p = GetPlayer(id);
        if (p == null) return;
        players.Remove(id);
        bots.Remove(id);
        proxies.Remove(id);
        Log($"{p.name} {(p.isBot ? "빠짐" : "접속 종료")}");
        if (hostId == id)
        {
            var next = Players().FirstOrDefault(o => !o.isBot);
            hostId = next?.id;
        }
        foreach (var pc in pieces) if (pc.controller == id) pc.controller = null;
        if (InRound() && p.alive && !p.zombie)
        {
            // 카운트다운 중에 나가도 사망 목록에 남긴다 (판 시계는 아직 0)
            deaths.Add(new Death { name = p.name, cause = "disconnect", t = phase == "playing" ? time - roundStartTime : 0 });
            CheckRoundEnd();
        }
    }

    // 봇 난이도 이름 (BOT_LEVELS 키 순서)
    public static readonly string[] BOT_LEVEL_IDS = C.BOT_LEVELS.Keys.ToArray();

    // 봇 난이도: 판 사이에만
    public bool SetBotLevel(string level)
    {
        if (InRound() || !C.BOT_LEVELS.ContainsKey(level) || level == botLevel) return false;
        botLevel = level;
        Log($"[호스트] 봇 난이도: {BOT_LEVEL_KO[level]}");
        return true;
    }

    public bool SetMap(string choice)
    {
        if (choice != "random" && !Maps.MAP_IDS.Contains(choice)) return false;
        if (mode == "practice" && InRound()) return PracticeMap(choice); // 연습은 판 중에도 바로
        if (InRound()) return false;
        mapChoice = choice;
        return true;
    }

    // 연습: 지형을 바로 바꿈
    public bool PracticeMap(string choice)
    {
        mapChoice = choice;
        string id = choice == "random" ? Maps.MAP_IDS[(int)Math.Floor(rng() * Maps.MAP_IDS.Length)] : choice;
        var cells = new List<(int x, int y, int z, byte v)>();
        foreach (var (x, y, h) in Maps.MapColumns(id, W, D))
            for (int z = 0; z < h; z++) cells.Add((x, y, z, Pieces.CELL.TERRAIN));
        return ResetArena(id, cells);
    }

    // 연습·튜토리얼: 지형을 cells 로 새로 깔고 나머지(블록·아이템·용암 등)는 치움, 모두 제자리로
    public bool ResetArena(string newMapId, List<(int x, int y, int z, byte v)> cells)
    {
        mapId = newMapId;
        grid = new byte[W * D * H];
        gridPiece = new int[grid.Length];
        foreach (var (x, y, z, v) in cells) if (InXY(x, y) && z >= 0 && z < H) grid[Idx(x, y, z)] = v;
        baseAvgHeight = AvgHeight();
        pieces = new List<Piece>();
        RefreshPieceCells();
        bblocks = new OrderedDictionary<long, BBlock>();
        bigBombs = new List<BigBomb>();
        foreach (var q in quakes) Emit(o => o.P("type", "quakeFall").P("id", q.id).Key("gone").Arr().EndArr().Key("cells").Arr().EndArr()); // 버리는 솟는 땅
        quakes = new List<Quake>();
        holes = new List<Hole>();
        items = new List<Item>();
        bombs = new List<Bomb>();
        lava = new Lava();
        gridVersion++;
        gridDirty = true;
        foreach (var p in Participants()) if (p.alive || p.dummy) PracticeReset(p, null);
        Emit(o => o.P("type", "mapChange").P("map", mapId));
        return true;
    }

    // 게임 모드 (판 사이에만). 블록 마스터는 1 대 다라 팀전을 끈다
    public bool SetMode(string m)
    {
        if (InRound() || !C.MODE_NAMES.ContainsKey(m) || mode == m) return false;
        mode = m;
        Log($"[호스트] 모드: {C.MODE_NAMES[m]}");
        if (m == "master" && teamMode)
        {
            teamMode = false;
            Log("[호스트] 팀전 끔 (블록 마스터는 1 대 다)");
        }
        return true;
    }

    public bool SetSkyStairs(bool on)
    {
        if (InRound() || skyStairs == on) return false;
        skyStairs = on;
        Log($"[호스트] 하늘 계단 {(on ? "켬" : "끔")}");
        return true;
    }

    // 체력전 켜고 끄기 (판 사이에만, 연습 방은 안 됨)
    public bool SetHpMode(bool on)
    {
        if (InRound() || mode == "practice" || hpMode == on) return false;
        hpMode = on;
        Log($"[호스트] 체력전 {(on ? "켬" : "끔")}");
        return true;
    }

    // 체력전 최대 HP: 모드별 (HP_MAX_BY_MODE) × 캐릭터 배율 (HP_CHAR_MULT, 캐릭터 켰을 때만, 반올림). p 없으면 모드 값 그대로 (스냅샷 맨 위 hpMax·로그)
    public double HpMax(Player? p = null)
    {
        double @base = C.HP_MAX_BY_MODE.TryGetValue(mode, out var v) ? v : C.HP_MAX_BY_MODE["survival"];
        double mult = p != null && characters && p.@char != null ? C.HP_CHAR_MULT.GetValueOrDefault(p.@char, 1) : 1;
        return mult == 1 ? @base : JsMath.Round(@base * mult);
    }

    // 체력전: HP 가 0 이하인 사람은 그 자리에서 KO (틱마다 전투 뒤에)
    public void HpKnockouts()
    {
        foreach (var p in Players().ToList()) if (p.alive && OnField(p) && p.damage >= HpMax(p)) Kill(p, "hp");
    }

    // 캐릭터 고르기 (판 사이에만, 연습은 판 중에도)
    public bool SetChar(int id, string c)
    {
        var p = GetPlayer(id);
        bool live = mode == "practice" && InRound();
        if (p == null || !characters || p.dummy || (InRound() && !live) || !C.CHARACTERS.Contains(c) || p.@char == c) return false;
        p.@char = c;
        Log($"{p.name} 캐릭터: {C.CHAR_NAMES[c]}");
        if (live && p.alive)
        {
            // 캐릭터별 상태를 되살아날 때처럼 새로, 위치·피해 % 는 그대로
            var (x, y, z, yaw, pitch, vz, kbx, kby, grounded, damage) = (p.x, p.y, p.z, p.yaw, p.pitch, p.vz, p.kbx, p.kby, p.grounded, p.damage);
            if (p.grab != null) HookGrabDrop(p);
            Respawn(p);
            (p.x, p.y, p.z, p.yaw, p.pitch, p.vz, p.kbx, p.kby, p.grounded, p.damage) = (x, y, z, yaw, pitch, vz, kbx, kby, grounded, damage);
            p.shieldUntil = 0;
            p.skillReadyAt = 0;
            p.ult = 0;
            Emit(o => o.P("type", "charChange").P("who", p.id).P("char", c));
        }
        return true;
    }

    // 손에 든 아이템 (하나만)
    public string? HeldItem(Player p) => p.ammo > 0 ? "knockback" : p.bricks > 0 ? "brick" : p.bombs > 0 ? "bomb" : null;

    // 필드 위에 있는 사람: 살아 있고 블록 마스터의 마스터가 아님
    public bool OnField(Player p) => p.alive && !p.master;

    // 블록 마스터 판의 처음 마스터 (죽어서 넘어간 마스터 편은 빼고)
    public Player? Master() => Players().FirstOrDefault(p => p.master && !p.zombie);

    // 블록 마스터: 죽은 생존자는 하늘로 올라가 마스터 편이 됨
    public void JoinMasterSide(Player p)
    {
        p.alive = true;
        p.master = true;
        p.zombie = true;
        p.x = W / 2.0;
        p.y = D / 2.0;
        p.z = H + 4;
        p.vz = 0;
        p.kbx = 0;
        p.kby = 0;
        p.stunUntil = 0;
        p.ghostUntil = 0;
        p.hasControl = false;
        p.nextPieceAt = time + C.MASTER_NEXT_PIECE_MS;
        Emit(o => o.P("type", "zombie").P("who", p.id));
        Log($"  [마스터 편] {p.name} → 하늘에서 블록");
    }

    // 블록 마스터 탑 방지: 놓인 뒤 높이가 둘레 가장 높은 기둥보다 MASTER_MAX_RISE 넘게 높으면 true
    public bool TooTall(IEnumerable<(int x, int y)> cellsXY, int landZ)
    {
        var list = cellsXY.ToList();
        var own = new HashSet<int>(list.Select(c => c.x * 100 + c.y));
        int ring = 0;
        foreach (var (x, y) in list)
        {
            for (int dx = -1; dx <= 1; dx++)
            {
                for (int dy = -1; dy <= 1; dy++)
                {
                    int nx = x + dx, ny = y + dy;
                    if (own.Contains(nx * 100 + ny) || !InXY(nx, ny)) continue;
                    ring = Math.Max(ring, ColumnTop(nx, ny));
                }
            }
        }
        return landZ + 1 - ring > C.MASTER_MAX_RISE;
    }

    // 시작 위치에서 발이 놓일 높이: 플레이어가 걸치는 칸들 중 가장 높은 기둥 위
    public int SpawnZ(double x, double y)
    {
        int top = 0;
        foreach (var ox in new[] { -C.PLAYER_HALF, C.PLAYER_HALF })
        {
            foreach (var oy in new[] { -C.PLAYER_HALF, C.PLAYER_HALF })
            {
                int cx = (int)Math.Floor(x + ox), cy = (int)Math.Floor(y + oy);
                if (InXY(cx, cy)) top = Math.Max(top, ColumnTop(cx, cy));
            }
        }
        return top;
    }

    public bool IsHost(int id) => hostId == id;

    public bool CanStart()
    {
        var ps = Participants();
        if (mode == "practice") return ps.Count >= 1 && !InRound(); // 연습: 혼자도
        if (teamMode && !(ps.Any(p => p.team == "red") && ps.Any(p => p.team == "blue"))) return false; // 팀마다 한 명 이상
        return ps.Count >= C.MIN_PLAYERS && !InRound();
    }

    // ---------- 팀전 ----------
    public bool SameTeam(Player? a, Player? b) => teamMode && a != null && b != null && a != b && a.team == b.team;

    string SmallerTeam()
    {
        var ps = Players().ToList();
        return ps.Count(p => p.team == "red") <= ps.Count(p => p.team == "blue") ? "red" : "blue";
    }

    public bool SetTeamMode(bool on)
    {
        if (InRound() || teamMode == on) return false;
        if (on && mode == "master") return false; // 블록 마스터는 팀전 없음
        teamMode = on;
        Log($"[호스트] 팀전 {(teamMode ? "켬" : "끔")}");
        return true;
    }

    public bool SetTeam(int id, string team)
    {
        var p = GetPlayer(id);
        if (p == null || InRound() || (team != "red" && team != "blue")) return false;
        p.team = team;
        Log($"[호스트] {p.name} {TEAM_KO[team]}팀으로");
        return true;
    }

    // 참가자를 무작위로 섞어 반씩 (홀수면 빨강이 한 명 더)
    public bool ShuffleTeams()
    {
        if (InRound()) return false;
        var ps = Participants();
        for (int i = ps.Count - 1; i > 0; i--)
        {
            int j = (int)Math.Floor(rng() * (i + 1));
            (ps[i], ps[j]) = (ps[j], ps[i]);
        }
        for (int i = 0; i < ps.Count; i++) ps[i].team = i < Math.Ceiling(ps.Count / 2.0) ? "red" : "blue";
        Log($"[호스트] 팀 섞기: {TeamLine()}");
        return true;
    }

    public string TeamLine()
    {
        var ps = Participants().OrderBy(p => p.slot).ToList();
        return string.Join(" / ", new[] { "red", "blue" }.Select(t => $"{TEAM_KO[t]} {string.Join(" ", ps.Where(p => p.team == t).Select(p => p.name))}"));
    }

    // 판에 참가하는 사람 (관전자 빼고)
    public List<Player> Participants() => Players().Where(p => !p.spectator).ToList();

    // 호스트가 관전 ↔ 참가 전환 (판 사이에만)
    public bool SetSpectator(int id, bool on)
    {
        var p = GetPlayer(id);
        if (p == null || InRound()) return false;
        p.spectator = on;
        p.alive = !p.spectator;
        Log($"[호스트] {p.name} {(p.spectator ? "관전으로" : "참가로")}");
        return true;
    }

    // 이름 바꾸기: 판 사이에만. 제어 문자 빼고 공백 하나로, NAME_MAX_LEN 글자까지 (코드 포인트 단위)
    public bool SetNick(int id, object? raw)
    {
        var p = GetPlayer(id);
        if (p == null || InRound()) return false;
        string nick = JsText.Clean(JsText.String(raw), C.NAME_MAX_LEN); // TEXT_RAW_MAX 로 먼저 자르고 제어 문자·공백 정리 (rooms 이름 정리와 같음)
        if (nick == p.nick) return true;
        p.nick = nick;
        Log($"{p.name} 이름: {(nick.Length > 0 ? nick : "(없음)")}");
        return true;
    }

    // 판 진행 중 (카운트다운 포함)
    public bool InRound() => phase == "playing" || phase == "countdown";
}
