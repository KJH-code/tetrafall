using System.Diagnostics;
using System.Text.Json;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using Tetrafall.Server;

namespace Tetrafall.Tests;

// 방 (S6) 의 작은 부품: JS 값 바꾸기·이름 정리 (fixtures/jsvalue.json 정답), 긴 글자, 빈도 제한, 자리 토큰, 봇 난이도 이름
public class RoomsUnitTests
{
    sealed class Sock : ISocket
    {
        public readonly List<string> msgs = new();
        public bool Open => true;
        public void Send(string text) => msgs.Add(text);
        public int Count(string type) => msgs.Count(m => JsonDocument.Parse(m).RootElement.GetProperty("type").GetString() == type);
    }

    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement;

    [Fact]
    public void Js_value_conversions_match_js()
    {
        foreach (var row in Fixtures.Load("jsvalue.json").GetProperty("values").EnumerateArray())
        {
            var text = row[0].GetString()!;
            JsonElement v = J(text);
            Assert.True(row[1].GetString() == JsValue.Str(v), $"String({text})");
            Assert.True(row[2].GetString() == JsValue.StrOrEmpty(v), $"String({text} ?? '')");
            Assert.True(row[3].GetBoolean() == JsValue.Truthy(v), $"!!{text}");
            double want = Fixtures.Bits(row[4].GetString()!), got = JsValue.ToNumber(v);
            Assert.True(double.IsNaN(want) ? double.IsNaN(got) : BitConverter.DoubleToInt64Bits(want) == BitConverter.DoubleToInt64Bits(got), $"Number({text}) = {got}, JS {want}");
        }
        Assert.Equal("undefined", JsValue.Str(null));
        Assert.Equal("", JsValue.StrOrEmpty(null));
        Assert.False(JsValue.Truthy(null));
        Assert.True(double.IsNaN(JsValue.ToNumber(null)));
    }

    [Fact]
    public void Clean_text_matches_js_set_nick_and_room_name()
    {
        foreach (var row in Fixtures.Load("jsvalue.json").GetProperty("clean").EnumerateArray())
        {
            var raw = row[0].GetString()!;
            Assert.Equal(row[2].GetString(), JsText.Clean(raw, row[1].GetDouble()));
        }
    }

    [Fact]
    public void Bot_level_ids_are_js_bot_levels_keys()
    {
        Assert.Equal(Fixtures.Load("jsvalue.json").GetProperty("botLevels").EnumerateArray().Select(e => e.GetString()), C.BOT_LEVELS.Keys);
    }

    [Fact]
    public void Ten_million_char_names_are_cut_first_and_do_not_stall()
    {
        var rooms = new Rooms(rng: new Mulberry32(7).AsFunc());
        var x = rooms.Connect(new Sock());
        var huge = new string('ㄱ', 10_000_000);
        // 화면의 JSON.stringify 처럼 한글을 이스케이프하지 않은 글자 (실제 서버는 NET_MAX_PAYLOAD_BYTES 에서 먼저 끊지만 Rooms 는 그것과 상관없이 안전해야 함)
        var opt = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
        var create = J(JsonSerializer.Serialize(new { type = "create", name = huge, nick = huge }, opt));
        var rename = J(JsonSerializer.Serialize(new { type = "setName", name = huge }, opt));
        var sw = Stopwatch.StartNew();
        rooms.Message(x, create);
        rooms.Message(x, rename);
        Assert.True(sw.ElapsedMilliseconds < 1000, $"{sw.ElapsedMilliseconds}ms"); // 정규식은 TEXT_RAW_MAX 글자만 봄 (긴 글자를 꺼내는 데만 시간)
        Assert.Equal(C.NAME_MAX_LEN, x.room!.game.players[x.id].nick.Length);
        Assert.Equal(C.ROOM_NAME_MAX_LEN, x.room.name.Length);
    }

