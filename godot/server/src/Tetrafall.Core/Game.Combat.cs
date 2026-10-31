namespace Tetrafall.Core;

// server/game-combat.js — 대시·밀치기·평타·스킬/필살기·넉백·콤보 (S1: 다른 묶음이 쓰는 작은 것. 나머지는 S3)
public sealed partial class Game
{
    public bool Foe(Player p, Player t) => t != p && OnField(t) && !SameTeam(p, t);
}
