# 갈고리 (해적 선장) 이동 동작 (W33): 어깨를 으스대며 흔드는 걸음, 오른팔은 칼 쥔 손 자연스럽게, 왼팔 (갈고리) 은 크게. 공격·스킬은 코드 구동 유지.
from clips_loco import define_loco

STYLE = dict(
    hold=dict(arm_fwd=(8, 8), arm_out=(6, 6), elbow=(30, 34), hand=(0, 0)),
    idle=dict(spine_pitch=-1, spine_twist=3),
    breathe=dict(spine_pitch=2, neck_pitch=-1, hips_z=-0.004),
    walk=dict(A=29, back=0.9, kf=6, kb=20, lift=22, K=46, foot_f=-8, foot_b=14, hz_c=-0.012, hz_p=0.005, hips_twist=7, spine_twist=-8, spine_pitch=1,
              neck_pitch=0, sway=3.5, arm_swing=(16, 20), arm_elbow_gain=0.4),
    run=dict(A=46, back=0.9, kf=18, kb=42, lift=8, K=80, foot_f=-12, foot_b=26, hz_c=-0.028, hz_p=-0.008, hips_twist=9, spine_twist=-12, spine_pitch=12,
             neck_pitch=-7, sway=3.5, arm_swing=(30, 34), arm_elbow_gain=0.5),
    jump=dict(arms_up=(40, 40), arms_out=(14, 14)),
    fall=dict(arms_out=(40, 40), arms_up=(24, 24)),
)


def define(M):
    define_loco(M, STYLE)
    define_attacks(M)
    define_poses(M)


