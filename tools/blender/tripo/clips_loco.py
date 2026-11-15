# W33 이동 동작 공용 생성기 (idle·walk·run·jump·fall·land): 캐릭터마다 '스타일' 표 하나로 clips_tank·clips_hunter·clips_hook 이 부름.
# 자세 값 설명은 anim_ninja.py 머리말. 걸음 한 바퀴 = 두 걸음, 4위상: 닿음 (앞발 뻗음) → 지나감 (뒷발이 앞으로 휘감) → 반대 닿음 → 반대 지나감.
# 쓰는 법: define_loco(M, S) — S 키는 아래 DEFAULT 참고 (모두 도 단위, 값 두 개 = (오른쪽, 왼쪽)).
DEFAULT = dict(
    hold=dict(arm_fwd=(10, 10), arm_out=(6, 6), elbow=(30, 30), hand=(0, 0)),   # 쉬는 팔 (손에 든 것을 받치는 자세)
    idle=dict(),                       # 쉴 때 덮어쓸 값 (hold 위에)
    breathe=dict(spine_pitch=2, neck_pitch=-1, hips_z=-0.004),
    base=dict(),                       # 모든 자세 공통 (구부정함 같은 몸 버릇)
    walk=dict(A=20, back=0.8, kf=6, kb=20, lift=22, K=46, foot_f=-8, foot_b=14, hz_c=-0.010, hz_p=0.004, hips_twist=5, spine_twist=-6,
              spine_pitch=2, neck_pitch=0, sway=2.0, arm_swing=(14, 14), arm_elbow_gain=0.4, spine_side=0),
    run=dict(A=34, back=0.9, kf=18, kb=40, lift=8, K=78, foot_f=-12, foot_b=26, hz_c=-0.026, hz_p=-0.008, hips_twist=8, spine_twist=-12,
             spine_pitch=14, neck_pitch=-8, sway=3.0, arm_swing=(24, 24), arm_elbow_gain=0.6, spine_side=0),
    jump=dict(crouch=dict(hips_z=-0.045, spine_pitch=18, neck_pitch=-8, leg_fwd=(28, 28), knee=(60, 60), foot=(-18, -18)),
              launch=dict(hips_z=0.0, spine_pitch=2, neck_pitch=-6, leg_fwd=(-6, -8), knee=(6, 8), foot=(28, 28)),
              tuck=dict(spine_pitch=10, neck_pitch=-8, leg_fwd=(50, 34), knee=(80, 64), foot=(10, 10)),
              arms_up=(40, 40), arms_out=(14, 14)),
    fall=dict(a=dict(leg_fwd=(22, 4), knee=(24, 44), foot=(12, 18)), b=dict(leg_fwd=(4, 22), knee=(44, 24), foot=(18, 12)), arms_out=(40, 40), arms_up=(24, 24), spine_pitch=2),
    land=dict(hips_z=-0.07, spine_pitch=24, neck_pitch=-12, leg_fwd=(36, 28), knee=(70, 64), foot=(-20, -18)),
)


def merged(S):
    out = {}
    for k, v in DEFAULT.items():
        out[k] = dict(v)
        if k in S:
            out[k].update(S[k])
    for k, v in S.items():
        if k not in out:
            out[k] = v
    return out


