using System.Text.Json;

namespace Tetrafall.Tests;

// tools/fixtures.mjs 가 JS 판에서 뽑은 정답 자료
static class Fixtures
{
    public static JsonElement Load(string name)
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "fixtures");
        return JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, name))).RootElement;
    }

    public static double Bits(string hex) => BitConverter.ToDouble(Convert.FromHexString(hex));
}
