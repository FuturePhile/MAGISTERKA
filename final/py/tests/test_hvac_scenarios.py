# tests/test_hvac_scenarios.py
from fuzzy_refmodel import DEFAULT_CFG, top_step, EstimatorRTLExact

def run_seq(seq_T, reg_mode=1, dt_mode=1):
    est = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    est.init_pulse(seq_T[0])
    Gs=[]
    for T in seq_T:
        G,_ = top_step(T, 0, DEFAULT_CFG, reg_mode, dt_mode, est)
        Gs.append(G)
    return Gs

def test_door_open_disturbance_stability():
    # steady 0, then -3 for 10 steps, then back to 0
    seq = [0]*10 + [-3]*10 + [0]*20
    Gs = run_seq(seq)
    # no wild oscillations: bounded and tends to mid (≈50)
    assert max(Gs) <= 100 and min(Gs) >= 0
    assert abs(Gs[-1] - 50) <= 10
