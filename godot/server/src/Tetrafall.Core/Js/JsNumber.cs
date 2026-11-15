using System.Globalization;
using System.Text;

namespace Tetrafall.Core.Js;

// JS Number → 글자 (Number::toString, JSON.stringify 와 같음). 가장 짧은 되돌림 자릿수는 .NET "R" 과 같고 모양만 JS 규칙으로
public static class JsNumber
{
  [ThreadStatic] static StringBuilder? t_sb; // ToJs 용 (스레드마다 하나라 방 병렬 스냅샷·로그에서도 안전)

  // Write 를 감싸기만 함 (글자 규칙은 Write 하나): 결과 string 하나만 새로 만듦
  public static string ToJs(double d) {
    var sb = t_sb ??= new StringBuilder(32);
    sb.Clear();
    Write(sb, d);
    return sb.ToString();
  }

  // ToJs 와 같은 글자를 sb 에 바로 씀 — 힙 할당 없음 (sb 자리가 모자랄 때 늘리는 것만).
  // 스냅샷은 숫자가 수천 개라 예전 ToJs (R 글자 + Substring·글자 잇기 여러 번 + 결과 string) 가 스냅샷 할당의 절반이 넘었음.
  // 소수는 "R" 을 stackalloc 칸에 쓰고 그 칸에서 부호·지수·자릿수를 읽어 JS 4갈래로 씀
  public static void Write(StringBuilder sb, double d) {
    if (double.IsNaN(d)) { sb.Append("NaN"); return; }
    if (double.IsPositiveInfinity(d)) { sb.Append("Infinity"); return; }
    if (double.IsNegativeInfinity(d)) { sb.Append("-Infinity"); return; }
    if (d == 0) { sb.Append('0'); return; } // -0 도 "0"
    if (d == Math.Floor(d) && Math.Abs(d) < 1e15) { AppendLong(sb, (long)d); return; }
    Span<char> r = stackalloc char[32]; // "R" 은 길어야 24자 (-1.2345678901234567E-308)
    if (!d.TryFormat(r, out int len, "R", CultureInfo.InvariantCulture)) throw new InvalidOperationException($"JsNumber: R 글자가 칸보다 김 ({d})");
    r = r[..len];
    bool neg = r[0] == '-';
    if (neg) r = r[1..];
    int e = 0;
    int ei = r.IndexOfAny('E', 'e');
    if (ei >= 0) {
      var es = r[(ei + 1)..];
      bool eneg = es[0] == '-';
      int i = es[0] == '-' || es[0] == '+' ? 1 : 0;
      for (; i < es.Length; i++) e = e * 10 + (es[i] - '0');
      if (eneg) e = -e;
      r = r[..ei];
    }
    int dot = r.IndexOf('.');
    int intLen = dot >= 0 ? dot : r.Length;
    // intPart + frac (점 뺀 자릿수) 를 칸 하나에
    Span<char> all = stackalloc char[32];
    int m = 0;
    for (int i = 0; i < r.Length; i++) if (r[i] != '.') all[m++] = r[i];
    int lead = 0; // 앞 0 개수
    while (lead < m && all[lead] == '0') lead++;
    int n = intLen + e - lead; // 소수점 위치 (JS 알고리즘의 n)
    int end = m;
    while (end > lead && all[end - 1] == '0') end--;
    ReadOnlySpan<char> digits = all[lead..end];
    int k = digits.Length;
    if (neg) sb.Append('-');
    if (k <= n && n <= 21) { sb.Append(digits).Append('0', n - k); }
    else if (0 < n && n <= 21) { sb.Append(digits[..n]).Append('.').Append(digits[n..]); }
    else if (-6 < n && n <= 0) { sb.Append("0.").Append('0', -n).Append(digits); }
    else {
      sb.Append(digits[0]);
      if (k > 1) sb.Append('.').Append(digits[1..]);
      int ex = n - 1;
      sb.Append('e').Append(ex >= 0 ? '+' : '-');
      AppendLong(sb, Math.Abs(ex));
    }
  }

  // 정수 그대로 (InvariantCulture — 예전 ToString(InvariantCulture) 와 같은 글자, 지금 문화권의 음수 부호를 안 탐)
  static void AppendLong(StringBuilder sb, long v) {
    Span<char> s = stackalloc char[20];
    v.TryFormat(s, out int n, default, CultureInfo.InvariantCulture);
    sb.Append(s[..n]);
  }

  // JS Number.prototype.toFixed (로그 글자 "x.toFixed(1)"): x·10^f 에 가장 가까운 정수, 딱 반이면 큰 쪽 (.NET "F" 는 짝수 쪽이라 다름).
  // double 의 정확한 값 (가수·2^지수) 으로 BigInteger 계산
  public static string ToFixed(double x, int digits) {
    if (double.IsNaN(x)) return "NaN";
    if (Math.Abs(x) >= 1e21) return ToJs(x);
    bool neg = x < 0;
    if (neg) x = -x;
    long bitsv = BitConverter.DoubleToInt64Bits(x);
    int exp = (int)((bitsv >> 52) & 0x7ff);
    long man = bitsv & 0xfffffffffffffL;
    if (exp == 0) exp = 1; else man |= 1L << 52;
    exp -= 1075; // x = man · 2^exp
    var num = new System.Numerics.BigInteger(man) * System.Numerics.BigInteger.Pow(10, digits);
    System.Numerics.BigInteger n;
    if (exp >= 0) n = num << exp;
    else {
      var den = System.Numerics.BigInteger.One << -exp;
      n = (2 * num + den) / (2 * den); // 반올림, 딱 반이면 위로
    }
    var str = n.ToString(CultureInfo.InvariantCulture);
    if (digits > 0) {
      if (str.Length <= digits) str = new string('0', digits - str.Length + 1) + str;
      str = str[..^digits] + "." + str[^digits..];
    }
    return (neg ? "-" : "") + str; // (-0.04).toFixed(1) = "-0.0" (JS 그대로), -0 은 neg 아님
  }
}
