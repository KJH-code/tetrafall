namespace Tetrafall.Core;

// 방 밸런스 표 (고도 판 전용 — shared/config.js 에 없음, gen-config 가 안 만듦. 층은 Tune.cs)
// 서버 방 (대전·연습·튜토리얼) 의 판만 이 표로 돎 (킬 점수전 판은 BALANCE_KILLS 를 덮어서): Program.cs 가 Rooms 에 넘김 (TF_BALANCE=off 면 안 넘김 — ServerBalance.cs).
// sim (기본)·Trace·테스트가 만드는 Game·Rooms 는 표 없음 → 34판 해시·JS 정답 자료는 그대로. sim 은 --balance on 으로 켬
public static partial class C
{
    // 넉백 배율만 (kbTaken 받는·kbDealt 주는). skillCd·ultGain·dmgDealt·hpMult 는 안 넣음 — 클라 쿨 표시 (C.SKILL_CD_MS) 와 어긋나지 않게.
    // 탱크 (TANK_KB_TAKEN 0.92) 보다 덜 밀리는 캐릭터가 없게: 닌자 1.1 × 0.9 = 0.99, 사냥꾼·갈고리 0.95.
    // 근거: sim --rounds 1000 --players 2,4,8 --balance on, 시드 1·2·3 평균 ×기대 —
    //   대포수 1.24 · 광전사 1.14 · 건축가 1.01 · 탱크 0.99 · 바드 0.95 · 닌자 0.88 · 사냥꾼 0.86 · 갈고리 0.81 (최대−최소 0.43, 판 길이 중앙값 82초, 시간 초과 0).
    //   표 없음 (같은 옵션, 시드 1): 대포수 1.51 · 광전사 1.33 · … · 닌자 0.80 · 사냥꾼 0.72 · 갈고리 0.64 (최대−최소 0.87)
    public const string BALANCE = "cannon.kbDealt=0.85,berserker.kbDealt=0.9,berserker.kbTaken=1.1,ninja.kbTaken=0.9,ninja.kbDealt=1.1,hunter.kbTaken=0.95,hunter.kbDealt=1.15,hook.kbTaken=0.95,hook.kbDealt=1.2";

    // 킬 점수전 덮기 (Tune 모드 덮기 — 킬 점수전 판에서만 위 표의 같은 캐릭터·키를 이 값으로 바꿈, 곱하지 않음). kbDealt 만 — 위와 같은 까닭 (클라 쿨 표시).
    // 생존은 오래 버티는 쪽 (탱크·건축가·광전사) 이 유리하지만 킬 점수전은 부활이 있어 남을 떨어뜨리는 힘이 승패 — 그래서 주는 넉백만 다시 맞춤.
    // 근거: 정찰 sim --rounds 300 --players 4,8 --mode kills --balance on, 시드 1·2·3 평균 ×기대 —
    //   표 없음 (BALANCE 만): 건축가 2.22 · 광전사 1.65 · 대포수 1.02 · 탱크 1.00 · 갈고리 0.83 · 사냥꾼 0.48 · 바드 0.42 · 닌자 0.32 (최대−최소 1.91)
    //   이 표: 광전사 1.25 · 건축가 1.11 · 탱크 1.11 · 갈고리 0.99 · 대포수 0.98 · 바드 0.91 · 사냥꾼 0.85 · 닌자 0.81 (최대−최소 0.44, 판 길이 중앙값 137.5~140.0초, 시간 초과 0)
    //   봇끼리 낸 값이라 사람 손 (콤보·피하기·자리 잡기) 에서는 다를 수 있음 — 플레이테스트 로그 (킬 점수전 캐릭터별) 로 다시 볼 것
    public const string BALANCE_KILLS = "berserker.kbDealt=0.8,builder.kbDealt=0.75,ninja.kbDealt=1.6,bard.kbDealt=1.45,hunter.kbDealt=1.45,hook.kbDealt=1.25";

    // 표를 Tune 으로 (부를 때마다 새 객체): BALANCE 가 기본, BALANCE_KILLS 는 kills 모드 덮기
    public static Tune BalanceTune()
    {
        var t = Tune.Parse(BALANCE);
        var kills = Tune.Parse(BALANCE_KILLS);
        foreach (var key in Tune.KEYS) foreach (var (c, x) in kills.Table(key)!) t.SetMode("kills", c, key, x);
        return t;
    }
}
