using System.Globalization;
using System.Text;

namespace Tetrafall.Core.Js;

// JS Number → 글자 (Number::toString, JSON.stringify 와 같음). 가장 짧은 되돌림 자릿수는 .NET "R" 과 같고 모양만 JS 규칙으로
public static class JsNumber
{
  public static string ToJs(double d) {
    if (double.IsNaN(d)) return "NaN";
    if (double.IsPositiveInfinity(d)) return "Infinity";
    if (double.IsNegativeInfinity(d)) return "-Infinity";
    if (d == 0) return "0"; // -0 도 "0"
    if (d == Math.Floor(d) && Math.Abs(d) < 1e15) return ((long)d).ToString(CultureInfo.InvariantCulture);
    var r = d.ToString("R", CultureInfo.InvariantCulture);
    bool neg = r[0] == '-';
    if (neg) r = r.Substring(1);
    int e = 0;
    int ei = r.IndexOfAny(new[] { 'E', 'e' });
    if (ei >= 0) { e = int.Parse(r.Substring(ei + 1), CultureInfo.InvariantCulture); r = r.Substring(0, ei); }
    int dot = r.IndexOf('.');
    string intPart = dot >= 0 ? r.Substring(0, dot) : r, frac = dot >= 0 ? r.Substring(dot + 1) : "";
    string digits = (intPart + frac).TrimStart('0');
    int lead = (intPart + frac).Length - digits.Length; // 앞 0 개수
    int n = intPart.Length + e - lead; // 소수점 위치 (JS 알고리즘의 n)
    digits = digits.TrimEnd('0');
    int k = digits.Length;
    var sb = new StringBuilder();
    if (neg) sb.Append('-');
    if (k <= n && n <= 21) { sb.Append(digits).Append('0', n - k); }
    else if (0 < n && n <= 21) { sb.Append(digits, 0, n).Append('.').Append(digits, n, k - n); }
    else if (-6 < n && n <= 0) { sb.Append("0.").Append('0', -n).Append(digits); }
    else {
      sb.Append(digits[0]);
      if (k > 1) sb.Append('.').Append(digits, 1, k - 1);
      int ex = n - 1;
      sb.Append('e').Append(ex >= 0 ? "+" : "-").Append(Math.Abs(ex));
    }
    return sb.ToString();
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
