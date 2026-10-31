namespace Tetrafall.Core;

// 플레이어 (server/game-players.js addPlayer 의 필드, 같은 순서·이름). JS 처럼 숫자는 double (같은 계산).
// JS 에서 null 로 두는 묶음 상태(leap·rush·atk …)는 아래 작은 클래스 (null = 없음). 각 묶음을 옮기는 세션이 필드를 더함 (이름은 JS 와 같게)
public sealed class Player
{
    public int id;
    public int slot;
    public int color; // PLAYER_PALETTE 번호
    public string name = "";
    public bool isBot;
    public double x, y, z, yaw, pitch, vz, kbx, kby;
    public bool grounded = true;
    public bool alive = true;
    public double stunUntil;
    public double freezeUntil; // 히트스톱
    public double jumpUntil; // 점프력 상승 끝
    public double airJumps = C.AIR_JUMPS;
    public double airDashes = C.AIR_DASHES;
    public bool airJumpQueued;
    public double jumpQueuedUntil;
    public double ghostUntil, speedUntil;
    public bool spectator;
    public string nick = "";
    public double bombs, bricks;
    public bool brickSide;
    public double damage, wins;
    public double dashReadyAt, pushReadyAt;
    public bool hasControl;
    public double ammo;
    public string? deathCause;
    public LastHit? lastHit; // 판 안에서 마지막으로 나를 날린 사람 — 킬 판정
    public double killStreak;
    public string team = "red";
    public double emote = -1, emoteUntil, emoteReadyAt;
    public bool master, zombie;
    public double nextPieceAt; // 블록 마스터: 마스터 편 각자의 다음 블록 시각
    public double respawnAt, shieldUntil;
    public bool wallBounced;
    public string? @char;
    public double skillReadyAt, ult, comboHits, comboStartAt, iframeUntil;
    public double chargeUntil, slamAt, wallAt; // 탱크 돌진·내려찍기, 건축가 솟는 벽
    public List<int[]>? wallCells;
    public bool loaded = true; // 갈고리 장전
    public double zipUntil;
    public XY? zipDir;
    public Grab? grab; // 갈고리 R (S3)
    public OrderedDictionary<int, Mark> marks = new(); // 사냥꾼 표식: 사냥꾼 id → { n, at } (JS Map: 넣은 순서)
    public Leap? leap;
    public Windup? windup;
    public Windup? hookFly; // { at, yaw }
    public HuntAim? huntAim;
    public Rush? rush;
    public Spin? spin;
    public string form = "bard";
    public double glideUntil, glideCount;
    public Dive? dive;
    public bool diveUsed;
    public Amp? amp;
    public double slowUntil, vulnUntil;
    public double cannonAmmo = C.CANNON_AMMO_MAX;
    public double reloadAt;
    public Atk? atk;
    public bool atkQueued, atkLanded;
    public string? castQueued; // 'skill' | 'ult'
    public double chainN, chainUntil, launchUntil, airN;
    public LastBasic? lastBasic;
    public double streak, streakUntil;
    public double empowerUntil;
    public Star2? star2;
    public int touchPiece;
    public PlayerInput input = new();
    // addPlayer 에 없고 나중에 생기는 필드 (JS 에선 undefined 로 시작)
    public bool away; // 접속 끊김 (setAway)
    public bool dummy; // 연습 허수아비
    public XY? chargeDir; // 탱크 돌진 방향
    public string? lastGround; // 마지막으로 밟은 칸 종류 (GROUND_LOG 키)
    public double? ghostReadyAt; // 유령 투하 다음 시각 (죽을 때 정함)
}

public sealed class PlayerInput
{
    public double fwd, strafe;
    public bool jump;
}

public sealed class XY
{
    public double x, y;
    public XY(double x, double y)
    {
        this.x = x;
        this.y = y;
    }
}

public sealed class LastHit
{
    public int by;
    public string kind = "";
    public string? name;
}

public sealed class Mark
{
    public double n, at;
}

// 이동 스킬 지상 준비 · 갈고리 F 날아가기: { at, yaw }
public sealed class Windup
{
    public double at, yaw;
}

// 사냥꾼 F: { at(도약 시작), target(id), endAt, vx, vy, yaw }
public sealed class Leap
{
    public double at, endAt, vx, vy, yaw;
    public int? target;
}

public sealed class HuntAim
{
    public double at;
}

// 광전사 F 도약
public sealed class Rush
{
    public double endAt, vx, vy, landBy;
}

// 광전사 R 회전
public sealed class Spin
{
    public double endAt, nextTick, rage;
}

// 바드 메탈 기타 꽂기
public sealed class Dive
{
    public double until;
    public TAttack? def;
}

// 바드 메탈 R 앰프
public sealed class Amp
{
    public double endAt, nextTick, yaw;
}

// 캐릭터 평타 준비 중: { n, def, air, chained, at, glided }
public sealed class Atk
{
    public double n, at;
    public TAttack def = null!;
    public bool air, chained, glided;
}

public sealed class LastBasic
{
    public double n, at;
    public bool air;
}

// 닌자 R 표창 둘째 발
public sealed class Star2
{
    public double at, n;
    public bool air, chained;
    public TAttack def = null!;
}

// 갈고리 R 뽑은 블록 (S3 가 필드를 채움): { at, cells, meta, from, dir }
public sealed class Grab
{
    public double at;
    public double[] from = Array.Empty<double>();
    public XY? dir;
}
