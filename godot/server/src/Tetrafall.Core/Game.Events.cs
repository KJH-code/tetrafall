using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 돌발 이벤트 (고도 판 전용, 방 옵션 roundEvents — 기본 끔): 생존·킬 점수전 판 중에 EVENT_GAP_MS 마다 짧은 이벤트 하나 (한 판 안에서 직전과 다른 종류 — PickEventKind).
// 블록 폭우 (rain: 자동 블록이 상한을 넘겨 쏟아짐) · 돌풍 (wind: 필드 위 모두가 한쪽으로 밀림) · 보급 (supply: 아이템 몇 개) ·
// 저중력 (lowgrav: 높이 뛰고 맞으면 멀리 날아감) · 빙판 (ice: 땅에서 맞으면 멀리 미끄러짐). 저중력·빙판은 IntegratePlayer 가
// GravityMult·GroundDampMult 로 배율만 받음. 봇은 이 둘을 모름 (점프 도달·낙하 시간 추정은 평소 중력 그대로) — 판정 특혜 없음.
// 끄면 Tick 이 여기를 안 불러 rng 도 안 씀 → 예전 판 (34판 해시·JS 정답 자료) 과 글자까지 같음. 수치는 ConfigEvents.cs
public sealed partial class Game
{
    double evRoundStart = double.NaN; // 마지막으로 본 roundStartTime (바뀌면 새 판 — Game.Round.cs 를 안 고치려고 여기서 알아챔)
    public double evNextAt; // 다음 이벤트 시각
    public string? evKind; // 진행 중인 이벤트 (rain | wind | lowgrav | ice). 보급은 그 자리에서 끝나 안 남음
    public double evEndsAt;
    public XY? evDir; // 돌풍 방향 (단위 벡터)
    double evRainNextAt; // 블록 폭우: 다음 블록 시각
    string? evLastKind; // 이번 판에서 마지막으로 고른 종류 (보급 포함 — 보급 뒤엔 evKind 가 null 이라 따로). 새 판이면 null
    public string[] eventKinds = C.EVENT_KINDS; // 고를 종류 (기본 config 그대로 — 테스트가 1종·0종으로 바꿔 봄)

    static readonly Dictionary<string, string> EVENT_LOG = new()
    {
        ["rain"] = "블록 폭우",
        ["wind"] = "돌풍",
        ["supply"] = "보급",
        ["lowgrav"] = "저중력",
        ["ice"] = "빙판",
    };

    // 돌발 이벤트 켜고 끄기 (판 사이에만, 연습 방은 안 됨 — SetHpMode 와 같은 규칙)
    public bool SetRoundEvents(bool on)
    {
        if (InRound() || mode == "practice" || roundEvents == on) return false;
        roundEvents = on;
        Log($"[호스트] 돌발 이벤트 {(on ? "켬" : "끔")}");
        return true;
    }

    // 이 방 설정에서 돌발 이벤트가 실제로 도는지: 블록 마스터 (자동 블록 없음)·연습·튜토리얼은 켜 둬도 안 돎.
    // 판 단계는 안 봄 — 대기실 스냅샷 itemsEnabled (아이템 키 안내) 도 이 값을 씀
    public bool RoundEventsRun() => roundEvents && mode != "master" && mode != "practice" && tutorial == null;

    // 스냅샷에 실을 진행 중 이벤트가 있는지. evRoundStart 가 이번 판 것이어야 함 — 카운트다운 0 이면 새 판 첫 틱 전
    // 스냅샷에 지난 판 이벤트가 남던 것을 막음 (새 판인지는 틱 안 UpdateRoundEvents 만 알아챔)
    public bool RoundEventActive() => roundEvents && phase == "playing" && evRoundStart == roundStartTime && evKind != null && time < evEndsAt;

