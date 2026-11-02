using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Server;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// 2026-10-30 코드 감사 서버 결함 S1·S3~S10 (재혁 W1): test/w1-audit.test.js 와 같은 내용
public class AuditTests
{
    static readonly double TICK = 1000 / C.TICK_RATE;

    [Fact]
    public void S1_갈고리_R_로_뽑는_중_나가면_뽑던_칸이_제자리로()
    {
        var (g, _, p) = Setup("hook", "ninja", "tank");
        var a = p(1);
        (p(2).x, p(2).y, p(2).z) = (1, 9, 0);
        Place(a, 3.5, 4.5);
        g.grid[g.Idx(5, 4, 0)] = Pieces.CELL.THROWN;
        g.GridChanged();
        a.pitch = -Math.Atan2(C.EYE_HEIGHT - 0.5, 2);
        a.ult = C.ULT_MAX;
        g.HandleAction(1, new ActionMsg { name = "ult" });
        Assert.NotNull(a.grab);
        Assert.Equal(0, g.grid[g.Idx(5, 4, 0)]);
        g.RemovePlayer(1);
        Assert.Equal(Pieces.CELL.THROWN, g.grid[g.Idx(5, 4, 0)]);
    }

    // 조종 블록 하나 잡은 게임 (조종권 아이템으로 p1 이 조종)
    static Game Controlling()
    {
        var g = new Game(_ => { });
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.StartRound();
        g.players[1].hasControl = true;
        g.nextSpawnAt = g.time;
        g.Tick(TICK);
        Assert.True(g.IsControlling(g.players[1]));
        return g;
    }

    static void Move(Game g, double dx, double dy) => g.HandleAction(1, new ActionMsg { name = "pieceMove", dx = dx, dy = dy });

    [Fact]
    public void S3_pieceMove는_한_칸씩_한_틱에_PIECE_MOVE_PER_TICK_번까지()
    {
        Assert.Equal(2, C.PIECE_MOVE_PER_TICK);
        var g = Controlling();
        var pc = g.ControlledPiece(g.players[1])!;
        (pc.px, pc.py) = (3, 3);
        Move(g, 99, 0);
        Assert.Equal(4, pc.px);
        Move(g, -50, 1e9);
        Assert.Equal((3, 4), (pc.px, pc.py));
        Move(g, 1, 0);
        Assert.Equal(3, pc.px); // 한 틱에 세 번째는 버림
        g.Tick(TICK);
        var pc2 = g.ControlledPiece(g.players[1])!;
        var (x0, y0) = (pc2.px, pc2.py);
        Move(g, double.NaN, double.NaN);
        Move(g, double.PositiveInfinity, double.NaN);
        Assert.Equal((x0, y0), (pc2.px, pc2.py));
        g.Tick(TICK);
        Move(g, 1, 0);
        Assert.Equal(x0 + 1, g.ControlledPiece(g.players[1])!.px);
    }

    [Fact]
    public void S7_호스트가_나가면_방장은_연결된_사람에게_먼저()
    {
        var g = new Game(_ => { });
        foreach (var id in new[] { 1, 2, 3 }) g.AddPlayer(id);
        g.SetAway(2, true);
        Assert.Equal(1, g.hostId);
        g.RemovePlayer(1);
        Assert.Equal(3, g.hostId); // 끊긴 2 가 아니라 연결된 3
        g.RemovePlayer(3);
        Assert.Equal(2, g.hostId); // 연결된 사람이 없으면 끊긴 사람에게라도
        g.RemovePlayer(2);
        Assert.Null(g.hostId);
    }

