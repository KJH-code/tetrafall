using System.Globalization;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 판별 캐릭터 조정 층 (고도 판 전용, JS 에 없음): 한 판 (Game) 만 캐릭터별 수치를 덮어씀 — 전역 표 (C.*) 는 그대로.
// Game 에 안 주면 (null) 곱셈 자체가 없어 예전과 비트까지 같음. 밸런스 시뮬레이션 (sim --tune) 이 씀, 방 (Rooms) 은 안 씀.
//   kbTaken  받는 넉백 배율 (% 배율 넉백에만 — 고정 넉백 중간 타는 그대로)
//   kbDealt  주는 넉백 배율 (고정 넉백 중간 타는 그대로 — 광전사 분노와 같은 규칙)
//   dmgDealt 주는 피해 % 배율 (남을 때릴 때만, 탱크 아머로 버틴 타도)
//   skillCd  F 쿨타임 배율
//   ultGain  필살기 게이지 차는 양 배율 (주든 받든 그 사람 몫)
//   hpMult   체력전 HP 배율 — 배율이 아니라 C.HP_CHAR_MULT[캐릭터] 대신 쓰는 값 (sim --hp-mult 와 같은 뜻)
public sealed class Tune
{
    public static readonly string[] KEYS = { "kbTaken", "kbDealt", "dmgDealt", "skillCd", "ultGain", "hpMult" };

    public readonly Dictionary<string, double> kbTaken = new();
    public readonly Dictionary<string, double> kbDealt = new();
    public readonly Dictionary<string, double> dmgDealt = new();
    public readonly Dictionary<string, double> skillCd = new();
    public readonly Dictionary<string, double> ultGain = new();
    public readonly Dictionary<string, double> hpMult = new();

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

    // "ninja.kbTaken=0.95,hook.kbDealt=1.1" (캐릭터.키=값, 쉼표로 여럿)
    public static Tune Parse(string spec)
    {
        var t = new Tune();
        foreach (var raw in spec.Split(','))
        {
            string part = raw.Trim();
            int eq = part.IndexOf('=');
            int dot = part.IndexOf('.');
            if (eq < 0 || dot < 0 || dot > eq) throw new ArgumentException($"tune '{part}': 캐릭터.키=값");
            if (!double.TryParse(part[(eq + 1)..], NumberStyles.Float, CultureInfo.InvariantCulture, out var x)) throw new ArgumentException($"tune '{part}': 값이 숫자가 아님");
            t.Set(part[..dot], part[(dot + 1)..eq], x);
        }
        return t;
    }

    // 같은 값의 새 표 (판마다 따로 고쳐 쓸 때)
    public Tune Clone()
    {
        var t = new Tune();
        foreach (var key in KEYS) foreach (var (c, x) in Table(key)!) t.Table(key)![c] = x;
        return t;
    }

    // summary.json 용: {"kbDealt":{"hook":1.15}, …} — 값이 있는 키만, KEYS 순서
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
        o.EndObj();
    }
}
