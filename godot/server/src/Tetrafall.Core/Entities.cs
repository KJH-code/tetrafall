using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// Game 이 들고 있는 작은 객체들 (JS 에선 그냥 객체 글자). 스냅샷에 통째로 나가는 것은 Write 가 JS 키 순서 그대로 씀.
// 각 묶음을 옮기는 세션이 필드를 더함 (이름은 JS 와 같게)

// 떨어지는·조종 중인 블록 (game-pieces.js makePiece + addPiece fields)
public sealed class Piece
{
    public int id;
    public string shape = "";
    public double rot;
    public int[][] cells = Array.Empty<int[]>();
    public int px, py, pz;
    public int landZ;
    public bool fits;
    public string phase = ""; // 'falling' | 'control'
    public int? controller;
    public double stepMs;
    public double nextStepAt;
    public double controlEndsAt;
    public int? thrownBy; // 설치 블록 던진 사람
    public int? ghostBy; // 유령 투하: 떨어뜨린 사람 id
    public int ghostSlot, ghostColor;
    public bool sky; // 하늘 계단 블록
    public int chain; // 하늘 계단 사슬 번호
}

public sealed class Lava
{
    public bool active;
    public double z = C.LAVA_START_Z;
    public double startedAt;
}

// 필드 아이템 { type, x, y, z } — 스냅샷에 그대로
public sealed class Item
{
    public string type = "";
    public int x, y, z;

    public void Write(JsonOut o) => o.Obj().P("type", type).P("x", x).P("y", y).P("z", z).EndObj();
}

public sealed class Projectile
{
    public double x, y, z, dx, dy, dz;
    public int owner;
    public double dieAt;
}

public sealed class Bomb
{
    public int id;
    public int x, y, z;
    public int by;
    public double explodeAt;
}

// 건축가 블록 { x, y, z, owner, kind, group, expiresAt, born }
public sealed class BBlock
{
    public int x, y, z;
    public int owner;
    public string kind = "";
    public int group;
    public double expiresAt, born;
}

public sealed class BigBomb
{
    public int owner, group;
    public double at;
    public XY? dir;
}

public sealed class Hole
{
    public int x, y, z, v, id;
    public double at;
}

public sealed class Quake
{
    public int id;
    public List<int[]> cells = new();
    public double at;
}

// 대포수 포탄 (S3)
public sealed class Shell
{
    public int id;
    public bool big;
    public int owner;
    public double x, y, z;
    public XY? dir;
}

// 바드 음파 (S3)
public sealed class Note
{
    public int id;
    public int owner;
    public double x, y, z;
    public XY? dir;
}

// 사망 기록 (스냅샷 round.deaths 에 그대로). 접속 끊김은 { name, cause, t } 만 (killer·weapon 키 없음)
public sealed class Death
{
    public string name = "";
    public string cause = "";
    public double t;
    public bool hasKiller; // false 면 killer·weapon 키를 안 씀 (JS 객체에 없음)
    public string? killer;
    public string? weapon;

    public void Write(JsonOut o)
    {
        o.Obj().P("name", name).P("cause", cause).P("t", t);
        if (hasKiller) o.P("killer", killer).P("weapon", weapon);
        o.EndObj();
    }
}

// 마지막 죽음 (finalKill)
public sealed class LastDeath
{
    public int who;
    public string cause = "";
    public int? by;
    public double x, y, z;
    public XY? @out;
    public double at;
}
