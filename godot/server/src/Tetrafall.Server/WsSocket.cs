using System.IO.Compression;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Channels;
using Tetrafall.Core;

namespace Tetrafall.Server;

// 게임 루프가 Send 를 부르면 줄에 넣고, 보내기는 이 접속의 비동기 루프 하나가 차례로 (SendAsync 는 한 번에 하나만)
public sealed class WsSocket : ISocket
{
    readonly WebSocket ws;
    readonly Channel<string> queue = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });
    readonly bool packed;
    volatile bool closed;

    // 누른 결과는 글자 객체마다 하나: 방은 스냅샷 string 하나를 모든 연결에 Send 하니 8명이어도 한 번만 누름.
    // 열쇠는 참조 (내용 아님) 라 string 이 버려지면 같이 사라짐. 두 보내기 루프가 동시에 처음 보면 팩토리가 두 번 돌 수 있는데 결과가 같아 괜찮음
    static readonly ConditionalWeakTable<string, byte[]> gzipCache = new();

    // packed: 주소에 ?pack=gzip 을 붙인 접속 (고도 PC 클라, core/net.gd). 고도 WebSocketPeer 는 permessage-deflate 를 협상하지 않아
    // 8명 판 스냅샷 13.9KB 가 그대로 30Hz (약 418KB/s) 로 나감 → 큰 메시지만 gzip 바이너리로 (약 3KB, 120KB/s 아래).
    // 브라우저 (웹 클라·JS 화면) 는 쿼리 없이 붙어 예전처럼 Text + permessage-deflate
    public WsSocket(WebSocket ws, bool packed = false)
    {
        this.ws = ws;
        this.packed = packed;
    }

    public bool Open => !closed && ws.State == WebSocketState.Open;

    public void Send(string text) => queue.Writer.TryWrite(text);

    public void Closed()
    {
        closed = true;
        queue.Writer.TryComplete();
    }

    public async Task RunSendLoop()
    {
        try
        {
            await foreach (var text in queue.Reader.ReadAllAsync())
            {
                if (ws.State != WebSocketState.Open) break;
                var bytes = Encoding.UTF8.GetBytes(text);
                if (packed && bytes.Length >= C.NET_DEFLATE_MIN_BYTES)
                {
                    // 이미 눌렀으니 permessage-deflate 로 또 누르지 않음. 받는 쪽은 바이너리 = gzip, 글자 = 예전 그대로로 가름
                    var gz = gzipCache.GetValue(text, _ => Gzip(bytes));
                    await ws.SendAsync(gz, WebSocketMessageType.Binary, WebSocketMessageFlags.EndOfMessage | WebSocketMessageFlags.DisableCompression, CancellationToken.None);
                    continue;
                }
                var flags = WebSocketMessageFlags.EndOfMessage | (bytes.Length < C.NET_DEFLATE_MIN_BYTES ? WebSocketMessageFlags.DisableCompression : 0);
                await ws.SendAsync(bytes, WebSocketMessageType.Text, flags, CancellationToken.None);
            }
        }
        catch (WebSocketException) { }
        catch (ObjectDisposedException) { }
    }

    static byte[] Gzip(byte[] bytes)
    {
        var ms = new MemoryStream();
        using (var gz = new GZipStream(ms, CompressionLevel.Fastest)) gz.Write(bytes, 0, bytes.Length);
        return ms.ToArray();
    }
}
