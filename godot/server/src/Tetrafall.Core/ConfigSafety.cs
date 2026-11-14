namespace Tetrafall.Core;

// 고도 전용 수치 (JS 에 없음 — shared/config.js 에서 만드는 Config.g.cs 와 따로): 서버 지키기
public static partial class C
{
    // |yaw| 이보다 크면 입력 무시 (NaN 처럼 예전 yaw 유지). JsMath 정밀 구간 1.6e6 (2^20·π/2) 안
    public const double INPUT_YAW_MAX = 1e6;

    // 멈춘 접속 끊기 (WebSocket keepalive): 서버가 이 간격마다 Ping 을 보내고, Pong 이 TIMEOUT 안에 안 오면 그 접속을 끊음
    // → 응답 없는 접속은 약 20초 (간격 + 제한, .NET 이 확인하는 주기 때문에 재 보면 20~25초) 뒤 끊겨 예전 끊김 흐름 (자리 유지 RECONNECT_GRACE_MS + 봇 대리 + 토큰 복귀) 으로.
    // 테스트는 환경 변수 TF_KEEPALIVE_MS·TF_KEEPALIVE_TIMEOUT_MS (양의 정수 ms) 로 줄임 (WsSocket.KeepAlive)
    public const double NET_KEEPALIVE_MS = 10000;
    public const double NET_KEEPALIVE_TIMEOUT_MS = 10000;
    // 접속 하나의 보내기 줄에 아직 못 보낸 메시지가 이보다 많이 쌓이면 그 접속을 끊음 (30Hz 스냅샷 × 5초).
    // 받는 쪽이 읽기를 멈추면 줄이 끝없이 자라 서버 메모리를 먹음. 스냅샷을 골라 버리면 이벤트·격자 변화가 빠져서 버리지 않고 끊음
    public const double NET_SEND_QUEUE_MAX = 150;
}
