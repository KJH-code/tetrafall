using System.Text.Json;
using System.Text.RegularExpressions;
using Tetrafall.Core;
using Tetrafall.Core.Js;
using static Tetrafall.Tests.CharKit;

namespace Tetrafall.Tests;

// test/characters.test.js 1201~2001 줄 (갈고리·건축가 벽·사냥꾼·대포수). 봇 테스트는 S5 (맨 아래 목록)
public class CharTestsB
{
    // ---------- 도움 ----------

    static JsonElement SnapP(Game g, int id)
    {
        var root = JsonDocument.Parse(g.Snapshot()).RootElement;
        foreach (var x in root.GetProperty("players").EnumerateArray()) if (x.Num("id") == id) return x;
        throw new Exception($"스냅샷에 P{id} 없음");
    }

    static JsonElement Snap(Game g) => JsonDocument.Parse(g.Snapshot()).RootElement;

    static void FireShell(Game g, Player p, bool big) => g.FireShell(p, big);

    // [[x,y,z], …] → 목록
    static List<int[]> CellList(JsonElement e, string k = "cells") =>
        e.GetProperty(k).EnumerateArray().Select(c => c.EnumerateArray().Select(v => v.GetInt32()).ToArray()).ToList();

    // 블록 하나를 (px,py,pz) 에 바로 착지시킴 (격자 + 블록 id)
    static Piece LandAt(Game g, string shape, double rot, int px, int py, int pz = 0)
    {
        var pc = g.AddPiece(g.MakePiece(shape, rot, px, py, pz), f =>
        {
            f.phase = "falling";
            f.controller = null;
            f.stepMs = 1e9;
            f.nextStepAt = double.PositiveInfinity;
            f.controlEndsAt = 0;
        });
        g.LandPiece(pc);
        return pc;
    }

    static JsonElement? UltHook(Game g, Player p)
    {
        p.ult = C.ULT_MAX;
        g.DrainEvents();
        Act(g, p.id, "ult");
        return Events(g).Find("blockGrab");
    }

    static void SetMark(Player t, int by, double n, double at) => t.marks[by] = new Mark { n = n, at = at };

    // ---------- 갈고리 ----------

    [Fact]
    public void Hook_basic_swing_punch_bang_then_empty_slam_no_passive_range()
    {
        var (g, lines, p) = Setup("hook", "builder");
        Assert.True(p(1).loaded, "판 시작에 장전");
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        var ev = new List<JsonElement>();
        for (double t = 0; t < 3000 && !lines.Any(l => l.Contains(" 마무리")); t += TICK)
        {
            Act(g, 1, "push");
            g.Tick(TICK);
            ev.AddRange(Events(g));
        }
        Assert.Equal(new[] { "갈고리 휘두르기", "주먹", "탕" }, ev.Where(e => e.IsType("attack") && e.Num("who") == 1).Select(e => e.Str("name")));
        Assert.True(ev.Has("bang", e => e.Num("who") == 1));
        Assert.False(p(1).loaded, "쏘면 빈 총");
        Assert.False(SnapP(g, 1).GetProperty("loaded").GetBoolean());
        // 빈 총: 내려치기
        Run(g, 2000);
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        p(1).chainN = 2;
        p(1).chainUntil = double.PositiveInfinity;
        p(1).pushReadyAt = 0;
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.Equal("갈고리 내려치기", Events(g).Find("attack")!.Value.Str("name"));
        Assert.True(C.BASIC_ATTACKS["hook"].chain[2].loaded!.dmg > C.BASIC_ATTACKS["hook"].chain[2].dmg, "탕이 더 셈");
        Assert.True(typeof(C).GetField("HOOK_PUSH_RANGE_MULT") == null && typeof(C).GetProperty("HOOK_PUSH_RANGE_MULT") == null, "패시브 없음");
        // 탕 사거리 2: 1.8 밖도 맞음
        var q = Setup("hook", "builder");
        Place(q.p(1), 3, 4.5, 0);
        Place(q.p(2), 4.95, 4.5);
        (q.p(1).chainN, q.p(1).chainUntil) = (2, double.PositiveInfinity);
        Basic(q.g, 1);
        Assert.Equal(C.BASIC_ATTACKS["hook"].chain[2].loaded!.dmg, q.p(2).damage);
    }

    [Fact]
    public void Hook_air_basic_spin_hits_all_around_including_behind()
    {
        var (g, _, p) = Setup("hook", "builder", "tank");
        Place(p(1), 4.5, 4.5, 0, 0.5);
        (p(1).grounded, p(1).vz) = (false, 2);
        Place(p(2), 5.5, 4.5);
        Place(p(3), 3.5, 4.5); // 뒤
        Act(g, 1, "push");
        Run(g, C.BASIC_ATTACKS["hook"].air[0].windup + TICK / 2);
        Assert.True(p(2).damage > 0 && p(3).damage > 0, $"앞 {p(2).damage} 뒤 {p(3).damage}");
    }

