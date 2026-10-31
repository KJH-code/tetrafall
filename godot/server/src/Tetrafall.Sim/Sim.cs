using System.Text;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;

namespace Tetrafall.Sim;

// tools/sim.js 그대로 (npm run sim 의 C# 판): 봇끼리 판을 코어 수만큼 나눠 돌리고 캐릭터별 승률·사망 원인·판 길이.
// 같은 옵션·시드면 JS 와 같은 판·같은 summary.json·같은 로그 (워커 수도 같으면 워커 로그 파일까지)
public sealed class SimOptions
{
    public double rounds = 504;
    public List<double> players = new() { 2, 3, 4 };
    public List<string> maps = Maps.MAP_IDS.ToList();
    public List<string> chars = C.CHARACTERS.ToList();
    public string level = C.BOT_LEVEL_DEFAULT;
    public bool sky = C.SKY_STAIRS_DEFAULT;
    public double seed = 1;
    public int workers = Environment.ProcessorCount;
    public bool mirror = true;
    public bool log = true;
    public string? @out;
    public string? @base;

    // JSON.stringify({ ...o, base: undefined }) 와 같은 키 순서
    public void Write(JsonOut o)
    {
        o.Obj().P("rounds", rounds).Key("players").Arr();
        foreach (var n in players) o.Num(n);
        o.EndArr().Key("maps").Arr();
        foreach (var m in maps) o.Str(m);
        o.EndArr().Key("chars").Arr();
        foreach (var c in chars) o.Str(c);
        o.EndArr().P("level", level).P("sky", sky).P("seed", seed).P("workers", workers).P("mirror", mirror).P("log", log).P("out", @out).EndObj();
    }
}

public sealed record SimJob(int id, int n, string map, uint seed, string[] chars, bool mirror = false);

public sealed record SimResult(int id, int n, string map, string[] chars, List<int> winSeats, double lenMs, Dictionary<string, double> causes, bool timeout);

public static class BotSim
{
    public const double SIM_ROUND_CAP_MS = 10 * 60 * 1000; // 이보다 길면 무승부로 끊고 '시간 초과'
    static readonly double TICK = 1000 / C.TICK_RATE;

    static uint HashSeed(params object[] parts)
    {
        uint h = 2166136261;
        string s = string.Join("|", parts.Select(x => x is double d ? JsNumber.ToJs(d) : x.ToString()));
        foreach (char ch in s) h = unchecked((h ^ ch) * 16777619u);
        return h;
    }

    public static SimOptions ParseArgs(string[] argv)
    {
        var o = new SimOptions();
        List<string> L(string v, List<string> all) => v == "all" ? all : v.Split(',').Select(s => s.Trim()).Where(s => s != "").ToList();
        for (int i = 0; i < argv.Length; i++)
        {
            string a = argv[i];
            string V() => ++i < argv.Length ? argv[i] : throw new ArgumentException($"{a} 뒤에 값이 없음");
            switch (a)
            {
                case "--rounds": o.rounds = double.Parse(V()); break;
                case "--players": o.players = L(V(), new()).Select(double.Parse).ToList(); break;
                case "--maps": o.maps = L(V(), Maps.MAP_IDS.ToList()); break;
                case "--chars": o.chars = L(V(), C.CHARACTERS.ToList()); break;
                case "--level": o.level = V(); break;
                case "--sky": o.sky = V() == "on"; break;
                case "--seed": o.seed = double.Parse(V()); break;
                case "--workers": o.workers = int.Parse(V()); break;
                case "--no-mirror": o.mirror = false; break;
                case "--no-log": o.log = false; break;
                case "--out": o.@out = V(); break;
                case "--base": o.@base = V(); break;
                default: throw new ArgumentException($"모르는 옵션 {a}");
            }
        }
        if (!(o.rounds > 0)) throw new ArgumentException("--rounds 는 1 이상");
        foreach (var n in o.players) if (!(n >= 2 && n <= C.MAX_PLAYERS)) throw new ArgumentException($"--players {n}: 2~{C.MAX_PLAYERS}");
        foreach (var m in o.maps) if (!Maps.MAP_IDS.Contains(m)) throw new ArgumentException($"--maps {m}: {string.Join(",", Maps.MAP_IDS)} 중");
        foreach (var c in o.chars) if (!C.CHARACTERS.Contains(c)) throw new ArgumentException($"--chars {c}: {string.Join(",", C.CHARACTERS)} 중");
        if (!C.BOT_LEVELS.ContainsKey(o.level)) throw new ArgumentException($"--level {o.level}: {string.Join(",", C.BOT_LEVELS.Keys)} 중");
        return o;
    }

