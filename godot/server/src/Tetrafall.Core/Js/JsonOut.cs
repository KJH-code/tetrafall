using System.Text;

namespace Tetrafall.Core.Js;

// JSON.stringify 와 글자 하나까지 같은 JSON 쓰기 (키 순서는 쓰는 순서 그대로, 숫자는 JsNumber, 글자 이스케이프는 JS 규칙).
// JS 의 undefined 필드는 안 씀 (부르지 않으면 됨), Infinity·NaN 은 null (JSON.stringify 와 같음)
public sealed class JsonOut
{
    readonly StringBuilder sb = new(4096);
    readonly Stack<bool> first = new();
    bool afterKey;

    public override string ToString() => sb.ToString();

    void Sep()
    {
        if (afterKey)
        {
            afterKey = false;
            return;
        }
        if (first.Count == 0) return;
        if (first.Peek())
        {
            first.Pop();
            first.Push(false);
        }
        else sb.Append(',');
    }

    public JsonOut Obj()
    {
        Sep();
        sb.Append('{');
        first.Push(true);
        return this;
    }

    public JsonOut EndObj()
    {
        first.Pop();
        sb.Append('}');
        return this;
    }

    public JsonOut Arr()
    {
        Sep();
        sb.Append('[');
        first.Push(true);
        return this;
    }

    public JsonOut EndArr()
    {
        first.Pop();
        sb.Append(']');
        return this;
    }

    public JsonOut Key(string k)
    {
        Sep();
        Escape(k);
        sb.Append(':');
        afterKey = true;
        return this;
    }

    public JsonOut Num(double v)
    {
        Sep();
        sb.Append(double.IsFinite(v) ? JsNumber.ToJs(v) : "null");
        return this;
    }

    public JsonOut Str(string? s)
    {
        Sep();
        if (s == null) sb.Append("null");
        else Escape(s);
        return this;
    }

    public JsonOut Bool(bool b)
    {
        Sep();
        sb.Append(b ? "true" : "false");
        return this;
    }

    public JsonOut Null()
    {
        Sep();
        sb.Append("null");
        return this;
    }

    // 이미 JSON 글자인 것 (이벤트 등)
    public JsonOut Raw(string json)
    {
        Sep();
        sb.Append(json);
        return this;
    }

    // 자주 쓰는 모양: "키":값
    public JsonOut P(string k, double v) => Key(k).Num(v);
    public JsonOut P(string k, string? v) => Key(k).Str(v);
    public JsonOut P(string k, bool v) => Key(k).Bool(v);
    public JsonOut P(string k, double? v) => v.HasValue ? Key(k).Num(v.Value) : Key(k).Null();
    public JsonOut PNull(string k) => Key(k).Null();

    void Escape(string s)
    {
        sb.Append('"');
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                    else if (char.IsHighSurrogate(c) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
                    {
                        sb.Append(c).Append(s[i + 1]);
                        i++;
                    }
                    else if (char.IsSurrogate(c)) sb.Append("\\u").Append(((int)c).ToString("x4")); // 짝 없는 반쪽 (ES2019 JSON.stringify)
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}
