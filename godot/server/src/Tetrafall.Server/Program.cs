using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using Tetrafall.Core;
using Tetrafall.Server;

// Tetrafall C# 서버 (server/index.js 자리): 정적 파일 (기존 JS 화면 client/·shared/·three.js) + WebSocket + 고정 틱 게임 루프.
// 실행: dotnet run --project godot/server/src/Tetrafall.Server   (포트: 환경 변수 PORT, 없으면 C.PORT = 3000)
//   --online (또는 TF_ONLINE=1): Cloudflare 터널도 켜서 친구용 https 주소 (Tunnel.cs, node 필요 없음)
// 배포 폴더 (tools/package.mjs zip): 서버 exe 옆 web/ 를 /play/ 로, / 는 /play/ 로 넘겨줌 (JS 화면 없음)
// 멈춘·밀린 접속 끊기: Ping 에 Pong 이 안 오거나 (C.NET_KEEPALIVE_MS + C.NET_KEEPALIVE_TIMEOUT_MS, 약 20~25초) 보내기 줄이 C.NET_SEND_QUEUE_MAX 를 넘으면
//   그 접속만 끊고 콘솔에 "접속 N 끊음: …" 한 줄 (서버를 끄는 중에 끊긴 접속은 안 찍음) → 예전 끊김 흐름 (자리 유지 + 봇 대리 + 토큰 복귀). 테스트용 환경 변수 TF_KEEPALIVE_MS·TF_KEEPALIVE_TIMEOUT_MS (양의 정수 ms)
// 스레드: WebSocket 받기·보내기는 비동기, 게임(Rooms·Game)은 루프 스레드 하나에서만 (받은 메시지는 inbox 로 넘김) → JS 처럼 잠금 없음

if (args.Length > 0 && args[0] == "load") Environment.Exit(LoadBench.Run(args)); // 서버 부하 재기 (tools/load.mjs 와 나란히)
var root = FindRepoRoot();
bool jsClient = StaticFiles.HasJsClient(root);
bool online = args.Contains("--online") || Environment.GetEnvironmentVariable("TF_ONLINE") == "1";
var envPort = Environment.GetEnvironmentVariable("PORT");
int port = int.TryParse(envPort, out var ep) && ep >= 0 ? ep : (int)C.PORT;
var runDir = Path.Combine(Environment.GetEnvironmentVariable("TF_LOG_DIR") is { Length: > 0 } ld ? ld : Path.Combine(root, "logs"), FileRoomLog.FileStamp(DateTime.Now)); // TF_LOG_DIR: 테스트
static string Stamp() => FileRoomLog.Stamp(DateTime.Now);

var inbox = new ConcurrentQueue<Action>();
var rooms = new Rooms(
    openLog: code => new FileRoomLog(runDir, code),
    serverLog: m => Console.WriteLine($"[{Stamp()}] {m}"),
    countdownMs: C.ROUND_COUNTDOWN_MS,
    tune: ServerBalance.FromEnv(Environment.GetEnvironmentVariable("TF_BALANCE"), Console.WriteLine));

var builder = WebApplication.CreateSlimBuilder(args);
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
builder.Logging.SetMinimumLevel(LogLevel.Warning);
var app = builder.Build();
var keepAlive = WsSocket.KeepAlive();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = keepAlive.interval, KeepAliveTimeout = keepAlive.timeout });

app.Run(async ctx =>
{
    if (ctx.WebSockets.IsWebSocketRequest)
    {
        // 스냅샷 압축 (permessage-deflate, 문맥 안 들고 있음 — index.js 와 같음). 작은 메시지는 안 누름 (WsSocket)
        // ?pack=gzip (고도 PC 클라): 고도 WebSocketPeer 는 permessage-deflate 를 못 써서 큰 메시지를 gzip 바이너리로 (WsSocket). 브라우저는 쿼리 없이 예전 그대로
        bool packed = ctx.Request.Query["pack"] == "gzip";
        using var ws = await ctx.WebSockets.AcceptWebSocketAsync(new WebSocketAcceptContext { DangerousEnableCompression = true, DisableServerContextTakeover = true });
        await Serve(ws, packed);
        return;
    }
    // 잘못된 % 인코딩 주소는 400 (JS decodeURIComponent 처럼 엄격하게, Kestrel 이 풀기 전 주소로)
    var raw = ctx.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpRequestFeature>()?.RawTarget ?? ctx.Request.Path.Value ?? "/";
    var path = StaticFiles.StrictDecode(raw.Split('?', 2)[0]);
    if (path == null) { ctx.Response.StatusCode = 400; await ctx.Response.WriteAsync("bad request"); return; }
    if (StaticFiles.Redirect(path, raw, jsClient) is string to) { ctx.Response.StatusCode = path == "/play" ? 301 : 302; ctx.Response.Headers.Location = to; return; } // / → /play/ (배포 폴더) 는 302: 브라우저가 기억하지 않게
    var file = StaticFiles.Resolve(root, path);
    if (file == null) { ctx.Response.StatusCode = 403; await ctx.Response.WriteAsync("forbidden"); return; }
    if (!File.Exists(file)) { ctx.Response.StatusCode = 404; await ctx.Response.WriteAsync("not found"); return; }
    ctx.Response.ContentType = StaticFiles.Mime(file); // 형식은 날것 파일 이름으로 (.wasm.br 이어도 application/wasm)
    ctx.Response.Headers.CacheControl = "no-cache";
    var (send, encoding) = StaticFiles.Precompressed(file, ctx.Request.Headers.AcceptEncoding);
    if (encoding != null || File.Exists(file + ".br") || File.Exists(file + ".gz")) ctx.Response.Headers.Vary = "Accept-Encoding";
    if (encoding != null) ctx.Response.Headers.ContentEncoding = encoding;
    await ctx.Response.SendFileAsync(send);
});

