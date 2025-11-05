# test_refmodel.py — PyTest suite mirroring tb_top_coprocessor.sv (class-based fuzzy_refmodel)
# Covers: REQ-010/020/030/040/050/060/061/062/210/230/310/320
# - DT_MODE=0: dense GRID, random MAE, VIS CSVs (T@dT=0, dT lines, heatmap)
# - DT_MODE=1: estimator INIT, ramp up/down, random walk
# - Parity extras from TB: AB toggle, edges, degenerate MF, small param sweep
# - CSV main file format identical to TB: run_id,case,idx,rm,dt,T,dT,Gexp,Gimpl

import os
import random
import pathlib
import pytest

from fuzzy_refmodel import (
    Q15_MAX,
    MfThresholds, MfSet3, CoprocessorCfg, Singletons,
    g2q15_percent, mul_q15_round, trapezoid_mu, rules9_min, aggregate, defuzz,
    top_step, EstimatorRTLExact, SimpleDtEstimator, fuzzify,
)

# ================== TB-equivalent configuration ==================

SINGLETONS_TB = Singletons(
    g00=100, g01=50,  g02=30,
    g10=50,  g11=50,  g12=50,
    g20=80,  g21=50,  g22=0,
)

MF_T_TB = MfSet3(
    neg=MfThresholds(a=-128, b=-64,  c=-32, d=0),
    zero=MfThresholds(a=-16,  b=0,    c=0,   d=16),
    pos=MfThresholds(a=0,     b=32,   c=64,  d=127),
)
MF_DT_TB = MfSet3(
    neg=MfThresholds(a=-100, b=-50, c=-30, d=-5),
    zero=MfThresholds(a=-10,  b=0,   c=0,   d=10),
    pos=MfThresholds(a=5,     b=25,  c=35,  d=60),
)

CFG_TB = CoprocessorCfg(mf_T=MF_T_TB, mf_dT=MF_DT_TB, singletons=SINGLETONS_TB)

ALPHA_CONST = 32  # ALPHA_P
KDT_CONST   = 3   # KDT_P

# ================== CSV helpers (exactly like TB) ==================

def _csv_open():
    csv_path = os.environ.get("CSV", "out/results_tb.csv")
    try:
        pathlib.Path(csv_path).parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    try:
        fd = open(csv_path, "w", encoding="utf-8", newline="\n")  # force LF
    except PermissionError:
        alt = f"out/results_tb_{os.getpid()}.csv"
        fd = open(alt, "w", encoding="utf-8", newline="\n")
        csv_path = alt
    return fd, csv_path

def _csv_header(fd):
    fd.write("run_id,case,idx,rm,dt,T,dT,Gexp,Gimpl\n")

def _csv_emit(fd, case_id, idx, reg_mode, dt_mode, T_in, dT_in, Gexp, Gimpl):
    line = f"{RUN_ID},{case_id},{idx},{reg_mode},{dt_mode},{T_in},{dT_in},{Gexp},{Gimpl}"
    fd.write(line + "\n")

# VIS file helpers (exact names/headers as in TB)
def _ensure_out_dir():
    pathlib.Path("out").mkdir(parents=True, exist_ok=True)

def _vis_open(filename):
    _ensure_out_dir()
    path = os.path.join("out", filename)
    f = open(path, "w", encoding="utf-8", newline="\n")
    f.write("T,dT,Gimpl,Gexp\n")
    return f, path

# ================== Bit-accurate reference path helpers ==================

def _fuzzify_TD(T: int, dT: int, cfg: CoprocessorCfg):
    muT = fuzzify(T, cfg.mf_T)
    muD = fuzzify(dT, cfg.mf_dT)
    return muT, muD

def _weights_q15(muT, muD):
    # rules9_min(muTn,muTz,muTp,muDn,muDz,muDp)
    return rules9_min(muT[0], muT[1], muT[2], muD[0], muD[1], muD[2])

def _agg_and_defuzz(reg_mode: int, w, singletons: Singletons):
    g = (
        singletons.g00, singletons.g01, singletons.g02,
        singletons.g10, singletons.g11, singletons.g12,
        singletons.g20, singletons.g21, singletons.g22,
    )
    Sw, Swg = aggregate(reg_mode, w, g)
    Gexp = defuzz(Sw, Swg)
    return Sw, Swg, Gexp