    // 저중력: 플레이어 중력 배율 (IntegratePlayer, 탱크 내려찍기 준비 중엔 안 곱함). 빙판: 땅 넉백 감쇠 배율 (IntegratePlayer,
    // 땅에 섰고 맞은 넉백 kbHit 일 때만 — 대시·대포 반동은 그대로). 아니면 1.
    // evKind 만 보면 안 됨 — UpdateRoundEvents 는 판이 끝난 틱에 바로 돌아가 evKind 가 결과·대기실·다음 판 첫 틱까지 남음.
    // RoundEventActive 가 판 단계·이번 판 것인지·남은 시간까지 봄
    public double GravityMult() => evKind == "lowgrav" && RoundEventActive() ? C.EVENT_LOWGRAV_G : 1;
    public double GroundDampMult() => evKind == "ice" && RoundEventActive() ? C.EVENT_ICE_DAMP : 1;

    // 이벤트 종류 고르기 (rng 한 번 = r): 판 첫 이벤트 (last null) 는 5종 중 floor(r×5), 그 뒤로는 직전 종류를 뺀 4종 (원래 순서) 중 floor(r×4)
    // — 한 판 안에서 같은 종류가 연이어 나오지 않음. kinds 를 줄인 config 도 틱 예외 (방 Crash) 없이: 1종이면 뺄 수 없어 직전 그대로,
    // 0종이면 null (이벤트 없음). r 은 어느 경우든 부르는 쪽이 한 번만 뽑음 → 5종 판의 rng 흐름·해시 그대로
    public static string? PickEventKind(double r, string? last) => PickEventKind(r, last, C.EVENT_KINDS);

    public static string? PickEventKind(double r, string? last, string[] kinds)
    {
        if (kinds.Length == 0) return null;
        var pool = last == null ? kinds : Array.FindAll(kinds, k => k != last);
        if (pool.Length == 0) return last;
        return pool[(int)Math.Floor(r * pool.Length)];
    }

    // 틱마다 (roundEvents 켰을 때만 Tick 이 부름): 시각이 되면 이벤트 하나 고르고, 진행 중인 것을 돌림
    public void UpdateRoundEvents(double dtMs)
    {
        if (phase != "playing") return; // 이 틱에 판이 끝남
        if (roundStartTime != evRoundStart)
        {
            // 새 판: 첫 이벤트 시각을 잡고 지난 판 것을 비움
            evRoundStart = roundStartTime;
            evNextAt = roundStartTime + C.EVENT_FIRST_MS;
            evKind = null;
            evDir = null;
            evLastKind = null;
        }
        if (!RoundEventsRun()) return; // 블록 마스터·연습·튜토리얼은 안 돎
        if (evKind != null && time >= evEndsAt)
        {
            evKind = null;
            evDir = null;
        }
        if (time >= evNextAt)
        {
            evNextAt += C.EVENT_GAP_MS;
            // null = 고를 종류가 없음 (config 를 비움): 이벤트 없이 판은 그대로 (rng 는 그래도 한 번)
            if (PickEventKind(rng(), evLastKind, eventKinds) is string kind)
            {
                evLastKind = kind;
                XY? dir = null;
                if (kind == "wind")
                {
                    var (dx, dy) = C.EVENT_WIND_DIRS[(int)Math.Floor(rng() * C.EVENT_WIND_DIRS.Length)];
                    dir = new XY(dx, dy);
                }
                StartRoundEvent(kind, dir);
            }
        }
        if (evKind == "rain")
        {
            // 블록 폭우: 동시 상한 (TargetConcurrent) 과 상관없이 자동 블록을 하나씩 더. 하늘 계단 판에서도 같음
            // (하늘 블록이 없는 기둥에 보통 자동 블록으로 떨어져 착지 — RoundEventTests 가 확인). 자리가 없으면 그 박자는 건너뜀
            while (time >= evRainNextAt && evRainNextAt < evEndsAt)
            {
                evRainNextAt += C.EVENT_RAIN_GAP_MS;
                SpawnAuto();
            }
        }
        else if (evKind == "wind" && evDir != null)
        {
            // 돌풍: 넉백 속도에 조금씩 더함. 넉백은 틱마다 exp(-k·dt) 로 줄어드니 (땅 6, 공중 1.2) k 를 곱해 넣어야
            // 땅에서도 공중에서도 흐르는 빠르기가 약 EVENT_WIND_SPEED 로 같아짐 (이벤트는 한 번에 하나라 빙판 배율과 안 겹침).
            // 히트스톱 (freezeUntil) 중인 사람은 건너뜀: IntegratePlayer 가 멈춤 동안 감쇠 전에 돌아가서 그동안 더한 바람이 안 줄고 쌓임
            double dt = dtMs / 1000;
            foreach (var p in Players())
            {
                if (!OnField(p) || time < p.freezeUntil) continue;
                double k = p.grounded ? C.KB_DAMPING_GROUND : C.KB_DAMPING_AIR;
                p.kbx += evDir.x * C.EVENT_WIND_SPEED * k * dt;
                p.kby += evDir.y * C.EVENT_WIND_SPEED * k * dt;
            }
        }
    }