    // 판 목록. (인원, 맵) 짝마다 rounds / 짝 수 만큼 (올림). mirror 면 같은 시드로 자리만 거꾸로 한 판을 하나 더
    public static List<SimJob> PlanJobs(SimOptions o)
    {
        var combos = o.players.SelectMany(n => o.maps.Select(map => (n, map))).ToList();
        int per = (int)Math.Ceiling(o.rounds / combos.Count);
        var jobs = new List<SimJob>();
        foreach (var (n, map) in combos)
        {
            for (int k = 0; k < per; k++)
            {
                uint seed = HashSeed(o.seed, n, map, (double)k);
                var r = new Mulberry32(seed ^ 0x9e3779b9);
                string[] chars;
                if (o.chars.Count >= n)
                {
                    var pool = o.chars.ToArray();
                    for (int i = pool.Length - 1; i > 0; i--)
                    {
                        int j = (int)Math.Floor(r.Next() * (i + 1));
                        (pool[i], pool[j]) = (pool[j], pool[i]);
                    }
                    chars = pool.Take((int)n).ToArray();
                }
                else chars = Enumerable.Range(0, (int)n).Select(_ => o.chars[(int)Math.Floor(r.Next() * o.chars.Count)]).ToArray();
                jobs.Add(new SimJob(jobs.Count, (int)n, map, seed, chars));
                if (o.mirror) jobs.Add(new SimJob(jobs.Count, (int)n, map, seed, chars.Reverse().ToArray(), true));
            }
        }
        return jobs;
    }

    // 한 판
    public static SimResult RunJob(SimJob job, SimOptions o, Action<string>? log = null)
    {
        var g = new Game(log, characters: true, skyStairs: o.sky);
        g.rng = new Mulberry32(job.seed).AsFunc();
        g.SetBotLevel(o.level);
        g.SetMap(job.map);
        var bots = new List<Player>();
        for (int i = 0; i < job.n; i++) bots.Add(g.AddBot()!);
        for (int i = 0; i < bots.Count; i++) g.SetChar(bots[i].id, job.chars[i]);
        g.StartRound();
        double t0 = g.time;
        while (g.phase == "playing" && g.time - t0 < SIM_ROUND_CAP_MS) g.Tick(TICK);
        bool timeout = g.phase == "playing";
        if (timeout) g.EndRound(null);
        var winners = g.winnerIds.Count > 0 ? g.winnerIds : g.winnerId != null ? new List<int> { g.winnerId.Value } : new List<int>();
        var seat = bots.Select((p, i) => (p.id, i)).ToDictionary(x => x.id, x => x.i);
        var causes = new Dictionary<string, double> { ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 };
        foreach (var d in g.deaths) if (causes.ContainsKey(d.cause)) causes[d.cause]++;
        return new SimResult(job.id, job.n, job.map, job.chars, winners.Where(seat.ContainsKey).Select(w => seat[w]).ToList(), g.roundEndTime - t0, causes, timeout);
    }

