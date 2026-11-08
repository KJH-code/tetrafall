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
