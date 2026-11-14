namespace Tetrafall.Core;

// 고도 전용 수치 (JS 에 없음 — shared/config.js 에서 만드는 Config.g.cs 와 따로): 서버 지키기
public static partial class C
{
    // |yaw| 이보다 크면 입력 무시 (NaN 처럼 예전 yaw 유지). JsMath 정밀 구간 1.6e6 (2^20·π/2) 안
    public const double INPUT_YAW_MAX = 1e6;
}
