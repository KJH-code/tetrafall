# 닌자 동작 표 (anim_ninja.py 가 부름). 자세 값 설명은 anim_ninja.py 머리말.
# 공격은 눈금 WIND(준비 끝)·STRIKE(타격 끝)·REC(회복 끝) 에 키: 0 = 준비 자세, WIND = 가장 뒤로 당긴 자세, STRIKE = 맞히는 순간 (가장 뻗은 자세), REC = 다시 준비 자세.
# 런타임이 서버 단계 (준비·타격·회복) 를 이 눈금에 구간별로 맞춰서 타격 순간이 판정과 같음.
def define(M):
    P_, clip, mirror = M.P_, M.clip, M.mirror
    W, S, R = M.WIND, M.STRIKE, M.REC

    # ---- 서 있기 (낮은 자세, 숨쉬기) ----
    ready = P_(hips_z=-0.014, spine_pitch=7, neck_pitch=-5, leg_fwd=(5, -3), knee=(16, 14), foot=(-4, 2),
               arm_fwd=(10, 12), arm_out=(4, 4), elbow=(36, 38), hand=(8, 8), clav_lift=(0, 0))
    breathe = P_(ready, hips_z=-0.018, spine_pitch=9, neck_pitch=-6, arm_fwd=(12, 13), elbow=(40, 42), clav_lift=(2, 2))
    clip("idle", 2.4, True, [(0.0, ready), (1.2, breathe), (2.4, ready)])

    # ---- 달리기 (닌자 달리기: 많이 숙이고 두 팔을 뒤로 젖힘). 한 바퀴 = 두 걸음 ----
    runR = P_(hips_z=-0.03, hips_twist=9, hips_pitch=5, spine_pitch=22, spine_twist=-16, neck_pitch=-14,
              leg_fwd=(44, -34), knee=(20, 40), foot=(-12, 28), toe=(0, 12),
              arm_fwd=(-62, -34), arm_out=(6, 8), elbow=(16, 34), clav_fwd=(-6, 6))
    passR = P_(hips_z=-0.012, hips_twist=0, hips_pitch=5, spine_pitch=22, spine_twist=0, neck_pitch=-14,
               leg_fwd=(6, 18), knee=(24, 78), foot=(2, -22), toe=(0, 0),
               arm_fwd=(-48, -48), arm_out=(6, 6), elbow=(22, 22), clav_fwd=(0, 0))
    runL = mirror(runR)
    passL = mirror(passR)
    clip("run", 0.60, True, [(0.0, runR), (0.15, passR), (0.30, runL), (0.45, passL), (0.60, runR)])

    wR = P_(hips_z=-0.016, hips_twist=6, spine_pitch=8, spine_twist=-9, neck_pitch=-5,
            leg_fwd=(28, -22), knee=(10, 22), foot=(-8, 12),
            arm_fwd=(-26, 24), arm_out=(5, 5), elbow=(20, 30), clav_fwd=(-3, 3))
    wpR = P_(hips_z=-0.006, spine_pitch=8, neck_pitch=-5, leg_fwd=(4, 8), knee=(14, 40), foot=(0, -12),
             arm_fwd=(0, 0), arm_out=(5, 5), elbow=(22, 24))
    clip("walk", 0.9, True, [(0.0, wR), (0.225, wpR), (0.45, mirror(wR)), (0.675, mirror(wpR)), (0.9, wR)])

    # ---- 공중 ----
    crouch = P_(hips_z=-0.05, spine_pitch=20, neck_pitch=-10, leg_fwd=(30, 30), knee=(62, 62), foot=(-20, -20), arm_fwd=(-40, -40), arm_out=(10, 10), elbow=(30, 30))
    launch = P_(hips_z=0.0, spine_pitch=2, neck_pitch=-8, leg_fwd=(-6, -8), knee=(6, 8), foot=(30, 30), arm_fwd=(110, 105), arm_out=(18, 18), elbow=(18, 18))
    tuck = P_(hips_z=0.0, spine_pitch=14, neck_pitch=-10, leg_fwd=(56, 36), knee=(88, 70), foot=(10, 10), arm_fwd=(85, 80), arm_out=(30, 30), elbow=(40, 40))
    clip("jump", 0.60, False, [(0.0, crouch), (0.12, launch), (0.40, tuck), (0.60, tuck)])
    fa = P_(hips_z=0.0, spine_pitch=2, neck_pitch=-6, leg_fwd=(24, 4), knee=(26, 48), foot=(12, 20),
            arm_fwd=(30, 56), arm_out=(62, 70), elbow=(26, 30), clav_lift=(6, 6))
    fb = P_(hips_z=0.0, spine_pitch=4, neck_pitch=-6, leg_fwd=(4, 24), knee=(48, 26), foot=(20, 12),
            arm_fwd=(56, 30), arm_out=(70, 62), elbow=(30, 26), clav_lift=(6, 6))
    clip("fall", 0.8, True, [(0.0, fa), (0.4, fb), (0.8, fa)])
    landdeep = P_(hips_z=-0.075, spine_pitch=26, neck_pitch=-14, leg_fwd=(38, 30), knee=(74, 68), foot=(-22, -20), arm_fwd=(30, 24), arm_out=(30, 30), elbow=(46, 42))
    clip("land", 0.30, False, [(0.0, landdeep), (0.30, ready)])

    # ---- 평타 1: 찌르기 (오른손 단검) ----
    a1_w = P_(hips_z=-0.04, hips_twist=-8, spine_pitch=10, spine_twist=-30, neck_pitch=-6, neck_yaw=14,
              leg_fwd=(-14, 26), knee=(36, 40), foot=(0, -6),
              arm_fwd=(14, 52), arm_out=(32, 6), elbow=(118, 96), clav_fwd=(-10, 6), hand=(-10, 0))
    a1_s = P_(hips_x=0.05, hips_z=-0.045, hips_twist=14, spine_pitch=16, spine_twist=26, neck_pitch=-9, neck_yaw=-12,
              leg_fwd=(-30, 38), knee=(14, 40), foot=(10, -8),
              arm_fwd=(96, -22), arm_out=(4, 14), elbow=(4, 102), clav_fwd=(14, -8), hand=(0, 0))
    a1_f = P_(a1_s, hips_x=0.04, spine_twist=14, arm_fwd=(86, -10), elbow=(14, 90))
    clip("atk1", R, False, [(0.0, ready), (W, a1_w), (S, a1_s), (0.55, a1_f), (R, ready)])
    clip("atk2", R, False, [(0.0, ready), (W, mirror(a1_w)), (S, mirror(a1_s)), (0.55, mirror(a1_f)), (R, ready)])

    # ---- 평타 3: 앞차기 (오른발) ----
    k3_w = P_(hips_z=-0.03, spine_pitch=-4, neck_pitch=-4, leg_fwd=(74, -4), knee=(112, 22), foot=(-10, 6),
              arm_fwd=(36, 40), arm_out=(30, 30), elbow=(70, 70))
    k3_s = P_(hips_x=0.03, hips_z=-0.01, spine_pitch=-12, neck_pitch=-2, leg_fwd=(96, -8), knee=(6, 18), foot=(-30, 4),
              arm_fwd=(-6, 28), arm_out=(46, 46), elbow=(38, 50))
    clip("atk3", R, False, [(0.0, ready), (W, k3_w), (S, k3_s), (0.58, P_(k3_s, leg_fwd=(78, -6), knee=(60, 20), foot=(-12, 4))), (R, ready)])

    # ---- 평타 4: 올려 차기 (오른발, 크게 뒤로 젖히며) ----
    k4_w = P_(hips_z=-0.07, spine_pitch=24, neck_pitch=-12, leg_fwd=(40, 30), knee=(68, 60), foot=(-18, -16),
              arm_fwd=(-34, -34), arm_out=(14, 14), elbow=(40, 40))
    k4_s = P_(hips_x=0.02, hips_z=0.0, spine_pitch=-26, neck_pitch=6, leg_fwd=(128, -4), knee=(4, 14), foot=(-24, 22),
              arm_fwd=(60, 80), arm_out=(60, 56), elbow=(26, 30), clav_lift=(6, 6))
    clip("atk4", R, False, [(0.0, ready), (W, k4_w), (S, k4_s), (0.58, P_(k4_s, leg_fwd=(96, 4), knee=(40, 20), spine_pitch=-14)), (R, ready)])

    # ---- 공중 평타 ----
    air_ready = P_(spine_pitch=8, neck_pitch=-8, leg_fwd=(44, 26), knee=(76, 62), foot=(8, 8), arm_fwd=(60, 60), arm_out=(30, 30), elbow=(46, 46))
    ax_w = P_(air_ready, spine_pitch=-8, spine_twist=-22, arm_fwd=(150, 40), arm_out=(30, 40), elbow=(60, 80))
    ax_s = P_(air_ready, spine_pitch=22, spine_twist=24, arm_fwd=(34, 10), arm_out=(12, 36), elbow=(4, 90), neck_pitch=-12)
    clip("air1", R, False, [(0.0, air_ready), (W, ax_w), (S, ax_s), (R, air_ready)])
    ak_w = P_(air_ready, spine_pitch=-14, neck_pitch=-4, leg_fwd=(140, 20), knee=(30, 70), arm_fwd=(130, 130), arm_out=(50, 50), elbow=(30, 30))
    ak_s = P_(air_ready, spine_pitch=30, neck_pitch=-14, leg_fwd=(34, 36), knee=(6, 80), arm_fwd=(-20, -20), arm_out=(40, 40), elbow=(30, 30))
    clip("air2", R, False, [(0.0, air_ready), (W, ak_w), (S, ak_s), (R, P_(ak_s, leg_fwd=(50, 40), knee=(30, 80)))])

    # ---- 스킬: 순간 베기 (두 단검을 앞으로 뻗어 날아감) ----
    d_w = P_(hips_z=-0.06, spine_pitch=26, neck_pitch=-14, leg_fwd=(36, 28), knee=(70, 62), foot=(-16, -16), arm_fwd=(-46, -46), arm_out=(14, 14), elbow=(34, 34), clav_fwd=(-10, -10))
    d_s = P_(hips_z=0.0, hips_x=0.05, spine_pitch=52, neck_pitch=-30, leg_fwd=(-34, -28), knee=(10, 14), foot=(40, 40), toe=(10, 10),
             arm_fwd=(88, 88), arm_out=(10, 10), elbow=(4, 4), clav_fwd=(16, 16))
    clip("dash", R, False, [(0.0, ready), (W, d_w), (S, d_s), (0.6, P_(d_s, spine_pitch=40)), (R, P_(d_s, spine_pitch=28, arm_fwd=(60, 60), elbow=(30, 30)))])

    # ---- 표창 (오른팔 머리 위에서 내려 던짐) ----
    st_w = P_(hips_z=-0.025, spine_pitch=-6, spine_twist=-26, neck_pitch=-4, neck_yaw=12, leg_fwd=(-10, 22), knee=(22, 30),
              arm_fwd=(148, 40), arm_out=(30, 12), elbow=(100, 70), clav_fwd=(-8, 4))
    st_s = P_(hips_z=-0.03, hips_x=0.03, spine_pitch=20, spine_twist=22, neck_pitch=-9, neck_yaw=-10, leg_fwd=(-22, 30), knee=(10, 28),
              arm_fwd=(70, 10), arm_out=(8, 18), elbow=(0, 80), clav_fwd=(14, -6))
    clip("star", R, False, [(0.0, ready), (W, st_w), (S, st_s), (R, ready)])
    clip("airstar", R, False, [(0.0, air_ready), (W, P_(ax_w, arm_fwd=(140, 40))), (S, P_(air_ready, spine_pitch=20, spine_twist=22, arm_fwd=(66, 10), arm_out=(10, 20), elbow=(0, 80))), (R, air_ready)])
