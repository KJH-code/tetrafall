using System.Diagnostics;
using System.IO.Compression;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;

namespace Tetrafall.Tests;

// 서버 프로세스 (JS test/safety.test.js '서버 프로세스' 와 같음): 잘못된 % 주소는 400 (서버 안 죽음), NET_MAX_PAYLOAD_BYTES 넘는 메시지는
// 그 연결만 1009 로 끊김, 다른 연결은 그대로. + 표준 입력으로 받은 터널 주소가 방 링크로, 방 로그 파일이 JS 와 같은 줄 모양
// + ?pack=gzip 으로 붙은 연결 (고도 PC 클라) 은 큰 메시지를 gzip 바이너리로, 쿼리 없는 연결은 예전처럼 Text
public class ServerProcessTests
{
    static string RepoRoot()
    {
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d != null; d = d.Parent)
            if (File.Exists(Path.Combine(d.FullName, "client", "index.html")) && File.Exists(Path.Combine(d.FullName, "shared", "config.js"))) return d.FullName;
        throw new InvalidOperationException("레포 뿌리를 못 찾음");
    }

    internal sealed class Server : IDisposable
    {
        public readonly Process proc;
        public readonly int port;
        public readonly string logDir;
        readonly List<string> lines = new();

        // env: 서버 프로세스에 더 줄 환경 변수 (NetGuardTests: TF_KEEPALIVE_MS 등), args: 서버 명령줄 (ShutdownTests: --online)
        public Server(IReadOnlyDictionary<string, string>? env = null, IEnumerable<string>? args = null)
        {
            logDir = Path.Combine(Path.GetTempPath(), "tf-logs-" + Guid.NewGuid().ToString("N"));
            var psi = new ProcessStartInfo("dotnet")
            {
                RedirectStandardOutput = true,
                RedirectStandardInput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            psi.ArgumentList.Add(Path.Combine(AppContext.BaseDirectory, "Tetrafall.Server.dll"));
            foreach (var a in args ?? Array.Empty<string>()) psi.ArgumentList.Add(a);
            psi.Environment["PORT"] = "0";
            psi.Environment["TF_ROOT"] = RepoRoot();
            psi.Environment["TF_LOG_DIR"] = logDir;
            psi.Environment["TF_STDIN_CONTROL"] = "1";
            foreach (var (k, v) in env ?? new Dictionary<string, string>()) psi.Environment[k] = v;
            proc = Process.Start(psi)!;
            var started = new TaskCompletionSource<int>();
            proc.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                lock (lines) lines.Add(e.Data);
                var m = Regex.Match(e.Data, @"실행 중 \(포트 (\d+),");
                if (m.Success) started.TrySetResult(int.Parse(m.Groups[1].Value));
            };
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            if (!started.Task.Wait(TimeSpan.FromSeconds(30))) throw new TimeoutException("서버가 안 켜짐");
            port = started.Task.Result;
        }

        public bool Saw(string part)
        {
            lock (lines) return lines.Any(l => l.Contains(part));
        }

        // part 가 든 콘솔 줄 수 (한 번만 찍혀야 하는 줄 — NetGuardTests '끊음')
        public int Count(string part)
        {
            lock (lines) return lines.Count(l => l.Contains(part));
        }

        [DllImport("libc", SetLastError = true)]
        static extern int kill(int pid, int sig);

        // 서버 프로세스에 신호 (리눅스·맥 libc kill — ShutdownTests: SIGTERM 15). 보냈으면 true
        public bool Signal(int sig) => kill(proc.Id, sig) == 0;

        // 프로세스가 ms 안에 끝나면 since 부터 끝날 때까지 ms (그 뒤 남은 출력 줄까지 다 읽음 — Saw·Count 가 마지막 줄도 봄), 안 끝나면 null
        public double? ExitedWithin(int ms, Stopwatch since)
        {
            if (!proc.WaitForExit(ms)) return null;
            double t = since.Elapsed.TotalMilliseconds;
            proc.WaitForExit();
            return t;
        }

        public void Dispose()
        {
            try { proc.Kill(true); } catch { }
            proc.Dispose();
            try { Directory.Delete(logDir, true); } catch { }
        }
    }

    // HttpClient 는 주소를 고쳐 보내서 (%A → %25A) 날 요청을 소켓으로
    static async Task<int> RawGet(int port, string target) => int.Parse((await RawHead(port, target)).Split(' ')[1]);

    // 응답 머리 (상태 줄 + 헤더) 글자
    static async Task<string> RawHead(int port, string target)
    {
        using var tcp = new TcpClient();
        await tcp.ConnectAsync("127.0.0.1", port);
        var s = tcp.GetStream();
        await s.WriteAsync(Encoding.ASCII.GetBytes($"GET {target} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"));
        var ms = new MemoryStream();
        var buf = new byte[1024];
        int n;
        while ((n = await s.ReadAsync(buf)) > 0)
        {
            ms.Write(buf, 0, n);
            if (Encoding.ASCII.GetString(ms.ToArray()).Contains("\r\n\r\n")) break;
        }
        return Encoding.ASCII.GetString(ms.ToArray()).Split("\r\n\r\n")[0];
    }

    static async Task<ClientWebSocket> Open(int port)
    {
        var ws = new ClientWebSocket();
        await ws.ConnectAsync(new Uri($"ws://127.0.0.1:{port}"), CancellationToken.None);
        return ws;
    }

    static async Task SendText(ClientWebSocket ws, string text) => await ws.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, CancellationToken.None);

    // type 이 맞는 메시지가 올 때까지 (못 받으면 null)
    static async Task<JsonElement?> Wait(ClientWebSocket ws, string type, int ms = 10000)
    {
        using var cts = new CancellationTokenSource(ms);
        var buf = new byte[1 << 20];
        try
        {
            for (; ; )
            {
                var ms_ = new MemoryStream();
                WebSocketReceiveResult r;
                do
                {
                    r = await ws.ReceiveAsync(buf, cts.Token);
                    if (r.MessageType == WebSocketMessageType.Close) return null;
                    ms_.Write(buf, 0, r.Count);
                } while (!r.EndOfMessage);
                var m = JsonDocument.Parse(ms_.ToArray()).RootElement;
                if (m.GetProperty("type").GetString() == type) return m;
            }
        }
        catch (OperationCanceledException) { return null; }
    }

    [Fact]
    public async Task Bad_url_400_big_message_closes_only_that_connection()
    {
        using var srv = new Server();
        Assert.Equal(400, await RawGet(srv.port, "/%E0%A4%A"));
        Assert.Equal(400, await RawGet(srv.port, "/%ZZ"));
        Assert.Equal(200, await RawGet(srv.port, "/"));
        Assert.Equal(404, await RawGet(srv.port, "/nope.js"));
        var head = await RawHead(srv.port, "/play?room=ABCD");
        Assert.StartsWith("HTTP/1.1 301", head);
        Assert.Contains("\r\nLocation: /play/?room=ABCD", head);
        var big = await Open(srv.port);
        var other = await Open(srv.port);
        await SendText(big, JsonSerializer.Serialize(new { type = "setName", name = new string('x', (int)C.NET_MAX_PAYLOAD_BYTES + 10) }));
        Assert.Null(await Wait(big, "never"));
        Assert.Equal(WebSocketCloseStatus.MessageTooBig, big.CloseStatus);
        await SendText(other, "{\"type\":\"ping\",\"t\":1}");
        var pong = await Wait(other, "pong");
        Assert.NotNull(pong);
        Assert.Equal(1, pong!.Value.GetProperty("t").GetDouble());
        Assert.False(srv.proc.HasExited, "서버 프로세스 살아 있음");
    }

    [Fact]
    public async Task Stdin_public_url_becomes_room_link_and_room_log_file_matches_js_format()
    {
        using var srv = new Server();
        srv.proc.StandardInput.WriteLine("not json");
        srv.proc.StandardInput.WriteLine("{\"type\":\"publicUrl\",\"url\":\"https://abc-def.trycloudflare.com/\"}");
        srv.proc.StandardInput.Flush();
        for (int i = 0; i < 100 && !srv.Saw("친구용 주소"); i++) await Task.Delay(50);
        var ws = await Open(srv.port);
        await SendText(ws, "{\"type\":\"create\",\"nick\":\"재혁\"}");
        var welcome = await Wait(ws, "welcome");
        Assert.NotNull(welcome);
        var room = welcome!.Value.GetProperty("room");
        var code = room.GetProperty("code").GetString()!;
        Assert.Equal($"https://abc-def.trycloudflare.com/?room={code}", room.GetProperty("link").GetString());
        Assert.Matches("^[0-9a-f]{32}$", welcome.Value.GetProperty("token").GetString()!);
        await SendText(ws, "{\"type\":\"leave\"}");
        Assert.NotNull(await Wait(ws, "left"));
        // logs/<서버 시각>/<방 시각>_<코드>.txt, 줄마다 "[H시 m분 s초] 내용"
        string? file = null;
        for (int i = 0; i < 100 && file == null; i++)
        {
            file = Directory.Exists(srv.logDir) ? Directory.GetFiles(srv.logDir, $"*_{code}.txt", SearchOption.AllDirectories).FirstOrDefault() : null;
            if (file == null) await Task.Delay(50);
        }
        Assert.NotNull(file);
        Assert.Matches(@"[/\\]\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d[/\\]\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d_[A-Z]{4}\.txt$", file!);
        string[] got = [];
        for (int i = 0; i < 100 && got.Length < 4; i++)
        {
            got = File.ReadAllLines(file!);
            if (got.Length < 4) await Task.Delay(50);
        }
        var bodies = got.Select(l => Regex.Match(l, @"^\[\d{1,2}시 \d{1,2}분 \d{1,2}초\] (.*)$")).ToList();
        Assert.All(bodies, m => Assert.True(m.Success));
        Assert.Equal(new[] { $"방 {code} 만듦: 재혁의 방 (비공개)", "P1 접속 (slot 0) — 호스트", "P1 접속 종료", $"방 {code} 닫음 (사람 0명)" }, bodies.Select(m => m.Groups[1].Value));
    }

    // 메시지 하나를 날것으로 (종류 + 바이트). 닫히거나 시간이 지나면 null
    static async Task<(WebSocketMessageType kind, byte[] bytes)?> Receive(ClientWebSocket ws, byte[] buf, CancellationToken ct)
    {
        var ms = new MemoryStream();
        try
        {
            WebSocketReceiveResult r;
            do
            {
                r = await ws.ReceiveAsync(buf, ct);
                if (r.MessageType == WebSocketMessageType.Close) return null;
                ms.Write(buf, 0, r.Count);
            } while (!r.EndOfMessage);
            return (r.MessageType, ms.ToArray());
        }
        catch (OperationCanceledException) { return null; }
    }

    static byte[] Gunzip(byte[] gz)
    {
        using var src = new GZipStream(new MemoryStream(gz), CompressionMode.Decompress);
        var ms = new MemoryStream();
        src.CopyTo(ms);
        return ms.ToArray();
    }

    // 방 만들고 봇 7명과 시작 → 판이 시작된 뒤 (phase 가 lobby 아님) 스냅샷 n 개를 받음: (종류, 받은 바이트, 푼 바이트). 다른 메시지 종류도 같이 돌려줌
    static async Task<(List<(WebSocketMessageType kind, byte[] wire, byte[] json)> states, List<(WebSocketMessageType kind, byte[] wire, byte[] json)> all)> EightPlayerStates(ClientWebSocket ws, int n)
    {
        await SendText(ws, "{\"type\":\"create\",\"nick\":\"재혁\"}");
        for (int i = 0; i < 7; i++) await SendText(ws, "{\"type\":\"addBot\"}");
        await SendText(ws, "{\"type\":\"start\"}");
        var states = new List<(WebSocketMessageType, byte[], byte[])>();
        var all = new List<(WebSocketMessageType, byte[], byte[])>();
        using var cts = new CancellationTokenSource(20000);
        var buf = new byte[1 << 20];
        while (states.Count < n)
        {
            var got = await Receive(ws, buf, cts.Token);
            if (got == null) break;
            var (kind, wire) = got.Value;
            var json = kind == WebSocketMessageType.Binary ? Gunzip(wire) : wire;
            all.Add((kind, wire, json));
            var m = JsonDocument.Parse(json).RootElement;
            if (m.GetProperty("type").GetString() == "state" && m.GetProperty("phase").GetString() != "lobby" && m.GetProperty("players").GetArrayLength() == 8) states.Add((kind, wire, json));
        }
        return (states, all);
    }

    [Fact]
    public async Task Packed_client_gets_gzip_snapshots()
    {
        using var srv = new Server();
        var packed = new ClientWebSocket();
        await packed.ConnectAsync(new Uri($"ws://127.0.0.1:{srv.port}/?pack=gzip"), CancellationToken.None);
        var (states, all) = await EightPlayerStates(packed, 30);
        Assert.Equal(30, states.Count);
        Assert.All(states, s => Assert.Equal(WebSocketMessageType.Binary, s.kind));
        Assert.All(states, s => Assert.Contains("\"type\":\"state\"", Encoding.UTF8.GetString(s.json)));
        double wire = states.Sum(s => (double)s.wire.Length), raw = states.Sum(s => (double)s.json.Length);
        Assert.True(wire / raw < 0.3, $"누른 {wire} / 푼 {raw} = {wire / raw:F3}");
        // 큰 메시지만 누름: 바이너리는 풀면 NET_DEFLATE_MIN_BYTES 이상, 글자는 그 아래 (welcome·작은 대기실 스냅샷 등)
        Assert.All(all, m => Assert.Equal(m.json.Length >= C.NET_DEFLATE_MIN_BYTES, m.kind == WebSocketMessageType.Binary));

        // 쿼리 없이 붙은 연결 (브라우저·예전 클라) 은 같은 서버에서 전부 Text — 8명 판 큰 스냅샷도
        var plain = await Open(srv.port);
        var (plainStates, plainAll) = await EightPlayerStates(plain, 30);
        Assert.Equal(30, plainStates.Count);
        Assert.All(plainAll, m => Assert.Equal(WebSocketMessageType.Text, m.kind));
        Assert.All(plainStates, s => Assert.True(s.wire.Length >= C.NET_DEFLATE_MIN_BYTES, $"스냅샷 {s.wire.Length}B"));
        Assert.False(srv.proc.HasExited, "서버 프로세스 살아 있음");
    }
}
