// V8(node) 과 비트까지 같은 수학 함수. System.Math 의 Sin·Cos·Exp·Atan2 는 V8 과 마지막 자리가 3~18% 다르고 hypot 은 38% 달라
// 판 해시가 갈라짐 (2026-10-31 100만 개 비교). 그래서 V8 이 쓰는 fdlibm (src/base/ieee754.cc 원본) 을 옮김 → 100만 개 전부 같음.
// 규칙 코드는 Math.Sin 대신 JsMath.Sin 을 씀 (Floor·Abs·Max·Min·Sqrt 는 System.Math 가 같음). Round 는 JS 규칙 (x.5 는 위로)
namespace Tetrafall.Core.Js;

public static class JsMath
{
  static double FromWords(uint hi, uint lo) => BitConverter.Int64BitsToDouble((long)(((ulong)hi << 32) | lo));
  static int Hi(double x) => (int)(BitConverter.DoubleToInt64Bits(x) >> 32);
  static uint Lo(double x) => (uint)BitConverter.DoubleToInt64Bits(x);
  static double WithLo(double x, uint lo) => BitConverter.Int64BitsToDouble((BitConverter.DoubleToInt64Bits(x) & unchecked((long)0xFFFFFFFF00000000)) | lo);
  static double WithHi(double x, int hi) => BitConverter.Int64BitsToDouble(((long)hi << 32) | (BitConverter.DoubleToInt64Bits(x) & 0xFFFFFFFFL));

  // ---- k_sin / k_cos ----
  const double S1 = -1.66666666666666324348e-01, S2 = 8.33333333332248946124e-03, S3 = -1.98412698298579493134e-04,
    S4 = 2.75573137070700676789e-06, S5 = -2.50507602534068634195e-08, S6 = 1.58969099521155010221e-10;
  static double KSin(double x, double y, int iy) {
    if ((Hi(x) & 0x7fffffff) < 0x3e400000 && (int)x == 0) return x; // |x| < 2^-27 (±0 은 부호 그대로)
    double z = x * x, v = z * x;
    double r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
    if (iy == 0) return x + v * (S1 + z * r);
    return x - ((z * (0.5 * y - v * r) - y) - v * S1);
  }
  const double C1 = 4.16666666666666019037e-02, C2 = -1.38888888888741095749e-03, C3 = 2.48015872894767294178e-05,
    C4 = -2.75573143513906633035e-07, C5 = 2.08757232129817482790e-09, C6 = -1.13596475577881948265e-11;
  static double KCos(double x, double y) {
    int ix = Hi(x) & 0x7fffffff;
    if (ix < 0x3e400000 && (int)x == 0) return 1.0;
    double z = x * x;
    double r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
    if (ix < 0x3FD33333) return 1.0 - (0.5 * z - (z * r - x * y));
    double qx = ix > 0x3fe90000 ? 0.28125 : FromWords((uint)(ix - 0x00200000), 0);
    double hz = 0.5 * z - qx, a = 1.0 - qx;
    return a - (hz - (z * r - x * y));
  }

  // ---- rem_pio2 (|x| < 2^20·π/2 만: 게임 각도는 작음) ----
  const double invpio2 = 6.36619772367581382433e-01, pio2_1 = 1.57079632673412561417e+00, pio2_1t = 6.07710050650619224932e-11,
    pio2_2 = 6.07710050630396597660e-11, pio2_2t = 2.02226624879595063154e-21, pio2_3 = 2.02226624871116645580e-21, pio2_3t = 8.47842766036889956997e-32;
  static int RemPio2(double x, out double y0, out double y1) {
    int hx = Hi(x), ix = hx & 0x7fffffff;
    if (ix <= 0x3fe921fb) { y0 = x; y1 = 0; return 0; }
    if (ix < 0x4002d97c) {
      if (hx > 0) {
        double z = x - pio2_1;
        if (ix != 0x3ff921fb) { y0 = z - pio2_1t; y1 = (z - y0) - pio2_1t; }
        else { z -= pio2_2; y0 = z - pio2_2t; y1 = (z - y0) - pio2_2t; }
        return 1;
      } else {
        double z = x + pio2_1;
        if (ix != 0x3ff921fb) { y0 = z + pio2_1t; y1 = (z - y0) + pio2_1t; }
        else { z += pio2_2; y0 = z + pio2_2t; y1 = (z - y0) + pio2_2t; }
        return -1;
      }
    }
    if (ix <= 0x413921fb) {
      double t = Math.Abs(x);
      int n = (int)(t * invpio2 + 0.5);
      double fn = n;
      double r = t - fn * pio2_1, w = fn * pio2_1t;
      int j = ix >> 20;
      y0 = r - w;
      int i = j - ((Hi(y0) >> 20) & 0x7ff);
      if (i > 16) {
        t = r; w = fn * pio2_2; r = t - w; w = fn * pio2_2t - ((t - r) - w); y0 = r - w;
        i = j - ((Hi(y0) >> 20) & 0x7ff);
        if (i > 49) { t = r; w = fn * pio2_3; r = t - w; w = fn * pio2_3t - ((t - r) - w); y0 = r - w; }
      }
      y1 = (r - y0) - w;
      if (hx < 0) { y0 = -y0; y1 = -y1; return -n; }
      return n;
    }
    throw new NotSupportedException("JsMath: 각도가 너무 큼");
  }