# ================== Env/plusargs parity ==================

def _env(name, default):
    val = os.environ.get(name)
    return val if val is not None else default

RUN_ID    = _env("RUN_ID",  "tb_run")
GIT_REV   = _env("GIT_REV",  "")
TOOL_VER  = _env("TOOL_VER", "PyTest")
SOURCE_ID = _env("SOURCE",  "py")
SEED_META = int(_env("SEED", "0") or 0)

# ================== Shared grids ==================

def _grid_T_values():
    return [-128, -64, -32, -16, 0, 16, 32, 64, 96, 127]

def _grid_dT_values():
    return [-60, -30, -10, 0, 10, 30, 60]

# ================== CSV main file fixture ==================

@pytest.fixture(scope="module")
def csv_file():
    fd, path = _csv_open()
    _csv_header(fd)
    yield fd
    try:
        fd.flush()
        fd.close()
    except Exception:
        pass

# ================== Block 1: DT_MODE=0 GRID + edge ==================

@pytest.mark.parametrize("reg_mode", [0, 1])
def test_grid_dt_mode0(csv_file, reg_mode):
    if SEED_META:
        random.seed(SEED_META)
    idx = 0

    for T in _grid_T_values():
        for dT in _grid_dT_values():
            muT, muD = _fuzzify_TD(T, dT, CFG_TB)
            w = _weights_q15(muT, muD)
            Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)

            Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)

            assert 0 <= Sw <= Q15_MAX
            assert 0 <= Swg <= Q15_MAX
            assert Gimpl == Gexp

            _csv_emit(csv_file, f"Grid_T={T}_dT={dT}", idx, reg_mode, 0, T, dT, Gexp, Gimpl)
            idx += 1

def test_edge_sumw_zero_dt_mode0(csv_file):
    reg_mode = 1
    T, dT = -128, 127
    muT, muD = _fuzzify_TD(T, dT, CFG_TB)
    w = _weights_q15(muT, muD)
    Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
    Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
    assert Gexp == 0
    assert Gimpl == Gexp
    _csv_emit(csv_file, "Edge_sumw_zero", 0, reg_mode, 0, T, dT, Gexp, Gimpl)

# ================== Block 2: DT_MODE=0 random MAE ==================

def test_random_mae_dt_mode0(csv_file):
    N = 1000
    reg_mode = 1
    mae_acc = 0
    idx = 0
    if SEED_META:
        random.seed(SEED_META)
    for _ in range(N):
        T = random.randint(-128, 127)
        dT = random.randint(-128, 127)
        muT, muD = _fuzzify_TD(T, dT, CFG_TB)
        w = _weights_q15(muT, muD)
        Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
        Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)

        diff = abs(Gimpl - Gexp)
        mae_acc += diff

        _csv_emit(csv_file, "Random", idx, reg_mode, 0, T, dT, Gexp, Gimpl)
        idx += 1

    mae = mae_acc // N
    assert mae <= 1, f"[REQ-310] MAE={mae}% > 1%"

# ================== Block 3: DT_MODE=1 estimator scenarios ==================

def _golden_at_dT0(T: int, reg_mode: int):
    muT, muD0 = _fuzzify_TD(T, 0, CFG_TB)
    w = _weights_q15(muT, muD0)
    Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
    return Gexp

def test_estimator_flow_dt_mode1(csv_file):
    reg_mode = 1
    dt_mode = 1

    est = EstimatorRTLExact(alpha=ALPHA_CONST, k_dt=KDT_CONST, d_max=64)
    est.init_pulse(0)

    # INIT: must match dT=0 golden for T=0
    T = 0
    Gexp_init = _golden_at_dT0(T, reg_mode)
    Gimpl, dbg = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
    _csv_emit(csv_file, "EST_INIT", 0, reg_mode, dt_mode, T, 0, -1, Gimpl)
    assert 0 <= Gimpl <= 100
    assert Gimpl == Gexp_init, f"[REQ-062] after INIT got={Gimpl} exp={Gexp_init}"

    # Two steady runs
    for _ in range(2):
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        assert 0 <= Gimpl <= 100

    # Ramp up 0..+40 step 2
    idx_up = 0
    for i in range(20):
        T = i * 2
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, "EST_RampUp", idx_up, reg_mode, dt_mode, T, 0, -1, Gimpl)
        assert 0 <= Gimpl <= 100
        idx_up += 1

    # Ramp down +40..0
    idx_dn = 0
    for i in range(20, -1, -1):
        T = i * 2
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, "EST_RampDown", idx_dn, reg_mode, dt_mode, T, 0, -1, Gimpl)
        assert 0 <= Gimpl <= 100
        idx_dn += 1

    # Random walk (100)
    T = 0
    idx_rw = 0
    for _ in range(100):
        step = random.randint(-5, 5)
        nxt = T + step
        if nxt > 127: nxt = 127
        if nxt < -128: nxt = -128
        T = nxt
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, "EST_RandWalk", idx_rw, reg_mode, dt_mode, T, 0, -1, Gimpl)
        assert 0 <= Gimpl <= 100
        idx_rw += 1

