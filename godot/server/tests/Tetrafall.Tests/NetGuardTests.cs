using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 멈춘·밀린 접속 끊기 (고도 전용, JS 에 없음): 보내기 줄 상한 (WsSocket) + keepalive 시간 제한 (Program.cs UseWebSockets).
// 끊긴 뒤는 예전 끊김 흐름 그대로 (rooms.Disconnect → 자리 유지 + 봇 대리)
public class NetGuardTests
{
    // 가짜 WebSocket: hang 이면 SendAsync 가 Abort 될 때까지 안 끝남 (받는 쪽이 읽기를 멈춘 접속), 아니면 바로 끝남
    sealed class FakeWs(bool hang) : WebSocket
    {
        readonly TaskCompletionSource stuck = new(TaskCreationOptions.RunContinuationsAsynchronously);
        WebSocketState state = WebSocketState.Open;
        public int aborts, sent, binary;

        public override WebSocketCloseStatus? CloseStatus => null;
        public override string? CloseStatusDescription => null;
        public override WebSocketState State => state;
        public override string? SubProtocol => null;

        public override void Abort()
        {
            Interlocked.Increment(ref aborts);
            state = WebSocketState.Aborted;
            stuck.TrySetCanceled();
        }

        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType messageType, bool endOfMessage, CancellationToken cancellationToken)
        {
            if (messageType == WebSocketMessageType.Binary) Interlocked.Increment(ref binary);
            Interlocked.Increment(ref sent);
            return hang ? stuck.Task : Task.CompletedTask;
        }

