namespace Tetrafall.Core;

// 플레이어 (server/game-players.js addPlayer 의 필드). JS 처럼 숫자는 double (같은 계산)
// 뼈대: 대기실 스냅샷에 나오는 필드만. 각 묶음을 옮기는 세션이 그 묶음 필드를 더함 (이름은 JS 와 같게)
public sealed class Player
{
    public int id;
    public int slot;
    public int color;
    public string name = "";
    public bool isBot;
    public double x, y, z, yaw, pitch, vz, kbx, kby;
    public bool grounded = true;
    public bool alive = true;
    public double stunUntil, freezeUntil, jumpUntil;
    public double airJumps = C.AIR_JUMPS;
    public double airDashes = C.AIR_DASHES;
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
    public string team = "red";
    public double emote = -1, emoteUntil, emoteReadyAt;
    public bool master, zombie;
    public double respawnAt, shieldUntil;
    public string? @char;
    public double skillReadyAt, ult, comboHits, iframeUntil, empowerUntil;
    public bool loaded = true;
    public double slowUntil, vulnUntil;
    public double cannonAmmo = C.CANNON_AMMO_MAX;
    public string form = "bard";
    public bool away;
    public bool dummy;
}
