using System.Text;

namespace Tetrafall.Core.Js;

// JS 글자 처리와 같게: String(x), \s (유니코드 공백), trim, Array.from (코드 포인트, 짝 없는 반쪽도 한 글자)
public static class JsText
{
    // JS String(v ?? '') — 화면 메시지 값 (null·글자·숫자·참거짓)
    public static string String(object? v) => v switch
    {
        null => "",
        string s => s,
        double d => JsNumber.ToJs(d),
        bool b => b ? "true" : "false",
        _ => v.ToString() ?? "",
    };

    // JS 정규식 \s 와 String.prototype.trim 이 보는 공백
    public static bool IsSpace(char c) =>
        c is (char)9 or (char)10 or (char)11 or (char)12 or (char)13 or (char)32 or (char)0xa0 or (char)0x1680 or (char)0x2028 or (char)0x2029 or (char)0x202f or (char)0x205f or (char)0x3000 or (char)0xfeff || (c >= (char)0x2000 && c <= (char)0x200a);

    // .replace(/\s+/g, ' ')
    public static string CollapseSpace(string s)
    {
        var sb = new StringBuilder(s.Length);
        bool inSpace = false;
        foreach (char c in s)
        {
            if (IsSpace(c))
            {
                if (!inSpace) sb.Append(' ');
                inSpace = true;
            }
            else
            {
                sb.Append(c);
                inSpace = false;
            }
        }
        return sb.ToString();
    }

    public static string Trim(string s)
    {
        int a = 0, b = s.Length;
        while (a < b && IsSpace(s[a])) a++;
        while (b > a && IsSpace(s[b - 1])) b--;
        return s.Substring(a, b - a);
    }

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

    // 이름 정리 (rooms.js cleanText · game-players.js setNick): 먼저 TEXT_RAW_MAX 로 자르고 (UTF-16, JS slice — 긴 글자에 정규식을 통째로 안 돌리게),
    // 제어 문자 빼고, 공백을 하나로, 앞뒤 공백 빼고, 글자(코드 포인트) max 개까지
    public static string Clean(string s, double max)
    {
        if (s.Length > C.TEXT_RAW_MAX) s = s.Substring(0, (int)C.TEXT_RAW_MAX);
        var sb = new StringBuilder();
        foreach (char ch in s) if (!(ch <= '\u001f' || ch == '\u007f')) sb.Append(ch);
        return string.Concat(CodePoints(Trim(CollapseSpace(sb.ToString()))).Take((int)max));
    }
}