    [Fact]
    public void S9_연습에서_끊기면_대리_봇_없이_입력만_0_생존_판은_봇_대리()
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.AddPlayer(1);
        g.StartPractice();
        g.AddDummy(1);
        g.HandleInput(1, new InputMsg { fwd = 1, strafe = 1, jump = true });
        Assert.True(g.SetAway(1, true));
        Assert.Empty(g.proxies);
        var p = g.players[1];
        Assert.Equal((0.0, 0.0, false), (p.input.fwd, p.input.strafe, p.input.jump));
        Assert.Contains(lines, l => l.Contains("[끊김]") && !l.Contains("봇 대리"));
        var (x, y) = (p.x, p.y);
        Run(g, 3000);
        Assert.Equal((x, y), (p.x, p.y));
        var g2 = new Game(lines.Add);
        g2.AddPlayer(1);
        g2.AddPlayer(2);
        g2.StartRound();
        g2.SetAway(1, true);
        Assert.Single(g2.proxies);
        Assert.Contains(lines, l => l.Contains("(봇 대리)"));
    }

    [Fact]
    public void S10_ColumnTop은_판_밖_칸이면_0()
    {
        var g = new Game(_ => { });
        g.AddPlayer(1);
        g.AddPlayer(2);
        g.StartRound();
        g.grid[g.Idx(0, 1, 3)] = 1;
        g.grid[g.Idx(g.W - 1, 0, 2)] = 1; // x=-1,y=1 이 새던 번호
        Assert.True(g.ColumnTop(0, 1) >= 4);
        foreach (var (x, y) in new[] { (-1, 1), (g.W, 0), (0, g.D), (0, -1), (g.W + 5, g.D + 5) }) Assert.Equal(0, g.ColumnTop(x, y));
        Assert.True(g.ColumnTop(g.W - 1, 0) >= 3);
    }

    static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }

    // ---------- 방 (Rooms.cs) ----------
    sealed class Sock : ISocket
    {
        public readonly List<string> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(text);
        public JsonElement? Last(string type)
        {
            for (int i = msgs.Count - 1; i >= 0; i--)
            {
                var e = JsonDocument.Parse(msgs[i]).RootElement;
                if (e.GetProperty("type").GetString() == type) return e;
            }
            return null;
        }
    }

    sealed class ListLog(string code, Dictionary<string, List<string>> logs) : IRoomLog
    {
        public void Log(string msg) { if (!logs.TryGetValue(code, out var l)) logs[code] = l = new(); l.Add(msg); }
        public void Close() { }
    }

    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    static (Conn conn, Sock ws) Open(Rooms rooms)
    {
        var ws = new Sock();
        return (rooms.Connect(ws), ws);
    }

    static string Code(Sock ws) => ws.Last("welcome")!.Value.GetProperty("room").GetProperty("code").GetString()!;

    [Fact]
    public void S4_한_판도_안_한_방은_연결_0명이면_바로_닫힘()
    {
        var logs = new Dictionary<string, List<string>>();
        var rooms = new Rooms(openLog: c => new ListLog(c, logs));
        var old = new List<string>();
        for (int i = 0; i < (int)C.ROOM_MAX; i++)
        {
            var (c, ws) = Open(rooms);
            rooms.Message(c, J("{\"type\":\"create\"}"));
            old.Add(Code(ws));
            rooms.Disconnect(c); // 만들고 바로 끊기
        }
        Assert.All(old, code => Assert.Null(rooms.Get(code)));
        var (a, wa) = Open(rooms);
        rooms.Message(a, J("{\"type\":\"create\"}"));
        var code = Code(wa);
        var (b, _) = Open(rooms);
        rooms.Message(b, J($"{{\"type\":\"join\",\"code\":\"{code}\"}}"));
        rooms.Disconnect(a);
        Assert.NotNull(rooms.Get(code)); // 연결이 남아 있으면 유지
        rooms.Disconnect(b);
        Assert.Null(rooms.Get(code));
        Assert.Contains("닫음", logs[code][^1]);
        // 한 판 한 방은 자리 유지
        var (c2, w2) = Open(rooms);
        rooms.Message(c2, J("{\"type\":\"create\"}"));
        var code2 = Code(w2);
        rooms.Get(code2)!.game.totals["rounds"] = 1;
        rooms.Disconnect(c2);
        Assert.NotNull(rooms.Get(code2));
        // 연습 방은 규칙 밖
        var (d, wd) = Open(rooms);
        rooms.Message(d, J("{\"type\":\"practice\"}"));
        var code3 = Code(wd);
        rooms.Disconnect(d);
        Assert.NotNull(rooms.Get(code3));
    }

    [Fact]
    public void S5_방_코드는_암호용_난수_rng_를_넣으면_그대로_따름()
    {
        var rooms = new Rooms();
        var codes = new HashSet<string>();
        for (int i = 0; i < 20; i++)
        {
            var (c, ws) = Open(rooms);
            rooms.Message(c, J("{\"type\":\"create\"}"));
            codes.Add(Code(ws));
            rooms.Message(c, J("{\"type\":\"leave\"}"));
        }
        Assert.True(codes.Count > 10, $"코드가 골고루 나옴 ({codes.Count}종)");
        foreach (var code in codes)
        {
            Assert.Equal((int)C.ROOM_CODE_LEN, code.Length);
            Assert.All(code, ch => Assert.Contains(ch, C.ROOM_CODE_CHARS));
        }
        var fixedRooms = new Rooms(rng: () => 0);
        var (f, wf) = Open(fixedRooms);
        fixedRooms.Message(f, J("{\"type\":\"create\"}"));
        Assert.Equal(new string(C.ROOM_CODE_CHARS[0], (int)C.ROOM_CODE_LEN), Code(wf));
    }

    [Fact]
    public void S6_join_rejoin_에러_문구에는_코드를_ROOM_CODE_LEN_글자까지만()
    {
        var rooms = new Rooms();
        var (a, wa) = Open(rooms);
        var huge = new string('x', 5000);
        rooms.Message(a, J($"{{\"type\":\"join\",\"code\":\"{huge}\"}}"));
        var reason = wa.Last("joinError")!.Value.GetProperty("reason").GetString()!;
        Assert.StartsWith("XXXX: ", reason);
        Assert.True(reason.Length < 100);
        rooms.Message(a, J($"{{\"type\":\"rejoin\",\"code\":\"{new string('y', 5000)}\",\"token\":\"t\"}}"));
        Assert.Equal("YYYY", wa.Last("rejoinError")!.Value.GetProperty("code").GetString());
        rooms.Message(a, J("{\"type\":\"join\",\"code\":\"   \"}"));
        Assert.StartsWith("빈 코드", wa.Last("joinError")!.Value.GetProperty("reason").GetString());
        var (h, wh) = Open(rooms);
        rooms.Message(h, J("{\"type\":\"create\"}"));
        rooms.Message(a, J($"{{\"type\":\"join\",\"code\":\" {Code(wh).ToLowerInvariant()} \"}}"));
        Assert.NotNull(wa.Last("welcome"));
    }

    [Fact]
    public void S8_튜토리얼_방에는_손님이_못_들어감()
    {
        var rooms = new Rooms();
        var (a, wa) = Open(rooms);
        rooms.Message(a, J("{\"type\":\"tutorial\",\"char\":\"tank\"}"));
        var code = Code(wa);
        var (b, wb) = Open(rooms);
        rooms.Message(b, J($"{{\"type\":\"join\",\"code\":\"{code}\"}}"));
        Assert.NotNull(wb.Last("joinError"));
        Assert.Null(wb.Last("welcome"));
        Assert.Single(rooms.Get(code)!.game.players);
        var (p, wp) = Open(rooms);
        rooms.Message(p, J("{\"type\":\"practice\"}"));
        var (q, wq) = Open(rooms);
        rooms.Message(q, J($"{{\"type\":\"join\",\"code\":\"{Code(wp)}\"}}"));
        Assert.NotNull(wq.Last("welcome")); // 연습 방은 같이
    }
}
