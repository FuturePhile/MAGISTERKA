# test_refmodel.py
# PyTest suite for fuzzy_refmodel.py
# Covers: REQ-010/020/030/040/050/060/061/062/210/320 (simulation-level logic)

import math
import random
import pytest

from fuzzy_refmodel import (
    Q15_MAX,
    DEFAULT_CFG,
    MfThresholds, MfSet3, CoprocessorCfg, Singletons,
    g2q15_percent, mul_q15_round, trapezoid_mu, rules9_min, aggregate, defuzz,
    top_step, EstimatorRTLExact, SimpleDtEstimator,
)

# ---------- REQ-020: Membership function correctness (trapezoid) ----------

@pytest.mark.parametrize("a,b,c,d,x,exp", [
    # Triangle peak b=c=10
    (0,10,10,30, -5, 0),
    (0,10,10,30,  0, 0),
    (0,10,10,30,  1, (1<<15)//10),  # rising edge
    (0,10,10,30, 10, Q15_MAX),      # plateau
    (0,10,10,30, 20, (1<<15)//2),   # falling edge (b==c → brak plateau; 50%) = 16384
    (0,10,10,30, 29, (1<<15)//(30-10)),  # falling edge (1 away from d)
    (0,10,10,30, 30, 0),
    # Generic trapezoid
    (-10,0,0,15, -10, 0),
    (-10,0,0,15,   0, Q15_MAX),
    (-10,0,0,15,  15, 0),
])
def test_req020_trapezoid_mu(a,b,c,d,x,exp):
    mu = trapezoid_mu(x,a,b,c,d)
    assert 0 <= mu <= Q15_MAX
    assert mu == exp

# ---------- REQ-040/210: Aggregation with Q1.15 arithmetic and saturation ----------

def test_req040_aggregator_corners_only_and_full():
    # weights crafted; singletons default (percent mapping checked implicitly)
    w = (20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000)
    g = (100, 50, 30, 50, 50, 50, 80, 50, 0)

    # reg_mode=0 → only corners contribute
    S_w0, S_wg0 = aggregate(0, w, g)
    # Only w00,w02,w20,w22 = 4 * 20000 = 80000 → saturate to Q15_MAX
    assert S_w0 == Q15_MAX
    assert 0 <= S_wg0 <= Q15_MAX

    # reg_mode=1 → all 9 contribute, guaranteed saturation
    S_w1, S_wg1 = aggregate(1, w, g)
    assert S_w1 == Q15_MAX
    assert S_wg1 == Q15_MAX

def test_req210_percent_q15_mapping_and_mul_round():
    # 100% → Q15_MAX, 0% → 0, 50% ≈ 16384
    assert g2q15_percent(0) == 0
    assert g2q15_percent(100) == Q15_MAX
    mid = g2q15_percent(50)
    assert 16000 <= mid <= 16400

    # Rounded multiply: 0.5 * 0.5 ≈ 0.25
    q15_half = mid
    q15_quarter = mul_q15_round(q15_half, q15_half)
    assert 8000 <= q15_quarter <= 8400

# ---------- REQ-050: Defuzz (ratio, clamp 0..100, epsilon) ----------

@pytest.mark.parametrize("Sw,Swg,exp", [
    (0,     0,     0),    # epsilon path
    (Q15_MAX, Q15_MAX, 100),
    (20000, 10000, 50),
    (30000, 14999, 49),
    (30000, 15000, 50),
    (10000, 30000, 100),  # clamp >100
])
def test_req050_defuzz_cases(Sw,Swg,exp):
    assert defuzz(Sw, Swg) == exp

# ---------- REQ-010/030/040/050 exact E2E (dt_mode=0) for selected vectors ----------

@pytest.mark.parametrize("reg_mode,T,dT,expG", [
    # From your system-TB expectations
    (0, -64, -10, 100),
    (0,   0,   0,   0),
    (0,  64,  10,   0),
    (1, -64, -10, 100),
    (1,   0,   0,  50),
    (1,  64,  10,   0),
    # Σw≈0 case → 0
    (1, -128, 127,  0),
])
def test_req010_030_040_050_e2e_dt_mode0(reg_mode, T, dT, expG):
    G, dbg = top_step(T, dT, DEFAULT_CFG, reg_mode, dt_mode=0, estimator=None)
    assert G == expG
    assert 0 <= dbg["S_w"]  <= Q15_MAX
    assert 0 <= dbg["S_wg"] <= Q15_MAX

# ---------- REQ-060/061/062: Exact estimator behavior (bit-accurate port) ----------

def test_req062_init_clears_estimator_and_no_spike():
    est = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    # INIT at T=0
    est.init_pulse(0)
    # First step at same T=0 → delta=0, dt_valid was False on entry
    dT, was_valid = est.step(0)
    assert was_valid is False
    assert dT == 0
    # Next step still T=0 → valid becomes True, remains zero
    dT2, was_valid2 = est.step(0)
    assert was_valid2 is True
    assert dT2 == 0

def test_req061_scaling_and_clamp_sign():
    est = EstimatorRTLExact(alpha=255, k_dt=0, d_max=10)  # max gain, no division, clamp 10
    est.init_pulse(0)
    dT, _ = est.step(20)    # delta = +20 → clip to +10
    assert dT == 10
    dTn, _ = est.step(-20)  # delta = -40 → clip to -10
    assert dTn == -10

def test_req060_trend_on_ramp_no_spike():
    est = EstimatorRTLExact(alpha=64, k_dt=2, d_max=64)
    est.init_pulse(0)
    vals = []
    T = 0
    for _ in range(8):
        T += 4
        dT, _ = est.step(T)
        vals.append(dT)
    # monotonic non-decreasing for upward ramp (allow equal due to quantization)
    assert all(vals[i] <= vals[i+1] for i in range(len(vals)-1))

# ---------- REQ-320 sanity: dt_mode=1 end-to-end uses estimator and stays bounded ----------

def test_req320_e2e_with_estimator_exact_defaults():
    cfg = DEFAULT_CFG
    est = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    est.init_pulse(0)
    # steady
    G0, dbg0 = top_step(0, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
    assert 0 <= G0 <= 100
    assert dbg0["dt_valid"] in (False, True)

    # step up then down
    G1, _ = top_step(30, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
    G2, _ = top_step(-30, 0, cfg, reg_mode=1, dt_mode=1, estimator=est)
    assert 0 <= G1 <= 100
    assert 0 <= G2 <= 100

# ---------- REQ-210 numeric bounds on S_w/S_wg for random vectors (dt_mode=0) ----------

@pytest.mark.parametrize("reg_mode", [0,1])
def test_req210_bounds_random(reg_mode):
    random.seed(0xC0FFEE)
    for _ in range(200):
        T  = random.randint(-128,127)
        dT = random.randint(-128,127)
        G, dbg = top_step(T, dT, DEFAULT_CFG, reg_mode, dt_mode=0, estimator=None)
        assert 0 <= G <= 100
        assert 0 <= dbg["S_w"]  <= Q15_MAX
        assert 0 <= dbg["S_wg"] <= Q15_MAX

# ---------- Optional cross-check: Simple vs Exact estimator (sanity, not equality) ----------

def test_estimator_simple_vs_exact_sanity():
    cfg = DEFAULT_CFG
    est_exact = EstimatorRTLExact(alpha=32, k_dt=3, d_max=64)
    est_simple = SimpleDtEstimator(alpha_p=32, kdt_p=3, dmax_p=64)
    est_exact.init_pulse(0)
    est_simple.init_pulse(0)

    T_seq = [0,0,5,10,15,20,15,10,0,-5,-10,0]
    for T in T_seq:
        Gx, _ = top_step(T, 0, cfg, 1, 1, est_exact)
        Gs, _ = top_step(T, 0, cfg, 1, 1, est_simple)
        assert 0 <= Gx <= 100 and 0 <= Gs <= 100
