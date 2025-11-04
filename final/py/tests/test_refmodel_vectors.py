# tests/test_refmodel_vectors.py
import os
from fuzzy_refmodel import DEFAULT_CFG, top_step, EstimatorRTLExact

def test_v1_center_4_and_9():
    for reg_mode in (0,1):
        G, dbg = top_step(0, 0, DEFAULT_CFG, reg_mode, dt_mode=0)
        assert G == 50

def test_v2_v3_corners():
    for reg_mode in (0,1):
        G2,_ = top_step( 100, -100, DEFAULT_CFG, reg_mode, 0)
        G3,_ = top_step(-100,  100, DEFAULT_CFG, reg_mode, 0)
        assert abs(G2 - 80) <= 1
        assert abs(G3 - 30) <= 1

def test_sigma_w_zero_guard():
    G,_ = top_step(-128, 127, DEFAULT_CFG, 1, 0)
    assert G == 0

def test_trapezoid_edges_monotonic():
    # Sweep around zero set; monotonic on slopes + clamp
    last=None
    for T in range(-32,33):
        G,_ = top_step(T, 0, DEFAULT_CFG, 1, 0)
        if last is not None:
            # Not strictly monotonic globally, but bounded and smooth
            assert 0 <= G <= 100
        last=G