    // 판들을 워커 여럿에 나눠 돌림 (JS 와 같은 나눔: j % k == i). 워커마다 로그 파일 하나 (logDir 이 있으면)
    public static List<SimResult> RunParallel(List<SimJob> jobs, SimOptions o, string? logDir = null, Action<int, int>? onProgress = null)
    {
        int k = Math.Max(1, Math.Min(o.workers, jobs.Count));
        var chunks = Enumerable.Range(0, k).Select(i => jobs.Where((_, j) => j % k == i).ToList()).ToList();
        var results = new System.Collections.Concurrent.ConcurrentBag<SimResult>();
        int done = 0;
        Parallel.For(0, k, new ParallelOptions { MaxDegreeOfParallelism = k }, i =>
        {
            StreamWriter? w = logDir != null ? new StreamWriter(Path.Combine(logDir, $"w{i:00}.txt"), false, new UTF8Encoding(false)) { NewLine = "\n" } : null;
            try
            {
                foreach (var job in chunks[i])
                {
                    results.Add(RunJob(job, o, w != null ? m => w.WriteLine(m) : null));
                    onProgress?.Invoke(Interlocked.Increment(ref done), jobs.Count);
                }
            }
            finally
            {
                w?.Dispose();
            }
        });
        return results.OrderBy(r => r.id).ToList();
    }

    // ---- 결과 모으기 (JS summarizeSim, 같은 키 순서로 JsonOut) ----
    public sealed class CharRow
    {
        public string @char = "";
        public double rounds, wins, expect, ratio;
        public SortedDictionary<int, (double rounds, double wins, double expect)> byN = new();
    }

    public sealed class Summary
    {
        public int rounds, draws, timeouts;
        public Dictionary<string, double> causes = new() { ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 };
        public List<int> ns = new();
        public Dictionary<int, (double rounds, double medianMs, Dictionary<string, double> causes)> byN = new();
        public double medianMs;
        public List<CharRow> chars = new();

        public void Write(JsonOut o)
        {
            o.Obj().P("rounds", rounds).P("draws", draws).P("timeouts", timeouts);
            WriteCauses(o.Key("causes"), causes);
            o.Key("ns").Arr();
            foreach (var n in ns) o.Num(n);
            o.EndArr().Key("byN").Obj();
            foreach (var n in ns)
            {
                var b = byN[n];
                o.Key(n.ToString()).Obj().P("rounds", b.rounds).P("medianMs", b.medianMs);
                WriteCauses(o.Key("causes"), b.causes);
                o.EndObj();
            }
            o.EndObj().P("medianMs", medianMs).Key("chars").Arr();
            foreach (var x in chars)
            {
                o.Obj().P("char", x.@char).P("rounds", x.rounds).P("wins", x.wins).P("expect", x.expect).Key("byN").Obj();
                foreach (var (n, v) in x.byN) o.Key(n.ToString()).Obj().P("rounds", v.rounds).P("wins", v.wins).P("expect", v.expect).EndObj();
                o.EndObj().P("ratio", x.ratio).EndObj();
            }
            o.EndArr().EndObj();
        }

        static void WriteCauses(JsonOut o, Dictionary<string, double> c) => o.Obj().P("crush", c["crush"]).P("fall", c["fall"]).P("lava", c["lava"]).EndObj();
    }

    static double Median(List<double> a)
    {
        if (a.Count == 0) return 0;
        var s = a.OrderBy(x => x).ToList();
        return s.Count % 2 != 0 ? s[(s.Count - 1) / 2] : (s[s.Count / 2 - 1] + s[s.Count / 2]) / 2;
    }

