using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 돌발 이벤트 (고도 판 전용, 방 옵션 roundEvents — 기본 끔): 생존·킬 점수전 판 중에 EVENT_GAP_MS 마다 짧은 이벤트 하나.
// 블록 폭우 (rain: 자동 블록이 상한을 넘겨 쏟아짐) · 돌풍 (wind: 필드 위 모두가 한쪽으로 밀림) · 보급 (supply: 아이템 몇 개).
// 끄면 Tick 이 여기를 안 불러 rng 도 안 씀 → 예전 판 (34판 해시·JS 정답 자료) 과 글자까지 같음. 수치는 ConfigEvents.cs
public sealed partial class Game
{
    double evRoundStart = double.NaN; // 마지막으로 본 roundStartTime (바뀌면 새 판 — Game.Round.cs 를 안 고치려고 여기서 알아챔)
    public double evNextAt; // 다음 이벤트 시각
    public string? evKind; // 진행 중인 이벤트 (rain | wind). 보급은 그 자리에서 끝나 안 남음
    public double evEndsAt;
    public XY? evDir; // 돌풍 방향 (단위 벡터)
    double evRainNextAt; // 블록 폭우: 다음 블록 시각

    static readonly Dictionary<string, string> EVENT_LOG = new() { ["rain"] = "블록 폭우", ["wind"] = "돌풍", ["supply"] = "보급" };

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
            string kind = C.EVENT_KINDS[(int)Math.Floor(rng() * C.EVENT_KINDS.Length)];
            XY? dir = null;
            if (kind == "wind")
            {
                var (dx, dy) = C.EVENT_WIND_DIRS[(int)Math.Floor(rng() * C.EVENT_WIND_DIRS.Length)];
                dir = new XY(dx, dy);
            }
            StartRoundEvent(kind, dir);
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
            // 땅에서도 공중에서도 흐르는 빠르기가 약 EVENT_WIND_SPEED 로 같아짐.
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
