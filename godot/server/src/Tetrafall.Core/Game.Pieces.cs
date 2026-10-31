using Tetrafall.Core.Js;
using static Tetrafall.Core.GameUtil;

namespace Tetrafall.Core;

// server/game-pieces.js — 블록: 떨어지기·조종·착지·압사·층 지우기·용암·유령 투하.
// 떨어지는 블록은 여러 개 (pieces). 블록끼리는 공중에서 겹치지 않는다: 한 칸 아래를 다른 블록이 차지하고 있으면 빌 때까지 기다린다
public sealed partial class Game
{
    // 예전 코드·테스트 호환: "대표 블록" = 조종 중인 블록, 없으면 첫 블록 (JS get piece / set piece)
    public Piece? piece
    {
        get => pieces.FirstOrDefault(pc => pc.phase == "control") ?? pieces.FirstOrDefault();
        set
        {
            pieces = value != null ? new List<Piece> { value } : new List<Piece>();
            if (value != null && value.id == 0) value.id = ++pieceCounter;
            RefreshPieceCells();
        }
    }

    // 떨어지는 블록이 이 사람을 깔기까지 남은 시간 (ms). CRUSH_WARN_MS 안에 깔 블록이 없으면 null
    public double? CrushDanger(Player p)
    {
        if (IsGhost(p) || time < p.shieldUntil) return null; // 블록이 통과하는 사람 (유령·부활 무적)
        double? best = null;
        var b = Aabb(p);
        foreach (var piece in pieces)
        {
            if (piece.phase != "falling") continue;
            if (!(piece.pz + 1 > p.z && piece.landZ < p.z + C.PLAYER_HEIGHT)) continue;
            bool over = piece.cells.Any(c =>
            {
                int x = piece.px + c[0], y = piece.py + c[1];
                return x < b.x1 && x + 1 > b.x0 && y < b.y1 && y + 1 > b.y0;
            });
            if (!over) continue;
            // 몸 꼭대기(머리)에 닿을 때까지: 지금 높이에서 머리 위 칸까지 내려오는 칸 수 × 한 칸 간격
            double steps = Math.Max(0, Math.Ceiling(piece.pz - (p.z + C.PLAYER_HEIGHT)));
            double eta = Math.Max(0, steps * piece.stepMs + (piece.nextStepAt - time) - piece.stepMs);
            if (eta <= C.CRUSH_WARN_MS && (best == null || eta < best)) best = eta;
        }
        return best;
    }

    public List<int[]> PieceWorldCells(Piece piece) => piece.cells.Select(c => new[] { piece.px + c[0], piece.py + c[1], piece.pz }).ToList();

    public void RefreshPieceCells()
    {
        pieceCells.Clear();
        foreach (var piece in pieces)
            foreach (var c in PieceWorldCells(piece)) pieceCells[CellKey(c[0], c[1], c[2])] = piece.id;
    }

    public Piece? ControlledPiece(Player p) => pieces.FirstOrDefault(pc => pc.phase == "control" && pc.controller == p.id);

    // 현재 xy 에서 착지 z (착지 가능한 가장 낮은 z). 격자만 본다
    public int ComputeLandZ(Piece piece)
    {
        int landZ = 0;
        foreach (var c in piece.cells)
        {
            int top = ColumnTop(piece.px + c[0], piece.py + c[1]);
            if (top > landZ) landZ = top;
        }
        return landZ;
    }

    public bool PieceFits(Piece piece)
    {
        if (piece.landZ + 1 > H || piece.landZ > piece.pz) return false;
        // 블록 마스터: 조종 중인 블록은 주변보다 너무 높게 못 놓음 (빨간 미리보기)
        if (mode == "master" && piece.phase == "control" && TooTall(piece.cells.Select(c => (piece.px + c[0], piece.py + c[1])), piece.landZ)) return false;
        return true;
    }

    public void UpdateLanding(Piece piece)
    {
        piece.landZ = ComputeLandZ(piece);
        piece.fits = PieceFits(piece);
    }

    public Piece MakePiece(string shape, double rot, int px, int py, int pz)
    {
        var piece = new Piece { id = 0, shape = shape, rot = rot, cells = Pieces.RotatedCells(shape, rot), px = px, py = py, pz = pz, landZ = 0, fits = false };
        UpdateLanding(piece);
        return piece;
    }