async Task Serve(WebSocket ws, bool packed)
{
    var sock = new WsSocket(ws, packed);
    var ready = new TaskCompletionSource<Conn>();
    inbox.Enqueue(() => ready.SetResult(rooms.Connect(sock)));
    var conn = await ready.Task;
    var sendLoop = sock.RunSendLoop();
    var buf = new byte[8192];
    var msg = new MemoryStream();
    string? dropped = null; // 서버가 먼저 끊은 이유 (있을 때만 콘솔 한 줄)
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
    catch (WebSocketException) { } // 보통 닫힘 (상대가 끊음): 조용히
    catch (OperationCanceledException) { dropped = WsSocket.CanceledReason(app.Lifetime.ApplicationStopping.IsCancellationRequested); } // keepalive 시간 초과로 Abort 된 소켓 (ConnectionAbortedException 도 이 계열). 서버를 끄는 중이면 안 찍음
    catch (IOException) { }
    finally
    {
        sock.Closed();
        dropped = sock.DropReason ?? dropped; // 보내기 줄 상한으로 끊은 것이면 그 이유
        if (dropped != null) Console.WriteLine($"[{Stamp()}] 접속 {conn.id} 끊음: {dropped}");
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
Console.WriteLine($"Tetrafall C# 서버 실행 중 (포트 {port}, 틱 {C.TICK_RATE}Hz, 방 최대 {C.ROOM_MAX}개)");
Console.WriteLine($"이 PC에서:        http://localhost:{port}");
foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
{
    if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
    foreach (var a in ni.GetIPProperties().UnicastAddresses)
        if (a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !System.Net.IPAddress.IsLoopback(a.Address)) Console.WriteLine($"다른 PC에서 ({ni.Name}): http://{a.Address}:{port}");
}
Console.WriteLine($"화면 파일: {root}{(jsClient ? "" : " (고도 웹 빌드만: / → /play/)")}");
if (!Directory.Exists(StaticFiles.WebDir(root))) Console.WriteLine($"고도 웹 빌드가 없음 ({StaticFiles.WebDir(root)}) — /play/ 는 404, PC 클라는 그대로 붙음");
Console.WriteLine($"로그: {Path.GetRelativePath(root, runDir)}/ 에 방마다 파일{(jsClient ? " (요약: npm run stats)" : "")}");
if (jsClient && !Directory.Exists(Path.Combine(root, "node_modules", "cannon-es"))) Console.WriteLine("⚠ cannon-es 가 없음 → 몸 래그돌이 꺼짐. 레포 폴더에서 npm install 을 한 번 해 주세요 (Windows PowerShell 은 npm.cmd install)"); // index.js 와 같은 경고
if (online) StartTunnel();
app.WaitForShutdown();

// --online: cloudflared 를 서버가 직접 켜고 지킴 (tools/online.js TunnelKeeper 와 같은 흐름). 서버가 꺼지면 cloudflared 도 끔
void StartTunnel()
{
    var exe = CloudflaredProc.Find();
    var page = jsClient ? "/" : "/play/";
    TunnelKeeper? keeper = null;
    keeper = new TunnelKeeper
    {
        SpawnTunnel = () =>
        {
            var c = CloudflaredProc.Start(exe, port);
            if (c == null) Console.WriteLine($"\n{TunnelProbe.INSTALL}");
            return c;
        },
        Probe = url => TunnelProbe.Check(url, page),
        OnStatus = (kind, text, output) =>
        {
            Console.WriteLine($"[터널] {text}");
            if (kind == "give-up" && output != null) Console.WriteLine(output.Length > 800 ? output[^800..] : output);
        },
        OnReady = url =>
        {
            inbox.Enqueue(() => rooms.SetPublicUrl(url));
            Console.WriteLine(TunnelProbe.Banner(url, TunnelProbe.Copy(url)));
        },
    };
    app.Lifetime.ApplicationStopping.Register(() => keeper.Stop());
    AppDomain.CurrentDomain.ProcessExit += (_, _) => keeper.Stop();
    _ = Task.Run(keeper.Run);
}

static string FindRepoRoot()
{
    var env = Environment.GetEnvironmentVariable("TF_ROOT");
    if (!string.IsNullOrEmpty(env)) return Path.GetFullPath(env);
    var exeDir = Path.TrimEndingDirectorySeparator(Path.GetFullPath(AppContext.BaseDirectory));
    if (File.Exists(Path.Combine(exeDir, "web", "index.html"))) return exeDir; // 배포 폴더 먼저
    foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
    {
        for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
            if (File.Exists(Path.Combine(d.FullName, "client", "index.html")) && File.Exists(Path.Combine(d.FullName, "shared", "config.js"))) return d.FullName;
    }
    // 배포 폴더: 서버 exe 옆 (web/ 고도 웹 빌드). 없어도 웹소켓 서버는 뜸 (PC 클라용)
    return exeDir;
}
