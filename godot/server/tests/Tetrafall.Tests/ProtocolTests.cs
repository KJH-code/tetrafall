using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 같은 각본이면 C# 서버가 JS 서버(rooms.js)와 같은 메시지·로그를 글자 그대로 보냄 → 기존 JS 화면이 C# 서버에 붙음
public class ProtocolTests
{
    sealed class FakeSocket(int i, List<(int, string)> sent) : ISocket
    {
        public bool Open => true;
        public void Send(string text) => sent.Add((i, text));
    }

    sealed class ListLog(string code, List<string> logs) : IRoomLog
    {
        public void Log(string msg) => logs.Add($"[{code}] {msg}");
        public void Close() => logs.Add($"[{code}] (닫음)");
    }

    static System.Text.Json.JsonElement J(string json) => System.Text.Json.JsonDocument.Parse(json).RootElement;

    [Fact]
    public void Lobby_script_matches_js_server()
    {
        var sent = new List<(int, string)>();
        var logs = new List<string>();
        int tk = 0;
        var rooms = new Rooms(openLog: code => new ListLog(code, logs), serverLog: m => logs.Add($"[서버] {m}"), rng: new Mulberry32(77).AsFunc(), now: () => 0, newToken: () => $"token{++tk}");
        const double TICK = 1000.0 / 30;
        void Step()
        {
            rooms.Tick(TICK);
            rooms.Broadcast();
        }
        var c1 = rooms.Connect(new FakeSocket(1, sent));
        rooms.Message(c1, J("{\"type\":\"create\",\"name\":\"\",\"nick\":\"  재혁\\u0001  최고 \"}"));
        Step();
        var code = c1.room!.code;
        var c2 = rooms.Connect(new FakeSocket(2, sent));
        rooms.Message(c2, J($"{{\"type\":\"join\",\"code\":\" {code.ToLowerInvariant()} \"}}"));
        Step();
        rooms.Message(c2, J("{\"type\":\"ping\",\"t\":123.5}"));
        rooms.Message(c2, J("{\"type\":\"ping\",\"t\":\"x\"}"));
        rooms.Message(c1, J("{\"type\":\"join\",\"code\":\"ZZZZ\"}"));
        rooms.Message(c2, J("{\"type\":\"leave\"}"));
        Step();
        var c3 = rooms.Connect(new FakeSocket(3, sent));
        rooms.Message(c3, J("{\"type\":\"join\",\"code\":\"nope\"}"));
        rooms.Message(c3, J("{\"type\":\"join\"}"));
        rooms.Message(c3, J("{\"type\":\"create\",\"name\":\"이름이 아주 아주 아주 아주 긴 방 이름입니다\",\"nick\":5}"));
        Step();
        rooms.BroadcastList(true);
        rooms.Message(c1, J("{\"type\":\"leave\"}"));
        rooms.BroadcastList();

        var want = Fixtures.Load("protocol-lobby.json");
        var wantSent = want.GetProperty("sent").EnumerateArray().Select(e => (e[0].GetInt32(), e[1].GetString()!)).ToList();
        var wantLogs = want.GetProperty("logs").EnumerateArray().Select(e => e.GetString()!).ToList();
        Assert.Equal(wantLogs, logs);
        Assert.Equal(wantSent.Count, sent.Count);
        for (int i = 0; i < sent.Count; i++) Assert.Equal(wantSent[i], sent[i]);
    }
}
