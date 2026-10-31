using System.Diagnostics;
using System.Net.WebSockets;
using System.Text.RegularExpressions;
using Tetrafall.Core;

namespace Tetrafall.Server;

// 인터넷 대전 터널 (tools/online.js 의 C# 판 — node 없이 서버 혼자): Tetrafall.Server --online
// cloudflared 를 켜고 → 출력에서 https://….trycloudflare.com 주소를 찾고 → 그 주소로 실제 요청(HTTP + 웹소켓)이 될 때까지 기다렸다가 알림 (OnReady).
// 정한 시간 안에 안 열리거나 열린 뒤 죽으면 cloudflared 를 다시 켬 (연속 실패 TUNNEL_MAX_RESTARTS 번까지). 수치는 config TUNNEL_*
public interface ITunnelProc
{
    string Output { get; } // 지금까지 stdout + stderr (끝 4000자)
    bool Exited { get; }
    void Kill();
}

public sealed class TunnelKeeper
{
    public required Func<ITunnelProc?> SpawnTunnel; // null = cloudflared 를 못 켬 (없음)
    public required Func<string, Task<bool>> Probe;
    public Action<string> OnReady = _ => { };
    public Action<string, string, string?> OnStatus = (_, _, _) => { }; // (종류, 글, cloudflared 출력)
    public Func<double, Task> Sleep = ms => Task.Delay(TimeSpan.FromMilliseconds(ms));
    public Func<double> Now = () => Environment.TickCount64;

    volatile bool stopped;
    ITunnelProc? child;
    public int Fails { get; private set; } // 연속 실패 (열리면 0)
    public string? Url { get; private set; } // 지금 열린 주소

    // cloudflared 출력에서 터널 주소 (online.js tunnelUrl 과 같음: 하이픈 있는 것만 — 실패 메시지의 api.trycloudflare.com 은 안 집음)
    public static string? TunnelUrl(string text)
    {
        var m = Regex.Match(text, @"https://[a-z0-9]+(?:-[a-z0-9]+)+\.trycloudflare\.com");
        return m.Success ? m.Value : null;
    }

    public void Stop()
    {
        stopped = true;
        child?.Kill();
    }

    public async Task<bool> Run()
    {
        while (!stopped)
        {
            if (Fails > C.TUNNEL_MAX_RESTARTS)
            {
                OnStatus("give-up", $"터널을 {C.TUNNEL_MAX_RESTARTS + 1}번 켰는데 안 열립니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다. 잠시 뒤 다시 켜 보세요", child?.Output);
                return false;
            }
            var c = SpawnTunnel();
            if (c == null) return false;
            child = c;
            // 1) 주소 받기
            string? url = null;
            for (var t0 = Now(); url == null && !c.Exited && !stopped && Now() - t0 < C.TUNNEL_URL_TIMEOUT_MS;)
            {
                url = TunnelUrl(c.Output);
                if (url == null) await Sleep(C.TUNNEL_POLL_MS);
            }
            if (stopped) return true;
            if (url == null)
            {
                Fail(c, c.Exited ? "cloudflared 가 바로 꺼짐" : "주소를 못 받음");
                continue;
            }
            // 2) 그 주소가 실제로 열릴 때까지 (Cloudflare 가 주소를 퍼뜨리는 데 몇 초)
            OnStatus("checking", $"터널 주소 받음: {url} — 친구가 열 수 있는지 확인 중…", null);
            bool open = false;
            for (var t0 = Now(); !open && !c.Exited && !stopped && Now() - t0 < C.TUNNEL_READY_TIMEOUT_MS;)
            {
                open = await Probe(url);
                if (!open) await Sleep(C.TUNNEL_PROBE_INTERVAL_MS);
            }
            if (stopped) return true;
            if (!open)
            {
                Fail(c, c.Exited ? "터널이 꺼짐" : $"{Math.Round(C.TUNNEL_READY_TIMEOUT_MS / 1000)}초 안에 안 열림");
                continue;
            }
            Fails = 0;
            Url = url;
            OnReady(url);
            // 3) 열린 뒤에도 주기적으로 확인. 꺼지거나 연속 TUNNEL_HEALTH_FAILS 번 안 열리면 다시 켬
            int bad = 0;
            while (!stopped && !c.Exited && bad < C.TUNNEL_HEALTH_FAILS)
            {
                await Sleep(C.TUNNEL_HEALTH_MS);
                if (stopped || c.Exited) break;
                bad = await Probe(url) ? 0 : bad + 1;
            }
            if (stopped) return true;
            Url = null;
            Fail(c, c.Exited ? "터널이 꺼짐" : "주소가 안 열림", wasOpen: true);
        }
        return true;
    }

    void Fail(ITunnelProc c, string why, bool wasOpen = false)
    {
        Fails++;
        c.Kill();
        OnStatus("restart", $"{(wasOpen ? "열려 있던 " : "")}터널 문제 ({why}) → 다시 켭니다 ({Fails}/{C.TUNNEL_MAX_RESTARTS})", c.Output);
    }
}

// 진짜 cloudflared 프로세스
public sealed class CloudflaredProc : ITunnelProc
{
    readonly Process proc;
    readonly System.Text.StringBuilder sb = new();

