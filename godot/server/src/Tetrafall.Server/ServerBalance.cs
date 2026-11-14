using Tetrafall.Core;

namespace Tetrafall.Server;

// 서버 방의 밸런스 표 고르기 (환경 변수 TF_BALANCE): "off" 면 표 없음 (null → 예전과 같은 판), 그 밖 (없음·빈 글자 포함) 이면 C.BALANCE.
// print: 시작할 때 한 줄 (서버 콘솔 — 방 로그·serverLog 에는 안 남김)
public static class ServerBalance
{
    public static Tune? FromEnv(string? value, Action<string> print)
    {
        if (value == "off")
        {
            print("밸런스 표: 끔 (TF_BALANCE=off)");
            return null;
        }
        print($"밸런스 표: {C.BALANCE}");
        return C.BalanceTune();
    }
}
