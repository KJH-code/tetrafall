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
