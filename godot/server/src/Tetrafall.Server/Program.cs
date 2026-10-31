using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using Tetrafall.Core;
using Tetrafall.Server;

// Tetrafall C# 서버 (server/index.js 자리): 정적 파일 (기존 JS 화면 client/·shared/·three.js) + WebSocket + 고정 틱 게임 루프.
// 실행: dotnet run --project godot/server/src/Tetrafall.Server   (포트: 환경 변수 PORT, 없으면 C.PORT = 3000)
// 스레드: WebSocket 받기·보내기는 비동기, 게임(Rooms·Game)은 루프 스레드 하나에서만 (받은 메시지는 inbox 로 넘김) → JS 처럼 잠금 없음

var root = FindRepoRoot();
var envPort = Environment.GetEnvironmentVariable("PORT");
int port = int.TryParse(envPort, out var ep) && ep >= 0 ? ep : (int)C.PORT;
var runDir = Path.Combine(Environment.GetEnvironmentVariable("TF_LOG_DIR") is { Length: > 0 } ld ? ld : Path.Combine(root, "logs"), FileRoomLog.FileStamp(DateTime.Now)); // TF_LOG_DIR: 테스트
static string Stamp() => FileRoomLog.Stamp(DateTime.Now);

var inbox = new ConcurrentQueue<Action>();
var rooms = new Rooms(
    openLog: code => new FileRoomLog(runDir, code),
    serverLog: m => Console.WriteLine($"[{Stamp()}] {m}"),
    countdownMs: C.ROUND_COUNTDOWN_MS);

var builder = WebApplication.CreateSlimBuilder(args);
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
builder.Logging.SetMinimumLevel(LogLevel.Warning);
var app = builder.Build();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });

app.Run(async ctx =>
{
    if (ctx.WebSockets.IsWebSocketRequest)
    {
        // 스냅샷 압축 (permessage-deflate, 문맥 안 들고 있음 — index.js 와 같음). 작은 메시지는 안 누름 (WsSocket)
        using var ws = await ctx.WebSockets.AcceptWebSocketAsync(new WebSocketAcceptContext { DangerousEnableCompression = true, DisableServerContextTakeover = true });
        await Serve(ws);
        return;
    }
    // 잘못된 % 인코딩 주소는 400 (JS decodeURIComponent 처럼 엄격하게, Kestrel 이 풀기 전 주소로)
    var raw = ctx.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpRequestFeature>()?.RawTarget ?? ctx.Request.Path.Value ?? "/";
    var path = StaticFiles.StrictDecode(raw.Split('?', 2)[0]);
    if (path == null) { ctx.Response.StatusCode = 400; await ctx.Response.WriteAsync("bad request"); return; }
    var file = StaticFiles.Resolve(root, path);
    if (file == null) { ctx.Response.StatusCode = 403; await ctx.Response.WriteAsync("forbidden"); return; }
    if (!File.Exists(file)) { ctx.Response.StatusCode = 404; await ctx.Response.WriteAsync("not found"); return; }
    ctx.Response.ContentType = StaticFiles.Mime(file);
    ctx.Response.Headers.CacheControl = "no-cache";
    await ctx.Response.SendFileAsync(file);
});

async Task Serve(WebSocket ws)
{
    var sock = new WsSocket(ws);
    var ready = new TaskCompletionSource<Conn>();
    inbox.Enqueue(() => ready.SetResult(rooms.Connect(sock)));
    var conn = await ready.Task;
    var sendLoop = sock.RunSendLoop();
    var buf = new byte[8192];
    var msg = new MemoryStream();
    try
    {
        while (ws.State == WebSocketState.Open)
        {
            var r = await ws.ReceiveAsync(buf, CancellationToken.None);
            if (r.MessageType == WebSocketMessageType.Close) break;
            msg.Write(buf, 0, r.Count);
            if (msg.Length > C.NET_MAX_PAYLOAD_BYTES)
            {
                Console.WriteLine($"[{Stamp()}] 접속 {conn.id} 소켓 오류: 메시지가 너무 큼");
                await ws.CloseAsync(WebSocketCloseStatus.MessageTooBig, "too big", CancellationToken.None);
                break;
            }
            if (!r.EndOfMessage) continue;
            var text = Encoding.UTF8.GetString(msg.GetBuffer(), 0, (int)msg.Length);
            msg.SetLength(0);
            if (r.MessageType == WebSocketMessageType.Text) inbox.Enqueue(() => rooms.MessageText(conn, text));
        }
    }
    catch (WebSocketException) { }
    finally
    {
        sock.Closed();
        inbox.Enqueue(() => rooms.Disconnect(conn));
        await sendLoop;
    }
}

