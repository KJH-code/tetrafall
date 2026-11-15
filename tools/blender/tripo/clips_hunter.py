# 사냥꾼 이동 동작 (W33): 소총을 두 손으로 가슴 앞에 받치고 낮게 웅크려 걸음, 달릴 땐 상체를 더 숙임 (팔 흔들림 작게). 공격·스킬은 코드 구동 유지.
from clips_loco import define_loco

STYLE = dict(
    hold=dict(arm_fwd=(28, 12), arm_out=(2, 6), elbow=(52, 28), hand=(0, 0)),
    idle=dict(spine_pitch=2),
    breathe=dict(spine_pitch=2, neck_pitch=-1, hips_z=-0.004),
    walk=dict(A=29, back=0.9, kf=7, kb=22, lift=24, K=48, foot_f=-8, foot_b=14, hz_c=-0.014, hz_p=0.004, hips_twist=5, spine_twist=-6, spine_pitch=3,
              neck_pitch=0, sway=2.0, arm_swing=(5, 5), arm_elbow_gain=0.3),
    run=dict(A=46, back=0.9, kf=18, kb=42, lift=8, K=80, foot_f=-12, foot_b=26, hz_c=-0.03, hz_p=-0.01, hips_twist=8, spine_twist=-9, spine_pitch=14,
             neck_pitch=-8, sway=3.0, arm_swing=(8, 8), arm_elbow_gain=0.3),
    jump=dict(arms_up=(20, 20), arms_out=(10, 10)),
    fall=dict(arms_out=(24, 24), arms_up=(14, 14)),
)


def define(M):
    define_loco(M, STYLE)
    define_attacks(M)
    define_poses(M)


