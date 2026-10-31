using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-snapshot.js — 키 순서·값이 JSON.stringify 결과와 글자 하나까지 같아야 함 (기존 JS 화면이 그대로 붙게, 판 해시 비교).
// 뼈대: 대기실에서 나오는 값. 아직 안 옮긴 묶음의 값은 대기실 값 그대로 쓰고 'TODO(묶음)' 표시 — 그 묶음을 옮기는 세션이 채움
public sealed partial class Game
{
    public string Snapshot(bool includeGrid = false, Action<JsonOut>? extra = null)
    {
        var o = new JsonOut();
        o.Obj();
        o.P("type", "state").P("time", time).P("phase", phase);
        o.Key("hostId");
        if (hostId.HasValue) o.Num(hostId.Value); else o.Null();
        o.P("canStart", CanStart());
        o.Key("round").Obj();
        o.P("n", roundNumber);
        // killsTarget: 킬 점수전만 TODO(GameRound)
        o.P("elapsed", phase == "playing" ? time - roundStartTime : phase == "countdown" ? 0 : roundEndTime - roundStartTime);
        o.P("countdownLeft", phase == "countdown" ? Math.Max(0, countdownEndsAt - time) : 0);
        o.P("winnerId", winnerId);
        o.P("winnerTeam", winnerTeam);
        o.Key("winnerIds").Arr();
        foreach (var w in winnerIds) o.Num(w);
        o.EndArr();
        o.PNull("left"); // TODO(GameRound): 블록 마스터·킬 점수전 남은 시간
        o.Key("deaths").Arr().EndArr(); // TODO(GameRound)
        o.Key("totals").Obj();
        foreach (var (k, v) in totals) o.P(k, v);
        o.EndObj();
        o.EndObj();
        o.Key("players").Arr();
        foreach (var p in Players()) WritePlayer(o, p);
        o.EndArr();
        o.Key("pieces").Arr().EndArr(); // TODO(GamePieces)
        o.P("nextSpawnIn", Math.Max(0, nextSpawnAt - time));
        o.Key("lava").Obj().P("active", lava.active).P("z", lava.z).EndObj();
        o.Key("itemTimers").Obj().PNull("control").PNull("power").EndObj(); // TODO(GameItems): 판 중
        o.P("itemsEnabled", C.ITEMS_ENABLED); // TODO(GameItems): || controlItemOn()
        o.P("botLevel", botLevel);
        o.P("teamMode", teamMode);
        o.PNull("practice"); // TODO(GamePractice)
        o.PNull("tutorial"); // TODO(Tutorial)
        o.P("skyStairs", skyStairs);
        if (hpMode) throw new NotImplementedException("체력전 스냅샷 TODO(GameRound)");
        o.Key("teamWins").Obj().P("red", teamWins["red"]).P("blue", teamWins["blue"]).EndObj();
        o.P("mode", mode);
        o.Key("teamScores").Obj().P("red", teamScores["red"]).P("blue", teamScores["blue"]).EndObj();
        o.Key("map").Obj().P("choice", mapChoice).P("id", mapId).P("name", Maps.MAPS[mapId].Name).EndObj();
        o.Key("items").Arr().EndArr(); // TODO(GameItems)
        o.Key("projectiles").Arr().EndArr();
        o.Key("shells").Arr().EndArr(); // TODO(CharCannon)
        o.Key("notes").Arr().EndArr(); // TODO(CharBard)
        o.Key("bombs").Arr().EndArr();
        o.Key("bblocks").Arr().EndArr(); // TODO(CharBuilder)
        o.P("gridVersion", gridVersion);
        o.Key("field").Obj().P("w", W).P("d", D).P("h", H).EndObj();
        if (includeGrid || gridDirty)
        {
            o.Key("grid").Arr();
            foreach (var v in grid) o.Num(v);
            o.EndArr();
            gridDirty = false;
        }
        extra?.Invoke(o);
        o.EndObj();
        return o.ToString();
    }

    void WritePlayer(JsonOut o, Player p)
    {
        o.Obj();
        o.P("id", p.id).P("slot", p.slot).P("away", p.away).P("color", p.color).P("name", p.name).P("nick", p.nick).P("spectator", p.spectator).P("team", p.team).P("isBot", p.isBot);
        o.P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", p.yaw).P("pitch", p.pitch).P("alive", p.alive).P("stunned", time < p.stunUntil);
        o.P("hasControl", p.hasControl).P("ammo", p.ammo).P("dashCd", Math.Max(0, p.dashReadyAt - time)).P("airDashes", p.airDashes).P("dummy", p.dummy);
        o.PNull("ghostCd"); // TODO(GamePieces): ghostCd(p) — 판 중 생존 모드 죽은 사람만 숫자
        o.P("pushCd", Math.Max(0, p.pushReadyAt - time)).P("jumpLeft", Math.Max(0, p.jumpUntil - time));
        o.PNull("danger"); // TODO(GamePieces): crushDanger
        o.P("ghostLeft", Math.Max(0, p.ghostUntil - time)).P("speedLeft", Math.Max(0, p.speedUntil - time));
        o.P("emote", -1).P("emoteLeft", Math.Max(0, p.emoteUntil - time)); // TODO(GameInput): isEmoting
        o.PNull("held"); // TODO(GameItems): heldItem
        o.P("bombs", p.bombs).P("bricks", p.bricks).P("brickSide", p.brickSide);
        o.PNull("aim"); // TODO(GameItems): aimPreview (벽돌·폭탄 들었을 때)
        o.P("damage", p.damage);
        // hp: 체력전만 TODO(GameRound)
        o.P("wins", p.wins).P("controlling", false).P("cause", p.deathCause).P("master", p.master).P("zombie", p.zombie);
        o.P("char", p.@char).P("skillCd", Math.Max(0, p.skillReadyAt - time)).P("ult", Math.Floor(p.ult));
        o.P("iframeLeft", Math.Max(0, p.iframeUntil - time)).P("combo", time < p.stunUntil ? p.comboHits : 0).P("empower", Math.Max(0, p.empowerUntil - time));
        if (p.@char == "hook") o.P("loaded", p.loaded);
        o.P("ultMax", C.ULT_MAX * (p.@char == "hunter" ? C.HUNTER_ULT_MULT : 1));
        if (p.@char is "cannon" or "bard") throw new NotImplementedException("대포수·바드 스냅샷 TODO(CharCannon·CharBard)");
        o.P("slowLeft", Math.Max(0, p.slowUntil - time)).P("vulnLeft", Math.Max(0, p.vulnUntil - time));
        if (p.@char is "berserker" or "hunter") throw new NotImplementedException("광전사·사냥꾼 스냅샷 TODO(CharBerserker·CharHunter)");
        o.Key("marks").Arr().EndArr(); // TODO(CharHunter)
        o.Key("respawnIn");
        if (!p.alive && p.respawnAt != 0) o.Num(Math.Max(0, p.respawnAt - time)); else o.Null();
        o.P("shieldLeft", Math.Max(0, p.shieldUntil - time)).P("score", scores.GetValueOrDefault(p.id));
        o.EndObj();
    }
}
