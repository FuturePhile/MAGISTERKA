# tests/test_estimator_properties.py
from fuzzy_refmodel import EstimatorRTLExact

def test_init_no_spike():
    est = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    est.init_pulse(0)
    dT, valid = est.step(0)
    assert valid is False  # previous valid flag
    assert dT == 0

def test_step_scale_sign_and_clamp():
    est = EstimatorRTLExact(alpha=64, k_dt=3, d_max=20)
    est.init_pulse(0)
    seq = [0,16,32,48,64,80]
    outs=[]
    for t in seq:
        dT, _ = est.step(t)
        outs.append(dT)
        assert abs(dT) <= 20  # clamp
    # sign positive, non-decreasing early on
    assert outs[1] >= 0 and outs[-1] >= outs[1]
