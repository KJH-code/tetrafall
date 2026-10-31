// 만든 파일 — 고치지 말 것. node godot/server/tools/gen-config.mjs 가 shared/config.js 에서 만듦
#pragma warning disable CS1591
namespace Tetrafall.Core;

public static partial class Maps
{
    public static readonly string[] MAP_IDS = { "flat", "pyramid", "stairs", "bowl", "spiral", "pillars", "fortress" };
    public static readonly Dictionary<string, (string Name, string Log)> MAPS = new() { ["flat"] = ("바람 들판", "평지"), ["pyramid"] = ("황금 피라미드", "피라미드"), ["stairs"] = ("자수정 동굴", "계단"), ["bowl"] = ("용암 분화구", "그릇"), ["spiral"] = ("구름 위 성", "나선 계단"), ["pillars"] = ("반딧불 버섯 숲", "기둥 숲"), ["fortress"] = ("횃불 요새", "요새") };
}