    // ---- 판이 길어질수록 빨라지고 많아진다 ----
    public double Elapsed() => time - roundStartTime;

    public double RampT() => Math.Min(1, Math.Max(0, Elapsed() / C.RAMP_FULL_MS));

    public double AutoFallStepMs() => C.AUTO_FALL_STEP_MS + (C.AUTO_FALL_STEP_MIN_MS - C.AUTO_FALL_STEP_MS) * RampT();

    public double AutoSpawnDelayMs() => C.AUTO_SPAWN_DELAY_MS + (C.AUTO_SPAWN_DELAY_MIN_MS - C.AUTO_SPAWN_DELAY_MS) * RampT();

    public double TargetConcurrent() => Math.Max(1, JsMath.Round(Math.Min(C.CONCURRENT_MAX, C.CONCURRENT_START + Math.Floor(Elapsed() / C.CONCURRENT_RAMP_MS)) * AreaScale())); // 넓은 판은 넓이만큼 더

    // JS addPiece(piece, fields): id 를 붙이고 fields 를 넣은 뒤 목록에. fields 는 set 이 채움
    public Piece AddPiece(Piece piece, Action<Piece> fields)
    {
        piece.id = ++pieceCounter;
        fields(piece);
        pieces.Add(piece);
        RefreshPieceCells();
        return piece;
    }

    // randomSpot: 블록 마스터는 무작위 자리에서 시작
    public Piece SpawnControlled(Player controller, bool randomSpot = false)
    {
        string shape = Pieces.SHAPE_NAMES[(int)Math.Floor(rng() * Pieces.SHAPE_NAMES.Length)];
        double rot = Math.Floor(rng() * 4);
        var (w, d) = Pieces.Footprint(Pieces.RotatedCells(shape, rot));
        int px = randomSpot ? (int)Math.Floor(rng() * (W - w + 1)) : (int)Math.Floor((W - w) / 2.0);
        int py = randomSpot ? (int)Math.Floor(rng() * (D - d + 1)) : (int)Math.Floor((D - d) / 2.0);
        var piece = MakePiece(shape, rot, px, py, (int)C.CONTROL_HOVER_Z);
        AddPiece(piece, pc =>
        {
            pc.phase = "control";
            pc.controller = controller.id;
            pc.stepMs = C.HARD_DROP_STEP_MS;
            pc.nextStepAt = 0;
            pc.controlEndsAt = time + C.CONTROL_TIME_MS;
        });
        UpdateLanding(piece); // 조종 블록이 된 뒤 다시 (블록 마스터 높이 제한)
        controller.hasControl = false;
        Emit(o => o.P("type", "controlStart").P("who", controller.id));
        Log($"  [블록] {shape} 조종 시작: {controller.name}");
        return piece;
    }

