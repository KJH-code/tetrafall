# 탱크 이동 동작 (W33): 무겁고 느린 걸음, 방패 든 왼팔·해머 든 오른팔은 거의 안 흔들고 몸통·골반으로 무게를 옮김. 공격·스킬은 코드 구동 유지.
from clips_loco import define_loco

STYLE = dict(
    hold=dict(arm_fwd=(38, 14), arm_out=(2, 4), elbow=(70, 34), hand=(0, 0)),
    idle=dict(spine_pitch=3, leg_fwd=(4, -2), knee=(8, 6)),
    breathe=dict(spine_pitch=2, neck_pitch=-1, hips_z=-0.006),
    base=dict(),
    walk=dict(A=25, back=0.9, kf=8, kb=18, lift=20, K=40, foot_f=-7, foot_b=12, hz_c=-0.014, hz_p=0.006, hips_twist=4, spine_twist=-5, spine_pitch=3,
              neck_pitch=1, sway=5.0, spine_side=2.0, arm_swing=(4, 10), arm_elbow_gain=0.3),
    run=dict(A=42, back=0.9, kf=18, kb=38, lift=8, K=70, foot_f=-11, foot_b=22, hz_c=-0.03, hz_p=-0.012, hips_twist=7, spine_twist=-9, spine_pitch=13,
             neck_pitch=-6, sway=5.0, spine_side=2.5, arm_swing=(8, 18), arm_elbow_gain=0.4),
    jump=dict(arms_up=(26, 26), arms_out=(10, 10)),
    fall=dict(arms_out=(30, 30), arms_up=(14, 14)),
    land=dict(hips_z=-0.08, spine_pitch=22, leg_fwd=(34, 28), knee=(70, 64)),
)


def define(M):
    define_loco(M, STYLE)
    define_attacks(M)


