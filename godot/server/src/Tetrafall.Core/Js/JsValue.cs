using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Tetrafall.Core.Js;

// 받은 JSON 값을 JS 처럼 바꾸기 (rooms.js 가 msg.x 에 하는 것): String(x) · String(x ?? '') · !!x · Number(x).
// null 인 JsonElement? = JS undefined (필드가 없음), JsonValueKind.Null = JS null
public static class JsValue
{
    public static JsonElement? Field(JsonElement msg, string name) => msg.ValueKind == JsonValueKind.Object && msg.TryGetProperty(name, out var v) ? v : null;

    // String(x)
    public static string Str(JsonElement? e)
    {
        if (e is not { } v) return "undefined";
        return v.ValueKind switch
        {
            JsonValueKind.Null => "null",
            JsonValueKind.Array => ArrayStr(v),
            _ => Prim(v),
        };
    }

    // String(x ?? '')
    public static string StrOrEmpty(JsonElement? e) => e is { ValueKind: not JsonValueKind.Null } v ? Str(v) : "";

    static string Prim(JsonElement v) => v.ValueKind switch
    {
        JsonValueKind.String => v.GetString() ?? "",
        JsonValueKind.Number => JsNumber.ToJs(v.GetDouble()),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        JsonValueKind.Object => "[object Object]",
        JsonValueKind.Array => ArrayStr(v),
        _ => "",
    };

    // Array.prototype.join(','): null·undefined 칸은 빈 글자
    static string ArrayStr(JsonElement v) => string.Join(",", v.EnumerateArray().Select(x => x.ValueKind == JsonValueKind.Null ? "" : Prim(x)));

    // !!x
    public static bool Truthy(JsonElement? e)
    {
        if (e is not { } v) return false;
        return v.ValueKind switch
        {
            JsonValueKind.Null or JsonValueKind.False or JsonValueKind.Undefined => false,
            JsonValueKind.Number => v.GetDouble() is var d && d != 0 && !double.IsNaN(d),
            JsonValueKind.String => (v.GetString() ?? "") != "",
            _ => true,
        };
    }

    // typeof x === 'string' 이면 그 글자, 아니면 null
    public static string? AsString(JsonElement? e) => e is { ValueKind: JsonValueKind.String } v ? v.GetString() : null;

    // typeof x === 'number' 이면 그 숫자, 아니면 null
    public static double? AsNumber(JsonElement? e) => e is { ValueKind: JsonValueKind.Number } v ? v.GetDouble() : null;

    // Number(x)
    public static double ToNumber(JsonElement? e)
    {
        if (e is not { } v) return double.NaN;
        return v.ValueKind switch
        {
            JsonValueKind.Null or JsonValueKind.False => 0,
            JsonValueKind.True => 1,
            JsonValueKind.Number => v.GetDouble(),
            JsonValueKind.String => StringToNumber(v.GetString() ?? ""),
            JsonValueKind.Array => StringToNumber(ArrayStr(v)),
            _ => double.NaN,
        };
    }

    static readonly Regex Dec = new(@"^[+-]?([0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?)$");

    // JS 의 글자 → 숫자 (앞뒤 공백 무시, 빈 글자 0, 0x·0o·0b, Infinity)
    public static double StringToNumber(string s)
    {
        s = JsText.Trim(s);
        if (s == "") return 0;
        if (s is "Infinity" or "+Infinity") return double.PositiveInfinity;
        if (s == "-Infinity") return double.NegativeInfinity;
        if (s.Length > 2 && s[0] == '0' && (s[1] | 0x20) is 'x' or 'o' or 'b')
        {
            int radix = (s[1] | 0x20) == 'x' ? 16 : (s[1] | 0x20) == 'o' ? 8 : 2;
            double n = 0;
            foreach (var ch in s[2..])
            {
                int d = ch >= '0' && ch <= '9' ? ch - '0' : (ch | 0x20) >= 'a' && (ch | 0x20) <= 'z' ? (ch | 0x20) - 'a' + 10 : 99;
                if (d >= radix) return double.NaN;
                n = n * radix + d;
            }
            return n;
        }
        if (!Dec.IsMatch(s)) return double.NaN;
        return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
    }

    // 숫자 → 플레이어 id (Map 키 비교: 정수가 아니면 어떤 플레이어와도 안 같음)
    public static int AsId(double x) => x == Math.Floor(x) && x >= int.MinValue + 1 && x <= int.MaxValue ? (int)x : int.MinValue;
}
