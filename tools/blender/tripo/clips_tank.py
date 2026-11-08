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
