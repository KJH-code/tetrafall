using System.Globalization;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 판별 캐릭터 조정 층 (고도 판 전용, JS 에 없음): 한 판 (Game) 만 캐릭터별 수치를 덮어씀 — 전역 표 (C.*) 는 그대로.
// Game 에 안 주면 (null) 곱셈 자체가 없어 예전과 비트까지 같음. 밸런스 시뮬레이션 (sim --tune) 이 쓰고, 서버 방 (Rooms) 은 밸런스 표 (ConfigBalance.cs) 를 이걸로 받음.
//   kbTaken  받는 넉백 배율 (% 배율 넉백에만 — 고정 넉백 중간 타는 그대로)
//   kbDealt  주는 넉백 배율 (고정 넉백 중간 타는 그대로 — 광전사 분노와 같은 규칙)
//   dmgDealt 주는 피해 % 배율 (남을 때릴 때만, 탱크 아머로 버틴 타도)
//   skillCd  F 쿨타임 배율
//   ultGain  필살기 게이지 차는 양 배율 (주든 받든 그 사람 몫). 건축가 블록 폭발 패시브 (BUILDER_BLAST_ULT) 는 제외 — GainUlt 를 안 거치고 바로 더함
//   hpMult   체력전 HP 배율 — 배율이 아니라 C.HP_CHAR_MULT[캐릭터] 대신 쓰는 값 (sim --hp-mult 와 같은 뜻)
// 모드 덮기 (modes): 그 모드 (C.MODE_NAMES 키) 판에서만 같은 캐릭터·키를 다른 값으로 — 곱하지 않고 바꿈. Game.StartRound 가 For(mode) 로 그 판의 표를 고름
public sealed class Tune
{
    public static readonly string[] KEYS = { "kbTaken", "kbDealt", "dmgDealt", "skillCd", "ultGain", "hpMult" };

    public readonly Dictionary<string, double> kbTaken = new();
    public readonly Dictionary<string, double> kbDealt = new();
    public readonly Dictionary<string, double> dmgDealt = new();
    public readonly Dictionary<string, double> skillCd = new();
    public readonly Dictionary<string, double> ultGain = new();
    public readonly Dictionary<string, double> hpMult = new();
    public readonly Dictionary<string, Tune> modes = new(); // 모드 → 그 모드에서만 바꾸는 값 (덮는 Tune 안에는 modes 가 없음)

    // 캐릭터가 없거나 (예전 규칙 판·허수아비) 표에 없으면 1
    static double Mult(Dictionary<string, double> table, string? c) => c != null && table.TryGetValue(c, out var x) ? x : 1;

    public double KbTaken(string? c) => Mult(kbTaken, c);
    public double KbDealt(string? c) => Mult(kbDealt, c);
    public double DmgDealt(string? c) => Mult(dmgDealt, c);
    public double SkillCd(string? c) => Mult(skillCd, c);
    public double UltGain(string? c) => Mult(ultGain, c);

    // 없으면 null → Game.HpMax 가 C.HP_CHAR_MULT 를 씀
    public double? HpMult(string? c) => c != null && hpMult.TryGetValue(c, out var x) ? x : null;

    public Dictionary<string, double>? Table(string key) => key switch
    {
        "kbTaken" => kbTaken,
        "kbDealt" => kbDealt,
        "dmgDealt" => dmgDealt,
        "skillCd" => skillCd,
        "ultGain" => ultGain,
        "hpMult" => hpMult,
        _ => null,
    };

    // 값 하나 넣기 (같은 자리에 또 넣으면 나중 값). 모르는 캐릭터·키, 0 이하·숫자 아님은 ArgumentException
    public Tune Set(string c, string key, double x)
    {
        if (!C.CHARACTERS.Contains(c)) throw new ArgumentException($"tune {c}.{key}: 캐릭터는 {string.Join(",", C.CHARACTERS)} 중");
        var table = Table(key) ?? throw new ArgumentException($"tune {c}.{key}: 키는 {string.Join(",", KEYS)} 중");
        if (!(x > 0) || !double.IsFinite(x)) throw new ArgumentException($"tune {c}.{key}={JsNumber.ToJs(x)}: 0 보다 큰 수");
        table[c] = x;
        return this;
    }