# ---- W38 평타·스킬 (소총 = 오른손 메시에 붙음, 왼손은 받침). 눈금 WIND/STRIKE/REC 는 clips_ninja.py 와 같음 ----
def define_attacks(M):
    P_, clip, mirror = M.P_, M.clip, M.mirror
    W, S, R = M.WIND, M.STRIKE, M.REC
    ready = P_(spine_pitch=2, arm_fwd=(28, 12), arm_out=(2, 6), elbow=(52, 28), knee=(8, 8), leg_fwd=(4, -2))

    # 베기 (오른손 대각 베기): 오른쪽 위로 젖혔다가 몸을 감으며 왼쪽 아래로 휘두름
    w = P_(ready, hips_z=-0.04, hips_twist=-10, spine_pitch=-4, spine_twist=-36, neck_yaw=14, leg_fwd=(-10, 22), knee=(26, 36),
           arm_fwd=(110, 30), arm_out=(60, 10), elbow=(70, 50), clav_fwd=(-12, 4))
    s = P_(ready, hips_x=0.32, hips_z=-0.08, hips_twist=22, spine_pitch=30, spine_twist=44, neck_yaw=-12, leg_fwd=(-34, 52), knee=(12, 54), foot=(10, -8),
           arm_fwd=(96, 30), arm_out=(6, 10), elbow=(4, 56), clav_fwd=(18, 2))
    clip("h_slash", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, hips_x=0.34, spine_twist=30, arm_fwd=(80, 30), elbow=(16, 56))), (R, ready)])

    # 반대 베기 (되받아 치기): 왼쪽 아래에서 오른쪽 위로 올려 베며 반대로 감음
    w = P_(ready, hips_z=-0.05, hips_twist=14, spine_pitch=10, spine_twist=30, neck_yaw=-12, leg_fwd=(22, -10), knee=(34, 20),
           arm_fwd=(40, 12), arm_out=(-8, 6), elbow=(60, 40), clav_fwd=(10, 0))
    s = P_(ready, hips_x=0.32, hips_z=-0.06, hips_twist=-20, spine_pitch=14, spine_twist=-44, neck_yaw=12, leg_fwd=(52, -30), knee=(46, 20),
           arm_fwd=(120, 24), arm_out=(64, 8), elbow=(4, 50), clav_fwd=(-14, 4))
    clip("h_back", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, hips_x=0.34, arm_fwd=(104, 24))), (R, ready)])

    # 찔러 넣기: 낮게 몸을 접어 뒤로 당김 → 한 발 크게 내딛으며 소총 끝을 곧게 찌름
    w = P_(ready, hips_z=-0.1, hips_twist=-14, spine_pitch=16, spine_twist=-26, neck_pitch=-8, leg_fwd=(-16, 34), knee=(40, 54), foot=(2, -8),
           arm_fwd=(16, 26), arm_out=(30, 8), elbow=(124, 100), clav_fwd=(-14, -8))
    s = P_(ready, hips_x=0.46, hips_z=-0.12, hips_twist=22, spine_pitch=38, spine_twist=30, neck_pitch=-14, leg_fwd=(-46, 58), knee=(8, 70), foot=(14, -10),
           arm_fwd=(100, 92), arm_out=(2, 6), elbow=(2, 8), clav_fwd=(22, 18))
    clip("h_thrust", R, False, [(0.0, ready), (W, w), (S, s), (0.58, P_(s, hips_x=0.48, spine_pitch=34)), (R, ready)])

    # 내려 베기 (공중): 소총을 머리 위로 → 온몸으로 내리침
    air = P_(ready, spine_pitch=8, neck_pitch=-6, leg_fwd=(30, 20), knee=(60, 50), foot=(8, 8), arm_fwd=(60, 40), arm_out=(14, 14), elbow=(60, 60))
    w = P_(air, spine_pitch=-16, arm_fwd=(150, 100), arm_out=(14, 10), elbow=(60, 80), leg_fwd=(40, 28))
    s = P_(air, hips_x=0.30, spine_pitch=52, neck_pitch=-20, arm_fwd=(62, 54), arm_out=(6, 6), elbow=(4, 8), leg_fwd=(-8, -4), knee=(20, 20))
    clip("h_dive", R, False, [(0.0, air), (W, w), (S, s), (R, P_(s, spine_pitch=30))])

    # 조준 (R 처형 사격·F 표식 조준): 소총을 어깨에 대고 두 팔을 앞으로 → 탕 반동 → 장전하듯 내림
    aim = P_(ready, hips_z=-0.03, hips_twist=-8, spine_pitch=4, spine_twist=-14, neck_yaw=8, neck_pitch=4, leg_fwd=(-8, 14), knee=(18, 24),
             arm_fwd=(50, 78), arm_out=(-4, 8), elbow=(34, 40), clav_fwd=(10, 8))
    shot = P_(aim, spine_pitch=-8, neck_pitch=-4, hips_x=-0.05, arm_fwd=(62, 84), elbow=(44, 50), leg_fwd=(-4, 10))
    clip("h_aim", R, False, [(0.0, ready), (W, aim), (S, shot), (0.55, P_(aim, arm_fwd=(34, 50), elbow=(58, 60), spine_pitch=2)), (R, ready)])

    # 추적 도약 (표식 쫓아 덮침): 크게 웅크림 → 몸 쭉 펴 날아가며 소총 앞으로
    lw = P_(ready, hips_z=-0.14, spine_pitch=40, neck_pitch=-24, leg_fwd=(52, 48), knee=(96, 90), foot=(-20, -20), arm_fwd=(72, 72), arm_out=(10, 10), elbow=(60, 60))
    ls = P_(ready, spine_pitch=30, neck_pitch=-14, leg_fwd=(-30, -18), knee=(18, 30), foot=(36, 30), arm_fwd=(80, 90), arm_out=(14, 10), elbow=(30, 36))
    clip("h_leap", R, False, [(0.0, ready), (W, lw), (S, ls), (0.6, P_(ls, spine_pitch=36, leg_fwd=(-20, -10))), (R, P_(ls, spine_pitch=22, leg_fwd=(20, 10), knee=(40, 50)))])


# ---- W38 도발 ("찍었다", 1.6초)·승리 (반복) ----
def define_poses(M):
    P_, clip = M.P_, M.clip
    ready = P_(spine_pitch=2, arm_fwd=(28, 12), arm_out=(2, 6), elbow=(52, 28), knee=(8, 8), leg_fwd=(4, -2))
    tip = P_(ready, hips_twist=-6, spine_twist=-12, neck_pitch=-6, leg_fwd=(-6, 14), knee=(16, 22), arm_fwd=(44, 150), arm_out=(4, 20), elbow=(40, 122))
    tip2 = P_(tip, neck_pitch=-12, spine_pitch=6, arm_fwd=(44, 156), elbow=(40, 130))
    clip("h_taunt", 1.6, False, [(0.0, ready), (0.3, tip), (0.7, tip2), (1.1, tip), (1.3, tip2), (1.6, ready)])
    up = P_(ready, spine_pitch=-6, neck_pitch=-8, leg_fwd=(8, -6), knee=(10, 12), arm_fwd=(120, 60), arm_out=(10, 24), elbow=(30, 100))
    up2 = P_(up, hips_z=0.012, spine_pitch=-10, arm_fwd=(126, 140), elbow=(30, 70))
    clip("h_victory", 1.6, True, [(0.0, up), (0.4, up2), (0.8, up), (1.2, up2), (1.6, up)])
