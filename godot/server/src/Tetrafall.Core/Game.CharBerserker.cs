namespace Tetrafall.Core;

// server/char-berserker.js — 광전사 (S1: 스냅샷이 쓰는 부분. 나머지는 S3)
public sealed partial class Game
{
    public double RageMult(double damage) => 1 + damage * C.BERSERKER_RAGE_PER_PERCENT;
}
