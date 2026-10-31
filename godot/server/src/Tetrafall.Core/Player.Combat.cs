namespace Tetrafall.Core;

// 플레이어 필드 중 전투 (S3, game-combat.js) 가 쓰는데 addPlayer 에 없는 것 (JS 에선 처음 맞을 때 생김)
public sealed partial class Player
{
    public List<string>? comboBy; // 이 콤보를 넣은 사람 이름 (JS Set: 넣은 순서, 겹침 없음)
    public double? counterAt; // 마지막으로 카운터히트를 맞은 시각
}

// 사냥꾼 F 도약: 내릴 자리 (유도로 옮겨짐) · 처음 정한 자리 (유도 상한 기준)
public sealed partial class Leap
{
    public XY? to, to0;
}

// 갈고리 R 뽑은 덩어리: 칸마다 { x, y, z, v(칸 값), meta(건축가 블록이면 그 속성) }, 1칸 건축가 블록이면 meta
public sealed partial class Grab
{
    public List<GrabCell> cells = new();
    public BBlock? meta;
}

public sealed class GrabCell
{
    public int x, y, z;
    public byte v;
    public BBlock? meta;
}
