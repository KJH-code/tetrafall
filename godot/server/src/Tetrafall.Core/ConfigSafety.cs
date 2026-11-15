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
    // 서버 끄기 (SIGTERM·Ctrl+C): 종료 대기 상한 (HostOptions.ShutdownTimeout). Kestrel 기본은 30초라, 열린 WebSocket 이 있으면 그동안
    // 틱·스냅샷을 계속 보내며 살아 있다가 30초 뒤에야 끊겼음 (사람들은 판이 멈춘 줄도 모름). 이제 끄는 순간 방마다 left + 닫기 1001 을 보내고
    // (Rooms.Shutdown → WsSocket.Bye), 닫기에 답하지 않는 접속 (안 읽는 클라) 도 이 시간 뒤 Kestrel 이 Abort → 늦어도 약 3초에 꺼짐
    public const double NET_SHUTDOWN_MS = 3000;
    // 끄기 신호를 받은 스레드가 게임 루프가 Rooms.Shutdown·Bye 를 다 할 때까지 기다리는 상한 (게임 상태는 루프 스레드만 만짐 — inbox 로 넘김).
    // 루프가 멈춰 있어도 이만큼만 기다리고 그대로 끔 (남은 접속은 NET_SHUTDOWN_MS 뒤 Abort)
    public const double NET_SHUTDOWN_WAIT_MS = 1000;
    // 끌 때 줄 (left) 을 다 보낸 뒤 닫기 1001 까지 쉬는 틈 (WsSocket.Bye). 고도 WebSocketPeer 는 한 poll 에 left 와 닫기 프레임을 같이 받으면
    // 바로 닫힌 상태가 되어 left 를 못 읽음 (get_available_packet_count 0 — e2e_net.sh C 에서 실제로 잃었음) → 클라 프레임 몇 번이 지나게 쉼
    public const double NET_SHUTDOWN_CLOSE_GAP_MS = 500;
}