    public Piece? SpawnAuto()
    {
        string shape = Pieces.SHAPE_NAMES[(int)Math.Floor(rng() * Pieces.SHAPE_NAMES.Length)];
        var piece = ChooseAutoPlacement(shape);
        if (piece == null) return null;
        double stepMs = AutoFallStepMs();
        return AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.stepMs = stepMs;
            pc.nextStepAt = time + stepMs;
            pc.controlEndsAt = 0;
        });
    }

    // 예전 호환: 조종권 보유자가 있으면 조종 블록, 없으면 자동 블록 하나
    public Piece? SpawnPiece()
    {
        var holder = Players().FirstOrDefault(p => p.alive && p.hasControl);
        if (holder != null && !pieces.Any(pc => pc.controller != null)) return SpawnControlled(holder);
        return SpawnAuto();
    }

    public void UpdateSpawning()
    {
        if (mode == "practice" && PracticeNoBlocks()) return; // 연습: 블록 안 떨어짐
        if (time < nextSpawnAt) return;
        if (mode == "master")
        {
            // 블록 마스터: 자동 블록 없이 마스터 편 각자의 블록만 (반격 아이템을 먹은 동안은 안 나옴)
            foreach (var p in Players().ToList())
            {
                if (p.master && p.alive && time >= p.nextPieceAt && time >= masterStallUntil && ControlledPiece(p) == null) SpawnControlled(p, true);
            }
            return;
        }
        var holder = Players().FirstOrDefault(p => p.alive && p.hasControl);
        if (holder != null && !pieces.Any(pc => pc.controller != null))
        {
            SpawnControlled(holder);
            nextSpawnAt = time + AutoSpawnDelayMs();
            return;
        }
        if (sky)
        {
            FillSky();
            return;
        }
        int autos = pieces.Count(pc => pc.controller == null && pc.thrownBy == null); // 던진 블록은 안 셈
        if (autos >= TargetConcurrent()) return;
        SpawnAuto(); // 자리가 없으면 다음 간격에 다시
        nextSpawnAt = time + AutoSpawnDelayMs();
    }

    // 용암에 녹은 하늘 블록: 격자에 안 남고 사라짐
    public void MeltPiece(Piece piece)
    {
        var cells = PieceWorldCells(piece);
        Emit(o =>
        {
            o.P("type", "melt").Key("cells").Arr();
            foreach (var c in cells) o.Arr().Num(c[0]).Num(c[1]).Num(c[2]).EndArr();
            o.EndArr();
        });
        Log($"  [하늘] {piece.shape} 용암에 녹음 (z={piece.pz})");
        RemovePiece(piece);
    }

    public void MovePiece(Piece piece, int dx, int dy)
    {
        var (w, d) = Pieces.Footprint(piece.cells);
        int nx = Math.Max(0, Math.Min(W - w, piece.px + dx));
        int ny = Math.Max(0, Math.Min(D - d, piece.py + dy));
        if (nx == piece.px && ny == piece.py) return;
        piece.px = nx;
        piece.py = ny;
        UpdateLanding(piece);
        RefreshPieceCells();
    }

    public void RotatePiece(Piece piece, int dir)
    {
        double rot = (piece.rot + dir + 4) % 4;
        var cells = Pieces.RotatedCells(piece.shape, rot);
        var (w, d) = Pieces.Footprint(cells);
        piece.rot = rot;
        piece.cells = cells;
        piece.px = Math.Max(0, Math.Min(W - w, piece.px));
        piece.py = Math.Max(0, Math.Min(D - d, piece.py));
        UpdateLanding(piece);
        RefreshPieceCells();
    }

    // reason: 'hard' = 조종자가 Enter, 'timeout' = 8초 초과, 'left' = 조종자 사망·이탈
    public void DropPiece(Piece? piece, string reason = "hard")
    {
        if (piece == null || !piece.fits) return; // 그 자리엔 못 넣는다 (기둥이 꽉 참)
        var who = GetPlayer(piece.controller);
        piece.phase = "falling";
        piece.stepMs = mode == "master" && who != null && who.master ? masterDropStep : C.HARD_DROP_STEP_MS; // 블록 마스터 편은 인원별 빠르기
        piece.nextStepAt = time + piece.stepMs;
        string name = who != null ? who.name : "?";
        if (mode == "master" && who != null && who.master) who.nextPieceAt = time + C.MASTER_NEXT_PIECE_MS;
        string what = reason == "hard" ? $"하드드롭 by {name}" : reason == "timeout" ? $"자동 낙하 (8초 초과, 조종자 {name})" : $"자동 낙하 (조종자 {name} 사망·이탈)";
        Log($"  [블록] {piece.shape} {what} → ({piece.px},{piece.py}) 착지 z={piece.landZ}");
    }

    // 조종권을 먹은 순간 바로 조종을 시작한다 (CONTROL_TAKEOVER)
    public void StartControlNow(Player p)
    {
        if (!C.CONTROL_TAKEOVER || !p.hasControl) return;
        if (pieces.Any(pc => pc.controller != null)) return;
        Piece? piece = null;
        foreach (var pc in pieces) if (pc.phase == "falling" && pc.thrownBy == null && !pc.sky && pc.ghostBy == null && (piece == null || pc.pz > piece.pz)) piece = pc; // 던진·하늘·유령 블록은 못 뺏음
        if (piece == null)
        {
            SpawnControlled(p);
            return;
        }
        piece.pz = (int)C.CONTROL_HOVER_Z;
        piece.phase = "control";
        piece.controller = p.id;
        piece.stepMs = C.HARD_DROP_STEP_MS;
        piece.nextStepAt = 0;
        piece.controlEndsAt = time + C.CONTROL_TIME_MS;
        p.hasControl = false;
        UpdateLanding(piece);
        RefreshPieceCells();
        Emit(o => o.P("type", "controlStart").P("who", p.id));
        Log($"  [블록] {piece.shape} 조종 시작: {p.name} (떨어지던 블록 넘겨받음)");
    }

    public void RemovePiece(Piece piece)
    {
        pieces.Remove(piece);
        RefreshPieceCells();
    }

    public void DiscardPiece(Piece piece, string reason)
    {
        Log($"  [블록] {piece.shape} 폐기 ({reason})");
        RemovePiece(piece);
        nextSpawnAt = Math.Max(nextSpawnAt, time + (mode == "master" ? C.MASTER_NEXT_PIECE_MS : AutoSpawnDelayMs()));
        if (piece.controller != null) controlItemNextAt = time + C.CONTROL_ITEM_RESPAWN_MS;
    }

    // 한 칸 아래에 다른 블록이 있으면 true (그 블록이 비킬 때까지 기다린다)
    public bool BlockedByPiece(Piece piece)
    {
        foreach (var c in PieceWorldCells(piece))
        {
            if (pieceCells.TryGetValue(CellKey(c[0], c[1], c[2] - 1), out var other) && other != piece.id) return true;
        }
        return false;
    }

    public void UpdatePieces()
    {
        UpdateSpawning();
        prof?.Lap("spawn");
        foreach (var piece in pieces.ToList())
        {
            if (piece.phase == "control")
            {
                var ctl = GetPlayer(piece.controller);
                if (ctl == null || !ctl.alive)
                {
                    // 조종자가 죽거나 나가면 그 자리에서 자동 낙하 (안 맞으면 폐기)
                    if (piece.fits) DropPiece(piece, "left");
                    else DiscardPiece(piece, "조종자 이탈, 자리 없음");
                }
                else if (time >= piece.controlEndsAt)
                {
                    if (piece.fits) DropPiece(piece, "timeout");
                    else DiscardPiece(piece, "시간 초과, 자리 없음");
                }
                continue;
            }
            // falling
            if (MeltsInLava(piece))
            {
                MeltPiece(piece);
                continue;
            }
            while (pieces.Contains(piece) && time >= piece.nextStepAt)
            {
                if (piece.pz <= piece.landZ)
                {
                    prof?.Lap("fall");
                    LandPiece(piece);
                    prof?.Lap("land");
                    break;
                }
                piece.nextStepAt += piece.stepMs;
                if (BlockedByPiece(piece)) continue;
                piece.pz--;
                RefreshPieceCells();
                CrushCheck(piece);
                if (MeltsInLava(piece))
                {
                    MeltPiece(piece);
                    break;
                }
                if (piece.pz <= piece.landZ)
                {
                    prof?.Lap("fall");
                    LandPiece(piece);
                    prof?.Lap("land");
                    break;
                }
            }
        }
        prof?.Lap("fall");
    }

    // 하늘 블록은 용암이 켜진 뒤 아래면이 용암 표면에 닿으면 녹는다
    public bool MeltsInLava(Piece piece) => piece.sky && lava.active && piece.pz <= lava.z && piece.pz > piece.landZ;

    // 그림자(경고)를 보일지: 보통 블록은 착지 SHADOW_LEAD_MS 전부터, 하늘 블록은 착지 높이 + SKY_SHADOW_CELLS 안
    public bool ShadowVisible(Piece piece, double eta)
    {
        if (piece.phase != "falling") return false;
        return piece.sky ? piece.pz - piece.landZ <= C.SKY_SHADOW_CELLS : eta <= C.SHADOW_LEAD_MS;
    }

    // 블록 셀이 플레이어 AABB 와 겹치면 압사
    public void CrushCheck(Piece piece)
    {
        var cells = PieceWorldCells(piece);
        foreach (var p in Players().ToList())
        {
            if (!OnField(p) || IsGhost(p) || time < p.shieldUntil) continue; // 유령·부활 무적은 블록이 통과
            foreach (var c in cells)
            {
                int cx = c[0], cy = c[1], cz = c[2];
                if (
                    cx < p.x + C.PLAYER_HALF - EPS &&
                    cx + 1 > p.x - C.PLAYER_HALF + EPS &&
                    cy < p.y + C.PLAYER_HALF - EPS &&
                    cy + 1 > p.y - C.PLAYER_HALF + EPS &&
                    cz < p.z + C.PLAYER_HEIGHT - EPS &&
                    cz + 1 > p.z + EPS)
                {
                    if (HeadBonk(p, piece)) break; // 머리 박음: 아래로 빠져나갈 공간이 있으면 안 깔림
                    if (piece.thrownBy != null)
                    {
                        var by = GetPlayer(piece.thrownBy);
                        Log($"  [투척] {(by != null ? by.name : "?")} 의 {piece.shape} 에 {p.name} 깔림");
                    }
                    // 조종한 블록·던진 블록이면 그 사람의 킬, 자동 블록이면 마지막으로 날린 사람
                    LastHit? src = piece.controller != null ? new LastHit { by = piece.controller.Value, kind = "control" }
                        : piece.thrownBy != null ? new LastHit { by = piece.thrownBy.Value, kind = "thrown" }
                        : piece.ghostBy != null ? new LastHit { by = piece.ghostBy.Value, kind = "ghost" } : null;
                    Kill(p, "crush", src);
                    break;
                }
            }
        }
    }

    // 머리 박음: 블록 아래면에서 몸 아래 기둥 꼭대기(필드 밖이면 끝없이)까지 빈 공간이 CRUSH_ESCAPE_CELLS 칸 이상이면 압사 대신 블록 아래로
    public bool HeadBonk(Player p, Piece piece)
    {
        int bottom = piece.pz;
        double floor = double.NegativeInfinity;
        double h = C.PLAYER_HALF - EPS;
        for (int cx = (int)Math.Floor(p.x - h); cx <= (int)Math.Floor(p.x + h); cx++)
        {
            for (int cy = (int)Math.Floor(p.y - h); cy <= (int)Math.Floor(p.y + h); cy++)
            {
                if (!InXY(cx, cy)) continue; // 필드 밖은 바닥이 없음
                int top = 0;
                for (int z = Math.Min(bottom, H) - 1; z >= 0; z--)
                {
                    if (grid[Idx(cx, cy, z)] != 0 || (pieceCells.TryGetValue(CellKey(cx, cy, z), out var id) && id != piece.id))
                    {
                        top = z + 1;
                        break;
                    }
                }
                floor = Math.Max(floor, top);
            }
        }
        if (bottom - floor < C.CRUSH_ESCAPE_CELLS) return false;
        p.z = bottom - C.PLAYER_HEIGHT;
        p.vz = Math.Min(p.vz, 0);
        p.grounded = false;
        p.stunUntil = Math.Max(p.stunUntil, time + C.HEAD_BONK_STUN_MS);
        Emit(o => o.P("type", "headBonk").P("who", p.id).P("x", p.x).P("y", p.y).P("z", p.z));
        Log($"  [머리 박음] {p.name} ← {piece.shape} (빈 공간 {(double.IsFinite(floor) ? JsNumber.ToJs(bottom - floor) : "∞")}칸)");
        return true;
    }

    public void LandPiece(Piece piece)
    {
        landed[piece.ghostBy != null ? "ghost" : piece.sky ? "sky" : piece.controller != null ? "control" : piece.thrownBy != null ? "item" : "auto"]++;
        byte cell = PieceCellValue(piece); // 색 구분용
        foreach (var c in PieceWorldCells(piece))
        {
            if (c[2] >= 0 && c[2] < H)
            {
                grid[Idx(c[0], c[1], c[2])] = cell;
                gridPiece[Idx(c[0], c[1], c[2])] = piece.id;
            }
        }
        var cells = PieceWorldCells(piece);
        bool controlled = piece.controller != null;
        Emit(o =>
        {
            o.P("type", "land").Key("cells").Arr();
            foreach (var c in cells) o.Arr().Num(c[0]).Num(c[1]).Num(c[2]).EndArr();
            o.EndArr().P("controlled", controlled);
        });
        bool wasControlled = piece.controller != null;
        if (piece.thrownBy != null) BrickShock(piece);
        RemovePiece(piece);
        gridVersion++;
        gridDirty = true;
        ClearLayers();
        if (mode == "kills") SinkIfTall();
        foreach (var pc in pieces) UpdateLanding(pc);
        if (piece.thrownBy == null && !piece.sky && mode != "master") nextSpawnAt = Math.Max(nextSpawnAt, time + AutoSpawnDelayMs()); // 던진 블록은 자동 블록 간격에 안 끼어듦
        if (wasControlled)
        {
            controlItemNextAt = time + C.CONTROL_ITEM_RESPAWN_MS;
            // 남의 조종 블록이 끝나길 기다리던 조종권 보유자는 바로 조종 시작
            var holder = Players().FirstOrDefault(p => p.alive && p.hasControl);
            if (holder != null) StartControlNow(holder);
        }
        foreach (var it in items) it.z = ColumnTop(it.x, it.y);
    }

    // 한 층이 꽉 차면 제거하고 위의 블록·플레이어·아이템을 내린다 (용암도 같이)
    public void ClearLayers()
    {
        int layerSize = W * D;
        var full = new List<int>();
        for (int z = 0; z < H; z++)
        {
            bool ok = true;
            for (int i = 0; i < layerSize && ok; i++) if (grid[z * layerSize + i] == 0) ok = false;
            if (ok) full.Add(z);
        }
        if (full.Count == 0) return;
        DropLayers(full);
        Emit(o => o.P("type", "clear").P("n", full.Count));
        Log($"  [층 클리어] z={string.Join(",", full)} 제거 → 위 블록·플레이어 {full.Count}칸 내려앉음");
    }

    // 킬 점수전: 가장 높은 기둥이 KILLS_SINK_HEIGHT 에 닿으면 맨 아래 층을 지워 전체를 한 칸씩 내림
    public void SinkIfTall()
    {
        int n = 0;
        while (MaxColumnTop() >= C.KILLS_SINK_HEIGHT)
        {
            DropLayers(new List<int> { 0 });
            n++;
        }
        if (n > 0) Log($"  [가라앉음] 가장 높은 기둥 {JsNumber.ToJs(C.KILLS_SINK_HEIGHT)}칸 → 맨 아래 {n}층 지움, 전체가 {n}칸 내려앉음");
    }

    public int MaxColumnTop()
    {
        int top = 0;
        for (int x = 0; x < W; x++) for (int y = 0; y < D; y++) top = Math.Max(top, ColumnTop(x, y));
        return top;
    }

    // 층들을 지우고 위의 블록·플레이어·용암을 그만큼 내린다
    public void DropLayers(List<int> full)
    {
        int layerSize = W * D;
        var next = new byte[grid.Length];
        var nextPiece = new int[grid.Length];
        int dst = 0;
        for (int z = 0; z < H; z++)
        {
            if (full.Contains(z)) continue;
            Array.Copy(grid, z * layerSize, next, dst * layerSize, layerSize);
            Array.Copy(gridPiece, z * layerSize, nextPiece, dst * layerSize, layerSize);
            dst++;
        }
        grid = next;
        gridPiece = nextPiece;
        gridVersion++;
        gridDirty = true;
        foreach (var p in Players())
        {
            if (p.master) continue; // 마스터는 필드 위 하늘에 둔 채로
            int shift = 0;
            foreach (var z in full) if (p.z >= z + 1 - 1e-3) shift++;
            p.z -= shift;
        }
        if (lava.active) lava.z -= full.Count(z => z < lava.z);
        // 건축가 블록·구멍 기록도 같이 내림 (지워진 층에 있던 것은 버림)
        var moved = new OrderedDictionary<long, BBlock>();
        foreach (var b in bblocks.Values)
        {
            if (full.Contains(b.z)) continue;
            b.z -= full.Count(z => z < b.z);
            moved[CellKey(b.x, b.y, b.z)] = b;
        }
        bblocks = moved;
        foreach (var q in quakes) q.cells = q.cells.Where(c => !full.Contains(c[2])).Select(c => new[] { c[0], c[1], c[2] - full.Count(f => f < c[2]) }).ToList();
        holes = holes.Where(h => !full.Contains(h.z)).ToList();
        foreach (var h in holes) h.z -= full.Count(z => z < h.z);
    }

    // ---------- 용암 ----------
    public double AvgHeight()
    {
        double sum = 0;
        for (int x = 0; x < W; x++) for (int y = 0; y < D; y++) sum += ColumnTop(x, y);
        return sum / (W * D);
    }

    public void UpdateLava(double dtMs)
    {
        if (mode == "practice" && PracticeNoBlocks()) return; // 연습: 용암 없음
        if (mode == "kills") return; // 킬 점수전은 용암 대신 아래층을 지움 (sinkIfTall)
        if (!lava.active)
        {
            bool piled = AvgHeight() - baseAvgHeight >= C.LAVA_TRIGGER_AVG_HEIGHT; // 시작 지형 빼고 쌓인 만큼
            bool late = sky && Elapsed() >= skyLavaMs; // 하늘 계단: 시간이 지나도 시작
            if (!piled && !late) return;
            lava.active = true;
            lava.z = C.LAVA_START_Z;
            lava.startedAt = time;
            Emit(o => o.P("type", "lava"));
            Log($"  [용암] {(piled ? "" : $"{FmtTime(skyLavaMs)} 지남 (하늘 계단), ")}쌓인 평균 높이 {JsNumber.ToFixed(AvgHeight() - baseAvgHeight, 2)} → 용암 상승 시작 @ {FmtTime(Elapsed())}");
            return;
        }
        lava.z = Math.Min(H + 1, lava.z + dtMs / C.LAVA_RISE_MS_PER_CELL);
        // 필드 밖에서 용암 높이 아래로 가면 밀려 떨어진 것이라 낙사로 센다
        foreach (var p in Players().ToList())
        {
            if (!OnField(p) || p.z >= lava.z - 0.05) continue;
            bool inField = p.x >= 0 && p.x < W && p.y >= 0 && p.y < D;
            Kill(p, inField ? "lava" : "fall");
        }
        items = items.Where(it => it.z >= lava.z).ToList();
    }

    // ---------- 유령 투하 ----------
    // 이 사람이 유령 투하를 할 수 있는 상태면 남은 쿨 ms (0 = 바로), 아니면 null
    public double? GhostCd(Player p)
    {
        if (!C.GHOST_DROP_ENABLED || phase != "playing" || mode != "survival") return null;
        if (p.alive || p.spectator || p.master || p.dummy || (p.isBot && !C.GHOST_DROP_BOTS) || !players.ContainsKey(p.id)) return null;
        return Math.Max(0, (p.ghostReadyAt ?? 0) - time);
    }

    // 받은 메시지 값 그대로 (rooms): JS Number(x)
    public bool GhostDrop(int id, System.Text.Json.JsonElement? x, System.Text.Json.JsonElement? y) => GhostDrop(id, JsValue.ToNumber(x), JsValue.ToNumber(y)) != null;

    // 죽은 사람이 (x, y) 칸에 1칸 블록을 떨어뜨림. 되면 블록, 안 되면 ghostDropFail 이벤트 + null
    public Piece? GhostDrop(int id, double rx, double ry)
    {
        var p = GetPlayer(id);
        if (p == null) return null;
        Piece? Fail(string reason)
        {
            Emit(o => o.P("type", "ghostDropFail").P("who", id).P("reason", reason));
            return null;
        }
        if (!C.GHOST_DROP_ENABLED || phase != "playing" || mode != "survival") return Fail("mode");
        var cd = GhostCd(p);
        if (cd == null) return Fail("notDead");
        if (cd > 0) return Fail("cooldown");
        double fx = Math.Floor(rx), fy = Math.Floor(ry);
        if (!double.IsFinite(fx) || !double.IsFinite(fy) || fx < 0 || fx >= W || fy < 0 || fy >= D) return Fail("outside");
        int x = (int)fx, y = (int)fy;
        int top = ColumnTop(x, y);
        if (top >= H) return Fail("full");
        if (pieces.Any(pc => pc.cells.Any(c => pc.px + c[0] == x && pc.py + c[1] == y))) return Fail("busy");
        int pz = (int)Math.Min(top + (sky ? C.GHOST_DROP_UP_SKY : C.GHOST_DROP_UP), H - 1); // 켬 판은 느려서 낮게
        double stepMs = sky ? C.SKY_FALL_STEP_MS : AutoFallStepMs(); // 그 판 보통 블록 속도
        var piece = new Piece { id = 0, shape = "ghost", rot = 0, cells = new[] { new[] { 0, 0 } }, px = x, py = y, pz = pz, landZ = top, fits = true };
        AddPiece(piece, pc =>
        {
            pc.phase = "falling";
            pc.controller = null;
            pc.ghostBy = p.id;
            pc.ghostSlot = p.slot;
            pc.ghostColor = p.color;
            pc.stepMs = stepMs;
            pc.nextStepAt = time + stepMs;
            pc.controlEndsAt = 0;
        });
        UpdateLanding(piece);
        p.ghostReadyAt = time + C.GHOST_DROP_CD_MS;
        Emit(o => o.P("type", "ghostDrop").P("who", p.id).P("x", x).P("y", y).P("z", pz).P("slot", p.slot).P("color", p.color));
        Log($"  [유령] {p.name} → ({x},{y}) 투하");
        return piece;
    }
}
