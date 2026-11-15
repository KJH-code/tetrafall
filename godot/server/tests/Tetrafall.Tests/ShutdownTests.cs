using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 서버 끄기 (고도 전용, JS 에 없음): SIGTERM·Ctrl+C → Rooms.Shutdown (방 로그 '[서버 종료]' + 방 안 접속에 left, 그 뒤 들어가기는 joinError)
// + 접속마다 WsSocket.Bye (줄을 다 보낸 뒤 닫기 1001) + 종료 대기 C.NET_SHUTDOWN_MS (Kestrel 기본 30초 대신). Program.cs 머리 주석
// 시간을 재는 테스트라 NetGuardCollection (다른 테스트와 같이 안 돎 — NetGuardTests 설명)
[Collection(nameof(NetGuardCollection))]
public class ShutdownTests
{
    sealed class Sock : ISocket
    {
        public readonly List<JsonElement> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(JsonDocument.Parse(text).RootElement);
        public List<JsonElement> Of(string type) => msgs.Where(m => m.GetProperty("type").GetString() == type).ToList();
    }

    sealed class ListLog : IRoomLog
    {
        public readonly List<string> lines = new();
        public int closes;
        public void Log(string msg) => lines.Add(msg);
        public void Close() => closes++;
    }

    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    [Fact]
    public void Config_values()
    {
        Assert.Equal(3000, C.NET_SHUTDOWN_MS);
        Assert.Equal(1000, C.NET_SHUTDOWN_WAIT_MS);
        Assert.Equal(500, C.NET_SHUTDOWN_CLOSE_GAP_MS);
        Assert.True(C.NET_SHUTDOWN_WAIT_MS < C.NET_SHUTDOWN_MS, "루프 기다림은 종료 대기 안에");
        Assert.True(C.NET_SHUTDOWN_WAIT_MS + C.NET_SHUTDOWN_CLOSE_GAP_MS < C.NET_SHUTDOWN_MS, "루프 기다림 + 닫기 틈도 종료 대기 안에 (읽는 클라는 Abort 전에 닫힘)");
    }

