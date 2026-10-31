namespace Tetrafall.Core;

// 플레이어 필드 중 대기실·재접속 (S6, Game.Players.cs) 이 더한 것. Player.cs 는 판 묶음 쪽 (A1) 이라 충돌이 안 나게 따로 둠.
// 같은 필드를 판 묶음이 Player.cs 에 만들면 여기서 지움
public sealed partial class Player
{
    public PlayerInput input = new(); // 지금 누르고 있는 이동 입력 (setAway 복귀 때 멈춤). TODO(S1 입력): 나머지 입력 필드
}

// JS p.input
public sealed class PlayerInput
{
    public double fwd, strafe;
    public bool jump;
}