    [Fact]
    public void Message_rate_limit_burst_then_refill_logged_once_and_normal_traffic_passes()
    {
        double clock = 0;
        var server = new List<string>();
        var rooms = new Rooms(serverLog: server.Add, now: () => clock);
        var sx = new Sock();
        var x = rooms.Connect(sx);
        for (int i = 0; i < 500; i++) rooms.Message(x, J($"{{\"type\":\"ping\",\"t\":{i}}}"));
        Assert.Equal(C.NET_MSG_BURST, sx.Count("pong"));
        Assert.Single(server, l => l.Contains("메시지가 너무 많아"));
        clock += 500;
        for (int i = 0; i < 500; i++) rooms.Message(x, J($"{{\"type\":\"ping\",\"t\":{i}}}"));
        Assert.Equal(C.NET_MSG_BURST + Math.Min(C.NET_MSG_BURST, C.NET_MSG_RATE / 2), sx.Count("pong"));
        // 입력 30Hz + 1초에 핑 하나 더 → 10초 내내 다 받음
        var sy = new Sock();
        var y = rooms.Connect(sy);
        int sent = 0;
        for (double t = 0; t < 10000; t += 1000 / C.INPUT_SEND_RATE)
        {
            clock += 1000 / C.INPUT_SEND_RATE;
            rooms.Message(y, J($"{{\"type\":\"ping\",\"t\":{t}}}"));
            sent++;
            if (sent % C.INPUT_SEND_RATE == 0)
            {
                rooms.Message(y, J($"{{\"type\":\"ping\",\"t\":{t}}}"));
                sent++;
            }
        }
        Assert.Equal(sent, sy.Count("pong"));
    }

    [Fact]
    public void Default_seat_tokens_are_random_hex_of_token_bytes()
    {
        var rooms = new Rooms();
        var a = new Sock();
        var b = new Sock();
        var ca = rooms.Connect(a);
        rooms.Message(ca, J("{\"type\":\"create\"}"));
        rooms.Message(rooms.Connect(b), J($"{{\"type\":\"join\",\"code\":\"{ca.room!.code}\"}}"));
        string Tok(Sock s) => s.msgs.Select(m => JsonDocument.Parse(m).RootElement).First(m => m.GetProperty("type").GetString() == "welcome").GetProperty("token").GetString()!;
        Assert.Matches($"^[0-9a-f]{{{(int)C.RECONNECT_TOKEN_BYTES * 2}}}$", Tok(a));
        Assert.Matches($"^[0-9a-f]{{{(int)C.RECONNECT_TOKEN_BYTES * 2}}}$", Tok(b));
        Assert.NotEqual(Tok(a), Tok(b));
    }

    [Fact]
    public void Practice_room_works_next_to_other_rooms()
    {
        // 연습 방 (S4 옮긴 뒤): 오류 없이 만들어지고, 다른 방·접속은 그대로
        var server = new List<string>();
        var rooms = new Rooms(serverLog: server.Add, rng: new Mulberry32(3).AsFunc());
        var s1 = new Sock();
        var c1 = rooms.Connect(s1);
        rooms.Message(c1, J("{\"type\":\"practice\",\"nick\":\"a\"}"));
        Assert.DoesNotContain(server, l => l.Contains("오류"));
        Assert.Equal(1, s1.Count("welcome"));
        var s2 = new Sock();
        var c2 = rooms.Connect(s2);
        rooms.Message(c2, J("{\"type\":\"create\"}"));
        rooms.Tick(1000.0 / 30);
        rooms.Broadcast();
        Assert.Equal(2, s2.Count("state")); // 들어갈 때 전체 스냅샷 + 틱 뒤 스냅샷
    }
}

public class StaticFilesTests
{
    [Fact]
    public void Play_serves_godot_web_build_with_wasm_and_pck_types()
    {
        var root = Path.Combine(Path.GetTempPath(), "tfroot");
        var web = Path.Combine(root, "godot", "client", "build", "web");
        Assert.Equal(Path.Combine(web, "index.html"), StaticFiles.Resolve(root, "/play/"));
        Assert.Equal(Path.Combine(web, "index.html"), StaticFiles.Resolve(root, "/play"));
        Assert.Equal(Path.Combine(web, "tetrafall.wasm"), StaticFiles.Resolve(root, "/play/tetrafall.wasm"));
        Assert.Null(StaticFiles.Resolve(root, "/play/../../../secret.txt"));
        Assert.Equal(Path.Combine(root, "client", "player.js"), StaticFiles.Resolve(root, "/player.js")); // /play 로 시작해도 /play/ 가 아니면 예전대로
        Assert.Equal("application/wasm", StaticFiles.Mime("a.wasm"));
        Assert.Equal("application/octet-stream", StaticFiles.Mime("a.pck"));
    }
}
