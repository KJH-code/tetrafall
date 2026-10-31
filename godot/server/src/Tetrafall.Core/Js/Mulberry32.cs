namespace Tetrafall.Core.Js;

// tools/sim.js mulberry32 그대로 (서버 난수는 전부 game.rng 를 지나서 시드가 같으면 판이 재현됨)
public sealed class Mulberry32
{
    uint a;

    public Mulberry32(uint seed) => a = seed;

    public double Next()
    {
        a += 0x6d2b79f5;
        uint t = a;
        t = (t ^ (t >> 15)) * (t | 1);
        t ^= t + (t ^ (t >> 7)) * (t | 61);
        return (t ^ (t >> 14)) / 4294967296.0;
    }

    public Func<double> AsFunc() => Next;
}