    public static Summary SummarizeSim(List<SimResult> results)
    {
        var chars = new List<CharRow>();
        CharRow Ch(string c)
        {
            var x = chars.FirstOrDefault(r => r.@char == c);
            if (x == null) chars.Add(x = new CharRow { @char = c });
            return x;
        }
        var s = new Summary();
        var byN = new Dictionary<int, (int rounds, List<double> lens, Dictionary<string, double> causes)>();
        foreach (var r in results)
        {
            if (!byN.TryGetValue(r.n, out var nb)) byN[r.n] = nb = (0, new List<double>(), new Dictionary<string, double> { ["crush"] = 0, ["fall"] = 0, ["lava"] = 0 });
            nb.rounds++;
            nb.lens.Add(r.lenMs);
            foreach (var k in new[] { "crush", "fall", "lava" })
            {
                s.causes[k] += r.causes[k];
                nb.causes[k] += r.causes[k];
            }
            byN[r.n] = nb;
            if (r.winSeats.Count == 0) s.draws++;
            if (r.timeout) s.timeouts++;
            double share = r.winSeats.Count > 0 ? 1.0 / r.winSeats.Count : 0; // 공동 승리는 나눠 가짐
            for (int seatI = 0; seatI < r.chars.Length; seatI++)
            {
                var x = Ch(r.chars[seatI]);
                double w = r.winSeats.Contains(seatI) ? share : 0;
                x.rounds++;
                x.wins += w;
                x.expect += 1.0 / r.n;
                var xn = x.byN.TryGetValue(r.n, out var v) ? v : (0, 0, 0);
                x.byN[r.n] = (xn.rounds + 1, xn.wins + w, xn.expect + 1.0 / r.n);
            }
        }
        foreach (var x in chars) x.ratio = x.expect != 0 ? x.wins / x.expect : 0;
        s.rounds = results.Count;
        s.chars = chars.OrderByDescending(x => x.ratio).ToList(); // 안정 정렬 (JS sort b - a)
        s.ns = byN.Keys.OrderBy(n => n).ToList();
        foreach (var n in s.ns) s.byN[n] = (byN[n].rounds, Median(byN[n].lens), byN[n].causes);
        s.medianMs = Median(results.Select(r => r.lenMs).ToList());
        return s;
    }

    // ---- 화면 표 (JS formatSim) ----
    static string Pct(double a, double b) => b != 0 ? $"{JsNumber.ToFixed((a / b) * 100, 1)}%" : "-";
    static string Sec(double ms) => $"{JsNumber.ToFixed(ms / 1000, 1)}초";

    // 한글은 두 칸
    static int Len(string s)
    {
        int n = 0;
        foreach (var cp in JsText.CodePoints(s))
        {
            int c = char.ConvertToUtf32(cp, 0);
            n += (c >= 0x1100 && c <= 0x11ff) || (c >= 0x3000 && c <= 0x9fff) || (c >= 0xac00 && c <= 0xd7af) ? 2 : 1;
        }
        return n;
    }

    static string Table(List<string> head, List<List<string>> rows)
    {
        var w = head.Select((h, i) => Math.Max(Len(h), rows.Select(r => Len(r[i])).DefaultIfEmpty(int.MinValue).Max())).ToList();
        string Line(List<string> r) => string.Join("  ", r.Select((c, i) => c + new string(' ', w[i] - Len(c)))).TrimEnd();
        return string.Join("\n", new[] { Line(head) }.Concat(rows.Select(Line)));
    }