    [Fact]
    public void Hook_F_pulls_foe_and_reloads_block_first_zips_me_miss_has_cooldown_hook_kill()
    {
        var (g, lines, p) = Setup("hook", "ninja", "ninja");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 4.5, 4.5);
        Place(p(3), 9.5, 9.5);
        p(1).loaded = false;
        Skill(g, 1);
        Assert.True(Math.Abs(p(2).x - (p(1).x + C.HOOK_PULL_TO)) < 0.05, $"끌려옴 x={p(2).x}");
        Assert.Equal(C.HOOK_DAMAGE, p(2).damage);
        Assert.True(p(1).loaded, "끌어오면 장전");
        Assert.Contains(lines, l => l.StartsWith("  [스킬] P1 갈고리 → P2") && l.EndsWith("장전"));
        Assert.Equal("hook", p(2).lastHit!.kind);
        // 끌려온 뒤 떨어지면 갈고리 킬
        (p(2).x, p(2).z) = (-3, C.FALL_DEATH_Z - 1);
        g.Tick(TICK);
        Assert.Contains(lines, l => Regex.IsMatch(l, @"\[사망\] P2 낙사 .*킬 P1 갈고리"));
        // 블록이 먼저 닿음: 내가 끌려감 (공중에서도)
        Run(g, C.SKILL_CD_MS["hook"]);
        g.grid[g.Idx(5, 2, 1)] = Pieces.CELL.TERRAIN;
        g.GridChanged();
        Place(p(3), 7.5, 2.5); // 블록 뒤 상대
        Place(p(1), 1.5, 2.5, 0, 0.3);
        (p(1).grounded, p(1).vz) = (false, -1);
        g.DrainEvents();
        Skill(g, 1);
        Assert.True(Events(g).Has("hook", e => e.TryGetProperty("block", out var b) && b.ValueKind == JsonValueKind.Array
            && e.TryGetProperty("target", out var tg) && tg.ValueKind == JsonValueKind.Null));
        Assert.Equal(0, p(3).damage);
        Run(g, 400);
        Assert.True(p(1).x > 4, $"블록 쪽으로 끌려감 x={p(1).x:F2}");
        // 빗나감도 쿨타임
        Run(g, C.SKILL_CD_MS["hook"]);
        Place(p(1), 1.5, 7.5, Math.PI);
        Skill(g, 1);
        Assert.Contains("  [스킬] P1 갈고리 빗나감", lines);
        Assert.True(p(1).skillReadyAt > g.time);
    }

    [Fact]
    public void Hook_R_block_slam_line_knockback_lands_at_end_builder_kept_off_field_gone()
    {
        var (g, lines, p) = Setup("hook", "ninja", "builder");
        Place(p(1), 4.5, 4.5, 0); // +x
        Place(p(2), 6.5, 4.5); // 직선 위
        Place(p(3), 9.5, 0.5, Math.PI); // 끝 칸 (x=9) 에 서 있음
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Assert.Equal(C.ULT_MAX, p(1).ult);
        g.PlaceBBlock(p(3), 7, 4, 1, "wall", 55); // 앞에 건축가 블록 (가슴 높이)
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        Assert.Equal(0, g.GridAt(7, 4, 1));
        Assert.True(Events(g).Has("blockGrab", e => e.GetProperty("builder").GetBoolean()));
        Run(g, C.HOOK_GRAB_MS + TICK);
        Assert.Equal(C.HOOK_SLAM_DAMAGE, p(2).damage);
        Assert.True(p(2).kbx > 0 && (p(2).vz > 0 || p(2).z > 0.1), "넉백 + 띄움");
        Assert.Equal("blockslam", p(2).lastHit!.kind);
        int x = (int)Math.Floor(4.5 + C.HOOK_SLAM_LEN);
        Assert.Equal(Pieces.CELL.BUILD, g.GridAt(x, 4, 0));
        Assert.True(g.bblocks.TryGetValue(GameUtil.CellKey(x, 4, 0), out var b) && b.owner == 3 && b.kind == "wall", "건축가 블록 그대로");
        Assert.True(lines.Any(l => l.Contains($"[필살] P1 블록 내려찍기 (1명) → ({x},4,0) 박힘")), string.Join("\n", lines));
        // 박히는 칸 사람은 밀쳐냄
        var q = Setup("hook", "ninja");
        Place(q.p(1), 1.5, 2.5, 0);
        q.g.grid[q.g.Idx(3, 2, 1)] = Pieces.CELL.TERRAIN;
        q.g.GridChanged();
        Place(q.p(2), 1.5 + C.HOOK_SLAM_LEN, 2.5); // 끝 칸
        q.p(1).ult = C.ULT_MAX;
        Act(q.g, 1, "ult");
        Run(q.g, C.HOOK_GRAB_MS + TICK);
        Assert.True(q.p(2).alive, "압사 없음");
        Assert.Equal(Pieces.CELL.TERRAIN, q.g.GridAt((int)Math.Floor(1.5 + C.HOOK_SLAM_LEN), 2, 0));
        // 필드 밖이면 사라짐
        var r = Setup("hook", "ninja");
        Place(r.p(2), 9.5, 9.5);
        Place(r.p(1), 7.5, 2.5, 0);
        r.g.grid[r.g.Idx(8, 2, 1)] = Pieces.CELL.TERRAIN;
        r.g.GridChanged();
        r.p(1).ult = C.ULT_MAX;
        Act(r.g, 1, "ult");
        Run(r.g, C.HOOK_GRAB_MS + TICK);
        int left = 0;
        for (int i = 0; i < r.g.grid.Length; i++) if (r.g.grid[i] == Pieces.CELL.TERRAIN) left++;
        Assert.Equal(0, left);
    }

    [Fact]
    public void Hook_R_whole_tetromino_neighbors_split_broken_piece_connected_terrain_one()
    {
        Assert.Equal(400, C.HOOK_GRAB_MS);
        Assert.Equal(1.2, C.HOOK_SLAM_WIDTH);
        Assert.Equal(14, C.HOOK_SLAM_DAMAGE);
        // 같은 모양 O 두 개가 붙어 있음: 앞 것만
        var (g, _, p) = Setup("hook", "ninja");
        Place(p(2), 1, 9);
        LandAt(g, "O", 0, 5, 4);
        LandAt(g, "O", 0, 7, 4);
        Place(p(1), 3.5, 4.5, 0);
        var e = UltHook(g, p(1))!.Value;
        Assert.Equal(4, e.GetProperty("cells").GetArrayLength());
        foreach (var (x, y) in new[] { (5, 4), (6, 4), (5, 5), (6, 5) }) Assert.True(g.GridAt(x, y, 0) == 0, $"({x},{y}) 뽑힘");
        foreach (var (x, y) in new[] { (7, 4), (8, 4), (7, 5), (8, 5) }) Assert.True(g.GridAt(x, y, 0) >= Pieces.CELL.SHAPE_BASE, $"({x},{y}) 옆 O 그대로");
        // 부서진 블록: I 의 가운데가 빠지면 맞은 쪽 이어진 칸만
        var q = Setup("hook", "ninja");
        Place(q.p(2), 1, 9);
        LandAt(q.g, "I", 0, 4, 4); // (4..7, 4)
        q.g.grid[q.g.Idx(6, 4, 0)] = 0;
        q.g.GridChanged();
        Place(q.p(1), 2.5, 4.5, 0);
        // JS .sort() 는 글자 순 — 4·5 는 한 자리라 같음
        Assert.Equal(new[] { 4, 5 }, CellList(UltHook(q.g, q.p(1))!.Value).Select(c => c[0]).OrderBy(v => v.ToString(), StringComparer.Ordinal));
        Assert.True(q.g.GridAt(7, 4, 0) > 0, "떨어진 칸은 남음");
        // 층 클리어로 내려앉아도 id 가 같이 내려감
        var r = Setup("hook", "ninja");
        Place(r.p(2), 1, 9);
        LandAt(r.g, "O", 0, 5, 4, 1);
        r.g.DropLayers(new List<int> { 0 });
        Assert.True(r.g.GridAt(5, 4, 0) >= Pieces.CELL.SHAPE_BASE);
        Place(r.p(1), 3.5, 4.5, 0);
        Assert.Equal(4, UltHook(r.g, r.p(1))!.Value.GetProperty("cells").GetArrayLength());
        // 지형은 1칸
        var t = Setup("hook", "ninja");
        Place(t.p(2), 1, 9);
        foreach (var x in new[] { 5, 6 }) t.g.grid[t.g.Idx(x, 4, 0)] = Pieces.CELL.TERRAIN;
        t.g.GridChanged();
        Place(t.p(1), 3.5, 4.5, 0);
        Assert.Equal(1, UltHook(t.g, t.p(1))!.Value.GetProperty("cells").GetArrayLength());
        Assert.Equal(Pieces.CELL.TERRAIN, t.g.GridAt(6, 4, 0));
    }

    [Fact]
    public void Hook_R_falling_sky_piece_whole_controlled_not_grabbed_rider_falls_hit_restores()
    {
        var (g, lines, p) = Setup("hook", "ninja");
        Place(p(2), 1, 9);
        var fall = g.AddPiece(g.MakePiece("T", 0, 5, 4, 1), f =>
        {
            f.phase = "falling";
            f.controller = null;
            f.sky = true;
            f.stepMs = 1e9;
            f.nextStepAt = double.PositiveInfinity;
            f.controlEndsAt = 0;
        });
        Place(p(1), 3.5, 4.5, 0);
        var e = UltHook(g, p(1))!.Value;
        Assert.Equal(4, e.GetProperty("cells").GetArrayLength());
        Assert.True(e.GetProperty("sky").GetBoolean());
        Assert.DoesNotContain(fall, g.pieces);
        Assert.Contains(lines, l => l.Contains("하늘 블록"));
        // 조종 중인 블록은 안 잡음
        var q = Setup("hook", "ninja");
        Place(q.p(2), 1, 9);
        q.g.AddPiece(q.g.MakePiece("O", 0, 5, 4, 1), f =>
        {
            f.phase = "control";
            f.controller = 2;
            f.stepMs = 1e9;
            f.nextStepAt = double.PositiveInfinity;
            f.controlEndsAt = double.PositiveInfinity;
        });
        Place(q.p(1), 3.5, 4.5, 0);
        Assert.Null(UltHook(q.g, q.p(1)));
        Assert.Equal(C.ULT_MAX, q.p(1).ult);
        // 뽑힌 블록 위 사람은 떨어짐
        var r = Setup("hook", "ninja");
        LandAt(r.g, "O", 0, 5, 4);
        Place(r.p(2), 6, 5, 0, 1); // O 위
        Place(r.p(1), 3.5, 4.5, 0);
        UltHook(r.g, r.p(1));
        Run(r.g, 300);
        Assert.True(r.p(2).z < 0.5, $"떨어짐 z {r.p(2).z:F2}");
        // 뽑다 맞으면 덩어리 제자리 (다시 덩어리로)
        var s = Setup("hook", "ninja");
        Place(s.p(2), 1, 9);
        LandAt(s.g, "O", 0, 5, 4);
        Place(s.p(1), 3.5, 4.5, 0);
        UltHook(s.g, s.p(1));
        s.g.ApplyKnockback(s.p(1), -1, 0, 1, 0, 300, 1, new Src(2, "push"));
        foreach (var (x, y) in new[] { (5, 4), (6, 4), (5, 5), (6, 5) }) Assert.True(s.g.GridAt(x, y, 0) >= Pieces.CELL.SHAPE_BASE, "제자리");
        Run(s.g, 1500);
        Place(s.p(1), 3.5, 4.5, 0);
        Assert.Equal(4, UltHook(s.g, s.p(1))!.Value.GetProperty("cells").GetArrayLength());
    }

    [Fact]
    public void Hook_R_slam_keeps_shape_on_highest_column_drops_off_field_regrab_pushes_people()
    {
        var (g, _, p) = Setup("hook", "ninja");
        Place(p(2), 1, 9);
        LandAt(g, "L", 0, 3, 4);
        var shape = new List<int[]>();
        for (int x = 0; x < g.W; x++) for (int y = 0; y < g.D; y++) if (g.GridAt(x, y, 0) >= Pieces.CELL.SHAPE_BASE) shape.Add(new[] { x, y });
        g.grid[g.Idx(7, 4, 0)] = Pieces.CELL.TERRAIN; // 끝 쪽 기둥 하나 높음
        g.GridChanged();
        Place(p(1), 1.5, 4.5, 0);
        var e = UltHook(g, p(1))!.Value;
        Assert.Equal(4, e.GetProperty("cells").GetArrayLength());
        Run(g, C.HOOK_GRAB_MS + TICK);
        var slam = CellList(Events(g).Find("blockSlam")!.Value);
        Assert.Equal(4, slam.Count);
        int z = slam[0][2];
        Assert.True(slam.All(c => c[2] == z) && z >= 1, $"한 높이, 높은 기둥 위 z={z}");
        static string Norm(List<int[]> cs)
        {
            int mx = cs.Min(c => c[0]), my = cs.Min(c => c[1]);
            return string.Join(" ", cs.Select(c => $"{c[0] - mx},{c[1] - my}").OrderBy(s => s, StringComparer.Ordinal));
        }
        Assert.Equal(Norm(shape), Norm(slam));
        // 다시 통째로 잡힘
        int sx = slam.Min(c => c[0]);
        Place(p(1), sx - 1.5, slam.First(c => c[0] == sx)[1] + 0.5, 0, z);
        Assert.Equal(4, UltHook(g, p(1))!.Value.GetProperty("cells").GetArrayLength());
        // 필드 밖 칸 버림
        var q = Setup("hook", "ninja");
        Place(q.p(2), 1, 1);
        Place(q.p(1), q.g.W - 6 + 0.5, 4.5, 0);
        LandAt(q.g, "I", 0, q.g.W - 5, 4); // 가로 I (W-5..W-2, 4)
        q.p(1).yaw = 0;
        UltHook(q.g, q.p(1));
        Run(q.g, C.HOOK_GRAB_MS + TICK);
        var s2 = CellList(Events(q.g).Find("blockSlam")!.Value);
        Assert.True(s2.Count < 4 && s2.Count >= 1, $"필드 밖 칸 버림 {s2.Count}");
        // 놓인 칸 사람은 압사 없이 밀쳐냄
        var r = Setup("hook", "ninja");
        LandAt(r.g, "O", 0, 3, 4);
        Place(r.p(1), 1.5, 4.5, 0);
        Place(r.p(2), 1.5 + C.HOOK_SLAM_LEN, 4.5);
        UltHook(r.g, r.p(1));
        Run(r.g, C.HOOK_GRAB_MS + TICK);
        Assert.True(r.p(2).alive, "압사 없음");
        Assert.Empty(r.g.OverlappingSolid(r.g.Aabb(r.p(2))));
    }

    [Fact]
    public void Hook_block_find_bug_1cell_block_on_flat_grabbed_by_R_and_F_floor_not()
    {
        var (g, _, p) = Setup("hook", "ninja");
        Place(p(2), 9.5, 9.5);
        g.grid[g.Idx(5, 4, 0)] = Pieces.CELL.THROWN; // 떨어져 쌓인 1칸 높이 블록
        g.GridChanged();
        Place(p(1), 2.5, 4.5, 0);
        p(1).pitch = -Math.Atan2(C.EYE_HEIGHT - 0.5, 3); // 블록 가운데를 봄
        var hb = g.HookRayBlock(p(1), p(1).yaw, Game.Pitch0(p(1)));
        Assert.NotNull(hb);
        Assert.Equal((5, 4, 0), (hb!.x, hb.y, hb.z));
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        Assert.Equal(0, g.GridAt(5, 4, 0));
        Run(g, C.HOOK_GRAB_MS + TICK);
        // F 도 걸림 (수평으로 봐도 발 층 보조로 잡힘)
        g.grid[g.Idx(5, 2, 0)] = Pieces.CELL.THROWN;
        g.GridChanged();
        Place(p(1), 2.5, 2.5, 0);
        p(1).pitch = 0;
        g.DrainEvents();
        Skill(g, 1);
        Assert.True(Events(g).Has("hook", e => e.TryGetProperty("block", out var b) && b.ValueKind == JsonValueKind.Array && b[2].GetDouble() == 0));
        // 바닥만 보면 없음
        var q = Setup("hook", "ninja");
        Place(q.p(2), 9.5, 9.5);
        Place(q.p(1), 2.5, 4.5, 0);
        q.p(1).pitch = -1.2;
        Assert.Null(q.g.HookRayBlock(q.p(1), q.p(1).yaw, Game.Pitch0(q.p(1))));
    }

    // ---------- 사람 테스트 수정 (2026-10-26) ----------

    [Fact]
    public void Builder_F_wall_cell_where_builder_walks_in_stays_empty_builder_not_lifted()
    {
        var (g, _, p) = Setup("builder", "ninja");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 4.5, 4.5, 0);
        Act(g, 1, "skill"); // x=5, y 3~5
        Place(p(1), 5.5, 4.5, 0); // 가운데 벽 칸 위로
        Run(g, C.BUILDER_WALL_WARN_MS + TICK);
        Assert.Equal(0, g.GridAt(5, 4, 0));
        Assert.Equal(Pieces.CELL.BUILD, g.GridAt(5, 3, 0));
        Assert.Equal(Pieces.CELL.BUILD, g.GridAt(5, 5, 0));
        Assert.True(p(1).z < 0.05, $"안 뜸 z={p(1).z}");
    }

    [Fact]
    public void Tank_R_windup_and_ring_up_blink_event_from_has_z()
    {
        Assert.Equal(700, C.TANK_SLAM_WINDUP_MS);
        Assert.Equal(5, C.TANK_RING_UP);
        var (g, _, p) = Setup("ninja", "builder");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 1.5, 4.5, 0, 0.5);
        p(1).grounded = false;
        g.DrainEvents();
        Act(g, 1, "skill");
        var e = Events(g).Find("blink")!.Value;
        Assert.Equal(0.5, e.GetProperty("from").Num("z"));
    }

    [Fact]
    public void Hook_R_one_press_fires_aim_tolerance_queued_after_recovery_ultFail_castDrop()
    {
        foreach (var pitch in new[] { 0, -0.3, 0.25 })
        {
            foreach (var off in new[] { 0, 0.7 })
            {
                var (g0, _, p0) = Setup("hook", "ninja");
                Place(p0(2), 9.5, 9.5);
                g0.grid[g0.Idx(5, 4, 0)] = Pieces.CELL.THROWN;
                g0.GridChanged();
                Place(p0(1), 2.5, 4.5, Math.Atan2(off, 3));
                p0(1).pitch = pitch;
                p0(1).ult = C.ULT_MAX;
                Act(g0, 1, "ult");
                Assert.True(p0(1).ult == 0, $"pitch {pitch} off {off}: 한 번에");
                Assert.Equal(0, g0.GridAt(5, 4, 0));
            }
        }
        // 평타 후딜 중 R
        var (g, _, p) = Setup("hook", "ninja");
        Place(p(2), 9.5, 9.5);
        g.grid[g.Idx(5, 4, 0)] = Pieces.CELL.THROWN;
        g.GridChanged();
        Place(p(1), 2.5, 4.5, 0);
        p(1).ult = C.ULT_MAX;
        Basic(g, 1); // 빗나감 → 후딜
        Act(g, 1, "ult");
        Assert.Equal(C.ULT_MAX, p(1).ult);
        Run(g, p(1).pushReadyAt - g.time + TICK);
        Assert.Equal(0, p(1).ult);
        // 블록 없음 → ultFail
        var q = Setup("hook", "ninja");
        Place(q.p(2), 9.5, 9.5);
        Place(q.p(1), 2.5, 4.5, 0);
        q.p(1).ult = C.ULT_MAX;
        q.g.DrainEvents();
        Act(q.g, 1, "ult");
        Assert.True(Events(q.g).Has("ultFail", e => e.Num("who") == 1 && e.Str("reason") == "noBlock"));
        Assert.Equal(C.ULT_MAX, q.p(1).ult);
        // 기억한 R 이 맞아서 버려지면 castDrop
        Act(q.g, 1, "push");
        Act(q.g, 1, "ult");
        q.g.DrainEvents();
        q.g.ApplyKnockback(q.p(1), 1, 0, 1, 0, 300, 1, new Src(2, "push"));
        Assert.True(Events(q.g).Has("castDrop", e => e.Num("who") == 1 && e.Str("kind") == "ult"));
    }

    // ---------- 사냥꾼 ----------

    [Fact]
    public void Hunter_mark_from_ground_finisher_only_max3_per_hunter_not_air_expires_snapshot_marks()
    {
        var (g, lines, p) = Setup("hunter", "tank", "hunter");
        Place(p(3), 9.5, 9.5);
        void Chain()
        {
            Place(p(1), 3, 4.5, 0);
            Place(p(2), 4.2, 4.5);
            (p(1).chainN, p(1).chainUntil, p(1).pushReadyAt) = (2, double.PositiveInfinity, 0);
            Basic(g, 1);
            Run(g, 1000); // 경직·무적 풀림
        }
        // 1·2타는 표식 없음
        Place(p(1), 3, 4.5, 0);
        Place(p(2), 4.2, 4.5);
        Basic(g, 1);
        Assert.Equal(0, g.MarkOf(p(1), p(2)));
        Run(g, 1000);
        foreach (var n in new[] { 1, 2, 3, 3 })
        {
            Chain();
            Assert.True(g.MarkOf(p(1), p(2)) == n, $"표식 {n}");
        }
        Assert.Contains("  [표식] P1 → P2 3개", lines);
        Assert.Equal(0, g.MarkOf(p(3), p(2)));
        var snap = SnapP(g, 2);
        Assert.Equal(1, snap.GetProperty("marks")[0].Num("by"));
        Assert.Equal(3, snap.GetProperty("marks")[0].Num("n"));
        // 공중 평타는 안 쌓임
        var q = Setup("hunter", "tank");
        Place(q.p(1), 3, 4.5, 0, 1);
        (q.p(1).grounded, q.p(1).vz) = (false, -1);
        Place(q.p(2), 4, 4.5);
        Basic(q.g, 1);
        Assert.True(q.p(2).damage > 0);
        Assert.Equal(0, q.g.MarkOf(q.p(1), q.p(2)));
        // 5초 뒤 사라짐
        Run(g, C.HUNTER_MARK_MS - 1000 - 2 * TICK);
        Assert.Equal(3, g.MarkOf(p(1), p(2)));
        g.DrainEvents();
        Run(g, 3 * TICK);
        Assert.Equal(0, g.MarkOf(p(1), p(2)));
        Assert.True(Events(g).Has("markGone", e => e.Num("by") == 1 && e.Num("target") == 2));
    }

    [Fact]
    public void Hunter_F_tracking_leap_to_nearest_marked_in_range_else_forward_3()
    {
        var (g, _, p) = Setup("hunter", "tank", "builder");
        Place(p(1), 2, 4.5, Math.PI); // 뒤를 보고 있어도
        Place(p(2), 7, 4.5);
        Place(p(3), 9.5, 9.5);
        SetMark(p(2), 1, 1, g.time);
        g.DrainEvents();
        Act(g, 1, "skill");
        Assert.True(Events(g).Has("leapWarn", e => e.NumOr("target") == 2 && e.Num("ms") == C.HUNTER_LEAP_WINDUP_MS));
        Run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
        Assert.True(JsMath.Hypot(p(2).x - p(1).x, p(2).y - p(1).y) <= C.HUNTER_POUNCE_RANGE, $"덮침 거리 {p(2).x - p(1).x:F2}");
        Assert.Equal(C.HUNTER_POUNCE_DAMAGE, p(2).damage);
        Assert.True(p(2).stunUntil > g.time, "경직 → 평타 연결");
        Assert.Equal("pounce", p(2).lastHit!.kind);
        // 표식 없음: 보는 방향 3칸
        Run(g, C.SKILL_CD_MS["hunter"]);
        p(2).marks.Clear();
        Place(p(1), 2, 1.5, 0);
        Act(g, 1, "skill");
        Run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
        Assert.True(Math.Abs(p(1).x - (2 + C.HUNTER_LEAP_DIST)) < 0.3, $"x={p(1).x:F2}");
    }

    [Fact]
    public void Hunter_thrust_not_finisher_combo_continues_no_iframe_pounce_lands_then_basic()
    {
        var (g, _, p) = Setup("hunter", "tank");
        Place(p(1), 3, 5, 0);
        Place(p(2), 4.1, 5);
        for (int i = 0; i < 3; i++)
        {
            Basic(g, 1);
            if (i < 2) Run(g, p(1).pushReadyAt - g.time + TICK);
        }
        Assert.Equal(1, g.MarkOf(p(1), p(2)));
        Assert.Equal(3, p(2).comboHits);
        Assert.True(p(2).iframeUntil <= g.time, "무적 없음");
        Assert.True(p(2).stunUntil - g.time >= C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS, "경직이 F 덮침까지 감");
        Assert.True(Math.Abs(p(2).kbx) < 3, $"밀림 작음 {p(2).kbx}");
        Act(g, 1, "skill"); // 맞힌 후딜 캔슬
        Run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
        Assert.Equal("pounce", p(2).lastHit!.kind);
        Assert.Equal(4, p(2).comboHits);
        Assert.True(p(2).iframeUntil <= g.time);
        double before = p(2).damage;
        Basic(g, 1);
        Assert.True(p(2).damage > before, "덮침 뒤 평타");
    }

    [Fact]
    public void Hunter_F_homing_follows_moving_target_up_to_max()
    {
        (Game g, Func<int, Player> p) LeapTo(double moveY)
        {
            var (g, _, p) = Setup("hunter", "tank");
            Place(p(1), 2, 5, 0);
            Place(p(2), 6, 5);
            SetMark(p(2), 1, 1, g.time);
            Act(g, 1, "skill");
            Run(g, C.HUNTER_LEAP_WINDUP_MS + TICK); // 도약 시작
            for (double t = 0; t < C.HUNTER_LEAP_MS + 2 * TICK; t += TICK)
            {
                (p(2).x, p(2).y) = (6, 5 + Math.Min(moveY, (moveY * t) / C.HUNTER_LEAP_MS)); // 도약 중 옆으로 걸어감
                g.Tick(TICK);
            }
            return (g, p);
        }
        var a = LeapTo(1.2);
        Assert.True(a.p(1).y > 5.4, $"따라감 y {a.p(1).y:F2}");
        Assert.True(JsMath.Hypot(a.p(2).x - a.p(1).x, a.p(2).y - a.p(1).y) <= C.HUNTER_POUNCE_RANGE, "덮칠 거리 안");
        Assert.Equal("pounce", a.p(2).lastHit!.kind);
        var b = LeapTo(5); // 너무 멀리 가면 최대 보정까지만
        Assert.True(b.p(1).y <= 5 + C.HUNTER_LEAP_HOMING_MAX + 0.1, $"최대 보정 y {b.p(1).y:F2}");
        Assert.True(b.p(1).y >= 5 + C.HUNTER_LEAP_HOMING_MAX - 0.4, $"보정은 함 y {b.p(1).y:F2}");
    }

    [Fact]
    public void Hunter_air_down_slash_finisher_shot_knockback_per_mark_marks_10s()
    {
        Assert.Equal(10000, C.HUNTER_MARK_MS);
        Assert.Equal(2.5, C.HUNTER_SHOT_KB_PER_MARK);
        // 평평평 → 점프 → 공중 내려 베기 = 마무리
        var (g, _, p) = Setup("hunter", "tank");
        Place(p(1), 3, 5, 0);
        Place(p(2), 4.1, 5);
        for (int i = 0; i < 3; i++)
        {
            Basic(g, 1);
            Run(g, p(1).pushReadyAt - g.time + TICK);
        }
        Assert.True(p(2).comboHits >= 3);
        (p(1).z, p(1).grounded, p(1).vz, p(1).x, p(1).y, p(1).yaw) = (p(2).z + 0.5, false, 0, p(2).x - 1, p(2).y, 0);
        Basic(g, 1);
        Assert.Equal("push", p(2).lastHit!.kind);
        Assert.Equal(0, p(2).comboHits);
        Assert.True(p(2).iframeUntil > g.time, "마무리 무적");
        // 처형 사격 넉백: 표식 수에 비례
        double Shot(double n)
        {
            var q = Setup("hunter", "tank");
            Place(q.p(1), 2, 5, 0);
            Place(q.p(2), 5, 5);
            SetMark(q.p(2), 1, n, q.g.time);
            q.p(1).ult = q.g.UltMax(q.p(1));
            Act(q.g, 1, "ult");
            Run(q.g, C.HUNTER_SHOT_WINDUP_MS + TICK);
            return JsMath.Hypot(q.p(2).kbx, q.p(2).kby);
        }
        double r = Shot(3) / Shot(1);
        double want = (C.HUNTER_SHOT_KB_BASE + 3 * C.HUNTER_SHOT_KB_PER_MARK) / (C.HUNTER_SHOT_KB_BASE + C.HUNTER_SHOT_KB_PER_MARK);
        Assert.True(Math.Abs(r - want) < 0.05 * want, $"넉백 비 {r:F3} (기대 {want:F3})");
    }

    [Fact]
    public void Hunter_R_execute_double_gauge_cone_marked_targets_consumes_blocked_refund_noTarget()
    {
        var (g, lines, p) = Setup("hunter", "tank", "builder", "ninja");
        Assert.Equal(C.ULT_MAX * 2, g.UltMax(p(1)));
        Assert.Equal(C.ULT_MAX * 2, SnapP(g, 1).Num("ultMax"));
        Place(p(1), 2, 6.5, 0);
        Place(p(2), 6, 6.5); // 표식 2
        Place(p(3), 6, 9.5); // 표식 3
        Place(p(4), 6, 3.5); // 블록 뒤, 표식 1
        SetMark(p(2), 1, 2, g.time);
        SetMark(p(3), 1, 3, g.time);
        SetMark(p(4), 1, 1, g.time);
        for (int z = 0; z < 3; z++) foreach (var y in new[] { 4, 5 }) g.grid[g.Idx(4, y, z)] = Pieces.CELL.TERRAIN; // p4 앞을 가림
        g.GridChanged();
        p(1).ult = C.ULT_MAX; // 1배로는 못 씀
        Act(g, 1, "ult");
        Assert.Equal(C.ULT_MAX, p(1).ult);
        p(1).ult = g.UltMax(p(1));
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.Equal(0, p(1).ult);
        var aim = Events(g).Find("aim")!.Value;
        // JS .sort() 는 글자 순 — 2·3 은 한 자리라 같음
        Assert.Equal(new[] { 2, 3 }, aim.GetProperty("targets").EnumerateArray().Select(v => v.GetInt32()).OrderBy(v => v.ToString(), StringComparer.Ordinal));
        Assert.Equal(0, p(2).damage);
        Run(g, C.HUNTER_SHOT_WINDUP_MS + TICK);
        Assert.Equal(2 * C.HUNTER_SHOT_DAMAGE_PER_MARK, p(2).damage);
        Assert.Equal(3 * C.HUNTER_SHOT_DAMAGE_PER_MARK, p(3).damage);
        Assert.Equal(0, p(4).damage);
        Assert.Equal(0, g.MarkOf(p(1), p(2)));
        Assert.Equal(1, g.MarkOf(p(1), p(4)));
        Assert.Equal(g.UltMax(p(1)), p(1).ult);
        Assert.Equal("execute", p(3).lastHit!.kind);
        Assert.True(lines.Any(l => l.Contains("[필살] P1 처형 사격") && l.Contains("막힘") && l.Contains("게이지 회수")), string.Join("\n", lines));
        // 대상 없음 → 안 쓰임 + ultFail
        Run(g, 2000);
        foreach (var i in new[] { 2, 3, 4 }) p(i).marks.Clear();
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.Equal(g.UltMax(p(1)), p(1).ult);
        Assert.True(Events(g).Has("ultFail", e => e.Str("reason") == "noTarget"));
    }

    [Fact]
    public void Hunter_R_cone_mixed_marked_only_noTarget_keeps_gauge_snapshot_ultTarget()
    {
        var (g, _, p) = Setup("hunter", "tank", "builder");
        Place(p(1), 2, 4.5, 0);
        Place(p(2), 5, 4.5); // 표식 없음
        Place(p(3), 5, 5.8); // 표식 1
        bool SnapT() => SnapP(g, 1).GetProperty("ultTarget").GetBoolean();
        Assert.False(SnapT(), "표식 대상 없음");
        p(1).ult = g.UltMax(p(1));
        g.DrainEvents();
        Act(g, 1, "ult");
        Assert.Equal(g.UltMax(p(1)), p(1).ult);
        Assert.True(Events(g).Has("ultFail", e => e.Str("reason") == "noTarget"));
        SetMark(p(3), 1, 1, g.time);
        Assert.True(SnapT(), "R 대상 있음");
        Act(g, 1, "ult");
        Run(g, C.HUNTER_SHOT_WINDUP_MS + TICK);
        Assert.Equal(0, p(2).damage);
        Assert.Equal(C.HUNTER_SHOT_DAMAGE_PER_MARK, p(3).damage);
        Assert.False(SnapP(g, 2).TryGetProperty("ultTarget", out _), "사냥꾼만");
    }

    // ---------- 대포수 ----------

    [Fact]
    public void Cannon_ammo_max3_full_at_start_reload_swat_when_empty_snapshot_cannon()
    {
        var (g, _, p) = Setup("cannon", "tank");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 2.5, 4.5, Math.PI / 2);
        Assert.Equal(C.CANNON_AMMO_MAX, p(1).cannonAmmo);
        for (int k = 0; k < 3; k++)
        {
            Act(g, 1, "push");
            Run(g, 600);
        }
        Assert.Equal(0, p(1).cannonAmmo);
        g.DrainEvents();
        Act(g, 1, "push");
        Assert.Equal("후려치기", Events(g).Find("attack")!.Value.Str("name"));
        var s = SnapP(g, 1).GetProperty("cannon");
        Assert.Equal(0, s.Num("ammo"));
        Assert.True(s.Num("reloadLeft") > 0 && s.Num("reloadLeft") <= C.CANNON_RELOAD_MS);
        Run(g, C.CANNON_RELOAD_MS * 3 + 100);
        Assert.Equal(3, p(1).cannonAmmo);
        Run(g, C.CANNON_RELOAD_MS);
        Assert.Equal(3, p(1).cannonAmmo);
    }

    [Fact]
    public void Cannon_shell_is_projectile_big_knockback_recoil_bigger_in_air()
    {
        var (g, _, p) = Setup("cannon", "tank");
        Place(p(1), 2.5, 4.5, 0);
        Place(p(2), 7.5, 4.5);
        p(1).pitch = -Math.Atan2(C.EYE_HEIGHT - 0.2 - 0.8, 5); // 상대 가슴
        g.DrainEvents();
        Act(g, 1, "push");
        Run(g, C.BASIC_ATTACKS["cannon"].chain[0].ammo!.windup + TICK);
        Assert.True(Events(g).Has("shellFire", e => e.Num("who") == 1));
        Assert.Equal(1, Snap(g).GetProperty("shells").GetArrayLength());
        Assert.Equal(0, p(2).damage);
        Assert.True(p(1).kbx < 0, "반동으로 뒤로");
        Run(g, 600);
        Assert.Equal(C.CANNON_SHELL_DAMAGE, p(2).damage);
        Assert.Equal("shell", p(2).lastHit!.kind);
        Assert.True(p(2).kbx > 0);
        // 공중 반동이 더 큼
        double ground;
        {
            var q = Setup("cannon", "tank");
            Place(q.p(2), 9.5, 9.5);
            Place(q.p(1), 4.5, 4.5, 0);
            FireShell(q.g, q.p(1), false);
            ground = -q.p(1).kbx;
        }
        double air;
        {
            var q = Setup("cannon", "tank");
            Place(q.p(2), 9.5, 9.5);
            Place(q.p(1), 4.5, 4.5, 0, 2);
            q.p(1).grounded = false;
            FireShell(q.g, q.p(1), false);
            air = -q.p(1).kbx;
        }
        Assert.Equal(C.CANNON_RECOIL, ground);
        Assert.Equal(C.CANNON_RECOIL_AIR, air);
    }

    [Fact]
    public void Cannon_shell_breaks_one_stacked_block_and_stops_not_terrain_or_floor()
    {
        var (g, _, p) = Setup("cannon", "tank");
        Place(p(2), 9.5, 9.5);
        Place(p(1), 2.5, 4.5, 0);
        g.grid[g.Idx(5, 4, 1)] = Pieces.CELL.THROWN;
        g.grid[g.Idx(6, 4, 1)] = Pieces.CELL.THROWN;
        g.GridChanged();
        g.DrainEvents();
        FireShell(g, p(1), false);
        Run(g, 800);
        Assert.Equal(0, g.GridAt(5, 4, 1));
        Assert.Equal(Pieces.CELL.THROWN, g.GridAt(6, 4, 1));
        Assert.True(Events(g).Has("blockBreak", e => e.GetProperty("cells").GetArrayLength() == 1));
        // 시작 지형
        g.grid[g.Idx(5, 4, 1)] = Pieces.CELL.TERRAIN;
        g.GridChanged();
        FireShell(g, p(1), false);
        Run(g, 800);
        Assert.Equal(Pieces.CELL.TERRAIN, g.GridAt(5, 4, 1));
        // 바닥 (아래로 쏨)
        p(1).pitch = -1.2;
        FireShell(g, p(1), false);
        Run(g, 800);
        Assert.Empty(g.shells);
    }

    [Fact]
    public void Cannon_F_ground_blast_launches_up_area_knockback_no_ammo()
    {
        var (g, _, p) = Setup("cannon", "tank");
        Place(p(1), 4.5, 4.5, 0);
        Place(p(2), 5.5, 4.5);
        Act(g, 1, "skill");
        Assert.Equal(C.CANNON_JUMP_UP, p(1).vz);
        Assert.Equal(C.CANNON_FBLAST_DAMAGE, p(2).damage);
        Assert.True(p(2).kbx > 0);
        Assert.Equal(C.CANNON_AMMO_MAX, p(1).cannonAmmo);
        Assert.True(p(1).skillReadyAt > g.time);
    }

    [Fact]
    public void Cannon_R_big_shell_pierces_breaks_stacked_passes_terrain_pushes_people_blast_recoil()
    {
        var (g, lines, p) = Setup("cannon", "tank", "builder");
        Place(p(1), 1.5, 4.5, 0);
        Place(p(2), 4.5, 4.5); // 길 위
        Place(p(3), 9.5, 4.5); // 끝 근처
        foreach (var x in new[] { 3, 6, 7 }) g.grid[g.Idx(x, 4, 1)] = Pieces.CELL.THROWN;
        g.grid[g.Idx(5, 4, 1)] = Pieces.CELL.TERRAIN;
        g.GridChanged();
        p(1).ult = C.ULT_MAX;
        Act(g, 1, "ult");
        Assert.Equal(-C.CANNON_R_RECOIL, p(1).kbx);
        Run(g, (C.CANNON_R_RANGE / C.CANNON_R_SPEED) * 1000 + 200);
        foreach (var x in new[] { 3, 6, 7 }) Assert.True(g.GridAt(x, 4, 1) == 0, $"({x},4,1) 부숨");
        Assert.Equal(Pieces.CELL.TERRAIN, g.GridAt(5, 4, 1));
        Assert.True(p(2).damage >= C.CANNON_R_DAMAGE, "지나가며 밀침");
        Assert.True(p(3).damage >= C.CANNON_R_DAMAGE, "계속 날아가 뒤 사람도");
        Assert.True(lines.Any(l => l.Contains("[필살] P1 대형 포탄 폭발")), string.Join("\n", lines));
    }

    // 안 옮김: 봇 갈고리: 상대 쪽으로 블록이 닿으면 R 블록 내려찍기, 없으면 안 씀. 떨어질 때 안쪽에 블록이 있으면 F 로 걸어 복귀 — 봇 (S5)
    // 안 옮김: 봇 사냥꾼: 표식 대상이 보이면 R, 표식 있는 상대가 떨어져 있으면 F — 봇 (S5)
    // 안 옮김: 봇 대포수: 탄이 있으면 거리를 두고 조준해 포탄을 쏨, 앞에 상대가 있으면 R — 봇 (S5)
}