# ================== VIS flows (CSV like TB) ==================

def test_vis_T_at_dt0_csv():
    # out/vis_T_at_dt0.csv with header T,dT,Gimpl,Gexp
    f, path = _vis_open("vis_T_at_dt0.csv")
    reg_mode = 1
    dT = 0
    for T in range(-128, 128, 2):
        muT, muD = _fuzzify_TD(T, dT, CFG_TB)
        w = _weights_q15(muT, muD)
        _, _, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
        Gimpl, _ = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
        assert Gimpl == Gexp
        f.write(f"{T},{dT},{Gimpl},{Gexp}\n")
    f.flush(); f.close()

def test_vis_dT_lines_csv():
    # out/vis_dT_lines.csv for T in {-32,0,32}, dT -60..60 step 4
    f, path = _vis_open("vis_dT_lines.csv")
    reg_mode = 1
    Ts = [-32, 0, 32]
    for T in Ts:
        for dT in range(-60, 61, 4):
            muT, muD = _fuzzify_TD(T, dT, CFG_TB)
            w = _weights_q15(muT, muD)
            _, _, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
            Gimpl, _ = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
            assert Gimpl == Gexp
            f.write(f"{T},{dT},{Gimpl},{Gexp}\n")
    f.flush(); f.close()

def test_vis_heatmap_csv():
    # out/vis_heatmap.csv for T -64..64 step 8, dT -60..60 step 5
    f, path = _vis_open("vis_heatmap.csv")
    reg_mode = 1
    for T in range(-64, 65, 8):
        for dT in range(-60, 61, 5):
            muT, muD = _fuzzify_TD(T, dT, CFG_TB)
            w = _weights_q15(muT, muD)
            _, _, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
            Gimpl, _ = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
            assert Gimpl == Gexp
            f.write(f"{T},{dT},{Gimpl},{Gexp}\n")
    f.flush(); f.close()

# ================== Parity extras from TB ==================

def test_ab_toggle_regmode_stability(csv_file):
    # AB toggle on same inputs to prove mode flip stability (dt_mode=0)
    T = 32
    dT = -10

    # reg_mode=0
    Gimpl0, _ = top_step(T, dT, CFG_TB, reg_mode=0, dt_mode=0, estimator=None)
    assert 0 <= Gimpl0 <= 100
    _csv_emit(csv_file, "AB_Toggle_reg0", 0, 0, 0, T, dT, -1, Gimpl0)

    # reg_mode=1
    Gimpl1, _ = top_step(T, dT, CFG_TB, reg_mode=1, dt_mode=0, estimator=None)
    assert 0 <= Gimpl1 <= 100
    _csv_emit(csv_file, "AB_Toggle_reg1", 0, 1, 0, T, dT, -1, Gimpl1)

    # flip back to 0 (stateless for dt_mode=0, so value must equal first)
    Gimpl0b, _ = top_step(T, dT, CFG_TB, reg_mode=0, dt_mode=0, estimator=None)
    assert Gimpl0b == Gimpl0

