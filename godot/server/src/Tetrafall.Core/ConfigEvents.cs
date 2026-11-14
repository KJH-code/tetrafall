namespace Tetrafall.Core;

// 돌발 이벤트 수치 (고도 판 전용 — shared/config.js 에 없음, gen-config 가 안 만듦. 규칙은 Game.Events.cs)
public static partial class C
{
    public const double EVENT_FIRST_MS = 20000; // 판 시작 뒤 첫 이벤트까지
    public const double EVENT_GAP_MS = 25000; // 이벤트 사이 간격 (시작 → 다음 시작)
    public static readonly string[] EVENT_KINDS = { "rain", "wind", "supply" }; // 블록 폭우 · 돌풍 · 보급
    public const double EVENT_RAIN_MS = 6000; // 블록 폭우: 지속 시간
    public const double EVENT_RAIN_GAP_MS = 800; // 블록 폭우: 자동 블록 하나씩 더 떨어지는 간격 (동시 상한 무시)
    public const double EVENT_WIND_MS = 5000; // 돌풍: 지속 시간
    public const double EVENT_WIND_SPEED = 1.0; // 돌풍: 밀려가는 빠르기 (칸/초, MOVE_SPEED 4.5 의 약 22%)
    public static readonly (double x, double y)[] EVENT_WIND_DIRS = { (1, 0), (-1, 0), (0, 1), (0, -1) }; // 돌풍 방향 후보 (+x, -x, +y, -y)
    public const double EVENT_SUPPLY_COUNT = 2; // 보급: 아이템 수 (ITEM_POOL 에서 무작위)
}