    CloudflaredProc(Process p)
    {
        proc = p;
        void Add(string? line)
        {
            if (line == null) return;
            lock (sb)
            {
                sb.Append(line).Append('\n');
                if (sb.Length > 4000) sb.Remove(0, sb.Length - 4000);
            }
        }
        p.OutputDataReceived += (_, e) => Add(e.Data);
        p.ErrorDataReceived += (_, e) => Add(e.Data);
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
    }

    public string Output { get { lock (sb) return sb.ToString(); } }
    public bool Exited => proc.HasExited;

    public void Kill()
    {
        try { if (!proc.HasExited) proc.Kill(entireProcessTree: true); } catch { } // 이미 꺼짐
    }

    // cloudflared 찾기: 환경 변수 CLOUDFLARED > 서버 exe 옆 (배포 zip 에 넣어 둠) > PATH
    public static string Find()
    {
        var env = Environment.GetEnvironmentVariable("CLOUDFLARED");
        if (!string.IsNullOrEmpty(env)) return env;
        var name = OperatingSystem.IsWindows() ? "cloudflared.exe" : "cloudflared";
        var beside = Path.Combine(AppContext.BaseDirectory, name);
        return File.Exists(beside) ? beside : "cloudflared";
    }

    // 못 켜면 (없음) null
    public static CloudflaredProc? Start(string exe, int port)
    {
        var psi = new ProcessStartInfo(exe) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        foreach (var a in new[] { "tunnel", "--no-autoupdate", "--url", $"http://localhost:{port}" }) psi.ArgumentList.Add(a);
        try
        {
            var p = Process.Start(psi);
            return p == null ? null : new CloudflaredProc(p);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }
}

public static class TunnelProbe
{
    static readonly HttpClient http = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMilliseconds(C.TUNNEL_PROBE_TIMEOUT_MS) };

    // 주소가 실제로 열리나: 첫 화면 HTTP 200 + 'Tetrafall' 글자 (Cloudflare 안내·에러 페이지가 200 으로 올 때 거름) + 웹소켓 열림.
    // page: 레포면 "/" (JS 화면), 배포 폴더면 "/play/" (/ 는 넘겨주기라 200 아님)
    public static async Task<bool> Check(string url, string page)
    {
        try
        {
            using var res = await http.GetAsync(url + page);
            if (!res.IsSuccessStatusCode) return false;
            if (!(await res.Content.ReadAsStringAsync()).Contains("Tetrafall")) return false;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return false;
        }
        using var ws = new ClientWebSocket();
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(C.TUNNEL_PROBE_TIMEOUT_MS));
        try
        {
            await ws.ConnectAsync(new Uri(Regex.Replace(url, "^https:", "wss:")), cts.Token);
            return ws.State == WebSocketState.Open;
        }
        catch (Exception e) when (e is WebSocketException or OperationCanceledException or HttpRequestException)
        {
            return false;
        }
        finally
        {
            if (ws.State == WebSocketState.Open) try { await ws.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None); } catch { }
        }
    }

    // 클립보드에 넣기 (online.js clipboardCommand 와 같은 명령). 실패해도 조용히 false
    public static bool Copy(string text)
    {
        (string, string[])? cmd = OperatingSystem.IsWindows() ? ("clip", Array.Empty<string>())
            : OperatingSystem.IsMacOS() ? ("pbcopy", Array.Empty<string>())
            : OperatingSystem.IsLinux() ? (Environment.GetEnvironmentVariable("WAYLAND_DISPLAY") != null ? ("wl-copy", Array.Empty<string>()) : ("xclip", new[] { "-selection", "clipboard" }))
            : null;
        if (cmd == null) return false;
        try
        {
            var psi = new ProcessStartInfo(cmd.Value.Item1) { RedirectStandardInput = true, UseShellExecute = false };
            foreach (var a in cmd.Value.Item2) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi)!;
            p.StandardInput.Write(text);
            p.StandardInput.Close();
            return p.WaitForExit(3000) && p.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    // online.js banner 와 같은 안내 상자
    public static string Banner(string url, bool copied)
    {
        var lines = new[]
        {
            "친구에게 이 주소를 보내세요 (켤 때마다 바뀜):",
            "",
            $"  {url}",
            "",
            copied ? "(클립보드에 복사해 둠 — 메신저에 붙여 넣기만)" : "(복사: 위 주소를 드래그)",
            "방을 만든 뒤 대기 화면의 \"링크 복사\" 는 이 주소 + 방 코드로 복사됨",
        };
        var bar = new string('=', lines.Max(l => l.Length) + 4);
        return string.Join("\n", new[] { "", bar }.Concat(lines.Select(l => $"  {l}")).Concat(new[] { bar, "" }));
    }

    public const string INSTALL = """
        cloudflared 가 없어 터널을 못 켰습니다. 서버는 켜져 있어 같은 Wi-Fi 에서는 됩니다.
        설치 (한 번만) — 아니면 cloudflared(.exe) 를 이 서버 파일 옆에 두기:
          Windows : winget install --id Cloudflare.cloudflared   (설치 뒤 창을 새로 열기)
          macOS   : brew install cloudflared
          그 밖   : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
        """;
}