# ---- W38 평타·스킬 (해머 = 오른손, 방패 = 왼손). 눈금 WIND/STRIKE/REC 는 clips_ninja.py 와 같음 (런타임이 서버 단계를 눈금에 맞춤) ----
def define_attacks(M):
    P_, clip, mirror = M.P_, M.clip, M.mirror
    W, S, R = M.WIND, M.STRIKE, M.REC
    guard = dict(arm_fwd=(38, 20), arm_out=(2, 8), elbow=(70, 70))  # 왼팔 방패는 가슴 앞에 (오른팔은 각 동작이 정함)
    ready = P_(spine_pitch=3, leg_fwd=(4, -2), knee=(8, 6), **guard)

    # 주먹 (해머 옆 후려치기): 크게 뒤로 감아 올림 → 허리 비틀며 앞으로 내딛고 쭉 뻗음 → 여운
    w = P_(hips_z=-0.05, hips_twist=-12, spine_pitch=-6, spine_twist=-42, neck_yaw=18, neck_pitch=-4, leg_fwd=(-12, 24), knee=(30, 40), foot=(0, -6),
           arm_fwd=(120, 20), arm_out=(46, 8), elbow=(70, 70), clav_fwd=(-14, 4))
    s = P_(hips_x=0.12, hips_z=-0.07, hips_twist=18, spine_pitch=20, spine_twist=40, neck_yaw=-14, neck_pitch=-8, leg_fwd=(-26, 44), knee=(14, 46), foot=(10, -10),
           arm_fwd=(92, 20), arm_out=(10, 8), elbow=(2, 70), clav_fwd=(18, 4))
    f = P_(s, hips_x=0.14, spine_twist=30, arm_fwd=(80, 20), arm_out=(24, 8), elbow=(14, 70))
    clip("t_punch", R, False, [(0.0, ready), (W, w), (S, s), (0.55, f), (R, ready)])

    # 어깨 박치기 (방패 든 왼쪽 어깨로 들이받음): 오른쪽으로 비틀며 웅크림 → 왼 어깨 앞으로 몸 전체 실음
    w = P_(hips_z=-0.09, hips_twist=-16, spine_pitch=14, spine_twist=-34, neck_pitch=-8, leg_fwd=(24, -14), knee=(48, 22), foot=(-8, 4),
           arm_fwd=(10, 78), arm_out=(10, 22), elbow=(100, 100))
    s = P_(hips_x=0.16, hips_z=-0.06, hips_twist=22, spine_pitch=30, spine_twist=34, neck_pitch=-14, leg_fwd=(-30, 38), knee=(10, 52), foot=(12, -8),
           arm_fwd=(30, 80), arm_out=(8, 24), elbow=(90, 100), clav_fwd=(10, 18))
    clip("t_bash", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, hips_x=0.1, spine_pitch=22, spine_twist=22)), (R, ready)])

    # 방패 올려치기: 낮게 웅크려 방패를 아래로 → 일어서며 방패·해머를 위로 쳐올림
    w = P_(hips_z=-0.12, spine_pitch=32, neck_pitch=-14, leg_fwd=(36, 30), knee=(70, 64), foot=(-18, -16),
           arm_fwd=(10, 20), arm_out=(10, 10), elbow=(80, 90))
    s = P_(hips_x=0.05, hips_z=0.0, spine_pitch=-22, neck_pitch=6, leg_fwd=(14, 8), knee=(10, 8), foot=(14, 14),
           arm_fwd=(140, 148), arm_out=(14, 18), elbow=(30, 40), clav_lift=(8, 8))
    clip("t_upper", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, spine_pitch=-14, arm_fwd=(124, 130))), (R, ready)])

    # 방패 내려치기 (공중): 두 팔 높이 들고 몸 젖힘 → 온몸으로 내리꽂음
    air = P_(spine_pitch=8, neck_pitch=-6, leg_fwd=(30, 20), knee=(60, 50), foot=(8, 8), arm_fwd=(60, 50), arm_out=(14, 14), elbow=(60, 60))
    w = P_(air, spine_pitch=-18, neck_pitch=-4, arm_fwd=(168, 160), arm_out=(14, 18), elbow=(40, 50), leg_fwd=(36, 30))
    s = P_(air, spine_pitch=46, neck_pitch=-20, arm_fwd=(34, 30), arm_out=(10, 10), elbow=(6, 10), leg_fwd=(-10, -6), knee=(20, 20))
    clip("t_dive", R, False, [(0.0, air), (W, w), (S, s), (R, P_(s, spine_pitch=30))])

    # 돌진 (방패 앞세우고 어깨 숙여 달림): 상체 크게 숙여 방패를 앞으로
    cw = P_(hips_z=-0.08, spine_pitch=30, neck_pitch=-14, leg_fwd=(38, -20), knee=(60, 30), foot=(-12, 10), arm_fwd=(60, 100), arm_out=(10, 14), elbow=(100, 70))
    cs = P_(hips_x=0.1, hips_z=-0.06, spine_pitch=42, neck_pitch=-20, leg_fwd=(-24, 40), knee=(14, 54), foot=(12, -8), arm_fwd=(60, 100), arm_out=(10, 14), elbow=(100, 70))
    clip("t_charge", R, False, [(0.0, ready), (W, cw), (S, cs), (0.6, P_(cs, leg_fwd=(40, -24), knee=(56, 20))), (R, P_(cs, leg_fwd=(-20, 36)))])

    # 땅 가르기 (R 솟는 땅): 해머 높이 머리 위 → 온몸으로 땅을 내리찍음
    sw = P_(hips_z=-0.04, spine_pitch=-20, neck_pitch=-8, leg_fwd=(26, 20), knee=(40, 40), arm_fwd=(172, 40), arm_out=(14, 10), elbow=(30, 70))
    ss = P_(hips_x=0.1, hips_z=-0.12, spine_pitch=50, neck_pitch=-24, leg_fwd=(40, 34), knee=(60, 56), foot=(-14, -14), arm_fwd=(62, 40), arm_out=(10, 10), elbow=(2, 70))
    clip("t_slam", R, False, [(0.0, ready), (W, sw), (S, ss), (0.6, P_(ss, hips_z=-0.14, spine_pitch=46)), (R, ready)])
