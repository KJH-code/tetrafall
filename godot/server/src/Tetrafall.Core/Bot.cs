using System.Reflection;
using Tetrafall.Core.Js;

namespace Tetrafall.Core;

// server/bot.js — 서버 안에서 도는 AI 봇. 사람과 똑같이 HandleInput / HandleAction 으로만 조작한다 (판정 특혜 없음).
// BOT_THINK_MS 마다 한 번 판단하고, 그 사이에는 마지막 입력을 유지한다. rng() 를 부르는 곳·순서는 JS 와 같게 (판 재현)
public sealed class BotBrain
{
    // 판 크기: JS 의 모듈 변수 W·D (update·useSkills·ghostDrop 첫머리에서 그 게임 크기로). 테스트가 여러 스레드라 스레드마다
    [ThreadStatic] static int W;
    [ThreadStatic] static int D;

    static string PieceKey(Piece piece) => $"{piece.id}:{piece.px},{piece.py},{JsNumber.ToJs(piece.rot)},{JsNumber.ToJs(piece.stepMs)}";

    static double EdgeDist(double x, double y) => Math.Min(Math.Min(x, W - x), Math.Min(y, D - y));

    // 서 있을 자리용: 필드 끝에서 BOT_EDGE_MARGIN 칸 안
    static double ClampSafe(double v, double max)
    {
        double m = Math.Min(C.BOT_EDGE_MARGIN, max / 2);
        return Math.Max(m, Math.Min(max - m, v));
    }

    // 플레이어 AABB 가 칸 목록 중 하나와 겹치는가 (xy 만)
    static bool OverlapsCells(double x, double y, IEnumerable<int[]> cells)
    {
        double h = C.PLAYER_HALF;
        foreach (var c in cells)
            if (c[0] < x + h && c[0] + 1 > x - h && c[1] < y + h && c[1] + 1 > y - h) return true;
        return false;
    }

    static bool OverlapsCells(Player p, IEnumerable<int[]> cells) => OverlapsCells(p.x, p.y, cells);

    public readonly Func<double> rng;
    readonly Func<string> level;
    public double nextThinkAt;
    public readonly BotInput input = new();
    readonly Dictionary<string, double> dangerSeen = new(); // 블록 위치 키 → 그림자를 처음 본 시각
    readonly Dictionary<string, (double at, bool dodge)> threatSeen = new(); // 상대 예고 키 → 처음 본 시각·피할지
    double? aimedAt; // 조종 중: 목표 위에 맞춘 시각
    (int piece, double x, double y)? dropOffset; // 조종 중: 이 블록에서 겨냥을 빗나가게 할 만큼
    XY? lastPos;
    double stuckMs;
    double unstickUntil;
    double unstickDir = 1;
    double nextPushAt;
    double chainDelay;
    double nextSkillAt;
    readonly Dictionary<int, double> targetBias = new(); // 상대 id → 판마다 다시 뽑는 무작위 가산 거리
    double biasRound = -1;
    (double yaw, double pitch)? shellErr; // 대포수·바드 조준 오차

    public sealed class BotInput
    {
        public double fwd, strafe, yaw, pitch;
        public bool jump;
    }

    public BotBrain(Func<double> rng, Func<string> level)
    {
        this.rng = rng;
        this.level = level;
    }

    static readonly Dictionary<string, double> BotConst = typeof(C).GetFields(BindingFlags.Public | BindingFlags.Static)
        .Where(f => f.Name.StartsWith("BOT_") && f.FieldType == typeof(double)).ToDictionary(f => f.Name, f => (double)f.GetValue(null)!);

    // 난이도가 걸린 수치: BOT_<name> × 난이도 배수
    public double K(string name)
    {
        double mult = C.BOT_LEVELS.TryGetValue(level(), out var lv) && lv.TryGetValue(name, out var m) ? m : 1;
        return BotConst["BOT_" + name] * mult;
    }

    void Send(Game g, Player p) => g.HandleInput(p.id, new InputMsg { fwd = input.fwd, strafe = input.strafe, jump = input.jump, yaw = input.yaw, pitch = input.pitch });

    static void Act(Game g, Player p, string name) => g.HandleAction(p.id, new ActionMsg { name = name });

    public void Update(Game g, Player p)
    {
        W = g.W;
        D = g.D;
        if (!p.alive || g.phase != "playing") return;
        if (g.time < nextThinkAt)
        {
            Send(g, p);
            return;
        }
        nextThinkAt = g.time + C.BOT_THINK_MS;
        TrackStuck(g, p);
        Think(g, p);
        Send(g, p);
    }

    void TrackStuck(Game g, Player p)
    {
        if (lastPos != null && input.fwd != 0)
        {
            double moved = JsMath.Hypot(p.x - lastPos.x, p.y - lastPos.y);
            stuckMs = moved < 0.05 ? stuckMs + C.BOT_THINK_MS : 0;
        }
        else stuckMs = 0;
        lastPos = new XY(p.x, p.y);
        if (stuckMs >= 500)
        {
            unstickUntil = g.time + 400;
            unstickDir = rng() < 0.5 ? -1 : 1;
            stuckMs = 0;
        }
    }

    // ---------- 상황 읽기 ----------
    List<Player> Enemies(Game g, Player p) => g.Players().Where(o => o != p && g.OnField(o) && !g.SameTeam(o, p)).ToList();

    sealed record Danger(List<int[]> cells, double eta, string key);

