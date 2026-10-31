using System.Text.RegularExpressions;

namespace Tetrafall.Core.Js;

// 글자 정리 (rooms.js cleanText · game-players.js setNick 과 같음): 먼저 TEXT_RAW_MAX 로 자르고, 제어 문자 빼고, JS \s 공백을 하나로, 앞뒤 공백 빼고,
// 글자(코드 포인트) max 개까지. JS 의 String.prototype.slice 는 UTF-16 단위, Array.from 은 코드 포인트 단위 — C# 도 같게
public static class JsText
{
    // JS 정규식 \s · String.prototype.trim 의 공백 목록
    const string JsSpace = "\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff";
    static readonly Regex Ctrl = new("[\\u0000-\\u001f\\u007f]");
    static readonly Regex Spaces = new($"[{JsSpace}]+");
    public static readonly char[] TrimChars = "\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff".ToCharArray();

    // 테스트용: 이 스레드에서 정규식이 본 가장 긴 글자 수 (긴 이름 테스트가 시간 대신 이걸로 판정 — test/safety.test.js 와 같은 방법)
    [ThreadStatic] public static int longestRegexInput;

    public static string Clean(string s, double max)
    {
        if (s.Length > C.TEXT_RAW_MAX) s = s[..(int)C.TEXT_RAW_MAX]; // 긴 문자열에 정규식을 통째로 돌리지 않게
        if (s.Length > longestRegexInput) longestRegexInput = s.Length;
        s = Ctrl.Replace(s, "");
        s = Spaces.Replace(s, " ").Trim(TrimChars);
        var sb = new System.Text.StringBuilder();
        int n = 0;
        for (int i = 0; i < s.Length && n < max; n++)
        {
            int len = char.IsSurrogatePair(s, i) ? 2 : 1;
            sb.Append(s, i, len);
            i += len;
        }
        return sb.ToString();
    }

    // JS String.prototype.trim
    public static string Trim(string s) => s.Trim(TrimChars);

    // JS String(v ?? '') — 게임 함수가 받은 값 (null·글자·숫자·참거짓)
    public static string String(object? v) => v switch
    {
        null => "",
        string s => s,
        double d => JsNumber.ToJs(d),
        bool b => b ? "true" : "false",
        _ => v.ToString() ?? "",
    };

    // Array.from(s): 짝 맞는 서로게이트는 한 글자, 짝 없는 반쪽도 한 글자
    public static IEnumerable<string> CodePoints(string s)
    {
        for (int i = 0; i < s.Length; i++)
        {
            if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
            {
                yield return s.Substring(i, 2);
                i++;
            }
            else yield return s[i].ToString();
        }
    }
}
