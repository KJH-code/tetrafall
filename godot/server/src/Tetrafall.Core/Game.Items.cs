using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-items.js — 아이템·설치 블록·폭탄·투사체 (S1: 스냅샷·물리가 쓰는 부분. 나머지는 S4)
public sealed partial class Game
{
    // 손에 든 것으로 우클릭하면 생길 것 (화면 미리보기): { kind, ...plan } 또는 null
    public void AimPreview(JsonOut o, Player p)
    {
        if (p.bricks > 0) BrickPlanPreview(o, p);
        else if (p.bombs > 0) BombPlanPreview(o, p);
        else o.Null();
    }

    // 조종권 아이템이 나오는 판인지
    public bool ControlItemOn() => C.CONTROL_ITEM && mode != "master" && !sky;

    // 조종권이 필드·누군가의 손·조종 중인 블록 어딘가에 있음
    public bool ControlInPlay() => items.Any(it => it.type == "control") || Players().Any(p => p.hasControl) || pieces.Any(pc => pc.controller != null);

    // 다음 조종권·아이템까지 남은 ms (시계가 안 돌면 null)
    public (double? control, double? power) ItemTimers()
    {
        if (phase != "playing") return (null, null);
        int powerCount = items.Count(it => it.type != "control");
        return (
            !ControlItemOn() || ControlInPlay() ? null : Math.Max(0, controlItemNextAt - time),
            !C.ITEMS_ENABLED || powerCount >= ItemMax() ? null : Math.Max(0, powerItemNextAt - time));
    }

    public bool IsGhost(Player p) => time < p.ghostUntil;

    // 유령화가 끝났는데 블록 안이면 그 기둥 꼭대기로 밀어 올린다
    public void EjectFromBlocks(Player p)
    {
        for (int i = 0; i < H + 2; i++)
        {
            var hits = OverlappingSolid(Aabb(p));
            if (hits.Count == 0) return;
            double top = double.NegativeInfinity;
            foreach (var h in hits) if (h[2] + 1 > top) top = h[2] + 1;
            p.z = top;
            p.vz = 0;
        }
    }
}