def define_loco(M, S0):
    S = merged(S0)
    P_, clip = M.P_, M.clip
    hold, base = S["hold"], S["base"]

    def with_hold(**kw):
        d = dict(hold)
        d.update(base)
        d.update(kw)
        return P_(**d)

    # ---- idle ----
    ready = with_hold(**S["idle"])
    br = dict(S["idle"])
    for k, v in S["breathe"].items():
        br[k] = (br.get(k, hold.get(k, base.get(k, 0.0))) + v) if not isinstance(v, tuple) else v
    breathe = with_hold(**br)
    clip("idle", 2.6, True, [(0.0, ready), (1.3, breathe), (2.6, ready)])

    def gait(G, sw_scale=1.0):
        def arms(s, mul):
            sR, sL = G["arm_swing"]
            hf, ho, he = hold["arm_fwd"], hold["arm_out"], hold["elbow"]
            fw = (hf[0] - s * sR * mul, hf[1] + s * sL * mul)
            el = (he[0] + abs(fw[0] - hf[0]) * G["arm_elbow_gain"], he[1] + abs(fw[1] - hf[1]) * G["arm_elbow_gain"])
            return dict(arm_fwd=fw, arm_out=ho, elbow=el, hand=hold.get("hand", (0, 0)))

        def contact(s):
            A, B = G["A"], G["A"] * G["back"]
            front, back = (A, -B) if s > 0 else (-B, A)
            kn = (G["kf"], G["kb"]) if s > 0 else (G["kb"], G["kf"])
            ft = (G["foot_f"], G["foot_b"]) if s > 0 else (G["foot_b"], G["foot_f"])
            d = dict(base)
            d.update(arms(s, 1.0))
            d.update(hips_z=G["hz_c"], hips_twist=G["hips_twist"] * s, spine_twist=G["spine_twist"] * s, spine_pitch=G["spine_pitch"],
                     neck_pitch=G["neck_pitch"], hips_side=G["sway"] * s, spine_side=G["spine_side"] * s,
                     leg_fwd=(front, back), knee=kn, foot=ft)
            return P_(**d)

        def passing(s):
            # s = 방금 닿은 쪽 (오른발이 앞이었음 = s>0): 앞이었던 다리가 지지, 뒤 다리가 앞으로 휘감
            sup, sw = G["lift"] * 0.25, G["lift"]
            lf = (sup, sw) if s > 0 else (sw, sup)
            kn = (G["kf"] + 4, G["K"]) if s > 0 else (G["K"], G["kf"] + 4)
            ft = (0, -G["foot_b"] * 0.8) if s > 0 else (-G["foot_b"] * 0.8, 0)
            d = dict(base)
            d.update(arms(s, 0.0))
            d.update(hips_z=G["hz_p"], hips_twist=0, spine_twist=0, spine_pitch=G["spine_pitch"], neck_pitch=G["neck_pitch"],
                     hips_side=G["sway"] * 0.6 * s, leg_fwd=lf, knee=kn, foot=ft)
            return P_(**d)
        return contact, passing

    for name, key, length in (("walk", "walk", 1.0), ("run", "run", 0.62)):
        c, p = gait(S[key])
        clip(name, length, True, [(0.0, c(1)), (length * 0.25, p(1)), (length * 0.5, c(-1)), (length * 0.75, p(-1)), (length, c(1))])

    # ---- 공중 ----
    J, F = S["jump"], S["fall"]
    au, ao = J["arms_up"], J["arms_out"]
    arm_c = dict(hold)
    crouch = with_hold(**J["crouch"], arm_fwd=(hold["arm_fwd"][0] - 20, hold["arm_fwd"][1] - 20))
    launch = with_hold(**J["launch"], arm_fwd=(hold["arm_fwd"][0] + au[0], hold["arm_fwd"][1] + au[1]), arm_out=(hold["arm_out"][0] + ao[0], hold["arm_out"][1] + ao[1]))
    tuck = with_hold(**J["tuck"], arm_fwd=(hold["arm_fwd"][0] + au[0] * 0.6, hold["arm_fwd"][1] + au[1] * 0.6), arm_out=(hold["arm_out"][0] + ao[0], hold["arm_out"][1] + ao[1]))
    clip("jump", 0.60, False, [(0.0, crouch), (0.12, launch), (0.40, tuck), (0.60, tuck)])
    fo = F["arms_out"]
    fu = F["arms_up"]
    fkw = dict(arm_fwd=(hold["arm_fwd"][0] + fu[0], hold["arm_fwd"][1] + fu[1]), arm_out=(hold["arm_out"][0] + fo[0], hold["arm_out"][1] + fo[1]), spine_pitch=F["spine_pitch"], neck_pitch=-6)
    fa = with_hold(**F["a"], **fkw)
    fb = with_hold(**F["b"], **fkw)
    clip("fall", 0.8, True, [(0.0, fa), (0.4, fb), (0.8, fa)])
    clip("land", 0.30, False, [(0.0, with_hold(**S["land"])), (0.30, ready)])