    // 그림자가 보이는 떨어지는 블록들 (p 를 주면 발밑보다 낮은 하늘 블록은 뺌) + 놓인 폭탄 범위
    List<Danger> VisibleDangers(Game g, Player? p = null)
    {
        var out_ = new List<Danger>();
        foreach (var piece in g.pieces)
        {
            if (piece.phase != "falling") continue;
            if (p != null && piece.sky && piece.pz + 1 <= p.z + 0.05) continue;
            double eta = Math.Max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - g.time));
            if (!g.ShadowVisible(piece, eta)) continue;
            out_.Add(new Danger(piece.cells.Select(c => new[] { piece.px + c[0], piece.py + c[1] }).ToList(), eta, PieceKey(piece)));
        }
        int R = (int)Math.Ceiling(C.BOMB_BLAST_RANGE);
        foreach (var b in g.bombs)
        {
            var cells = new List<int[]>();
            for (int dx = -R; dx <= R; dx++)
                for (int dy = -R; dy <= R; dy++)
                    if (JsMath.Hypot(dx, dy) <= C.BOMB_BLAST_RANGE + C.BOT_BOMB_DANGER_PAD) cells.Add(new[] { b.x + dx, b.y + dy });
            out_.Add(new Danger(cells, Math.Max(0, b.explodeAt - g.time), $"bomb:{b.id}"));
        }
        return out_;
    }

    sealed record Threat(string key, Player o, double left, bool radial = false);

    // 나를 노리는 상대 예고
    List<Threat> Telegraphs(Game g, Player p, List<Player> enemies)
    {
        var out_ = new List<Threat>();
        foreach (var o in enemies)
        {
            double dx = p.x - o.x, dy = p.y - o.y;
            double d = JsMath.Hypot(dx, dy);
            if (Math.Abs(p.z - o.z) > 2.5) continue;
            bool Ahead(double yaw, double len, double half)
            {
                double along = dx * JsMath.Cos(yaw) + dy * JsMath.Sin(yaw);
                double side = Math.Abs(-dx * JsMath.Sin(yaw) + dy * JsMath.Cos(yaw));
                return along > -0.3 && along <= len && side <= half;
            }
            bool InCone(double yaw, double len, double deg) => d <= len && (d < 0.5 || (dx * JsMath.Cos(yaw) + dy * JsMath.Sin(yaw)) / d >= JsMath.Cos(((deg / 2) * Math.PI) / 180));
            string T(double v) => JsNumber.ToJs(v);
            if (o.windup != null)
            {
                double reach = o.@char == "tank" ? C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000) : o.@char == "ninja" ? C.NINJA_BLINK_DIST : C.HOOK_RANGE;
                if (Ahead(o.windup.yaw, reach + 0.5, 0.9)) out_.Add(new Threat($"{o.id}:windup:{T(o.windup.at)}", o, o.windup.at - g.time));
            }
            if (o.slamAt != 0 && d <= C.TANK_SLAM_RANGE + C.TANK_RING_WIDTH + 0.3) out_.Add(new Threat($"{o.id}:slam:{T(o.slamAt)}", o, o.slamAt - g.time, true));
            if (o.atk != null && o.atk.def.finish && !o.atk.def.shell && Ahead(o.yaw, (o.atk.def.range is double r && r != 0 ? r : C.PUSH_RANGE) + 0.4, 1)) out_.Add(new Threat($"{o.id}:fin:{T(o.atk.at)}", o, o.atk.at - g.time));
            if (o.leap != null && o.leap.endAt == 0 && o.leap.target == p.id) out_.Add(new Threat($"{o.id}:leap:{T(o.leap.at)}", o, o.leap.at - g.time));
            if (o.huntAim != null && g.MarkOf(o, p) > 0 && InCone(o.yaw, C.HUNTER_SHOT_RANGE, C.HUNTER_SHOT_ANGLE_DEG)) out_.Add(new Threat($"{o.id}:aim:{T(o.huntAim.at)}", o, o.huntAim.at - g.time));
            if (o.spin != null && d <= C.BERSERKER_SPIN_END_RANGE + 0.5) out_.Add(new Threat($"{o.id}:spin:{T(o.spin.endAt)}", o, o.spin.endAt - g.time, true));
            if (o.amp != null && InCone(g.AmpYaw(o), C.BARD_AMP_RANGE + 0.5, C.BARD_AMP_ANGLE_DEG + 10)) out_.Add(new Threat($"{o.id}:amp:{T(o.amp.endAt)}", o, o.amp.endAt - g.time));
        }
        return out_;
    }

    // 예고를 처음 본 뒤 BOT_REACTION_MS 가 지나면, 예고마다 한 번 정한 확률로 옆(범위 공격이면 바깥)으로 피함. 피했으면 true
    bool DodgeTelegraph(Game g, Player p, List<Player> enemies, List<int[]> avoid)
    {
        var threats = Telegraphs(g, p, enemies);
        var live = new HashSet<string>(threats.Select(t => t.key));
        foreach (var k in threatSeen.Keys.ToList()) if (!live.Contains(k)) threatSeen.Remove(k);
        if (g.time < p.stunUntil) return false;
        double chance = Math.Min(C.BOT_DODGE_CHANCE_MAX, K("DODGE_CHANCE"));
        foreach (var t in threats)
        {
            if (!threatSeen.ContainsKey(t.key)) threatSeen[t.key] = (g.time, rng() < chance);
            var seen = threatSeen[t.key];
            if (!seen.dodge || g.time - seen.at < K("REACTION_MS") || t.left <= 0) continue;
            double dx = p.x - t.o.x, dy = p.y - t.o.y;
            double d = JsMath.Hypot(dx, dy);
            if (d == 0 || double.IsNaN(d)) d = 1;
            var dirs = t.radial ? new[] { (dx / d, dy / d), (-dy / d, dx / d), (dy / d, -dx / d) } : new[] { (-dy / d, dx / d), (dy / d, -dx / d) };
            (XY spot, double e)? best = null;
            foreach (var (ux, uy) in dirs)
            {
                var spot = new XY(p.x + ux * C.BOT_DODGE_STEP, p.y + uy * C.BOT_DODGE_STEP);
                double e = EdgeDist(spot.x, spot.y);
                if (e < 0.8) continue;
                if (best == null || e > best.Value.e) best = (spot, e);
            }
            if (best == null) continue;
            MoveTo(g, p, best.Value.spot, avoid);
            if (t.left < C.BOT_DODGE_DASH_MS && g.time >= p.dashReadyAt)
            {
                Send(g, p);
                Act(g, p, "dash");
            }
            return true;
        }
        return false;
    }

    // ---------- 판단 ----------
    void Think(Game g, Player p)
    {
        input.jump = false;
        if (biasRound != g.roundNumber)
        {
            biasRound = g.roundNumber;
            targetBias.Clear();
        }
        var enemies = Enemies(g, p);
        var dangers = VisibleDangers(g, p);
        // 그림자를 처음 본 순간부터 반응 시간이 지나야 "안다"
        var live = new HashSet<string>();
        foreach (var d in dangers)
        {
            live.Add(d.key);
            if (!dangerSeen.ContainsKey(d.key)) dangerSeen[d.key] = g.time;
        }
        foreach (var k in dangerSeen.Keys.ToList()) if (!live.Contains(k)) dangerSeen.Remove(k);
        var known = dangers.Where(d => g.time - dangerSeen[d.key] >= K("REACTION_MS")).ToList();
        var avoid = known.SelectMany(d => d.cells).ToList();
        var danger = dangers.Count > 0 ? dangers[0] : null;

        var mine = g.ControlledPiece(p);
        if (p.master)
        {
            // 블록 마스터: 몸은 필드에 없음. 블록만 상대 위로 몬다
            input.fwd = 0;
            input.strafe = 0;
            if (mine != null) ControlPiece(g, p, enemies, mine);
            return;
        }
        if (mine != null)
        {
            ControlPiece(g, p, enemies, mine);
            var hover = g.PieceWorldCells(mine).Select(c => new[] { c[0], c[1] }).ToList();
            if (!ClimbFromLava(g, p, avoid)) MoveTo(g, p, SafeSpot(g, p, hover.Concat(avoid).ToList()), avoid);
            return;
        }
        if (CharRecover(g, p)) return; // 0.5) 캐릭터 F 복귀
        if (Recover(g, p)) return; // 0.6) 공용 복귀
        if (DodgeTelegraph(g, p, enemies, avoid)) return; // 0.8) 상대 예고 피하기

        // 1) 피하기
        var hit = known.Where(d => OverlapsCells(p, d.cells)).ToList();
        if (hit.Count > 0)
        {
            var spot = SafeSpot(g, p, avoid);
            MoveTo(g, p, spot);
            double dist = JsMath.Hypot(spot.x - p.x, spot.y - p.y);
            double eta = hit.Min(d => d.eta);
            if (dist > 0.8 && eta < 900 && g.time >= p.dashReadyAt) Act(g, p, "dash");
            return;
        }

        // 1.5) 용암이 다가오면 높은 곳으로
        if (SkyHop(g, p)) return;
        if (ClimbFromLava(g, p, avoid)) return;
        if (BrickStep(g, p)) return;

        // 2) 가장자리에 너무 붙었으면 안쪽으로
        if (EdgeDist(p.x, p.y) < 0.75)
        {
            MoveTo(g, p, new XY(W / 2.0, D / 2.0), avoid);
            return;
        }

        var target = Nearest(p, enemies);

        // 2.5) 캐릭터 스킬·필살기
        if (target != null && p.@char != null && g.time >= nextSkillAt && UseSkills(g, p, target, enemies, avoid))
        {
            nextSkillAt = g.time + K("SKILL_INTERVAL_MS") * (0.7 + 0.6 * rng());
            return;
        }

        // 3) 투사체: 보이면 쏜다
        if (target != null && p.ammo > 0 && CanShoot(g, p, target))
        {
            AimAt(p, target);
            Send(g, p);
            Act(g, p, "fire");
            input.fwd = 0;
            return;
        }

        // 3.5) 설치 블록 · 3.6) 폭탄
        if (target != null && p.bricks > 0 && !g.lava.active && BrickOnTarget(g, p, target)) return;
        if (target != null && p.bombs > 0 && BombOnTarget(g, p, target)) return;

        // 4) 아이템
        var item = PickItem(g, p, target);
        if (item != null)
        {
            MoveTo(g, p, new XY(item.x + 0.5, item.y + 0.5), avoid);
            if (input.fwd != 0 || JsMath.Hypot(item.x + 0.5 - p.x, item.y + 0.5 - p.y) < 0.5) return;
        }

        // 5) 밀치기
        if (target != null)
        {
            Attack(g, p, target, danger, avoid);
            return;
        }
        MoveTo(g, p, new XY(W / 2.0, D / 2.0), avoid);
    }

    Player? Nearest(Player p, List<Player> list)
    {
        Player? best = null;
        double bd = double.PositiveInfinity;
        foreach (var o in list)
        {
            if (!targetBias.ContainsKey(o.id)) targetBias[o.id] = rng() * C.BOT_TARGET_JITTER;
            double d = JsMath.Hypot(o.x - p.x, o.y - p.y) + targetBias[o.id];
            if (d < bd)
            {
                bd = d;
                best = o;
            }
        }
        return best;
    }

    public Item? PickItem(Game g, Player p, Player? target)
    {
        Item? best = null;
        double bd = double.PositiveInfinity;
        foreach (var it in g.items)
        {
            if (C.HELD_ITEMS.Contains(it.type) && g.HeldItem(p) != null) continue; // 손 아이템은 하나만
            if (it.type == "jump" && g.time < p.jumpUntil) continue;
            if (it.type == "ghost" && g.time < p.ghostUntil) continue;
            if (it.z - p.z > JumpReach(g, p) + 0.15 || p.z - it.z > 6) continue;
            double d = JsMath.Hypot(it.x + 0.5 - p.x, it.y + 0.5 - p.y);
            double de = target != null ? JsMath.Hypot(it.x + 0.5 - target.x, it.y + 0.5 - target.y) : double.PositiveInfinity;
            if (it.type != "counter" && d > de + 1) continue; // 블록 마스터 반격 아이템은 상대보다 멀어도 먹으러 감
            if (d < bd)
            {
                bd = d;
                best = it;
            }
        }
        return best;
    }

    // 대포수 조준 오차 (좌우·위아래 각각 ±BOT_SHELL_AIM_ERROR_RAD)
    void RollShellErr()
    {
        double e = K("SHELL_AIM_ERROR_RAD");
        double yaw = (rng() * 2 - 1) * e;
        double pitch = (rng() * 2 - 1) * e;
        shellErr = (yaw, pitch);
    }

    // 다음 평타 타의 사거리
    double BasicRange(Player p, Game? g)
    {
        var set = Game.BasicSet(p.@char, p.form);
        int n = (int)Math.Min(p.chainN, set.chain.Length - 1);
        if (p.@char == "ninja" && g != null && g.time < p.empowerUntil && n < 3) return C.NINJA_STAR["range"]; // R 강화 표창
        var d = set.chain[n];
        return d.range is double r && r != 0 ? r : C.PUSH_RANGE;
    }

    void Attack(Game g, Player p, Player t, Danger? dangerIn, List<int[]> avoid)
    {
        var danger = dangerIn;
        XY? dir = null;
        if (danger != null)
        {
            Danger? best = null;
            double bd = double.PositiveInfinity;
            foreach (var d in g.pieces.Count > 0 ? VisibleDangers(g) : new List<Danger>())
            {
                double cx0 = d.cells.Aggregate(0.0, (a, c) => a + c[0] + 0.5) / d.cells.Count;
                double cy0 = d.cells.Aggregate(0.0, (a, c) => a + c[1] + 0.5) / d.cells.Count;
                double dd = JsMath.Hypot(cx0 - t.x, cy0 - t.y);
                if (dd < bd)
                {
                    bd = dd;
                    best = d;
                }
            }
            danger = best ?? danger;
            double cx = danger.cells.Aggregate(0.0, (a, c) => a + c[0] + 0.5) / danger.cells.Count;
            double cy = danger.cells.Aggregate(0.0, (a, c) => a + c[1] + 0.5) / danger.cells.Count;
            double dl = JsMath.Hypot(cx - t.x, cy - t.y);
            if (dl < 1.8 && dl > 0.2) dir = new XY((cx - t.x) / dl, (cy - t.y) / dl);
        }
        if (dir == null)
        {
            var opts = new[] { (d: t.x, x: -1.0, y: 0.0), (d: W - t.x, x: 1.0, y: 0.0), (d: t.y, x: 0.0, y: -1.0), (d: D - t.y, x: 0.0, y: 1.0) }.OrderBy(o => o.d).ToList();
            dir = new XY(opts[0].x, opts[0].y);
        }
        double dist = JsMath.Hypot(t.x - p.x, t.y - p.y);
        double dn = dist == 0 || double.IsNaN(dist) ? 1 : dist;
        var toT = new XY((t.x - p.x) / dn, (t.y - p.y) / dn);
        // 대포수: 탄이 있으면 거리를 두고 상대 가슴을 조준해 쏨
        if (p.@char == "cannon" && p.cannonAmmo > 0 && dist <= C.CANNON_SHELL_RANGE * 0.7)
        {
            double dz = t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.2);
            var err = shellErr ?? (0, 0);
            Kite(g, p, t, C.CANNON_SHELL_RANGE * 0.6, avoid);
            input.yaw += err.yaw;
            input.pitch = JsMath.Atan2(dz, dist) + err.pitch;
            Send(g, p);
            if (p.atk == null && g.time >= p.pushReadyAt && g.time >= nextPushAt)
            {
                Act(g, p, "push");
                nextPushAt = g.time + K("PUSH_INTERVAL_MS") * 0.5 * (0.7 + 0.6 * rng());
                RollShellErr();
            }
            return;
        }
        if (p.@char == "cannon") input.pitch = 0;
        bool softened = g.time < t.vulnUntil && g.time >= p.skillReadyAt;
        // 바드 음유 공중: 상대가 천천히 낙하 음파 고리 안이면 공중 평타
        var glideDef = p.@char == "bard" && p.form != "metal" ? Game.BasicSet("bard", "bard").air[0] : null;
        bool ringing = p.atk != null && p.atk.def.glide && p.atk.glided;
        if (glideDef != null && !p.grounded && Math.Abs(t.z - p.z) <= C.PLAYER_HEIGHT && (ringing || (dist <= glideDef.range && p.glideCount < C.BARD_GLIDE_MAX_PER_AIR && p.atk == null && g.time >= p.pushReadyAt)))
        {
            input.yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
            input.pitch = 0;
            input.fwd = dist > 0.6 ? 1 : 0;
            input.strafe = 0;
            Send(g, p);
            if (!ringing) Act(g, p, "push");
            return;
        }
        if (p.@char == "bard" && p.form != "metal" && !softened && dist <= C.BARD_NOTE_RANGE * 0.8)
        {
            double dz = t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.3);
            var err = shellErr ?? (0, 0);
            Kite(g, p, t, C.BARD_NOTE_RANGE * 0.6, avoid);
            input.yaw += err.yaw;
            input.pitch = JsMath.Atan2(dz, dist) + err.pitch;
            Send(g, p);
            if (p.atk == null && g.time >= p.pushReadyAt && g.time >= nextPushAt)
            {
                Act(g, p, "push");
                nextPushAt = g.time + K("PUSH_INTERVAL_MS") * 0.5 * (0.7 + 0.6 * rng());
                RollShellErr();
            }
            return;
        }
        if (p.@char == "bard") input.pitch = 0;
        // 닌자·탱크: 지상 마지막 타로 띄운 상대를 점프해 따라가 공중 평타
        var lb = p.lastBasic;
        bool launcher = p.@char != null && !Game.BasicSet(p.@char, p.form).chain[^1].finish;
        bool lifted = t.z > p.z + 0.4 || (p.@char == "hunter" && p.leap == null && g.time < p.skillReadyAt && g.time < t.stunUntil - 250);
        if (launcher && p.leap == null && lb != null && !lb.air && lb.n == Game.BasicSet(p.@char, p.form).chain.Length && g.time - lb.at < 900 && lifted && g.time < t.stunUntil && dist < 2)
        {
            input.fwd = dist > 0.8 ? 1 : 0;
            input.strafe = 0;
            input.yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
            input.jump = p.grounded;
            Send(g, p);
            if (!p.grounded && p.vz < 2 && p.airJumps > 0 && t.z > p.z + 1) Act(g, p, "jump");
            if (!p.grounded && Math.Abs(t.z - p.z) < 1.4 && p.atk == null) Act(g, p, "push");
            return;
        }
        // 캐릭터 평타: 앞 타가 끝나고 창 안이면 상대를 보고 다음 타
        if (p.@char != null && (p.atk != null || ((p.chainN > 0 || p.airN > 0) && g.time < p.chainUntil && dist < BasicRange(p, g) * 0.95)))
        {
            input.fwd = 0;
            input.strafe = 0;
            input.yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
            Send(g, p);
            if (p.atk == null && g.time >= p.pushReadyAt + chainDelay - C.BOT_THINK_MS)
            {
                Act(g, p, "push");
                chainDelay = K("CHAIN_DELAY_MS") * (0.7 + 0.6 * rng());
            }
            return;
        }
        bool overlap = dist < 0.3;
        bool lined = overlap || toT.x * dir.x + toT.y * dir.y > 0.5; // 내가 상대 "뒤"에 있다
        if (dist < (p.@char == "ninja" ? BasicRange(p, g) : C.PUSH_RANGE) * 0.85 && (lined || EdgeDist(p.x, p.y) < 1.2))
        {
            input.fwd = 0;
            input.strafe = 0;
            input.yaw = overlap ? JsMath.Atan2(dir.y, dir.x) : JsMath.Atan2(t.y - p.y, t.x - p.x);
            bool free = g.time >= t.stunUntil && g.time >= t.iframeUntil;
            bool myCombo = p.@char != null && t.comboHits > 0 && g.time < t.stunUntil && t.lastHit?.by == p.id;
            if (g.time >= p.pushReadyAt && (free || myCombo) && (myCombo || g.time >= nextPushAt))
            {
                Send(g, p);
                Act(g, p, "push");
                nextPushAt = g.time + K("PUSH_INTERVAL_MS") * (0.7 + 0.6 * rng());
                return;
            }
            if (g.time < nextPushAt)
            {
                var side = new XY(-dir.y, dir.x);
                MoveTo(g, p, new XY(ClampSafe(t.x - dir.x * 1.2 + side.x * 0.6, W), ClampSafe(t.y - dir.y * 1.2 + side.y * 0.6, D)), avoid);
            }
            return;
        }
        var spot = new XY(ClampSafe(t.x - dir.x * 1.0, W), ClampSafe(t.y - dir.y * 1.0, D));
        MoveTo(g, p, spot, avoid);
    }

    // 돌진·순간 베기 길(보는 방향 len 칸)이 피할 칸을 지나가나
    static bool PathHits(Player p, double yaw, double len, List<int[]> cells)
    {
        for (double d = 0; d <= len + 1e-9; d += 0.25)
            if (OverlapsCells(p.x + JsMath.Cos(yaw) * d, p.y + JsMath.Sin(yaw) * d, cells)) return true;
        return false;
    }

    // 캐릭터마다 간단한 규칙. 썼으면 true
    public bool UseSkills(Game g, Player p, Player t, List<Player> enemies, List<int[]>? avoidIn = null)
    {
        var avoid = avoidIn ?? new List<int[]>();
        W = g.W;
        D = g.D;
        double dist = JsMath.Hypot(t.x - p.x, t.y - p.y);
        bool ultReady = p.ult >= g.UltMax(p);
        bool skillReady = g.time >= p.skillReadyAt;
        List<Player> Near(double r) => enemies.Where(o => JsMath.Hypot(o.x - p.x, o.y - p.y) <= r && Math.Abs(o.z - p.z) <= 2).ToList();
        void Face()
        {
            input.yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
            input.pitch = 0;
        }
        bool Use(string name)
        {
            Send(g, p);
            double before = name == "ult" ? p.ult : p.skillReadyAt;
            Act(g, p, name);
            return name == "ult" ? p.ult != before : p.skillReadyAt > g.time; // 실제로 쓰였나
        }
        bool comboing = g.time < t.stunUntil && t.comboHits > 0;
        bool level = Math.Abs(t.z - p.z) < 1;
        switch (p.@char)
        {
            case "tank":
            {
                if (ultReady && Near(C.TANK_SLAM_RANGE + C.TANK_RING_WIDTH * 0.5).Count > 0) return Use("ult");
                double reachNow = C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000);
                double atkSeen = t.atk != null ? g.time - (t.atk.at - t.atk.def.windup) : 0;
                if (skillReady && level && t.atk != null && atkSeen >= K("REACTION_MS") && dist <= reachNow && !PathHits(p, JsMath.Atan2(t.y - p.y, t.x - p.x), dist, avoid))
                {
                    Face();
                    return Use("skill");
                }
                double reach = C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000);
                if (skillReady && level && dist >= 1 && dist <= reach && !PathHits(p, JsMath.Atan2(t.y - p.y, t.x - p.x), Math.Min(reach, dist + 0.5), avoid))
                {
                    Face();
                    return Use("skill");
                }
                break;
            }
            case "ninja":
            {
                if (ultReady && dist <= C.NINJA_STAR["range"] + 1) return Use("ult");
                if (skillReady && level && dist <= C.NINJA_BLINK_DIST && (comboing || dist > 1.5))
                {
                    double yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
                    double land = Math.Min(C.NINJA_BLINK_DIST, dist + C.NINJA_BLINK_BEHIND);
                    if (EdgeDist(p.x + JsMath.Cos(yaw) * land, p.y + JsMath.Sin(yaw) * land) < 0.8) return false;
                    if (PathHits(p, yaw, land, avoid)) return false;
                    Face();
                    return Use("skill");
                }
                break;
            }
            case "builder":
            {
                foreach (var b in g.bblocks.Values.ToList())
                {
                    if (b.owner != p.id || b.kind == "pad" || g.time < p.pushReadyAt || p.atk != null) continue;
                    double bx = b.x + 0.5, by = b.y + 0.5;
                    double db = JsMath.Hypot(bx - p.x, by - p.y);
                    if (db > C.PUSH_RANGE || Math.Abs(b.z - p.z) > 1) continue;
                    double ahead = ((t.x - bx) * (bx - p.x) + (t.y - by) * (by - p.y)) / (db == 0 || double.IsNaN(db) ? 1 : db);
                    if (JsMath.Hypot(t.x - bx, t.y - by) > C.BUILDER_BLAST_RANGE + 0.8 || ahead < -0.3) continue;
                    input.yaw = JsMath.Atan2(by - p.y, bx - p.x);
                    Send(g, p);
                    Act(g, p, "push");
                    return true;
                }
                double bigFrom = C.BUILDER_BIG_GAP + 1;
                if (ultReady && level && dist >= bigFrom && dist <= bigFrom + C.BUILDER_BIG_SIZE)
                {
                    Face();
                    return Use("ult");
                }
                if (skillReady && level && p.grounded && dist >= 0.8 && dist < 2.2)
                {
                    Face();
                    return Use("skill");
                }
                break;
            }
            case "cannon":
                if (ultReady && dist <= C.CANNON_R_RANGE * 0.7 && Math.Abs(t.z - p.z) < 2)
                {
                    Face();
                    RollShellErr();
                    input.yaw += shellErr!.Value.yaw;
                    input.pitch = JsMath.Atan2(t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.2), dist) + shellErr.Value.pitch;
                    return Use("ult");
                }
                if (skillReady && dist < 1.6 && t.atk != null) return Use("skill");
                break;
            case "berserker":
            {
                int around = Near(C.BERSERKER_SPIN_END_RANGE).Count;
                if (ultReady && around > 0 && (p.damage >= 80 || around >= 2)) return Use("ult");
                if (skillReady && level && p.grounded && dist >= 2.5 && dist <= C.BERSERKER_LEAP_DIST + 1)
                {
                    double yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
                    double land = C.BERSERKER_LEAP_DIST;
                    if (EdgeDist(p.x + JsMath.Cos(yaw) * land, p.y + JsMath.Sin(yaw) * land) < 1) return false;
                    if (PathHits(p, yaw, land, avoid)) return false;
                    Face();
                    return Use("skill");
                }
                break;
            }
            case "bard":
                if (p.form != "metal")
                {
                    if (ultReady && dist <= C.BARD_SONG_RANGE * 0.9 && Math.Abs(t.z - p.z) < 2)
                    {
                        Face();
                        return Use("ult");
                    }
                    if (skillReady && (dist <= C.BARD_RIFF_RANGE + 0.3 || (g.time < t.vulnUntil && dist <= C.BARD_RIFF_RANGE + 0.8))) return Use("skill");
                }
                else
                {
                    if (ultReady && level && dist <= C.BARD_AMP_RANGE * 0.8)
                    {
                        Face();
                        return Use("ult");
                    }
                    if (skillReady && ((p.damage >= 90 && !comboing) || dist > 4.5)) return Use("skill");
                }
                break;
            case "hunter":
            {
                var marked = enemies.Where(o => g.MarkOf(p, o) > 0 && JsMath.Hypot(o.x - p.x, o.y - p.y) <= C.HUNTER_SHOT_RANGE && !g.LineBlocked(p, o)).ToList();
                if (ultReady && marked.Count > 0)
                {
                    var best = marked.OrderByDescending(o => g.MarkOf(p, o)).First(); // 안정 정렬 (JS sort b - a)
                    input.yaw = JsMath.Atan2(best.y - p.y, best.x - p.x);
                    if (Use("ult")) return true;
                }
                bool chase = enemies.Any(o => g.MarkOf(p, o) > 0 && JsMath.Hypot(o.x - p.x, o.y - p.y) <= C.HUNTER_LEAP_RANGE && JsMath.Hypot(o.x - p.x, o.y - p.y) > 2);
                if (skillReady && chase) return Use("skill");
                if (skillReady && comboing && g.MarkOf(p, t) > 0 && p.lastBasic != null && p.lastBasic.n == C.BASIC_ATTACKS["hunter"].chain.Length && !p.lastBasic.air && g.time - p.lastBasic.at < 400) return Use("skill");
                break;
            }
            case "hook":
            {
                double yawT = JsMath.Atan2(t.y - p.y, t.x - p.x);
                if (ultReady && dist <= C.HOOK_SLAM_LEN && Math.Abs(t.z - p.z) < 1.5 && g.HookRayBlock(p, yawT, 0) != null)
                {
                    Face();
                    return Use("ult");
                }
                if (skillReady && dist >= 1.6 && dist <= C.HOOK_RANGE * 0.9 && Math.Abs(t.z - p.z) < 1.5 && (comboing || dist >= 2.5))
                {
                    Face();
                    return Use("skill");
                }
                break;
            }
        }
        return false;
    }

    static bool CanShoot(Game g, Player p, Player t)
    {
        double sx = p.x, sy = p.y, sz = p.z + C.EYE_HEIGHT;
        double tx = t.x, ty = t.y, tz = t.z + C.PLAYER_HEIGHT * 0.6;
        double len = JsMath.Hypot(tx - sx, ty - sy, tz - sz);
        if (len > 7 || len < 1.2) return false;
        for (double s = 0.5; s < len; s += 0.25)
        {
            double k = s / len;
            if (g.SolidAt((int)Math.Floor(sx + (tx - sx) * k), (int)Math.Floor(sy + (ty - sy) * k), (int)Math.Floor(sz + (tz - sz) * k))) return false;
        }
        return true;
    }

    void AimAt(Player p, Player t)
    {
        double Err() => (rng() * 2 - 1) * K("AIM_ERROR_RAD");
        double dx = t.x - p.x, dy = t.y - p.y;
        double dz = t.z + C.PLAYER_HEIGHT * 0.6 - (p.z + C.EYE_HEIGHT);
        input.yaw = JsMath.Atan2(dy, dx) + Err();
        input.pitch = JsMath.Atan2(dz, JsMath.Hypot(dx, dy)) + Err();
    }

    // 위험 칸·가장자리를 피하면서 지금 높이에서 갈 수 있는 가장 가까운 칸 중심
    XY SafeSpot(Game g, Player p, List<int[]> bad)
    {
        var badSet = new HashSet<int>(bad.Select(c => c[0] * 100 + c[1]));
        XY? best = null;
        double bs = double.PositiveInfinity;
        for (int x = 0; x < W; x++)
        {
            for (int y = 0; y < D; y++)
            {
                if (badSet.Contains(x * 100 + y)) continue;
                int top = g.ColumnTop(x, y);
                if (top > p.z + JumpReach(g, p)) continue;
                if (g.lava.active && top < g.lava.z + 0.6) continue;
                double cx = x + 0.5, cy = y + 0.5;
                int near = 0;
                foreach (var b in bad) if (Math.Abs(b[0] - x) <= 1 && Math.Abs(b[1] - y) <= 1) near++;
                double score = JsMath.Hypot(cx - p.x, cy - p.y) + (EdgeDist(cx, cy) < 1 ? 0.8 : 0) + near * 0.15;
                if (score < bs)
                {
                    bs = score;
                    best = new XY(cx, cy);
                }
            }
        }
        return best ?? new XY(W / 2.0, D / 2.0);
    }

    void MoveTo(Game g, Player p, XY spot, List<int[]>? avoidIn = null)
    {
        var avoid = avoidIn ?? new List<int[]>();
        if (g.time < unstickUntil)
        {
            // 막혔을 때: 옆으로 비켜 걸으며 점프
            input.fwd = 0.3;
            input.strafe = unstickDir;
            input.jump = true;
            return;
        }
        double tx = spot.x, ty = spot.y;
        if (avoid.Count > 0 && OverlapsCells(tx, ty, avoid))
        {
            var s = SafeSpot(g, p, avoid);
            tx = s.x;
            ty = s.y;
        }
        double dx = tx - p.x, dy = ty - p.y;
        double d = JsMath.Hypot(dx, dy);
        if (d < 0.2)
        {
            input.fwd = 0;
            input.strafe = 0;
            return;
        }
        double ux = dx / d, uy = dy / d;
        if (avoid.Count > 0 && !OverlapsCells(p, avoid))
        {
            bool Hits(double vx, double vy) => OverlapsCells(p.x + vx * 0.35, p.y + vy * 0.35, avoid) || OverlapsCells(p.x + vx * 0.7, p.y + vy * 0.7, avoid);
            if (Hits(ux, uy))
            {
                if (Math.Abs(ux) > 0.15 && !Hits(JsMath.Sign(ux), 0))
                {
                    ux = JsMath.Sign(ux);
                    uy = 0;
                }
                else if (Math.Abs(uy) > 0.15 && !Hits(0, JsMath.Sign(uy)))
                {
                    ux = 0;
                    uy = JsMath.Sign(uy);
                }
                else
                {
                    input.fwd = 0;
                    input.strafe = 0;
                    return;
                }
            }
        }
        int ax = (int)Math.Floor(p.x + ux * 0.55), ay = (int)Math.Floor(p.y + uy * 0.55);
        int top = g.InXY(ax, ay) ? g.ColumnTop(ax, ay) : ColumnTopJs(g, ax, ay);
        // 용암이 켜졌으면 용암 가까운 낮은 칸으로 내려가지 않는다
        if (g.lava.active && top < StandHeight(g, p) - 0.5 && top < g.lava.z + C.BOT_LAVA_MARGIN)
        {
            input.fwd = 0;
            input.strafe = 0;
            return;
        }
        input.yaw = JsMath.Atan2(uy, ux);
        input.pitch = 0;
        input.fwd = 1;
        input.strafe = 0;
        if (p.grounded)
        {
            if (top > p.z + 0.05 && top <= p.z + JumpReach(g, p)) input.jump = true;
        }
        else if (top > p.z + 0.05 && p.airJumps > 0 && p.vz < C.BOT_AIR_JUMP_VZ) Act(g, p, "jump"); // 2단 점프
    }

    // JS columnTop 은 필드 밖 칸도 grid 배열을 그대로 읽음 (idx 가 다른 칸이나 배열 밖 → undefined = 0). 같은 값을 내려고 그대로 흉내
    static int ColumnTopJs(Game g, int cx, int cy)
    {
        for (int z = g.H - 1; z >= 0; z--)
        {
            int i = (z * g.D + cy) * g.W + cx;
            if (i >= 0 && i < g.grid.Length && g.grid[i] != 0) return z + 1;
        }
        return 0;
    }

    // ---------- 조종 ----------
    void ControlPiece(Game g, Player p, List<Player> enemies, Piece piece)
    {
        var t = Nearest(p, enemies);
        double timeLeft = piece.controlEndsAt - g.time;
        if (dropOffset == null || dropOffset.Value.piece != piece.id)
        {
            double R = K("CONTROL_AIM_ERROR");
            double r = R > 0 ? R * Math.Sqrt(rng()) : 0; // 0 이면 난수를 안 씀
            double a = r > 0 ? rng() * Math.PI * 2 : 0;
            dropOffset = (piece.id, r * JsMath.Cos(a), r * JsMath.Sin(a));
        }
        (double x, double y, double z)? aim = t != null ? (t.x + dropOffset.Value.x, t.y + dropOffset.Value.y, t.z) : null;
        var plan = aim != null ? BestDrop(g, p, aim.Value, piece) : null;
        if (plan == null)
        {
            if (timeLeft < 1500 && piece.fits) Drop(g, p, piece);
            else if (!piece.fits) g.HandleAction(p.id, new ActionMsg { name = "pieceMove", dx = piece.px > W / 2.0 ? -1 : 1, dy = 0 });
            return;
        }
        if (piece.rot != plan.Value.rot)
        {
            double diff = (plan.Value.rot - piece.rot + 4) % 4;
            g.HandleAction(p.id, new ActionMsg { name = "rotate", dir = diff == 3 ? -1 : 1 });
            aimedAt = null;
            return;
        }
        if (piece.px != plan.Value.px)
        {
            g.HandleAction(p.id, new ActionMsg { name = "pieceMove", dx = Math.Sign(plan.Value.px - piece.px), dy = 0 });
            aimedAt = null;
            return;
        }
        if (piece.py != plan.Value.py)
        {
            g.HandleAction(p.id, new ActionMsg { name = "pieceMove", dx = 0, dy = Math.Sign(plan.Value.py - piece.py) });
            aimedAt = null;
            return;
        }
        aimedAt ??= g.time;
        if (g.time - aimedAt >= K("DROP_DELAY_MS") || timeLeft < 1000)
        {
            Drop(g, p, piece);
            aimedAt = null;
        }
    }

    // 내가 떨어뜨린 블록은 어디로 떨어지는지 이미 안다 → 반응 시간 없이 바로 피할 대상으로
    void Drop(Game g, Player p, Piece piece)
    {
        Act(g, p, "drop");
        if (piece.phase == "falling") dangerSeen[PieceKey(piece)] = g.time - K("REACTION_MS");
    }

    // 서 있는 높이 (칸). 점프 중이면 발밑 기둥 높이
    static double StandHeight(Game g, Player p)
    {
        int x = Math.Max(0, Math.Min(W - 1, (int)Math.Floor(p.x)));
        int y = Math.Max(0, Math.Min(D - 1, (int)Math.Floor(p.y)));
        int under = g.ColumnTop(x, y);
        return p.grounded || under > p.z ? Math.Floor(p.z + 0.05) : under;
    }

    // 용암이 2.5칸 안인데 걸어서 갈 더 높은 곳이 없을 때: 설치 블록을 던져 바로 앞에 높은 발판. 던졌으면 true
    bool BrickStep(Game g, Player p)
    {
        if (!p.grounded || !g.lava.active || p.z - g.lava.z > 2.5) return false;
        double h0 = StandHeight(g, p);
        if (p.bricks <= 0) return false;
        if (g.pieces.Any(pc => pc.thrownBy == p.id)) return false;
        var sides = new[] { p.brickSide, !p.brickSide };
        bool side0 = p.brickSide;
        (double yaw, bool side)? pick = null;
        foreach (var yaw in new[] { 0, Math.PI / 2, Math.PI, -Math.PI / 2 })
        {
            foreach (var side in sides)
            {
                p.brickSide = side; // 계획만 본다
                var plan = g.BrickPlan(p, yaw, C.BOT_BRICK_STEP_PITCH);
                if (plan.ok && plan.z + 1 > h0 + 0.5 && plan.z + 1 <= h0 + JumpReach(g, p)) pick ??= (yaw, side);
            }
        }
        p.brickSide = side0;
        if (pick == null) return false;
        if (pick.Value.side != p.brickSide) g.HandleAction(p.id, new ActionMsg { name = "rotate", dir = 1 });
        ThrowAt(g, p, pick.Value.yaw, C.BOT_BRICK_STEP_PITCH);
        return true;
    }

    // 상대 발밑을 조준했을 때 떨어질 칸이 상대를 덮으면 던진다
    bool BrickOnTarget(Game g, Player p, Player t)
    {
        (double yaw, double pitch, double d) Aim(double tx, double ty)
        {
            double d = JsMath.Hypot(tx - p.x, ty - p.y);
            return (JsMath.Atan2(ty - p.y, tx - p.x), JsMath.Atan2(t.z - (p.z + C.EYE_HEIGHT), d), d);
        }
        var exact = Aim(t.x, t.y);
        if (exact.d > C.BRICK_RANGE || g.pieces.Any(pc => pc.thrownBy == p.id)) return false;
        var plan = g.BrickPlan(p, exact.yaw, exact.pitch);
        if (!plan.ok || !OverlapsCells(t, plan.cells)) return false;
        double r = K("BRICK_AIM_ERROR") * Math.Sqrt(rng());
        double a = rng() * Math.PI * 2;
        var off = Aim(t.x + r * JsMath.Cos(a), t.y + r * JsMath.Sin(a));
        var shot = g.BrickPlan(p, off.yaw, off.pitch).ok ? off : exact;
        ThrowAt(g, p, shot.yaw, shot.pitch);
        return true;
    }

    // 상대 발밑 칸이 폭발 범위에 들면 던진다
    bool BombOnTarget(Game g, Player p, Player t)
    {
        double d = JsMath.Hypot(t.x - p.x, t.y - p.y);
        if (d > C.BRICK_RANGE || d < C.BOMB_BLAST_RANGE) return false;
        (double yaw, double pitch) Aim(double tx, double ty) => (JsMath.Atan2(ty - p.y, tx - p.x), JsMath.Atan2(t.z - (p.z + C.EYE_HEIGHT), JsMath.Hypot(tx - p.x, ty - p.y)));
        var exact = Aim(t.x, t.y);
        var plan = g.BombPlan(p, exact.yaw, exact.pitch);
        if (!plan.ok) return false;
        int bx = plan.cells[0][0], by = plan.cells[0][1];
        if (Math.Abs(Math.Floor(t.x) - bx) > C.BOMB_RADIUS || Math.Abs(Math.Floor(t.y) - by) > C.BOMB_RADIUS) return false;
        double r = K("BRICK_AIM_ERROR") * Math.Sqrt(rng());
        double a = rng() * Math.PI * 2;
        var off = Aim(t.x + r * JsMath.Cos(a), t.y + r * JsMath.Sin(a));
        var shot = g.BombPlan(p, off.yaw, off.pitch).ok ? off : exact;
        ThrowAt(g, p, shot.yaw, shot.pitch);
        return true;
    }

    // 손에 든 것(설치 블록·폭탄)을 이 방향으로 우클릭
    void ThrowAt(Game g, Player p, double yaw, double pitch)
    {
        input.yaw = yaw;
        input.pitch = pitch;
        input.fwd = 0;
        input.strafe = 0;
        Send(g, p);
        Act(g, p, "fire");
        var mine = g.pieces.FirstOrDefault(pc => pc.thrownBy == p.id);
        if (mine != null) dangerSeen[PieceKey(mine)] = g.time - K("REACTION_MS");
    }

    // 지금 한 번 점프로 올라갈 수 있는 높이 (칸)
    static double JumpReach(Game g, Player p) => (g.time < p.jumpUntil ? 2.25 : 1.05) + (C.AIR_JUMPS > 0 ? 1 : 0);

    // 유령 투하 (죽은 봇, GHOST_DROP_BOTS 일 때만): 살아 있는 상대 중 가장 가까운 사람 발밑 칸에
    public void GhostDrop(Game g, Player p)
    {
        W = g.W;
        D = g.D;
        var live = g.Players().Where(o => o != p && o.alive && g.OnField(o) && !g.SameTeam(o, p)).ToList();
        if (live.Count == 0) return;
        var t = Nearest(p, live)!;
        double r = K("BRICK_AIM_ERROR") * Math.Sqrt(rng());
        double a = rng() * Math.PI * 2;
        g.GhostDrop(p.id, Math.Max(0, Math.Min(W - 1, t.x + r * JsMath.Cos(a))), Math.Max(0, Math.Min(D - 1, t.y + r * JsMath.Sin(a))));
    }

    // ---------- 위치·복귀 ----------
    // 거리 유지 이동 (원거리 캐릭터): 상대와 want 칸 거리를 두고 상대를 바라본 채 상대 둘레 원 위에서 가장자리·그림자를 등지지 않는 자리로
    XY Kite(Game g, Player p, Player t, double want, List<int[]> avoid)
    {
        double dx0 = p.x - t.x, dy0 = p.y - t.y;
        double a0 = JsMath.Hypot(dx0, dy0) > 0.05 ? JsMath.Atan2(dy0, dx0) : JsMath.Atan2(D / 2.0 - t.y, W / 2.0 - t.x);
        double h0 = StandHeight(g, p);
        double reach = JumpReach(g, p);
        int steps = (int)JsMath.Round(C.BOT_KITE_ARC_DEG / 15);
        XY? best = null;
        double bs = double.NegativeInfinity;
        for (int k = -steps; k <= steps; k++)
        {
            double a = a0 + (k * Math.PI) / 12;
            double x = t.x + JsMath.Cos(a) * want, y = t.y + JsMath.Sin(a) * want;
            if (x < 0.45 || y < 0.45 || x > W - 0.45 || y > D - 0.45) continue;
            double score = Math.Min(EdgeDist(x, y), 3) * 2 - Math.Abs(k) * 0.3;
            if (EdgeDist(x, y) < C.BOT_EDGE_MARGIN) score -= 50;
            if (OverlapsCells(x, y, avoid)) score -= 100;
            int top = g.ColumnTop((int)Math.Floor(x), (int)Math.Floor(y));
            if (top > h0 + reach) score -= 30;
            else if (h0 - top >= 2) score -= 10;
            if (PathHits(p, JsMath.Atan2(y - p.y, x - p.x), JsMath.Hypot(x - p.x, y - p.y), avoid)) score -= 20;
            if (score > bs)
            {
                bs = score;
                best = new XY(x, y);
            }
        }
        best ??= RecoverPoint(p);
        input.yaw = JsMath.Atan2(t.y - p.y, t.x - p.x);
        double mx = best.x - p.x, my = best.y - p.y;
        double len = JsMath.Hypot(mx, my);
        if (len < 0.2)
        {
            input.fwd = 0;
            input.strafe = 0;
            return best;
        }
        double fx = JsMath.Cos(input.yaw), fy = JsMath.Sin(input.yaw);
        input.fwd = (mx * fx + my * fy) / len;
        input.strafe = (mx * fy - my * fx) / len;
        int ax = (int)Math.Floor(p.x + (mx / len) * 0.55), ay = (int)Math.Floor(p.y + (my / len) * 0.55);
        int ahead = g.InXY(ax, ay) ? g.ColumnTop(ax, ay) : 0;
        if (p.grounded && ahead > p.z + 0.05 && ahead <= p.z + reach) input.jump = true;
        return best;
    }

    // 공중에서 필드 밖으로 떨어질 참인가
    static bool FallingOff(Game g, Player p)
    {
        if (p.grounded || !g.OnField(p)) return false;
        static bool InField(double x, double y) => x >= 0.05 && x <= W - 0.05 && y >= 0.05 && y <= D - 0.05;
        if (!InField(p.x, p.y)) return true;
        double h = Math.Max(0, p.z);
        double t = (p.vz + Math.Sqrt(p.vz * p.vz + 2 * C.GRAVITY * h)) / C.GRAVITY;
        double decay = (1 - JsMath.Exp(-C.KB_DAMPING_AIR * t)) / C.KB_DAMPING_AIR;
        return !InField(p.x + p.kbx * decay, p.y + p.kby * decay);
    }

    // 돌아갈 자리: 필드 안 가장 가까운 점에서 BOT_RECOVER_INSET 칸 더 안쪽
    static XY RecoverPoint(Player p)
    {
        double m = C.BOT_RECOVER_INSET;
        return new XY(Math.Max(m, Math.Min(W - m, p.x)), Math.Max(m, Math.Min(D - m, p.y)));
    }

    // 복귀: 안쪽으로 걸음 + 넉백이 밖으로 향하면 공중 대시 + 떨어지기 시작하면 2단 점프. 했으면 true
    bool Recover(Game g, Player p)
    {
        if (!FallingOff(g, p) || g.time < p.stunUntil) return false;
        var to = RecoverPoint(p);
        double dx = to.x - p.x, dy = to.y - p.y;
        double d = JsMath.Hypot(dx, dy);
        if (d == 0 || double.IsNaN(d)) d = 1;
        input.yaw = JsMath.Atan2(dy, dx);
        input.pitch = 0;
        input.fwd = 1;
        input.strafe = 0;
        Send(g, p);
        double outV = -(p.kbx * dx + p.kby * dy) / d;
        bool dashed = p.airDashes > 0 && g.time >= p.dashReadyAt && outV > C.BOT_RECOVER_DASH_OUT;
        if (dashed) Act(g, p, "dash");
        if (p.airJumps > 0 && (p.vz < C.BOT_AIR_JUMP_VZ || p.z < C.BOT_RECOVER_LOW_Z)) Act(g, p, "jump");
        return true;
    }

    // 캐릭터 F 복귀. 썼으면 true
    bool CharRecover(Game g, Player p)
    {
        if (p.@char == null || p.vz > 0 || g.time < p.stunUntil || !FallingOff(g, p)) return false;
        var to = RecoverPoint(p);
        double yaw = JsMath.Atan2(to.y - p.y, to.x - p.x);
        bool ready = g.time >= p.skillReadyAt;
        if ((p.@char == "bard" || p.@char == "hunter") && p.z >= -0.3) return false;
        string? act = null;
        if (p.@char == "bard")
        {
            if (p.form != "metal") act = p.glideUntil == 0 && p.glideCount < C.BARD_GLIDE_MAX_PER_AIR ? "push" : null;
            else if (ready) act = "skill";
        }
        else if (!ready) return false;
        else if (p.@char is "ninja" or "berserker" or "tank") act = "skill";
        else if (p.@char == "hunter") act = g.players.Count > 0 && g.Players().Any(o => o != p && g.MarkOf(p, o) > 0 && JsMath.Hypot(o.x - p.x, o.y - p.y) <= C.HUNTER_LEAP_RANGE) ? null : "skill";
        else if (p.@char == "hook") act = g.HookRayBlock(p, yaw, 0) != null ? "skill" : null;
        else if (p.@char is "cannon" or "builder") act = p.z < 0.5 ? "skill" : null;
        if (act == null) return false;
        input.yaw = yaw;
        input.pitch = 0;
        input.fwd = 1;
        input.strafe = 0;
        Send(g, p);
        Act(g, p, act);
        return true;
    }

    // 하늘 계단: 용암이 BOT_SKY_HOP_LAVA 안이면 점프로 닿는 더 높은 하늘 블록으로 건너뛴다
    bool SkyHop(Game g, Player p)
    {
        if (!g.sky || !g.lava.active || p.z - g.lava.z > C.BOT_SKY_HOP_LAVA) return false;
        double h0 = StandHeight(g, p);
        double reach = JumpReach(g, p);
        (XY cell, double top, double d)? best = null;
        double bs = double.NegativeInfinity;
        bool onSky = false;
        foreach (var pc in g.pieces)
        {
            if (!pc.sky || pc.phase != "falling") continue;
            double top = pc.pz + 1;
            if (p.grounded && Math.Abs(top - p.z) < 0.1 && pc.cells.Any(c => pc.px + c[0] == Math.Floor(p.x) && pc.py + c[1] == Math.Floor(p.y))) onSky = true;
            if (top <= h0 + 0.5 || top > h0 + reach) continue;
            XY? cell = null;
            double cd = double.PositiveInfinity;
            foreach (var c in pc.cells)
            {
                double cx = pc.px + c[0] + 0.5, cy = pc.py + c[1] + 0.5;
                double dd = JsMath.Hypot(cx - p.x, cy - p.y);
                if (dd < cd)
                {
                    cd = dd;
                    cell = new XY(cx, cy);
                }
            }
            if (cd - 0.5 > C.BOT_SKY_HOP_DIST) continue;
            double score = top * 2 - cd;
            if (score > bs)
            {
                bs = score;
                best = (cell!, top, cd);
            }
        }
        if (best == null)
        {
            if (!onSky) return false;
            input.fwd = 0;
            input.strafe = 0;
            return true;
        }
        var B = best.Value;
        input.yaw = JsMath.Atan2(B.cell.y - p.y, B.cell.x - p.x);
        input.pitch = 0;
        input.fwd = B.d < 0.3 ? 0 : 1;
        input.strafe = 0;
        if (p.grounded)
        {
            if (B.d < 2.5) input.jump = true;
        }
        else if (p.airJumps > 0 && p.vz < C.BOT_AIR_JUMP_VZ && p.z < B.top) Act(g, p, "jump");
        return true;
    }

    // 용암이 2.5칸 안으로 다가오면 걸어서 이어진 가장 높은 칸으로 (BFS). 움직였으면 true
    bool ClimbFromLava(Game g, Player p, List<int[]> avoid)
    {
        if (!g.lava.active || p.z - g.lava.z > 2.5) return false;
        double reach = JumpReach(g, p);
        double floorZ = g.lava.z + 0.15;
        var bad = new HashSet<int>(avoid.Select(c => c[0] * 100 + c[1]));
        int sx = Math.Max(0, Math.Min(W - 1, (int)Math.Floor(p.x)));
        int sy = Math.Max(0, Math.Min(D - 1, (int)Math.Floor(p.y)));
        double h0 = StandHeight(g, p);
        int start = sx * 100 + sy;
        var height = new Dictionary<int, double> { [start] = h0 };
        var first = new Dictionary<int, (int x, int y)?> { [start] = null };
        var steps = new Dictionary<int, int> { [start] = 0 };
        var queue = new Queue<(int x, int y)>();
        queue.Enqueue((sx, sy));
        int best = start;
        double bs = double.NegativeInfinity;
        while (queue.Count > 0)
        {
            var (x, y) = queue.Dequeue();
            int k = x * 100 + y;
            double h = height[k];
            double score = h * 20 - steps[k];
            if (score > bs)
            {
                bs = score;
                best = k;
            }
            foreach (var (dx, dy) in new[] { (1, 0), (-1, 0), (0, 1), (0, -1) })
            {
                int nx = x + dx, ny = y + dy, nk = nx * 100 + ny;
                if (nx < 0 || nx >= W || ny < 0 || ny >= D || height.ContainsKey(nk) || bad.Contains(nk)) continue;
                int top = g.ColumnTop(nx, ny);
                if (top > h + reach || top < floorZ) continue;
                height[nk] = top;
                steps[nk] = steps[k] + 1;
                first[nk] = first[k] ?? (nx, ny);
                queue.Enqueue((nx, ny));
            }
        }
        if (best == start || height[best] <= h0 + 0.5) return false;
        var (fx, fy) = first[best]!.Value;
        MoveTo(g, p, new XY(fx + 0.5, fy + 0.5), avoid);
        return true;
    }

    // 상대가 서 있는 칸들을 덮고, 나는 안 덮고, 들어가는 배치 중 이동 키 수가 가장 적은 것
    (int rot, int px, int py)? BestDrop(Game g, Player p, (double x, double y, double z) t, Piece piece)
    {
        double h = C.PLAYER_HALF;
        var tCells = new HashSet<int>();
        foreach (var (ox, oy) in new[] { (-h, -h), (h, -h), (-h, h), (h, h), (0.0, 0.0) }) tCells.Add((int)Math.Floor(t.x + ox) * 100 + (int)Math.Floor(t.y + oy));
        (int rot, int px, int py)? best = null;
        double bs = double.PositiveInfinity;
        for (int r = 0; r < 4; r++)
        {
            var cells = Pieces.RotatedCells(piece.shape, r);
            var (w, d) = Pieces.Footprint(cells);
            for (int px = 0; px <= W - w; px++)
            {
                for (int py = 0; py <= D - d; py++)
                {
                    var world = cells.Select(c => new[] { px + c[0], py + c[1] }).ToList();
                    int cover = world.Count(c => tCells.Contains(c[0] * 100 + c[1]));
                    if (cover == 0) continue;
                    if (OverlapsCells(p, world)) continue;
                    int landZ = world.Max(c => g.ColumnTop(c[0], c[1]));
                    if (landZ + 1 > C.GRID_H) continue;
                    if (g.mode == "master" && g.TooTall(world.Select(c => (c[0], c[1])), landZ)) continue;
                    if (landZ > t.z + 0.5) continue;
                    double rd = (r - piece.rot + 4) % 4;
                    double keys = (rd == 3 ? 1 : rd) + Math.Abs(px - piece.px) + Math.Abs(py - piece.py);
                    double score = keys - cover * 2;
                    if (score < bs)
                    {
                        bs = score;
                        best = (r, px, py);
                    }
                }
            }
        }
        return best;
    }
}
