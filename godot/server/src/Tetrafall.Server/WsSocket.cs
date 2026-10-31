using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;
using Tetrafall.Core;

namespace Tetrafall.Server;

// 게임 루프가 Send 를 부르면 줄에 넣고, 보내기는 이 접속의 비동기 루프 하나가 차례로 (SendAsync 는 한 번에 하나만)
public sealed class WsSocket : ISocket
{
    readonly WebSocket ws;
    readonly Channel<string> queue = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });
    volatile bool closed;

    public WsSocket(WebSocket ws) => this.ws = ws;

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
                var flags = WebSocketMessageFlags.EndOfMessage | (bytes.Length < C.NET_DEFLATE_MIN_BYTES ? WebSocketMessageFlags.DisableCompression : 0);
                await ws.SendAsync(bytes, WebSocketMessageType.Text, flags, CancellationToken.None);
            }
        }
        catch (WebSocketException) { }
        catch (ObjectDisposedException) { }
    }
}
