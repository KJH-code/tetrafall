namespace Tetrafall.Core;

// 돌발 이벤트 수치 (고도 판 전용 — shared/config.js 에 없음, gen-config 가 안 만듦. 규칙은 Game.Events.cs)
public static partial class C
{
    public const double EVENT_FIRST_MS = 20000; // 판 시작 뒤 첫 이벤트까지
    public const double EVENT_GAP_MS = 25000; // 이벤트 사이 간격 (시작 → 다음 시작)
    public static readonly string[] EVENT_KINDS = { "rain", "wind", "supply", "lowgrav", "ice", "bolt" }; // 블록 폭우 · 돌풍 · 보급 · 저중력 · 빙판 · 번개
    public const double EVENT_RAIN_MS = 6000; // 블록 폭우: 지속 시간
    public const double EVENT_RAIN_GAP_MS = 800; // 블록 폭우: 자동 블록 하나씩 더 떨어지는 간격 (동시 상한 무시)
    public const double EVENT_WIND_MS = 5000; // 돌풍: 지속 시간
    public const double EVENT_WIND_SPEED = 1.0; // 돌풍: 밀려가는 빠르기 (칸/초, MOVE_SPEED 4.5 의 약 22%)
    public static readonly (double x, double y)[] EVENT_WIND_DIRS = { (1, 0), (-1, 0), (0, 1), (0, -1) }; // 돌풍 방향 후보 (+x, -x, +y, -y)
    public const double EVENT_SUPPLY_COUNT = 2; // 보급: 아이템 수 (ITEM_POOL 에서 무작위)
    public const double EVENT_LOWGRAV_MS = 6000; // 저중력: 지속 시간
    // 저중력: 플레이어 중력 배율 (GRAVITY 20 → 9, 바드 활공 배율과 곱해짐). 점프 꼭짓점 약 2.3배 (연속식 1/G = 2.22,
    // 30Hz 틱 적분 2.34), 맞고 뜬 사람도 오래 떠서 멀리 날아감 (공중 넉백 감쇠는 그대로)
    public const double EVENT_LOWGRAV_G = 0.45;
    public const double EVENT_ICE_MS = 6000; // 빙판: 지속 시간
    // 빙판: 땅에 선 사람의 맞은 넉백 감쇠 배율 (KB_DAMPING_GROUND 6 → 1.8). 맞으면 띄워지므로 착지 뒤 남은 미끄러짐에만 걸림 —
    // 땅 구간은 약 3.3배 (1/0.3), 실제로 맞은 거리는 약 1.2~2배 (밀치기 0% 약 1.8). 걷기·대시·대포 반동은 그대로 (Player.kbHit)
    public const double EVENT_ICE_DAMP = 0.3;
    // 번개 (c9): 차례마다 필드 위 사람 몇 명의 발밑에 예고 고리 → EVENT_BOLT_WARN_MS 뒤 그 자리에 떨어짐 (자리는 예고 때 고정 — 비키면 안 맞음)
    public const double EVENT_BOLT_MS = 6000; // 지속 시간
    public const double EVENT_BOLT_GAP_MS = 1500; // 차례 간격: 시작 순간부터 0·1.5·3.0·4.5초 (4번)
    public const double EVENT_BOLT_SHARE = 0.5; // 차례마다 대상 수 = 필드 위 사람 수 × 이 값 올림 (최소 1)
    public const double EVENT_BOLT_WARN_MS = 1200; // 예고 → 떨어짐
    public const double EVENT_BOLT_RADIUS = 1.2; // 맞는 범위: 수평 반지름 (칸, 몸 가운데까지)
    public const double EVENT_BOLT_HEIGHT = 3; // 맞는 범위: 예고 바닥과 발 높이 차 (칸)
    public const double EVENT_BOLT_DAMAGE = 15; // 피해 %
    public const double EVENT_BOLT_STUN_MS = 700; // 경직
    public const double EVENT_BOLT_KB = 3; // 넉백 (바깥쪽, 피해 % 배율을 받음)
    public const double EVENT_BOLT_UP = 7; // 띄움
    public const double EVENT_BOLT_BOT_PAD = 0.3; // 봇이 피하는 칸: 예고 가운데에서 반지름 + 이 값 안에 칸 가운데가 드는 칸 (Bot.VisibleDangers)
}