    // 가짜 소켓: 방 2개 (사람 2 / 사람 1 + 봇) + 방 밖 접속 1개
    [Fact]
    public void Shutdown_closes_rooms_sends_left_to_room_conns_only()
    {
        var logs = new Dictionary<string, ListLog>();
        var rooms = new Rooms(openLog: code => logs[code] = new ListLog(), rng: new Mulberry32(3).AsFunc());
        Conn Join(Sock ws) => rooms.Connect(ws);
        Sock a = new(), a2 = new(), b = new(), menu = new();
        var ca = Join(a);
        rooms.Message(ca, J("{\"type\":\"create\",\"nick\":\"가\"}"));
        var roomA = ca.room!;
        var ca2 = Join(a2);
        rooms.Message(ca2, J($"{{\"type\":\"join\",\"code\":\"{roomA.code}\"}}"));
        var cb = Join(b);
        rooms.Message(cb, J("{\"type\":\"create\",\"nick\":\"나\"}"));
        var roomB = cb.room!;
        rooms.Message(cb, J("{\"type\":\"addBot\"}"));
        rooms.Message(cb, J("{\"type\":\"start\"}")); // 판 중인 방
        for (int t = 0; t < 30; t++) rooms.Tick(1000 / C.TICK_RATE);
        var cm = Join(menu);
        Assert.Equal(2, rooms.Count);
        Assert.Same(roomA, ca2.room);
        Assert.Null(cm.room);
        foreach (var s in new[] { a, a2, b, menu }) s.msgs.Clear();

        Assert.Equal(2, rooms.Shutdown());
        Assert.True(rooms.Closing);
        Assert.Equal(0, rooms.Count);
        // 방 안 접속만 left 하나 (까닭 상수), 방 밖 접속은 아무것도 안 받음
        foreach (var s in new[] { a, a2, b })
        {
            var left = Assert.Single(s.Of("left"));
            Assert.Equal(Rooms.SHUTDOWN_REASON, left.GetProperty("reason").GetString());
            Assert.Equal("서버를 껐습니다 — 호스트가 다시 켜면 새로 들어오세요", Rooms.SHUTDOWN_REASON);
        }
        Assert.Empty(menu.msgs);
        Assert.All(new[] { ca, ca2, cb, cm }, c => Assert.Null(c.room));
        foreach (var r in new[] { roomA, roomB })
        {
            Assert.Equal(0, r.conns.Count);
            Assert.Equal(0, r.seats.Count);
        }
        // 방 로그: 마지막 줄 '[서버 종료] …' + 로그 Close 는 방마다 한 번
        Assert.Equal($"[서버 종료] 방 {roomA.code} 닫음 (사람 2명)", logs[roomA.code].lines[^1]);
        Assert.Equal($"[서버 종료] 방 {roomB.code} 닫음 (사람 1명)", logs[roomB.code].lines[^1]);
        Assert.All(logs.Values, l => Assert.StartsWith("[서버 종료]", l.lines[^1]));
        Assert.All(logs.Values, l => Assert.Equal(1, l.closes));
        Assert.Equal(2, logs.Count);

        // 그 뒤 들어가기 (만들기·연습·튜토리얼·코드·자리 토큰) 는 joinError '서버를 끄는 중입니다', 방은 안 생김
        foreach (var s in new[] { a, a2, b }) s.msgs.Clear();
        string[] tries =
        {
            "{\"type\":\"create\",\"nick\":\"또\"}",
            "{\"type\":\"practice\",\"nick\":\"또\"}",
            "{\"type\":\"tutorial\",\"nick\":\"또\"}",
            $"{{\"type\":\"join\",\"code\":\"{roomA.code}\"}}",
            $"{{\"type\":\"rejoin\",\"code\":\"{roomA.code}\",\"token\":\"x\"}}",
        };
        foreach (var m in tries)
        {
            menu.msgs.Clear();
            rooms.Message(cm, J(m));
            var err = Assert.Single(menu.msgs);
            Assert.Equal("joinError", err.GetProperty("type").GetString());
            Assert.Equal(Rooms.SHUTDOWN_JOIN, err.GetProperty("reason").GetString());
            Assert.Equal("서버를 끄는 중입니다", Rooms.SHUTDOWN_JOIN);
        }
        Assert.Equal(0, rooms.Count);
        Assert.Equal(2, logs.Count);
        // 핑은 그대로 답함 (방 밖 메시지 중 들어가기만 막음)
        menu.msgs.Clear();
        rooms.Message(cm, J("{\"type\":\"ping\",\"t\":5}"));
        Assert.Single(menu.Of("pong"));

        // 두 번째 Shutdown 은 아무 일 없음
        foreach (var s in new[] { a, a2, b, menu }) s.msgs.Clear();
        var before = logs.ToDictionary(kv => kv.Key, kv => kv.Value.lines.Count);
        Assert.Equal(0, rooms.Shutdown());
        Assert.All(new[] { a, a2, b, menu }, s => Assert.Empty(s.msgs));
        Assert.All(logs, kv => Assert.Equal(before[kv.Key], kv.Value.lines.Count));
        Assert.All(logs.Values, l => Assert.Equal(1, l.closes));
        // 틱·방송도 그대로 돎 (방이 없음)
        rooms.Tick(1000 / C.TICK_RATE);
        rooms.Broadcast();
    }

    // 가짜 WebSocket: 보낸 글자와 닫기 (상태·설명) 를 시각과 함께 적어 둠
    sealed class RecWs : WebSocket
    {
        public readonly ConcurrentQueue<(string what, double ms)> log = new();
        readonly Stopwatch sw = Stopwatch.StartNew();
        public WebSocketState state = WebSocketState.Open;

        public override WebSocketCloseStatus? CloseStatus => null;
        public override string? CloseStatusDescription => null;
        public override WebSocketState State => state;
        public override string? SubProtocol => null;
        public override void Abort() => state = WebSocketState.Aborted;

        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType messageType, bool endOfMessage, CancellationToken cancellationToken)
        {
            log.Enqueue((Encoding.UTF8.GetString(buffer), sw.Elapsed.TotalMilliseconds));
            return Task.CompletedTask;
        }