    // 이벤트 하나 시작 (UpdateRoundEvents 가 고른 뒤 부름. 테스트는 종류를 정해 바로 부름). 진행 중이던 것은 새것으로 바뀜.
    // dir: 돌풍 방향 (단위 벡터, 돌풍일 때만)
    public void StartRoundEvent(string kind, XY? dir = null)
    {
        evKind = null;
        evDir = null;
        switch (kind)
        {
            case "rain":
                evKind = kind;
                evEndsAt = time + C.EVENT_RAIN_MS;
                evRainNextAt = time; // 첫 블록은 바로
                Emit(o => o.P("type", "roundEvent").P("kind", kind).P("ms", C.EVENT_RAIN_MS));
                Log($"  [이벤트] {EVENT_LOG[kind]} {JsNumber.ToJs(C.EVENT_RAIN_MS / 1000)}초");
                break;
            case "lowgrav":
            case "ice":
            {
                // 저중력·빙판: 시간 동안 배율만 (GravityMult·GroundDampMult). 틱마다 할 일은 없음
                double ms = kind == "lowgrav" ? C.EVENT_LOWGRAV_MS : C.EVENT_ICE_MS;
                evKind = kind;
                evEndsAt = time + ms;
                Emit(o => o.P("type", "roundEvent").P("kind", kind).P("ms", ms));
                Log($"  [이벤트] {EVENT_LOG[kind]} {JsNumber.ToJs(ms / 1000)}초");
                break;
            }
            case "wind":
            {
                var d = dir ?? new XY(1, 0);
                evKind = kind;
                evDir = d;
                evEndsAt = time + C.EVENT_WIND_MS;
                Emit(o =>
                {
                    o.P("type", "roundEvent").P("kind", kind).P("ms", C.EVENT_WIND_MS).Key("dir");
                    WriteXY(o, d);
                });
                string axis = d.x != 0 ? (d.x > 0 ? "+x" : "-x") : (d.y > 0 ? "+y" : "-y");
                Log($"  [이벤트] {EVENT_LOG[kind]} {axis} {JsNumber.ToJs(C.EVENT_WIND_MS / 1000)}초");
                break;
            }
            case "supply":
            {
                // 보급: ITEM_POOL 에서 무작위로 EVENT_SUPPLY_COUNT 개 (줍기는 예전 PickupItems 그대로). 자리를 못 찾은 것은 빠짐
                int placed = 0;
                for (int i = 0; i < C.EVENT_SUPPLY_COUNT; i++)
                {
                    if (SpawnItem(C.ITEM_POOL[(int)Math.Floor(rng() * C.ITEM_POOL.Length)])) placed++;
                }
                Emit(o => o.P("type", "roundEvent").P("kind", kind).P("ms", 0));
                Log($"  [이벤트] {EVENT_LOG[kind]} {placed}개");
                break;
            }
        }
    }
}