def test_edge_threshold_points():
    # T edges at dT=0, then dT edges at T=0
    reg_mode = 1

    Tvec = [CFG_TB.mf_T.neg.a, CFG_TB.mf_T.neg.b, CFG_TB.mf_T.neg.c, CFG_TB.mf_T.neg.d,
            CFG_TB.mf_T.pos.a, CFG_TB.mf_T.pos.b, CFG_TB.mf_T.pos.c, CFG_TB.mf_T.pos.d]
    dTvec = [CFG_TB.mf_dT.neg.a, CFG_TB.mf_dT.neg.b, CFG_TB.mf_dT.neg.c, CFG_TB.mf_dT.neg.d,
             CFG_TB.mf_dT.pos.a, CFG_TB.mf_dT.pos.b, CFG_TB.mf_dT.pos.c, CFG_TB.mf_dT.pos.d]

    for T in Tvec:
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode=0, estimator=None)
        assert 0 <= Gimpl <= 100

    for dT in dTvec:
        Gimpl, _ = top_step(0, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
        assert 0 <= Gimpl <= 100

def test_degenerate_zero_T_mf():
    # Force ZERO MF to degenerate shoulders (b==a, d==c) and verify outputs are valid
    reg_mode = 1
    dt_mode = 0
    mfT = MfSet3(
        neg=CFG_TB.mf_T.neg,
        zero=MfThresholds(a=CFG_TB.mf_T.zero.a, b=CFG_TB.mf_T.zero.a, c=CFG_TB.mf_T.zero.d, d=CFG_TB.mf_T.zero.d),
        pos=CFG_TB.mf_T.pos,
    )
    cfg2 = CoprocessorCfg(mf_T=mfT, mf_dT=CFG_TB.mf_dT, singletons=CFG_TB.singletons)

    for dT in _grid_dT_values():
        Gimpl, _ = top_step(0, dT, cfg2, reg_mode, dt_mode, estimator=None)
        assert 0 <= Gimpl <= 100

def test_near_eps_safe_defuzz(csv_file):
    # Find a coarse-grid vector with SumW in [1..4] LSBs; ensure defuzz stays finite/in-range.
    reg_mode = 1
    found = False
    cand = (0, 0)
    for T in _grid_T_values():
        for dT in _grid_dT_values():
            muT, muD = _fuzzify_TD(T, dT, CFG_TB)
            w = _weights_q15(muT, muD)
            Sw, Swg, _ = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
            if 1 <= Sw <= 4:
                cand = (T, dT)
                found = True
                break
        if found:
            break
    if found:
        T, dT = cand
        Gimpl, _ = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
        assert 0 <= Gimpl <= 100
        _csv_emit(csv_file, "NearEPS", 0, reg_mode, 0, T, dT, -1, Gimpl)

def test_param_sweep_small_grid():
    # A few legal MF layouts to prove configurability (mirror TB PARAM_SWEEP)
    reg_mode = 1
    dt_mode = 0
    Ts = _grid_T_values()
    dTs = _grid_dT_values()

    for v in range(3):
        # widen ZERO by 2*v around 0 (keep monotonic a<=b<=c<=d)
        mfT = MfSet3(
            neg=CFG_TB.mf_T.neg,
            zero=MfThresholds(a=-16 - 2*v, b=0, c=0, d=16 + 2*v),
            pos=MfThresholds(a=0, b=32 + 2*v, c=64 + 2*v, d=127),
        )
        cfgv = CoprocessorCfg(mf_T=mfT, mf_dT=CFG_TB.mf_dT, singletons=CFG_TB.singletons)
        for T in Ts:
            for dT in dTs:
                muT, muD = _fuzzify_TD(T, dT, cfgv)
                w = _weights_q15(muT, muD)
                _, _, Gexp = _agg_and_defuzz(reg_mode, w, cfgv.singletons)
                Gimpl, _ = top_step(T, dT, cfgv, reg_mode, dt_mode, estimator=None)
                assert Gimpl == Gexp
                assert 0 <= Gimpl <= 100

# ================== Light sanity tests kept from earlier ==================

def test_req210_percent_q15_mapping_and_mul_round():
    assert g2q15_percent(0) == 0
    assert g2q15_percent(100) == Q15_MAX
    mid = g2q15_percent(50)
    assert 16000 <= mid <= 16400
    q15_half = mid
    q15_quarter = mul_q15_round(q15_half, q15_half)
    assert 8000 <= q15_quarter <= 8400

def test_req020_trapezoid_mu_samples():
    # A few samples; complete coverage happens in GRID and VIS
    assert trapezoid_mu(-5, 0, 10, 10, 30) == 0
    assert trapezoid_mu(10, 0, 10, 10, 30) == Q15_MAX
    assert trapezoid_mu(30, 0, 10, 10, 30) == 0
