using System.Text.Json;
using Tetrafall.Core;

namespace Tetrafall.Tests;

// S3 캐릭터 단위 테스트 도움 (test/characters.test.js·windup.test.js 머리의 setupChars·basic·skill·place 그대로)
public static class CharKit
{
    public static readonly double TICK = 1000 / C.TICK_RATE;

    public static void Run(Game g, double ms)
    {
        for (double t = 0; t < ms; t += TICK) g.Tick(TICK);
    }

    // 사람 2~3명, 캐릭터 지정, 평지, 블록·아이템 없이
    public static (Game g, List<string> lines, Func<int, Player> p) Setup(params string[] chars)
    {
        var lines = new List<string>();
        var g = new Game(lines.Add, characters: true);
        g.rng = () => 0.5;
        for (int i = 0; i < chars.Length; i++)
        {
            g.AddPlayer(i + 1);
            g.SetChar(i + 1, chars[i]);
        }
        g.StartRound();
        g.nextSpawnAt = double.PositiveInfinity;
        g.controlItemNextAt = double.PositiveInfinity;
        g.powerItemNextAt = double.PositiveInfinity;
        return (g, lines, id => g.players[id]);
    }

    public static void Act(Game g, int id, string name) => g.HandleAction(id, new ActionMsg { name = name });

    // 평타 한 번: 누르고 준비 시간 뒤 판정까지
    public static void Basic(Game g, int id)
    {
        Act(g, id, "push");
        var atk = g.players[id].atk;
        if (atk != null) Run(g, atk.at - g.time + TICK / 2);
    }

    // F 한 번: 누르고, 지상 이동 스킬 준비·갈고리가 날아가 닿는 시간까지
    public static void Skill(Game g, int id)
    {
        var p = g.players[id];
        Act(g, id, "skill");
        while (p.windup != null || p.hookFly != null) g.Tick(TICK);
    }

    public static void Place(Player p, double x, double y, double yaw = 0, double z = 0)
    {
        (p.x, p.y, p.z, p.yaw, p.vz, p.kbx, p.kby, p.grounded, p.stunUntil, p.freezeUntil) = (x, y, z, yaw, 0, 0, 0, true, 0, 0);
    }

    // 이벤트 (JSON 글자 → 요소)
    public static List<JsonElement> Events(Game g) => g.DrainEvents().Select(e => JsonDocument.Parse(e).RootElement).ToList();

    public static string? Str(this JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    public static double Num(this JsonElement e, string k) => e.GetProperty(k).GetDouble();

    // 키가 있고 숫자면 그 값, 아니면 null (JS e.k === 값 비교용)
    public static double? NumOr(this JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;

    public static bool IsType(this JsonElement e, string type) => e.Str("type") == type;

    public static JsonElement? Find(this List<JsonElement> ev, string type, Func<JsonElement, bool>? pred = null)
    {
        foreach (var e in ev) if (e.IsType(type) && (pred == null || pred(e))) return e;
        return null;
    }

    public static bool Has(this List<JsonElement> ev, string type, Func<JsonElement, bool>? pred = null) => ev.Find(type, pred) != null;

    // [[x,y,z], …] → 글자 (deepEqual 비교용)
    public static string Cells(this JsonElement e, string k) => e.GetProperty(k).GetRawText();
}
