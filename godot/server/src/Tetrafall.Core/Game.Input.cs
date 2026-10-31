using System.Text.Json;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/game-input.js — 입력·행동·이모트. 화면 메시지의 숫자는 JS 처럼 double? (없거나 숫자가 아니면 null = JS Number.isFinite 거짓)
public sealed class InputMsg
{
    public double? fwd, strafe, yaw, pitch;
    public bool jump;
}

// 행동 { name, n, dx, dy, dir } (JS action 객체). dx·dy·dir 은 JS Number(x) 값 (없으면 NaN: `| 0` → 0, `> 0` → 거짓)
public sealed class ActionMsg
{
    public string? name = "";
    public object? n; // 이모트 번호 (JS Number.isInteger 검사 — 숫자 double 만, 글자는 거절)
    public double dx = double.NaN, dy = double.NaN, dir = double.NaN;
}

public sealed partial class Game
{
    // ---------- 입력 ----------
    // 받은 메시지 그대로 (rooms): 숫자 칸은 JS Number.isFinite 처럼 숫자만, jump 는 !!x
    public void HandleInput(int id, JsonElement msg) => HandleInput(id, new InputMsg
    {
        fwd = JsValue.AsNumber(JsValue.Field(msg, "fwd")),
        strafe = JsValue.AsNumber(JsValue.Field(msg, "strafe")),
        yaw = JsValue.AsNumber(JsValue.Field(msg, "yaw")),
        pitch = JsValue.AsNumber(JsValue.Field(msg, "pitch")),
        jump = JsValue.Truthy(JsValue.Field(msg, "jump")),
    });

    public void HandleAction(int id, JsonElement msg)
    {
        HandleAction(id, new ActionMsg
        {
            name = JsValue.AsString(JsValue.Field(msg, "name")), // 글자가 아니면 null — 어느 행동과도 안 맞음 (JS 도 같음)
            n = JsValue.AsNumber(JsValue.Field(msg, "n")),
            dx = JsValue.ToNumber(JsValue.Field(msg, "dx")),
            dy = JsValue.ToNumber(JsValue.Field(msg, "dy")),
            dir = JsValue.ToNumber(JsValue.Field(msg, "dir")),
        });
    }

    public void HandleInput(int id, InputMsg input)
    {
        var p = GetPlayer(id);
        if (p == null) return;
        static double Clamp(double? v) => v is double d && double.IsFinite(d) ? Math.Max(-1, Math.Min(1, d)) : 0;
        p.input.fwd = Clamp(input.fwd);
        p.input.strafe = Clamp(input.strafe);
        p.input.jump = input.jump;
        if (input.yaw is double yaw && double.IsFinite(yaw)) p.yaw = yaw;
        if (input.pitch is double pitch && double.IsFinite(pitch)) p.pitch = Math.Max(-1.5, Math.Min(1.5, pitch));
    }

    public bool IsControlling(Player p) => ControlledPiece(p) != null;

    public void HandleAction(int id, ActionMsg action)
    {
        var p = GetPlayer(id);
        // 이모트는 판이 끝난 뒤에도 됨 (GG). 하는 동안 못 움직이고, 맞거나 공격하면 끊김
        if (action.name == "emote")
        {
            StartEmote(p, action.n);
            return;
        }
        if (p == null || phase != "playing" || !p.alive) return;
        if (p.master && action.name is not ("pieceMove" or "rotate" or "drop")) return; // 마스터는 블록 조종만
        bool stunned = time < p.stunUntil;
        bool controlling = IsControlling(p);
        if (action.name is "dash" or "push" or "fire" or "skill" or "ult") p.emoteUntil = 0;
        switch (action.name)
        {
            case "jump":
                // 땅에서는 연속 입력이 뛰고, 공중이면 다음 틱에 2단 점프. 땅에서 누른 것도 JUMP_BUFFER_MS 동안 기억
                if (!p.grounded) p.airJumpQueued = true;
                else p.jumpQueuedUntil = time + C.JUMP_BUFFER_MS;
                return;
            case "dash":
                if (stunned || controlling || p.amp != null || time < p.dashReadyAt) return; // 조종 중·바드 앰프 연주 중 대시 불가
                if (!p.grounded && p.airDashes <= 0) return; // 공중 대시는 착지 전 AIR_DASHES 번까지
                Dash(p);
                return;
            case "push":
                if (stunned || controlling || p.spin != null || p.amp != null) return; // 조종 중·광전사 회전·바드 앰프 중 불가
                if (p.@char != null)
                {
                    BasicPress(p); // 캐릭터 평타
                    return;
                }
                if (time < p.pushReadyAt) return;
                Push(p);
                return;
            case "fire": // 우클릭: 손에 든 아이템
                if (stunned || controlling) return;
                if (p.bricks > 0) ThrowBrick(p);
                else if (p.ammo > 0) Fire(p);
                else if (p.bombs > 0) ThrowBomb(p);
                return;
            case "skill": // F
                if (stunned || controlling || p.@char == null || time < p.skillReadyAt) return;
                Cast(p, "skill");
                return;
            case "ult": // R
                if (stunned || controlling || p.@char == null || p.ult < UltMax(p)) return;
                Cast(p, "ult");
                return;
            case "pieceMove":
                if (!controlling) return;
                MovePiece(ControlledPiece(p)!, JsMath.ToInt32(action.dx), JsMath.ToInt32(action.dy));
                return;
            case "rotate":
                if (!controlling)
                {
                    if (p.bricks > 0) p.brickSide = !p.brickSide; // 조종 중이 아니면 Q/E 는 1×2 방향 바꾸기
                    return;
                }
                RotatePiece(ControlledPiece(p)!, action.dir > 0 ? 1 : -1);
                return;
            case "drop":
                if (!controlling) return;
                DropPiece(ControlledPiece(p)!);
                return;
        }
    }

    public bool StartEmote(Player? p, object? nRaw)
    {
        if (p == null || !OnField(p) || (phase != "playing" && phase != "over")) return false;
        if (nRaw is not double n || n != Math.Floor(n) || !double.IsFinite(n) || n < 0 || n >= C.EMOTE_NAMES.Length) return false; // JS Number.isInteger
        if (time < p.emoteReadyAt || time < p.stunUntil || IsControlling(p)) return false;
        p.emote = n;
        p.emoteUntil = time + C.EMOTE_MS;
        p.emoteReadyAt = time + C.EMOTE_COOLDOWN_MS;
        return true;
    }

    public bool IsEmoting(Player p) => time < p.emoteUntil;
}
