using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// 아직 안 옮긴 메서드 (부르면 NotImplementedException). 옮긴 묶음 세션이 여기서 지우고 Game.<묶음>.cs 에 진짜를 넣음.
// 괄호 = 옮길 작업 (godot/PLAN.md 5절)
public sealed partial class Game
{
    static Exception Todo(string what) => new NotImplementedException($"아직 안 옮김: {what} (godot/PLAN.md)");
}
