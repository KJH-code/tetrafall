using Tetrafall.Core;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// --online 터널 (Tunnel.cs, tools/online.js TunnelKeeper 의 C# 판) — 가짜 cloudflared·가짜 요청·가짜 시계
public class TunnelTests
{
    sealed class FakeProc : ITunnelProc
    {
        public string Output { get; set; } = "";
        public bool Exited { get; set; }
        public bool Killed;
        public void Kill()
        {
            Killed = true;
            Exited = true;
        }
    }

    sealed class Rig
    {
        public double now;
        public readonly List<FakeProc> procs = new();
        public readonly List<string> ready = new(), status = new();
        public Func<int, string> outputOf = n => $"INF |  https://word-{n}-tetra.trycloudflare.com  |";
        public Func<string, int, bool> probe = (_, _) => true; // (주소, 몇 번째 확인)
        int probes;

        public TunnelKeeper Keeper()
        {
            TunnelKeeper k = null!;
            k = new TunnelKeeper
            {
                SpawnTunnel = () =>
                {
                    var p = new FakeProc { Output = outputOf(procs.Count) };
                    procs.Add(p);
                    return p;
                },
                Probe = url => Task.FromResult(probe(url, probes++)),
                OnReady = url =>
                {
                    ready.Add(url);
                    k.Stop(); // 열리면 끝 (지키기 고리는 따로)
                },
                OnStatus = (kind, text, _) => status.Add(kind),
                Sleep = ms =>
                {
                    now += ms;
                    return Task.CompletedTask;
                },
                Now = () => now,
            };
            return k;
        }
    }

    [Fact]
    public void Tunnel_url_picks_hyphenated_trycloudflare_only()
    {
        Assert.Equal("https://a-b-c.trycloudflare.com", TunnelKeeper.TunnelUrl("x https://api.trycloudflare.com err\n|  https://a-b-c.trycloudflare.com  |"));
        Assert.Null(TunnelKeeper.TunnelUrl("failed to request quick Tunnel: https://api.trycloudflare.com/tunnel"));
    }

    [Fact]
    public async Task Ready_after_url_and_probe()
    {
        var r = new Rig();
        Assert.True(await r.Keeper().Run());
        Assert.Equal(new[] { "https://word-0-tetra.trycloudflare.com" }, r.ready);
        Assert.Equal(new[] { "checking" }, r.status);
    }

    [Fact]
    public async Task Restarts_when_address_never_opens_then_succeeds()
    {
        var r = new Rig();
        r.probe = (url, _) => !url.Contains("word-0"); // 첫 주소는 안 열림 (530)
        Assert.True(await r.Keeper().Run());
        Assert.Equal(new[] { "https://word-1-tetra.trycloudflare.com" }, r.ready);
        Assert.True(r.procs[0].Killed);
        Assert.Contains("restart", r.status);
        Assert.True(r.now >= C.TUNNEL_READY_TIMEOUT_MS);
    }

    [Fact]
    public async Task Gives_up_after_max_restarts_and_missing_cloudflared_stops()
    {
        var r = new Rig { outputOf = _ => "ERR failed to request quick Tunnel: https://api.trycloudflare.com" };
        Assert.False(await r.Keeper().Run());
        Assert.Equal((int)C.TUNNEL_MAX_RESTARTS + 1, r.procs.Count);
        Assert.Equal("give-up", r.status[^1]);
        Assert.Empty(r.ready);

        var k = r.Keeper();
        k.SpawnTunnel = () => null; // cloudflared 없음
        Assert.False(await k.Run());
    }

    [Fact]
    public void Release_folder_serves_web_at_play_and_redirects_root()
    {
        var root = Path.Combine(Path.GetTempPath(), "tf-release-" + Guid.NewGuid().ToString("N"));
        var web = Path.Combine(root, "web");
        Directory.CreateDirectory(web);
        try
        {
            Assert.False(StaticFiles.HasJsClient(root));
            Assert.Equal(web, StaticFiles.WebDir(root));
            Assert.Equal(Path.Combine(web, "index.html"), StaticFiles.Resolve(root, "/play/"));
            Assert.Equal(Path.Combine(web, "tetrafall.pck"), StaticFiles.Resolve(root, "/play/tetrafall.pck"));
            // JS 화면이 없으면 / 는 /play/ 로 (방 링크 ?room= 그대로)
            Assert.Equal("/play/?room=ABCD", StaticFiles.Redirect("/", "/?room=ABCD", jsClient: false));
            Assert.Equal("/play/", StaticFiles.Redirect("/", "/", jsClient: false));
            Assert.Null(StaticFiles.Redirect("/", "/", jsClient: true));
            Assert.Null(StaticFiles.Redirect("/play/", "/play/", jsClient: false));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Precompressed_picks_br_then_gzip_by_accept_encoding()
    {
        var dir = Path.Combine(Path.GetTempPath(), "tf-pre-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var wasm = Path.Combine(dir, "tetrafall.wasm");
            var js = Path.Combine(dir, "tetrafall.js");
            foreach (var f in new[] { wasm, wasm + ".br", wasm + ".gz", js, js + ".gz" }) File.WriteAllText(f, "x");
            Assert.Equal((wasm + ".br", "br"), StaticFiles.Precompressed(wasm, "gzip, deflate, br, zstd"));
            Assert.Equal((wasm + ".gz", "gzip"), StaticFiles.Precompressed(wasm, "gzip, deflate"));
            Assert.Equal((wasm + ".gz", "gzip"), StaticFiles.Precompressed(wasm, "br;q=0, gzip;q=0.8"));
            Assert.Equal((wasm, (string?)null), StaticFiles.Precompressed(wasm, null));
            Assert.Equal((wasm, (string?)null), StaticFiles.Precompressed(wasm, "identity"));
            Assert.Equal((js + ".gz", "gzip"), StaticFiles.Precompressed(js, "br, gzip")); // .br 없으면 gz
            var html = Path.Combine(dir, "index.html");
            File.WriteAllText(html, "x");
            Assert.Equal((html, (string?)null), StaticFiles.Precompressed(html, "br, gzip")); // 압축본 없으면 날것
            Assert.Equal("application/wasm", StaticFiles.Mime(wasm)); // 형식은 날것 이름으로
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
