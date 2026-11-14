namespace Tetrafall.Core;

// 방 밸런스 표 (고도 판 전용 — shared/config.js 에 없음, gen-config 가 안 만듦. 층은 Tune.cs)
// 서버 방 (대전·연습·튜토리얼) 의 판만 이 표로 돎: Program.cs 가 Rooms 에 넘김 (TF_BALANCE=off 면 안 넘김 — ServerBalance.cs).
// sim (기본)·Trace·테스트가 만드는 Game·Rooms 는 표 없음 → 34판 해시·JS 정답 자료는 그대로. sim 은 --balance on 으로 켬
public static partial class C
{
    // 넉백 배율만 (kbTaken 받는·kbDealt 주는). skillCd·ultGain·dmgDealt·hpMult 는 안 넣음 — 클라 쿨 표시 (C.SKILL_CD_MS) 와 어긋나지 않게.
    // 탱크 (TANK_KB_TAKEN 0.92) 보다 덜 밀리는 캐릭터가 없게: 닌자 1.1 × 0.9 = 0.99, 사냥꾼·갈고리 0.95.
    // 근거: sim --rounds 1000 --players 2,4,8 --balance on, 시드 1·2·3 평균 ×기대 —
    //   대포수 1.24 · 광전사 1.14 · 건축가 1.01 · 탱크 0.99 · 바드 0.95 · 닌자 0.88 · 사냥꾼 0.86 · 갈고리 0.81 (최대−최소 0.43, 판 길이 중앙값 82초, 시간 초과 0).
    //   표 없음 (같은 옵션, 시드 1): 대포수 1.51 · 광전사 1.33 · … · 닌자 0.80 · 사냥꾼 0.72 · 갈고리 0.64 (최대−최소 0.87)
    public const string BALANCE = "cannon.kbDealt=0.85,berserker.kbDealt=0.9,berserker.kbTaken=1.1,ninja.kbTaken=0.9,ninja.kbDealt=1.1,hunter.kbTaken=0.95,hunter.kbDealt=1.15,hook.kbTaken=0.95,hook.kbDealt=1.2";

    // 표를 Tune 으로 (부를 때마다 새 객체)
    public static Tune BalanceTune() => Tune.Parse(BALANCE);
}
