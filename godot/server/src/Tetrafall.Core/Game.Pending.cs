using System.Text.Json;

namespace Tetrafall.Core;

// 방(Rooms, S6)이 부르는데 아직 안 옮긴 게임 함수 자리 (인터페이스만). 그 묶음을 옮기는 세션이 진짜를 만들고 여기서 지움
// (같은 이름이 두 곳이면 컴파일 에러 → 지울 곳을 알려 줌). 부르면 NotImplementedException → Rooms 가 그 방만 닫음 (서버는 계속)
public sealed partial class Game
{
    // S2 (game-pieces.js): 유령 투하. x·y 는 받은 값 그대로 (숫자 아닐 수 있음)
    public bool GhostDrop(int id, JsonElement? x, JsonElement? y) => throw Todo("ghostDrop (S2)");

    // S4 연습 (game-practice.js)
    public void StartPractice() => throw Todo("startPractice (S4 연습)");
    public void PracticeJoin(int id) => throw Todo("practiceJoin (S4 연습)");
    public bool PracticeSet(int id, string key, JsonElement? value) => throw Todo("practiceSet (S4 연습)");
    public Player? AddDummy(int id) => throw Todo("addDummy (S4 연습)");
    public bool RemoveDummy(double? id) => throw Todo("removeDummy (S4 연습)");
    public bool SetDummyDamage(double? id, JsonElement? damage) => throw Todo("setDummyDamage (S4 연습)");

    // S4 튜토리얼 (tutorial.js): 튜토리얼 방이면 game.tutorial 이 생김
    public void StartTutorial(int id) => throw Todo("startTutorial (S4 튜토리얼)");
    public Tutorial? tutorial;

    static NotImplementedException Todo(string what) => new($"아직 안 옮김: {what} — godot/PLAN.md");
}

// 튜토리얼 단계 (tutorial.js). TODO(S4 튜토리얼)
public sealed class Tutorial
{
    public void Skip() => throw new NotImplementedException("아직 안 옮김: tutorial.skip (S4 튜토리얼)");
}
