namespace Tetrafall.Core;

// server/char-bard.js — 바드 (S1: 스냅샷이 쓰는 부분. 나머지는 S3)
public sealed partial class Game
{
    public double AmpYaw(Player p) => C.BARD_AMP_LOCK_YAW && p.amp != null ? p.amp.yaw : p.yaw;
}
