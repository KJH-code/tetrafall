namespace Tetrafall.Core;

// 플레이어 필드 중 연습·허수아비 (S4, game-practice.js) — addPlayer 에 없고 연습 판에서 생김
public sealed partial class Player
{
    public XY? home; // 연습: 제자리 (허수아비 = 놓은 자리, 사람 = 처음 자리)
    public double practiceDamage; // 연습: 내 피해 % 설정값
    public double dummyDamage; // 허수아비 피해 % 설정값
    public DummyCombo? combo; // 허수아비 지금 콤보 기록
    public ComboOut? lastCombo; // 허수아비 마지막 콤보 기록
    public double prevX, prevY, prevZ, prevDamage, prevCombo; // 허수아비 앞 틱 값 (맞음 판정)
}

// 허수아비 콤보 기록 { active, hits, damage, dist, height, sx, sy, sz, dmg0 }
public sealed class DummyCombo
{
    public bool active;
    public double hits, damage, dist, height, sx, sy, sz, dmg0;
}

// comboOut: 보낼 값 { hits, damage, dist, height } (dist·height 는 소수 둘째 자리)
public sealed record ComboOut(double hits, double damage, double dist, double height)
{
    public static ComboOut Of(DummyCombo c) => new(c.hits, c.damage, Js.JsMath.Round(c.dist * 100) / 100, Js.JsMath.Round(Math.Max(0, c.height) * 100) / 100);

    public void WriteFields(Js.JsonOut o) => o.P("hits", hits).P("damage", damage).P("dist", dist).P("height", height);
}

// 연습 토글 (방 전체) — 스냅샷 practice 에 이 순서로
public sealed class PracticeToggles
{
    public bool noCooldown, fullUlt, noBlocks = true, noDeath = true;
}
