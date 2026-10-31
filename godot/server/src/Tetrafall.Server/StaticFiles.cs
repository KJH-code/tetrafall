namespace Tetrafall.Server;

// URL → 디스크 경로 (server/index.js resolveFile 과 같음): client/, shared/, three.js·cannon-es 만 노출.
// + /play/ → godot/client/build/web (고도 웹 빌드, 스레드 없는 판이라 COOP/COEP 헤더 필요 없음. 같은 호스트라 ?server= 없이 이 서버에 붙음)
// 배포 폴더 (tools/package.mjs zip: 서버 exe 옆에 web/) 면 /play/ → <뿌리>/web, JS 화면이 없으니 / 는 /play/ 로 보냄 (방 링크 ?room= 그대로)
public static class StaticFiles
{
    // 고도 웹 빌드 폴더: 배포 폴더 web/ 가 있으면 그것, 아니면 레포 godot/client/build/web
    public static string WebDir(string root)
    {
        var release = Path.Combine(root, "web");
        return Directory.Exists(release) ? release : Path.Combine(root, "godot", "client", "build", "web");
    }

    // 기존 JS 화면(client/index.html)이 있나 — 레포면 있음, 배포 폴더면 없음
    public static bool HasJsClient(string root) => File.Exists(Path.Combine(root, "client", "index.html"));

    static readonly Dictionary<string, string> MIME = new()
    {
        [".html"] = "text/html; charset=utf-8",
        [".js"] = "text/javascript; charset=utf-8",
        [".css"] = "text/css; charset=utf-8",
        [".json"] = "application/json",
        [".png"] = "image/png",
        [".glb"] = "model/gltf-binary",
        [".ico"] = "image/x-icon",
        [".woff2"] = "font/woff2",
        [".wasm"] = "application/wasm", // 고도 웹 빌드 (/play/)
        [".pck"] = "application/octet-stream",
        [".svg"] = "image/svg+xml",
    };

    public static string Mime(string file) => MIME.GetValueOrDefault(Path.GetExtension(file), "application/octet-stream");

    static readonly System.Text.UTF8Encoding StrictUtf8 = new(false, throwOnInvalidBytes: true);

    // decodeURIComponent 처럼: %XX 가 아니거나 UTF-8 이 깨졌으면 null (→ 400)
    public static string? StrictDecode(string s)
    {
        if (!s.Contains('%')) return s;
        var bytes = new List<byte>();
        var sb = new System.Text.StringBuilder();
        void Flush()
        {
            if (bytes.Count == 0) return;
            sb.Append(StrictUtf8.GetString(bytes.ToArray()));
            bytes.Clear();
        }
        try
        {
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] == '%')
                {
                    if (i + 2 >= s.Length || !Uri.IsHexDigit(s[i + 1]) || !Uri.IsHexDigit(s[i + 2])) return null;
                    bytes.Add(Convert.ToByte(s.Substring(i + 1, 2), 16));
                    i += 2;
                }
                else
                {
                    Flush();
                    sb.Append(s[i]);
                }
            }
            Flush();
        }
        catch (System.Text.DecoderFallbackException)
        {
            return null;
        }
        return sb.ToString();
    }

    // /play (끝 / 없음) → /play/ 로 보냄 (쿼리 그대로). 아니면 HTML 안 상대 주소 index.js 가 /index.js (JS 화면) 로 풀려 고도가 안 뜸.
    // jsClient 가 false (배포 폴더) 면 / 도 /play/ 로
    public static string? Redirect(string urlPath, string rawTarget, bool jsClient = true)
    {
        if (urlPath != "/play" && !(!jsClient && (urlPath == "/" || urlPath == ""))) return null;
        int q = rawTarget.IndexOf('?');
        return "/play/" + (q >= 0 ? rawTarget[q..] : "");
    }

    public static string? Resolve(string root, string urlPath)
    {
        if (urlPath == "/" || urlPath == "") return Path.Combine(root, "client", "index.html");
        if (urlPath == "/vendor/three.module.js") return Path.Combine(root, "node_modules", "three", "build", "three.module.js");
        if (urlPath == "/vendor/cannon-es.js") return Path.Combine(root, "node_modules", "cannon-es", "dist", "cannon-es.js");
        string @base, rel;
        if (urlPath == "/play" || urlPath.StartsWith("/play/"))
        {
            @base = WebDir(root);
            rel = urlPath.Length <= "/play/".Length ? "index.html" : urlPath["/play/".Length..];
        }
        else if (urlPath.StartsWith("/vendor/jsm/"))
        {
            @base = Path.Combine(root, "node_modules", "three", "examples", "jsm");
            rel = urlPath["/vendor/jsm/".Length..];
        }
        else if (urlPath.StartsWith("/shared/"))
        {
            @base = Path.Combine(root, "shared");
            rel = urlPath["/shared/".Length..];
        }
        else
        {
            @base = Path.Combine(root, "client");
            rel = urlPath[1..];
        }
        var full = Path.GetFullPath(Path.Combine(@base, rel));
        if (!full.StartsWith(@base + Path.DirectorySeparatorChar)) return null; // 경로 탈출 방지
        return full;
    }
}

// 방마다 로그 파일: logs/<서버를 켠 시각>/<방을 연 시각>_<코드>.txt, 줄마다 "[시각] 내용" (JS 서버와 같은 모양 → npm run stats 가 그대로 읽음).
// 콘솔에는 같은 줄을 [코드] 를 붙여 찍음
public sealed class FileRoomLog : IRoomLog
{
    // JS new Date().toLocaleTimeString('ko-KR', { hour12: false }) 와 같은 글자: "13시 5분 7초"
    public static string Stamp(DateTime d) => $"{d.Hour}시 {d.Minute}분 {d.Second}초";

    // 폴더·파일 이름 시각 (index.js fileStamp): 2026-10-31_13-05-07
    public static string FileStamp(DateTime d) => d.ToString("yyyy-MM-dd_HH-mm-ss", System.Globalization.CultureInfo.InvariantCulture);

    readonly string code;
    StreamWriter? w;

    public FileRoomLog(string runDir, string code)
    {
        this.code = code;
        try
        {
            Directory.CreateDirectory(runDir);
            w = new StreamWriter(Path.Combine(runDir, $"{FileStamp(DateTime.Now)}_{code}.txt"), append: true, new System.Text.UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" }; // 바로 씀: Ctrl+C 로 꺼도 마지막 줄까지
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"[{code}] 로그 파일을 못 엶 (콘솔에만 남김): {e.Message}");
        }
    }

    public void Log(string msg)
    {
        var st = Stamp(DateTime.Now);
        Console.WriteLine($"[{st}] [{code}] {msg}");
        try { w?.WriteLine($"[{st}] {msg}"); } catch { w = null; }
    }

    public void Close()
    {
        w?.Dispose();
        w = null;
    }
}