        public override Task CloseOutputAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken)
        {
            log.Enqueue(($"close {(int)closeStatus} {statusDescription}", sw.Elapsed.TotalMilliseconds));
            state = WebSocketState.CloseSent;
            return Task.CompletedTask;
        }

        public override Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken cancellationToken) => throw new NotSupportedException();
        public override Task CloseAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken) => Task.CompletedTask;
        public override void Dispose() { }
    }

    // WsSocket.Bye: 이미 넣은 left 는 보내고, 그 뒤 C.NET_SHUTDOWN_CLOSE_GAP_MS 쉬고 닫기 1001 (고도 클라가 left 를 따로 읽게).
    // Bye 뒤 Send 는 아무 일 없음, Open 이 아니면 닫기를 건너뜀, 보통 닫힘 (Closed) 은 닫기 프레임을 안 보냄
    [Fact]
    public async Task Bye_sends_queued_then_1001_after_gap()
    {
        Assert.Equal(500, C.NET_SHUTDOWN_CLOSE_GAP_MS);
        foreach (bool loopFirst in new[] { true, false }) // 보내기 루프가 Bye 전에 돌고 있음 / Bye 뒤에 시작 (Serve 가 늦게 붙음)
        {
            var ws = new RecWs();
            var sock = new WsSocket(ws);
            Task loop = loopFirst ? sock.RunSendLoop() : Task.CompletedTask;
            sock.Send("{\"type\":\"left\"}");
            sock.Bye();
            Assert.False(sock.Open);
            sock.Send("{\"type\":\"after\"}"); // 줄이 닫힘: 버림
            if (!loopFirst) loop = sock.RunSendLoop();
            await loop.WaitAsync(TimeSpan.FromSeconds(5));
            var got = ws.log.ToArray();
            Assert.Equal(new[] { "{\"type\":\"left\"}", "close 1001 server shutdown" }, got.Select(g => g.what));
            Assert.Equal(WebSocketCloseStatus.EndpointUnavailable, (WebSocketCloseStatus)1001);
            double gap = got[1].ms - got[0].ms;
            Assert.True(gap >= C.NET_SHUTDOWN_CLOSE_GAP_MS - 20, $"left 와 닫기 사이 {gap:F0}ms");
            Assert.True(gap < C.NET_SHUTDOWN_MS, $"틈 {gap:F0}ms 는 종료 대기 안");
        }
        // 이미 Open 이 아닌 소켓 (상대가 끊음·Abort): 닫기 프레임 안 보냄
        var gone = new RecWs { state = WebSocketState.Aborted };
        var s2 = new WsSocket(gone, closeGapMs: 0);
        s2.Bye();
        await s2.RunSendLoop().WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Empty(gone.log);
        // 보통 닫힘 (Serve finally 의 Closed): 닫기 프레임 안 보냄 (Bye 만)
        var normal = new RecWs();
        var s3 = new WsSocket(normal, closeGapMs: 0);
        var l3 = s3.RunSendLoop();
        s3.Send("{}");
        s3.Closed();
        await l3.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(new[] { "{}" }, normal.log.Select(g => g.what));
    }

    // 백그라운드에서 계속 읽는 클라 (NetGuardTests.Reader 와 같은 모양) + 닫기 프레임을 받으면 답하고 끝 (브라우저·고도 클라처럼)
    sealed class Reader
    {
        readonly ConcurrentQueue<JsonElement> got = new();
        public readonly Task task;

        public Reader(ClientWebSocket ws)
        {
            task = Task.Run(async () =>
            {
                var buf = new byte[1 << 20];
                try
                {
                    for (; ; )
                    {
                        var ms = new MemoryStream();
                        WebSocketReceiveResult r;
                        do
                        {
                            r = await ws.ReceiveAsync(buf, CancellationToken.None);
                            if (r.MessageType == WebSocketMessageType.Close)
                            {
                                await ws.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
                                return;
                            }
                            ms.Write(buf, 0, r.Count);
                        } while (!r.EndOfMessage);
                        got.Enqueue(JsonDocument.Parse(ms.ToArray()).RootElement);
                    }
                }
                catch (WebSocketException) { }
                catch (OperationCanceledException) { }
                catch (ObjectDisposedException) { }
            });
        }

        // 조건에 맞는 메시지가 올 때까지 (앞의 것은 버림). 못 받으면 null
        public async Task<JsonElement?> Wait(Func<JsonElement, bool> ok, int ms = 10000)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < ms)
            {
                while (got.TryDequeue(out var m)) if (ok(m)) return m;
                if (task.IsCompleted && got.IsEmpty) return null;
                await Task.Delay(5);
            }
            return null;
        }
    }

    static bool Is(JsonElement m, string type) => m.GetProperty("type").GetString() == type;

    static async Task<ClientWebSocket> Open(int port)
    {
        var ws = new ClientWebSocket();
        await ws.ConnectAsync(new Uri($"ws://127.0.0.1:{port}"), CancellationToken.None);
        return ws;
    }

    static Task SendText(ClientWebSocket ws, string text) => ws.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, CancellationToken.None);

    const int SIGTERM = 15;
    // 끄기 신호 → 프로세스가 끝날 때까지 상한: 종료 대기 + 여유 (프로세스 정리·바쁜 기계)
    static readonly int EXIT_WITHIN_MS = (int)C.NET_SHUTDOWN_MS + 1500;

    // 방을 만들고 봇 하나와 판을 시작 (판 중 스냅샷이 올 때까지). 방 코드
    static async Task<string> PlayingRoom(ClientWebSocket host, Reader reader)
    {
        await SendText(host, "{\"type\":\"create\",\"nick\":\"방장\"}");
        var welcome = await reader.Wait(m => Is(m, "welcome"));
        Assert.NotNull(welcome);
        await SendText(host, "{\"type\":\"addBot\"}");
        await SendText(host, "{\"type\":\"start\"}");
        Assert.NotNull(await reader.Wait(m => Is(m, "state") && m.GetProperty("phase").GetString() != "lobby"));
        return welcome!.Value.GetProperty("room").GetProperty("code").GetString()!;
    }

    // 방 로그 파일 줄 (프로세스가 끝난 뒤)
    static string[] RoomLog(ServerProcessTests.Server srv, string code)
    {
        var file = Directory.GetFiles(srv.logDir, $"*_{code}.txt", SearchOption.AllDirectories).Single();
        using var f = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        return new StreamReader(f).ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries);
    }

    // 진짜 서버 프로세스: 판 중 방 (방장 + 봇) + 메뉴 접속 1개에 SIGTERM
    [Fact]
    public async Task Sigterm_sends_left_and_1001_then_exits_fast()
    {
        if (!OperatingSystem.IsLinux()) return; // 신호는 리눅스에서만 (libc kill)
        using var srv = new ServerProcessTests.Server();
        using var host = await Open(srv.port);
        var hostReader = new Reader(host);
        var code = await PlayingRoom(host, hostReader);
        using var menu = await Open(srv.port);
        var menuReader = new Reader(menu);
        Assert.NotNull(await menuReader.Wait(m => Is(m, "rooms")));

        var sw = Stopwatch.StartNew();
        Assert.True(srv.Signal(SIGTERM), "SIGTERM 보냄");
        var took = srv.ExitedWithin(EXIT_WITHIN_MS, sw);
        Assert.True(took != null, $"{EXIT_WITHIN_MS}ms 안에 안 꺼짐");

        // 방장은 left (까닭 상수) → 닫기 1001, 메뉴 접속은 닫기 1001 만
        var left = await hostReader.Wait(m => Is(m, "left"), 3000);
        Assert.NotNull(left);
        Assert.Equal(Rooms.SHUTDOWN_REASON, left!.Value.GetProperty("reason").GetString());
        await Task.WhenAll(hostReader.task, menuReader.task).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(WebSocketCloseStatus.EndpointUnavailable, host.CloseStatus);
        Assert.Equal(WebSocketCloseStatus.EndpointUnavailable, menu.CloseStatus);
        Assert.Equal("server shutdown", host.CloseStatusDescription);

        // 방 로그 마지막 줄 '[서버 종료] …', 콘솔 '서버 끄는 중:' 한 줄 · '끊음:' 없음
        var lines = RoomLog(srv, code);
        Assert.Matches(@"^\[\d{1,2}시 \d{1,2}분 \d{1,2}초\] \[서버 종료\] 방 " + code + @" 닫음 \(사람 1명\)$", lines[^1]);
        Assert.Equal(1, srv.Count("서버 끄는 중:"));
        Assert.True(srv.Saw("서버 끄는 중: 방 1개 닫음 · 접속 2개"), "콘솔 줄 내용");
        Assert.Equal(0, srv.Count("끊음:"));
    }

    // 받기를 안 하는 클라 (닫기에 답하지 않음) 가 있어도 종료 대기 (NET_SHUTDOWN_MS) 뒤 Abort → 상한 안에 꺼짐, '끊음' 줄도 없음
    [Fact]
    public async Task Sigterm_exits_even_with_client_that_never_reads()
    {
        if (!OperatingSystem.IsLinux()) return;
        using var srv = new ServerProcessTests.Server();
        using var host = await Open(srv.port);
        var hostReader = new Reader(host);
        var code = await PlayingRoom(host, hostReader);
        // 조용한 클라: 판 중 방에 들어온 뒤 다시는 읽지 않음 (스냅샷이 쌓이고 닫기 프레임에도 답 안 함)
        using var quiet = await Open(srv.port);
        await SendText(quiet, JsonSerializer.Serialize(new { type = "join", code }));
        Assert.NotNull(await hostReader.Wait(m => Is(m, "state") && m.GetProperty("players").GetArrayLength() == 3));
        await Task.Delay(500);

        var sw = Stopwatch.StartNew();
        Assert.True(srv.Signal(SIGTERM), "SIGTERM 보냄");
        var took = srv.ExitedWithin(EXIT_WITHIN_MS, sw);
        Assert.True(took != null, $"{EXIT_WITHIN_MS}ms 안에 안 꺼짐 (안 읽는 클라)");
        Assert.NotNull(await hostReader.Wait(m => Is(m, "left"), 3000));
        Assert.Equal(1, srv.Count("서버 끄는 중:"));
        Assert.Equal(0, srv.Count("끊음:"));
        Assert.Matches(@"\[서버 종료\] 방 " + code + @" 닫음 \(사람 2명\)$", RoomLog(srv, code)[^1]);
    }
}