    public static string FormatSim(Summary s, JsonElement? baseSum = null)
    {
        string Name(string c) => C.CHAR_NAMES.TryGetValue(c, out var n) ? n : c;
        double deaths = s.causes["crush"] + s.causes["fall"] + s.causes["lava"];
        Dictionary<string, double>? bc = baseSum?.GetProperty("chars").EnumerateArray().ToDictionary(x => x.GetProperty("char").GetString()!, x => x.GetProperty("ratio").GetDouble());
        var out_ = new List<string>();
        out_.Add($"판 {s.rounds} · 무승부 {s.draws} · 시간 초과 {s.timeouts} · 판 길이 중앙값 {Sec(s.medianMs)}{(baseSum != null ? $" (전 {Sec(baseSum.Value.GetProperty("medianMs").GetDouble())})" : "")}");
        out_.Add($"사망 {JsNumber.ToJs(deaths)}: 압사 {Pct(s.causes["crush"], deaths)} · 낙사 {Pct(s.causes["fall"], deaths)} · 용암 {Pct(s.causes["lava"], deaths)}");
        out_.Add("");
        out_.Add("== 캐릭터별 (×기대 = 승 ÷ 판마다 1/인원 합, 1.00 이 평균) ==");
        var head = new List<string> { "캐릭터", "판", "승률", "×기대" };
        head.AddRange(s.ns.Select(n => $"{n}인"));
        if (bc != null) head.AddRange(new[] { "전 ×기대", "차이" });
        out_.Add(Table(head, s.chars.Select(x =>
        {
            var row = new List<string> { Name(x.@char), JsNumber.ToJs(x.rounds), Pct(x.wins, x.rounds), JsNumber.ToFixed(x.ratio, 2) };
            row.AddRange(s.ns.Select(n => x.byN.TryGetValue(n, out var v) ? JsNumber.ToFixed(v.wins / v.expect, 2) : "-"));
            if (bc != null)
            {
                bool has = bc.TryGetValue(x.@char, out var b);
                row.Add(has ? JsNumber.ToFixed(b, 2) : "-");
                row.Add(has ? $"{(x.ratio - b >= 0 ? "+" : "")}{JsNumber.ToFixed(x.ratio - b, 2)}" : "-");
            }
            return row;
        }).ToList()));
        out_.Add("");
        out_.Add("== 인원별 ==");
        out_.Add(Table(new List<string> { "인원", "판", "판 길이 중앙값", "압사", "낙사", "용암" }, s.ns.Select(n =>
        {
            var b = s.byN[n];
            double d = b.causes["crush"] + b.causes["fall"] + b.causes["lava"];
            return new List<string> { $"{n}인", JsNumber.ToJs(b.rounds), Sec(b.medianMs), Pct(b.causes["crush"], d), Pct(b.causes["fall"], d), Pct(b.causes["lava"], d) };
        }).ToList()));
        return string.Join("\n", out_);
    }

    // JSON.stringify(v, null, 1) 모양으로 (한 칸 들여쓰기). 숫자·글자는 원래 글자 그대로
    public static string Pretty(string compact)
    {
        var sb = new StringBuilder();
        void W(JsonElement e, int depth)
        {
            switch (e.ValueKind)
            {
                case JsonValueKind.Object:
                {
                    var props = e.EnumerateObject().ToList();
                    if (props.Count == 0)
                    {
                        sb.Append("{}");
                        return;
                    }
                    sb.Append("{\n");
                    for (int i = 0; i < props.Count; i++)
                    {
                        sb.Append(' ', depth + 1);
                        var k = new JsonOut();
                        k.Str(props[i].Name);
                        sb.Append(k.ToString()).Append(": ");
                        W(props[i].Value, depth + 1);
                        sb.Append(i < props.Count - 1 ? ",\n" : "\n");
                    }
                    sb.Append(' ', depth).Append('}');
                    return;
                }
                case JsonValueKind.Array:
                {
                    var items = e.EnumerateArray().ToList();
                    if (items.Count == 0)
                    {
                        sb.Append("[]");
                        return;
                    }
                    sb.Append("[\n");
                    for (int i = 0; i < items.Count; i++)
                    {
                        sb.Append(' ', depth + 1);
                        W(items[i], depth + 1);
                        sb.Append(i < items.Count - 1 ? ",\n" : "\n");
                    }
                    sb.Append(' ', depth).Append(']');
                    return;
                }
                case JsonValueKind.String:
                {
                    var k = new JsonOut();
                    k.Str(e.GetString());
                    sb.Append(k.ToString());
                    return;
                }
                default:
                    sb.Append(e.GetRawText());
                    return;
            }
        }
        using var doc = JsonDocument.Parse(compact);
        W(doc.RootElement, 0);
        return sb.ToString();
    }

    // summary.json 글자 (JS 와 같은 모양)
    public static string SummaryJson(string? commit, SimOptions o, Summary s)
    {
        var j = new JsonOut();
        j.Obj().P("commit", commit).Key("options");
        o.Write(j);
        j.Key("summary");
        s.Write(j);
        j.EndObj();
        return Pretty(j.ToString());
    }
}
