namespace Tetrafall.Core;

// server/bot.js — AI 봇 (S5). 지금은 뼈대: 만들기만 (생성자는 rng 를 안 부름, JS 와 같음)
public sealed class BotBrain
{
    readonly Func<double> rng;
    readonly Func<string> level;

    public BotBrain(Func<double> rng, Func<string> level)
    {
        this.rng = rng;
        this.level = level;
    }

    public void Update(Game g, Player p) => throw new NotImplementedException("봇 (S5)");

    public void GhostDrop(Game g, Player p) => throw new NotImplementedException("봇 유령 투하 (S5)");
}
