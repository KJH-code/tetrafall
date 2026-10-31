namespace Tetrafall.Core;

// server/game-players.js (뼈대: 넣기·빼기·방장·시작 가능·맵 고르기만)
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

    int FreeColor()
    {
        var used = new HashSet<int>(Players().Select(p => p.color));
        for (int c = 0; c < C.PLAYER_PALETTE.Length; c++) if (!used.Contains(c)) return c;
        return 0;
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

    public void RemovePlayer(int id)
    {
        if (!players.TryGetValue(id, out var p)) return;
        players.Remove(id);
        order.Remove(id);
        Log($"{p.name} {(p.isBot ? "빠짐" : "접속 종료")}");
        if (hostId == id)
        {
            var next = Players().FirstOrDefault(o => !o.isBot);
            hostId = next?.id;
        }
        if (InRound()) throw new NotImplementedException("판 중 나가기는 GameRound 묶음에서");
    }

    public void RemoveAllBots()
    {
        foreach (var p in Players().Where(p => p.isBot).ToList()) RemovePlayer(p.id);
    }

    public bool SetMap(string choice)
    {
        if (choice != "random" && !Maps.MAP_IDS.Contains(choice)) return false;
        if (InRound()) return false;
        mapChoice = choice;
        return true;
    }
}