// godot/server/tools/online-cs.mjs (npm run online 의 C# 판) 이 터널 주소를 찾으면 표준 입력 한 줄로 알려 줌: {"type":"publicUrl","url":"https://…"}
// (JS 서버는 node IPC 로 받음 — C# 은 표준 입력) → 대기실 "링크 복사" 가 터널 주소로
if (Environment.GetEnvironmentVariable("TF_STDIN_CONTROL") == "1")
{
    new Thread(() =>
    {
        for (string? line; (line = Console.In.ReadLine()) != null;)
        {
            try
            {
                using var d = System.Text.Json.JsonDocument.Parse(line);
                var m = d.RootElement;
                if (m.ValueKind == System.Text.Json.JsonValueKind.Object && Tetrafall.Core.Js.JsValue.AsString(Tetrafall.Core.Js.JsValue.Field(m, "type")) == "publicUrl")
                {
                    var url = Tetrafall.Core.Js.JsValue.AsString(Tetrafall.Core.Js.JsValue.Field(m, "url"));
                    inbox.Enqueue(() => { if (rooms.SetPublicUrl(url)) Console.WriteLine($"친구용 주소: {url}"); });
                }
            }
            catch (System.Text.Json.JsonException) { }
        }
    }) { IsBackground = true, Name = "stdin-control" }.Start();
}

// 고정 틱 루프 (index.js 와 같음: 누적 시간으로 보정, 한 번에 최대 5틱, 너무 밀리면 버림)
var loop = new Thread(() =>
{
    double TICK_MS = 1000 / C.TICK_RATE;
    var sw = Stopwatch.StartNew();
    double last = sw.Elapsed.TotalMilliseconds, acc = 0, nextList = 0;
    for (; ; )
    {
        try
        {
            while (inbox.TryDequeue(out var a)) a();
            double now = sw.Elapsed.TotalMilliseconds;
            acc += now - last;
            last = now;
            int steps = 0;
            double behind = Math.Max(0, acc - TICK_MS);
            while (acc >= TICK_MS && steps < 5)
            {
                rooms.Tick(TICK_MS);
                acc -= TICK_MS;
                steps++;
            }
            if (acc > TICK_MS * 5) acc = 0;
            rooms.NoteTick(sw.Elapsed.TotalMilliseconds - now, behind);
            if (steps > 0) rooms.Broadcast();
            if (now >= nextList)
            {
                rooms.BroadcastList();
                nextList = now + C.ROOM_LIST_MS;
            }
        }
        catch (Exception err)
        {
            Console.Error.WriteLine($"[{Stamp()}] 틱 루프 오류 (서버는 계속): {err}");
        }
        Thread.Sleep(1); // 1ms 마다 inbox·시계 확인 (틱은 위 누적 시간으로)
    }
}) { IsBackground = true, Name = "game-loop" };
loop.Start();

app.Start(); // 포트 0 이면 운영체제가 빈 포트를 고름 (테스트) → 실제 포트를 시작 줄에
port = new Uri(app.Urls.First()).Port;
Console.WriteLine($"Tetrafall C# 서버 실행 중 (포트 {port}, 틱 {C.TICK_RATE}Hz, 방 최대 {C.ROOM_MAX}개) — 아직 대기실까지 (판은 godot/PLAN.md S1~S5)");
Console.WriteLine($"이 PC에서:        http://localhost:{port}");
foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
{
    if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
    foreach (var a in ni.GetIPProperties().UnicastAddresses)
        if (a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !System.Net.IPAddress.IsLoopback(a.Address)) Console.WriteLine($"다른 PC에서 ({ni.Name}): http://{a.Address}:{port}");
}
Console.WriteLine($"화면 파일: {root}");
Console.WriteLine($"로그: {Path.GetRelativePath(root, runDir)}/ 에 방마다 파일 (요약: npm run stats)");
app.WaitForShutdown();

static string FindRepoRoot()
{
    var env = Environment.GetEnvironmentVariable("TF_ROOT");
    if (!string.IsNullOrEmpty(env)) return Path.GetFullPath(env);
    foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
    {
        for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
            if (File.Exists(Path.Combine(d.FullName, "client", "index.html")) && File.Exists(Path.Combine(d.FullName, "shared", "config.js"))) return d.FullName;
    }
    throw new InvalidOperationException("레포 뿌리(client/index.html)를 못 찾음 — TF_ROOT 환경 변수로 알려 주세요");
}
