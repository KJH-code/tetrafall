using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-snapshot.js — 키 순서·값이 JSON.stringify 결과와 글자 하나까지 같아야 함 (기존 JS 화면이 그대로 붙게, 판 trace 비교).
// JS 에서 undefined 인 키는 안 씀, Infinity 는 null (JsonOut)
public sealed partial class Game
{
    // extra: 스냅샷 끝에 더 붙일 키 (trace 의 events 등)
    public string Snapshot(bool includeGrid = false, Action<JsonOut>? extra = null)
    {
        var o = new JsonOut();
        o.Obj();
        o.P("type", "state").P("time", time).P("phase", phase);
        o.P("hostId", hostId);
        o.P("canStart", CanStart());
        // 조종권 보유자에게 "N초 후 조종 시작" 표시용: 남이 조종한 블록이 있으면 그게 착지할 때까지, 아니면 다음 생성까지
        double? nextSpawnIn = Math.Max(0, nextSpawnAt - time);
        var ctl = pieces.FirstOrDefault(pc => pc.controller != null);
        if (ctl != null) nextSpawnIn = ctl.phase == "control" ? null : PieceEta(ctl);
        o.Key("round").Obj();
        o.P("n", roundNumber);
        if (mode == "kills") o.P("killsTarget", killsTarget); // 킬 점수전 목표 (판마다 인원으로 정함)
        o.P("elapsed", phase == "playing" ? time - roundStartTime : phase == "countdown" ? 0 : roundEndTime - roundStartTime);
        o.P("countdownLeft", phase == "countdown" ? Math.Max(0, countdownEndsAt - time) : 0);
        o.P("winnerId", winnerId);
        o.P("winnerTeam", winnerTeam);
        o.Key("winnerIds").Arr();
        foreach (var w in winnerIds) o.Num(w);
        o.EndArr();
        o.P("left", phase == "playing" && roundEndsAt != 0 ? Math.Max(0, roundEndsAt - time) : null); // 블록 마스터·킬 점수전 남은 시간
        o.Key("deaths").Arr();
        foreach (var d in deaths) d.Write(o);
        o.EndArr();
        o.Key("totals").Obj();
        foreach (var (k, v) in totals) o.P(k, v);
        o.EndObj();
        o.EndObj();
        o.Key("players").Arr();
        foreach (var p in Players()) WritePlayer(o, p);
        o.EndArr();
        o.Key("pieces").Arr();
        foreach (var pc in pieces) WritePiece(o, pc);
        o.EndArr();
        o.P("nextSpawnIn", nextSpawnIn);
        o.Key("lava").Obj().P("active", lava.active).P("z", lava.z).EndObj();
        var (tc, tp) = ItemTimers();
        o.Key("itemTimers").Obj().P("control", tc).P("power", tp).EndObj();
        o.P("itemsEnabled", C.ITEMS_ENABLED || ControlItemOn()); // 필드에 아이템이 나오는 판인지
        o.P("botLevel", botLevel);
        o.P("teamMode", teamMode);
        o.Key("practice");
        if (mode == "practice") PracticeSnapshot(o); else o.Null();
        o.Key("tutorial");
        if (tutorial != null) TutorialSnapshot(o); else o.Null(); // 튜토리얼 진행
        o.P("skyStairs", skyStairs);
        if (hpMode) o.P("hpMode", true).P("hpMax", HpMax()); // 체력전 (켰을 때만 — 끄면 스냅샷이 예전과 같게)
        o.Key("teamWins").Obj().P("red", teamWins["red"]).P("blue", teamWins["blue"]).EndObj();
        o.P("mode", mode);
        o.Key("teamScores").Obj().P("red", teamScores["red"]).P("blue", teamScores["blue"]).EndObj();
        o.Key("map").Obj().P("choice", mapChoice).P("id", mapId).P("name", Maps.MAPS[mapId].Name).EndObj();
        o.Key("items").Arr();
        foreach (var it in items) it.Write(o);
        o.EndArr();
        o.Key("projectiles").Arr();
        foreach (var pr in projectiles) o.Obj().P("x", pr.x).P("y", pr.y).P("z", pr.z).EndObj();
        o.EndArr();
        o.Key("shells").Arr();
        foreach (var sh in shells)
        {
            o.Obj().P("id", sh.id).P("owner", sh.owner).P("big", sh.big).P("x", sh.x).P("y", sh.y).P("z", sh.z);
            o.Key("dir").Obj().P("x", sh.dir.x).P("y", sh.dir.y).P("z", sh.dir.z).EndObj();
            o.EndObj();
        }
        o.EndArr();
        o.Key("notes").Arr();
        foreach (var nt in notes)
        {
            o.Obj().P("id", nt.id).P("owner", nt.owner).P("x", nt.x).P("y", nt.y).P("z", nt.z);
            o.Key("dir").Obj().P("x", nt.dir.x).P("y", nt.dir.y).P("z", nt.dir.z).EndObj();
            o.EndObj();
        }
        o.EndArr();
        o.Key("bombs").Arr();
        foreach (var b in bombs) o.Obj().P("id", b.id).P("x", b.x).P("y", b.y).P("z", b.z).P("left", Math.Max(0, b.explodeAt - time)).EndObj();
        o.EndArr();
        o.Key("bblocks").Arr();
        foreach (var b in bblocks.Values)
        {
            double left = b.kind == "big" ? Math.Max(0, (bigBombs.FirstOrDefault(x => x.group == b.group)?.at ?? time) - time) : Math.Max(0, b.expiresAt - time);
            o.Obj().P("x", b.x).P("y", b.y).P("z", b.z).P("owner", b.owner).P("kind", b.kind).P("group", b.group).P("left", left).EndObj();
        }
        o.EndArr();
        o.P("gridVersion", gridVersion);
        o.Key("field").Obj().P("w", W).P("d", D).P("h", H).EndObj(); // grid 배열은 (z * d + y) * w + x
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

    // { x, y } 또는 null
    public static void WriteXY(JsonOut o, XY? v)
    {
        if (v == null) o.Null();
        else o.Obj().P("x", v.x).P("y", v.y).EndObj();
    }

    // 떨어지는 블록이 착지까지 남은 ms (조종 중이면 Infinity → JSON null)
    double PieceEta(Piece piece) => piece.phase == "falling" ? Math.Max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - time)) : double.PositiveInfinity;

    void WritePiece(JsonOut o, Piece piece)
    {
        double eta = PieceEta(piece);
        o.Obj().P("id", piece.id).P("shape", piece.shape);
        o.Key("cells").Arr();
        foreach (var c in piece.cells) o.Arr().Num(piece.px + c[0]).Num(piece.py + c[1]).Num(piece.pz).EndArr();
        o.EndArr();
        o.P("phase", piece.phase).P("controller", piece.controller);
        o.P("thrown", piece.thrownBy != null); // 설치 블록 (노랑)
        o.P("ghostBy", piece.ghostBy is int gb && gb != 0 ? gb : null);
        bool ghost = piece.ghostBy is int g && g != 0;
        o.P("ghostSlot", ghost ? piece.ghostSlot : null).P("ghostColor", ghost ? piece.ghostColor : null);
        o.P("sky", piece.sky).P("landZ", piece.landZ).P("fits", piece.fits);
        o.Key("shadow").Arr();
        foreach (var c in piece.cells) o.Arr().Num(piece.px + c[0]).Num(piece.py + c[1]).EndArr();
        o.EndArr();
        o.P("shadowVisible", ShadowVisible(piece, eta)).P("eta", eta);
        o.P("timeLeft", piece.phase == "control" ? Math.Max(0, piece.controlEndsAt - time) : 0);
        o.EndObj();
    }

    void WritePlayer(JsonOut o, Player p)
    {
        o.Obj();
        o.P("id", p.id).P("slot", p.slot).P("away", p.away).P("color", p.color).P("name", p.name).P("nick", p.nick).P("spectator", p.spectator).P("team", p.team).P("isBot", p.isBot);
        o.P("x", p.x).P("y", p.y).P("z", p.z).P("yaw", p.yaw).P("pitch", p.pitch).P("alive", p.alive).P("stunned", time < p.stunUntil);
        o.P("hasControl", p.hasControl).P("ammo", p.ammo).P("dashCd", Math.Max(0, p.dashReadyAt - time)).P("airDashes", p.airDashes).P("dummy", p.dummy);
        o.P("ghostCd", GhostCd(p)); // 유령 투하: null = 지금 못 함, 0 = 바로, 아니면 남은 쿨 ms
        o.P("pushCd", Math.Max(0, p.pushReadyAt - time)).P("jumpLeft", Math.Max(0, p.jumpUntil - time));
        o.P("danger", p.alive ? CrushDanger(p) : null); // 머리 위로 떨어지는 블록이 깔기까지 남은 ms
        o.P("ghostLeft", Math.Max(0, p.ghostUntil - time)).P("speedLeft", Math.Max(0, p.speedUntil - time));
        o.P("emote", IsEmoting(p) ? p.emote : -1).P("emoteLeft", Math.Max(0, p.emoteUntil - time));
        o.P("held", HeldItem(p));
        o.P("bombs", p.bombs).P("bricks", p.bricks).P("brickSide", p.brickSide);
        o.Key("aim");
        if (p.alive) AimPreview(o, p); else o.Null(); // 고른 칸으로 우클릭하면 어디에 무엇이 생기는지
        o.P("damage", p.damage);
        if (hpMode) o.P("hp", Math.Max(0, HpMax(p) - p.damage)).P("hpMax", HpMax(p)); // 체력전: 남은 HP·이 사람 최대 HP (캐릭터 배율, 켰을 때만)
        o.P("wins", p.wins).P("controlling", IsControlling(p)).P("cause", p.deathCause).P("master", p.master).P("zombie", p.zombie);
        o.P("char", p.@char).P("skillCd", Math.Max(0, p.skillReadyAt - time)).P("ult", Math.Floor(p.ult));
        o.P("iframeLeft", Math.Max(0, p.iframeUntil - time)).P("combo", time < p.stunUntil ? p.comboHits : 0).P("empower", Math.Max(0, p.empowerUntil - time));
        if (p.@char == "hook") o.P("loaded", p.loaded); // 갈고리 장전
        o.P("ultMax", UltMax(p)); // 필살기 게이지 필요량 (사냥꾼 2배)
        if (p.@char == "cannon")
            o.Key("cannon").Obj().P("ammo", p.cannonAmmo).P("max", C.CANNON_AMMO_MAX).P("reloadLeft", p.reloadAt != 0 ? Math.Max(0, p.reloadAt - time) : 0).P("reloadMs", C.CANNON_RELOAD_MS).EndObj();
        if (p.@char == "bard")
        {
            o.Key("bard").Obj().P("form", p.form).P("glideLeft", p.glideUntil != 0 ? Math.Max(0, p.glideUntil - time) : 0).P("glidesLeft", Math.Max(0, C.BARD_GLIDE_MAX_PER_AIR - p.glideCount));
            o.P("ampLeft", p.amp != null ? Math.Max(0, p.amp.endAt - time) : 0).P("ampMs", C.BARD_AMP_MS).P("ampYaw", p.amp != null ? AmpYaw(p) : null).EndObj();
        }
        o.P("slowLeft", Math.Max(0, p.slowUntil - time)).P("vulnLeft", Math.Max(0, p.vulnUntil - time));
        if (p.@char == "berserker")
            o.Key("berserker").Obj().P("rage", RageMult(p.damage)).P("spinLeft", p.spin != null ? Math.Max(0, p.spin.endAt - time) : 0).P("spinMs", C.BERSERKER_SPIN_MS).P("spinRage", p.spin != null ? RageMult(p.spin.rage) : 0).EndObj();
        if (p.@char == "hunter") o.P("ultTarget", OnField(p) && ShotTargets(p).Any(t => !LineBlocked(p, t))); // 사냥꾼: 지금 R 쏠 대상이 있나
        o.Key("marks").Arr();
        foreach (var (by, m) in p.marks) o.Obj().P("by", by).P("n", m.n).P("left", Math.Max(0, C.HUNTER_MARK_MS - (time - m.at))).EndObj();
        o.EndArr();
        o.P("respawnIn", !p.alive && p.respawnAt != 0 ? Math.Max(0, p.respawnAt - time) : null);
        o.P("shieldLeft", Math.Max(0, p.shieldUntil - time)).P("score", scores.TryGetValue(p.id, out var sc) ? sc : 0);
        o.EndObj();
    }
}
