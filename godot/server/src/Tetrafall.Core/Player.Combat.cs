namespace Tetrafall.Core;

// 플레이어 필드 중 전투 (S3, game-combat.js) 가 쓰는데 addPlayer 에 없는 것 (JS 에선 처음 맞을 때 생김)
public sealed partial class Player
{
    public List<string>? comboBy; // 이 콤보를 넣은 사람 이름 (JS Set: 넣은 순서, 겹침 없음)
    public double? counterAt; // 마지막으로 카운터히트를 맞은 시각
}