# ---- W38 평타·스킬 (오른손 = 칼/권총, 왼손 = 갈고리). 눈금 WIND/STRIKE/REC 는 clips_ninja.py 와 같음 ----
def define_attacks(M):
    P_, clip, mirror = M.P_, M.clip, M.mirror
    W, S, R = M.WIND, M.STRIKE, M.REC
    ready = P_(spine_pitch=-1, spine_twist=3, arm_fwd=(8, 8), arm_out=(6, 6), elbow=(30, 34), knee=(8, 8), leg_fwd=(4, -2))
    air = P_(ready, spine_pitch=8, neck_pitch=-6, leg_fwd=(30, 20), knee=(60, 50), foot=(8, 8), arm_fwd=(50, 50), arm_out=(14, 14), elbow=(60, 60))

    # 갈고리 휘두르기 (왼팔 옆으로 크게 벌려 감았다가 몸을 비틀며 앞으로 후려침)
    w = P_(ready, hips_z=-0.05, hips_twist=12, spine_pitch=2, spine_twist=44, neck_yaw=-16, leg_fwd=(26, -10), knee=(40, 20),
           arm_fwd=(10, -14), arm_out=(10, 112), elbow=(30, 46), clav_fwd=(4, -14))
    s = P_(ready, hips_x=0.24, hips_z=-0.06, hips_twist=-18, spine_pitch=20, spine_twist=-40, neck_yaw=14, leg_fwd=(40, -26), knee=(40, 22), foot=(-6, 8),
           arm_fwd=(10, 86), arm_out=(10, 8), elbow=(30, 4), clav_fwd=(4, 18))
    clip("k_hook", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, hips_x=0.28, spine_twist=-28, arm_fwd=(10, 72), arm_out=(10, 24))), (R, ready)])

    # 주먹 (오른팔 주먹 → 몸 실어 곧게 찌름)
    w = P_(ready, hips_z=-0.06, hips_twist=-12, spine_pitch=-4, spine_twist=-36, neck_yaw=14, leg_fwd=(-14, 28), knee=(34, 44),
           arm_fwd=(-12, 12), arm_out=(34, 6), elbow=(116, 40), clav_fwd=(-14, 4))
    s = P_(ready, hips_x=0.32, hips_z=-0.07, hips_twist=18, spine_pitch=24, spine_twist=32, neck_yaw=-12, leg_fwd=(-30, 46), knee=(12, 52), foot=(12, -10),
           arm_fwd=(92, 12), arm_out=(2, 6), elbow=(0, 40), clav_fwd=(22, 4))
    clip("k_fist", R, False, [(0.0, ready), (W, w), (S, s), (0.55, P_(s, hips_x=0.36, spine_twist=24, arm_fwd=(84, 12))), (R, ready)])

    # 갈고리 내려치기 (왼팔 머리 위 → 내리꽂음)
    w = P_(ready, hips_z=-0.03, spine_pitch=-12, neck_pitch=-6, leg_fwd=(24, 16), knee=(34, 30), arm_fwd=(10, 168), arm_out=(6, 14), elbow=(30, 40))
    s = P_(ready, hips_x=0.20, hips_z=-0.1, spine_pitch=40, neck_pitch=-22, leg_fwd=(34, 28), knee=(52, 48), foot=(-10, -10), arm_fwd=(10, 50), arm_out=(6, 8), elbow=(30, 4))
    clip("k_chop", R, False, [(0.0, ready), (W, w), (S, s), (0.6, P_(s, hips_z=-0.12, spine_pitch=36)), (R, ready)])

    # 탕 (권총, 오른손): 팔 앞으로 조준 → 반동으로 팔이 위로 튐
    aim = P_(ready, hips_z=-0.03, hips_twist=-6, spine_twist=-12, neck_yaw=8, leg_fwd=(-6, 14), knee=(16, 22), arm_fwd=(86, 14), arm_out=(0, 6), elbow=(8, 40), clav_fwd=(10, 0))
    kick = P_(aim, hips_x=-0.05, spine_pitch=-8, neck_pitch=-5, arm_fwd=(122, 14), elbow=(34, 40))
    clip("k_shot", R, False, [(0.0, ready), (W, aim), (S, kick), (0.55, P_(aim, arm_fwd=(60, 14), elbow=(50, 40))), (R, ready)])

    # 갈고리 스핀 (공중): 팔 벌려 갈고리 쪽을 크게 휘두르며 몸 비틂 (회전은 코드가 몸 전체를 돌림)
    w = P_(air, spine_twist=40, arm_fwd=(10, -10), arm_out=(30, 112), elbow=(30, 40))
    s = P_(air, spine_twist=-30, arm_fwd=(10, 12), arm_out=(30, 100), elbow=(30, 8), spine_pitch=14)
    clip("k_spin", R, False, [(0.0, air), (W, w), (S, s), (R, P_(s, spine_twist=-10))])

    # 갈고리 던지기: 왼팔을 뒤로 젖혔다 앞으로 곧게 뻗어 던짐 (줄이 날아감)
    w = P_(ready, hips_z=-0.04, hips_twist=10, spine_pitch=-4, spine_twist=34, neck_yaw=-12, leg_fwd=(20, -8), knee=(30, 18),
           arm_fwd=(8, -34), arm_out=(6, 70), elbow=(30, 100), clav_fwd=(0, -14))
    s = P_(ready, hips_x=0.20, hips_z=-0.05, hips_twist=-14, spine_pitch=14, spine_twist=-28, neck_yaw=12, leg_fwd=(34, -20), knee=(32, 18),
           arm_fwd=(8, 96), arm_out=(6, 2), elbow=(30, 0), clav_fwd=(0, 22))
    clip("k_throw", R, False, [(0.0, ready), (W, w), (S, s), (0.6, P_(s, hips_x=0.24, arm_fwd=(8, 84))), (R, ready)])

    # 블록 내려찍기 준비·타격 (두 팔 위로 → 내리침)
    w = P_(ready, hips_z=-0.04, spine_pitch=-16, neck_pitch=-8, leg_fwd=(26, 20), knee=(36, 34), arm_fwd=(166, 166), arm_out=(12, 14), elbow=(30, 40))
    s = P_(ready, hips_x=0.16, hips_z=-0.1, spine_pitch=44, neck_pitch=-22, leg_fwd=(36, 30), knee=(56, 50), foot=(-10, -10), arm_fwd=(48, 48), arm_out=(8, 8), elbow=(6, 6))
    clip("k_slam", R, False, [(0.0, ready), (W, w), (S, s), (0.6, P_(s, hips_z=-0.12)), (R, ready)])

    # 갈고리 줄 타고 날아가기 (공중, 왼팔 위로 쭉 뻗고 몸은 매달려 끌려감)
    zw = P_(air, spine_pitch=10, arm_fwd=(-30, 130), arm_out=(30, 10), elbow=(50, 8), leg_fwd=(-30, -20), knee=(30, 40))
    clip("k_zip", R, False, [(0.0, air), (W, zw), (S, zw), (R, zw)])


# ---- W38 도발 ("이리 와", 1.6초)·승리 (반복) ----
def define_poses(M):
    P_, clip = M.P_, M.clip
    ready = P_(spine_pitch=-1, spine_twist=3, arm_fwd=(8, 8), arm_out=(6, 6), elbow=(30, 34), knee=(8, 8), leg_fwd=(4, -2))
    beck = P_(ready, hips_twist=-8, spine_twist=-12, neck_pitch=-6, leg_fwd=(-6, 14), knee=(16, 22), arm_fwd=(14, 80), arm_out=(10, 10), elbow=(40, 30), hips_side=3)
    beck2 = P_(beck, arm_fwd=(14, 70), elbow=(40, 100))
    clip("k_taunt", 1.6, False, [(0.0, ready), (0.3, beck), (0.55, beck2), (0.8, beck), (1.05, beck2), (1.2, beck), (1.6, ready)])
    up = P_(ready, spine_pitch=-4, neck_pitch=-8, leg_fwd=(8, -6), knee=(10, 12), arm_fwd=(30, 150), arm_out=(60, 20), elbow=(20, 20), spine_twist=8)
    up2 = P_(up, hips_z=0.012, spine_pitch=-8, arm_fwd=(30, 160))
    clip("k_victory", 1.6, True, [(0.0, up), (0.4, up2), (0.8, up), (1.2, up2), (1.6, up)])