  public static double Sin(double x) {
    int ix = Hi(x) & 0x7fffffff;
    if (ix <= 0x3fe921fb) return KSin(x, 0, 0);
    if (ix >= 0x7ff00000) return double.NaN;
    int n = RemPio2(x, out var y0, out var y1);
    switch (n & 3) { case 0: return KSin(y0, y1, 1); case 1: return KCos(y0, y1); case 2: return -KSin(y0, y1, 1); default: return -KCos(y0, y1); }
  }
  public static double Cos(double x) {
    int ix = Hi(x) & 0x7fffffff;
    if (ix <= 0x3fe921fb) return KCos(x, 0);
    if (ix >= 0x7ff00000) return double.NaN;
    int n = RemPio2(x, out var y0, out var y1);
    switch (n & 3) { case 0: return KCos(y0, y1); case 1: return -KSin(y0, y1, 1); case 2: return -KCos(y0, y1); default: return KSin(y0, y1, 1); }
  }

  // ---- exp ----
  static readonly double[] halF = { 0.5, -0.5 }, ln2HI = { 6.93147180369123816490e-01, -6.93147180369123816490e-01 }, ln2LO = { 1.90821492927058770002e-10, -1.90821492927058770002e-10 };
  const double o_threshold = 7.09782712893383973096e+02, u_threshold = -7.45133219101941108420e+02, invln2 = 1.44269504088896338700e+00,
    P1 = 1.66666666666666019037e-01, P2 = -2.77777777770155933842e-03, P3 = 6.61375632143793436117e-05, P4 = -1.65339022054652515390e-06, P5 = 4.13813679705723846039e-08,
    E = 2.718281828459045, two1023 = 8.988465674311579539e307, twom1000 = 9.33263618503218878990e-302, huge = 1.0e+300;
  public static double Exp(double x) {
    double hi = 0, lo = 0, c, t, twopk; int k = 0;
    uint hx = (uint)Hi(x); int xsb = (int)((hx >> 31) & 1); hx &= 0x7fffffff;
    if (hx >= 0x40862E42) {
      if (hx >= 0x7ff00000) { if (((hx & 0xfffff) | Lo(x)) != 0) return x + x; return xsb == 0 ? x : 0.0; }
      if (x > o_threshold) return double.PositiveInfinity;
      if (x < u_threshold) return 0;
    }
    if (hx > 0x3fd62e42) {
      if (hx < 0x3FF0A2B2) {
        if (x == 1.0) return E;
        hi = x - ln2HI[xsb]; lo = ln2LO[xsb]; k = 1 - xsb - xsb;
      } else {
        k = (int)(invln2 * x + halF[xsb]); t = k;
        hi = x - t * ln2HI[0]; lo = t * ln2LO[0];
      }
      x = hi - lo;
    } else if (hx < 0x3e300000) {
      if (huge + x > 1.0) return 1.0 + x;
    } else k = 0;
    t = x * x;
    twopk = k >= -1021 ? FromWords((uint)(0x3ff00000 + (k << 20)), 0) : FromWords((uint)(0x3ff00000 + ((k + 1000) << 20)), 0);
    c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    if (k == 0) return 1.0 - ((x * c) / (c - 2.0) - x);
    double y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi);
    if (k >= -1021) { if (k == 1024) return y * 2.0 * two1023; return y * twopk; }
    return y * twopk * twom1000;
  }

  // ---- atan / atan2 ----
  static readonly double[] atanhi = { 4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01, 1.57079632679489655800e+00 };
  static readonly double[] atanlo = { 2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17, 6.12323399573676603587e-17 };
  static readonly double[] aT = { 3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01, -1.11111104054623557880e-01, 9.09088713343650656196e-02,
    -7.69187620504482999495e-02, 6.66107313738753120669e-02, -5.83357013379057348645e-02, 4.97687799461593236017e-02, -3.65315727442169155270e-02, 1.62858201153657823623e-02 };
  public static double Atan(double x) {
    int hx = Hi(x), ix = hx & 0x7fffffff, id;
    if (ix >= 0x44100000) {
      if (ix > 0x7ff00000 || (ix == 0x7ff00000 && Lo(x) != 0)) return x + x;
      return hx > 0 ? atanhi[3] + atanlo[3] : -atanhi[3] - atanlo[3];
    }
    if (ix < 0x3fdc0000) {
      if (ix < 0x3e400000) { if (huge + x > 1.0) return x; }
      id = -1;
    } else {
      x = Math.Abs(x);
      if (ix < 0x3ff30000) {
        if (ix < 0x3fe60000) { id = 0; x = (2.0 * x - 1.0) / (2.0 + x); } else { id = 1; x = (x - 1.0) / (x + 1.0); }
      } else {
        if (ix < 0x40038000) { id = 2; x = (x - 1.5) / (1.0 + 1.5 * x); } else { id = 3; x = -1.0 / x; }
      }
    }
    double z = x * x, w = z * z;
    double s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    double s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0) return x - x * (s1 + s2);
    z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x);
    return hx < 0 ? -z : z;
  }
  const double tiny = 1.0e-300, pi_o_4 = 7.8539816339744827900E-01, pi_o_2 = 1.5707963267948965580E+00, pi = 3.1415926535897931160E+00, pi_lo = 1.2246467991473531772E-16;
  public static double Atan2(double y, double x) {
    int hx = Hi(x), ix = hx & 0x7fffffff; uint lx = Lo(x);
    int hy = Hi(y), iy = hy & 0x7fffffff; uint ly = Lo(y);
    if (((uint)ix | ((lx | (uint)-(int)lx) >> 31)) > 0x7ff00000 || ((uint)iy | ((ly | (uint)-(int)ly) >> 31)) > 0x7ff00000) return x + y;
    if (((hx - 0x3ff00000) | (int)lx) == 0) return Atan(y);
    int m = ((hy >> 31) & 1) | ((hx >> 30) & 2);
    if ((iy | (int)ly) == 0) { switch (m) { case 0: case 1: return y; case 2: return pi + tiny; default: return -pi - tiny; } }
    if ((ix | (int)lx) == 0) return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny;
    if (ix == 0x7ff00000) {
      if (iy == 0x7ff00000) { switch (m) { case 0: return pi_o_4 + tiny; case 1: return -pi_o_4 - tiny; case 2: return 3.0 * pi_o_4 + tiny; default: return -3.0 * pi_o_4 - tiny; } }
      switch (m) { case 0: return 0.0; case 1: return -0.0; case 2: return pi + tiny; default: return -pi - tiny; }
    }
    if (iy == 0x7ff00000) return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny;
    int k = (iy - ix) >> 20;
    double z;
    if (k > 60) { z = pi_o_2 + 0.5 * pi_lo; m &= 1; }
    else if (hx < 0 && k < -60) z = 0.0;
    else z = Atan(Math.Abs(y / x));
    switch (m) { case 0: return z; case 1: return -z; case 2: return pi - (z - pi_lo); default: return (z - pi_lo) - pi; }
  }

  // ---- V8 Math.hypot (builtins/math.tq): 가장 큰 값으로 나눠 Kahan 합 ----
  public static double Hypot(double a, double b) {
    a = Math.Abs(a); b = Math.Abs(b);
    if (double.IsInfinity(a) || double.IsInfinity(b)) return double.PositiveInfinity;
    if (double.IsNaN(a) || double.IsNaN(b)) return double.NaN;
    double max = Math.Max(a, b);
    if (max == 0) return 0;
    double sum = 0, comp = 0;
    double n = a / max, summand = n * n - comp, prelim = sum + summand;
    comp = (prelim - sum) - summand; sum = prelim;
    n = b / max; summand = n * n - comp; prelim = sum + summand;
    sum = prelim;
    return Math.Sqrt(sum) * max;
  }

  // 3개짜리 (봇 시선·사냥꾼 사격 거리)
  public static double Hypot(double a, double b, double c) {
    a = Math.Abs(a); b = Math.Abs(b); c = Math.Abs(c);
    if (double.IsInfinity(a) || double.IsInfinity(b) || double.IsInfinity(c)) return double.PositiveInfinity;
    if (double.IsNaN(a) || double.IsNaN(b) || double.IsNaN(c)) return double.NaN;
    double max = Math.Max(Math.Max(a, b), c);
    if (max == 0) return 0;
    double sum = 0, comp = 0;
    foreach (double v in (ReadOnlySpan<double>)[a, b, c]) {
      double n = v / max, summand = n * n - comp, prelim = sum + summand;
      comp = (prelim - sum) - summand; sum = prelim;
    }
    return Math.Sqrt(sum) * max;
  }

  // JS Math.round: x.5 는 +∞ 쪽 (C# Math.Round 는 짝수 쪽이라 다름), (-0.5, 0) 은 -0
  public static double Round(double x) {
    if (double.IsNaN(x) || double.IsInfinity(x)) return x;
    double r = Math.Floor(x);
    if (x - r >= 0.5) r += 1;
    return r == 0 ? Math.CopySign(0.0, x) : r;
  }

  // JS Math.sign (NaN·±0 그대로)
  public static double Sign(double x) => double.IsNaN(x) || x == 0 ? x : x > 0 ? 1 : -1;

  // JS ToInt32 (x | 0): 소수 버리고 2^32 로 감음. C# (int)x 는 범위 밖이면 다름
  public static int ToInt32(double x) {
    if (double.IsNaN(x) || double.IsInfinity(x)) return 0;
    double t = Math.Truncate(x) % 4294967296.0;
    if (t < 0) t += 4294967296.0;
    return unchecked((int)(uint)t);
  }

  // JS ToUint32 (x >>> 0)
  public static uint ToUint32(double x) => unchecked((uint)ToInt32(x));
}