    // 모드 덮기 값 하나 (그 모드 판에서만). 모르는 모드 (survival·master·kills 밖 — practice 도) 는 ArgumentException, 캐릭터·키·값은 Set 과 같은 검사
    public Tune SetMode(string mode, string c, string key, double x)
    {
        if (!C.MODE_NAMES.ContainsKey(mode)) throw new ArgumentException($"tune {mode}:{c}.{key}: 모드는 {string.Join(",", C.MODE_NAMES.Keys)} 중");
        var over = modes.TryGetValue(mode, out var m) ? m : new Tune();
        over.Set(c, key, x); // 던지면 빈 덮기가 안 남게 넣기 전에
        modes[mode] = over;
        return this;
    }

    // "ninja.kbTaken=0.95,hook.kbDealt=1.1" (캐릭터.키=값, 쉼표로 여럿). "kills:ninja.kbDealt=1.6" = 그 모드에서만 (모드:캐릭터.키=값)
    public static Tune Parse(string spec)
    {
        var t = new Tune();
        foreach (var raw in spec.Split(','))
        {
            string part = raw.Trim();
            int col = part.IndexOf(':');
            string? mode = col >= 0 ? part[..col] : null;
            string body = col >= 0 ? part[(col + 1)..] : part;
            int eq = body.IndexOf('=');
            int dot = body.IndexOf('.');
            if (eq < 0 || dot < 0 || dot > eq) throw new ArgumentException($"tune '{part}': 캐릭터.키=값 (또는 모드:캐릭터.키=값)");
            if (!double.TryParse(body[(eq + 1)..], NumberStyles.Float, CultureInfo.InvariantCulture, out var x)) throw new ArgumentException($"tune '{part}': 값이 숫자가 아님");
            if (mode != null) t.SetMode(mode, body[..dot], body[(dot + 1)..eq], x);
            else t.Set(body[..dot], body[(dot + 1)..eq], x);
        }
        return t;
    }

    // 그 모드 판의 표: 덮기가 없으면 (mode null·연습 포함) 이 객체 그대로, 있으면 기본 표를 복사하고 그 모드 값으로 같은 캐릭터·키를 바꾼 새 표
    // (modes 는 안 옮김 — 판 하나에 쓰는 표). 원본은 안 고침
    public Tune For(string? mode)
    {
        if (mode == null || !modes.TryGetValue(mode, out var over)) return this;
        var t = new Tune();
        foreach (var key in KEYS)
        {
            foreach (var (c, x) in Table(key)!) t.Table(key)![c] = x;
            foreach (var (c, x) in over.Table(key)!) t.Table(key)![c] = x;
        }
        return t;
    }

    // 같은 값의 새 표 (판마다 따로 고쳐 쓸 때). 모드 덮기까지 깊게
    public Tune Clone()
    {
        var t = new Tune();
        foreach (var key in KEYS) foreach (var (c, x) in Table(key)!) t.Table(key)![c] = x;
        foreach (var (m, over) in modes) t.modes[m] = over.Clone();
        return t;
    }

    // summary.json 용: {"kbDealt":{"hook":1.15}, …} — 값이 있는 키만, KEYS 순서. 모드 덮기가 있을 때만 끝에 "modes":{"kills":{…}} (C.MODE_NAMES 순서)
    public void Write(JsonOut o)
    {
        o.Obj();
        foreach (var key in KEYS)
        {
            var table = Table(key)!;
            if (table.Count == 0) continue;
            o.Key(key).Obj();
            foreach (var (c, x) in table) o.P(c, x);
            o.EndObj();
        }
        if (modes.Count > 0)
        {
            o.Key("modes").Obj();
            foreach (var m in C.MODE_NAMES.Keys) if (modes.TryGetValue(m, out var over)) over.Write(o.Key(m));
            o.EndObj();
        }
        o.EndObj();
    }
}