        public override Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken cancellationToken) => throw new NotSupportedException();
        public override Task CloseAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken) => Task.CompletedTask;
        public override Task CloseOutputAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken) => Task.CompletedTask;
        public override void Dispose() { }
    }

    static async Task Until(Func<bool> ok, int ms, string what)
    {
        var sw = Stopwatch.StartNew();
        while (!ok())
        {
            Assert.True(sw.ElapsedMilliseconds < ms, $"{ms}ms 안에 안 됨: {what}");
            await Task.Delay(5);
        }
    }

    [Fact]
    public async Task Send_queue_over_limit_aborts_socket()
    {
        const int MAX = 5;
        var ws = new FakeWs(hang: true);
        var sock = new WsSocket(ws, queueMax: MAX);
        var loop = sock.RunSendLoop();
        // 상한까지는 그대로 열려 있음 (첫 메시지는 보내는 중에 멈춰 있고 나머지는 줄에)
        for (int i = 0; i < MAX; i++)
        {
            sock.Send($"{{\"n\":{i}}}");
            Assert.True(sock.Open, $"{i + 1}개째");
            Assert.Null(sock.DropReason);
        }
        await Until(() => ws.sent == 1, 5000, "첫 메시지 보내기 시작");
        Assert.Equal(0, ws.aborts);
        Assert.True(sock.Open);
        // 상한을 넘는 순간 끊음
        sock.Send("{\"n\":\"넘침\"}");
        Assert.False(sock.Open);
        Assert.Equal(1, ws.aborts);
        Assert.Equal($"보내기 줄이 밀림 ({MAX + 1}개)", sock.DropReason);
        // 보내기 루프는 Abort 된 SendAsync 의 예외를 삼키고 끝남 (Serve 의 await sendLoop 가 안 걸림)
        await loop.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(1, ws.sent);
        // 끊긴 뒤 Send 는 아무 일도 안 함
        sock.Send("{}");
        Assert.Equal(1, ws.aborts);
        Assert.Equal($"보내기 줄이 밀림 ({MAX + 1}개)", sock.DropReason);

        // 상한을 안 주면 C.NET_SEND_QUEUE_MAX (30Hz × 5초). 보내기 루프를 안 돌려 줄에 그대로 쌓임: 그만큼은 열림, 하나 더면 끊음
        Assert.Equal(150, C.NET_SEND_QUEUE_MAX);
        Assert.Equal(C.TICK_RATE * 5, C.NET_SEND_QUEUE_MAX);
        var ws2 = new FakeWs(hang: true);
        var sock2 = new WsSocket(ws2);
        for (int i = 0; i < C.NET_SEND_QUEUE_MAX; i++) sock2.Send("{}");
        Assert.True(sock2.Open);
        Assert.Equal(0, ws2.aborts);
        sock2.Send("{}");
        Assert.False(sock2.Open);
        Assert.Equal(1, ws2.aborts);
        Assert.Equal($"보내기 줄이 밀림 ({C.NET_SEND_QUEUE_MAX + 1}개)", sock2.DropReason);
    }

    [Fact]
    public async Task Fast_reader_never_aborted()
    {
        // 바로바로 읽는 접속: 틱마다 4개씩 (스냅샷 + 작은 메시지) 1000번 보내도 상한 8 에 안 걸림 = 보낸 만큼 계수가 줄어듦
        const int MAX = 8, BATCH = 4, TOTAL = 1000;
        var big = "{\"type\":\"state\",\"pad\":\"" + new string('x', (int)C.NET_DEFLATE_MIN_BYTES) + "\"}";
        foreach (var packed in new[] { false, true })
        {
            var ws = new FakeWs(hang: false);
            var sock = new WsSocket(ws, packed, queueMax: MAX);
            var loop = sock.RunSendLoop();
            for (int n = 0; n < TOTAL; n += BATCH)
            {
                for (int i = 0; i < BATCH; i++) sock.Send(i == 0 ? big : "{\"type\":\"pong\"}");
                Assert.True(sock.Open, $"{n + BATCH}개째");
                int want = n + BATCH;
                await Until(() => ws.sent == want, 5000, $"{want}개 보냄");
            }
            Assert.True(sock.Open);
            Assert.Equal(0, ws.aborts);
            Assert.Null(sock.DropReason);
            Assert.Equal(TOTAL, ws.sent);
            Assert.Equal(packed ? TOTAL / BATCH : 0, ws.binary); // ?pack=gzip 접속은 큰 메시지만 gzip 바이너리 (그 갈래도 계수를 줄임)
            sock.Closed();
            await loop.WaitAsync(TimeSpan.FromSeconds(5));
        }
    }

    [Fact]
    public void Keepalive_env_override()
    {
        Assert.Equal(10000, C.NET_KEEPALIVE_MS);
        Assert.Equal(10000, C.NET_KEEPALIVE_TIMEOUT_MS);
        var normal = (TimeSpan.FromMilliseconds(C.NET_KEEPALIVE_MS), TimeSpan.FromMilliseconds(C.NET_KEEPALIVE_TIMEOUT_MS));
        static Func<string, string?> Env(string? interval, string? timeout) => k => k == "TF_KEEPALIVE_MS" ? interval : k == "TF_KEEPALIVE_TIMEOUT_MS" ? timeout : throw new ArgumentException(k);
        // 없거나 양의 정수가 아니면 C 값
        Assert.Equal(normal, WsSocket.KeepAlive(Env(null, null)));
        foreach (var bad in new[] { "", "abc", "0", "-300", "1.5", "300ms", " 300", "99999999999" })
            Assert.Equal(normal, WsSocket.KeepAlive(Env(bad, bad)));
        // 양의 정수면 그 값 (ms), 둘은 따로
        Assert.Equal((TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(300)), WsSocket.KeepAlive(Env("300", "300")));
        Assert.Equal((TimeSpan.FromMilliseconds(300), normal.Item2), WsSocket.KeepAlive(Env("300", null)));
        Assert.Equal((normal.Item1, TimeSpan.FromMilliseconds(450)), WsSocket.KeepAlive(Env("abc", "450")));
        // 인자 없이 부르면 진짜 환경 변수 (테스트 프로세스엔 없음 → C 값)
        if (Environment.GetEnvironmentVariable("TF_KEEPALIVE_MS") == null && Environment.GetEnvironmentVariable("TF_KEEPALIVE_TIMEOUT_MS") == null)
            Assert.Equal(normal, WsSocket.KeepAlive());
    }

    // 백그라운드에서 계속 읽는 클라 (읽어야 서버 Ping 에 Pong 이 나감): 받은 메시지를 쌓아 두고 조건에 맞는 것을 기다림
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
                            if (r.MessageType == WebSocketMessageType.Close) return;
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

    [Fact]
    public async Task Silent_client_dropped_seat_goes_to_bot()
    {
        using var srv = new ServerProcessTests.Server(new Dictionary<string, string> { ["TF_KEEPALIVE_MS"] = "300", ["TF_KEEPALIVE_TIMEOUT_MS"] = "300" });
        using var host = await Open(srv.port);
        var reader = new Reader(host);
        await SendText(host, "{\"type\":\"create\",\"nick\":\"방장\"}");
        var welcome = await reader.Wait(m => Is(m, "welcome"));
        Assert.NotNull(welcome);
        var code = welcome!.Value.GetProperty("room").GetProperty("code").GetString()!;

        // 조용한 클라: 들어온 뒤 다시는 읽지 않음 → 서버 Ping 에 Pong 이 안 나감 (ClientWebSocket 은 ReceiveAsync 안에서만 Ping 을 처리)
        using var quiet = await Open(srv.port);
        await SendText(quiet, JsonSerializer.Serialize(new { type = "join", code }));
        Assert.NotNull(await reader.Wait(m => Is(m, "state") && m.GetProperty("players").GetArrayLength() == 2));
        await SendText(host, "{\"type\":\"start\"}");
        var sw = Stopwatch.StartNew();
        Assert.NotNull(await reader.Wait(m => Is(m, "state") && m.GetProperty("phase").GetString() != "lobby"));

        // 5초 안에: 서버 콘솔 한 줄 + 방 로그에 자리 유지 (봇 대리) = 예전 끊김 흐름
        await Until(() => srv.Saw("접속 2 끊음: 응답 없음"), 5000, "서버 콘솔 '끊음: 응답 없음'");
        const string AWAY = "[끊김] P2 자리 유지 60초 (봇 대리)";
        string log = "";
        await Until(() =>
        {
            var file = Directory.Exists(srv.logDir) ? Directory.GetFiles(srv.logDir, $"*_{code}.txt", SearchOption.AllDirectories).FirstOrDefault() : null;
            if (file == null) return false;
            using var f = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            log = new StreamReader(f).ReadToEnd();
            return log.Contains(AWAY);
        }, 5000, $"방 로그 '{AWAY}'");
        Assert.True(sw.ElapsedMilliseconds < 5000, $"시작 뒤 {sw.ElapsedMilliseconds}ms");

        // 계속 읽는 호스트는 그대로: 안 끊기고 ping → pong
        await SendText(host, "{\"type\":\"ping\",\"t\":7}");
        var pong = await reader.Wait(m => Is(m, "pong"));
        Assert.NotNull(pong);
        Assert.Equal(7, pong!.Value.GetProperty("t").GetDouble());
        Assert.Equal(WebSocketState.Open, host.State);
        Assert.False(srv.Saw("접속 1 끊음"), "호스트는 안 끊김");
        Assert.False(srv.Saw("보내기 줄"), "줄 상한이 아니라 keepalive 로 끊김");
        Assert.False(srv.proc.HasExited, "서버 프로세스 살아 있음");
    }
}
