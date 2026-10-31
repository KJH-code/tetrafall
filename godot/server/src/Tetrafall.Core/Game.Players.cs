using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-players.js. 대기실 부분 (S6, 2026-10-31): 넣기·빼기·방장·색·봇·끊김(setAway)·봇 난이도·맵·모드·하늘 계단·체력전·캐릭터·팀전·관전·이름.
// 판 안 일 (판 중 나가기 사망·연습 맵·판 중 캐릭터 바꾸기·onField·tooTall·spawnZ·hpKnockouts) 은 그 묶음 (S2·S4) 이 더함
public sealed partial class Game
{
    const int SPAWN_POINT_COUNT = 8; // shared/config.js spawnPoints 8곳
    static double MaxPlayers() => Math.Min(C.MAX_PLAYERS, SPAWN_POINT_COUNT);

    public bool InRound() => phase == "countdown" || phase == "playing";

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
        var sp = SpawnPoint(slot);
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
            alive = !InRound(),
            team = SmallerTeam(),
        };
        if (characters) p.@char = isBot ? C.CHARACTERS[(int)Math.Floor(rng() * C.CHARACTERS.Length)] : C.CHAR_DEFAULT; // 봇은 무작위
        players[id] = p;
        order.Add(id);
        if (hostId == null && !isBot) hostId = id;
        Log($"{p.name} 접속 (slot {slot}){(hostId == id ? " — 호스트" : "")}");
        return p;
    }

    // 시작 위치 (shared/config.js spawnPoints 그대로, 지금 판 크기)
    public (double x, double y, double yaw) SpawnPoint(int slot)
    {
        double inset = C.SPAWN_INSET;
        var pts = new (double, double)[] { (inset, inset), (W - inset, D - inset), (W - inset, inset), (inset, D - inset), (W / 2, inset), (W / 2, D - inset), (inset, D / 2), (W - inset, D / 2) };
        var (x, y) = pts[slot % pts.Length];
        return (x, y, Js.JsMath.Atan2(D / 2 - y, W / 2 - x));
    }

    string SmallerTeam()
    {
        int red = Players().Count(p => p.team == "red"), blue = Players().Count(p => p.team == "blue");
        return red <= blue ? "red" : "blue";
    }

    public int HumanCount() => Players().Count(p => !p.isBot);

    public bool IsHost(int id) => hostId == id;

    public List<Player> Participants() => Players().Where(p => !p.spectator).ToList();

    public bool CanStart()
    {
        var ps = Participants();
        if (mode == "practice") return ps.Count >= 1 && !InRound();
        if (teamMode && !(ps.Any(p => p.team == "red") && ps.Any(p => p.team == "blue"))) return false;
        return ps.Count >= C.MIN_PLAYERS && !InRound();
    }

    // 봇 플레이어 id (넣은 순서, JS this.bots Map 의 키). 봇 id 는 음수. TODO(S5 봇): BotBrain 을 같이 들고 틱마다 생각
    public readonly List<int> bots = new();
    // 접속이 끊긴 사람 id (넣은 순서, JS this.proxies Map 의 키) — 판 중엔 봇이 대신 조종. TODO(S5 봇): BotBrain
    public readonly List<int> proxies = new();

    // 방에서 아무도 안 쓰는 색 중 가장 앞 번호
    int FreeColor()
    {
        var used = new HashSet<int>(Players().Select(p => p.color));
        for (int c = 0; c < C.PLAYER_PALETTE.Length; c++) if (!used.Contains(c)) return c;
        return 0;
    }

    // 색 고르기: 판 사이에만, 팔레트 안 번호 (정수만 — null·문자열·소수는 거절), 다른 사람이 쓰는 색은 안 됨. 되면 true
    public bool SetColor(int id, double? raw)
    {
        players.TryGetValue(id, out var p);
        if (p == null || InRound() || raw is not { } c || c != Math.Floor(c) || double.IsInfinity(c) || c < 0 || c >= C.PLAYER_PALETTE.Length) return false;
        if (c == p.color) return true;
        if (Players().Any(o => o != p && o.color == c)) return false;
        p.color = (int)c;
        Log($"{p.name} 색: {JsNumber.ToJs(c)}");
        return true;
    }

    // 봇 추가 (판 진행 중에는 안 됨). 성공하면 플레이어, 자리가 없으면 null
    public Player? AddBot()
    {
        if (InRound()) return null;
        int id = -++botCounter;
        var p = AddPlayer(id, true);
        if (p != null) bots.Add(id);
        return p;
    }

    // 가장 나중에 넣은 봇 하나 빼기
    public bool RemoveBot()
    {
        if (InRound() || bots.Count == 0) return false;
        RemovePlayer(bots.Min()); // 음수라 가장 작은 게 가장 최근
        return true;
    }

    public void RemoveAllBots()
    {
        foreach (var id in bots.ToList()) RemovePlayer(id);
    }

    // 접속 끊김·복귀 (Rooms 가 부름): 자리는 그대로, 끊긴 동안 봇이 대신 조종. 돌아오면 바로 돌려받고 입력은 멈춤
    public bool SetAway(int id, bool on)
    {
        players.TryGetValue(id, out var p);
        if (p == null || p.isBot || p.away == on) return false;
        p.away = on;
        if (on)
        {
            proxies.Add(id);
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

    public void RemovePlayer(int id)
    {
        if (!players.TryGetValue(id, out var p)) return;
        players.Remove(id);
        order.Remove(id);
        bots.Remove(id);
        proxies.Remove(id);
        Log($"{p.name} {(p.isBot ? "빠짐" : "접속 종료")}");
        if (hostId == id)
        {
            var next = Players().FirstOrDefault(o => !o.isBot);
            hostId = next?.id;
        }
        // TODO(S2 판 흐름): 조종하던 블록 놓기, 판 중이면 접속 끊김 사망 (deaths·checkRoundEnd)
        if (InRound() && p.alive && !p.zombie) throw new NotImplementedException("판 중 나가기는 판 흐름 묶음 (S2) 에서");
    }

    // 봇 난이도 이름 (shared/config.js BOT_LEVELS 의 키 — 표라 생성기가 아직 안 만듦, 테스트가 JS 와 같은지 봄)
    public static readonly string[] BOT_LEVEL_IDS = { "easy", "normal", "hard" };
    static readonly Dictionary<string, string> BOT_LEVEL_KO = new() { ["easy"] = "쉬움", ["normal"] = "보통", ["hard"] = "어려움" };
    static readonly Dictionary<string, string> TEAM_KO = new() { ["red"] = "빨강", ["blue"] = "파랑" };

    // 봇 난이도: 판 사이에만
    public bool SetBotLevel(string level)
    {
        if (InRound() || !BOT_LEVEL_IDS.Contains(level) || level == botLevel) return false;
        botLevel = level;
        Log($"[호스트] 봇 난이도: {BOT_LEVEL_KO[level]}");
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

    // 하늘 계단 켜고 끄기 (판 사이에만)
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

    // 캐릭터 고르기 (판 사이에만, 같은 캐릭터 여럿 됨). TODO(S4 연습): 연습 판 중 바로 바꾸기 (live)
    public bool SetChar(int id, string c)
    {
        players.TryGetValue(id, out var p);
        bool live = mode == "practice" && InRound();
        if (p == null || !characters || p.dummy || (InRound() && !live) || !C.CHARACTERS.Contains(c) || p.@char == c) return false;
        p.@char = c;
        Log($"{p.name} 캐릭터: {C.CHAR_NAMES[c]}");
        if (live && p.alive) throw new NotImplementedException("연습 판 중 캐릭터 바꾸기는 연습 묶음 (S4) 에서");
        return true;
    }

    // ---------- 팀전 ----------
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
        players.TryGetValue(id, out var p);
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

    string TeamLine()
    {
        var ps = Participants().OrderBy(p => p.slot).ToList(); // 안정 정렬 (JS sort 와 같게)
        return string.Join(" / ", new[] { "red", "blue" }.Select(t => $"{TEAM_KO[t]} {string.Join(" ", ps.Where(p => p.team == t).Select(p => p.name))}"));
    }

    // 호스트가 관전 ↔ 참가 전환 (판 사이에만)
    public bool SetSpectator(int id, bool on)
    {
        players.TryGetValue(id, out var p);
        if (p == null || InRound()) return false;
        p.spectator = on;
        p.alive = !p.spectator;
        Log($"[호스트] {p.name} {(p.spectator ? "관전으로" : "참가로")}");
        return true;
    }

    // 이름 바꾸기: 판 사이에만. 제어 문자 빼고 공백 하나로, NAME_MAX_LEN 글자까지 (rooms 의 이름 정리와 같은 방식)
    public bool SetNick(int id, string raw)
    {
        players.TryGetValue(id, out var p);
        if (p == null || InRound()) return false;
        var nick = JsText.Clean(raw, C.NAME_MAX_LEN);
        if (nick == p.nick) return true;
        p.nick = nick;
        Log($"{p.name} 이름: {(nick != "" ? nick : "(없음)")}");
        return true;
    }

    public bool SetMap(string choice)
    {
        if (choice != "random" && !Maps.MAP_IDS.Contains(choice)) return false;
        if (InRound()) return false;
        mapChoice = choice;
        return true;
    }
}
